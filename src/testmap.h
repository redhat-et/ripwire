#pragma once

// testmap.h — the test<->code map, both directions (§P11.2 and §P11.4).
//
// §P11.2 recorded the map as "one-directional and file-granular": the tool could answer "which tests reach
// this FILE" and nothing else. The two questions an agent actually has were unanswerable —
//
//   planning a change     "which tests cover this SYMBOL?"      → --affected=SYM   (resolveAffectedSeeds)
//   fixing a failing test "what does this test EXERCISE?"       → --exercises=FILE
//
// — and §P11.4 recorded that even when the map named a test it named a bare `.cpp` harness path, which is
// not a command: the verb created an obligation its own output could not discharge (--test-gate exits 4 on
// it).
//
// Everything here is SEEDING and PRESENTATION over traversals that already exist. The reachability itself is
// graph.h's transitiveCallers / forwardReach and filter.h's isTestPath — this header adds no new traversal,
// which is why --affected=SYM is a seeding change rather than a second verb. Its own file (not main.cpp)
// because more than one verb reads it, the same reason ownersview.h and pageview.h exist.
//
// Deterministic by construction: every returned list is sorted (symbol id, or path) and every scan runs in
// file/symbol id order.

#include "model.h"
#include "graph.h"        // filePathContains / splitQualifiedSpec / resolveAllByNameQualified — reused, not re-rolled
#include "filter.h"       // isTestPath — the ONE test-path convention the whole tool shares
#include "docparse.h"     // docparse::detail::readWholeFile — the canonical whole-file byte read (reused, not re-rolled)
#include "mention.h"      // mention_detail::baseNameOf + stripExt — the ONE basename/stem pair binstale.h/gitmine.h reuse
#include "infra/sortutil.h" // rw::sortutil::svLess — string_view ordering is never operator< (portablebuildcheck #6)
#include "infra/namesplit.h" // namesplit::isIdentChar — the canonical ASCII identifier-byte predicate
#include "sarif.h"       // rootPrefixOf / rootRelativeUri — the ONE relativizer every p= emitter already shares (A3)
#include "infra/jsonesc.h" // rw::shSingleQuote — the ONE shell quoter; run= is a COMMAND, see spell() below
#include "pythonrunner.h" // main-guard / pytest evidence; a .py extension alone is not a runner
#include "jsrunner.h"     // #323: nearest package.json evidence (vitest/jest/node --test); a .ts/.js extension alone is not a runner
#include "serialize.h"    // lane/t10-mcp-coverage: escapeXml — writeAffectedReport's ONE escaper (CLI ≡ MCP)
#include "langfacts.h"    // constructorMethod — the class-new backstop's per-language construction row
#include "graphlegend.h"  // lane/t10-mcp-coverage: unprovenDefsVerbLegend/unprovenDefsAttrXml/graphCountFloorBrief/
                          // rootRelPathsLegend — writeAffectedReport's shared legend vocabulary

#include <algorithm>
#include <cstdio>
#include <format>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// ── §P11.2a — the --affected argument, read under the FILE-FIRST rule ────────────────────────────────
// One argument string can name a path or a symbol, and the two readings answer different questions over
// the same bytes. The rule is: an item matching ANY indexed path is a path (so every argument shape that
// worked before --affected took symbols means exactly what it meant before), and only an item matching NO
// indexed path is offered to the symbol resolver. `file:NAME` and `path::scope::name` reach the symbol
// reading explicitly — the same two spellings --callers/--impact/--around already accept.
//
// A refusal is per-ITEM, not "the whole list resolved to nothing": before this, `--affected=src/x.cpp,typo`
// silently dropped the typo and answered confidently for the half it understood (§P0's class exactly).
// F3 (terminality round A 2026-09-05) — the TEST PARTITION of the seed set, and why it is not optional.
// The path reading is a substring PATTERN, so one item can match several files: `geo.py` also matches
// `test/check_geo.py`. Every matched file's symbols used to become seeds, and transitiveCallers returns
// "reached, MINUS the seeds" — so the very tests that reach the change were subtracted out of their own
// answer. `--affected=geo.py` reported seeds="6" tests="0" reached="0" on a corpus where `--affected=./geo.py`
// reported reached="1" (lane-L8.md 2026-09-04, found-not-fixed #1): a confidently wrong ZERO in the verb
// whose whole job is telling an agent which tests to run, with the reason it was wrong nowhere in the output.
//
// The two facts are DIFFERENT and are kept apart now. A test file cannot "reach" a change it is part of, so
// it is no seed of the caller walk (walkSeeds); it is in the ANSWER because the argument MATCHED it — it
// changed, so run it — and its row says so with seed_kind="test". The walk itself is unchanged: dropping a
// symbol from the seed SET never hides it from the traversal, which still finds it as a caller.
struct AffectedSeeds
{
    std::vector<NodeId>        seeds;                  // deduped seed symbols, id asc (both readings)
    std::vector<NodeId>        walkSeeds;              // seeds OUTSIDE test paths — the caller walk's roots
    std::vector<std::uint32_t> seedTestFiles;          // matched TEST files, file id asc, deduped
    std::size_t                unprovenDefs  = 0;      // H1: the decl→def residue, summed over the SYMBOL items (a path item adds 0)
    bool                       sawFileItem   = false;  // at least one item read as a path pattern
    bool                       sawSymbolItem = false;  // at least one item read as a symbol
    bool                       ok            = true;   // false ⇒ badItem resolved under NEITHER reading
    std::string                badItem;                // the offending item, for the caller's did-you-mean refusal
};

// seeded_by= — which reading fired. A fact about the measurement (the two readings return different test
// sets from the same argument), so it is disclosed on the root element rather than left to be inferred.
inline const char* affectedSeededBy( const AffectedSeeds& sel ) noexcept
{
    if( sel.sawFileItem && sel.sawSymbolItem )
    {
        return "mixed";
    }
    return sel.sawSymbolItem ? "symbol" : "file";
}

// The partition itself, over the DEDUPED seed set and therefore over both readings: a bare symbol name that
// resolves into a test file is the same fact as a path pattern that matched one — the symbol changed, its
// test must be run, and nothing that test "reaches" answers the question asked.
inline void partitionAffectedSeedsByTestPath( const IngestResult& ing, AffectedSeeds& sel )
{
    for( NodeId n : sel.seeds )
    {
        const std::uint32_t fileId = ing.symbols[n].fileId;
        if( isTestPath( rootRelPath( ing, fileId ) ) )
        {
            sel.seedTestFiles.push_back( fileId );
        }
        else
        {
            sel.walkSeeds.push_back( n );
        }
    }
    std::sort( sel.seedTestFiles.begin(), sel.seedTestFiles.end() );
    sel.seedTestFiles.erase( std::unique( sel.seedTestFiles.begin(), sel.seedTestFiles.end() ), sel.seedTestFiles.end() );
}

inline AffectedSeeds resolveAffectedSeeds( const IngestResult& ing, std::string_view spec )
{
    AffectedSeeds sel;
    for( std::size_t start = 0; start < spec.size(); )
    {
        std::size_t comma = spec.find( ',', start );
        if( comma == std::string_view::npos )
        {
            comma = spec.size();
        }
        const std::string_view item = spec.substr( start, comma - start );
        start = comma + 1;
        if( item.empty() )
        {
            continue;
        }

        // §P8 seam 2: the PATH reading is stripLineLocator'd, so a `./src/graph.h:1148` row pasted out of
        // --hotspots/--clones/--grep/--lint/--quality-delta means the bare path. The SYMBOL reading gets
        // the item VERBATIM — its own `file:NAME` colon must survive.
        const std::string_view pathPattern = stripLineLocator( item );
        bool                   fileMatched = false;
        // #228/A1: matched against the ROOT-RELATIVE spelling (filePathContainsRootRel, graph.h), never
        // ing.files[f] raw — a directory above the crawl root (the checkout location under an absolute or
        // trailing-slash root) must decide nothing, exactly like the isTestPath/isFixturePath call sites
        // elsewhere in this file.
        for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ); ++f )
        {
            if( filePathContainsRootRel( ing, f, pathPattern ) )
            {
                fileMatched = true;
                break;
            }
        }
        if( fileMatched )
        {
            sel.sawFileItem = true;
            for( NodeId i = 0; i < NodeId( ing.symbols.size() ); ++i )
            {
                if( filePathContainsRootRel( ing, ing.symbols[i].fileId, pathPattern ) )
                {
                    sel.seeds.push_back( i );
                }
            }
            continue;
        }

        // H1: the out-param is this item's decl→def residue — definitions a file:NAME item found and could not tie to
        // the file it named, so they are no seed and the caller walk never starts from them. Summed item by item onto
        // the answer, --path's rule for its two endpoints: a path item never reaches this line, a bare NAME never widens.
        std::size_t               itemUnprovenDefs = 0;
        const std::vector<NodeId> defs             = resolveAllByNameQualified( ing, item, &itemUnprovenDefs );
        if( defs.empty() ) { sel.ok = false;  sel.badItem.assign( item );  return sel; }
        sel.sawSymbolItem = true;
        sel.unprovenDefs += itemUnprovenDefs;
        sel.seeds.insert( sel.seeds.end(), defs.begin(), defs.end() );
    }
    std::sort( sel.seeds.begin(), sel.seeds.end() );
    sel.seeds.erase( std::unique( sel.seeds.begin(), sel.seeds.end() ), sel.seeds.end() );
    partitionAffectedSeedsByTestPath( ing, sel );
    return sel;
}

// The ANSWER for one resolved argument, assembled from the two DIFFERENT facts that put a test file in it —
// kept out of the emitter for the same reason the seeding is (more than one reader, and the reasoning above
// belongs next to the walk it constrains, not next to the printf).
//
//   reached  — the caller walk over the NON-test seeds. transitiveCallers returns "reached, minus the seeds",
//              so seeding it with a matched test file's own symbols subtracted the very tests that reach the
//              change. Excluding them from the seed SET does not hide them from the traversal: they are still
//              found as callers, which is why the answer is unchanged for every argument that matches no test.
//   matched  — a matched TEST file is in the answer on its own evidence: the argument named it, so it changed,
//              so run it. isSeedTestFile marks those rows, which the emitter labels seed_kind="test".
// ── H2H-Graft F1 (2026-09-07) — a tests-to-run row says WHY it is one, and rows come in EVIDENCE order ──
// Head-to-head vs Graft on rocksdb (bench/graft-h2h): asked "which tests cover cache/tiered_secondary_cache.cc",
// --affected named two tests the graph reaches and never the file's own cache/tiered_secondary_cache_test.cc,
// which builds the object through NewTieredCache() — a factory edge the name-based walk cannot see; Graft's
// plain lexical `ask` named it in 167 B. Asked about db/write_batch.cc, --affected DID name
// db/write_batch_test.cc — at row ~60 of 127, because rows were path-sorted. Three kinds of evidence now
// travel on the row, each a fact:
//   changed=1  the test file is IN the change set: you edited it, run it (Graft's blast verb calls this
//              state "changed"; before this the file was silently ABSENT — its symbols were skipped as
//              "the change, not its radius", and a diff of {src, its test} exited 0 with no obligations)
//   partner=1  the test is NAMED after a changed file by convention — <stem>_test.cc, test_<stem>.py,
//              <stem>.test.ts / .spec.ts, <stem>_spec.rb, <Stem>Test.java, <stem>_unittest — listed on that
//              evidence even when the graph never reaches it; such a row carries NO hops= (0 would claim an edge)
//   hops=N     the caller-walk depth at which the test first reaches a changed symbol (1 = a direct call)
// Order: changed, then partner, then hops ascending, then path. The graph-reached rows are Graft's "stale":
// tests that reach the changed area and the diff did not touch.
struct TestRow
{
    std::uint32_t fileId  = 0;
    std::uint32_t hops    = 0;   // 0 = not reached by the caller walk; never printed as a value
    bool          partner = false;
    bool          changed = false;
};

inline bool isTestPartnerOf( std::string_view testPath, std::string_view srcPath ) noexcept
{
    const auto base = []( std::string_view p ) noexcept -> std::string_view
    {
        const std::size_t sl = p.rfind( '/' );
        return sl == std::string_view::npos ? p : p.substr( sl + 1 );
    };
    const auto stem = []( std::string_view fn ) noexcept -> std::string_view
    {
        const std::size_t dot = fn.rfind( '.' );
        return dot == std::string_view::npos ? fn : fn.substr( 0, dot );
    };
    const std::string_view s = stem( base( srcPath ) );
    const std::string_view t = stem( base( testPath ) );
    if( s.empty() || t.size() <= s.size() )
    {
        return false;
    }
    if( t.substr( 0, s.size() ) == s )
    {
        const std::string_view suffix = t.substr( s.size() );
        for( std::string_view k : { std::string_view( "_test" ), std::string_view( "_unittest" ), std::string_view( "_spec" ),
                                    std::string_view( "Test" ), std::string_view( "Tests" ), std::string_view( ".test" ), std::string_view( ".spec" ) } )
        {
            if( suffix == k )
            {
                return true;
            }
        }
    }
    return t.size() > 5 && t.substr( 0, 5 ) == "test_" && t.substr( 5 ) == s;
}

// `reach`/`depth` are transitiveCallersDepth's outputs; `skipSym` (optional) drops nodes that are the change
// itself rather than its radius (--test-gate's per-symbol claims); `partnerOf` are the changed SOURCE files a
// test may be named after; `changedTests` are test files in the change set (rows on their own evidence).
inline std::vector<TestRow> rankTestRows( const IngestResult& ing, std::span<const NodeId> reach, const std::vector<std::uint32_t>& depth,
                                          const std::vector<char>* skipSym, std::span<const std::uint32_t> partnerOf,
                                          std::span<const std::uint32_t> changedTests )
{
    const std::uint32_t        F = std::uint32_t( ing.files.size() );
    std::vector<std::uint32_t> minHops( F, 0 );
    std::vector<char>          isPartner( F, 0 ), isChanged( F, 0 );
    for( NodeId n : reach )
    {
        if( n >= ing.symbols.size() || ( skipSym && n < skipSym->size() && ( *skipSym )[n] ) )
        {
            continue;
        }
        const std::uint32_t f = ing.symbols[n].fileId;
        if( f < F && isTestPath( rootRelPath( ing, f ) ) && ( minHops[f] == 0 || depth[n] < minHops[f] ) )
        {
            minHops[f] = depth[n];
        }
    }
    if( !partnerOf.empty() )
    {
        std::vector<std::uint32_t> testFiles;
        for( std::uint32_t f = 0; f < F; ++f )
        {
            if( isTestPath( rootRelPath( ing, f ) ) )
            {
                testFiles.push_back( f );
            }
        }
        for( std::uint32_t src : partnerOf )
        {
            for( std::uint32_t t : testFiles )
            {
                if( src < F && t != src && !isPartner[t] && isTestPartnerOf( ing.files[t], ing.files[src] ) )
                {
                    isPartner[t] = 1;
                }
            }
        }
    }
    for( std::uint32_t f : changedTests )
    {
        if( f < F )
        {
            isChanged[f] = 1;
        }
    }
    std::vector<TestRow> rows;
    for( std::uint32_t f = 0; f < F; ++f )
    {
        if( minHops[f] || isPartner[f] || isChanged[f] )
        {
            rows.push_back( TestRow{ f, minHops[f], isPartner[f] != 0, isChanged[f] != 0 } );
        }
    }
    std::sort( rows.begin(), rows.end(), [ & ]( const TestRow& a, const TestRow& b )
               {
                   if( a.changed != b.changed ) { return a.changed; }
                   if( a.partner != b.partner ) { return a.partner; }
                   const std::uint32_t ha = a.hops ? a.hops : UINT32_MAX, hb = b.hops ? b.hops : UINT32_MAX;
                   if( ha != hb ) { return ha < hb; }
                   return ing.files[a.fileId] < ing.files[b.fileId];
               } );
    return rows;
}

// The evidence attributes, ONE builder for every emitter of a tests-to-run row: the XML row, its JSON twin,
// and --situ's text line — so the three dialects cannot drift on which facts a row carries.
enum class EvDialect : std::uint8_t { Xml, Json, Text };
inline std::string testRowEvidence( const TestRow& r, EvDialect d )
{
    // The dialect tables were arrays of printf FORMATS indexed at runtime, which std::format_string —
    // consteval — cannot hold. Switching on the dialect instead keeps every format a literal at its own
    // call site, so each one is compile-time checked; the three spellings are unchanged.
    std::string s;
    char        buf[ 48 ];
    const auto  flagOf = [ & ]( const char* name )
    {
        switch( d )
        {
            case EvDialect::Xml:  rw::formatTo( buf, sizeof buf, " {}=\"1\"", name );   break;
            case EvDialect::Json: rw::formatTo( buf, sizeof buf, ",\"{}\":true", name ); break;
            case EvDialect::Text: rw::formatTo( buf, sizeof buf, " [{}]", name );       break;
        }
    };
    for( const auto& [ name, on ] : { std::pair{ "changed", r.changed }, std::pair{ "partner", r.partner } } )
    {
        if( on )
        {
            flagOf( name );
            s += buf;
        }
    }
    if( r.hops )
    {
        switch( d )
        {
            case EvDialect::Xml:  rw::formatTo( buf, sizeof buf, " hops=\"{}\"", unsigned( r.hops ) );   break;
            case EvDialect::Json: rw::formatTo( buf, sizeof buf, ",\"hops\":{}", unsigned( r.hops ) );   break;
            case EvDialect::Text: rw::formatTo( buf, sizeof buf, " [hops={}]", unsigned( r.hops ) );     break;
        }
        s += buf;
    }
    return s;
}
// The change set split into the files a partner test may be named after (source) and the test files that
// are obligations on their own evidence — ONE rule for the file-mask callers (--situ's two reports) and the
// symbol-set caller (--test-gate's per-symbol claims).
struct ChangedFileSplit
{
    std::vector<std::uint32_t> src, tests;
};
inline ChangedFileSplit splitChangedFiles( const IngestResult& ing, const std::vector<char>& changedFile )
{
    ChangedFileSplit out;
    for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ) && f < changedFile.size(); ++f )
    {
        if( changedFile[f] )
        {
            ( isTestPath( rootRelPath( ing, f ) ) ? out.tests : out.src ).push_back( f );
        }
    }
    return out;
}
inline ChangedFileSplit splitChangedFilesOfSymbols( const IngestResult& ing, std::span<const NodeId> changedSyms )
{
    std::vector<char> changedFile( ing.files.size(), 0 );
    for( NodeId s : changedSyms )
    {
        if( s < ing.symbols.size() && ing.symbols[s].fileId < changedFile.size() )
        {
            changedFile[ing.symbols[s].fileId] = 1;
        }
    }
    return splitChangedFiles( ing, changedFile );
}
inline std::size_t testRowPartnerCount( const std::vector<TestRow>& rows )
{
    std::size_t n = 0;
    for( const TestRow& r : rows )
    {
        n += r.partner ? 1 : 0;
    }
    return n;
}
// THE RUN-FIRST HEAD (comparison table hono-20 / textual-20, 2026-09-30): an evidence-ordered list of 80-249 test files
// said nothing about which rows carry the most direct evidence (textual's snapshot test sat inside an undifferentiated
// tier of 157). The head is every changed=, partner= or hops=1 row — the module's own tests and the tests that call it
// directly — or, when the list has none of those, the rows at its smallest hops=. rankTestRows' order makes it a prefix.
// It is a RUN ORDER, never a skip list: the walk is name-based and its counts are floors, so a row past the head (or a
// test the walk missed) can still exercise the change. Nothing is dropped: the count only marks where the head ends.
inline std::size_t testRowRunFirstCount( const std::vector<TestRow>& rows )
{
    std::size_t n = 0;
    while( n < rows.size() && ( rows[n].changed || rows[n].partner || rows[n].hops == 1 ) )
    {
        ++n;
    }
    if( n == 0 && !rows.empty() && rows.front().hops > 0 )
    {
        const std::uint32_t nearest = rows.front().hops;
        while( n < rows.size() && rows[n].hops == nearest && !rows[n].changed && !rows[n].partner )
        {
            ++n;
        }
    }
    return n;
}
// Present only when the tier SPLITS the list (0 < N < total rows): a list that is all run-first, or empty, says nothing new.
inline bool runFirstSplits( std::size_t runFirst, std::size_t totalRows ) noexcept
{
    return runFirst > 0 && runFirst < totalRows;
}
// The XML attribute or the JSON key, through graphlegend.h's shared absent-at-zero spelling.
inline std::string runFirstField( const std::vector<TestRow>& rows, std::size_t totalRows, bool json )
{
    const std::size_t runFirst = testRowRunFirstCount( rows );
    return countFieldOrEmpty( "run_first", runFirstSplits( runFirst, totalRows ) ? runFirst : 0, json );
}
inline constexpr std::string_view kRunFirstLegend =
    "run_first=N (only when it splits the list): the first N test files carry the most direct evidence (changed, partner or "
    "hops=1 rows, else those at the smallest hops=); a run order, not a skip list: the rest can still exercise the change. ";
inline std::string_view runFirstLegend( bool on ) noexcept
{
    return on ? kRunFirstLegend : std::string_view();
}

// The legend clause every emitter splices next to its rows — one wording, so the four verbs cannot drift.
// Written long, measured (477 B), cut to the shortest honest form — test/testgatelegendbudgetcheck.sh's ratchet.
inline constexpr std::string_view kTestRowEvidenceLegend =
    "rows in EVIDENCE order: changed=1 (the test file is in the change set: run it), partner=1 (named after a changed "
    "file — <stem>_test, test_<stem>, <Stem>Test — listed by convention, no hops=), then hops= ascending (caller-walk "
    "depth to a changed symbol; 1 = direct), then path. ";

struct AffectedAnswer
{
    std::vector<NodeId>        reach;           // symbols the caller walk found (the seeds are not in it)
    std::vector<TestRow>       rows;            // the answer rows, EVIDENCE order (rankTestRows)
    std::vector<std::uint32_t> testFiles;       // the same rows as file ids, same order — the pre-F1 consumers' view
    std::vector<char>          isSeedTestFile;  // per file: matched by the argument AND a test path
    std::vector<std::uint32_t> depth;           // per symbol: the caller-walk hop at which `reach` found it (read for reach members only)
};

inline AffectedAnswer affectedAnswer( const IngestResult& ing, const Graph& g, const AffectedSeeds& sel )
{
    AffectedAnswer             out;
    std::vector<std::uint32_t>& depth = out.depth;
    out.isSeedTestFile.assign( ing.files.size(), 0 );
    out.reach = transitiveCallersDepth( g, sel.walkSeeds, &depth );
    for( std::uint32_t fileId : sel.seedTestFiles )
    {
        out.isSeedTestFile[fileId] = 1;
    }
    // partners are named after the files the walk seeds live in (both argument readings); a matched TEST file
    // is a row on its own evidence, exactly as it was before F1
    out.rows = rankTestRows( ing, out.reach, depth, nullptr, splitChangedFilesOfSymbols( ing, sel.walkSeeds ).src, sel.seedTestFiles );
    for( const TestRow& r : out.rows )
    {
        out.testFiles.push_back( r.fileId );
    }
    return out;
}

// ── IX-5 (ideas-r4 L6-2 / D11) — the CLASS-NEW BACKSTOP: tests that BUILD a class the change reaches into ─────────────
// hono-20: `--affected=src/utils/url.ts` reached TrieRouter.add, but trie-router/router.test.ts only does
// `newRouter: () => new TrieRouter()` and drives the router through an interface-typed helper (`router.add( … )`),
// whose dispatch no resolver can prove, so the caller walk never reached the test. A programmer asking "which tests
// does this file affect" checks that test anyway: it constructs the class whose method the change sits under.
// The backstop lists exactly those tests, APART from the proven rows: a test-file caller of a class that OWNS a symbol
// the walk reached (or that is itself a seed — the changed class), not already a row. It is a hedge, never an edge:
// the construction is proven (a resolved call edge to the class), the dispatch from the test to the reached method is
// not — so the rows are never counted in tests=/reached= and never merged into the proven list.
// Construction, per language, is DATA the parser already records: a call edge whose target is a class or struct
// (`new T(` JS/TS/Java/C#, `T(` Python/Kotlin/C++ functional form), plus a call to the
// language's conventional constructor METHOD of the class (langfacts.h constructorMethod: Rust `T::new`). Not captured, so never a row (a floor):
// Go composite literals `T{…}` and C++ declarations `T x;` (no call reference), Ruby `T.new` (no constructorMethod row).
// Deliberately NOT the peers' flat dependents dump: one hop from the class, test callers only, capped.
inline constexpr std::uint32_t kClassNewRowCap = 8;   // rows shown; the group's total= counts them all, next= is --callers= of the first cut row's class

struct ClassNewRow
{
    std::uint32_t testFile = 0;
    std::uint32_t line     = 0;         // the construction's line in testFile; 0 = no call reference named it (l= absent)
    NodeId        cls      = kNoNode;   // the class constructed
    std::uint32_t rank     = 0;         // the class's nearest reached member, in caller-walk hops (0 = a seed)
    NodeId        target   = kNoNode;   // what the construction calls: cls itself, or its constructorMethod (Rust `new`)
};

// The kinds a construction can build — a class or a struct (an interface, alias or function type is never instantiated).
// A per-kind DATA row, read through the shared enum-table accessor.
inline constexpr std::array<bool, kSymKindCount> kConstructibleKind = []
{
    std::array<bool, kSymKindCount> table {};
    table[ static_cast<std::size_t>( SymKind::Class ) ]  = true;
    table[ static_cast<std::size_t>( SymKind::Struct ) ] = true;
    return table;
}();
inline bool isConstructibleClassKind( SymKind k ) noexcept
{
    return enumTableAt( kConstructibleKind, k, false );
}

// The class owning `s`: the innermost class/struct in s's file whose span contains it; with none, the ONE class of s's
// language named by s's scope (a C++ out-of-line member, a Rust impl method), kNoNode when the name is not unique.
// `classesIn` holds the file's classes; `byName` is every class, (name, id) sorted — consulted only on that fallback.
inline NodeId classOwnerOf( const IngestResult& ing, NodeId s, std::span<const NodeId> classesIn,
                            std::span<const std::pair<std::string_view, NodeId>> byName )
{
    const Symbol& sym       = ing.symbols[s];
    NodeId        innermost = kNoNode;
    for( const NodeId c : classesIn )
    {
        const Symbol& t = ing.symbols[c];
        if( c != s && t.sigStartByte <= sym.sigStartByte && sym.endByte <= t.endByte
            && ( innermost == kNoNode || t.sigStartByte > ing.symbols[innermost].sigStartByte ) )
        {
            innermost = c;
        }
    }
    if( innermost != kNoNode || sym.scope.empty() )
    {
        return innermost;
    }
    const std::string_view owner = scopeLastSegment( sym.scope );
    // rw::sortutil::svLess, never operator<: the order byName is sorted under (classNewMarkReached's sort; portablebuildcheck #6/#6b/#6c).
    using Entry = std::pair<std::string_view, NodeId>;
    const auto nameLess = []( const Entry& a, const Entry& b ) { return rw::sortutil::svLess( a.first, b.first ); };
    const auto [ lo, hi ] = std::equal_range( byName.begin(), byName.end(), Entry{ owner, 0 }, nameLess );
    NodeId found = kNoNode;
    for( auto it = lo; it != hi; ++it )
    {
        if( ing.symbols[ it->second ].lang != sym.lang )
        {
            continue;
        }
        if( found != kNoNode )
        {
            return kNoNode;   // two same-named classes in the language: the scope proves neither
        }
        found = it->second;
    }
    return found;
}

// The state the backstop's steps share — built once per answer by classNewTestRows, read by its steps in order.
struct ClassNewScan
{
    static constexpr std::uint32_t kUnreached = UINT32_MAX;
    const IngestResult&                              ing;
    NodeId                                           N = 0;
    std::vector<char>                                isTestFile;   // per file
    std::vector<char>                                fileMarked;   // per file: holds a reached non-test symbol
    std::vector<std::uint32_t>                       hop;          // per symbol: its caller-walk hop (a seed is 0), kUnreached otherwise
    std::vector<std::vector<NodeId>>                 classesIn;    // per marked file: its classes
    std::vector<std::pair<std::string_view, NodeId>> byName;       // every class, (name, id) sorted
    std::vector<std::uint32_t>                       classRank;    // per symbol: an owner class's nearest reached member hop

    // the classes of `fileId` for classOwnerOf: the gathered list for a marked file, else gathered now (the rare
    // constructorMethod row in an unmarked file)
    std::vector<NodeId> classesOf( std::uint32_t fileId ) const
    {
        if( fileMarked[ fileId ] )
        {
            return classesIn[ fileId ];
        }
        std::vector<NodeId> out;
        for( const auto& entry : byName )
        {
            if( ing.symbols[ entry.second ].fileId == fileId )
            {
                out.push_back( entry.second );
            }
        }
        return out;
    }
};

// Step 1: the reached set with its hop, non-test symbols only (a reached TEST symbol is a proven row already), and the classes.
inline void classNewMarkReached( ClassNewScan& s, const AffectedSeeds& sel, const AffectedAnswer& ans )
{
    const IngestResult& ing = s.ing;
    const auto mark = [ & ]( NodeId n, std::uint32_t h )
    {
        if( n < s.N && !s.isTestFile[ ing.symbols[n].fileId ] )
        {
            s.hop[n]                              = std::min( s.hop[n], h );
            s.fileMarked[ ing.symbols[n].fileId ] = 1;
        }
    };
    for( const NodeId seed : sel.walkSeeds )
    {
        mark( seed, 0 );
    }
    for( const NodeId n : ans.reach )
    {
        mark( n, n < ans.depth.size() ? ans.depth[n] : ClassNewScan::kUnreached );
    }
    for( NodeId c = 0; c < s.N; ++c )
    {
        const Symbol& t = ing.symbols[c];
        if( isConstructibleClassKind( t.kind ) )
        {
            s.byName.emplace_back( t.name, c );
            if( s.fileMarked[ t.fileId ] )
            {
                s.classesIn[ t.fileId ].push_back( c );
            }
        }
    }
    std::sort( s.byName.begin(), s.byName.end(), []( const std::pair<std::string_view, NodeId>& a, const std::pair<std::string_view, NodeId>& b )
               { return a.first != b.first ? rw::sortutil::svLess( a.first, b.first ) : a.second < b.second; } );
}

// Step 2: the owner classes, each at the hop of its nearest reached member (the changed class itself at its own hop).
inline bool classNewRankOwners( ClassNewScan& s )
{
    bool anyOwner = false;
    for( NodeId n = 0; n < s.N; ++n )
    {
        if( s.hop[n] == ClassNewScan::kUnreached )
        {
            continue;
        }
        const Symbol& sym   = s.ing.symbols[n];
        const NodeId  owner = isConstructibleClassKind( sym.kind ) ? n : classOwnerOf( s.ing, n, s.classesIn[ sym.fileId ], s.byName );
        if( owner != kNoNode )
        {
            s.classRank[owner] = std::min( s.classRank[owner], s.hop[n] );
            anyOwner           = true;
        }
    }
    return anyOwner;
}

// Step 3: what a construction calls — each owner class, plus its language's constructor METHOD (langfacts.h constructorMethod).
struct ClassNewTarget { NodeId node; NodeId cls; };
inline std::vector<ClassNewTarget> classNewTargets( const ClassNewScan& s )
{
    std::vector<ClassNewTarget> targets;
    for( NodeId c = 0; c < s.N; ++c )
    {
        const Symbol&          t    = s.ing.symbols[c];
        const std::string_view ctor = langFacts( t.lang ).constructorMethod;
        if( s.classRank[c] != ClassNewScan::kUnreached )
        {
            targets.push_back( { c, c } );
            continue;
        }
        if( ctor.empty() || t.name != ctor || s.isTestFile[ t.fileId ] )
        {
            continue;
        }
        const std::vector<NodeId> fileClasses = s.classesOf( t.fileId );
        const NodeId              owner       = classOwnerOf( s.ing, c, fileClasses, s.byName );
        if( owner != kNoNode && s.classRank[owner] != ClassNewScan::kUnreached )
        {
            targets.push_back( { c, owner } );
        }
    }
    return targets;
}

// Step 4: a test-file caller of a target whose file is no proven row — (caller, class, target), sorted by caller.
struct ClassNewSite { NodeId caller; NodeId cls; NodeId target; };
inline std::vector<ClassNewSite> classNewSites( const ClassNewScan& s, const Graph& g, std::span<const ClassNewTarget> targets,
                                                const std::vector<char>& proven )
{
    std::vector<ClassNewSite> sites;
    const auto*               ro = g.inEdges.rowOffsets();
    const auto*               ci = g.inEdges.colIndices();
    for( const ClassNewTarget& t : targets )
    {
        if( t.node >= g.inEdges.rows() )
        {
            continue;   // a graph built over fewer symbols than the ingest (none today) has no callers to offer
        }
        for( std::uint32_t k = ro[ t.node ]; k < ro[ t.node + 1 ]; ++k )
        {
            const NodeId u = ci[k];
            if( u < s.N && s.isTestFile[ s.ing.symbols[u].fileId ] && !proven[ s.ing.symbols[u].fileId ] )
            {
                sites.push_back( { u, t.cls, t.node } );
            }
        }
    }
    std::sort( sites.begin(), sites.end(), []( const ClassNewSite& a, const ClassNewSite& b ) { return std::tie( a.caller, a.cls ) < std::tie( b.caller, b.cls ); } );
    return sites;
}

// Does the call reference `r` (from a caller that constructs) name this construction? A constructorMethod call is named by its
// LAST segment only (`new`), so `Other::new()` would pass the name test for `Eng`: the call's written qualifier must also be the
// class (exact, or no l= — a Rust alias import is a floor). A target that IS the class (Python `T()`) carries no
// qualifier test (Reference holds no resolved target), so classNewBestRows hedges instead: two passing refs with different
// receivers (`ext.Eng()` / `Eng()`) leave the row without its l=. TS/JS never reach this name test: ClassNewJsBinds resolves them.
inline bool classNewCallNames( const IngestResult& ing, const Reference& r, const ClassNewSite& site )
{
    return r.calleeName == ing.symbols[ site.target ].name
           && ( site.target == site.cls || scopeLastSegment( r.qualifier ) == ing.symbols[ site.cls ].name );
}

// A test file's class-new row hedges its l= (every language but TS/JS, see ClassNewJsBinds): the call refs that named the row's class must all be
// WRITTEN the same way. The qualifier proper is a C++/Rust `A::b` scope; a Python `ext.Eng()` writes it as a member receiver, which the extractor
// files under recv/recvVar/memberRoot/memberPath — so two refs to one name that differ there may be two classes (a namesake), and the line is dropped.
struct ClassNewSpelling
{
    std::vector<std::string> first;   // per test file: how the first call ref that named the row's class was written
    std::vector<char>        mixed;   // per test file: a later ref naming that class was written differently
    explicit ClassNewSpelling( std::size_t files ) : first( files ), mixed( files, 0 ) {}
    static std::string written( const Reference& r )
    {
        std::string out( 1, char( '0' + int( r.recv ) ) );
        for( const std::string* part : { &r.qualifier, &r.recvVar, &r.memberRoot, &r.memberPath } )
        {
            out.append( 1, '|' ).append( *part );
        }
        return out;
    }
    void adopt( const Reference& r ) { first[ r.fileId ] = written( r ); mixed[ r.fileId ] = 0; }
    void note( const Reference& r ) { mixed[ r.fileId ] |= char( written( r ) != first[ r.fileId ] ); }
    void hedge( ClassNewRow& row ) const { row.line = mixed[ row.testFile ] ? 0 : row.line; }   // the emitter omits l= for line 0
};

// THE l= RULE FOR TS/JS (LangFacts importBoundConstruction): a construction counts for the row only when its WRITTEN callee RESOLVES to the
// reached class through the import resolver the call binder uses (graph.h pinJsImport over buildJsExportTables) — never by the name it is
// written with, never by which module it comes from. In the test file:
//   - `new X()`: X's import binding (`import { A as X }`, `import X` = the module's "default", a `const { A: X } = require( m )`) pins the
//     exporting module's definition of the IMPORTED name, export-side renames (`export { Foo as Eng }`) included;
//   - `new N.X()`: N is a whole-module binding (`import * as N`, `const N = require( m )`) and X the module's export of that name;
//   - a name a JsShadow span hides at the site (a parameter `Eng`), a name bound twice, no import binding at all (a class declared in the test,
//     a global), a module the resolver does not place (a tsconfig alias, a package) and an export the table does not list (a re-export
//     `export { X as Y } from`, `export *`: ingest_jsimports.h records none, the call binder falls back to the name ladder there) resolve to
//     NOTHING, so they never give the line. The row's l= is the earliest construction that resolves to the class; none → no l= (row kept).
struct ClassNewJsBinds
{
    struct Bound
    {
        NodeId        node     = kNoNode;   // a named/default/destructure binding: the definition it pins
        std::uint32_t nsModule = kNoFile;   // a whole-module binding: the module file
    };
    JsExportTables       ex;
    HashMap<std::string, Bound> bound;   // "<fileId>#<local>" (jsImportKey) for the row test files only; two bindings of one name: an empty Bound

    ClassNewJsBinds( const IngestResult& ing, const std::vector<char>& wanted ) : ex( buildJsExportTables( ing ) )
    {
        for( const Binding& b : ing.bindings )
        {
            const bool whole = b.kind == LocalBindKind::ModuleAlias && b.importedName == "*";
            if( b.fileId >= wanted.size() || !wanted[ b.fileId ] || b.isFromAssignment
                || ( b.kind != LocalBindKind::JsImport && b.kind != LocalBindKind::ModuleAlias ) )
            {
                continue;
            }
            Bound v;
            if( whole )
            {
                const JsModuleCtx ctx{ ex.files, nullptr, ex.vocabulary };
                v.nsModule = resolveJsImportModule( rootRelPath( ing, b.fileId ), b.typeName, b.fileId, ctx ).first;
            }
            else
            {
                const JsImportTarget t = pinJsImport( ing, ex, nullptr, b.fileId, b.typeName, b.importedName );
                v.node                 = t.outcome == JsImportOutcome::Pinned ? t.node : kNoNode;
            }
            const auto [ it, inserted ] = bound.try_emplace( jsImportKey( b.fileId, b.var ), v );
            if( !inserted )
            {
                it->second = Bound{};   // one local name, two bindings: never choose one (buildJsImportTables' rule)
            }
        }
    }

    // The definition the construction `r` builds, or kNoNode when the resolver cannot say.
    NodeId resolve( const Reference& r ) const
    {
        if( r.memberCall && ( r.memberRoot.empty() || !r.memberPath.empty() ) )
        {
            return kNoNode;   // `new (f()).X()`, `new a.b.X()`: no one-hop module member
        }
        const std::string key   = jsImportKey( r.fileId, r.memberCall ? r.memberRoot : r.calleeName );
        const auto        spans = ex.shadows.find( key );
        if( spans != ex.shadows.end()
            && std::ranges::any_of( spans->second, [ & ]( const VarSpan& v ) { return r.startByte >= v.startByte && r.startByte < v.endByte; } ) )
        {
            return kNoNode;
        }
        const auto it = bound.find( key );
        if( it == bound.end() )
        {
            return kNoNode;
        }
        if( !r.memberCall )
        {
            return it->second.node;
        }
        return it->second.nsModule == kNoFile ? kNoNode : jsExportedNode( ex, it->second.nsModule, r.calleeName );
    }
};

// One call reference from a constructing caller, offered to its test file's row: adopt it when it is a construction of the site's class (TS/JS:
// it resolves to the class, ClassNewJsBinds; else it passes the name test) and is as near a class and earlier than the row's line. Outside TS/JS
// a second ref to the row's class spelled differently marks the row's line unreliable.
inline void classNewOffer( const ClassNewScan& s, const Reference& r, const ClassNewSite& site, ClassNewRow& cur, ClassNewSpelling& spelling,
                           const ClassNewJsBinds* js )
{
    const ClassNewRow cand{ r.fileId, r.line, site.cls, s.classRank[ site.cls ], site.target };
    const bool        resolved = langFacts( r.lang ).importBoundConstruction;
    const bool        builds   = resolved ? js != nullptr && js->resolve( r ) == site.cls : classNewCallNames( s.ing, r, site );
    if( !builds || cand.rank > cur.rank )
    {
        return;
    }
    const bool sameClass = !resolved && cur.line != 0 && cur.cls == site.cls;
    if( sameClass )
    {
        spelling.note( r );
    }
    if( cur.line == 0 || std::tie( cand.rank, cand.line ) < std::tie( cur.rank, cur.line ) )
    {
        if( !sameClass && !resolved )
        {
            spelling.adopt( r );
        }
        cur = cand;
    }
}

// Step 5: per test file, the nearest class, then its earliest construction line (a call reference from that caller naming the target).
inline std::vector<ClassNewRow> classNewBestRows( const ClassNewScan& s, std::span<const ClassNewSite> sites )
{
    const IngestResult&      ing = s.ing;
    std::vector<ClassNewRow> best( ing.files.size(), ClassNewRow{ 0, 0, kNoNode, ClassNewScan::kUnreached, kNoNode } );
    ClassNewSpelling         spelling( best.size() );
    for( const ClassNewSite& site : sites )
    {
        const std::uint32_t f = ing.symbols[ site.caller ].fileId;
        if( best[f].cls == kNoNode || s.classRank[ site.cls ] < best[f].rank )
        {
            best[f] = ClassNewRow{ f, 0, site.cls, s.classRank[ site.cls ], site.target };
        }
    }
    std::vector<char> jsRow( best.size(), 0 );   // a TS/JS test file holding a row: its constructions resolve through ClassNewJsBinds
    for( const ClassNewSite& site : sites )
    {
        jsRow[ ing.symbols[ site.caller ].fileId ] |= char( langFacts( ing.symbols[ site.caller ].lang ).importBoundConstruction );
    }
    const std::optional<ClassNewJsBinds> js = std::ranges::any_of( jsRow, []( char c ) { return c != 0; } )
                                                  ? std::optional<ClassNewJsBinds>( std::in_place, ing, jsRow ) : std::nullopt;
    for( const Reference& r : ing.references )
    {
        if( r.role != RefRole::Call || r.isCompose || r.isDocLink || r.fileId >= best.size() || best[ r.fileId ].cls == kNoNode )
        {
            continue;
        }
        const auto [ lo, hi ] = std::equal_range( sites.begin(), sites.end(), ClassNewSite{ r.fromSymbol, 0, kNoNode },
                                                  []( const ClassNewSite& a, const ClassNewSite& b ) { return a.caller < b.caller; } );
        for( auto it = lo; it != hi; ++it )
        {
            classNewOffer( s, r, *it, best[ r.fileId ], spelling, js ? &*js : nullptr );
        }
    }
    std::vector<ClassNewRow> rows;
    std::copy_if( best.begin(), best.end(), std::back_inserter( rows ), []( const ClassNewRow& r ) { return r.cls != kNoNode; } );
    std::ranges::for_each( rows, [ & ]( ClassNewRow& r ) { spelling.hedge( r ); } );
    return rows;
}

// The backstop rows, nearest class first (rank), then test path; ONE row per test file (its earliest construction of
// the nearest class). Cost: nothing past one O(symbols) pass unless the walk reached a member of some class.
inline std::vector<ClassNewRow> classNewTestRows( const IngestResult& ing, const Graph& g, const AffectedSeeds& sel, const AffectedAnswer& ans )
{
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    ClassNewScan        s{ ing };
    s.N = NodeId( ing.symbols.size() );
    s.isTestFile.assign( F, 0 );
    for( std::uint32_t f = 0; f < F; ++f )
    {
        s.isTestFile[f] = isTestPath( rootRelPath( ing, f ) ) ? 1 : 0;
    }
    s.fileMarked.assign( F, 0 );
    s.hop.assign( s.N, ClassNewScan::kUnreached );
    s.classesIn.resize( F );
    s.classRank.assign( s.N, ClassNewScan::kUnreached );
    classNewMarkReached( s, sel, ans );
    if( !classNewRankOwners( s ) )
    {
        return {};
    }
    std::vector<char> proven( F, 0 );
    for( const TestRow& r : ans.rows )
    {
        proven[ r.fileId ] = 1;
    }
    const std::vector<ClassNewTarget> targets = classNewTargets( s );
    const std::vector<ClassNewSite>   sites   = classNewSites( s, g, targets, proven );
    std::vector<ClassNewRow>          rows    = classNewBestRows( s, sites );
    std::sort( rows.begin(), rows.end(), [ & ]( const ClassNewRow& a, const ClassNewRow& b )
               {
                   if( a.rank != b.rank ) { return a.rank < b.rank; }
                   return ing.files[ a.testFile ] < ing.files[ b.testFile ];
               } );
    DASSERT( std::ranges::all_of( rows, [ & ]( const ClassNewRow& r )
                                  { return s.isTestFile[ r.testFile ] && !proven[ r.testFile ] && isConstructibleClassKind( ing.symbols[ r.cls ].kind )
                                           && r.target < s.N && r.rank != ClassNewScan::kUnreached; } ),
             "classNewTestRows: every row is an unproven TEST file that constructs a class owning a reached symbol — never a proven row (a scan: debug only)" );
    return rows;
}

// ── §P11.2b — the INVERSE: what does this test exercise? ─────────────────────────────────────────────
// Seeds are every symbol of every matched TEST file; the answer is graph.h's forwardReach from them, minus
// everything that is itself test code. Refusal on a non-test path is deliberate and is stated in --help:
// the verb's whole content is the test/non-test PARTITION (it SUBTRACTS test code from the answer), and on
// a non-test file that subtraction is meaningless — "everything this file transitively calls" is a
// different question, already answered by --callees (1 hop) and --graph-query's bounded callees closure.
// Answering it generically here would make one verb quietly mean two things depending on its argument.
struct ExerciseSeeds
{
    std::vector<NodeId>        seeds;              // every symbol of the matched test files, id asc
    std::vector<std::uint32_t> testFiles;          // the matched TEST files, path asc
    std::uint32_t              nonTestMatches = 0; // matched files that are NOT test paths (the refusal reason)
    bool                       anyFileMatched = false;
};

inline ExerciseSeeds resolveExerciseSeeds( const IngestResult& ing, std::string_view spec )
{
    ExerciseSeeds          sel;
    const std::string_view pathPattern = stripLineLocator( spec );      // §P8 seam 2: a pasted `path:line` row means the path
    std::vector<char>      isSeedFile( ing.files.size(), 0 );
    for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ); ++f )
    {
        // #228/A1: same seam as resolveAffectedSeeds above — match the root-relative spelling.
        if( !filePathContainsRootRel( ing, f, pathPattern ) )
        {
            continue;
        }
        sel.anyFileMatched = true;
        if( !isTestPath( rootRelPath( ing, f ) ) ) { ++sel.nonTestMatches;  continue; }
        isSeedFile[f] = 1;
        sel.testFiles.push_back( f );
    }
    std::sort( sel.testFiles.begin(), sel.testFiles.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );
    for( NodeId i = 0; i < NodeId( ing.symbols.size() ); ++i )
    {
        if( isSeedFile[ing.symbols[i].fileId] )
        {
            sel.seeds.push_back( i );
        }
    }
    return sel;
}

// The non-test symbols the seeds transitively call. The seeds are test symbols, so the isTestPath filter
// removes them for free — no separate "minus the seeds" pass that could disagree with the partition.
inline std::vector<NodeId> exercisedSymbols( const IngestResult& ing, const Graph& g, const std::vector<NodeId>& seeds )
{
    const std::vector<char> reached = forwardReach( g, seeds );
    std::vector<NodeId>     out;
    for( NodeId i = 0; i < NodeId( reached.size() ) && i < NodeId( ing.symbols.size() ); ++i )
    {
        if( reached[i] && !isTestPath( rootRelPath( ing, ing.symbols[i].fileId ) ) )
        {
            out.push_back( i );
        }
    }
    return out;
}

// ── §P11.4 — run=, the runner hint on a test row ─────────────────────────────────────────────────────
// --affected/--situ/--test-gate NAME `.cpp` harnesses; the runners are `test/*.sh` (or `*.py`). --test-gate
// EXITS 4 on that obligation, so the one verb family whose job is "here is what to run before you ship"
// produced an obligation its own output could not discharge.
//
// TWO evidence kinds, both REAL — never a guess. An ABSENT run= means "not derivable", and that is the
// whole contract: falling back to the repo's suite runner would emit a plausible command that may not run
// the named harness at all — §P0's fabricated confidence, in command form, on a row the agent is being
// told to act on.
//   (1) STEM    — a runner whose basename stem equals the harness's        (samename.cpp <-> samename.sh)
//   (2) MENTION — a runner whose TEXT contains the harness's basename      (clonebandcheck.sh names
//                 cloneband_harness.cpp). This is the shape that dominates in practice: none of this
//                 repo's four *_harness.cpp files stem-matches its gate.
// Stem beats mention; among several mentioners the path-ascending first wins, so the hint is deterministic.
// Both are honest evidence: a script that names the harness does drive it.
//
// COST: runner evidence is lazy and commands are cached per file. The mention scan loads candidate texts
// once when needed; verbs that emit no test rows perform none of these reads or parses.
// A3 / review of #219: run= is spelled relative to root= exactly when the run HAS one root and declares it.
// A multi-root run's disk path lies under no single root, so its command must stay absolute — and the legend
// sentence below is gated on this SAME predicate, so the spelling and the claim cannot disagree.
inline bool runsAreRootRelative( const IngestResult& ing, std::string_view root ) noexcept
{
    return ing.realPaths.empty() && !root.empty();
}

class TestRunnerIndex
{
public:
    // A3 (one absolute root per document): `root` bounds Python runner evidence and spells commands relative
    // to the crawl root — the same rootPrefixOf/rootRelativeUri pair every p= emitter uses.
    // Defaulted to "" so a caller that has no root (or a multi-root run, where the disk path is not under any
    // single root) keeps the absolute spelling: an unrelativizable command must stay pasteable, never become
    // a path relative to a root that does not contain it.
    /// Index candidate test scripts in path order without reading their contents.
    /// ing must outlive the index; root controls single-root evidence boundaries and command spelling.
    explicit TestRunnerIndex( const IngestResult& ing, std::string_view root = {} )
        : ing_( &ing ),
          rootPrefix_( runsAreRootRelative( ing, root ) ? rw::sarif::rootPrefixOf( root ) : std::string() )
    {
        for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ); ++f )
        {
            if( isTestPath( rootRelPath( ing, f ) ) && runnerVerb( ing.files[f] ) != nullptr )
            {
                runners_.push_back( f );
            }
        }
        std::sort( runners_.begin(), runners_.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );
    }

    // The pasteable command for `fileId`, or "" when no REAL runner is derivable.
    const std::string& commandFor( std::uint32_t fileId ) const
    {
        static const std::string kNoRunner;
        if( fileId >= ing_->files.size() )
        {
            return kNoRunner;
        }
        const auto cached = cache_.find( fileId );
        if( cached != cache_.end() )
        {
            return cached->second;
        }
        return cache_.emplace( fileId, derive( fileId ) ).first->second;
    }

    // Whether the commands this index spells are relative to a root — the SAME fact the legend sentence
    // is gated on, read off the index rather than re-derived at each legend site.
    bool rootRelative() const noexcept { return !rootPrefix_.empty(); }

    /// Return this file's own validated script command, or empty for an invalid ID or unknown runner.
    /// Unlike commandFor, this does not search for another script that drives the file.
    std::string commandForScript( std::uint32_t fileId ) const
    { return fileId < ing_->files.size() && runnerVerb( ing_->files[fileId] ) != nullptr ? spell( fileId ) : std::string(); }

private:
    // #323: the JS/TS placeholder verb — NEVER emitted. runnerVerb()'s only job for these extensions is to
    // mark the file a CANDIDATE (non-null ⇒ "index it", "it is self-runnable", the same two questions the
    // .sh/.py rows answer); spellUncached() always overrides this exact pointer with jsrunner's evidence-
    // derived verb, or refuses, before any concatenation happens. Comparing by pointer identity (not by
    // re-checking the extension a second time) is safe and intentional: this is the one static object both
    // sides of the table share, not two string literals that could be merged or not at the compiler's whim.
    static constexpr const char* kJsEvidenceVerb = "js-evidence-pending";

    // Candidate script kinds. Python's and JS/TS's verbs are provisional until spellUncached verifies runner
    // evidence — a .py/.ts/.js extension alone never spells a command (a main-guard/pytest project, or a
    // package.json naming vitest/jest/node --test, must say so first).
    /// Return the extension-based candidate interpreter, or nullptr for an unsupported script kind.
    static const char* runnerVerb( std::string_view path ) noexcept
    {
        struct RunnerRow { std::string_view ext; const char* verb; };
        static constexpr RunnerRow kRunnerKinds[] = {
            { ".sh", "bash" }, { ".py", "python3" },
            // #323: TS/JS test-file EXTENSIONS — same set resolve.h/ingest_crawl.h already recognize as
            // TypeScript/JavaScript sources. This is an EXTENSION table only: it still matches a ".d.ts"
            // declaration file (a "d." prefix is invisible to a suffix check) or a non-test helper under a
            // test/ directory, so neither is rejected HERE. rv-test-gate-tsjs F4: the actual "is this
            // something vitest/jest would run" decision — never a .d.ts, and only a .test./.spec./
            // __tests__/-shaped name — is resolveJsVerb's own jsrunner::looksLikeJsTestFile call, below;
            // a rejected candidate still falls through to matchingRunner's shell/py-driver search (F1).
            { ".ts", kJsEvidenceVerb }, { ".tsx", kJsEvidenceVerb }, { ".mts", kJsEvidenceVerb }, { ".cts", kJsEvidenceVerb },
            { ".js", kJsEvidenceVerb }, { ".jsx", kJsEvidenceVerb }, { ".mjs", kJsEvidenceVerb }, { ".cjs", kJsEvidenceVerb },
        };
        for( const RunnerRow& r : kRunnerKinds )
        {
            if( path.size() > r.ext.size() && path.compare( path.size() - r.ext.size(), r.ext.size(), r.ext ) == 0 )
            {
                return r.verb;
            }
        }
        return nullptr;
    }

    // basename / stem come from mention.h's ONE pair (mention_detail::baseNameOf + stripExt) — the same
    // primitives binstale.h, gitmine.h and docdrift.h already stem paths with. Re-rolling them here is
    // exactly the new-clone-of-a-reused-helper --quality-delta reports, and it would also fork the
    // "strip the LAST dot" convention that every other stemming call site in this repo shares.
    static std::string_view stemOf( std::string_view p ) noexcept { return mention_detail::pathStem( p ); }

    /// Return whether two valid file IDs belong to the same crawl root; single-root files always do.
    bool sameRoot( std::uint32_t a, std::uint32_t b ) const noexcept
    {
        return ing_->realPaths.empty() || ing_->fileRoot[a] == ing_->fileRoot[b];
    }

    /// Read candidate script contents once, aligned with runners_; unreadable files supply no mentions.
    void loadTexts() const
    {
        if( textsLoaded_ )
        {
            return;
        }
        textsLoaded_ = true;
        texts_.resize( runners_.size() );
        for( std::size_t i = 0; i < runners_.size(); ++i )
        {
            if( !isDriverCandidate( runners_[i] ) )
            {
                continue;   // a TS/JS entry is never another row's driver (matchingRunner), so its text is never read
            }
            texts_[i] = docparse::detail::readWholeFile( diskPath( *ing_, runners_[i] ) ).value_or( std::string() ); // unreadable ⇒ no evidence, never a guess
        }
    }

    /// Script kinds use only their own runner evidence; other files try same-root stem/text matches.
    /// fileId must be valid; return empty when the applicable evidence cannot establish a command.
    std::string derive( std::uint32_t fileId ) const
    {
        const std::string& target = ing_->files[ fileId ];
        const char*        verb   = runnerVerb( target );
        if( verb != nullptr )
        {
            // M21(b) (capture-audit 2026-09-04): a runner script IS the command, and this used to return ""
            // — which was harmless while "" meant only "nothing to ADD to p=". It stopped being harmless the
            // moment "" acquired a MEANING: run_unknown="1" asserts no runner is derivable, and for a row
            // whose own path is directly runnable that assertion is simply false. So the self-runnable case
            // now spells its own command, exactly as commandForScript already does for a shell gate.
            // Missing Python evidence means unknown, not permission to borrow another file's runner — a
            // Python file's OWN main-guard/pytest evidence decides its OWN command, full stop.
            //
            // rv-test-gate-tsjs F1: TS/JS is DIFFERENT, on purpose, not by the same rule. A .sh/.py script
            // is intrinsically runnable (bash/python3 need nothing but the path); a .ts/.js file is not —
            // whether it is runnable at ALL depends on a package.json this repo may not even have, so
            // "no package.json evidence" is not this file's own considered unknown the way "no main guard"
            // is for Python — it is simply NO EVIDENCE YET, and a named shell/py driver mentioning this
            // exact file (matchingRunner, below) is real evidence a TS/JS row should not be denied. Only
            // .sh/.py keep the old short-circuit; a TS/JS command's own evidence, if any, still wins here
            // first — this is a FALLBACK for the miss, never a preference over real JS evidence.
            std::string command = spell( fileId );
            if( !command.empty() || verb != kJsEvidenceVerb )
            {
                return command;
            }
        }

        if( std::string command = matchingRunner( fileId, true ); !command.empty() )
        {
            return command;
        }
        loadTexts();
        return matchingRunner( fileId, false );
    }

    // A DRIVER is a shell or Python script: the F1 fallback above is "a named shell/py driver mentioning this exact
    // file", and that is all it may search (CodeRabbit on #331). runners_ also holds the #323 TS/JS entries so they
    // can spell their OWN command; left in this search, a jest/vitest test that merely mentions another row's file
    // (`require("./util.js")`) became that row's runner, and loadTexts read every TS/JS test file to find out.
    bool isDriverCandidate( std::uint32_t candidate ) const noexcept
    {
        return runnerVerb( ing_->files[candidate] ) != kJsEvidenceVerb;
    }

    // Stem first, then mention; skip candidates that have no runnable command. Both passes are path-sorted.
    /// Return the first runnable same-root match in path order, or empty if there is none.
    /// fileId must be valid; byStem selects stem matching, otherwise loadTexts must have run first.
    std::string matchingRunner( std::uint32_t fileId, bool byStem ) const
    {
        const std::string_view target = ing_->files[fileId];
        for( std::size_t i = 0; i < runners_.size(); ++i )
        {
            const std::uint32_t candidate = runners_[i];
            if( !sameRoot( fileId, candidate ) || !isDriverCandidate( candidate ) )
            {
                continue;
            }
            const bool matches = byStem ? stemOf( ing_->files[candidate] ) == stemOf( target )
                : texts_[i].find( mention_detail::baseNameOf( target ) ) != std::string::npos;
            if( matches )
            {
                if( std::string command = spell( candidate ); !command.empty() )
                {
                    return command;
                }
            }
        }
        return {};
    }

    // Spelled against the ON-DISK path (diskPath), so a multi-root `<label>/<rel>` identity spelling — which
    // is a label, not a directory — can never leak into something a shell would mis-resolve. A leading "./"
    // is dropped for readability; the result is pasteable from the repo root.
    // CWE-78, security review of #219. A run= is a COMMAND, and the path inside it comes from the CRAWLED
    // CORPUS, so the corpus decides its bytes. `test/check;touch PWNED.sh` is a legal filename, and plain
    // concatenation emitted `bash test/check;touch PWNED.sh` — a command this tool tells an agent to paste,
    // which would run `touch PWNED` in the reader's shell. The path is now always emitted as ONE argument.
    //
    // QUOTED WHEN NOT PROVABLY SAFE, rather than unconditionally, and the difference is measured rather than
    // preferred. shSingleQuote always wraps, so quoting unconditionally would move the run= bytes of every
    // row in eight emitters: 13 literal command assertions across 7 gates, docs/COMMANDS.md, 15 committed
    // capture snapshots, README, and the printf_parity pins — a documented output-format change for every
    // user. Every path `git ls-files` tracks in this repo, and every runner path under test/, is in the safe
    // set (measured: 0 of either outside it, apart from the bracket-named test/testgatenestedfix fixtures), so the conditional form is byte-identical on every real corpus
    // while a hostile name is still quoted. The predicate is an ALLOWLIST, so a byte nobody enumerated is
    // quoted by default instead of passed through — which is the direction a quoting bug should fail in.
    static bool isShellSafePath( std::string_view p ) noexcept
    {
        if( p.empty() || p.front() == '-' )   // a leading '-' is read as a FLAG, not a path
        {
            return false;
        }
        for( const char c : p )
        {
            const bool isSafeByte = ( c >= 'A' && c <= 'Z' ) || ( c >= 'a' && c <= 'z' ) || ( c >= '0' && c <= '9' )
                                    || c == '.' || c == '_' || c == '/' || c == '-';
            if( !isSafeByte )
            {
                return false;
            }
        }
        return true;
    }

    /// Cache a candidate file's command, including an empty result, to avoid repeated evidence reads.
    /// runnerFile must identify an indexed file with a supported script extension.
    std::string spell( std::uint32_t runnerFile ) const
    {
        if( scriptCache_.empty() )
        {
            scriptCache_.reserve( runners_.size() );
        }
        auto [ entry, inserted ] = scriptCache_.try_emplace( runnerFile );
        if( inserted )
        {
            entry->second = spellUncached( runnerFile );
        }
        return entry->second;
    }

    // The crawl root a runnerFile's evidence search is bounded to — the ONE string both the Python and
    // TS/JS evidence walks need, factored out so spellUncached itself carries one fewer inline branch.
    std::string_view evidenceRoot( std::uint32_t runnerFile ) const
    {
        return ing_->realPaths.empty() ? std::string_view( rootPrefix_ )
            : std::string_view( ing_->rootPaths[ ing_->fileRoot[ runnerFile ] ] );
    }

    // #323: the TS/JS verb, decided ENTIRELY by the nearest package.json's own evidence (walking up from
    // the test file, like pytest's project search below) — no extension-based default, ever. Kept out of
    // spellUncached so that function's own branching stays at its pre-#323 shape; nullptr here is DISCLOSED
    // by construction, since spellUncached's "" ⇒ runHint's run_unknown="1" rule (testmap.h's M21(b)
    // banner) already reads an empty command as "not derivable", never a guessed default.
    // rv-test-gate-tsjs F4: a file whose NAME does not look like a vitest/jest target (never a helper, a
    // setup file, or a `.d.ts`) is rejected before the manifest is even read — package.json evidence names
    // WHICH runner exists, never WHICH files that runner would collect. A rejection here is not final: the
    // caller (derive()) falls through to matchingRunner's shell/py-driver search, same as any other miss.
    // The name test reads the ROOT-RELATIVE path, never `disk` (CodeRabbit on #331): the `__tests__/` segment scan
    // over an absolute path also matched directories ABOVE the crawl root, so a checkout under /work/__tests__/repo/
    // spelled test/setup.ts as a vitest target that every other checkout reads run_unknown="1" — output that
    // depended on where the repo sits (the #228/A1 rule isTestPath already follows).
    //
    // #60 (train 20): package.json evidence still goes first and, when it DECIDES anything — including an
    // authoritative-but-unrecognized scripts.test (mocha, say) — still WINS; only when it decides nothing
    // (no manifest anywhere in the boundary, or the nearest one is a true marker per nearestPackageManifests's
    // own F5 rule) does the test file's OWN node:test import/require get a say. That ordering is what makes
    // the precedence gate arm hold without any special-casing here: a manifest naming vitest/jest/node --test
    // already returns below, before jsrunner::hasNodeTestImport is ever consulted.
    //
    // rv-nodetest-runner-60 fix round: jsrunner::nodeTestVerb now also needs the test file's OWN bytes (F1
    // extension refusal, F2 relative-import resolvability) in addition to `engines.node` (F3) — a run=
    // that fails is worse than an honest run_unknown="1" — so `source` is read on BOTH paths that can reach
    // it, not only the import-fallback path below.
    const char* resolveJsVerb( std::uint32_t runnerFile, const std::string& disk, std::size_t& climbs ) const
    {
        const std::string_view relPath = rootRelPath( *ing_, runnerFile );
        if( !jsrunner::looksLikeJsTestFile( relPath ) )
        {
            return nullptr;
        }
        const jsrunner::PackageManifests manifests = jsrunner::nearestPackageManifests( disk, evidenceRoot( runnerFile ) );   // train20-cr C8: + Node's package scope
        const std::string&               manifest  = manifests.evidence;
        climbs                                     = manifests.evidenceClimbs;   // #335: the package directory, for spellJsRun's cd
        const jsrunner::Framework        fw        = jsrunner::detectFramework( manifest );
        if( fw == jsrunner::Framework::NodeTest )
        {
            // #60: node's own runner needs a Node-version decision (see jsrunner.h's own banner) whether it
            // was named by scripts.test or (below) inferred from the test file's own import — one spelling.
            const std::string source = docparse::detail::readWholeFile( disk ).value_or( "" );
            return jsrunner::nodeTestVerb( relPath, manifests, source, disk );
        }
        if( const char* verb = jsrunner::verbFor( fw ); verb != nullptr )
        {
            // vitest/jest: explicit package.json evidence, never overridden by import evidence. The evidence names WHICH
            // runner; the runner's default include says whether it would collect this file (#330, @rainhuang0220).
            return jsrunner::matchesDefaultInclude( fw, relPath ) ? verb : nullptr;
        }
        if( !manifest.empty() && jsrunner::hasAuthoritativeScript( manifest ) )
        {
            return nullptr;   // an explicit (if unrecognized) scripts.test still wins — never overridden
        }
        const std::string source = docparse::detail::readWholeFile( disk ).value_or( "" );
        if( !jsrunner::hasNodeTestImport( source, relPath ) )
        {
            return nullptr;   // no package.json evidence, and the file's own bytes name no runner either
        }
        return jsrunner::nodeTestVerb( relPath, manifests, source, disk );
    }

    /// #335: the first `n` '/'-separated components of a root-relative path (n >= 1; the whole path when it has
    /// fewer). A package directory is a prefix of its test files' root-relative path.
    static std::string_view leadingComponents( std::string_view p, std::size_t n ) noexcept
    {
        std::size_t end = 0;   // one past the last '/' consumed
        for( std::size_t i = 0; i < n; ++i )
        {
            end = p.find( '/', end );
            if( end == std::string_view::npos )
            {
                return p;
            }
            ++end;
        }
        return p.substr( 0, end - 1 );
    }

    /// #335: the TS/JS run= for one test file, given its verb (resolveJsVerb) and how many directories the
    /// manifest walk climbed to find the deciding manifest (`climbs`, npos = none decided). vitest and jest find a
    /// package's config, path aliases and node_modules from the package directory, so a package BELOW root= is
    /// entered in a subshell, `(cd <pkg> && <runner> <path>)`, and the path after the cd is package-relative. The parentheses keep
    /// the cd from outliving the command, so a second pasted row still starts at root= (an agent shell that keeps its cwd between calls).
    /// A package AT root= needs no cd, and a multi-root run has no root= to cd from, so both keep the plain spelling.
    /// vitest and jest take the path as a substring filter, so it is one quoted argument with no `--` (which ended
    /// their options and dropped the filter, so a bracketed route ran the whole suite). A path a CLI would read as
    /// an option (leading '-') has no spelling that runs it, and node's own runner globs its file arguments
    /// (`c[1].test.js` matched no file; node exits 1): both get no run=, the honest run_unknown.
    std::string spellJsRun( const char* verb, std::string_view p, std::size_t climbs ) const
    {
        const auto token = []( std::string_view s )
        { return isShellSafePath( s ) ? std::string( s ) : rw::shSingleQuote( std::string( s ) ); };
        std::string_view rel = p;
        std::string      cd;
        std::string      closeSub;   // ")" when cd opened a subshell
        std::size_t      dirs = 0;   // directory components of the file: its '/' count
        for( const char c : p )
        {
            dirs += ( c == '/' ) ? 1 : 0;
        }
        if( rootRelative() && climbs < dirs )
        {
            const std::string_view pkgDir = leadingComponents( p, dirs - climbs );
            rel                           = p.substr( pkgDir.size() + 1 );
            // a directory named "-x" would read as a cd option; "./" makes it a path
            const std::string dir = pkgDir.front() == '-' ? "./" + std::string( pkgDir ) : std::string( pkgDir );
            cd                    = "(cd " + token( dir ) + " && ";
            closeSub              = ")";
        }
        if( rel.empty() || rel.front() == '-' )
        {
            return {};
        }
        if( std::string_view( verb ).starts_with( "node " ) && rel.find_first_of( "*?[]{}()!\\" ) != std::string_view::npos )
        {
            return {};
        }
        std::string arg( rel );
        if( std::string_view( verb ).ends_with( "jest" ) && ( !cd.empty() || !isShellSafePath( rel ) ) )
        {
            // jest reads the argument as a regex: escape the metacharacters a route path carries. A package below root= always
            // gets it (a plain dot would also match `aXtest.js`); a package at root= keeps its stored spelling unless it needs quoting
            std::string esc;
            for( const char c : rel )
            {
                if( std::string_view( "[](){}.+*?^$|\\" ).find( c ) != std::string_view::npos )
                {
                    esc += '\\';
                }
                esc += c;
            }
            arg = std::move( esc );
        }
        return cd + std::string( verb ) + " " + token( arg ) + closeSub;
    }

    /// Validate a candidate script and format its disk path as one shell argument.
    /// runnerFile must have a supported extension; Python without main-guard or pytest evidence, or TS/JS
    /// without a package.json naming vitest/jest/node --test, yields empty (never a guessed default).
    /// Commands are root-relative only for single-root scans, with quoting and option separation as needed. A TS/JS
    /// package below root= is entered in a `(cd <pkg> && ...)` subshell (spellJsRun).
    std::string spellUncached( std::uint32_t runnerFile ) const
    {
        const std::string& disk = diskPath( *ing_, runnerFile );
        const char* verb = runnerVerb( disk );
        if( disk.ends_with( ".py" ) )
        {
            const std::string source = docparse::detail::readWholeFile( disk ).value_or( "" );
            if( !pythonrunner::hasMainGuard( source ) )
            {
                if( !pythonrunner::hasPytestProject( disk, evidenceRoot( runnerFile ) ) )
                {
                    return {};   // Django / unittest modules need a project runner; python3 may run zero tests.
                }
                verb = "pytest";
            }
        }
        else if( verb == kJsEvidenceVerb )
        {
            std::size_t climbs = std::string::npos;
            verb               = resolveJsVerb( runnerFile, disk, climbs );
            if( verb == nullptr )
            {
                return {};   // no package.json in the crawl boundary, or none of the three named runners it declares
            }
            return spellJsRun( verb, rw::sarif::rootRelativeUri( disk, rootPrefix_ ), climbs );
        }
        // A3: root-relative, like every p= beside it. rootRelativeUri strips a leading "./" unconditionally,
        // so the readability strip the pre-A3 code did by hand is the SAME call now, not a second rule.
        std::string_view p = rw::sarif::rootRelativeUri( disk, rootPrefix_ );
        if( isShellSafePath( p ) )
        {
            return std::string( verb ) + " " + std::string( p );
        }
        // QUOTING WAS NECESSARY AND NOT SUFFICIENT — third review of #219, a bypass of the fix above. The
        // quoted form hands the path to the shell as ONE argument, which is the whole point, and then the
        // INTERPRETER parses it: a root-level `-cimport os;open("PWNED","w")#_test.py` passes isTestPath,
        // keeps its leading dash through normalisation, survives quoting intact — and `python3` reads `-c`
        // as "execute this code". The path never reaches the shell as code; it reaches the interpreter as an
        // OPTION. Same trust boundary as the injection above: corpus filename → run= → a reader pastes it.
        //
        // MEASURED, both directions, on the original shell and Python script verbs:
        //   python3 '<-c…#_test.py>'     rc=0, created the payload file   — bypass reproduced
        //   python3 -- '<same path>'     rc=7 (the file's own status), no side effect
        //   bash    -- '<-c…#_test.sh>'  rc=7, no side effect
        // bash did NOT reproduce the bypass with the equivalent payload (it rejected the combined -c form,
        // rc=1), so the confirmed case is python3; `--` is emitted for both because both honour it and the
        // cost is zero on every real path. pytest also honours `--`: runhint_python.py executes its emitted
        // hints for both shell-metacharacter and leading-dash paths when pytest is available.
        //
        // Conditional for the same measured reason as the quoting: a leading '-' is already outside
        // isShellSafePath, so `--` costs bytes only where the path is hostile and every real corpus stays
        // byte-identical (printffmtparitycheck needs no re-pin).
        return std::string( verb ) + " -- " + rw::shSingleQuote( std::string( p ) );
    }

    const IngestResult*                         ing_;
    std::string                                 rootPrefix_;   // A3: "" ⇒ the command keeps its stored spelling
    std::vector<std::uint32_t>                  runners_;
    mutable std::vector<std::string>            texts_;
    mutable bool                                textsLoaded_ = false;
    mutable HashMap<std::uint32_t, std::string> cache_;
    mutable HashMap<std::uint32_t, std::string> scriptCache_;
};

// The ` run="…"` attribute for one test row, or "" — the ONE spelling, so the four emitters (--affected,
// --exercises' seed rows, --test-gate's XML and its JSON sibling) cannot disagree about quoting or escaping.
// ONE renderer for all four emitters (--affected, --exercises' seed rows, --test-gate's XML and its JSON
// sibling, --situ's text lines). The three output shapes differ only in their delimiters, so they are
// PARAMETERS, not three near-identical functions: the load-bearing half is the `cmd.empty()` branch — the
// "absent means not derivable" rule — and that must exist exactly once or a later edit will fix it in one
// shape and leave a fabricated command in another. `esc` is the caller's escaper (escapeXml / jsonStr /
// identity), passed in rather than included, so this header stays below serialize.h in the include order.
template<class EscapeFn>
inline std::string runHint( const TestRunnerIndex& idx, std::uint32_t fileId,
                            std::string_view open, std::string_view close, EscapeFn esc )
{
    const std::string& cmd = idx.commandFor( fileId );
    if( cmd.empty() )
    {
        return {};
    }
    return std::string( open ) + esc( cmd ) + std::string( close );
}

// The three call shapes, named so a caller never spells a delimiter by hand.
template<class EscapeFn>
inline std::string runAttr( const TestRunnerIndex& idx, std::uint32_t fileId, EscapeFn esc )
{ return runHint( idx, fileId, " run=\"", "\"", esc ); }

template<class EscapeFn>
inline std::string runFieldJson( const TestRunnerIndex& idx, std::uint32_t fileId, EscapeFn esc )
{ return runHint( idx, fileId, ",\"run\":\"", "\"", esc ); }

inline std::string runSuffixText( const TestRunnerIndex& idx, std::uint32_t fileId )
{ return runHint( idx, fileId, "   (run: ", ")", []( std::string_view s ) { return std::string( s ); } ); }

// ── M21(b), capture-audit 2026-09-04 — the NOT-DERIVABLE case, SAID ───────────────────────────────────
// The three shapes above return "" when no runner is derivable, and every emitter simply printed nothing.
// The rule behind that ("a guessed command is worse than none") is right and is unchanged here; what was
// wrong is that an ABSENCE is not a disclosure. A reader of `<t p="./test/verify_radix.cpp"/>` — a row the
// verb that emits it calls an OBLIGATION and exits 4 over — cannot tell "this harness has no runner in the
// corpus" from "this emitter never asked". It is the same class as counts_floor= and
// script_gates_unmodelled=: the gap is stated where the number is consumed. So a tests_to_run row now says
// one of two things and never neither, and test/testrowruncheck.sh asserts exactly that over every emitter
// in the family — including --handoff and --flags --flip, which asked for no runner at all.
//
// These are WRAPPERS, not copies: the ""-means-not-derivable test stays in runHint alone, so a later edit
// to what counts as derivable cannot fix one dialect and leave another fabricating.
template<class EscapeFn>
inline std::string runAttrDisclosed( const TestRunnerIndex& idx, std::uint32_t fileId, EscapeFn esc )
{
    std::string attr = runAttr( idx, fileId, esc );
    return attr.empty() ? std::string( " run_unknown=\"1\"" ) : attr;
}

template<class EscapeFn>
inline std::string runFieldJsonDisclosed( const TestRunnerIndex& idx, std::uint32_t fileId, EscapeFn esc )
{
    std::string field = runFieldJson( idx, fileId, esc );
    return field.empty() ? std::string( ",\"run_unknown\":true" ) : field;
}

inline std::string runSuffixTextDisclosed( const TestRunnerIndex& idx, std::uint32_t fileId )
{
    std::string suffix = runSuffixText( idx, fileId );
    return suffix.empty() ? std::string( "   (run: not derivable)" ) : suffix;
}

// ── E1 / A4-2 (output-routing loop, 2026-09-12, owner call) — runner-less rows GROUPED, the disclosure once ──
// On a corpus where almost no harness has a derivable runner (rocksdb: 126 of 127 rows), every row paid the
// same 16 bytes of `run_unknown="1"` (23 in --situ's text) — 2.0–2.5 KB per answer for one fact said 127
// times. The rows come in EVIDENCE order (changed, partner, hops asc, path), so consecutive runner-less rows
// share their attributes; those are served as ONE row:
//
//     <g hops="2" n="7" p="a,b,c" run_unknown="1"/>                 XML   (the per-row attrs, then n= p=)
//     {"p":["a","b","c"],"hops":2,"n":7,"run_unknown":true}          JSON  ("p" — or "test" — becomes an ARRAY)
//     [hops=2] (7): a, b, c   (run: not derivable)                   text
//
// What the grouping may never change — test/testrowruncheck.sh arm 12 proves it on every dialect — is the
// MULTISET of paths: every path verbatim (a reader's grep for a file name still hits; E3's brace-grouped
// directories were disqualified on exactly that), each exactly once, in the order the single rows had. The
// rules, stated once here because they decide every emitter:
//   * a row WITH a runner stays a single <t>/<test> row exactly as before — run= is per row;
//   * only rows whose remaining per-row attributes are BYTE-EQUAL group (hops=, partner=, changed=,
//     seed_kind= — the `attrs` string is the key), so a group never blurs two kinds of evidence;
//   * a group is emitted where its FIRST member stood, its members in list order; a single row with a
//     runner in the middle of a group stays where it was, so evidence order is preserved row for row;
//   * a group of ONE is a single row (the <t> spelling is shorter and a consumer has one less shape);
//   * a path containing a ',' is NEVER grouped — it is served as a single row. p= is a comma-separated list
//     and every XML parser undoes an entity BEFORE a consumer splits on the delimiter, so an escaped comma
//     (this seam spelled &#44; until 2026-09-13) reappears as a separator and n= then disagrees with what
//     the reader counts; the text twin had no escape at all. Refusing to group the row is the only spelling
//     that is right in all three dialects at once, it costs one row on a path shape that is vanishingly
//     rare, and the legend clause says so rather than describing an escape.
// The ""-means-not-derivable test stays in runHint alone: the single rows below go through the Disclosed
// wrappers, and a group exists only where commandFor is empty — one seam, one rule.
//
// The byte cap this seam used to carry (`maxGroupBytes`, a pre-escape estimate of a group's rendered size)
// is GONE, and with it its 48-byte overhead constant and pack-task's per-row units arithmetic. It was the
// wrong depth: the estimate counted UNESCAPED path bytes, so a list of paths holding '&' or '<' rendered
// wider than the cap admitted and packTaskListSection — which breaks at the first over-budget entry — then
// dropped the whole tail of the section, run= singles included. pack-task now CUTS first and GROUPS second
// (packtask.h): the section is cut over single rows, whose rendered bytes are exactly what it measures, and
// the kept prefix is grouped afterwards. Grouping a run of N≥2 rows is strictly smaller than the N single
// rows it replaces (it drops N-1 tag+attribute+disclosure repeats and adds only ` n="N"`), so it can never
// breach a cut that already held.
struct TestRowOut
{
    std::uint32_t fileId = 0;
    std::string   path;    // as the verb spells it (root-relative or not), UNESCAPED
    std::string   attrs;   // the per-row attributes in the dialect's spelling (testRowEvidence + seed_kind=), possibly empty — the group key
};

enum class RowDialect : std::uint8_t { Xml, Json, Text };

struct TestRowShape
{
    RowDialect       dialect = RowDialect::Xml;
    std::string_view tag     = "t";   // XML element name ("t" | "test") or JSON key ("p" | "test")
    std::string_view indent  = "";    // text dialect: the line prefix
};

// One rendered row: the text, and how many test FILES it carries (1 for a single row, n for a group), so a
// caller counting files (pack-task's kept/shown arithmetic) never mistakes rows for tests.
struct RenderedTestRow
{
    std::string   text;
    std::uint32_t files = 1;
};

// The partition: index lists into `rows`, a run of one for a single row, a run of ≥2 for a group.
//
// A group covers a CONTIGUOUS run only: the scan stops at the first row that is not a groupable row with the
// same attrs. The rows arrive in evidence order, so equal-attribute groupable rows are already adjacent and
// the only things that can interrupt a run are a same-attribute row WITH a runner and a path carrying a ',';
// hoisting the rows after it into a group in FRONT of it would move them ahead of it (review of #214:
// A, B(run), A became G(A,A), B). Stopping instead costs one more <g> per interruption and makes order
// preservation true by construction — test/testrowruncheck.sh arm 12 reads the paths back in emitted order
// and asserts they are the single rows' order. Linear: `i` advances to the end of the run it just closed, so
// every row is visited exactly once and no `taken` bookkeeping is needed to find the next unconsumed row.
inline std::vector<std::vector<std::uint32_t>> partitionTestRows( const TestRunnerIndex& idx, std::span<const TestRowOut> rows )
{
    std::vector<std::vector<std::uint32_t>> groups;
    // The two disqualifications, in one place: a derivable runner (run= is per row) and a ',' in the path
    // (p= is a comma-separated list — see the seam's header comment for why no escape can rescue it).
    const auto groupable = [ & ]( std::uint32_t i ) noexcept
    {
        return idx.commandFor( rows[i].fileId ).empty() && rows[i].path.find( ',' ) == std::string::npos;
    };
    for( std::uint32_t i = 0; i < rows.size(); )
    {
        std::uint32_t end = i + 1;
        if( groupable( i ) )
        {
            while( end < rows.size() && groupable( end ) && rows[end].attrs == rows[i].attrs )
            {
                ++end;
            }
        }
        std::vector<std::uint32_t> members;
        members.reserve( end - i );
        for( std::uint32_t k = i; k < end; ++k )
        {
            members.push_back( k );
        }
        groups.push_back( std::move( members ) );
        i = end;
    }
    return groups;
}

// A single row, in the dialect — the disclosure through the Disclosed wrappers above, never re-spelled.
template<class EscapeFn>
inline std::string renderSingleTestRow( const TestRunnerIndex& idx, const TestRowOut& r, const TestRowShape& shape, EscapeFn esc )
{
    std::string s;
    switch( shape.dialect )
    {
        case RowDialect::Xml:
            s += "<";  s.append( shape.tag );  s += " p=\"";  s += esc( r.path );  s += "\"";  s += r.attrs;  s += runAttrDisclosed( idx, r.fileId, esc );  s += "/>";
            break;
        case RowDialect::Json:
            s += "{\"";  s.append( shape.tag );  s += "\":\"";  s += esc( r.path );  s += "\"";  s += r.attrs;  s += runFieldJsonDisclosed( idx, r.fileId, esc );  s += "}";
            break;
        case RowDialect::Text:
            s.append( shape.indent );  s += r.path;  s += r.attrs;  s += runSuffixTextDisclosed( idx, r.fileId );  s += "\n";
            break;
    }
    return s;
}

// A group row (≥2 members, no runner by construction), in the dialect.
template<class EscapeFn>
inline std::string renderTestRowGroup( std::span<const TestRowOut> rows, std::span<const std::uint32_t> members, const TestRowShape& shape, EscapeFn esc )
{
    ASSUME( members.size() >= 2 );
    const TestRowOut& first = rows[ members[0] ];
    std::string       s;
    switch( shape.dialect )
    {
        case RowDialect::Xml:
        {
            s += "<g";  s += first.attrs;  s += " n=\"";  s += std::to_string( members.size() );  s += "\" p=\"";
            for( std::size_t k = 0; k < members.size(); ++k )
            {
                if( k ) { s += ','; }
                s += esc( rows[ members[k] ].path );   // no path here holds a ',' — partitionTestRows refuses to group one
            }
            s += "\" run_unknown=\"1\"/>";
            break;
        }
        case RowDialect::Json:
        {
            s += "{\"";  s.append( shape.tag );  s += "\":[";
            for( std::size_t k = 0; k < members.size(); ++k )
            {
                if( k ) { s += ','; }
                s += '"';  s += esc( rows[ members[k] ].path );  s += '"';
            }
            s += "]";  s += first.attrs;  s += ",\"n\":";  s += std::to_string( members.size() );  s += ",\"run_unknown\":true}";
            break;
        }
        case RowDialect::Text:
        {
            s.append( shape.indent );
            // attrs are built with a LEADING space so every other dialect can append them straight after a
            // tag name; this dialect STARTS a line with them, so that one space is dropped. A view, not a
            // substr copy. (Deliberately not lintrules.h's ltrim: that header is the --lint verb's rule table
            // and pulls ingest.h in with it — this shared emit seam must not depend on a verb.)
            if( !first.attrs.empty() )
            {
                std::string_view a( first.attrs );
                if( a.front() == ' ' ) { a.remove_prefix( 1 ); }
                s.append( a );  s += ' ';   // " [hops=2]" -> "[hops=2] "
            }
            s += '(';  s += std::to_string( members.size() );  s += "): ";
            for( std::size_t k = 0; k < members.size(); ++k )
            {
                if( k ) { s += ", "; }
                s += rows[ members[k] ].path;
            }
            s += "   (run: not derivable)\n";
            break;
        }
    }
    return s;
}

// The two ways a caller has its rows: a bare file list (--exercises' seeds, --pr-context, --handoff, --flags
// --flip, --pack-task, situational_awareness — no per-row attributes), or rankTestRows' evidence rows
// (--situ's three dialects). ONE builder each, so six sites do not carry six copies of the same loop.
template<class PathFn>
inline std::vector<TestRowOut> testRowsOutOf( std::span<const std::uint32_t> files, PathFn pathRel )
{
    std::vector<TestRowOut> rows;
    rows.reserve( files.size() );
    for( std::uint32_t f : files )
    {
        rows.push_back( { f, std::string( pathRel( f ) ), {} } );
    }
    return rows;
}

template<class PathFn>
inline std::vector<TestRowOut> evidenceRowsOut( std::span<const TestRow> rows, EvDialect d, PathFn pathRel )
{
    std::vector<TestRowOut> out;
    out.reserve( rows.size() );
    for( const TestRow& r : rows )
    {
        out.push_back( { r.fileId, std::string( pathRel( r.fileId ) ), testRowEvidence( r, d ) } );
    }
    return out;
}

// THE SEAM every tests_to_run emitter calls (test/testrowruncheck.sh arm 0 censuses its call sites): the
// partition and the rows, in the order the reader gets them. A caller that needs two dialects of ONE
// partition (pack-task's XML section and its JSON tail) passes the partition it already has.
template<class EscapeFn>
inline std::vector<RenderedTestRow> testRowsRendered( const TestRunnerIndex& idx, std::span<const TestRowOut> rows, const TestRowShape& shape, EscapeFn esc,
                                                      const std::vector<std::vector<std::uint32_t>>* partition = nullptr )
{
    const std::vector<std::vector<std::uint32_t>> own = partition ? std::vector<std::vector<std::uint32_t>>{} : partitionTestRows( idx, rows );
    const std::vector<std::vector<std::uint32_t>>& groups = partition ? *partition : own;
    std::vector<RenderedTestRow>                   out;
    out.reserve( groups.size() );
    for( const std::vector<std::uint32_t>& members : groups )
    {
        if( members.size() == 1 )
        {
            out.push_back( { renderSingleTestRow( idx, rows[ members[0] ], shape, esc ), 1 } );
        }
        else
        {
            out.push_back( { renderTestRowGroup( rows, members, shape, esc ), std::uint32_t( members.size() ) } );
        }
    }
    return out;
}

// The joined form AND the number of test FILES it names, as ONE value.
//
// Review of #214: eight legends gate the run-hint clause below, and each one asked its own question — "is the
// rendered string empty", "does the document contain `<tests `", nothing at all. Two of them were wrong (a
// CDATA body carrying the literal text `<tests ` charged the clause with zero rows; --handoff and --flags
// --flip charged it unconditionally, and --handoff is byte-budgeted, so `<tests n="0">` could evict a real
// row to pay for a rule about rows it has none of). The seam that renders the rows is the only thing that
// KNOWS how many there are, so it returns the count with them and every legend asks that one count.
// `files` is the number of test FILES (a <g n="N"> row contributes N), and it is 0 exactly when `text` is.
struct JoinedTestRows
{
    std::string text;
    std::size_t files = 0;
};

template<class EscapeFn>
inline JoinedTestRows testRowsList( const TestRunnerIndex& idx, std::span<const TestRowOut> rows, const TestRowShape& shape, EscapeFn esc, std::string_view sep = {} )
{
    JoinedTestRows out;
    bool           first = true;
    for( const RenderedTestRow& r : testRowsRendered( idx, rows, shape, esc ) )
    {
        if( !first ) { out.text.append( sep ); }
        first = false;
        out.text  += r.text;
        out.files += r.files;
    }
    return out;
}

// The joined form alone, for the emitters that print the list in one go and count their files elsewhere
// (`sep` between rows: "," for JSON, "" else).
template<class EscapeFn>
inline std::string testRowsJoined( const TestRunnerIndex& idx, std::span<const TestRowOut> rows, const TestRowShape& shape, EscapeFn esc, std::string_view sep = {} )
{
    return testRowsList( idx, rows, shape, esc, sep ).text;
}

// The ONE sentence every legend that carries a tests_to_run row splices, so the seven cannot drift into
// seven wordings of one rule. Deliberately short: it rides on --test-gate's own byte ratchets.
// E1 (2026-09-12): the <g> row is defined in the same sentence, because it is the same rule said once per
// group — and legendcoveragecheck wants n= defined wherever a document carries it.
inline constexpr std::string_view kRunHintLegendClause =
    "run= is the command that discharges a test row; run_unknown=\"1\" means none is derivable for that "
    "harness (a guess would be worse than none) — a <t> or <g> row carries one or the other, never neither. "
    "<g n= p=a,b,c> is 2+ runner-less rows with equal attributes served as ONE row: n= how many, p= their paths "
    "verbatim in list order — a path holding ',' is never grouped, so p= splits into exactly n= paths. A "
    "shown=/total= over these rows counts test FILES: a <g> row is n= of them. ";

// A3 / review of #219: the ROOT-RELATIVE half of the rule, and it is CONDITIONAL. Spliced unconditionally —
// as the first cut of A3 did — this sentence told a multi-root reader, in a document carrying no root= at
// all, that its absolute command was relative to something. runsAreRootRelative (above) decides BOTH the
// spelling and the sentence, so the two cannot disagree. Gate: rootrelemitcheck ARM 9c, runhintcheck 2d.
inline constexpr std::string_view kRunRootRelSentence =
    "A run= command is relative to root=: run it from there. ";

// The clause is a rule about ROWS, so a legend splices it only when the document actually renders one — a
// tests="0" answer pays nothing for it. THE gate, taking the count testRowsList returns (or, for a section
// that cut its own rows, that section's kept count): one rule, one spelling, asked by all eight sites.
inline std::string runHintClauseIfRows( std::size_t testFilesRendered, bool rootRelativeRuns )
{
    if( testFilesRendered == 0 )
    {
        return {};
    }
    return std::string( kRunHintLegendClause ) + ( rootRelativeRuns ? std::string( kRunRootRelSentence ) : std::string() );
}

// ── P9 (capture-audit 2026-09-04) — the tests_to_run row set for ONE changed file ────────────────────
// The FILE reading of --affected, seeded by file id rather than by a path pattern, for callers that already
// hold the file (the MCP edit receipt wrote it and knows which). It routes through the SAME affectedAnswer
// the verb uses, so the two cannot answer differently. Seeding from the fileId rather than re-running the
// path-PATTERN match is the one deliberate difference and it is preserved: `--affected=geo.py` is a
// substring pattern that also matches test/check_geo.py, and a receipt knows exactly which file it wrote.
//
// WHY THIS IS NOT A PRIVATE WALK ANY MORE. It was one, with the comment "BYTE FOR BYTE what runAffected
// does" — TRUE when written (050a6b07, 2026-09-04): --affected was then the same bare
// transitiveCallers/isTestPath walk. Two commits orphaned it within days, both touching neither mcpedit.h
// nor packtask.h: 015e5a0f (2026-09-05) made a test that IS the edit target list itself (seed_kind="test"),
// and 7dae6522 (2026-09-07) added the partner tier. A bare walk can produce NEITHER — transitiveCallers
// returns reached MINUS seeds, so the edit target can never appear, and nothing knew about partners. The
// receipt therefore answered "tests":0 for 100% of test-file edits, under a --help promising the rows
// --affected gives. One seam now, so a third tier cannot land at one site and not the other.
inline AffectedAnswer affectedAnswerForFile( const IngestResult& ing, const Graph& g, std::uint32_t fileId )
{
    AffectedSeeds sel;
    sel.sawFileItem = true;
    for( NodeId i = 0; i < NodeId( ing.symbols.size() ); ++i )
    {
        if( ing.symbols[i].fileId == fileId )
        {
            sel.seeds.push_back( i );
        }
    }
    partitionAffectedSeedsByTestPath( ing, sel );
    return affectedAnswer( ing, g, sel );
}

// The FIRST test row for a file, in EVIDENCE order, or rw::kNoFile when there is none — the receipt's
// next= hint suggests ONE command, so it needs one row, not the list. Evidence order is what makes that
// the changed or partner test rather than a deeper graph hop. Reuses resolve.h's kNoFile sentinel: a
// second constant of the same value and meaning is the kind of near-duplicate this tree lints for.
inline std::uint32_t firstTestFileForFile( const IngestResult& ing, const Graph& g, std::uint32_t fileId )
{
    const AffectedAnswer ans = affectedAnswerForFile( ing, g, fileId );
    return ans.rows.empty() ? rw::kNoFile : ans.rows.front().fileId;
}


// ── §P9 N5 / §B7.3 — the blindness this whole map shares, counted ONCE ────────────────────────────────
// Every verb built on the call-graph walk (--affected, --test-gate, --situ) is blind to the same thing: a
// shell harness that runs the compiled BINARY as a subprocess is not a call edge, so those gates are
// invisible to the traversal and can never appear in a tests= or reached= count. The honest-limits rule
// (§P0.5's family) says absence of modelling must be stated WHERE THE NUMBER IS CONSUMED — and --test-gate
// is the verb that EXITS 4 calling its rows "the obligations", so it needed the disclosure most and had it
// least: six named tests, no hint that 276 shell gates were never modelled at all.
//
// It lives HERE rather than in main.cpp because three verbs must report the SAME number. A second copy
// would drift the moment the test-path convention moved, and the three would then disagree about how blind
// they are — which is worse than the original silence, because the disagreement looks like a measurement.
// Counts every corpus file under test/ ending in ".sh", regardless of whether THIS run's changed set
// reaches it: the point is disclosing what the model cannot see AT ALL, not scoping it to the query. A path
// count, deliberately — the files are never opened, so this never claims each one invokes the binary.
inline std::size_t scriptGatesUnmodelledCount( const IngestResult& ing )
{
    std::size_t gateCount = 0;
    for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ); ++f )
    {
        const std::string_view filePath = rootRelPath( ing, f );
        if( isTestPath( filePath ) && filePath.ends_with( ".sh" ) )
        {
            ++gateCount;
        }
    }
    return gateCount;
}

// ─── writeAffectedReport (lane/t10-mcp-coverage) — THE renderer behind BOTH --affected (CLI,
// main.cpp verbs_change.h::runAffected) and the MCP `affected` verb (mcpverbs.h::affectedText). One
// function, one FILE* target: the two surfaces answer byte-identical <affected>…</affected> XML for the
// identical seed set, never a second hand-copied emitter to drift from the first — the exact mistake
// this file's header comment already warns against for the test<->code map itself. Lifted verbatim out
// of what used to be runAffected's body (main.cpp), with `stdout`/`cfg.affectedFiles`/`d.root` generalized
// to `out`/`spec`/`root` — the CLI wrapper's own bytes are unchanged (it is the same code, just callable
// from two places now).
//
// Resolution failure is reported through the return value ONLY (nothing is written to `out` on failure):
// each surface composes its own refusal in its own idiom — the CLI prints a near-miss suggestion to stderr
// and exits 1; the MCP arm returns a JSON-RPC error. Only the SUCCESS document has to be byte-identical,
// never the two callers' very different failure UX (the same split every other CLI/MCP verb pair in this
// tree already draws — see impactText/usesText's own refusal wording beside their CLI twins).
// IX-5: the class-new group's legend clause and its rendering — spliced only when the group renders (absent when empty, so an
// answer without one is byte-identical). The rows are tests NOT in the proven list, so the group is never counted in tests=.
inline constexpr std::string_view kClassNewLegend =
    "<g via=\"class-new\" total= shown= capped= next=>: tests not listed above that construct a class owning a reached method (or the "
    "changed class); <new p= l= class=>: the test file, the construction line if exact, the class. The dispatch to the method is not "
    "proven, so never in tests=/reached=; nearest class first; a floor (Go T{}, C++ T x;, Ruby T.new are not read). ";
template<class EscapeFn>
inline std::string classNewGroupXml( const IngestResult& ing, std::span<const ClassNewRow> rows, std::string_view rootPrefix, EscapeFn ex )
{
    if( rows.empty() )
    {
        return {};
    }
    const std::size_t shown = std::min<std::size_t>( rows.size(), kClassNewRowCap );
    std::string       next;   // the rows past the cap: --callers of what the first cut row calls lists every construction of its class
    if( shown < rows.size() )
    {
        const Symbol& c = ing.symbols[ rows[shown].cls ];
        const Symbol& t = ing.symbols[ rows[shown].target ];
        // the class itself (file:Class), or its constructor method by its canonical id (file::Class::new: `Class.new` named every
        // same-named class's constructor, widening the continuation past the class the first cut row built; CR #434)
        const std::string sel = rows[shown].target == rows[shown].cls
                                  ? std::format( "{}:{}", sarif::rootRelativeUri( ing.files[ c.fileId ], rootPrefix ), c.name )
                              : t.scope.empty()
                                  ? std::format( "{}.{}", c.name, t.name )
                                  : canonicalId( sarif::rootRelativeUri( ing.files[ t.fileId ], rootPrefix ), t.scope, t.name );
        next = nextAttrXml( nextFlag( "--callers=", sel ) );   // checklist 34: the one continuation spelling and escaper
    }
    // the house window (total= shown= capped=): capped="1" exactly when rows were cut, beside the next= for the first cut row's class (not a list of the rest)
    std::string out = std::format( "<g via=\"class-new\" total=\"{}\" shown=\"{}\"{}{}>", rows.size(), shown,
                                   shown < rows.size() ? " capped=\"1\"" : "", next );
    for( std::size_t i = 0; i < shown; ++i )
    {
        const ClassNewRow& r = rows[i];
        out += std::format( "<new p=\"{}\"{} class=\"{}\"/>", ex( sarif::rootRelativeUri( ing.files[ r.testFile ], rootPrefix ) ),
                            r.line ? std::format( " l=\"{}\"", r.line ) : std::string(), ex( ing.symbols[ r.cls ].name ) );
    }
    return out + "</g>";
}

struct AffectedReportResult
{
    bool        ok           = false;   // true ⇒ `out` now holds a complete <affected>…</affected> document
    bool        badSelector  = false;   // sel.ok == false: `badItem` matched neither an indexed path nor a symbol
    std::string badItem;                // populated only when badSelector
    bool        noSeeds      = false;   // sel.ok, but the matched item(s) resolved to zero seed symbols
};

inline AffectedReportResult writeAffectedReport( std::FILE* out, const IngestResult& ing, const Graph& g,
                                                  const std::string& root, std::string_view spec, bool singleRoot )
{
    EXPECTS( out != nullptr, "writeAffectedReport: the answer needs a stream to write to; the failure returns below write nothing, so a null sink would be silent" );
    // §P11.2a: the map was file-granular, so "which tests cover the function I am about to change?" had
    // to be widened to its whole FILE first, over-reporting the obligation. Only the SEED SET changes
    // here: everything below (transitiveCallers → isTestPath → path-sorted rows) is the same traversal
    // --affected always ran. The file-first argument rule and its per-item refusal live in
    // resolveAffectedSeeds above; only the did-you-mean wording is each surface's own.
    const AffectedSeeds sel = resolveAffectedSeeds( ing, spec );
    if( !sel.ok )
    {
        return { false, true, sel.badItem, false };
    }
    const std::vector<NodeId>& seeds = sel.seeds;
    if( seeds.empty() )
    {
        return { false, false, {}, true };
    }
    // F3: the caller walk and the matched-test rows are assembled in affectedAnswer, next to the seeding
    // whose test partition constrains them (lane-L8 found-not-fixed #1: seeding the walk with a matched
    // test file's own symbols subtracted the very tests that reach the change).
    const AffectedAnswer          answer    = affectedAnswer( ing, g, sel );
    const std::vector<NodeId>&    reach     = answer.reach;
    const std::vector<std::uint32_t>& testFiles = answer.testFiles;
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    // M12: root-relative --situ/--test-gate/--pr-context/--handoff parity — every <test p=> row below is
    // root-relative, and root= says what it is relative to (absent under multi-root, same convention as
    // every other verb's root= disclosure).
    const std::string afRootPrefix = singleRoot ? sarif::rootPrefixOf( root ) : std::string();
    const std::string afRootAttr   = singleRoot ? ( " root=\"" + ex( root ) + "\"" ) : std::string();
    const auto         afPathRel   = [ & ]( std::uint32_t fileId ) -> std::string_view
    {
        return sarif::rootRelativeUri( ing.files[ fileId ], afRootPrefix );
    };
    // §P11.4 / E1: the rows are rendered FIRST (the run=/run_unknown= rule and the <g> group row) so the
    // legend below can splice that clause only when there are rows for it to be a rule about — a tests="0"
    // answer, the common clean case, pays nothing for it.
    // TRAIN 10 (CodeRabbit 4056211650): the index is handed a root ONLY when this document declares one, so
    // the command spelling cannot contradict the root= disclosure whatever a caller passes for singleRoot.
    // With no root the ctor keeps the absolute spelling, which is what an unanchored document owes its reader
    // (see TestRunnerIndex's own ctor comment). The caller-side half of this — counting the roots that SURVIVED
    // dedupe rather than the roots as typed — is in verbs_change.h::runChangeViews.
    const TestRunnerIndex   runners( ing, singleRoot ? std::string_view( root ) : std::string_view() );
    std::vector<TestRowOut> afRows;
    afRows.reserve( answer.rows.size() );
    for( TestRow row : answer.rows )   // by value: a matched test file's changed= is spelled seed_kind="test" on this verb
    {
        const std::uint32_t f = row.fileId;
        row.changed           = false;
        afRows.push_back( { f, std::string( afPathRel( f ) ), std::string( answer.isSeedTestFile[f] ? " seed_kind=\"test\"" : "" ) + testRowEvidence( row, EvDialect::Xml ) } );
    }
    const JoinedTestRows afRowsXml = testRowsList( runners, afRows, TestRowShape{ RowDialect::Xml, "test" }, ex );
    const std::string    afRunFirst = runFirstField( answer.rows, answer.rows.size(), /*json=*/false );   // hono-20: the run-first head
    // IX-5 (hono-20): the class-new backstop, rendered apart from the proven rows above and counted in none of the root's counts
    const std::string    afClassNew = classNewGroupXml( ing, classNewTestRows( ing, g, sel, answer ), afRootPrefix, ex );
    // seeded_by= is the honesty half of the file-first rule: the two readings answer DIFFERENT questions
    // over the same argument string and return different counts, so which one fired is a fact about the
    // measurement, not a detail. seeds= is the resolved seed-symbol count (1 for a lone function, ~84
    // for a header), which is what makes the two readings comparable at a glance.
    rw::emitTo( out, "<!-- ripwire affected: test files that transitively reach the changed files/symbols (run these); seeded_by= says which reading the argument took. "
                 "seed_test_files= how many of the matched files are TEST files: a test cannot reach a change it is part of, so its own symbols are not seeds of the "
                 "caller walk and its row carries seed_kind=\"test\" — it is listed because the argument matched it (it changed, run it), not because it reaches the change. "
                 "script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) — "
                 "script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=/reached=. "
                 "{}"     // H2H-Graft F1: the evidence-order clause, testmap.h's ONE wording (changed= is spelled seed_kind="test" here: the argument matched it)
                 "order=evidence says so on the root; partners= counts the partner rows. "
                 "{}"     // M21(b)/E1: the run=/run_unknown= rule and the <g> group row, testmap.h's ONE wording — rows-gated
                 // TRAIN 10: read off the index rather than re-derived here (testmap.h's own rule for this fact),
                 // so the sentence is decided by the very object that spelled the commands it describes.
                 "{}"     // hono-20/textual-20: the run-first clause, exactly when the root carries run_first=
                 "{}"     // IX-5: the class-new group's clause, exactly when the group renders
                 "{}{}-->{}", kTestRowEvidenceLegend, runHintClauseIfRows( afRowsXml.files, runners.rootRelative() ),
                 // H1: the decl→def residue resolveAffectedSeeds summed over the symbol items. A file:name item whose
                 // definitions were dropped seeded the walk with declarations alone, which reached the reader as a bare
                 // tests="0" — on the verb whose answer is the list of tests to run. Exactly when the root carries it.
                 runFirstLegend( !afRunFirst.empty() ),
                 afClassNew.empty() ? std::string_view() : kClassNewLegend,
                 unprovenDefsVerbLegend( UnprovenDefsVerb::Affected, sel.unprovenDefs > 0 ).c_str(),
                 graphCountFloorBrief( rw::graphGaugeClauses( g ) ).c_str(), rootRelPathsLegend( singleRoot ) );
    rw::emitTo( out, "<affected changed=\"{}\" seeded_by=\"{}\" seeds=\"{}\" seed_test_files=\"{}\" tests=\"{}\" reached=\"{}\"{} script_gates_unmodelled=\"{}\""
                 "{}"   // hono-20: run_first=, where the run-first head ends; absent unless it splits
                 " order=\"evidence\" partners=\"{}\"{}{}>",
                 ex( spec ).c_str(), affectedSeededBy( sel ), seeds.size(), sel.seedTestFiles.size(), testFiles.size(), reach.size(),
                 unprovenDefsAttrXml( sel.unprovenDefs ).c_str(),   // H1: beside the zero it qualifies; absent at zero
                 scriptGatesUnmodelledCount( ing ),
                 afRunFirst.c_str(),
                 testRowPartnerCount( answer.rows ),      // F1: how many rows stand on the name convention alone or as well
                 afRootAttr.c_str(),                      // M12: root= says what every <test p=> below is relative to
                 graphCountFloorAttrXml( g ).c_str()  );   // H5/M15: gauge + marker; tests=/reached= are a transitive-caller walk over the name-based CSR
    rw::emitRaw( out, afRowsXml.text.c_str() );   // E1: the rows rendered above — runner-less rows with equal evidence as ONE <g> row, the multiset unchanged
    rw::emitRaw( out, afClassNew.c_str() );       // IX-5: the hedged class-new group, after every proven row (empty when none)
    rw::emitRaw( out, "</affected>" );
    return { true, false, {}, false };
}

struct ShellGateObligation
{
    std::uint32_t fileId = 0;
    const char*   evidence = nullptr;
};

struct ShellGateIndex
{
    std::vector<ShellGateObligation> obligations;
    std::size_t                      registered = 0;
    std::size_t                      mapped = 0;
    std::size_t                      unresolvedDynamic = 0;
};

namespace testmap_detail
{

inline std::string executableShellText( std::string_view source )
{
    std::string executable;
    bool comment = false;
    for( const char c : source )
    {
        if( c == '\n' )
        {
            comment = false;
            executable.push_back( c );
        }
        else if( c == '#' )
        {
            comment = true;
        }
        else if( !comment ) { executable.push_back( c ); }
    }
    return executable;
}

inline std::string_view trimShellSpace( std::string_view value ) noexcept
{
    const std::size_t first = value.find_first_not_of( " \t\r" );
    if( first == std::string_view::npos ) { return {}; }
    return value.substr( first, value.find_last_not_of( " \t\r" ) - first + 1 );
}

inline void appendManifestDependencies( std::string_view line, std::vector<std::string>& deps )
{
    constexpr std::string_view kMarker = "# RIPWIRE_TEST_DEPS:";
    line = trimShellSpace( line );
    if( line.rfind( kMarker, 0 ) != 0 ) { return; }
    line.remove_prefix( kMarker.size() );
    for( std::size_t begin = 0; begin <= line.size(); )
    {
        const std::size_t comma = line.find( ',', begin );
        const std::string_view dep = trimShellSpace( line.substr( begin, comma == std::string_view::npos ? line.size() - begin : comma - begin ) );
        if( !dep.empty() ) { deps.emplace_back( dep ); }
        if( comma == std::string_view::npos ) { return; }
        begin = comma + 1;
    }
}

inline std::vector<std::string> manifestDependencies( std::string_view source )
{
    std::vector<std::string> deps;
    for( std::size_t begin = 0; begin < source.size(); )
    {
        const std::size_t end = source.find( '\n', begin );
        appendManifestDependencies( source.substr( begin, end == std::string_view::npos ? source.size() - begin : end - begin ), deps );
        if( end == std::string_view::npos ) { break; }
        begin = end + 1;
    }
    return deps;
}

inline bool pathLiteralMatches( std::string_view indexedPath, std::string_view literal ) noexcept
{
    while( indexedPath.rfind( "./", 0 ) == 0 ) { indexedPath.remove_prefix( 2 ); }
    while( literal.rfind( "./", 0 ) == 0 ) { literal.remove_prefix( 2 ); }
    if( literal.find( '/' ) == std::string_view::npos )
    {
        return false; // a basename alone is not exact path evidence
    }
    if( indexedPath == literal )
    {
        return true;
    }
    return indexedPath.size() > literal.size() && indexedPath.ends_with( literal ) && indexedPath[indexedPath.size() - literal.size() - 1] == '/';
}

inline std::vector<std::string> shellTokens( std::string_view executable )
{
    std::vector<std::string> tokens;
    for( std::size_t begin = 0; begin < executable.size(); )
    {
        while( begin < executable.size() && executable[begin] != '/' && executable[begin] != '.' && !namesplit::isIdentChar( executable[begin] ) ) { ++begin; }
        std::size_t end = begin;
        while( end < executable.size() )
        {
            const char c = executable[end];
            if( c != '/' && c != '.' && c != '-' && !namesplit::isIdentChar( c ) ) { break; }
            ++end;
        }
        if( end > begin ) { tokens.emplace_back( executable.substr( begin, end - begin ) ); }
        begin = end == begin ? begin + 1 : end;
    }
    return tokens;
}

inline std::vector<std::string> shellPathTokens( std::string_view executable )
{
    std::vector<std::string> paths = shellTokens( executable );
    paths.erase( std::remove_if( paths.begin(), paths.end(), []( const std::string& token ) { return token.find( '/' ) == std::string::npos; } ), paths.end() );
    return paths;
}

inline bool dependenciesMatchChanged( const IngestResult& ing, const std::vector<char>& changedFiles,
                                      const std::vector<std::string>& dependencies ) noexcept
{
    for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ) && f < changedFiles.size(); ++f )
    {
        if( !changedFiles[f] ) { continue; }
        for( const std::string& dependency : dependencies )
        {
            if( pathLiteralMatches( ing.files[f], dependency ) ) { return true; }
        }
    }
    return false;
}

inline bool dependenciesMapCorpus( const IngestResult& ing, const std::vector<std::string>& dependencies ) noexcept
{
    for( const std::string& file : ing.files )
    {
        for( const std::string& dependency : dependencies )
        {
            if( pathLiteralMatches( file, dependency ) ) { return true; }
        }
    }
    return false;
}

// The word list of every `for <var> in <members…>; do` in the token stream, one token of lookahead state.
inline void appendForListStems( const std::vector<std::string>& tokens, std::vector<std::string>& stems )
{
    ASSUME_NO_ALIAS( tokens, stems );
    enum class Loop : std::uint8_t { Scan, Var, ExpectIn, List };
    Loop state = Loop::Scan;
    for( const std::string& token : tokens )
    {
        if( token.find( '/' ) != std::string::npos )
        {
            continue;   // a path token is never a shell keyword or a bare list member
        }
        switch( state )
        {
            case Loop::Scan:     if( token == "for" ) { state = Loop::Var; }  break;
            case Loop::Var:      state = Loop::ExpectIn;  break;   // the loop variable name
            case Loop::ExpectIn: state = token == "in" ? Loop::List : Loop::Scan;  break;
            case Loop::List:
                if( token == "do" ) { state = Loop::Scan; }
                else                { stems.push_back( token ); }
                break;
        }
    }
}

inline std::vector<std::string> suiteMemberStems( const std::vector<std::string>& tokens )
{
    std::vector<std::string> stems;
    for( const std::string& token : tokens )
    {
        if( token.find( '/' ) == std::string::npos ) { continue; }
        const std::string_view stem = mention_detail::pathStem( token );
        if( !stem.empty() ) { stems.emplace_back( stem ); }
    }
    appendForListStems( tokens, stems );
    return stems;
}

inline std::vector<std::string> registeredShellTokens( const IngestResult& ing )
{
    std::string manifest;
    for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ); ++f )
    {
        if( mention_detail::baseNameOf( ing.files[f] ) == "regression.sh" && isTestPath( rootRelPath( ing, f ) ) )
        {
            manifest = docparse::detail::readWholeFile( diskPath( ing, f ) ).value_or( std::string() );
            break;
        }
    }
    // A stem is REGISTERED only where regression.sh names it as a suite member: as a path-shaped token
    // (a direct `bash test/<stem>.sh` invocation), or as a word inside a `for … in <list>; do` word list
    // (the absorb loop). A bare word elsewhere in the manifest — an echo, a variable, a status label —
    // must never register a coincidentally-named script; that inflated registered/unresolved_dynamic.
    return suiteMemberStems( shellTokens( executableShellText( manifest ) ) );
}

inline void addRegisteredShellGate( const IngestResult& ing, const std::vector<char>& changedFiles, std::uint32_t fileId, ShellGateIndex& index )
{
    ++index.registered;
    const std::optional<std::string> source = docparse::detail::readWholeFile( diskPath( ing, fileId ) );
    if( !source ) { return; }
    const std::vector<std::string> manifestDeps = manifestDependencies( *source );
    const std::vector<std::string> literalDeps  = shellPathTokens( executableShellText( *source ) );
    const bool manifestMapped = dependenciesMapCorpus( ing, manifestDeps );
    const bool literalMapped  = dependenciesMapCorpus( ing, literalDeps );
    if( manifestMapped || literalMapped ) { ++index.mapped; }
    if( manifestMapped && dependenciesMatchChanged( ing, changedFiles, manifestDeps ) )
    {
        index.obligations.push_back( ShellGateObligation{ fileId, "manifest_declared" } );
    }
    else if( literalMapped && dependenciesMatchChanged( ing, changedFiles, literalDeps ) )
    {
        index.obligations.push_back( ShellGateObligation{ fileId, "script_literal" } );
    }
}

} // namespace testmap_detail

inline ShellGateIndex buildShellGateIndex( const IngestResult& ing, const std::vector<char>& changedFiles )
{
    using namespace testmap_detail;
    ShellGateIndex index;
    const std::vector<std::string> registeredTokens = registeredShellTokens( ing );
    if( registeredTokens.empty() )
    {
        return index;
    }

    for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ); ++f )
    {
        const std::string_view path = rootRelPath( ing, f );
        if( !isTestPath( path ) || !path.ends_with( ".sh" ) || mention_detail::baseNameOf( path ) == "regression.sh" ) { continue; }
        const std::string_view stem = mention_detail::pathStem( path );
        if( std::find( registeredTokens.begin(), registeredTokens.end(), stem ) == registeredTokens.end() ) { continue; }
        addRegisteredShellGate( ing, changedFiles, f, index );
    }
    index.unresolvedDynamic = index.registered - index.mapped;
    std::sort( index.obligations.begin(), index.obligations.end(), [ & ]( const ShellGateObligation& a, const ShellGateObligation& b )
               { return ing.files[a.fileId] < ing.files[b.fileId]; } );
    return index;
}

}   // namespace rw
