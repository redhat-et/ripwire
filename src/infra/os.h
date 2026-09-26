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
// WINDOWS. The Windows branch DECLARES the same functions and constants; their bodies live out of line in
// src/infra/os_win32.cpp, compiled only for Windows, so <windows.h> never reaches another translation unit.
// Where a POSIX contract has a security edge, the Windows body
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
#include <string_view>

#include "shquote.h"   // rw::shSingleQuote: path_prepend_hint quotes its directory as a shell literal

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
using sockaddr       = struct ::sockaddr;
using sockaddr_in    = struct ::sockaddr_in;
using timeval        = struct ::timeval;

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
// fflush / fclose of a stream open_memstream returned: the POSIX calls themselves. Spelled os:: at a memstream's
// flush and close because that is when POSIX publishes *buffer and *size — and a platform without open_memstream
// has to publish them there itself. Any other stream closes through std::fclose.
[[gnu::always_inline]] inline int        fflush( std::FILE* stream )                               { return std::fflush( stream ); }
[[gnu::always_inline]] inline int        fclose( std::FILE* stream )                               { return std::fclose( stream ); }

// ── paths ──────────────────────────────────────────────────────────────────────────────────────────────────
[[gnu::always_inline]] inline int   unlink( const char* path )                                     { return ::unlink( path ); }
[[gnu::always_inline]] inline int   remove( const char* path )                                     { return ::remove( path ); }
[[gnu::always_inline]] inline int   rename( const char* from, const char* to )                     { return ::rename( from, to ); }
[[gnu::always_inline]] inline int   mkdir( const char* path, mode_t mode )                         { return ::mkdir( path, mode ); }
[[gnu::always_inline]] inline int   chmod( const char* path, mode_t mode )                         { return ::chmod( path, mode ); }
[[gnu::always_inline]] inline int   access( const char* path, int mode )                           { return ::access( path, mode ); }
[[gnu::always_inline]] inline char* realpath( const char* path, char* resolved )                   { return ::realpath( path, resolved ); }
[[gnu::always_inline]] inline char* getcwd( char* buf, std::size_t size )                          { return ::getcwd( buf, size ); }
[[gnu::always_inline]] inline int   setenv( const char* name, const char* value, int overwrite )   { return ::setenv( name, value, overwrite ); }

// rebased_path: the spelling of `path` that THIS layer's own calls above actually touch — identity on POSIX,
// where a path is never rewritten between the caller and the syscall. Windows rewrites some paths (see the
// Windows branch); exists for a caller that must hand `path` to something outside os:: that performs no such
// rewrite itself (std::filesystem, a popen'd shell command) and needs the same answer os::open/os::stat/os::mkdir
// already give internally — #326.
[[gnu::always_inline]] inline std::string rebased_path( const char* path )
{
    if( path == nullptr )
    {
        return {};
    }
    return path;   // no rewrite on this platform: `path` already is the spelling every os:: call above touches
}

// which: the path a shell would run for `command` — `command` itself when it contains a '/' and is executable,
// otherwise the first executable PATH entry joined with it (an empty entry is the current directory, as sh
// reads it); "" when there is none. No POSIX call does this search (execvp does it without saying what it found).
[[gnu::always_inline]] inline std::string which( std::string_view command )
{
    if( command.empty() ) { return {}; }
    const auto executable = []( const std::string& path )
    {
        return ::access( path.c_str(), X_OK ) == 0;
    };
    if( command.find( '/' ) != std::string_view::npos )
    {
        const std::string path( command );
        return executable( path ) ? path : std::string();
    }
    const char* pathEnv = std::getenv( "PATH" );
    std::string_view remaining = pathEnv ? std::string_view( pathEnv ) : std::string_view();
    while( !remaining.empty() )
    {
        const std::size_t split = remaining.find( ':' );
        const std::string_view dir = remaining.substr( 0, split );
        const std::string candidate = std::string( dir.empty() ? "." : dir ) + "/" + std::string( command );
        if( executable( candidate ) ) { return candidate; }
        if( split == std::string_view::npos ) { break; }
        remaining.remove_prefix( split + 1 );
    }
    return {};
}

// which_spelling_is_exact: does a `which NAME` answer (this which() above, or a child shell's popen `which`, as
// --doctor's binary-path row runs) come back with NAME's own on-disk spelling, extension included? True on POSIX,
// where a name IS the spelling. False only on Windows, where Git Bash's MSYS `which` never prints ".exe" — a call
// site comparing that answer to a real path must not read the difference alone as proof the two files differ.
[[gnu::always_inline]] inline bool which_spelling_is_exact() { return true; }
// path_prepend_hint: the line a user pastes to put `dir` (a program path) first on PATH in the shell they use there, as
// --doctor's NOT ON PATH hint prints it. POSIX: an `export PATH=` line and the rc-file reminder. Windows: PowerShell's
// `$env:Path =` (oswin::powerShellPathPrependHint), since a POSIX line pasted there does nothing (#334).
// `dir` is single-quoted as a shell literal (CodeRabbit 4109273959): unquoted or double-quoted, a `$`, a backtick or
// a `$(...)` in the directory name would expand or run when the user pastes the hint. `$PATH` stays outside the
// quotes so it still expands to the existing PATH.
inline std::string path_prepend_hint( std::string_view dir )
{
    return "export PATH=" + shSingleQuote( std::string( dir ) ) + ":\"$PATH\" (and put that line in your shell rc file)";
}

// ── process start and path intake ──────────────────────────────────────────────────────────────────────────
// Inside the program a path is UTF-8 with '/' separators on every platform, so the spelling is fixed where a path
// ENTERS — argv, the environment, an MCP argument — and nowhere else. Neither call has a POSIX name because POSIX
// needs neither: argv is already the caller's bytes, stdio does no newline translation, and a path has one
// separator. Both POSIX bodies are empty; a call compiles to nothing.
// init_process: the first statement of main. (Windows: UTF-8 argv from the UTF-16 command line, binary
//   stdin/stdout/stderr, and HOME/TMPDIR/XDG_CACHE_HOME/CODEX_HOME/CLAUDE_CONFIG_DIR in the program's spelling.)
// normalize_path_arg: one argument the CALLER knows is a path — a positional root, a --cache= value, an MCP `path` —
//   rewritten in place, never longer. (Windows: '\' becomes '/', Git Bash's "/c/..." becomes "C:/...".) A value that
//   is not a path (a --grep pattern) must never reach it.
[[gnu::always_inline]] inline void init_process( int&, char**& ) {}
[[gnu::always_inline]] inline void normalize_path_arg( char* ) {}

// path grammar: the three questions about a PROGRAM path (UTF-8, '/'-separated) whose answer is spelled differently
// where drives exist. No POSIX call asks them; each POSIX body is the expression its call site used to hold.
// path_is_absolute: does `path` start at a root ("/x"; Windows also "C:/x" and "//server/x").
// path_is_root: is `path` a filesystem root itself ("/"; Windows also "C:/").
// program_path: a std::filesystem::path in the program's spelling — its native string here; on Windows the generic
//   ('/') one. A template, so this header needs no <filesystem>.
// path_arg: the same spelling at the moment a std::filesystem::path is handed to one of the calls ABOVE, every one of
//   which takes `const char*`. `path.c_str()` cannot be that argument on both platforms — std::filesystem::path's
//   value_type is char here and wchar_t on Windows, so `os::stat( p.c_str(), … )` compiles on exactly one of them
//   (@lennix1337's Windows validation of #44 caught it in src/ingest.cpp and src/wrap.h, clang-cl and cl.exe alike).
//   This is the ONE place that difference is absorbed, instead of a per-call-site narrowing. Here a path's own native
//   bytes ARE the program's spelling, so it returns a reference to them and copies nothing: `os::path_arg( p ).c_str()`
//   is the very pointer `p.c_str()` was, and every POSIX call site below it is byte-for-byte the call it already made.
[[gnu::always_inline]] inline bool path_is_absolute( const std::string& path ) { return !path.empty() && path.front() == '/'; }
[[gnu::always_inline]] inline bool path_is_root( const std::string& path )     { return path == "/"; }
template<class FsPath>
[[gnu::always_inline]] inline std::string program_path( const FsPath& path ) { return path.string(); }
template<class FsPath>
[[gnu::always_inline]] inline const std::string& path_arg( const FsPath& path ) { return path.native(); }

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

#else   // _WIN32 ── DECLARATIONS ONLY: every body below lives out of line in src/infra/os_win32.cpp ──────────────────

// WHAT THIS BRANCH IS. The same functions the POSIX branch defines, declared with the same names and shapes (arm E of
// test/osswitchcheck.sh compares the two sets), plus the POSIX types, constants and stat fields call sites spell. It
// includes no <windows.h> and no <winsock2.h>: those reach exactly one translation unit, os_win32.cpp, which includes
// them BEFORE this header — so every constant below that the SDK also defines is #ifndef-guarded and steps aside for
// the SDK's own spelling there. The headers named here are the C runtime's (UCRT), not the Win32 API's.
//
// THE CONTRACTS THE BODIES KEEP (each one is what the POSIX call site already relies on):
//   * errno — every failure sets errno from ONE Win32/WSA→errno table (os_win32_logic.h), so a call site's
//     `errno == ELOOP` / `strerror( errno )` reads the same on every platform;
//   * paths — the program's paths are UTF-8 with '/' separators; each body converts to UTF-16 on a stack buffer at
//     the call and back to '/' on the way out (realpath, getcwd, exepath). Git Bash's "/c/..." drive spelling is
//     accepted at the same conversion, so a path that arrived through argv, the environment or MCP needs no pass of
//     its own;
//   * O_NOFOLLOW — refuses a link at the FINAL component only, as POSIX specifies. A symlink or a junction reparse
//     point is a link; any other reparse tag (OneDrive placeholders, dedup) is an ordinary file;
//   * lstat — S_IFLNK for the same two tags; st_uid is this user's id only when lstat has read the owner and it is
//     this user (or BUILTIN\Administrators), and (uid_t)-2 from stat/fstat, which never read it — an ownership test
//     over stat fails closed. st_dev/st_ino are the volume serial and the file id, so a same-file test is real;
//   * descriptors — CRT descriptors (_open_osfhandle), so read/write/close/fstat stay one-liners; a SOCKET is not
//     one, and socket() hands out a descriptor from its own range that the socket calls and close() map back;
//   * processes — spawn_sh starts bash (Git for Windows, resolved once, never from the current directory) with
//     `-c command` inside a Job Object: kill( -pid, SIGKILL ) ends the whole tree, and waitpid's status decodes
//     through the W* macros below.
#include <climits>
#include <fcntl.h>       // UCRT: _O_RDONLY/_O_WRONLY/_O_RDWR/_O_CREAT/_O_TRUNC/_O_EXCL/_O_APPEND/_O_BINARY
#include <sys/stat.h>    // UCRT: _S_IFMT/_S_IFDIR/_S_IFREG/_S_IFCHR/_S_IFIFO
#include <sys/types.h>

// ── open() flags: the UCRT's own values where it has the flag, unused high bits where POSIX has one and it does not ─
#ifndef O_RDONLY
  #define O_RDONLY _O_RDONLY
#endif
#ifndef O_WRONLY
  #define O_WRONLY _O_WRONLY
#endif
#ifndef O_RDWR
  #define O_RDWR _O_RDWR
#endif
#ifndef O_APPEND
  #define O_APPEND _O_APPEND
#endif
#ifndef O_CREAT
  #define O_CREAT _O_CREAT
#endif
#ifndef O_TRUNC
  #define O_TRUNC _O_TRUNC
#endif
#ifndef O_EXCL
  #define O_EXCL _O_EXCL
#endif
#ifndef O_NONBLOCK
  #define O_NONBLOCK 0x01000000   // open(): a non-disk handle (pipe, console, device) is refused a blocking read — see os_win32.cpp
#endif
#ifndef O_NOFOLLOW
  #define O_NOFOLLOW 0x02000000   // open(): the final component must not be a symlink or junction (ELOOP)
#endif
#ifndef O_CLOEXEC
  #define O_CLOEXEC 0x04000000    // open(): the handle is not inherited by a child
#endif
#ifndef O_DIRECTORY
  #define O_DIRECTORY 0x08000000  // open(): the path must name a directory (ENOTDIR); the directory cannot be renamed while open
#endif
#ifndef F_GETFL
  #define F_GETFL 3
#endif
#ifndef F_SETFL
  #define F_SETFL 4
#endif
#ifndef LOCK_SH
  #define LOCK_SH 1
#endif
#ifndef LOCK_EX
  #define LOCK_EX 2
#endif
#ifndef LOCK_NB
  #define LOCK_NB 4
#endif
#ifndef LOCK_UN
  #define LOCK_UN 8
#endif

// ── file types and access modes ─────────────────────────────────────────────────────────────────────────────────
#ifndef S_IFMT
  #define S_IFMT _S_IFMT
#endif
#ifndef S_IFDIR
  #define S_IFDIR _S_IFDIR
#endif
#ifndef S_IFREG
  #define S_IFREG _S_IFREG
#endif
#ifndef S_IFCHR
  #define S_IFCHR _S_IFCHR
#endif
#ifndef S_IFIFO
  #define S_IFIFO _S_IFIFO
#endif
#ifndef S_IFLNK
  #define S_IFLNK 0xA000
#endif
#ifndef S_ISREG
  #define S_ISREG( m ) ( ( ( m ) & S_IFMT ) == S_IFREG )
#endif
#ifndef S_ISDIR
  #define S_ISDIR( m ) ( ( ( m ) & S_IFMT ) == S_IFDIR )
#endif
#ifndef S_ISLNK
  #define S_ISLNK( m ) ( ( ( m ) & S_IFMT ) == S_IFLNK )
#endif
#ifndef S_ISFIFO
  #define S_ISFIFO( m ) ( ( ( m ) & S_IFMT ) == S_IFIFO )
#endif
#ifndef F_OK
  #define F_OK 0
#endif
#ifndef X_OK
  #define X_OK 1
#endif
#ifndef W_OK
  #define W_OK 2
#endif
#ifndef R_OK
  #define R_OK 4
#endif
#ifndef STDIN_FILENO
  #define STDIN_FILENO 0
#endif
#ifndef STDOUT_FILENO
  #define STDOUT_FILENO 1
#endif
#ifndef STDERR_FILENO
  #define STDERR_FILENO 2
#endif
#ifndef PATH_MAX
  #define PATH_MAX 4096           // realpath/getcwd/exepath write at most this many bytes, or fail with ENAMETOOLONG
#endif

// ── processes: the wait status is (exit code & 0xff) << 8 for an exit and the signal number for a kill, so the POSIX
//    decoders read it unchanged; os_win32_logic.h maps a crash's NTSTATUS to the signal POSIX would have reported ─
#ifndef SIGKILL
  #define SIGKILL 9
#endif
#ifndef WNOHANG
  #define WNOHANG 1
#endif
#ifndef WIFEXITED
  #define WIFEXITED( s ) ::rw::oswin::waitIfExited( s )       // the decoders are tested on every platform (os_win32_logic.h)
#endif
#ifndef WEXITSTATUS
  #define WEXITSTATUS( s ) ::rw::oswin::waitExitStatus( s )
#endif
#ifndef WIFSIGNALED
  #define WIFSIGNALED( s ) ::rw::oswin::waitIfSignaled( s )
#endif
#ifndef WTERMSIG
  #define WTERMSIG( s ) ::rw::oswin::waitTermSig( s )
#endif
#ifndef POLLIN
  #define POLLIN 0x0300           // Winsock's POLLRDNORM | POLLRDBAND
#endif
#ifndef MSG_NOSIGNAL
  #define MSG_NOSIGNAL 0          // Windows raises no SIGPIPE
#endif

// ── sockets: the Winsock values of the POSIX names call sites spell. <winsock2.h> is not included here; os_win32.cpp
//    includes it BEFORE this header, so there each guard below finds the SDK's own (identical) definition ─────────
#ifndef AF_INET
  #define AF_INET 2
#endif
#ifndef SOCK_STREAM
  #define SOCK_STREAM 1
#endif
#ifndef SOL_SOCKET
  #define SOL_SOCKET 0xffff
#endif
#ifndef SO_REUSEADDR
  #define SO_REUSEADDR 0x0004     // setsockopt maps it to SO_EXCLUSIVEADDRUSE: Winsock's own SO_REUSEADDR lets a second socket steal the port
#endif
#ifndef SO_RCVTIMEO
  #define SO_RCVTIMEO 0x1006
#endif
#ifndef IPPROTO_TCP
  #define IPPROTO_TCP 6
#endif
#ifndef TCP_NODELAY
  #define TCP_NODELAY 0x0001
#endif
#if !defined( _WINSOCK2API_ ) && !defined( htons )
  // glibc defines htons as a function-like macro too; this one is the byte swap Windows' little-endian ABI needs.
  #define htons( x ) static_cast<unsigned short>( ( ( static_cast<unsigned>( x ) & 0xff ) << 8 ) | ( ( static_cast<unsigned>( x ) >> 8 ) & 0xff ) )
#endif

#include "os_win32_logic.h"       // pure logic, no Win32 API: the wait-status decoders the W* macros above name

namespace rw::os
{

// ── types ──────────────────────────────────────────────────────────────────────────────────────────────────
using ssize_t   = std::intptr_t;
using off_t     = std::int64_t;      // the UCRT's off_t is a 32-bit long; every os:: offset is 64-bit
using pid_t     = int;
using mode_t    = unsigned int;
using uid_t     = unsigned int;
using nfds_t    = unsigned long;
using socklen_t = int;
using pthread_t = void*;             // a thread HANDLE: pthread_create's is joined and closed by pthread_join; pthread_self's is the
                                     // current-thread pseudo-handle, which pthread_getname_np is asked about
struct pthread_attr_t                // what os::pthread_attr_* can set: the stack reservation, 0 = the executable's default
{
    std::size_t stackBytes = 0;
};

// The stat fields call sites read, filled by stat/lstat/fstat from one handle query each.
struct stat_t
{
    std::uint64_t st_dev   = 0;      // volume serial number
    std::uint64_t st_ino   = 0;      // file id: BY_HANDLE_FILE_INFORMATION's 64-bit nFileIndexHigh/nFileIndexLow only — a
                                     // ReFS/DevDrive volume's 128-bit FILE_ID_INFO is not queried, so two files whose ids
                                     // differ only in the high 64 bits can collide here (LOW-3, not fixed this release)
    mode_t        st_mode  = 0;      // S_IFREG / S_IFDIR / S_IFLNK / S_IFIFO / S_IFCHR, plus 0700 or 0777-style permission bits
    std::uint32_t st_nlink = 0;
    uid_t         st_uid   = 0;
    std::int64_t  st_size  = 0;
    std::time_t   st_mtime = 0;
    std::time_t   st_ctime = 0;      // the NTFS change time, which is what POSIX calls ctime (not the creation time)
    ::timespec    st_mtim  = {};
    ::timespec    st_ctim  = {};
};
static_assert( requires( const stat_t& st ) { st.st_mode; st.st_size; st.st_mtime; st.st_ctime; st.st_dev; st.st_ino; st.st_uid; } );

struct pollfd
{
    int   fd;
    short events;
    short revents;
};

// The Winsock layouts of the socket structures call sites fill (checked against the SDK's in os_win32.cpp). Declared in
// this namespace, not globally, so they can never collide with <winsock2.h>'s; POSIX spells them os:: too.
struct sockaddr
{
    unsigned short sa_family;
    char           sa_data[ 14 ];
};
struct sockaddr_in
{
    short          sin_family;
    unsigned short sin_port;
    unsigned char  sin_addr[ 4 ];   // Winsock's in_addr is a 4-byte union whose member names are macros; callers only take its address
    char           sin_zero[ 8 ];
};
struct timeval
{
    long tv_sec;
    long tv_usec;
};

// ── descriptors and files ──────────────────────────────────────────────────────────────────────────────────
int     open( const char* path, int flags );
int     open( const char* path, int flags, mode_t mode );
int     openat( int dirFd, const char* path, int flags );   // relative to an O_DIRECTORY descriptor; one component, no separators
int     close( int fd );
ssize_t read( int fd, void* buf, std::size_t count );
ssize_t write( int fd, const void* buf, std::size_t count );
ssize_t pread( int fd, void* buf, std::size_t count, off_t offset );
int     fstat( int fd, stat_t* st );
int     stat( const char* path, stat_t* st );
int     lstat( const char* path, stat_t* st );
int     fcntl( int fd, int cmd );
int     fcntl( int fd, int cmd, int arg );
int     dup( int fd );
int     dup2( int fd, int fd2 );
int     ftruncate( int fd, off_t length );
int     fsync( int fd );
int     fchmod( int fd, mode_t mode );
int     flock( int fd, int operation );
int     pipe( int fds[ 2 ] );
int     poll( pollfd* fds, nfds_t count, int timeoutMs );

// ── streams over descriptors and memory ────────────────────────────────────────────────────────────────────
std::FILE* fdopen( int fd, const char* mode );
int        fileno( std::FILE* stream );
ssize_t    getline( char** line, std::size_t* capacity, std::FILE* stream );
std::FILE* open_memstream( char** buffer, std::size_t* size );
int        fflush( std::FILE* stream );   // publishes a memstream's buffer; any other stream: std::fflush
int        fclose( std::FILE* stream );   // publishes a memstream's buffer; any other stream: std::fclose

// ── paths ──────────────────────────────────────────────────────────────────────────────────────────────────
int   unlink( const char* path );
int   remove( const char* path );
int   rename( const char* from, const char* to );
int   mkdir( const char* path, mode_t mode );
int   chmod( const char* path, mode_t mode );
int   access( const char* path, int mode );
char* realpath( const char* path, char* resolved );
char* getcwd( char* buf, std::size_t size );
int   setenv( const char* name, const char* value, int overwrite );

// rebased_path: the spelling of `path` os::open/os::stat/os::mkdir/… above actually touch, for a caller that must
// hand `path` to something outside os:: performing no such rewrite itself (std::filesystem, a popen'd shell
// command). Git for Windows' "/tmp" is rebased onto the user's real temp directory and a "/dev/null/…" fail-closed
// spelling onto one Win32 cannot create (see os_win32_logic.h's oswin::rebasedProgramPath, which does the actual
// routing and is what NativePath itself calls); any other path — including a path already in its native spelling —
// is returned unchanged. Never fails: an unrebased path is simply `path` itself. #326.
std::string rebased_path( const char* path );

// process start and path intake (see the POSIX branch)
std::string which( std::string_view command );   // PATH is ';'-separated; PATHEXT names; relative entries (the current directory) are never searched
// Git Bash's MSYS `which` never prints ".exe" — always false here, unlike the POSIX branch (see the POSIX branch
// above for the full contract); no Windows API call needed, so this stays inline rather than in os_win32.cpp.
[[gnu::always_inline]] inline bool which_spelling_is_exact() { return false; }
// path_prepend_hint (see the POSIX branch): PowerShell's spelling, native separators
inline std::string path_prepend_hint( std::string_view dir ) { return oswin::powerShellPathPrependHint( dir ); }
void init_process( int& argc, char**& argv );
void normalize_path_arg( char* text );

// path grammar (see the POSIX branch): pure logic over the program's spelling, inline on every platform
[[gnu::always_inline]] inline bool path_is_absolute( const std::string& path )
{
    return oswin::isAbsoluteNativePath( path ) || ( !path.empty() && path.front() == '/' );
}
[[gnu::always_inline]] inline bool path_is_root( const std::string& path )
{
    return path == "/" || ( path.size() == 3 && oswin::isDriveLetter( path[ 0 ] ) && path[ 1 ] == ':' && path[ 2 ] == '/' );
}
template<class FsPath>
[[gnu::always_inline]] inline std::string program_path( const FsPath& path ) { return path.generic_string(); }
// path_arg (see the POSIX branch for what it is for): here path::value_type is wchar_t, so the path's own c_str() is
// NOT a `const char*` and cannot reach the calls above. generic_string() narrows the wide native form to the same
// UTF-8 '/'-separated spelling program_path() produces and every os:: body takes, so the two never disagree about
// what a path IS. It returns by value: the caller's `.c_str()` names that temporary, which the language keeps alive
// to the end of the full expression the os:: call is part of — the only shape any call site uses.
template<class FsPath>
[[gnu::always_inline]] inline std::string path_arg( const FsPath& path ) { return path.generic_string(); }

// field reads, not calls: inline on every platform
[[gnu::always_inline]] inline const ::timespec& st_mtim( const stat_t& st ) { return st.st_mtim; }
[[gnu::always_inline]] inline const ::timespec& st_ctim( const stat_t& st ) { return st.st_ctim; }

int exepath( char* buf, std::size_t bufCount );

// ── time ───────────────────────────────────────────────────────────────────────────────────────────────────
int      nanosleep( const ::timespec* request, ::timespec* remaining );
std::tm* localtime_r( const std::time_t* time, std::tm* result );

// ── processes ──────────────────────────────────────────────────────────────────────────────────────────────
pid_t      getpid();
uid_t      getuid();
int        kill( pid_t pid, int sig );
pid_t      waitpid( pid_t pid, int* status, int options );
std::FILE* popen( const char* command, const char* mode );
int        pclose( std::FILE* stream );
int        system( const char* command );
pid_t      spawn_sh( const std::string& command, const int pipeFds[ 2 ] );

// ── threads ────────────────────────────────────────────────────────────────────────────────────────────────
pthread_t     pthread_self();
std::uint64_t gettid();
int           pthread_main_np();
int           pthread_getname_np( pthread_t thread, char* name, std::size_t nameCount );
int           pthread_attr_init( pthread_attr_t* attr );
int           pthread_attr_setstacksize( pthread_attr_t* attr, std::size_t stackBytes );
int           pthread_attr_destroy( pthread_attr_t* attr );
int           pthread_create( pthread_t* thread, const pthread_attr_t* attr, void* (*start)( void* ), void* arg );
int           pthread_join( pthread_t thread, void** valueOut );

// ── sockets ────────────────────────────────────────────────────────────────────────────────────────────────
int     socket( int domain, int type, int protocol );
int     setsockopt( int fd, int level, int name, const void* value, socklen_t length );
int     bind( int fd, const sockaddr* address, socklen_t length );
int     listen( int fd, int backlog );
int     accept( int fd, sockaddr* address, socklen_t* length );
ssize_t recv( int fd, void* buf, std::size_t count, int flags );
ssize_t send( int fd, const void* buf, std::size_t count, int flags );
int     inet_pton( int family, const char* text, void* address );
int     setsockopt_nosigpipe( int fd, const void* value, socklen_t length );

// ── directory watching: ReadDirectoryChangesW behind the same kevent-shaped calls (os_win32.cpp says how) ──────────
struct dirwatch_event
{
    int ident;   // the directory descriptor the event is for
};
[[gnu::always_inline]] inline constexpr bool dirwatch_available() { return true; }
int dirwatch_open();
int dirwatch_add( int watchFd, int dirFd, dirwatch_event* change );
int dirwatch_poll( int watchFd, dirwatch_event* events, int eventCount, const ::timespec* timeout );

}   // namespace rw::os

#endif
