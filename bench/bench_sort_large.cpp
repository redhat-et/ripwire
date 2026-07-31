// bench_sort_large.cpp — large-N sort tournament for ripwire's graph-edge shape.
//
// The production edge list is a dense POD array sorted by `(from,to)` before building out-edge and
// in-edge CSR. This benchmark pushes that exact shape past cache-sized inputs and compares:
//   A std::sort comparator
//   B pdqsort comparator (vendored as src/infra/fastSort.h)
//   C stable byte-radix on the two uint32 keys (src/sortutil.h)
//
// Build:
//   c++ -O3 -march=native -std=c++23 bench/bench_sort_large.cpp -Isrc -Isrc/infra -Ithird_party -o /tmp/ripwire_bench_sort_large
// Run:
//   /tmp/ripwire_bench_sort_large 4000000

#include "fastSort.h"
#include "sortutil.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <string_view>
#include <vector>

struct Edge
{
    std::uint32_t from = 0;
    std::uint32_t to   = 0;
    float         w    = 0.0f;
};
static_assert( sizeof( Edge ) == 12 );

template<class Fn>
static double timedMs( Fn&& fn )
{
    const auto t0 = std::chrono::steady_clock::now();
    fn();
    return std::chrono::duration<double, std::milli>( std::chrono::steady_clock::now() - t0 ).count();
}

static bool isSorted( const std::vector<Edge>& v )
{
    for( std::size_t i = 1; i < v.size(); ++i )
        if( ctx::sortutil::lessByFromTo( v[ i ], v[ i - 1 ] ) )
            return false;
    return true;
}

static bool sameSortedOutput( const std::vector<Edge>& a, const std::vector<Edge>& b )
{
    if( a.size() != b.size() )
        return false;

    std::vector<float> aw;
    std::vector<float> bw;
    std::size_t i = 0;
    while( i < a.size() )
    {
        if( a[ i ].from != b[ i ].from || a[ i ].to != b[ i ].to )
            return false;

        const std::uint32_t from = a[ i ].from;
        const std::uint32_t to   = a[ i ].to;
        std::size_t ae = i + 1;
        std::size_t be = i + 1;
        while( ae < a.size() && a[ ae ].from == from && a[ ae ].to == to ) ++ae;
        while( be < b.size() && b[ be ].from == from && b[ be ].to == to ) ++be;
        if( ae != be )
            return false;

        aw.clear();
        bw.clear();
        aw.reserve( ae - i );
        bw.reserve( be - i );
        for( std::size_t k = i; k < ae; ++k ) aw.push_back( a[ k ].w );
        for( std::size_t k = i; k < be; ++k ) bw.push_back( b[ k ].w );
        std::sort( aw.begin(), aw.end() );
        std::sort( bw.begin(), bw.end() );
        if( aw != bw )
            return false;

        i = ae;
    }
    return true;
}

static double median( std::vector<double> v )
{
    std::sort( v.begin(), v.end() );
    return v[ v.size() / 2 ];
}

static std::vector<Edge> makeRandomEdges( std::size_t edgeCount, std::uint32_t nodeCount )
{
    std::mt19937_64 rng( 0xC7C7C7C7ull );
    std::vector<Edge> edges( edgeCount );
    for( Edge& e : edges )
    {
        e.from = std::uint32_t( rng() % nodeCount );
        e.to   = std::uint32_t( rng() % nodeCount );
        e.w    = float( ( rng() & 255u ) + 1u );
    }
    return edges;
}

static std::vector<Edge> makeGraphLikeEdges( std::size_t edgeCount, std::uint32_t nodeCount )
{
    std::mt19937_64 rng( 0x51515151ull );
    std::vector<Edge> edges( edgeCount );
    const std::uint32_t hotNodeCount = std::max<std::uint32_t>( 1, nodeCount / 64 );
    for( Edge& e : edges )
    {
        const bool hotSource = ( rng() & 7u ) != 0u;
        e.from = hotSource ? std::uint32_t( rng() % hotNodeCount ) : std::uint32_t( rng() % nodeCount );
        e.to   = std::uint32_t( rng() % nodeCount );
        e.w    = float( ( rng() & 15u ) + 1u );
    }
    return edges;
}

static std::vector<Edge> makeNearlySortedEdges( std::size_t edgeCount, std::uint32_t nodeCount )
{
    std::vector<Edge> edges = makeRandomEdges( edgeCount, nodeCount );
    std::vector<Edge> scratch;
    ctx::sortutil::radixSortByFromTo( edges, scratch );

    std::mt19937_64 rng( 0xA11CE5ull );
    const std::size_t swapCount = std::max<std::size_t>( 1, edgeCount / 200 );
    for( std::size_t i = 0; i < swapCount; ++i )
    {
        const std::size_t a = rng() % edgeCount;
        const std::size_t b = rng() % edgeCount;
        std::swap( edges[ a ], edges[ b ] );
    }
    return edges;
}

template<class Sorter>
static double runSorter( std::string_view name, const std::vector<Edge>& base, const std::vector<Edge>& expected, Sorter&& sorter )
{
    constexpr int kRuns = 3;
    std::vector<double> times;
    times.reserve( kRuns );
    for( int run = 0; run < kRuns; ++run )
    {
        std::vector<Edge> v = base;
        const double ms = timedMs( [ & ] { sorter( v ); } );
        if( !isSorted( v ) )
        {
            std::fprintf( stderr, "sort failed: %.*s produced unsorted output\n", int( name.size() ), name.data() );
            std::exit( 2 );
        }
        if( !sameSortedOutput( v, expected ) )
        {
            std::fprintf( stderr, "sort failed: %.*s output mismatch\n", int( name.size() ), name.data() );
            std::exit( 2 );
        }
        times.push_back( ms );
    }
    return median( times );
}

static void benchCase( std::string_view caseName, const std::vector<Edge>& base )
{
    std::vector<Edge> sorted = base;
    std::sort( sorted.begin(), sorted.end(), ctx::sortutil::lessByFromTo<Edge> );

    const double stdMs = runSorter( "std::sort", base, sorted,
                                    []( std::vector<Edge>& v )
                                    {
                                        std::sort( v.begin(), v.end(), ctx::sortutil::lessByFromTo<Edge> );
                                    } );
    const double pdqMs = runSorter( "pdqsort", base, sorted,
                                    []( std::vector<Edge>& v )
                                    {
                                        infra::sort::unstable( v.begin(), v.end(), ctx::sortutil::lessByFromTo<Edge> );
                                    } );
    const double radixMs = runSorter( "edge-radix", base, sorted,
                                      []( std::vector<Edge>& v )
                                      {
                                          std::vector<Edge> scratch;
                                          ctx::sortutil::radixSortByFromTo( v, scratch );
                                      } );

    std::printf( "%-15.*s std %8.3f ms | pdq %8.3f ms (%5.2fx std) | radix %8.3f ms (%5.2fx std)\n",
                 int( caseName.size() ), caseName.data(),
                 stdMs, pdqMs, stdMs / pdqMs, radixMs, stdMs / radixMs );
}

static std::vector<float> makeRandomScores( std::size_t scoreCount )
{
    std::mt19937_64 rng( 0x5C02E5ull );
    std::vector<float> scores( scoreCount );
    for( float& s : scores )
        s = float( rng() & 0x00ffffffu ) / float( 0x01000000u );
    return scores;
}

static std::vector<float> makeTiedScores( std::size_t scoreCount )
{
    std::mt19937_64 rng( 0x7105E5ull );
    std::vector<float> scores( scoreCount );
    for( float& s : scores )
        s = float( rng() % 4096u );
    return scores;
}

template<class Sorter>
static double runScoreSorter( std::string_view name, const std::vector<float>& scores, const std::vector<std::uint32_t>& expected, Sorter&& sorter )
{
    constexpr int kRuns = 3;
    std::vector<double> times;
    times.reserve( kRuns );
    for( int run = 0; run < kRuns; ++run )
    {
        std::vector<std::uint32_t> order( scores.size() );
        for( std::uint32_t i = 0; i < order.size(); ++i ) order[ i ] = i;
        const double ms = timedMs( [ & ] { sorter( order ); } );
        if( order != expected )
        {
            std::fprintf( stderr, "score sort failed: %.*s output mismatch\n", int( name.size() ), name.data() );
            std::exit( 2 );
        }
        times.push_back( ms );
    }
    return median( times );
}

static void benchScoreCase( std::string_view caseName, const std::vector<float>& scores )
{
    std::vector<std::uint32_t> expected( scores.size() );
    for( std::uint32_t i = 0; i < expected.size(); ++i ) expected[ i ] = i;
    std::sort( expected.begin(), expected.end(),
               [ &scores ]( std::uint32_t a, std::uint32_t b ) noexcept { return ctx::sortutil::lessByScoreDescId( scores, a, b ); } );

    const double stdMs = runScoreSorter( "std::sort.score", scores, expected,
                                         [ &scores ]( std::vector<std::uint32_t>& order )
                                         {
                                             std::sort( order.begin(), order.end(),
                                                        [ &scores ]( std::uint32_t a, std::uint32_t b ) noexcept
                                                        { return ctx::sortutil::lessByScoreDescId( scores, a, b ); } );
                                         } );
    const double pdqMs = runScoreSorter( "pdqsort.score", scores, expected,
                                         [ &scores ]( std::vector<std::uint32_t>& order )
                                         {
                                             infra::sort::unstable( order.begin(), order.end(),
                                                                    [ &scores ]( std::uint32_t a, std::uint32_t b ) noexcept
                                                                    { return ctx::sortutil::lessByScoreDescId( scores, a, b ); } );
                                         } );
    const double radixMs = runScoreSorter( "score-radix", scores, expected,
                                           [ &scores ]( std::vector<std::uint32_t>& order )
                                           {
                                               std::vector<std::uint32_t> scratch;
                                               ctx::sortutil::radixSortByScoreDescId( order, scores, scratch );
                                           } );

    std::printf( "%-15.*s std %8.3f ms | pdq %8.3f ms (%5.2fx std) | radix %8.3f ms (%5.2fx std)\n",
                 int( caseName.size() ), caseName.data(),
                 stdMs, pdqMs, stdMs / pdqMs, radixMs, stdMs / radixMs );
}

int main( int argc, char** argv )
{
    const std::size_t edgeCount = argc >= 2 ? std::strtoull( argv[ 1 ], nullptr, 10 ) : 2'000'000ull;
    const std::uint32_t nodeCount = std::uint32_t( std::max<std::size_t>( 1024, edgeCount / 8 ) );
    const double payloadMiB = double( edgeCount * sizeof( Edge ) ) / ( 1024.0 * 1024.0 );
    std::printf( "ripwire edge sort large-N: %zu edges, %u nodes, %.1f MiB edge array (scratch doubles radix working set)\n",
                 edgeCount, nodeCount, payloadMiB );

    benchCase( "random", makeRandomEdges( edgeCount, nodeCount ) );
    benchCase( "graph-like", makeGraphLikeEdges( edgeCount, nodeCount ) );
    benchCase( "nearly-sorted", makeNearlySortedEdges( edgeCount, nodeCount ) );

    std::printf( "\nripwire score sort large-N: %zu ids, %.1f MiB score array\n",
                 edgeCount, double( edgeCount * sizeof( float ) ) / ( 1024.0 * 1024.0 ) );
    benchScoreCase( "score-random", makeRandomScores( edgeCount ) );
    benchScoreCase( "score-tied", makeTiedScores( edgeCount ) );

    return 0;
}
