#pragma once

// dualcompile.h — the motivating idiom itself: ONE macro with TWO definitions behind an #ifdef, spelling
// the same 2-byte scalar on each side of the CPU/GPU boundary. The model must resolve BOTH and accept the
// answer because they agree on the size; if a later edit made them disagree, the field would go unsized
// rather than pick a side.
//   beat@0(2)  hat@2(2)  pad4  level@8(4)  => 12? no: level is 4-aligned, so pad 0. See below.
//   beat@0(2)  hat@2(2)  level@4(4)  => 8, align 4
#ifdef __METAL_VERSION__
    #define FIX_HALF_SCALAR half
#else
    #define FIX_HALF_SCALAR __fp16
#endif

typedef struct DualCompileUniforms
{
    FIX_HALF_SCALAR beat;
    FIX_HALF_SCALAR hat;
    float           level;
} DualCompileUniforms;

static_assert( sizeof( DualCompileUniforms ) == 8, "dual-compile byte contract" );

// The same shape with a macro whose two definitions DISAGREE on size — the model must refuse rather than
// pick whichever arm it read last.
#ifdef __METAL_VERSION__
    #define FIX_AMBIGUOUS_SCALAR half
#else
    #define FIX_AMBIGUOUS_SCALAR double
#endif

typedef struct AmbiguousMacroCase
{
    FIX_AMBIGUOUS_SCALAR wobbly;
    float                after;
} AmbiguousMacroCase;
