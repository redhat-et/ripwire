// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  platform.h
//
//  The compiler/platform substrate every other infra header sits on: the attribute
//  macros, the cache-line interference sizes, and the two scalar helpers that the
//  sort and profiling paths actually call.
//
//  This replaces the game-math header (fastmath.h/.inl) this tree was seeded from.
//  Ripwire used five things out of ~1500 lines of vector trig, polynomial pow, easing
//  curves and spline interpolation; the rest is gone. What survived is here, and every
//  macro below has a call site elsewhere in src/ — nothing is kept "in case".
//
//  The NAMESPACE keeps its old name `fastmath` on purpose. CONTRIBUTING.md's layout
//  rule is written as `alignas( fastmath::hardware_destructive_interference_size )`
//  and ~20 call sites spell it that way; the file died, the namespace did not.
//

#pragma once

#include <cstddef>       // std::size_t for the hardware-interference-size constants
#include <type_traits>   // std::is_integral_v for the integral min/max overloads

// ==========================================================================
// Compiler attributes
// ==========================================================================

#ifdef __clang__
#define ALWAYS_INLINE  [[clang::always_inline]] inline
#else
#define ALWAYS_INLINE  __attribute__((always_inline)) inline
#endif

#define memorycopy(dst,src,size)  __builtin_memcpy(dst,src,size)

// Diagnostics.h provides VERIFY, VERIFY_TEXT, VERIFY_NOT_REACHED, PANIC, and
// DEGRADED_PATH_ALERT. Included here, not merely alongside, because this header is
// the one every infra consumer already takes for the attribute macros and the
// cache-line constants — sparseCsr.h and radixSort.h document that dependency.
#include "Diagnostics.h"

// ==========================================================================
// fastmath namespace — cache-line constants + the scalar helpers still in use
// ==========================================================================

namespace fastmath
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

// ---- fast-math-safe finite check  ----------------------------------------
// std::isfinite / __builtin_isfinite are folded to constant-true under
// -ffinite-math-only (implied by -ffast-math). This tests the IEEE-754
// exponent field directly through an opaque asm barrier so the optimiser
// cannot assume finiteness. NaN and ±Inf both have exponent == 0xFF.
[[nodiscard]] ALWAYS_INLINE bool isFiniteFast( float x ) noexcept
{
    unsigned u = __builtin_bit_cast(unsigned, x);
    asm volatile("" : "+r"(u));                 // opaque: defeat -ffinite-math-only
    return (u & 0x7F800000u) != 0x7F800000u;
}

// ---- integral min / max (branchless) -------------------------------------
// std::min/std::max take references and return one, so a call on two atomically
// loaded tick counts costs a spill; these take values and fold to a single CSEL
// on ARM64. Constrained to integral T because that is all this tree passes them.
// ALWAYS_INLINE makes the body visible at every call site, so the old
// __attribute__((const)) hint bought nothing and is not carried over.
template<class T> requires std::is_integral_v<T>
[[nodiscard]] ALWAYS_INLINE constexpr T min( T a, T b ) noexcept { return b < a ? b : a; }

template<class T> requires std::is_integral_v<T>
[[nodiscard]] ALWAYS_INLINE constexpr T max( T a, T b ) noexcept { return a < b ? b : a; }

// ---- type-mixing guard ---------------------------------------------------
// The templates above deduce a single T and are constrained to INTEGRAL types, so this
// catch-all deletes every 2-arg call that is not a matching integral pair: mixed types
// ( min( uint64_t, int ), max( size_t, unsigned ) ) which would otherwise fall through
// to whatever the surrounding namespaces offer — including a float path that rounds
// BOTH operands (lossy past 2^24) — AND same-type float/double pairs, which this tree
// does not make (the float overloads left with the game-math header). Cast to a
// matching integral pair at the call site, where the truncation is visible, or use
// std::min. Matching integral calls still bind above (the constrained template is
// more specialized than this catch-all).
template<class A, class B> auto min( A, B ) noexcept = delete;
template<class A, class B> auto max( A, B ) noexcept = delete;

} // namespace fastmath
