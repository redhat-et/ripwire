#pragma once
// externalnames.h — the COMMITTED external-name tables behind the Phase 5 external-name veto
// (docs/EVALS.md "Phase 5", mechanism 1; graph.h buildGraph; gate test/externalvetocheck.sh).
//
// WHY A TABLE AND NOT A HEURISTIC. A bare call whose name is a language builtin, or a standard-library
// function a bare spelling reaches, pinned to an in-repo definition of that name is a wrong edge whenever
// no in-repo evidence makes the name reachable (Python: a bare `sum(…)` can never reach a METHOD; C++: an
// unqualified `find(…)` from a free function can never reach an unrelated class's member). "Looks like a
// builtin" is not a fact the resolver may guess at; "IS in this list, whose provenance is stated" is. The
// two tables below are that list. They are consulted ONLY after every evidence rule has missed (Rules
// 1/2/2b/2c/3, the base walk, a local binding, an in-repo import binding, a same-file module-level def, a
// free symbol of that name anywhere in the corpus for C-family), so a repo that legitimately defines and
// reaches its own `max` or `filter` keeps its edge.
//
// PROVENANCE, per group. Regenerate with the generator recorded in docs/EVALS.md "Phase 5"; the sortedness
// static_asserts below are the compile-time proof the binary search is valid.
//
//   kPythonBuiltinNames — CPython 3.14.7 `builtins`: `python3 -c 'import builtins; print(sorted(dir(builtins)))'`,
//     minus the six `site`-injected names (copyright credits exit help license quit — present only when the
//     `site` module ran, not part of the language) and the five non-callable constants (True False None
//     Ellipsis NotImplemented — never in callee position). The exception and warning classes are KEPT: they
//     are callable (`ValueError(…)`). 141 names. The stdlib MODULE surface (`sys.stdlib_module_names`) is
//     deliberately NOT a table: a stdlib member only becomes a bare name through an import, and the import
//     binding decides that by resolution (LocalBindKind::Import), not by list.
//
//   kCFamilyStdNames — the ISO C11 §7 library function names by header, plus the C++23 `std::` function
//     templates a BARE spelling reaches through ADL or a using-directive, by header. Function names only
//     (no types, no objects, no namespaces): a type is a receiver's binding, never a callee name.
//       <ctype.h>              isalnum isalpha isblank iscntrl isdigit isgraph islower isprint ispunct isspace isupper isxdigit tolower toupper
//       <stdio.h>              remove rename tmpfile tmpnam fclose fflush fopen freopen setbuf setvbuf fprintf fscanf printf scanf snprintf sprintf sscanf vfprintf vfscanf vprintf vscanf vsnprintf vsprintf vsscanf fgetc fgets fputc fputs getc getchar putc putchar puts ungetc fread fwrite fgetpos fseek fsetpos ftell rewind clearerr feof ferror perror
//       <stdlib.h>             atof atoi atol atoll strtod strtof strtold strtol strtoll strtoul strtoull rand srand aligned_alloc calloc free malloc realloc abort atexit at_quick_exit exit _Exit getenv quick_exit system bsearch qsort abs labs llabs div ldiv lldiv mblen mbtowc wctomb mbstowcs wcstombs
//       <string.h>             memcpy memmove strcpy strncpy strcat strncat memcmp strcmp strcoll strncmp strxfrm memchr strchr strcspn strpbrk strrchr strspn strstr strtok memset strerror strlen
//       <math.h>               acos asin atan atan2 cos sin tan acosh asinh atanh cosh sinh tanh exp exp2 expm1 frexp ilogb ldexp log log10 log1p log2 logb modf scalbn scalbln cbrt fabs hypot pow sqrt erf erfc lgamma tgamma ceil floor nearbyint rint lrint llrint round lround llround trunc fmod remainder remquo copysign nan nextafter nexttoward fdim fmax fmin fma sqrtf fabsf floorf ceilf powf expf logf sinf cosf tanf roundf fmaxf fminf truncf isnan isinf isfinite isnormal signbit
//       <time.h>               clock difftime mktime time timespec_get asctime ctime gmtime localtime strftime
//       <signal.h>             signal raise
//       <inttypes.h>           imaxabs imaxdiv strtoimax strtoumax
//       <wchar.h>              wcslen wcscpy wcsncpy wcscat wcsncat wcscmp wcsncmp wcschr wcsrchr wcsstr wmemcpy wmemmove wmemset wmemcmp wmemchr wprintf swprintf fwprintf mbrtowc wcrtomb btowc wctob fgetwc fputwc mbrlen wcstol wcstoul wcstod
//       <setjmp.h>             setjmp longjmp
//       <stdarg.h>             va_start va_end va_arg va_copy
//       <locale.h>             setlocale localeconv
//       <uchar.h>              mbrtoc16 c16rtomb mbrtoc32 c32rtomb
//       <assert.h>             assert
//       <algorithm>            all_of any_of none_of for_each for_each_n find find_if find_if_not find_end find_first_of adjacent_find count count_if mismatch equal is_permutation search search_n copy copy_n copy_if copy_backward move_backward swap_ranges iter_swap transform replace replace_if replace_copy replace_copy_if fill fill_n generate generate_n remove_if remove_copy remove_copy_if unique unique_copy reverse reverse_copy rotate rotate_copy shuffle sample is_partitioned partition partition_copy stable_partition partition_point sort stable_sort partial_sort partial_sort_copy is_sorted is_sorted_until nth_element lower_bound upper_bound equal_range binary_search merge inplace_merge includes set_union set_intersection set_difference set_symmetric_difference push_heap pop_heap make_heap sort_heap is_heap is_heap_until min max minmax min_element max_element minmax_element clamp lexicographical_compare lexicographical_compare_three_way next_permutation prev_permutation
//       <utility>              swap exchange forward move move_if_noexcept as_const declval make_pair get cmp_equal cmp_not_equal cmp_less cmp_greater cmp_less_equal cmp_greater_equal in_range to_underlying
//       <memory>               addressof allocate_shared make_shared make_unique make_shared_for_overwrite make_unique_for_overwrite static_pointer_cast dynamic_pointer_cast const_pointer_cast reinterpret_pointer_cast uninitialized_copy uninitialized_copy_n uninitialized_fill uninitialized_fill_n uninitialized_move uninitialized_move_n uninitialized_default_construct uninitialized_value_construct destroy destroy_at destroy_n construct_at to_address assume_aligned
//       <numeric>              accumulate reduce transform_reduce inner_product adjacent_difference partial_sum inclusive_scan exclusive_scan transform_inclusive_scan transform_exclusive_scan iota gcd lcm midpoint
//       <iterator>             begin end cbegin cend rbegin rend crbegin crend size ssize empty data advance distance next prev back_inserter front_inserter inserter make_move_iterator make_reverse_iterator
//       <functional>           bind bind_front bind_back ref cref invoke invoke_r not_fn mem_fn
//       <string>               to_string to_wstring stoi stol stoll stoul stoull stof stod stold getline
//       <tuple>                tie make_tuple forward_as_tuple tuple_cat apply make_from_tuple
//       <bit>                  bit_cast has_single_bit bit_ceil bit_floor bit_width rotl rotr countl_zero countl_one countr_zero countr_one popcount byteswap
//       <charconv>             to_chars from_chars
//       <optional>/<variant>   make_optional visit get_if holds_alternative
//     459 names.
#include "infra/sortutil.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <span>
#include <string_view>
namespace rw
{
namespace externalnames
{
inline constexpr std::string_view kPythonBuiltinNames[] = {
    "ArithmeticError", "AssertionError", "AttributeError", "BaseException", "BaseExceptionGroup", "BlockingIOError", "BrokenPipeError",
    "BufferError", "BytesWarning", "ChildProcessError", "ConnectionAbortedError", "ConnectionError", "ConnectionRefusedError",
    "ConnectionResetError", "DeprecationWarning", "EOFError", "EncodingWarning", "EnvironmentError", "Exception", "ExceptionGroup",
    "FileExistsError", "FileNotFoundError", "FloatingPointError", "FutureWarning", "GeneratorExit", "IOError", "ImportError", "ImportWarning",
    "IndentationError", "IndexError", "InterruptedError", "IsADirectoryError", "KeyError", "KeyboardInterrupt", "LookupError", "MemoryError",
    "ModuleNotFoundError", "NameError", "NotADirectoryError", "NotImplementedError", "OSError", "OverflowError", "PendingDeprecationWarning",
    "PermissionError", "ProcessLookupError", "PythonFinalizationError", "RecursionError", "ReferenceError", "ResourceWarning", "RuntimeError",
    "RuntimeWarning", "StopAsyncIteration", "StopIteration", "SyntaxError", "SyntaxWarning", "SystemError", "SystemExit", "TabError", "TimeoutError",
    "TypeError", "UnboundLocalError", "UnicodeDecodeError", "UnicodeEncodeError", "UnicodeError", "UnicodeTranslateError", "UnicodeWarning",
    "UserWarning", "ValueError", "Warning", "ZeroDivisionError", "__build_class__", "__import__", "abs", "aiter", "all", "anext", "any", "ascii",
    "bin", "bool", "breakpoint", "bytearray", "bytes", "callable", "chr", "classmethod", "compile", "complex", "delattr", "dict", "dir", "divmod",
    "enumerate", "eval", "exec", "filter", "float", "format", "frozenset", "getattr", "globals", "hasattr", "hash", "hex", "id", "input", "int",
    "isinstance", "issubclass", "iter", "len", "list", "locals", "map", "max", "memoryview", "min", "next", "object", "oct", "open", "ord", "pow",
    "print", "property", "range", "repr", "reversed", "round", "set", "setattr", "slice", "sorted", "staticmethod", "str", "sum", "super", "tuple",
    "type", "vars", "zip"
};

// P4 (capture-audit 2026-09-04, lane L7): the POSIX sh special + regular builtins and bash's builtins — the names a
// shell script "calls" that are the interpreter itself, not a dependency (--external-surface drops them by default;
// --include-builtins keeps them; builtins_excluded= counts the drop). Source: POSIX.1-2024 XCU 2.14 (special
// builtins) + 2.9.1 intrinsic utilities, and bash 5.2 `compgen -b`. NOT here on purpose: grep/sed/awk/git/python3 —
// external programs a script really depends on, which is exactly what the surface is for.
inline constexpr std::string_view kShellBuiltinNames[] = {
    ".", ":", "[", "alias", "bg", "bind", "break", "builtin", "caller", "cd", "command", "compgen", "complete", "compopt",
    "continue", "declare", "dirs", "disown", "echo", "enable", "eval", "exec", "exit", "export", "false", "fc", "fg",
    "getopts", "hash", "help", "history", "jobs", "kill", "let", "local", "logout", "mapfile", "popd", "printf", "pushd",
    "pwd", "read", "readarray", "readonly", "return", "set", "shift", "shopt", "source", "suspend", "test", "times",
    "trap", "true", "type", "typeset", "ulimit", "umask", "unalias", "unset", "wait",
};

// wave-3 close: this file's own house shape — a strictly sorted constant table, pinned at compile time, read by
// binary_search through svLess (isPythonBuiltin / isCFamilyStdName above). The hand loop P4 landed with read as a
// 29-40 token clone of five unrelated tiny predicates in --quality-delta=ec5e3c3..HEAD; a std::find one-liner
// cloned KindCounts::total instead. The sibling shape is the one this file already carries.
static_assert( std::is_sorted( std::begin( kShellBuiltinNames ), std::end( kShellBuiltinNames ), rw::sortutil::svLess )
               , "kShellBuiltinNames must be strictly sorted (binary search)" );
inline bool isShellBuiltinName( std::string_view name ) noexcept
{
    return std::binary_search( std::begin( kShellBuiltinNames ), std::end( kShellBuiltinNames ), name, rw::sortutil::svLess );
}

inline constexpr std::string_view kCFamilyStdNames[] = {
    "_Exit", "abort", "abs", "accumulate", "acos", "acosh", "addressof", "adjacent_difference", "adjacent_find", "advance", "aligned_alloc",
    "all_of", "allocate_shared", "any_of", "apply", "as_const", "asctime", "asin", "asinh", "assert", "assume_aligned", "at_quick_exit", "atan",
    "atan2", "atanh", "atexit", "atof", "atoi", "atol", "atoll", "back_inserter", "begin", "binary_search", "bind", "bind_back", "bind_front",
    "bit_cast", "bit_ceil", "bit_floor", "bit_width", "bsearch", "btowc", "byteswap", "c16rtomb", "c32rtomb", "calloc", "cbegin", "cbrt", "ceil",
    "ceilf", "cend", "clamp", "clearerr", "clock", "cmp_equal", "cmp_greater", "cmp_greater_equal", "cmp_less", "cmp_less_equal", "cmp_not_equal",
    "const_pointer_cast", "construct_at", "copy", "copy_backward", "copy_if", "copy_n", "copysign", "cos", "cosf", "cosh", "count", "count_if",
    "countl_one", "countl_zero", "countr_one", "countr_zero", "crbegin", "cref", "crend", "ctime", "data", "declval", "destroy", "destroy_at",
    "destroy_n", "difftime", "distance", "div", "dynamic_pointer_cast", "empty", "end", "equal", "equal_range", "erf", "erfc", "exchange",
    "exclusive_scan", "exit", "exp", "exp2", "expf", "expm1", "fabs", "fabsf", "fclose", "fdim", "feof", "ferror", "fflush", "fgetc", "fgetpos",
    "fgets", "fgetwc", "fill", "fill_n", "find", "find_end", "find_first_of", "find_if", "find_if_not", "floor", "floorf", "fma", "fmax", "fmaxf",
    "fmin", "fminf", "fmod", "fopen", "for_each", "for_each_n", "forward", "forward_as_tuple", "fprintf", "fputc", "fputs", "fputwc", "fread",
    "free", "freopen", "frexp", "from_chars", "front_inserter", "fscanf", "fseek", "fsetpos", "ftell", "fwprintf", "fwrite", "gcd", "generate",
    "generate_n", "get", "get_if", "getc", "getchar", "getenv", "getline", "gmtime", "has_single_bit", "holds_alternative", "hypot", "ilogb",
    "imaxabs", "imaxdiv", "in_range", "includes", "inclusive_scan", "inner_product", "inplace_merge", "inserter", "invoke", "invoke_r", "iota",
    "is_heap", "is_heap_until", "is_partitioned", "is_permutation", "is_sorted", "is_sorted_until", "isalnum", "isalpha", "isblank", "iscntrl",
    "isdigit", "isfinite", "isgraph", "isinf", "islower", "isnan", "isnormal", "isprint", "ispunct", "isspace", "isupper", "isxdigit", "iter_swap",
    "labs", "lcm", "ldexp", "ldiv", "lexicographical_compare", "lexicographical_compare_three_way", "lgamma", "llabs", "lldiv", "llrint", "llround",
    "localeconv", "localtime", "log", "log10", "log1p", "log2", "logb", "logf", "longjmp", "lower_bound", "lrint", "lround", "make_from_tuple",
    "make_heap", "make_move_iterator", "make_optional", "make_pair", "make_reverse_iterator", "make_shared", "make_shared_for_overwrite",
    "make_tuple", "make_unique", "make_unique_for_overwrite", "malloc", "max", "max_element", "mblen", "mbrlen", "mbrtoc16", "mbrtoc32", "mbrtowc",
    "mbstowcs", "mbtowc", "mem_fn", "memchr", "memcmp", "memcpy", "memmove", "memset", "merge", "midpoint", "min", "min_element", "minmax",
    "minmax_element", "mismatch", "mktime", "modf", "move", "move_backward", "move_if_noexcept", "nan", "nearbyint", "next", "next_permutation",
    "nextafter", "nexttoward", "none_of", "not_fn", "nth_element", "partial_sort", "partial_sort_copy", "partial_sum", "partition", "partition_copy",
    "partition_point", "perror", "pop_heap", "popcount", "pow", "powf", "prev", "prev_permutation", "printf", "push_heap", "putc", "putchar", "puts",
    "qsort", "quick_exit", "raise", "rand", "rbegin", "realloc", "reduce", "ref", "reinterpret_pointer_cast", "remainder", "remove", "remove_copy",
    "remove_copy_if", "remove_if", "remquo", "rename", "rend", "replace", "replace_copy", "replace_copy_if", "replace_if", "reverse", "reverse_copy",
    "rewind", "rint", "rotate", "rotate_copy", "rotl", "rotr", "round", "roundf", "sample", "scalbln", "scalbn", "scanf", "search", "search_n",
    "set_difference", "set_intersection", "set_symmetric_difference", "set_union", "setbuf", "setjmp", "setlocale", "setvbuf", "shuffle", "signal",
    "signbit", "sin", "sinf", "sinh", "size", "snprintf", "sort", "sort_heap", "sprintf", "sqrt", "sqrtf", "srand", "sscanf", "ssize",
    "stable_partition", "stable_sort", "static_pointer_cast", "stod", "stof", "stoi", "stol", "stold", "stoll", "stoul", "stoull", "strcat",
    "strchr", "strcmp", "strcoll", "strcpy", "strcspn", "strerror", "strftime", "strlen", "strncat", "strncmp", "strncpy", "strpbrk", "strrchr",
    "strspn", "strstr", "strtod", "strtof", "strtoimax", "strtok", "strtol", "strtold", "strtoll", "strtoul", "strtoull", "strtoumax", "strxfrm",
    "swap", "swap_ranges", "swprintf", "system", "tan", "tanf", "tanh", "tgamma", "tie", "time", "timespec_get", "tmpfile", "tmpnam", "to_address",
    "to_chars", "to_string", "to_underlying", "to_wstring", "tolower", "toupper", "transform", "transform_exclusive_scan",
    "transform_inclusive_scan", "transform_reduce", "trunc", "truncf", "tuple_cat", "ungetc", "uninitialized_copy", "uninitialized_copy_n",
    "uninitialized_default_construct", "uninitialized_fill", "uninitialized_fill_n", "uninitialized_move", "uninitialized_move_n",
    "uninitialized_value_construct", "unique", "unique_copy", "upper_bound", "va_arg", "va_copy", "va_end", "va_start", "vfprintf", "vfscanf",
    "visit", "vprintf", "vscanf", "vsnprintf", "vsprintf", "vsscanf", "wcrtomb", "wcscat", "wcschr", "wcscmp", "wcscpy", "wcslen", "wcsncat",
    "wcsncmp", "wcsncpy", "wcsrchr", "wcsstr", "wcstod", "wcstol", "wcstombs", "wcstoul", "wctob", "wctomb", "wmemchr", "wmemcmp", "wmemcpy",
    "wmemmove", "wmemset", "wprintf"
};

// compile-time sortedness proof — the lookups below binary-search, so an unsorted insert would be a
// silent miss, not a compile error, without this. Strict: a duplicate is as wrong as a swap.
// The lookups and the static_asserts below share ONE comparator, rw::sortutil::svLess — never
// string_view's operator<, which aborts the Linux G1 leg (the full reason is in infra/sortutil.h, and
// test/portablebuildcheck.sh arm #6 enforces it). A table sorted under one comparator and searched under
// another is the second bug that shape invites, so both sides name the same function here.

static_assert( std::is_sorted( std::begin( kPythonBuiltinNames ), std::end( kPythonBuiltinNames ), rw::sortutil::svLess )
               && std::adjacent_find( std::begin( kPythonBuiltinNames ), std::end( kPythonBuiltinNames ) ) == std::end( kPythonBuiltinNames ),
               "kPythonBuiltinNames must be strictly sorted (binary search)" );
static_assert( std::is_sorted( std::begin( kCFamilyStdNames ), std::end( kCFamilyStdNames ), rw::sortutil::svLess )
               && std::adjacent_find( std::begin( kCFamilyStdNames ), std::end( kCFamilyStdNames ) ) == std::end( kCFamilyStdNames ),
               "kCFamilyStdNames must be strictly sorted (binary search)" );

inline bool isPythonBuiltin( std::string_view name ) noexcept
{
    return std::binary_search( std::begin( kPythonBuiltinNames ), std::end( kPythonBuiltinNames ), name, rw::sortutil::svLess );
}
inline bool isCFamilyStdName( std::string_view name ) noexcept
{
    return std::binary_search( std::begin( kCFamilyStdNames ), std::end( kCFamilyStdNames ), name, rw::sortutil::svLess );
}

// The INLINE ABI namespaces a standard library implementation opens inside namespace std — the one fact
// graph.h's keepStdQualifiedCandidates needs beyond the literal `std`. Symbol::scope and Reference::qualifier
// are both the IMMEDIATE segment, so a def written in `namespace std { inline namespace __1 { … } }` carries
// scope "__1", and a call written `std::__1::move( x )` carries qualifier "__1". Provenance, per spelling:
//   __1 __2   libc++ <__config>: _LIBCPP_ABI_NAMESPACE is `__` + _LIBCPP_ABI_VERSION (1 = the stable ABI every
//             shipping toolchain uses, 2 = the unstable next ABI)
//   __ndk1    the Android NDK's libc++ build defines _LIBCPP_ABI_NAMESPACE=__ndk1
//   __Cr      Chromium's bundled libc++ build defines _LIBCPP_ABI_NAMESPACE=__Cr
//   __cxx11   libstdc++ <bits/c++config.h>: _GLIBCXX_BEGIN_NAMESPACE_CXX11 opens `inline namespace __cxx11`
//             (the dual-ABI std::string and std::list)
//   __8       libstdc++ configured with the versioned namespace (_GLIBCXX_INLINE_VERSION, GCC 8 onward)
// RESERVED SPELLINGS ONLY, on purpose. Every entry starts with a double underscore, which [lex.name] reserves to
// the implementation, so no conforming program names a namespace or an alias this way. The standard's own inline
// namespaces (`literals`, `chrono_literals`, …) are NOT here: those are legal user spellings, and a user's
// `mylib::literals::f()` must never read as a std-qualified call.
// Read by binary_search through svLess inside keepStdQualifiedCandidates, its only consumer — the lookup lives
// there rather than as a fourth `isX( name )` one-liner here, because --quality-delta reads that sibling shape as
// a gating clone group (measured on this lane: 35 tokens, five members). The assert below keeps the search valid.
inline constexpr std::string_view kStdInlineNamespaceNames[] = { "__1", "__2", "__8", "__Cr", "__cxx11", "__ndk1" };

static_assert( std::is_sorted( std::begin( kStdInlineNamespaceNames ), std::end( kStdInlineNamespaceNames ), rw::sortutil::svLess )
               && std::adjacent_find( std::begin( kStdInlineNamespaceNames ), std::end( kStdInlineNamespaceNames ) ) == std::end( kStdInlineNamespaceNames ),
               "kStdInlineNamespaceNames must be strictly sorted (binary search)" );


// ── FE-A: the JS/TS GLOBAL tables (graph.h FalseEdgeRules; gate test/falseedgecheck.sh). A call on a global object
// (`JSON.stringify( b )`, `Buffer.from( p )`, `crypto.subtle.verify( … )`) or to a global function (`fetch( u )`) reaches
// the runtime, never an in-repo definition the calling file does not import, declare or shadow — yet the name ladder
// bound each of them to the lone same-named in-repo function, getter or object property. A name in these tables, used
// in a file that binds no name of that spelling (no import, require, declaration, parameter or local — the extractor
// records each as a JsShadow or ModuleAlias binding, ingest_jsimports.h), is a call outside the tree: external=.
// PROVENANCE — Node 26.9.0, the global object as an ES MODULE sees it (the `node -e` REPL adds every builtin module as
// a global, so the module form is the honest one), identifier-shaped own property names only:
//   node --no-warnings m.mjs, m.mjs:
//     const n=Object.getOwnPropertyNames(globalThis).filter(k=>/^[A-Za-z_][A-Za-z0-9_]*$/.test(k));
//     console.log(n.filter(k=>typeof globalThis[k]==='function'&&/^[a-z]/.test(k)).sort());            // kJsGlobalFunctionNames
//     console.log(n.filter(k=>/^[A-Z]/.test(k)&&['function','object'].includes(typeof globalThis[k])).sort(),   // kJsGlobalObjectNames:
//                 n.filter(k=>/^[a-z]/.test(k)&&typeof globalThis[k]==='object').sort());              //   both lists
//   kJsGlobalObjectNames takes both lists minus `global` and `globalThis`, which name the global object ITSELF and so
//   are kJsGlobalAliasNames below, with the browser's `self` and `window`: a call through an alias is external only when
//   the called name is itself in a global table (`globalThis.fetch( u )`), because a script's own top-level function is
//   reachable as `window.f()`. A global object name is ALSO a global function when called bare (`Symbol()`, `new URL()`).
//   Browser-only globals (`document`, `alert`, `requestAnimationFrame`) are not in Node's list: a stated floor.
inline constexpr std::string_view kJsGlobalObjectNames[] = {
    "AbortController", "AbortSignal", "AggregateError", "Array", "ArrayBuffer", "AsyncDisposableStack", "Atomics", "BigInt", "BigInt64Array",
    "BigUint64Array", "Blob", "Boolean", "BroadcastChannel", "Buffer", "ByteLengthQueuingStrategy", "CloseEvent", "CompressionStream",
    "CountQueuingStrategy", "Crypto", "CryptoKey", "CustomEvent", "DOMException", "DataView", "Date", "DecompressionStream", "DisposableStack",
    "Error", "ErrorEvent", "EvalError", "Event", "EventTarget", "File", "FinalizationRegistry", "Float16Array", "Float32Array", "Float64Array",
    "FormData", "Function", "Headers", "Int16Array", "Int32Array", "Int8Array", "Intl", "Iterator", "JSON", "Map", "Math", "MessageChannel",
    "MessageEvent", "MessagePort", "Navigator", "Number", "Object", "Performance", "PerformanceEntry", "PerformanceMark", "PerformanceMeasure",
    "PerformanceObserver", "PerformanceObserverEntryList", "PerformanceResourceTiming", "Promise", "Proxy", "QuotaExceededError", "RangeError",
    "ReadableByteStreamController", "ReadableStream", "ReadableStreamBYOBReader", "ReadableStreamBYOBRequest", "ReadableStreamDefaultController",
    "ReadableStreamDefaultReader", "ReferenceError", "Reflect", "RegExp", "Request", "Response", "Set", "SharedArrayBuffer", "Storage", "String",
    "SubtleCrypto", "SuppressedError", "Symbol", "SyntaxError", "TextDecoder", "TextDecoderStream", "TextEncoder", "TextEncoderStream",
    "TransformStream", "TransformStreamDefaultController", "TypeError", "URIError", "URL", "URLPattern", "URLSearchParams", "Uint16Array",
    "Uint32Array", "Uint8Array", "Uint8ClampedArray", "WeakMap", "WeakRef", "WeakSet", "WebAssembly", "WebSocket", "WritableStream",
    "WritableStreamDefaultController", "WritableStreamDefaultWriter", "console", "crypto", "navigator", "performance", "process", "sessionStorage"
};
inline constexpr std::string_view kJsGlobalFunctionNames[] = {
    "atob", "btoa", "clearImmediate", "clearInterval", "clearTimeout", "decodeURI", "decodeURIComponent", "encodeURI", "encodeURIComponent",
    "escape", "eval", "fetch", "isFinite", "isNaN", "parseFloat", "parseInt", "queueMicrotask", "setImmediate", "setInterval", "setTimeout",
    "structuredClone", "unescape"
};
inline constexpr std::string_view kJsGlobalAliasNames[] = { "global", "globalThis", "self", "window" };

// FE-A: Go's predeclared FUNCTIONS (The Go Programming Language Specification, "Predeclared identifiers" — Functions,
// go1.21+, which added clear/max/min). A bare Go call that no same-package function answers (graph.h FalseEdgeRules —
// a bare call reaches only its own package) is external= when its name is one of these, and unresolved= otherwise (a
// local closure the extractor does not record). 18 names, transcribed from the spec's list; sorted.
inline constexpr std::string_view kGoBuiltinNames[] = {
    "append", "cap", "clear", "close", "complex", "copy", "delete", "imag", "len", "make", "max", "min", "new", "panic", "print", "println",
    "real", "recover"
};

// ── THE BUILTIN-METHOD TABLES — the member twin of the tables above (graph.h BuiltinMethodGate; gate
// test/builtinbindcheck.sh). A member call `d.get( k )` whose receiver's type no evidence rule proved is resolved by
// NAME alone, and when a repository defines exactly one method called `get` that lone definition used to take
// every such call: on a real Python corpus one `ConnectionPool.get` collected 611 callers, almost all of them
// `dict.get`. A name in these tables is a method of the language's own builtin map, list, set or string type, so a
// receiver of unproven type is at least as likely to be one of those as an instance of the in-repo class. The gate
// therefore keeps the ladder's edge only when the caller's FILE gives evidence for one of its targets (it names the
// defining class or a class in its inheritance cone); otherwise the edge is removed and the call counted (declined, or
// external when no target is reachable at all). It never adds or retargets an edge. A name NOT in a table keeps the
// ladder unchanged: the list decides only WHEN evidence is required, never what the target is.
//
// PROVENANCE, per table — each is generated by the one command shown, so it can be regenerated and diffed, never
// edited by hand. Public (non-underscore) methods only; the sortedness static_asserts below are the compile-time proof
// the binary search is valid.
//   kPythonBuiltinMethodNames — CPython 3.13.3, the builtin types dict list set frozenset str bytes bytearray tuple:
//     python3 -c "print(sorted({n for t in (dict,list,set,frozenset,str,bytes,bytearray,tuple) for n in dir(t) if not n.startswith('_')}))"
//     79 names.
//   kJsBuiltinMethodNames — Node 26.9.0 (V8), the prototypes of Object Array Map Set WeakMap WeakSet String Promise,
//     function-valued own properties minus `constructor` and the `__`-prefixed legacy accessors:
//     node -e "const s=new Set();for(const t of [Object,Array,Map,Set,WeakMap,WeakSet,String,Promise])for(const n of
//       Object.getOwnPropertyNames(t.prototype)){if(n==='constructor'||n.startsWith('__'))continue;
//       if(typeof Object.getOwnPropertyDescriptor(t.prototype,n).value==='function')s.add(n)}console.log([...s].sort())"
//     102 names. TypeScript reads the same table: it runs on the same builtin objects.
//   kRubyBuiltinMethodNames — Ruby 4.0.7, Hash Array String public_instance_methods(false), identifier-shaped names only
//     (operators such as `<<` and `[]` are never a call reference's name):
//     ruby -e 'puts [Hash,Array,String].flat_map{|t| t.public_instance_methods(false)}.map(&:to_s)
//       .select{|n| n =~ /\A[a-z_][A-Za-z0-9_]*[?!=]?\z/}.uniq.sort'
//     233 names.
// NO TABLE, BY DESIGN, for the other indexed languages — each reason is recorded in graph.h beside BuiltinMethodGate:
// Java, Kotlin, C#, Swift, Rust and ObjC record no declared parameter or local type (and an ObjC message send carries no
// receiver shape), so a gate would decline their typed true edges along with the false ones; Go's builtin types have
// no methods, and its stdlib-type receivers (`sync.Pool.Get`) need the same missing declared-type evidence; C and C++
// already carry declared-type evidence (Rule 2, 2b, CHA-lite) and want an evidence-against rule instead.
inline constexpr std::string_view kPythonBuiltinMethodNames[] = {
    "add", "append", "capitalize", "casefold", "center", "clear", "copy", "count", "decode", "difference", "difference_update", "discard", "encode",
    "endswith", "expandtabs", "extend", "find", "format", "format_map", "fromhex", "fromkeys", "get", "hex", "index", "insert", "intersection",
    "intersection_update", "isalnum", "isalpha", "isascii", "isdecimal", "isdigit", "isdisjoint", "isidentifier", "islower", "isnumeric",
    "isprintable", "isspace", "issubset", "issuperset", "istitle", "isupper", "items", "join", "keys", "ljust", "lower", "lstrip", "maketrans",
    "partition", "pop", "popitem", "remove", "removeprefix", "removesuffix", "replace", "reverse", "rfind", "rindex", "rjust", "rpartition", "rsplit",
    "rstrip", "setdefault", "sort", "split", "splitlines", "startswith", "strip", "swapcase", "symmetric_difference", "symmetric_difference_update",
    "title", "translate", "union", "update", "upper", "values", "zfill"
};
inline constexpr std::string_view kJsBuiltinMethodNames[] = {
    "add", "anchor", "at", "big", "blink", "bold", "catch", "charAt", "charCodeAt", "clear", "codePointAt", "concat", "copyWithin", "delete",
    "difference", "endsWith", "entries", "every", "fill", "filter", "finally", "find", "findIndex", "findLast", "findLastIndex", "fixed", "flat",
    "flatMap", "fontcolor", "fontsize", "forEach", "get", "getOrInsert", "getOrInsertComputed", "has", "hasOwnProperty", "includes", "indexOf",
    "intersection", "isDisjointFrom", "isPrototypeOf", "isSubsetOf", "isSupersetOf", "isWellFormed", "italics", "join", "keys", "lastIndexOf", "link",
    "localeCompare", "map", "match", "matchAll", "normalize", "padEnd", "padStart", "pop", "propertyIsEnumerable", "push", "reduce", "reduceRight",
    "repeat", "replace", "replaceAll", "reverse", "search", "set", "shift", "slice", "small", "some", "sort", "splice", "split", "startsWith",
    "strike", "sub", "substr", "substring", "sup", "symmetricDifference", "then", "toLocaleLowerCase", "toLocaleString", "toLocaleUpperCase",
    "toLowerCase", "toReversed", "toSorted", "toSpliced", "toString", "toUpperCase", "toWellFormed", "trim", "trimEnd", "trimLeft", "trimRight",
    "trimStart", "union", "unshift", "valueOf", "values", "with"
};
inline constexpr std::string_view kRubyBuiltinMethodNames[] = {
    "all?", "any?", "append", "append_as_bytes", "ascii_only?", "assoc", "at", "b", "bsearch", "bsearch_index", "byteindex", "byterindex", "bytes",
    "bytesize", "byteslice", "bytesplice", "capitalize", "capitalize!", "casecmp", "casecmp?", "center", "chars", "chomp", "chomp!", "chop", "chop!",
    "chr", "clear", "codepoints", "collect", "collect!", "combination", "compact", "compact!", "compare_by_identity", "compare_by_identity?",
    "concat", "count", "crypt", "cycle", "deconstruct", "deconstruct_keys", "dedup", "default", "default=", "default_proc", "default_proc=", "delete",
    "delete!", "delete_at", "delete_if", "delete_prefix", "delete_prefix!", "delete_suffix", "delete_suffix!", "detect", "difference", "dig",
    "downcase", "downcase!", "drop", "drop_while", "dump", "dup", "each", "each_byte", "each_char", "each_codepoint", "each_grapheme_cluster",
    "each_index", "each_key", "each_line", "each_pair", "each_value", "empty?", "encode", "encode!", "encoding", "end_with?", "eql?", "except",
    "fetch", "fetch_values", "fill", "filter", "filter!", "find", "find_index", "first", "flatten", "flatten!", "force_encoding", "freeze", "getbyte",
    "grapheme_clusters", "gsub", "gsub!", "has_key?", "has_value?", "hash", "hex", "include?", "index", "insert", "inspect", "intern", "intersect?",
    "intersection", "invert", "join", "keep_if", "key", "key?", "keys", "last", "length", "lines", "ljust", "lstrip", "lstrip!", "map", "map!",
    "match", "match?", "max", "member?", "merge", "merge!", "min", "minmax", "next", "next!", "none?", "oct", "one?", "ord", "pack", "partition",
    "permutation", "pop", "prepend", "product", "push", "rassoc", "rehash", "reject", "reject!", "repeated_combination", "repeated_permutation",
    "replace", "reverse", "reverse!", "reverse_each", "rfind", "rindex", "rjust", "rotate", "rotate!", "rpartition", "rstrip", "rstrip!", "sample",
    "scan", "scrub", "scrub!", "select", "select!", "setbyte", "shift", "shuffle", "shuffle!", "size", "slice", "slice!", "sort", "sort!", "sort_by!",
    "split", "squeeze", "squeeze!", "start_with?", "store", "strip", "strip!", "sub", "sub!", "succ", "succ!", "sum", "swapcase", "swapcase!", "take",
    "take_while", "to_a", "to_ary", "to_c", "to_f", "to_h", "to_hash", "to_i", "to_proc", "to_r", "to_s", "to_str", "to_sym", "tr", "tr!", "tr_s",
    "tr_s!", "transform_keys", "transform_keys!", "transform_values", "transform_values!", "transpose", "undump", "unicode_normalize",
    "unicode_normalize!", "unicode_normalized?", "union", "uniq", "uniq!", "unpack", "unpack1", "unshift", "upcase", "upcase!", "update", "upto",
    "valid_encoding?", "value?", "values", "values_at", "zip"
};

// ONE sortedness proof for the three tables above, taking the table as a span, so the three stay one shape rather than
// three near-copies of the assert this file already spells per table. The lookup is graph.h BuiltinMethodGate::appliesTo,
// its only reader, which picks the table by language first.
constexpr bool isStrictlySortedTable( std::span<const std::string_view> table ) noexcept
{
    return std::is_sorted( table.begin(), table.end(), rw::sortutil::svLess ) && std::adjacent_find( table.begin(), table.end() ) == table.end();
}
static_assert( isStrictlySortedTable( kPythonBuiltinMethodNames ), "kPythonBuiltinMethodNames must be strictly sorted (binary search)" );
static_assert( isStrictlySortedTable( kJsBuiltinMethodNames ), "kJsBuiltinMethodNames must be strictly sorted (binary search)" );
static_assert( isStrictlySortedTable( kRubyBuiltinMethodNames ), "kRubyBuiltinMethodNames must be strictly sorted (binary search)" );
static_assert( isStrictlySortedTable( kJsGlobalObjectNames ), "kJsGlobalObjectNames must be strictly sorted (binary search)" );
static_assert( isStrictlySortedTable( kJsGlobalFunctionNames ), "kJsGlobalFunctionNames must be strictly sorted (binary search)" );
static_assert( isStrictlySortedTable( kJsGlobalAliasNames ), "kJsGlobalAliasNames must be strictly sorted (binary search)" );
static_assert( isStrictlySortedTable( kGoBuiltinNames ), "kGoBuiltinNames must be strictly sorted (binary search)" );

// FE-A: which JS/TS global table holds `name` (graph.h FalseEdgeRules, ingest_jsimports.h) — an object (`JSON`; also a
// constructor when called bare), a function (`fetch`), or a name for the global object itself (`globalThis`).
enum class JsGlobal : std::uint8_t { None, Object, Function, GlobalObject };
inline JsGlobal jsGlobalKindOf( std::string_view name ) noexcept
{
    const auto holds = [ name ]( std::span<const std::string_view> table ) { return std::ranges::binary_search( table, name, rw::sortutil::svLess ); };
    if( holds( kJsGlobalObjectNames ) )
    {
        return JsGlobal::Object;
    }
    if( holds( kJsGlobalFunctionNames ) )
    {
        return JsGlobal::Function;
    }
    return holds( kJsGlobalAliasNames ) ? JsGlobal::GlobalObject : JsGlobal::None;
}
inline bool isJsGlobalName( std::string_view name ) noexcept   // an object or a function: a name a bare call can mean
{
    switch( jsGlobalKindOf( name ) )
    {
        case JsGlobal::Object:
        case JsGlobal::Function:
        {
            return true;
        }
        case JsGlobal::GlobalObject:
        case JsGlobal::None:
        {
            return false;
        }
    }
    return false;
}

}   // namespace externalnames
}   // namespace rw
