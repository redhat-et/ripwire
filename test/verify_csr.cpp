#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "csrverify.h"
#include "graph.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <utility>
#include <vector>

namespace
{

using Edge = std::pair<std::uint32_t, float>;
using Adjacency = std::vector<std::vector<Edge>>;

sparseCsr<float> buildCsr( const Adjacency& adjacency )
{
    const std::size_t nodeCount = adjacency.size();
    std::size_t edgeCount = 0;
    for( const auto& row : adjacency )
    {
        edgeCount += row.size();
    }

    sparseCsr<float> csr( nodeCount, nodeCount, edgeCount );
    std::uint32_t* rowOffsets = csr.rowOffsets();
    std::uint32_t* columnIndices = csr.colIndices();
    float* values = csr.values();

    rowOffsets[0] = 0;
    std::size_t edgeIndex = 0;
    for( std::size_t rowIndex = 0; rowIndex < nodeCount; ++rowIndex )
    {
        for( const auto& [ columnIndex, value ] : adjacency[ rowIndex ] )
        {
            columnIndices[ edgeIndex ] = columnIndex;
            values[ edgeIndex ] = value;
            ++edgeIndex;
        }
        rowOffsets[ rowIndex + 1 ] = std::uint32_t( edgeIndex );
    }
    return csr;
}

Adjacency generateAdjacency( std::size_t nodeCount )
{
    Adjacency adjacency( nodeCount );
    if( nodeCount == 0 )
    {
        return adjacency;
    }

    std::uint32_t state = 0x9e3779b9u ^ std::uint32_t( nodeCount );
    const std::size_t edgeCountPerRow = std::min<std::size_t>( nodeCount, 7 );
    for( std::size_t rowIndex = 0; rowIndex < nodeCount; ++rowIndex )
    {
        auto& row = adjacency[ rowIndex ];
        row.reserve( edgeCountPerRow );
        for( std::size_t edgeIndex = 0; edgeIndex < edgeCountPerRow; ++edgeIndex )
        {
            const std::uint64_t nextState = std::uint64_t( state ) * 1664525u + 1013904223u;
            state = std::uint32_t( nextState & 0xFFFFFFFFu );
            const std::uint32_t columnIndex = std::uint32_t( std::uint64_t( state ) % nodeCount );
            const float value = 0.25f * float( 1u + ( state & 7u ) );
            row.emplace_back( columnIndex, value );
        }
    }
    return adjacency;
}

bool roundTrips( const sparseCsr<float>& csr, const Adjacency& expected )
{
    if( csr.rows() != expected.size() )
    {
        return false;
    }

    const std::uint32_t* rowOffsets = csr.rowOffsets();
    const std::uint32_t* columnIndices = csr.colIndices();
    const float* values = csr.values();
    for( std::size_t rowIndex = 0; rowIndex < expected.size(); ++rowIndex )
    {
        const auto& row = expected[ rowIndex ];
        if( std::size_t( rowOffsets[ rowIndex + 1 ] - rowOffsets[ rowIndex ] ) != row.size() )
        {
            return false;
        }

        for( std::size_t localEdgeIndex = 0; localEdgeIndex < row.size(); ++localEdgeIndex )
        {
            const std::size_t edgeIndex = rowOffsets[ rowIndex ] + localEdgeIndex;
            if( columnIndices[edgeIndex] != row[localEdgeIndex].first || std::fabs( values[edgeIndex] - row[localEdgeIndex].second ) > 1e-7f )
            {
                return false;
            }
        }
    }
    return true;
}

}

TEST_CASE( "CSR structural properties and adjacency round-trip" )
{
    // Required random sparse sizes plus adjacency-list round-trip.
    for( const std::size_t nodeCount : { std::size_t( 0 ), std::size_t( 1 ), std::size_t( 2 ), std::size_t( 100 ), std::size_t( 10000 ) } )
    {
        const Adjacency adjacency = generateAdjacency( nodeCount );
        const sparseCsr<float> csr = buildCsr( adjacency );
        CHECK_MESSAGE( rw::verifyCsr( csr, nodeCount ), "generated CSR failed structural verification" );
        CHECK_MESSAGE( roundTrips( csr, adjacency ), "generated CSR failed adjacency round-trip" );
    }

    // A row count beyond uint16 capacity catches implicit 16-bit edge-count truncation.
    {
        constexpr std::size_t kStressEdgeCount = 70001;
        Adjacency adjacency( 2 );
        adjacency[ 0 ].reserve( kStressEdgeCount );
        for( std::size_t edgeIndex = 0; edgeIndex < kStressEdgeCount; ++edgeIndex )
        {
            adjacency[ 0 ].emplace_back( std::uint32_t( edgeIndex & 1u ), 1.f );
        }
        const sparseCsr<float> csr = buildCsr( adjacency );
        CHECK_MESSAGE( csr.nnz() == kStressEdgeCount, "CSR edge count truncated above uint16 range" );
        CHECK_MESSAGE( rw::verifyCsr( csr, adjacency.size() ), "large CSR failed structural verification" );
        CHECK_MESSAGE( roundTrips( csr, adjacency ), "large CSR failed adjacency round-trip" );
    }

    // Invalid values must be rejected by the reusable production verifier.
    {
        sparseCsr<float> csr( 1, 1, 1 );
        csr.rowOffsets()[0] = 0;
        csr.rowOffsets()[1] = 1;
        csr.colIndices()[0] = 0;
        csr.values()[0] = -1.f;
        CHECK_MESSAGE( !rw::verifyCsr( csr, 1 ), "negative CSR value was accepted" );
        csr.values()[0] = std::numeric_limits<float>::quiet_NaN();
        CHECK_MESSAGE( !rw::verifyCsr( csr, 1 ), "non-finite CSR value was accepted" );
    }
}

TEST_CASE( "production buildGraph stores caller to callee as target-row source-column" )
{
    rw::IngestResult ingest;
    ingest.files.emplace_back( "orientation.cpp" );
    ingest.symbols.resize( 2 );
    ingest.symbols[ 0 ].id = 0;
    ingest.symbols[ 0 ].fileId = 0;
    ingest.symbols[ 0 ].lang = rw::Lang::Cpp;
    ingest.symbols[ 0 ].kind = rw::SymKind::Function;
    ingest.symbols[ 0 ].name = "caller";
    ingest.symbols[ 1 ].id = 1;
    ingest.symbols[ 1 ].fileId = 0;
    ingest.symbols[ 1 ].lang = rw::Lang::Cpp;
    ingest.symbols[ 1 ].kind = rw::SymKind::Function;
    ingest.symbols[ 1 ].name = "callee";

    rw::Reference reference;
    reference.fromSymbol = 0;
    reference.fileId = 0;
    reference.lang = rw::Lang::Cpp;
    reference.role = rw::RefRole::Call;
    reference.calleeName = "callee";
    ingest.references.push_back( std::move( reference ) );

    const rw::Graph graph = rw::buildGraph( ingest );
    REQUIRE( graph.inEdges.rows() == 2 );
    REQUIRE( graph.inEdges.nnz() == 1 );
    CHECK( graph.inEdges.rowOffsets()[ 0 ] == 0 );
    CHECK( graph.inEdges.rowOffsets()[ 1 ] == 0 );
    CHECK( graph.inEdges.rowOffsets()[ 2 ] == 1 );
    CHECK( graph.inEdges.colIndices()[ 0 ] == 0 );
    CHECK( graph.wOutDeg[ 0 ] == doctest::Approx( 1.0 ) );
    CHECK( graph.wOutDeg[ 1 ] == doctest::Approx( 0.0 ) );
}
