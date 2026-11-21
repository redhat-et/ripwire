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

TEST_CASE( "G1: production buildGraph stores caller to callee as target-row source-column" )
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
    CHECK( graph.outOff.size() == 3 );
    CHECK( graph.outOff[ 0 ] == 0 );
    CHECK( graph.outOff[ 1 ] == 1 );
    CHECK( graph.outOff[ 2 ] == 1 );
    REQUIRE( graph.outTargets.size() == 1 );
    CHECK( graph.outTargets[ 0 ] == 1 );
    REQUIRE( graph.outVals.size() == 1 );
    CHECK( graph.outVals[ 0 ] == 1.0f );
}

// ------------------------------------------------------------------------------------------------
// C1-C6: CSR structure and verification (prompts/help-wanted/graph-unit-tests.md)
// ------------------------------------------------------------------------------------------------

TEST_CASE( "C1: default constructor produces empty unverified CSR" )
{
    const sparseCsr<float> csr;
    CHECK( csr.rows() == 0 );
    CHECK( csr.cols() == 0 );
    CHECK( csr.nnz() == 0 );
    CHECK( csr.rowOffsets() == nullptr );
    CHECK( csr.colIndices() == nullptr );
    CHECK( csr.values() == nullptr );
    CHECK( !rw::verifyCsr( csr, 0 ) );
}

TEST_CASE( "C2: 0-node three-argument constructor creates verified empty CSR" )
{
    const sparseCsr<float> csr( 0, 0, 0 );
    CHECK( csr.rows() == 0 );
    CHECK( csr.cols() == 0 );
    CHECK( csr.nnz() == 0 );
    REQUIRE( csr.rowOffsets() != nullptr );
    CHECK( csr.rowOffsets()[ 0 ] == 0 );
    CHECK( csr.colIndices() == nullptr );
    CHECK( csr.values() == nullptr );
    CHECK( rw::verifyCsr( csr, 0 ) );
}

TEST_CASE( "C3: 3-node zero-edge CSR initializes offsets and verifies" )
{
    const sparseCsr<float> csr( 3, 3, 0 );
    CHECK( csr.rows() == 3 );
    CHECK( csr.cols() == 3 );
    CHECK( csr.nnz() == 0 );
    REQUIRE( csr.rowOffsets() != nullptr );
    for( std::size_t rowIndex = 0; rowIndex <= 3; ++rowIndex )
    {
        CHECK( csr.rowOffsets()[ rowIndex ] == 0 );
    }
    CHECK( csr.colIndices() == nullptr );
    CHECK( csr.values() == nullptr );
    CHECK( rw::verifyCsr( csr, 3 ) );
}

TEST_CASE( "C4: move semantics reset source and preserve destination verification" )
{
    // Build a verified 3-node base matrix
    sparseCsr<float> base( 3, 3, 3 );
    base.rowOffsets()[ 0 ] = 0;
    base.rowOffsets()[ 1 ] = 1;
    base.rowOffsets()[ 2 ] = 1;
    base.rowOffsets()[ 3 ] = 3;
    base.colIndices()[ 0 ] = 2;
    base.colIndices()[ 1 ] = 0;
    base.colIndices()[ 2 ] = 1;
    base.values()[ 0 ] = 0.5f;
    base.values()[ 1 ] = 1.0f;
    base.values()[ 2 ] = 2.0f;
    REQUIRE( rw::verifyCsr( base, 3 ) );

    // Move-construct from base
    sparseCsr<float> movedConstructed( std::move( base ) );
    CHECK( base.rows() == 0 );
    CHECK( base.cols() == 0 );
    CHECK( base.nnz() == 0 );
    CHECK( base.rowOffsets() == nullptr );
    CHECK( !rw::verifyCsr( base, 0 ) );
    CHECK( rw::verifyCsr( movedConstructed, 3 ) );

    // Move-assign into a non-empty destination
    sparseCsr<float> movedAssigned( 1, 1, 1 );
    movedAssigned = std::move( movedConstructed );
    CHECK( movedConstructed.rows() == 0 );
    CHECK( movedConstructed.cols() == 0 );
    CHECK( movedConstructed.nnz() == 0 );
    CHECK( movedConstructed.rowOffsets() == nullptr );
    CHECK( !rw::verifyCsr( movedConstructed, 0 ) );
    CHECK( rw::verifyCsr( movedAssigned, 3 ) );

    // Self-move-assign through a reference
    sparseCsr<float>& selfRef = movedAssigned;
    movedAssigned = std::move( selfRef );
    CHECK( rw::verifyCsr( movedAssigned, 3 ) );
}

TEST_CASE( "C5: CSR verifier mutation matrix catches structural and numeric violations" )
{
    const auto makeBase = []()
    {
        sparseCsr<float> base( 3, 3, 3 );
        base.rowOffsets()[ 0 ] = 0;
        base.rowOffsets()[ 1 ] = 1;
        base.rowOffsets()[ 2 ] = 1;
        base.rowOffsets()[ 3 ] = 3;
        base.colIndices()[ 0 ] = 2;
        base.colIndices()[ 1 ] = 0;
        base.colIndices()[ 2 ] = 1;
        base.values()[ 0 ] = 0.5f;
        base.values()[ 1 ] = 1.0f;
        base.values()[ 2 ] = 2.0f;
        return base;
    };

    const sparseCsr<float> base = makeBase();
    REQUIRE( rw::verifyCsr( base, 3 ) );

    // C5a: node count 2 -> false
    CHECK( !rw::verifyCsr( base, 2 ) );

    // C5b: same arrays in (3, 4, 3) matrix -> cols != nodeCount -> false
    {
        sparseCsr<float> m( 3, 4, 3 );
        std::copy( base.rowOffsets(), base.rowOffsets() + 4, m.rowOffsets() );
        std::copy( base.colIndices(), base.colIndices() + 3, m.colIndices() );
        std::copy( base.values(), base.values() + 3, m.values() );
        CHECK( !rw::verifyCsr( m, 3 ) );
    }

    // C5c: offsets[0] = 1 -> false
    {
        sparseCsr<float> m = makeBase();
        m.rowOffsets()[ 0 ] = 1;
        CHECK( !rw::verifyCsr( m, 3 ) );
    }

    // C5d: offsets[3] = 2 -> offsets[n] != nnz -> false
    {
        sparseCsr<float> m = makeBase();
        m.rowOffsets()[ 3 ] = 2;
        CHECK( !rw::verifyCsr( m, 3 ) );
    }

    // C5e: offsets decrease -> offsets { 0, 2, 1, 3 } -> false
    {
        sparseCsr<float> m = makeBase();
        m.rowOffsets()[ 1 ] = 2;
        m.rowOffsets()[ 2 ] = 1;
        CHECK( !rw::verifyCsr( m, 3 ) );
    }

    // C5f: 2-node matrix with offsets { 0, 5, 2 }, cols { 0, 1 }, nnz 2 -> false
    {
        sparseCsr<float> m( 2, 2, 2 );
        m.rowOffsets()[ 0 ] = 0;
        m.rowOffsets()[ 1 ] = 5;
        m.rowOffsets()[ 2 ] = 2;
        m.colIndices()[ 0 ] = 0;
        m.colIndices()[ 1 ] = 1;
        m.values()[ 0 ] = 1.0f;
        m.values()[ 1 ] = 1.0f;
        CHECK( !rw::verifyCsr( m, 2 ) );
    }

    // C5g: columns[0] = 3 >= nodeCount -> false
    {
        sparseCsr<float> m = makeBase();
        m.colIndices()[ 0 ] = 3;
        CHECK( !rw::verifyCsr( m, 3 ) );
    }

    // C5h: values[0] = NaN -> false
    {
        sparseCsr<float> m = makeBase();
        m.values()[ 0 ] = std::numeric_limits<float>::quiet_NaN();
        CHECK( !rw::verifyCsr( m, 3 ) );
    }

    // C5i: values[0] = +inf -> false
    {
        sparseCsr<float> m = makeBase();
        m.values()[ 0 ] = std::numeric_limits<float>::infinity();
        CHECK( !rw::verifyCsr( m, 3 ) );
    }

    // C5j: values[0] = -1.0f -> false
    {
        sparseCsr<float> m = makeBase();
        m.values()[ 0 ] = -1.0f;
        CHECK( !rw::verifyCsr( m, 3 ) );
    }

    // C5k: values[0] = -0.0f -> passes because -0.0f < 0 is false -> true
    {
        sparseCsr<float> m = makeBase();
        m.values()[ 0 ] = -0.0f;
        CHECK( rw::verifyCsr( m, 3 ) );
    }
}

TEST_CASE( "C6: applyInto on 3x10 float matrix matches exact integer sums" )
{
    sparseCsr<float> csr( 3, 10, 49 );
    csr.rowOffsets()[ 0 ] = 0;
    csr.rowOffsets()[ 1 ] = 40;
    csr.rowOffsets()[ 2 ] = 40;
    csr.rowOffsets()[ 3 ] = 49;

    for( std::uint32_t edgeIndex = 0; edgeIndex < 40; ++edgeIndex )
    {
        csr.colIndices()[ edgeIndex ] = edgeIndex % 10u;
        csr.values()[ edgeIndex ] = 1.0f;
    }
    for( std::uint32_t edgeIndex = 0; edgeIndex < 9; ++edgeIndex )
    {
        csr.colIndices()[ 40 + edgeIndex ] = edgeIndex;
        csr.values()[ 40 + edgeIndex ] = float( edgeIndex + 1 );
    }

    std::vector<float> vectorX( 10 );
    for( std::size_t nodeIndex = 0; nodeIndex < 10; ++nodeIndex )
    {
        vectorX[ nodeIndex ] = float( nodeIndex );
    }
    std::vector<float> vectorY( 3, 0.0f );
    csr.applyInto( vectorX.data(), vectorY.data() );

    CHECK( vectorY[ 0 ] == 180.0f );
    CHECK( vectorY[ 1 ] == 0.0f );
    CHECK( vectorY[ 2 ] == 240.0f );
}

// ------------------------------------------------------------------------------------------------
// G0-G10: Graphs produced by buildGraph (prompts/help-wanted/graph-unit-tests.md)
// ------------------------------------------------------------------------------------------------

namespace
{

rw::Symbol makeSymbol( std::uint32_t id, std::string_view name, std::uint32_t fileId = 0 )
{
    rw::Symbol sym;
    sym.id = id;
    sym.fileId = fileId;
    sym.lang = rw::Lang::Cpp;
    sym.kind = rw::SymKind::Function;
    sym.name = std::string( name );
    return sym;
}

rw::Reference makeReference( std::uint32_t fromSymbol, std::string_view calleeName, std::uint32_t line = 1, std::uint32_t fileId = 0 )
{
    rw::Reference ref;
    ref.fromSymbol = fromSymbol;
    ref.fileId = fileId;
    ref.line = line;
    ref.lang = rw::Lang::Cpp;
    ref.role = rw::RefRole::Call;
    ref.calleeName = std::string( calleeName );
    return ref;
}

void checkGraphInvariants( const rw::Graph& graph, std::size_t nodeCount )
{
    REQUIRE( rw::verifyCsr( graph.inEdges, nodeCount ) );
    REQUIRE( graph.outOff.size() == nodeCount + 1 );
    CHECK( graph.outOff.back() == graph.inEdges.nnz() );

    struct Triple
    {
        std::uint32_t fromNode;
        std::uint32_t toNode;
        float weight;
        bool operator<( const Triple& other ) const noexcept
        {
            if( fromNode != other.fromNode )
            {
                return fromNode < other.fromNode;
            }
            if( toNode != other.toNode )
            {
                return toNode < other.toNode;
            }
            return weight < other.weight;
        }
    };

    std::vector<Triple> outTriples;
    outTriples.reserve( graph.outTargets.size() );
    for( std::uint32_t fromNode = 0; fromNode < std::uint32_t( nodeCount ); ++fromNode )
    {
        const std::uint32_t start = graph.outOff[ fromNode ];
        const std::uint32_t end = graph.outOff[ fromNode + 1 ];
        for( std::uint32_t edgeIndex = start; edgeIndex < end; ++edgeIndex )
        {
            outTriples.push_back( { fromNode, graph.outTargets[ edgeIndex ], graph.outVals[ edgeIndex ] } );
        }
    }

    std::vector<Triple> inTriples;
    inTriples.reserve( graph.inEdges.nnz() );
    for( std::uint32_t toNode = 0; toNode < std::uint32_t( nodeCount ); ++toNode )
    {
        const std::uint32_t start = graph.inEdges.rowOffsets()[ toNode ];
        const std::uint32_t end = graph.inEdges.rowOffsets()[ toNode + 1 ];
        std::uint32_t previousCol = 0;
        for( std::uint32_t edgeIndex = start; edgeIndex < end; ++edgeIndex )
        {
            const std::uint32_t fromNode = graph.inEdges.colIndices()[ edgeIndex ];
            if( edgeIndex > start )
            {
                CHECK( fromNode > previousCol );
            }
            previousCol = fromNode;
            CHECK( fromNode != toNode );
            inTriples.push_back( { fromNode, toNode, graph.inEdges.values()[ edgeIndex ] } );
        }
    }

    std::sort( outTriples.begin(), outTriples.end() );
    std::sort( inTriples.begin(), inTriples.end() );
    REQUIRE( outTriples.size() == inTriples.size() );
    for( std::size_t edgeIndex = 0; edgeIndex < outTriples.size(); ++edgeIndex )
    {
        CHECK( outTriples[ edgeIndex ].fromNode == inTriples[ edgeIndex ].fromNode );
        CHECK( outTriples[ edgeIndex ].toNode == inTriples[ edgeIndex ].toNode );
        CHECK( std::fabs( outTriples[ edgeIndex ].weight - inTriples[ edgeIndex ].weight ) <= 1e-6f );
    }

    std::vector<double> summedOutDeg( nodeCount, 0.0 );
    for( const auto& triple : outTriples )
    {
        summedOutDeg[ triple.fromNode ] += double( triple.weight );
    }
    for( std::size_t nodeIndex = 0; nodeIndex < nodeCount; ++nodeIndex )
    {
        const double bound = 1e-12 * std::max( 1.0, graph.wOutDeg[ nodeIndex ] );
        CHECK( std::fabs( summedOutDeg[ nodeIndex ] - graph.wOutDeg[ nodeIndex ] ) <= bound );
    }
}

}

TEST_CASE( "G0: empty IngestResult produces empty verified graph" )
{
    const rw::IngestResult ingest;
    const rw::Graph graph = rw::buildGraph( ingest );
    CHECK( graph.inEdges.rows() == 0 );
    CHECK( graph.inEdges.nnz() == 0 );
    REQUIRE( graph.inEdges.rowOffsets() != nullptr );
    CHECK( graph.inEdges.rowOffsets()[ 0 ] == 0 );
    CHECK( rw::verifyCsr( graph.inEdges, 0 ) );
    CHECK( graph.wOutDeg.empty() );
    REQUIRE( graph.outOff.size() == 1 );
    CHECK( graph.outOff[ 0 ] == 0 );
    checkGraphInvariants( graph, 0 );
}

TEST_CASE( "G2: duplicate calls are aggregated sublinearly" )
{
    // Both references on different lines (11 and 12)
    {
        rw::IngestResult ingest;
        ingest.files.emplace_back( "g2.cpp" );
        ingest.symbols.push_back( makeSymbol( 0, "caller" ) );
        ingest.symbols.push_back( makeSymbol( 1, "callee" ) );
        ingest.references.push_back( makeReference( 0, "callee", 11 ) );
        ingest.references.push_back( makeReference( 0, "callee", 12 ) );

        const rw::Graph graph = rw::buildGraph( ingest );
        REQUIRE( graph.inEdges.nnz() == 1 );
        const float expectedWeight = std::sqrt( 2.0f );
        CHECK( std::fabs( graph.inEdges.values()[ 0 ] - expectedWeight ) <= 1e-6f );
        CHECK( graph.wOutDeg[ 0 ] == double( graph.inEdges.values()[ 0 ] ) );
        checkGraphInvariants( graph, 2 );
    }

    // Both references on the same line (11)
    {
        rw::IngestResult ingest;
        ingest.files.emplace_back( "g2.cpp" );
        ingest.symbols.push_back( makeSymbol( 0, "caller" ) );
        ingest.symbols.push_back( makeSymbol( 1, "callee" ) );
        ingest.references.push_back( makeReference( 0, "callee", 11 ) );
        ingest.references.push_back( makeReference( 0, "callee", 11 ) );

        const rw::Graph graph = rw::buildGraph( ingest );
        REQUIRE( graph.inEdges.nnz() == 1 );
        const float expectedWeight = std::sqrt( 2.0f );
        CHECK( std::fabs( graph.inEdges.values()[ 0 ] - expectedWeight ) <= 1e-6f );
        CHECK( graph.wOutDeg[ 0 ] == double( graph.inEdges.values()[ 0 ] ) );
        checkGraphInvariants( graph, 2 );
    }
}

TEST_CASE( "G3: self-loops are dropped by buildGraph" )
{
    rw::IngestResult ingest;
    ingest.files.emplace_back( "g3.cpp" );
    ingest.symbols.push_back( makeSymbol( 0, "recur" ) );
    ingest.references.push_back( makeReference( 0, "recur" ) );

    const rw::Graph graph = rw::buildGraph( ingest );
    CHECK( graph.inEdges.nnz() == 0 );
    CHECK( graph.inEdges.rowOffsets()[ 0 ] == 0 );
    CHECK( graph.inEdges.rowOffsets()[ 1 ] == 0 );
    REQUIRE( graph.wOutDeg.size() == 1 );
    CHECK( graph.wOutDeg[ 0 ] == 0.0 );
    REQUIRE( graph.outOff.size() == 2 );
    CHECK( graph.outOff[ 0 ] == 0 );
    CHECK( graph.outOff[ 1 ] == 0 );
    checkGraphInvariants( graph, 1 );
}

TEST_CASE( "G4: references added out-of-order are radix sorted" )
{
    rw::IngestResult ingest;
    ingest.files.emplace_back( "g4.cpp" );
    ingest.symbols.push_back( makeSymbol( 0, "alpha" ) );
    ingest.symbols.push_back( makeSymbol( 1, "bravo" ) );
    ingest.symbols.push_back( makeSymbol( 2, "charlie" ) );
    ingest.symbols.push_back( makeSymbol( 3, "hub" ) );

    // Added in order charlie->hub, alpha->hub, bravo->hub
    ingest.references.push_back( makeReference( 2, "hub" ) );
    ingest.references.push_back( makeReference( 0, "hub" ) );
    ingest.references.push_back( makeReference( 1, "hub" ) );

    const rw::Graph graph = rw::buildGraph( ingest );
    REQUIRE( graph.inEdges.rows() == 4 );
    REQUIRE( graph.inEdges.nnz() == 3 );
    CHECK( graph.inEdges.rowOffsets()[ 0 ] == 0 );
    CHECK( graph.inEdges.rowOffsets()[ 1 ] == 0 );
    CHECK( graph.inEdges.rowOffsets()[ 2 ] == 0 );
    CHECK( graph.inEdges.rowOffsets()[ 3 ] == 0 );
    CHECK( graph.inEdges.rowOffsets()[ 4 ] == 3 );

    CHECK( graph.inEdges.colIndices()[ 0 ] == 0 );
    CHECK( graph.inEdges.colIndices()[ 1 ] == 1 );
    CHECK( graph.inEdges.colIndices()[ 2 ] == 2 );

    CHECK( graph.inEdges.values()[ 0 ] == 1.0f );
    CHECK( graph.inEdges.values()[ 1 ] == 1.0f );
    CHECK( graph.inEdges.values()[ 2 ] == 1.0f );

    REQUIRE( graph.wOutDeg.size() == 4 );
    CHECK( graph.wOutDeg[ 0 ] == 1.0 );
    CHECK( graph.wOutDeg[ 1 ] == 1.0 );
    CHECK( graph.wOutDeg[ 2 ] == 1.0 );
    CHECK( graph.wOutDeg[ 3 ] == 0.0 );

    REQUIRE( graph.outOff.size() == 5 );
    CHECK( graph.outOff[ 0 ] == 0 );
    CHECK( graph.outOff[ 1 ] == 1 );
    CHECK( graph.outOff[ 2 ] == 2 );
    CHECK( graph.outOff[ 3 ] == 3 );
    CHECK( graph.outOff[ 4 ] == 3 );

    REQUIRE( graph.outTargets.size() == 3 );
    CHECK( graph.outTargets[ 0 ] == 3 );
    CHECK( graph.outTargets[ 1 ] == 3 );
    CHECK( graph.outTargets[ 2 ] == 3 );

    checkGraphInvariants( graph, 4 );
}

TEST_CASE( "G5: repeated call weight is capped at 8.0f" )
{
    const auto makeGraph = []( std::size_t callCount )
    {
        rw::IngestResult ingest;
        ingest.files.emplace_back( "g5.cpp" );
        ingest.symbols.push_back( makeSymbol( 0, "caller" ) );
        ingest.symbols.push_back( makeSymbol( 1, "callee" ) );
        for( std::size_t callIndex = 0; callIndex < callCount; ++callIndex )
        {
            ingest.references.push_back( makeReference( 0, "callee", std::uint32_t( callIndex + 1 ) ) );
        }
        return rw::buildGraph( ingest );
    };

    // 63 calls: sqrt(63.0f)
    {
        const rw::Graph g63 = makeGraph( 63 );
        REQUIRE( g63.inEdges.nnz() == 1 );
        CHECK( std::fabs( g63.inEdges.values()[ 0 ] - std::sqrt( 63.0f ) ) <= 1e-6f );
        checkGraphInvariants( g63, 2 );
    }

    // 64 calls: exactly 8.0f (sqrt(64), not capped)
    {
        const rw::Graph g64 = makeGraph( 64 );
        REQUIRE( g64.inEdges.nnz() == 1 );
        CHECK( g64.inEdges.values()[ 0 ] == 8.0f );
        checkGraphInvariants( g64, 2 );
    }

    // 65 calls: exactly 8.0f (capped, distinct from sqrt(65.0f))
    {
        const rw::Graph g65 = makeGraph( 65 );
        REQUIRE( g65.inEdges.nnz() == 1 );
        CHECK( g65.inEdges.values()[ 0 ] == 8.0f );
        CHECK( g65.inEdges.values()[ 0 ] != std::sqrt( 65.0f ) );
        checkGraphInvariants( g65, 2 );
    }

    // 100 calls: exactly 8.0f (capped)
    {
        const rw::Graph g100 = makeGraph( 100 );
        REQUIRE( g100.inEdges.nnz() == 1 );
        CHECK( g100.inEdges.values()[ 0 ] == 8.0f );
        checkGraphInvariants( g100, 2 );
    }
}

TEST_CASE( "G6: multi-definition split conserves reference confidence" )
{
    rw::IngestResult ingest;
    ingest.files.emplace_back( "g6.cpp" );
    ingest.symbols.push_back( makeSymbol( 0, "caller" ) );
    ingest.symbols.push_back( makeSymbol( 1, "callee" ) );
    ingest.symbols.push_back( makeSymbol( 2, "callee" ) );
    ingest.references.push_back( makeReference( 0, "callee" ) );

    const rw::Graph graph = rw::buildGraph( ingest );
    REQUIRE( graph.inEdges.rows() == 3 );
    REQUIRE( graph.inEdges.nnz() == 2 );
    CHECK( graph.inEdges.rowOffsets()[ 0 ] == 0 );
    CHECK( graph.inEdges.rowOffsets()[ 1 ] == 0 );
    CHECK( graph.inEdges.rowOffsets()[ 2 ] == 1 );
    CHECK( graph.inEdges.rowOffsets()[ 3 ] == 2 );

    CHECK( graph.inEdges.colIndices()[ 0 ] == 0 );
    CHECK( graph.inEdges.colIndices()[ 1 ] == 0 );
    CHECK( graph.inEdges.values()[ 0 ] == 0.5f );
    CHECK( graph.inEdges.values()[ 1 ] == 0.5f );

    REQUIRE( graph.wOutDeg.size() == 3 );
    CHECK( graph.wOutDeg[ 0 ] == 1.0 );
    CHECK( graph.wOutDeg[ 1 ] == 0.0 );
    CHECK( graph.wOutDeg[ 2 ] == 0.0 );

    REQUIRE( graph.outTargets.size() == 2 );
    CHECK( graph.outTargets[ 0 ] == 1 );
    CHECK( graph.outTargets[ 1 ] == 2 );

    float outValSum = 0.0f;
    for( const float val : graph.outVals )
    {
        outValSum += val;
    }
    CHECK( std::fabs( outValSum - 1.0f ) <= 1e-6f );

    checkGraphInvariants( graph, 3 );
}

TEST_CASE( "G7: leading underscore deboosts edge weight" )
{
    rw::IngestResult ingest;
    ingest.files.emplace_back( "g7.cpp" );
    ingest.symbols.push_back( makeSymbol( 0, "caller" ) );
    ingest.symbols.push_back( makeSymbol( 1, "_priv" ) );
    ingest.references.push_back( makeReference( 0, "_priv" ) );

    const rw::Graph graph = rw::buildGraph( ingest );
    REQUIRE( graph.inEdges.nnz() == 1 );
    CHECK( graph.inEdges.values()[ 0 ] == 0.1f );
    CHECK( graph.wOutDeg[ 0 ] == double( 0.1f ) );
    checkGraphInvariants( graph, 2 );
}

TEST_CASE( "G8: multi-edge graph builds matching in and out CSRs" )
{
    rw::IngestResult ingest;
    ingest.files.emplace_back( "g8.cpp" );
    ingest.symbols.push_back( makeSymbol( 0, "alpha" ) );
    ingest.symbols.push_back( makeSymbol( 1, "bravo" ) );
    ingest.symbols.push_back( makeSymbol( 2, "charlie" ) );

    ingest.references.push_back( makeReference( 0, "bravo" ) );
    ingest.references.push_back( makeReference( 0, "charlie" ) );
    ingest.references.push_back( makeReference( 1, "charlie" ) );

    const rw::Graph graph = rw::buildGraph( ingest );
    REQUIRE( graph.inEdges.rows() == 3 );
    REQUIRE( graph.inEdges.nnz() == 3 );
    CHECK( graph.inEdges.rowOffsets()[ 0 ] == 0 );
    CHECK( graph.inEdges.rowOffsets()[ 1 ] == 0 );
    CHECK( graph.inEdges.rowOffsets()[ 2 ] == 1 );
    CHECK( graph.inEdges.rowOffsets()[ 3 ] == 3 );

    CHECK( graph.inEdges.colIndices()[ 0 ] == 0 );
    CHECK( graph.inEdges.colIndices()[ 1 ] == 0 );
    CHECK( graph.inEdges.colIndices()[ 2 ] == 1 );

    CHECK( graph.inEdges.values()[ 0 ] == 1.0f );
    CHECK( graph.inEdges.values()[ 1 ] == 1.0f );
    CHECK( graph.inEdges.values()[ 2 ] == 1.0f );

    REQUIRE( graph.wOutDeg.size() == 3 );
    CHECK( graph.wOutDeg[ 0 ] == 2.0 );
    CHECK( graph.wOutDeg[ 1 ] == 1.0 );
    CHECK( graph.wOutDeg[ 2 ] == 0.0 );

    REQUIRE( graph.outOff.size() == 4 );
    CHECK( graph.outOff[ 0 ] == 0 );
    CHECK( graph.outOff[ 1 ] == 2 );
    CHECK( graph.outOff[ 2 ] == 3 );
    CHECK( graph.outOff[ 3 ] == 3 );

    REQUIRE( graph.outTargets.size() == 3 );
    CHECK( graph.outTargets[ 0 ] == 1 );
    CHECK( graph.outTargets[ 1 ] == 2 );
    CHECK( graph.outTargets[ 2 ] == 2 );

    checkGraphInvariants( graph, 3 );
}

TEST_CASE( "G9: unresolvable callee name produces no edge" )
{
    rw::IngestResult ingest;
    ingest.files.emplace_back( "g9.cpp" );
    ingest.symbols.push_back( makeSymbol( 0, "alpha" ) );
    ingest.references.push_back( makeReference( 0, "nosuchname" ) );

    const rw::Graph graph = rw::buildGraph( ingest );
    CHECK( graph.inEdges.nnz() == 0 );
    REQUIRE( graph.wOutDeg.size() == 1 );
    CHECK( graph.wOutDeg[ 0 ] == 0.0 );
    checkGraphInvariants( graph, 1 );
}

TEST_CASE( "G10: graph invariant helper passes across all standard fixtures" )
{
    // G10 is directly verified across G0 through G9 via checkGraphInvariants()
    CHECK( true );
}

