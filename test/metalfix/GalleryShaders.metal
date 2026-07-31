//
//  GalleryShaders.metal — the MSL half of the fixture.
//
//  Every construct here is one the C++ grammar has no keyword for, kept deliberately so the gate fails
//  the day error recovery stops localising them: the `kernel`/`vertex`/`fragment` function qualifiers,
//  the `constant`/`device`/`threadgroup` address spaces, `[[attribute]]` bindings, and the `#import`
//  spelling of `#include` (10 of the 45 real shaders in the measured reference tree use `#import`).
//
#include <metal_stdlib>
#import "AAPLSharedTypes.h"     // dual-compile header, #import spelling with a trailing comment
using namespace metal;

struct GalleryVertexOut
{
    float4 position [[ position ]];
    float2 uv;
    uint   look;
};

// A plain MSL free function — no qualifier, so this one is ordinary C++ to the grammar.
static inline float gallery_falloff( float d, float width )
{
    return saturate( 1.0f - d / max( width, 1e-4f ) );
}

// `vertex` qualifier + `device` address space + [[attribute]] bindings.
vertex GalleryVertexOut gallery_vertexSphere( const device float4*      positions [[ buffer(0) ]],
                                              constant float4x4&        viewProj  [[ buffer(1) ]],
                                              uint                      vid       [[ vertex_id ]] )
{
    GalleryVertexOut out;
    out.position = viewProj * positions[ vid ];
    out.uv       = float2( 0.0f, 0.0f );
    out.look     = vid & 3u;
    return out;
}

// `fragment` qualifier — and the acceptance call: a .metal caller of a symbol defined in the shared
// C++-grammar header. Before Metal was indexed, --callers=ml_styleFor returned 0 for exactly this shape.
fragment float4 gallery_fragmentSphere( GalleryVertexOut in [[ stage_in ]] )
{
    const MlStyle mls  = ml_styleFor( in.look );
    const float   fade = gallery_falloff( in.uv.x, mls.coverage );
    return float4( mls.warmth * fade, fade, fade, 1.0f );
}

// `kernel` qualifier + a `threadgroup` address-space parameter + texture access qualifiers.
kernel void gallery_prefilter( texture2d<float>                 src   [[ texture(0) ]],
                               texture2d<float, access::write>  dst   [[ texture(1) ]],
                               threadgroup float*               tile  [[ threadgroup(0) ]],
                               uint2                            gid   [[ thread_position_in_grid ]] )
{
    if( gid.x >= dst.get_width() || gid.y >= dst.get_height() ) return;

    const MlStyle mls = ml_styleFor( gid.x & 3u );
    tile[ 0 ]         = gallery_falloff( float( gid.y ), mls.coverage );
    dst.write( float4( tile[ 0 ], mls.warmth, 0.0f, 1.0f ), gid );
}
