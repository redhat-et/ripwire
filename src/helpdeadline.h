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

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>

#include "infra/Diagnostics.h"
#include "infra/emit.h"
#include "infra/os.h"
#include "infra/ownedfile.h"   // rw::OwnedFile — the status and marker reads close on every return
#include "gitmine.h"   // rw::civilFromDays — the UTC calendar date of the meter row's `at`
#include "pathguard.h"   // pathguard::OwnedFd — the pipe ends close themselves on every return
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
    return static_cast<std::int64_t>( std::time( nullptr ) );
}

inline std::string utcStamp( std::int64_t epoch )
{
    if( !VALIDATE( epoch >= 0, "the wall clock reads after 1970 (std::time is -1 on failure)" ) )
    {
        epoch = 0;   // a misset clock costs the row its `at`, never the row
    }
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
    std::string     text;
    const OwnedFile f = openOwnedFile( path.c_str(), "rb" );
    if( !f )
    {
        return text;
    }
    char              buf[ 512 ];
    const std::size_t got = std::fread( buf, 1, sizeof( buf ), f.file );
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

// quality::atomicWriteFile's tmp + rename, so a reader never sees half a record. Best effort: a status that cannot be
// written costs the next call its shortcut (it waits on the lock instead), never an answer.
inline void writeSmallFile( const std::string& path, const std::string& text )
{
    if( !quality::atomicWriteFile( path, text ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "the status file is the next call's shortcut, never this call's answer",
                  "helpdeadline: could not write a warm status file" );
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
    const pathguard::OwnedFd fd( os::open( log.c_str(), O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644 ) );
    if( !fd.valid() )
    {
        return;
    }
    // One write of one short line on an O_APPEND descriptor: rows from concurrent writers never interleave.
    (void)os::write( fd.get(), line.data(), line.size() );
}

// ── the child's side ─────────────────────────────────────────────────────────────────────────────────────────────
struct ChildSession
{
    bool              active = false;
    int               downFd = -1;   // the parent writes 'D' here at the overrun; EOF means the parent is gone
    int               lockFd = -1;   // the inherited warm lock: open (flock held) until this process exits
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
        if( Clock::now() >= deadline )
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

// The four pipes, each end an owned descriptor (pathguard::OwnedFd), so every return path closes what it holds, and
// each close-on-exec (os::pipe_cloexec): the fork keeps them, and no git or shell the child starts later inherits one.
struct ChildPipes
{
    using Fd = pathguard::OwnedFd;
    Fd outR{ -1 }, outW{ -1 };     // child stdout -> parent
    Fd errR{ -1 }, errW{ -1 };     // child stderr -> parent
    Fd upR{ -1 }, upW{ -1 };       // child 'S' (started: in its own session, status written) -> parent
    Fd downR{ -1 }, downW{ -1 };   // parent 'D' (deferred) -> child

    static bool openPair( Fd& readEnd, Fd& writeEnd )
    {
        int fds[ 2 ] = { -1, -1 };
        if( os::pipe_cloexec( fds ) != 0 )
        {
            return false;
        }
        readEnd.reset( fds[ 0 ] );
        writeEnd.reset( fds[ 1 ] );
        return true;
    }
    bool open() { return openPair( outR, outW ) && openPair( errR, errW ) && openPair( upR, upW ) && openPair( downR, downW ); }
};

// The lock descriptor leaves `lock` (which would close it when superviseHelpTask returns) for the rest of this process:
// the flock stays held until exit, and, opened close-on-exec, no git child that outlives this process inherits it.
inline void keepLockUntilExit( pathguard::OwnedFd& lock )
{
    childSession().lockFd = lock.release();
}

// In the child, right after the fork: stdout/stderr onto the pipes, the status record, then 'S' to the parent.
inline void becomeChild( ChildPipes& pipes, pathguard::OwnedFd& lock, const WarmPaths& paths, int deadlineMs, Clock::time_point t0 )
{
    os::dup2( pipes.outW.get(), STDOUT_FILENO );
    os::dup2( pipes.errW.get(), STDERR_FILENO );
    pipes.outR.reset( -1 );  pipes.outW.reset( -1 );
    pipes.errR.reset( -1 );  pipes.errW.reset( -1 );
    pipes.upR.reset( -1 );
    pipes.downW.reset( -1 );

    ChildSession& s = childSession();
    s.active        = true;
    s.downFd        = pipes.downR.release();   // outlives `pipes`: finishChild reads it at the end of main
    keepLockUntilExit( lock );
    s.deadlineMs    = deadlineMs;
    s.statusPath    = paths.status;
    s.rootKey       = paths.rootKey;
    s.t0            = t0;
    s.startedUnix   = unixNow();
    writeStatus( s.statusPath, WarmStatus{ "running", (long long)os::getpid(), s.startedUnix, -1, -1, -1 } );
    (void)os::write( pipes.upW.get(), "S", 1 );
    pipes.upW.reset( -1 );

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
inline bool relayOnce( pathguard::OwnedFd& fd, std::string* keep, std::FILE* forward )
{
    char          buf[ 65536 ];
    const auto    got = os::read( fd.get(), buf, sizeof( buf ) );
    if( got <= 0 )
    {
        if( got < 0 && errno == EINTR )
        {
            return true;
        }
        fd.reset( -1 );
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
// One poll's worth: a closed descriptor (-1) polls as nothing, and revents != 0 covers POLLIN and POLLHUP (EOF) alike.
inline void drainReady( const os::pollfd ( &fds )[ 3 ], ChildPipes& pipes, std::string& out, bool& started )
{
    if( fds[ 0 ].revents != 0 ) { relayOnce( pipes.outR, &out, nullptr ); }
    if( fds[ 1 ].revents != 0 ) { relayOnce( pipes.errR, nullptr, stderr ); }
    if( pipes.upR.valid() && fds[ 2 ].revents != 0 )
    {
        started = true;
        pipes.upR.reset( -1 );
    }
}

inline bool relayUntil( ChildPipes& pipes, std::string& out, bool& started, Clock::time_point deadline )
{
    while( pipes.outR.valid() || pipes.errR.valid() )
    {
        // Past the deadline the poll does not wait, but what is already in the pipes still drains: a child that finished
        // in time is relayed even when the caller reached this loop late (the abstention's git facts took that long).
        const long long left = std::max( 0LL, (long long)std::chrono::ceil<std::chrono::milliseconds>( deadline - Clock::now() ).count() );
        os::pollfd      fds[ 3 ] = { { pipes.outR.get(), POLLIN, 0 }, { pipes.errR.get(), POLLIN, 0 }, { pipes.upR.get(), POLLIN, 0 } };
        const int       n        = os::poll( fds, pipes.upR.valid() ? 3 : 2, int( left ) );
        if( n < 0 && errno != EINTR )
        {
            return false;
        }
        if( n > 0 )
        {
            drainReady( fds, pipes, out, started );
        }
        else if( left == 0 )
        {
            return false;
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

// The parent's side of the fork: relay the child's answer when it finishes by the deadline (its exit code), or nullopt
// at the overrun with the pipes still open for deferChild. The child's 'S' is consumed here when it arrives in time.
inline std::optional<int> relayChild( ChildPipes& pipes, long long childPid, Clock::time_point deadline )
{
    pipes.outW.reset( -1 );
    pipes.errW.reset( -1 );
    pipes.upW.reset( -1 );
    pipes.downR.reset( -1 );
    std::string out;
    bool        started = false;
    if( !relayUntil( pipes, out, started, deadline ) )
    {
        return std::nullopt;
    }
    int       status = 0;
    os::pid_t reaped = -1;
    do
    {
        reaped = os::waitpid( os::pid_t( childPid ), &status, 0 );
    } while( reaped < 0 && errno == EINTR );
    std::fwrite( out.data(), 1, out.size(), stdout );
    std::fflush( stdout );
    return reaped < 0 ? 1 : exitCodeOf( status );   // a failed wait leaves the code unknown: 1, never the initial 0
}

// The overrun: make sure the child is in its own session (it said 'S'), tell it, leave the marker, record the row.
inline void deferChild( ChildPipes& pipes, long long childPid, const WarmPaths& paths, int deadlineMs )
{
    if( pipes.upR.valid() )   // no 'S' yet: wait (bounded) until the child is in its own session
    {
        os::pollfd ready = { pipes.upR.get(), POLLIN, 0 };
        (void)os::poll( &ready, 1, kStartedWaitMs );
    }
    pipes.upR.reset( -1 );
    writeSmallFile( paths.marker, std::format( "{}\n", childPid ) );
    (void)os::write_nosigpipe( pipes.downW.get(), "D", 1 );   // a child that just exited reads nothing: EPIPE, never SIGPIPE
    pipes.downW.reset( -1 );
    pipes.outR.reset( -1 );
    pipes.errR.reset( -1 );
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
    // fork() copies only the calling thread: a lock any other thread holds (malloc's included) stays locked in the child
    // forever. main() calls this before it starts a thread; a thread started earlier must move after this call.
    ASSUME( os::liveThreadCount() <= 1, "superviseHelpTask forks: the process must be single-threaded here" );
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

    // Close-on-exec: a git child that outlives the indexing child (git's own background maintenance) must not keep the
    // flock, or every later call waits out its deadline on a lock nobody is indexing under.
    pathguard::OwnedFd lock( os::open( paths.lock.c_str(), O_RDWR | O_CREAT | O_CLOEXEC, 0644 ) );
    if( !lock.valid() )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "without the lock the verb runs synchronously, exactly as without --deadline-ms",
                  "helpdeadline: the warm lock file could not be opened; answering synchronously" );
        return std::nullopt;
    }
    switch( acquireWarmLock( lock.get(), paths, deadline ) )
    {
        case LockOutcome::Busy:     lock.reset( -1 ); return abstain( "busy" );
        case LockOutcome::TimedOut: lock.reset( -1 ); return abstain( "lock-wait" );
        case LockOutcome::Held:     break;
    }
    recordCrashedChild( paths, deadlineMs );
    os::unlink( paths.marker.c_str() );   // a new child: an older marker names a pid that is not ours

    ChildPipes pipes;
    std::fflush( stdout );
    std::fflush( stderr );
    // The synchronous fallbacks below keep the lock for the run that follows, so a concurrent call still waits or abstains.
    if( !pipes.open() )
    {
        keepLockUntilExit( lock );
        DISCLOSE( Diagnostics::answerUnchanged, "without the relay pipes the verb runs synchronously, exactly as without --deadline-ms",
                  "helpdeadline: the relay pipes could not be opened; answering synchronously, with no deadline" );
        return std::nullopt;
    }
    const auto pid = os::fork_session();
    if( pid < 0 )
    {
        if( errno != ENOSYS )   // Windows has no fork: synchronous by design, documented in --help, nothing to disclose
        {
            DISCLOSE( Diagnostics::answerUnchanged, "without a child the verb runs synchronously, exactly as without --deadline-ms",
                      "helpdeadline: fork failed (no process slot?); answering synchronously, with no deadline" );
        }
        keepLockUntilExit( lock );
        return std::nullopt;
    }
    if( pid == 0 )
    {
        becomeChild( pipes, lock, paths, deadlineMs, t0 );
        return std::nullopt;   // the child runs the verb; its copy of the lock descriptor stays open until it exits
    }
    // The parent. Its copy of the lock descriptor closes WITHOUT LOCK_UN: the child shares the open file description,
    // and the flock stays held until the child's copy closes.
    lock.reset( -1 );
    std::string doc = prepareAbstain();   // the child's output waits in the pipes meanwhile
    if( const std::optional<int> rc = relayChild( pipes, (long long)pid, deadline ) )
    {
        return rc;
    }
    deferChild( pipes, (long long)pid, paths, deadlineMs );
    emitAbstain( doc );
    return 0;
}

}   // namespace rw::helpdeadline
