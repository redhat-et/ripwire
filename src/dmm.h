#pragma once

// dmm.h — `--dmm`: the Delta Maintainability Model, one comparable scalar per change.
//
// `--quality-delta` answers WHICH KINDS of debt a change added. It cannot answer "was this change, on the
// whole, better or worse than the last one" — a per-kind report has no scale. DMM is that scale: ONE number
// in [0,1] per commit (or per working diff), trendable across commits and comparable across authors, tools
// and repos.
//
// THE MODEL. di Biase, Rastogi, Bruntink & van Deursen, "The Delta Maintainability Model: measuring
// maintainability of fine-grained code changes", TechDebt 2019 (SIG). The arithmetic and the three risk
// thresholds below are PyDriller's `deltamaintainability` reference implementation, verbatim
// (pydriller/domain/commit.py, `Method.is_low_risk` / `ModifiedFile._risk_profile` /
// `Commit._good_change_proportion`) — read from the package, not paraphrased from the paper:
//
//   A UNIT is a function/method DEFINITION WITH A BODY. Its VOLUME is its line span.
//   Per property, a unit is LOW risk iff   size: loc <= 15   complexity: cx <= 5   interfacing: params <= 2
//   A side's RISK PROFILE is (sum of volume over low units, sum of volume over high units).
//   delta_low = low_target - low_base                 delta_high = high_target - high_base
//   good = max( delta_low, 0 ) + max( -delta_high, 0 )      added low-risk code, or removed high-risk code
//   bad  = max( -delta_low, 0 ) + max( delta_high, 0 )      removed low-risk code, or added high-risk code
//   DMM  = good / ( good + bad )
//
// WHY THAT SHAPE IS THE POINT. Deleting a god function is the best thing a commit can do, and it scores 1.0.
// Adding lines to one is the worst, and it scores 0.0. And — the property this verb exists to protect —
// EDITING bad code without growing it moves nothing: the unit sits in the same bin with the same volume on
// both sides, so it contributes exactly zero to both good and bad. DMM is a DELTA measure, never a level
// measure over a tree. A gate that punished you for touching an already-bad function is a gate people route
// around, and that is precisely the failure this model was designed to avoid.
//
// WHAT `good + bad == 0` MEANS, and what it must never be reported as. A commit that renames a local, edits
// a string literal, reorders statements or reflows a comment moves no unit's loc/cx/params. Its total change
// is zero and the ratio is 0/0. PyDriller returns None; this verb reports UNAVAILABLE on the attribute and
// says so in `reason=`. It is NOT 1.0 ("a perfect commit") and NOT 0.0 ("a terrible one"): it is a commit
// this model cannot score, and the house rule is to say that rather than pick a flattering default. The same
// applies per property — a change that only adds parameters leaves `size` and `complexity` UNAVAILABLE while
// `interfacing` is measured.
//
// THE COMBINED SCORE IS OURS, NOT THE PAPER'S. PyDriller exposes three separate properties and no
// aggregate. `dmm=` on the root is a POOLED ratio — (sum of good over the three properties) / (sum of good +
// sum of bad) — which weights each property by how much change it actually saw, and stays defined when one
// property is UNAVAILABLE. It is labelled `combine="pooled"` on the root so nobody mistakes it for a
// published number. The three sub-scores are emitted alongside it because they are separately actionable.
//
// THE ONE DEVIATION FROM THE REFERENCE, stated here rather than discovered later. PyDriller's volume is
// lizard's `nloc` (non-blank, non-comment lines); ripwire's volume is `Symbol::loc`, the definition's
// PHYSICAL line span, which is what this index already carries. Physical span >= nloc, so a heavily
// commented or airily formatted unit crosses the size threshold here EARLIER than it would in PyDriller.
// The thresholds are unchanged (they are the SIG risk-profile boundaries); the measure under them is
// ripwire's. The root discloses this as `size_metric="physical-loc"` and the legend spells it out.
//
// DETERMINISM. Both profiles are integer sums over the symbol table in index order — no float accumulation,
// no hash iteration, no thread timing. Only the final division is floating point, and it is printed at three
// decimals from two exact integers that are themselves emitted, so the ratio is auditable rather than
// trusted.

#include "model.h"
#include "quality.h"     // materializeCommitTree / TmpTreeGuard / gitResolveCommitSha / gitHeadSha / the HEAD ingest-cache keys
#include "ingest.h"      // ingest — the second side is a real parse of a materialized tree
#include "serialize.h"   // escapeXml
#include "Diagnostics.h" // DEGRADED_PATH_ALERT — every failure here degrades to UNAVAILABLE, never aborts

#include <cstdint>
#include <cstdio>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

namespace rw::dmm
{

// The SIG risk-profile boundaries, as PyDriller spells them (Method.UNIT_*_LOW_RISK_THRESHOLD). Named, not
// inlined as three literals, so a reader can check them against the package without decoding an expression.
inline constexpr std::uint32_t kUnitSizeLowRiskMax        = 15;   // lines
inline constexpr std::uint32_t kUnitComplexityLowRiskMax  = 5;    // cyclomatic complexity
inline constexpr std::uint32_t kUnitInterfacingLowRiskMax = 2;    // parameters

// The three properties, in the order they are emitted. Index-addressed rather than switched: every loop in
// this file walks all three, and a fourth would be a row here plus a threshold above.
inline constexpr std::size_t kPropCount = 3;
inline constexpr const char* kPropNames[kPropCount] = { "size", "complexity", "interfacing" };

// Why the run could not produce a score. Ok and NoParent/NoGit/… are NOT the same thing as BadRev: the first
// group is the environment (degrade to an UNAVAILABLE report, exit 0), BadRev is the user's typo (a refusal
// that names the offending token, exit 1). Keeping them apart is the difference between "this tree cannot be
// scored" and "you asked for a revision that does not exist".
enum class Status : std::uint8_t { Ok, BadRev, BadRange, NoGit, NoParent, MaterializeFailed };

struct RiskProfile
{
    std::uint64_t lowVolume  = 0;
    std::uint64_t highVolume = 0;
};

// One side of the comparison (base tree or target tree).
struct SideProfile
{
    RiskProfile   byProp[kPropCount] {};
    std::uint64_t unitCount = 0;   // definitions with a body that were measured
    std::uint64_t volume    = 0;   // their total line span — the denominator a reader needs to size the deltas
};

// One property's answer. The four integers are emitted because the ratio alone is not auditable.
struct PropScore
{
    std::int64_t  deltaLow  = 0;
    std::int64_t  deltaHigh = 0;
    std::uint64_t good      = 0;
    std::uint64_t bad       = 0;
    bool          available = false;   // false ⇔ good + bad == 0 ⇔ this property saw no risk-profile change
    double        score     = 0.0;
};

struct Result
{
    Status        status = Status::Ok;
    std::string   badToken;              // the revision spelling that did not resolve (BadRev/BadRange only)
    std::string   reason;                // the sentence the report prints when there is no score
    std::string   baseSha;               // resolved, full
    std::string   targetSha;             // resolved, full; empty ⇔ the target is the working tree
    bool          targetIsWorkingTree = false;
    SideProfile   base;
    SideProfile   target;
    PropScore     props[kPropCount] {};
    bool          available = false;     // the COMBINED score exists
    double        score     = 0.0;
    std::uint64_t good      = 0;
    std::uint64_t bad       = 0;
};

// Is this symbol a UNIT? A definition with a body, of a callable kind. A prototype, an abstract declaration
// and a markdown heading are not units — they have no volume to move, and counting a one-line prototype as a
// low-risk unit would let a header reshuffle manufacture a score. Same body test `--readability` uses.
inline bool isUnit( const Symbol& s ) noexcept
{
    if( s.kind != SymKind::Function && s.kind != SymKind::Method )
    {
        return false;
    }
    return s.endByte > s.sigEndByte;
}

inline bool isLowRisk( const Symbol& s, std::size_t propIndex ) noexcept
{
    if( propIndex == 0 )
    {
        return s.loc <= kUnitSizeLowRiskMax;
    }
    if( propIndex == 1 )
    {
        return s.cx <= kUnitComplexityLowRiskMax;
    }
    return std::uint32_t( s.params ) <= kUnitInterfacingLowRiskMax;
}

// The risk profile of a whole ingested tree. Deliberately NOT keyed by symbol identity: DMM compares two
// VOLUMES, and an unchanged unit lands in the same bin with the same volume on both sides, so it cancels to
// zero without ever being matched. That is also what makes a pure file move free — the volume leaves one
// path and arrives at another inside the same sum.
inline SideProfile profileOf( const IngestResult& ing )
{
    SideProfile out;
    for( const Symbol& s : ing.symbols )
    {
        if( !isUnit( s ) )
        {
            continue;
        }
        ++out.unitCount;
        out.volume += s.loc;
        for( std::size_t propIndex = 0; propIndex < kPropCount; ++propIndex )
        {
            RiskProfile& p = out.byProp[propIndex];
            if( isLowRisk( s, propIndex ) )
            {
                p.lowVolume += s.loc;
            }
            else
            {
                p.highVolume += s.loc;
            }
        }
    }
    return out;
}

// PyDriller's `_good_change_proportion`, transcribed. The asymmetry is the model: low-risk volume ARRIVING is
// good and LEAVING is bad; high-risk volume arriving is bad and leaving is good.
inline PropScore scoreProperty( const RiskProfile& base, const RiskProfile& target ) noexcept
{
    PropScore out;
    out.deltaLow  = std::int64_t( target.lowVolume )  - std::int64_t( base.lowVolume );
    out.deltaHigh = std::int64_t( target.highVolume ) - std::int64_t( base.highVolume );

    if( out.deltaLow >= 0 )
    {
        out.good += std::uint64_t( out.deltaLow );
    }
    else
    {
        out.bad += std::uint64_t( -out.deltaLow );
    }
    if( out.deltaHigh >= 0 )
    {
        out.bad += std::uint64_t( out.deltaHigh );
    }
    else
    {
        out.good += std::uint64_t( -out.deltaHigh );
    }

    const std::uint64_t total = out.good + out.bad;
    out.available = total != 0;
    out.score     = out.available ? double( out.good ) / double( total ) : 0.0;
    return out;
}

// Join the two sides. Pure arithmetic on two profiles — no git, no IO — so the gate can reason about it and
// so `computeDmm` below is the only place that has to be careful about trees.
inline void scoreSides( Result& r )
{
    for( std::size_t propIndex = 0; propIndex < kPropCount; ++propIndex )
    {
        r.props[propIndex] = scoreProperty( r.base.byProp[propIndex], r.target.byProp[propIndex] );
        r.good += r.props[propIndex].good;
        r.bad  += r.props[propIndex].bad;
    }
    const std::uint64_t total = r.good + r.bad;
    r.available = total != 0;
    r.score     = r.available ? double( r.good ) / double( total ) : 0.0;
    if( !r.available )
    {
        r.reason = "no unit's size, complexity or parameter count moved — this change is outside what the model measures";
    }
}

// Ingest the tree at `sha`, materialized out of `root`'s object store. The HEAD side reuses the SAME
// incremental ingest-cache family `--quality-delta` already maintains (keyed on repo + excludes + sha, with
// per-file content hashes, so it can never serve a foreign or stale parse) — the common case is then a warm
// blob read instead of a full parse. Any OTHER revision is parsed cold on purpose: that family is capped at
// two files per (repo, excludes), and letting an arbitrary rev-range sweep evict `--quality-delta`'s entry
// would trade this verb's speed for that one's on every run.
inline bool ingestCommitTree( const std::string& root, const std::string& sha, const std::vector<std::string>& excludes,
                              std::size_t maxFileBytes, IngestResult& out )
{
    const std::string tmpRoot = quality::materializeCommitTree( root, sha, "dmm" );
    if( tmpRoot.empty() )
    {
        return false;   // materializeCommitTree already alerted
    }
    quality::TmpTreeGuard guard{ tmpRoot };

    std::string cachePath;
    if( sha == quality::gitHeadSha( root ) )
    {
        const std::string repoHex = quality::headSnapRepoHex( root );
        const std::string exclHex = quality::headSnapExclHex( excludes, maxFileBytes );
        cachePath                 = quality::headSnapCachePath( repoHex, exclHex, sha );
    }

    // ingest() writes single-writer process-global query caches; the sibling HEAD-tree readers in quality.h
    // serialize on this same mutex, so this one does too rather than inventing a second lock order.
    std::lock_guard<std::mutex> ingestLock( quality::headSnapshotIngestMutex() );
    out = ingest( tmpRoot.c_str(), excludes, cachePath.empty() ? std::string_view {} : std::string_view( cachePath ), maxFileBytes );
    if( out.symbols.empty() && out.files.empty() )
    {
        DEGRADED_PATH_ALERT( "dmm: a materialized commit tree ingested empty" );
        return false;
    }
    return true;
}

// Split `--dmm=VALUE`. Three accepted spellings, and every one of them resolves through
// `gitResolveCommitSha` before a token reaches git a second time:
//   ""        the working tree against HEAD                (the default, and what `--quality-delta` compares)
//   "REV"     REV against its FIRST PARENT                 (the per-commit scalar the paper defines)
//   "A..B"    B against A                                  (an explicit range; an empty side means HEAD)
// `A...B` (symmetric difference) is refused rather than silently read as `A..B`: for a TREE comparison the
// two spellings mean different things and guessing which one was meant is exactly the kind of quiet
// substitution this codebase does not ship.
inline Result computeDmm( const std::string& root, std::string_view spec, const IngestResult& workingIng,
                          const std::vector<std::string>& excludes, std::size_t maxFileBytes )
{
    Result r;

    if( !quality::gitRepoHasHistory( root ) )
    {
        r.status = Status::NoGit;
        r.reason = "not a git repository, or no commit on HEAD — there is no earlier tree to compare against";
        return r;
    }

    // Resolve both endpoints to bare shas BEFORE anything else touches git — one place, three spellings.
    if( spec.empty() )
    {
        r.targetIsWorkingTree = true;
        r.baseSha             = quality::gitResolveCommitSha( root, "HEAD" );
        if( r.baseSha.empty() )
        {
            r.status = Status::NoGit;
            r.reason = "HEAD does not resolve to a commit — there is no earlier tree to compare against";
            return r;
        }
    }
    else if( spec.find( "..." ) != std::string_view::npos )
    {
        r.status   = Status::BadRange;
        r.badToken = std::string( spec );
        return r;
    }
    else if( const std::size_t sep = spec.find( ".." ); sep != std::string_view::npos )
    {
        const std::string baseRef   = sep == 0 ? std::string( "HEAD" ) : std::string( spec.substr( 0, sep ) );
        const std::string targetRef = sep + 2 >= spec.size() ? std::string( "HEAD" ) : std::string( spec.substr( sep + 2 ) );
        r.baseSha   = quality::gitResolveCommitSha( root, baseRef );
        r.targetSha = quality::gitResolveCommitSha( root, targetRef );
        if( r.baseSha.empty() || r.targetSha.empty() )
        {
            r.status   = Status::BadRev;
            r.badToken = r.baseSha.empty() ? baseRef : targetRef;
            return r;
        }
    }
    else
    {
        const std::string targetRef = std::string( spec );
        r.targetSha                 = quality::gitResolveCommitSha( root, targetRef );
        if( r.targetSha.empty() )
        {
            r.status   = Status::BadRev;
            r.badToken = targetRef;
            return r;
        }
        // The per-commit form: the commit against its FIRST parent. A root commit has none — an environment
        // fact, not a typo, so it degrades to UNAVAILABLE with a stated reason rather than refusing.
        r.baseSha = quality::gitResolveCommitSha( root, r.targetSha + "^" );
        if( r.baseSha.empty() )
        {
            r.status = Status::NoParent;
            r.reason = "that commit has no parent — a root commit has no earlier tree to be a delta against";
            return r;
        }
    }

    IngestResult baseIng;
    if( !ingestCommitTree( root, r.baseSha, excludes, maxFileBytes, baseIng ) )
    {
        r.status = Status::MaterializeFailed;
        r.reason = "the base commit's tree could not be materialized or parsed";
        return r;
    }
    r.base = profileOf( baseIng );

    if( r.targetIsWorkingTree )
    {
        r.target = profileOf( workingIng );   // already parsed, with the same excludes this run was given
    }
    else
    {
        IngestResult targetIng;
        if( !ingestCommitTree( root, r.targetSha, excludes, maxFileBytes, targetIng ) )
        {
            r.status = Status::MaterializeFailed;
            r.reason = "the target commit's tree could not be materialized or parsed";
            return r;
        }
        r.target = profileOf( targetIng );
    }

    scoreSides( r );
    return r;
}

// The legend the reader meets FIRST. Every attribute this verb emits is DEFINED here in the house `name=`
// form. No `--` digraph anywhere in it — illegal inside an XML comment — so flags are named bare.
inline constexpr const char* kDmmLegend =
    "<!-- ripwire dmm: the Delta Maintainability Model (di Biase, Rastogi, Bruntink, van Deursen, TechDebt 2019), "
    "ONE comparable scalar per change. Thresholds and arithmetic are PyDriller's deltamaintainability reference "
    "implementation. A UNIT is a function or method definition WITH A BODY; its VOLUME is its line span. Per property "
    "a unit is LOW risk iff size: loc at most 15, complexity: cyclomatic at most 5, interfacing: params at most 2. "
    "good=volume of low-risk code ADDED plus high-risk code REMOVED bad=volume of low-risk code REMOVED plus "
    "high-risk code ADDED dmm=good/(good+bad), in [0,1]: 1.000 means every line this change moved made the code "
    "healthier. THIS IS A DELTA, NOT A LEVEL: editing bad code without growing it moves nothing and scores nothing, "
    "which is deliberate. dmm=UNAVAILABLE means good+bad was 0, i.e. the change moved no unit's size, complexity or "
    "parameter count, and is NEVER to be read as 1.000 or 0.000; reason= says which case it was. "
    "base=the earlier tree's commit target=the later tree's commit, or working-tree base_units= target_units= units "
    "measured on each side base_volume= target_volume= their total line span "
    "combine=how the root dmm= pools the three sub-scores (pooled = summed good over summed good+bad; the paper "
    "publishes the three separately and no aggregate, so this one is ripwire's) "
    "size_metric=physical-loc: volume is the definition's PHYSICAL line span, where the reference implementation "
    "uses non-comment non-blank lines, so a heavily commented unit crosses the size threshold here earlier "
    "available=0 when no score could be produced at all "
    "p=one property row k=its name (size|complexity|interfacing) d_low=change in low-risk volume d_high=change in "
    "high-risk volume. Every indexed language and every indexed path counts, tests and fixtures included; params "
    "and cyclomatic complexity come from the index, so a definition whose grammar exposes no parameter list "
    "contributes params=0 and classifies LOW on interfacing. -->";

// Print one score attribute: the number, or the honest token. Shared by the root and the property rows so the
// two can never drift into disagreeing about what "no score" looks like — which is also why the value is
// formatted into ONE buffer and emitted from ONE printf rather than through a two-armed branch: there is a
// single place that decides how a score is spelled, and UNAVAILABLE is its default rather than its else.
// 16 bytes holds both spellings with room to spare ("UNAVAILABLE" is 11 + NUL; "%.3f" of a ratio in [0,1] is 5).
inline void printScoreAttr( const char* name, bool available, double score )
{
    char value[16] = "UNAVAILABLE";
    if( available )
    {
        std::snprintf( value, sizeof value, "%.3f", score );
    }
    std::printf( " %s=\"%s\"", name, value );
}

// Emit the report. Returns the process exit code — always 0. This is a MEASUREMENT, not a gate: it has no
// threshold and renders no verdict, and the moment a maintainability score gates a merge is the moment
// people start writing code to the score.
inline int writeDmmReport( const Result& r )
{
    std::vector<char> escReason;
    std::vector<char> escBase;
    std::vector<char> escTarget;

    std::fputs( kDmmLegend, stdout );
    std::fputs( "<dmm", stdout );

    if( r.status != Status::Ok )
    {
        const std::string reason( escapeXml( r.reason, escReason ) );
        std::printf( " available=\"0\" dmm=\"UNAVAILABLE\" reason=\"%s\"/>", reason.c_str() );
        return 0;
    }

    const std::string base( escapeXml( r.baseSha, escBase ) );
    const std::string target( escapeXml( r.targetIsWorkingTree ? std::string( "working-tree" ) : r.targetSha, escTarget ) );
    std::printf( " base=\"%s\" target=\"%s\" available=\"%d\" combine=\"pooled\" size_metric=\"physical-loc\"",
                 base.c_str(), target.c_str(), r.available ? 1 : 0 );
    printScoreAttr( "dmm", r.available, r.score );
    std::printf( " good=\"%llu\" bad=\"%llu\"", static_cast<unsigned long long>( r.good ), static_cast<unsigned long long>( r.bad ) );
    std::printf( " base_units=\"%llu\" base_volume=\"%llu\" target_units=\"%llu\" target_volume=\"%llu\"",
                 static_cast<unsigned long long>( r.base.unitCount ), static_cast<unsigned long long>( r.base.volume ),
                 static_cast<unsigned long long>( r.target.unitCount ), static_cast<unsigned long long>( r.target.volume ) );
    if( !r.available )
    {
        const std::string reason( escapeXml( r.reason, escReason ) );
        std::printf( " reason=\"%s\"", reason.c_str() );
    }
    std::fputs( ">", stdout );

    for( std::size_t propIndex = 0; propIndex < kPropCount; ++propIndex )
    {
        const PropScore& p = r.props[propIndex];
        std::printf( "<p k=\"%s\"", kPropNames[propIndex] );
        printScoreAttr( "dmm", p.available, p.score );
        std::printf( " good=\"%llu\" bad=\"%llu\" d_low=\"%lld\" d_high=\"%lld\"/>",
                     static_cast<unsigned long long>( p.good ), static_cast<unsigned long long>( p.bad ),
                     static_cast<long long>( p.deltaLow ), static_cast<long long>( p.deltaHigh ) );
    }
    std::fputs( "</dmm>", stdout );
    return 0;
}

}   // namespace rw::dmm
