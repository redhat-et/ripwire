// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  diagnostics.cpp
//
//  The one out-of-line translation unit behind Diagnostics.h: the ConsoleLog report handlers (assert-family / panic /
//  thread-ownership violation / VALIDATE trace / degraded path) and the thread-id counter. Everything else in the
//  diagnostics system is macros, so every target and every standalone test harness in test/ links exactly this file
//  to satisfy ASSUME, EXPECTS, ENSURES, DASSERT, UNREACHABLE, VALIDATE, ASSUME_SAME_THREAD*, PANIC and
//  DISCLOSE.
//
#include "Diagnostics.h"
#include "agenttrap.h"
#include "emit.h"

#include <atomic>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <format>
#include <utility>

#if !defined( NDEBUG )
  #include <chrono>
  #include <ctime>
  #include <string_view>
  #include <thread>
#endif

namespace Diagnostics
{

// The build-flavour link check behind ThreadOwner (Diagnostics.h §2): only a debug diagnostics.cpp defines it, so a
// debug TU that constructs a ThreadOwner cannot link against a release one.
#if !defined( NDEBUG )
void debugFlavourLinkCheck() noexcept {}
#endif

namespace
{

// Two columns, one row per CheckKind in enum order: the banner, then who to suspect. The blame line is the reason
// EXPECTS and ENSURES exist as words — it is the first thing a reader of the report needs.
constexpr const char* kKindBanner[] = {
    "ASSUME FAILED",
    "EXPECTS FAILED (precondition)",
    "ENSURES FAILED (postcondition)",
    "DASSERT FAILED",
    "UNREACHABLE REACHED",
};
constexpr const char* kKindBlame[] = {
    "an invariant this function relies on is false here",
    "the CALLER broke this function's contract (a bug in ripwire's calling code, not in your input)",
    "THIS function broke its own contract — look inside it",
    "a debug-only check is false (no release promise was made)",
    "control arrived where this function says it cannot",
};

// ── ONE NOTICE, ONE WRITE ────────────────────────────────────────────────────────────────────────────────────────
// Every reporter below formats its whole notice first and hands it to stderr in ONE stdio call. Built instead from a
// chain of `std::cerr <<` insertions, with stdio sync on (the default) each insertion is its own fwrite on an
// unbuffered stderr, so its own write(2): any other thread's single-write line can then land between two insertions
// and split the notice across lines. Measured on a gate whose fixture refuses two files at once: the degraded notice
// torn in 32-73% of runs depending on load, and 0 tears in 3,800 runs once it was written whole (test/diagnoticecheck.sh).
//
// WHY emitRaw OVER A RAW write( 2, … ). One stdio call holds the stream's lock for the whole call, so no other stdio
// writer in the process — which is every other stderr writer here — can interleave, at any length. Underneath, the
// unbuffered stderr hands the whole notice to the kernel as one write(2), measured up to the full buffer (4,094 bytes
// in one write) on macOS's libc and on glibc. A libc that split a long write would still do it with the lock held.
// A raw write(2) would add nothing for this process and would step OUTSIDE that lock, so a line another thread is
// writing through stdio could be split by the notice instead. Across PROCESSES sharing the descriptor, one write to a
// pipe is atomic only up to PIPE_BUF (512 bytes on macOS), and neither spelling changes that.
//
// NO ALLOCATION. A reporter may be running because memory ran out, so the notice is formatted into a fixed stack
// buffer through rw::formatTo, never into a std::string (which std::print and rw::emitTo both build). The buffer is
// a cap: a notice longer than it is cut, and the cut is DISCLOSED in the notice itself (markTruncated, below).
//
// STDOUT FIRST. std::cerr is tied to std::cout, so a chain of insertions flushes stdout before it writes. writeNotice
// keeps that: without it a trap or an abort right after the notice loses whatever stdout still held, and under
// `>file 2>&1` a notice lands ahead of output the program wrote before it. fflush allocates nothing.
inline constexpr std::size_t kNoticeByteCap = 4096;   // a longer notice is cut and says so: " ... [notice truncated: kept K of N bytes]"

// std::format on a null const char* is undefined, and a reporter must survive the malformed call it is reporting.
const char* orEmpty( const char* text ) noexcept
{
    return text != nullptr ? text : "";
}

// The optional "Notes:" row of the assert and thread-violation banners: three pieces, all empty without a description.
struct NotesRow
{
    const char* label;
    const char* text;
    const char* eol;
};

NotesRow notesRowOf( const char* description ) noexcept
{
    if( description != nullptr && description[ 0 ] != '\0' )
    {
        return NotesRow{ "  Notes:    ", description, "\n" };
    }
    return NotesRow{ "", "", "" };
}

// A notice past kNoticeByteCap keeps its opening and ends in a marker giving the bytes KEPT and the notice's full
// length (shown and total, never one ambiguous number), still on a line of its own. The cut backs off to a UTF-8 lead
// byte, so the kept text never ends inside a multi-byte sequence. K depends on the marker's length and the marker
// spells K, so the marker is first sized with the largest K it could carry; the real K is never longer.
void markTruncated( char* notice, std::size_t capacity, std::size_t fullBytes ) noexcept
{
    char       marker[ 96 ];   // 42 literal B + two 20-digit counts + NUL = 83
    const auto formatMarker = [ & ]( std::size_t kept ) noexcept
    {
        return rw::formatTo( marker, sizeof( marker ), " ... [notice truncated: kept {} of {} bytes]\n", kept, fullBytes );
    };
    std::size_t keptBytes = capacity - 1 - formatMarker( capacity - 1 );
    while( keptBytes > 0 && ( static_cast<unsigned char>( notice[ keptBytes ] ) & 0xC0 ) == 0x80 )
    {
        --keptBytes;
    }
    const std::size_t markerBytes = formatMarker( keptBytes );
    std::memcpy( notice + keptBytes, marker, markerBytes + 1 );
}

template<class... A>
RW_COLD void writeNotice( std::format_string<A...> format, A&&... args ) noexcept
{
    char              notice[ kNoticeByteCap ];
    const std::size_t fullBytes = rw::formatTo( notice, sizeof( notice ), format, std::forward<A>( args )... );
    if( fullBytes >= sizeof( notice ) )
    {
        markTruncated( notice, sizeof( notice ), fullBytes );
    }
    std::fflush( stdout );
    rw::emitRaw( stderr, notice );
    std::fflush( stderr );
}

} // namespace

// ── AGENT-VISIBLE-TRAP (agenttrap.h) ─────────────────────────────────────────────────────────────────────────────────
// Debug builds only. What the failure path writes for an agent before the stderr notice and the trap: the JSON-RPC
// error for the MCP request in flight, or the CLI's one <ripwire_internal_error/> line; then the last-crash record.
//
// NO ALLOCATION AFTER THE CHECK FAILS. Everything is formatted into static buffers (the report runs at most once per
// process, claimReport below) or fixed stack buffers, and written with write(2), not stdio: a stdio stream may be the
// thing that is broken, and a FILE* open would allocate. stdout's own buffer is flushed first (fflush allocates
// nothing), so the line lands after whatever the answer already printed, never inside it.
//
// WHY THE TRAP STAYS. The exit status is still the trap's signal (SIGTRAP or SIGILL: 133 or 132 under a shell), not a
// new _exit code. A debugger stops on the failing instruction and a sanitizer or crash reporter records the stack, and
// both depend on the process dying AT the trap with no unwinding. An agent does not need a new exit code to tell this
// apart from an answer: ripwire's own codes are 0-5, a signal status is already distinct from all of them, and the
// line on stdout (or the JSON-RPC error) names the failure in words.
#if !defined( NDEBUG )
namespace agenttrap
{
namespace
{

// The OS calls, through the table main hands over at arm time (agenttrap_os.h, rw::os). This file is linked alone into
// every standalone harness, so it reaches no OS layer of its own; an unarmed process (every harness) has a null table and
// writes nothing beyond the stderr notice.
OsCalls g_os{};

// `put` is g_os.write (a descriptor) or g_os.send (the --listen socket). A short write continues; a failed one stops,
// because nothing is left to fall back to: the stderr notice and the trap still follow.
void writeAll( long long ( *put )( int, const char*, std::size_t ) noexcept, int fd, const char* bytes, std::size_t count ) noexcept
{
    while( put != nullptr && count > 0 )
    {
        const long long wrote = put( fd, bytes, count );
        if( wrote <= 0 )
        {
            return;
        }
        bytes += wrote;
        count -= static_cast<std::size_t>( wrote );
    }
}

// A bounded byte sink over a caller's buffer. Each escaped FIELD has its own output cap, so a long expression or
// signature is cut (and ends in "...") instead of pushing the closing quotes and braces off the end; the sink's own
// cap is a backstop the per-field caps keep it from reaching. A cut backs off to a UTF-8 lead byte, so the kept text
// is still valid UTF-8 and the JSON still parses.
class Sink
{
public:
    Sink( char* buffer, std::size_t capacity ) noexcept : buffer_( buffer ), capacity_( capacity ) { buffer_[ 0 ] = '\0'; }

    void raw( const char* text, std::size_t count ) noexcept
    {
        const std::size_t room = capacity_ - 1 - size_;
        const std::size_t kept = count < room ? count : room;
        std::memcpy( buffer_ + size_, text, kept );
        size_ += kept;
        buffer_[ size_ ] = '\0';
    }
    void raw( const char* text ) noexcept { raw( text, std::strlen( text ) ); }

    void number( long long value ) noexcept
    {
        char digits[ 24 ];
        raw( digits, rw::formatTo( digits, sizeof( digits ), "{}", value ) );
    }

    enum class Escape : unsigned char { Json, Xml, Plain };

    // `text` escaped for its context, at most `maxBytes` of output.
    void escaped( const char* text, std::size_t maxBytes, Escape how ) noexcept
    {
        const std::size_t start = size_;
        for( const char* at = orEmptyText( text ); *at != '\0'; ++at )
        {
            const EscapedByte piece = escapeByte( *at, how );
            if( size_ - start + piece.bytes > maxBytes )
            {
                cutAt( start, static_cast<unsigned char>( *at ) );
                return;
            }
            raw( piece.text, piece.bytes );
        }
    }

    const char* data() const noexcept { return buffer_; }
    std::size_t size() const noexcept { return size_; }

private:
    static const char* orEmptyText( const char* text ) noexcept { return text != nullptr ? text : ""; }

    struct EscapedByte
    {
        char        text[ 8 ];
        std::size_t bytes;
    };

    // One input byte as its context spells it. Bytes 0x80 and up pass through unchanged, so UTF-8 survives.
    static EscapedByte escapeByte( char c, Escape how ) noexcept
    {
        return how == Escape::Json ? jsonByte( c ) : markupByte( c, how == Escape::Xml );
    }

    static EscapedByte jsonByte( char c ) noexcept
    {
        if( c == '"' || c == '\\' )
        {
            return EscapedByte{ { '\\', c }, 2 };
        }
        EscapedByte out{ { c }, 1 };
        if( static_cast<unsigned char>( c ) < 0x20 )
        {
            out.bytes = rw::formatTo( out.text, sizeof( out.text ), "\\u{:04x}", static_cast<unsigned>( static_cast<unsigned char>( c ) ) );
        }
        return out;
    }

    // XML attribute text (isXml) or a plain line: a control byte becomes a space, because XML 1.0 cannot carry most
    // of them even as references and a line cannot carry a newline; in XML the four markup bytes become entities.
    static EscapedByte markupByte( char c, bool isXml ) noexcept
    {
        struct Entity
        {
            char        byte;
            const char* text;
        };
        static constexpr Entity kEntities[] = { { '&', "&amp;" }, { '<', "&lt;" }, { '>', "&gt;" }, { '"', "&quot;" } };
        EscapedByte out{ { static_cast<unsigned char>( c ) < 0x20 ? ' ' : c }, 1 };
        for( const Entity& entity : kEntities )
        {
            if( isXml && entity.byte == c )
            {
                out.bytes = std::strlen( entity.text );
                std::memcpy( out.text, entity.text, out.bytes + 1 );
            }
        }
        return out;
    }

    // The field ran out of room at a byte whose high bits are `next`. If that byte continues a UTF-8 sequence, the
    // partial sequence already copied goes too, so the kept text is valid UTF-8; then the cut says itself.
    void cutAt( std::size_t start, unsigned char next ) noexcept
    {
        const auto isContinuation = [ & ]( std::size_t at ) noexcept { return ( static_cast<unsigned char>( buffer_[ at ] ) & 0xC0 ) == 0x80; };
        if( ( next & 0xC0 ) == 0x80 )
        {
            while( size_ > start && isContinuation( size_ - 1 ) )
            {
                --size_;
            }
            if( size_ > start && ( static_cast<unsigned char>( buffer_[ size_ - 1 ] ) & 0xC0 ) == 0xC0 )
            {
                --size_;
            }
        }
        buffer_[ size_ ] = '\0';
        raw( "..." );
    }

    char*       buffer_;
    std::size_t capacity_;
    std::size_t size_ = 0;
};

// Per-field output caps. Sized so the largest document (the record) stays well inside its buffer: a backstop cut by
// Sink::raw would break the JSON, so the caps, not the buffer, decide what is kept.
inline constexpr std::size_t kFieldCap    = 700;   // expr, function, note
inline constexpr std::size_t kFileCap     = 256;
inline constexpr std::size_t kArgvCap     = 2048;  // the argv JSON array, preformatted at arm time
inline constexpr std::size_t kDocumentCap = 12288; // 3 x kFieldCap x 2 (message + data) + argv + the rest, with room

struct Slot
{
    Transport         transport = Transport::None;
    char              version[ 64 ];
    char              builtFrom[ 64 ];
    char              crashPath[ 1024 ];
    char              argvJson[ kArgvCap + 64 ];
    char              flags[ 256 ];   // the call's `--name` flags, values dropped: "--no-cache --for"
    char              requestId[ 256 ];
    char              tool[ 96 ];
    int               httpFd = -1;
    std::atomic<bool> inFlight{ false };
};
Slot g_slot;

std::atomic<std::uint64_t> g_reportingThread{ 0 };
char                       g_document[ kDocumentCap ];   // the one report a process writes (claimReport)

void copyCapped( char* destination, std::size_t capacity, const char* source, std::size_t count ) noexcept
{
    const std::size_t kept = count < capacity - 1 ? count : capacity - 1;
    std::memcpy( destination, source, kept );
    destination[ kept ] = '\0';
}
void copyCapped( char* destination, std::size_t capacity, const char* source ) noexcept
{
    copyCapped( destination, capacity, source != nullptr ? source : "", source != nullptr ? std::strlen( source ) : 0 );
}

constexpr const char* kKindName[] = { "Assume", "Expects", "Ensures", "DAssert", "Unreachable" };
constexpr const char* kTransportName[] = { "none", "cli", "mcp-stdio", "mcp-http" };

// The one sentence an agent can act on: who is at fault, what to do next, where to report. The MCP form adds that
// the server process is gone, which is what the client will see on its next call.
constexpr const char kHint[] = "This is a ripwire bug, not your input. Retry once with a different wording or verb; if it fails again, "
                               "fall back to grep/Read for this question. Report the kind, location and command at "
                               "https://github.com/redhat-et/ripwire/issues";
constexpr const char kMcpHint[] = " This MCP server process exits after this response: reconnect it before the next call (Claude Code: /mcp).";

struct Failure
{
    CheckKind   kind;
    const char* expr;
    const char* file;
    int         line;
    const char* function;
    const char* note;
};

bool hasText( const char* text ) noexcept
{
    return text != nullptr && text[ 0 ] != '\0';
}

// "<KIND> <expr> at <file>:<line> in <function> — <note>", escaped for `how`.
void writeSentence( Sink& out, const Failure& f, Sink::Escape how ) noexcept
{
    out.raw( kKindName[ static_cast<std::size_t>( f.kind ) ] );
    out.raw( " " );
    out.escaped( f.expr, kFieldCap, how );
    out.raw( " at " );
    out.escaped( f.file, kFileCap, how );
    out.raw( ":" );
    out.number( f.line );
    out.raw( " in " );
    out.escaped( f.function, kFieldCap, how );
    if( hasText( f.note ) )
    {
        out.raw( " \xE2\x80\x94 " );
        out.escaped( f.note, kFieldCap, how );
    }
}

// The fields every JSON form shares, without the braces.
void writeJsonFields( Sink& out, const Failure& f ) noexcept
{
    out.raw( "\"kind\":\"" );
    out.raw( kKindName[ static_cast<std::size_t>( f.kind ) ] );
    out.raw( "\",\"expr\":\"" );
    out.escaped( f.expr, kFieldCap, Sink::Escape::Json );
    out.raw( "\",\"file\":\"" );
    out.escaped( f.file, kFileCap, Sink::Escape::Json );
    out.raw( "\",\"line\":" );
    out.number( f.line );
    out.raw( ",\"function\":\"" );
    out.escaped( f.function, kFieldCap, Sink::Escape::Json );
    out.raw( "\",\"note\":\"" );
    out.escaped( f.note, kFieldCap, Sink::Escape::Json );
    out.raw( "\",\"version\":\"" );
    out.escaped( g_slot.version, 64, Sink::Escape::Json );
    out.raw( "\",\"built_from\":\"" );
    out.escaped( g_slot.builtFrom, 64, Sink::Escape::Json );
    out.raw( "\"" );
}

void writeMcpError( const Failure& f ) noexcept
{
    Sink out( g_document, sizeof( g_document ) );
    out.raw( "{\"jsonrpc\":\"2.0\",\"id\":" );
    out.raw( g_slot.requestId );
    out.raw( ",\"error\":{\"code\":-32603,\"message\":\"ripwire internal check failed (this is a ripwire bug): " );
    writeSentence( out, f, Sink::Escape::Json );
    out.raw( "\",\"data\":{" );
    writeJsonFields( out, f );
    out.raw( ",\"hint\":\"" );
    out.raw( kHint );
    out.raw( kMcpHint );
    out.raw( "\"}}}" );
    if( g_slot.transport == Transport::McpStdio )
    {
        out.raw( "\n" );   // newline-delimited JSON-RPC, the stdio loop's framing (mcp.h runMcp)
        std::fflush( stdout );
        writeAll( g_os.write, 1, out.data(), out.size() );
        return;
    }
    // --listen: one HTTP/1.1 response per connection (mcpserver.h respond), Content-Length framed, on the socket.
    char       header[ 160 ];
    const auto headerBytes = rw::formatTo( header, sizeof( header ),
                                           "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                                           out.size() );
    if( g_slot.httpFd >= 0 && headerBytes < sizeof( header ) )
    {
        writeAll( g_os.send, g_slot.httpFd, header, headerBytes );
        writeAll( g_os.send, g_slot.httpFd, out.data(), out.size() );
    }
}

void writeCliLine( const Failure& f ) noexcept
{
    Sink out( g_document, sizeof( g_document ) );
    // The leading newline ends a line the answer may have left open; the element then starts a line of its own.
    out.raw( "\n<ripwire_internal_error kind=\"" );
    out.raw( kKindName[ static_cast<std::size_t>( f.kind ) ] );
    out.raw( "\" expr=\"" );
    out.escaped( f.expr, kFieldCap, Sink::Escape::Xml );
    out.raw( "\" at=\"" );
    out.escaped( f.file, kFileCap, Sink::Escape::Xml );
    out.raw( ":" );
    out.number( f.line );
    out.raw( "\" fn=\"" );
    out.escaped( f.function, kFieldCap, Sink::Escape::Xml );
    out.raw( "\" note=\"" );
    out.escaped( f.note, kFieldCap, Sink::Escape::Xml );
    out.raw( "\" version=\"" );
    out.escaped( g_slot.version, 64, Sink::Escape::Xml );
    out.raw( "\" built_from=\"" );
    out.escaped( g_slot.builtFrom, 64, Sink::Escape::Xml );
    out.raw( "\" hint=\"" );
    out.raw( kHint );
    out.raw( "\"/>\n" );
    std::fflush( stdout );
    writeAll( g_os.write, 1, out.data(), out.size() );
}

// `<cacheDir>/last-crash`: line 1 the summary the next call prints, line 2 the whole record as one JSON object.
void writeRecord( const Failure& f ) noexcept
{
    if( g_slot.crashPath[ 0 ] == '\0' || g_os.createTruncate == nullptr || g_os.close == nullptr )
    {
        return;
    }
    Sink out( g_document, sizeof( g_document ) );
    writeSentence( out, f, Sink::Escape::Plain );
    out.raw( " (ripwire " );
    out.escaped( g_slot.version, 64, Sink::Escape::Plain );
    out.raw( " built_from=" );
    out.escaped( g_slot.builtFrom, 64, Sink::Escape::Plain );
    out.raw( g_slot.tool[ 0 ] != '\0' ? ", tool " : ", flags " );
    out.escaped( g_slot.tool[ 0 ] != '\0' ? g_slot.tool : ( g_slot.flags[ 0 ] != '\0' ? g_slot.flags : "(none: the map)" ), sizeof( g_slot.flags ), Sink::Escape::Plain );
    out.raw( ")\n{" );
    writeJsonFields( out, f );
    out.raw( ",\"transport\":\"" );
    out.raw( kTransportName[ static_cast<std::size_t>( g_slot.transport ) ] );
    out.raw( "\",\"argv\":" );
    out.raw( g_slot.argvJson[ 0 ] != '\0' ? g_slot.argvJson : "[]" );
    out.raw( ",\"flags\":\"" );
    out.escaped( g_slot.flags, sizeof( g_slot.flags ), Sink::Escape::Json );
    out.raw( "\",\"tool\":\"" );
    out.escaped( g_slot.tool, 96, Sink::Escape::Json );
    out.raw( "\",\"request_id\":" );
    out.raw( g_slot.inFlight.load( std::memory_order_acquire ) ? g_slot.requestId : "null" );
    out.raw( ",\"pid\":" );
    out.number( g_os.processId != nullptr ? g_os.processId() : 0 );
    out.raw( ",\"time\":" );
    out.number( static_cast<long long>( std::time( nullptr ) ) );
    out.raw( "}\n" );
    const int fd = g_os.createTruncate( g_slot.crashPath );
    if( fd >= 0 )
    {
        writeAll( g_os.write, fd, out.data(), out.size() );
        g_os.close( fd );
    }
}

// True when this call owns the process's one agent report. A check that fails INSIDE the report (same thread) gets
// false and falls through to the bare notice and trap. Another thread failing at the same moment waits, bounded, for
// the first to finish: the first one's trap ends the process, and a reporter stuck on a full pipe cannot hang this one
// for more than two seconds.
bool claimReport() noexcept
{
    const std::uint64_t self     = currentThreadId();
    std::uint64_t       expected = 0;
    if( g_reportingThread.compare_exchange_strong( expected, self ) )
    {
        return true;
    }
    if( expected != self )
    {
        for( int waited = 0; waited < 200; ++waited )
        {
            std::this_thread::sleep_for( std::chrono::milliseconds( 10 ) );
        }
    }
    return false;
}

bool isAgentVisible( CheckKind kind ) noexcept
{
    return kind != CheckKind::DAssert;   // DASSERT promises nothing (Diagnostics.h): unchanged, stderr notice + trap
}

// Before the stderr notice: the agent's copy, where the transport can carry one.
void reportToAgent( const Failure& f ) noexcept
{
    const Transport transport = g_slot.transport;
    if( transport == Transport::Cli )
    {
        writeCliLine( f );
    }
    else if( ( transport == Transport::McpStdio || transport == Transport::McpHttp ) && g_slot.inFlight.load( std::memory_order_acquire ) )
    {
        writeMcpError( f );
    }
}

// argv as a JSON array of strings, capped at kArgvCap with a "..." element when cut.
void armArgvJson( int argc, const char* const* argv ) noexcept
{
    Sink json( g_slot.argvJson, sizeof( g_slot.argvJson ) );
    json.raw( "[" );
    for( int i = 0; i < argc; ++i )
    {
        if( json.size() + 8 >= kArgvCap )
        {
            json.raw( ",\"...\"" );
            break;
        }
        json.raw( i == 0 ? "\"" : ",\"" );
        json.escaped( argv[ i ], kArgvCap - json.size() - 8, Sink::Escape::Json );
        json.raw( "\"" );
    }
    json.raw( "]" );
}

// The call's `--name` flags, values dropped. The verb is one of them, but which one is the CLI parser's knowledge, not
// this file's: the names are listed (so a task string or a path never lands here twice) and argv carries the rest.
void armFlags( int argc, const char* const* argv ) noexcept
{
    Sink flags( g_slot.flags, sizeof( g_slot.flags ) );
    for( int i = 1; i < argc; ++i )
    {
        const char* arg = argv[ i ];
        if( arg == nullptr || arg[ 0 ] != '-' || arg[ 1 ] != '-' )
        {
            continue;
        }
        const char*       equals = std::strchr( arg, '=' );
        const std::size_t bytes  = equals != nullptr ? static_cast<std::size_t>( equals - arg ) : std::strlen( arg );
        if( flags.size() + bytes + 2 < sizeof( g_slot.flags ) )
        {
            flags.raw( flags.size() > 0 ? " " : "" );
            flags.raw( arg, bytes );
        }
    }
}

void armArgv( int argc, const char* const* argv ) noexcept
{
    if( argv == nullptr )
    {
        argc = 0;
    }
    armArgvJson( argc, argv );
    armFlags( argc, argv );
}

} // namespace

void arm( const ArmInfo& info ) noexcept
{
    g_os             = info.os;
    g_slot.transport = info.transport;
    copyCapped( g_slot.version, sizeof( g_slot.version ), info.version );
    copyCapped( g_slot.builtFrom, sizeof( g_slot.builtFrom ), info.builtFrom );
    g_slot.crashPath[ 0 ] = '\0';
    if( hasText( info.cacheDir ) && std::strlen( info.cacheDir ) + sizeof( "/last-crash" ) < sizeof( g_slot.crashPath ) )
    {
        Sink path( g_slot.crashPath, sizeof( g_slot.crashPath ) );
        path.raw( info.cacheDir );
        path.raw( "/last-crash" );
    }
    armArgv( info.argc, info.argv );
}

void beginRequest( const char* idToken, std::size_t idBytes, int httpFd ) noexcept
{
    if( idToken != nullptr && idBytes > 0 && idBytes < sizeof( g_slot.requestId ) )
    {
        copyCapped( g_slot.requestId, sizeof( g_slot.requestId ), idToken, idBytes );
    }
    else
    {
        copyCapped( g_slot.requestId, sizeof( g_slot.requestId ), "null" );
    }
    g_slot.httpFd  = httpFd;
    g_slot.tool[ 0 ] = '\0';
    g_slot.inFlight.store( true, std::memory_order_release );
}

void noteTool( const char* name, std::size_t nameBytes ) noexcept
{
    copyCapped( g_slot.tool, sizeof( g_slot.tool ), name, nameBytes );
}

void endRequest() noexcept
{
    g_slot.inFlight.store( false, std::memory_order_release );
    g_slot.httpFd = -1;
}

TakenCrash takeLastCrash() noexcept
{
    TakenCrash taken;
    if( g_slot.crashPath[ 0 ] == '\0' || g_os.rename == nullptr || g_os.readPrefix == nullptr || g_os.remove == nullptr || g_os.processId == nullptr )
    {
        return taken;   // unarmed
    }
    char aside[ sizeof( g_slot.crashPath ) + 32 ];
    if( rw::formatTo( aside, sizeof( aside ), "{}.taken.{}", rw::cstr( g_slot.crashPath ), g_os.processId() ) >= sizeof( aside )
        || g_os.rename( g_slot.crashPath, aside ) != 0 )
    {
        return taken;   // no record (the common case), or another call took it first
    }
    // Line 1 is the summary; the read stops at its newline or at the buffer, whichever is first.
    const std::size_t bytes = g_os.readPrefix( aside, taken.summary, sizeof( taken.summary ) - 1 );
    taken.summary[ bytes ] = '\0';
    if( char* const eol = std::strchr( taken.summary, '\n' ) )
    {
        *eol = '\0';
    }
    taken.summaryBytes = std::strlen( taken.summary );
    while( taken.summaryBytes > 0 && taken.summary[ taken.summaryBytes - 1 ] == '\r' )
    {
        taken.summary[ --taken.summaryBytes ] = '\0';
    }
    taken.found = taken.summaryBytes > 0;
    g_os.remove( aside );
    return taken;
}

const char* lastCrashPath() noexcept
{
    return g_slot.crashPath;
}

// RIPWIRE_TEST_TRAP=assume|expects|ensures|unreachable — the gate's trigger (test/agenttrapcheck.sh). Each arm is a
// real check of its kind, so the report the gate reads is the one a real failure writes.
void fireTestTrap() noexcept
{
    const char* const armed = std::getenv( "RIPWIRE_TEST_TRAP" );
    if( armed == nullptr )
    {
        return;
    }
    const std::string_view which( armed );
    if( which == "assume" )
    {
        ASSUME( which != "assume", "RIPWIRE_TEST_TRAP=assume: the agent-visible failure path's test trigger" );
    }
    else if( which == "expects" )
    {
        EXPECTS( which != "expects", "RIPWIRE_TEST_TRAP=expects: the agent-visible failure path's test trigger" );
    }
    else if( which == "ensures" )
    {
        ENSURES( which != "ensures", "RIPWIRE_TEST_TRAP=ensures: the agent-visible failure path's test trigger" );
    }
    else if( which == "unreachable" )
    {
        UNREACHABLE( "RIPWIRE_TEST_TRAP=unreachable: the agent-visible failure path's test trigger" );
    }
}

} // namespace agenttrap
#endif

RW_COLD_NOINLINE
void ConsoleLog::handleAssert( CheckKind kind, const char* expr, const char* file, int line, const char* function,
                               const char* description ) noexcept
{
    const std::size_t row   = static_cast<std::size_t>( kind );
    const NotesRow     notes = notesRowOf( description );
#if !defined( NDEBUG )
    // AGENT-VISIBLE-TRAP: the agent's copy first (stdout / the request's socket), then this notice, then the record.
    const agenttrap::Failure failure{ kind, expr, file, line, function, description };
    const bool               ownsReport = agenttrap::isAgentVisible( kind ) && agenttrap::claimReport();
    if( ownsReport )
    {
        agenttrap::reportToAgent( failure );
    }
    const NotesRow next = agenttrap::isAgentVisible( kind ) ? NotesRow{ "  Next:     ", agenttrap::kHint, "\n" } : NotesRow{ "", "", "" };
#else
    const NotesRow next{ "", "", "" };
#endif
    writeNotice( "\n======================================\n"
                 "!!! {} !!!\n"
                 "======================================\n"
                 "  Expr:     {}\n"
                 "  Blame:    {}\n"
                 "  Location: {}:{}\n"
                 "  Function: {}\n"
                 "{}{}{}"
                 "{}{}{}"
                 "======================================\n",
                 kKindBanner[ row ], orEmpty( expr ), kKindBlame[ row ], orEmpty( file ), line, orEmpty( function ),
                 notes.label, notes.text, notes.eol, next.label, next.text, next.eol );
#if !defined( NDEBUG )
    if( ownsReport )
    {
        agenttrap::writeRecord( failure );
    }
#endif
    RW_TRAP();
}

[[noreturn]] RW_COLD_NOINLINE
void ConsoleLog::handlePanic( const char* file, int line, const char* function, const char* description ) noexcept
{
    writeNotice( "\n======================================\n"
                 "!!! CRITICAL SYSTEM PANIC !!!\n"
                 "======================================\n"
                 "  Location: {}:{}\n"
                 "  Function: {}\n"
                 "  Reason:   {}\n"
                 "======================================\n",
                 orEmpty( file ), line, orEmpty( function ), orEmpty( description ) );
    std::abort();
}

RW_COLD_NOINLINE
void ConsoleLog::handleThreadViolation( std::uint64_t expected, std::uint64_t got, const char* file, int line, const char* function,
                                        const char* description ) noexcept
{
    const NotesRow notes = notesRowOf( description );
    writeNotice( "\n======================================\n"
                 "!!! THREAD-OWNERSHIP VIOLATION !!!\n"
                 "======================================\n"
                 "  This site or object is single-thread owned but was reached from another thread.\n"
                 "  Owner thread: {}   Offending thread: {}\n"
                 "  Location: {}:{}\n"
                 "  Function: {}\n"
                 "{}{}{}"
                 "======================================\n",
                 expected, got, orEmpty( file ), line, orEmpty( function ), notes.label, notes.text, notes.eol );
    RW_TRAP();
}

RW_COLD_NOINLINE
void ConsoleLog::handleValidateFailed( const char* expr, const char* file, int line, const char* function, const char* description ) noexcept
{
    // One line, no trap: a false VALIDATE is input being refused, which is the program working.
    const bool  hasDescription = description != nullptr && description[ 0 ] != '\0';
    const char* separator      = hasDescription ? " — " : "";
    const char* text           = hasDescription ? description : "";
    writeNotice( "[validate] {} is false{}{}  ({}:{}, {} — logged once per site)\n",
                 orEmpty( expr ), separator, text, orEmpty( file ), line, orEmpty( function ) );
}

RW_COLD_NOINLINE
void ConsoleLog::handleDegraded( const char* file, int line, const char* function, const char* description ) noexcept
{
    // DISCLOSE's debug trace. One-line notice, no trap — the caller clamps/falls back and continues. The
    // "[math degraded]" prefix and every message are kept byte-identical: 11 gates grep for the prefix
    // (test/*.sh on 3bf884e2) and test/sidecarsymlinkcheck.sh pins message text. Retiring the prefix is its own change.
    writeNotice( "[math degraded] {}  ({}:{}, {} — logged once per site)\n", orEmpty( description ), orEmpty( file ), line, orEmpty( function ) );
}

// Unique, stable, non-zero per-thread id. thread_local counter avoids pulling <thread> into the widely-included
// Diagnostics.h; first thread to ask gets 1, next 2, etc. Non-zero so 0 stays a valid "unclaimed" sentinel for the
// per-site latch and ThreadOwner.
std::uint64_t currentThreadId() noexcept
{
    static std::atomic<std::uint64_t> counter{ 0 };
    thread_local const std::uint64_t  id = ++counter;
    return id;
}

} // namespace Diagnostics
