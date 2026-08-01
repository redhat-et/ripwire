// Alternating A/B benchmark for the pre-A6 per-pass radix versus the vendored single-read histogram core.
// Build: c++ -O3 -march=native -std=c++23 bench/bench_radix_ab.cpp src/infra/diagnostics.cpp -Isrc -Isrc/infra -Ithird_party -o /tmp/ripwire_radix_ab

#include "radixSort.h"
#include "sortutil.h"

#include <algorithm>
#include <array>
#include <bit>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <numeric>
#include <random>
#include <string_view>
#include <vector>

namespace
{

struct Edge
{
    std::uint32_t from = 0;
    std::uint32_t to = 0;
    std::uint32_t payload = 0;
    bool operator==( const Edge& ) const = default;
};
static_assert( sizeof( Edge ) == 12 );

template<class Item, class KeyOf>
void legacySortSmall( std::vector<Item>& values, std::vector<Item>& scratch, KeyOf keyOf )
{
    if( values.size() < 2 )
        return;
    scratch.resize( values.size() );
    Item* source = values.data();
    Item* destination = scratch.data();
    bool sourceIsScratch = false;
    for( unsigned shift = 0; shift < 32; shift += 8 )
    {
        std::array<std::size_t, 256> histogram{};
        for( std::size_t valueIndex = 0; valueIndex < values.size(); ++valueIndex )
            ++histogram[ ( keyOf( source[ valueIndex ] ) >> shift ) & 0xffu ];
        bool isNoOp = false;
        for( const std::size_t count : histogram )
            if( count == values.size() )
                isNoOp = true;
        if( isNoOp )
            continue;
        std::array<std::size_t, 256> offsets{};
        std::size_t sum = 0;
        for( std::size_t bucketIndex = 0; bucketIndex < offsets.size(); ++bucketIndex )
        {
            offsets[ bucketIndex ] = sum;
            sum += histogram[ bucketIndex ];
        }
        for( std::size_t valueIndex = 0; valueIndex < values.size(); ++valueIndex )
        {
            const std::uint32_t bucketIndex = ( keyOf( source[ valueIndex ] ) >> shift ) & 0xffu;
            destination[ offsets[ bucketIndex ]++ ] = source[ valueIndex ];
        }
        std::swap( source, destination );
        sourceIsScratch = !sourceIsScratch;
    }
    if( sourceIsScratch )
        std::copy( source, source + values.size(), values.data() );
}

template<class Item, class KeyOf>
void infraSortSmall( std::vector<Item>& values, std::vector<Item>& scratch, KeyOf keyOf )
{
    scratch.resize( values.size() );
    radix::sortKeySmall( values.data(), scratch.data(), values.size(), keyOf );
}

double median( std::vector<double> samples )
{
    std::sort( samples.begin(), samples.end() );
    return samples[ samples.size() / 2 ];
}

template<class Value, class SortA, class SortB>
void benchAlternating( std::string_view name, const std::vector<Value>& base, const std::vector<Value>& expected, SortA sortA, SortB sortB )
{
    constexpr int kSamples = 7;
    std::vector<double> samplesA;
    std::vector<double> samplesB;
    samplesA.reserve( kSamples );
    samplesB.reserve( kSamples );
    const auto run = [ & ]( auto sorter, std::vector<double>& samples )
    {
        std::vector<Value> values = base;
        const auto begin = std::chrono::steady_clock::now();
        sorter( values );
        samples.push_back( std::chrono::duration<double, std::milli>( std::chrono::steady_clock::now() - begin ).count() );
        if( values != expected )
        {
            std::fprintf( stderr, "semantic preflight failed: %.*s\n", int( name.size() ), name.data() );
            std::exit( 2 );
        }
    };
    for( int sampleIndex = 0; sampleIndex < kSamples; ++sampleIndex )
    {
        if( sampleIndex % 2 == 0 )
        {
            run( sortA, samplesA );
            run( sortB, samplesB );
        }
        else
        {
            run( sortB, samplesB );
            run( sortA, samplesA );
        }
    }
    const double beforeMs = median( samplesA );
    const double afterMs = median( samplesB );
    std::printf( "%-22.*s before=%9.3f ms after=%9.3f ms speedup=%5.2fx samples=%d alternating\n",
                 int( name.size() ), name.data(), beforeMs, afterMs, beforeMs / afterMs, kSamples );
}

std::vector<float> makeScores( std::size_t count, bool hasTies )
{
    std::mt19937 rng( hasTies ? 0x71E5u : 0x5C02E5u );
    std::vector<float> scores( count );
    for( float& score : scores )
        score = hasTies ? float( rng() % 4096u ) : float( rng() & 0x00ffffffu ) / float( 0x01000000u );
    return scores;
}

void benchScores( std::size_t count, bool hasTies )
{
    const std::vector<float> scores = makeScores( count, hasTies );
    std::vector<std::uint32_t> base( count );
    std::iota( base.begin(), base.end(), 0u );
    std::mt19937 rng( 0x51D5u );
    std::shuffle( base.begin(), base.end(), rng );
    std::vector<std::uint32_t> expected = base;
    std::sort( expected.begin(), expected.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return rw::sortutil::lessByScoreDescId( scores, a, b ); } );
    const auto before = [ & ]( std::vector<std::uint32_t>& order )
    {
        std::vector<std::uint32_t> scratch;
        legacySortSmall( order, scratch, []( std::uint32_t id ) { return id; } );
        legacySortSmall( order, scratch, [ & ]( std::uint32_t id ) { return rw::sortutil::nonNegativeFloatDescKey( scores[ id ] ); } );
    };
    const auto after = [ & ]( std::vector<std::uint32_t>& order )
    {
        std::vector<std::uint32_t> scratch;
        infraSortSmall( order, scratch, []( std::uint32_t id ) { return id; } );
        infraSortSmall( order, scratch, [ & ]( std::uint32_t id ) { return rw::sortutil::nonNegativeFloatDescKey( scores[ id ] ); } );
    };
    benchAlternating( hasTies ? "score-id tied shuffled" : "score-id random shuffled", base, expected, before, after );
}

void benchAdaptive( std::size_t count )
{
    const std::vector<float> base = makeScores( count, false );
    std::vector<float> expected = base;
    std::stable_sort( expected.begin(), expected.end(), std::greater<float>() );
    const auto keyOf = []( float value ) { return rw::sortutil::nonNegativeFloatDescKey( value ); };
    benchAlternating( "adaptive float", base, expected,
                      [ & ]( std::vector<float>& values ) { std::vector<float> scratch; legacySortSmall( values, scratch, keyOf ); },
                      [ & ]( std::vector<float>& values ) { std::vector<float> scratch; infraSortSmall( values, scratch, keyOf ); } );
}

void benchEdges( std::size_t count )
{
    std::mt19937 rng( 0xED6Eu );
    std::vector<Edge> base( count );
    for( std::size_t edgeIndex = 0; edgeIndex < count; ++edgeIndex )
        base[ edgeIndex ] = Edge{ rng() % 65536u, rng() % 32768u, std::uint32_t( edgeIndex ) };
    std::vector<Edge> expected = base;
    std::stable_sort( expected.begin(), expected.end(), []( const Edge& a, const Edge& b ) { return a.from != b.from ? a.from < b.from : a.to < b.to; } );
    const auto before = []( std::vector<Edge>& values )
    {
        std::vector<Edge> scratch;
        legacySortSmall( values, scratch, []( const Edge& edge ) { return edge.to; } );
        legacySortSmall( values, scratch, []( const Edge& edge ) { return edge.from; } );
    };
    const auto after = []( std::vector<Edge>& values )
    {
        std::vector<Edge> scratch;
        infraSortSmall( values, scratch, []( const Edge& edge ) { return edge.to; } );
        infraSortSmall( values, scratch, []( const Edge& edge ) { return edge.from; } );
    };
    benchAlternating( "edge from/to stable", base, expected, before, after );
}

}

int main( int argc, char** argv )
{
    const std::size_t count = argc > 1 ? std::strtoull( argv[ 1 ], nullptr, 10 ) : 2'000'000;
    const char* machine = std::getenv( "RIPWIRE_MACHINE" );
    if( machine == nullptr )
        machine = "local";
    std::printf( "ripwire radix A/B: count=%zu machine=%s samples=7 policy=alternating A/B\n", count, machine );
    benchScores( count, false );
    benchScores( count, true );
    benchAdaptive( count );
    benchEdges( count );
    return 0;
}
