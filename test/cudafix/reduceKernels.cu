// The device translation unit: every CUDA construct the plain C++ grammar measurably mishandles.
// `__global__`/`__device__` qualifiers, a `__constant__` module table, `__launch_bounds__`, a
// templated kernel, and — the acceptance case — `<<<grid, block>>>` launch sites, which under the
// C++ grammar produced NO call reference at all (--callers of a kernel returned count=0).
#include "reduceShared.cuh"

__constant__ float rk_scaleTable[ 64 ];

__device__ float rk_warpReduce( float v )
{
    for( int offset = 16; offset > 0; offset >>= 1 )
    {
        v += __shfl_down_sync( 0xffffffffu, v, offset );
    }
    return v;
}

__device__ __forceinline__ float rk_clampScale( float v, int bin )
{
    return v * rk_scaleTable[ bin & 63 ];
}

__global__ void rk_reduceSum( const float* in, float* out, int n )
{
    __shared__ float tile[ 256 ];
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    float v = ( i < n ) ? rk_clampScale( in[ i ], i ) : 0.0f;
    v = rk_warpReduce( v );
    tile[ threadIdx.x ] = v;
    __syncthreads();
    if( threadIdx.x == 0 )
    {
        out[ blockIdx.x ] = tile[ 0 ];
    }
}

__global__ void __launch_bounds__( 256, 4 ) rk_reduceMax( const float* in, float* out, int n )
{
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if( i < n )
    {
        atomicMax( reinterpret_cast<int*>( out ), __float_as_int( in[ i ] ) );
    }
}

// Host-side wrappers in the SAME .cu — the launch sites the call graph must see.
float rk_launchReduce( const float* devIn, float* devOut, int n )
{
    const dim3 grid( ( n + 255 ) / 256 );
    const dim3 block( 256 );
    rk_reduceSum<<<grid, block>>>( devIn, devOut, n );
    rk_reduceMax<<<grid, block, 0>>>( devIn, devOut, n );
    cudaDeviceSynchronize();
    return 0.0f;
}

template <typename T>
__global__ void rk_fill( T* dst, T value, int n )
{
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if( i < n )
    {
        dst[ i ] = value;
    }
}

void rk_launchFill( float* dst, int n )
{
    rk_fill<float><<<( n + 255 ) / 256, 256>>>( dst, 1.0f, n );
}
