// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  platform.h
//
//  The compiler/platform substrate every other infra header sits on: the attribute
//  macros and the cache-line interference sizes. Namespace is `infra::platform`.
//
//  Split out of this tree's own fastmath.h (2026-08-09) along the line "describes the
//  MACHINE" vs "computes a NUMBER": ALWAYS_INLINE, memorycopy, and a cache-line width
//  are facts about the compilation target, not math, and a header that needs only
//  those should not have to pull in fastmath.h's number helpers to get them.
//  fastmath.h #includes this header, so its own includers still see ALWAYS_INLINE,
//  memorycopy, and the interference sizes exactly as before this split.
//
//  PORTING NOTE — this file is hand-copied, file for file, to and from a companion
//  C++ game-math tree that vendors the same infra set. Keep the sibling include below
//  BARE (`#include "Diagnostics.h"`, never a directory-prefixed path) — the
//  destination tree's layout differs and a hardcoded prefix breaks on arrival.
//
//  Every macro and constant below has a real call site above this layer; nothing is
//  kept "in case". (The companion tree also carries a `memorycopyinline` macro
//  immediately below `memorycopy` — there is no caller for it in this tree, so it is
//  not mirrored here.)
//

#pragma once

#include <cstddef>       // std::size_t for the hardware-interference-size constants
#include <cstring>       // std::memcpy — memorycopy's portable arm, on a compiler with no __builtin_memcpy
#include <limits>        // std::numeric_limits — the checked-multiply arm's INT_MIN / -1 case
#include <type_traits>   // std::make_unsigned_t — the checked-arithmetic arms wrap through the unsigned twin

// ==========================================================================
// Compiler attributes
// ==========================================================================

// Every macro in this section picks a spelling by COMPILER IDENTITY, never by operating system. These are
// language extensions, not platform features: clang-cl compiles for Windows and has the GNU spellings, while a
// hypothetical cl.exe on another OS would not. `test/osswitchcheck.sh` arm A enforces exactly that distinction —
// an OS-conditional name in a directive outside src/infra/os.h is a FAIL — and src/infra/Diagnostics.h §1/§1b
// set the house shape this section follows. Architecture macros (`_M_X64`, `__aarch64__`) are a third axis and
// are fine here; the cache-line block at the bottom of this file already keys on them.
//
// The GNU arm is `__clang__ || __GNUC__`. The `#else` arm is MSVC's cl.exe, the second supported front end
// (CONTRIBUTING.md: Unix/Linux/macOS first, native Windows second, clang-cl primary and cl.exe must also build).
//
// WHERE THE REST OF THE SEAM IS, and why it is not all here. Diagnostics.h is the layer BELOW this file — this
// header includes it, it includes nothing of ours, and it is deliberately library-free so every standalone
// harness in test/ can compile it alone. It therefore cannot use the macros below, and it carries the six its
// own macros need (RW_TRAP, RW_UNREACHABLE_HINT, RW_LIKELY, RW_COLD, RW_COLD_NOINLINE) in its §1c.
// That is a LAYERING split, not a second seam: no spelling is defined in both files, and each one lives where
// its only consumers are. A new extension goes here unless Diagnostics.h is the only caller.

#ifdef __clang__
#define ALWAYS_INLINE  [[clang::always_inline]] inline
#elif defined(__GNUC__)
#define ALWAYS_INLINE  __attribute__((always_inline)) inline
#else
// [[msvc::forceinline]] is an attribute, so it sits in the same syntactic position the other two arms use and
// this macro stays a drop-in at every call site. __forceinline is a declaration specifier and would not.
#define ALWAYS_INLINE  [[msvc::forceinline]] inline
#endif

#if defined(__clang__) || defined(__GNUC__)
#define memorycopy(dst,src,size)  __builtin_memcpy(dst,src,size)
#else
#define memorycopy(dst,src,size)  std::memcpy(dst,src,size)
#endif

// RW_PRINTF_FORMAT( fmtIndex, firstArgIndex ) — tell the compiler a variadic function takes a printf format, so it
// type-checks the arguments against it. Indices are 1-based and count `this` for a member function. MSVC has no
// counterpart in the language (it offers only the SAL annotation _Printf_format_string_ on the parameter, which is
// a different mechanism at a different position), so that arm is empty: the checking is lost on cl.exe and the
// other legs keep holding it. CONTRIBUTING.md routes new output through rw::emitTo, so this has exactly one caller
// — profileScope.h's stderr reporter — and should not gain another.
#if defined(__clang__) || defined(__GNUC__)
#define RW_PRINTF_FORMAT(fmtIndex,firstArgIndex)  __attribute__(( format( printf, fmtIndex, firstArgIndex ) ))
#else
#define RW_PRINTF_FORMAT(fmtIndex,firstArgIndex)
#endif

// RW_ATTR_USED — keep a definition the optimizer can prove is never referenced. structlayout.h's self-registering
// layout records are the caller: each is a file-scope object whose constructor is the only thing that runs, so
// without this the linker is free to drop the registration and the record silently never appears. MSVC keeps such
// an object anyway for a non-trivial constructor at namespace scope, so the empty arm is correct rather than a
// concession — there is no __declspec that means `used`, and none is needed.
#if defined(__clang__) || defined(__GNUC__)
#define RW_ATTR_USED  __attribute__(( used ))
#else
#define RW_ATTR_USED
#endif

// RW_LIFETIMEBOUND — on a parameter (after its name) or on `this` (after the member function's cv-qualifiers): the
// returned reference or view points INTO this argument. Clang then reports, under the -Werror=dangling fence in
// CMakeLists.txt, a caller that binds the result to a temporary that dies at the end of the full-expression
// (`const std::string& r = f( std::string( "x" ) );`), and clang-tidy's bugprone-return-const-ref-from-parameter
// stops reporting the function, since the hazard it names is now checked at every call site. Clang and clang-cl
// only: GCC warns on the unknown `clang::` attribute (-Wattributes), and cl.exe's [[msvc::lifetimebound]] is read
// only by /analyze (C26815/C26816), which no Windows leg runs — so both arms are empty, and the fence there is the
// rest of the matrix. Put it only where a function really returns a view of an argument; it is a promise clang
// checks callers against, not a comment.
#if defined(__clang__) && defined(__has_cpp_attribute)
#if __has_cpp_attribute( clang::lifetimebound )
#define RW_LIFETIMEBOUND  [[clang::lifetimebound]]
#endif
#endif
#ifndef RW_LIFETIMEBOUND
#define RW_LIFETIMEBOUND
#endif

// --------------------------------------------------------------------------
// Opaque-value barrier
// --------------------------------------------------------------------------
// Forces `var` to exist in a register the optimizer cannot see through, so a bit-pattern test done on it is not
// constant-folded. Its one purpose is to survive a compiler that has been told no operand is NaN or infinite:
// under -ffinite-math-only (which -ffast-math implies) a finiteness test folds to constant true. Callers:
// fastmath.h::isFiniteFast and charconvcompat.h::isInfiniteBits.
//
// BE CLEAR ABOUT WHEN THAT IS LIVE, because the flags say it usually is not. Every architecture arm of this
// build's flag selection that passes -ffast-math passes -fno-finite-math-only immediately after it (the native,
// Apple-Silicon, x86-64-v3 and generic arms alike), so on the builds actually shipped here, finite-math
// assumptions are OFF and the barrier is defending against a configuration nobody currently compiles. It earns
// its place as a guard on the callers, not as a load-bearing part of today's build: drop the -fno- from one arm
// and the test silently becomes constant true, which is exactly the failure a bit-pattern check exists to avoid.
//
// The MSVC arm is EMPTY, and the reason is the flag this tree passes rather than a claim about the compiler.
// All four MSVC arms pass /fp:precise explicitly, which evaluates to the source semantics, so there is nothing
// to defeat and a barrier would cost a register round-trip for nothing. It would NOT be safe to assume the same
// under /fp:fast: Microsoft documents that model as licensing exactly this assumption — their own example is
// `NAN == NAN` evaluating to 1 — so if an arm ever adopts /fp:fast, this is the arm that has to grow a body,
// and the empty one becomes a bug rather than an optimization.
//
// This is NOT a general optimization barrier and must not be reused as one: it constrains a single value, not
// memory. Diagnostics::ClobberMemory and Diagnostics::DoNotOptimize are the benchmark barriers, and they
// already carry their own no-inline-asm fallback.
#if defined(__clang__) || defined(__GNUC__)
#define RW_OPAQUE(var)             asm volatile( "" : "+r"( var ) )
#else
#define RW_OPAQUE(var)             ( (void)0 )
#endif

// --------------------------------------------------------------------------
// Software prefetch
// --------------------------------------------------------------------------
// RW_PREFETCH_READ_NT( addr ) — bring a line toward the core for an imminent READ that will not be reused
// (__builtin_prefetch's rw=0, locality=0). sparseCsr.h's SpMV is the only caller: it walks an indirection array
// and prefetches the x[] elements two iterations ahead.
//
// Architecture, not OS, decides the MSVC spelling, and the two are not interchangeable: _mm_prefetch is an
// x86 SSE intrinsic and does not exist on MSVC/ARM64, which spells the same thing __prefetch. Rather than
// guess at a Windows-on-ARM target no CI leg builds, that arm expands to nothing — a prefetch is a hint, so
// dropping it is always correct and costs at most the latency it would have hidden.
#if defined(__clang__) || defined(__GNUC__)
#define RW_PREFETCH_READ_NT(addr)  __builtin_prefetch( (addr), 0, 0 )
#elif defined(_M_X64) || defined(_M_IX86)
#include <intrin.h>                                     // _mm_prefetch — a compiler intrinsic header, not a system header
#define RW_PREFETCH_READ_NT(addr)  _mm_prefetch( reinterpret_cast<const char*>( addr ), _MM_HINT_NTA )
#else
#define RW_PREFETCH_READ_NT(addr)  ( (void)0 )
#endif

// Diagnostics.h provides ASSUME, EXPECTS, ENSURES, DASSERT, UNREACHABLE, VALIDATE, PANIC, and
// DISCLOSE. Included here, not merely alongside, because this header is
// the one every infra consumer already takes for the attribute macros and the
// cache-line constants — sparseCsr.h and radixSort.h document that dependency.
#include "Diagnostics.h"

// ==========================================================================
// infra::platform — facts about the machine this tree compiles for
// ==========================================================================

namespace infra::platform
{

// Cache-line size constants — follow the C++17 std::hardware_*_interference_size
// naming convention. Provided here as project-owned constexpr values because
// libc++ doesn't always ship the std:: versions (ABI-stability concerns) and we
// need the values correct for the production target — Apple Silicon (A11+ /
// M-series) uses 128-byte L1d cache lines vs 64 on commodity x86.
//
//   hardware_destructive_interference_size  : minimum offset between two objects
//       to avoid FALSE SHARING across cores. Pad cross-thread shared structs to
//       this — the per-thread radix histograms and the profiler's counter rows.
//
//   hardware_constructive_interference_size : maximum size of contiguous memory
//       likely to SHARE one L1 cache line. Align hot SoA array STARTS to this so
//       the first SIMD load lands inside a fresh line. This is the one the CSR
//       rowOffsets/colIndices/values arrays are allocated against.
//
// Numerically identical on every target we ship to; the two names exist so the
// call site documents which kind of layout problem it is preventing.
#if defined(_M_ARM) || defined(_M_ARM64) || defined(__arm__) || defined(__aarch64__)
    constexpr std::size_t hardware_destructive_interference_size  = 128;
    constexpr std::size_t hardware_constructive_interference_size = 128;
#else
    constexpr std::size_t hardware_destructive_interference_size  = 64;
    constexpr std::size_t hardware_constructive_interference_size = 64;
#endif


// ==========================================================================
// Wrapping multiply, sanitizer-clean
// ==========================================================================
// The low 64 bits of a * b. Trivial arithmetic, and it needs a seam for one reason: the tree builds under G1's
// `integer` group with -fno-sanitize-recover=all, and that group flags `a * b` on two uint64s as
// `unsigned-integer-overflow` the moment the product exceeds 2^64 — even though C++ DEFINES the wrap. Every
// FNV-1a step does exactly that, so a narrow multiply aborts the sanitizer build on the first byte of the first
// hash of every crawl (measured: rc=134 at hashutil.h, `1469598103934665703 * 1099511628211`).
//
// The house answer to that sanitizer, everywhere it comes up, is to write arithmetic that genuinely does not
// overflow rather than to suppress the check — src/infra/gitblob.h says it explicitly ("every modular add is
// done in uint64_t and masked back (the same posture infra/hashutil.h's multiplyModulo64 takes)"), and its
// rotate masks the bits it is about to shift out for the same reason. So this does the multiply in a type wide
// enough to hold the whole product and masks back, which is not an overflow at all and needs no annotation.
//
// What does the work here is the WIDE multiply: at 128 bits the product of two uint64s cannot wrap, so
// `unsigned-integer-overflow` has nothing to report. The mask is intent-documenting and free — it folds away at
// -O2 — but it is NOT what keeps the narrowing clean, and an earlier version of this comment claimed it was.
// Measured 2026-09-21: the `integer` group's implicit-integer-truncation does not fire on an EXPLICIT
// static_cast, masked or not; both variants run clean. It fires on an implicit narrowing (`std::uint64_t out =
// wideProduct;`), which aborts at rc=134. So the cast must stay explicit; the mask is a courtesy to the reader.
//
// MSVC has neither the 128-bit integer nor that sanitizer group, so its arm is the plain wrapping multiply —
// correct, and the cheapest thing that is correct. This is the whole reason the function is here rather than
// written out at its one call site: `__int128` is a GCC/Clang extension, test/osswitchcheck.sh arm H refuses it
// outside this seam, and the refusal is right — the spelling needs a per-compiler answer.
[[nodiscard]] ALWAYS_INLINE constexpr std::uint64_t multiplyLow64( std::uint64_t lhs, std::uint64_t rhs ) noexcept
{
#if defined(__clang__) || defined(__GNUC__)
    using Wide = unsigned __int128;
    constexpr Wide kMask64 = Wide( ~std::uint64_t( 0 ) );
    return static_cast<std::uint64_t>( ( Wide( lhs ) * Wide( rhs ) ) & kMask64 );
#else
    return lhs * rhs;
#endif
}

// The low 64 bits of lhs + rhs + carry (carry is 0 or 1), and the carry out of bit 63 written back to `carry`: one word
// of a multi-word add (clones.h CloneLcsBits, the bit-parallel LCS). Same posture as multiplyLow64 above: the sum is
// formed in 128 bits, so nothing wraps for the `integer` sanitizer group, and the explicit casts take the two halves
// (the compiler emits add / adc). MSVC's arm is the plain wrapping add with the carry read from the compares.
[[nodiscard]] ALWAYS_INLINE constexpr std::uint64_t addWithCarry64( std::uint64_t lhs, std::uint64_t rhs, std::uint64_t& carry ) noexcept
{
#if defined(__clang__) || defined(__GNUC__)
    using Wide = unsigned __int128;
    constexpr Wide kMask64 = Wide( ~std::uint64_t( 0 ) );
    const Wide     sum     = Wide( lhs ) + Wide( rhs ) + Wide( carry );
    carry                  = static_cast<std::uint64_t>( sum >> 64 );
    return static_cast<std::uint64_t>( sum & kMask64 );
#else
    const std::uint64_t partial = lhs + rhs;
    const std::uint64_t sum     = partial + carry;
    carry                       = std::uint64_t( partial < lhs ) | std::uint64_t( sum < partial );
    return sum;
#endif
}

// ==========================================================================
// Checked integer arithmetic
// ==========================================================================
// GCC and Clang answer "did this overflow?" with one instruction and a flag read. MSVC has no counterpart, so a
// portable twin re-derives the same answer from the operands. Both have the SAME contract, which is the
// __builtin_*_overflow contract and not the C++ one: `out` is ALWAYS written, with the mathematically correct
// result when the return is false and the wrapped two's-complement result when it is true, and a true return is
// never undefined behaviour. Callers rely on that — layout.h evaluates a constant expression and reports
// out-of-range, statclock.h clamps a timespec conversion.
//
// WHY THE PORTABLE TWIN IS COMPILED EVERYWHERE, not just on MSVC. An arm that only compiles on the one platform
// no one here can run is an arm nobody has executed. These are `constexpr` and always compiled, the static_asserts
// below evaluate them on EVERY leg including this one, and only the CHOICE between twin and builtin is
// conditional. A bug in the MSVC path therefore fails a macOS build, not a Windows CI round.
//
// Each twin computes the wrapped result through the unsigned type of the same width, because signed overflow is
// itself UB and computing it to test for it would be the bug these functions exist to avoid; the test then reads
// only the SIGNS of the operands and of that defined result.
namespace detail
{
template<class T> using Unsigned = std::make_unsigned_t<T>;

template<class T>
[[nodiscard]] constexpr bool addOverflowPortable( T a, T b, T* out ) noexcept
{
    *out = static_cast<T>( static_cast<Unsigned<T>>( a ) + static_cast<Unsigned<T>>( b ) );
    return ( ( a ^ *out ) & ( b ^ *out ) ) < 0;   // both operands' signs differ from the result's
}

template<class T>
[[nodiscard]] constexpr bool subOverflowPortable( T a, T b, T* out ) noexcept
{
    *out = static_cast<T>( static_cast<Unsigned<T>>( a ) - static_cast<Unsigned<T>>( b ) );
    return ( ( a ^ b ) & ( a ^ *out ) ) < 0;      // the operands differ in sign AND the result differs from a
}

template<class T>
[[nodiscard]] constexpr bool mulOverflowPortable( T a, T b, T* out ) noexcept
{
    *out = static_cast<T>( static_cast<Unsigned<T>>( a ) * static_cast<Unsigned<T>>( b ) );
    if( a == 0 )
    {
        return false;
    }
    // Division is the portable test: it needs no type wider than T, so it holds at the widest width there is.
    // The INT_MIN / -1 pair is the one case the division itself would trap on, so it is answered before it runs.
    return ( a == -1 && b == std::numeric_limits<T>::min() ) || ( *out / a != b );
}

// The twins, evaluated at compile time on every platform. Each line is a case the callers actually reach or a
// boundary the arithmetic is most likely to get wrong: the two extremes, the sign-crossing pairs, and the
// INT_MIN / -1 multiply that a naive division test traps on.
consteval bool checkedArithmeticHolds()
{
    using I = long long;
    constexpr I kMax = std::numeric_limits<I>::max();
    constexpr I kMin = std::numeric_limits<I>::min();
    I r = 0;
    bool ok = true;
    ok = ok && !addOverflowPortable<I>( 2, 3, &r ) && r == 5;
    ok = ok && !addOverflowPortable<I>( kMax, -1, &r ) && r == kMax - 1;
    ok = ok &&  addOverflowPortable<I>( kMax, 1, &r );
    ok = ok &&  addOverflowPortable<I>( kMin, -1, &r );
    ok = ok && !subOverflowPortable<I>( 3, 2, &r ) && r == 1;
    ok = ok && !subOverflowPortable<I>( kMin, -1, &r ) && r == kMin + 1;
    ok = ok &&  subOverflowPortable<I>( kMin, 1, &r );
    ok = ok &&  subOverflowPortable<I>( kMax, -1, &r );
    ok = ok && !mulOverflowPortable<I>( 6, 7, &r ) && r == 42;
    ok = ok && !mulOverflowPortable<I>( 0, kMax, &r ) && r == 0;
    ok = ok && !mulOverflowPortable<I>( kMax, 0, &r ) && r == 0;
    ok = ok && !mulOverflowPortable<I>( kMax, 1, &r ) && r == kMax;
    ok = ok &&  mulOverflowPortable<I>( kMax, 2, &r );
    // BOTH orders of the INT_MIN / -1 pair. Only the second reaches the guard: the division below is `*out / a`,
    // so it is a == -1 that would evaluate kMin / -1 and trap. Writing only ( kMin, -1 ) tests the guard's
    // neighbour and leaves the guard itself unexecuted — this pair is what makes the static_assert non-vacuous.
    ok = ok &&  mulOverflowPortable<I>( kMin, -1, &r );
    ok = ok &&  mulOverflowPortable<I>( -1, kMin, &r );
    ok = ok && !mulOverflowPortable<I>( 1'000'000'000LL, 1'000'000'000LL, &r );
    ok = ok &&  mulOverflowPortable<I>( 1'000'000'000'000LL, 1'000'000'000LL, &r );
    return ok;
}
static_assert( checkedArithmeticHolds(), "the portable checked-arithmetic twins disagree with their contract" );
} // namespace detail

template<class T>
[[nodiscard]] ALWAYS_INLINE bool addOverflow( T a, T b, T* out ) noexcept
{
#if defined(__clang__) || defined(__GNUC__)
    return __builtin_add_overflow( a, b, out );
#else
    return detail::addOverflowPortable( a, b, out );
#endif
}

template<class T>
[[nodiscard]] ALWAYS_INLINE bool subOverflow( T a, T b, T* out ) noexcept
{
#if defined(__clang__) || defined(__GNUC__)
    return __builtin_sub_overflow( a, b, out );
#else
    return detail::subOverflowPortable( a, b, out );
#endif
}

template<class T>
[[nodiscard]] ALWAYS_INLINE bool mulOverflow( T a, T b, T* out ) noexcept
{
#if defined(__clang__) || defined(__GNUC__)
    return __builtin_mul_overflow( a, b, out );
#else
    return detail::mulOverflowPortable( a, b, out );
#endif
}

} // namespace infra::platform
