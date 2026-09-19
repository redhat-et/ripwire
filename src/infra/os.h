#pragma once

// os.h — the ONE header that asks which operating system it is compiled for.
//
// THE RULE. Every call whose behaviour or existence differs across operating systems goes through namespace
// rw::os, and every preprocessor test that names an operating system (or a macro that is really one, such as
// MSG_NOSIGNAL or SO_NOSIGPIPE) lives in this file. A call site reads like Unix code with an os:: prefix —
// os::lstat( path, &st ), os::rename( tmp, dst ), os::flock( fd, LOCK_EX ) — with POSIX names, POSIX
// signatures and the POSIX errno contract. It never asks which platform it is on: not with #if, and not with a
// platform fact in a plain if. The facts below exist for this header's own use. test/osswitchcheck.sh (outside
// this layer) refuses an OS test, a POSIX or Windows system header, a raw POSIX call or type, or a platform fact
// anywhere else in src/.
//
// ZERO COST ON POSIX. Each POSIX body is the libc call itself, always inlined, taking the libc call's own raw
// types: no path normalisation, no errno translation, no extra syscall, no lock, no heap, and no std::string
// except spawn_sh's command (its comment says why). The wrappers are deliberately NOT noexcept — a noexcept
// wrapper around a C function the compiler cannot prove non-throwing would add a terminate landing pad the direct
// call never had. A release build carries no out-of-line rw::os symbol. Where a helper's shape could move work
// (a read across a fork, a store across a scope), the shape follows the code it replaced, so the caller compiles
// to the same instructions: the stat-time helpers return a reference to the field, spawn_sh reads its arguments
// in the child, and dirwatch_add / dirwatch_poll take kevent's own caller-owned records.
//
// POSIX CONSTANTS STAY BARE. O_NOFOLLOW, X_OK, PATH_MAX, S_ISREG( m ), LOCK_EX, SIGKILL and friends are macros
// on every POSIX libc, and a function-like macro cannot be wrapped by its own name: `os::S_ISLNK( m )` and even
// the declaration `bool S_ISLNK( mode_t )` would be macro-expanded before the compiler saw a function. The same
// trap closes htons (a function-like macro under glibc at -O2), which is why it is not wrapped either. Call
// sites spell those names bare; the Windows branch of this header defines them.
//
// HELPERS WITHOUT A POSIX NAME exist only where no POSIX call says what the call site needs: exepath (the
// running executable), gettid / pthread_main_np (thread identity), st_mtim / st_ctim (the nanosecond stat
// fields, which Darwin spells st_mtimespec), setsockopt_nosigpipe (the per-socket SIGPIPE switch Linux does
// not have), spawn_sh (the capture child — see its comment for why it is not posix_spawn), and dirwatch_* (the
// kqueue directory watcher). Each is lowercase and C-shaped, and each POSIX body is the code that used to sit at
// its call site.
//
// WINDOWS. The Windows branch will DECLARE the same functions and constants; their bodies live out of line in
// src/infra/os_win32.cpp, compiled only for Windows, so <windows.h> never reaches another translation unit.
// Until that lands the branch is a hard #error. Where a POSIX contract has a security edge, the Windows body
// keeps the POSIX one: open( …, O_NOFOLLOW ) refuses a link at the FINAL component only, as POSIX specifies.
//
// SELECTION. #if is used only where a branch names something that does not exist on the other platform — a
// system header, a platform API or type, or a struct field whose name differs; every #if below is one of those.
// Pure logic selects on the constexpr facts with `if constexpr`, so both branches are type-checked on every CI leg
// and the non-native one cannot rot.

#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <string>

namespace rw::os
{

// ── platform facts: referenced only inside this header ─────────────────────────────────────────────────────
enum class Target : std::uint8_t
{
    Linux,
    Apple,
    OtherPosix,
    Windows,
};

#if defined( _WIN32 )
inline constexpr Target kTarget = Target::Windows;
#elif defined( __APPLE__ )
inline constexpr Target kTarget = Target::Apple;
#elif defined( __linux__ )
inline constexpr Target kTarget = Target::Linux;
#else
inline constexpr Target kTarget = Target::OtherPosix;
#endif
inline constexpr bool kWindows = kTarget == Target::Windows;
inline constexpr bool kApple   = kTarget == Target::Apple;
inline constexpr bool kLinux   = kTarget == Target::Linux;

// the directory watcher's drain batch: a poll that fills it means "call again".
inline constexpr int kDirwatchBatch = 32;

}   // namespace rw::os

#if !defined( _WIN32 )

#include <arpa/inet.h>
#include <fcntl.h>
#include <limits.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#if defined( __APPLE__ )
  #include <mach-o/dyld.h>          // _NSGetExecutablePath
#elif defined( __linux__ )
  #include <sys/syscall.h>          // SYS_gettid
#else
  #include <functional>             // std::hash<std::thread::id> — the last-resort numeric thread id
  #include <thread>
#endif

// kqueue is a BSD interface: <sys/event.h> does not exist on Linux. The `#ifndef` is a deliberate override seam:
// `-DRW_OS_HAS_KQUEUE=0` compiles the no-watcher path on a Mac, so it can be built and RUN there.
#ifndef RW_OS_HAS_KQUEUE
  #if defined( __APPLE__ ) || defined( __FreeBSD__ ) || defined( __OpenBSD__ ) || defined( __NetBSD__ ) || defined( __DragonFly__ )
    #define RW_OS_HAS_KQUEUE 1
  #else
    #define RW_OS_HAS_KQUEUE 0
  #endif
#endif
#if RW_OS_HAS_KQUEUE
  #include <sys/event.h>
#endif

// POSIX.1-2008 names MSG_NOSIGNAL. A platform without it has no per-send switch; its send flag is 0 and SIGPIPE
// is suppressed per socket by setsockopt_nosigpipe instead.
#ifndef MSG_NOSIGNAL
  #define MSG_NOSIGNAL 0
#endif

namespace rw::os
{

// ── types ──────────────────────────────────────────────────────────────────────────────────────────────────
using stat_t    = struct ::stat;
using pollfd    = struct ::pollfd;
using ssize_t   = ::ssize_t;
using off_t     = ::off_t;
using pid_t     = ::pid_t;
using mode_t    = ::mode_t;
using uid_t     = ::uid_t;
using nfds_t    = ::nfds_t;
using socklen_t = ::socklen_t;
using pthread_t      = ::pthread_t;
using pthread_attr_t = ::pthread_attr_t;

// the stat fields call sites read; every platform's stat_t carries them
static_assert( requires( const stat_t& st ) { st.st_mode; st.st_size; st.st_mtime; st.st_ctime; st.st_dev; st.st_ino; st.st_uid; } );

// ── descriptors and files ──────────────────────────────────────────────────────────────────────────────────
// open and fcntl are variadic in C: the two-argument forms pass no third argument, exactly as a direct call does.
[[gnu::always_inline]] inline int     open( const char* path, int flags )                          { return ::open( path, flags ); }
[[gnu::always_inline]] inline int     open( const char* path, int flags, mode_t mode )             { return ::open( path, flags, mode ); }
[[gnu::always_inline]] inline int     openat( int dirFd, const char* path, int flags )              { return ::openat( dirFd, path, flags ); }
[[gnu::always_inline]] inline int     close( int fd )                                              { return ::close( fd ); }
[[gnu::always_inline]] inline ssize_t read( int fd, void* buf, std::size_t count )                 { return ::read( fd, buf, count ); }
[[gnu::always_inline]] inline ssize_t write( int fd, const void* buf, std::size_t count )          { return ::write( fd, buf, count ); }
[[gnu::always_inline]] inline ssize_t pread( int fd, void* buf, std::size_t count, off_t offset )  { return ::pread( fd, buf, count, offset ); }
[[gnu::always_inline]] inline int     fstat( int fd, stat_t* st )                                  { return ::fstat( fd, st ); }
[[gnu::always_inline]] inline int     stat( const char* path, stat_t* st )                         { return ::stat( path, st ); }
[[gnu::always_inline]] inline int     lstat( const char* path, stat_t* st )                        { return ::lstat( path, st ); }
[[gnu::always_inline]] inline int     fcntl( int fd, int cmd )                                     { return ::fcntl( fd, cmd ); }
[[gnu::always_inline]] inline int     fcntl( int fd, int cmd, int arg )                            { return ::fcntl( fd, cmd, arg ); }
[[gnu::always_inline]] inline int     dup( int fd )                                                { return ::dup( fd ); }
[[gnu::always_inline]] inline int     dup2( int fd, int fd2 )                                      { return ::dup2( fd, fd2 ); }
[[gnu::always_inline]] inline int     ftruncate( int fd, off_t length )                            { return ::ftruncate( fd, length ); }
[[gnu::always_inline]] inline int     fsync( int fd )                                              { return ::fsync( fd ); }
[[gnu::always_inline]] inline int     fchmod( int fd, mode_t mode )                                { return ::fchmod( fd, mode ); }
[[gnu::always_inline]] inline int     flock( int fd, int operation )                               { return ::flock( fd, operation ); }
[[gnu::always_inline]] inline int     pipe( int fds[ 2 ] )                                         { return ::pipe( fds ); }
[[gnu::always_inline]] inline int     poll( pollfd* fds, nfds_t count, int timeoutMs )             { return ::poll( fds, count, timeoutMs ); }

// ── streams over descriptors and memory ────────────────────────────────────────────────────────────────────
[[gnu::always_inline]] inline std::FILE* fdopen( int fd, const char* mode )                        { return ::fdopen( fd, mode ); }
[[gnu::always_inline]] inline int        fileno( std::FILE* stream )                               { return ::fileno( stream ); }
[[gnu::always_inline]] inline ssize_t    getline( char** line, std::size_t* capacity, std::FILE* stream ) { return ::getline( line, capacity, stream ); }
[[gnu::always_inline]] inline std::FILE* open_memstream( char** buffer, std::size_t* size )        { return ::open_memstream( buffer, size ); }

// ── paths ──────────────────────────────────────────────────────────────────────────────────────────────────
[[gnu::always_inline]] inline int   unlink( const char* path )                                     { return ::unlink( path ); }
[[gnu::always_inline]] inline int   remove( const char* path )                                     { return ::remove( path ); }
[[gnu::always_inline]] inline int   rename( const char* from, const char* to )                     { return ::rename( from, to ); }
[[gnu::always_inline]] inline int   symlink( const char* target, const char* linkPath )             { return ::symlink( target, linkPath ); }
[[gnu::always_inline]] inline int   mkdir( const char* path, mode_t mode )                         { return ::mkdir( path, mode ); }
[[gnu::always_inline]] inline int   chmod( const char* path, mode_t mode )                         { return ::chmod( path, mode ); }
[[gnu::always_inline]] inline int   access( const char* path, int mode )                           { return ::access( path, mode ); }
[[gnu::always_inline]] inline char* realpath( const char* path, char* resolved )                   { return ::realpath( path, resolved ); }
[[gnu::always_inline]] inline char* getcwd( char* buf, std::size_t size )                          { return ::getcwd( buf, size ); }
[[gnu::always_inline]] inline int   setenv( const char* name, const char* value, int overwrite )   { return ::setenv( name, value, overwrite ); }

// The nanosecond modification / status-change time of a filled stat_t. POSIX.1-2008 names the fields st_mtim and
// st_ctim; Darwin and the BSDs spell them st_mtimespec and st_ctimespec. A reference to the field itself, so
// `os::st_mtim( st ).tv_nsec` is the same load as `st.st_mtim.tv_nsec`. A platform with neither gets whole seconds
// (by value).
#if defined( __APPLE__ ) || defined( __FreeBSD__ ) || defined( __OpenBSD__ ) || defined( __NetBSD__ )
[[gnu::always_inline]] inline const ::timespec& st_mtim( const stat_t& st ) { return st.st_mtimespec; }
[[gnu::always_inline]] inline const ::timespec& st_ctim( const stat_t& st ) { return st.st_ctimespec; }
#elif defined( __linux__ )
[[gnu::always_inline]] inline const ::timespec& st_mtim( const stat_t& st ) { return st.st_mtim; }
[[gnu::always_inline]] inline const ::timespec& st_ctim( const stat_t& st ) { return st.st_ctim; }
#else
[[gnu::always_inline]] inline ::timespec st_mtim( const stat_t& st ) { return ::timespec{ st.st_mtime, 0 }; }
[[gnu::always_inline]] inline ::timespec st_ctim( const stat_t& st ) { return ::timespec{ st.st_ctime, 0 }; }
#endif

// The running executable's path, NUL-terminated in buf: 0, or -1 when the platform cannot say (argv[0] is often
// just a bare name after the shell's PATH search). Not realpath'd — the caller decides.
#if defined( __APPLE__ )
[[gnu::always_inline]] inline int exepath( char* buf, std::size_t bufCount )
{
    std::uint32_t size = std::uint32_t( bufCount );
    return ::_NSGetExecutablePath( buf, &size ) == 0 ? 0 : -1;
}
#elif defined( __linux__ )
[[gnu::always_inline]] inline int exepath( char* buf, std::size_t bufCount )
{
    // readlink returns exactly bufCount when the target does not fit, with no way to tell "exact fit" from
    // "truncated" after the fact — so the call is given the FULL capacity, and a result that reaches it is
    // refused rather than NUL-terminated as if it were complete. bufCount == 0 has no room for a terminator.
    if( bufCount == 0 )
    {
        errno = ERANGE;
        return -1;
    }
    const ssize_t byteCount = ::readlink( "/proc/self/exe", buf, bufCount );
    if( byteCount <= 0 )
    {
        return -1;
    }
    if( std::size_t( byteCount ) >= bufCount )
    {
        errno = ENAMETOOLONG;
        return -1;
    }
    buf[ byteCount ] = '\0';
    return 0;
}
#else
[[gnu::always_inline]] inline int exepath( char*, std::size_t )
{
    errno = ENOSYS;
    return -1;
}
#endif

// ── time ───────────────────────────────────────────────────────────────────────────────────────────────────
[[gnu::always_inline]] inline int      nanosleep( const ::timespec* request, ::timespec* remaining ) { return ::nanosleep( request, remaining ); }
[[gnu::always_inline]] inline std::tm* localtime_r( const std::time_t* time, std::tm* result )       { return ::localtime_r( time, result ); }

// ── processes ──────────────────────────────────────────────────────────────────────────────────────────────
[[gnu::always_inline]] inline pid_t      getpid()                                                  { return ::getpid(); }
[[gnu::always_inline]] inline uid_t      getuid()                                                  { return ::getuid(); }
[[gnu::always_inline]] inline int        kill( pid_t pid, int sig )                                { return ::kill( pid, sig ); }
[[gnu::always_inline]] inline pid_t      waitpid( pid_t pid, int* status, int options )            { return ::waitpid( pid, status, options ); }
[[gnu::always_inline]] inline std::FILE* popen( const char* command, const char* mode )            { return ::popen( command, mode ); }
[[gnu::always_inline]] inline int        pclose( std::FILE* stream )                               { return ::pclose( stream ); }
[[gnu::always_inline]] inline int        system( const char* command )                             { return ::system( command ); }

// Start `/bin/sh -c command` as the leader of its own process group — so a timeout can SIGKILL the whole tree —
// with stdin from /dev/null (a command that reads its terminal must not hang the caller), stdout AND stderr both
// onto the pipe's write end pipeFds[1] (interleaved, as a terminal would show them), and both pipe ends closed in
// the child. fork's contract: the child's pid, or -1 with errno set and no child. An exec failure is the child's own
// exit status 127, mirroring sh's command-not-found code.
//
// WHY NOT ::posix_spawn. Its file actions and POSIX_SPAWN_SETPGROUP express every step here, but three failure
// paths would change what the caller reports: a /bin/sh that cannot be exec'd becomes a spawn error instead of
// exit 127, an unopenable /dev/null or a refused setpgid fails the spawn instead of being tolerated, and no gate
// can reach any of the three to show them equal. So the body stays the fork/exec it has always been, and a
// Windows body gives the same contract (a job object is the process group).
//
// WHY A std::string AND THE PIPE ARRAY. The command's c_str() and both descriptors are read in the CHILD, after
// fork, exactly where the call site used to read them; `const char*` and two ints would move those reads into the
// parent and change the caller's codegen.
[[gnu::always_inline]] inline pid_t spawn_sh( const std::string& command, const int pipeFds[ 2 ] )
{
    const pid_t child = ::fork();
    if( child < 0 )
    {
        return child;
    }
    if( child == 0 )
    {
        ::setpgid( 0, 0 );
        const int devNull = ::open( "/dev/null", O_RDONLY );
        if( devNull >= 0 ) { ::dup2( devNull, STDIN_FILENO );  ::close( devNull ); }
        ::dup2( pipeFds[ 1 ], STDOUT_FILENO );  ::dup2( pipeFds[ 1 ], STDERR_FILENO );
        ::close( pipeFds[ 0 ] );  ::close( pipeFds[ 1 ] );
        ::execl( "/bin/sh", "sh", "-c", command.c_str(), static_cast<char*>( nullptr ) );
        ::_exit( 127 );
    }
    ::setpgid( child, child );   // the parent side of the same race — both settings agree, whichever runs first
    return child;
}

// ── threads ────────────────────────────────────────────────────────────────────────────────────────────────
// gettid: the 64-bit kernel thread id a tracer shows (Darwin's pthread_threadid_np, Linux's SYS_gettid).
// pthread_main_np: nonzero on the process's initial thread. Linux: the thread whose tid EQUALS the pid — the exact
// definition. A platform with neither latches its first caller, and a stable per-thread hash stands in for the id.
[[gnu::always_inline]] inline ::pthread_t pthread_self() { return ::pthread_self(); }
#if defined( __APPLE__ )
[[gnu::always_inline]] inline std::uint64_t gettid()
{
    std::uint64_t tid = 0;
    ::pthread_threadid_np( nullptr, &tid );
    return tid;
}
[[gnu::always_inline]] inline int pthread_main_np() { return ::pthread_main_np(); }
#elif defined( __linux__ )
[[gnu::always_inline]] inline std::uint64_t gettid()          { return (std::uint64_t) ::syscall( SYS_gettid ); }
[[gnu::always_inline]] inline int           pthread_main_np() { return ::getpid() == (pid_t) ::syscall( SYS_gettid ) ? 1 : 0; }
#else
[[gnu::always_inline]] inline std::uint64_t gettid() { return (std::uint64_t) std::hash<std::thread::id>{}( std::this_thread::get_id() ); }
inline int pthread_main_np()
{
    static const std::thread::id firstCaller = std::this_thread::get_id();
    return std::this_thread::get_id() == firstCaller ? 1 : 0;
}
#endif
#if defined( __APPLE__ ) || defined( __linux__ )
[[gnu::always_inline]] inline int pthread_getname_np( ::pthread_t thread, char* name, std::size_t nameCount ) { return ::pthread_getname_np( thread, name, nameCount ); }
#else
[[gnu::always_inline]] inline int pthread_getname_np( ::pthread_t, char*, std::size_t ) { return ENOSYS; }
#endif

// A stack whose SIZE is chosen rather than inherited (infra/stackthreads.h): attr init/setstacksize/destroy,
// create and join, nothing wrapped beyond the always_inline passthrough every other os:: call gets.
[[gnu::always_inline]] inline int pthread_attr_init( pthread_attr_t* attr )                                { return ::pthread_attr_init( attr ); }
[[gnu::always_inline]] inline int pthread_attr_setstacksize( pthread_attr_t* attr, std::size_t stackBytes ) { return ::pthread_attr_setstacksize( attr, stackBytes ); }
[[gnu::always_inline]] inline int pthread_attr_destroy( pthread_attr_t* attr )                              { return ::pthread_attr_destroy( attr ); }
[[gnu::always_inline]] inline int pthread_create( pthread_t* thread, const pthread_attr_t* attr, void* (*start)( void* ), void* arg )
{
    return ::pthread_create( thread, attr, start, arg );
}
[[gnu::always_inline]] inline int pthread_join( pthread_t thread, void** valueOut ) { return ::pthread_join( thread, valueOut ); }

// ── sockets ────────────────────────────────────────────────────────────────────────────────────────────────
[[gnu::always_inline]] inline int     socket( int domain, int type, int protocol )                     { return ::socket( domain, type, protocol ); }
[[gnu::always_inline]] inline int     setsockopt( int fd, int level, int name, const void* value, socklen_t length ) { return ::setsockopt( fd, level, name, value, length ); }
[[gnu::always_inline]] inline int     bind( int fd, const ::sockaddr* address, socklen_t length )     { return ::bind( fd, address, length ); }
[[gnu::always_inline]] inline int     listen( int fd, int backlog )                                     { return ::listen( fd, backlog ); }
[[gnu::always_inline]] inline int     accept( int fd, ::sockaddr* address, socklen_t* length )          { return ::accept( fd, address, length ); }
[[gnu::always_inline]] inline ssize_t recv( int fd, void* buf, std::size_t count, int flags )           { return ::recv( fd, buf, count, flags ); }
[[gnu::always_inline]] inline ssize_t send( int fd, const void* buf, std::size_t count, int flags )     { return ::send( fd, buf, count, flags ); }
[[gnu::always_inline]] inline int     inet_pton( int family, const char* text, void* address )          { return ::inet_pton( family, text, address ); }

// A send to a peer that is gone fails with EPIPE instead of raising SIGPIPE, for this socket only. Where the
// platform has the per-socket option (SO_NOSIGPIPE) this sets it; elsewhere MSG_NOSIGNAL on each send does the
// job and this is a no-op that reports success. A platform with both gets both.
#ifdef SO_NOSIGPIPE
[[gnu::always_inline]] inline int setsockopt_nosigpipe( int fd, const void* value, socklen_t length ) { return ::setsockopt( fd, SOL_SOCKET, SO_NOSIGPIPE, value, length ); }
#else
[[gnu::always_inline]] inline int setsockopt_nosigpipe( int, const void*, socklen_t ) { return 0; }
#endif

// ── directory watching ─────────────────────────────────────────────────────────────────────────────────────
// No POSIX call watches a directory; on a kqueue platform these ARE kqueue/kevent, with kevent's own argument shapes.
// dirwatch_available: whether this build has a watcher at all. Where it has none, "no watcher, always sweep" is the
//   caller's DESIGNED path, not a degradation, and must stay silent — so the caller asks this before it opens one,
//   and a platform without a watcher folds the whole arm away.
// dirwatch_open: kqueue() — a descriptor, or -1 with errno set.
// dirwatch_add: register dirFd for write/delete/rename/extend events (edge-triggered) through the caller's change
//   record, without blocking — the kevent result, -1 on failure.
// dirwatch_poll: kevent's receive half — up to eventCount pending events into the caller's array, waiting at most
//   *timeout; how many it took, or -1.
#if RW_OS_HAS_KQUEUE
using dirwatch_event = struct ::kevent;
[[gnu::always_inline]] inline constexpr bool dirwatch_available() { return true; }
[[gnu::always_inline]] inline int            dirwatch_open()      { return ::kqueue(); }
[[gnu::always_inline]] inline int dirwatch_add( int watchFd, int dirFd, dirwatch_event* change )
{
    EV_SET( change, dirFd, EVFILT_VNODE, EV_ADD | EV_CLEAR, NOTE_WRITE | NOTE_DELETE | NOTE_RENAME | NOTE_EXTEND, 0, nullptr );
    struct timespec zero = { 0, 0 };
    return ::kevent( watchFd, change, 1, nullptr, 0, &zero );
}
[[gnu::always_inline]] inline int dirwatch_poll( int watchFd, dirwatch_event* events, int eventCount, const ::timespec* timeout )
{
    return ::kevent( watchFd, nullptr, 0, events, eventCount, timeout );
}
#else
struct dirwatch_event
{
};
[[gnu::always_inline]] inline constexpr bool dirwatch_available() { return false; }
[[gnu::always_inline]] inline int dirwatch_open()                                                         { errno = ENOSYS; return -1; }
[[gnu::always_inline]] inline int dirwatch_add( int, int, dirwatch_event* )                               { errno = ENOSYS; return -1; }
[[gnu::always_inline]] inline int dirwatch_poll( int, dirwatch_event*, int, const ::timespec* )           { errno = ENOSYS; return -1; }
#endif

}   // namespace rw::os

#else   // _WIN32

#error "rw::os: the Windows declarations (this header) and their bodies (src/infra/os_win32.cpp) land with PR #44"

#endif
