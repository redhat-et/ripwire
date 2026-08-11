// The dual-compile header (.cuh): compiled by BOTH nvcc's device pass and the host C++ compiler,
// exactly the role AAPLSharedTypes.h plays in the Metal fixture.
#pragma once

#ifdef __CUDACC__
#define RK_HOSTDEV __host__ __device__
// A module table INSIDE the preprocessor conditional — the NVIDIA cuda-samples header-guard/dual-compile
// idiom (volumeRender's c_invViewMatrix, particles' cudaParams): the declaration's parent is
// preproc_ifdef, not translation_unit, so the capture needs the preproc wrappers to see it.
__constant__ float rk_guardTable[ 16 ];
#else
#define RK_HOSTDEV
#endif

constexpr int RK_TILE_WIDTH = 256;

struct RkReduceParams
{
    int   count;
    float scale;
};

RK_HOSTDEV inline float rk_normalize( float v, const RkReduceParams& p )
{
    return v * p.scale;
}

float rk_launchReduce( const float* devIn, float* devOut, int n );
void  rk_launchFill( float* dst, int n );
