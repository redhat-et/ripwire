// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  fastmath.h
//
//  Compiler attributes, platform macros, constants, and declarations.
//  All function bodies are in fastmath.inl (included at bottom).
//  Lookup tables and out-of-line slow paths are in fastmath.cpp.

#pragma once

#include <cmath>
#include <cstddef>   // std::size_t for the hardware-interference-size constants
#include <type_traits>   // std::is_integral_v for the integral min/max overloads
#include <utility>
#include <iosfwd>
#if defined(__ARM_NEON) || defined(__ARM_NEON__)
  #include <arm_neon.h>
#endif

// ==========================================================================
// Compiler attributes
// ==========================================================================

#ifdef __clang__
#define ALWAYS_INLINE  [[clang::always_inline]] inline
#else
#define ALWAYS_INLINE  __attribute__((always_inline)) inline
#endif
#define NO_INLINE      __attribute__((noinline))
#define FLATTEN        __attribute__((flatten))
#define COLD_FUNC      __attribute__((cold))
#define HOT_FUNC       __attribute__((hot))
#define CONST_FUNC     __attribute__((const))   // reads/writes no global memory
#define PURE_FUNC      __attribute__((pure))    // reads globals, writes none

#define CONSTRUCTOR_MIN_PRIORITY 101
#define CONSTRUCTOR_MAX_PRIORITY 65535
#define constructor(priority)   __attribute__((constructor(priority)))
#define destructor(priority)    __attribute__((destructor(priority)))
#define initPriority(priority)  __attribute__((init_priority(priority)))

#define likely(x)   __builtin_expect(!!(x), 1)
#define unlikely(x) __builtin_expect(!!(x), 0)

#define noalias                                  __restrict__
#define prefetch(addr,rw,locality)               __builtin_prefetch(addr,rw,locality)
#define memorycopy(dst,src,size)                 __builtin_memcpy(dst,src,size)
#define memorycopyinline(dst,src,size)           __builtin_memcpy_inline(dst,src,size)
#define assumeAligned(ptr,alignment)             __builtin_assume_aligned(ptr,alignment)

// Hot-loop SIMD contract. Place IMMEDIATELY before a tight elementwise loop whose
// body is structurally gather-free (broadcast / contiguous loads, no data-dependent
// index, no loop-carried dependence): it REQUESTS vectorization. The project build
// adds `-Werror=pass-failed` (see build.sh / BUILD.md), so a loop that later
// regresses to scalar — a stray `break`, a non-inlined call, an accidental recurrence
// — becomes a BUILD ERROR pinned to this line, not a silent perf cliff. No-op on
// non-Clang and at -O0 (the vectorizer doesn't run there, so there is nothing to
// enforce — debug builds stay buildable). CAVEAT: enforces *vectorized*, not
// *gather-free* (Clang can vectorize a gather with lane loads) — keep the body
// gather-free by construction; this guards the cliff, the structure guards the rest.
#ifdef __clang__
#define VECTORIZE_LOOP  _Pragma("clang loop vectorize(enable)")
#else
#define VECTORIZE_LOOP
#endif

// Diagnostics.h provides VERIFY, VERIFY_TEXT, VERIFY_NOT_REACHED, PANIC
#include "Diagnostics.h"

// ==========================================================================
// fastmath namespace — constants, scalar utilities, polynomials, easing
// ==========================================================================

namespace fastmath
{

// ---- constants  ----------------------------------------------------------
constexpr float PI_FLOAT           = 3.141592654f;
constexpr float TWO_PI_FLOAT       = 6.283185307f;
constexpr float INV_PI             = 0.318309886f;
constexpr float DEGREES_PER_RADIAN = 57.29577951308232286465f;
constexpr float RADIANS_PER_DEGREE = 0.01745329251994329547f;
constexpr float FLOAT_TINY         = 1.0e-4f;
constexpr float SMALLEST_DIVISOR   = 1.0e-5f;
constexpr float MATH_VERY_SMALL    = 1.0e-10f;
constexpr float MATH_VERY_SMALL2   = 1.0e-20f;
constexpr float MATH_INFINITY      = 3.4e38f;
// Legacy aliases
constexpr float pi                 = PI_FLOAT;
constexpr float two_pi             = TWO_PI_FLOAT;
constexpr float inv_pi             = INV_PI;
constexpr float TWO_PI             = TWO_PI_FLOAT;
constexpr float NEG_MATH_VERY_SMALL = -1.0e-10f;

// Cache-line size constants — follow the C++17 std::hardware_*_interference_size
// naming convention. Provided here as project-owned constexpr values because
// libc++ doesn't always ship the std:: versions (ABI-stability concerns) and we
// need the values correct for the production target — Apple Silicon (A11+ /
// M-series) uses 128-byte L1d cache lines vs 64 on commodity x86.
//
//   hardware_destructive_interference_size  : minimum offset between two objects
//       to avoid FALSE SHARING across cores. Pad cross-thread shared structs
//       to this. (Single-threaded today — relevant once job parallelism lands.)
//
//   hardware_constructive_interference_size : maximum size of contiguous memory
//       likely to SHARE one L1 cache line. Align hot SoA array STARTS to this
//       so the first SIMD load lands inside a fresh line. This is the one that
//       matters for the SpherePool / SphereLauncher arrays today.
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

// Legacy alias retained for any code that doesn't care about the intent split.
// New code should prefer the destructive/constructive form so the layout intent
// is visible at the call site.
constexpr std::size_t CACHE_LINE_SIZE = hardware_constructive_interference_size;

// ---- spin-loop relaxation hint  --------------------------------------------
// cpuRelax(): one cheap "breathe" instruction for tight CAS-retry / spin-wait
// loops, so a retry storm doesn't saturate the coherence bus. NOT
// std::this_thread::yield() — this stays ON-CORE, no scheduler round-trip.
// On Apple Silicon the ARM `yield` hint is ~a nop, so we emit `isb` instead — a
// real, cheap (~ns) pipeline stall that genuinely relaxes the core. On x86 it
// is the canonical `pause`. Lives here beside the interference-size constants
// (the same false-sharing battles); infrastucture/concurrency.h re-exports it
// as infra::cpuRelax for its locks/queues.
inline void cpuRelax() noexcept
{
#if defined(__aarch64__) || defined(_M_ARM64)
    __asm__ __volatile__( "isb" ::: "memory" );
#elif ( defined(__x86_64__) || defined(_M_X64) ) && ( defined(__clang__) || defined(__GNUC__) )
    __builtin_ia32_pause();
#endif
    // other targets: plain spin — no portable on-core relax exists without <thread>
}

// ---- type-punning union  -------------------------------------------------
union unholy {
    constexpr unholy( float x ) : f(x) {}
    unsigned int i;
    float f;
};

// ---- fast-math-safe finite checks  ---------------------------------------
// std::isfinite / __builtin_isfinite are folded to constant-true under
// -ffinite-math-only (implied by -ffast-math). These test the IEEE-754
// exponent field directly through an opaque asm barrier so the optimiser
// cannot assume finiteness. NaN and ±Inf both have exponent == 0xFF.
[[nodiscard]] ALWAYS_INLINE bool isFiniteFast( float x ) noexcept
{
    unsigned u = __builtin_bit_cast(unsigned, x);
    asm volatile("" : "+r"(u));                 // opaque: defeat -ffinite-math-only
    return (u & 0x7F800000u) != 0x7F800000u;
}
[[nodiscard]] ALWAYS_INLINE bool isNaNFast( float x ) noexcept
{
    unsigned u = __builtin_bit_cast(unsigned, x);
    asm("" : "+r"(u));
    return (u & 0x7F800000u) == 0x7F800000u && (u & 0x007FFFFFu) != 0u;
}
[[nodiscard]] ALWAYS_INLINE bool isInfFast( float x ) noexcept
{
    unsigned u = __builtin_bit_cast(unsigned, x);
    asm("" : "+r"(u));
    return (u & 0x7FFFFFFFu) == 0x7F800000u;
}

// ---- declarations  -------------------------------------------------------
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float degreesToRadians( float deg ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float radiansToDegrees( float rad ) noexcept;

[[nodiscard]] ALWAYS_INLINE CONST_FUNC int   ifloorf ( float x )          noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC int   iceilf  ( float x )          noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float fabsf   ( float x )          noexcept;

    // ---- branchless rounding (item 9) — map to single-instruction builtins ----
    // __builtin_rintf  → FRINTX (ARM64) / ROUNDSS (x86-SSE4.1): no branches
    // __builtin_floorf → FRINTM (ARM64) / ROUNDSS mode 1
    // __builtin_ceilf  → FRINTP (ARM64) / ROUNDSS mode 2
    // __builtin_truncf → FRINTZ (ARM64) / ROUNDSS mode 3
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float rintf     ( float x ) noexcept { return __builtin_rintf(x);  }
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float floorf    ( float x ) noexcept { return __builtin_floorf(x); }
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float ceilf     ( float x ) noexcept { return __builtin_ceilf(x);  }
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float truncf    ( float x ) noexcept { return __builtin_truncf(x); }
[[nodiscard]] ALWAYS_INLINE CONST_FUNC int   roundToInt( float x ) noexcept { return (int)__builtin_rintf(x); }
    // fract: fractional part, always in [0,1) regardless of sign of x
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float fract     ( float x ) noexcept { return x - __builtin_floorf(x); }
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float fmodf   ( float x, float y ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float sqrt    ( float f )          noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float safeSqrt( float f )          noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float realpowf( float x, float e ) noexcept;

[[nodiscard]] ALWAYS_INLINE CONST_FUNC float max( float a, float b )                         noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float min( float a, float b )                         noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float clamp( float x, float lo, float hi )            noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float max( float a, float b, float c )                noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float min( float a, float b, float c )                noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float max( float a, float b, float c, float d )       noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float min( float a, float b, float c, float d )       noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float max( float a, float b, float c, float d, float e ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float min( float a, float b, float c, float d, float e ) noexcept;

// ---- integral min / max (branchless) -------------------------------------
// The float overloads above don't cover counters / sizes / tick deltas. These
// fold to a single CSEL on ARM64. Constrained to integral T so float/double
// calls still bind to the float paths above (existing call sites unaffected).
// Defined inline here rather than in fastmath.inl because they are templates.
template<class T> requires std::is_integral_v<T>
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr T min( T a, T b ) noexcept { return b < a ? b : a; }

template<class T> requires std::is_integral_v<T>
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr T max( T a, T b ) noexcept { return a < b ? b : a; }

// ---- type-mixing guard ---------------------------------------------------
// With min/max overloaded for float AND integral T, a 2-arg call mixing two
// DIFFERENT arithmetic types (min( uint64_t, int ), min( int, 1.5f ), min(double,..))
// would otherwise silently bind the float path and round BOTH operands through
// float -- lossy past 2^24. Delete that case: callers must pass a matching pair or
// cast. Same-type calls still bind above (more-specialized template / non-template).
template<class A, class B> auto min( A, B ) noexcept = delete;
template<class A, class B> auto max( A, B ) noexcept = delete;

[[nodiscard]] ALWAYS_INLINE CONST_FUNC bool approxZero( float x )             noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC bool closeTo   ( float x, float a )    noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC bool absNotTiny( float x )             noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float square( float x )                noexcept;

NO_INLINE float safeDivisorNoInLine( float d ) noexcept;   // defined in fastmath.cpp
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float safeDivisor( float d ) noexcept;

[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float fmadd ( float a, float b, float c ) noexcept;   // a*b + c (Intel order: product first)
// (scalar fmsub/fnmadd/fnmsub deleted — zero callers, and they carried ARM
//  FMSUB semantics (c−a·b) under an Intel-shaped signature while fastsimd::
//  fmsub takes the addend FIRST: three conflicting conventions in one name.
//  Use fmadd with negated operands; it expresses every variant unambiguously.)

[[nodiscard]] ALWAYS_INLINE CONST_FUNC float lerp       ( float a, float b, float t )      noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float interpolate( float alpha, float x0, float x1 ) noexcept;
template<class T> [[nodiscard]] ALWAYS_INLINE T interpolate( float alpha, const T& x0, const T& x1 ) noexcept;

// ---- range helpers (the lerp family's standard companions) ----------------
// saturate(x)            = clamp(x, 0, 1)                       (GLSL/Metal name)
// inverseLerp(a, b, x)   = the t for which lerp(a,b,t) == x — UNCLAMPED
// remap(x, inLo,inHi, outLo,outHi) = lerp(outLo,outHi, saturate(inverseLerp(inLo,inHi,x)))
//                          (saturating: tuning-curve semantics; callers wanting
//                           extrapolation can compose lerp+inverseLerp directly)
// moveTowards(cur, target, maxDelta) = step cur toward target by at most maxDelta
//                          (the standard rate-limit primitive; maxDelta >= 0)
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float saturate   ( float x )                                       noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float inverseLerp( float a, float b, float x )                     noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float remap      ( float x, float inLo, float inHi,
                                                          float outLo, float outHi )                      noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float moveTowards( float current, float target, float maxDelta )   noexcept;

// ---- low-discrepancy sequences (R1 / R2 — Roberts 2018) -------------------
// Deterministic additive recurrences with the golden / plastic ratios in
// 32-bit FIXED POINT (exact: no float accumulation error at any n). Sample n
// covers [0,1) / [0,1)² evenly — O(1) per sample, replacing O(n·k) blue-noise
// rejection wherever "evenly spread, not clumpy" is the actual requirement
// (reef/prize placement, dither phases, spawn jitter).
struct R2Sample { float x, y; };
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float    r1Sequence( uint32_t n ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC R2Sample r2Sequence( uint32_t n ) noexcept;

// ---- byte packing  -------------------------------------------------------
// Pack four bytes into a uint32 (little-endian: b0 = low byte). Compiler
// emits ARM64 `bfi` / x86 `or`+`shl` sequences inline — single-cycle
// throughput on M-series. Use for GPU instance-data writes where a
// shader reads `(packed >> n) & 0xFF` to recover each byte.
//
// Defined inline so the call site optimizes identically to hand-written
// bit-OR. constexpr so call-with-constants folds at compile time.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr uint32_t pack4u8(
    uint8_t b0, uint8_t b1, uint8_t b2, uint8_t b3 ) noexcept
{
    return  uint32_t( b0 )
         | (uint32_t( b1 ) <<  8)
         | (uint32_t( b2 ) << 16)
         | (uint32_t( b3 ) << 24);
}

// Inverse — extract one byte at index 0..3.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr uint8_t byteOf(
    uint32_t packed, int byteIdx ) noexcept
{
    return uint8_t( ( packed >> ( byteIdx * 8 ) ) & 0xFFu );
}

// Horner-form polynomial evaluators
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float poly2( float x, float c2, float c1, float c0 ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float poly3( float x, float c3, float c2, float c1, float c0 ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float poly4( float x, float c4, float c3, float c2, float c1, float c0 ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float poly5( float x, float c5, float c4, float c3, float c2, float c1, float c0 ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float poly6( float x, float c6, float c5, float c4, float c3, float c2, float c1, float c0 ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float poly7( float x, float c7, float c6, float c5, float c4, float c3, float c2, float c1, float c0 ) noexcept;

[[nodiscard]] ALWAYS_INLINE CONST_FUNC float approx_powf( float x, float exp ) noexcept;

// General floating-point exp2 / log2 / pow  (~5 cycles, ~1.5e-5 / 0.0006 error)
// Use for fog, exposure, attenuation, BRDFs, specular, tone mapping, LOD.
// See also: pow{50..95}H (compile-time fixed base ≥ 0.5), realpowf (exact libm).
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float exp2( float x )             noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float log2( float x )             noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float pow ( float x, float y )    noexcept;

// Natural log / log base 10, built on log2 (log(x) = log2(x)*ln2). Same tier as
// log2/exp2/pow: ~0.3 ns, ~5e-4 absolute error (max relative blows up only at
// x≈1 where ln→0, an artifact — absolute error is the meaningful bound there).
// For near-exact results use reallogf (libm). A 9-term cephes minimax sits in
// between (~1 ns, ~1 ULP, 2× faster than libm) — see math/bench_log.cpp if a
// caller ever needs it.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float log  ( float x )            noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float log10( float x )            noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float reallogf( float x )         noexcept;   // exact libm wrapper

// Natural exp (e^x). Unlike log — where reusing log2 won — the profile (see
// math/bench_exp.cpp) picked the cephes 6-term minimax: it is near-exact
// (~5.5e-7 max relative) at ~0.42 ns, only ~0.15 ns over the exp2-reuse path
// (exp2(x*log2e), ~1.3e-4) but ~230× more accurate, and ~5× faster than libm.
// For an exact result use realexpf (libm).
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float exp ( float x )             noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float realexpf( float x )         noexcept;   // exact libm wrapper

// Hyperbolic tangent — the soft-clip / saturation curve (audio waveshaping,
// smooth limiters, blend gating). Built on the fast exp: tanh(x)=1-2/(e^{2x}+1).
// Per math/bench_tanh.cpp it is near-exact (~1.8e-7 max abs) at ~0.54 ns — ~4.5×
// faster than libm tanhf and far more accurate than cheap rational fits. For an
// exact result use realtanhf (libm).
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float tanh( float x )             noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float realtanhf( float x )        noexcept;   // exact libm wrapper

[[nodiscard]] ALWAYS_INLINE CONST_FUNC float remainingFromHalfLife( float halfLife, float dt ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float alphaFromHalfLife    ( float halfLife, float dt ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float remainingFromFrequencyHz( float frequencyHz, float dt ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float alphaFromFrequencyHz    ( float frequencyHz, float dt ) noexcept;

// Polynomial pow approximations: pow(base, t), t ∈ [1/120, 1].
// Surviving set: bases ≥ 0.50. The 0.1–0.4 variants (pow10H..pow40H) were
// removed — their poly3 fit had > 3% relative error and grew to > 5× at
// base=0.1; use fastmath::pow(base, t) instead (only 2× the cost, ~0.02% rel).
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float pow50H( float t ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float pow60H( float t ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float pow70H( float t ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float pow80H( float t ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float pow90H( float t ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr float pow95H( float t ) noexcept;

static inline float smoothStepUp(float min, float max, float input) noexcept;
static inline float smoothStepDown(float min, float max, float input) noexcept;
// GLSL-semantics smoothstep: input CLAMPED to [min,max] first, so result is
// always in [0,1] (smoothStepUp does NOT clamp and overshoots outside the band).
static inline float smoothstep(float min, float max, float input) noexcept;
static inline float superSmoothStepUp(float min, float max, float input) noexcept;
static inline float superSmoothStepDown(float min, float max, float input) noexcept;


// (Removed: slowpow<i> and fastpowf<i>. Both were dominated by fastmath::pow
//  on accuracy at comparable speed (~1 ns) with the added cost of a compile-
//  time fixed base. For runtime base use fastmath::pow; for fixed base ≥ 0.5
//  with a cubic-quality fit use pow{50..95}H.)

// Easing curves  (t∈[0,1], begin, change/finish, duration)
template<class T> [[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr T easeInQuad     ( float t, T b, T c, float d ) noexcept;
template<class T> [[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr T easeOutQuad    ( float t, T b, T c, float d ) noexcept;
template<class T> [[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr T easeOutInCubic ( float t, T begin, T change, float d ) noexcept;
template<class T> [[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr T easeOutInQuint ( float t, T begin, T change, float d ) noexcept;
template<class T> [[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr T easeOutInQuart ( float t, T begin, T change, float d ) noexcept;
template<class T> [[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr T startFinishCubic( float t, T begin, T finish, float d ) noexcept;
template<class T> [[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr T clampedCubic   ( float t, T begin, T finish, float d ) noexcept;

// Spline interpolation
template<class T> [[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr T hermiteInterpolate( T y0, T y1, T y2, T y3, float mu ) noexcept;
template<class T> [[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr T Binterpolate      ( T p0, T p1, T p2, T p3, float mu ) noexcept;
template<class T> [[nodiscard]] ALWAYS_INLINE CONST_FUNC constexpr T catmullInterpolate( T P0, T P1, T P2, T P3, float t  ) noexcept;

} // namespace fastmath

// ==========================================================================
// fastTrig namespace — polynomial sin/cos/acos/asin, angle utilities.
// No lookup tables: pure FMA polynomial, no cache pressure.
// All bodies are in fastmath.inl.
// ==========================================================================

namespace fastTrig
{

// ---- result structs  -----------------------------------------------------
struct SinCosOut  { float sin;   float cos;      };  // returned by sincos()
struct AcosSinOut { float theta; float sinTheta; };  // returned by acosSin()

// ---- polynomial sin/cos/acos/asin  --------------------------------------
// Accuracy: sin/cos ≈ 1.5 ULP near the primary range, ~270 ULP over [-10π,10π]
//           (see fastmath.inl); acos/asin ≈ 3e-4 rad (sufficient for slerp)
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float      sin    ( float x )          noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float      cos    ( float x )          noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC SinCosOut  sincos ( float x )          noexcept;
// tan — octant range-reduce + minimax polynomial; diverges (±inf) near ±π/2 as it must.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float      tan    ( float x )          noexcept;
// invSin(theta)       — 1/sin(theta), computes sin internally
// invSinDirect(s)     — 1/s where s=sin(theta) already known (avoids recomputing sinPoly)
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float      invSin      ( float theta )      noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float      invSinDirect( float sinTheta )   noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float      acos   ( float x )          noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float      asin   ( float x )          noexcept;
// acos + sin(theta) together — used by slerp to avoid calling sin(acos(x))
[[nodiscard]] ALWAYS_INLINE CONST_FUNC AcosSinOut acosSin( float x )          noexcept;

// ---- real (libm) wrappers  -----------------------------------------------
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float realSin  ( float x )          noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float realCos  ( float x )          noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float realTan  ( float x )          noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float realAtan2( float y, float x ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float realAcos ( float x )          noexcept;

// ---- angle utilities  ----------------------------------------------------
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float arctan2H    ( float y, float x ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float arctan2HSafe( float y, float x ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float atanUnitH   ( float a )          noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float wrapToPi    ( float a )          noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float wrapToPi2   ( float a )          noexcept;
// Shortest SIGNED angular difference from→to, in [−π, π]: to ≈ from + angleDiff(from,to).
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float angleDiff   ( float fromRad, float toRad ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float rotationLerp( float start, float end, float t ) noexcept;

// ---- legacy aliases (deprecated, use sin/cos/acos/sincos directly)  -----
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float polySin ( float v ) noexcept;
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float polyAcos( float x ) noexcept;
             inline void   polySinCos( float v, float& s, float& c ) noexcept;

} // namespace fastTrig

// ==========================================================================
// Pull in all inline/template bodies
// ==========================================================================
#include "fastmath.inl"
