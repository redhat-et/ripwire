// diagnotice_harness.cpp — measures how the Diagnostics reporters (src/infra/diagnostics.cpp) put a notice on
// fd 2: in how many write(2) calls, with which bytes, and whether a competing writer can split it. Driven by
// test/diagnoticecheck.sh, which reads the rows this prints and owns every verdict.
//
// WHY WRITE COUNTS AND NOT ONLY A STRESS RUN. A notice torn by a competing writer is a race, and a race run
// alone gives a RATE, not a verdict. The race needs one precondition that is not a race at all: the notice
// must leave the process in more than one write. `writes` measures that precondition exactly, with no timing
// in it, by making fd 2 one end of an AF_UNIX SOCK_DGRAM socketpair. A datagram socket keeps write
// boundaries, so every write(2) the child's stdio (or iostream, through stdio) makes arrives as its own
// datagram, and the parent counts them. Nothing in the reporter is stubbed: the real stream stack runs.
//
// Modes (argv[1]):
//   writes [DUMPDIR]  every reporter, each in a forked child (assert and thread-violation trap, panic
//                     aborts). One row per case:
//                       case NAME writes=N bytes=N exact=0|1 ended=return|trap|abort|status:N
//                     The stdout-* cases also point fd 1 at the same socket (a `2>&1`) and leave text in stdout's
//                     buffer before the reporter runs: that text must arrive FIRST, in its own write, because the
//                     reporters flush stdout before the notice as std::cerr's tie to std::cout always did.
//                     and for the over-long notice:
//                       case degraded-long writes=N bytes=N lines=N marker=0|1 utf8=0|1 prefix=0|1 ended=...
//                     marker=1 only when "kept K of N bytes" is honest: K is the length of the text in front of
//                     it and N the full notice's length; prefix=1 when those K bytes are the notice's own first K.
//                     With DUMPDIR, each case's reassembled bytes are also written to DUMPDIR/NAME.bin, so two
//                     builds of this harness can be compared byte for byte.
//   stress PATH R C N fd 2 is a regular file opened O_APPEND. R threads each raise N degraded notices while
//                     C threads write one line per stdio call and C more write one line per raw write(2).
//                     The file is then split into lines, and every line must be a whole notice or a whole
//                     competitor line. Row: stress notices=n/want stdio=n/want raw=n/want torn=n
//   alloc N           N short and N over-long degraded notices after one warm-up pair, and nothing else. Built
//                     with src/alloccount.cpp, the process reports its heap allocations at exit on stderr; the
//                     gate runs `alloc 0` and `alloc N` and requires the SAME count, because that instrument's
//                     own rule is that only a delta between otherwise identical runs is attributable. Everything
//                     the harness itself does in this mode must therefore allocate the SAME in both runs.
//   info              prints emitter=<rw::kEmitterName>, the emit.h arm this harness was compiled with.
//
// Exit 0 when the mode ran to completion (the rows carry the verdicts); 3 when the measurement itself could not
// be set up (socketpair, fork, open), which the gate reports as a failure to measure, never as a pass.

#include "infra/Diagnostics.h"
#include "infra/emit.h"

#include <algorithm>
#include <atomic>
#include <charconv>
#include <csignal>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <format>
#include <limits>
#include <string>
#include <string_view>
#include <system_error>
#include <thread>
#include <vector>

#include <fcntl.h>
#include <poll.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

namespace
{

// ── the inputs every case shares ─────────────────────────────────────────────────────────────────────────
// The description carries an em dash (multi-byte UTF-8), a brace pair and a percent sign on purpose: it is an
// ARGUMENT, never a format, and a reporter that ever formatted it as one would print something else.
constexpr const char*   kFile            = "noticefix.cpp";
constexpr int           kLine            = 4242;
constexpr const char*   kFunction        = "int noticefix::probe(const char *, std::size_t) [T = std::basic_string_view<char>]";
constexpr const char*   kExpr            = "count <= capacity && \"a {} brace\"";
constexpr const char*   kNotes           = "a note with an em dash \xE2\x80\x94, a brace pair {} and a percent % sign";
constexpr std::uint64_t kOwnerThread     = 7;
constexpr std::uint64_t kOffendingThread = std::numeric_limits<std::uint64_t>::max();

// ── the text each reporter has always printed, spelled out here independently of diagnostics.cpp ─────────
// Assembled differently from the reporters on purpose (a banner frame around rows), so a shared mistake would
// have to be made twice in two shapes.
std::string banner( std::string_view title, std::string_view rows )
{
    constexpr std::string_view kRule = "======================================";
    return std::format( "\n{0}\n{1}\n{0}\n{2}{0}\n", kRule, title, rows );
}

std::string locationRows()
{
    return std::format( "  Location: {}:{}\n  Function: {}\n", kFile, kLine, kFunction );
}

std::string notesRow( const char* description )
{
    const bool hasNotes = description != nullptr && description[ 0 ] != '\0';
    return hasNotes ? std::format( "  Notes:    {}\n", description ) : std::string();
}

std::string expectedDegraded( const char* description )
{
    return std::format( "[math degraded] {}  ({}:{}, {} \xE2\x80\x94 logged once per site)\n", description, kFile, kLine, kFunction );
}

std::string expectedAssert( const char* description )
{
    // Assume is the kind every "assert"-named case below actually raises; the banner and blame text are the row
    // Diagnostics::CheckKind::Assume owns in diagnostics.cpp's kKindBanner/kKindBlame tables.
    return banner( "!!! ASSUME FAILED !!!",
                   std::format( "  Expr:     {}\n"
                                "  Blame:    an invariant this function relies on is false here\n", kExpr ) +
                       locationRows() + notesRow( description ) );
}

std::string expectedPanic()
{
    return banner( "!!! CRITICAL SYSTEM PANIC !!!", locationRows() + std::format( "  Reason:   {}\n", kNotes ) );
}

std::string expectedThread( const char* description )
{
    const std::string owner = std::format( "  This site or object is single-thread owned but was reached from another thread.\n"
                                           "  Owner thread: {}   Offending thread: {}\n", kOwnerThread, kOffendingThread );
    return banner( "!!! THREAD-OWNERSHIP VIOLATION !!!", owner + locationRows() + notesRow( description ) );
}

// ── printable form of captured bytes, for a mismatch report ─────────────────────────────────────────────
// Pure ASCII out, every byte past 0x7E as \xNN: the gate greps these rows, and one raw multi-byte character in a
// mismatch line makes grep under a C locale call the whole file binary and print none of the rows around it.
std::string escaped( std::string_view bytes, std::size_t maxBytes )
{
    std::string out;
    for( std::size_t i = 0; i < bytes.size() && i < maxBytes; ++i )
    {
        const unsigned char c = static_cast<unsigned char>( bytes[ i ] );
        if( c == '\n' )
        {
            out += "\\n";
        }
        else if( c < 0x20 || c >= 0x7F )
        {
            out += std::format( "\\x{:02x}", static_cast<unsigned>( c ) );
        }
        else
        {
            out += static_cast<char>( c );
        }
    }
    if( bytes.size() > maxBytes )
    {
        out += "...";
    }
    return out;
}

std::size_t utf8FollowCount( unsigned char lead )
{
    if( lead < 0x80 )
    {
        return 0;
    }
    if( ( lead & 0xE0 ) == 0xC0 )
    {
        return 1;
    }
    if( ( lead & 0xF0 ) == 0xE0 )
    {
        return 2;
    }
    return ( lead & 0xF8 ) == 0xF0 ? 3 : std::numeric_limits<std::size_t>::max();
}

bool isValidUtf8( std::string_view bytes )
{
    std::size_t i = 0;
    while( i < bytes.size() )
    {
        const std::size_t followCount = utf8FollowCount( static_cast<unsigned char>( bytes[ i ] ) );
        if( followCount > 3 || i + followCount >= bytes.size() )
        {
            return false;
        }
        for( std::size_t k = 1; k <= followCount; ++k )
        {
            if( ( static_cast<unsigned char>( bytes[ i + k ] ) & 0xC0 ) != 0x80 )
            {
                return false;
            }
        }
        i += followCount + 1;
    }
    return true;
}

// ── a reporter run in a child whose fd 2 keeps write boundaries ──────────────────────────────────────────
struct Captured
{
    std::string bytes;
    int         writeCount = 0;
    std::string ended;
    bool        isMeasured = false;
};

// Installed in the child as a signal handler: a trap or an abort becomes an exit status the parent can read,
// and no crash report is written.
[[noreturn]] void exitOnSignal( int signalNumber )
{
    _exit( 100 + signalNumber );
}

std::string endedFromStatus( int status )
{
    if( !WIFEXITED( status ) )
    {
        return std::format( "signal:{}", WIFSIGNALED( status ) ? WTERMSIG( status ) : -1 );
    }
    const int code = WEXITSTATUS( status );
    if( code == 0 )
    {
        return "return";
    }
    if( code == 100 + SIGTRAP || code == 100 + SIGILL )
    {
        return "trap";
    }
    return code == 100 + SIGABRT ? "abort" : std::format( "status:{}", code );
}

[[noreturn]] void runReporterAsChild( int writeEnd, void ( *report )() )
{
    alarm( 60 );   // a reporter that hangs dies of SIGALRM (the parent reads signal:14) instead of leaving the drain loop waiting
    dup2( writeEnd, 2 );
    close( writeEnd );
    const rlimit noCore = { 0, 0 };
    setrlimit( RLIMIT_CORE, &noCore );
    std::signal( SIGTRAP, exitOnSignal );
    std::signal( SIGILL, exitOnSignal );
    std::signal( SIGABRT, exitOnSignal );
    report();
    _exit( 0 );
}

// Drain WHILE the child runs: a Linux datagram queue holds a bounded number of datagrams, and a child that writes
// past it blocks until the parent reads, so waiting first and reading after would deadlock. Returns the status.
int drainUntilExit( int readEnd, pid_t child, Captured& out )
{
    fcntl( readEnd, F_SETFL, fcntl( readEnd, F_GETFL ) | O_NONBLOCK );
    std::vector<char> datagram( 1 << 17 );
    int               status      = 0;
    bool              isChildDone = false;
    for( ;; )
    {
        for( ssize_t got = 0; ( got = recv( readEnd, datagram.data(), datagram.size(), 0 ) ) >= 0; )
        {
            out.bytes.append( datagram.data(), static_cast<std::size_t>( got ) );
            ++out.writeCount;
        }
        if( isChildDone )
        {
            return status;
        }
        // One more drain after the exit is seen: the last datagrams may have landed after the read above.
        const pid_t reaped = waitpid( child, &status, WNOHANG );
        isChildDone        = reaped == child || reaped < 0;
        pollfd readable = { readEnd, POLLIN, 0 };
        poll( &readable, 1, isChildDone ? 0 : 20 );
    }
}

Captured captureInChild( void ( *report )() )
{
    Captured out;
    int      ends[ 2 ];
    if( socketpair( AF_UNIX, SOCK_DGRAM, 0, ends ) != 0 )
    {
        return out;
    }
    // The defaults are small on macOS (net.local.dgram.recvspace 4096, maxdgram 2048): a notice written in many
    // small writes could overflow the queue and be DROPPED, and a long one could be refused outright. Both would
    // corrupt the count this mode exists to take.
    const int socketBytes = 1 << 20;
    setsockopt( ends[ 0 ], SOL_SOCKET, SO_RCVBUF, &socketBytes, sizeof( socketBytes ) );
    setsockopt( ends[ 1 ], SOL_SOCKET, SO_SNDBUF, &socketBytes, sizeof( socketBytes ) );
    std::fflush( nullptr );
    const pid_t child = fork();
    if( child == 0 )
    {
        close( ends[ 0 ] );
        runReporterAsChild( ends[ 1 ], report );
    }
    close( ends[ 1 ] );
    if( child > 0 )
    {
        out.ended      = endedFromStatus( drainUntilExit( ends[ 0 ], child, out ) );
        out.isMeasured = true;
    }
    close( ends[ 0 ] );
    return out;
}

void dumpBytes( const char* dumpDir, const char* caseName, const std::string& bytes )
{
    if( dumpDir == nullptr )
    {
        return;
    }
    const std::string path = std::format( "{}/{}.bin", dumpDir, caseName );
    if( std::FILE* f = std::fopen( path.c_str(), "wb" ); f != nullptr )
    {
        std::fwrite( bytes.data(), 1, bytes.size(), f );
        std::fclose( f );
    }
}

// ── writes: every reporter, every branch of its text ─────────────────────────────────────────────────────
using CL = Diagnostics::ConsoleLog;

struct ExactCase
{
    const char* name;
    std::string want;
    void ( *report )();
};

std::string g_longNotes;   // 3,000 em dashes, built before any fork

// No newline on purpose: a line-buffered stdout (a terminal) would flush at one, and the case must hold the text in the
// buffer until the reporter runs, whatever stdout's buffering mode is.
constexpr std::string_view kStdoutText = "[stdout] written before the notice, still in stdout's buffer|";

// The `2>&1` shape: fd 1 joins fd 2 on the capture socket, and stdout holds kStdoutText when the reporter is called.
void bufferStdoutIntoCapture()
{
    dup2( 2, 1 );
    rw::emitRaw( stdout, kStdoutText.data() );
}

// " ... [notice truncated: kept K of N bytes]\n" at the very end of `bytes`, parsed; false when it is not there.
bool parseTruncationMarker( std::string_view bytes, std::size_t& markerAt, std::size_t& keptBytes, std::size_t& fullBytes )
{
    constexpr std::string_view kHead = " ... [notice truncated: kept ";
    markerAt                         = bytes.rfind( kHead );
    if( markerAt == std::string_view::npos )
    {
        return false;
    }
    const char* const end  = bytes.data() + bytes.size();
    const auto        kept = std::from_chars( bytes.data() + markerAt + kHead.size(), end, keptBytes );
    if( kept.ec != std::errc() || !std::string_view( kept.ptr, static_cast<std::size_t>( end - kept.ptr ) ).starts_with( " of " ) )
    {
        return false;
    }
    const auto full = std::from_chars( kept.ptr + 4, end, fullBytes );
    return full.ec == std::errc() && std::string_view( full.ptr, static_cast<std::size_t>( end - full.ptr ) ) == " bytes]\n";
}

bool reportLongCase( const char* dumpDir )
{
    // Its bytes cannot be pinned without pinning the reporter's capacity, so the row carries properties instead:
    // one line, an honest truncation marker, valid UTF-8 (the cut is likely to land inside a 3-byte sequence), and
    // the notice's own first K bytes.
    const Captured got = captureInChild( [] { CL::handleDegraded( kFile, kLine, kFunction, g_longNotes.c_str() ); } );
    if( !got.isMeasured )
    {
        rw::emitRaw( stdout, "case degraded-long unmeasured (socketpair or fork failed)\n" );
        return false;
    }
    dumpBytes( dumpDir, "degraded-long", got.bytes );
    const std::string want      = expectedDegraded( g_longNotes.c_str() );
    const bool        endsLine  = !got.bytes.empty() && got.bytes.back() == '\n';
    const std::size_t lineCount = endsLine ? static_cast<std::size_t>( std::count( got.bytes.begin(), got.bytes.end(), '\n' ) ) : 0;
    std::size_t       markerAt = 0, keptBytes = 0, fullBytes = 0;
    const bool        isMarkerHonest = parseTruncationMarker( got.bytes, markerAt, keptBytes, fullBytes ) && keptBytes == markerAt
                                    && fullBytes == want.size();
    const bool        isOwnPrefix = isMarkerHonest && keptBytes > 0 && want.compare( 0, keptBytes, got.bytes, 0, keptBytes ) == 0;
    rw::emitTo( stdout, "case degraded-long writes={} bytes={} lines={} marker={} utf8={} prefix={} ended={}\n", got.writeCount,
                got.bytes.size(), lineCount, isMarkerHonest ? 1 : 0, isValidUtf8( got.bytes ) ? 1 : 0, isOwnPrefix ? 1 : 0, got.ended );
    if( !isMarkerHonest )
    {
        rw::emitTo( stdout, "  tail: {}\n  want full={}\n", escaped( std::string_view( got.bytes ).substr( got.bytes.size() > 80 ? got.bytes.size() - 80 : 0 ), 80 ),
                    want.size() );
    }
    return true;
}

int runWrites( const char* dumpDir )
{
    for( int i = 0; i < 3000; ++i )
    {
        g_longNotes += "\xE2\x80\x94";
    }
    const ExactCase cases[] = {
        { "degraded", expectedDegraded( kNotes ), [] { CL::handleDegraded( kFile, kLine, kFunction, kNotes ); } },
        { "assert", expectedAssert( kNotes ), [] { CL::handleAssert( Diagnostics::CheckKind::Assume, kExpr, kFile, kLine, kFunction, kNotes ); } },
        { "assert-nonotes", expectedAssert( "" ), [] { CL::handleAssert( Diagnostics::CheckKind::Assume, kExpr, kFile, kLine, kFunction, "" ); } },
        { "assert-nullnotes", expectedAssert( nullptr ), [] { CL::handleAssert( Diagnostics::CheckKind::Assume, kExpr, kFile, kLine, kFunction, nullptr ); } },
        { "panic", expectedPanic(), [] { CL::handlePanic( kFile, kLine, kFunction, kNotes ); } },
        { "thread", expectedThread( kNotes ), [] { CL::handleThreadViolation( kOwnerThread, kOffendingThread, kFile, kLine, kFunction, kNotes ); } },
        { "thread-nonotes", expectedThread( "" ), [] { CL::handleThreadViolation( kOwnerThread, kOffendingThread, kFile, kLine, kFunction, "" ); } },
        { "stdout-degraded", std::string( kStdoutText ) + expectedDegraded( kNotes ),
          [] { bufferStdoutIntoCapture(); CL::handleDegraded( kFile, kLine, kFunction, kNotes ); } },
        { "stdout-assert", std::string( kStdoutText ) + expectedAssert( kNotes ),
          [] { bufferStdoutIntoCapture(); CL::handleAssert( Diagnostics::CheckKind::Assume, kExpr, kFile, kLine, kFunction, kNotes ); } },
        { "stdout-panic", std::string( kStdoutText ) + expectedPanic(), [] { bufferStdoutIntoCapture(); CL::handlePanic( kFile, kLine, kFunction, kNotes ); } },
    };
    bool isMeasured = true;
    for( const ExactCase& c : cases )
    {
        const Captured got = captureInChild( c.report );
        if( !got.isMeasured )
        {
            rw::emitTo( stdout, "case {} unmeasured (socketpair or fork failed)\n", c.name );
            isMeasured = false;
            continue;
        }
        dumpBytes( dumpDir, c.name, got.bytes );
        const bool isExact = got.bytes == c.want;
        rw::emitTo( stdout, "case {} writes={} bytes={} exact={} ended={}\n", c.name, got.writeCount, got.bytes.size(), isExact ? 1 : 0, got.ended );
        if( !isExact )
        {
            rw::emitTo( stdout, "  got:  {}\n  want: {}\n", escaped( got.bytes, 600 ), escaped( c.want, 600 ) );
        }
    }
    isMeasured = reportLongCase( dumpDir ) && isMeasured;
    return isMeasured ? 0 : 3;
}

// ── stress: real threads, real competitors, one shared regular file ──────────────────────────────────────
constexpr std::string_view kStdioLine = "[competitor] one line, one stdio call\n";
constexpr std::string_view kRawLine   = "[competitor] one line, one raw write(2)\n";

void raceWriters( int reporterCount, int competitorCount, int iterationCount )
{
    std::atomic<bool>        isGo{ false };
    std::vector<std::thread> pool;
    const auto               spawn = [ & ]( void ( *writeOne )() ) {
        pool.emplace_back( [ &isGo, writeOne, iterationCount ] {
            while( !isGo.load( std::memory_order_relaxed ) ) { std::this_thread::yield(); }
            for( int i = 0; i < iterationCount; ++i ) { writeOne(); }
        } );
    };
    for( int t = 0; t < reporterCount; ++t )
    {
        spawn( [] { CL::handleDegraded( kFile, kLine, kFunction, kNotes ); } );
    }
    for( int t = 0; t < competitorCount; ++t )
    {
        spawn( [] { rw::emitRaw( stderr, kStdioLine.data() ); } );
        spawn( [] { [[maybe_unused]] const ssize_t written = write( 2, kRawLine.data(), kRawLine.size() ); } );
    }
    isGo.store( true, std::memory_order_relaxed );
    for( std::thread& worker : pool )
    {
        worker.join();
    }
    std::fflush( stderr );
}

struct StressTally
{
    long                     noticeCount = 0;
    long                     stdioCount  = 0;
    long                     rawCount    = 0;
    long                     tornCount   = 0;
    std::vector<std::string> tornSamples;
};

// Every line must be one of the three whole lines; anything else, an unterminated tail included, is torn.
StressTally classifyLines( std::string_view text )
{
    const std::string      wantNotice = expectedDegraded( kNotes );
    const std::string_view noticeLine = std::string_view( wantNotice ).substr( 0, wantNotice.size() - 1 );
    StressTally            tally;
    for( std::size_t lineStart = 0; lineStart < text.size(); )
    {
        const std::size_t      newline = text.find( '\n', lineStart );
        const std::size_t      lineEnd = newline == std::string_view::npos ? text.size() : newline;
        const std::string_view line    = text.substr( lineStart, lineEnd - lineStart );
        const bool             isWhole = newline != std::string_view::npos;
        if( isWhole && line == noticeLine )
        {
            ++tally.noticeCount;
        }
        else if( isWhole && line == kStdioLine.substr( 0, kStdioLine.size() - 1 ) )
        {
            ++tally.stdioCount;
        }
        else if( isWhole && line == kRawLine.substr( 0, kRawLine.size() - 1 ) )
        {
            ++tally.rawCount;
        }
        else if( ++tally.tornCount <= 3 )
        {
            tally.tornSamples.push_back( escaped( line, 240 ) );
        }
        lineStart = lineEnd + 1;
    }
    return tally;
}

int runStress( const char* path, int reporterCount, int competitorCount, int iterationCount )
{
    const int fd = open( path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0644 );
    if( fd < 0 || dup2( fd, 2 ) < 0 )
    {
        rw::emitTo( stdout, "stress unmeasured (cannot open {})\n", path );
        return 3;
    }
    close( fd );
    raceWriters( reporterCount, competitorCount, iterationCount );

    std::string text;
    if( std::FILE* f = std::fopen( path, "rb" ); f != nullptr )
    {
        char chunk[ 65536 ];
        for( std::size_t got = 0; ( got = std::fread( chunk, 1, sizeof( chunk ), f ) ) > 0; )
        {
            text.append( chunk, got );
        }
        std::fclose( f );
    }
    const StressTally tally    = classifyLines( text );
    const long        wantEach = iterationCount;
    rw::emitTo( stdout, "stress notices={}/{} stdio={}/{} raw={}/{} torn={}\n", tally.noticeCount, wantEach * reporterCount, tally.stdioCount,
                wantEach * competitorCount, tally.rawCount, wantEach * competitorCount, tally.tornCount );
    for( const std::string& sample : tally.tornSamples )
    {
        rw::emitTo( stdout, "  torn: {}\n", sample );
    }
    return 0;
}

// ── alloc: the same process shape with and without the reporter calls ───────────────────────────────────
int runAlloc( int pairCount )
{
    const std::string longNotes( 9000, 'x' );
    CL::handleDegraded( kFile, kLine, kFunction, kNotes );             // warm-up pair, in every run: a one-time lazy
    CL::handleDegraded( kFile, kLine, kFunction, longNotes.c_str() );  // setup in the C library is charged to both
    for( int i = 0; i < pairCount; ++i )
    {
        CL::handleDegraded( kFile, kLine, kFunction, kNotes );
        CL::handleDegraded( kFile, kLine, kFunction, longNotes.c_str() );
    }
    // Into a stack buffer, never through rw::emitTo: on the std::format+fputs arm that renders a std::string, and
    // "alloc calls=110\n" is 16 bytes, one past libstdc++'s 15-byte small-string buffer, while "alloc calls=0\n" fits
    // it. That one 31-byte allocation turned this arm red on every g++ leg while libc++'s 22-byte buffer hid it on
    // macOS (review of #245). The report line must cost the same in both runs, so it costs nothing in either.
    char line[ 32 ];
    rw::formatTo( line, sizeof( line ), "alloc calls={}\n", 2 * pairCount );
    rw::emitRaw( stdout, line );
    return 0;
}

} // namespace

int main( int argc, char** argv )
{
    alarm( 300 );   // backstop: a harness that outlives its gate dies of SIGALRM instead of spinning (see scripts/gatebound.sh)
    const std::string_view mode = argc > 1 ? argv[ 1 ] : "";
    if( mode == "writes" )
    {
        return runWrites( argc > 2 ? argv[ 2 ] : nullptr );
    }
    if( mode == "stress" && argc > 5 )
    {
        return runStress( argv[ 2 ], std::atoi( argv[ 3 ] ), std::atoi( argv[ 4 ] ), std::atoi( argv[ 5 ] ) );
    }
    if( mode == "alloc" && argc > 2 )
    {
        return runAlloc( std::atoi( argv[ 2 ] ) );
    }
    if( mode == "info" )
    {
        rw::emitTo( stdout, "emitter={}\n", rw::kEmitterName );
        return 0;
    }
    rw::emitRaw( stderr, "usage: diagnotice_harness writes [DUMPDIR] | stress PATH R C N | alloc N | info\n" );
    return 64;
}
