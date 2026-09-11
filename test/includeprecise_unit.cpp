// includeprecise_unit.cpp — P1 unit driver for the PURE path-precise include functions in resolve.h
// (resolvePreciseInclude / lexicalNormalize / buildPreciseIncludeAdj / transitiveIncludeSet). These are
// dead-but-tested at P1 (nothing in buildGraph consumes them yet), so this standalone driver exercises
// them directly against a real ingest() of test/includeprecisefix. Compiled + run by includeprecisecheck.sh.
//
// Prints "UNIT ALL PASS" on success; on any failure prints "UNIT FAIL: <what>" and exits non-zero.

#include "../src/model.h"
#include "../src/ingest.h"
#include "../src/resolve.h"

#include <algorithm>
#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

using namespace rw;

static int g_fail = 0;
static void check( bool cond, const char* what )
{
    if( cond )
    {
        std::printf( "  PASS  %s\n", what );
    }
    else
    {
        std::printf( "  FAIL  %s\n", what );
        g_fail = 1;
    }
}

// find a fileId whose stored path ENDS WITH `suffix` (paths are `<root>/<rel>`); kNoFile if none / >1.
static std::uint32_t fileEndingWith( const IngestResult& ing, std::string_view suffix )
{
    std::uint32_t hit = kNoFile;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        std::string_view p = ing.files[f];
        if( p.size() >= suffix.size() && p.compare( p.size() - suffix.size(), suffix.size(), suffix ) == 0 )
        {
            hit = ( hit == kNoFile ) ? f : 0xFFFFFFFEu;   // 0xFFFFFFFE = ambiguous-suffix marker
        }
    }
    return hit;
}

int main( int argc, char** argv )
{
    if( argc < 2 ) { std::printf( "UNIT FAIL: usage: %s <fixtureDir>\n", argv[0] ); return 2; }
    const IngestResult ing = ingest( argv[1] );

    // ── locate the fixture files by suffix (root-spelling-agnostic) ──────────────────────────────
    const std::uint32_t rootGeom = fileEndingWith( ing, "includeprecisefix/geometry.h" );
    const std::uint32_t otherGeom = fileEndingWith( ing, "includeprecisefix/other/geometry.h" );
    const std::uint32_t consumer = fileEndingWith( ing, "includeprecisefix/sub/consumer.cpp" );
    const std::uint32_t aH = fileEndingWith( ing, "includeprecisefix/a.h" );
    const std::uint32_t bH = fileEndingWith( ing, "includeprecisefix/b.h" );
    const std::uint32_t cH = fileEndingWith( ing, "includeprecisefix/c.h" );
    check( rootGeom < ing.files.size() && otherGeom < ing.files.size() && consumer < ing.files.size()
           && aH < ing.files.size() && bH < ing.files.size() && cH < ing.files.size(),
           "fixture files all located (root+other geometry.h, sub/consumer.cpp, a/b/c.h)" );

    // build the path→fileId index the resolver uses (exact ing.files spelling)
    HashMap<std::string, std::uint32_t> fileIndex;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        fileIndex.emplace( ing.files[f], f );
    }

    // ── (a) `#include "../geometry.h"` from sub/ resolves to the ROOT geometry.h, NOT the decoy ──
    const std::string consumerPath = ing.files[ consumer ];
    const std::uint32_t r1 = resolvePreciseInclude( consumerPath, "../geometry.h", /*isAngle=*/false, fileIndex );
    check( r1 == rootGeom, "quote `../geometry.h` from sub/ resolves to the ONE real root geometry.h" );
    check( r1 != otherGeom, "quote `../geometry.h` does NOT match the same-basename decoy in other/" );

    // ── (b) a `..`-escape ABOVE the crawl root → unresolved ──────────────────────────────────────
    const std::uint32_t rEsc = resolvePreciseInclude( consumerPath, "../../../../../../etc/passwd", false, fileIndex );
    check( rEsc == kNoFile, "`..`-escape above the crawl root → kNoFile (unresolved, no guess)" );

    // ── (c) an angle include → unresolved (never basename-matched) ───────────────────────────────
    const std::uint32_t rAng = resolvePreciseInclude( consumerPath, "geometry.h", /*isAngle=*/true, fileIndex );
    check( rAng == kNoFile, "angle `<geometry.h>` → kNoFile (external/unresolvable, never matched)" );
    const std::uint32_t rAngV = resolvePreciseInclude( consumerPath, "vector", /*isAngle=*/true, fileIndex );
    check( rAngV == kNoFile, "angle `<vector>` (not in repo) → kNoFile" );

    // a quote include that resolves nowhere (typo) → unresolved, no basename fallback
    const std::uint32_t rMiss = resolvePreciseInclude( consumerPath, "nonesuch.h", false, fileIndex );
    check( rMiss == kNoFile, "quote miss `nonesuch.h` → kNoFile (no basename fallback)" );

    // ── (d) transitive closure over the 3-file chain a.h -> b.h -> c.h ───────────────────────────
    const auto adj   = buildPreciseIncludeAdj( ing );
    const auto trans = transitiveIncludeSet( adj );
    const auto has   = []( const std::vector<NodeId>& v, std::uint32_t x )
    { for( NodeId n : v ) { if( n == x ) { return true; } } return false; };

    check( aH < trans.size() && has( trans[aH], bH ) && has( trans[aH], cH ),
           "transitive closure: a.h reaches BOTH b.h and c.h (3-file chain)" );
    check( !has( trans[aH], aH ), "transitive closure: a.h does NOT include itself" );
    check( has( trans[bH], cH ) && !has( trans[bH], aH ),
           "transitive closure: b.h reaches c.h but not a.h (direction respected)" );

    // ── (d2) POSTCONDITION over EVERY closure: sorted ascending, and duplicate-free ──────────────
    // `trans[f]` is consumed by std::binary_search (rule3IncludeFile), so ASCENDING ORDER is the
    // contract, not a nicety. Duplicate-freedom is the separate invariant the epoch stamp in the walk
    // already guarantees — asserted here so that guarantee is checked by a gate rather than assumed by
    // a reader. Both arms run over every file in the fixture, including the diamond and the cycle below.
    {
        bool allSorted = true, allUnique = true;
        std::size_t worstFile = 0;
        for( std::size_t f = 0; f < trans.size(); ++f )
        {
            if( !std::is_sorted( trans[f].begin(), trans[f].end() ) )
            {
                allSorted = false; worstFile = f;
            }
            if( std::adjacent_find( trans[f].begin(), trans[f].end() ) != trans[f].end() )
            {
                allUnique = false; worstFile = f;
            }
        }
        check( allSorted, "closure postcondition: EVERY trans[f] is sorted ascending (binary_search contract)" );
        check( allUnique, "closure postcondition: EVERY trans[f] is duplicate-free (epoch-stamp invariant)" );
        (void)worstFile;
    }

    // ── (d3) DIAMOND: two distinct paths reach the same file — the duplicate-producing shape ──────
    // diamond/top.h includes left.h and right.h; BOTH include shared.h. A walk without the epoch stamp
    // would append shared.h twice. This is the population that makes the uniqueness arm above non-vacuous.
    {
        const std::uint32_t top    = fileEndingWith( ing, "includeprecisefix/diamond/top.h" );
        const std::uint32_t left   = fileEndingWith( ing, "includeprecisefix/diamond/left.h" );
        const std::uint32_t right  = fileEndingWith( ing, "includeprecisefix/diamond/right.h" );
        const std::uint32_t shared = fileEndingWith( ing, "includeprecisefix/diamond/shared.h" );
        check( top < trans.size() && left < trans.size() && right < trans.size() && shared < trans.size(),
               "diamond fixture located (top/left/right/shared)" );
        if( top < trans.size() && shared < trans.size() )
        {
            const std::size_t sharedCount = std::size_t( std::count( trans[top].begin(), trans[top].end(), NodeId( shared ) ) );
            check( sharedCount == 1, "diamond: top.h reaches shared.h EXACTLY ONCE despite two distinct paths" );
            check( has( trans[top], left ) && has( trans[top], right ), "diamond: top.h reaches both left.h and right.h" );
        }
    }

    // ── (d4) CYCLE: mutually-including headers terminate, and neither lands in its own set ────────
    {
        const std::uint32_t pH = fileEndingWith( ing, "includeprecisefix/cyc/p.h" );
        const std::uint32_t qH = fileEndingWith( ing, "includeprecisefix/cyc/q.h" );
        check( pH < trans.size() && qH < trans.size(), "cycle fixture located (cyc/p.h, cyc/q.h)" );
        if( pH < trans.size() && qH < trans.size() )
        {
            check( has( trans[pH], qH ) && has( trans[qH], pH ), "cycle: p.h and q.h each reach the other" );
            check( !has( trans[pH], pH ) && !has( trans[qH], qH ), "cycle: neither file lands in its OWN closure" );
        }
    }

    // ── (d5) LARGE-N arm: closures above the radix threshold, against an INDEPENDENT oracle ───────
    // THE FIXTURE CANNOT REACH THIS CODE PATH. Every closure above is under ten elements, so a
    // size-routed sort inside transitiveIncludeSet would take its small-input branch on all of them and
    // the large-input branch would be gated by nothing at all (CONTRIBUTING.md §2, shape 1: a population
    // that cannot contain the defect). transitiveIncludeSet is a pure function of `adj`, so this arm
    // hands it a synthetic 400-node graph directly. The adjacency is a deliberately SCRAMBLED expander
    // (i*7+13, i*29+5, i*101+61 mod N) so discovery order is nowhere near sorted order — a chain would
    // arrive pre-sorted and prove nothing about the sort at all. The oracle is an independent
    // mark-and-sweep reachability, written differently from the code under test.
    {
        constexpr std::uint32_t N = 400;
        std::vector<std::vector<std::uint32_t>> synth( N );
        for( std::uint32_t i = 0; i < N; ++i )
        {
            synth[i] = { ( i * 7 + 13 ) % N, ( i * 29 + 5 ) % N, ( i * 101 + 61 ) % N };
            std::sort( synth[i].begin(), synth[i].end() );
            synth[i].erase( std::unique( synth[i].begin(), synth[i].end() ), synth[i].end() );
        }
        const auto got = transitiveIncludeSet( synth );

        bool bigEnough = false, matches = true, sortedAll = true, uniqueAll = true;
        std::size_t maxClosure = 0;
        for( std::uint32_t s0 = 0; s0 < N; ++s0 )
        {
            // independent oracle: iterate-to-fixpoint mark sweep, then materialise ascending by scan.
            std::vector<char> reach( N, 0 );
            reach[s0] = 2;                              // 2 = seed (excluded from the answer)
            bool changed = true;
            while( changed )
            {
                changed = false;
                for( std::uint32_t v = 0; v < N; ++v )
                {
                    if( reach[v] == 0 ) { continue; }
                    for( std::uint32_t w : synth[v] )
                    {
                        if( reach[w] == 0 ) { reach[w] = 1; changed = true; }
                    }
                }
            }
            std::vector<std::uint32_t> want;
            for( std::uint32_t v = 0; v < N; ++v ) { if( reach[v] == 1 ) { want.push_back( v ); } }

            const std::vector<NodeId>& have = got[s0];
            maxClosure = std::max( maxClosure, have.size() );
            if( have.size() >= 128 ) { bigEnough = true; }
            if( !std::is_sorted( have.begin(), have.end() ) ) { sortedAll = false; }
            if( std::adjacent_find( have.begin(), have.end() ) != have.end() ) { uniqueAll = false; }
            if( have.size() != want.size() ) { matches = false; }
            else { for( std::size_t k = 0; k < want.size(); ++k ) { if( have[k] != want[k] ) { matches = false; break; } } }
        }
        std::printf( "  INFO  synthetic closure max=%zu (radix path needs >=128)\n", maxClosure );
        check( bigEnough,  "large-N arm is NON-VACUOUS: at least one synthetic closure exceeds the radix threshold" );
        check( sortedAll,  "large-N: every synthetic closure is sorted ascending" );
        check( uniqueAll,  "large-N: every synthetic closure is duplicate-free" );
        check( matches,    "large-N: every synthetic closure equals an INDEPENDENT mark-sweep oracle, element for element" );
    }

    // ── determinism: build the set twice, identical ──────────────────────────────────────────────
    const auto trans2 = transitiveIncludeSet( buildPreciseIncludeAdj( ing ) );
    bool identical = ( trans.size() == trans2.size() );
    for( std::size_t f = 0; identical && f < trans.size(); ++f )
    {
        identical = ( trans[f] == trans2[f] );
    }
    check( identical, "transitive closure deterministic (built twice, byte-identical)" );

    // ── lexicalNormalize edge cases (the sharp `.`/`..` collapsing) ──────────────────────────────
    check( lexicalNormalize( "a/b/../c.h" )   == "a/c.h",   "lexicalNormalize collapses a/b/../c.h → a/c.h" );
    check( lexicalNormalize( "a/./b.h" )      == "a/b.h",   "lexicalNormalize elides `.` → a/b.h" );
    check( lexicalNormalize( "a/b/../../c.h" ) == "c.h",    "lexicalNormalize a/b/../../c.h → c.h" );
    check( lexicalNormalize( "../x.h" ).empty(),            "lexicalNormalize `../x.h` (escape) → empty" );
    check( lexicalNormalize( "./a//b/./c.h" ) == "a/b/c.h", "lexicalNormalize normalizes ./a//b/./c.h → a/b/c.h" );

    if( g_fail ) { std::printf( "UNIT FAIL\n" ); return 1; }
    std::printf( "UNIT ALL PASS\n" );
    return 0;
}
