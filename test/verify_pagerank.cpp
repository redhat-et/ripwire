#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "pagerank.h"
#include "graph.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <numeric>
#include <span>
#include <vector>

namespace
{

constexpr double kShippedAlpha = double( 0.85f );
constexpr double kShippedBand = 1e-5;
constexpr double kPreciseBand = 1e-12;

sparseCsr<float> buildCsr( std::size_t nodeCount, std::span<const std::uint32_t> rowOffsets,
                           std::span<const std::uint32_t> columnIndices, std::span<const float> values )
{
    sparseCsr<float> csr( nodeCount, nodeCount, values.size() );
    std::copy( rowOffsets.begin(), rowOffsets.end(), csr.rowOffsets() );
    std::copy( columnIndices.begin(), columnIndices.end(), csr.colIndices() );
    std::copy( values.begin(), values.end(), csr.values() );
    return csr;
}

bool isProbabilityVector( std::span<const double> rank )
{
    double mass = 0.0;
    for( const double value : rank )
    {
        if( !std::isfinite( value ) || value < 0.0 )
        {
            return false;
        }
        mass += value;
    }
    return std::fabs( mass - 1.0 ) <= 1e-9;
}

void checkKernelInvariants( std::span<const double> rank )
{
    double mass = 0.0;
    for( const double value : rank )
    {
        CHECK( std::isfinite( value ) );
        CHECK( value >= 0.0 );
        mass += value;
    }
    if( !rank.empty() )
    {
        CHECK( std::fabs( mass - 1.0 ) <= 1e-12 );
    }
}

std::vector<std::uint32_t> topOrder( std::span<const double> rank )
{
    std::vector<std::uint32_t> order( rank.size() );
    std::iota( order.begin(), order.end(), 0u );
    std::sort( order.begin(), order.end(), [ rank ]( std::uint32_t a, std::uint32_t b )
               {
                   if( rank[ a ] != rank[ b ] )
                   {
                       return rank[ a ] > rank[ b ];
                   }
                   return a < b;
               } );
    return order;
}

}

TEST_CASE( "double PageRank numeric, dangling, and top-K contracts" )
{
    const rw::PageRankConfig preciseConfig{ .alpha = 0.85, .tolerance = 1e-13, .maxIterationCount = 400 };

    // Empty input is a valid graph boundary.
    {
        const sparseCsr<float> csr( 0, 0, 0 );
        std::vector<double> rank;
        const unsigned iterationCount = rw::pageRankDouble( csr, {}, {}, rank, preciseConfig ).iterationCount;
        const bool isEmptyBoundaryValid = iterationCount == 0 && rank.empty();
        CHECK_MESSAGE( isEmptyBoundaryValid, "empty PageRank boundary failed" );
    }

    // Two-node dangling fixture: 0 -> 1, node 1 dangling. Exact stationary vector at alpha=.85 is [20/57,37/57].
    {
        const std::array<std::uint32_t, 3> rowOffsets{ 0, 0, 1 };
        const std::array<std::uint32_t, 1> columnIndices{ 0 };
        const std::array<float, 1> values{ 1.f };
        const sparseCsr<float> csr = buildCsr( 2, rowOffsets, columnIndices, values );
        const std::array<double, 2> weightedOutDegree{ 1.0, 0.0 };
        const std::array<double, 2> teleport{ 0.5, 0.5 };
        std::vector<double> rank( 2, 0.0 );
        rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, preciseConfig );

        CHECK_MESSAGE( isProbabilityVector( rank ), "dangling PageRank lost probability mass or produced invalid values" );
        const bool matchesDominantVector = std::fabs( rank[ 0 ] - 20.0 / 57.0 ) <= 1e-5
                                           && std::fabs( rank[ 1 ] - 37.0 / 57.0 ) <= 1e-5;
        CHECK_MESSAGE( matchesDominantVector, "PageRank does not match the hand-derived dominant vector" );
    }

    // Every node dangling: teleport is the unique stationary distribution.
    {
        const std::array<std::uint32_t, 4> rowOffsets{ 0, 0, 0, 0 };
        const sparseCsr<float> csr = buildCsr( 3, rowOffsets, {}, {} );
        const std::array<double, 3> weightedOutDegree{ 0.0, 0.0, 0.0 };
        const std::array<double, 3> teleport{ 0.6, 0.3, 0.1 };
        std::vector<double> rank( 3, 0.0 );
        rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, preciseConfig );
        CHECK_MESSAGE( isProbabilityVector( rank ), "all-dangling PageRank lost probability mass" );
        for( std::size_t nodeIndex = 0; nodeIndex < rank.size(); ++nodeIndex )
        {
            CHECK_MESSAGE( std::fabs( rank[ nodeIndex ] - teleport[ nodeIndex ] ) <= 1e-12,
                           "all-dangling PageRank differs from teleport distribution" );
        }
    }

    // Fractional edge weights use a double out-degree accumulated from the same promoted float edges.
    {
        const std::array<std::uint32_t, 4> rowOffsets{ 0, 0, 1, 2 };
        const std::array<std::uint32_t, 2> columnIndices{ 0, 0 };
        const std::array<float, 2> values{ 0.1f, 0.2f };
        const sparseCsr<float> csr = buildCsr( 3, rowOffsets, columnIndices, values );
        const std::array<double, 3> weightedOutDegree{ double( values[ 0 ] ) + double( values[ 1 ] ), 0.0, 0.0 };
        const std::array<double, 3> teleport{ 1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0 };
        std::vector<double> rank( 3, 0.0 );
        rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, preciseConfig );
        CHECK_MESSAGE( isProbabilityVector( rank ), "fractional-edge PageRank lost probability mass" );
    }

    // Three callers point to one dangling hub.
    {
        const std::array<std::uint32_t, 5> rowOffsets{ 0, 0, 0, 0, 3 };
        const std::array<std::uint32_t, 3> columnIndices{ 0, 1, 2 };
        const std::array<float, 3> values{ 1.f, 1.f, 1.f };
        const sparseCsr<float> csr = buildCsr( 4, rowOffsets, columnIndices, values );
        const std::array<double, 4> weightedOutDegree{ 1.0, 1.0, 1.0, 0.0 };
        const std::array<double, 4> teleport{ 0.25, 0.25, 0.25, 0.25 };
        const std::array<std::uint32_t, 4> expectedOrder{ 3, 0, 1, 2 };

        std::vector<std::uint32_t> firstOrder;
        for( unsigned runIndex = 0; runIndex < 3; ++runIndex )
        {
            std::vector<double> rank( 4, 0.0 );
            rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, preciseConfig );
            CHECK_MESSAGE( isProbabilityVector( rank ), "star PageRank produced an invalid probability vector" );
            const std::vector<std::uint32_t> order = topOrder( rank );
            CHECK_MESSAGE( std::equal( order.begin(), order.end(), expectedOrder.begin() ), "star PageRank top-K order is wrong" );
            if( runIndex == 0 )
            {
                firstOrder = order;
            }
            else
            {
                CHECK_MESSAGE( order == firstOrder, "PageRank top-K order changed between identical runs" );
            }
        }
    }
}

// ------------------------------------------------------------------------------------------------
// K0-K17: The PageRank kernel (prompts/help-wanted/graph-unit-tests.md)
// ------------------------------------------------------------------------------------------------

TEST_CASE( "K0: empty graph boundary produces zero iterations and empty rank" )
{
    const sparseCsr<float> csr( 0, 0, 0 );
    const rw::PageRankConfig shippedConfig{ .alpha = kShippedAlpha, .tolerance = 1e-6, .maxIterationCount = 100 };

    std::vector<double> rank;
    const rw::PageRankRun run = rw::pageRankDouble( csr, {}, {}, rank, shippedConfig );
    CHECK( run.iterationCount == 0 );
    CHECK( run.hasConverged );
    CHECK( rank.empty() );
    checkKernelInvariants( rank );

    const rw::PageRankConfig cap1Config{ .alpha = kShippedAlpha, .tolerance = 1e-6, .maxIterationCount = 1 };
    const rw::PageRankRun runCap1 = rw::pageRankDouble( csr, {}, {}, rank, cap1Config );
    CHECK( runCap1.iterationCount == 0 );
    CHECK( runCap1.hasConverged );
    CHECK( rank.empty() );
}

TEST_CASE( "K1: 1 node with no edges converges in 1 iteration to stationary vector 1.0" )
{
    const sparseCsr<float> csr( 1, 1, 0 );
    const std::array<double, 1> weightedOutDegree{ 0.0 };
    const std::array<double, 1> teleport{ 1.0 };
    std::vector<double> rank( 1, 0.0 );
    const rw::PageRankConfig shippedConfig{ .alpha = kShippedAlpha, .tolerance = 1e-6, .maxIterationCount = 100 };

    const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, shippedConfig );
    CHECK( run.iterationCount == 1 );
    CHECK( run.hasConverged );
    CHECK( rank[ 0 ] == 1.0 );
    checkKernelInvariants( rank );
}

TEST_CASE( "K2: 1 node with self-loop is respected by the kernel" )
{
    const std::array<std::uint32_t, 2> rowOffsets{ 0, 1 };
    const std::array<std::uint32_t, 1> columnIndices{ 0 };
    const std::array<float, 1> values{ 1.0f };
    const sparseCsr<float> csr = buildCsr( 1, rowOffsets, columnIndices, values );
    const std::array<double, 1> weightedOutDegree{ 1.0 };
    const std::array<double, 1> teleport{ 1.0 };
    std::vector<double> rank( 1, 0.0 );
    const rw::PageRankConfig shippedConfig{ .alpha = kShippedAlpha, .tolerance = 1e-6, .maxIterationCount = 100 };

    const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, shippedConfig );
    CHECK( run.iterationCount == 1 );
    CHECK( run.hasConverged );
    CHECK( rank[ 0 ] == 1.0 );
    checkKernelInvariants( rank );
}

TEST_CASE( "K3: 2-node chain 0->1 matches closed form across shipped and precise configs" )
{
    const std::array<std::uint32_t, 3> rowOffsets{ 0, 0, 1 };
    const std::array<std::uint32_t, 1> columnIndices{ 0 };
    const std::array<float, 1> values{ 1.0f };
    const sparseCsr<float> csr = buildCsr( 2, rowOffsets, columnIndices, values );
    const std::array<double, 2> weightedOutDegree{ 1.0, 0.0 };
    const std::array<double, 2> teleport{ 0.5, 0.5 };

    const double alpha = kShippedAlpha;
    const double expected0 = 1.0 / ( 2.0 + alpha );
    const double expected1 = ( 1.0 + alpha ) / ( 2.0 + alpha );

    // Shipped config: 17 iterations
    {
        std::vector<double> rank( 2, 0.0 );
        const rw::PageRankConfig shippedConfig{ .alpha = alpha, .tolerance = 1e-6, .maxIterationCount = 100 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, shippedConfig );
        CHECK( run.iterationCount == 17 );
        CHECK( run.hasConverged );
        CHECK( std::fabs( rank[ 0 ] - expected0 ) <= kShippedBand );
        CHECK( std::fabs( rank[ 1 ] - expected1 ) <= kShippedBand );
        checkKernelInvariants( rank );
    }

    // Precise config: 35 iterations
    {
        std::vector<double> rank( 2, 0.0 );
        const rw::PageRankConfig preciseConfig{ .alpha = alpha, .tolerance = 1e-13, .maxIterationCount = 400 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, preciseConfig );
        CHECK( run.iterationCount == 35 );
        CHECK( run.hasConverged );
        CHECK( std::fabs( rank[ 0 ] - expected0 ) <= kPreciseBand );
        CHECK( std::fabs( rank[ 1 ] - expected1 ) <= kPreciseBand );
        checkKernelInvariants( rank );
    }

    // Explicit 0.85 alpha checks 20/57 and 37/57
    {
        std::vector<double> rank( 2, 0.0 );
        const rw::PageRankConfig config85{ .alpha = 0.85, .tolerance = 1e-13, .maxIterationCount = 400 };
        rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, config85 );
        CHECK( std::fabs( rank[ 0 ] - 20.0 / 57.0 ) <= 1e-5 );
        CHECK( std::fabs( rank[ 1 ] - 37.0 / 57.0 ) <= 1e-5 );
    }
}

TEST_CASE( "K4: 3 disconnected nodes preserve teleport within 1e-12" )
{
    const sparseCsr<float> csr( 3, 3, 0 );
    const std::array<double, 3> weightedOutDegree{ 0.0, 0.0, 0.0 };
    const std::array<double, 3> teleport{ 0.6, 0.3, 0.1 };
    std::vector<double> rank( 3, 0.0 );
    const rw::PageRankConfig shippedConfig{ .alpha = kShippedAlpha, .tolerance = 1e-6, .maxIterationCount = 100 };

    const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, shippedConfig );
    CHECK( run.iterationCount == 1 );
    CHECK( run.hasConverged );
    for( std::size_t nodeIndex = 0; nodeIndex < 3; ++nodeIndex )
    {
        CHECK( std::fabs( rank[ nodeIndex ] - teleport[ nodeIndex ] ) <= 1e-12 );
    }
    checkKernelInvariants( rank );
}

TEST_CASE( "K5: cycle 0->1->2->0 produces uniform scores within 1e-15 of 1/3" )
{
    const std::array<std::uint32_t, 4> rowOffsets{ 0, 1, 2, 3 };
    const std::array<std::uint32_t, 3> columnIndices{ 2, 0, 1 };
    const std::array<float, 3> values{ 1.0f, 1.0f, 1.0f };
    const sparseCsr<float> csr = buildCsr( 3, rowOffsets, columnIndices, values );
    const std::array<double, 3> weightedOutDegree{ 1.0, 1.0, 1.0 };
    const std::array<double, 3> teleport{ 1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0 };
    std::vector<double> rank( 3, 0.0 );
    const rw::PageRankConfig shippedConfig{ .alpha = kShippedAlpha, .tolerance = 1e-6, .maxIterationCount = 100 };

    const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, shippedConfig );
    CHECK( run.iterationCount == 1 );
    CHECK( run.hasConverged );
    for( std::size_t nodeIndex = 0; nodeIndex < 3; ++nodeIndex )
    {
        CHECK( std::fabs( rank[ nodeIndex ] - 1.0 / 3.0 ) <= 1e-15 );
    }
    checkKernelInvariants( rank );
}

TEST_CASE( "K6: three callers of dangling hub produce bit-identical caller scores and stable top-K" )
{
    const std::array<std::uint32_t, 5> rowOffsets{ 0, 0, 0, 0, 3 };
    const std::array<std::uint32_t, 3> columnIndices{ 0, 1, 2 };
    const std::array<float, 3> values{ 1.0f, 1.0f, 1.0f };
    const sparseCsr<float> csr = buildCsr( 4, rowOffsets, columnIndices, values );
    const std::array<double, 4> weightedOutDegree{ 1.0, 1.0, 1.0, 0.0 };
    const std::array<double, 4> teleport{ 0.25, 0.25, 0.25, 0.25 };

    const double alpha = kShippedAlpha;
    const double expectedCaller = 1.0 / ( 4.0 + 3.0 * alpha );
    const double expectedHub = ( 1.0 + 3.0 * alpha ) / ( 4.0 + 3.0 * alpha );

    // Shipped config: 32 iterations
    {
        std::vector<double> rank( 4, 0.0 );
        const rw::PageRankConfig shippedConfig{ .alpha = alpha, .tolerance = 1e-6, .maxIterationCount = 100 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, shippedConfig );
        CHECK( run.iterationCount == 32 );
        CHECK( run.hasConverged );
        CHECK( std::fabs( rank[ 0 ] - expectedCaller ) <= kShippedBand );
        CHECK( std::fabs( rank[ 1 ] - expectedCaller ) <= kShippedBand );
        CHECK( std::fabs( rank[ 2 ] - expectedCaller ) <= kShippedBand );
        CHECK( std::fabs( rank[ 3 ] - expectedHub ) <= kShippedBand );
        CHECK( rank[ 0 ] == rank[ 1 ] );
        CHECK( rank[ 1 ] == rank[ 2 ] );
        checkKernelInvariants( rank );
    }

    // Precise config: 68 iterations
    {
        std::vector<double> rank( 4, 0.0 );
        const rw::PageRankConfig preciseConfig{ .alpha = alpha, .tolerance = 1e-13, .maxIterationCount = 400 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, preciseConfig );
        CHECK( run.iterationCount == 68 );
        CHECK( run.hasConverged );
        CHECK( std::fabs( rank[ 0 ] - expectedCaller ) <= kPreciseBand );
        CHECK( std::fabs( rank[ 1 ] - expectedCaller ) <= kPreciseBand );
        CHECK( std::fabs( rank[ 2 ] - expectedCaller ) <= kPreciseBand );
        CHECK( std::fabs( rank[ 3 ] - expectedHub ) <= kPreciseBand );
        checkKernelInvariants( rank );
    }

    // Stable sort order across three runs
    {
        const rw::PageRankConfig shippedConfig{ .alpha = alpha, .tolerance = 1e-6, .maxIterationCount = 100 };
        const std::array<std::uint32_t, 4> expectedOrder{ 3, 0, 1, 2 };
        std::vector<std::uint32_t> initialOrder;
        for( unsigned runIndex = 0; runIndex < 3; ++runIndex )
        {
            std::vector<double> rank( 4, 0.0 );
            rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, shippedConfig );
            const std::vector<std::uint32_t> order = topOrder( rank );
            CHECK( std::equal( order.begin(), order.end(), expectedOrder.begin() ) );
            if( runIndex == 0 )
            {
                initialOrder = order;
            }
            else
            {
                CHECK( order == initialOrder );
            }
        }
    }
}

TEST_CASE( "K7: weighted fan-out produces closed-form scores and order {2, 1, 0}" )
{
    const std::array<std::uint32_t, 4> rowOffsets{ 0, 0, 1, 2 };
    const std::array<std::uint32_t, 2> columnIndices{ 0, 0 };
    const std::array<float, 2> values{ 1.0f, 3.0f };
    const sparseCsr<float> csr = buildCsr( 3, rowOffsets, columnIndices, values );
    const std::array<double, 3> weightedOutDegree{ 4.0, 0.0, 0.0 };
    const std::array<double, 3> teleport{ 1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0 };

    const double alpha = kShippedAlpha;
    const double c = 1.0 / ( 3.0 + alpha );
    const double expected0 = c;
    const double expected1 = ( 1.0 + alpha / 4.0 ) * c;
    const double expected2 = ( 1.0 + 3.0 * alpha / 4.0 ) * c;

    // Shipped config: 11 iterations, order { 2, 1, 0 }
    {
        std::vector<double> rank( 3, 0.0 );
        const rw::PageRankConfig shippedConfig{ .alpha = alpha, .tolerance = 1e-6, .maxIterationCount = 100 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, shippedConfig );
        CHECK( run.iterationCount == 11 );
        CHECK( run.hasConverged );
        CHECK( std::fabs( rank[ 0 ] - expected0 ) <= kShippedBand );
        CHECK( std::fabs( rank[ 1 ] - expected1 ) <= kShippedBand );
        CHECK( std::fabs( rank[ 2 ] - expected2 ) <= kShippedBand );
        const std::vector<std::uint32_t> order = topOrder( rank );
        const std::array<std::uint32_t, 3> expectedOrder{ 2, 1, 0 };
        CHECK( std::equal( order.begin(), order.end(), expectedOrder.begin() ) );
        checkKernelInvariants( rank );
    }

    // Precise config: 24 iterations
    {
        std::vector<double> rank( 3, 0.0 );
        const rw::PageRankConfig preciseConfig{ .alpha = alpha, .tolerance = 1e-13, .maxIterationCount = 400 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, preciseConfig );
        CHECK( run.iterationCount == 24 );
        CHECK( run.hasConverged );
        CHECK( std::fabs( rank[ 0 ] - expected0 ) <= kPreciseBand );
        CHECK( std::fabs( rank[ 1 ] - expected1 ) <= kPreciseBand );
        CHECK( std::fabs( rank[ 2 ] - expected2 ) <= kPreciseBand );
        checkKernelInvariants( rank );
    }
}

TEST_CASE( "K8: fractional edge weights match closed-form scores" )
{
    const std::array<std::uint32_t, 4> rowOffsets{ 0, 0, 1, 2 };
    const std::array<std::uint32_t, 2> columnIndices{ 0, 0 };
    const std::array<float, 2> values{ 0.1f, 0.2f };
    const sparseCsr<float> csr = buildCsr( 3, rowOffsets, columnIndices, values );
    const std::array<double, 3> weightedOutDegree{ double( values[ 0 ] ) + double( values[ 1 ] ), 0.0, 0.0 };
    const std::array<double, 3> teleport{ 1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0 };

    const double alpha = kShippedAlpha;
    const double w1 = double( values[ 0 ] );
    const double w2 = double( values[ 1 ] );
    const double c = 1.0 / ( 3.0 + alpha );
    const double expected0 = c;
    const double expected1 = ( 1.0 + alpha * ( w1 / ( w1 + w2 ) ) ) * c;
    const double expected2 = ( 1.0 + alpha * ( w2 / ( w1 + w2 ) ) ) * c;

    // Shipped config: 11 iterations
    {
        std::vector<double> rank( 3, 0.0 );
        const rw::PageRankConfig shippedConfig{ .alpha = alpha, .tolerance = 1e-6, .maxIterationCount = 100 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, shippedConfig );
        CHECK( run.iterationCount == 11 );
        CHECK( run.hasConverged );
        CHECK( std::fabs( rank[ 0 ] - expected0 ) <= kShippedBand );
        CHECK( std::fabs( rank[ 1 ] - expected1 ) <= kShippedBand );
        CHECK( std::fabs( rank[ 2 ] - expected2 ) <= kShippedBand );
        checkKernelInvariants( rank );
    }

    // Precise config: 24 iterations
    {
        std::vector<double> rank( 3, 0.0 );
        const rw::PageRankConfig preciseConfig{ .alpha = alpha, .tolerance = 1e-13, .maxIterationCount = 400 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, preciseConfig );
        CHECK( run.iterationCount == 24 );
        CHECK( run.hasConverged );
        CHECK( std::fabs( rank[ 0 ] - expected0 ) <= kPreciseBand );
        CHECK( std::fabs( rank[ 1 ] - expected1 ) <= kPreciseBand );
        CHECK( std::fabs( rank[ 2 ] - expected2 ) <= kPreciseBand );
        checkKernelInvariants( rank );
    }
}

TEST_CASE( "K9: personalization propagates rank to zero-teleport descendants" )
{
    const std::array<std::uint32_t, 4> rowOffsets{ 0, 0, 1, 2 };
    const std::array<std::uint32_t, 2> columnIndices{ 0, 1 };
    const std::array<float, 2> values{ 1.0f, 1.0f };
    const sparseCsr<float> csr = buildCsr( 3, rowOffsets, columnIndices, values );
    const std::array<double, 3> weightedOutDegree{ 1.0, 1.0, 0.0 };
    const std::array<double, 3> teleport{ 1.0, 0.0, 0.0 };

    const double alpha = kShippedAlpha;
    const double expected0 = 1.0 / ( 1.0 + alpha + alpha * alpha );
    const double expected1 = alpha * expected0;
    const double expected2 = alpha * alpha * expected0;

    // Shipped config: 90 iterations
    {
        std::vector<double> rank( 3, 0.0 );
        const rw::PageRankConfig shippedConfig{ .alpha = alpha, .tolerance = 1e-6, .maxIterationCount = 100 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, shippedConfig );
        CHECK( run.iterationCount == 90 );
        CHECK( run.hasConverged );
        CHECK( std::fabs( rank[ 0 ] - expected0 ) <= kShippedBand );
        CHECK( std::fabs( rank[ 1 ] - expected1 ) <= kShippedBand );
        CHECK( std::fabs( rank[ 2 ] - expected2 ) <= kShippedBand );
        CHECK( rank[ 1 ] > 0.0 );
        CHECK( rank[ 2 ] > 0.0 );
        checkKernelInvariants( rank );
    }

    // Precise config: 189 iterations
    {
        std::vector<double> rank( 3, 0.0 );
        const rw::PageRankConfig preciseConfig{ .alpha = alpha, .tolerance = 1e-13, .maxIterationCount = 400 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, preciseConfig );
        CHECK( run.iterationCount == 189 );
        CHECK( run.hasConverged );
        CHECK( std::fabs( rank[ 0 ] - expected0 ) <= kPreciseBand );
        CHECK( std::fabs( rank[ 1 ] - expected1 ) <= kPreciseBand );
        CHECK( std::fabs( rank[ 2 ] - expected2 ) <= kPreciseBand );
        checkKernelInvariants( rank );
    }
}

TEST_CASE( "K10: node outside teleport support produces exactly [0.0, 1.0]" )
{
    const std::array<std::uint32_t, 3> rowOffsets{ 0, 0, 1 };
    const std::array<std::uint32_t, 1> columnIndices{ 0 };
    const std::array<float, 1> values{ 1.0f };
    const sparseCsr<float> csr = buildCsr( 2, rowOffsets, columnIndices, values );
    const std::array<double, 2> weightedOutDegree{ 1.0, 0.0 };
    const std::array<double, 2> teleport{ 0.0, 1.0 };
    std::vector<double> rank( 2, 0.0 );
    const rw::PageRankConfig shippedConfig{ .alpha = kShippedAlpha, .tolerance = 1e-6, .maxIterationCount = 100 };

    const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, shippedConfig );
    CHECK( run.iterationCount == 1 );
    CHECK( run.hasConverged );
    CHECK( rank[ 0 ] == 0.0 );
    CHECK( rank[ 1 ] == 1.0 );
    checkKernelInvariants( rank );
}

TEST_CASE( "K11: alpha = 0 returns teleport distribution exactly" )
{
    const std::array<std::uint32_t, 3> rowOffsets{ 0, 0, 1 };
    const std::array<std::uint32_t, 1> columnIndices{ 0 };
    const std::array<float, 1> values{ 1.0f };
    const sparseCsr<float> csr = buildCsr( 2, rowOffsets, columnIndices, values );
    const std::array<double, 2> weightedOutDegree{ 1.0, 0.0 };
    const std::array<double, 2> teleport{ 0.25, 0.75 };
    std::vector<double> rank( 2, 0.0 );
    const rw::PageRankConfig zeroAlphaConfig{ .alpha = 0.0, .tolerance = 1e-6, .maxIterationCount = 100 };

    const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, zeroAlphaConfig );
    CHECK( run.iterationCount == 1 );
    CHECK( run.hasConverged );
    CHECK( rank[ 0 ] == 0.25 );
    CHECK( rank[ 1 ] == 0.75 );
    checkKernelInvariants( rank );
}

TEST_CASE( "K12: worst-case cycle 0<->1 reaches 90 iterations with closed-form iterate values" )
{
    const std::array<std::uint32_t, 3> rowOffsets{ 0, 1, 2 };
    const std::array<std::uint32_t, 2> columnIndices{ 1, 0 };
    const std::array<float, 2> values{ 1.0f, 1.0f };
    const sparseCsr<float> csr = buildCsr( 2, rowOffsets, columnIndices, values );
    const std::array<double, 2> weightedOutDegree{ 1.0, 1.0 };
    const std::array<double, 2> teleport{ 1.0, 0.0 };

    const double alpha = kShippedAlpha;
    const double expectedX90_0 = 0.54054073772537781;
    const double expectedX89_0 = 0.54054029339663212;

    // Shipped config: exactly 90 iterations
    {
        std::vector<double> rank( 2, 0.0 );
        const rw::PageRankConfig shippedConfig{ .alpha = alpha, .tolerance = 1e-6, .maxIterationCount = 100 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, shippedConfig );
        CHECK( run.iterationCount == 90 );
        CHECK( run.hasConverged );
        CHECK( std::fabs( rank[ 0 ] - expectedX90_0 ) <= 1e-14 );
        CHECK( std::fabs( rank[ 1 ] - ( 1.0 - rank[ 0 ] ) ) <= 1e-14 );
        checkKernelInvariants( rank );
    }

    // Max iteration count = 90: converges on the last allowed iteration
    {
        std::vector<double> rank( 2, 0.0 );
        const rw::PageRankConfig cap90Config{ .alpha = alpha, .tolerance = 1e-6, .maxIterationCount = 90 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, cap90Config );
        CHECK( run.iterationCount == 90 );
        CHECK( run.hasConverged );
        CHECK( std::fabs( rank[ 0 ] - expectedX90_0 ) <= 1e-14 );
        checkKernelInvariants( rank );
    }

    // Max iteration count = 89: truncated run
    {
        std::vector<double> rank( 2, 0.0 );
        const rw::PageRankConfig cap89Config{ .alpha = alpha, .tolerance = 1e-6, .maxIterationCount = 89 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, cap89Config );
        CHECK( run.iterationCount == 89 );
        CHECK( !run.hasConverged );
        CHECK( std::fabs( rank[ 0 ] - expectedX89_0 ) <= 1e-14 );
        checkKernelInvariants( rank );
    }

    // Precise config: 189 iterations
    {
        std::vector<double> rank( 2, 0.0 );
        const rw::PageRankConfig preciseConfig{ .alpha = alpha, .tolerance = 1e-13, .maxIterationCount = 400 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, preciseConfig );
        CHECK( run.iterationCount == 189 );
        CHECK( run.hasConverged );
        checkKernelInvariants( rank );
    }
}

TEST_CASE( "K13: legal configuration non-convergence returns {100, false}" )
{
    const std::array<std::uint32_t, 3> rowOffsets{ 0, 1, 2 };
    const std::array<std::uint32_t, 2> columnIndices{ 1, 0 };
    const std::array<float, 2> values{ 1.0f, 1.0f };
    const sparseCsr<float> csr = buildCsr( 2, rowOffsets, columnIndices, values );
    const std::array<double, 2> weightedOutDegree{ 1.0, 1.0 };
    const std::array<double, 2> teleport{ 1.0, 0.0 };

    const rw::PageRankConfig nonConvergeConfig{ .alpha = 0.9, .tolerance = 1e-6, .maxIterationCount = 100 };
    std::vector<double> rank( 2, 0.0 );
    const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, nonConvergeConfig );

    CHECK( run.iterationCount == 100 );
    CHECK( !run.hasConverged );
    const double expectedX100_0 = 0.52632837118894671;
    CHECK( std::fabs( rank[ 0 ] - expectedX100_0 ) <= 1e-14 );
    CHECK( std::fabs( rank[ 0 ] - 10.0 / 19.0 ) > 1e-5 );
    checkKernelInvariants( rank );
}

TEST_CASE( "K14: truncated runs return exact intermediate iterates" )
{
    const std::array<std::uint32_t, 3> rowOffsets{ 0, 0, 1 };
    const std::array<std::uint32_t, 1> columnIndices{ 0 };
    const std::array<float, 1> values{ 1.0f };
    const sparseCsr<float> csr = buildCsr( 2, rowOffsets, columnIndices, values );
    const std::array<double, 2> weightedOutDegree{ 1.0, 0.0 };
    const std::array<double, 2> teleport{ 0.5, 0.5 };

    const double alpha = kShippedAlpha;

    // Max 1 iteration
    {
        std::vector<double> rank( 2, 0.0 );
        const rw::PageRankConfig cap1Config{ .alpha = alpha, .tolerance = 1e-6, .maxIterationCount = 1 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, cap1Config );
        CHECK( run.iterationCount == 1 );
        CHECK( !run.hasConverged );
        CHECK( rank[ 0 ] == ( 0.5 - alpha / 4.0 ) );
        CHECK( rank[ 1 ] == ( 0.5 + alpha / 4.0 ) );
        checkKernelInvariants( rank );
    }

    // Max 2 iterations
    {
        std::vector<double> rank( 2, 0.0 );
        const rw::PageRankConfig cap2Config{ .alpha = alpha, .tolerance = 1e-6, .maxIterationCount = 2 };
        const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rank, cap2Config );
        CHECK( run.iterationCount == 2 );
        CHECK( !run.hasConverged );
        const double expected0 = 0.5 - alpha / 4.0 + ( alpha * alpha ) / 8.0;
        CHECK( std::fabs( rank[ 0 ] - expected0 ) <= 1e-15 );
        checkKernelInvariants( rank );
    }
}

TEST_CASE( "K15: reduction block seam is correct across sizes 1023, 1024, 1025, 2049" )
{
    const double alpha = kShippedAlpha;
    const rw::PageRankConfig shippedConfig{ .alpha = alpha, .tolerance = 1e-6, .maxIterationCount = 100 };

    for( const std::size_t nodeCount : { std::size_t( 1023 ), std::size_t( 1024 ), std::size_t( 1025 ), std::size_t( 2049 ) } )
    {
        const double N = double( nodeCount );
        const double c = 1.0 / ( N + ( N - 1.0 ) * alpha );
        const double hubExpected = c * ( 1.0 + ( N - 1.0 ) * alpha );

        // 1. Hub at ID N - 1 (callers 0..N-2)
        std::vector<double> rankHubLast( nodeCount, 0.0 );
        {
            sparseCsr<float> csr( nodeCount, nodeCount, nodeCount - 1 );
            for( std::size_t rowIndex = 0; rowIndex < nodeCount; ++rowIndex )
            {
                csr.rowOffsets()[ rowIndex ] = 0;
            }
            csr.rowOffsets()[ nodeCount ] = std::uint32_t( nodeCount - 1 );
            for( std::uint32_t edgeIndex = 0; edgeIndex < std::uint32_t( nodeCount - 1 ); ++edgeIndex )
            {
                csr.colIndices()[ edgeIndex ] = edgeIndex;
                csr.values()[ edgeIndex ] = 1.0f;
            }

            std::vector<double> weightedOutDegree( nodeCount, 1.0 );
            weightedOutDegree[ nodeCount - 1 ] = 0.0;
            const std::vector<double> teleport( nodeCount, 1.0 / N );

            const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rankHubLast, shippedConfig );
            CHECK( run.hasConverged );
            if( nodeCount <= 1025 )
            {
                CHECK( run.iterationCount == 89 );
            }
            else
            {
                CHECK( run.iterationCount <= 90 );
            }

            CHECK( std::fabs( rankHubLast[ nodeCount - 1 ] - hubExpected ) <= 1e-5 );
            for( std::size_t callerIndex = 0; callerIndex < nodeCount - 1; ++callerIndex )
            {
                CHECK( std::fabs( rankHubLast[ callerIndex ] - c ) <= 1e-5 );
                CHECK( rankHubLast[ callerIndex ] == rankHubLast[ 0 ] );
            }
            checkKernelInvariants( rankHubLast );
        }

        // 2. Hub at ID 0 (callers 1..N-1)
        std::vector<double> rankHubFirst( nodeCount, 0.0 );
        {
            sparseCsr<float> csr( nodeCount, nodeCount, nodeCount - 1 );
            csr.rowOffsets()[ 0 ] = 0;
            for( std::size_t rowIndex = 1; rowIndex <= nodeCount; ++rowIndex )
            {
                csr.rowOffsets()[ rowIndex ] = std::uint32_t( nodeCount - 1 );
            }
            for( std::uint32_t edgeIndex = 0; edgeIndex < std::uint32_t( nodeCount - 1 ); ++edgeIndex )
            {
                csr.colIndices()[ edgeIndex ] = edgeIndex + 1u;
                csr.values()[ edgeIndex ] = 1.0f;
            }

            std::vector<double> weightedOutDegree( nodeCount, 1.0 );
            weightedOutDegree[ 0 ] = 0.0;
            const std::vector<double> teleport( nodeCount, 1.0 / N );

            const rw::PageRankRun run = rw::pageRankDouble( csr, weightedOutDegree, teleport, rankHubFirst, shippedConfig );
            CHECK( run.hasConverged );
            if( nodeCount <= 1025 )
            {
                CHECK( run.iterationCount == 89 );
            }
            else
            {
                CHECK( run.iterationCount <= 90 );
            }

            CHECK( std::fabs( rankHubFirst[ 0 ] - hubExpected ) <= 1e-5 );
            for( std::size_t callerIndex = 1; callerIndex < nodeCount; ++callerIndex )
            {
                CHECK( std::fabs( rankHubFirst[ callerIndex ] - c ) <= 1e-5 );
                CHECK( rankHubFirst[ callerIndex ] == rankHubFirst[ 1 ] );
            }
            checkKernelInvariants( rankHubFirst );

            // Hub-last and hub-first agree within 1e-15 per score
            CHECK( std::fabs( rankHubLast[ nodeCount - 1 ] - rankHubFirst[ 0 ] ) <= 1e-15 );
            CHECK( std::fabs( rankHubLast[ 0 ] - rankHubFirst[ 1 ] ) <= 1e-15 );
        }
    }
}

TEST_CASE( "K16: pre-filled NaN buffers verify clean writes and input constness" )
{
    const std::array<std::uint32_t, 4> rowOffsets{ 0, 0, 1, 2 };
    const std::array<std::uint32_t, 2> columnIndices{ 0, 0 };
    const std::array<float, 2> values{ 1.0f, 3.0f };
    const sparseCsr<float> csr = buildCsr( 3, rowOffsets, columnIndices, values );
    const std::array<double, 3> weightedOutDegree{ 4.0, 0.0, 0.0 };
    const std::array<double, 3> teleport{ 1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0 };
    const rw::PageRankConfig shippedConfig{ .alpha = kShippedAlpha, .tolerance = 1e-6, .maxIterationCount = 100 };

    // Baseline run
    std::vector<double> rankBase( 3, 0.0 );
    rw::pageRankDouble( csr, weightedOutDegree, teleport, rankBase, shippedConfig );

    // NaN prefilled run 1
    std::vector<double> rankNan1( 3, std::numeric_limits<double>::quiet_NaN() );
    rw::pageRankDouble( csr, weightedOutDegree, teleport, rankNan1, shippedConfig );

    // NaN prefilled run 2
    std::vector<double> rankNan2( 3, std::numeric_limits<double>::quiet_NaN() );
    rw::pageRankDouble( csr, weightedOutDegree, teleport, rankNan2, shippedConfig );

    CHECK( std::memcmp( rankNan1.data(), rankNan2.data(), 3 * sizeof( double ) ) == 0 );
    CHECK( std::memcmp( rankNan1.data(), rankBase.data(), 3 * sizeof( double ) ) == 0 );
}

TEST_CASE( "K17: defaults for PageRankConfig and PageRankRun" )
{
    const rw::PageRankConfig config{};
    CHECK( config.alpha == 0.85 );
    CHECK( config.tolerance == 1e-6 );
    CHECK( config.maxIterationCount == 100 );

    const rw::PageRankRun run{};
    CHECK( run.iterationCount == 0 );
    CHECK( run.hasConverged );
}

// ------------------------------------------------------------------------------------------------
// B1-B3: biasPrior wrappers (prompts/help-wanted/graph-unit-tests.md)
// ------------------------------------------------------------------------------------------------

TEST_CASE( "B1: biasPrior renormalizes exact float products to unit sum" )
{
    rw::Graph graph;
    graph.priorWeight = { 1.0f, 1.0f, 0.5f, 0.0f };
    const std::vector<float> prior{ 0.25f, 0.25f, 0.25f, 0.25f };
    const std::vector<float> biased = rw::biasPrior( graph, prior );

    const std::vector<float> expected{ 0.4f, 0.4f, 0.2f, 0.0f };
    REQUIRE( biased.size() == 4 );
    CHECK( biased[ 0 ] == expected[ 0 ] );
    CHECK( biased[ 1 ] == expected[ 1 ] );
    CHECK( biased[ 2 ] == expected[ 2 ] );
    CHECK( biased[ 3 ] == expected[ 3 ] );
}

TEST_CASE( "B2: biasPrior size mismatch returns prior bit for bit" )
{
    rw::Graph graph;
    graph.priorWeight = { 1.0f, 1.0f, 1.0f };
    const std::vector<float> prior{ 0.25f, 0.25f, 0.25f, 0.25f };
    const std::vector<float> biased = rw::biasPrior( graph, prior );

    REQUIRE( biased.size() == 4 );
    CHECK( std::memcmp( biased.data(), prior.data(), 4 * sizeof( float ) ) == 0 );
}

TEST_CASE( "B3: biasPrior non-positive sum returns prior bit for bit" )
{
    rw::Graph graph;
    graph.priorWeight = { 0.0f, 0.0f };
    const std::vector<float> prior{ 0.5f, 0.5f };
    const std::vector<float> biased = rw::biasPrior( graph, prior );

    REQUIRE( biased.size() == 2 );
    CHECK( std::memcmp( biased.data(), prior.data(), 2 * sizeof( float ) ) == 0 );
}

// ------------------------------------------------------------------------------------------------
// R1-R5: Rank wrappers (prompts/help-wanted/graph-unit-tests.md)
// ------------------------------------------------------------------------------------------------

TEST_CASE( "R1: rankGraphTeleport matches kernel output narrowed to float" )
{
    rw::Graph graph;
    const std::array<std::uint32_t, 3> rowOffsets{ 0, 0, 1 };
    const std::array<std::uint32_t, 1> columnIndices{ 0 };
    const std::array<float, 1> values{ 1.0f };
    graph.inEdges = buildCsr( 2, rowOffsets, columnIndices, values );
    graph.wOutDeg = { 1.0, 0.0 };
    graph.priorWeight = { 1.0f, 1.0f };

    const rw::RankedGraph ranked = rw::rankGraphTeleport( graph, { 0.5f, 0.5f } );
    CHECK( ranked.iterationCount == 17 );
    CHECK( ranked.hasConverged );

    std::vector<double> kernelRank( 2, 0.0 );
    const rw::PageRankConfig shippedConfig{ .alpha = kShippedAlpha, .tolerance = 1e-6, .maxIterationCount = 100 };
    rw::pageRankDouble( graph.inEdges, graph.wOutDeg, { 0.5, 0.5 }, kernelRank, shippedConfig );

    REQUIRE( ranked.rank.size() == 2 );
    CHECK( ranked.rank[ 0 ] == float( kernelRank[ 0 ] ) );
    CHECK( ranked.rank[ 1 ] == float( kernelRank[ 1 ] ) );
}

TEST_CASE( "R2: takeRank sets isPageRank true and transfers rank vector" )
{
    rw::Graph graph;
    const std::array<std::uint32_t, 3> rowOffsets{ 0, 0, 1 };
    const std::array<std::uint32_t, 1> columnIndices{ 0 };
    const std::array<float, 1> values{ 1.0f };
    graph.inEdges = buildCsr( 2, rowOffsets, columnIndices, values );
    graph.wOutDeg = { 1.0, 0.0 };
    graph.priorWeight = { 1.0f, 1.0f };

    rw::RankDisclosure disclosure;
    const std::vector<float> rank = rw::takeRank( rw::rankGraphTeleport( graph, { 0.5f, 0.5f } ), disclosure );

    CHECK( rank.size() == 2 );
    CHECK( disclosure.iterationCount == 17 );
    CHECK( disclosure.hasConverged );
    CHECK( disclosure.isPageRank );
}

TEST_CASE( "R3: rankGraphTeleport with asymmetric prior weights biases teleport vector" )
{
    rw::Graph graph;
    const std::array<std::uint32_t, 3> rowOffsets{ 0, 0, 1 };
    const std::array<std::uint32_t, 1> columnIndices{ 0 };
    const std::array<float, 1> values{ 1.0f };
    graph.inEdges = buildCsr( 2, rowOffsets, columnIndices, values );
    graph.wOutDeg = { 1.0, 0.0 };
    graph.priorWeight = { 3.0f, 1.0f };

    const rw::RankedGraph ranked = rw::rankGraphTeleport( graph, { 0.5f, 0.5f } );
    CHECK( ranked.iterationCount == 17 );
    CHECK( ranked.hasConverged );

    // Teleport { 0.5, 0.5 } with weights { 3, 1 } becomes { 0.75, 0.25 }
    std::vector<double> kernelRank( 2, 0.0 );
    const rw::PageRankConfig shippedConfig{ .alpha = kShippedAlpha, .tolerance = 1e-6, .maxIterationCount = 100 };
    rw::pageRankDouble( graph.inEdges, graph.wOutDeg, { 0.75, 0.25 }, kernelRank, shippedConfig );

    REQUIRE( ranked.rank.size() == 2 );
    CHECK( ranked.rank[ 0 ] == float( kernelRank[ 0 ] ) );
    CHECK( ranked.rank[ 1 ] == float( kernelRank[ 1 ] ) );
}

TEST_CASE( "R4: rankGraph on empty graph produces empty rank and {0, true}" )
{
    const rw::Graph emptyGraph;
    const rw::RankedGraph ranked = rw::rankGraph( emptyGraph );
    CHECK( ranked.rank.empty() );
    CHECK( ranked.iterationCount == 0 );
    CHECK( ranked.hasConverged );
}

TEST_CASE( "R5: rankGraph on star graph preserves ordering {3, 0, 1, 2} across 3 runs" )
{
    rw::Graph graph;
    const std::array<std::uint32_t, 5> rowOffsets{ 0, 0, 0, 0, 3 };
    const std::array<std::uint32_t, 3> columnIndices{ 0, 1, 2 };
    const std::array<float, 3> values{ 1.0f, 1.0f, 1.0f };
    graph.inEdges = buildCsr( 4, rowOffsets, columnIndices, values );
    graph.wOutDeg = { 1.0, 1.0, 1.0, 0.0 };
    graph.priorWeight = { 1.0f, 1.0f, 1.0f, 1.0f };

    const std::array<std::uint32_t, 4> expectedOrder{ 3, 0, 1, 2 };
    for( unsigned runIndex = 0; runIndex < 3; ++runIndex )
    {
        const rw::RankedGraph ranked = rw::rankGraph( graph );
        CHECK( ranked.hasConverged );

        std::vector<std::uint32_t> order( 4 );
        std::iota( order.begin(), order.end(), 0u );
        std::sort( order.begin(), order.end(), [ &ranked ]( std::uint32_t a, std::uint32_t b )
                   {
                       if( ranked.rank[ a ] != ranked.rank[ b ] )
                       {
                           return ranked.rank[ a ] > ranked.rank[ b ];
                       }
                       return a < b;
                   } );
        CHECK( std::equal( order.begin(), order.end(), expectedOrder.begin() ) );
    }
}

