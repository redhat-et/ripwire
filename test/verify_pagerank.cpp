#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "pagerank.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <numeric>
#include <span>
#include <vector>

namespace
{

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
            return false;
        mass += value;
    }
    return std::fabs( mass - 1.0 ) <= 1e-9;
}

std::vector<std::uint32_t> topOrder( std::span<const double> rank )
{
    std::vector<std::uint32_t> order( rank.size() );
    std::iota( order.begin(), order.end(), 0u );
    std::sort( order.begin(), order.end(), [ rank ]( std::uint32_t a, std::uint32_t b )
    {
        if( rank[ a ] != rank[ b ] )
            return rank[ a ] > rank[ b ];
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
        const unsigned iterationCount = rw::pageRankDouble( csr, {}, {}, rank, preciseConfig );
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
            CHECK_MESSAGE( std::fabs( rank[ nodeIndex ] - teleport[ nodeIndex ] ) <= 1e-12,
                           "all-dangling PageRank differs from teleport distribution" );
    }

    // Fractional edge weights use a double out-degree accumulated from the same promoted float edges.
    // This catches probability-mass drift from dividing by a separately rounded float denominator.
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

    // Three callers point to one dangling hub. Top-K must remain hub, then tied callers by node id across repeated runs.
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
                firstOrder = order;
            else
                CHECK_MESSAGE( order == firstOrder, "PageRank top-K order changed between identical runs" );
        }
    }
}
