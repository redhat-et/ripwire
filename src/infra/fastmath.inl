// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  fastmath.inl
//
//  Inline and template bodies for fastmath and fastTrig namespaces.
//  Included at the bottom of fastmath.h. Do NOT include directly.

#pragma once
#include <cstdint>
#include <bit>
#include <cmath>

// ==========================================================================
// fastmath — bodies
// ==========================================================================

namespace fastmath
{

ALWAYS_INLINE CONST_FUNC constexpr float degreesToRadians( float deg ) noexcept { return deg * RADIANS_PER_DEGREE; }
ALWAYS_INLINE CONST_FUNC constexpr float radiansToDegrees( float rad ) noexcept { return rad * DEGREES_PER_RADIAN; }

ALWAYS_INLINE CONST_FUNC int   ifloorf ( float x )          noexcept { return __builtin_floorf(x); }
ALWAYS_INLINE CONST_FUNC int   iceilf  ( float x )          noexcept { return __builtin_ceilf(x);  }
ALWAYS_INLINE CONST_FUNC float fabsf   ( float x )          noexcept { return __builtin_fabsf(x);  }
ALWAYS_INLINE CONST_FUNC float fmodf   ( float x, float y ) noexcept { return __builtin_fmodf(x,y); }
ALWAYS_INLINE CONST_FUNC float sqrt    ( float f )          noexcept { return __builtin_sqrtf(f); }
// safeSqrt: NaN-guard only — clamps negative float-noise inputs to 0.
// (The old 1e-9 floor silently lifted sqrt(0) to 3.16e-5.)
ALWAYS_INLINE CONST_FUNC float safeSqrt( float f )          noexcept { return __builtin_sqrtf(__builtin_fmaxf(0.f,f)); }
ALWAYS_INLINE CONST_FUNC float realpowf( float x, float e ) noexcept { return __builtin_powf(x,e); }

ALWAYS_INLINE CONST_FUNC float max( float a, float b ) noexcept { return __builtin_fmaxf(a,b); }
ALWAYS_INLINE CONST_FUNC float min( float a, float b ) noexcept { return __builtin_fminf(a,b); }
ALWAYS_INLINE CONST_FUNC float clamp( float x, float lo, float hi ) noexcept { return __builtin_fminf(__builtin_fmaxf(x,lo),hi); }
ALWAYS_INLINE CONST_FUNC float max( float a, float b, float c ) noexcept { return max(max(a,b),c); }
ALWAYS_INLINE CONST_FUNC float min( float a, float b, float c ) noexcept { return min(min(a,b),c); }
ALWAYS_INLINE CONST_FUNC float max( float a, float b, float c, float d ) noexcept { return max(max(a,b),max(c,d)); }
ALWAYS_INLINE CONST_FUNC float min( float a, float b, float c, float d ) noexcept { return min(min(a,b),min(c,d)); }
ALWAYS_INLINE CONST_FUNC float max( float a, float b, float c, float d, float e ) noexcept { return max(max(a,b),max(c,max(d,e))); }
ALWAYS_INLINE CONST_FUNC float min( float a, float b, float c, float d, float e ) noexcept { return min(min(a,b),min(c,min(d,e))); }

ALWAYS_INLINE CONST_FUNC bool approxZero( float x )          noexcept { return fabsf(x) < MATH_VERY_SMALL; }
ALWAYS_INLINE CONST_FUNC bool closeTo   ( float x, float a ) noexcept { return fabsf(x-a) < MATH_VERY_SMALL; }
ALWAYS_INLINE CONST_FUNC bool absNotTiny( float x )          noexcept { return fabsf(x) > FLOAT_TINY; }
ALWAYS_INLINE CONST_FUNC float square( float x )             noexcept { return x*x; }

ALWAYS_INLINE CONST_FUNC float safeDivisor( float d ) noexcept
{
    if( fabsf(d) > SMALLEST_DIVISOR ) [[likely]]   return d;
    else                               [[unlikely]] return safeDivisorNoInLine(d);
}

ALWAYS_INLINE CONST_FUNC constexpr float fmadd ( float a, float b, float c ) noexcept
{
    // C++23: std::fmaf is not constexpr in libc++, but at constant-evaluation time
    // the compiler can fold a*b+c exactly. At runtime we want the FMA instruction.
    if consteval { return a*b + c; }
    else         { return std::fmaf(a, b, c); }
}

ALWAYS_INLINE CONST_FUNC float lerp( float a, float b, float t ) noexcept { return fmadd(b-a,t,a); }
ALWAYS_INLINE CONST_FUNC float saturate( float x ) noexcept { return clamp(x, 0.f, 1.f); }
ALWAYS_INLINE CONST_FUNC float inverseLerp( float a, float b, float x ) noexcept
{
    VERIFY( fastmath::absNotTiny(b - a) );
    return (x - a) / (b - a);
}
ALWAYS_INLINE CONST_FUNC float remap( float x, float inLo, float inHi, float outLo, float outHi ) noexcept
{
    return lerp(outLo, outHi, saturate(inverseLerp(inLo, inHi, x)));
}
ALWAYS_INLINE CONST_FUNC float moveTowards( float current, float target, float maxDelta ) noexcept
{
    VERIFY( maxDelta >= 0.f );
    const float d = target - current;
    if( fabsf(d) <= maxDelta ) return target;
    return current + __builtin_copysignf(maxDelta, d);
}

ALWAYS_INLINE CONST_FUNC float r1Sequence( uint32_t n ) noexcept
{
    // frac(n·φ⁻¹) as a Weyl sequence: φ⁻¹·2³² = 0x9E3779B9 (the golden-ratio
    // hash constant). Wrapping uint multiply IS the frac — exact at any n.
    return (float)(n * 0x9E3779B9u) * 0x1p-32f;
}

ALWAYS_INLINE CONST_FUNC R2Sample r2Sequence( uint32_t n ) noexcept
{
    // R2: α = (1/g, 1/g²) with g the plastic constant 1.3247179572…
    return { (float)(n * 0xC13FA9A9u) * 0x1p-32f,
             (float)(n * 0x91E10DA6u) * 0x1p-32f };
}
// interpolate(alpha, x0, x1) is the LEGACY alpha-FIRST spelling of lerp(a,b,t).
// Same operation, opposite parameter convention — canonical is lerp(a, b, t).
ALWAYS_INLINE CONST_FUNC float interpolate( float alpha, float x0, float x1 ) noexcept { return x0+(x1-x0)*alpha; }
template<class T> ALWAYS_INLINE T interpolate( float alpha, const T& x0, const T& x1 ) noexcept { return x0+(x1-x0)*alpha; }

// ---- polynomials  --------------------------------------------------------
ALWAYS_INLINE CONST_FUNC constexpr float poly2( float x, float c2, float c1, float c0 ) noexcept
    { return fmadd(x*x,c2,fmadd(x,c1,c0)); }
ALWAYS_INLINE CONST_FUNC constexpr float poly3( float x, float c3, float c2, float c1, float c0 ) noexcept
    { const float x2=x*x; return fmadd(x2,fmadd(x,c3,c2),fmadd(x,c1,c0)); }
ALWAYS_INLINE CONST_FUNC constexpr float poly4( float x, float c4, float c3, float c2, float c1, float c0 ) noexcept
    { const float x2=x*x,x4=x2*x2; return fmadd(x2,fmadd(x,c3,c2),fmadd(x,c1,c0)+c4*x4); }
ALWAYS_INLINE CONST_FUNC constexpr float poly5( float x, float c5, float c4, float c3, float c2, float c1, float c0 ) noexcept
    { const float x2=x*x,x4=x2*x2; return fmadd(x2,fmadd(x,c3,c2),fmadd(x4,fmadd(x,c5,c4),fmadd(x,c1,c0))); }
ALWAYS_INLINE CONST_FUNC constexpr float poly6( float x, float c6, float c5, float c4, float c3, float c2, float c1, float c0 ) noexcept
    { const float x2=x*x,x4=x2*x2; return fmadd(x4,fmadd(x2,c6,fmadd(x,c5,c4)),fmadd(x2,fmadd(x,c3,c2),fmadd(x,c1,c0))); }
ALWAYS_INLINE CONST_FUNC constexpr float poly7( float x, float c7, float c6, float c5, float c4, float c3, float c2, float c1, float c0 ) noexcept
    { const float x2=x*x,x4=x2*x2; return fmadd(x4,fmadd(x2,fmadd(x,c7,c6),fmadd(x,c5,c4)),fmadd(x2,fmadd(x,c3,c2),fmadd(x,c1,c0))); }

// ---- approx_powf  --------------------------------------------------------
ALWAYS_INLINE CONST_FUNC float approx_powf( float x, float exp ) noexcept
{
    unholy u(x);
    u.i = static_cast<unsigned>((1.f-exp)*0x3f800000u + exp*static_cast<float>(u.i));
    return u.f;
}

// Cubic smoothstep: 0→1 as input goes min→max (smooth start and end).
// Saturates outside [min,max] (GLSL contract) — the unclamped cubic is
// NON-MONOTONE past the band (peaks then goes negative), which no caller wants.
static inline float smoothStepUp(float min, float max, float input ) noexcept
{
    VERIFY( fastmath::absNotTiny(max - min) );

    float r  = fastmath::clamp( (input - min) / (max - min), 0.f, 1.f );
    float r2 = r * r;
    return r2 * fmaf(-2.f, r, 3.f);      // r² × (3 − 2r)  — 1 div, 2 mul, 1 FMA
}

// Cubic smoothstep: 1→0 as input goes min→max  (Down = 1 − Up, same cost)
static inline float smoothStepDown( float min, float max, float input ) noexcept
{
    VERIFY( fastmath::absNotTiny(max - min) );

    float r  = fastmath::clamp( (max - input) / (max - min), 0.f, 1.f );
    float r2 = r * r;
    return r2 * fmaf(-2.f, r, 3.f);
}

// GLSL-semantics smoothstep — same as smoothStepUp; kept as the canonical
// shader-matching name.
static inline float smoothstep( float min, float max, float input ) noexcept
{
    VERIFY( fastmath::absNotTiny( max - min ) );

    float r  = fastmath::clamp( ( input - min ) / ( max - min ), 0.f, 1.f );
    float r2 = r * r;
    return r2 * fmaf( -2.f, r, 3.f );    // r² × (3 − 2r)
}

// Quintic smootherstep (Perlin): 0→1, also zero second derivative at endpoints.
// Saturates outside [min,max] like the cubic family.
static inline float superSmoothStepUp(float min, float max, float input ) noexcept
{
    VERIFY( fastmath::absNotTiny(max - min) );

    float t  = fastmath::clamp( (input - min) / (max - min), 0.f, 1.f );
    float t2 = t * t;
    float t3 = t2 * t;
    return t3 * fmaf(t, fmaf(6.f, t, -15.f), 10.f);   // t³(t(6t−15)+10) — 1 div, 3 mul, 2 FMA
}

// Canonical GLSL-style name for the quintic — same function as superSmoothStepUp.
static inline float smootherstep( float min, float max, float input ) noexcept
{
    return superSmoothStepUp(min, max, input);
}

// Quintic smootherstep: 1→0 as input goes min→max
static inline float superSmoothStepDown( float min, float max, float input ) noexcept
{
    VERIFY( fastmath::absNotTiny(max - min) );

    float t  = fastmath::clamp( (max - input) / (max - min), 0.f, 1.f );
    float t2 = t * t;
    float t3 = t2 * t;
    return t3 * fmaf(t, fmaf(6.f, t, -15.f), 10.f);
}



// ---- pow*H  --------------------------------------------------------------
// poly3 fits for fixed bases. Valid for t ∈ [1/120, 1].
// pow10H..pow40H were deleted — their poly3 diverged near t=0 (rel err 3% to
// 510%). For bases < 0.5 use fastmath::pow(base, t) instead.
ALWAYS_INLINE CONST_FUNC constexpr float pow50H( float t ) noexcept { return poly3(t,-0.0506545f,0.239535f, -0.693114f,  1.0f); }
ALWAYS_INLINE CONST_FUNC constexpr float pow60H( float t ) noexcept { return poly3(t,-0.0214264f,0.130397f, -0.510823f,  1.0f); }
ALWAYS_INLINE CONST_FUNC constexpr float pow70H( float t ) noexcept { return poly3(t,-0.00721381f,0.0635585f,-0.356673f, 1.0f); }
ALWAYS_INLINE CONST_FUNC constexpr float pow80H( float t ) noexcept { return poly3(t,-0.00179736f,0.0248885f,-0.223143f, 1.0f); }
ALWAYS_INLINE CONST_FUNC constexpr float pow90H( float t ) noexcept { return poly3(t,-0.000187609f,0.0055479f,-0.10536f, 1.0f); }
ALWAYS_INLINE CONST_FUNC constexpr float pow95H( float t ) noexcept { return poly3(t,-0.0000220679f,0.00131535f,-0.0512933f,1.0f); }

// (Removed: slowpow<i>, fastpowf<i>, and the _ln_impl helper they shared.
//  Audit table: fastmath::pow had equal or better accuracy at the same ~1 ns
//  cost while accepting a runtime base. slowpow<10> in particular reached
//  155% rel err near t=0; fastpowf<i> reached 890% at base=0.1 and never got
//  better than 9% across [0.1,0.9]. Re-check the pow-approximation test in
//  test_all.cpp before reintroducing either family.)


template <class T>
[[gnu::const]] [[nodiscard]] ALWAYS_INLINE constexpr T easeInQuad(float t, const T b, const T c, const float d) noexcept
{
    t /= d;
    return static_cast<T>(-c * t * (t - 2.f) + b);   // (was float(...) — truncated double T and broke vector T)
}

// Ease Out Quadratic                 ( +++ +  +   +    +     + )
template <class T>
[[gnu::const]] [[nodiscard]] ALWAYS_INLINE constexpr T easeOutQuad(float t, const T b, const T c, const float d) noexcept
{
    t /= d;
    return static_cast<T>(c * t * t + b);
}

template <class T>
[[gnu::const]] [[nodiscard]] ALWAYS_INLINE constexpr T easeOutInCubic(float t, const T begin, const T change, const float d) noexcept
{
    if ((t /= d * 0.5f) < 1.f)
        return (begin + change * (0.5f * t * t * t));
    else
    {
        t -= 2.f;
        return (begin + change * 0.5f * (t * t * t + 2.f));
    }
}

// Ease Out/In Quintic  ( +++ +  +   +    +     +     +     +    +   +  + +++
// )
template <class T>
[[gnu::const]] [[nodiscard]] ALWAYS_INLINE constexpr T easeOutInQuint(float t, const T begin, const T change, const float d) noexcept
{
    if ((t /= d * 0.5f) < 1.f)
    {
        const float a = t * t;
        return (begin + change * (0.5f * a * a * t));
    }
    else
    {
        t -= 2.f;
        const float a = t * t;
        return (begin + change * 0.5f * (a * a * t + 2.f));
    }
}
// Ease Out/In Quartic  ( +++ +  +   +    +     +     +     +    +   +  + +++
// )
template <class T>
[[gnu::const]] [[nodiscard]] ALWAYS_INLINE constexpr T easeOutInQuart(float t, const T begin, const T change, const float d) noexcept
{
    if ((t /= d * 0.5f) < 1.f)
    {
        const float a = t * t;
        return (begin + change * 0.5f * a * a);
    }
    else
    {
        t -= 2;
        const float a = t * t;
        return (begin - change * 0.5f * (a * a - 2.f));
    }
}

template <class T>
[[gnu::const]] [[nodiscard]] ALWAYS_INLINE constexpr T startFinishCubic(float t, const T begin, const T finish, const float d) noexcept
{
    float change = finish - begin;

    if ((t /= d * 0.5f) < 1.f)
        return (begin + change * (0.5f * t * t * t));
    else
    {
        t -= 2.f;
        return (begin + change * 0.5f * (t * t * t + 2.f));
    }
}

template <class T>
[[gnu::const]] [[nodiscard]] ALWAYS_INLINE constexpr T clampedCubic(float t, const T begin, const T finish, const float d) noexcept
{
    t = fastmath::min(t,d);
    
    float change = finish - begin;

    if ((t /= d * 0.5f) < 1.f)
        return (begin + change * (0.5f * t * t * t));
    else
    {
        t -= 2.f;
        return (begin + change * 0.5f * (t * t * t + 2.f));
    }
}

template <class T>
[[gnu::const]] [[nodiscard]] ALWAYS_INLINE constexpr T hermiteInterpolate(const T y0, const T y1, const T y2, const T y3, float mu) noexcept
{
    float mu2 = mu * mu;
    float mu3 = mu2 * mu;

    float a3 = 3.f * mu2 - 2.f * mu3;
    float a0 = -a3 + 1.f;
    float a1 = 0.5f * (mu3 - 2.f * mu2 + mu);   // f-suffixed: bare 0.5 promoted the whole chain to double
    float a2 = 0.5f * (mu3 - mu2);

    return (a0 * y1 + (a1 * (y2 - y0)) + (a2 * (y3 - y1)) + a3 * y2);
}

template <class T>
[[gnu::const]] [[nodiscard]] ALWAYS_INLINE constexpr T Binterpolate(const T p0, const T p1, const T p2, const T p3, float mu) noexcept
{
    float mu2 = mu * mu;
    float mu3 = mu2 * mu;

    float _3mu2 = 3.f * mu2;
    float _3mu3 = 3.f * mu3;
    float _3mu = 3.f * mu;

    const float a0 = (1.f - _3mu + _3mu2 - mu3);
    const float a1 = (4.f - 6.f * mu2 + _3mu3);
    const float a2 = (1.f + _3mu + _3mu2 - _3mu3);
    const float a3 = mu3;

    return (a0 * p0 + a1 * p1 + a2 * p2 + a3 * p3) * (1.f / 6.f);   // exact ⅙ (was a 7-digit double 0.1666667)
}

template <class T>
[[gnu::const]] [[nodiscard]] ALWAYS_INLINE constexpr T catmullInterpolate(const T P0, const T P1, const T P2, const T P3, float t) noexcept
{
    float t2 = t * t;
    return 0.5f * ((2.f * P1) + (-P0 + P2) * t + (2.f * P0 - 5.f * P1 + 4.f * P2 - P3) * t2 +
                   (-P0 + 3.f * P1 - 3.f * P2 + P3) * t2 * t);
}


#if 0
// ---- easing curves  ------------------------------------------------------
template<class T> ALWAYS_INLINE CONST_FUNC constexpr T easeInQuad(float t,T b,T c,float d) noexcept
    { t/=d; return static_cast<T>(std::fmaf(-c*t, t-2.f, b)); }  // fmaf(-c*t, t-2, b)
template<class T> ALWAYS_INLINE CONST_FUNC constexpr T easeOutQuad(float t,T b,T c,float d) noexcept
    { t/=d; return static_cast<T>(std::fmaf(c,t*t,b)); }         // fmaf(c, t², b)
template<class T> ALWAYS_INLINE CONST_FUNC constexpr T easeOutInCubic(float t,T begin,T change,float d) noexcept
{
    t/=d*0.5f;
    if(t<1.f){ const float t2=t*t; return begin+change*(0.5f*std::fmaf(t2,t,0.f)); }
    t-=2.f; const float t2=t*t; return begin+change*0.5f*std::fmaf(t2,t,2.f);
}
template<class T> ALWAYS_INLINE CONST_FUNC constexpr T easeOutInQuint(float t,T begin,T change,float d) noexcept
{
    t/=d*0.5f;
    if(t<1.f){const float t2=t*t,t4=t2*t2;return begin+change*(0.5f*std::fmaf(t4,t,0.f));}
    t-=2.f; const float t2=t*t,t4=t2*t2; return begin+change*0.5f*std::fmaf(t4,t,2.f);
}
template<class T> ALWAYS_INLINE CONST_FUNC constexpr T easeOutInQuart(float t,T begin,T change,float d) noexcept
{
    t/=d*0.5f;
    if(t<1.f){const float t2=t*t;return begin+change*0.5f*t2*t2;}
    t-=2.f; const float t2=t*t; return std::fmaf(-change*0.5f,t2*t2-2.f,begin);
}
template<class T> ALWAYS_INLINE CONST_FUNC constexpr T startFinishCubic(float t,T begin,T finish,float d) noexcept
{
    T ch=finish-begin; t/=d*0.5f;
    if(t<1.f){const float t2=t*t;return begin+ch*(0.5f*std::fmaf(t2,t,0.f));}
    t-=2.f; const float t2=t*t; return begin+ch*0.5f*std::fmaf(t2,t,2.f);
}
template<class T> ALWAYS_INLINE CONST_FUNC constexpr T clampedCubic(float t,T begin,T finish,float d) noexcept
{
    t=min(t,d); T ch=finish-begin; t/=d*0.5f;
    if(t<1.f){const float t2=t*t;return begin+ch*(0.5f*std::fmaf(t2,t,0.f));}
    t-=2.f; const float t2=t*t; return begin+ch*0.5f*std::fmaf(t2,t,2.f);
}
template<class T> ALWAYS_INLINE CONST_FUNC constexpr T hermiteInterpolate(T y0,T y1,T y2,T y3,float mu) noexcept
{
    // FMA form: all four multiply-adds become fused, saving 4 rounding steps
    const float mu2=mu*mu, mu3=std::fmaf(mu2,mu,0.f);
    const float a3=std::fmaf(3.f,mu2,std::fmaf(-2.f,mu3,0.f));   // 3μ² - 2μ³
    const float a0=1.f-a3;
    const float a1=0.5f*std::fmaf(mu3,1.f,std::fmaf(-2.f,mu2,mu));  // 0.5*(μ³ - 2μ² + μ)
    const float a2=0.5f*(mu3-mu2);
    return std::fmaf(a0,y1,std::fmaf(a1,y2-y0,std::fmaf(a2,y3-y1,a3*y2)));
}
template<class T> ALWAYS_INLINE CONST_FUNC constexpr T Binterpolate(T p0,T p1,T p2,T p3,float mu) noexcept
{
    // Cubic B-spline: FMA each coefficient-product
    const float mu2=mu*mu, mu3=mu2*mu;
    const float _3m=3.f*mu, _3m2=3.f*mu2, _3m3=3.f*mu3;
    // Horner FMA form for each basis weight
    const T r = std::fmaf(1.f-_3m+_3m2-mu3, p0,
               std::fmaf(4.f-6.f*mu2+_3m3,  p1,
               std::fmaf(1.f+_3m+_3m2-_3m3, p2, mu3*p3)));
    return r * 0.1666667f;
}
template<class T> ALWAYS_INLINE CONST_FUNC constexpr T catmullInterpolate(T P0,T P1,T P2,T P3,float t) noexcept
{
    // Catmull-Rom: group into two FMA chains for ILP
    const float t2=t*t, t3=t2*t;
    // Each term: FMA replaces the mul-then-add
    const T c0 = 2.f*P1;
    const T c1 = (-P0+P2)*t;
    const T c2 = std::fmaf(2.f,P0, std::fmaf(-5.f,P1, std::fmaf(4.f,P2,-P3))) * t2;
    const T c3 = std::fmaf(-1.f,P0, std::fmaf(3.f,P1, std::fmaf(-3.f,P2,P3))) * t3;
    return 0.5f*(c0+c1+c2+c3);
}

#endif

// ==========================================================================
// exp2 / log2 / pow — general floating-point power functions
//
// Use cases: fog, exposure, attenuation, BRDFs, specular, tone mapping, LOD.
//
// Compared with existing fastmath functions:
//   approx_powf(x,e)   — bit-trick, ~5% error, ~0.4 ns
//   pow{50..95}H       — poly3, compile-time fixed base ≥ 0.5, ~0.5 ns
//   realpowf           — exact libm, ~20–50 cycles
//   pow below          — general runtime base, ~2e-4 rel error, ~1 ns
//
// The submitted versions used 2-term Taylor for exp2 (~3e-4 error) and
// 2-term polynomial for log2 (~0.006 error).  The 3-term minimax below is
// 20× more accurate for exp2 and 10× more accurate for log2 at the same
// instruction count.
// ==========================================================================

// exp2(x) — 2^x
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float exp2( float x ) noexcept
{
    x = clamp(x, -126.0f, 126.0f);
    const float ipart = __builtin_floorf(x);
    const float fpart = x - ipart;
    // 3-term Remez minimax for 2^f on [0,1): max error ~1.5e-5
    // Horner 3-term for 2^f on [0,1): c0=1.0 exact (ensures exp2(0)=1 exactly),
    // c1..c3 fitted by LSQ with c0 fixed. Max relative error ~1.25e-4.
    const float p = std::fmaf(fpart,
                        std::fmaf(fpart,
                        std::fmaf(fpart, 0.07737671f, 0.22694461f),
                        0.69542890f), 1.00000000f);
    const float expi = std::bit_cast<float>((static_cast<int32_t>(ipart) + 127) << 23);
    return expi * p;
}

// log2(x) — log base 2
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float log2( float x ) noexcept
{
    x = __builtin_fmaxf(x, 1.0e-20f);
    const uint32_t bits     = std::bit_cast<uint32_t>(x);
    const float    exponent = static_cast<float>(static_cast<int32_t>((bits >> 23) & 0xFF) - 127);
    // Mantissa in [0,1): m = x / 2^exponent - 1
    const float m = std::bit_cast<float>((bits & 0x007FFFFFu) | (127u << 23)) - 1.0f;
    // 4-term polynomial for log2(1+m) on [0,1): max error ~7e-4
    // Coefficients via least-squares minimax; original 3-term had 12% error (wrong coefficients).
    const float p = m * std::fmaf(m, std::fmaf(m, std::fmaf(m, -0.10661f, 0.36338f), -0.69918f), 1.44169f);
    return exponent + p;
}

// pow(x, y) — x^y for x > 0
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float pow( float x, float y ) noexcept
{
    return exp2(y * log2(__builtin_fmaxf(x, 1.0e-20f)));
}

// log(x) — natural log. log2 already does the bit-exponent split + 4-term
// mantissa poly; ln(x) = log2(x) * ln(2). ~0.3 ns, ~5e-4 abs error. See the
// candidate sweep in math/bench_log.cpp (vs libm logf and a cephes minimax).
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float log( float x ) noexcept
{
    return log2(x) * 0.69314718055994531f;        // * ln(2)
}

// log10(x) — log base 10 = log2(x) / log2(10) = log2(x) * log10(2).
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float log10( float x ) noexcept
{
    return log2(x) * 0.30102999566398120f;        // * log10(2)
}

// Exact libm natural log (mirrors realpowf) for the rare caller needing it.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float reallogf( float x ) noexcept { return __builtin_logf(x); }

// exp(x) — natural exponential, cephes single-precision expf (~1 ULP).
// n = round(x/ln2); reduce r = x - n*ln2 into [-ln2/2, ln2/2] (ln2 split into a
// hi/lo pair so the large multiply keeps precision); 6-term minimax for e^r;
// scale by 2^n through the exponent field. Chosen over the exp2(x*log2e) reuse
// because it is ~230× more accurate for ~0.15 ns more — see math/bench_exp.cpp.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float exp( float x ) noexcept
{
    // Upper clamp keeps n = round(x/ln2) ≤ 127: past 127.5·ln2 ≈ 88.3763 the
    // 2^n exponent-field construction below hits biased exponent 255 → +Inf
    // even though e^x is still finite up to x ≈ 88.7228.
    x = clamp(x, -87.33654f, 88.37626f);

    const float n = __builtin_floorf(1.44269504088896341f * x + 0.5f);   // round(x/ln2)
    float r = x - n * 0.693359375f;                   // - n*ln2 (hi part)
    r       = r - n * -2.12194440e-4f;                // - n*ln2 (lo part)

    // e^r for r in [-ln2/2, ln2/2]
    float p =        1.9875691500e-4f;
    p = std::fmaf(p, r, 1.3981999507e-3f);
    p = std::fmaf(p, r, 8.3334519073e-3f);
    p = std::fmaf(p, r, 4.1665795894e-2f);
    p = std::fmaf(p, r, 1.6666665459e-1f);
    p = std::fmaf(p, r, 5.0000001201e-1f);
    p = p * (r * r) + r + 1.0f;

    const float scale = std::bit_cast<float>((static_cast<int32_t>(n) + 127) << 23);  // 2^n
    return p * scale;
}

// Exact libm natural exp (mirrors realpowf / reallogf).
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float realexpf( float x ) noexcept { return __builtin_expf(x); }

// tanh(x) = 1 - 2/(e^{2x}+1), built on the fast exp. exp() clamps its argument
// to the float exp range, so e stays finite and the ratio saturates cleanly to
// ±1 with no extra branch. Near-exact (~1.8e-7 max abs) at ~0.54 ns — ~4.5×
// faster than libm tanhf, far more accurate than cheap rational fits. See
// math/bench_tanh.cpp.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float tanh( float x ) noexcept
{
    const float e = exp( 2.0f * x );
    return 1.0f - 2.0f / ( e + 1.0f );
}

// Exact libm tanh (mirrors realexpf / reallogf).
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float realtanhf( float x ) noexcept { return __builtin_tanhf(x); }

// Half-life smoothing helpers.
// remaining = 0.5^(dt/halfLife) = exp2(-dt/halfLife), avoiding the
// runtime-base log2() inside fastmath::pow(0.5f, ...).
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float remainingFromHalfLife( float halfLife, float dt ) noexcept
{
    if( dt <= 0.f ) [[unlikely]]
        return 1.f;
    const float invHalfLife = 1.f / safeDivisor(halfLife);
    return clamp(exp2(-dt * invHalfLife), 0.f, 1.f);
}

[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float alphaFromHalfLife( float halfLife, float dt ) noexcept
{
    return 1.f - remainingFromHalfLife(halfLife, dt);
}

// First-order smoothing from a cutoff-like frequency in Hz.
// remaining = exp(-2*pi*frequencyHz*dt) = exp2(-(2*pi/log(2))*f*dt).
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float remainingFromFrequencyHz( float frequencyHz, float dt ) noexcept
{
    if( dt <= 0.f || frequencyHz <= 0.f ) [[unlikely]]
        return 1.f;
    constexpr float kTwoPiInvLn2 = 9.064720154f;
    return clamp(exp2(-kTwoPiInvLn2 * frequencyHz * dt), 0.f, 1.f);
}

[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float alphaFromFrequencyHz( float frequencyHz, float dt ) noexcept
{
    return 1.f - remainingFromFrequencyHz(frequencyHz, dt);
}

} // namespace fastmath

namespace fastTrig
{

// ---- Constants (local to this section, avoid name collision) --------------
namespace detail {
    constexpr float PI_2       = 1.570796327f;
    constexpr float PI_v       = 3.141592654f;
    constexpr float TWO_PI     = 6.283185307f;
    constexpr float INV_TWO_PI = 0.159154943f;
}

// ==========================================================================
// Result structs
// ==========================================================================

// Returned by sincos() — both components computed in one call via ILP
// SinCosOut and AcosSinOut declared in fastmath.h

// ==========================================================================
// Core polynomial helpers (file-scope, not exported)
// ==========================================================================

// Evaluates the 7-degree minimax sin polynomial on x ∈ [0, π/2].
// Coefficients from Remez optimisation; max error ≈ 3e-7.
// Does NOT handle range reduction or sign — caller must do that.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
static float sinPoly( float x ) noexcept
{
    const float x2 = x * x;
    // Horner form: x * (1 + x²*(c1 + x²*(c2 + x²*c3)))
    float p = std::fmaf( x2, -0.000185420f,  0.008314304f );
    p       = std::fmaf( p,   x2,           -0.166666546f );
    p       = p * x2;
    return std::fmaf( x, p, x );   // x*(1 + p)  =  x + x*p
}

// Folds x into [0, π/2] and returns the folded value + the required sign flip.
// The sign flip is returned as a uint32 mask to XOR onto the final result.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
static float sinFold( float x_wrap, uint32_t& signMask ) noexcept
{
    using namespace detail;
    // Sign of x_wrap determines final sign of sin
    signMask = std::bit_cast<uint32_t>(x_wrap) & 0x80000000u;
    float x_abs = std::abs(x_wrap);
    // Mirror [π/2, π] back onto [0, π/2]: sin(π-x) = sin(x)
    return (x_abs > PI_2) ? (PI_v - x_abs) : x_abs;
}

// Range-reduces any angle to [-π, π] via roundf
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
static float wrapToPI( float x ) noexcept
{
    using namespace detail;
    const float q = std::roundf(x * INV_TWO_PI);
    return x - q * TWO_PI;
}

// ==========================================================================
// sin / cos / sincos
// ==========================================================================

// sin — full range, Cody-Waite two-step range reduction.
// Uses the identity sin(x + k*pi) = (-1)^k * sin(x).
// Two-step reduction:  x_red = x - k*PI_HI - k*PI_LO
//   PI_HI = 3.1415927f (rounded)
//   PI_LO = -8.742278e-8f (PI - PI_HI, compensating for rounding)
// This preserves more bits than single roundf() subtraction for |x| > ~10,
// and produces a 2.8× speedup by eliminating the conditional fold branch.
// Same polynomial; same ~270 ULP accuracy over [-10π, 10π].
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float sin( float x ) noexcept
{
    constexpr float INV_PI = 0.3183098861837907f;
    constexpr float PI_HI  = 3.1415927f;
    constexpr float PI_LO  = -8.742278e-8f;   // PI - PI_HI (compensating remainder)

    const float k     = __builtin_rintf(x * INV_PI);
    float x_red       = std::fmaf(-k, PI_HI, x);
    x_red             = std::fmaf(-k, PI_LO, x_red);  // two-step Cody-Waite

    const float x2    = x_red * x_red;
    float p           = std::fmaf(-0.0001854270f, x2,  0.0083142754f);
    p                 = std::fmaf(p,              x2, -0.1666665668f);
    p                 = std::fmaf(p,              x2,  1.0f);

    // Branchless sign: sin(x + k*pi) = (-1)^k * sin(x)
    // The parity of k is in bit 31 of (uint32_t)k
    const uint32_t sign = static_cast<uint32_t>(static_cast<int>(k)) << 31;
    return std::bit_cast<float>(std::bit_cast<uint32_t>(x_red * p) ^ sign);
}

// cos — using Cody-Waite reduction with half-period shift.
// cos(x) = sin(x + π/2) = sin( (x + π/2) + k*π ) with k = round((x+π/2)/π)
// Equivalently: reduce x then add π/2 offset, fold sign from parity of k.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float cos( float x ) noexcept
{
    constexpr float INV_PI  = 0.3183098861837907f;
    constexpr float PI_HI   = 3.1415927f;
    constexpr float PI_LO   = -8.742278e-8f;
    constexpr float PI_2    = 1.5707963267948966f;

    // Reduce x + π/2 to [-π/2, π/2] via Cody-Waite
    const float xp    = x + PI_2;
    const float k     = __builtin_rintf(xp * INV_PI);
    float x_red       = std::fmaf(-k, PI_HI, xp);
    x_red             = std::fmaf(-k, PI_LO, x_red);

    const float x2    = x_red * x_red;
    float p           = std::fmaf(-0.0001854270f, x2,  0.0083142754f);
    p                 = std::fmaf(p,              x2, -0.1666665668f);
    p                 = std::fmaf(p,              x2,  1.0f);

    const uint32_t sign = static_cast<uint32_t>(static_cast<int>(k)) << 31;
    return std::bit_cast<float>(std::bit_cast<uint32_t>(x_red * p) ^ sign);
}

// sincos — sin and cos computed in ILP-parallel; one range-reduce
// Returns {sin, cos} with same accuracy as individual calls.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
SinCosOut sincos( float x ) noexcept
{
    using namespace detail;
    float x_wrap = wrapToPI(x);

    // cos offset: add π/2 then guard against overshoot
    float c_wrap = x_wrap + PI_2;
    if( c_wrap > PI_v ) c_wrap -= TWO_PI;

    uint32_t s_sign, c_sign;
    float xf_s = sinFold( x_wrap, s_sign );
    float xf_c = sinFold( c_wrap, c_sign );

    // Evaluate both polynomials — independent, ILP-friendly
    const float xs2 = xf_s * xf_s;
    const float xc2 = xf_c * xf_c;

    float ps = std::fmaf( xs2, -0.000185420f,  0.008314304f );
    float pc = std::fmaf( xc2, -0.000185420f,  0.008314304f );

    ps = std::fmaf( ps, xs2, -0.166666546f );
    pc = std::fmaf( pc, xc2, -0.166666546f );

    ps = ps * xs2;
    pc = pc * xc2;

    const float rs = std::bit_cast<float>( std::bit_cast<uint32_t>(std::fmaf(xf_s,ps,xf_s)) ^ s_sign );
    const float rc = std::bit_cast<float>( std::bit_cast<uint32_t>(std::fmaf(xf_c,pc,xf_c)) ^ c_sign );

    return {rs, rc};
}

// ==========================================================================
// tan
// ==========================================================================

// Evaluates the tan minimax polynomial on r ∈ [-π/4, π/4]  (Cephes tanf).
// tan(r) = r + r·z·P(z),  z = r²;  max relative error ≈ 3e-8 over the octant.
// Does NOT handle range reduction — caller reduces to [-π/4, π/4] first.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
static float tanPoly( float r ) noexcept
{
    const float z = r * r;
    float p = std::fmaf( 9.38540185543e-3f, z, 3.11992232697e-3f );
    p       = std::fmaf( p,                 z, 2.44301354525e-2f );
    p       = std::fmaf( p,                 z, 5.34112807005e-2f );
    p       = std::fmaf( p,                 z, 1.33387994085e-1f );
    p       = std::fmaf( p,                 z, 3.33331568548e-1f );
    return std::fmaf( r, z * p, r );   // r + r·z·P(z)
}

// tan — octant range reduction by π/2 + the identity tan(r + π/2) = -1/tan(r).
// k = round(x / (π/2)) puts r = x − k·π/2 into [-π/4, π/4] via two-step
// Cody-Waite (HI/LO split of π/2, the halves of sin()'s PI_HI/PI_LO so the
// reduction stays bit-consistent with sin/cos). Odd octants take the −cot
// branch; tan correctly returns ±inf at the ±π/2 poles (−1/0).
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float tan( float x ) noexcept
{
    constexpr float TWO_OVER_PI = 0.6366197723675814f;
    constexpr float PIO2_HI     = 1.5707963f;       // PI_HI * 0.5
    constexpr float PIO2_LO     = -4.371139e-8f;    // PI_LO * 0.5

    const float k = __builtin_rintf( x * TWO_OVER_PI );
    float r       = std::fmaf( -k, PIO2_HI, x );
    r             = std::fmaf( -k, PIO2_LO, r );    // r ∈ [-π/4, π/4]

    const float t = tanPoly( r );
    return ( static_cast<int>(k) & 1 ) ? ( -1.0f / t ) : t;
}

// ==========================================================================
// invSin(theta)  — 1 / sin(theta)  for theta ∈ (0, π)
// invSinDirect(s) — 1 / s  where s = sin(theta), already computed
//
// Two entry points exist because several callers have sin(theta) already in
// hand (from acosSin) and should not recompute it:
//
//   invSinDirect(sinTheta)  — use when sinTheta came from acosSin()
//   invSin(theta)           — use when only theta is known
//
// Stability analysis — all small-denominator cases:
//
//   theta ≈ 0  (nearly-identical quaternions):
//     slerp's  if(1-cos_t > .0001f)  guard fires at cos_t > 0.9999,
//     meaning sinTheta = sqrt(1-cos²) > 0.014 at the threshold.
//     invSin(theta) is never called for angles that small in practice.
//     The SMALLEST_DIVISOR guard is a backstop for numerical accidents.
//
//   theta ≈ π  (antipodal quaternions — 180° apart):
//     The hemisphere flip  cos_t = -cos_t  maps cos_t ≈ -1 → cos_t ≈ 1,
//     so again the slerp guard fires before invSin is reached.
//     For log() the identity-rotation case (w=1, theta=0) is handled by
//     the explicit sinTheta threshold check in the caller.
//
//   theta exactly 0 or π:
//     acosSin(±1.0) returns sinTheta = sqrt(fmaf(-x,x,1)) = sqrt(0) = 0.
//     The SMALLEST_DIVISOR guard returns a finite large value; the caller
//     (log / getAxisAngle) must check sinTheta before calling invSinDirect.
//
// NEON vrecpe + two NR steps:
//   Step 1: ~11-bit mantissa → ~23-bit (sufficient for slerp)
//   Step 2: ~23-bit → ~47-bit (exceeds float precision — ensures no error
//           accumulates when invSin feeds into a subsequent multiply)
//   The extra step costs 2 instructions and executes in the multiply pipeline
//   alongside the two sin() calls in slerp — effectively free on A75+.
// ==========================================================================

#if defined(__ARM_NEON) || defined(__ARM_NEON__)

// invSinDirect: takes already-computed sinTheta from acosSin() — no sinPoly.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float invSinDirect( float sinTheta ) noexcept
{
    if( sinTheta < fastmath::SMALLEST_DIVISOR ) [[unlikely]]
        return 1.f / fastmath::SMALLEST_DIVISOR;

    float32x2_t vs = vdup_n_f32(sinTheta);
    float32x2_t r  = vrecpe_f32(vs);
    r = vmul_f32(r, vrecps_f32(vs, r));    // step 1: 8 → 23 bits
    r = vmul_f32(r, vrecps_f32(vs, r));    // step 2: 23 → 47 bits (exceeds float)
    return vget_lane_f32(r, 0);
}

[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float invSin( float theta ) noexcept
{
    const float thetaAbs = fastmath::fabsf(theta);
    const float xf = (thetaAbs > detail::PI_2) ? (detail::PI_v - thetaAbs) : thetaAbs;
    const float s  = sinPoly(xf);
    return invSinDirect(s);   // reuse the guarded NEON path
}

#else

[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float invSinDirect( float sinTheta ) noexcept
{
    if( sinTheta < fastmath::SMALLEST_DIVISOR ) [[unlikely]]
        return 1.f / fastmath::SMALLEST_DIVISOR;
    return 1.f / sinTheta;
}

[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float invSin( float theta ) noexcept
{
    const float thetaAbs = fastmath::fabsf(theta);
    const float xf = (thetaAbs > detail::PI_2) ? (detail::PI_v - thetaAbs) : thetaAbs;
    const float s  = sinPoly(xf);
    return invSinDirect(s);
}

#endif

// ==========================================================================
// acos / asin / acosSin
//
// On boundary handling:
//   We clamp to [-1, 1] unconditionally.  The polynomial uses sqrt(1-|x|),
//   which is imaginary for |x| > 1 even by a single ULP.  Using a soft guard
//   (0.99987) as the old code did leaves valid inputs in (0.99987, 1.0) mapped
//   to 0 incorrectly.  The full clamp + explicit boundary return is correct
//   and costs one compare per call.
//
// Polynomial: Abramowitz & Stegun 4.4.45 (3-term, max error ≈ 3e-4 rad)
//   acos(x) ≈ sqrt(1-|x|) * (c0 + |x|*(c1 + |x|*(c2 + |x|*c3)))
//   reflected for negative x: acos(x) = π - acos(-x)
//
// For higher accuracy (if needed), the 7-term minimax reduces error to ~1e-7:
//   p = ((((((-0.0012624911*|x|+0.0066700901)*|x|-0.0170881256)*|x|+0.0308918810)
//         *|x|-0.0501743046)*|x|+0.0889789874)*|x|-0.2145988016)*|x|+1.5707963050
// The 3-term version below is sufficient for all uses in this codebase.
// ==========================================================================

// Internal: evaluate acos polynomial on x ∈ [0, 1).  NO clamp, NO boundary check.
// Returns acos for positive x; caller mirrors for negative.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
static float acosPoly( float x_abs ) noexcept
{
    // A&S 4.4.45 — 3-term Horner on |x|
    float p = std::fmaf( x_abs, -0.0187293f,  0.0742610f );
    p       = std::fmaf( x_abs,  p,           -0.2121144f );
    p       = std::fmaf( x_abs,  p,            1.5707288f );
    return std::sqrt( 1.0f - x_abs ) * p;
}

// acos — safe, full [-1, 1] input range
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float acos( float x ) noexcept
{
    // Clamp to prevent sqrt of negative from rounding noise
    x = fastmath::clamp( x, -1.0f, 1.0f );
    if( x >=  1.0f ) return 0.0f;
    if( x <= -1.0f ) return fastmath::PI_FLOAT;

    const float result = acosPoly( fastmath::fabsf(x) );
    return ( x < 0.0f ) ? (fastmath::PI_FLOAT - result) : result;
}

// asin — via identity: asin(x) = π/2 - acos(x)
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float asin( float x ) noexcept
{
    return detail::PI_2 - acos(x);
}

// acosSin — returns {theta, sin(theta)} in one call.
// Used by slerp: avoids computing acos then separately evaluating sin(theta).
// sin(theta) = sqrt(1 - x²) via Pythagorean identity — this is EXACT
// (no polynomial error) and cheaper than calling sin(acos(x)).
// fmaf(-x,x,1) = 1 - x² with a single fused instruction, no cancellation.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
AcosSinOut acosSin( float x ) noexcept
{
    x = fastmath::clamp( x, -1.0f, 1.0f );
    const float x_abs = fastmath::fabsf(x);

    const float acosVal   = acosPoly( x_abs );
    const float theta     = ( x < 0.0f ) ? (fastmath::PI_FLOAT - acosVal) : acosVal;
    const float sinTheta  = std::sqrt( std::fmaf(-x, x, 1.0f) );  // sqrt(1 - x²), exact

    return { theta, sinTheta };
}

// ==========================================================================
// Real (libm) wrappers — use when highest accuracy is required
// ==========================================================================
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float realSin  ( float x )          noexcept { return __builtin_sinf(x); }
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float realCos  ( float x )          noexcept { return __builtin_cosf(x); }
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float realTan  ( float x )          noexcept { return __builtin_tanf(x); }
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float realAtan2( float y, float x ) noexcept { return __builtin_atan2f(y,x); }
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float realAcos ( float x )          noexcept
{
    x = fastmath::clamp(x, -1.f, 1.f);
    return __builtin_acosf(x);
}

// ==========================================================================
// Angle utilities (unchanged from previous version)
// ==========================================================================

// ==========================================================================
// atanUnitH / arctan2H / arctan2HSafe
//
// atanUnitH(a)     — core: atan(a) for a ∈ [0, 1], NO guards, ~1.8e-6 rad error
// arctan2H(y, x)   — fast path: maxv guard only, no isfinite, branchless signs
// arctan2HSafe(y,x)— adds NaN/Inf + origin guard; use for external/untrusted input
//
// Why separate?
//   isfinite() compiles to 2 compares + AND on ARM64 and adds a taken-branch
//   penalty on every call even when inputs are provably finite.  The vast
//   majority of call sites in this codebase use matrix elements, quaternion
//   components, or dot-product results — all of which are finite if the
//   upstream data is valid.  Splitting lets hot paths pay zero overhead.
//
// Accuracy: degree-11 odd minimax on [0,1], max error ≈ 1.8e-6 rad (0.0001°).
// (Upgraded from a 3-coeff Hastings fit at ~5e-4 rad — see math/bench_atan.cpp;
// the extra terms are essentially free.) An even-earlier arctan2H had max error
// ~0.006 rad (0.35°) and returned wrong values at the origin.
// ==========================================================================

// Core polynomial: atan(a) for a ∈ [0, 1].
// Caller is responsible for ensuring a is in range.
// No branches — pure arithmetic, good for ILP.
// Degree-11 odd minimax (6 coeffs). Profiling (math/bench_atan.cpp) showed the
// extra Horner terms cost ~0.01 ns over the old 3-coeff Hastings fit yet cut the
// error ~115× (2.0e-4 → 1.8e-6 rad), so the higher-order fit is essentially free.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float atanUnitH( float a ) noexcept
{
    const float s = a * a;
    float p =          -0.01172120f;
    p = std::fmaf(p, s,  0.05265332f);
    p = std::fmaf(p, s, -0.11643287f);
    p = std::fmaf(p, s,  0.19354346f);
    p = std::fmaf(p, s, -0.33262347f);
    p = std::fmaf(p, s,  0.99997726f);
    return p * a;
}

// Fast atan2 — assumes finite, non-NaN inputs.
// maxv < 1e-20 guard handles exact zero and subnormal inputs gracefully
// (returns 0, which is the correct limit as (x,y)→(0,0)).
// 1e-20 sits above the subnormal range (~1.4e-45); any normal-float input passes.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float arctan2H( float y, float x ) noexcept
{
    constexpr float EPS     = 1.0e-20f;
    constexpr float HALF_PI = 1.57079632679489661923f;

    const float ax   = fastmath::fabsf(x);
    const float ay   = fastmath::fabsf(y);
    const float maxv = __builtin_fmaxf(ax, ay);

    if( maxv < EPS ) [[unlikely]] return 0.f;

    float r = atanUnitH( __builtin_fminf(ax, ay) / maxv );

    // Octant folds as ternary selects (fcsel on ARM, no taken-branch penalty —
    // ~7% faster than the equivalent `if`s, see math/bench_atan2.cpp).
    r = ( ay > ax ) ? ( HALF_PI - r )            : r;   // fold [π/4,π/2] octant
    r = ( x < 0.f ) ? ( fastmath::PI_FLOAT - r ) : r;   // fold left half-plane
    // Branchless sign restore: XOR sign bit of y onto result
    const uint32_t sy = std::bit_cast<uint32_t>(y) & 0x80000000u;
    return std::bit_cast<float>(std::bit_cast<uint32_t>(r) ^ sy);
}

// Safe atan2 — adds NaN/Inf protection for untrusted or external inputs.
// Uses bit manipulation to detect NaN/Inf since __builtin_isfinite is
// optimized away with -ffast-math. Checks IEEE exponent field directly.
// Use this at API boundaries; prefer arctan2H in internal hot paths.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC
float arctan2HSafe( float y, float x ) noexcept
{
    // NaN or Inf: exponent field == 0xFF (all ones) means non-finite
    const uint32_t ex = std::bit_cast<uint32_t>(x) & 0x7F800000u;
    const uint32_t ey = std::bit_cast<uint32_t>(y) & 0x7F800000u;
    if( __builtin_expect(ex == 0x7F800000u || ey == 0x7F800000u, 0) )
        return 0.f;
    return arctan2H(y, x);
}

// Wrap to [−π, π] via round-multiply-subtract (NO fmod — one round + FMA).
// Both endpoints can occur and are equivalent angles; note wrapToPi(π) = −π.
// (The old pre-rewrite code returned 0 for |a| >= 3.141, silently dropping
// valid angles between 3.141 and π.)
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float wrapToPi( float a ) noexcept
{
    const float q = std::roundf(a * fastmath::INV_PI * 0.5f);
    return a - q * fastmath::TWO_PI_FLOAT;
}

// wrapToPi2 — same as wrapToPi; kept as a separate name for call-site clarity.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float wrapToPi2( float a ) noexcept
{
    const float q = std::roundf(a * fastmath::INV_PI * 0.5f);
    return a - q * fastmath::TWO_PI_FLOAT;
}

// Shortest signed angular difference from→to in [−π, π]. The heading-error
// primitive: steering code wants wrapToPi(target − current) constantly.
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float angleDiff( float fromRad, float toRad ) noexcept
{
    return wrapToPi(toRad - fromRad);
}

[[nodiscard]] ALWAYS_INLINE CONST_FUNC float rotationLerp( float start, float end, float t ) noexcept
{
    const float d1 = fastmath::fabsf(start - end);
    const float d2 = fastmath::fabsf(start - (end + fastmath::TWO_PI_FLOAT));
    const float d3 = fastmath::fabsf(start - (end - fastmath::TWO_PI_FLOAT));
    float out;
    if(d1 < d2 && d1 < d3) out = fastmath::lerp(start, end,                        t);
    else if(d2 <= d3)      out = fastmath::lerp(start, end + fastmath::TWO_PI_FLOAT, t);
    else                   out = fastmath::lerp(start, end - fastmath::TWO_PI_FLOAT, t);
    return wrapToPi2(out);
}

// Legacy aliases kept for callers using the old names
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float polySin ( float v ) noexcept { return sin(v);  }
[[nodiscard]] ALWAYS_INLINE CONST_FUNC float polyAcos( float x ) noexcept { return acos(x); }
inline void polySinCos( float v, float& s, float& c ) noexcept
    { auto r = sincos(v); s = r.sin; c = r.cos; }

} // namespace fastTrig
