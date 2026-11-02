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
//     (an operator such as `<<` is never a call reference's name; `[]`/`[]=` is one only as an element access whose
//     receiver class graph.h subscriptOperatorProven has proven, which no name table decides):
//     ruby -e 'puts [Hash,Array,String].flat_map{|t| t.public_instance_methods(false)}.map(&:to_s)
//       .select{|n| n =~ /\A[a-z_][A-Za-z0-9_]*[?!=]?\z/}.uniq.sort'
//     233 names.
// NO TABLE HERE for the other indexed languages — each reason is recorded in graph.h beside BuiltinMethodGate and
// StdMemberGate. C++ and Rust have their own tables below (kCppStdMemberNames, kRustStdMemberNames), read by a different
// rule: StdMemberGate (graph.h kStdMemberNames holds one row per language).
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

// ── THE RAILS FRAMEWORK TABLES — rows of the builtin-method gate that join only in a tree that uses the framework (graph.h
// BuiltinMethodGate::frameworkTables; ruby_frameworks.h decides which; gate test/rubyframeworknamescheck.sh). In a Rails
// application a receiver no rule typed is as often a relation, a record or a value ActiveSupport extends as it is an
// instance of the ONE in-tree class that defines a method of the same name: `scope.where( … )` bound a test double's
// `where`, `params[ :q ].present?` a value class's `present?`, `Time.zone.now` a library class's `now` — 20 of 20 such
// sampled sites wrong on one Rails application and 18 of 20 on another (docs/research/ruby-roadmap.md §2.2). A name here
// asks the gate for the same file evidence a Hash method's name does; it never adds or retargets an edge.
// PROVENANCE, per table — each generated by the one command shown (Ruby 4.0.9, Rails 8.1.4 gems), never edited by hand.
// Public, identifier-shaped names with no leading underscore; an operator is never a call reference's name.
//   kRubyActiveSupportMethodNames — what `require "active_support/all"` adds to every object (Object's new public methods:
//     blank?, present?, try, to_param, …) and the methods of the zone `Time.zone` returns (ActiveSupport::TimeZone):
//     ruby -e 'gem "activesupport","8.1.4"; b=Object.public_instance_methods; require "active_support/all";
//       puts ((Object.public_instance_methods-b)+ActiveSupport::TimeZone.public_instance_methods(false)).map(&:to_s)
//       .select{|n| n=~/\A[a-z][A-Za-z0-9_]*[?!=]?\z/}.uniq.sort'
//     47 names.
//   kRubyActiveRecordMethodNames — a record's public methods, a relation's, and a model class's, each beyond what every
//     object (or every class) already has once ActiveSupport is loaded:
//     ruby -e 'gem "activerecord","8.1.4"; require "active_support/all"; o=Object.public_instance_methods;
//       c=Class.public_instance_methods; require "active_record"; puts ((ActiveRecord::Base.public_instance_methods-o)
//       +(ActiveRecord::Relation.public_instance_methods-o)+(ActiveRecord::Base.singleton_class.public_instance_methods-c))
//       .map(&:to_s).select{|n| n=~/\A[a-z][A-Za-z0-9_]*[?!=]?\z/}.uniq.sort'
//     893 names.
// The namespaces whose constants show a tree uses each framework (ruby_frameworks.h reads a written constant's first
// segment): every Rails framework loads ActiveSupport; only ActiveRecord's own constants show ActiveRecord. Sorted by byte.
inline constexpr std::string_view kRailsNamespaces[] = {
    "ActionCable", "ActionController", "ActionDispatch", "ActionMailbox", "ActionMailer", "ActionText", "ActionView", "ActiveJob", "ActiveModel",
    "ActiveRecord", "ActiveStorage", "ActiveSupport", "Rails"
};
inline constexpr std::string_view kActiveRecordNamespaces[] = { "ActiveRecord" };
inline constexpr std::string_view kRubyActiveSupportMethodNames[] = {
    "abbr", "acts_like?", "as_json", "at", "blank?", "class_eval", "deep_dup", "dst?", "duplicable?", "encode_with", "formatted_offset", "html_safe?",
    "in?", "init_with", "instance_values", "instance_variable_names", "iso8601", "local", "local_to_utc", "match?", "name", "now", "parse",
    "period_for_local", "period_for_utc", "periods_for_local", "presence", "presence_in", "present?", "rfc3339", "standard_name", "strptime",
    "to_json", "to_param", "to_query", "to_s", "to_yaml", "today", "tomorrow", "try", "try!", "tzinfo", "utc_offset", "utc_to_local", "with",
    "with_options", "yesterday"
};
inline constexpr std::string_view kRubyActiveRecordMethodNames[] = {
    "abstract_class", "abstract_class=", "abstract_class?", "accepts_nested_attributes_for", "accessed_fields", "adapter_class", "after_commit",
    "after_create", "after_create_commit", "after_destroy", "after_destroy_commit", "after_find", "after_initialize", "after_rollback", "after_save",
    "after_save_commit", "after_touch", "after_update", "after_update_commit", "after_validation", "aggregate_reflections", "aggregate_reflections=",
    "aggregate_reflections?", "alias_attribute_method_definition", "alias_tracker", "aliases_by_attribute_name", "all", "all?",
    "all_timestamp_attributes_in_model", "and", "and!", "annotate", "annotate!", "annotate_values", "annotate_values=", "any?",
    "application_record_class?", "arel", "arel_table", "around_create", "around_destroy", "around_save", "around_update", "assign_attributes",
    "association", "association_cached?", "async_average", "async_count", "async_count_by_sql", "async_find_by_sql", "async_ids", "async_maximum",
    "async_minimum", "async_pick", "async_pluck", "async_sum", "asynchronous_queries_session", "asynchronous_queries_tracker", "attr_readonly",
    "attribute", "attribute_alias", "attribute_alias?", "attribute_aliases", "attribute_aliases=", "attribute_aliases?", "attribute_before_last_save",
    "attribute_change_to_be_saved", "attribute_changed?", "attribute_changed_in_place?", "attribute_for_inspect", "attribute_in_database",
    "attribute_method?", "attribute_method_affix", "attribute_method_patterns", "attribute_method_patterns=", "attribute_method_patterns?",
    "attribute_method_prefix", "attribute_method_suffix", "attribute_methods_generated?", "attribute_missing", "attribute_names",
    "attribute_present?", "attribute_previously_changed?", "attribute_previously_was", "attribute_types", "attribute_was", "attribute_writer_missing",
    "attributes", "attributes=", "attributes_before_type_cast", "attributes_builder", "attributes_for_database", "attributes_for_inspect",
    "attributes_for_inspect=", "attributes_for_inspect?", "attributes_in_database", "authenticate_by", "automatic_scope_inversing",
    "automatic_scope_inversing=", "automatic_scope_inversing?", "automatically_invert_plural_associations",
    "automatically_invert_plural_associations=", "automatically_invert_plural_associations?", "autosaving_belongs_to_for?", "average", "base_class",
    "base_class?", "becomes", "becomes!", "before_commit", "before_committed!", "before_create", "before_destroy", "before_save", "before_update",
    "before_validation", "belongs_to", "belongs_to_required_by_default", "belongs_to_required_by_default=", "belongs_to_required_by_default?",
    "benchmark", "bind_attribute", "build", "cache", "cache_key", "cache_key_with_version", "cache_timestamp_format", "cache_timestamp_format=",
    "cache_timestamp_format?", "cache_version", "cache_versioning", "cache_versioning=", "cache_versioning?", "cached_find_by_statement", "calculate",
    "chain", "changed", "changed?", "changed_attribute_names_to_save", "changed_attributes", "changed_for_autosave?", "changes", "changes_applied",
    "changes_to_save", "chunk", "chunk_while", "ciphertext_for", "clear_attribute_changes", "clear_cache!", "clear_changes_information",
    "clear_query_caches_for_current_thread", "clear_reflections_cache", "clear_validators!", "collect", "collect_concat",
    "collecting_queries_for_explain", "collection_cache_key", "collection_cache_versioning", "collection_cache_versioning=",
    "collection_cache_versioning?", "column_defaults", "column_for_attribute", "column_names", "columns", "columns_hash",
    "combine_signed_id_purposes", "committed!", "compact", "compact_blank", "composed_of", "composite_primary_key?",
    "composite_query_constraints_list", "configurations", "configurations=", "connected?", "connected_to", "connected_to?", "connected_to_all_shards",
    "connected_to_many", "connected_to_stack", "connecting_to", "connection", "connection_class", "connection_class=", "connection_class?",
    "connection_class_for_self", "connection_db_config", "connection_handler", "connection_handler=", "connection_pool",
    "connection_specification_name", "connection_specification_name=", "connects_to", "construct_join_dependency", "content_columns", "count",
    "count_by_sql", "counter_cache_column?", "counter_cached_association_names", "counter_cached_association_names=",
    "counter_cached_association_names?", "create", "create!", "create_or_find_by", "create_or_find_by!", "create_with", "create_with!",
    "create_with_value", "create_with_value=", "current_preventing_writes", "current_role", "current_scope", "current_scope=", "current_shard",
    "current_time_from_proper_timezone", "current_transaction", "custom_validation_context?", "cycle", "dangerous_attribute_method?",
    "dangerous_class_method?", "decorate_attributes", "decrement", "decrement!", "decrement_counter", "decrypt", "default_column_serializer",
    "default_column_serializer=", "default_column_serializer?", "default_connection_handler", "default_connection_handler=",
    "default_connection_handler?", "default_extensions", "default_role", "default_role=", "default_role?", "default_scope_override",
    "default_scope_override=", "default_scoped", "default_scopes", "default_scopes=", "default_scopes?", "default_shard", "default_shard=",
    "default_shard?", "define_attribute", "define_attribute_method", "define_attribute_method_pattern", "define_attribute_methods",
    "define_callbacks", "define_model_callbacks", "defined_enums", "defined_enums=", "defined_enums?", "delegated_type", "delete", "delete_all",
    "delete_by", "descends_from_active_record?", "destroy", "destroy!", "destroy_all", "destroy_association_async_batch_size",
    "destroy_association_async_batch_size=", "destroy_association_async_job", "destroy_association_async_job=", "destroy_by", "destroyed?",
    "destroyed_by_association", "destroyed_by_association=", "detect", "deterministic_encrypted_attributes", "disallow_raw_sql!", "distinct",
    "distinct!", "distinct_value", "distinct_value=", "drop", "drop_while", "each", "each_cons", "each_entry", "each_slice", "each_with_index",
    "each_with_object", "eager_load", "eager_load!", "eager_load_values", "eager_load_values=", "eager_loading?",
    "eagerly_generate_alias_attribute_methods", "empty?", "empty_scope?", "encode_with", "encrypt", "encrypted_attribute?", "encrypted_attributes",
    "encrypted_attributes=", "encrypted_attributes?", "encrypts", "entries", "enum", "enumerate_columns_in_select_statements",
    "enumerate_columns_in_select_statements=", "enumerate_columns_in_select_statements?", "errors", "establish_connection", "except", "exclude?",
    "excluding", "excluding!", "exec_explain", "exists?", "explain", "extending", "extending!", "extending_values", "extending_values=", "extensions",
    "extract_associated", "fifth", "fifth!", "filter", "filter_attributes", "filter_attributes=", "filter_map", "find", "find_all", "find_by",
    "find_by!", "find_by_sql", "find_by_token_for", "find_by_token_for!", "find_each", "find_in_batches", "find_index", "find_or_create_by",
    "find_or_create_by!", "find_or_initialize_by", "find_signed", "find_signed!", "find_sole_by", "finder_needs_type_condition?", "first", "first!",
    "first_or_create", "first_or_create!", "first_or_initialize", "flat_map", "forty_two", "forty_two!", "fourth", "fourth!", "from", "from!",
    "from_clause", "from_clause=", "from_json", "full_inspect", "full_table_name_prefix", "full_table_name_suffix",
    "generate_alias_attribute_methods", "generate_alias_attributes", "generate_relation_method", "generate_token_for", "generate_unique_secure_token",
    "generated_association_methods", "generated_token_verifier", "generated_token_verifier=", "generates_token_for", "get_primary_key",
    "global_current_scope", "global_current_scope=", "grep", "grep_v", "group", "group!", "group_by", "group_values", "group_values=",
    "has_and_belongs_to_many", "has_attribute?", "has_changes_to_save?", "has_limit_or_offset?", "has_many", "has_many_inversing",
    "has_many_inversing=", "has_many_inversing?", "has_one", "has_query_constraints?", "has_secure_password", "has_secure_token", "having", "having!",
    "having_clause", "having_clause=", "human_attribute_name", "i18n_scope", "id", "id=", "id?", "id_before_type_cast", "id_for_database",
    "id_in_database", "id_was", "ids", "ignored_columns", "ignored_columns=", "immutable_strings_by_default", "immutable_strings_by_default=",
    "immutable_strings_by_default?", "implicit_order_column", "implicit_order_column=", "implicit_order_column?", "in_batches", "in_groups",
    "in_groups_of", "in_order_of", "include?", "include_root_in_json", "include_root_in_json=", "include_root_in_json?", "includes", "includes!",
    "includes_values", "includes_values=", "including", "increment", "increment!", "increment_counter", "index", "index_by", "index_with",
    "inheritance_column", "inheritance_column=", "inheritance_column?", "init_attributes", "init_with", "init_with_attributes",
    "initialize_find_by_cache", "initialize_generated_modules", "initialize_internals_callback", "initialize_relation_delegate_cache", "inject",
    "insert", "insert!", "insert_all", "insert_all!", "inspection_filter", "instance_method_already_implemented?", "instantiate",
    "internal_metadata_table_name", "internal_metadata_table_name=", "internal_metadata_table_name?", "intersect?", "invalid?", "invert_where",
    "invert_where!", "join", "joined_includes_values", "joins", "joins!", "joins_values", "joins_values=", "klass", "last", "last!", "lazy",
    "lease_connection", "left_joins", "left_outer_joins", "left_outer_joins!", "left_outer_joins_values", "left_outer_joins_values=", "length",
    "limit", "limit!", "limit_value", "limit_value=", "load", "load_async", "load_schema", "loaded", "loaded?", "local_stored_attributes",
    "local_stored_attributes=", "lock", "lock!", "lock_optimistically", "lock_optimistically=", "lock_optimistically?", "lock_value", "lock_value=",
    "locked?", "locking_column", "locking_column=", "locking_enabled?", "logger", "logger=", "logger?", "lookup_ancestors", "many?", "map",
    "mark_for_destruction", "marked_for_destruction?", "marshal_load", "max", "max_by", "maximum", "member?", "merge", "merge!",
    "method_defined_within?", "min", "min_by", "minimum", "minmax", "minmax_by", "model", "model_name", "name", "nested_attributes_options",
    "nested_attributes_options=", "nested_attributes_options?", "new", "new_record?", "next_sequence_value", "no_touching", "no_touching?", "none",
    "none!", "none?", "normalize_attribute", "normalize_callback_params", "normalize_value_for", "normalized_attributes", "normalized_attributes=",
    "normalized_attributes?", "normalized_reflections", "normalizes", "null_relation?", "offset", "offset!", "offset_value", "offset_value=", "one?",
    "only", "only_columns", "only_columns=", "optimizer_hints", "optimizer_hints!", "optimizer_hints_values", "optimizer_hints_values=", "or", "or!",
    "order", "order!", "order_values", "order_values=", "param_delimiter", "param_delimiter=", "param_delimiter?", "partial_inserts",
    "partial_inserts=", "partial_inserts?", "partial_updates", "partial_updates=", "partial_updates?", "partition", "persisted?", "pick", "pluck",
    "pluralize_table_names", "pluralize_table_names=", "pluralize_table_names?", "polymorphic_class_for", "polymorphic_name",
    "pool_transaction_isolation_level", "populate_with_current_scope_attributes", "predicate_builder", "prefetch_primary_key?", "preload", "preload!",
    "preload_associations", "preload_values", "preload_values=", "pretty_print", "preventing_writes?", "previous_changes", "previously_new_record?",
    "previously_persisted?", "primary_abstract_class", "primary_class?", "primary_key", "primary_key=", "primary_key_prefix_type",
    "primary_key_prefix_type=", "primary_key_prefix_type?", "primary_key_values_present?", "prohibit_shard_swapping", "protected_environments",
    "protected_environments=", "query_attribute", "query_constraints", "query_constraints_list", "quoted_primary_key", "quoted_table_name",
    "raise_record_not_found_exception!", "read_attribute", "read_attribute_before_type_cast", "read_attribute_for_database",
    "read_attribute_for_serialization", "read_attribute_for_validation", "readonly", "readonly!", "readonly?", "readonly_attribute?",
    "readonly_attributes", "readonly_value", "readonly_value=", "real_inheritance_column=", "record_timestamps", "record_timestamps=",
    "record_timestamps?", "records", "reduce", "references", "references!", "references_values", "references_values=", "reflect_on_aggregation",
    "reflect_on_all_aggregations", "reflect_on_all_associations", "reflect_on_all_autosave_associations", "reflect_on_association", "reflections",
    "regroup", "regroup!", "reject", "relation_delegate_class", "release_connection", "reload", "remove_connection", "reorder", "reorder!",
    "reordering_value", "reordering_value=", "require_dependency", "reselect", "reselect!", "reset", "reset_callbacks", "reset_column_information",
    "reset_counters", "reset_locking_column", "reset_primary_key", "reset_sequence_name", "reset_table_name", "respond_to_without_attributes?",
    "restore_attributes", "retrieve_connection", "reverse", "reverse_each", "reverse_order", "reverse_order!", "reverse_order_value",
    "reverse_order_value=", "rewhere", "rindex", "rolledback!", "rotate", "run_callbacks",
    "run_commit_callbacks_on_first_saved_instances_in_transaction", "run_commit_callbacks_on_first_saved_instances_in_transaction=",
    "run_commit_callbacks_on_first_saved_instances_in_transaction?", "sample", "sanitize_sql", "sanitize_sql_array", "sanitize_sql_for_assignment",
    "sanitize_sql_for_conditions", "sanitize_sql_for_order", "sanitize_sql_hash_for_assignment", "sanitize_sql_like", "save", "save!",
    "saved_change_to_attribute", "saved_change_to_attribute?", "saved_changes", "saved_changes?", "scheduled?", "schema_cache",
    "schema_migrations_table_name", "schema_migrations_table_name=", "schema_migrations_table_name?", "scope", "scope_attributes",
    "scope_attributes?", "scope_for_association", "scope_for_create", "scope_registry", "scoping", "second", "second!", "second_to_last",
    "second_to_last!", "select", "select_values", "select_values=", "sequence_name", "sequence_name=", "serializable_hash", "serialize",
    "set_callback", "shard_keys", "shard_selector", "shard_selector=", "shard_selector?", "shard_swapping_prohibited?", "sharded?", "shuffle",
    "signed_id", "signed_id_verifier", "signed_id_verifier=", "signed_id_verifier_secret", "signed_id_verifier_secret=", "signed_id_verifier_secret?",
    "size", "skip_callback", "skip_preloading!", "skip_preloading_value", "skip_preloading_value=", "skip_query_cache!", "skip_query_cache_value",
    "skip_query_cache_value=", "skip_time_zone_conversion_for_attributes", "skip_time_zone_conversion_for_attributes=",
    "skip_time_zone_conversion_for_attributes?", "slice", "slice_after", "slice_before", "slice_when", "sole", "sort", "sort_by",
    "source_attribute_from_preserved_attribute", "spawn", "split", "sti_class_for", "sti_name", "store", "store_accessor", "store_full_class_name",
    "store_full_class_name=", "store_full_class_name?", "store_full_sti_class", "store_full_sti_class=", "store_full_sti_class?", "stored_attributes",
    "strict_loading", "strict_loading!", "strict_loading?", "strict_loading_all?", "strict_loading_by_default", "strict_loading_by_default=",
    "strict_loading_by_default?", "strict_loading_mode", "strict_loading_mode=", "strict_loading_mode?", "strict_loading_n_plus_one_only?",
    "strict_loading_value", "strict_loading_value=", "strict_loading_violation!", "structurally_compatible?", "sum", "suppress",
    "symbol_column_to_string", "table", "table_exists?", "table_name", "table_name=", "table_name_prefix", "table_name_prefix=", "table_name_prefix?",
    "table_name_qualified_unscope_values", "table_name_suffix", "table_name_suffix=", "table_name_suffix?", "take", "take!", "take_while", "tally",
    "third", "third!", "third_to_last", "third_to_last!", "time_zone_aware_attributes", "time_zone_aware_attributes=", "time_zone_aware_attributes?",
    "time_zone_aware_types", "time_zone_aware_types=", "time_zone_aware_types?", "timestamp_attributes_for_create_in_model",
    "timestamp_attributes_for_update_in_model", "to_a", "to_ary", "to_formatted_s", "to_fs", "to_h", "to_key", "to_model", "to_partial_path",
    "to_sentence", "to_set", "to_sql", "to_xml", "toggle", "toggle!", "token_definitions", "token_definitions=", "touch", "touch_all",
    "touch_attributes_with_time", "touch_later", "transaction", "trigger_transactional_callbacks?", "type_caster", "type_for_attribute", "uncached",
    "undefine_attribute_methods", "uniq", "uniq!", "unscope", "unscope!", "unscope_values", "unscope_values=", "unscoped", "update", "update!",
    "update_all", "update_attribute", "update_attribute!", "update_column", "update_columns", "update_counters", "upsert", "upsert_all", "valid?",
    "validate", "validate!", "validates", "validates!", "validates_absence_of", "validates_acceptance_of", "validates_associated",
    "validates_comparison_of", "validates_confirmation_of", "validates_each", "validates_exclusion_of", "validates_format_of",
    "validates_inclusion_of", "validates_length_of", "validates_numericality_of", "validates_presence_of", "validates_size_of",
    "validates_uniqueness_of", "validates_with", "validating_belongs_to_for?", "validation_context", "validators", "validators_on", "values",
    "values_at", "values_for_queries", "where", "where!", "where_clause", "where_clause=", "where_values_hash", "while_preventing_writes",
    "will_save_change_to_attribute?", "with!", "with_connection", "with_lock", "with_pool_transaction_isolation_level", "with_recursive",
    "with_recursive!", "with_transaction_returning_status", "with_values", "with_values=", "without", "write_attribute", "yaml_encoder", "yaml_tag",
    "zip"
};

// ── THE C++ STANDARD-MEMBER TABLE (graph.h StdMemberGate; gate test/stdmembergatecheck.sh). A C++ member call
// `out.push_back( c )` whose receiver no rule typed used to bind by NAME to whatever in-tree class defines `push_back`:
// on this repository's own map the top 20 PageRank rows were 14 such names (svector::push_back, WidePath::c_str,
// ElixirResolver::append, every `empty`/`find` in src/), fed by calls on `std::vector`, `std::string` and friends. A
// standard container is a concrete, non-virtual class template, so a receiver of standard type never dispatches into
// the tree — the call's other candidate is always the standard library's own member. A name here makes StdMemberGate
// DECLINE such a call (no edge, counted, disclosed) instead of letting the name pick an in-tree definition. A call
// whose receiver a rule typed (Rule 1/2/2b, `this`) is never touched, and neither is one whose recorded written type —
// a local's, a parameter's, a field's or a namespace-scope variable's — names an in-tree class that may define the
// callee: the class itself, an alias of it, or the pointee of a `->` (kCppStdArrowTemplates below, an in-tree class
// with its own `operator->`, a class the tree does not define), or the element type of ONE element access of a std container
// (kCppStdElementFirstArg below). What the index records no written type for (a call result, an iterator, `auto`, a
// dereference, a second element access) is graph.h StdMemberGate's stated floor.
// PROVENANCE: transcribed from the C++23 member synopses of the sequence, associative and unordered containers
// ([containers]), basic_string and basic_string_view ([strings]), span ([views.span]), optional ([optional]) and the
// smart pointers ([smartptr]) — MINUS every name that is also a generic verb or noun non-container classes routinely
// define for themselves (get set reset release swap count value index compare copy replace merge extract splice remove
// remove_if unique sort reverse fill first last lock top push pop transform and_then or_else error expired), and minus
// every iostream, filesystem, atomic, thread and chrono member (read write flush open close string str load store join
// wait), whose unproven-receiver calls are an unmeasured mix of standard and in-tree types. 78 names; sorted by byte.
inline constexpr std::string_view kCppStdMemberNames[] = {
    "append", "append_range", "assign", "assign_range", "at", "back", "before_begin", "begin", "bucket_count", "c_str", "capacity",
    "cbefore_begin", "cbegin", "cend", "clear", "contains", "crbegin", "crend", "data", "emplace", "emplace_after", "emplace_back",
    "emplace_front", "emplace_hint", "empty", "end", "ends_with", "equal_range", "erase", "erase_after", "find", "find_first_not_of",
    "find_first_of", "find_last_not_of", "find_last_of", "front", "get_allocator", "has_value", "hash_function", "insert", "insert_after",
    "insert_or_assign", "insert_range", "insert_range_after", "key_comp", "key_eq", "length", "load_factor", "lower_bound", "max_bucket_count",
    "max_load_factor", "max_size", "owner_before", "pop_back", "pop_front", "prepend_range", "push_back", "push_front", "rbegin", "rehash",
    "remove_prefix", "remove_suffix", "rend", "reserve", "resize", "resize_and_overwrite", "rfind", "shrink_to_fit", "size", "size_bytes",
    "starts_with", "subspan", "substr", "try_emplace", "upper_bound", "use_count", "value_comp", "value_or"
};

// ── THE RUST STANDARD-MEMBER TABLE (graph.h kStdMemberNames' Rust row; gate test/stdmembergatecheck.sh arm R). The same
// defect in Rust: `v.push( x )` on a `&mut Vec<T>` parameter, `m.insert( k, v )` on a map, `xs.iter()` bound by NAME to an
// in-tree `push` / `insert` / `iter` (on rust-lang/mdBook, 6 of the 8 printed callers of `iter` were `.iter()` on a Vec or a
// HashMap). Rust has no inheritance and these std types are concrete, so a receiver of std type never dispatches into the
// tree; a trait method an in-tree type implements is the other case, and every such name is left OUT below.
// PROVENANCE: written from the Rust standard library documentation's inherent methods of Vec / slice, String / str,
// HashMap / BTreeMap / HashSet and their Entry, Option / Result, and the Iterator / ToOwned / ToString trait methods those
// types are almost always reached through — MINUS every name an in-tree type commonly defines for itself: trait methods
// in-tree types implement on purpose (next, read, write, flush, clone, fmt, from, into, default, eq, cmp, hash, drop, deref,
// index, and the conversion/collection traits into_iter extend as_ref as_mut borrow borrow_mut — over 311 crates of
// crates.io source their in-tree definitions are mostly trait impls: into_iter 195 of 201, extend 87/106, as_ref 180/226,
// as_mut 26/43, borrow_mut 6/8, and borrow is defined in 32 crates (95 defs, RefCell-style wrappers); rust-lang/mdBook
// defines none of the six, so dropping them moved no row there), generic verbs (get, set, map, remove, clear, take,
// replace, find, filter, run, build, lock, join, send, close, first, last, sort), and `expect` (a parser's own
// `expect( token )` is common). Unlike C++ the receiver exception has no Rust written type to read yet (no parameter,
// local or field type is recorded), so a receiver written as an in-tree type is declined too: graph.h's stated floor.
// 40 names; sorted by byte.
inline constexpr std::string_view kRustStdMemberNames[] = {
    "and_then", "as_bytes", "as_slice", "as_str", "chars", "collect", "contains", "contains_key", "drain", "ends_with", "entry",
    "extend_from_slice", "get_mut", "insert", "is_empty", "is_none", "is_some", "iter", "iter_mut", "keys", "len", "ok_or",
    "or_insert", "or_insert_with", "pop", "push", "push_str", "retain", "starts_with", "to_lowercase", "to_owned", "to_string",
    "to_uppercase", "to_vec", "trim", "unwrap", "unwrap_or", "unwrap_or_default", "unwrap_or_else", "values"
};

// ── THE KOTLIN SCOPE-FUNCTION TABLE (graph.h FalseEdgeRules, the Kotlin arm; gate test/kotlincheck.sh §15 and test/falseedgecheck.sh
// arm J). A Kotlin call with a TRAILING lambda to one of these names is the stdlib scope function, never a Java method of the same
// name: `s.run { }`, `with( sb ) { }`, `s?.let { }`, `xs.also { }`. The fact is the call's trailing lambda (ingest_metrics.h
// kotlinTrailingLambda); the name alone is never a veto — `block.run()` on a Runnable has no lambda and keeps its edge.
// PROVENANCE: the five functions the Kotlin documentation names as scope functions — "There are five of them: let, run, with,
// apply, and also" (https://kotlinlang.org/docs/scope-functions.html, read 2026-10-24) — each an inline function of kotlin-stdlib
// 2.4.0 (https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-stdlib/2.4.0/kotlin-stdlib-2.4.0.jar), class
// kotlin.StandardKt__StandardKt. Regenerated and diffed by ONE command, which prints exactly these five names:
//     javap -p -cp kotlin-stdlib-2.4.0.jar kotlin.StandardKt__StandardKt | sed -n 's/.* \([a-z][A-Za-z]*\)(.*/\1/p' | grep -xE 'let|run|with|apply|also' | LC_ALL=C sort -u
// takeIf, takeUnless, repeat and use stay OUT: the documentation does not call them scope functions, and no corpus evidence joined them.
// 5 names; sorted by byte (isStrictlySortedTable below).
inline constexpr std::string_view kKotlinScopeFunctionNames[] = { "also", "apply", "let", "run", "with" };

// The standard templates whose `->` reaches their FIRST template argument, so a `->` call through a declaration written
// `std::unique_ptr<ns::List>` / `std::shared_ptr<…>` / `std::optional<…>` may be a member of that argument (graph.h
// StdMemberGate::stdArrowPointee reads the declaration's recorded text). std::weak_ptr and std::reference_wrapper have no
// `->`; a standard container reached through `->` is a raw pointer to the container, whose own member is the call. The
// member-field capture reads the two smart pointers alone (ingest_relations.h kStdSmartPointers). Sorted by byte.
inline constexpr std::string_view kCppStdArrowTemplates[] = { "optional", "shared_ptr", "unique_ptr" };

// The standard containers whose ELEMENT ACCESS — `c[ k ]`, `c.at( k )`, `c.front()`, `c.back()` — yields a template argument the
// declaration wrote, so a member call on that element may be a member of that argument (graph.h stdElementType reads
// the container's recorded text; ingest_relations.h stdElementContainerText records it for a member field and a type alias). The
// sequence containers and span yield their FIRST argument; the subscriptable maps their SECOND, the mapped type. Not here: the
// strings (an element is a character), std::set (no element access), multimap (no `[]` / `at`), and every container adaptor.
// Sorted by byte.
inline constexpr std::string_view kCppStdElementFirstArg[]  = { "array", "deque", "forward_list", "list", "span", "vector" };
inline constexpr std::string_view kCppStdElementSecondArg[] = { "flat_map", "map", "unordered_map" };

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
static_assert( isStrictlySortedTable( kRubyActiveSupportMethodNames ), "kRubyActiveSupportMethodNames must be strictly sorted (binary search)" );
static_assert( isStrictlySortedTable( kRubyActiveRecordMethodNames ), "kRubyActiveRecordMethodNames must be strictly sorted (binary search)" );
static_assert( isStrictlySortedTable( kRailsNamespaces ) && isStrictlySortedTable( kActiveRecordNamespaces ), "the framework namespaces must be strictly sorted" );
static_assert( isStrictlySortedTable( kCppStdMemberNames ), "kCppStdMemberNames must be strictly sorted (binary search)" );
static_assert( isStrictlySortedTable( kRustStdMemberNames ), "kRustStdMemberNames must be strictly sorted (binary search)" );
static_assert( isStrictlySortedTable( kCppStdArrowTemplates ), "kCppStdArrowTemplates must be strictly sorted (binary search)" );
static_assert( isStrictlySortedTable( kCppStdElementFirstArg ), "kCppStdElementFirstArg must be strictly sorted (binary search)" );
static_assert( isStrictlySortedTable( kCppStdElementSecondArg ), "kCppStdElementSecondArg must be strictly sorted (binary search)" );
static_assert( isStrictlySortedTable( kKotlinScopeFunctionNames ), "kKotlinScopeFunctionNames must be strictly sorted (binary search)" );
// #155: the lookup of a strictly sorted table (isStrictlySortedTable), taken as a span so a new table reuses it.
inline bool inSortedTable( std::span<const std::string_view> table, std::string_view name ) noexcept
{
    return std::binary_search( table.begin(), table.end(), name, rw::sortutil::svLess );
}
inline bool isKotlinScopeFunction( std::string_view name ) noexcept
{
    return inSortedTable( kKotlinScopeFunctionNames, name );
}

// Which template argument an element access of the standard container `name` ("map", "vector") yields: 0 or 1, or -1 when `name`
// is no container of kCppStdElementFirstArg / kCppStdElementSecondArg.
constexpr int cppStdElementArgIndex( std::string_view name ) noexcept
{
    if( std::binary_search( std::begin( kCppStdElementFirstArg ), std::end( kCppStdElementFirstArg ), name, rw::sortutil::svLess ) )
    {
        return 0;
    }
    return std::binary_search( std::begin( kCppStdElementSecondArg ), std::end( kCppStdElementSecondArg ), name, rw::sortutil::svLess ) ? 1 : -1;
}
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
