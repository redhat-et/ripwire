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

static rw::FileClosureOptions forced( std::uint32_t bits, std::uint64_t hashMask = ~std::uint64_t( 0 ) )
{
    rw::FileClosureOptions o;
    o.chunkBits = bits;
    o.hashMask  = hashMask;
    return o;
}

static bool stopNow() noexcept { return true; }

static void shape( const char* name, const Rows& adj )
{
    const Rows want = oracle( adj );
    bool       ok   = true;
    for( const std::uint32_t bits : { 16u, 12u, 10u, 8u, 4u, 2u } )
    {
        ok = ok && agrees( rw::buildFileClosure( adj, forced( bits ) ), want );
        ok = ok && agrees( rw::buildFileClosure( adj, forced( bits, 0 ) ), want );   // every row on one hash: only the verify shares
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

    // A row ORed from far-apart words in descending order: the working row sorts the words it touched, so the row is still
    // ascending. 2,000 files are 32 words, and a row that touches two of them is read from the touched list, not by a scan.
    {
        Rows adj( 2000 );
        adj[0] = { 1900, 5 };
        adj[7] = { 1999, 1000, 64 };
        shape( "far-apart ids listed high first: the touched words are sorted", adj );
    }

    // A cycle in a wide universe, so its row is a sorted-array chunk, not a bitset: the walk's other branch skips self too.
    {
        Rows adj( 300 );
        adj[10] = { 20 };
        adj[20] = { 10, 30 };
        shape( "cycle whose row is a sorted array", adj );
    }

    // The universe's last chunk is truncated, and its bitset takes only the words the universe needs.
    {
        const rw::FileSetStore s = rw::buildFileClosure( Rows{ { 1, 2 }, { 2 }, {} }, forced( 8 ) );
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
        const rw::FileSetStore s8 = rw::buildFileClosure( adj, forced( 8 ) );
        const rw::FileSetStore s2 = rw::buildFileClosure( adj, forced( 2 ) );
        check( s8.arrayChunkCount() > 0 && s8.arrayChunkCount() < s8.chunkCount(), "non-vacuous: 8-bit chunks hold both arrays and bitsets" );
        check( s2.chunkCount() > s2.rowCount(), "non-vacuous: rows cross chunks at 2 bits" );
        check( s8.rowCount() < 1200 / 2, "identical rows and a cycle's members share one row" );
        const rw::FileSetStore a = rw::buildFileClosure( adj );
        const rw::FileSetStore b = rw::buildFileClosure( adj );
        check( a.chunkBits() == b.chunkBits() && a.bytes() == b.bytes() && a.rowCount() == b.rowCount(), "built twice: same chunk size, rows and bytes" );
    }

    // Two rows with one hash must not share: the same size and chunk count, different lows, and the hash forced to ONE value
    // so only the verify can tell them apart. An equal row still shares. Without the verify the second row would join the first.
    {
        rw::FileSetBuilder  b( 1024, 3, 8, /*hashMask=*/0 );
        const std::uint32_t r1[] = { 1, 2, 300 }, r2[] = { 1, 3, 300 };
        const std::uint32_t x = b.addSorted( r1, 3 ), y = b.addSorted( r2, 3 ), z = b.addSorted( r1, 3 );
        check( x != y, "builder: two rows on one hash do not share (the verify decides, not the hash)" );
        check( x == z, "builder: an equal row on the same hash shares" );
        // The seam is live, not ignored: the collided row y was never registered, so a second copy of it cannot share with it.
        // That is the whole cost of a collision (a lost share, never a wrong one).
        const std::uint32_t w = b.addSorted( r2, 3 );
        check( w != y, "builder: the hash seam forces collisions (a row that collided is not registered, so its copy does not share)" );
        rw::FileSetBuilder  c( 1024, 3, 8 );
        const std::uint32_t cx = c.addSorted( r1, 3 ), cy = c.addSorted( r2, 3 ), cw = c.addSorted( r2, 3 );
        check( cx != cy && cy == cw, "builder: on the real hash different rows differ and a copy shares" );
    }

    // The umbrella: one file imports every module, each module imports a leaf of its own. A component's row used to be held
    // until its last reader, so the fold held a bitset per module (universe / 8 bytes each): N^2 / 32 bytes. The fold now holds
    // one working row, ORed from the stored rows; the arm fails on any frontier that grows with the umbrella's fan-out.
    {
        const auto umbrella = []( std::uint32_t modules, bool umbrellaLast )
        {
            const std::uint32_t N = 2 * modules + 1;
            Rows                adj( N );
            const std::uint32_t top = umbrellaLast ? N - 1 : 0, first = umbrellaLast ? 0 : 1;
            for( std::uint32_t m = 0; m < modules; ++m )
            {
                adj[top].push_back( first + 2 * m );
                adj[first + 2 * m] = { first + 2 * m + 1 };
            }
            return adj;
        };
        shape( "umbrella of 60 modules, umbrella first", umbrella( 60, false ) );
        shape( "umbrella of 60 modules, umbrella last", umbrella( 60, true ) );
        constexpr std::uint32_t M = 10000, N = 2 * M + 1;
        const Rows              adj = umbrella( M, false );
        rw::FileClosureStats    st;
        rw::FileClosureOptions  o;
        o.stats = &st;
        const rw::FileSetStore s = rw::buildFileClosure( adj, o );
        bool                   ok = s.setSize( 0 ) == 2 * M && s.setSize( 1 ) == 1 && s.setSize( 2 * M ) == 0 && s.contains( 0, 2 * M ) && !s.contains( 1, 3 );
        for( std::uint32_t m = 0; m < M && ok; m += 97 )
        {
            ok = s.contains( 0, 1 + 2 * m ) && s.contains( 0, 2 + 2 * m ) && s.contains( 1 + 2 * m, 2 + 2 * m ) && s.setSize( 1 + 2 * m ) == 1;
        }
        check( ok, "umbrella of 10,000 modules: the umbrella reaches all 20,000, each module reaches its own leaf" );
        check( st.stop == rw::FileGraphStop::None, "umbrella: the fold did not stop" );
        // The frontier of the first form here was ~10,000 rows x N / 8 bytes = 25 MB; one working row is N / 8 = 2.5 KB.
        check( st.workPeakBytes <= 4 * ( std::size_t( N ) / 8 ), "umbrella: the fold's working set stays a few rows, whatever the fan-out" );
    }

    // The stop callback: asked after kFoldCheckComponents components; a true answer stops the fold, says why, and the store is partial.
    {
        constexpr std::uint32_t N = rw::kFoldCheckComponents + 100;
        Rows                    adj( N );
        for( std::uint32_t i = 0; i + 1 < N; ++i )
        {
            adj[i] = { i + 1 };
        }
        rw::FileClosureStats   st;
        rw::FileClosureOptions o;
        o.stats      = &st;
        o.shouldStop = &stopNow;
        const rw::FileSetStore s = rw::buildFileClosure( adj, o );
        check( st.stop == rw::FileGraphStop::MemoryLimit && st.checks == 1, "stop callback: a true answer stops the fold, once, and says why" );
        check( s.fileCount() == N, "stop callback: the partial store still answers within its universe" );
        rw::FileClosureStats   st2;
        o.stats      = &st2;
        o.shouldStop = nullptr;
        (void)rw::buildFileClosure( adj, o );
        check( st2.stop == rw::FileGraphStop::None && st2.checks == 0, "no callback: no stop, no check" );
    }

    // A u32 chunk offset must never wrap. The real limit is 2^32 - 1 payload words (8 GiB), too big to run, so the limit is a
    // parameter: exactly the payload fits, one word less stops the fold at the row that would pass it, and nothing wraps.
    {
        constexpr std::uint32_t N = 600;
        Rows                    adj( N );
        for( std::uint32_t i = 0; i + 1 < N; ++i )
        {
            adj[i] = { i + 1 };
        }
        const std::uint64_t words = rw::buildFileClosure( adj, forced( 8 ) ).payloadBytes() / 2;
        rw::FileClosureStats   st;
        rw::FileClosureOptions o = forced( 8 );
        o.stats     = &st;
        o.wordLimit = words;
        const rw::FileSetStore fits = rw::buildFileClosure( adj, o );
        check( st.stop == rw::FileGraphStop::None && agrees( fits, oracle( adj ) ), "capacity: a payload exactly at the limit fits and is exact" );
        o.wordLimit = words - 1;
        const rw::FileSetStore cut = rw::buildFileClosure( adj, o );
        check( st.stop == rw::FileGraphStop::Capacity, "capacity: one word past the limit stops the fold, disclosed" );
        check( cut.payloadBytes() / 2 <= words - 1 && cut.fileCount() == N, "capacity: the partial store holds no payload past the limit" );
    }

    // The reserve is an estimate that sharing can make huge: a million-file graph that is one cycle stores ONE row.
    {
        const rw::FileSetChunkChoice sample{ 16, 64 * 16, std::size_t( 64 ) * 16 * 4096 };   // 64 sample rows, each a full 1 M-file bitset
        const rw::FileSetReservePlan one = rw::fileSetReservePlan( sample, 64, 1 );
        check( one.rows == 2 && one.words < 2 * 16 * 4096 + 8 && one.chunks < 64, "reserve: one giant cycle reserves one row, not one per file" );
        const rw::FileSetReservePlan many = rw::fileSetReservePlan( sample, 64, 1000000000 );   // far past any real graph
        check( many.words == rw::kReserveMaxWords && many.chunks == rw::kReserveMaxChunks && many.rows == 1000000001, "reserve: a huge estimate is clamped; the arrays grow past it" );
        const rw::FileSetReservePlan chain = rw::fileSetReservePlan( { 10, 64 * 49, std::size_t( 64 ) * 3125 }, 64, 100000 );   // mean closure 50,000: 49 chunks, 3,125 words
        check( chain.words < rw::kReserveMaxWords, "reserve: a 100,000-file chain (654 MB of payload) is not clamped, so it never grows by doubling" );
        check( rw::fileSetReservePlan( sample, 0, 5 ).words == 0, "reserve: no sample, no payload reserve" );
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
        rw::FileAdjacency moved( std::move( d ) );
        check( d.size() == 0 && d.empty() && moved.size() == 4, "adjacency: a moved-from adjacency is empty, not a count of rows it no longer has" );
        // 2^32 - 1 edges is 16 GB of targets, so the limit is a parameter; one edge over it throws, and no adjacency exists to read.
        bool          threw = false;
        rw::FileGraphStop cause = rw::FileGraphStop::None;
        try
        {
            const rw::FileAdjacency over = rw::FileAdjacency::fromEdges( 4, from, to, false, from.size() - 1 );
            (void)over;
        }
        catch( const rw::FileGraphStopped& stopped )
        {
            threw = true;
            cause = stopped.why();
        }
        check( threw && cause == rw::FileGraphStop::Capacity, "adjacency: past the edge limit the build fails with FileGraphStopped(Capacity); no partial adjacency is returned" );
        const rw::FileAdjacency at = rw::FileAdjacency::fromEdges( 4, from, to, false, from.size() );
        check( at.edgeCount() == 5, "adjacency: exactly the limit is stored" );
    }
    std::printf( "fileset_unit: %s\n", g_fail == 0 ? "PASS" : "FAIL" );
    return g_fail == 0 ? 0 : 1;
}
