// AAPLSharedTypes.h — a DUAL-COMPILE header: the same declarations are compiled once by the C++/ObjC++
// host and once by the Metal shader compiler, guarded by __METAL_VERSION__. This is the shape the
// Metal (.metal) dual-compile-header case turns on: the shared symbol is DEFINED here (a C++-grammar file) and CALLED from
// both sides, so the call graph must reach it from a .cpp AND from a .metal.
#ifndef AAPL_SHARED_TYPES_H
#define AAPL_SHARED_TYPES_H

#if __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
#else
#include <cstdint>
#endif

// The per-world style row both halves read.
struct MlStyle
{
    float coverage;
    float warmth;
};

// Module-scope table in the METAL address space — `constant` is an MSL-only storage qualifier the C++
// grammar has no keyword for. It must not derail the declarations that follow it.
#if __METAL_VERSION__
constant float kMlWarmthBias[4] = { 0.0f, 0.25f, 0.5f, 0.75f };
#else
static const float kMlWarmthBias[4] = { 0.0f, 0.25f, 0.5f, 0.75f };
#endif

static inline float ml_warmthFor( unsigned int personality )
{
    return kMlWarmthBias[ personality & 3u ];
}

// The acceptance symbol: defined here, called from BOTH the .metal shader and the .cpp host.
static inline MlStyle ml_styleFor( unsigned int personality )
{
    MlStyle s;
    s.coverage = 0.5f + 0.1f * float( personality & 3u );
    s.warmth   = ml_warmthFor( personality );
    return s;
}

#endif   // AAPL_SHARED_TYPES_H
