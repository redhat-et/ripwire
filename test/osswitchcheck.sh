#!/usr/bin/env bash
# osswitchcheck.sh — src/infra/os.h is the ONE file in src/ that asks which operating system it is compiled for.
#
# WHY THIS GATE EXISTS
#   Operating-system differences used to live wherever a call needed one: `#if defined( __APPLE__ )` beside a
#   stat field, `#ifdef MSG_NOSIGNAL` beside a send, a kqueue watcher behind a project macro, and a POSIX header
#   at the top of every file that made a system call. Each site compiled, and each was correct for the two
#   platforms it had been written against. What nothing could see was the TOTAL: a port to a third platform
#   meant finding every such site by reading, and a port that took the other road — force-including a compat
#   header whose object-like macros rename `open`, `rename` and `fclose` in every translation unit — compiled
#   just as quietly while changing what `std::fclose` means in code nobody touched.
#
#   So the property is asserted mechanically, over the whole tree, and every arm names what it refuses:
#
#     (A)  no OS-conditional preprocessor name (`_WIN32`, `__APPLE__`, `__linux__`, `__FreeBSD__`, …) in any
#          directive outside os.h;
#     (A') no OS PROXY name in a directive outside os.h either — a feature macro that is really an OS test
#          (`MSG_NOSIGNAL`, `SO_NOSIGPIPE`, `O_NOFOLLOW`, the kqueue seam, `_GNU_SOURCE`, `__has_include` of a
#          system header). Arm (A) cannot see these, and they are how an OS switch survives a rename;
#     (B)  no POSIX or Windows system header (`<unistd.h>`, `<sys/*.h>`, `<windows.h>`, …) included outside
#          os.h;
#     (C)  no force-include (`-include`, `-imacros`, `/FI`) in any CMake file or workflow, no compat include
#          directory, and no header under src/ that mirrors a system header's path;
#     (D)  no macro, object-like OR function-like, named after a libc/POSIX function anywhere in src/ (os.h
#          included), and no CMake compile definition of one: a macro that renames `open` renames it in every
#          file that includes it, including `std::` spellings;
#     (E)  os.h's POSIX branch and Windows branch declare the same function names, so a POSIX-only addition
#          cannot silently break the Windows build. (While the Windows branch was a placeholder `#error` the arm
#          reported itself disabled; it turned itself on when that branch declared its first function.) Its
#          comparator also runs against a planted pair on every run;
#     (F)  no raw POSIX/libc call with Windows-divergent behaviour outside os.h — `::open(`, `std::rename(`,
#          an unqualified `popen(` — and no raw POSIX type (`struct stat`, `ssize_t`, `pid_t`) at a call site;
#     (G)  no platform FACT (`os::kWindows`, `os::kApple`, `os::kLinux`, `os::kTarget`, `os::Target`) named
#          outside os.h, and namespace `os` is not reopened elsewhere. A call site never asks which OS it is
#          on; it calls the os:: function that says what it needs. The fact list is READ from os.h, so a new
#          fact is covered the moment it is declared.
#
# THE ALLOWLIST is a table in the Python below, one row per file, naming the arms it is exempt from and why.
#   Two rows: src/infra/os_win32.cpp (arms A', B, F, G) — os.h's own Windows bodies, the one translation unit that sees
#   <windows.h>; and src/infra/profilePmc.h (arms A, B, F) — the self-profiler's hardware-counter backends. A row that no longer exempts anything is itself a FAIL, so the table cannot outlive its reason.
#
# NON-VACUITY (CONTRIBUTING.md §2). Every arm runs its detector over a planted fixture that violates it and
#   must FIRE, and over a clean fixture and must stay SILENT; the scan must reach real files; os.h must exist
#   and declare its facts. Directives are read as LOGICAL lines (backslash continuations joined) with comments
#   removed, and calls/types are read with comments and string literals blanked, so a sentence in a comment
#   that names `__APPLE__` or `::open(` is not a hit and a `#if` split over two lines is not a miss.
#
# Usage:  bash test/osswitchcheck.sh            (OSSWITCH_ROOT=<checkout> scans another tree, e.g. a PR head;
#                                               OSSWITCH_VERBOSE=1 lists every violation instead of the first 14)
# Binds no ripwire binary. Exits non-zero on any FAIL; prints ALL PASS on success.

set -u
ROOT="${OSSWITCH_ROOT:-$( cd "$( dirname "$0" )/.." && pwd )}"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "osswitchcheck: ROOT=$ROOT"
if [ -d "$ROOT/src" ]; then
    ok "scan root has a src/ tree"
else
    no "scan root $ROOT has no src/ — every arm below would pass while measuring nothing"
fi

python3 - "$ROOT" <<'PY' || fail=1
import bisect, os, re, sys, tempfile, shutil

ROOT = sys.argv[1]
HOME = "src/infra/os.h"
bad  = 0
def ok( m ): print( "  PASS  %s" % m )
def no( m ):
    global bad; bad = 1; print( "  FAIL  %s" % m )

# ── the allowlist: path -> ( arms, reason ). A row that exempts nothing any more is reported stale. ──────────
ALLOW = {
    "src/infra/os_win32.cpp": ( { "A'", "B", "F", "G" },
        "os.h's Windows bodies, out of line: the ONE translation unit that includes <windows.h>/<winsock2.h> (arm B) after "
        "WIN32_LEAN_AND_MEAN/NOMINMAX (arm A'), calls "
        "the Win32 and Winsock API by its global names inside rw::os's own definitions (arm F), and reopens namespace rw::os "
        "to define what os.h declares (arm G). Compiled only for Windows; no other file may do any of the three" ),
    "src/infra/platform.h": ( { "H" },
        "THE compiler-extension seam: the one file that may spell __builtin_memcpy, __attribute__ and an inline-asm "
        "barrier, each behind a __clang__/__GNUC__ vs MSVC arm, so every other file names a macro instead" ),
    "src/infra/Diagnostics.h": ( { "H" },
        "the seam's lower half. platform.h INCLUDES this header and this header includes nothing of ours (it stays "
        "library-free so a standalone harness can compile it alone), so it cannot use platform.h's macros and owns "
        "the six its own checks need in its S1c, plus the benchmark barriers' no-inline-asm fallback" ),
    "src/infra/enumcount.h": ( { "H" },
        "the enum-name probe reads __PRETTY_FUNCTION__'s TEXT to decide whether a value spells a declared "
        "enumerator — it is parsing the string, not printing it, so _PRETTYFUNCTION_ would not serve: the parser "
        "is written against Clang's exact spelling. Behind `#if defined( __clang__ )`, with an #else that sets "
        "kEnumCountProbed = false and degrades, so MSVC never reaches the line" ),
    "src/infra/radixSort.h": ( { "H" },
        "the SIMD backend choice, in a PREPROCESSOR condition where std::endian cannot be spelled (it is a "
        "constant expression, not a macro). Already correct where the macro does not exist: the condition leads "
        "with `!defined( __BYTE_ORDER__ )`, so MSVC takes the little-endian answer for NEON and otherwise falls "
        "to the _M_X64 arm. The absence IS the portability guard" ),
    "src/structlayout.h": ( { "H" },
        "the two lines that DEFINE the RIPWIRE_LAYOUT_TU fallback — `#if defined( __BASE_FILE__ )` and the "
        "#define that uses it. This is that spelling's own seam: the header #errors rather than guess when the "
        "extension is absent, and CMake supplies the value for the front end that needs it" ),
    "src/infra/profileScope.h": ( { "H" },
        "three `mrs` reads of the ARM64 cycle counter, inside `#if defined( __aarch64__ )`. An architecture is not a "
        "compiler: MSVC never reaches them (every other target takes the std::chrono arm), so they block no front end "
        "and there is no portable spelling of a register read to route them through" ),
    "src/infra/profilePmc.h": ( { "A", "B", "F" },
        "the opt-in self-profiler's hardware-counter backends: dlopen of Apple's private kperf frameworks and Linux "
        "perf_event_open (syscall/ioctl/read on a perf descriptor) — an undocumented ABI with no POSIX shape and no "
        "Windows counterpart, compiled only into PROFILE_ENABLED builds" ),
}

# ── name tables ─────────────────────────────────────────────────────────────────────────────────────────────
OS_NAMES = re.compile( r'\b(?:_WIN32|_WIN64|_MSC_VER|__MINGW32__|__MINGW64__|__CYGWIN__|__APPLE__|__MACH__|TARGET_OS_\w+|'
                       r'__linux__|__linux|linux|__gnu_linux__|__ANDROID__|__unix__|__unix|unix|__FreeBSD__|__OpenBSD__|'
                       r'__NetBSD__|__DragonFly__|__sun|__HAIKU__|__EMSCRIPTEN__|__GLIBC__|__BIONIC__|_AIX)\b' )
PROXY_NAMES = re.compile( r'\b(?:RIPWIRE_HAS_KQUEUE|RW_OS_HAS_KQUEUE|MSG_NOSIGNAL|SO_NOSIGPIPE|O_NOFOLLOW|O_CLOEXEC|O_BINARY|'
                          r'F_FULLFSYNC|SOCK_CLOEXEC|EVFILT_VNODE|SYS_gettid|PATH_MAX|_POSIX_VERSION|_POSIX_C_SOURCE|'
                          r'_XOPEN_SOURCE|_GNU_SOURCE|_DEFAULT_SOURCE|_BSD_SOURCE|_DARWIN_C_SOURCE|__DARWIN_C_LEVEL|'
                          r'WIN32_LEAN_AND_MEAN|NOMINMAX)\b' )

POSIX_HEADER_FILES = set( """unistd fcntl poll pthread spawn dirent dlfcn netdb termios pwd grp libgen fnmatch glob wordexp sched
    semaphore syslog utime strings ifaddrs libproc crt_externs execinfo paths err sysexits ucontext aio mqueue ftw utmpx
    langinfo iconv regex alloca malloc features endian byteswap elf link mntent shadow pty resolv util libutil copyfile
    removefile getopt xlocale""".split() )
POSIX_HEADER_DIRS = ( "sys/", "netinet/", "netinet6/", "arpa/", "net/", "mach/", "mach-o/", "linux/", "asm/", "asm-generic/",
                      "bits/", "gnu/", "machine/", "libkern/", "os/", "dispatch/", "CoreFoundation/", "CoreServices/",
                      "Security/", "malloc/", "xlocale/", "bsm/" )
WIN_HEADER_FILES = set( """windows winsock winsock2 ws2tcpip ws2def mswsock winbase windef winnt winerror winuser winioctl winternl
    ntstatus ntdef io direct process share aclapi sddl shlobj shlwapi shellapi psapi tlhelp32 bcrypt dbghelp userenv
    lmcons objbase combaseapi crtdbg conio dos""".split() )

def is_system_header( name ):
    n = name.strip()
    base = n[ :-2 ] if n.endswith( ".h" ) else None
    if base is not None and "/" not in n and ( base in POSIX_HEADER_FILES or base.lower() in WIN_HEADER_FILES
                                                 or re.fullmatch( r'\w+api(?:set)?', base.lower() ) ):
        return True
    return any( n.startswith( d ) for d in POSIX_HEADER_DIRS )

# (F) POSIX/libc functions whose behaviour or existence differs on Windows. getenv (ISO C, portable), the stdio
# family (fopen/fclose/fseek: a D2 decision after the UTF-8 path probe), std::tmpfile and htons (a function-like
# macro under glibc -O2, so it cannot be wrapped by name) are deliberately not listed.
POSIX_FUNCS = """open close read write lstat fstat stat fcntl pipe dup dup2 fork vfork execl execlp execle execv execvp execve
    execvpe waitpid wait kill killpg poll select socket bind listen accept connect setsockopt getsockopt shutdown send recv
    sendto recvfrom flock lockf mkstemp mkdtemp rename realpath readlink symlink link unlink rmdir mkdir mkfifo chmod fchmod
    chown fchown access faccessat getpid getppid getuid geteuid getgid setsid setpgid isatty fileno ftruncate truncate fsync
    fdatasync mmap munmap sigaction sigprocmask pthread_sigmask clock_gettime localtime_r gmtime_r pread pwrite lseek popen
    pclose getcwd chdir setenv unsetenv nanosleep usleep sleep _exit inet_pton inet_ntop open_memstream getline getdelim
    fdopen opendir readdir closedir umask kqueue kevent inotify_init inotify_add_watch posix_spawn posix_spawnp system
    remove syscall dlopen dlsym dlclose ioctl statvfs pthread_self pthread_threadid_np pthread_main_np pthread_getname_np
    pthread_setname_np _NSGetExecutablePath""".split()
FUNC_ALT = "|".join( sorted( POSIX_FUNCS, key=len, reverse=True ) )
STD_QUALIFIED = { "rename", "remove", "system" }        # declared in namespace std by <cstdio>/<cstdlib>
POSIX_TYPES_BARE = r'ssize_t|pid_t|off_t|mode_t|uid_t|gid_t|nfds_t|socklen_t|pthread_t|useconds_t|suseconds_t|ino_t|dev_t|nlink_t|blksize_t|blkcnt_t|clockid_t|sigset_t'
POSIX_STRUCTS   = r'stat|pollfd|kevent|kevent64_s|flock|dirent|rusage|rlimit|passwd|group|utsname|statvfs|statfs|termios|sigaction|sockaddr_un|ifaddrs|addrinfo'
# (D) the libc names a macro must never take: every (F) function plus the stdio/stdlib calls a compat layer renames.
LIBC_MACRO_NAMES = set( POSIX_FUNCS ) | set( """fopen fclose fflush fread fwrite fseek ftell fseeko ftello fgets fputs fprintf
    printf snprintf sprintf vsnprintf getc putc freopen tmpfile getenv malloc free calloc realloc strdup strerror exit abort
    atexit time localtime gmtime mktime strftime""".split() )
CALL_KEYWORDS = { "return", "else", "do", "case", "throw", "co_return", "co_yield", "not", "and", "or", "xor", "new", "delete",
                  "sizeof", "decltype", "typeid", "noexcept", "alignof", "if", "while", "for", "switch", "static_assert" }

# ── the reader ──────────────────────────────────────────────────────────────────────────────────────────────
_TOKEN = re.compile( r'//|/\*|(?:u8|u|U|L)?R"(?P<d>[^()\\\s]{0,16})\(|"|\'' )
_stripped = {}
def strip( text, keep_strings ):
    """Blank comments (and, unless keep_strings, string/char literals and raw strings), keeping every newline."""
    key = ( text, keep_strings )
    if key in _stripped: return _stripped[key]
    blank = lambda t: re.sub( r'[^\n]', " ", t )
    out = []; i = 0; n = len( text )
    while True:
        m = _TOKEN.search( text, i )
        if not m:
            out.append( text[i:] ); break
        s = m.start(); tok = m.group( 0 ); out.append( text[i:s] )
        if tok == "//":
            j = text.find( "\n", s ); j = n if j < 0 else j
            out.append( " " * ( j - s ) ); i = j
        elif tok == "/*":
            j = text.find( "*/", s + 2 ); j = n if j < 0 else j + 2
            out.append( blank( text[s:j] ) ); i = j
        elif m.group( "d" ) is not None:
            if s > 0 and ( text[s - 1].isalnum() or text[s - 1] == "_" ):
                out.append( text[s] ); i = s + 1; continue        # an identifier ending in R, then an ordinary literal
            delim = ")" + m.group( "d" ) + '"'
            j = text.find( delim, m.end() ); j = n if j < 0 else j + len( delim )
            out.append( text[s:j] if keep_strings else blank( text[s:j] ) ); i = j
        else:
            if tok == "'" and s > 0 and text[s - 1].isalnum():
                out.append( tok ); i = s + 1; continue            # a digit separator, 1'000
            j = s + 1
            while j < n and text[j] != tok and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            closed = j < n and text[j] == tok
            j = j + 1 if closed else min( j, n )                  # an unterminated literal stops before its newline
            out.append( text[s:j] if keep_strings else tok + blank( text[s + 1:j - 1 if closed else j] ) + ( tok if closed else "" ) ); i = j
    result = "".join( out ); _stripped[key] = result
    assert len( result ) == len( text ), "strip() must preserve every offset"
    return result

def directives( code ):
    """(line number, logical directive text) for every preprocessor line, continuations joined."""
    lines = code.split( "\n" ); i = 0
    while i < len( lines ):
        if re.match( r'\s*#', lines[i] ):
            start = i; parts = [ lines[i] ]
            while parts[-1].rstrip().endswith( "\\" ) and i + 1 < len( lines ):
                parts[-1] = parts[-1].rstrip()[ :-1 ]; i += 1; parts.append( lines[i] )
            yield start + 1, " ".join( p.strip() for p in parts )
        i += 1

def non_directive_code( code ):
    """The code with every preprocessor line (and its continuations) blanked to spaces — calls and types live
    here. Offsets are preserved, so a position in this text is a position in the file."""
    lines = code.split( "\n" ); out = []; cont = False
    for ln in lines:
        if cont or re.match( r'\s*#', ln ):
            cont = ln.rstrip().endswith( "\\" ); out.append( " " * len( ln ) ); continue
        out.append( ln )
    return "\n".join( out )

_newlines = {}
def line_of( text, pos ):
    if text not in _newlines: _newlines[text] = [ m.start() for m in re.finditer( "\n", text ) ]
    return bisect.bisect_left( _newlines[text], pos ) + 1

# ── detectors: each takes ( relpath, raw text ) and returns [ "path:line: what" ] ────────────────────────────
def detect_A( rel, raw ):
    hits = []
    for ln, d in directives( strip( raw, False ) ):
        m = re.match( r'#\s*(if|ifdef|ifndef|elif|elifdef|elifndef|define|undef)\b(.*)', d )
        if m and OS_NAMES.search( m.group( 2 ) ):
            hits.append( "%s:%d: #%s names %s" % ( rel, ln, m.group( 1 ), OS_NAMES.search( m.group( 2 ) ).group( 0 ) ) )
    return hits

def detect_A2( rel, raw ):
    hits = []
    for ln, d in directives( strip( raw, True ) ):
        m = re.match( r'#\s*(if|ifdef|ifndef|elif|elifdef|elifndef|define|undef)\b(.*)', d )
        if not m: continue
        body = strip( m.group( 2 ), False ) if m.group( 1 ) in ( "define", "undef" ) else m.group( 2 )
        p = PROXY_NAMES.search( body )
        if p:
            hits.append( "%s:%d: #%s names the OS proxy %s" % ( rel, ln, m.group( 1 ), p.group( 0 ) ) ); continue
        for h in re.finditer( r'__has_include(?:_next)?\s*\(\s*[<"]([^>"]+)[>"]\s*\)', m.group( 2 ) ):
            if is_system_header( h.group( 1 ) ):
                hits.append( "%s:%d: #%s probes the system header <%s>" % ( rel, ln, m.group( 1 ), h.group( 1 ) ) ); break
    return hits

def detect_B( rel, raw, root ):
    hits = []
    for ln, d in directives( strip( raw, True ) ):
        m = re.match( r'#\s*(?:include|include_next|import)\s*([<"])([^>"]+)[>"]', d )
        if not m or not is_system_header( m.group( 2 ) ): continue
        if m.group( 1 ) == '"':
            here = os.path.dirname( os.path.join( root, rel ) )
            if any( os.path.exists( os.path.join( b, m.group( 2 ) ) ) for b in ( here, os.path.join( root, "src" ),
                    os.path.join( root, "src", "infra" ), os.path.join( root, "third_party" ) ) ):
                continue                                          # a first-party header that happens to share the name
        hits.append( "%s:%d: includes %s%s%s" % ( rel, ln, m.group( 1 ), m.group( 2 ), ">" if m.group( 1 ) == "<" else '"' ) )
    return hits

FORCE_INCLUDE = re.compile( r'(?<![\w./-])(?:-include(?:-pch)?|-imacros|[/-]FI(?!XED))(?![\w-]*=)' )
def cmake_code( raw ):
    out = []
    for ln in raw.split( "\n" ):
        q = False; cut = len( ln )
        for i, c in enumerate( ln ):
            if c == '"': q = not q
            elif c == "#" and not q: cut = i; break
        out.append( ln[ :cut ] )
    return "\n".join( out )

def detect_C_text( rel, raw, yaml=False ):
    code = cmake_code( raw )
    hits = []
    for m in FORCE_INCLUDE.finditer( code ):
        hits.append( "%s:%d: force-include flag %s" % ( rel, line_of( code, m.start() ), m.group( 0 ) ) )
    if not yaml:
        for m in re.finditer( r'include_directories\s*\(([^)]*)\)', code, re.S ):
            if re.search( r'\bcompat\b', m.group( 1 ) ):
                hits.append( "%s:%d: an include directory named compat" % ( rel, line_of( code, m.start() ) ) )
    return hits

def detect_C_tree( root ):
    hits = []
    if os.path.isdir( os.path.join( root, "src", "infra", "compat" ) ):
        hits.append( "src/infra/compat/: a compat header directory exists" )
    for dp, _dn, fn in os.walk( os.path.join( root, "src" ) ):
        for f in fn:
            if not f.endswith( ".h" ): continue
            rel = os.path.relpath( os.path.join( dp, f ), root )
            parent = os.path.basename( dp )
            if f[ :-2 ] in POSIX_HEADER_FILES or f[ :-2 ].lower() in WIN_HEADER_FILES or ( parent + "/" ) in POSIX_HEADER_DIRS:
                hits.append( "%s: a first-party header that mirrors a system header's path" % rel )
    return sorted( hits )

def detect_D( rel, raw ):
    hits = []
    for ln, d in directives( strip( raw, False ) ):
        m = re.match( r'#\s*(define|undef)\s+([A-Za-z_]\w*)', d )
        if m and m.group( 2 ) in LIBC_MACRO_NAMES:
            hits.append( "%s:%d: #%s %s renames a libc function in every file that includes it" % ( rel, ln, m.group( 1 ), m.group( 2 ) ) )
    return hits

def detect_D_cmake( rel, raw ):
    code = cmake_code( raw ); hits = []
    for m in re.finditer( r'(?<![\w-])-D\s*([A-Za-z_]\w*)', code ):
        if m.group( 1 ) in LIBC_MACRO_NAMES:
            hits.append( "%s:%d: -D%s" % ( rel, line_of( code, m.start() ), m.group( 1 ) ) )
    for m in re.finditer( r'(?:add|target)_compile_definitions\s*\(([^)]*)\)', code, re.S ):
        for tok in re.findall( r'[A-Za-z_]\w*(?==|[\s")]|$)', m.group( 1 ) ):
            if tok in LIBC_MACRO_NAMES:
                hits.append( "%s:%d: compile definition %s" % ( rel, line_of( code, m.start() ), tok ) )
    return hits

def top_level_args( code, open_paren ):
    depth = 0; commas = 0; i = open_paren
    while i < len( code ):
        c = code[i]
        if c in "([{": depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0: return commas + 1 if code[ open_paren + 1:i ].strip() else 0
        elif c == "," and depth == 1: commas += 1
        i += 1
    return -1

def prev_token( code, pos ):
    k = pos - 1
    while k >= 0 and code[k] in " \t\n": k -= 1
    if k < 0: return ""
    if code[k] == "_" or code[k].isalnum():
        j = k
        while j >= 0 and ( code[j] == "_" or code[j].isalnum() ): j -= 1
        return code[ j + 1:k + 1 ]
    return code[ max( 0, k - 1 ):k + 1 ]

def is_declaration_head( code, pos ):
    t = prev_token( code, pos )
    if not t: return False
    if t[-1] == "_" or t[-1].isalnum():
        return t not in CALL_KEYWORDS and not t.isdigit()
    return t[-1] in "*&>" and t not in ( "&&", "->", ">>" )

def matching_close( code, openPos, openCh, closeCh ):
    depth, j = 0, openPos
    while j < len( code ):
        if code[j] == openCh: depth += 1
        elif code[j] == closeCh:
            depth -= 1
            if depth == 0: return j
        j += 1
    return None

def enclosing_block( code, pos ):
    """The [start,end] span a declaration AT pos shadows an unqualified call within: the function body when pos
    sits inside that function's own parenthesized parameter list (a callable parameter, `Accept accept`), else
    the nearest enclosing { ... } (a class/struct member, a local), else None — no enclosing brace at all, a
    genuine file-scope declaration, which really does shadow the whole file (this scanner does not track
    namespaces, so two same-named globals in different namespaces are not told apart either way)."""
    i, pdepth, parenStart = pos - 1, 0, None
    while i >= 0:
        c = code[i]
        if c == ")":
            pdepth += 1
        elif c == "(":
            if pdepth == 0:
                parenStart = i
                break
            pdepth -= 1
        elif c in "{}":
            break               # a brace first: pos is not inside an enclosing parameter list
        i -= 1
    if parenStart is not None:
        close = matching_close( code, parenStart, "(", ")" )
        if close is not None:
            j = close + 1
            while j < len( code ) and code[j] in " \t\r\n": j += 1
            if j < len( code ) and code[j] == "{":
                end = matching_close( code, j, "{", "}" )
                if end is not None:
                    return ( j, end )
    depth, i = 0, pos - 1
    while i >= 0:
        c = code[i]
        if c == "}":
            depth += 1
        elif c == "{":
            if depth == 0:
                end = matching_close( code, i, "{", "}" )
                return ( i, end ) if end is not None else ( i, len( code ) )
            depth -= 1
        i -= 1
    return None

def detect_F( rel, raw ):
    code = non_directive_code( strip( raw, False ) )
    hits = []
    # F1: global-qualified POSIX calls
    for m in re.finditer( r'(?<![\w:>])::\s*(%s)\s*\(' % FUNC_ALT, code ):
        hits.append( "%s:%d: ::%s(" % ( rel, line_of( code, m.start() ), m.group( 1 ) ) )
    # F2: std::rename / std::system / single-argument std::remove (the C stdio call, not the algorithm)
    for m in re.finditer( r'\bstd\s*::\s*(rename|remove|system)\s*\(', code ):
        if m.group( 1 ) == "remove" and top_level_args( code, m.end() - 1 ) != 1: continue
        hits.append( "%s:%d: std::%s(" % ( rel, line_of( code, m.start() ), m.group( 1 ) ) )
    # F3: unqualified POSIX calls — not a member access, not qualified, not a declaration, and not a name the
    #     ENCLOSING SCOPE declares (a parser's accept(), a class's own write(), a callable parameter named accept).
    #     Scoped, not file-wide: a struct's own `read` member must not hide an unrelated raw `read(fd, buf, n)`
    #     elsewhere in the same file (CodeRabbit #290 — a name match is not symbol resolution). declared_at
    #     answers per call site instead of building one file-wide name set.
    declared = []   # [(name, scope)]; scope is enclosing_block(...) at the declaration, or None (true file scope)
    for m in re.finditer( r'\b(%s)\s*([(),;={])' % FUNC_ALT, code ):
        before = code[ max( 0, m.start() - 2 ):m.start() ]
        if before.endswith( ( ".", "->", "::" ) ) or re.search( r'::\s*$', code[ max( 0, m.start() - 4 ):m.start() ] ): continue
        if is_declaration_head( code, m.start() ):
            declared.append( ( m.group( 1 ), enclosing_block( code, m.start() ) ) )
    def declared_at( name, pos ):
        return any( n == name and ( scope is None or scope[0] <= pos <= scope[1] ) for n, scope in declared )
    for m in re.finditer( r'(?<![\w.:>~])(%s)\s*\(' % FUNC_ALT, code ):
        name = m.group( 1 )
        if declared_at( name, m.start() ) or is_declaration_head( code, m.start() ): continue
        if code[ max( 0, m.start() - 2 ):m.start() ].endswith( "->" ): continue
        hits.append( "%s:%d: %s(" % ( rel, line_of( code, m.start() ), name ) )
    # F4: raw POSIX types at a call site
    for m in re.finditer( r'\bstruct\s+(%s)\b' % POSIX_STRUCTS, code ):
        hits.append( "%s:%d: struct %s" % ( rel, line_of( code, m.start() ), m.group( 1 ) ) )
    for m in re.finditer( r'((?:\b\w+\s*)?::\s*)?\b(%s)\b' % POSIX_TYPES_BARE, code ):
        q = ( m.group( 1 ) or "" ).replace( " ", "" )
        if q.endswith( "os::" ): continue
        hits.append( "%s:%d: %s%s" % ( rel, line_of( code, m.start() ), q, m.group( 2 ) ) )
    return sorted( set( hits ), key=lambda h: ( int( h.split( ":" )[1] ), h ) )

# (H) a GCC/Clang language extension that cl.exe REFUSES. These are the spellings that are a hard compile ERROR
# on MSVC, not a warning, so a new one silently un-builds the Windows leg. What to write instead:
#   __builtin_*, asm volatile, __attribute__  -> the seam macro in infra/platform.h (or Diagnostics.h S1c below it)
#   __PRETTY_FUNCTION__                       -> _PRETTYFUNCTION_            (Diagnostics.h S1b)
#   __BASE_FILE__                             -> RIPWIRE_LAYOUT_TU           (CMake supplies it; structlayout.h)
#   __BYTE_ORDER__ / __ORDER_*_ENDIAN__       -> std::endian                 (<bit>, C++20)
#   __int128 / unsigned __int128              -> a 64-bit formulation        (MSVC has no 128-bit integer on x64)
# The last four were each found by a CI round AFTER the first three were fixed, which is why the arm names
# spellings rather than a category: the category is "whatever cl.exe refuses", and only the leg can enumerate it.
# The seam pair (infra/platform.h, infra/Diagnostics.h) owns every spelling and is allowlisted; everything else
# calls the seam's macro. `[[gnu::…]]` is deliberately NOT refused here: MSVC ignores an unknown attribute with
# C5030, a warning, so those sites still build — routing them through ALWAYS_INLINE is its own change with its
# own arm, and folding them in here would red this gate on 104 pre-existing sites that break nothing.
# `\basm\b` is the BARE keyword, not `asm\s+volatile`: cl.exe refuses `asm( "nop" );` exactly as it refuses the
# volatile form, so pinning the qualifier let the unqualified spelling through. The word boundaries are what keep
# it from over-firing — `__asm__`, `wasm`, `asm_buf` and `assembler` all fail \b — and comments and string
# literals are gone before the scan (`strip( raw, keep_strings=False )`), which is why slice.h's C++ keyword
# table listing "asm" is not a hit. The whole tree was re-scanned after widening it: no new site.
EXTENSION_RE = re.compile( r'(__builtin_\w+|__attribute__|\basm\b|__asm__|__PRETTY_FUNCTION__|__BASE_FILE__'
                           r'|__BYTE_ORDER__|__ORDER_[A-Z]+_ENDIAN__|\bunsigned __int128\b|\b__int128\b'
                           r'|__restrict__|__extension__|__typeof__)' )

def has_builtin_arg_spans( code ):
    """The character span of each `__has_builtin( … )` ARGUMENT — nothing else.

    A feature TEST is not a use, but the carve-out must be no wider than the parentheses it belongs to. Reading a
    fixed window of text BEFORE a match sheltered every extension within that window, so a genuine violation on
    the same line as a guard — or on the next one — inherited the exemption it had no claim to. The spans are
    paren-matched so a nested `(` inside the argument cannot end one early."""
    spans = []
    for m in re.finditer( r'__has_builtin\s*\(', code ):
        i = m.end(); depth = 1
        while i < len( code ) and depth:
            if code[i] == "(": depth += 1
            elif code[i] == ")": depth -= 1
            i += 1
        spans.append( ( m.end(), i - 1 if depth == 0 else len( code ) ) )   # unterminated: to end of file, never wider
    return spans

def detect_H( rel, raw ):
    hits = []
    code = strip( raw, keep_strings=False )
    spans = has_builtin_arg_spans( code )
    for m in EXTENSION_RE.finditer( code ):
        # __has_builtin( __builtin_x ) is a portable feature TEST, not a use: it is how a file asks whether the
        # extension exists before spelling it, which is the behaviour this arm wants rather than one it refuses.
        # The exemption reaches the ARGUMENT and stops there.
        if any( start <= m.start() and m.end() <= end for start, end in spans ):
            continue
        hits.append( "%s:%d: %s outside the compiler-extension seam" % ( rel, line_of( code, m.start() ), m.group( 1 ) ) )
    return hits

def facts_of( os_raw ):
    code = strip( os_raw, False )
    names = set( re.findall( r'inline\s+constexpr\s+(?:bool|Target)\s+(k[A-Z]\w*)', code ) )
    if re.search( r'enum\s+class\s+Target\b', code ): names.add( "Target" )
    return names

def detect_G( rel, raw, facts ):
    if not facts: return []
    code = strip( raw, False ); alt = "|".join( sorted( facts, key=len, reverse=True ) ); hits = []
    for m in re.finditer( r'\b(?:rw\s*::\s*)?os\s*::\s*(%s)\b' % alt, code ):
        hits.append( "%s:%d: os::%s" % ( rel, line_of( code, m.start() ), m.group( 1 ) ) )
    for m in re.finditer( r'\busing\s+namespace\s+(?:rw\s*::\s*)?os\b|\busing\s+(?:rw\s*::\s*)?os\s*::\s*(?:%s)\b|\bnamespace\s+(?:rw\s*::\s*)?os\b' % alt, code ):
        hits.append( "%s:%d: %s — namespace os is opened or imported outside os.h" % ( rel, line_of( code, m.start() ), " ".join( m.group( 0 ).split() ) ) )
    return hits

DECL_HEAD = re.compile( r'^(?:\[\[[^\]]*\]\]\s*)*(?:(?:inline|static|extern|constexpr|const)\s+)*(?!return\b|using\b|typedef\b|namespace\b|enum\b|struct\b|class\b)'
                        r'[\w:<>]+(?:\s*[*&])*\s+[*&]?\s*(\w+)\s*\(', re.M )
def branch_functions( os_raw ):
    """( POSIX names, Windows names, Windows-is-placeholder ) from os.h's top-level `#if !defined( _WIN32 )` split,
    or None when the split is not there."""
    code = strip( os_raw, False ); lines = code.split( "\n" )
    start = None; depth = 0; els = None; end = None
    for i, ln in enumerate( lines ):
        d = ln.strip()
        if not d.startswith( "#" ): continue
        d = re.sub( r'\s+', " ", d.replace( "# ", "#" ) )
        if start is None:
            if re.match( r'#if !\s?defined\s?\(\s?_WIN32\s?\)', d ): start = i; depth = 0
            continue
        if re.match( r'#if', d ): depth += 1
        elif re.match( r'#else', d ) and depth == 0 and els is None: els = i
        elif re.match( r'#endif', d ):
            if depth == 0: end = i; break
            depth -= 1
    if start is None or els is None or end is None: return None
    posix = "\n".join( lines[ start + 1:els ] ); win = "\n".join( lines[ els + 1:end ] )
    names = lambda t: { m.group( 1 ) for m in DECL_HEAD.finditer( t ) if m.group( 1 ) not in CALL_KEYWORDS }   # column-0 declarations: a body statement is indented
    placeholder = bool( re.search( r'^\s*#\s*error\b', win, re.M ) ) and not names( win )
    return names( posix ), names( win ), placeholder

# ── the population ──────────────────────────────────────────────────────────────────────────────────────────
EXTS = ( ".h", ".hpp", ".inl", ".ipp", ".cpp", ".cc", ".c", ".mm" )
files = []
for dp, dn, fn in os.walk( os.path.join( ROOT, "src" ) ):
    dn.sort()
    for f in sorted( fn ):
        if f.endswith( EXTS ):
            files.append( os.path.relpath( os.path.join( dp, f ), ROOT ) )
files.sort()
texts = { r: open( os.path.join( ROOT, r ), encoding="utf-8", errors="surrogateescape" ).read() for r in files }
def cmake_reachable_files( root ):
    """Repository-owned CMake inputs the root build can reach: CMakeLists.txt, cmake/*.cmake, and — recursively —
    every CMakeLists.txt / *.cmake a FetchContent_Declare vendors into third_party/deps/<name> (CodeRabbit #290:
    doctest's own CMakeLists.txt and its scripts/cmake/*.cmake were unscanned, reached via FetchContent_MakeAvailable
    when RIPWIRE_TESTS is ON). EXCLUDED: a name the root CMakeLists.txt itself declares SOURCE_SUBDIR _none_ for —
    its CMakeLists.txt is never configured by this build, so there is nothing to reach. add_ts_grammar's macro body
    sets that for every grammar it is invoked with; three explicit blocks (swift, php, ts_typescript) set it by
    hand. Both are read out of CMakeLists.txt itself, not hand-listed, so a new grammar or a new plain
    FetchContent_Declare both stay covered without a second edit here."""
    files = [ "CMakeLists.txt" ]
    cdir = os.path.join( root, "cmake" )
    if os.path.isdir( cdir ):
        files += sorted( os.path.join( "cmake", f ) for f in os.listdir( cdir ) if f.endswith( ".cmake" ) )
    root_txt = open( os.path.join( root, "CMakeLists.txt" ), encoding="utf-8", errors="replace" ).read()
    none_names = set( re.findall( r'add_ts_grammar\(\s*([A-Za-z0-9_]+)', root_txt ) )
    for m in re.finditer( r'FetchContent_Declare\(\s*([A-Za-z0-9_]+)', root_txt ):
        openParen = root_txt.index( "(", m.start() )
        close = matching_close( root_txt, openParen, "(", ")" )
        body = root_txt[ openParen:close ] if close is not None else root_txt[ openParen: ]
        if re.search( r'SOURCE_SUBDIR\s+_none_', body ):
            none_names.add( m.group( 1 ) )
    deps_dir = os.path.join( root, "third_party", "deps" )
    if os.path.isdir( deps_dir ):
        for name in sorted( os.listdir( deps_dir ) ):
            if name in none_names or not os.path.isdir( os.path.join( deps_dir, name ) ):
                continue
            for dp, dn, fn in os.walk( os.path.join( deps_dir, name ) ):
                dn.sort()
                for f in sorted( fn ):
                    if f == "CMakeLists.txt" or f.endswith( ".cmake" ):
                        files.append( os.path.relpath( os.path.join( dp, f ), root ) )
    return sorted( f for f in files if os.path.exists( os.path.join( root, f ) ) )
cmake_files = cmake_reachable_files( ROOT )
wf_dir = os.path.join( ROOT, ".github", "workflows" )
yaml_files = sorted( os.path.join( ".github", "workflows", f ) for f in os.listdir( wf_dir ) if f.endswith( ( ".yml", ".yaml" ) ) ) if os.path.isdir( wf_dir ) else []

if len( files ) >= 50:
    ok( "the scan reaches %d first-party C/C++ files under src/ (a short scan would pass while measuring little)" % len( files ) )
else:
    no( "the scan reached only %d files under src/ — the walk or the layout moved; the arms below would measure nothing" % len( files ) )

os_raw = texts.get( HOME )
if os_raw is None:
    no( "%s does not exist — there is no home for the OS switch, so arms E and G have no facts or branches to read" % HOME )
    facts = set()
else:
    facts = facts_of( os_raw )
    if { "kTarget", "kWindows", "kApple", "kLinux", "Target" } <= facts:
        ok( "%s declares its platform facts (%s) — arm G's population is read from the header, not restated here" % ( HOME, ", ".join( sorted( facts ) ) ) )
    else:
        no( "%s declares facts %s; arm G expects at least kTarget/kWindows/kApple/kLinux/Target — its refusal list would be short" % ( HOME, sorted( facts ) ) )

# An allowlist row says "these KNOWN sites are exempt", not "this file is exempt for ever". Without a pinned
# count an exempted file absorbs the next violation silently — a planted __builtin_expect in profileScope.h
# passed while the same plant in strkern.h reddened (review, 2026-09-21). EXEMPT_COUNTS pins what each row
# covers; anything above it is reported like any other violation, and anything BELOW it is reported too, so a
# row cannot outlive the sites that justified it.
EXEMPT_COUNTS = {
    ( "src/infra/Diagnostics.h",  "H" ): 11,
    ( "src/infra/platform.h",     "H" ): 11,   # +1 addWithCarry64's Wide (QD-LCS, 2026-11-13)
    ( "src/infra/profileScope.h", "H" ): 3,
    ( "src/infra/enumcount.h",    "H" ): 1,
    ( "src/infra/radixSort.h",    "H" ): 3,
    ( "src/structlayout.h",       "H" ): 2,
}

def scan( arm, fn ):
    hits = []; exempted = {}
    for r in files:
        if r == HOME and arm != "D": continue
        got = fn( r, texts[r] )
        if r in ALLOW and arm in ALLOW[r][0]:
            exempted[r] = len( got )
            want = EXEMPT_COUNTS.get( ( r, arm ) )
            # Arm H REQUIRES a pin (that is the arm the absorb was demonstrated on). The older arms keep their
            # unpinned behaviour unless a pin is added for them, so this fixes what was found without silently
            # changing five arms nobody measured; adding their counts here is the obvious follow-up.
            if want is None and arm == "H":
                hits.append( "%s: allowlisted for arm H with no pinned count — add one to EXEMPT_COUNTS" % r )
            elif want is not None and len( got ) != want:
                hits.append( "%s: arm %s allowlist covers %d site(s), found %d — re-read them and re-pin"
                             % ( r, arm, want, len( got ) ) )
            continue
        hits += got
    return hits, exempted

LIMIT = 1000000 if os.environ.get( "OSSWITCH_VERBOSE" ) == "1" else 14
def report( arm, what, hits, exempted, limit=LIMIT ):
    if hits:
        no( "(%s) %s — %d violation(s):" % ( arm, what, len( hits ) ) )
        for h in hits[ :limit ]: print( "          %s" % h )
        if len( hits ) > limit: print( "          … and %d more" % ( len( hits ) - limit ) )
    else:
        ex = ( "; allowlisted: " + ", ".join( "%s (%d)" % ( k, v ) for k, v in sorted( exempted.items() ) ) ) if exempted else ""
        ok( "(%s) %s%s" % ( arm, what, ex ) )

all_exempted = {}
def run_arm( arm, what, fn ):
    hits, ex = scan( arm, fn )
    for k, v in ex.items(): all_exempted.setdefault( k, {} )[ arm ] = v
    report( arm, what, hits, ex )

run_arm( "A",  "no OS-conditional name in a preprocessor directive outside %s" % HOME, detect_A )
run_arm( "A'", "no OS proxy name (feature macro, kqueue seam, __has_include of a system header) in a directive outside %s" % HOME, detect_A2 )
run_arm( "B",  "no POSIX or Windows system header included outside %s" % HOME, lambda r, t: detect_B( r, t, ROOT ) )

c_hits = []
for f in cmake_files: c_hits += detect_C_text( f, open( os.path.join( ROOT, f ), encoding="utf-8", errors="replace" ).read() )
for f in yaml_files:  c_hits += detect_C_text( f, open( os.path.join( ROOT, f ), encoding="utf-8", errors="replace" ).read(), yaml=True )
c_hits += detect_C_tree( ROOT )
report( "C", "no force-include in %d CMake file(s) or %d workflow(s), no compat include directory, no first-party header mirroring a system header"
        % ( len( cmake_files ), len( yaml_files ) ), c_hits, {} )

d_hits, _ = scan( "D", detect_D )
for f in cmake_files: d_hits += detect_D_cmake( f, open( os.path.join( ROOT, f ), encoding="utf-8", errors="replace" ).read() )
report( "D", "no macro or compile definition named after a libc/POSIX function anywhere in src/ (%s included) or CMake" % HOME, d_hits, {} )

run_arm( "F", "no raw POSIX/libc call or POSIX type outside %s" % HOME, detect_F )
run_arm( "G", "no platform fact (%s) named, and namespace os not reopened, outside %s" % ( ", ".join( sorted( facts ) ) or "none declared", HOME ),
         lambda r, t: detect_G( r, t, facts ) )

run_arm( "H", "no cl.exe-refused compiler extension (__builtin_*, inline asm, __attribute__, __PRETTY_FUNCTION__, __BASE_FILE__, the endianness macros, __int128) outside the seam in src/infra/platform.h", detect_H )

# ── (E) declaration parity ──────────────────────────────────────────────────────────────────────────────────
if os_raw is not None:
    split = branch_functions( os_raw )
    if split is None:
        no( "(E) %s has no top-level `#if !defined( _WIN32 )` … `#else` … `#endif` split — there is no POSIX branch and no Windows branch to compare" % HOME )
    else:
        posix, win, placeholder = split
        if not posix:
            no( "(E) the POSIX branch of %s declares no function this arm can read — the extractor is blind, so parity would be vacuous" % HOME )
        elif placeholder:
            print( "  NOTE  (E) disabled: the Windows branch of %s is still the placeholder #error and declares no function, so there is "
                   "no second set to compare (PR #44 fills it). The POSIX branch declares %d names; the comparison turns on by itself "
                   "when the Windows branch declares its first one." % ( HOME, len( posix ) ) )
        elif posix != win:
            no( "(E) POSIX/Windows declaration parity: only in POSIX %s; only in Windows %s" % ( sorted( posix - win ), sorted( win - posix ) ) )
        else:
            ok( "(E) the POSIX and Windows branches of %s declare the same %d function names" % ( HOME, len( posix ) ) )

# ── stale allowlist rows ────────────────────────────────────────────────────────────────────────────────────
for path, ( arms, why ) in sorted( ALLOW.items() ):
    if path not in texts:
        no( "allowlist row %s names a file that does not exist — delete the row (reason was: %s)" % ( path, why[ :80 ] ) ); continue
    idle = sorted( a for a in arms if not all_exempted.get( path, {} ).get( a ) )
    if idle:
        no( "allowlist row %s exempts arm(s) %s from nothing any more — narrow the row" % ( path, ", ".join( idle ) ) )
    else:
        ok( "allowlist row %s is live for arms %s: %s" % ( path, ", ".join( sorted( arms ) ), why ) )

# ── controls: every detector fires on a planted violation and stays silent on a clean file ──────────────────
PLANT = {
    "A":  ( "#if defined( __APPLE__ ) \\\n    || defined( _WIN32 )\nint x;\n#endif\n", 1 ),
    "A'": ( "#ifdef MSG_NOSIGNAL\nint a;\n#endif\n#if __has_include( <sys/event.h> )\nint b;\n#endif\n", 2 ),
    "B":  ( "#include <unistd.h>\n#  include <sys/stat.h>\n#include <windows.h>\n", 3 ),
    "D":  ( "#define open _open\n#define fclose( f ) rw_fclose( f )\n#undef rename\n", 3 ),
    # the last two statements are CodeRabbit #290's control: a struct's own `read` member must not hide an
    # unrelated raw `read( fd, buf, n )` in a sibling scope of the same file (a file-wide declared-name set would
    # miss it; the fix scopes each declaration to its own enclosing block).
    "F":  ( "void f( int fd ) { ::close( fd ); if( std::rename( a, b ) ) {} FILE* p = popen( c, \"r\" ); struct stat st; ssize_t n = 0; }\n"
            "struct QRead { void read( int c ); };\nvoid h( int fd, char* buf, unsigned n ) { read( fd, buf, n ); }\n", 6 ),
    "G":  ( "void f() { if( os::kWindows ) {} bool b = rw::os::kApple; }\nnamespace rw::os { }\n", 3 ),
    # the __has_builtin block is the control for the carve-out: a feature TEST must not count as a use, or a file
    # asking whether an extension exists would be refused for asking. The two statements after it are the controls
    # for the review round of 2026-09-21: an UNQUALIFIED `asm(…)` is refused by cl.exe exactly as `asm volatile` is,
    # and a genuine `__builtin_expect` USE on the SAME LINE as a `__has_builtin` guard must still red — it sits
    # beside the exemption, not inside its parentheses, and the fixed 40-character look-back sheltered it.
    "H":  ( "int f( int* p ) { __builtin_prefetch( p, 0, 0 ); asm volatile( \"\" : : : \"memory\" ); return 0; }\n"
            "__attribute__(( used )) static int g = 0;\n"
            "const char* w() { return __PRETTY_FUNCTION__; }\nconst char* b() { return __BASE_FILE__; }\n"
            "int e = ( __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__ );\nunsigned __int128 wide = 0;\n"
            "#if defined( __has_builtin )\n#if __has_builtin( __builtin_trap )\nint h = 1;\n#endif\n#endif\n"
            "void n() { asm( \"nop\" ); }\n"
            "#if __has_builtin( __builtin_clz ) && __builtin_expect( 1, 1 )\nint c = 1;\n#endif\n", 10 ),
}
CLEAN = ( "// __APPLE__ and ::open( and #include <unistd.h> are only words in a comment\n"
          "int wasm = 0; int asm_buf = 1; struct Q { int assembler; };\n"   # \basm\b must not fire inside a longer identifier

          "#include \"infra/os.h\"\n#if defined( __aarch64__ )\nint z;\n#endif\n"
          "struct P { bool accept( char c ); void write( int n ); };\n"
          "template<class Accept> bool route( Accept accept ) { return accept( 1 ); }\n"
          "void g( P& p, int fd ) { p.write( 1 ); p.accept( 'x' ); os::close( fd ); os::stat_t st; os::ssize_t n = os::read( fd, 0, 0 );\n"
          "  const char* s = \"::open( popen( struct stat\"; std::remove( v.begin(), v.end(), 3 ); std::getline( in, line ); }\n" )
DET = { "A": detect_A, "A'": detect_A2, "B": lambda r, t: detect_B( r, t, "/nonexistent" ), "D": detect_D, "F": detect_F,
        "G": lambda r, t: detect_G( r, t, { "kWindows", "kApple", "kLinux", "kTarget", "Target" } ), "H": detect_H }
for arm in [ "A", "A'", "B", "D", "F", "G", "H" ]:
    text, want = PLANT[arm]
    got = DET[arm]( "planted.h", text ); clean = DET[arm]( "clean.h", CLEAN )
    if len( got ) != want:
        no( "(%s-control) the detector found %d of the %d planted violations — its silence above proves nothing: %s" % ( arm, len( got ), want, got ) )
    elif clean:
        no( "(%s-control) the detector fires on a CLEAN file (comments, strings, os:: calls, member calls, arch macros): %s" % ( arm, clean ) )
    else:
        ok( "(%s-control) the detector finds all %d planted violations and stays silent on the clean file" % ( arm, want ) )

cm = detect_C_text( "planted.cmake", 'target_compile_options(t PRIVATE -include ${X} /FIplatform_compat.h)\n# -include in a comment\ntarget_include_directories(t PRIVATE src/infra/compat)\ntarget_link_options(t PRIVATE /FIXED)\n' )
dm = detect_D_cmake( "planted.cmake", 'add_compile_definitions(open=_open PROFILE_ENABLED=1)\nset(F "-Dfclose=rw_fclose")\n' )
tmp = tempfile.mkdtemp( prefix="osswitch-ctl-" )
try:
    os.makedirs( os.path.join( tmp, "src", "infra", "compat", "sys" ) )
    open( os.path.join( tmp, "src", "infra", "compat", "sys", "socket.h" ), "w" ).write( "#pragma once\n" )
    tree = detect_C_tree( tmp )
finally:
    shutil.rmtree( tmp, True )
if len( cm ) == 3 and len( dm ) == 2 and len( tree ) == 2:
    ok( "(C/D-control) the CMake detectors find -include, /FI and a compat include dir (not /FIXED, not a comment), both libc "
        "compile definitions, and a planted compat/sys/socket.h tree" )
else:
    no( "(C/D-control) planted CMake/tree violations found C=%d/3 D=%d/2 tree=%d/2 — %s %s %s" % ( len( cm ), len( dm ), len( tree ), cm, dm, tree ) )

pair = ( "#if !defined( _WIN32 )\n[[gnu::always_inline]] inline int close( int fd ) { return ::close( fd ); }\n"
         "inline ssize_t read( int fd, void* b, size_t n ) { return ::read( fd, b, n ); }\n#else\nint close( int fd );\n#endif\n" )
hole = ( "#if !defined( _WIN32 )\ninline int close( int fd ) { return ::close( fd ); }\n#else\n#error \"later\"\n#endif\n" )
sp = branch_functions( pair ); sh = branch_functions( hole )
if sp and sp[0] == { "close", "read" } and sp[1] == { "close" } and not sp[2] and sh and sh[2]:
    ok( "(E-control) the parity reader extracts {close, read} vs {close} from a planted pair (a mismatch E would report) and "
        "recognises a placeholder #error branch as not yet comparable" )
else:
    no( "(E-control) the parity reader read %r from a planted pair and %r from a placeholder — arm E cannot be trusted when it turns on" % ( sp, sh ) )

sys.exit( bad )
PY

if [ "$fail" = 0 ]; then
    echo "ALL PASS"
else
    echo "SOME CHECKS FAILED"
fi
exit "$fail"
