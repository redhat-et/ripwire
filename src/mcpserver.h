#pragma once

// mcpserver.h — the OPTIONAL remote MCP transport: Streamable HTTP per the 2026
// MCP spec, plain request/response only (SSE is CUT — §2b). A single hand-rolled HTTP/1.1 reader over
// POSIX sockets keeps G3 (zero build deps) intact: we parse ONLY what we need (request line, Content-Length,
// Authorization, Content-Type) and reject the rest politely. The JSON-RPC layer is reused VERBATIM — every
// request routes through mcp.h's shared dispatchMcpLine(), so a given body returns byte-identical bytes over
// HTTP and over stdio. Concurrency model (§2b, decided): a single-threaded accept loop serving one request
// at a time — exactly the stdio semantics, no shared mutable state, no locks, no TSan surface.
//
// SECURITY POSTURE IS THE FEATURE (§2.3, the ~200K exposed-MCP-server lesson):
//   • bind 127.0.0.1 by default; a non-loopback bind requires BOTH an explicit host AND a shared bearer
//     token — missing either ⇒ REFUSE TO START (exit 1 + loud stderr banner).
//   • a token, if configured, gates EVERY request (constant-time Bearer compare) → 401 on missing/wrong.
//   • edit verbs are refused over the remote transport by default; --allow-remote-edits opts in and FORCES
//     the token requirement even on loopback (McpDispatchPolicy carries this into the shared handler).
//   • one listener serves ONE workspace fixed at startup; an off-workspace path is refused (mcp.h pin gate).
//   • no TLS — documented "reverse-proxy it" (§2.3). The token is a tripwire, not a security boundary.
//
// Include direction stays one-way: mcpserver.h → mcp.h → {mcpverbs,mcpedit} → mcpindex → mcpjson. main.cpp
// includes this header and picks stdio (runMcp) vs HTTP (runMcpHttp) — mcp.h itself never learns about HTTP.

#include "mcp.h"

#include <string>
#include <string_view>
#include <vector>
#include <cstdint>
#include <cstring>
#include <cctype>
#include <cerrno>
#include <chrono>

#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <sys/time.h>       // struct timeval — SO_RCVTIMEO (slow-loris guard)

namespace rw
{

// ─── configuration handed down from the CLI (main.cpp parses --listen/--mcp-token/--allow-remote-edits) ──
struct McpHttpConfig
{
    std::string              listenSpec;             // the raw --listen value: "HOST:PORT" or bare "PORT" (loopback)
    std::string              token;                  // shared bearer (--mcp-token or RIPWIRE_MCP_TOKEN); "" = none
    std::string              root;                   // roots[0] — the single-root workspace to pin
    std::vector<std::string> roots;                  // ALL positional roots (multi-root workspace when size() >= 2)
    int                      topK             = 200;
    bool                     stable           = false;
    bool                     noRedact         = false;
    bool                     allowRemoteEdits = false;
};

namespace mcphttp
{

// ── size ceilings (degrade-don't-crash: a hostile client cannot make us allocate without bound) ──
inline constexpr std::size_t kMaxHeaderBytes = 64u * 1024u;              // request line + headers cap → 431
inline constexpr std::size_t kMaxBodyBytes   = 8u  * 1024u * 1024u;      // JSON-RPC body cap (§ requirements) → 413
inline constexpr int         kRecvTimeoutSec = 10;                       // SO_RCVTIMEO — a partial (slow-loris) request is dropped

// constant-time string compare — no early-out on the first mismatched byte (a wrong token must not be
// distinguishable by timing from a right one). Compares length first (safe: length is not the secret).
inline bool constantTimeEquals( std::string_view a, std::string_view b ) noexcept
{
    if( a.size() != b.size() )
    {
        return false;
    }
    unsigned diff = 0;
    for( std::size_t i = 0; i < a.size(); ++i )
    {
        diff |= static_cast<unsigned char>( a[i] ) ^ static_cast<unsigned char>( b[i] );
    }
    return diff == 0;
}

// case-insensitive ASCII compare for HTTP header names (RFC 7230 §3.2: field names are case-insensitive).
inline bool iEquals( std::string_view a, std::string_view b ) noexcept
{
    if( a.size() != b.size() )
    {
        return false;
    }
    for( std::size_t i = 0; i < a.size(); ++i )
    {
        if( std::tolower( static_cast<unsigned char>( a[i] ) ) != std::tolower( static_cast<unsigned char>( b[i] ) ) )
        {
            return false;
        }
    }
    return true;
}

inline std::string_view trim( std::string_view s ) noexcept
{
    std::size_t b = 0, e = s.size();
    while( b < e && ( s[b] == ' ' || s[b] == '\t' ) )
    {
        ++b;
    }
    while( e > b && ( s[e - 1] == ' ' || s[e - 1] == '\t' || s[e - 1] == '\r' ) )
    {
        --e;
    }
    return s.substr( b, e - b );
}

// send an entire buffer, tolerating short writes; false if the peer went away mid-write (we just drop it).
inline bool sendAll( int fd, const std::string& data ) noexcept
{
    std::size_t sent = 0;
    while( sent < data.size() )
    {
        const ssize_t n = ::send( fd, data.data() + sent, data.size() - sent, 0 );
        if( n <= 0 )
        {
            return false;
        }
        sent += static_cast<std::size_t>( n );
    }
    return true;
}

// build + send a minimal HTTP/1.1 response. Connection: close — one request per connection (§2b serialize).
inline void respond( int fd, const char* status, const char* contentType, const std::string& body ) noexcept
{
    std::string out;
    out.reserve( body.size() + 160 );
    out += "HTTP/1.1 ";
    out += status;
    out += "\r\nContent-Type: ";
    out += contentType;
    out += "\r\nContent-Length: ";
    out += std::to_string( body.size() );
    out += "\r\nConnection: close\r\n\r\n";
    out += body;
    sendAll( fd, out );
}

// a JSON-RPC error envelope (id:null — a transport-level rejection has no request id to echo).
inline std::string jsonRpcError( int code, const char* message )
{
    return std::string( "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":" ) + std::to_string( code )
         + ",\"message\":\"" + message + "\"}}";
}

// one parsed request (only the fields we act on). ok=false ⇒ malformed → 400.
struct Request
{
    bool        ok                   = false;
    bool        hasContentLength     = false;
    bool        hasAuthorization     = false;
    bool        hasOrigin            = false;
    bool        hasAccept            = false;
    bool        hasContentType       = false;
    bool        hasProtocolVersion   = false;
    bool        hasTransferEncoding  = false;
    std::string method;                  // "POST", "GET", …
    std::string target;                  // "/mcp" (query stripped)
    std::size_t contentLength         = 0;
    std::string authorization;
    std::string origin;
    std::string accept;
    std::string contentType;
    std::string protocolVersion;
    std::string body;                    // the JSON-RPC request body
};

// read + parse one HTTP request off `fd`. Returns Request{ok=false} on malformed input (→ 400) so the
// caller can answer politely and move on; the server process NEVER dies on bad input. Oversized header
// or body sets a sentinel the caller maps to 431/413. A partial request that stalls past SO_RCVTIMEO
// makes recv() return <= 0 → we abandon the connection (server lives).
//
// `tooManyHeaderBytes` / `tooLargeBody` out-params let the caller pick the right 4xx without a wider enum.
inline Request readRequest( int fd, bool& tooManyHeaderBytes, bool& tooLargeBody )
{
    tooManyHeaderBytes = false;
    tooLargeBody       = false;
    Request req;

    // 1) accumulate until the end-of-headers marker (or the header cap, or a stalled/closed peer).
    std::string buf;
    std::size_t headerEnd = std::string::npos;
    char        tmp[ 8192 ];
    for( ;; )
    {
        headerEnd = buf.find( "\r\n\r\n" );
        if( headerEnd != std::string::npos )
        {
            break;
        }
        if( buf.size() > kMaxHeaderBytes ) { tooManyHeaderBytes = true; return req; }   // → 431
        const ssize_t n = ::recv( fd, tmp, sizeof( tmp ), 0 );
        if( n <= 0 )
        {
            return req; // EOF or SO_RCVTIMEO fired mid-headers (slow-loris) → drop, ok stays false but caller only 400s a *complete* malformed request; a stalled read just closes
        }
        buf.append( tmp, static_cast<std::size_t>( n ) );
    }

    // 2) request line: METHOD SP TARGET SP VERSION
    const std::size_t lineEnd = buf.find( "\r\n" );
    if( lineEnd == std::string::npos || lineEnd == 0 )
    {
        return req; // malformed → caller 400s
    }
    const std::string_view reqLine( buf.data(), lineEnd );
    const std::size_t sp1 = reqLine.find( ' ' );
    if( sp1 == std::string_view::npos )
    {
        return req;
    }
    const std::size_t sp2 = reqLine.find( ' ', sp1 + 1 );
    if( sp2 == std::string_view::npos )
    {
        return req;
    }
    req.method = std::string( reqLine.substr( 0, sp1 ) );
    std::string_view target = reqLine.substr( sp1 + 1, sp2 - sp1 - 1 );
    if( const std::size_t q = target.find( '?' ); q != std::string_view::npos )
    {
        target = target.substr( 0, q );
    }
    req.target = std::string( target );

    // 3) bounded headers we act on. Duplicate security/framing headers are ambiguous and therefore malformed.
    bool badHeader = false;
    std::size_t pos = lineEnd + 2;
    while( pos < headerEnd )
    {
        std::size_t eol = buf.find( "\r\n", pos );
        if( eol == std::string::npos || eol > headerEnd )
        {
            eol = headerEnd;
        }
        const std::string_view hline( buf.data() + pos, eol - pos );
        const std::size_t colon = hline.find( ':' );
        if( colon != std::string_view::npos )
        {
            const std::string_view key = trim( hline.substr( 0, colon ) );
            const std::string_view val = trim( hline.substr( colon + 1 ) );
            if( iEquals( key, "content-length" ) )
            {
                if( req.hasContentLength ) { badHeader = true; break; }
                // parse a non-negative decimal; reject anything else (a bad length → treat as malformed later).
                std::size_t cl = 0;  bool any = false, bad = false;
                for( char c : val )
                {
                    if( c < '0' || c > '9' ) { bad = true; break; }
                    any = true;
                    const std::size_t digit = std::size_t( c - '0' );
                    if( cl > ( kMaxBodyBytes + 1 - digit ) / 10 ) { cl = kMaxBodyBytes + 1; break; }   // saturate before multiply/add
                    cl = cl * 10 + digit;
                }
                if( any && !bad ) { req.contentLength = cl; req.hasContentLength = true; }
                else
                {
                    badHeader = true;
                }
            }
            else if( iEquals( key, "authorization" ) )
            {
                if( req.hasAuthorization ) { badHeader = true; break; }
                req.hasAuthorization = true;
                req.authorization = std::string( val );
            }
            else if( iEquals( key, "origin" ) )
            {
                if( req.hasOrigin ) { badHeader = true; break; }
                req.hasOrigin = true;
                req.origin = std::string( val );
            }
            else if( iEquals( key, "accept" ) )
            {
                if( req.hasAccept ) { badHeader = true; break; }
                req.hasAccept = true;
                req.accept = std::string( val );
            }
            else if( iEquals( key, "content-type" ) )
            {
                if( req.hasContentType ) { badHeader = true; break; }
                req.hasContentType = true;
                req.contentType = std::string( val );
            }
            else if( iEquals( key, "mcp-protocol-version" ) )
            {
                if( req.hasProtocolVersion ) { badHeader = true; break; }
                req.hasProtocolVersion = true;
                req.protocolVersion = std::string( val );
            }
            else if( iEquals( key, "transfer-encoding" ) )
            {
                req.hasTransferEncoding = true;
            }
        }
        pos = eol + 2;
    }

    if( badHeader || req.hasTransferEncoding )
    {
        return req;
    }

    if( req.contentLength > kMaxBodyBytes ) { tooLargeBody = true; return req; }   // → 413 (before reading the body)

    // 4) body: whatever already trailed the headers, plus the rest up to Content-Length.
    const std::size_t bodyStart = headerEnd + 4;
    req.body = buf.substr( bodyStart );
    while( req.body.size() < req.contentLength )
    {
        const ssize_t n = ::recv( fd, tmp, sizeof( tmp ), 0 );
        if( n <= 0 )
        {
            return req; // truncated body (stall/EOF) — ok stays false; caller 400s a request we couldn't complete
        }
        req.body.append( tmp, static_cast<std::size_t>( n ) );
        if( req.body.size() > kMaxBodyBytes ) { tooLargeBody = true; return req; }
    }
    if( req.body.size() > req.contentLength )
    {
        req.body.resize( req.contentLength );
    }

    req.ok = true;
    return req;
}

// extract the bearer credential from an "Authorization: Bearer <token>" value ("" if not a bearer scheme).
inline std::string_view bearerCredential( std::string_view auth ) noexcept
{
    constexpr std::string_view kBearer = "Bearer ";
    auth = trim( auth );
    if( auth.size() < kBearer.size() )
    {
        return {};
    }
    if( !iEquals( auth.substr( 0, kBearer.size() ), kBearer ) )
    {
        return {};
    }
    return trim( auth.substr( kBearer.size() ) );
}

inline bool hasMediaType( std::string_view values, std::string_view wanted ) noexcept
{
    std::size_t offset = 0;
    while( offset <= values.size() )
    {
        const std::size_t comma = values.find( ',', offset );
        std::string_view value = trim( values.substr( offset, comma == std::string_view::npos ? values.size() - offset : comma - offset ) );
        if( const std::size_t semi = value.find( ';' ); semi != std::string_view::npos )
        {
            value = trim( value.substr( 0, semi ) );
        }
        if( iEquals( value, wanted ) )
        {
            return true;
        }
        if( comma == std::string_view::npos )
        {
            break;
        }
        offset = comma + 1;
    }
    return false;
}

inline bool acceptsMcpResponseTypes( std::string_view accept ) noexcept
{
    return hasMediaType( accept, "application/json" ) && hasMediaType( accept, "text/event-stream" );
}

inline bool isJsonContentType( std::string_view contentType ) noexcept
{
    if( const std::size_t semi = contentType.find( ';' ); semi != std::string_view::npos )
    {
        contentType = contentType.substr( 0, semi );
    }
    return iEquals( trim( contentType ), "application/json" );
}

inline bool isAllowedOrigin( std::string_view origin, std::string_view host, int port, bool loopback )
{
    if( !loopback )
    {
        return false; // remote browser origins require a future explicit allowlist; native clients omit Origin
    }
    const std::string suffix = ":" + std::to_string( port );
    if( origin == std::string( "http://" ) + std::string( host ) + suffix )
    {
        return true;
    }
    if( origin == std::string( "http://127.0.0.1" ) + suffix || origin == std::string( "http://localhost" ) + suffix )
    {
        return true;
    }
    return false;
}

// a host that is NOT reachable off-box (loopback / link-local host-only). Anything else — 0.0.0.0, a LAN
// IP, a public IP — is treated as non-loopback and triggers the two-opt-in security requirement (§2.3).
inline bool isLoopbackHost( std::string_view host ) noexcept
{
    return host == "127.0.0.1" || host == "localhost" || host == "::1";
}

}   // namespace mcphttp

// serve the remote HTTP transport. Returns the process exit code. REFUSES TO START (returns 1 + stderr)
// when the security preconditions are not met; otherwise loops forever, one request at a time.
inline int runMcpHttp( const McpHttpConfig& cfg )
{
    using namespace mcphttp;

    // ── 1) parse the listen spec: "HOST:PORT" or a bare "PORT" (⇒ loopback default 127.0.0.1) ──────────
    std::string host = "127.0.0.1";
    std::string portStr;
    {
        const std::string& spec = cfg.listenSpec;
        const std::size_t   colon = spec.rfind( ':' );
        if( colon == std::string::npos )
        {
            portStr = spec;                                 // bare port → loopback host
        }
        else
        {
            host = spec.substr( 0, colon );
            portStr = spec.substr( colon + 1 );
            if( host.empty() )
            {
                host = "127.0.0.1";
            }
        }
    }
    int port = 0;
    {
        bool any = false;
        for( char c : portStr ) { if( c < '0' || c > '9' ) { port = -1; break; } any = true; port = port * 10 + ( c - '0' ); if( port > 65535 ) { port = -1; break; } }
        if( !any )
        {
            port = -1;
        }
    }
    if( port <= 0 || port > 65535 )
    {
        std::fprintf( stderr, "ripwire: --listen: could not parse a port from '%s' (want HOST:PORT or PORT, 1..65535)\n", cfg.listenSpec.c_str() );
        return 1;
    }

    const bool loopback = isLoopbackHost( host );

    // ── 2) security preconditions — REFUSE TO START rather than expose an unauthenticated listener ─────
    // (§2.3) a non-loopback bind needs BOTH an explicit host (the operator spelled it) AND a shared token.
    if( !loopback && cfg.token.empty() )
    {
        std::fprintf( stderr,
            "ripwire: REFUSING to bind %s:%d — a non-loopback MCP listener requires a shared bearer token.\n"
            "         Set one with --mcp-token=SECRET or the RIPWIRE_MCP_TOKEN env var, and put ripwire behind\n"
            "         your own reverse proxy for TLS + real auth (the token is a tripwire, not a security boundary).\n",
            host.c_str(), port );
        return 1;
    }
    // (§2.4) --allow-remote-edits turns a read-only map server into a remote FILE-WRITER; force the token
    // even on loopback so an opt-in write surface is never reachable without the shared secret.
    if( cfg.allowRemoteEdits && cfg.token.empty() )
    {
        std::fprintf( stderr,
            "ripwire: REFUSING to start — --allow-remote-edits enables remote file WRITES and therefore requires\n"
            "         a shared bearer token (--mcp-token=SECRET or RIPWIRE_MCP_TOKEN), even on loopback.\n" );
        return 1;
    }

    // ── 3) resolve + pin the ONE workspace this listener serves (§2b: one listener = one workspace) ─────
    std::string pinnedRoot;
    if( cfg.roots.size() >= 2 )
    {
        std::string wsErr;
        const std::string key = mcpWorkspaceKey( cfg.roots, wsErr );
        if( key.empty() ) { std::fprintf( stderr, "ripwire: --listen: %s\n", wsErr.c_str() ); return 1; }
        pinnedRoot = mcpCanonRoot( key );   // a real path if the dedupe collapsed to one root; else the opaque key (realpath fails → returned as-is)
    }
    else
    {
        pinnedRoot = mcpCanonRoot( cfg.root );
    }

    McpDispatchPolicy policy;
    policy.pinnedRoot   = pinnedRoot;
    policy.editsAllowed = cfg.allowRemoteEdits;   // remote edits refused by default

    // V3/F4: can the git-backed verbs answer about THIS workspace at all? Resolved ONCE, here — the answer
    // is fixed for the listener's life (the workspace is pinned at startup) and the probe forks `git`, so
    // per-tools/list would be a fork per client handshake. A MULTI-root workspace answers no without
    // asking (all three are kMcpSingleRootVerbs rows and refuse a `paths` workspace by rule); otherwise it
    // is exactly gitRepoHasHistory — the same predicate their own refusals are built on, so the catalog
    // can neither advertise a verb this tree makes refuse nor omit one it would have answered.
    policy.pinnedRootHasGit = ( cfg.roots.size() < 2 ) && quality::gitRepoHasHistory( pinnedRoot );

    // finding #7: WHICH git-only cause is it, when pinnedRootHasGit came back false? A second probe, only
    // forked when the first one already failed (the common git-with-history path pays nothing extra) —
    // gitRepoToplevel succeeds on a `.git init`-only tree with zero commits (rev-parse --show-toplevel
    // needs no HEAD), so a non-empty toplevel here means "git repo, no HEAD" rather than "no git at all".
    policy.pinnedRootIsGitDir = !policy.pinnedRootHasGit && ( cfg.roots.size() < 2 )
                              && !gitRepoToplevel( pinnedRoot ).empty();

    // ── 4) open the listening socket ───────────────────────────────────────────────────────────────────
    const int listenFd = ::socket( AF_INET, SOCK_STREAM, 0 );
    if( listenFd < 0 ) { std::fprintf( stderr, "ripwire: --listen: socket() failed: %s\n", std::strerror( errno ) ); return 1; }
    int one = 1;
    ::setsockopt( listenFd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof( one ) );

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port   = htons( static_cast<uint16_t>( port ) );
    const std::string bindHost = ( host == "localhost" ) ? std::string( "127.0.0.1" ) : host;
    if( ::inet_pton( AF_INET, bindHost.c_str(), &addr.sin_addr ) != 1 )
    {
        std::fprintf( stderr, "ripwire: --listen: '%s' is not a valid IPv4 bind address (IPv6 is not supported; reverse-proxy for that)\n", host.c_str() );
        ::close( listenFd );
        return 1;
    }
    if( ::bind( listenFd, reinterpret_cast<sockaddr*>( &addr ), sizeof( addr ) ) != 0 )
    {
        std::fprintf( stderr, "ripwire: --listen: bind %s:%d failed: %s\n", host.c_str(), port, std::strerror( errno ) );
        ::close( listenFd );
        return 1;
    }
    if( ::listen( listenFd, 16 ) != 0 )
    {
        std::fprintf( stderr, "ripwire: --listen: listen() failed: %s\n", std::strerror( errno ) );
        ::close( listenFd );
        return 1;
    }

    // ── 5) startup banner. LOUD + explicit on any non-loopback bind (§2.3.4: an accidental 0.0.0.0 is never silent) ──
    if( loopback )
    {
        std::fprintf( stderr, "ripwire: MCP HTTP listener on http://%s:%d/mcp (loopback only)%s%s\n",
                      host.c_str(), port,
                      cfg.token.empty() ? "" : " [token required]",
                      cfg.allowRemoteEdits ? " [remote edits ENABLED]" : "" );
    }
    else
    {
        std::fprintf( stderr,
            "ripwire: ****************************************************************************\n"
            "ripwire: *  MCP HTTP listener bound to %s:%d — REACHABLE OFF-HOST.\n"
            "ripwire: *  Bearer token REQUIRED. No TLS — put this behind a reverse proxy for TLS\n"
            "ripwire: *  and real auth. The token is a tripwire, not a security boundary.%s\n"
            "ripwire: ****************************************************************************\n",
            host.c_str(), port, cfg.allowRemoteEdits ? "  [remote edits ENABLED]" : "" );
    }

    // warm the pinned index once so the first client request is fast (and any parse issue surfaces now, on
    // stderr, not mid-request). getIndex caches process-wide; failure degrades to a lazy first-request build.
    (void)getIndex( pinnedRoot );

    const bool authRequired = !cfg.token.empty();

    // MEASURE-FIRST parity with the stdio loop: RIPWIRE_MCP_TIMINGS emits ONE stderr line per handled
    // request (verb, wall-ms, rebuilt=0|1) — off by default (byte-identical, silent). The rebuilt bit is
    // what the workspace-pinning gate reads to assert an off-workspace refusal did NOT rebuild the index.
    const bool timingsOn = std::getenv( "RIPWIRE_MCP_TIMINGS" ) != nullptr;

    // ── 6) accept loop: single-threaded, one request per connection (Connection: close) — §2b serialize ─
    for( ;; )
    {
        const int fd = ::accept( listenFd, nullptr, nullptr );
        if( fd < 0 )
        {
            if( errno == EINTR )
            {
                continue; // interrupted by a signal → retry, don't die
            }
            continue;                          // any other accept() error: skip this one, keep serving
        }

        // slow-loris guard: a client that opens a connection and dribbles (or stalls) must not wedge the
        // single-threaded loop. SO_RCVTIMEO makes recv() return after kRecvTimeoutSec → readRequest drops it.
        timeval tv{ kRecvTimeoutSec, 0 };
        ::setsockopt( fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof( tv ) );
        ::setsockopt( fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof( one ) );

        bool          tooManyHeaderBytes = false, tooLargeBody = false;
        const Request req = readRequest( fd, tooManyHeaderBytes, tooLargeBody );

        if( tooLargeBody )
        {
            respond( fd, "413 Payload Too Large", "application/json", jsonRpcError( -32600, "request body exceeds the 8 MB limit" ) );
        }
        else if( tooManyHeaderBytes )
        {
            respond( fd, "431 Request Header Fields Too Large", "application/json", jsonRpcError( -32600, "request headers too large" ) );
        }
        else if( !req.ok )
        {
            // A COMPLETE-but-malformed request that we actually parsed a line of → a clean 400. A connection
            // that merely stalled/closed before a full request produced an empty method; nothing to answer,
            // just close (the server lives either way).
            if( !req.method.empty() )
            {
                respond( fd, "400 Bad Request", "application/json", jsonRpcError( -32600, "malformed HTTP request" ) );
            }
        }
        else if( req.hasOrigin && !isAllowedOrigin( req.origin, host, port, loopback ) )
        {
            respond( fd, "403 Forbidden", "application/json", jsonRpcError( -32003, "invalid Origin header" ) );
        }
        else if( authRequired && !constantTimeEquals( bearerCredential( req.authorization ), cfg.token ) )
        {
            respond( fd, "401 Unauthorized", "application/json", jsonRpcError( -32001, "missing or invalid bearer token" ) );
        }
        else if( req.target != "/mcp" )
        {
            respond( fd, "404 Not Found", "application/json", jsonRpcError( -32601, "unknown endpoint (POST to /mcp)" ) );
        }
        else if( req.method == "GET" )
        {
            respond( fd, "405 Method Not Allowed", "application/json", jsonRpcError( -32600, "SSE is not supported" ) );
        }
        else if( req.method != "POST" )
        {
            respond( fd, "405 Method Not Allowed", "application/json", jsonRpcError( -32600, "only POST /mcp is supported" ) );
        }
        else if( !req.hasContentLength )
        {
            respond( fd, "411 Length Required", "application/json", jsonRpcError( -32600, "Content-Length is required" ) );
        }
        else if( !req.hasAccept || !acceptsMcpResponseTypes( req.accept ) )
        {
            respond( fd, "406 Not Acceptable", "application/json", jsonRpcError( -32600, "Accept must list application/json and text/event-stream" ) );
        }
        else if( !req.hasContentType || !isJsonContentType( req.contentType ) )
        {
            respond( fd, "415 Unsupported Media Type", "application/json", jsonRpcError( -32600, "Content-Type must be application/json" ) );
        }
        else if( mcpdetail::findString( req.body, "method" ) != "initialize" && req.hasProtocolVersion && !isMcpProtocolVersionSupported( req.protocolVersion ) )
        {
            respond( fd, "400 Bad Request", "application/json", jsonRpcError( -32600, "invalid or unsupported MCP-Protocol-Version" ) );
        }
        else
        {
            // authorized, well-formed POST /mcp → the SAME shared handler the stdio loop uses. A notification
            // (no id) gets a bodyless 202; everything else a 200 with the JSON-RPC response as the body.
            const std::chrono::steady_clock::time_point t0 =
                timingsOn ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
            const std::uint64_t rebuildAtStart = timingsOn ? mcpRebuildCounter().load( std::memory_order_relaxed ) : 0;

            const McpDispatchResult r = dispatchMcpLine( req.body, cfg.topK, cfg.stable, cfg.noRedact, policy );
            if( r.isNotification )
            {
                respond( fd, "202 Accepted", "application/json", std::string{} );
            }
            else
            {
                respond( fd, "200 OK", "application/json", r.resp );
            }

            if( timingsOn )
            {
                const double wallMs = std::chrono::duration< double, std::milli >(
                                          std::chrono::steady_clock::now() - t0 ).count();
                const unsigned rebuilt = ( mcpRebuildCounter().load( std::memory_order_relaxed ) != rebuildAtStart ) ? 1u : 0u;
                std::fprintf( stderr, "ripwire-timing verb=%s wall_ms=%.3f rebuilt=%u\n", r.timingVerb.c_str(), wallMs, rebuilt );
                std::fflush( stderr );
            }
        }

        ::close( fd );
    }

    // unreachable (the accept loop runs until the process is signalled) — kept for symmetry / future signal handling.
    ::close( listenFd );
    return 0;
}

}   // namespace rw
