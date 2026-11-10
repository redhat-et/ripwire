#pragma once

// helpdeadline.h — `--help-task --deadline-ms=N` (issue #594, reported by @WingedGuardian).
//
// THE PROBLEM. A prompt hook runs `ripwire DIR --help-task=…` under the harness's hard timeout (Claude Code: 8 s). A
// cold index of a mid-sized repository takes longer; the harness kills the run, and a killed run saves no cache, so
// the next prompt in that directory is cold again — every prompt times out, forever, until something indexes the
// directory without a deadline. Fresh git worktrees hit it first: each one is a new cold directory.
//
// THE SHAPE. With --deadline-ms=N the process forks ONCE, before any thread exists, and the CHILD runs the verb
// exactly as it runs without the flag, its stdout and stderr on pipes to the parent. The parent only relays:
//   - the child finishes inside N  -> the parent prints the child's stdout byte for byte and exits with its code,
//                                     so a warm or small repository sees the answer it always saw;
//   - N passes first               -> the parent prints the ordinary abstention and exits 0; the child, in its own
//                                     session, keeps going, finishes the index and writes the cache, and the next
//                                     call is warm.
// Windows has no fork (os::fork_session fails with ENOSYS): the verb runs synchronously, as without the flag.
//
// ONE INDEX AT A TIME. The child holds a flock on a per-root lock file (the cache dir's locks/, the same place and
// pattern as the edit and sidecar locks) for its whole run, taken by the parent before the fork and inherited, so
// the lock and the work end together, crash or not. A second call that finds the lock held either abstains at once
// (the holder is a deferred child, still indexing: a second prompt stays silent instead of waiting out its own
// deadline) or waits for the lock up to its deadline (the holder is another in-time run) and abstains if it is not
// free in time. No call starts a second cold index, and none exits 2.
//
// THE RECORD. No user notification (a hook cannot push into a session, and an OS toast is too loud). Instead:
//   - a per-root STATUS file the child writes: state=running at its start, state=finished with rc/ms/files at its
//     end. running + a FREE lock means the child died without finishing — the next call records it (warm-crashed)
//     and starts over; a running record older than kStaleRunningSec is ignored as stale;
//   - a DEFERRED marker the parent writes at the overrun, naming the child's pid (only the parent knows the moment);
//   - route-meter rows in the hooks' log ($RIPWIRE_HOME, else ~/.ripwire, routing.jsonl; RIPWIRE_ROUTE_METER=0 opts
//     out): `deferred` (cause=overrun|busy|lock-wait) when a call abstains on time, `warm-done` with ms/rc/files when
//     a deferred child finishes, `warm-crashed` when a dead child is found. agent="ripwire" router="warm", so the A/B
//     readout (bench/routing_ab_report.py reads agent="claude" rows) never pools them, and like the hooks' rows they
//     carry a hash of the root, never its path, and never the task text.
//
// TEST KNOB (test-only, documented here and in test/helptaskdeadlinecheck.sh): RIPWIRE_TEST_HELPTASK_DELAY_MS=N
// makes the child sleep N ms before it runs the verb, so a gate can build a "slow index" on a tiny fixture. It is
// read only in the deadline child, never on the plain path.

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>

#include "infra/Diagnostics.h"
#include "infra/emit.h"
#include "infra/os.h"
#include "gitmine.h"   // rw::civilFromDays — the UTC calendar date of the meter row's `at`
#include "quality.h"   // cacheDirLadder / cacheRootKeyHex / resolveCacheBlobPath — the per-user cache dir and the root key

namespace rw::helpdeadline
{

inline constexpr std::int64_t kStaleRunningSec = 2 * 3600;   // a `running` record older than this is not trusted
inline constexpr int          kLockPollMs      = 10;
inline constexpr int          kStartedWaitMs   = 1000;       // the longest the parent waits, past N, for the child's setsid

using Clock = std::chrono::steady_clock;

// The three per-root files, beside the edit/sidecar locks (cacheDirLadder()/locks/, never swept as a blob).
struct WarmPaths
{
    std::string lock;
    std::string status;
    std::string marker;
    std::string rootKey;   // cacheRootKeyHex: the realpath's hash, the same key the root's cache blobs carry
};

inline WarmPaths warmPaths( const std::string& root )
{
    const std::string lockDir = quality::cacheDirLadder() + "/locks";
    os::mkdir( lockDir.c_str(), 0700 );
    os::chmod( lockDir.c_str(), 0700 );
    WarmPaths p;
    p.rootKey             = quality::cacheRootKeyHex( root );
    const std::string stem = "ripwire-warm-" + p.rootKey;
    p.lock                = quality::resolveCacheBlobPath( lockDir, stem + ".lock" );
    p.status              = quality::resolveCacheBlobPath( lockDir, stem + ".status" );
    p.marker              = quality::resolveCacheBlobPath( lockDir, stem + ".deferred" );
    return p;
}

inline std::int64_t unixNow()
{
    return std::chrono::duration_cast<std::chrono::seconds>( std::chrono::system_clock::now().time_since_epoch() ).count();
}

inline std::string utcStamp( std::int64_t epoch )
{
    ASSUME( epoch >= 0, "the wall clock reads after 1970" );
    const std::int64_t days = epoch / 86400;
    const std::int64_t sec  = epoch % 86400;
    std::int64_t       y    = 0;
    unsigned           m = 0, d = 0;
    civilFromDays( days, y, m, d );
    return std::format( "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", y, m, d, sec / 3600, ( sec / 60 ) % 60, sec % 60 );
}

// ── the status record ────────────────────────────────────────────────────────────────────────────────────────────
struct WarmStatus
{
    std::string  state;          // running | finished | crashed
    long long    pid     = 0;
    std::int64_t started = 0;    // unix seconds
    int          rc      = -1;
    long long    ms      = -1;
    long long    files   = -1;
};

inline std::string readSmallFile( const std::string& path )
{
    std::string text;
    std::FILE*  f = std::fopen( path.c_str(), "rb" );
    if( f == nullptr )
    {
        return text;
    }
    char        buf[ 512 ];
    std::size_t got = std::fread( buf, 1, sizeof( buf ), f );
    std::fclose( f );
    text.assign( buf, got );
    return text;
}

// One `key=value` per line; an unknown key is skipped, a malformed number leaves the field at its default. The file
// lives in the per-user cache dir, but it is still bytes from disk, so every field is VALIDATEd rather than assumed.
inline std::optional<WarmStatus> readStatus( const std::string& path )
{
    const std::string text = readSmallFile( path );
    if( text.empty() )
    {
        return std::nullopt;
    }
    WarmStatus  st;
    std::size_t at = 0;
    while( at < text.size() )
    {
        std::size_t eol = text.find( '\n', at );
        if( eol == std::string::npos )
        {
            eol = text.size();
        }
        const std::string_view line( text.data() + at, eol - at );
        at                    = eol + 1;
        const std::size_t eq  = line.find( '=' );
        if( !VALIDATE( eq != std::string_view::npos && eq > 0, "a warm status line is key=value" ) )
        {
            continue;
        }
        const std::string_view key = line.substr( 0, eq );
        const std::string      val( line.substr( eq + 1 ) );
        const long long        num = std::strtoll( val.c_str(), nullptr, 10 );
        if( key == "state" ) { st.state = val; }
        else if( key == "pid" ) { st.pid = num; }
        else if( key == "started" ) { st.started = num; }
        else if( key == "rc" ) { st.rc = int( num ); }
        else if( key == "ms" ) { st.ms = num; }
        else if( key == "files" ) { st.files = num; }
    }
    if( !VALIDATE( !st.state.empty(), "a warm status record names its state" ) )
    {
        return std::nullopt;
    }
    return st;
}

// tmp + rename, so a reader never sees half a record. Best effort: a status that cannot be written costs the next
// call its shortcut (it waits on the lock instead), never an answer.
inline void writeSmallFile( const std::string& path, const std::string& text )
{
    const std::string tmp = std::format( "{}.{}.tmp", path, (long long)os::getpid() );
    std::FILE*        f   = std::fopen( tmp.c_str(), "wb" );
    if( f == nullptr )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "the status file is the next call's shortcut, never this call's answer",
                  "helpdeadline: could not write the warm status file" );
        return;
    }
    const bool wrote = std::fwrite( text.data(), 1, text.size(), f ) == text.size();
    if( std::fclose( f ) != 0 || !wrote || os::rename( tmp.c_str(), path.c_str() ) != 0 )
    {
        os::unlink( tmp.c_str() );
    }
}

inline void writeStatus( const std::string& path, const WarmStatus& st )
{
    writeSmallFile( path, std::format( "state={}\npid={}\nstarted={}\nrc={}\nms={}\nfiles={}\n", st.state, st.pid, st.started, st.rc, st.ms,
                                       st.files ) );
}

// ── the route meter ──────────────────────────────────────────────────────────────────────────────────────────────
struct MeterRow
{
    std::string_view status;           // deferred | warm-done | warm-crashed
    std::string_view cause;            // overrun | busy | lock-wait | finished | child-gone
    int              deadlineMs = 0;
    long long        ms         = -1;
    int              rc         = -1;
    long long        files      = -1;
};

inline void appendMeterRow( const std::string& rootKey, const MeterRow& row )
{
    const char* const off = std::getenv( "RIPWIRE_ROUTE_METER" );
    if( off != nullptr && std::string_view( off ) == "0" )
    {
        return;
    }
    const char* const home    = std::getenv( "RIPWIRE_HOME" );
    const char* const userDir = std::getenv( "HOME" );
    std::string       dir;
    if( home != nullptr && *home != '\0' )
    {
        dir = home;
    }
    else if( userDir != nullptr && *userDir != '\0' )
    {
        dir = std::string( userDir ) + "/.ripwire";
    }
    else
    {
        return;   // the hooks' own rule: no meter home, no row
    }
    std::error_code mkEc;
    std::filesystem::create_directories( std::filesystem::path( dir ), mkEc );
    const std::string line = std::format(
        "{{\"v\":2,\"at\":\"{}\",\"agent\":\"ripwire\",\"router\":\"warm\",\"event\":\"HelpTaskDeadline\",\"status\":\"{}\","
        "\"cause\":\"{}\",\"root_hash\":\"{}\",\"deadline_ms\":{},\"ms\":{},\"rc\":{},\"files\":{}}}\n",
        utcStamp( unixNow() ), row.status, row.cause, rootKey, row.deadlineMs, row.ms, row.rc, row.files );
    const std::string log = dir + "/routing.jsonl";
    const int         fd  = os::open( log.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644 );
    if( fd < 0 )
    {
        return;
    }
    // One write of one short line on an O_APPEND descriptor: rows from concurrent writers never interleave.
    (void)os::write( fd, line.data(), line.size() );
    os::close( fd );
}

// ── the child's side ─────────────────────────────────────────────────────────────────────────────────────────────
struct ChildSession
{
    bool              active = false;
    int               downFd = -1;   // the parent writes 'D' here at the overrun; EOF means the parent is gone
    int               deadlineMs = 0;
    std::string       statusPath;
    std::string       rootKey;
    Clock::time_point t0;
    std::int64_t      startedUnix = 0;
    long long         files       = -1;
};

inline ChildSession& childSession()
{
    static ChildSession session;
    return session;
}

// runHelpTask records how many files the index it answered from holds, for the warm-done row.
inline void noteIndexedFiles( std::size_t count ) noexcept
{
    childSession().files = static_cast<long long>( count );
}

// Was this child's answer abandoned? The parent writes 'D' at the overrun and then exits; a parent killed by the
// harness writes nothing, and the pipe reads as EOF. Either is "deferred". Nothing readable yet = in time.
inline bool parentDeferred( int downFd )
{
    os::pollfd ready = { downFd, POLLIN, 0 };
    if( os::poll( &ready, 1, 0 ) <= 0 || ready.revents == 0 )
    {
        return false;
    }
    char byte = 0;
    return os::read( downFd, &byte, 1 ) >= 0;   // 'D' (1 byte) or EOF (0): both mean nobody is waiting for this answer
}

// Called once, with the verb's final exit code, at the end of main. A no-op in every process but a deadline child.
inline void finishChild( int rc )
{
    ChildSession& s = childSession();
    if( !s.active )
    {
        return;
    }
    s.active          = false;
    const long long ms = std::chrono::duration_cast<std::chrono::milliseconds>( Clock::now() - s.t0 ).count();
    writeStatus( s.statusPath, WarmStatus{ "finished", (long long)os::getpid(), s.startedUnix, rc, ms, s.files } );
    if( parentDeferred( s.downFd ) )
    {
        appendMeterRow( s.rootKey, MeterRow{ "warm-done", "finished", s.deadlineMs, ms, rc, s.files } );
    }
    os::close( s.downFd );
}

// ── the parent's side ────────────────────────────────────────────────────────────────────────────────────────────
inline long long remainingMs( Clock::time_point deadline )
{
    return std::chrono::duration_cast<std::chrono::milliseconds>( deadline - Clock::now() ).count();
}

inline void sleepMs( int ms )
{
    const ::timespec ts{ ms / 1000, long( ms % 1000 ) * 1000 * 1000 };
    os::nanosleep( &ts, nullptr );
}

// A deferred child is indexing right now: the lock is held (the caller's precondition), the status says running and
// is fresh, and the parent's marker names the same pid.
inline bool deferredChildRunning( const WarmPaths& paths )
{
    const std::optional<WarmStatus> st = readStatus( paths.status );
    if( !st || st->state != "running" || unixNow() - st->started >= kStaleRunningSec )
    {
        return false;
    }
    const std::string marker = readSmallFile( paths.marker );
    return !marker.empty() && std::strtoll( marker.c_str(), nullptr, 10 ) == st->pid;
}

enum class LockOutcome : std::uint8_t { Held, Busy, TimedOut };

// Take the per-root lock, or say why not by the deadline. Busy = a deferred child holds it (abstain now).
inline LockOutcome acquireWarmLock( int lockFd, const WarmPaths& paths, Clock::time_point deadline )
{
    for( ;; )
    {
        if( os::flock( lockFd, LOCK_EX | LOCK_NB ) == 0 )
        {
            return LockOutcome::Held;
        }
        if( deferredChildRunning( paths ) )
        {
            return LockOutcome::Busy;
        }
        if( remainingMs( deadline ) <= 0 )
        {
            return LockOutcome::TimedOut;
        }
        sleepMs( kLockPollMs );
    }
}

// The lock was free, yet the record says running: that child died without finishing. Make it visible once.
inline void recordCrashedChild( const WarmPaths& paths, int deadlineMs )
{
    std::optional<WarmStatus> st = readStatus( paths.status );
    if( !st || st->state != "running" )
    {
        return;
    }
    appendMeterRow( paths.rootKey, MeterRow{ "warm-crashed", "child-gone", deadlineMs, -1, -1, -1 } );
    st->state = "crashed";
    writeStatus( paths.status, *st );
}

struct ChildPipes
{
    int out[ 2 ]  = { -1, -1 };   // child stdout -> parent
    int err[ 2 ]  = { -1, -1 };   // child stderr -> parent
    int up[ 2 ]   = { -1, -1 };   // child 'S' (started: in its own session, status written) -> parent
    int down[ 2 ] = { -1, -1 };   // parent 'D' (deferred) -> child

    bool open()
    {
        return os::pipe( out ) == 0 && os::pipe( err ) == 0 && os::pipe( up ) == 0 && os::pipe( down ) == 0;
    }
    static void closeFd( int& fd )
    {
        if( fd >= 0 )
        {
            os::close( fd );
            fd = -1;
        }
    }
    void closeAll()
    {
        for( int* pair : { out, err, up, down } )
        {
            closeFd( pair[ 0 ] );
            closeFd( pair[ 1 ] );
        }
    }
};

// In the child, right after the fork: stdout/stderr onto the pipes, the status record, then 'S' to the parent.
inline void becomeChild( ChildPipes& pipes, const WarmPaths& paths, int deadlineMs, Clock::time_point t0 )
{
    os::dup2( pipes.out[ 1 ], STDOUT_FILENO );
    os::dup2( pipes.err[ 1 ], STDERR_FILENO );
    ChildPipes::closeFd( pipes.out[ 0 ] );  ChildPipes::closeFd( pipes.out[ 1 ] );
    ChildPipes::closeFd( pipes.err[ 0 ] );  ChildPipes::closeFd( pipes.err[ 1 ] );
    ChildPipes::closeFd( pipes.up[ 0 ] );
    ChildPipes::closeFd( pipes.down[ 1 ] );

    ChildSession& s = childSession();
    s.active        = true;
    s.downFd        = pipes.down[ 0 ];
    s.deadlineMs    = deadlineMs;
    s.statusPath    = paths.status;
    s.rootKey       = paths.rootKey;
    s.t0            = t0;
    s.startedUnix   = unixNow();
    writeStatus( s.statusPath, WarmStatus{ "running", (long long)os::getpid(), s.startedUnix, -1, -1, -1 } );
    (void)os::write( pipes.up[ 1 ], "S", 1 );
    ChildPipes::closeFd( pipes.up[ 1 ] );

    // test-only: a slow index on a tiny fixture (see the header comment)
    if( const char* const delay = std::getenv( "RIPWIRE_TEST_HELPTASK_DELAY_MS" ); delay != nullptr && *delay != '\0' )
    {
        const long long ms = std::strtoll( delay, nullptr, 10 );
        if( VALIDATE( ms > 0 && ms <= 600000, "RIPWIRE_TEST_HELPTASK_DELAY_MS is a test knob in 1..600000 ms" ) )
        {
            sleepMs( int( ms ) );
        }
    }
}

// Read what one relay descriptor has; false once it reads EOF (or fails), which closes it.
inline bool relayOnce( int& fd, std::string* keep, std::FILE* forward )
{
    char          buf[ 65536 ];
    const auto    got = os::read( fd, buf, sizeof( buf ) );
    if( got <= 0 )
    {
        if( got < 0 && errno == EINTR )
        {
            return true;
        }
        ChildPipes::closeFd( fd );
        return false;
    }
    if( keep != nullptr )
    {
        keep->append( buf, std::size_t( got ) );
    }
    else
    {
        std::fwrite( buf, 1, std::size_t( got ), forward );
        std::fflush( forward );
    }
    return true;
}

// Relay until the child closes stdout and stderr, or the deadline passes. stderr is forwarded as it arrives; stdout is
// held, so an abandoned answer never reaches the caller half-printed. True = the child finished in time.
inline bool relayUntil( ChildPipes& pipes, std::string& out, bool& started, Clock::time_point deadline )
{
    while( pipes.out[ 0 ] >= 0 || pipes.err[ 0 ] >= 0 )
    {
        const long long left = remainingMs( deadline );
        if( left <= 0 )
        {
            return false;
        }
        os::pollfd fds[ 3 ] = { { pipes.out[ 0 ], POLLIN, 0 }, { pipes.err[ 0 ], POLLIN, 0 }, { pipes.up[ 0 ], POLLIN, 0 } };
        const int  n        = os::poll( fds, pipes.up[ 0 ] >= 0 ? 3 : 2, int( left ) );
        if( n < 0 && errno != EINTR )
        {
            return false;
        }
        if( n <= 0 )
        {
            continue;
        }
        // a closed descriptor (-1) polls as nothing; revents != 0 covers POLLIN and POLLHUP (EOF) alike
        if( fds[ 0 ].revents != 0 ) { relayOnce( pipes.out[ 0 ], &out, nullptr ); }
        if( fds[ 1 ].revents != 0 ) { relayOnce( pipes.err[ 0 ], nullptr, stderr ); }
        if( pipes.up[ 0 ] >= 0 && fds[ 2 ].revents != 0 )
        {
            started = true;
            ChildPipes::closeFd( pipes.up[ 0 ] );
        }
    }
    return true;
}

inline int exitCodeOf( int status )
{
    if( WIFEXITED( status ) )
    {
        return WEXITSTATUS( status );
    }
    return WIFSIGNALED( status ) ? 128 + WTERMSIG( status ) : 1;
}

// The overrun: make sure the child is in its own session (it said 'S'), tell it, leave the marker, record the row.
inline void deferChild( ChildPipes& pipes, bool started, long long childPid, const WarmPaths& paths, int deadlineMs )
{
    if( !started && pipes.up[ 0 ] >= 0 )
    {
        os::pollfd ready = { pipes.up[ 0 ], POLLIN, 0 };
        (void)os::poll( &ready, 1, kStartedWaitMs );
    }
    ChildPipes::closeFd( pipes.up[ 0 ] );
    writeSmallFile( paths.marker, std::format( "{}\n", childPid ) );
    (void)os::write( pipes.down[ 1 ], "D", 1 );
    ChildPipes::closeFd( pipes.down[ 1 ] );
    ChildPipes::closeFd( pipes.out[ 0 ] );
    ChildPipes::closeFd( pipes.err[ 0 ] );
    appendMeterRow( paths.rootKey, MeterRow{ "deferred", "overrun", deadlineMs, deadlineMs, -1, -1 } );
}

// THE ENTRY POINT, called from main() while the process is still single-threaded. Returns the exit code when this
// process is the PARENT and has answered (the child's answer, or the abstention); nullopt when the caller must run the
// verb itself: the synchronous fallback, or this process is the child. The abstention comes in two steps so its cost
// lands in time the parent spends waiting anyway: `prepareAbstain()` returns the document (it runs git for the facts),
// called right after the fork while the child works; `emitAbstain( doc )` prints it, called only at the overrun.
template<class PrepareAbstain, class EmitAbstain>
std::optional<int> superviseHelpTask( const std::string& root, int deadlineMs, PrepareAbstain&& prepareAbstain, EmitAbstain&& emitAbstain )
{
    EXPECTS( deadlineMs > 0, "the caller asks only with a deadline" );
    const Clock::time_point t0       = Clock::now();
    const Clock::time_point deadline = t0 + std::chrono::milliseconds( deadlineMs );
    const WarmPaths         paths    = warmPaths( root );
    const auto              abstain  = [&]( std::string_view cause )
    {
        const long long elapsed = std::chrono::duration_cast<std::chrono::milliseconds>( Clock::now() - t0 ).count();
        appendMeterRow( paths.rootKey, MeterRow{ "deferred", cause, deadlineMs, elapsed, -1, -1 } );
        std::string doc = prepareAbstain();
        emitAbstain( doc );
        return std::optional<int>( 0 );
    };

    const int lockFd = os::open( paths.lock.c_str(), O_RDWR | O_CREAT, 0644 );
    if( lockFd < 0 )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "without the lock the verb runs synchronously, exactly as without --deadline-ms",
                  "helpdeadline: the warm lock file could not be opened; answering synchronously" );
        return std::nullopt;
    }
    switch( acquireWarmLock( lockFd, paths, deadline ) )
    {
        case LockOutcome::Busy:     os::close( lockFd ); return abstain( "busy" );
        case LockOutcome::TimedOut: os::close( lockFd ); return abstain( "lock-wait" );
        case LockOutcome::Held:     break;
    }
    recordCrashedChild( paths, deadlineMs );
    os::unlink( paths.marker.c_str() );   // a new child: an older marker names a pid that is not ours

    ChildPipes pipes;
    std::fflush( stdout );
    std::fflush( stderr );
    if( !pipes.open() )
    {
        pipes.closeAll();
        return std::nullopt;   // synchronous, the lock still held (its descriptor closes when this process exits)
    }
    const auto pid = os::fork_session();
    if( pid < 0 )
    {
        pipes.closeAll();
        return std::nullopt;   // Windows (ENOSYS), or no process slot: synchronous, as without the flag
    }
    if( pid == 0 )
    {
        becomeChild( pipes, paths, deadlineMs, t0 );
        return std::nullopt;   // the child runs the verb; the inherited lock descriptor stays open until it exits
    }
    // The parent. Its copy of the lock descriptor closes WITHOUT LOCK_UN: the child shares the open file description,
    // and the flock stays held until the child's copy closes.
    os::close( lockFd );
    ChildPipes::closeFd( pipes.out[ 1 ] );
    ChildPipes::closeFd( pipes.err[ 1 ] );
    ChildPipes::closeFd( pipes.up[ 1 ] );
    ChildPipes::closeFd( pipes.down[ 0 ] );

    std::string doc = prepareAbstain();   // the child's output waits in the pipes meanwhile
    std::string out;
    bool        started = false;
    if( relayUntil( pipes, out, started, deadline ) )
    {
        int status = 0;
        os::waitpid( pid, &status, 0 );
        ChildPipes::closeFd( pipes.up[ 0 ] );
        ChildPipes::closeFd( pipes.down[ 1 ] );
        std::fwrite( out.data(), 1, out.size(), stdout );
        std::fflush( stdout );
        return exitCodeOf( status );
    }
    deferChild( pipes, started, (long long)pid, paths, deadlineMs );
    emitAbstain( doc );
    return 0;
}

}   // namespace rw::helpdeadline
