// test/fileset_unit.cpp: the file graph's two stores against an independent oracle (test/filesetcheck.sh).
// The oracle is a fixpoint mark sweep over nested vectors: no fold, no epoch stamp, no store layout in common with the code
// under test. Every shape runs at chunk sizes 16, 12, 10, 8, 4 and 2, and through the sampled choice.
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <vector>

#include "infra/fileSetStore.h"

using Rows = std::vector<std::vector<std::uint32_t>>;
static int g_fail = 0;
static void check( bool ok, const char* what )
{
    std::printf( "  %s  %s\n", ok ? "PASS" : "FAIL", what );
    g_fail += ok ? 0 : 1;
}

static Rows oracle( const Rows& adj )
{
    const std::uint32_t F = std::uint32_t( adj.size() );
    Rows                out( F );
    for( std::uint32_t s = 0; s < F; ++s )
    {
        std::vector<char> reach( F, 0 );
        reach[s]     = 2;   // the seed; reached again only over a cycle, and a file is never in its own set
        bool changed = true;
        while( changed )
        {
            changed = false;
            for( std::uint32_t v = 0; v < F; ++v )
            {
                if( reach[v] == 0 )
                {
                    continue;
                }
                for( const std::uint32_t w : adj[v] )
                {
                    if( w < F && reach[w] == 0 )
                    {
                        reach[w] = 1;
                        changed  = true;
                    }
                }
            }
        }
        for( std::uint32_t v = 0; v < F; ++v )
        {
            if( reach[v] == 1 )
            {
                out[s].push_back( v );
            }
        }
    }
    return out;
}

// True when every read of `st` agrees with the oracle: walk order, membership of every (file, id), size, emptiness.
static bool agrees( const rw::FileSetStore& st, const Rows& want )
{
    const std::uint32_t F = std::uint32_t( want.size() );
    if( st.fileCount() != F )
    {
        return false;
    }
    std::vector<std::uint32_t> got;
    for( std::uint32_t f = 0; f < F; ++f )
    {
        got.clear();
        st.forEach( f, [ & ]( std::uint32_t id ) { got.push_back( id ); } );
        if( got != want[f] || st.empty( f ) != want[f].empty() || st.setSize( f ) != want[f].size() )
        {
            return false;
        }
        for( std::uint32_t id = 0; id < F + 2; ++id )
        {
            if( st.contains( f, id ) != std::binary_search( want[f].begin(), want[f].end(), id ) )
            {
                return false;
            }
        }
    }
    return !st.contains( F, 0 ) && st.empty( F ) && st.setSize( F ) == 0;
}

static void shape( const char* name, const Rows& adj )
{
    const Rows want = oracle( adj );
    bool       ok   = true;
    for( const std::uint32_t bits : { 16u, 12u, 10u, 8u, 4u, 2u } )
    {
        ok = ok && agrees( rw::buildFileClosure( adj, bits ), want );
    }
    ok = ok && agrees( rw::buildFileClosure( adj ), want );
    check( ok, name );
}

int main()
{
    shape( "empty graph", {} );
    shape( "one file, no edges", { {} } );
    shape( "no edges at all", Rows( 300 ) );
    shape( "chain a -> b -> c", { { 1 }, { 2 }, {} } );
    shape( "diamond: two paths to one file, listed once", { { 1, 2 }, { 3 }, { 3 }, {} } );
    shape( "two-file cycle: each holds the other, neither itself", { { 1 }, { 0 } } );
    shape( "cycle with a tail and an entry", { { 1 }, { 2 }, { 3, 1 }, { 4 }, {} } );
    shape( "self edge: not a member, and the row stays empty", { { 0 }, { 1, 2 }, {} } );
    shape( "duplicate ids in a row", { { 1, 1, 2, 1 }, { 2, 2 }, {} } );
    shape( "unsorted row, directive order", { { 2, 1 }, { 3 }, { 1, 3 }, {} } );
    shape( "out-of-range ids contribute nothing", { { 7, 1, 99999 }, { 2, 4000000000u }, {} } );

    // A cycle in a wide universe, so its row is a sorted-array chunk, not a bitset: the walk's other branch skips self too.
    {
        Rows adj( 300 );
        adj[10] = { 20 };
        adj[20] = { 10, 30 };
        shape( "cycle whose row is a sorted array", adj );
    }

    // The universe's last chunk is truncated, and its bitset takes only the words the universe needs.
    {
        const rw::FileSetStore s = rw::buildFileClosure( Rows{ { 1, 2 }, { 2 }, {} }, 8 );
        check( s.payloadBytes() == 2 * 2, "a truncated chunk's bitset is one word, not a full chunk's sixteen" );
    }

    // Large, scrambled: closures with no sorted discovery order, a dense region and a sparse tail, so both chunk forms live.
    {
        constexpr std::uint32_t N = 1200;
        Rows                    adj( N );
        for( std::uint32_t i = 0; i < N; ++i )
        {
            if( i < 400 )
            {
                adj[i] = { ( i * 7 + 13 ) % 400, ( i * 29 + 5 ) % 400 };   // one big tangle
            }
            else if( i % 3 == 0 )
            {
                adj[i] = { ( i * i * 31 + i * 17 ) % N, i - 1 };
            }
        }
        shape( "1,200 files: a cycle-heavy tangle and a sparse tail", adj );
        const rw::FileSetStore s8 = rw::buildFileClosure( adj, 8 );
        const rw::FileSetStore s2 = rw::buildFileClosure( adj, 2 );
        check( s8.arrayChunkCount() > 0 && s8.arrayChunkCount() < s8.chunkCount(), "non-vacuous: 8-bit chunks hold both arrays and bitsets" );
        check( s2.chunkCount() > s2.rowCount(), "non-vacuous: rows cross chunks at 2 bits" );
        check( s8.rowCount() < 1200 / 2, "identical rows and a cycle's members share one row" );
        const rw::FileSetStore a = rw::buildFileClosure( adj );
        const rw::FileSetStore b = rw::buildFileClosure( adj );
        check( a.chunkBits() == b.chunkBits() && a.bytes() == b.bytes() && a.rowCount() == b.rowCount(), "built twice: same chunk size, rows and bytes" );
    }

    // Two rows with one hash must not share: identical size and chunk count, different lows.
    {
        rw::FileSetBuilder  b( 1024, 3, 8 );
        const std::uint32_t r1[] = { 1, 2, 300 }, r2[] = { 1, 3, 300 };
        const std::uint32_t x    = b.addSorted( r1, 3 ), y = b.addSorted( r2, 3 ), z = b.addSorted( r1, 3 );
        check( x != y && x == z, "builder: an equal row shares, a different one does not" );
    }

    // FileAdjacency: rows keep edge order and duplicates, dedup sorts, retainRows compacts, an unlisted file has an empty row.
    {
        const std::vector<std::uint32_t> from = { 2, 0, 2, 2, 0 }, to = { 9, 5, 1, 7, 5 };
        const rw::FileAdjacency          raw  = rw::FileAdjacency::fromEdges( 4, from, to, false );
        const auto                       eq   = []( std::span<const std::uint32_t> r, std::vector<std::uint32_t> w ) { return std::ranges::equal( r, w ); };
        check( raw.size() == 4 && eq( raw[0], { 5, 5 } ) && eq( raw[1], {} ) && eq( raw[2], { 9, 1, 7 } ) && eq( raw[3], {} ), "adjacency: un-deduped rows keep directive order" );
        rw::FileAdjacency d = rw::FileAdjacency::fromEdges( 4, from, to, true );
        check( eq( d[0], { 5 } ) && eq( d[2], { 1, 7, 9 } ) && d.edgeCount() == 4, "adjacency: deduped rows are sorted, duplicate-free" );
        d.retainRows( []( std::uint32_t f, std::span<std::uint32_t> row )
        {
            std::size_t kept = 0;
            for( const std::uint32_t id : row )
            {
                if( f == 2 && id == 1 )
                {
                    continue;
                }
                row[kept++] = id;
            }
            return kept;
        } );
        check( eq( d[0], { 5 } ) && eq( d[1], {} ) && eq( d[2], { 7, 9 } ) && d.edgeCount() == 3, "adjacency: retainRows shrinks one row and moves the rest" );
        check( rw::FileAdjacency().size() == 0 && rw::FileAdjacency( 3 ).edgeCount() == 0, "adjacency: empty forms" );
    }
    std::printf( "fileset_unit: %s\n", g_fail == 0 ? "PASS" : "FAIL" );
    return g_fail == 0 ? 0 : 1;
}
