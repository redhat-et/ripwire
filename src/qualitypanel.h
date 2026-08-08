#pragma once

// qualitypanel.h — `--quality-panel[=strict|default|lenient]`: THE SINGLE COMMAND.
//
// THE ASK. The quality signal in this tool is scattered across --ensemble, --context-ratio, --nonlocal-state,
// --readability, --lint's two rule packs and --quality-delta. --ensemble is already the JOIN, but it joins only
// the four families wave 1 shipped; the wave-2 lenses are not in it. So the panel was real and incomplete. This
// verb is the whole panel, reported ONCE, ranked ONCE.
//
// WHY A NEW VERB AND NOT A WIDER --ensemble. Two reasons, both about not breaking something that is already
// calibrated:
//   1. `--ensemble` IS the published instrument behind docs/EVALS.md §9. Every number in that section — the
//      fire rates, the phi matrix, the co-firing ladder, the stability ladder — is that verb's output at FOUR
//      families. Adding families to it would silently invalidate the published record and change what fam= and
//      of= mean for anyone already reading it. §9 stays reproducible because --ensemble does not move.
//   2. A preset is a SELECTION, and --ensemble has no selection: it reports every family it has. Giving it one
//      would make its default output a choice rather than the whole join.
// So --ensemble keeps its four families and its file rollup untouched, and the panel CALLS it — literally
// ensemble::computeEnsemble, through its own entry point — for those four. The two verbs cannot drift, because
// there is exactly one implementation of the four calibrated families and the panel is not it.
//
// THE SIX FAMILIES. Four are ensemble's, unchanged and uncalibrated-by-me; two are new and had to earn it:
//   structural  the SHAPE of the code (ccx / loc / nest / params bars + the Posnett readability rank)
//   lexical     the identifier TEXT (the naming-* rules)
//   confusion   the syntactic CONSTRUCT (the atom-* rules)
//   historical  git change frequency (the --hotspots churn axis) — PER FILE, so the row inherits it
//   colocation  how much of what you must READ to understand this function lives outside its own file
//               (--context-ratio, src/contextratio.h) — the LOCAL-REASONING axis
//   state       the function's OWN BODY touching non-local MUTABLE state (--nonlocal-state,
//               src/nonlocalstate.h) — the ACTION-AT-A-DISTANCE axis
//
// A NEW FAMILY EARNS ITS PLACE BEFORE IT IS ENABLED, NEVER AFTER. §9.1's rule is that corroboration is worth
// something only when the lenses fail DIFFERENTLY; a family that correlates with an existing one is that one
// wearing a second hat. Both candidates were run through bench/ensemblecal/ on the same five independent
// corpora §9 used, BEFORE this verb shipped them enabled. The matrix is in docs/EVALS.md §9.9. Pooled, the
// largest cross-family phi involving a new family is +0.163 (structural x state) and +0.096
// (structural x colocation) — inside the envelope §9 already published for the four (+0.168 pooled). Both pass.
//
// WHY `state` IS THE OWN-BODY HALF AND NOT THE TRANSITIVE ONE. --nonlocal-state reports both: writes=/reads=
// are the CALLEE-CLOSURE union, direct_writes=/direct_reads= are what this function's own text does. The panel's
// unit is one function's own comprehensibility, so the family must be a property of THAT function's body — the
// closure half is a fact about its callees. The measurement agrees with the principle rather than driving it:
// the closure form fires on 35% of one corpus and correlates with structural at phi +0.201, the own-body form
// fires on 18% at worst and at +0.163. The principled choice was also the orthogonal one; had it not been, the
// principle would still have won and the family would have been dropped.
//
// WHY --field-affinity IS NOT A FAMILY, and this is an exclusion by UNIT, not a failed measurement. That lens
// measures an AGGREGATE: which of a struct's fields are read together but declared far apart, scored with
// Chilimbi's cache-line separation weight. Its unit is a type and its subject is memory layout. To make it a
// family here it would have to be attributed to the functions that touch those fields — flagging a function for
// a property of a type it merely uses, an attribution the lens itself never makes. A panel row must be a claim
// about the row's own symbol. It is left out and said so, rather than folded in on a plausible-looking join.
//
// PRESETS SELECT, THEY NEVER WEIGHT. A preset is exactly two things: WHICH families count, and HOW MANY must
// agree. There is no weight, no score and no composite anywhere in this verb, by contract — that is §3.10's
// Maintainability-Index failure mode and the whole reason the rank is an ordinal family count. The three are
// derived in docs/EVALS.md §9.7/§9.9 from measured distributions, not chosen:
//   lenient  all six, fam >= 1   a browse list / reading order
//   default  all six, fam >= 2   a review list
//   strict   the four MEASURED-STABLE families, fam >= 2   the only rung the stability data supports gating on
//
// TWO FAMILIES ARE OUT OF `strict`, AND BOTH EXCLUSIONS ARE MEASUREMENTS. §9.5 ran one binary over a ladder of
// past commits and found `historical`'s flagged set at mean consecutive Jaccard 0.800-0.862 and endpoint
// 0.426-0.546 — on gameA, 40% of the symbols it flagged in June were unflagged in July on code that had not
// changed. §9.9 ran the SAME ladder on the two new families rather than assuming they inherited the others'
// stability, and that is how the second exclusion was found: on the ctxpack ladder `colocation` comes out at
// 0.732 mean consecutive and 0.222 endpoint — WORSE than historical, and the worst endpoint anywhere in either
// study. Measured per family, worst case over the two ladders: lexical 1.000, state 0.999, structural 0.965,
// confusion 0.920, historical 0.852, colocation 0.732. §9.7's own cut interval, (0.862, 0.920), is unchanged;
// what moved is which families fall on which side of it.
//
// THE MECHANISM IS THE SAME IN BOTH CASES, which is why this is a finding and not a coincidence: each is a
// FIXED-SIZE cut (the worst 40 ranks) over a ranking whose POPULATION moves. Churn is a rolling 12-month
// window, so a busy week reshuffles the file order; the local-reasoning ranking is by absolute outside-reading
// volume, so a tree that grew 19x across the ctxpack window reshuffles its top 40 completely. On a repository
// of stable size the same family is perfectly steady — colocation is 1.000/1.000 on the ripwire ladder. A
// family that is stable only while the corpus is not growing cannot carry a gate.
//
// Both stay in `default` and `lenient`, where a moving window is a feature and the report is a reading order
// rather than a verdict. Neither is in `strict`.
//
// UNAVAILABLE IS NOT FIRING, and the panel inherits every one of ensemble's four verdicts verbatim plus two of
// its own, decided PER CORPUS from what was indexed and never hardcoded:
//   colocation  the ranking is EMPTY — not one eligible function resolves a single definition outside its own
//               file. An ordinal family that ranked nothing fired for nobody for a reason that is not a fact
//               about the code, which is the exact case ensemble's historical family got wrong on its first run.
//   state       the lens analyses C++/ObjC/ObjC++ only (nonlocal::isAnalyzedLang, CALLED and never restated).
//               On a corpus with no eligible function in one of those, the family was never applicable rather
//               than quiet — the same shape, and the same defect class, the wave-2 calibration found in the
//               confusion family (§9.6 defect 1).
// of= is the count of ENABLED families that were EVALUABLE, so a row never counts a family that could not have
// been evaluated for it, and cut_reachable= says so out loud when the preset's cut exceeds that count.
//
// SCOPE: this verb JOINS and SELECTS. It computes no new metric, invents no threshold and adds no rule — every
// number in it comes out of machinery that already shipped, called through its existing entry point.
//
// THE ONE ANNOTATION, and why it is not a hole in that scope rule. `join="deep+untested"` marks a row that
// carries deep= (model.h Symbol::deepLoc, already inside the structural family's evidence string) and that
// computeQMetrics' tested= flag says no indexed test reaches. It is a CONJUNCTION of two facts the report
// already holds, not a metric: no new measurement, no new threshold, no entry point that did not exist. It is
// deliberately NOT a seventh family, because deep IS the structural family — counting it would be that family
// wearing a second hat, which is §9.1's disqualification and §3.10's failure mode in one. Structurally it
// cannot become one by accident: the flag is set AFTER the count and the cut are decided, and neither
// firedMask, countedMask, firedCount nor the sort comparator can see it. And it is suppressed when
// tested_scope=0, because on a corpus whose tests were never crawled "untested" describes the crawl and not
// the code — the same verdict the historical family's empty-ranking case already gets. Pinned by
// test/qualitypanelcheck.sh arm (O), on twin functions with byte-identical bodies and different coverage.
//
// DETERMINISM. Every stage sorts before it is read: the four calibrated families arrive already ordered from
// computeEnsemble, the colocation rank is a prefix of --context-ratio's own integer-keyed order, the state hits
// are walked in NodeId order, and the rows sort by (counted family count desc, NodeId asc) — NodeId is assigned
// in file/line/name order, so that is a total order. No float is compared or printed anywhere in this file.

#include "model.h"
#include "graph.h"           // Graph — computeNonLocalState walks the call graph for its closure
#include "ensemble.h"        // computeEnsemble + the four calibrated families, called through its own entry point
#include "contextratio.h"    // computeContextRatio — the colocation family's ranking, its own entry point
#include "nonlocalstate.h"   // computeNonLocalState + isAnalyzedLang — the state family and its language gate
#include "pageview.h"        // pageWindow + pagingDisclosure — THE TRUNCATION VOCABULARY
#include "gitstamp.h"        // atAttr — one family is git-mined, so the row set is stamped like --hotspots
#include "serialize.h"       // escapeXml

#include <algorithm>
#include <array>
#include <bit>
#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
namespace qpanel
{

// The symbol listing is the PRIMARY one (pageview.h rule 6): raisable with --limit, paged with --offset, in the
// same shape as --ensemble's 40.
inline constexpr std::size_t kPanelRowCap = 40;

// The two new family indices continue ensemble's numbering rather than restating it, so the four calibrated
// masks mean the same bit in both verbs and a mask can be handed from one to the other untouched.
enum : std::uint8_t
{
    kFamColocation    = ensemble::kFamilyCount,      // 4
    kFamState         = ensemble::kFamilyCount + 1,  // 5
    kPanelFamilyCount = ensemble::kFamilyCount + 2   // 6
};

inline constexpr std::array<const char*, 2> kNewFamilyNames = { { "colocation", "state" } };

// ONE name table for six families, and the four calibrated names are READ from ensemble's own table rather
// than copied into a second one — a copied name list is how a report ends up naming a family the join stopped
// using.
inline const char* familyName( std::uint8_t family ) noexcept
{
    return family < ensemble::kFamilyCount ? ensemble::kFamilyNames[family]
                                           : kNewFamilyNames[ family - ensemble::kFamilyCount ];
}

inline constexpr std::uint8_t kAllFamilies = std::uint8_t( ( 1u << kPanelFamilyCount ) - 1u );

// The families measured stable enough to stand behind a gate — everything but `historical` and `colocation`,
// BOTH of which the commit-ladder pass put below the criterion-C1 cut (docs/EVALS.md §9.9). This constant is
// the one place the verdict lives; the presets read it, so a family cannot be stable in the table and unstable
// in the prose.
inline constexpr std::uint8_t kUnstableForGating = std::uint8_t( ( 1u << ensemble::kFamHistorical ) | ( 1u << kFamColocation ) );
inline constexpr std::uint8_t kStableFamilies    = std::uint8_t( kAllFamilies & ~kUnstableForGating );

enum class Preset : std::uint8_t { Strict = 0, Default = 1, Lenient = 2 };

// A preset is a SELECTION and a CUT. No third field exists, and none may be added: a weight here would be the
// composite score this verb's rank is defined against.
struct PresetRow
{
    const char*   name;
    std::uint8_t  enabled;
    std::uint8_t  cut;
};

inline constexpr std::array<PresetRow, 3> kPresets = { {
    { "strict",  kStableFamilies, 2 },
    { "default", kAllFamilies,    2 },
    { "lenient", kAllFamilies,    1 },
} };

inline const PresetRow& presetRow( Preset p ) noexcept
{
    return kPresets[ static_cast<std::size_t>( p ) ];
}

// The value parse for --quality-panel=VALUE. Returns false on an unknown name so the caller can REFUSE rather
// than fall back to a preset the reader did not ask for — a silently substituted selection is a silently
// different report.
inline bool parsePreset( std::string_view value, Preset& out ) noexcept
{
    for( std::size_t index = 0; index < kPresets.size(); ++index )
    {
        if( value == kPresets[index].name )
        {
            out = static_cast<Preset>( index );
            return true;
        }
    }
    return false;
}

struct PanelRow
{
    NodeId       id         = kNoNode;
    std::uint8_t firedMask  = 0;      // every family that fired, enabled or not
    std::uint8_t countedMask = 0;     // firedMask & the preset's enabled set — what fam= counts
    std::uint8_t firedCount = 0;      // popcount( countedMask )
    std::string  why[kPanelFamilyCount];

    // The ONE annotation: deep AND untested. NOT a family and not part of any count — see the block comment
    // above kJoinDeepUntested. It is set after the count and the cut have already been decided, so nothing
    // downstream of it can read it into fam=, and the sort comparator never sees it.
    bool         deepUntested = false;
};

struct PanelScan
{
    std::vector<PanelRow> rows;               // rows that MET the cut, ranked
    std::size_t  eligibleCount = 0;           // functions/methods with a body — the denominator
    std::size_t  belowCutCount = 0;           // fired at least one ENABLED family, but fewer than the cut
    std::size_t  noFamilyCount = 0;           // fired no enabled family at all
    std::uint8_t unavailMask   = 0;
    std::string  unavailWhy[kPanelFamilyCount];

    // ── the disclosure counters, one group per family that has a threshold or a precondition ──
    std::size_t   readabilityMeasured = 0;
    std::size_t   readabilityCut      = 0;
    std::size_t   churnRanked         = 0;
    std::size_t   churnCut            = 0;
    std::size_t   confusionFiles      = 0;
    std::size_t   confusionScope      = 0;
    std::size_t   lexicalScope        = 0;
    std::uint32_t unreadableFileCount = 0;
    std::vector<std::string> floorRules;

    std::size_t   colocRanked  = 0;           // eligible functions that resolve ANY outside-the-file definition
    std::size_t   colocCut     = 0;
    std::size_t   stateFiles   = 0;           // indexed files in a language the state lens analyses
    std::size_t   stateScope   = 0;           // eligible functions inside them — the lens' REACH
    std::size_t   stateCells   = 0;           // non-local mutable cells the lens found
    bool          stateFloor   = false;       // the lens saturated a budget, so the family is a FLOOR

    std::size_t   testedScope       = 0;      // symbols an indexed test reaches — the JOIN's honest denominator
    std::size_t   deepUntestedCount = 0;      // rows carrying the annotation, over the WHOLE row set (not the page)
};

namespace detail
{

// Mark one family unavailable — ensemble.h's shared first-writer-wins rule, bound to this verb's scan. The
// rule itself is NOT reimplemented here: two verbs disagreeing about which reason survives would be a fresh
// way to under-report a missing measurement inside the machinery that exists to report one.
inline void markUnavailable( PanelScan& scan, std::uint8_t family, const char* why )
{
    ensemble::markUnavailableIn( scan.unavailMask, scan.unavailWhy, family, why );
}

// tested_scope= — how many symbols an indexed test transitively reaches. computeQMetrics' own flag, summed;
// no second traversal, so the panel and --metrics/--seams/--exercises cannot disagree about what tested=
// means. It is the JOIN's denominator, and it is published for the same reason cranked= and lscope= are: a
// reader has to be able to tell "no deep function here is uncovered" from "no test was crawled here".
inline std::size_t testedScopeOf( const QMetrics& qm ) noexcept
{
    std::size_t reached = 0;
    for( const std::uint8_t flag : qm.tested )
    {
        reached += ( flag != 0 ) ? 1u : 0u;
    }
    return reached;
}

// THE ONE ANNOTATION: deep AND untested — the whole of it, in one predicate that nothing else in this file
// may consult. Two facts the report ALREADY holds: `deep=` is inside the structural family's own evidence
// string (lines inside the regions that reach bar_nest, model.h Symbol::deepLoc), and tested= is the
// transitive test-seed reach above. Their INTERSECTION is the pair worth pointing at — a body that SUSTAINS
// depth is where a reader most wants to refactor, and no test reaching it is what makes doing so dangerous.
//
// IT IS NOT A SEVENTH FAMILY, and the code is shaped so it cannot quietly become one. §9.1's rule is that
// corroboration counts only when the lenses fail DIFFERENTLY, and `deep` IS the structural family; counting
// this would be that family wearing a second hat, which is §3.10's Maintainability-Index failure with extra
// steps. So it is a bool on the row, set AFTER the cut, read by the emitter and by nothing else: firedMask,
// countedMask, firedCount and the sort comparator never see it.
//
// AND IT IS SUPPRESSED WHEN "UNTESTED" IS NOT A MEASUREMENT. On a corpus no indexed test reaches — a tree
// scanned without its tests, a language whose test files were not crawled — every deep symbol is nominally
// uncovered, and annotating all of them would report a fact about what was INDEXED as a property of each
// function. That is the historical family's empty-ranking defect in a new place, so it gets the same answer
// the legend already gives that one: at testedScope == 0 the annotation fires nowhere, and the zero is
// published so the silence can be read correctly.
inline bool deepAndUntested( const Symbol& s, const QMetrics& qm, std::size_t testedScope ) noexcept
{
    return testedScope != 0 && s.deepLoc > 0 && qm.tested[s.id] == 0;
}

// STAGE: the colocation RANK. --context-ratio already returns its rows MOST-OUTSIDE-READING-FIRST on integer
// keys, so position IS the rank; filtering to the join's eligible set preserves that order, and only the
// worst-decile prefix is recorded.
//
// A row with rtok_out = 0 resolves NOTHING outside its own file, so it has no outside reading to be worst at.
// Including those would let a corpus where nothing resolves manufacture a "worst decile" out of an all-zero
// column, ranked by nothing but symbol id. They are excluded from the ranking and coloc_ranked= discloses the
// denominator that remains — the same shape --ensemble's churn family uses for files with no in-window commit.
inline std::vector<std::uint32_t> rankColocation( const IngestResult& ing, const std::vector<char>& eligible, PanelScan& scan )
{
    const contextratio::Scan   lens = contextratio::computeContextRatio( ing );
    std::vector<std::uint32_t> rank( ing.symbols.size(), UINT32_MAX );

    std::vector<std::uint32_t> order;
    for( const contextratio::Row& row : lens.symbols )
    {
        if( row.unitId < eligible.size() && eligible[row.unitId] != 0 && row.rtokOut != 0 )
        {
            order.push_back( row.unitId );
        }
    }
    scan.colocRanked = order.size();
    scan.colocCut    = ensemble::ordinalCut( scan.colocRanked, contextratio::kSymbolRowCap );
    if( scan.colocRanked == 0 )
    {
        markUnavailable( scan, kFamColocation,
                         "the colocation family is the local-reasoning lens, and not one eligible function here resolves a single definition outside its own file - the ranking is EMPTY, so the family ranked NOTHING and its silence is not a fact about this code" );
        return rank;
    }
    for( std::size_t rankIndex = 0; rankIndex < scan.colocCut && rankIndex < order.size(); ++rankIndex )
    {
        rank[ order[rankIndex] ] = std::uint32_t( rankIndex );
    }
    return rank;
}

// STAGE: the state family. The predicate is the OWN-BODY half of --nonlocal-state (direct_reads/direct_writes),
// never the callee-closure half — see the header note. `why` is written per symbol; an empty string means the
// family did not fire, which is the same "the evidence IS the fire decision" rule ensemble uses, so a row can
// never claim a family its own <e> children do not account for.
inline void collectState( const IngestResult& ing, const Graph& g, const std::vector<char>& eligible,
                          PanelScan& scan, std::vector<std::string>& why )
{
    // The LANGUAGE-COVERAGE precondition, computed the way ensemble computes the confusion family's: over the
    // join's own denominator, by CALLING the lens' own predicate rather than restating its language list.
    for( const std::string& path : ing.files )
    {
        if( nonlocal::isAnalyzedLang( langOfPath( path ) ) )
        {
            ++scan.stateFiles;
        }
    }
    for( const Symbol& s : ing.symbols )
    {
        if( eligible[s.id] != 0 && nonlocal::isAnalyzedLang( s.lang ) )
        {
            ++scan.stateScope;
        }
    }
    if( scan.stateScope == 0 )
    {
        markUnavailable( scan, kFamState, scan.stateFiles == 0
            ? "the state family is the non-local-mutable-state lens, which analyses C++/ObjC/ObjC++ only, and this corpus indexed NO such file - the family was NOT measured here, which is not the same as measured and silent"
            : "the state family is the non-local-mutable-state lens, which analyses C++/ObjC/ObjC++ only, and although this corpus indexed such files not one eligible function lives in them - the lens could not reach a single row of this report, so its silence is not a fact about this code" );
    }

    // The lens still RUNS when the family is unavailable: short-circuiting it would make the verdict and the
    // evidence two different measurements, which is exactly the shape ensemble refuses for its own packs.
    const nonlocal::Scan lens = nonlocal::computeNonLocalState( ing, g );
    scan.stateCells = lens.cells.size();
    scan.stateFloor = lens.cellsCapped || lens.declsCapped;
    for( const nonlocal::Row& row : lens.rows )
    {
        if( row.directReadCount == 0 && row.directWriteCount == 0 )
        {
            continue;
        }
        if( row.fn >= eligible.size() || eligible[row.fn] == 0 )
        {
            continue;
        }
        std::string& out = why[row.fn];
        if( row.directWriteCount != 0 )
        {
            ensemble::detail::appendMeasurement( out, "writes", row.directWriteCount );
        }
        if( row.directReadCount != 0 )
        {
            ensemble::detail::appendMeasurement( out, "reads", row.directReadCount );
        }
    }
}

// The per-family reasons, over this verb's SIX-family table — ensemble.h's shared renderer, handed this
// verb's count and name lookup. Sharing it is the point: a reader comparing an ensemble report with a panel
// report must be reading the same sentence structure, not two that happen to look alike today.
inline std::string unavailWhyList( const PanelScan& scan )
{
    return ensemble::unavailWhyListOf( scan.unavailWhy, kPanelFamilyCount, familyName );
}

}   // namespace detail

// The comma-joined names of the families in `bits` — the value of enabled= / fired= / uncounted= /
// unavailable= / unavail=.
inline std::string familyList( std::uint8_t bits )
{
    return ensemble::familyListOf( bits, kPanelFamilyCount, familyName );
}

// THE PANEL. `churnPerFile` is the caller's own git mining (null when git could not be mined at all, which
// makes the historical family unavailable rather than silent — ensemble's contract, inherited unchanged).
inline PanelScan computePanel( const IngestResult& ing, const Graph& g,
                               const std::vector<std::uint32_t>* churnPerFile, Preset preset )
{
    using namespace detail;
    PanelScan scan;
    const PresetRow& sel = presetRow( preset );

    // ── the four calibrated families, from --ensemble's OWN entry point. Not re-derived, not re-thresholded:
    //    one implementation, so the two verbs cannot disagree about what `structural` means. ───────────────
    const ensemble::EnsembleScan four = ensemble::computeEnsemble( ing, churnPerFile );
    scan.eligibleCount       = four.eligibleCount;
    scan.unavailMask         = four.unavailMask;
    scan.readabilityMeasured = four.readabilityMeasured;
    scan.readabilityCut      = four.readabilityCut;
    scan.churnRanked         = four.churnRanked;
    scan.churnCut            = four.churnCut;
    scan.confusionFiles      = four.confusionFiles;
    scan.confusionScope      = four.confusionScope;
    scan.lexicalScope        = four.lexicalScope;
    scan.unreadableFileCount = four.unreadableFileCount;
    scan.floorRules          = four.floorRules;
    for( std::uint8_t family = 0; family < ensemble::kFamilyCount; ++family )
    {
        scan.unavailWhy[family] = four.unavailWhy[family];
    }

    // The eligible set, from ensemble's OWN predicate — one definition of "a function with a body", shared.
    const std::size_t symbolCount = ing.symbols.size();
    std::vector<char> eligible( symbolCount, 0 );
    for( const Symbol& s : ing.symbols )
    {
        if( ensemble::detail::eligibleForJoin( s ) )
        {
            eligible[s.id] = 1;
        }
    }

    // ── the two new families ─────────────────────────────────────────────────────────────────────────────
    const std::vector<std::uint32_t> colocRank = rankColocation( ing, eligible, scan );
    std::vector<std::string>         stateWhy( symbolCount );
    collectState( ing, g, eligible, scan, stateWhy );

    // An empty eligible set means NO family measured anything, including the two new ones. ensemble already
    // marked its own four; the same fact has to reach the two it does not know about.
    if( scan.eligibleCount == 0 )
    {
        markUnavailable( scan, kFamColocation, "not one function or method with a body was indexed here, so this family had no eligible symbol to measure - the report's silence is not a fact about any code" );
        markUnavailable( scan, kFamState,      "not one function or method with a body was indexed here, so this family had no eligible symbol to measure - the report's silence is not a fact about any code" );
    }

    // THE ONE ANNOTATION's inputs — see detail::deepAndUntested for what it is, and what it is deliberately not.
    const QMetrics qm = computeQMetrics( ing, g );
    scan.testedScope  = testedScopeOf( qm );

    // ── the join. The four calibrated families' evidence is COPIED from their own rows (ensemble emits a row
    //    only where at least one of its four fired), then the two new families are OR-ed in. ──────────────
    std::vector<std::uint32_t> ensembleRowOf( symbolCount, UINT32_MAX );
    for( std::size_t rowIndex = 0; rowIndex < four.rows.size(); ++rowIndex )
    {
        ensembleRowOf[ four.rows[rowIndex].id ] = std::uint32_t( rowIndex );
    }

    for( const Symbol& s : ing.symbols )
    {
        if( eligible[s.id] == 0 )
        {
            continue;
        }
        PanelRow row;
        row.id = s.id;
        if( const std::uint32_t at = ensembleRowOf[s.id]; at != UINT32_MAX )
        {
            row.firedMask = four.rows[at].firedMask;
            for( std::uint8_t family = 0; family < ensemble::kFamilyCount; ++family )
            {
                row.why[family] = four.rows[at].why[family];
            }
        }
        if( colocRank[s.id] != UINT32_MAX )
        {
            row.firedMask |= std::uint8_t( 1u << kFamColocation );
            ensemble::detail::appendMeasurement( row.why[kFamColocation], "crank", colocRank[s.id] );
        }
        if( !stateWhy[s.id].empty() )
        {
            row.firedMask |= std::uint8_t( 1u << kFamState );
            row.why[kFamState] = std::move( stateWhy[s.id] );
        }

        row.countedMask = std::uint8_t( row.firedMask & sel.enabled );
        row.firedCount  = std::uint8_t( std::popcount( row.countedMask ) );
        if( row.firedCount == 0 )
        {
            ++scan.noFamilyCount;
            continue;
        }
        if( row.firedCount < sel.cut )
        {
            ++scan.belowCutCount;
            continue;
        }
        // AFTER the cut, deliberately: an annotated row was selected by its families alone (see deepAndUntested).
        row.deepUntested          = deepAndUntested( s, qm, scan.testedScope );
        scan.deepUntestedCount   += row.deepUntested ? 1u : 0u;
        scan.rows.push_back( std::move( row ) );
    }

    // Counted family count DESC, then NodeId ASC. There is deliberately no second criterion — any "which
    // 3-family row is worse" tiebreak would be the weighted composite this verb refuses to compute.
    std::sort( scan.rows.begin(), scan.rows.end(), []( const PanelRow& a, const PanelRow& b ) noexcept
               {
                   if( a.firedCount != b.firedCount ) { return a.firedCount > b.firedCount; }
                   return a.id < b.id;
               } );
    return scan;
}

// The legend the reader meets FIRST. Every attribute this verb emits is DEFINED here in the house `name=` form
// (test/legendcoveragecheck.sh derives that mechanically). No `--` digraph anywhere in it: that is illegal
// inside an XML comment, which is why flags are named bare (src/graphlegend.h).
//
// M4 (density audit 2026-08-08): this used to be a ~7.3 KB prose ESSAY that exceeded the panel's own payload
// on this very repo (35% of every emission was fixed text). The legend is now TERSE by contract: every
// attribute still defined in name= form, every HONESTY disclosure kept (floors, caps, unavailability, the
// per-file historical unit, the join's denominators — those are contract, not prose), and ONE pointer to the
// explanatory essay's single home (docs/COMMANDS.md quality-panel section, generated from the flag's own
// grown help block). test/panellegendcheck.sh holds the 4096 B budget AND legend<=payload on the repo panel;
// test/qualitypanelcheck.sh (N2/O) pins the honesty phrases that must survive any future trim.
inline constexpr const char* kPanelLegend =
    "<!-- ripwire quality-panel: THE SINGLE COMMAND, the whole panel of software-quality checks in ONE report, "
    "ranked ONLY by the COUNT OF DISTINCT EVIDENCE FAMILIES that fire; NO composite score, by contract. "
    "Rationale + worked reading: docs/COMMANDS.md quality-panel; every threshold is reused from its source "
    "lens. "
    "SIX FAMILIES, partitioned by KIND of evidence: structural (shape: complexity, size, nesting, params, "
    "readability rank) lexical (identifier text: naming rules) confusion (syntax: the atom rules) "
    "historical (git change frequency, measured PER FILE: every symbol carries its file's churn= and hrank= "
    "verbatim, file evidence inherited by the row, not the row's own history) "
    "colocation (how much you must READ outside this file) state (this function's OWN BODY touching "
    "non-local MUTABLE state). "
    "preset=the preset that produced this enabled=the families it COUNTS enabled_n=how many cut=distinct "
    "enabled families that must agree for a row families=how many exist. Presets SELECT and CUT, never "
    "weight: strict=the five families measured stable enough to stand behind a gate, cut 2 (historical is "
    "deliberately absent: a moving 12-month window re-shuffles on unchanged code) default=all six, cut 2 "
    "lenient=all six, cut 1. "
    "eligible=functions/methods with a body, the denominator ranked=rows that met the cut below_cut=fired "
    "at least one enabled family but fewer than the cut no_family=no enabled family fired "
    "(ranked= + below_cut= + no_family= = eligible=, always). "
    "s=one symbol: p=path:line n=name fam=distinct ENABLED families that fired of=enabled families "
    "EVALUABLE for it fired=their names uncounted=fired but not enabled here unavail=not measurable here. "
    "e=evidence in one fired family: f=family counted=1 when this preset counts it why=the measurements "
    "that crossed (a rule that fired N times reads rule*N). "
    "Absolute bars: bar_ccx=cognitive complexity bar_loc=physical lines bar_nest=max nesting depth "
    "bar_params=param count; a row shows only the ones that crossed. Rankings fire for the worst decile of "
    "their OWN corpus (RELATIVE: 'worst in THIS corpus', never 'bad in absolute terms'): rrank=readability "
    "rank (0 least readable) rcut=decile width rmeasured=functions measured; hrank=file churn rank (0 most "
    "changed) churn=in-window commit count hcut=decile width hranked=files with any in-window commit "
    "window=the churn window; crank=local-reasoning rank (0 reads most from outside its file) ccut=decile "
    "width cranked=functions resolving any outside definition. state has no threshold (fires on a direct "
    "access site): writes= reads= distinct cells the own body writes/reads. "
    "HONESTY: unavailable=families not evaluated at all unavailable_why=one reason each; a family listed "
    "there was NOT measured, so its absence from fired= is not evidence of health. An empty ranking or "
    "language coverage counts as not measured (hranked=0 voids historical, cranked=0 colocation); published "
    "denominators: cfiles=files the atom rules read cscope=eligible symbols in them lscope=symbols the "
    "naming rules read sfiles=files the state lens reads sscope=symbols in them cells=non-local mutable "
    "cells found. "
    "of= is enabled_n= minus the unavailable (a row never counts a family it could not evaluate); "
    "cut_reachable=0 when the cut exceeds of=, a fact about the corpus, never a clean bill of health. "
    "unreadable_files=files readability could not read (rrank= a floor); findings_capped=1 when a rule "
    "spent its per-rule budget, floor_rules=naming them (those families are FLOORS); state_floor=1 when the "
    "state lens saturated its budget (a FLOOR too). "
    "join=deep+untested is an annotation, NOT a seventh family (changes nothing: not fam=, not of=, not the "
    "order): deep= structural evidence (a body that SUSTAINS depth at bar_nest) that no indexed test "
    "reaches. tested_scope=symbols an indexed test reaches, the join's honest denominator; at "
    "tested_scope=0 the annotation is emitted on NO row. deep_untested=rows carrying it across the WHOLE "
    "set (unchanged by limit=). "
    "shown=symbol rows printed capped=1 when rows were dropped; the one limit=N offset=M window also prints "
    "total= has_more= next_offset= -->";

// Emit the report. Returns the process exit code — always 0: this is a lens, not a gate.
inline int writePanelReport( const IngestResult& ing, const Graph& g, const std::vector<std::uint32_t>* churnPerFile,
                             const std::string& root, Preset preset, int pageLimit, int pageOffset )
{
    const PanelScan  scan  = computePanel( ing, g, churnPerFile, preset );
    const PresetRow& sel   = presetRow( preset );
    const std::size_t total = scan.rows.size();
    const PageWindow  page  = pageWindow( total, effectiveRowCap( pageLimit, int( kPanelRowCap ) ), pageOffset );
    const std::size_t shown = page.end > page.begin ? page.end - page.begin : 0;

    char paging[kPageDisclosureCap];
    pagingDisclosure( paging, sizeof paging, total, page.end, pageLimit, pageOffset );

    std::string floorRules;
    for( const std::string& rule : scan.floorRules )
    {
        if( !floorRules.empty() )
        {
            floorRules += ',';
        }
        floorRules += rule;
    }

    // enabled MINUS unavailable: the honest denominator for fam= under this preset.
    const std::uint8_t evaluableMask = std::uint8_t( sel.enabled & ~scan.unavailMask );
    const unsigned     evaluable     = unsigned( std::popcount( evaluableMask ) );

    std::vector<char> escUnavail;
    std::vector<char> escFloor;

    std::fputs( kPanelLegend, stdout );
    std::fputs( rw::kAtStampLegend, stdout );
    std::printf( "<quality_panel preset=\"%s\" families=\"%u\" enabled=\"%s\" enabled_n=\"%u\" cut=\"%u\" cut_reachable=\"%s\"",
                 sel.name, unsigned( kPanelFamilyCount ), familyList( sel.enabled ).c_str(),
                 unsigned( std::popcount( sel.enabled ) ), unsigned( sel.cut ),
                 unsigned( sel.cut ) <= evaluable ? "1" : "0" );
    std::printf( " eligible=\"%zu\" ranked=\"%zu\" below_cut=\"%zu\" no_family=\"%zu\" unavailable=\"%s\" unavailable_why=\"%s\"",
                 scan.eligibleCount, total, scan.belowCutCount, scan.noFamilyCount,
                 familyList( scan.unavailMask ).c_str(),
                 std::string( escapeXml( detail::unavailWhyList( scan ), escUnavail ) ).c_str() );
    std::printf( " bar_ccx=\"%u\" bar_loc=\"%u\" bar_nest=\"%u\" bar_params=\"%u\"",
                 quality::kCcxBar, quality::kLocBar, quality::kNestBar, quality::kParamBar );
    std::printf( " rcut=\"%zu\" rmeasured=\"%zu\" hcut=\"%zu\" hranked=\"%zu\" window=\"%s\" ccut=\"%zu\" cranked=\"%zu\"",
                 scan.readabilityCut, scan.readabilityMeasured, scan.churnCut, scan.churnRanked,
                 ensemble::kEnsembleWindowLabel, scan.colocCut, scan.colocRanked );
    // The LANGUAGE-COVERAGE denominators — what each availability verdict was computed FROM, so a reader can
    std::printf( " cfiles=\"%zu\" cscope=\"%zu\" lscope=\"%zu\" sfiles=\"%zu\" sscope=\"%zu\" cells=\"%zu\"",
                 scan.confusionFiles, scan.confusionScope, scan.lexicalScope,   // check each verdict instead of
                 scan.stateFiles, scan.stateScope, scan.stateCells );           // taking it on trust.
    // The join's own two numbers, on the root for the same reason every other denominator is: tested_scope=0
    // is what a reader needs to know before reading a missing annotation as a clean bill of coverage.
    std::printf( " tested_scope=\"%zu\" deep_untested=\"%zu\"", scan.testedScope, scan.deepUntestedCount );
    if( scan.unreadableFileCount != 0 )
    {
        std::printf( " unreadable_files=\"%u\"", scan.unreadableFileCount );
    }
    if( scan.stateFloor )
    {
        std::printf( " state_floor=\"1\"" );
    }
    if( !floorRules.empty() )
    {
        std::printf( " findings_capped=\"1\" floor_rules=\"%s\"", std::string( escapeXml( std::string_view( floorRules ), escFloor ) ).c_str() );
    }
    std::printf( " shown=\"%zu\" capped=\"%s\"%s%s>", shown, shown < total ? "1" : "0", paging, gitstamp::atAttr( root ).c_str() );

    // TWO scratch buffers, not one reused twice in the same call: escapeXml returns a VIEW into its `out`, so a
    // second call with the same buffer invalidates the first view (readability.h carries the same note).
    std::vector<char> escPath;
    std::vector<char> escName;
    const std::string unavailNames = familyList( scan.unavailMask );
    for( std::size_t rowIndex = page.begin; rowIndex < page.end; ++rowIndex )
    {
        const PanelRow&   row = scan.rows[rowIndex];
        const Symbol&     s   = ing.symbols[row.id];
        const std::string path( escapeXml( ing.files[s.fileId], escPath ) );
        const std::string name( escapeXml( s.name, escName ) );
        // The annotation rides LAST on the row and is omitted when it does not hold — "absent = did not
        // hold", the same posture as every other optional attribute in this tool, never join="" or join="0".
        std::printf( "<s p=\"%s:%u\" n=\"%s\" fam=\"%u\" of=\"%u\" fired=\"%s\" uncounted=\"%s\" unavail=\"%s\"%s>",
                     path.c_str(), s.line, name.c_str(), unsigned( row.firedCount ), evaluable,
                     familyList( row.countedMask ).c_str(),
                     familyList( std::uint8_t( row.firedMask & ~row.countedMask ) ).c_str(),
                     unavailNames.c_str(),
                     row.deepUntested ? " join=\"deep+untested\"" : "" );
        for( std::uint8_t family = 0; family < kPanelFamilyCount; ++family )
        {
            if( ( ( row.firedMask >> family ) & 1u ) == 0 )
            {
                continue;
            }
            std::vector<char> escWhy;
            std::printf( "<e f=\"%s\" counted=\"%s\" why=\"%s\"/>", familyName( family ),
                         ( ( row.countedMask >> family ) & 1u ) != 0 ? "1" : "0",
                         std::string( escapeXml( row.why[family], escWhy ) ).c_str() );
        }
        std::printf( "</s>" );
    }
    std::printf( "</quality_panel>" );
    return 0;
}

}   // namespace qpanel
}   // namespace rw
