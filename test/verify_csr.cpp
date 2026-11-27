#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "infra/csrverify.h"
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

// ── buildGraph/4 as a UNIT, not through the whole function ─────────────────────────────────────────
// Before the decomposition (lane resolve-parallel, Series C) the flatten + CSR build was 144 lines
// inside a 4,043-line buildGraph whose production radius had NO indexed test: --impact=buildGraph
// reported radius_tested=0, with this file the single test in its radius. Reaching phase 4 meant
// running everything before it. Now flattenEdgesIntoCsr is a named function, these cases call it
// directly, and they can pin properties the whole-function path cannot reach cheaply: the edge
// WEIGHT formula and its cap, and the rule that the optional per-edge columns stay UNALLOCATED on a
// corpus that needs none.
namespace
{

// the minimum buildGraph has established before phase 4 runs: symbol count and the out-degree vector
// it accumulates into.
rw::IngestResult symbolsOnly( std::size_t count )
{
    rw::IngestResult ingest;
    ingest.files.emplace_back( "flatten.cpp" );
    ingest.symbols.resize( count );
    for( std::size_t i = 0; i < count; ++i )
    {
        ingest.symbols[ i ].id     = rw::NodeId( i );
        ingest.symbols[ i ].fileId = 0;
        ingest.symbols[ i ].lang   = rw::Lang::Cpp;
        ingest.symbols[ i ].kind   = rw::SymKind::Function;
        ingest.symbols[ i ].name   = "s" + std::to_string( i );
    }
    return ingest;
}

} // namespace

TEST_CASE( "buildGraph/4 flattens the accumulator into both CSRs, called directly" )
{
    const rw::IngestResult ingest = symbolsOnly( 3 );
    rw::Graph              graph;
    graph.wOutDeg.assign( 3, 0.0 );

    rw::HashMap<std::uint64_t, rw::EdgeAcc> acc;
    acc[ rw::hashutil::packPair( 0, 1 ) ] = rw::EdgeAcc{ .confSum = 1.0f, .nref = 1, .marks = 0 };
    acc[ rw::hashutil::packPair( 0, 2 ) ] = rw::EdgeAcc{ .confSum = 1.0f, .nref = 1, .marks = 0 };

    rw::flattenEdgesIntoCsr( graph, ingest, acc, /*scip=*/nullptr, /*anyImplSite=*/false );

    // out-edges: both of node 0's edges, offsets prefix-summed, ascending by target after the sort
    REQUIRE( graph.outOff.size() == 4 );
    CHECK( graph.outOff[ 0 ] == 0 );
    CHECK( graph.outOff[ 1 ] == 2 );
    CHECK( graph.outOff[ 3 ] == 2 );
    REQUIRE( graph.outTargets.size() == 2 );
    CHECK( graph.outTargets[ 0 ] == 1 );
    CHECK( graph.outTargets[ 1 ] == 2 );

    // in-edges mirror them: one row each for 1 and 2, both naming 0 as the source
    REQUIRE( graph.inEdges.rows() == 3 );
    REQUIRE( graph.inEdges.nnz() == 2 );
    CHECK( graph.inEdges.rowOffsets()[ 1 ] == 0 );
    CHECK( graph.inEdges.rowOffsets()[ 2 ] == 1 );
    CHECK( graph.inEdges.rowOffsets()[ 3 ] == 2 );
    CHECK( graph.inEdges.colIndices()[ 0 ] == 0 );
    CHECK( graph.inEdges.colIndices()[ 1 ] == 0 );

    // the accumulator is CONSUMED (G1c: released as soon as it is flattened)
    CHECK( acc.empty() );
}

TEST_CASE( "buildGraph/4 weights an edge by confidence times sqrt(refs), capped at 8" )
{
    const rw::IngestResult ingest = symbolsOnly( 2 );

    // confSum / nref * sqrt( nref ): four sites each contributing 1.0 → 1.0 * 2.0 = 2.0
    {
        rw::Graph graph;
        graph.wOutDeg.assign( 2, 0.0 );
        rw::HashMap<std::uint64_t, rw::EdgeAcc> acc;
        acc[ rw::hashutil::packPair( 0, 1 ) ] = rw::EdgeAcc{ .confSum = 4.0f, .nref = 4, .marks = 0 };
        rw::flattenEdgesIntoCsr( graph, ingest, acc, nullptr, false );
        REQUIRE( graph.outVals.size() == 1 );
        CHECK( graph.outVals[ 0 ] == doctest::Approx( 2.0 ) );
        CHECK( graph.wOutDeg[ 0 ] == doctest::Approx( 2.0 ) );
    }

    // the cap is a real cut, not a formula: 100 sites at full confidence would weigh 10, and must not
    {
        rw::Graph graph;
        graph.wOutDeg.assign( 2, 0.0 );
        rw::HashMap<std::uint64_t, rw::EdgeAcc> acc;
        acc[ rw::hashutil::packPair( 0, 1 ) ] = rw::EdgeAcc{ .confSum = 100.0f, .nref = 100, .marks = 0 };
        rw::flattenEdgesIntoCsr( graph, ingest, acc, nullptr, false );
        REQUIRE( graph.outVals.size() == 1 );
        CHECK( graph.outVals[ 0 ] == doctest::Approx( 8.0 ) );
    }
}

TEST_CASE( "buildGraph/4 leaves the optional per-edge columns unallocated when nothing needs them" )
{
    const rw::IngestResult ingest = symbolsOnly( 2 );

    // A corpus that resolves cleanly must keep outProv EMPTY, so serialize emits no prov= at all --
    // the zero-token-cost property test/golden.xml stands as proof of. An unmarked edge, no overlay
    // and no one-implementor dispatch is exactly that corpus.
    {
        rw::Graph graph;
        graph.wOutDeg.assign( 2, 0.0 );
        rw::HashMap<std::uint64_t, rw::EdgeAcc> acc;
        acc[ rw::hashutil::packPair( 0, 1 ) ] = rw::EdgeAcc{ .confSum = 1.0f, .nref = 1, .marks = 0 };
        rw::flattenEdgesIntoCsr( graph, ingest, acc, nullptr, /*anyImplSite=*/false );
        CHECK( graph.outProv.empty() );
        CHECK( graph.outAnchorMiss.empty() );
    }

    // ... and must allocate it the moment one site committed a one-implementor dispatch edge, which is
    // a fact only the caller knows, which is why phase 4 takes it as an argument rather than deriving it.
    {
        rw::Graph graph;
        graph.wOutDeg.assign( 2, 0.0 );
        rw::HashMap<std::uint64_t, rw::EdgeAcc> acc;
        acc[ rw::hashutil::packPair( 0, 1 ) ] = rw::EdgeAcc{ .confSum = 1.0f, .nref = 1, .marks = 0 };
        rw::flattenEdgesIntoCsr( graph, ingest, acc, nullptr, /*anyImplSite=*/true );
        REQUIRE( graph.outProv.size() == 1 );
    }
}
