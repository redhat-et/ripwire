// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  fastmath.h
//
//  The number helpers this tree actually calls: branchless integral min/max (with
//  their mixed-type delete guards) and a fast-math-safe finite check. Namespace is
//  `fastmath`.
//
//  Split out of this file on 2026-08-09 — the machine-facts half (ALWAYS_INLINE,
//  memorycopy, the cache-line interference sizes) moved to platform.h, namespace
//  `infra::platform`. This header #includes platform.h, so everything that used to
//  come from one file is still visible from this one.
//
//  This is a small subset of a much larger game-math library on the companion tree
//  this file is hand-ported with — that tree's fastmath.h is ~1500 lines of vector
//  trig, polynomial pow, easing curves, and splines. This tree kept the handful of
//  helpers it actually calls; the rest was never carried over, and that is the
//  designed state, not a fork to close. Only platform.h — the machine-facts half —
//  is expected to correspond closely between the two trees.
//

#pragma once

#include "platform.h"
#include <type_traits>   // std::is_integral_v for the integral min/max overloads

namespace fastmath
{

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
// BOTH operands (lossy past 2^24) — AND same-type float/double pairs, which this
// subset of the number helpers does not implement (the companion tree's larger math
// library carries float overloads; this tree never calls them). Cast to a matching
// integral pair at the call site, where the truncation is visible, or use std::min.
// Matching integral calls still bind above (the constrained template is more
// specialized than this catch-all).
template<class A, class B> auto min( A, B ) noexcept = delete;
template<class A, class B> auto max( A, B ) noexcept = delete;

} // namespace fastmath
