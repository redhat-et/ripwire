#pragma once

// filter.h — --ignore-tests: drop symbols/references in test files so the token
// window is packed with production logic. Post-ingest, densifies symbol ids.

#include "model.h"
#include "docparse.h"     // lowerExtOf / isDocExtension — the single source of truth for "this file is a DOCUMENT"
#include "queryshape.h"   // the QUERY half of the shape-conditional document demotion below

#include <algorithm>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// Does `p` contain `seg` (which must end in '/') as a whole leading directory component? Factored out of
// isTestPath so pathTierOf below can ask the same question about bench/fixture dirs without a second copy
// of the scan — the copy is what would drift.
inline bool hasDirSegment( std::string_view p, std::string_view seg ) noexcept
{
    std::size_t pos = 0;
    while( ( pos = p.find( seg, pos ) ) != std::string_view::npos )
    {
        if( pos == 0 || p[pos - 1] == '/' )
        {
            return true;
        }
        ++pos;
    }
    return false;
}

// rv-test-gate-tsjs G2 (delta review, treated as a real defect, not advisory): jest's OWN default
// `testMatch` collects every file under a `__tests__/` directory, named or not — a real, common JS/TS
// convention this function did not recognize, so such a file was invisible to `--test-gate` (and every
// other tested=/untested= partition) before this fix: `src/__tests__/lib.js` read as an untestable
// module-scope owner even though jest runs it by default. Added HERE (not scoped to a JS/TS extension
// check) because isTestPath is the ONE language-neutral test-path convention every verb shares
// (this file's own banner) — a directory NAMING convention, unlike a file extension, is not inherently
// tied to one language (Dart/Flutter's own test tooling uses the same directory name), and BRIEF_COMMON's
// language-neutrality rule prefers one shared mechanism over a per-language special case when the
// mechanism itself does not need to differ. Verified zero-risk to every OTHER language's existing
// fixtures/goldens: no `__tests__` directory exists anywhere in this repo's tree today (a directory this
// convention did not previously recognize cannot have been counted as test code by any committed fixture
// or pinned gate), confirmed by a repo-wide `find -type d -name __tests__` returning nothing before this
// change landed. jest's OTHER default pattern half — a bare `test.js`/`spec.js` filename with no leading
// dot or underscore (`?(*.)+(spec|test).[tj]s?(x)`) — is a narrower, separate gap this fix does not close.
inline bool isTestPath( std::string_view p ) noexcept
{
    // directory segment: test/, tests/ or __tests__/  (bounded by '/' or start)
    for( std::string_view seg : { std::string_view( "test/" ), std::string_view( "tests/" ), std::string_view( "__tests__/" ) } )
    {
        if( hasDirSegment( p, seg ) )
        {
            return true;
        }
    }

    // filename heuristics
    const std::size_t      sl = p.rfind( '/' );
    const std::string_view fn = ( sl == std::string_view::npos ) ? p : p.substr( sl + 1 );
    if( fn.rfind( "test_", 0 ) == 0 )
    {
        return true; // test_*.*
    }
    for( std::string_view m : { std::string_view( "_test." ), std::string_view( ".test." ),
                                std::string_view( "_spec." ), std::string_view( ".spec." ) } )
    {
        if( fn.find( m ) != std::string_view::npos )
        {
            return true;
        }
    }
    return false;
}

// ── L8: the WHOLE test partition — path OR in-file convention ────────────────────────────────────────────
// isTestPath above is a FILE question and cannot see the four mainstream conventions that put test code
// inside a production source file (Rust's own `#[cfg(test)] mod tests`, Python `class Test*` / module-level
// `def test_*`, a JS/TS helper inside `describe(`/`it(`/`test(`, a C# `[Fact]`/`[Test]`/`[TestMethod]`
// member). Measured on astral-sh/ruff: `--ignore-tests` dropped 15,811 path-classified symbols and left the
// top-5 of the map untouched, because every one of them was a `#[cfg(test)]` helper inside `src/`.
//
// ingest.cpp fills the syntactic half into Symbol::testScope at extraction. THIS predicate is the only
// place the two halves meet, and every SYMBOL-keyed consumer of "is this a test?" must ask it rather than
// re-deriving either half — the second copy is what would drift, exactly as hasDirSegment was factored out
// above for the same reason.
//
// Deliberately NOT rerouted through this predicate: the FILE-keyed verbs (--affected / --situ /
// --test-gate / --pr-context / --exercises) which answer "which test FILES should I run?". An in-file test
// gives an agent no separate file to run, and naming a `src/` file as a test to run would be a wrong
// answer, not a better one. Those keep asking isTestPath, and test/testscopecheck.sh arm 10b pins it.
inline bool isTestSymbol( const IngestResult& ing, std::size_t symbolIndex ) noexcept
{
    if( symbolIndex >= ing.symbols.size() )
    {
        return false;
    }
    const Symbol& s = ing.symbols[symbolIndex];
    if( s.testScope != 0 )
    {
        return true;
    }
    return s.fileId < ing.files.size() && isTestPath( rootRelPath( ing, s.fileId ) );
}

// ── §P11 first-screen ORDERING tiers ─────────────────────────────────────────────────────────────────────
// Several LISTING verbs serialized their rows in plain path-alphabetical order, which on a doc-heavy repo is
// a systematic bias against code: `AGENTS.md` and other long-named docs sort above `src/`, and a fixed row cap then cuts
// the deepest paths — usually the code — first (`--grep=DISCLOSE` showed 34 src + 66 doc rows and
// not one `test/` or `third_party/` row, the macro's own definition site included).
//
// This is a pure ORDERING key and nothing else: no row is dropped, no attribute is added or changed, and
// within one tier the pre-existing order (path-alphabetical, or rank) is preserved exactly. A reader who
// wants the old shape still gets every row, just later.
enum class PathTier : std::uint8_t { Source = 0, TestOrBench = 1, Doc = 2 };

// Extension decides DOC first (a `.md` under `test/` is prose, not a test), then the directory convention
// decides TEST/BENCH, and everything left is source. The question here is the READER's — is this file
// prose? — so it asks docparse::isProseExtension, which answers for the unindexed prose (`.txt`, `.tsv`)
// as well as for everything the index carries. This used to spell its own `.md`/`.markdown`/`.rst`/`.txt`
// list beside the extractor test; four other headers spelled four different ones (see docparse.h's
// vocabulary note), which is how `.adoc` and `.org` ended up prose to nobody.
inline PathTier pathTierOf( std::string_view p ) noexcept
{
    if( docparse::isProseExtension( docparse::lowerExtOf( p ) ) )
    {
        return PathTier::Doc;
    }

    if( isTestPath( p ) )
    {
        return PathTier::TestOrBench;
    }
    for( std::string_view seg : { std::string_view( "bench/" ),   std::string_view( "benches/" ),
                                  std::string_view( "fixture/" ), std::string_view( "fixtures/" ),
                                  std::string_view( "testdata/" ) } )
    {
        if( hasDirSegment( p, seg ) )
        {
            return PathTier::TestOrBench;
        }
    }

    return PathTier::Source;
}

// ── LB-G (r10 GitNexus round) — the ORDERING key, in ONE place for every verb that sorts rows by it ──────
// --grep has ordered SOURCE > TEST/BENCH > DOC since the span-tier round; --callers/--callees/--uses joined
// it in the r10 fix round. Three verbs sorting by "tier then path" is three chances to spell the key
// differently, which is the echo-site drift class this tree keeps re-finding, so the key is stated once.
//
// The index is materialized ONCE PER DISTINCT FILE the row list actually touches, never inside a
// comparator: pathTierOf() lowercases an extension into a fresh std::string, so an O(n log n) comparator
// that called it would allocate millions of times on a large --grep. search.h derives the same fact the
// same way for the same reason; this is that reasoning hoisted rather than a second copy of it.
// 0xFF = not computed (PathTier has three values, so the sentinel can never collide with a real tier).
template<class RowRange, class FileIdOf>
inline std::vector<std::uint8_t> pathTierIndexOver( const IngestResult& ing, const RowRange& rows, FileIdOf fileIdOf )
{
    std::vector<std::uint8_t> tierOfFile( ing.files.size(), 0xFFu );
    for( const auto& row : rows )
    {
        const std::uint32_t f = fileIdOf( row );
        if( f < tierOfFile.size() && tierOfFile[f] == 0xFFu )
        {
            tierOfFile[f] = std::uint8_t( pathTierOf( rootRelPath( ing, f ) ) );
        }
    }
    return tierOfFile;
}

// Three-way compare on the (tier, path) key of two FILES. 0 means "the same file" — the row-level tiebreak
// (line, name, role …) is the caller's, because it differs per verb; everything above it does not.
// Three-way rather than a `less` predicate so a caller spends ONE branch on the file key instead of the two
// nested ones each open-coded copy needed.
inline int compareTierThenPath( const IngestResult& ing, const std::vector<std::uint8_t>& tierOfFile,
                                std::uint32_t a, std::uint32_t b ) noexcept
{
    if( a == b )
    {
        return 0;
    }
    if( tierOfFile[a] != tierOfFile[b] )
    {
        return tierOfFile[a] < tierOfFile[b] ? -1 : 1;
    }
    return ing.files[a] < ing.files[b] ? -1 : 1;
}

// ── cut-fix C (2026-09-23): RANK BEFORE THE CAP — the navigation lists' ONE row order ─────────────────────
// --callers/--callees (and their MCP twins, find_symbol's calledBy array included), --uses (CLI, MCP and the
// member-field arm) and --impact's import tier sorted their rows by the key above — tier, then path, then line —
// and then cut at a default cap, so the cut dropped whatever sorted LAST: on a 342-caller answer the 40 survivors
// were the alphabetically-first files. docs/METHODOLOGY.md §9: the ceiling bounds the tail, never the head.
//
// The order is now tier first (LB-G's decision, unchanged: source before test/bench before docs), then
// `weightOf` DESCENDING, then the caller's own documented key (path, line, …) as the tie-break. It is the ONE
// total order the cap, the emitted rows and offset=/limit= paging all read, so:
//   * a cap keeps the heaviest rows and drops the lightest;
//   * page[0:k] + page[k:2k] == page[0:2k] (test/pagingsweepcheck.sh arm C): the pages ARE slices of the order,
//     which a select-then-re-sort-by-path page could not keep;
//   * the most relevant rows come first, which is the reading the owner asked the answer to lead with;
//   * the key is integer-exact (a uint32 weight; the incoming order is the caller's deterministic sort, and the
//     sort is stable), so there are no float ties and the result is byte-identical across runs.
// Rows whose weights tie keep the documented order, so a list of equal weights is byte-identical to before.
// `rows` must arrive in the documented order; it leaves as a permutation of itself (no row dropped or added).
template<class Row, class FileIdOf, class WeightOf>
inline void rankBeforeCap( const IngestResult& ing, std::vector<Row>& rows, FileIdOf fileIdOf, WeightOf weightOf )
{
    const std::size_t n = rows.size();
    EXPECTS( n <= std::size_t( UINT32_MAX ), "positions are carried as uint32 — a row list is bounded by the symbol/reference/file tables" );
    if( n < 2 )
    {
        return;
    }
    const std::vector<std::uint8_t> tierOfFile = pathTierIndexOver( ing, rows, fileIdOf );
    struct Key { std::uint8_t tier; std::uint32_t weight; std::uint32_t pos; };
    std::vector<Key>           key( n );
    std::vector<std::uint32_t> order( n );
    for( std::size_t i = 0; i < n; ++i )
    {
        const std::uint32_t f = fileIdOf( rows[i] );
        key[i]   = { f < tierOfFile.size() ? tierOfFile[f] : std::uint8_t( 0xFFu ), std::uint32_t( weightOf( rows[i] ) ), std::uint32_t( i ) };
        order[i] = std::uint32_t( i );
    }
    std::sort( order.begin(), order.end(), [ & ]( std::uint32_t a, std::uint32_t b )
    {
        const Key& ka = key[a];
        const Key& kb = key[b];
        if( ka.tier != kb.tier ) { return ka.tier < kb.tier; }
        if( ka.weight != kb.weight ) { return ka.weight > kb.weight; }
        return ka.pos < kb.pos;   // the incoming (documented) position: unique, so this is a TOTAL order
    } );
    std::vector<Row> ranked;
    ranked.reserve( n );
    for( const std::uint32_t i : order ) { ranked.push_back( std::move( rows[i] ) ); }
    ENSURES( ranked.size() == n, "a permutation: no row dropped, none repeated" );
    rows = std::move( ranked );
}

// ── §P4 de-prioritization tier (SCORING, not ordering) ───────────────────────────────────────────────────
// The retrieval lenses treated test fixtures and presentation decks as first-class source: a fixture stub
// outranked the real algorithm on the plan's cited example, and a deck-build local got bodied as a top hit.
// The decided fix (§P4) is NOT exclusion — those files stay indexed, findable by name, and anchorable by
// mention — but a path-keyed (0,1] down-weight folded into the scoring loop, generalizing the precedent
// src/exemplar.h INVARIANT 2 set (fixtures lose to real code — a sort key there, a down-weight here).
// Path-based, never language-based, so the tiers transfer unchanged to a C++ tree.
//
// ONE TABLE, ALL CONSUMERS: the classifier is pathTierOf (the §P11 ordering tiers above) plus the §P4 path
// families that are neither test nor source — decks, generated captures, and (2026-08-22) the vendored and
// machine-authored asset trees below. Extend THIS table; do not grow a second component list elsewhere
// (bench/recalleval's pollution predicate mirrors it). The extension carries the SAME 0.35 factor rather
// than a second constant: it is the same claim about the same kind of file, and a second knob would be a
// second calibration nobody re-derived. It is registered and band-judged in docs/EVALS.md, on an external
// slice, because THIS tree contains none of the new families — a gate here would be green while inert.
// The factor 0.35 is calibrated against bench/recalleval (2026-07-28), measured at 0.5 / 0.35 / 0.2:
// 0.5 left pollution@5 at 0.6% (one residual slot); 0.35 and 0.2 both reached 0.0% with byte-identical
// recall/MRR — so 0.35 is the GENTLEST factor that empties the measured pollution, keeping down-weighted
// files as close to the surface as the goal allows. DOC paths stay at 1.0 — the Section ×0.30 down-weight
// in lexical.h already covers prose, and the --recall docs lane is §P2b's, untouched here.
//
// NOTE ON THESE COMMENTS: deliberately no verbatim eval-query vocabulary in the per-function lines below —
// a doc comment quoting a benchmark phrase becomes a match for it (observed when this block first quoted
// the plan and promptly ranked itself #1 for the quoted words). Blank lines detach this banner from the
// functions (docCommentStart stops at a non-comment line).

// ONE declarative table of directory components that are shipped-but-not-authored: nobody edits them to
// change behaviour, so a task bundle that spends a slot on one has spent it on nothing. The first two rows
// are this repo's own decks and recorded captures; the rest are the cross-ecosystem asset trees a retrieval
// slice on outside repositories measured taking top slots on tasks that had nothing to do with them.
// A component must be whole (hasDirSegment) — `staticfiles/` is ordinary source and must not match.
//
// DELIBERATELY ABSENT: vendor/, node_modules/, dist/. The crawl already PRUNES those subtrees whole
// (ingest.h kCrawlSkipDirs), so a ranking tier for them would be a table row nothing can ever reach —
// dead weight that reads like coverage. The same check removed a *.min.js filename rule from this file:
// ingest.cpp isDenylistedName drops those before they are ever a symbol.
//
// ".yarn/releases/" (2026-08-29, SWE-Explore loss bucket 4) is the one exception to "the crawl already
// prunes it": Yarn Berry repos commit the package-manager's own executable release bundle
// (`.yarn/releases/yarn-3.1.0.cjs`) into version control, and nothing in kCrawlSkipDirs names `.yarn`, so
// it is crawled, parsed, and — measured on babel — ranked top-8 for ordinary task queries while being the
// only source of 90s+ `--expand` timeouts in that corpus. It is added here rather than to kCrawlSkipDirs
// on purpose: a hard prune would make the bundle unreachable even by an explicit `--expand`, and the
// §P4 contract is de-prioritize, never hide. A SOFT-max floor (see kVendoredBundleLineBytes below)
// generalizes the same claim to bundles that don't live under this exact path.
inline constexpr std::string_view kDemoOrGeneratedDirs[] = { "present/", "docs/captures/", "static/", "locale/", "min/",
                                                              ".yarn/releases/" };

// Yarn Plug'n'Play's own generated resolution manifest/loader — an exact, unambiguous basename (not a
// directory component: both files conventionally sit at a workspace ROOT, so hasDirSegment's "whole leading
// component" test cannot see them), regenerated by `yarn install` and never hand-edited. Same
// generated-not-authored fact isNumberedMigrationFileName below already carries for a numbered migration,
// keyed by basename instead of a digit run because that is the whole of what identifies this file.
inline bool isYarnPnpFileName( std::string_view fileName ) noexcept
{
    return fileName == ".pnp.cjs" || fileName == ".pnp.loader.mjs";
}

// 0001_initial.py — a numbered migration is machine-authored and append-only. The number is what makes it
// one: an UNnumbered file in the same directory (migrations/__init__.py) is ordinary source and stays so.
inline bool isNumberedMigrationFileName( std::string_view fileName ) noexcept
{
    std::size_t digitCount = 0;
    while( digitCount < fileName.size() && fileName[digitCount] >= '0' && fileName[digitCount] <= '9' )
    {
        ++digitCount;
    }
    return digitCount >= 2 && digitCount < fileName.size() && fileName[digitCount] == '_';
}

// tier check: deck / generated-capture / vendored-asset directories (neither test nor source; checked before
// pathTierOf because captures carry a doc extension and decks a source one). Same table-loop shape as
// pathTierOf, then the one FILENAME family a directory component alone cannot see.
inline bool isDemoOrGeneratedPath( std::string_view p ) noexcept
{
    for( std::string_view seg : kDemoOrGeneratedDirs )
    {
        if( hasDirSegment( p, seg ) )
        {
            return true;
        }
    }
    const std::size_t      slashPos = p.rfind( '/' );
    const std::string_view fileName = ( slashPos == std::string_view::npos ) ? p : p.substr( slashPos + 1 );
    return isYarnPnpFileName( fileName ) || ( hasDirSegment( p, "migrations/" ) && isNumberedMigrationFileName( fileName ) );
}

inline constexpr float kRankTierTestMul = 0.35f;
inline constexpr float kRankTierDemoMul = 0.35f;

// tier factor for one path — 1.0 for anything not in the two down-weighted families
inline float rankTierMultiplierOf( std::string_view p ) noexcept
{
    if( isDemoOrGeneratedPath( p ) )
    {
        return kRankTierDemoMul;
    }
    if( pathTierOf( p ) == PathTier::TestOrBench )
    {
        return kRankTierTestMul;
    }
    return 1.0f;
}

// EVIDENCE tier (2026-08-29, SWE-Explore loss bucket 4, the general class the path table above cannot
// enumerate): a minified/bundled single-file artifact packs a whole definition onto one or a handful of
// physical lines, so its bytes-per-line ratio is an order of magnitude past anything a human writes —
// true whether the file sits under `.yarn/releases/`, a `dist/` a repo kept out of the crawl denylist, or
// anywhere else. 2000 mirrors the "this line is generated, not authored" threshold renamemine.h's
// kMaxLineLen already uses for the SAME underlying claim in an unrelated lens (rename mining reads
// git-diff text; this reads a parsed Symbol's byte span) — independently re-derived rather than shared
// because coupling the two would tie ranking's cadence to rename-mining's.
//
// Computed from fields ingest ALREADY fills for every def (sigStartByte/endByte/loc) — no second file
// read, no new ingest plumbing, no cache-format change, and it runs once over every symbol here rather
// than once per file, so cost is O(symbols), not O(files × symbols).
inline constexpr std::uint32_t kVendoredBundleLineBytes = 2000;

// ── the SHAPE-CONDITIONAL document tier (the path half; queryshape.h is the query half) ─────────────────
// The tiers above are query-INDEPENDENT: a fixture is a fixture whatever was asked. This one is not. It
// fires only when the query itself says the answer cannot be prose — a pasted stack trace, sanitizer
// report or compiler diagnostic, or a pasted issue-template form. The mechanism is deliberately the tier
// multiplier and NOT a scoring change, a length floor, or a re-rank: the same shrink-only factor, folded
// into the same loop, with the same MaxScore-bound argument, and the same "de-prioritized is not absent"
// contract — those files stay indexed, still score, still surface when nothing else matches, and the
// query-mention anchor (which runs AFTER this) still lifts a document the query literally names.
//
// REPOSITORY META-PROSE takes the factor TWICE. A repository's documents ABOUT ITSELF — its issue and
// pull-request templates, its contributing / conduct / security / support policies, its changelog — are
// written in exactly the vocabulary a pasted bug report carries, and no failure ever lives in one. Twice
// the SAME factor, not a second constant: nothing new was calibrated here, the file is simply disqualified
// on two independent counts. Extend the stem table below rather than starting a third component list.
//
// The disclosure is not optional and not paraphrased — shapeDemotionNote() below is the one spelling, it
// rides in route= verbatim, and the callers gate the whole mechanism on the routed path precisely because
// route= is the only place it can be said.
inline constexpr int   kShapeDocMulPct = 35;                             // the calibrated tier factor, as a percent
inline constexpr float kShapeDocMul    = float( kShapeDocMulPct ) / 100.f;
static_assert( kShapeDocMul == kRankTierDemoMul,
               "the shape demotion REUSES the calibrated tier factor — it must never introduce a second one" );
static_assert( kShapeDocMulPct >= 10 && kShapeDocMulPct <= 99,
               "shapeFactorText() below prints exactly two decimals" );

// Basename stems, extension stripped and lowercased. `.github/` and `.gitlab/` are covered by the
// directory rule instead, so a template that keeps its upstream name is caught either way.
inline constexpr std::string_view kRepoMetaDocStems[] = {
    "contributing", "code_of_conduct", "code-of-conduct", "changelog", "changes", "history",
    "security", "support", "governance", "maintainers", "codeowners", "issue_template",
    "pull_request_template", "bug_report", "feature_request" };

// Only ever NARROWS the document tier: a source file is never repository meta-prose, whatever it is called.
inline bool isRepoMetaDocPath( std::string_view p ) noexcept
{
    if( pathTierOf( p ) != PathTier::Doc )
    {
        return false;
    }
    for( std::string_view seg : { std::string_view( ".github/" ), std::string_view( ".gitlab/" ) } )
    {
        if( hasDirSegment( p, seg ) )
        {
            return true;
        }
    }

    const std::size_t      slashPos = p.rfind( '/' );
    const std::string_view fileName = ( slashPos == std::string_view::npos ) ? p : p.substr( slashPos + 1 );
    const std::size_t      dotPos   = fileName.rfind( '.' );
    const std::string_view stem     = ( dotPos == std::string_view::npos ) ? fileName : fileName.substr( 0, dotPos );

    std::string lowerStem;
    lowerStem.reserve( stem.size() );
    for( const char ch : stem )   // EXPLICIT narrowing, as elsewhere in this tree
    {
        const unsigned char c = static_cast<unsigned char>( ch );
        lowerStem.push_back( ( c >= 'A' && c <= 'Z' ) ? char( c - 'A' + 'a' ) : char( c ) );
    }
    for( std::string_view knownStem : kRepoMetaDocStems )
    {
        if( lowerStem == knownStem )
        {
            return true;
        }
    }
    return false;
}

// the shape factor for one path — 1.0 for anything that is not a document
inline float shapeDocMultiplierOf( std::string_view p ) noexcept
{
    if( pathTierOf( p ) != PathTier::Doc )
    {
        return 1.0f;
    }
    return isRepoMetaDocPath( p ) ? kShapeDocMul * kShapeDocMul : kShapeDocMul;
}

// "0.35" from the integer percent, so the disclosure below cannot drift from the constant above and no
// float formatting (hence no locale) is involved in an emitted byte.
inline std::string shapeFactorText( int pct )
{
    std::string out = "0.";
    out.push_back( char( '0' + pct / 10 ) );
    out.push_back( char( '0' + pct % 10 ) );
    return out;
}

// The ONE spelling of what happened, appended to the routed reason so it lands in route= (and its JSON
// twin) verbatim. Empty when no shape fired — silence means nothing happened, the same convention route=
// and over_ceiling already use.
//
// PR #215 review item 4 — and the ONE PRODUCER of the whole route= value is routeNoteOf() below it, because the
// four sites that built this string by hand did not all build the same string. Row 6 made route= a CODE
// (`name-exact(X)`, `subtoken+body[:broad|:declined(…)]`) and dropped the "routed: " prose prefix at three of
// them; the MCP FILE PAGE kept `"routed: " + rc.reason`, so one server, on one query, answered its bundle with
// `route="name-exact(pick)"` and its page with `route="routed: name-exact(pick)"` — a spelling no legend in the
// product defines, and a parity break with both the CLI page and this server's own default serving. A value
// with a vocabulary needs a producer, not four spellings.
inline std::string shapeDemotionNote( const queryshape::Verdict& shape );

// `noRoute` is the caller's --no-route / no_route: the router never ran, so there is no route to report and the
// attribute is absent (ctxRootOpen omits it on an empty value). Every route= on every surface comes from here.
template<typename RouteChoiceT>
inline std::string routeNoteOf( const RouteChoiceT& rc, const queryshape::Verdict& shape, bool noRoute )
{
    return noRoute ? std::string() : rc.reason + shapeDemotionNote( shape );
}

inline std::string shapeDemotionNote( const queryshape::Verdict& shape )
{
    if( !shape.fires() )
    {
        return {};
    }
    const std::string factor = shapeFactorText( kShapeDocMulPct );

    std::string note = "; doc tier demoted (query is ";
    if( shape.trace )
    {
        note += "trace-shaped: " + std::to_string( shape.frameCount ) + " " + shape.frameFormat + " frame";
        note += shape.frameCount == 1 ? "" : "s";
    }
    if( shape.trace && shape.bugReport )
    {
        note += "; ";
    }
    if( shape.bugReport )
    {
        note += "bug-report-form-shaped: " + std::to_string( shape.formFamilies ) + " template label";
        note += shape.formFamilies == 1 ? "" : "s";
    }
    note += ") — documents x" + factor + ", repo meta-docs x" + factor + " twice";
    return note;
}

// The machine form of the same fact, for surfaces that carry attributes rather than prose (the candidates
// export's doc_tier=). nullptr ⇒ attribute absent ⇒ nothing happened, the same silence convention route=
// and weak= use. Static strings: an attribute value must not allocate on a per-row emit path.
inline const char* shapeDocTierTag( const queryshape::Verdict& shape ) noexcept
{
    // one row per (trace, bugReport) bit pair — the declarative-table rule, and it keeps the four cases
    // impossible to spell inconsistently with shapeDemotionNote above
    static constexpr const char* kDocTierTags[ 4 ] = { nullptr, "demoted:trace", "demoted:bug-report",
                                                       "demoted:trace+bug-report" };
    return kDocTierTags[ ( shape.trace ? 1u : 0u ) | ( shape.bugReport ? 2u : 0u ) ];
}

// tier factors fanned out per def, via each def's file (every entry in (0,1] — shrink-only keeps the
// MaxScore bound in lexical.h safe, same argument as its Section down-weight).
// demoteDocTier: the shape-conditional document factor above, folded into the SAME per-file pass rather
// than a second multiplier vector the callers would have to remember to combine. A SEPARATE entry point
// rather than a defaulted parameter, exactly as lexicalScoresTiered is separate from lexicalScores: the
// query-independent contract every existing consumer holds does not change arity, so a caller that never
// heard of query shapes cannot accidentally acquire an opinion about it.
inline std::vector<float> rankTierSymbolMultipliersShaped( const IngestResult& ing, bool demoteDocTier )
{
    std::vector<float> fileMul( ing.files.size(), 1.f );
    for( std::size_t f = 0; f < ing.files.size(); ++f )
    {
        fileMul[f] = rankTierMultiplierOf( rootRelPath( ing, std::uint32_t( f ) ) );
        // min(), not assignment or a product: a file already down-weighted for being a deck or a fixture
        // must never be LIFTED by this line, and two independent de-prioritizations are one claim about
        // one file, not a compounding penalty.
        if( demoteDocTier )
        {
            fileMul[f] = std::min( fileMul[f], shapeDocMultiplierOf( rootRelPath( ing, std::uint32_t( f ) ) ) );
        }
    }

    // then the EVIDENCE tier above: any def whose own span trips the bundle floor demotes its whole file.
    for( const Symbol& s : ing.symbols )
    {
        if( s.loc == 0 || s.endByte <= s.sigStartByte || s.fileId >= fileMul.size() )
        {
            continue; // loc==0 is Symbol's own default (never-measured — a def path off ingest.cpp's own
                       // extractor always leaves loc>=1); guards the division below, not a kind filter.
        }
        if( ( s.endByte - s.sigStartByte ) / s.loc >= kVendoredBundleLineBytes )
        {
            // min(), not assignment — a file a PATH rule already demoted further must never be lifted up.
            fileMul[s.fileId] = std::min( fileMul[s.fileId], kRankTierDemoMul );
        }
    }

    std::vector<float> mul( ing.symbols.size(), 1.f );
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        if( ing.symbols[i].fileId < fileMul.size() )
        {
            mul[i] = fileMul[ing.symbols[i].fileId];
        }
        // L8: an in-file test symbol earns the SAME tier factor its path-classified twin already gets —
        // the file it lives in is production, so fileMul above left it at 1.0. min(), not assignment, so a
        // file that is ALREADY down-weighted (a fixture, a deck) can never be lifted back up by this line.
        if( ing.symbols[i].testScope != 0 )
        {
            mul[i] = std::min( mul[i], kRankTierTestMul );
        }
    }
    return mul;
}

// the query-INDEPENDENT contract every pre-shape caller keeps (--query, and any lens that ranks without
// a query shape to read): same arity as always, byte-identical multipliers.
inline std::vector<float> rankTierSymbolMultipliers( const IngestResult& ing )
{
    return rankTierSymbolMultipliersShaped( ing, /*demoteDocTier=*/false );
}

// the tier's own inverse, for the weak-evidence honesty signal (R4 weak=): the strongest score with the
// tier factor divided back OUT — a corpus whose best evidence lives under a down-weighted path still HAS
// that evidence; de-prioritized is not absent. (Under MaxScore pruning a down-weighted entry outside the
// kept head stays 0 and escapes the divide-back — only material within a ~3x band of the threshold, far
// inside the calibrated margin documented at kWeakLexicalScoreThreshold.)
inline float maxScoreUndoingTier( const std::vector<float>& rank, const std::vector<float>& tierMul )
{
    ASSUME( rank.size() == tierMul.size() );
    float rawMax = 0.f;
    for( std::size_t i = 0; i < rank.size() && i < tierMul.size(); ++i )
    {
        rawMax = std::max( rawMax, tierMul[i] > 0.f ? rank[i] / tierMul[i] : rank[i] );
    }
    return rawMax;
}

// ── the CHANGE-LOG and TRANSLATION document tier (query-conditional; path half + query half, both here) ───
// Dogfood 2026-09-26, a public Python repo (10,606 symbols): for a CODE question, three `### Added` sections of
// CHANGELOG.md and one section of README.hi-IN.md took 4 of the top 20 --for slots. Neither kind of file explains
// code: a change log records THAT something changed, and a translated README repeats the default-language one,
// which is itself a candidate. They reached the head through doc-mention surfacing (mention.h
// applyDocMentionBoost): both kinds backtick the same identifiers the code defines, and the per-anchor cap took
// the lowest node ids, which path order hands to `CHANGELOG.md` and `README.hi-IN.md` ahead of `README.md`.
//
// The mechanism is the §P4 one — a shrink-only per-symbol factor, never exclusion — at the SAME calibrated 0.35
// (no second constant): folded into BM25 through tierMul (foldDocNoiseTier), and read by the doc-mention lift,
// which consults these docs only AFTER every full-weight doc and lifts them to target × this factor. The files
// stay indexed, scored and in the candidate pool; `--mentions=SYM` still lists them.
//
// It does NOT apply when the question is ABOUT what these files hold — both exemptions are per file, so they
// can only ever restore the pre-tier ranking:
//   * a change log keeps full weight when the task carries a change cue (kChangeQuestionCues: "what changed in
//     1.2", "when was X added", "which version …") or spells the file's own stem (`news`, `history`, `changes`);
//   * a translation keeps full weight when the task carries a translation cue (kTranslationQuestionCues) or spells
//     its language tag (`zh-CN`, `ja`) — which a task naming `README.zh-CN.md` does;
//   * and the mention anchor (applyMentionBoost, which runs after this tier) still lifts any file the task names.
// Routed path only, like the shape tier above: --no-route is the A/B handle and restores the old ranking.

// Change-log BASENAMES, lowercased: a stem matches as a PREFIX followed by the end or a non-letter, so
// CHANGELOG.md, CHANGES.rst, HISTORY.md, NEWS, RELEASE_NOTES.md and changelog-2023.md match while newsletter.md
// and historyoracle.md do not. `release.md` is deliberately absent: that name usually documents how to CUT a
// release, which is process, not a record of changes.
inline constexpr std::string_view kChangeLogStems[] = { "changelog", "changes", "history", "news",
                                                        "release-notes", "release_notes", "releasenotes", "releases" };

// Whole directory components that hold per-release notes (towncrier's changelog.d/, docs/releases/<ver>.rst).
inline constexpr std::string_view kChangeLogDirs[] = { "changelog/", "changelog.d/", "changelogs/", "release-notes/",
                                                       "release_notes/", "releasenotes/", "releases/" };

// Question cues, matched word-bounded in the lowercased task ([a-z0-9_] is a word byte); `prefix` lets the cue
// end inside a word (`release` covers releases/released, `version` covers versions/versioning). These are the
// only word lists the tier uses. A false cue is the cheap side to be wrong on: it restores the old ranking.
struct DocNoiseCue
{
    std::string_view word;
    bool             prefix;
};
inline constexpr DocNoiseCue kChangeQuestionCues[] = { { "added", false },     { "changed", false }, { "changelog", true },
                                                       { "deprecat", true },   { "introduced", false }, { "release", true },
                                                       { "removed", false },   { "version", true } };
inline constexpr DocNoiseCue kTranslationQuestionCues[] = { { "i18n", false }, { "l10n", false }, { "locali", true },
                                                            { "translat", true } };

// English spellings a parallel docs tree names its DEFAULT-language directory with (docs/en/, docs/source/en/).
inline constexpr std::string_view kDefaultLanguageDirs[] = { "en", "en-gb", "en-us", "en_gb", "en_us" };

inline constexpr float kDocNoiseMul = kRankTierDemoMul;
static_assert( kDocNoiseMul > 0.f && kDocNoiseMul < 1.f, "a shrink-only (0,1) factor keeps the MaxScore bound in lexical.h safe" );

inline bool isAsciiWordByte( char c ) noexcept
{
    return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_';
}

inline bool isAsciiLetter( char c ) noexcept
{
    return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' );
}

inline std::string lowerAsciiCopy( std::string_view s )
{
    std::string out;
    out.reserve( s.size() );
    for( const char ch : s )   // EXPLICIT narrowing, as elsewhere in this tree
    {
        const unsigned char c = static_cast<unsigned char>( ch );
        out.push_back( ( c >= 'A' && c <= 'Z' ) ? char( c - 'A' + 'a' ) : char( c ) );
    }
    return out;
}

// `word` occurs in the (already lowercased) task with a word boundary before it, and after it unless `prefix`.
inline bool taskHasCue( std::string_view lowerTask, std::string_view word, bool prefix ) noexcept
{
    EXPECTS( !word.empty(), "an empty cue would match everywhere" );
    for( std::size_t pos = lowerTask.find( word ); pos != std::string_view::npos; pos = lowerTask.find( word, pos + 1 ) )
    {
        const std::size_t end = pos + word.size();
        if( ( pos == 0 || !isAsciiWordByte( lowerTask[pos - 1] ) ) && ( prefix || end == lowerTask.size() || !isAsciiWordByte( lowerTask[end] ) ) )
        {
            return true;
        }
    }
    return false;
}

template<std::size_t N>
inline bool taskHasAnyCue( std::string_view lowerTask, const DocNoiseCue ( &cues )[N] ) noexcept
{
    return std::any_of( std::begin( cues ), std::end( cues ), [lowerTask]( const DocNoiseCue& c ) { return taskHasCue( lowerTask, c.word, c.prefix ); } );
}

// The change-log stem a LOWERCASED root-relative path matches (a basename stem, or a kChangeLogDirs component
// without its slash); empty when it is not a change log. The caller has already established the file is prose.
inline std::string_view changeLogStemOf( std::string_view lowerPath ) noexcept
{
    for( const std::string_view dir : kChangeLogDirs )
    {
        if( hasDirSegment( lowerPath, dir ) )
        {
            return dir.substr( 0, dir.size() - 1 );
        }
    }
    const std::size_t      slashPos = lowerPath.rfind( '/' );
    const std::string_view fileName = ( slashPos == std::string_view::npos ) ? lowerPath : lowerPath.substr( slashPos + 1 );
    for( const std::string_view stem : kChangeLogStems )
    {
        if( fileName.starts_with( stem ) && ( fileName.size() == stem.size() || !isAsciiLetter( fileName[stem.size()] ) ) )
        {
            return stem;
        }
    }
    return {};
}

// An ISO 639-1-shaped language tag: two letters, optionally joined by '-' or '_' to a region (two letters, or
// three digits as in es-419) or a script (four letters, zh-Hant). Case-insensitive. SHAPE only — which is why
// every caller also demands a default-language twin before it calls a file a translation.
inline bool isLanguageTagShape( std::string_view tag ) noexcept
{
    if( tag.size() < 2 || !isAsciiLetter( tag[0] ) || !isAsciiLetter( tag[1] ) )
    {
        return false;
    }
    if( tag.size() == 2 )
    {
        return true;
    }
    if( tag[2] != '-' && tag[2] != '_' )
    {
        return false;
    }
    const std::string_view sub = tag.substr( 3 );
    if( sub.size() == 3 )
    {
        return std::all_of( sub.begin(), sub.end(), []( char c ) { return c >= '0' && c <= '9'; } );
    }
    return ( sub.size() == 2 || sub.size() == 4 ) && std::all_of( sub.begin(), sub.end(), isAsciiLetter );
}

// English is the default language this tier assumes; an `en` tag is never a translation. A repository whose
// default README is in another language (README.md in Chinese beside README.en.md) is therefore left alone:
// neither file carries a non-English tag with an untagged twin.
inline bool isDefaultLanguageTag( std::string_view tag ) noexcept
{
    return tag.size() >= 2 && ( tag[0] == 'e' || tag[0] == 'E' ) && ( tag[1] == 'n' || tag[1] == 'N' );
}

// Per-symbol factor for the change-log / translation tier under THIS task: kDocNoiseMul on every symbol of a file
// the rules above demote, 1 elsewhere. EMPTY when nothing is demoted — the caller's cue that the whole tier is inert
// and every downstream consumer must be byte-identical to a build without it.
//
// A file is a TRANSLATION on filename evidence plus a default-language TWIN that the index also holds (compared
// lowercased, same extension):
//   * basename form: README.zh-CN.md / README_ja.md / guide-ko.rst, twin README.md / guide.rst in the same directory;
//   * directory form: docs/ja/guide.md with a twin at docs/en/guide.md (any kDefaultLanguageDirs spelling), or at
//     docs/guide.md with the component removed. The removal twin is weaker evidence — `ui/README.md` beside
//     `README.md` is not a Ukrainian page — so it counts only for a tag with a region/script subtag, or for a
//     language directory holding at least two such files (a parallel tree, not a coincidence of one name).
inline std::vector<float> docNoiseSymbolMultipliers( const IngestResult& ing, std::string_view task )
{
    const std::string lowerTask      = lowerAsciiCopy( task );
    const bool        changeAsked    = taskHasAnyCue( lowerTask, kChangeQuestionCues );
    const bool        translateAsked = taskHasAnyCue( lowerTask, kTranslationQuestionCues );
    if( changeAsked && translateAsked )
    {
        return {};
    }

    // the prose files, lowercased root-relative — the only population either rule can match or twin against
    std::vector<std::uint32_t> proseIds;
    std::vector<std::string>   lowerOf( ing.files.size() );
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view p = rootRelPath( ing, f );
        if( pathTierOf( p ) == PathTier::Doc )
        {
            proseIds.push_back( f );
            lowerOf[f] = lowerAsciiCopy( p );
        }
    }
    if( proseIds.empty() )
    {
        return {};
    }

    std::vector<std::uint8_t> fileDemoted( ing.files.size(), 0 );
    bool                      anyDemoted = false;
    auto                      demote     = [ & ]( std::uint32_t f ) { fileDemoted[f] = 1; anyDemoted = true; };

    if( !changeAsked )
    {
        for( const std::uint32_t f : proseIds )
        {
            const std::string_view stem = changeLogStemOf( lowerOf[f] );
            if( !stem.empty() && !taskHasCue( lowerTask, stem, false ) )
            {
                demote( f );
            }
        }
    }

    if( !translateAsked )
    {
        std::vector<std::string_view> sortedLower;   // the twin index: binary-searched, so no hash order can reach output
        sortedLower.reserve( proseIds.size() );
        for( const std::uint32_t f : proseIds )
        {
            sortedLower.push_back( lowerOf[f] );
        }
        std::sort( sortedLower.begin(), sortedLower.end() );
        const auto has = [ & ]( const std::string& p ) { return std::binary_search( sortedLower.begin(), sortedLower.end(), std::string_view( p ) ); };

        // removal-twin evidence per language directory (its lowercased prefix, through the tag's slash)
        struct RemovalHit { std::string langDir; std::uint32_t fileId; std::string tag; bool strong; };
        std::vector<RemovalHit> removalHits;

        for( const std::uint32_t f : proseIds )
        {
            const std::string&     lp       = lowerOf[f];
            const std::size_t      slashPos = lp.rfind( '/' );
            const std::string      dirPart  = ( slashPos == std::string::npos ) ? std::string() : lp.substr( 0, slashPos + 1 );
            const std::string_view fileName = std::string_view( lp ).substr( dirPart.size() );
            const std::size_t      dotPos   = fileName.rfind( '.' );
            const std::string_view stem     = ( dotPos == std::string_view::npos ) ? fileName : fileName.substr( 0, dotPos );
            const std::string_view ext      = ( dotPos == std::string_view::npos ) ? std::string_view() : fileName.substr( dotPos );

            std::string_view tag;
            // basename form: <base><sep><tag><ext>, twin <base><ext> beside it
            for( std::size_t i = 1; i + 1 < stem.size() && tag.empty(); ++i )
            {
                const std::string_view cand = stem.substr( i + 1 );
                if( ( stem[i] == '.' || stem[i] == '_' || stem[i] == '-' ) && isLanguageTagShape( cand ) && !isDefaultLanguageTag( cand )
                 && has( dirPart + std::string( stem.substr( 0, i ) ) + std::string( ext ) ) )
                {
                    tag = cand;
                }
            }
            // directory form: a language-tag component with an English sibling tree, or (weaker) with the component removed
            for( std::size_t begin = 0; begin < dirPart.size() && tag.empty(); )
            {
                const std::size_t      end  = dirPart.find( '/', begin );
                const std::string_view comp = std::string_view( dirPart ).substr( begin, end - begin );
                if( isLanguageTagShape( comp ) && !isDefaultLanguageTag( comp ) )
                {
                    const std::string head = dirPart.substr( 0, begin );
                    const std::string rest = lp.substr( end + 1 );
                    for( const std::string_view en : kDefaultLanguageDirs )
                    {
                        if( tag.empty() && has( head + std::string( en ) + "/" + rest ) )
                        {
                            tag = comp;
                        }
                    }
                    if( tag.empty() && has( head + rest ) )
                    {
                        removalHits.push_back( { dirPart.substr( 0, end + 1 ), f, std::string( comp ), comp.size() > 2 } );
                    }
                }
                begin = end + 1;
            }
            if( !tag.empty() && !taskHasCue( lowerTask, tag, false ) )
            {
                demote( f );
            }
        }

        // the removal form: strong on its own, else only where the same language directory has two or more hits
        std::sort( removalHits.begin(), removalHits.end(), []( const RemovalHit& a, const RemovalHit& b )
                   { return a.langDir != b.langDir ? a.langDir < b.langDir : a.fileId < b.fileId; } );
        for( std::size_t i = 0; i < removalHits.size(); )
        {
            std::size_t j = i;
            while( j < removalHits.size() && removalHits[j].langDir == removalHits[i].langDir )
            {
                ++j;
            }
            for( std::size_t k = i; k < j; ++k )
            {
                const RemovalHit& h = removalHits[k];
                if( ( h.strong || j - i >= 2 ) && !fileDemoted[h.fileId] && !taskHasCue( lowerTask, h.tag, false ) )
                {
                    demote( h.fileId );
                }
            }
            i = j;
        }
    }

    if( !anyDemoted )
    {
        return {};
    }
    std::vector<float> mul( ing.symbols.size(), 1.f );
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        const std::uint32_t f = ing.symbols[i].fileId;
        if( f < fileDemoted.size() && fileDemoted[f] != 0 )
        {
            mul[i] = kDocNoiseMul;
        }
    }
    ENSURES( mul.size() == ing.symbols.size(), "one factor per symbol, or none at all" );
    return mul;
}

// Fold the tier above into the §P4 tier vector BM25 scores with. min(), not a product, for the reason
// rankTierSymbolMultipliersShaped gives: one file de-prioritized twice is one claim, not a compounding penalty —
// a change log a trace-shaped query already demoted as repository meta-prose keeps that deeper factor.
inline void foldDocNoiseTier( std::vector<float>& tierMul, const std::vector<float>& docNoiseMul ) noexcept
{
    EXPECTS( docNoiseMul.empty() || docNoiseMul.size() == tierMul.size(), "both are per-symbol over the same index" );
    for( std::size_t i = 0; i < docNoiseMul.size() && i < tierMul.size(); ++i )
    {
        tierMul[i] = std::min( tierMul[i], docNoiseMul[i] );
    }
}

// Order a file-id list by a per-id KEY descending, PATH ascending as the tiebreak — the shared
// "most-consequential-first, and deterministically so" ordering the first-screen verbs need (§P11.7
// --pr-context by blast radius, §P11.8 --tree by best-symbol rank). Templated on the key because one of
// those is a dependent COUNT and the other a PageRank score; the path tiebreak is what makes the result a
// TOTAL order rather than merely a stable one, so two runs over the same corpus agree byte for byte.
template<class Key>
inline void orderIdsByKeyDescPathAsc( std::vector<std::uint32_t>& ids, const std::vector<Key>& key,
                                      const std::vector<std::string>& paths )
{
    std::sort( ids.begin(), ids.end(), [ & ]( std::uint32_t a, std::uint32_t b )
               { return key[a] != key[b] ? key[a] > key[b] : paths[a] < paths[b]; } );
}

// remove defs + refs in test files; remap remaining symbol ids to a dense [0,N) range.
//
// L8: the DEF side is now SYMBOL-keyed (isTestSymbol), so a `#[cfg(test)] mod` member inside a production
// .rs file is dropped like a symbol under `tests/`. The REF/BINDING side stays FILE-keyed on purpose: a
// whole test FILE contributes nothing, while a production file that merely contains a test module still
// holds production references that must survive. What that leaves behind is exactly the FILE-SCOPE
// references inside an in-file test block (fromSymbol == kNoNode, so no dropped owner identifies them) —
// a floor, not a claim of completeness, and the same honest shape the resolver's `amb=` already takes.
inline void applyIgnoreTests( IngestResult& ing )
{
    std::vector<char> drop( ing.files.size(), 0 );
    for( std::size_t f = 0; f < ing.files.size(); ++f )
    {
        drop[f] = isTestPath( rootRelPath( ing, std::uint32_t( f ) ) ) ? 1 : 0;   // #228: a tests/ ABOVE the root is not this tree's
    }

    std::vector<NodeId> remap( ing.symbols.size(), kNoNode );
    std::vector<Symbol> keptSyms;
    keptSyms.reserve( ing.symbols.size() );
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        if( !isTestSymbol( ing, i ) )
        {
            const Symbol& s   = ing.symbols[i];
            const NodeId  nid = NodeId( keptSyms.size() );
            remap[ s.id ] = nid;
            Symbol c = s;  c.id = nid;
            keptSyms.push_back( std::move( c ) );
        }
    }

    std::vector<Reference> keptRefs;
    keptRefs.reserve( ing.references.size() );
    for( const Reference& r : ing.references )
    {
        if( drop[r.fileId] )
        {
            continue;
        }
        Reference c = r;
        if( c.fromSymbol != kNoNode )
        {
            const NodeId nf = remap[ c.fromSymbol ];
            if( nf == kNoNode )
            {
                continue; // caller was a test symbol → drop
            }
            c.fromSymbol = nf;
        }
        keptRefs.push_back( std::move( c ) );
    }

    // bindings carry fromSymbol ids too — left unremapped they key Rule-2 narrowing to whatever PRODUCTION
    // symbol inherits a dropped test symbol's id, producing confidently WRONG call edges.
    std::vector<Binding> keptBinds;
    keptBinds.reserve( ing.bindings.size() );
    for( const Binding& b : ing.bindings )
    {
        if( drop[b.fileId] )
        {
            continue;
        }
        Binding c = b;
        if( c.fromSymbol != kNoNode )
        {
            const NodeId nf = remap[ c.fromSymbol ];
            if( nf == kNoNode )
            {
                continue; // scope was a test symbol → drop
            }
            c.fromSymbol = nf;
        }
        keptBinds.push_back( std::move( c ) );
    }

    ing.symbols    = std::move( keptSyms );
    ing.references = std::move( keptRefs );
    ing.bindings   = std::move( keptBinds );
}

}   // namespace rw
