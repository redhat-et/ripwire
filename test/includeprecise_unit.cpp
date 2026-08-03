// includeprecise_unit.cpp — P1 unit driver for the PURE path-precise include functions in resolve.h
// (resolvePreciseInclude / lexicalNormalize / buildPreciseIncludeAdj / transitiveIncludeSet). These are
// dead-but-tested at P1 (nothing in buildGraph consumes them yet), so this standalone driver exercises
// them directly against a real ingest() of test/includeprecisefix. Compiled + run by includeprecisecheck.sh.
//
// Prints "UNIT ALL PASS" on success; on any failure prints "UNIT FAIL: <what>" and exits non-zero.

#include "../src/model.h"
#include "../src/ingest.h"
#include "../src/resolve.h"

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
