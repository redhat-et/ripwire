#pragma once

// ensemble.h — `--ensemble`: the FAMILY JOIN. Wave 1 shipped four readability-adjacent evidence families and
// nothing that combines them; four lenses run separately are four opinions, not an ensemble. This verb is the
// join: per function, WHICH families fire, HOW MANY DISTINCT families that is, and the specific evidence inside
// each one — ranked by the count of distinct families and by nothing else.
//
// THE FOUR FAMILIES (the readability-metrics design note, §9.1 — not a tracked file, so it is cited by section
// rather than by name; test/ripwirepubliccheck.sh arm 8 refuses a path that does not exist in the repo).
// Corroboration is only worth something when the lenses
// fail DIFFERENTLY, so the partition is by KIND OF EVIDENCE, not by metric:
//   structural  — the shape of the code: cognitive complexity, physical size, nesting depth, parameter count
//                 (the four bars quality.h already uses) plus the --readability lens' Posnett rank.
//   lexical     — the identifier TEXT: the naming-* rules (src/naminglens.h).
//   confusion   — the syntactic CONSTRUCT: the atom-* rules (src/atoms.h, Gopstein et al. ESEC/FSE 2017).
//   historical  — git: how often the FILE changes (the --hotspots churn axis, same 12-month window). Its unit
//                 is the file and not the symbol, so every symbol in a file carries that file's churn/hrank
//                 verbatim and a symbol in a churny file collects this family without any property of its
//                 own. That is the family's real unit rather than a defect, but a reader has to be told: the
//                 legend says PER FILE where it introduces the family, and test/qualitypanelcheck.sh (N)
//                 pins the measurement first and the sentence second.
//
// WHY THE FIVE STRUCTURAL SIGNALS ARE ONE FAMILY AND NOT FIVE. ccx, loc, nest, params and the Posnett score all
// track SIZE — Posnett's own fit is literally linear in L. Counting them as five agreeing witnesses is the
// Maintainability-Index failure (§3.10): re-weighting one signal and calling it five. They corroborate nothing
// about each other; they are one family that fires when any of its members does, and the row shows which.
//
// WHY THE HISTORICAL FAMILY USES CHURN ALONE AND NOT THE --hotspots SCORE. --hotspots ranks by churn × Σccx.
// Half of that product is the structural family, so a hotspot-rank-based historical family would agree with the
// structural one BY CONSTRUCTION — two families that cannot disagree are one family counted twice, which is the
// exact defect §9.1 forbids. The join therefore ranks files by churn alone; the complexity half is already in
// the structural family where it belongs.
//
// NEVER A WEIGHTED SCORE. There is no composite number anywhere in this verb, by contract. Averaging correlated
// metrics re-weights one signal and calls it three (§3.10), and a single quotable number becomes wrong the
// moment someone quotes it. The rank is ORDINAL — a count of distinct families — and every row carries the
// evidence that produced it, so a reader can see WHY without a second command. fam="3" is "three independent
// kinds of evidence agree here", which is a statement that survives being quoted.
//
// TWO KINDS OF THRESHOLD, AND THE DIFFERENCE IS DISCLOSED. Four of the structural signals are ABSOLUTE bars
// reused verbatim from src/quality.h (kCcxBar 15, kLocBar 60, kNestBar 4, kParamBar 5) — no new magic numbers.
// The other two signals (Posnett readability, churn) are RANKINGS whose own authors publish no defensible
// absolute cut: --readability's header says in so many words to read the ORDER, not the number. The only honest
// predicate on an ordinal signal is an ordinal cut, so each fires for the WORST DECILE of its own ranking,
// bounded above by that verb's own default display window (40 rows) and below by one row. That means some
// symbol is ALWAYS in the worst decile of its own corpus — which is what "ordinal" means, and the legend says
// so where the reader meets it rather than letting a relative cut read as an absolute verdict.
//
// UNAVAILABLE IS NOT SILENT. A family that could not be MEASURED is reported as unavailable on the root and on
// every row, and of= drops so the count has an honest denominator. A missing measurement must never read as a
// clean bill of health; that distinction is the point of the verb. THREE ways a family fails to be measured,
// and all three are unavailable rather than silent:
//   (1) an EMPTY RANKING — the two cases enumerated at the historical family below, the second of which this
//       verb got wrong on its first run;
//   (2) an empty LANGUAGE COVERAGE — the two rule-pack families have a language gate of their own, so on a
//       corpus with no eligible function they can read they were never applicable rather than quiet. This is
//       the defect the wave-2 calibration found (docs/EVALS.md §9.6): the confusion family is the atom pack,
//       C/C++/ObjC/CUDA by design, and it reported itself measured on a pure-Rust tree. See scopeByLanguage;
//   (3) an empty ELIGIBLE SET — nothing with a body was indexed, so no family measured anything at all.
// Every one of them is decided PER CORPUS from what was actually indexed. None is hardcoded, because the
// question "could this family have fired here" is a fact about the corpus, never about the build.
//
// ONE REASON PER FAMILY. Two families can be unavailable at once — a Rust tree outside a repository is both —
// so unavailable_why= carries a `family: reason` segment for each, in family order. A single reason slot keeps
// whichever wrote last, which would be a fresh way to under-report a missing measurement inside the very
// machinery that exists to report one.
//
// SCOPE: this verb JOINS. It computes no new metric and adds no new rule — every number in it is produced by
// machinery that already shipped, called through its existing entry point.
//
// DETERMINISM. Everything sorts before it is emitted: the finding stream by (symbol, family, rule tag), the
// symbol rows by (family count desc, NodeId asc — NodeId is already assigned in file/line/name order), the file
// rollup by (best per-symbol count desc, union count desc, path asc). No float is summed, compared or printed
// anywhere in this file: the two float-valued lenses enter as RANKS, which is the whole point.

#include "model.h"
#include "readability.h"     // computeReadability — the Posnett lens, called through its own entry point
#include "naminglens.h"      // appendNamingFindings — the naming-* rules
#include "atoms.h"           // atomsOfConfusion — the atom-* rules
#include "lintrules.h"       // kLintMaxPerRule — the SAME per-rule budget --lint gives both packs
#include "quality.h"         // kCcxBar / kLocBar / kNestBar / kParamBar — the repo's existing structural bars
#include "pageview.h"        // pageWindow + pagingDisclosure — THE TRUNCATION VOCABULARY
#include "graphlegend.h"     // kGraphCountFloorAttrXml — H8: the floor a fired findings_capped= carries
#include "gitstamp.h"        // atAttr — the historical family is git-mined, so the row set is stamped like --hotspots
#include "serialize.h"       // escapeXml

#include <algorithm>
#include <array>
#include <bit>          // std::popcount — familyCountOf
#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
namespace ensemble
{

// Display caps, in the same shape as --hotspots' 40: raisable with --limit, paged with --offset. The symbol
// listing is the PRIMARY one (pageview.h rule 6); the file rollup discloses through its own noun-prefixed pair.
inline constexpr std::size_t kEnsembleSymbolRowCap = 40;
inline constexpr std::size_t kEnsembleFileRowCap   = 20;

// The ordinal-signal window: --readability and --hotspots both default to showing 40 rows, so a symbol or file
// inside that window is exactly "what the existing verb would have put on your screen".
inline constexpr std::size_t kOrdinalWindowCap = 40;

// THE churn window, in both spellings, defined ONCE: what the caller asks gitChurnCounts for, and what the
// root element discloses. Two constants in one place rather than a string literal in main.cpp and a label
// argument threaded back down — the window is part of this verb's disclosed threshold set, so a spelling that
// can drift from the mining call is a lie waiting to happen. Deliberately fixed (--since is refused on this
// verb by the shared modifier guard): a moving window makes hrank= incomparable between runs.
inline constexpr const char* kEnsembleChurnSince = "12 months ago";
inline constexpr const char* kEnsembleWindowLabel = "12mo";

enum : std::uint8_t
{
    kFamStructural = 0,
    kFamLexical    = 1,
    kFamConfusion  = 2,
    kFamHistorical = 3,
    kFamilyCount   = 4
};

inline constexpr std::array<const char*, kFamilyCount> kFamilyNames = { { "structural", "lexical", "confusion", "historical" } };

// ── THE FAMILY-VOCABULARY HELPERS, written ONCE over a (count, name lookup) pair ──────────────────────────
// Three operations are pure functions of "a bitmask over a family table": name the set bits, mark one family
// unavailable keeping the first reason, and render the per-family reasons. They live out here rather than
// inside this verb because a SECOND verb (src/qualitypanel.h) has a LONGER family table and needs exactly
// these three — and a second copy of them is how one report ends up naming a family the other stopped using.
// The name lookup is a function pointer rather than a std::array so a caller whose table is assembled from two
// pieces (the panel reads these four names from THIS table and appends its own) can still share the code.
using FamilyNameFn = const char* ( * )( std::uint8_t );

inline const char* ensembleFamilyName( std::uint8_t family ) noexcept
{
    return kFamilyNames[family];
}

// The comma-joined names of the families in `bits`, in family order — a total order over a fixed table, so
// the string is deterministic without a sort.
inline std::string familyListOf( std::uint8_t bits, std::uint8_t familyCount, FamilyNameFn nameOf )
{
    std::string out;
    for( std::uint8_t family = 0; family < familyCount; ++family )
    {
        if( ( ( bits >> family ) & 1u ) != 0 )
        {
            if( !out.empty() )
            {
                out += ',';
            }
            out += nameOf( family );
        }
    }
    return out;
}

// Mark one family unavailable, KEEPING THE FIRST reason. First-writer-wins is the rule because the specific
// reason is always written before the general one: a family's own precondition names which case fired before
// the eligible-set guard would overwrite it with "nothing was eligible". A family already unavailable stays
// unavailable — the mask is an OR, so the order of these calls cannot change the verdict, only which sentence
// explains it.
inline void markUnavailableIn( std::uint8_t& mask, std::string* why, std::uint8_t family, const char* reason )
{
    mask |= std::uint8_t( 1u << family );
    if( why[family].empty() )
    {
        why[family] = reason;
    }
}

// The per-family reasons as `family: reason` segments, in family order. Empty when every family was measured,
// which is exactly what an empty unavailable= means.
inline std::string unavailWhyListOf( const std::string* why, std::uint8_t familyCount, FamilyNameFn nameOf )
{
    std::string out;
    for( std::uint8_t family = 0; family < familyCount; ++family )
    {
        if( why[family].empty() )
        {
            continue;
        }
        if( !out.empty() )
        {
            out += " | ";
        }
        out += nameOf( family );
        out += ": ";
        out += why[family];
    }
    return out;
}

// The worst decile of a ranking, never wider than the ranking verb's own default window and never narrower
// than one row. Zero rows in, zero out — a cut over nothing must not manufacture a row.
inline std::size_t ordinalCut( std::size_t rankedCount, std::size_t windowCap ) noexcept
{
    if( rankedCount == 0 )
    {
        return 0;
    }
    const std::size_t decile = ( rankedCount + 9 ) / 10;    // ceil(n/10)
    return decile < windowCap ? decile : windowCap;
}

// One joined symbol. `why[f]` is the evidence INSIDE family f, empty when f did not fire.
struct EnsembleRow
{
    NodeId       id         = kNoNode;
    std::uint8_t firedMask  = 0;
    std::uint8_t firedCount = 0;
    std::string  why[kFamilyCount];
};

// One file's rollup. topCount is the STRONGER claim (corroboration on ONE symbol); unionMask is the weaker one
// (different families firing on different symbols) — kept apart on purpose, see the legend.
struct EnsembleFileRow
{
    std::uint32_t fileId    = 0;
    std::uint32_t symCount  = 0;      // symbols in this file with at least one family
    NodeId        topSym    = kNoNode;
    std::uint8_t  topCount  = 0;
    std::uint8_t  unionMask = 0;
};

struct EnsembleScan
{
    std::vector<EnsembleRow>     rows;
    std::vector<EnsembleFileRow> files;
    std::size_t   eligibleCount       = 0;    // functions/methods with a body — the denominator
    std::size_t   noFamilyCount       = 0;    // eligible symbols where NO family fired
    std::uint8_t  unavailMask         = 0;    // families that could not be evaluated at all
    // ONE reason PER FAMILY, not one reason per scan. Two families can be unavailable at the same time —
    // a Rust tree outside a repository is both — and a single slot silently keeps whichever wrote last,
    // which would be a NEW way for this verb to under-report a missing measurement in the exact place the
    // verb exists to report one. Indexed by kFam*; empty means "this family WAS measured".
    std::string   unavailWhy[kFamilyCount];
    std::size_t   confusionFiles      = 0;    // indexed files in a language the atom pack can read
    std::size_t   confusionScope      = 0;    // eligible symbols inside those files — the pack's REACH
    std::size_t   lexicalScope        = 0;    // eligible symbols in a language the naming pack can read
    std::size_t   readabilityMeasured = 0;
    std::size_t   readabilityCut      = 0;
    std::size_t   churnRanked         = 0;    // files with at least one in-window commit
    std::size_t   churnCut            = 0;
    std::uint32_t unreadableFileCount = 0;    // files the Posnett lens could not read → its rank is a FLOOR
    std::vector<std::string> floorRules;      // pack rules that spent their per-rule budget → lexical/confusion is a FLOOR
};

namespace detail
{

// Mark one family unavailable — the shared first-writer-wins rule above, bound to this verb's scan. Here
// the specific reason is always written before the general one: rankChurn names which of its two git cases
// fired before the eligible-set guard below would overwrite it with "nothing was eligible".
inline void markUnavailable( EnsembleScan& scan, std::uint8_t family, const char* why )
{
    markUnavailableIn( scan.unavailMask, scan.unavailWhy, family, why );
}

// A single rule firing, already bound to the function that contains it. The lint packs emit byte spans; the
// join needs symbols, and this is the only place the two are reconciled.
struct FamilyHit
{
    NodeId       id;
    std::uint8_t family;
    std::string  tag;
};

// The join's eligibility predicate, and it is deliberately the SAME one --readability uses: a function or
// method with a body. A declaration has no shape to measure and no construct to confuse, so counting its
// silent families as "did not fire" would be the very lie the unavailable/silent distinction exists to stop.
inline bool eligibleForJoin( const Symbol& s ) noexcept
{
    return ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && s.endByte > s.sigEndByte;
}

// Per-file lists of eligible symbols, sorted by sigStartByte — the index the span→symbol binding walks.
// model.h::symbolsByFile is the shared bucket-and-sort; only the filter and the key are ours. sigStartByte is
// unique per symbol within a file, so this comparator is already a total order.
inline SymbolsByFile eligibleByFile( const IngestResult& ing, const std::vector<char>& eligible )
{
    return symbolsByFile( ing,
                          [ & ]( const Symbol& s ) { return eligible[s.id] != 0; },
                          [ & ]( NodeId a, NodeId b ) { return ing.symbols[a].sigStartByte < ing.symbols[b].sigStartByte; } );
}

// The INNERMOST eligible function containing `offset`, or kNoNode. Walks the sorted list downward from the last
// definition that starts at or before the offset, so the first container found is the innermost one (a lambda
// inside a function binds to the lambda). A finding outside every function body — a file-scope variable's name,
// a macro — binds to nothing and is dropped, which the legend discloses.
inline NodeId enclosingEligible( const IngestResult& ing, const FileSymbols& sorted, std::uint32_t offset ) noexcept
{
    std::size_t index = sorted.size();
    while( index > 0 )
    {
        --index;
        const Symbol& s = ing.symbols[ sorted[index] ];
        if( s.sigStartByte > offset )
        {
            continue;
        }
        if( offset < s.endByte )
        {
            return s.id;
        }
    }
    return kNoNode;
}

// Bind one pack's findings to functions and push them into `hits` under `family`.
inline void bindFindings( const IngestResult& ing, const SymbolsByFile& byFile,
                          const std::vector<AstMatch>& findings, std::uint8_t family, std::vector<FamilyHit>& hits )
{
    for( const AstMatch& hit : findings )
    {
        if( hit.fileId >= byFile.size() )
        {
            continue;
        }
        const NodeId owner = enclosingEligible( ing, byFile[hit.fileId], hit.startByte );
        if( owner != kNoNode )
        {
            hits.push_back( { owner, family, hit.tag } );
        }
    }
}

// Append " item" / "item" to an evidence string — the one place the separator is decided.
inline void appendEvidence( std::string& why, std::string_view item )
{
    if( !why.empty() )
    {
        why += ' ';
    }
    why.append( item );
}

// Append a `name=value` measurement. Composed on std::string rather than through a fixed char buffer, so this
// file carries no format string to widen, no buffer size to re-derive, and nothing for test/fixedbufsweep.sh
// to classify — that gate's own advice, applied before it had to ask for it.
inline void appendMeasurement( std::string& why, std::string_view name, std::uint32_t value )
{
    if( !why.empty() )
    {
        why += ' ';
    }
    why.append( name );
    why += '=';
    why += std::to_string( value );
}

// One absolute structural bar and the symbol's value against it.
struct BarHit { const char* name; std::uint32_t value; std::uint32_t bar; };

// The four ABSOLUTE structural bars as ONE table, and the evidence string IS the fire decision: a non-empty
// return means the bars fired, and it lists exactly which ones and with what value. Deliberately not a
// predicate beside a separate string builder — that shape is two copies of `ccx >= kCcxBar`, and two copies is
// how a report ends up naming a bar the predicate stopped using.
inline std::string structuralBarEvidence( const Symbol& s )
{
    const BarHit bars[] = { { "ccx",    s.ccx,                      quality::kCcxBar    },
                            { "loc",    s.loc,                      quality::kLocBar    },
                            { "nest",   std::uint32_t( s.maxNest ), quality::kNestBar   },
                            { "params", std::uint32_t( s.params ),  quality::kParamBar  } };
    std::string why;
    for( const BarHit& hit : bars )
    {
        if( hit.value >= hit.bar )
        {
            appendMeasurement( why, hit.name, hit.value );
        }
    }
    // The nesting PROFILE, reported beside the max instead of gating on it (model.h Symbol::humps/deepLoc).
    // nest= is the deepest line and says nothing about how much of the body is that deep, so a long
    // BLOCKED-SEQUENTIAL function — a run of shallow scoped steps whose max is set by one inner loop — and a
    // TANGLED one that holds depth for hundreds of lines produce the identical evidence string. humps= (how
    // many regions reach the bar) and deep= (how many lines are inside them, against the loc= already above)
    // are what tells them apart, and a reader gets it without opening the file.
    //
    // This adds NO firing case: humps>0 is exactly maxNest>=kNestBar, which is precisely when the `nest` bar
    // in the table above already fired. The family count and the panel's ranking are therefore untouched, so
    // no recalibration round is owed for it — this is strictly more evidence for rows that already appear.
    if( s.humps > 0 )
    {
        appendMeasurement( why, "humps", std::uint32_t( s.humps ) );
        appendMeasurement( why, "deep",  std::uint32_t( s.deepLoc ) );
    }
    // Essential complexity, ANNOTATION-ONLY (the essential-complexity design note, §8). The humps line above
    // rides free because humps>0 IS the nest bar; ev does NOT have that property — a small function with
    // one break-under-an-if has ev>=2 and clears no bar — so an ungated append here would be a NEW firing
    // case, which changes the panel's row set and fam= counts and owes a pre-registered calibration round
    // (qualitypanel.h: "A NEW FAMILY EARNS ITS PLACE BEFORE IT IS ENABLED, NEVER AFTER"). Gating on the
    // family having ALREADY fired (why non-empty) makes this strictly-more-evidence on rows that already
    // appear; test/essentialcxcheck.sh arm 10 pins both halves (row set unchanged + this being the only
    // read of Symbol::ev outside the emitters). Promotion to a firing signal is a separate change with a frozen
    // PREREG under bench/ (§8.3), not an edit to this line.
    if( const std::uint32_t evValue = std::uint32_t( s.ev ); !why.empty() && evCountedLang( s.lang ) && evValue > 1u )
    {
        appendMeasurement( why, "ev", evValue );
    }
    return why;
}

// STAGE: the readability RANK — structural's ordinal half. computeReadability already returns its rows LEAST
// READABLE FIRST, so position IS the rank; only the worst-decile prefix is recorded, everything else stays
// UINT32_MAX (= did not enter the cut).
inline std::vector<std::uint32_t> rankReadability( const IngestResult& ing, EnsembleScan& scan )
{
    const ReadabilityScan readability = computeReadability( ing );
    scan.readabilityMeasured          = readability.rows.size();
    scan.readabilityCut               = ordinalCut( scan.readabilityMeasured, kOrdinalWindowCap );
    scan.unreadableFileCount          = readability.unreadableFileCount;

    std::vector<std::uint32_t> rank( ing.symbols.size(), UINT32_MAX );
    for( std::size_t rowIndex = 0; rowIndex < scan.readabilityCut && rowIndex < readability.rows.size(); ++rowIndex )
    {
        rank[ readability.rows[rowIndex].id ] = std::uint32_t( rowIndex );
    }
    return rank;
}

// STAGE: files ranked by CHURN ALONE (see the header note on why not by the --hotspots score).
// TWO ways this family fails to produce a ranking, and BOTH are unavailable rather than silent:
//   (1) the caller could not mine git at all (not a repo, git missing, no history);
//   (2) mining ran and bound ZERO indexed files to any in-window commit — a directory scanned from outside the
//       repository that tracks it, a path join that matched nothing, a window with no commits.
// Case (2) is the dangerous one, and it was found by running this verb on a non-git directory that happened to
// sit INSIDE another repository: mining "succeeded", every count was zero, and the row set said unavailable=""
// — i.e. "history was consulted and had nothing to say about any of this code". It had not been consulted
// about any of this code at all. An ordinal family whose ranking is EMPTY ranked nothing, so it fired for
// nobody for a reason that is not a fact about the code.
inline std::vector<std::uint32_t> rankChurn( const IngestResult& ing, const std::vector<std::uint32_t>* churnPerFile, EnsembleScan& scan )
{
    std::vector<std::uint32_t> rank( ing.files.size(), UINT32_MAX );
    if( churnPerFile == nullptr )
    {
        markUnavailable( scan, kFamHistorical, "git could not be mined here (not a repository, no git on PATH, or no history) - the historical family was NOT measured, which is not the same as measured and silent" );
        return rank;
    }

    std::vector<std::uint32_t> order;
    for( std::uint32_t fileIndex = 0; fileIndex < ing.files.size() && fileIndex < churnPerFile->size(); ++fileIndex )
    {
        if( ( *churnPerFile )[fileIndex] != 0 )
        {
            order.push_back( fileIndex );
        }
    }
    std::sort( order.begin(), order.end(), [ & ]( std::uint32_t a, std::uint32_t b ) noexcept
               {
                   const std::uint32_t ca = ( *churnPerFile )[a];
                   const std::uint32_t cb = ( *churnPerFile )[b];
                   return ca != cb ? ca > cb : ing.files[a] < ing.files[b];
               } );
    scan.churnRanked = order.size();
    scan.churnCut    = ordinalCut( scan.churnRanked, kOrdinalWindowCap );
    if( scan.churnRanked == 0 )
    {
        markUnavailable( scan, kFamHistorical, "git was mined but not one indexed file bound to an in-window commit (a corpus scanned from outside the repository that tracks it, a path join that matched nothing, or a window with no commits) - the historical family ranked NOTHING, so its silence is not a fact about this code" );
    }
    for( std::size_t rankIndex = 0; rankIndex < scan.churnCut && rankIndex < order.size(); ++rankIndex )
    {
        rank[ order[rankIndex] ] = std::uint32_t( rankIndex );
    }
    return rank;
}

// STAGE: the LANGUAGE-COVERAGE precondition — the same shape rankChurn already carries for git, applied to
// the two families that are RULE PACKS with a language gate of their own.
//
//   confusion  the atom pack runs ONLY on C/C++/ObjC/CUDA paths (atoms::isCFamilyPath). That is a decision
//              with evidence behind it, not an oversight: atom transfer to other languages is empirically
//              falsified, so the rules are deliberately not run elsewhere. On a pure Rust / Python / Swift /
//              TypeScript corpus the family therefore cannot fire AT ALL — not "found nothing", but "was
//              never applicable" — and reporting that as a silent non-firing makes a clean bill of health
//              out of a measurement that never happened. Found by the wave-2 calibration (docs/EVALS.md
//              §9.6 defect 1) on a 115-file Rust tree, where the verb said three families were evaluated
//              and two were quiet while one of the three had not been run on a single file.
//   lexical    the naming pack skips data and doc languages (naminglens::namingEvaluableLang). Audited for
//              the same defect and it is reachable in principle, so the precondition is computed the same
//              way rather than assumed away — the only honest form of "we checked".
//
// BOTH predicates are CALLED, never restated here. A second copy of an extension list is how a report ends
// up naming a gate the pack stopped using, which is the same class of defect one layer down.
//
// THE PRECONDITION IS OVER THE JOIN'S OWN DENOMINATOR (eligible functions), not over the crawl. A vendored
// header holding nothing but macros puts a C-family file in the corpus while leaving every eligible symbol
// out of the pack's reach; a family that could not have reached ONE ROW of this report did not measure this
// report, whatever it was handed. Both numbers are disclosed (cfiles= and cscope=) so the verdict is
// auditable from the output instead of on trust.
//
// The `structural` family is deliberately absent from this pass: its four absolute bars read ccx/loc/nest/
// params, which ingest computes for every language, and its ordinal half is the Posnett lens, which is not
// language-gated either. It has no coverage precondition to check — only the eligible-set one below, which
// it shares with all four.
// The three coverage counts, in one pass over the eligible set. Both predicates are the PACKS' OWN, called
// rather than restated (see the stage comment below).
inline void countCoverage( const IngestResult& ing, const std::vector<char>& eligible, EnsembleScan& scan )
{
    for( const std::string& path : ing.files )
    {
        if( atoms::isCFamilyPath( path ) )
        {
            ++scan.confusionFiles;
        }
    }
    for( const Symbol& s : ing.symbols )
    {
        if( eligible[s.id] == 0 )
        {
            continue;
        }
        if( s.fileId < ing.files.size() && atoms::isCFamilyPath( ing.files[s.fileId] ) )
        {
            ++scan.confusionScope;
        }
        if( naminglens::namingEvaluableLang( s.lang ) )
        {
            ++scan.lexicalScope;
        }
    }
}

inline void scopeByLanguage( const IngestResult& ing, const std::vector<char>& eligible, EnsembleScan& scan )
{
    // Nothing eligible ⇒ NO family measured anything, and an empty unavailable= would claim all four did.
    if( scan.eligibleCount == 0 )
    {
        for( std::uint8_t family = 0; family < kFamilyCount; ++family )
        {
            markUnavailable( scan, family, "not one function or method with a body was indexed here, so this family had no eligible symbol to measure - the report's silence is not a fact about any code" );
        }
        return;
    }

    countCoverage( ing, eligible, scan );

    if( scan.confusionScope == 0 )
    {
        markUnavailable( scan, kFamConfusion, scan.confusionFiles == 0
            ? "the confusion family is the atom pack, which by design runs only on C/C++/ObjC/CUDA paths (atom transfer to other languages is empirically falsified), and this corpus indexed NO such file - the family was NOT measured here, which is not the same as measured and silent"
            : "the confusion family is the atom pack, which by design runs only on C/C++/ObjC/CUDA paths, and although this corpus indexed such files not one eligible function lives in them - the atom rules could not reach a single row of this report, so their silence is not a fact about this code" );
    }
    if( scan.lexicalScope == 0 )
    {
        markUnavailable( scan, kFamLexical, "the lexical family is the naming pack, which has no opinion about identifiers in a data or doc language, and not one eligible function here is in a language it reads - the family was NOT measured, which is not the same as measured and silent" );
    }
}

// The per-family reasons, over this verb's own four-family table.
inline std::string unavailWhyList( const EnsembleScan& scan )
{
    return unavailWhyListOf( scan.unavailWhy, kFamilyCount, ensembleFamilyName );
}

// STAGE: the two lint packs, called through their existing entry points, bound to functions and sorted into
// the one total order the evidence strings are folded from.
inline std::vector<FamilyHit> collectLintHits( const IngestResult& ing, const SymbolsByFile& byFile, EnsembleScan& scan )
{
    std::vector<FamilyHit> hits;

    std::vector<AstMatch> namingFindings;
    for( std::string& saturated : naminglens::appendNamingFindings( ing, kLintMaxPerRule, namingFindings ) )
    {
        scan.floorRules.push_back( std::move( saturated ) );
    }
    bindFindings( ing, byFile, namingFindings, kFamLexical, hits );

    const atoms::AtomsRun pack = atoms::atomsOfConfusion( ing, kLintMaxPerRule );
    for( const std::string& saturated : pack.saturatedTags )
    {
        scan.floorRules.push_back( saturated );
    }
    bindFindings( ing, byFile, pack.findings, kFamConfusion, hits );

    std::sort( scan.floorRules.begin(), scan.floorRules.end() );
    scan.floorRules.erase( std::unique( scan.floorRules.begin(), scan.floorRules.end() ), scan.floorRules.end() );
    std::sort( hits.begin(), hits.end(), []( const FamilyHit& a, const FamilyHit& b ) noexcept
               {
                   if( a.id != b.id )         { return a.id < b.id; }
                   if( a.family != b.family ) { return a.family < b.family; }
                   return a.tag < b.tag;
               } );
    return hits;
}

// STAGE: the lexical/confusion evidence, run-length folded over the sorted hit stream so a rule that fired N
// times reads `rule*N` instead of N repetitions of its own name.
inline void appendHitEvidence( const std::vector<FamilyHit>& hits, const std::vector<std::uint32_t>& rowOf, EnsembleScan& scan )
{
    for( std::size_t hitIndex = 0; hitIndex < hits.size(); )
    {
        std::size_t runEnd = hitIndex + 1;
        while( runEnd < hits.size() && hits[runEnd].id == hits[hitIndex].id
               && hits[runEnd].family == hits[hitIndex].family && hits[runEnd].tag == hits[hitIndex].tag )
        {
            ++runEnd;
        }
        const std::uint32_t rowIndex = rowOf[ hits[hitIndex].id ];
        if( rowIndex != UINT32_MAX )
        {
            std::string item = hits[hitIndex].tag;
            if( runEnd - hitIndex > 1 )
            {
                item += '*';
                item += std::to_string( runEnd - hitIndex );
            }
            appendEvidence( scan.rows[rowIndex].why[ hits[hitIndex].family ], item );
        }
        hitIndex = runEnd;
    }
}

// How many families a mask names. Only the low kFamilyCount bits are ever set (every write goes through
// `1u << kFam*`), so a whole-byte popcount IS the family count — and std::popcount beats the hand-rolled
// accumulate loop this started as, which a --quality-delta pass correctly read as a clone of clones.h's
// sketch-match counter: two counting loops with nothing to share but their shape.
inline std::uint8_t familyCountOf( std::uint8_t bits ) noexcept
{
    return std::uint8_t( std::popcount( bits ) );
}

// STAGE: the per-file rollup, aggregated from the finished rows. topCount is the STRONGER claim (several
// families on ONE symbol), unionMask the weaker one — the ordering puts the strong claim first and the legend
// says why the two are not interchangeable.
inline void rollUpByFile( const IngestResult& ing, EnsembleScan& scan )
{
    std::vector<EnsembleFileRow> byFileRow( ing.files.size() );
    for( std::uint32_t fileIndex = 0; fileIndex < ing.files.size(); ++fileIndex )
    {
        byFileRow[fileIndex].fileId = fileIndex;
    }
    for( const EnsembleRow& row : scan.rows )
    {
        EnsembleFileRow& agg = byFileRow[ ing.symbols[row.id].fileId ];
        agg.unionMask       |= row.firedMask;
        ++agg.symCount;
        // Strictly greater, so ties keep the FIRST symbol in NodeId order (file/line/name) — deterministic.
        if( row.firedCount > agg.topCount )
        {
            agg.topCount = row.firedCount;
            agg.topSym   = row.id;
        }
    }
    for( const EnsembleFileRow& agg : byFileRow )
    {
        if( agg.symCount != 0 )
        {
            scan.files.push_back( agg );
        }
    }
    std::sort( scan.files.begin(), scan.files.end(), [ & ]( const EnsembleFileRow& a, const EnsembleFileRow& b ) noexcept
               {
                   if( a.topCount != b.topCount ) { return a.topCount > b.topCount; }
                   const std::uint8_t ua = familyCountOf( a.unionMask ), ub = familyCountOf( b.unionMask );
                   if( ua != ub )                 { return ua > ub; }
                   return ing.files[a.fileId] < ing.files[b.fileId];
               } );
}

}   // namespace detail

// THE JOIN. `churnPerFile` is the per-file in-window commit count from the caller's own git mining (the same
// gitChurnCounts --hotspots uses); a null pointer means git could not be mined at all, which makes the
// historical family UNAVAILABLE rather than silent.
inline EnsembleScan computeEnsemble( const IngestResult& ing, const std::vector<std::uint32_t>* churnPerFile )
{
    using namespace detail;
    EnsembleScan scan;

    const std::size_t symbolCount = ing.symbols.size();
    std::vector<char> eligible( symbolCount, 0 );
    for( const Symbol& s : ing.symbols )
    {
        if( eligibleForJoin( s ) )
        {
            eligible[s.id] = 1;
            ++scan.eligibleCount;
        }
    }

    // ── the two ordinal signals, each ranked by its own existing lens ────────────────────────────────────────
    const std::vector<std::uint32_t> posnettRank = rankReadability( ing, scan );      // structural's ordinal half
    const std::vector<std::uint32_t> churnRank   = rankChurn( ing, churnPerFile, scan );

    // ── availability, decided PER CORPUS from what was indexed. After rankChurn, so the historical family's
    //    own reason is already in place; the packs below still run unconditionally, because short-circuiting
    //    an unavailable family would make the verdict and the evidence two different measurements. ─────────
    scopeByLanguage( ing, eligible, scan );

    // ── the two categorical signals: the lint packs, bound to the functions that contain their findings ─────
    const SymbolsByFile                    byFile = eligibleByFile( ing, eligible );
    const std::vector<FamilyHit>           hits   = collectLintHits( ing, byFile, scan );

    // ── ONE pass builds the rows: the evidence string per family IS the fire decision for that family, so a
    //    row can never claim a count its own <e> children do not account for. Built in NodeId order, which is
    //    both the tie-break order and what keeps `rowOf` valid while the hit evidence is appended below.
    std::vector<std::uint8_t> mask( symbolCount, 0 );
    for( const FamilyHit& hit : hits )
    {
        mask[hit.id] |= std::uint8_t( 1u << hit.family );
    }

    std::vector<std::uint32_t> rowOf( symbolCount, UINT32_MAX );
    for( const Symbol& s : ing.symbols )
    {
        if( eligible[s.id] == 0 )
        {
            continue;
        }
        // The bars themselves are on the root element, once, instead of repeated on every row.
        std::string structuralWhy = structuralBarEvidence( s );
        if( posnettRank[s.id] != UINT32_MAX )
        {
            appendMeasurement( structuralWhy, "rrank", posnettRank[s.id] );
        }
        std::string historicalWhy;
        if( s.fileId < churnRank.size() && churnRank[s.fileId] != UINT32_MAX )
        {
            appendMeasurement( historicalWhy, "hrank", churnRank[s.fileId] );
            appendMeasurement( historicalWhy, "churn", ( *churnPerFile )[s.fileId] );
        }

        std::uint8_t fired = mask[s.id];
        fired |= structuralWhy.empty() ? 0u : std::uint8_t( 1u << kFamStructural );
        fired |= historicalWhy.empty() ? 0u : std::uint8_t( 1u << kFamHistorical );
        if( fired == 0 )
        {
            ++scan.noFamilyCount;
            continue;
        }

        EnsembleRow row;
        row.id                     = s.id;
        row.firedMask              = fired;
        row.firedCount             = familyCountOf( fired );
        row.why[kFamStructural]    = std::move( structuralWhy );
        row.why[kFamHistorical]    = std::move( historicalWhy );
        rowOf[s.id]                = std::uint32_t( scan.rows.size() );
        scan.rows.push_back( std::move( row ) );
    }
    appendHitEvidence( hits, rowOf, scan );

    // ── the two orderings, both total ───────────────────────────────────────────────────────────────────────
    // Symbols: family count DESC, then NodeId ASC. There is deliberately no second ranking criterion — any
    // "which 3-family row is worse" tiebreak would be the weighted composite this verb refuses to compute.
    std::sort( scan.rows.begin(), scan.rows.end(), []( const EnsembleRow& a, const EnsembleRow& b ) noexcept
               {
                   if( a.firedCount != b.firedCount ) { return a.firedCount > b.firedCount; }
                   return a.id < b.id;
               } );
    rollUpByFile( ing, scan );      // the file rollup reads the finished rows, and sorts itself
    return scan;
}

// The comma-joined names of the families in `bits` — the value of fired= / unavail= / union=.
inline std::string familyList( std::uint8_t bits )
{
    return familyListOf( bits, kFamilyCount, ensembleFamilyName );
}

// The legend the reader meets FIRST. Every attribute this verb emits is DEFINED here in the house `name=` form
// (test/legendcoveragecheck.sh derives that mechanically). No `--` digraph anywhere in it: that is illegal
// inside an XML comment, which is why flags are named bare (src/graphlegend.h).
inline constexpr const char* kEnsembleLegend =
    "<!-- ripwire ensemble: the FAMILY JOIN over four orthogonal evidence families, ranked by the COUNT OF "
    "DISTINCT FAMILIES that fire and by nothing else. There is NO composite score here, by contract: averaging "
    "correlated metrics re-weights one signal and calls it three, and a single quotable number is wrong the "
    "moment it is quoted. fam= is ordinal and every row carries its own evidence. "
    "The four families are structural (the shape of the code), lexical (the identifier text: the naming rules), "
    "confusion (the syntactic construct: the atom rules) and historical (git change frequency, measured PER "
    "FILE: every symbol in a file carries that file's churn= and hrank= verbatim, so this family is file "
    "evidence inherited by the row, not the row's own history). "
    "families=how many families exist eligible=functions and methods with a body, the denominator "
    "ranked=eligible symbols where at least one family fired no_family=eligible symbols where none did "
    "(ranked= + no_family= = eligible= exactly, on every run). "
    "s=one joined symbol: p=path:line n=symbol name fam=how many DISTINCT families fired of=how many families "
    "could be EVALUATED at all fired=their names unavail=families that could not be measured here. "
    "e=the evidence inside one fired family: f=family name why=the measurements that crossed, space separated; "
    "a lexical or confusion rule that fired N times reads rule*N. "
    "f=the per-file rollup: p=path top=the file's most corroborated symbol top_l=its line top_fam=its family "
    "count union_fam=how many distinct families fire ANYWHERE in the file union=their names syms=symbols in the "
    "file with at least one family. top_fam= is the STRONGER claim (several families agreeing on ONE symbol); "
    "union_fam= is weaker (different families on different symbols) and the rollup is ranked by the stronger one. "
    "THRESHOLDS, all stated here. Four structural signals are ABSOLUTE bars, reused verbatim from the "
    "quality-delta bars: bar_ccx=cognitive complexity bar_loc=physical lines bar_nest=max nesting depth "
    "bar_params=parameter count; a row shows only the ones that crossed, with the value that crossed. "
    "Two signals are RANKINGS with no defensible absolute cut, so each fires for the worst decile of its own "
    "ranking, at least one row and at most 40 (each verb's own default window): rrank=the symbol's rank in the "
    "readability lens (0 is least readable) rcut=how many ranks that decile covers rmeasured=functions the "
    "readability lens measured; hrank=the file's rank by git churn (0 is most changed) churn=its in-window "
    "commit count hcut=how many ranks that decile covers hranked=files with any in-window commit "
    "window=the churn window. An ordinal cut is RELATIVE: some symbol is always in the worst decile of its own "
    "corpus, so rrank= and hrank= mean 'worst in THIS corpus', never 'bad in absolute terms'. "
    "The historical family ranks by churn ALONE, not by the hotspots score (churn x complexity), because half of "
    "that product is the structural family and two families that cannot disagree are one family counted twice. "
    "unavailable=families that could not be evaluated at all, with unavailable_why= saying why, one reason per "
    "unavailable family (§L10: both absent, never =\"\", when every family was measured — house convention, "
    "absent means none). UNAVAILABLE is "
    "never the same as silent: an ABSENT unavailable= means every family was measured, and a family listed there "
    "was NOT measured, so its absence from fired= is not evidence of health. An EMPTY ranking counts as not "
    "measured, so hranked=0 makes the historical family unavailable: a corpus scanned from outside the "
    "repository that tracks it mines zero churn for every file, and that silence is not a fact about the code. "
    "So does an empty LANGUAGE COVERAGE. The confusion family is the atom pack, which by design runs only on "
    "C/C++/ObjC/CUDA paths, so on a corpus with no eligible function in one it was never applicable rather than "
    "quiet: cfiles=indexed files it can read cscope=eligible symbols inside them, and cscope=0 makes it "
    "unavailable. The lexical family is the naming pack, which has no opinion about a data or doc language: "
    "lscope=eligible symbols in a language it reads, and lscope=0 makes it unavailable. The structural family "
    "has no such precondition - its bars and its readability rank are computed for every language. "
    "of= on each row is 4 minus the unavailable families, so a row NEVER counts a family that could not have "
    "been evaluated for it, and fam= cannot reach 4 on a corpus where one family was never applicable. "
    "unreadable_files=indexed files the readability lens could not read, so rrank= is a floor over what it saw. "
    "findings_capped=1 when a lexical or confusion rule spent its per-rule budget, with floor_rules= naming "
    "them: those families are then FLOORS and the root carries counts_floor=1. A naming or atom finding that lies outside every function body is "
    "not joined to any symbol and is not counted here. "
    "shown_syms=symbol rows printed syms_capped=1 when symbol rows were dropped shown_files=file rows printed "
    "files_capped=1 when file rows were dropped; the symbol listing is the one limit=N and offset=M window, "
    "which also prints total= has_more= next_offset= offset= limit= -->";

// Emit the report. Returns the process exit code — always 0: this is a lens, not a gate.
// M12: `singleRoot`/`rootPrefix`/`rootAttr` are the caller's own single-root spelling (verbs_report.h's
// mvSingleRoot/mvRootPrefix/mvRootAttr, the same variables every OTHER lens this dispatcher serves already
// threads through) — before this parameter existed, every p= here printed the raw ingest-stored path
// ("./src/…" on a relative root) and the root open tag carried no root= at all, unlike every sibling verb.
inline int writeEnsembleReport( const IngestResult& ing, const std::vector<std::uint32_t>* churnPerFile,
                                const std::string& root, int pageLimit, int pageOffset,
                                bool singleRoot = false, const std::string& rootPrefix = {}, const std::string& rootAttr = {} )
{
    const EnsembleScan scan  = computeEnsemble( ing, churnPerFile );
    const std::size_t  total = scan.rows.size();
    const PageWindow   page  = pageWindow( total, effectiveRowCap( pageLimit, int( kEnsembleSymbolRowCap ) ), pageOffset );
    const std::size_t  shown = page.end > page.begin ? page.end - page.begin : 0;
    const std::size_t  fileShown = scan.files.size() < kEnsembleFileRowCap ? scan.files.size() : kEnsembleFileRowCap;

    char paging[kPageDisclosureCap];
    pagingDisclosure( paging, sizeof paging, total, page.end, pageLimit, pageOffset );

    std::vector<char> escUnavail;
    std::vector<char> escFloor;
    std::string       floorRules;
    for( const std::string& rule : scan.floorRules )
    {
        if( !floorRules.empty() )
        {
            floorRules += ',';
        }
        floorRules += rule;
    }

    std::fputs( kEnsembleLegend, stdout );
    std::fputs( rw::kAtStampLegend, stdout );
    // §L10: absent-means-none — unavailable=/unavailable_why= used to print unconditionally, so a run
    // where every family was available still carried unavailable="" unavailable_why="" (qualitypanel.h's
    // twin of this same emitter carries the identical fix).
    const std::string ensUnavailNamesStr    = familyList( scan.unavailMask );
    const std::string ensUnavailWhyStr      = detail::unavailWhyList( scan );
    const std::string ensUnavailableAttr    = ensUnavailNamesStr.empty() ? std::string() : ( " unavailable=\"" + ensUnavailNamesStr + "\"" );
    const std::string ensUnavailableWhyAttr = ensUnavailWhyStr.empty()   ? std::string() : ( " unavailable_why=\"" + std::string( escapeXml( ensUnavailWhyStr, escUnavail ) ) + "\"" );
    std::fputs( rw::rootRelPathsLegend( singleRoot ), stdout );   // M12: root= is new below
    std::printf( "<ensemble families=\"%u\" eligible=\"%zu\" ranked=\"%zu\" no_family=\"%zu\"%s%s",
                 unsigned( kFamilyCount ), scan.eligibleCount, total, scan.noFamilyCount,
                 ensUnavailableAttr.c_str(), ensUnavailableWhyAttr.c_str() );
    std::printf( " bar_ccx=\"%u\" bar_loc=\"%u\" bar_nest=\"%u\" bar_params=\"%u\"",
                 quality::kCcxBar, quality::kLocBar, quality::kNestBar, quality::kParamBar );
    std::printf( " rcut=\"%zu\" rmeasured=\"%zu\" hcut=\"%zu\" hranked=\"%zu\" window=\"%s\"",
                 scan.readabilityCut, scan.readabilityMeasured, scan.churnCut, scan.churnRanked, kEnsembleWindowLabel );
    // The LANGUAGE-COVERAGE denominators — what the availability verdict was computed FROM, so a reader can
    std::printf( " cfiles=\"%zu\" cscope=\"%zu\" lscope=\"%zu\"",     // check the verdict instead of taking it.
                 scan.confusionFiles, scan.confusionScope, scan.lexicalScope );
    if( scan.unreadableFileCount != 0 )
    {
        std::printf( " unreadable_files=\"%u\"", scan.unreadableFileCount );
    }
    if( !floorRules.empty() )
    {
        std::printf( " findings_capped=\"1\" floor_rules=\"%s\"%s", std::string( escapeXml( std::string_view( floorRules ), escFloor ) ).c_str(),
                     kGraphCountFloorAttrXml );   // H8: a floored family floors the root's counts
        // (kGraphCountFloorAttrXml: graphlegend.h — one attribute, one reading, for cap floors and graph floors alike)
    }
    std::printf( " shown_syms=\"%zu\" syms_capped=\"%s\" shown_files=\"%zu\" files_capped=\"%s\"%s%s%s>",
                 shown, shown < total ? "1" : "0",
                 fileShown, fileShown < scan.files.size() ? "1" : "0",
                 paging, gitstamp::atAttr( root ).c_str(), rootAttr.c_str() );

    // TWO scratch buffers, not one reused twice in the same call: escapeXml returns a VIEW into its `out`, so a
    // second call with the same buffer invalidates the first view (readability.h carries the same note).
    std::vector<char>  escPath;
    std::vector<char>  escName;
    const std::string  unavailNames = familyList( scan.unavailMask );
    // §L10: same absent-means-none convention as the root's unavailable= above — per-row unavail= must
    // not print ="" when nothing is unavailable (loop-invariant, so computed once, not per row).
    const std::string  unavailAttr  = unavailNames.empty() ? std::string() : ( " unavail=\"" + unavailNames + "\"" );
    const unsigned     evaluable    = unsigned( kFamilyCount ) - detail::familyCountOf( scan.unavailMask );
    for( std::size_t rowIndex = page.begin; rowIndex < page.end; ++rowIndex )
    {
        const EnsembleRow& row  = scan.rows[rowIndex];
        const Symbol&      s    = ing.symbols[row.id];
        const std::string_view rp = singleRoot ? rw::sarif::rootRelativeUri( ing.files[s.fileId], rootPrefix ) : std::string_view( ing.files[s.fileId] );
        const std::string  path( escapeXml( rp, escPath ) );
        const std::string  name( escapeXml( s.name, escName ) );
        std::printf( "<s p=\"%s:%u\" n=\"%s\" fam=\"%u\" of=\"%u\" fired=\"%s\"%s>",
                     path.c_str(), s.line, name.c_str(), unsigned( row.firedCount ), evaluable,
                     familyList( row.firedMask ).c_str(), unavailAttr.c_str() );
        for( std::uint8_t family = 0; family < kFamilyCount; ++family )
        {
            if( ( ( row.firedMask >> family ) & 1u ) == 0 )
            {
                continue;
            }
            std::vector<char> escWhy;
            std::printf( "<e f=\"%s\" why=\"%s\"/>", kFamilyNames[family],
                         std::string( escapeXml( row.why[family], escWhy ) ).c_str() );
        }
        std::printf( "</s>" );
    }
    for( std::size_t fileIndex = 0; fileIndex < fileShown; ++fileIndex )
    {
        const EnsembleFileRow& agg  = scan.files[fileIndex];
        const Symbol&          top  = ing.symbols[agg.topSym];
        const std::string_view frp  = singleRoot ? rw::sarif::rootRelativeUri( ing.files[agg.fileId], rootPrefix ) : std::string_view( ing.files[agg.fileId] );
        const std::string      path( escapeXml( frp, escPath ) );
        const std::string      name( escapeXml( top.name, escName ) );
        const std::string      names = familyList( agg.unionMask );
        std::printf( "<f p=\"%s\" top=\"%s\" top_l=\"%u\" top_fam=\"%u\" union_fam=\"%u\" union=\"%s\" syms=\"%u\"/>",
                     path.c_str(), name.c_str(), top.line, unsigned( agg.topCount ),
                     unsigned( detail::familyCountOf( agg.unionMask ) ), names.c_str(), agg.symCount );
    }
    std::printf( "</ensemble>" );
    return 0;
}

}   // namespace ensemble
}   // namespace rw
