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
#include <iterator>
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

}   // namespace externalnames
}   // namespace rw
