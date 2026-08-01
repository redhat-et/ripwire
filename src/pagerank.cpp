#include "pagerank.h"

#include "csrverify.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

namespace rw
{

namespace
{

inline constexpr std::size_t kReductionBlockSize = 1024;

double probabilityMass( std::span<const double> values ) noexcept
{
    double total = 0.0;
    for( std::size_t blockBegin = 0; blockBegin < values.size(); blockBegin += kReductionBlockSize )
    {
        const std::size_t blockEnd = std::min( blockBegin + kReductionBlockSize, values.size() );
        double partial = 0.0;
        for( std::size_t valueIndex = blockBegin; valueIndex < blockEnd; ++valueIndex )
            partial += values[valueIndex];
        total += partial;
    }
    return total;
}

}

unsigned pageRankDouble( const sparseCsr<float>& inEdges, std::span<const double> weightedOutDegree,
                         std::span<const double> teleport, std::span<double> rank, PageRankConfig config )
{
    const std::size_t nodeCount = inEdges.rows();
    VERIFY( verifyCsr( inEdges, nodeCount ) );
    VERIFY( weightedOutDegree.size() == nodeCount );
    VERIFY( teleport.size() == nodeCount );
    VERIFY( rank.size() == nodeCount );
    VERIFY( config.alpha >= 0.0 && config.alpha < 1.0 );
    VERIFY( config.tolerance > 0.0 );
    VERIFY( config.maxIterationCount > 0 );
    if( nodeCount == 0 )
        return 0;
    VERIFY( rank.data() != teleport.data() );

    for( std::size_t nodeIndex = 0; nodeIndex < nodeCount; ++nodeIndex )
    {
        VERIFY( std::isfinite( weightedOutDegree[nodeIndex] ) && weightedOutDegree[nodeIndex] >= 0.0 );
        VERIFY( std::isfinite( teleport[nodeIndex] ) && teleport[nodeIndex] >= 0.0 );
    }
    VERIFY( std::fabs( probabilityMass( teleport ) - 1.0 ) <= 1e-9 );

    // Allocate all scratch once. The power-iteration loop performs no dynamic allocation.
    std::vector<double> currentRank( teleport.begin(), teleport.end() );
    std::vector<double> nextRank( nodeCount, 0.0 );
    std::vector<double> scaledRank( nodeCount, 0.0 );

    const std::uint32_t* rowOffsets = inEdges.rowOffsets();
    const std::uint32_t* columnIndices = inEdges.colIndices();
    const float* edgeValues = inEdges.values();
    bool hasConverged = false;
    unsigned iterationCount = 0;

    for( ; iterationCount < config.maxIterationCount; ++iterationCount )
    {
        // Dangling mass uses fixed blocks and canonical fold order.
        double danglingMass = 0.0;
        for( std::size_t blockBegin = 0; blockBegin < nodeCount; blockBegin += kReductionBlockSize )
        {
            const std::size_t blockEnd = std::min( blockBegin + kReductionBlockSize, nodeCount );
            double partial = 0.0;
            for( std::size_t nodeIndex = blockBegin; nodeIndex < blockEnd; ++nodeIndex )
                partial += weightedOutDegree[nodeIndex] > 0.0 ? 0.0 : currentRank[nodeIndex];
            danglingMass += partial;
        }

        for( std::size_t nodeIndex = 0; nodeIndex < nodeCount; ++nodeIndex )
            scaledRank[nodeIndex] = weightedOutDegree[nodeIndex] > 0.0 ? currentRank[nodeIndex] / weightedOutDegree[nodeIndex] : 0.0;

        // In-edge CSR gather. Edges remain float; multiplication and accumulation promote to double.
        const double teleportScale = config.alpha * danglingMass + ( 1.0 - config.alpha );
        for( std::size_t targetNodeId = 0; targetNodeId < nodeCount; ++targetNodeId )
        {
            double incomingRank = 0.0;
            for( std::uint32_t edgeIndex = rowOffsets[targetNodeId]; edgeIndex < rowOffsets[targetNodeId + 1]; ++edgeIndex )
                incomingRank += double( edgeValues[edgeIndex] ) * scaledRank[columnIndices[edgeIndex]];
            nextRank[targetNodeId] = config.alpha * incomingRank + teleportScale * teleport[targetNodeId];
        }

        // L1 residual uses the same fixed-block canonical reduction discipline.
        double residual = 0.0;
        for( std::size_t blockBegin = 0; blockBegin < nodeCount; blockBegin += kReductionBlockSize )
        {
            const std::size_t blockEnd = std::min( blockBegin + kReductionBlockSize, nodeCount );
            double partial = 0.0;
            for( std::size_t nodeIndex = blockBegin; nodeIndex < blockEnd; ++nodeIndex )
                partial += std::fabs( nextRank[nodeIndex] - currentRank[nodeIndex] );
            residual += partial;
        }

        currentRank.swap( nextRank );
        if( residual < config.tolerance )
        {
            ++iterationCount;
            hasConverged = true;
            break;
        }
    }

    if( !hasConverged )
        DEGRADED_PATH_ALERT( "PageRank reached max iterations before L1 convergence" );
    std::copy( currentRank.begin(), currentRank.end(), rank.begin() );
    return iterationCount;
}

} // namespace rw
