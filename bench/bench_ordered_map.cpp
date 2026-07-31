// bench_ordered_map.cpp - ordered-map tournament for ripwire quality hot paths.
//
// The quality-delta code uses sorted numeric maps keyed by fnv1a64(canonId): aggregate MAX
// metrics, insert "seen" sets, lookup baseline/current maps, then sometimes iterate in key order.
// This benchmark compares the current `gtl::btree_map` against the bounded, no-per-op-allocation
// S+tree `dynamic_map` for that exact uint64 -> tiny-value shape.
//
// Build:
//   c++ -O3 -march=native -std=c++23 bench/bench_ordered_map.cpp -Isrc/infra -Ithird_party -o /tmp/ripwire_bench_ordered_map
// Run:
//   /tmp/ripwire_bench_ordered_map 1000000

#include "btree.hpp"
#include "dynamic_map.hpp"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string_view>
#include <utility>
#include <vector>

template<class Fn>
static double timedMs( Fn&& fn )
{
    const auto t0 = std::chrono::steady_clock::now();
    fn();
    return std::chrono::duration<double, std::milli>( std::chrono::steady_clock::now() - t0 ).count();
}

static double median( std::vector<double> v )
{
    std::sort( v.begin(), v.end() );
    return v[ v.size() / 2 ];
}

static std::uint64_t splitmix64( std::uint64_t& x )
{
    std::uint64_t z = ( x += 0x9E3779B97F4A7C15ull );
    z = ( z ^ ( z >> 30 ) ) * 0xBF58476D1CE4E5B9ull;
    z = ( z ^ ( z >> 27 ) ) * 0x94D049BB133111EBull;
    return z ^ ( z >> 31 );
}

struct Inputs
{
    std::vector<std::uint64_t> keys;
    std::vector<std::uint32_t> values;
    std::size_t                uniqueCount = 0;
};

static Inputs makeInputs( std::size_t opCount, std::size_t uniqueCount )
{
    Inputs in;
    in.keys.resize( opCount );
    in.values.resize( opCount );
    in.uniqueCount = uniqueCount;

    std::vector<std::uint64_t> universe( uniqueCount );
    std::uint64_t seed = 0xC7C7DADAC0FFEE11ull;
    for( std::uint64_t& key : universe )
        key = splitmix64( seed );

    for( std::size_t i = 0; i < opCount; ++i )
    {
        in.keys[ i ] = universe[ splitmix64( seed ) % uniqueCount ];
        in.values[ i ] = std::uint32_t( splitmix64( seed ) & 0xFFFFu );
    }
    return in;
}

template<class Map>
static std::vector<std::pair<std::uint64_t, std::uint32_t>> pairsOf( const Map& m )
{
    std::vector<std::pair<std::uint64_t, std::uint32_t>> out;
    out.reserve( m.size() );
    for( const auto& [ k, v ] : m )
        out.push_back( { k, v } );
    return out;
}

template<class Map>
static void aggregateMax( Map& m, const Inputs& in )
{
    for( std::size_t i = 0; i < in.keys.size(); ++i )
    {
        std::uint32_t& slot = m[ in.keys[ i ] ];
        slot = std::max( slot, in.values[ i ] );
    }
}

template<class Map>
static void insertSeen( Map& m, const Inputs& in )
{
    for( std::uint64_t key : in.keys )
        m.insert( { key, std::uint8_t( 1 ) } );
}

template<class Map>
static std::uint64_t lookupSum( const Map& m, const Inputs& in )
{
    std::uint64_t sum = 0;
    for( std::uint64_t key : in.keys )
    {
        const auto it = m.find( key );
        if( it != m.end() )
            sum += it->second;
    }
    return sum;
}

template<class Map>
static std::uint64_t iterateSum( const Map& m )
{
    std::uint64_t sum = 0;
    for( const auto& [ k, v ] : m )
        sum += ( k >> 32 ) ^ v;
    return sum;
}

template<class Map>
static std::uint64_t consumeOnce( Map& m, const Inputs& in )
{
    std::uint64_t sum = 0;
    for( std::uint64_t key : in.keys )
    {
        const auto it = m.find( key );
        if( it == m.end() )
            continue;
        sum += it->second;
        m.erase( it );
    }
    return sum;
}

static std::uint64_t perSymbolBtreeErase( const Inputs& in )
{
    gtl::btree_map<std::uint64_t, std::uint32_t> nowBySym;
    aggregateMax( nowBySym, in );

    std::uint64_t sum = 0;
    for( std::uint64_t key : in.keys )
    {
        const auto it = nowBySym.find( key );
        if( it == nowBySym.end() )
            continue;
        sum += it->second;
        nowBySym.erase( it );
    }
    return sum;
}

template<int B>
static std::uint64_t perSymbolDynamicSeen( const Inputs& in )
{
    stree::dyn::dynamic_map<std::uint64_t, std::uint32_t, B> nowBySym( in.uniqueCount );
    aggregateMax( nowBySym, in );

    stree::dyn::dynamic_map<std::uint64_t, std::uint8_t, B> reported( in.uniqueCount );
    std::uint64_t sum = 0;
    for( std::uint64_t key : in.keys )
    {
        if( !reported.insert( { key, 1 } ).second )
            continue;

        const auto it = nowBySym.find( key );
        if( it == nowBySym.end() )
            continue;
        sum += it->second;
    }
    return sum;
}

template<class Maker, class Fn>
static double runCase( Maker&& maker, Fn&& fn )
{
    constexpr int kRuns = 3;
    std::vector<double> times;
    times.reserve( kRuns );
    for( int run = 0; run < kRuns; ++run )
    {
        auto m = maker();
        times.push_back( timedMs( [ & ] { fn( m ); } ) );
    }
    return median( times );
}

template<class Maker>
static void benchAggregate( std::string_view name, Maker&& maker, const Inputs& in,
                            const std::vector<std::pair<std::uint64_t, std::uint32_t>>& expected )
{
    double ms = runCase( maker, [ & ]( auto& m ) { aggregateMax( m, in ); } );

    auto m = maker();
    aggregateMax( m, in );
    if( pairsOf( m ) != expected )
    {
        std::fprintf( stderr, "aggregate output mismatch: %.*s\n", int( name.size() ), name.data() );
        std::exit( 2 );
    }

    std::printf( "  %-18.*s aggregate-max %8.3f ms\n", int( name.size() ), name.data(), ms );
}

template<class Maker>
static void benchSeen( std::string_view name, Maker&& maker, const Inputs& in, std::size_t expectedSize )
{
    double ms = runCase( maker, [ & ]( auto& m ) { insertSeen( m, in ); } );

    auto m = maker();
    insertSeen( m, in );
    if( m.size() != expectedSize )
    {
        std::fprintf( stderr, "seen size mismatch: %.*s\n", int( name.size() ), name.data() );
        std::exit( 2 );
    }

    std::printf( "  %-18.*s insert-seen   %8.3f ms\n", int( name.size() ), name.data(), ms );
}

template<class Maker>
static std::uint64_t benchRead( std::string_view name, Maker&& maker, const Inputs& in )
{
    constexpr int kRuns = 3;
    auto m = maker();
    aggregateMax( m, in );

    std::uint64_t guard = 0;
    std::vector<double> lookupTimes;
    std::vector<double> iterTimes;
    lookupTimes.reserve( kRuns );
    iterTimes.reserve( kRuns );
    for( int run = 0; run < kRuns; ++run )
    {
        lookupTimes.push_back( timedMs( [ & ]
        {
            guard ^= lookupSum( m, in );
        } ) );
        iterTimes.push_back( timedMs( [ & ]
        {
            guard ^= iterateSum( m );
        } ) );
    }

    std::printf( "  %-18.*s lookup        %8.3f ms | iterate %8.3f ms\n",
                 int( name.size() ), name.data(), median( lookupTimes ), median( iterTimes ) );
    return guard;
}

template<class Maker>
static std::uint64_t benchConsume( std::string_view name, Maker&& maker, const Inputs& in )
{
    constexpr int kRuns = 3;
    std::vector<double> times;
    times.reserve( kRuns );

    std::uint64_t guard = 0;
    for( int run = 0; run < kRuns; ++run )
    {
        auto m = maker();
        aggregateMax( m, in );
        times.push_back( timedMs( [ & ] { guard ^= consumeOnce( m, in ); } ) );
        if( !m.empty() )
        {
            std::fprintf( stderr, "consume failed to empty map: %.*s\n", int( name.size() ), name.data() );
            std::exit( 2 );
        }
    }

    std::printf( "  %-18.*s consume-once  %8.3f ms\n", int( name.size() ), name.data(), median( times ) );
    return guard;
}

template<class Fn>
static std::uint64_t benchPerSymbolShape( std::string_view name, Fn&& fn )
{
    constexpr int kRuns = 3;
    std::vector<double> times;
    times.reserve( kRuns );

    std::uint64_t guard = 0;
    for( int run = 0; run < kRuns; ++run )
        times.push_back( timedMs( [ & ] { guard ^= fn(); } ) );

    std::printf( "  %-18.*s per-symbol    %8.3f ms\n", int( name.size() ), name.data(), median( times ) );
    return guard;
}

int main( int argc, char** argv )
{
    const std::size_t opCount = ( argc > 1 ) ? std::strtoull( argv[1], nullptr, 10 ) : 1000000;
    const std::size_t uniqueCount = std::max<std::size_t>( 1, opCount / 2 );
    const Inputs in = makeInputs( opCount, uniqueCount );

    gtl::btree_map<std::uint64_t, std::uint32_t> expectedMap;
    aggregateMax( expectedMap, in );
    const auto expected = pairsOf( expectedMap );

    std::printf( "ordered-map workload: %zu ops, %zu unique requested, %zu actual unique\n",
                 opCount, uniqueCount, expected.size() );

    const auto makeBtree32 = [] { return gtl::btree_map<std::uint64_t, std::uint32_t>(); };
    const auto makeDyn16_32 = [ & ] { return stree::dyn::dynamic_map<std::uint64_t, std::uint32_t, 16>( uniqueCount ); };
    const auto makeDyn32_32 = [ & ] { return stree::dyn::dynamic_map<std::uint64_t, std::uint32_t, 32>( uniqueCount ); };

    benchAggregate( "gtl::btree", makeBtree32, in, expected );
    benchAggregate( "dynamic_map<16>", makeDyn16_32, in, expected );
    benchAggregate( "dynamic_map<32>", makeDyn32_32, in, expected );

    std::printf( "\n" );

    const auto makeBtree8 = [] { return gtl::btree_map<std::uint64_t, std::uint8_t>(); };
    const auto makeDyn16_8 = [ & ] { return stree::dyn::dynamic_map<std::uint64_t, std::uint8_t, 16>( uniqueCount ); };
    const auto makeDyn32_8 = [ & ] { return stree::dyn::dynamic_map<std::uint64_t, std::uint8_t, 32>( uniqueCount ); };

    benchSeen( "gtl::btree", makeBtree8, in, expected.size() );
    benchSeen( "dynamic_map<16>", makeDyn16_8, in, expected.size() );
    benchSeen( "dynamic_map<32>", makeDyn32_8, in, expected.size() );

    std::printf( "\n" );

    std::uint64_t guard = 0;
    guard ^= benchRead( "gtl::btree", makeBtree32, in );
    guard ^= benchRead( "dynamic_map<16>", makeDyn16_32, in );
    guard ^= benchRead( "dynamic_map<32>", makeDyn32_32, in );

    std::printf( "\n" );

    guard ^= benchConsume( "gtl::btree", makeBtree32, in );
    guard ^= benchConsume( "dynamic_map<16>", makeDyn16_32, in );
    guard ^= benchConsume( "dynamic_map<32>", makeDyn32_32, in );

    std::printf( "\n" );

    const std::uint64_t expectedPerSymbol = perSymbolBtreeErase( in );
    guard ^= benchPerSymbolShape( "btree erase", [ & ] { return perSymbolBtreeErase( in ); } );
    guard ^= benchPerSymbolShape( "dynamic<16> seen", [ & ] { return perSymbolDynamicSeen<16>( in ); } );
    guard ^= benchPerSymbolShape( "dynamic<32> seen", [ & ] { return perSymbolDynamicSeen<32>( in ); } );
    if( expectedPerSymbol != perSymbolDynamicSeen<16>( in ) || expectedPerSymbol != perSymbolDynamicSeen<32>( in ) )
    {
        std::fprintf( stderr, "per-symbol shape mismatch\n" );
        return 2;
    }

    std::printf( "guard %llu\n", static_cast<unsigned long long>( guard ) );
    return 0;
}
