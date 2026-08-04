// The pure-host half: calls the launch wrappers and the dual-compile helper through the .cuh.
#include "reduceShared.cuh"

float host_runPipeline( const float* devIn, float* devOut, int n )
{
    rk_launchFill( devOut, n );
    const float sum = rk_launchReduce( devIn, devOut, n );
    RkReduceParams params{ n, 0.5f };
    return rk_normalize( sum, params );
}
