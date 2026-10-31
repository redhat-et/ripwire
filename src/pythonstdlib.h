#pragma once
// pythonstdlib.h — the Python standard-library module names, a LANGUAGE-layer fact beside langfacts.h (a list, so it is not a
// langfacts column).
//
// WHAT IT IS FOR, and the ONLY thing it is for. A Python import written inside a source-layout tree (resolve.h
// pythonFallbackRoots: `src/`, a package chain's source root) is probed at that layout root as a fallback. A layout root is a
// directory a build puts on sys.path, so a file there named like a stdlib module (`src/logging.py`, `lib/json.py`) shadows the
// stdlib only if that directory comes FIRST on the path, which an installed package root never does. Resolution alone cannot decide
// that (both files exist), so a stdlib-named FIRST segment does not bind through a layout root, and the import stays unresolved
// the way the stdlib itself is. A package importing ITSELF is probed at its own chain root before any of this
// (resolve.h pythonSelfChainRoot), so the guard never hides a package's own `email/`. Not consulted anywhere else: a plain script directory really can shadow the stdlib (it is
// sys.path[0]), the repo root is probed as before, and the older suffix scan is untouched (a card, not this table). A layout root
// that IS the stdlib (cpython `Lib/`) is exempt: resolve.h pythonRootHoldsStdlib.
//
// PROVENANCE. CPython 3.13.3 `sorted(sys.stdlib_module_names)`, 290 names. Regenerate the list with
//   python3 -c 'import sys; print(*sorted(sys.stdlib_module_names), sep="\n")'
// and wrap it into the array below. Version skew is a few names: asynchat, distutils and imp left the stdlib in 3.12, and 3.13
// removed the PEP 594 set (cgi, telnetlib and so on). A name missing here is treated like any project name, so a layout root holding
// it binds; the base resolver had no layout roots, so that is a new edge: true for 3.13 code, false for older code. The static_assert
// below is the compile-time proof that the binary search is valid. `__main__` is not in the interpreter's list and is tested beside
// the lookup (isPythonStdlibModule).
#include "externalnames.h"   // inSortedTable: the house lookup of a strictly sorted name table
#include "infra/sortutil.h"

#include <algorithm>
#include <iterator>
#include <string_view>

namespace rw
{
namespace pythonstdlib
{
inline constexpr std::string_view kPythonStdlibModules[] = {
    "__future__", "_abc", "_aix_support", "_android_support", "_apple_support", "_ast", "_asyncio", "_bisect", "_blake2", "_bz2", "_codecs",
    "_codecs_cn", "_codecs_hk", "_codecs_iso2022", "_codecs_jp", "_codecs_kr", "_codecs_tw", "_collections", "_collections_abc", "_colorize",
    "_compat_pickle", "_compression", "_contextvars", "_csv", "_ctypes", "_curses", "_curses_panel", "_datetime", "_dbm", "_decimal", "_elementtree",
    "_frozen_importlib", "_frozen_importlib_external", "_functools", "_gdbm", "_hashlib", "_heapq", "_imp", "_interpchannels", "_interpqueues",
    "_interpreters", "_io", "_ios_support", "_json", "_locale", "_lsprof", "_lzma", "_markupbase", "_md5", "_multibytecodec", "_multiprocessing",
    "_opcode", "_opcode_metadata", "_operator", "_osx_support", "_overlapped", "_pickle", "_posixshmem", "_posixsubprocess", "_py_abc", "_pydatetime",
    "_pydecimal", "_pyio", "_pylong", "_pyrepl", "_queue", "_random", "_scproxy", "_sha1", "_sha2", "_sha3", "_signal", "_sitebuiltins", "_socket",
    "_sqlite3", "_sre", "_ssl", "_stat", "_statistics", "_string", "_strptime", "_struct", "_suggestions", "_symtable", "_sysconfig", "_thread",
    "_threading_local", "_tkinter", "_tokenize", "_tracemalloc", "_typing", "_uuid", "_warnings", "_weakref", "_weakrefset", "_winapi", "_wmi",
    "_zoneinfo", "abc", "antigravity", "argparse", "array", "ast", "asyncio", "atexit", "base64", "bdb", "binascii", "bisect", "builtins", "bz2",
    "cProfile", "calendar", "cmath", "cmd", "code", "codecs", "codeop", "collections", "colorsys", "compileall", "concurrent", "configparser",
    "contextlib", "contextvars", "copy", "copyreg", "csv", "ctypes", "curses", "dataclasses", "datetime", "dbm", "decimal", "difflib", "dis",
    "doctest", "email", "encodings", "ensurepip", "enum", "errno", "faulthandler", "fcntl", "filecmp", "fileinput", "fnmatch", "fractions", "ftplib",
    "functools", "gc", "genericpath", "getopt", "getpass", "gettext", "glob", "graphlib", "grp", "gzip", "hashlib", "heapq", "hmac", "html", "http",
    "idlelib", "imaplib", "importlib", "inspect", "io", "ipaddress", "itertools", "json", "keyword", "linecache", "locale", "logging", "lzma",
    "mailbox", "marshal", "math", "mimetypes", "mmap", "modulefinder", "msvcrt", "multiprocessing", "netrc", "nt", "ntpath", "nturl2path", "numbers",
    "opcode", "operator", "optparse", "os", "pathlib", "pdb", "pickle", "pickletools", "pkgutil", "platform", "plistlib", "poplib", "posix",
    "posixpath", "pprint", "profile", "pstats", "pty", "pwd", "py_compile", "pyclbr", "pydoc", "pydoc_data", "pyexpat", "queue", "quopri", "random",
    "re", "readline", "reprlib", "resource", "rlcompleter", "runpy", "sched", "secrets", "select", "selectors", "shelve", "shlex", "shutil", "signal",
    "site", "smtplib", "socket", "socketserver", "sqlite3", "sre_compile", "sre_constants", "sre_parse", "ssl", "stat", "statistics", "string",
    "stringprep", "struct", "subprocess", "symtable", "sys", "sysconfig", "syslog", "tabnanny", "tarfile", "tempfile", "termios", "textwrap", "this",
    "threading", "time", "timeit", "tkinter", "token", "tokenize", "tomllib", "trace", "traceback", "tracemalloc", "tty", "turtle", "turtledemo",
    "types", "typing", "unicodedata", "unittest", "urllib", "uuid", "venv", "warnings", "wave", "weakref", "webbrowser", "winreg", "winsound",
    "wsgiref", "xml", "xmlrpc", "zipapp", "zipfile", "zipimport", "zlib", "zoneinfo",
};
static_assert( std::is_sorted( std::begin( kPythonStdlibModules ), std::end( kPythonStdlibModules ), rw::sortutil::svLess ),
               "kPythonStdlibModules must be sorted (binary search)" );

/// Is `name` (a module's FIRST dotted segment) a CPython 3.13 standard-library module? The table is an exact copy of the
/// interpreter's list, which omits `__main__` (always in sys.modules, never found on a path), so it is tested beside the lookup.
inline bool isPythonStdlibModule( std::string_view name ) noexcept
{
    return name == "__main__" || rw::externalnames::inSortedTable( kPythonStdlibModules, name );
}
} // namespace pythonstdlib
} // namespace rw
