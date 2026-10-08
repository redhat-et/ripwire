#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "lsp.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

// ─── lsp.h — the --lsp navigation server (Phase 1 PoC; plan: docs/LSP.md) ──────────────────────
//
// A read-only, navigation-focused LSP 3.x server over stdio: initialize/shutdown/exit lifecycle, the five
// providers (definition, references, documentSymbol, workspace symbol, hover), and nothing else. The whole
// server is this section — framing, session, dispatch, handlers — riding the SAME warm index every MCP verb
// uses (getIndex(): parse-once, lazy stat-sweep staleness, content-hash cache), so no second indexer runs
// and the resolvers are the house ones verbatim (resolveAllByName, collectUseSites, docCommentBefore).
//
// THE PHASE 1 CONTRACT (locked decisions, docs/LSP.md — read before changing anything here):
//   • Saved-state answers. An unsaved (or never-saved) buffer is not "mispositioned" — it is ABSENT from
//     the index: no symbols, no references, nothing to navigate. didChange content is deliberately never
//     read; didOpen/didClose are tracked for the session record only. A saved file is picked up by the
//     stat sweep on the next request — the MCP freshness contract unchanged.
//   • Positions are UTF-8 encoding units (bytes within a line) — advertised as such at initialize, and
//     every conversion in this file honours it. UTF-16 is out of scope.
//   • Floor honesty (D6): JSON-RPC has no metadata channel beside a result, so the disclosure travels
//     inside the hover text — every hover carries "counts are floors, not totals; unsaved buffers are
//     absent" — and a zero means "none found", never "none exists".
//   • definition → null on not-found (D5, the standard LSP reading); references → [] as the normal
//     answer; documentSymbol → null for a file the index does not know (absent, not empty).
//   • The root comes from initialize.rootUri (authoritative), falling back to the command-line root and
//     then the launch cwd (D4). The first request after spawn carries the cold-build cost inside
//     initialize — warm-up runs there, not on the first go-to-definition.
//   • Single-threaded, one request at a time — the MCP stdio posture: no locks, no TSan surface. Every
//     response is a pure function of tree state; nothing about timing reaches an output byte.
//
// NON-GOALS (Phase 1): callHierarchy, completion, diagnostics, rename, codeActions, didChange overlays,
// UTF-16 columns, TCP transport, multi-root workspaceFolders, $/progress, reference end-byte persistence,
// BM25 workspace ranking. Each has a stated reason in docs/LSP.md; do not "helpfully" add one here.

#include "infra/os.h"        // rw::os::realpath / getcwd / stat — the root-is-a-directory check at initialize, the launch-cwd base for relative index paths
#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits.h>          // PATH_MAX — lspReal's realpath buffer, os::getcwd's buffer
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace
{
namespace lsp
{

// ─── framing (Content-Length, RFC 8259 bodies) ───────────────────────────────────────────────────────
// LSP frames every message with `Content-Length: N` headers and an N-byte body. MCP stdio is
// newline-delimited and HTTP has its own reader — none of those readers apply here; this is the one seam
// that is genuinely new, and it is deliberately small: parse ONLY Content-Length, ignore every other
// header the spec allows, and never allocate past the ceilings (degrade-don't-crash, the mcphttp posture).

inline constexpr std::size_t kLspMaxHeaderBytes = 64u * 1024u;
inline constexpr std::size_t kLspMaxBodyBytes   = 32u * 1024u * 1024u;
inline constexpr std::size_t kLspHoverDefCap    = 8u;     // definitions rendered in one hover
inline constexpr std::size_t kLspHoverUseCap    = 8u;     // use-site links rendered in one hover
inline constexpr std::size_t kLspWorkspaceCap   = 20u;    // workspace/symbol picker rows (D9)

struct LspFrame
{
    bool        eof       = false;   // stream ended (or framing broke) — the session closes
    bool        malformed = false;   // framing broke specifically (the stderr note distinguishes it)
    std::string body;
};

inline bool lspHeaderHasTerm( const std::string& head, int& termLen )
{
    const std::size_t n = head.size();
    if( n >= 4 && head.compare( n - 4, 4, "\r\n\r\n" ) == 0 ) { termLen = 4; return true; }
    if( n >= 2 && head[ n - 1 ] == '\n' && head[ n - 2 ] == '\n' ) { termLen = 2; return true; }   // lenient LF-only
    return false;
}

// Read exactly one framed message off `in`. EOF is the normal shutdown (an editor closing the pipe);
// an oversized header or body, a missing/unparseable Content-Length, or a short body read all read as
// malformed framing — the session then closes, exactly as a transport failure should, never mid-message.
inline LspFrame lspReadMessage( std::FILE* in )
{
    LspFrame f;
    std::string head;
    int         termLen = 0;
    for( ;; )
    {
        const int c = std::fgetc( in );
        if( c == EOF ) { f.eof = true; return f; }
        head.push_back( static_cast<char>( c ) );
        if( lspHeaderHasTerm( head, termLen ) ) break;
        if( head.size() > kLspMaxHeaderBytes ) { f.eof = true; f.malformed = true; return f; }
    }

    std::string low = head;
    std::transform( low.begin(), low.end(), low.begin(),
                    [ ]( char c ) { return static_cast<char>( std::tolower( static_cast<unsigned char>( c ) ) ); } );   // char in, explicit narrowing: an unsigned char parameter is G1's implicit sign-change on a byte >= 0x80
    const std::size_t k = low.find( "content-length:" );
    if( k == std::string::npos ) { f.eof = true; f.malformed = true; return f; }
    std::size_t len = 0;
    std::size_t p   = k + 15;
    while( p < low.size() && ( low[ p ] == ' ' || low[ p ] == '\t' ) ) ++p;   // "Content-Length: N" carries a space
    for( ; p < low.size() && low[ p ] >= '0' && low[ p ] <= '9'; ++p )
    {
        len = len * 10 + static_cast<std::size_t>( low[ p ] - '0' );
        if( len > kLspMaxBodyBytes ) { f.eof = true; f.malformed = true; return f; }
    }
    if( p == k + 15 || len == 0 ) { f.eof = true; f.malformed = true; return f; }

    // The header loop stops at the LAST byte of the terminator, so no body byte was consumed yet —
    // read the full body here and only here.
    f.body.resize( len );
    const std::size_t got = std::fread( f.body.data(), 1, len, in );
    if( got != len ) { f.eof = true; f.malformed = true; return f; }
    return f;
}

// The picker's cap, disclosed (#279 review, @mpapis): a query matching more than kLspWorkspaceCap rows answers the first
// kLspWorkspaceCap and says how many it left out in a window/logMessage (type 3, Info) sent just before the response,
// the one channel LSP gives a result that has no truncation field. test/lspcheck.sh arm (17).
inline std::string lspWorkspaceCapNotice( const std::string& query, std::size_t total )
{
    return "{\"jsonrpc\":\"2.0\",\"method\":\"window/logMessage\",\"params\":{\"type\":3,\"message\":\"ripwire: workspace/symbol shows the first "
         + std::to_string( kLspWorkspaceCap ) + " of " + std::to_string( total ) + " matches for '" + rw::mcpdetail::jsonEscape( query )
         + "'; refine the query to see the rest\"}}";
}

inline void lspWriteMessage( std::FILE* out, const std::string& body )
{
    char hdr[ 64 ];
    rw::formatTo( hdr, sizeof( hdr ), "Content-Length: {}\r\n\r\n", body.size() );
    std::fwrite( hdr, 1, std::strlen( hdr ), out );
    std::fwrite( body.data(), 1, body.size(), out );
    std::fflush( out );
}

// ─── URI ⇄ path (UTF-8 percent codec over the minimal set: % space # ? control DEL) ─────────────────
inline std::string lspPercentDecode( std::string_view s )
{
    const auto hexVal = [ ]( char c ) noexcept -> int
    {
        if( c >= '0' && c <= '9' ) return c - '0';
        if( c >= 'a' && c <= 'f' ) return c - 'a' + 10;
        if( c >= 'A' && c <= 'F' ) return c - 'A' + 10;
        return -1;
    };
    std::string out;
    out.reserve( s.size() );
    for( std::size_t i = 0; i < s.size(); ++i )
    {
        if( s[ i ] == '%' && i + 2 < s.size() )
        {
            const int hi = hexVal( s[ i + 1 ] ), lo = hexVal( s[ i + 2 ] );
            if( hi >= 0 && lo >= 0 ) { out.push_back( static_cast<char>( hi * 16 + lo ) ); i += 2; continue; }
        }
        out.push_back( s[ i ] );
    }
    return out;
}

inline std::string lspUriToPath( std::string_view uri )
{
    static constexpr std::string_view scheme = "file://";
    if( uri.size() > scheme.size() && uri.substr( 0, scheme.size() ) == scheme )
    {
        return lspPercentDecode( uri.substr( scheme.size() ) );
    }
    return {};   // untitled:, vscode-vfs:, anything else — a buffer the disk index cannot know (absent)
}

inline std::string lspEncodeUriPath( const std::string& p )
{
    static constexpr char kHex[] = "0123456789ABCDEF";
    std::string out;
    out.reserve( p.size() + 8 );
    for( const char c : p )
    {
        const unsigned char u = static_cast<unsigned char>( c );
        if( c == '%' || c == ' ' || c == '#' || c == '?' || u < 0x20 || u == 0x7F )
        {
            out += '%'; out += kHex[ u >> 4 ]; out += kHex[ u & 0xF ];
        }
        else
        {
            out.push_back( c );
        }
    }
    return out;
}

// Make an index path absolute against the server's launch cwd. The ingest stored paths in whatever
// spelling the root argument carried ("./x", "sub/x", or already absolute); the client always speaks
// absolute. The same cwd joined both sides for the whole process lifetime, so the two agree.
inline std::string lspCwdAbsolute( const std::string& cwd, std::string_view p )
{
    if( !p.empty() && p.front() == '/' ) return std::string( p );
    std::string r( p );
    while( r.rfind( "./", 0 ) == 0 ) r.erase( 0, 2 );
    if( r.empty() || r == "." ) return cwd;
    return cwd + "/" + r;
}

inline std::string lspReal( const std::string& p )
{
    char buf[ PATH_MAX ];
    return rw::os::realpath( p.c_str(), buf ) ? std::string( buf ) : std::string();
}


// ─── line-indexed documents (UTF-8 byte positions throughout, per D3) ───────────────────────────────
struct LspDoc
{
    bool                      loaded = false;   // read attempted (ok may still be false — the file is gone)
    bool                      ok     = false;
    std::string               bytes;
    std::vector<std::size_t>  starts;   // byte offset of each 0-based line
};

inline LspDoc lspLoadDoc( const std::string& path )
{
    LspDoc d;
    d.loaded = true;
    const std::optional<std::string> raw = rw::docparse::detail::readWholeFile( path );
    if( !raw ) return d;
    d.ok    = true;
    d.bytes = *raw;
    d.starts.push_back( 0 );
    for( std::size_t i = 0; i < d.bytes.size(); ++i )
    {
        if( d.bytes[ i ] == '\n' ) d.starts.push_back( i + 1 );
    }
    return d;
}

inline bool lspByteAt( const LspDoc& d, std::uint32_t line, std::uint32_t ch, std::size_t& out )
{
    if( !d.ok || line >= d.starts.size() ) return false;
    const std::size_t lineEnd = ( line + 1 < d.starts.size() ) ? d.starts[ line + 1 ] : d.bytes.size();
    std::size_t b = d.starts[ line ] + ch;
    if( b > lineEnd ) b = lineEnd;   // a position past the line's end clamps onto it (clients may ask)
    out = b;
    return true;
}

inline bool lspLineCol( const LspDoc& d, std::size_t byte, std::uint32_t& line, std::uint32_t& ch )
{
    if( !d.ok || d.starts.empty() || byte > d.bytes.size() ) return false;
    const auto it = std::upper_bound( d.starts.begin(), d.starts.end(), byte );
    const std::size_t idx = ( it == d.starts.begin() ) ? 0 : static_cast<std::size_t>( it - d.starts.begin() - 1 );
    line = static_cast<std::uint32_t>( idx );
    ch   = static_cast<std::uint32_t>( byte - d.starts[ idx ] );
    return true;
}

inline bool lspIdentChar( char c ) noexcept
{
    const unsigned char u = static_cast<unsigned char>( c );
    return std::isalnum( u ) != 0 || c == '_' || c == '$' || u >= 0x80;
}

// The identifier token at/adjacent to a byte. An LSP cursor sits BETWEEN characters, so a byte that is
// not itself identifier material may still be right after the token's last character (the word-end
// cursor) — that one-step look-back is the whole reason this is not just isIdent(byte).
inline bool lspIdentSpan( const LspDoc& d, std::size_t byte, std::size_t& b0, std::size_t& b1 )
{
    if( !d.ok || d.bytes.empty() ) return false;
    std::size_t p = ( byte < d.bytes.size() ) ? byte : d.bytes.size() - 1;
    if( !lspIdentChar( d.bytes[ p ] ) )
    {
        if( p == 0 || !lspIdentChar( d.bytes[ p - 1 ] ) ) return false;
        p -= 1;
    }
    b0 = p; b1 = p + 1;
    while( b0 > 0 && lspIdentChar( d.bytes[ b0 - 1 ] ) ) --b0;
    while( b1 < d.bytes.size() && lspIdentChar( d.bytes[ b1 ] ) ) ++b1;
    return true;   // newlines are never identifier chars, so the span never crosses a line
}

// First whole-identifier occurrence of `name` on a 0-based line — the selection/range the client highlights.
inline bool lspFindNameOnLine( const LspDoc& d, std::uint32_t line, std::string_view name,
                               std::uint32_t& c0, std::uint32_t& c1 )
{
    if( !d.ok || name.empty() || line >= d.starts.size() ) return false;
    const std::size_t ls = d.starts[ line ];
    const std::size_t le = ( line + 1 < d.starts.size() ) ? d.starts[ line + 1 ] : d.bytes.size();
    for( std::size_t i = ls; i + name.size() <= le; ++i )
    {
        if( d.bytes.compare( i, name.size(), name ) != 0 ) continue;
        if( i > ls && lspIdentChar( d.bytes[ i - 1 ] ) ) continue;
        const std::size_t after = i + name.size();
        if( after < le && lspIdentChar( d.bytes[ after ] ) ) continue;
        c0 = static_cast<std::uint32_t>( i - ls );
        c1 = c0 + static_cast<std::uint32_t>( name.size() );
        return true;
    }
    return false;
}

// Per-request document cache keyed by fileId. Sized once against the index, loaded lazily, never outlives
// the request — a rebuild between requests gets fresh bytes because the cache dies with the request.
struct LspDocs
{
    const rw::IngestResult& ing;
    std::vector<LspDoc>     slots;
    explicit LspDocs( const rw::IngestResult& i ) : ing( i ), slots( i.files.size() ) {}
    const LspDoc& get( std::uint32_t fileId )
    {
        if( fileId >= slots.size() )
        {
            static const LspDoc kNoDoc;
            return kNoDoc;
        }
        LspDoc& d = slots[ fileId ];
        if( !d.loaded ) d = lspLoadDoc( rw::diskPath( ing, fileId ) );
        return d;
    }
};

// ─── JSON (reuse the MCP protocol layer for parse + escape) ──────────────────────────────────────────
inline std::string lspEscape( const std::string& s ) { return rw::mcpdetail::jsonEscape( s ); }

inline std::string lspRangeJson( std::uint32_t l0, std::uint32_t c0, std::uint32_t l1, std::uint32_t c1 )
{
    char buf[ 128 ];
    rw::formatTo( buf, sizeof( buf ),
                  "{{\"start\":{{\"line\":{},\"character\":{}}},\"end\":{{\"line\":{},\"character\":{}}}}}",
                  l0, c0, l1, c1 );
    return std::string( buf );
}

inline std::string lspResultJson( const std::string& idToken, const std::string& result )
{
    return "{\"jsonrpc\":\"2.0\",\"id\":" + idToken + ",\"result\":" + result + "}";
}

inline std::string lspErrorJson( const std::string& idToken, int code, const std::string& message )
{
    return "{\"jsonrpc\":\"2.0\",\"id\":" + idToken + ",\"error\":{\"code\":" + std::to_string( code )
         + ",\"message\":\"" + lspEscape( message ) + "\"}}";
}

// ─── kinds (LSP SymbolKind numbers; the words ride hover text only) ──────────────────────────────────
inline int lspKindOf( rw::SymKind k ) noexcept
{
    switch( k )
    {
        case rw::SymKind::Function:  return 12;   // Function
        case rw::SymKind::Method:    return 6;    // Method
        case rw::SymKind::Class:     return 5;    // Class
        case rw::SymKind::Struct:    return 23;   // Struct
        case rw::SymKind::Interface: return 11;   // Interface
        case rw::SymKind::Var:       return 13;   // Variable
        case rw::SymKind::Section:   return 2;    // Module — a doc-heading section has no LSP home
        case rw::SymKind::Macro:     return 14;   // Constant
        case rw::SymKind::Field:     return 8;    // Field
        case rw::SymKind::ModuleScope: return 2;  // Module — LSP's own word for a file's top-level scope
        case rw::SymKind::NamedType: return 5;    // Class — LSP has no defined-type/alias kind; gopls files a non-struct named type here too
        case rw::SymKind::Alias:     return 5;    // Class (as above)
        case rw::SymKind::FuncType:  return 5;    // Class (as above)
        case rw::SymKind::Other:     break;
    }
    return 13;   // Variable — the neutral bucket
}

// The hover word per SymKind, a declarative table in enum order (CONTRIBUTING §3's table-over-switch rule; it was a
// switch, and the three Go named-type kinds made it a near-clone of model.h's langTag switch). Sized by kSymKindCount,
// so an appended kind without a word does not compile.
inline constexpr std::array<const char*, rw::kSymKindCount> kLspKindWords = {
    "function", "method", "class", "struct", "interface", "variable", "section", "macro", "field",
    "symbol",          // Other
    "module scope",    // ModuleScope
    "type", "type alias", "function type"   // NamedType, Alias, FuncType
};
inline const char* lspKindWord( rw::SymKind k ) noexcept
{
    EXPECTS( std::size_t( k ) < kLspKindWords.size(), "a symbol's kind is a SymKind enumerator (the cache validates the byte)" );
    return kLspKindWords[ std::size_t( k ) ];
}

// ─── file identity: a client URI → an index fileId ──────────────────────────────────────────────────
inline bool lspFindFile( const rw::IngestResult& ing, const std::string& cwd,
                         const std::string& uri, std::uint32_t& fileIdOut )
{
    const std::string path = lspUriToPath( uri );
    if( path.empty() ) return false;
    const std::string want = lspCwdAbsolute( cwd, path );
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( lspCwdAbsolute( cwd, rw::diskPath( ing, f ) ) == want ) { fileIdOut = f; return true; }
    }
    const std::string wantReal = lspReal( want );   // the slow path once: a symlinked checkout
    if( wantReal.empty() ) return false;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( lspReal( lspCwdAbsolute( cwd, rw::diskPath( ing, f ) ) ) == wantReal ) { fileIdOut = f; return true; }
    }
    return false;
}

// ─── params readers (the MCP findObject/findString/findRawValue ladder, nested per level) ────────────
inline std::string lspDocUri( const std::string& params )
{
    return rw::mcpdetail::findString( rw::mcpdetail::findObject( params, "textDocument" ), "uri" );
}

struct LspPos
{
    bool           ok = false;
    std::string    uri;
    std::uint32_t  line = 0, ch = 0;
};

inline LspPos lspReadPos( const std::string& params )
{
    LspPos p;
    p.uri = lspDocUri( params );
    const std::string pos = rw::mcpdetail::findObject( params, "position" );
    const rw::mcpdetail::RawValue lv = rw::mcpdetail::findRawValue( pos, "line" );
    const rw::mcpdetail::RawValue cv = rw::mcpdetail::findRawValue( pos, "character" );
    long long l = -1, c = -1;
    p.ok = !p.uri.empty() && lv.isPresent && cv.isPresent
        && rw::mcpdetail::parseWholeInt( lv.text, l ) && rw::mcpdetail::parseWholeInt( cv.text, c )
        && l >= 0 && c >= 0;
    p.line = static_cast<std::uint32_t>( l );
    p.ch   = static_cast<std::uint32_t>( c );
    return p;
}

// What the cursor is on: the identifier token plus the index file it sits in (absent ⇒ the buffer is
// outside the index — unsaved or another tree — which is "none found", never an error).
struct LspAtCursor
{
    bool           found = false;
    std::string    name;
    std::string    rangeJson;
    std::uint32_t  fileId = 0;
    std::size_t    byte   = 0;
    bool           hasByte = false;
};

inline LspAtCursor lspAtCursor( const rw::IngestResult& ing, const std::string& cwd, LspDocs& docs,
                                const LspPos& pos )
{
    LspAtCursor r;
    std::uint32_t fileId = 0;
    if( !lspFindFile( ing, cwd, pos.uri, fileId ) ) return r;
    const LspDoc& d = docs.get( fileId );
    std::size_t byte = 0;
    if( !lspByteAt( d, pos.line, pos.ch, byte ) ) return r;
    std::size_t b0 = 0, b1 = 0;
    if( !lspIdentSpan( d, byte, b0, b1 ) ) return r;
    r.found   = true;
    r.fileId  = fileId;
    r.byte    = byte;
    r.hasByte = true;
    r.name    = d.bytes.substr( b0, b1 - b0 );
    std::uint32_t l0 = 0, c0 = 0;
    if( lspLineCol( d, b0, l0, c0 ) )
    {
        const std::size_t ls = d.starts[ l0 ];
        r.rangeJson = lspRangeJson( l0, static_cast<std::uint32_t>( b0 - ls ),
                                    l0, static_cast<std::uint32_t>( b1 - ls ) );
    }
    return r;
}

// ─── locations ───────────────────────────────────────────────────────────────────────────────────────
inline std::string lspLocationJson( const rw::IngestResult& ing, const std::string& cwd, std::uint32_t fileId,
                                    std::uint32_t l0, std::uint32_t c0, std::uint32_t l1, std::uint32_t c1 )
{
    const std::string uri = "file://" + lspEncodeUriPath( lspCwdAbsolute( cwd, rw::diskPath( ing, fileId ) ) );
    return "{\"uri\":\"" + lspEscape( uri ) + "\",\"range\":" + lspRangeJson( l0, c0, l1, c1 ) + "}";
}

// The def's Location: its start line, narrowed to the name token where the line carries it.
inline std::string lspSymbolLocationJson( const rw::IngestResult& ing, const std::string& cwd, LspDocs& docs,
                                          const rw::Symbol& s )
{
    const LspDoc&       d    = docs.get( s.fileId );
    const std::uint32_t line = ( s.line > 0 ) ? s.line - 1 : 0;
    std::uint32_t       c0   = 0, c1 = 1;
    if( !lspFindNameOnLine( d, line, s.name, c0, c1 ) ) { c0 = 0; c1 = 1; }
    return lspLocationJson( ing, cwd, s.fileId, line, c0, line, c1 );
}

inline std::string lspSymbolRangeJson( const LspDoc& d, const rw::Symbol& s )
{
    const std::uint32_t line = ( s.line > 0 ) ? s.line - 1 : 0;
    std::uint32_t       l0   = line, c0 = 0, l1 = line, c1 = 1;
    if( d.ok )
    {
        const std::size_t start = std::min( static_cast<std::size_t>( s.sigStartByte ), d.bytes.size() );
        const std::size_t end   = std::max( std::min( static_cast<std::size_t>( s.endByte ), d.bytes.size() ),
                                            start + 1u );   // a range must be non-empty
        if( !lspLineCol( d, start, l0, c0 ) ) { l0 = line; c0 = 0; }
        if( !lspLineCol( d, end,   l1, c1 ) ) { l1 = line; c1 = 1; }
    }
    return lspRangeJson( l0, c0, l1, c1 );
}

// ─── handlers ────────────────────────────────────────────────────────────────────────────────────────
// definition: the name under the cursor, resolved through the shared name resolver (the same one --callers
// and MCP find_symbol use). Multi-definition names return every def — the client shows a picker.
inline std::string lspDefinition( const rw::IngestResult& ing, const std::string& cwd, LspDocs& docs,
                                  const LspPos& pos )
{
    const LspAtCursor at = lspAtCursor( ing, cwd, docs, pos );
    if( !at.found ) return "null";
    const std::vector<rw::NodeId> defs = rw::resolveAllByName( ing, at.name );
    std::string                   out  = "[";
    bool                          first = true;
    for( const rw::NodeId id : defs )
    {
        if( id >= ing.symbols.size() ) continue;
        if( !first ) out += ",";
        first = false;
        out += lspSymbolLocationJson( ing, cwd, docs, ing.symbols[ id ] );
    }
    out += "]";
    return first ? std::string( "null" ) : out;
}

// references: the house use-site scan (collectUseSites — the --uses answer, name-matched FLOOR by
// construction; the hover carries the disclosure because the result itself has no channel for it).
inline std::string lspReferences( const rw::IngestResult& ing, const std::string& cwd, LspDocs& docs,
                                  const LspPos& pos, bool includeDeclaration )
{
    const LspAtCursor at = lspAtCursor( ing, cwd, docs, pos );
    if( !at.found ) return "[]";
    const std::vector<rw::NodeId> defs = rw::resolveAllByName( ing, at.name );
    const UsesSelector            sel  = resolveUsesSelector( ing, at.name, defs );
    const auto                    got  = collectUseSites( ing, sel, std::span<const char>{}, std::string_view{} );

    std::vector<char>                                        seenDef( ing.symbols.size(), 0 );
    std::vector<std::pair<std::uint32_t, std::uint32_t>>     seenSite;
    std::string                                              out = "[";
    bool                                                     first = true;
    const auto append = [ & ]( const std::string& loc )
    {
        if( !first ) out += ",";
        first = false;
        out += loc;
    };
    if( includeDeclaration )
    {
        for( const rw::NodeId id : defs )
        {
            if( id >= ing.symbols.size() || seenDef[ id ] ) continue;
            seenDef[ id ] = 1;
            const rw::Symbol& s = ing.symbols[ id ];
            const LspDoc&     d  = docs.get( s.fileId );
            const std::uint32_t line = ( s.line > 0 ) ? s.line - 1 : 0;
            std::uint32_t     c0 = 0, c1 = 1;
            if( !lspFindNameOnLine( d, line, s.name, c0, c1 ) ) { c0 = 0; c1 = 1; }
            append( lspLocationJson( ing, cwd, s.fileId, line, c0, line, c1 ) );
            seenSite.emplace_back( s.fileId, s.line );
        }
    }
    for( const UseSite& u : got.first )
    {
        if( u.fileId >= ing.files.size() ) continue;
        bool dup = false;
        for( const auto& s : seenSite ) { if( s.first == u.fileId && s.second == u.line ) { dup = true; break; } }
        if( dup ) continue;
        seenSite.emplace_back( u.fileId, u.line );
        const LspDoc&            d    = docs.get( u.fileId );
        const std::uint32_t      line = ( u.line > 0 ) ? u.line - 1 : 0;
        std::uint32_t            c0   = 0, c1 = 1;
        if( !lspFindNameOnLine( d, line, at.name, c0, c1 ) ) { c0 = 0; c1 = 1; }
        append( lspLocationJson( ing, cwd, u.fileId, line, c0, line, c1 ) );
    }
    out += "]";
    return out;
}

// documentSymbol: the file's defs AND the field side table merged (D8 — a field is a symbol to an
// outline even though it enters no map row), nested one level by byte-span containment.
inline std::string lspDocumentSymbol( const rw::IngestResult& ing, const std::string& cwd, LspDocs& docs,
                                      const std::string& uri )
{
    std::uint32_t fileId = 0;
    if( !lspFindFile( ing, cwd, uri, fileId ) ) return "null";

    struct Node
    {
        const rw::Symbol*  sym   = nullptr;
        std::size_t        start = 0, end = 0;
        int                parent = -1;
        std::vector<int>   children;
    };
    std::vector<Node> nodes;
    for( const rw::Symbol& s : ing.symbols )
    {
        if( s.fileId == fileId ) nodes.push_back( { &s, s.sigStartByte, s.endByte, -1, {} } );
    }
    for( const rw::Symbol& f : ing.fields )   // D8: the side table, in the outline too
    {
        if( f.fileId == fileId ) nodes.push_back( { &f, f.sigStartByte, f.endByte, -1, {} } );
    }
    std::sort( nodes.begin(), nodes.end(), [ ]( const Node& a, const Node& b )
               {
        if( a.start != b.start ) return a.start < b.start;
        if( a.end   != b.end   ) return a.end > b.end;
        return a.sym->name < b.sym->name; } );

    for( std::size_t i = 0; i < nodes.size(); ++i )
    {
        int        best = -1;
        std::size_t bestSpan = 0;
        for( std::size_t j = 0; j < nodes.size(); ++j )
        {
            if( i == j ) continue;
            if( nodes[ j ].start <= nodes[ i ].start && nodes[ i ].end <= nodes[ j ].end )
            {
                const std::size_t span = nodes[ j ].end - nodes[ j ].start;
                if( best < 0 || span < bestSpan ) { best = static_cast<int>( j ); bestSpan = span; }
            }
        }
        nodes[ i ].parent = best;
    }
    for( std::size_t i = 0; i < nodes.size(); ++i )
    {
        if( nodes[ i ].parent >= 0 ) nodes[ nodes[ i ].parent ].children.push_back( static_cast<int>( i ) );
    }

    const LspDoc& d = docs.get( fileId );
    const auto nodeJson = [ & ]( auto&& self, std::size_t idx ) -> std::string
    {
        const rw::Symbol&  s    = *nodes[ idx ].sym;
        const std::uint32_t line = ( s.line > 0 ) ? s.line - 1 : 0;
        std::uint32_t      sc0  = 0, sc1 = 1;
        if( !lspFindNameOnLine( d, line, s.name, sc0, sc1 ) ) { sc0 = 0; sc1 = 1; }
        std::string out = "{\"name\":\"" + lspEscape( s.name ) + "\",\"kind\":" + std::to_string( lspKindOf( s.kind ) )
                        + ",\"range\":" + lspSymbolRangeJson( d, s )
                        + ",\"selectionRange\":" + lspRangeJson( line, sc0, line, sc1 );
        if( !nodes[ idx ].children.empty() )
        {
            out += ",\"children\":[";
            for( std::size_t k = 0; k < nodes[ idx ].children.size(); ++k )
            {
                if( k ) out += ",";
                out += self( self, static_cast<std::size_t>( nodes[ idx ].children[ k ] ) );
            }
            out += "]";
        }
        out += "}";
        return out;
    };

    std::string out = "[";
    bool        first = true;
    for( std::size_t i = 0; i < nodes.size(); ++i )
    {
        if( nodes[ i ].parent != -1 ) continue;
        if( !first ) out += ",";
        first = false;
        out += nodeJson( nodeJson, i );
    }
    out += "]";
    return out;
}

// workspace/symbol (D9): exact-name resolution first, then case-insensitive substring over NAMES only —
// no BM25, which is tuned for task prose and would surface non-name rows in a picker. The list keeps the first
// kLspWorkspaceCap matches in that order; every match is still COUNTED into `totalOut`, so the caller can disclose a
// cut (lspWorkspaceCapNotice) — a SymbolInformation[] has no field that could say "and N more".
inline std::string lspWorkspaceSymbol( const rw::IngestResult& ing, const std::string& cwd, LspDocs& docs,
                                       std::string_view query, std::size_t& totalOut )
{
    totalOut = 0;
    if( query.empty() ) return "[]";   // Q3: an empty picker query is not an outline dump

    const auto lowerCopy = [ ]( std::string s )
    {
        std::transform( s.begin(), s.end(), s.begin(),
                        [ ]( char c ) { return static_cast<char>( std::tolower( static_cast<unsigned char>( c ) ) ); } );   // char in, explicit narrowing: an unsigned char parameter is G1's implicit sign-change on a byte >= 0x80
        return s;
    };
    const std::string qLower = lowerCopy( std::string( query ) );
    std::vector<char> seen( ing.symbols.size(), 0 );

    std::string out   = "[";
    bool        first = true;
    std::size_t n     = 0;
    const auto  itemJson = [ & ]( const rw::Symbol& s ) -> std::string
    {
        const LspDoc&       d    = docs.get( s.fileId );
        const std::uint32_t line = ( s.line > 0 ) ? s.line - 1 : 0;
        std::uint32_t       c0   = 0, c1 = 1;
        if( !lspFindNameOnLine( d, line, s.name, c0, c1 ) ) { c0 = 0; c1 = 1; }
        std::string o = "{\"name\":\"" + lspEscape( s.name ) + "\",\"kind\":" + std::to_string( lspKindOf( s.kind ) )
                      + ",\"location\":" + lspLocationJson( ing, cwd, s.fileId, line, c0, line, c1 );
        if( !s.scope.empty() ) o += ",\"containerName\":\"" + lspEscape( s.scope ) + "\"";
        o += "}";
        return o;
    };

    const auto take = [ & ]( const rw::Symbol& s )   // count every match; serialize only the first kLspWorkspaceCap
    {
        ++totalOut;
        if( n >= kLspWorkspaceCap ) return;
        ++n;
        if( !first ) out += ",";
        first = false;
        out += itemJson( s );
    };
    for( const rw::NodeId id : rw::resolveAllByName( ing, query ) )
    {
        if( id >= ing.symbols.size() || seen[ id ] ) continue;
        seen[ id ] = 1;
        take( ing.symbols[ id ] );
    }
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        const rw::Symbol& s = ing.symbols[ i ];
        if( seen[ i ] || lowerCopy( s.name ).find( qLower ) == std::string::npos ) continue;
        seen[ i ] = 1;
        take( s );
    }
    for( const rw::Symbol& f : ing.fields )   // fields join the picker too (D8's spirit — the outline and the picker agree)
    {
        if( lowerCopy( f.name ).find( qLower ) != std::string::npos ) take( f );
    }
    out += "]";
    return out;
}

// Is (fileId, line) already in this pair list? The lists are floors and short — linear probe.
inline bool lspPairHas( const std::vector<std::pair<std::uint32_t, std::uint32_t>>& pairs,
                        std::uint32_t fileId, std::uint32_t line )
{
    for( const auto& p : pairs )
        if( p.first == fileId && p.second == line ) return true;
    return false;
}

// One hover link tier: header, up to `cap` clickable lines (clients open "file:///path#L<n>" from hover
// markdown), and the remainder disclosure. An empty tier speaks `whenEmpty` when given, disappears without.
inline void lspAppendSiteTier( std::string& md, const rw::IngestResult& ing, const std::string& cwd,
                               const char* header, std::size_t cap,
                               const std::vector<std::pair<std::uint32_t, std::uint32_t>>& sites,
                               const char* whenEmpty )
{
    if( sites.empty() && whenEmpty == nullptr ) return;
    md += "\n";
    md += header;
    if( sites.empty() )
    {
        md += "\n" + std::string( whenEmpty ) + "\n";
        return;
    }
    const std::size_t shown = std::min( sites.size(), cap );
    for( std::size_t i = 0; i < shown; ++i )
    {
        const std::string& path = ing.files[ sites[ i ].first ];
        md += "\n- [`" + path + ":" + std::to_string( sites[ i ].second ) + "`](file://"
            + lspEncodeUriPath( lspCwdAbsolute( cwd, rw::diskPath( ing, sites[ i ].first ) ) )
            + "#L" + std::to_string( sites[ i ].second ) + ")";
    }
    if( sites.size() > shown ) md += "\n_+" + std::to_string( sites.size() - shown ) + " more_";
    md += "\n";
}

// The defs a hover answers with: name resolution first; when the cursor sits inside a definition whose
// NAME is not under it (a call in its own body, a blank line in a method), the innermost covering def —
// the same containment resolveAtSeed applies to a line seed.
inline std::vector<rw::NodeId> lspHoverDefs( const rw::IngestResult& ing, const LspAtCursor& at )
{
    std::vector<rw::NodeId> defs = rw::resolveAllByName( ing, at.name );
    if( !defs.empty() || !at.hasByte ) return defs;
    const rw::Symbol* best = nullptr;
    for( const rw::Symbol& s : ing.symbols )
    {
        if( s.fileId != at.fileId ) continue;
        if( static_cast<std::size_t>( s.sigStartByte ) > at.byte || at.byte >= static_cast<std::size_t>( s.endByte ) ) continue;
        if( best && ( s.endByte - s.sigStartByte ) >= ( best->endByte - best->sigStartByte ) ) continue;
        best = &s;
    }
    if( best ) defs.push_back( best->id );
    return defs;
}

// The D7 def gist: kind, scope::name, file:line, loc/cx, CSR degrees, the verbatim signature, and the
// captured doc comment — up to kLspHoverDefCap definitions, the remainder disclosed.
inline void lspAppendHoverDefs( std::string& md, const rw::IngestResult& ing, const rw::Graph& g,
                                LspDocs& docs, const std::vector<rw::NodeId>& defs )
{
    std::size_t shown = 0;
    for( const rw::NodeId id : defs )
    {
        if( id >= ing.symbols.size() ) continue;
        if( shown >= kLspHoverDefCap )
        {
            md += "\n_+" + std::to_string( defs.size() - shown ) + " more definitions_\n";
            break;
        }
        ++shown;
        const rw::Symbol& s = ing.symbols[ id ];
        md += std::string( "**" ) + lspKindWord( s.kind ) + "** `"
            + ( s.scope.empty() ? s.name : s.scope + "::" + s.name ) + "`\n";
        md += "`" + ing.files[ s.fileId ] + ":" + std::to_string( s.line ) + "` · "
            + std::to_string( s.loc ) + " lines · cx " + std::to_string( s.cx );
        const auto* ro = g.inEdges.rowOffsets();
        md += " · callers " + std::to_string( ro ? ro[ id + 1 ] - ro[ id ] : 0u )
            + " · callees " + std::to_string( g.outOff[ id + 1 ] - g.outOff[ id ] ) + "\n";
        const LspDoc& d = docs.get( s.fileId );
        if( d.ok && s.sigStartByte < s.sigEndByte && s.sigEndByte <= d.bytes.size() )
        {
            std::string sig = d.bytes.substr( s.sigStartByte, s.sigEndByte - s.sigStartByte );
            md += "\n```\n" + sig;
            if( sig.empty() || sig.back() != '\n' ) md += "\n";
            md += "```\n";
        }
        if( d.ok && s.sigStartByte < d.bytes.size() )
        {
            const std::string doc = rw::docCommentBefore( d.bytes, s.sigStartByte );
            if( !doc.empty() ) md += "\n" + doc + "\n";
        }
    }
}

// hover (D7): the structured gist (above), the Used at (call-role floor) and Referenced at (Ruby
// constant-load directives) link tiers, and the standing floor sentence (D6).
inline std::string lspHover( const rw::IngestResult& ing, const rw::Graph& g, const std::string& cwd,
                             LspDocs& docs, const LspPos& pos )
{
    const LspAtCursor at = lspAtCursor( ing, cwd, docs, pos );
    if( !at.found ) return "null";
    const std::vector<rw::NodeId> defs = lspHoverDefs( ing, at );
    if( defs.empty() ) return "null";

    std::string md;
    lspAppendHoverDefs( md, ing, g, docs, defs );

    // Used at (D7): the same name-matched floor the references provider answers with. Def lines are
    // omitted — they are the block above.
    const UsesSelector sel  = resolveUsesSelector( ing, at.name, defs );
    const auto         uses = collectUseSites( ing, sel, std::span<const char>{}, std::string_view{} );
    std::vector<std::pair<std::uint32_t, std::uint32_t>> defLines, usedAt, refAt;
    for( const rw::NodeId id : defs )
        if( id < ing.symbols.size() ) defLines.emplace_back( ing.symbols[ id ].fileId, ing.symbols[ id ].line );
    for( const UseSite& u : uses.first )
        if( u.fileId < ing.files.size() && !lspPairHas( defLines, u.fileId, u.line ) && !lspPairHas( usedAt, u.fileId, u.line ) )
            usedAt.emplace_back( u.fileId, u.line );

    // Referenced at: Ruby constant-load directives (parser versions 82-93 — superclass, mixin, autoload,
    // constant receivers/arguments, rescue clauses; the constant AS WRITTEN, deduped per body). These never
    // reach the calleeName-keyed scan above — for a class name this is where the uses live. Tail-segment
    // match: `A::B` and `::B` both speak hover name B (floor — lexical resolution is the extractor's
    // RubyConstantIndex's job; hover does not re-resolve it differently).
    for( const rw::Include& inc : ing.includes )
    {
        if( !inc.isSymbolic || inc.fileId >= ing.files.size() ) continue;
        const std::size_t colon = inc.target.rfind( "::" );
        if( inc.target.substr( colon == std::string::npos ? 0 : colon + 2 ) != at.name ) continue;
        const LspDoc&     rd   = docs.get( inc.fileId );
        std::uint32_t     rl0  = 0, rc0 = 0;
        if( !lspLineCol( rd, inc.byte, rl0, rc0 ) ) continue;   // the byte outlived its lines — floor
        const std::uint32_t line = rl0 + 1;
        if( lspPairHas( defLines, inc.fileId, line ) || lspPairHas( usedAt, inc.fileId, line )
            || lspPairHas( refAt, inc.fileId, line ) ) continue;
        refAt.emplace_back( inc.fileId, line );
    }
    std::sort( refAt.begin(), refAt.end() );   // the includes table is scan order; the list reads in line order

    lspAppendSiteTier( md, ing, cwd, "**Used at** (name-matched floor):", kLspHoverUseCap, usedAt,
                       "_None found in this index._" );
    lspAppendSiteTier( md, ing, cwd, "**Referenced at** (Ruby constant-load directives, floor):", kLspHoverUseCap,
                       refAt, nullptr );
    md += "\n*ripwire: name-based index — counts are floors, not totals; unsaved buffers are absent.*";

    return "{\"contents\":{\"kind\":\"markdown\",\"value\":\"" + lspEscape( md ) + "\"}"
         + ( at.rangeJson.empty() ? std::string() : ",\"range\":" + at.rangeJson ) + "}";
}

// ─── the session ─────────────────────────────────────────────────────────────────────────────────────
inline std::string lspStartupCwd()
{
    char buf[ PATH_MAX ];
    if( rw::os::getcwd( buf, sizeof( buf ) ) ) return std::string( buf );
    return {};
}

inline std::string lspCapabilitiesJson()
{
    std::string v( rw::kRipwireVersion );
    return "{\"capabilities\":{\"positionEncoding\":\"utf-8\","
           "\"textDocumentSync\":{\"openClose\":true,\"change\":0},"
           "\"definitionProvider\":true,\"referencesProvider\":true,"
           "\"documentSymbolProvider\":true,\"workspaceSymbolProvider\":true,\"hoverProvider\":true},"
           "\"serverInfo\":{\"name\":\"ripwire\",\"version\":\"" + lspEscape( v ) + "\"}}";
}

// The runLsp loop — shape of runMcp(): read a frame, handle it, write the response, fflush. Lifecycle
// per the LSP 3.x state machine: initialize → initialized → … → shutdown → exit. didChange content is
// read by NOBODY in Phase 1 — the saved-state contract lives in the file header above.
inline int runLsp( const std::string& cliRoot )
{
    const std::string cwd = lspStartupCwd();
    bool              initialized = false, shutDown = false;
    std::string       root;

    for( ;; )
    {
        const LspFrame frame = lspReadMessage( stdin );
        if( frame.eof )
        {
            if( frame.malformed )
            {
                rw::emitRaw( stderr, "ripwire --lsp: malformed Content-Length framing — closing the stream\n" );
            }
            break;
        }

        const rw::mcpdetail::RawId id       = rw::mcpdetail::findRawId( frame.body );
        const std::string          method   = rw::mcpdetail::findString( frame.body, "method" );
        const std::string          params   = rw::mcpdetail::findObject( frame.body, "params" );

        if( method == "exit" ) break;

        std::string resp;
        const auto  respond = [ & ]( int code, const std::string& msg )
        {
            if( id.hasId ) resp = lspErrorJson( id.token, code, msg );
        };

        if( method == "initialize" )
        {
            if( initialized )
            {
                respond( -32002, "server already initialized" );
            }
            else
            {
                std::string cand = lspUriToPath( rw::mcpdetail::findString( params, "rootUri" ) );
                if( cand.empty() ) cand = cliRoot;
                std::string noRootWhy;   // #350: why the launch cwd was not assumed, when it was a home/system directory
                if( cand.empty() ) cand = rw::mcpResolveAssumedRoot( &noRootWhy );
                const std::string canon = cand.empty() ? std::string() : rw::mcpCanonRoot( cand );
                // #350 layer 1: an editor's rootUri is the window it opened, not a project a human named for ripwire —
                // $HOME, a filesystem root or a system tree is refused like the MCP path=, unless it IS the root typed on
                // the command line (`ripwire <root> --lsp`)
                if( noRootWhy.empty() && !canon.empty() && ( cliRoot.empty() || canon != rw::mcpCanonRoot( cliRoot ) ) )
                {
                    noRootWhy = rw::noProjectRootReason( rw::rootGuardCanon( canon.c_str() ) );
                }
                rw::os::stat_t    st;
                if( !noRootWhy.empty() )
                {
                    respond( -32002, "ripwire --lsp: " + noRootWhy );
                }
                else if( canon.empty() || rw::os::stat( canon.c_str(), &st ) != 0 || !S_ISDIR( st.st_mode ) )
                {
                    respond( -32002, "ripwire --lsp: no readable workspace root (initialize.rootUri, the command-line root, or the launch cwd)" );
                }
                else
                {
                    root        = canon;
                    const rw::McpIndex& mix = rw::getIndex( root );   // warm-up HERE, not on the first navigation request
                    initialized = true;
                    rw::emitTo( stderr, "ripwire --lsp: serving {} (files={} symbols={}; utf-8 positions, saved-state answers — counts are floors)\n",
                                root, mix.ing.files.size(), mix.ing.symbols.size() );
                    if( id.hasId ) resp = lspResultJson( id.token, lspCapabilitiesJson() );
                }
            }
        }
        else if( method == "initialized" || method == "$/cancelRequest" || method.rfind( "textDocument/did", 0 ) == 0 )
        {
            // notifications: no response, per the protocol. Phase 1 records open/close nowhere — answers
            // read only saved state — and $/cancelRequest has nothing to cancel: the loop serves one
            // request at a time; a Phase-2 multiplexed transport would answer -32800.
        }
        else if( method == "shutdown" )
        {
            shutDown = true;
            if( id.hasId ) resp = lspResultJson( id.token, "null" );
        }
        else if( !id.hasId )
        {
            // an unknown notification — ignore it, as the spec directs
        }
        else if( !initialized )
        {
            respond( -32002, "server not initialized" );
        }
        else if( shutDown )
        {
            respond( -32001, "server is shut down" );
        }
        else if( method == "textDocument/definition" )
        {
            const LspPos pos = lspReadPos( params );
            if( !pos.ok ) respond( -32602, "textDocument/definition needs params.textDocument.uri and params.position{line,character}" );
            else { const rw::McpIndex& mix = rw::getIndex( root ); LspDocs docs( mix.ing );
                   resp = lspResultJson( id.token, lspDefinition( mix.ing, cwd, docs, pos ) ); }
        }
        else if( method == "textDocument/references" )
        {
            const LspPos pos = lspReadPos( params );
            if( !pos.ok ) respond( -32602, "textDocument/references needs params.textDocument.uri and params.position{line,character}" );
            else
            {
                const rw::mcpdetail::RawValue iv = rw::mcpdetail::findRawValue(
                    rw::mcpdetail::findObject( params, "context" ), "includeDeclaration" );
                const rw::McpIndex& mix = rw::getIndex( root );
                LspDocs         docs( mix.ing );
                resp = lspResultJson( id.token, lspReferences( mix.ing, cwd, docs, pos, iv.isPresent && iv.text == "true" ) );
            }
        }
        else if( method == "textDocument/documentSymbol" )
        {
            const std::string uri = lspDocUri( params );
            if( uri.empty() ) respond( -32602, "textDocument/documentSymbol needs params.textDocument.uri" );
            else { const rw::McpIndex& mix = rw::getIndex( root ); LspDocs docs( mix.ing );
                   resp = lspResultJson( id.token, lspDocumentSymbol( mix.ing, cwd, docs, uri ) ); }
        }
        else if( method == "workspace/symbol" )
        {
            const rw::McpIndex& mix = rw::getIndex( root );
            LspDocs         docs( mix.ing );
            const std::string   query = rw::mcpdetail::findString( params, "query" );
            std::size_t         total = 0;
            const std::string   items = lspWorkspaceSymbol( mix.ing, cwd, docs, query, total );
            if( total > kLspWorkspaceCap ) lspWriteMessage( stdout, lspWorkspaceCapNotice( query, total ) );
            resp = lspResultJson( id.token, items );
        }
        else if( method == "textDocument/hover" )
        {
            const LspPos pos = lspReadPos( params );
            if( !pos.ok ) respond( -32602, "textDocument/hover needs params.textDocument.uri and params.position{line,character}" );
            else { const rw::McpIndex& mix = rw::getIndex( root ); LspDocs docs( mix.ing );
                   resp = lspResultJson( id.token, lspHover( mix.ing, mix.g, cwd, docs, pos ) ); }
        }
        else
        {
            respond( -32601, "method not found: " + method );
        }

        if( !resp.empty() ) lspWriteMessage( stdout, resp );
    }
    return shutDown ? 0 : 1;
}

}   // namespace lsp
}   // unnamed namespace — the LSP PoC section
