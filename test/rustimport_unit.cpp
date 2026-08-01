// rustimport_unit.cpp — LEVER-B B3 unit driver for the Rust Step-A (resolve.h::resolveRustImport +
// resolvePreciseInclude dispatch). Exercises the resolver DIRECTLY against a real ingest() of
// test/rustimportprecisefix so the "unique-or-degrade" soundness contract is proven at the source, not
// only through the whole pipeline (where §2a can mask a degrade). Compiled + run by rustimportprecisecheck.sh.
//
// Prints "UNIT ALL PASS" on success; on any failure prints "  FAIL <what>" + "UNIT FAIL" and exits non-zero.

#include "../src/model.h"
#include "../src/ingest.h"
#include "../src/resolve.h"

#include <cstdio>
#include <string>
#include <string_view>

using namespace rw;

static int g_fail = 0;
static void check( bool cond, const char* what )
{
    if( cond ) std::printf( "  PASS  %s\n", what );
    else       { std::printf( "  FAIL  %s\n", what ); g_fail = 1; }
}

static std::uint32_t fileEndingWith( const IngestResult& ing, std::string_view suffix )
{
    std::uint32_t hit = kNoFile;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        std::string_view p = ing.files[f];
        if( p.size() >= suffix.size() && p.compare( p.size() - suffix.size(), suffix.size(), suffix ) == 0 )
            hit = ( hit == kNoFile ) ? f : 0xFFFFFFFEu;
    }
    return hit;
}

int main( int argc, char** argv )
{
    if( argc < 2 ) { std::printf( "UNIT FAIL: usage: %s <fixtureDir>\n", argv[0] ); return 2; }
    const IngestResult ing = ingest( argv[1] );

    HashMap<std::string, std::uint32_t> fileIndex;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f ) fileIndex.emplace( ing.files[f], f );

    const std::uint32_t geoMod    = fileEndingWith( ing, "rustimportprecisefix/src/geo/mod.rs" );
    const std::uint32_t utilRs    = fileEndingWith( ing, "rustimportprecisefix/src/util.rs" );
    const std::uint32_t otherMod  = fileEndingWith( ing, "rustimportprecisefix/src/other/mod.rs" );
    const std::uint32_t ambRs     = fileEndingWith( ing, "rustimportprecisefix/src/amb.rs" );
    const std::uint32_t ambMod    = fileEndingWith( ing, "rustimportprecisefix/src/amb/mod.rs" );
    const std::uint32_t consumer  = fileEndingWith( ing, "rustimportprecisefix/src/consumer.rs" );
    const std::uint32_t lib       = fileEndingWith( ing, "rustimportprecisefix/src/lib.rs" );
    check( geoMod < ing.files.size() && utilRs < ing.files.size() && otherMod < ing.files.size()
           && ambRs < ing.files.size() && ambMod < ing.files.size() && consumer < ing.files.size()
           && lib < ing.files.size(), "fixture files all located" );

    // crate root = the dir holding src/lib.rs. Derive it exactly as buildPreciseIncludeAdj does.
    std::string_view crateRootDir;
    bool             hasCrateRoot = false;
    for( std::uint32_t f = 0; f < ing.files.size() && !hasCrateRoot; ++f )
    {
        std::string_view p = ing.files[f];
        if( p == "lib.rs" || ( p.size() >= 7 && p.substr( p.size() - 7 ) == "/lib.rs" ) )
        { crateRootDir = includerDir( p ); hasCrateRoot = true; }
    }
    check( hasCrateRoot, "crate root located (src/lib.rs present)" );

    const std::string libPath      = ing.files[ lib ];
    const std::string consumerPath = ing.files[ consumer ];

    // ── (a) `mod geo;` from src/lib.rs → src/geo/mod.rs (dir/mod.rs form) — sound module-file rule ──
    const std::uint32_t rGeo = resolvePreciseInclude( libPath, "mod:geo", false, fileIndex, crateRootDir, hasCrateRoot );
    check( rGeo == geoMod, "`mod geo;` → src/geo/mod.rs (dir/mod.rs form), unique" );
    check( rGeo != otherMod, "`mod geo;` does NOT match the same-basename decoy src/other/mod.rs" );

    // `mod util;` → src/util.rs (file form)
    const std::uint32_t rUtil = resolvePreciseInclude( libPath, "mod:util", false, fileIndex, crateRootDir, hasCrateRoot );
    check( rUtil == utilRs, "`mod util;` → src/util.rs (file form), unique" );

    // ── (b) `use crate::geo::helper` → src/geo/mod.rs (geo module, helper item) — crate-anchored, sound ─
    const std::uint32_t rUseGeo = resolvePreciseInclude( consumerPath, "crate::geo::helper", false, fileIndex, crateRootDir, hasCrateRoot );
    check( rUseGeo == geoMod, "`use crate::geo::helper` → src/geo/mod.rs (crate-anchored)" );

    const std::uint32_t rUseUtil = resolvePreciseInclude( consumerPath, "crate::util::utilfn", false, fileIndex, crateRootDir, hasCrateRoot );
    check( rUseUtil == utilRs, "`use crate::util::utilfn` → src/util.rs" );

    // ── (c) THE SOUNDNESS PROOF — `use crate::amb::dupfn` where BOTH src/amb.rs AND src/amb/mod.rs exist
    //        → two distinct file candidates → resolveRustImport must DEGRADE to kNoFile (never guess one).
    check( ambRs != ambMod, "amb.rs and amb/mod.rs are distinct files (the ambiguity setup)" );
    const std::uint32_t rAmb = resolvePreciseInclude( consumerPath, "crate::amb::dupfn", false, fileIndex, crateRootDir, hasCrateRoot );
    check( rAmb == kNoFile, "`use crate::amb::dupfn` with amb.rs AND amb/mod.rs both present → DEGRADE (kNoFile), never a guess" );

    // ── (d) `use std::…` (external crate) → unresolved; a bare use likewise ──────────────────────────
    const std::uint32_t rStd = resolvePreciseInclude( consumerPath, "std::collections::HashMap", false, fileIndex, crateRootDir, hasCrateRoot );
    check( rStd == kNoFile, "`use std::collections::HashMap` (external crate) → kNoFile (unresolved)" );

    // a brace group never resolves to one file → degrade
    const std::uint32_t rBrace = resolvePreciseInclude( consumerPath, "crate::{geo, util}", false, fileIndex, crateRootDir, hasCrateRoot );
    check( rBrace == kNoFile, "`use crate::{geo, util}` (brace group) → kNoFile (degrade, not one file)" );

    // ── (e) crate-root gating: with hasCrateRoot=false, a `crate::` use MUST degrade (workspace member) ─
    const std::uint32_t rNoRoot = resolvePreciseInclude( consumerPath, "crate::geo::helper", false, fileIndex, {}, false );
    check( rNoRoot == kNoFile, "`use crate::…` with NO locatable crate root → kNoFile (degrade)" );

    // ── (f) an inline `mod inner { … }` is captured with a body → NOT a mod: target → no file edge ────
    // (proven at ingest: no `mod:inner` include for the body-having mod; assert none was captured)
    bool sawInlineMod = false;
    for( const Include& inc : ing.includes ) if( inc.target == "mod:inner" ) sawInlineMod = true;
    check( !sawInlineMod, "inline `mod inner { … }` (with body) captured NO mod: target (no phantom file edge)" );

    if( g_fail ) { std::printf( "UNIT FAIL\n" ); return 1; }
    std::printf( "UNIT ALL PASS\n" );
    return 0;
}
