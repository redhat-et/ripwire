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

inline bool isTestPath( std::string_view p ) noexcept
{
    // directory segment: test/ or tests/  (bounded by '/' or start)
    for( std::string_view seg : { std::string_view( "test/" ), std::string_view( "tests/" ) } )
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
    return s.fileId < ing.files.size() && isTestPath( ing.files[s.fileId] );
}

// ── §P11 first-screen ORDERING tiers ─────────────────────────────────────────────────────────────────────
// Several LISTING verbs serialized their rows in plain path-alphabetical order, which on a doc-heavy repo is
// a systematic bias against code: `AGENTS.md` and other long-named docs sort above `src/`, and a fixed row cap then cuts
// the deepest paths — usually the code — first (`--grep=DEGRADED_PATH_ALERT` showed 34 src + 66 doc rows and
// not one `test/` or `third_party/` row, the macro's own definition site included).
//
// This is a pure ORDERING key and nothing else: no row is dropped, no attribute is added or changed, and
// within one tier the pre-existing order (path-alphabetical, or rank) is preserved exactly. A reader who
// wants the old shape still gets every row, just later.
enum class PathTier : std::uint8_t { Source = 0, TestOrBench = 1, Doc = 2 };

// Extension decides DOC first (a `.md` under `test/` is prose, not a test), then the directory convention
// decides TEST/BENCH, and everything left is source. Markdown is spelled out because docparse::docKindOf
// deliberately excludes it — `.md` is ingested as a first-class document, not through an extractor.
inline PathTier pathTierOf( std::string_view p ) noexcept
{
    const std::string ext = docparse::lowerExtOf( p );
    if( ext == ".md" || ext == ".markdown" || ext == ".rst" || ext == ".txt" || docparse::isDocExtension( ext ) )
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
            tierOfFile[f] = std::uint8_t( pathTierOf( ing.files[f] ) );
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
inline constexpr std::string_view kDemoOrGeneratedDirs[] = { "present/", "docs/captures/", "static/", "locale/", "min/" };

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
    return hasDirSegment( p, "migrations/" ) && isNumberedMigrationFileName( fileName );
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
        fileMul[f] = rankTierMultiplierOf( ing.files[f] );
        // min(), not assignment or a product: a file already down-weighted for being a deck or a fixture
        // must never be LIFTED by this line, and two independent de-prioritizations are one claim about
        // one file, not a compounding penalty.
        if( demoteDocTier )
        {
            fileMul[f] = std::min( fileMul[f], shapeDocMultiplierOf( ing.files[f] ) );
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
    VERIFY( rank.size() == tierMul.size() );
    float rawMax = 0.f;
    for( std::size_t i = 0; i < rank.size() && i < tierMul.size(); ++i )
    {
        rawMax = std::max( rawMax, tierMul[i] > 0.f ? rank[i] / tierMul[i] : rank[i] );
    }
    return rawMax;
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
        drop[f] = isTestPath( ing.files[f] ) ? 1 : 0;
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
