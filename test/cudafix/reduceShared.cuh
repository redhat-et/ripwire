// The dual-compile header (.cuh): compiled by BOTH nvcc's device pass and the host C++ compiler,
// exactly the role AAPLSharedTypes.h plays in the Metal fixture.
#pragma once

#ifdef __CUDACC__
#define RK_HOSTDEV __host__ __device__
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
