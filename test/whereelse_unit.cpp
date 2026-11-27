// whereelse_unit.cpp — the where-else family's own cases (src/whereelse.h, lane WHERE-ELSE-SHARED): one case per behaviour where the
// three former copies (listedin.h, --for's <where>, --brief's <where-else>) disagreed, each with the twin that holds the other side.
//
// usage: whereelse_unit TMPDIR   (an empty scratch directory; the manifest and changelog cases build small trees under it)
// Prints "  PASS/FAIL <case>" lines and a final count; exit 0 only when every case holds and there is at least one.
// Run by test/listedincheck.sh arm (U).

#include "whereelse.h"
#include "infra/emit.h"

#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string>
#include <string_view>
#include <vector>

namespace
{

namespace fs = std::filesystem;
namespace we = rw::whereelse;

struct Case
{
    std::string what;
    bool        held;
};

void put( const fs::path& p, std::string_view text )
{
    fs::create_directories( p.parent_path() );
    std::ofstream( p ) << text;
}

// An ingest over the files `rels` of the tree at `root` (absolute disk paths, root-relative by crawlRoot).
rw::IngestResult treeIngest( const fs::path& root, const std::vector<std::string>& rels )
{
    rw::IngestResult ing;
    ing.crawlRoot = root.string();
    for( const std::string& r : rels )
    {
        ing.files.push_back( ( root / r ).string() );
    }
    return ing;
}

we::Manifest manifestOf( std::string_view dir, std::string_view text, we::CommentStyle style )
{
    return we::Manifest{ std::string( dir ) + "/CMakeLists.txt", std::string( dir ), std::string( text ), we::blankComments( text, style ), false, false };
}

void nameCases( std::vector<Case>& cs )
{
    const we::Manifest m = manifestOf( "src", "add_library(x\n  catalog.c\n  # log.c\n)\n", we::CommentStyle::CMake );
    cs.push_back( { "(N1) `catalog.c` does not name src/log.c (a substring did: --brief's nearestManifest)", we::lineNaming( m, "src/log.c", 5 ) == 0 } );
    const we::Manifest m2 = manifestOf( "src", "add_library(x\n  log.c\n)\n", we::CommentStyle::CMake );
    cs.push_back( { "(N1 twin) `log.c` on line 2 names src/log.c", we::lineNaming( m2, "src/log.c", 5 ) == 2 } );
    cs.push_back( { "(N2) a commented-out `# log.c` never names it (--brief matched raw text)", we::lineNaming( m, "src/log.c", 0 ) == 0 } );
    const we::Manifest t = manifestOf( "tests", "set(TESTS\n  test_file_logging\n)\n", we::CommentStyle::CMake );
    cs.push_back( { "(N3) a CMake test list names tests/test_file_logging.cpp by its stem", we::lineNaming( t, "tests/test_file_logging.cpp", 5 ) == 2 } );
    const we::Manifest io = manifestOf( "src", "target(io)\n", we::CommentStyle::CMake );
    cs.push_back( { "(N3 twin) a stem under kMinStemNaming bytes (`io`) never names", we::lineNaming( io, "src/io.c", we::kMinStemNaming ) == 0 } );
    cs.push_back( { "(N4) src/x.c is not named from another directory's manifest by its base name", we::lineNaming( manifestOf( "lib", "x.c\n", we::CommentStyle::CMake ), "src/x.c", 0 ) == 0 } );
}

void ecosystemCases( std::vector<Case>& cs )
{
    cs.push_back( { "(K1) go.mod, BUILD.gn, a *.bzl and a *.cmake fragment are manifests; README.md is not",
                    we::isManifestPath( "go.mod" ) && we::isManifestPath( "a/BUILD.gn" ) && we::isManifestPath( "x/defs.bzl" ) && we::isManifestPath( "cmake/w.cmake" )
                        && !we::isManifestPath( "README.md" ) } );
    const std::string xml = we::blankComments( "<a>\n<!-- x.c\n y.c -->\n<s>z.c</s>\n", we::CommentStyle::Xml );
    cs.push_back( { "(K2) an XML comment spanning lines is blanked, line breaks kept, live text kept",
                    xml.find( "x.c" ) == std::string::npos && xml.find( "y.c" ) == std::string::npos && xml.find( "z.c" ) != std::string::npos
                        && std::ranges::count( xml, '\n' ) == 4 } );
    cs.push_back( { "(K3) changelogName: NEWS, CHANGES.rst, release-notes.md yes; newsletter.md no; .changeset/ and changelog.d/ as dirs",
                    we::changelogName( "NEWS", false ) && we::changelogName( "CHANGES.rst", false ) && we::changelogName( "release-notes.md", false )
                        && !we::changelogName( "newsletter.md", false ) && we::changelogName( ".changeset", true ) && we::changelogName( "changelog.d", true )
                        && !we::changelogName( "changelog.d", false ) } );
    cs.push_back( { "(K4) isChangelogPath by name: src/changelog_parser.go and docs/newsletter.md are not (a substring said they were)",
                    !we::isChangelogPath( "src/changelog_parser.go" ) && !we::isChangelogPath( "docs/newsletter.md" ) } );
    cs.push_back( { "(K4 twin) changelog.d/123.md, CHANGELOG.md and pkg/NEWS are",
                    we::isChangelogPath( "changelog.d/123.md" ) && we::isChangelogPath( "CHANGELOG.md" ) && we::isChangelogPath( "pkg/NEWS" ) } );
}

void changelogCases( const fs::path& tmp, std::vector<Case>& cs )
{
    const fs::path a = tmp / "cl-frag";
    put( a / "CHANGELOG.md", "# log\n" );
    put( a / "changelog.d" / "1.md", "x\n" );
    cs.push_back( { "(C1) a directory with CHANGELOG.md and changelog.d/: the fragment directory (--for's <where> said the file)", we::changelogIn( a ) == "changelog.d/" } );
    const fs::path b = tmp / "cl-unrel";
    put( b / "changelog" / "unreleased" / "1.md", "x\n" );
    cs.push_back( { "(C2) changelog/unreleased/ is named whole", we::changelogIn( b ) == "changelog/unreleased/" } );
    const fs::path c = tmp / "cl-mono";
    put( c / "CHANGELOG.md", "# root\n" );
    put( c / "packages" / "zod" / "CHANGELOG.md", "# pkg\n" );
    put( c / "packages" / "zod" / "src" / "a.ts", "x\n" );
    cs.push_back( { "(C3) a monorepo package's own changelog before the root's (--brief read the root only)",
                    we::changelogNear( "packages/zod/src/a.ts", c / "packages" / "zod" / "src" ) == "packages/zod/CHANGELOG.md" } );
    cs.push_back( { "(C3 twin) a file with no package changelog gets the root's",
                    we::changelogNear( "src/b.ts", c / "src" ) == "CHANGELOG.md" } );
    put( tmp / "cl-none" / "x" / "a.c", "x\n" );
    cs.push_back( { "(C4) no changelog anywhere: empty", we::changelogIn( tmp / "cl-none" / "x" ).empty() } );
}

void manifestCases( const fs::path& tmp, std::vector<Case>& cs )
{
    const fs::path r = tmp / "mf";
    put( r / "CMakeLists.txt", "add_subdirectory(tests)\n" );
    put( r / "Makefile", "all:\n\tcmake --build build\n" );
    put( r / "tests" / "CMakeLists.txt", "set(T\n  test_alpha.cpp\n)\n" );
    put( r / "tests" / "test_alpha.cpp", "x\n" );
    put( r / "tests" / "test_beta.cpp", "x\n" );
    put( r / "src" / "a.c", "x\n" );
    const rw::IngestResult ing = treeIngest( r, { "src/a.c", "tests/test_alpha.cpp", "tests/test_beta.cpp" } );
    const we::ManifestRef named = we::nearestNaming( ing, 1 );
    cs.push_back( { "(M1) nearestNaming: tests/CMakeLists.txt line 2 names tests/test_alpha.cpp", named.rel == "tests/CMakeLists.txt" && named.line == 2 } );
    cs.push_back( { "(M1 twin) nothing names tests/test_beta.cpp: empty (--for's <where> rule)", we::nearestNaming( ing, 2 ).rel.empty() } );
    const we::ManifestRef unit = we::nearestUnit( ing, 2, false );
    cs.push_back( { "(M2) nearestUnit: the test dir's own CMakeLists.txt even when it does not name the file (--brief's unit build)",
                    unit.rel == "tests/CMakeLists.txt" && unit.line == 0 } );
    cs.push_back( { "(M3) a root holding CMakeLists.txt and a wrapper Makefile: CMakeLists.txt is the unit", we::nearestUnit( ing, 0, false ).rel == "CMakeLists.txt" } );
    cs.push_back( { "(M3 twin) skipRoot: no unit above src/a.c below the root", we::nearestUnit( ing, 0, true ).rel.empty() } );
    const fs::path am = tmp / "am";
    put( am / "Makefile.am", "x_SOURCES = a.c\n" );
    put( am / "Makefile", "# generated by automake\n" );
    std::vector<we::Manifest> got;
    bool                      capped = false;
    we::readDirManifests( "", am, got, capped );
    cs.push_back( { "(M4) Makefile beside Makefile.am: only Makefile.am is read (automake's source)", got.size() == 1 && got[0].rel == "Makefile.am" } );
    const fs::path py = tmp / "py";
    put( py / "pyproject.toml", "[project]\n" );
    std::vector<we::Manifest> li, un;
    we::readDirManifests( "", py, li, capped );
    we::readDirManifests( "", py, un, capped, we::kRoleUnit );
    cs.push_back( { "(M5) pyproject.toml is a unit manifest, not a LISTED-IN one (LISTED-IN reads exactly its old set)", li.empty() && un.size() == 1 } );
}

// Files: 0 src/sw.py (subject), 1 src/btn.py (sibling), 2 tests/test_switch.py, 3 tests/test_all.py, 4 other/tests/test_far.py.
// test_switch: 2 calls, both into sw.py (share 1.0). test_all: 7 calls, 3 into sw.py (share 0.43), one of them sw.py's exemplar (sym 8).
rw::Graph graphOf( const std::vector<std::vector<rw::NodeId>>& out )
{
    rw::Graph g;
    g.outOff.push_back( 0 );
    for( const std::vector<rw::NodeId>& o : out )
    {
        g.outTargets.insert( g.outTargets.end(), o.begin(), o.end() );
        g.outOff.push_back( std::uint32_t( g.outTargets.size() ) );
    }
    return g;
}

void testCases( std::vector<Case>& cs )
{
    rw::IngestResult ing;
    ing.files = { "src/sw.py", "src/btn.py", "tests/test_switch.py", "tests/test_all.py", "other/tests/test_far.py" };
    for( const std::uint32_t f : { 0u, 1u, 1u, 2u, 2u, 3u, 3u, 3u, 0u, 4u } )
    {
        rw::Symbol s;
        s.fileId = f;
        ing.symbols.push_back( s );
    }
    const rw::Graph g = graphOf( { {}, {}, {}, { 0 }, { 0 }, { 0, 1, 2 }, { 0, 2 }, { 1, 8 }, {}, { 0 } } );
    const std::vector<std::uint8_t> sibling = { 1, 1, 0, 0, 0 };
    const auto isTest   = [ & ]( std::uint32_t f ) { return f >= 2; };
    const auto inScope  = [ & ]( std::uint32_t f ) { return f != 4; };
    const auto hits     = we::subjectTestHits( ing, g, 0, sibling, isTest, []( rw::NodeId ) { return false; } );
    const auto ranked   = we::rankSubjectTests( ing, hits, inScope );
    cs.push_back( { "(T1) counts: test_all calls sw.py 3 times in 7 cross-file calls, test_switch 2 in 2",
                    hits.size() == 3 && hits[1].file == 3 && hits[1].subject == 3 && hits[1].all == 7 && hits[0].subject == 2 && hits[0].all == 2 } );
    cs.push_back( { "(T2) the test ABOUT the subject first: test_switch.py (share 1.0) before test_all.py (more calls: --for's <where> order)",
                    ranked.size() == 2 && ranked[0].file == 2 && ranked[1].file == 3 } );
    cs.push_back( { "(T3) a test outside the subject's scope (other/tests/) is dropped", std::ranges::none_of( ranked, []( const we::TestHits& h ) { return h.file == 4; } ) } );
    const auto ex = we::rankSubjectTests( ing, we::subjectTestHits( ing, g, 0, sibling, isTest, []( rw::NodeId n ) { return n == 8; } ), inScope );
    cs.push_back( { "(T4) a test that reaches the exemplar symbol leads whatever its share", ex.size() == 2 && ex[0].file == 3 && ex[0].exemplar } );
}

} // namespace

int main( int argc, char** argv )
{
    if( argc < 2 )
    {
        rw::emitTo( stderr, "usage: whereelse_unit TMPDIR\n" );
        return 2;
    }
    const fs::path    tmp = argv[1];
    std::vector<Case> cases;
    nameCases( cases );
    ecosystemCases( cases );
    changelogCases( tmp, cases );
    manifestCases( tmp, cases );
    testCases( cases );
    const auto failed = std::ranges::count_if( cases, []( const Case& c ) { return !c.held; } );
    for( const Case& c : cases )
    {
        rw::emitTo( stdout, "  {}  {}\n", c.held ? "PASS" : "FAIL", c.what );
    }
    rw::emitTo( stdout, "whereelse_unit: {} case(s), {} failed\n", cases.size(), failed );
    return failed == 0 && !cases.empty() ? 0 : 1;
}
