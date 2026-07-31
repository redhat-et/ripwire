#pragma once

// landingplan.h — --stray-content --plan: "of all my branches, which still hold REAL work, and in what
// order should I land them?" Two verbs already answer adjacent questions and stop just short of this one:
//   --stray-content  sweeps every local branch (cheap, per-BLOB) and verdicts each: unmerged (genuinely
//                    absent work), superseded (the live line already re-implemented it — git cherry's
//                    blind spot), merged (omitted).
//   --merge-scout    takes a HAND-AUTHORED ref list (expensive, per-ARM: git-archive + full ingest) and
//                    reports pairwise same-symbol conflicts / same-file risks + a landing order.
// The gap: you must already know which branches matter to reach for merge-scout. This composes them —
// select the refs --stray-content calls "unmerged", DROP the "superseded" ones (landing them would re-do
// work the live line already did, exactly the waste --stray-content exists to catch), and feed the
// survivors straight to merge-scout's existing overlap + landing-order machinery. Composition only: every
// number below comes from crossref::computeStrayContent or mergescout::computeMergeScout verbatim, neither
// reimplemented.
//
// ── the cost seam (read this before raising kMaxPlanScout) ──────────────────────────────────────────────
// --stray-content is a per-BLOB sweep (one `git cat-file --batch` for the whole run, never parses) — cheap:
// ~2 s for 35 refs on the dogfood repo. --merge-scout is a per-ARM git-archive + FULL ingest of a ref's
// tree AND its merge-base — the audited multi-second, high-RSS path TreeIndexMemo exists to bound (see its
// class comment in mergescout.h). Composing "scout every unmerged ref" naively multiplies that cost by the
// unmerged count: measured on the dogfood repo (35 branches, 9 unmerged, real C++ sources), scouting all 9
// took 27 s (~3 s/ref, some of it warmed by TreeIndexMemo sharing a merge-base tree across arms). That is
// nowhere near the ~0.10 s default-map path, but this whole verb is an EXPLICIT opt-in (`--plan` refuses
// without `--stray-content`) for a "before you land" decision, not a per-question call — the same cost
// class --merge-scout itself already accepted for a hand-authored ref list.
//
// kMaxPlanScout bounds the worst case anyway: only the top-N unmerged refs BY STRAY SIZE (the ones with the
// most real work, i.e. the ones a landing decision actually matters for) are fed to merge-scout; the rest
// are still COUNTED and LISTED with scouted="0" — never silently dropped, just not paid for this run.
// --detail lifts the bound (SIZE_MAX), the same "show me everything, I will pay for it" meaning it already
// has for every other verb in this file family (--stray-content/--whereis/--flags row caps).
//
// Read-only, always: pure composition of two read-only verbs — no git plumbing of its own. Inherits both
// verbs' contract: no checkout, no ref write, no working-tree mutation.
//
// ANCHORING (r26 merge-base audit): inherited, not re-decided. This file runs no git command at all, so
// every comparison here is whichever anchor crossref.h §ANCHORING and mergescout.h §ANCHORING already
// chose — base-anchored selection from --stray-content, base-anchored arms plus the head_conflicts= row
// class from --merge-scout. There is nothing HEAD-anchored to defend at this layer; adding a git call here
// would be the way to reintroduce the problem, so don't.

#include "model.h"
#include "crossref.h"
#include "mergescout.h"
#include "serialize.h"    // escapeXml
#include "Diagnostics.h"  // DEGRADED_PATH_ALERT
#include "gitstamp.h"     // r26-stamp Task A: gitstamp::stampAt — the at="<sha>[+dirty]" root anchor

#include <cstdint>
#include <cstdio>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace ctx
{
namespace landingplan
{

// Default cap on how many UNMERGED refs get the expensive merge-scout treatment, ranked by stray line
// count. Picked to clear the dogfood repo's own 9-unmerged-branch fleet with room to spare while still
// bounding a runaway branch count (kMaxRefs=512 is --stray-content's OWN refusal ceiling — 512 arms through
// merge-scout would be a different order of cost problem entirely). --detail overrides it to unbounded.
constexpr std::size_t kMaxPlanScout = 12;

struct PlanResult
{
    bool                      ok          = true;
    bool                      nonGitRoot  = false;    // --stray-content's own refusal reasons, passed through
    bool                      tooManyRefs = false;    // verbatim — this verb adds no refusal of its own
    crossref::StrayResult     stray;                  // the full sweep (headSha/refsScanned/mergedRefs/refs)
    std::vector<std::size_t>  scouted;                // indices into stray.refs: the landing set fed to merge-scout
    std::vector<std::size_t>  bounded;                // indices into stray.refs: unmerged, but cut by the size bound
    std::vector<std::size_t>  undetermined;           // indices into stray.refs: v="unknown" — NOT analysable (no merge-base),
                                                      // so neither selectable nor dismissable; surfaced, never omitted
    bool                      scoutOk     = true;      // false ⇒ merge-scout itself refused (see mergescout::ScoutResult;
                                                        // e.g. a local branch literally named "working-tree" collides
                                                        // with its reserved arm name) — degrade, arms/pairs/landing empty
    mergescout::ScoutResult   scout;                  // computeMergeScout() over `scouted`'s ref names, in order
    std::string               atStamp;                // r26-stamp Task A: gitstamp::stampAt(root) — "" on a non-git root
};

// `refs[idx[i]].ref.name` joined with commas, in `idx` order — the exact CSV merge-scout wants, and the
// same order its arms come back in, so the plan and scout sections of the emitted XML line up name-for-name.
inline std::string joinRefNames( const std::vector<crossref::RefRow>& refs, const std::vector<std::size_t>& idx )
{
    std::string csv;
    for( std::size_t i : idx )
    {
        if( !csv.empty() ) csv += ',';
        csv += refs[i].ref.name;
    }
    return csv;
}

// The whole computation: sweep, select+bound the unmerged set, scout it. `scoutCap` is the caller's already-
// resolved bound (kMaxPlanScout, or SIZE_MAX under --detail) — resolved by the caller so this stays a pure
// function of its inputs, no cfg.detail reach-in.
inline PlanResult computePlan( const std::string& root, std::string_view filter, const IngestResult& workingIng,
                               const std::vector<std::string>& excludes, std::size_t maxFileBytes,
                               std::size_t scoutCap = kMaxPlanScout )
{
    PlanResult result;
    result.atStamp = gitstamp::stampAt( root );   // r26-stamp Task A: set up front so every return path carries it
    result.stray    = crossref::computeStrayContent( root, filter );
    if( !result.stray.ok )
    {
        result.ok          = false;
        result.nonGitRoot   = result.stray.nonGitRoot;
        result.tooManyRefs  = result.stray.tooManyRefs;
        return result;
    }

    // stray.refs is ALREADY sorted strayLines desc / ref name asc (computeStrayContent's own report order —
    // "the queue the owner works"), so the unmerged subset inherits that order for free: "top-N by stray
    // size" is just "first N of the filtered list", no second sort needed.
    // Three-way, not two-way. A ref whose analysis FAILED (no merge-base: shallow clone, unrelated history)
    // is not unmerged and is not superseded, so a straight `verdict == Unmerged` selection dropped it out of
    // every list this verb emits — a branch holding real orphan work appearing NOWHERE in the report whose
    // entire purpose is "which branches still hold real work". It gets its own list and its own row instead.
    std::vector<std::size_t> unmergedIdx;
    for( std::size_t i = 0; i < result.stray.refs.size(); ++i )
    {
        const crossref::RefRow& r = result.stray.refs[i];
        if     ( !r.ok || r.verdict == crossref::Verdict::Unknown ) result.undetermined.push_back( i );
        else if( r.verdict == crossref::Verdict::Unmerged )         unmergedIdx.push_back( i );
    }

    for( std::size_t rank = 0; rank < unmergedIdx.size(); ++rank )
        ( rank < scoutCap ? result.scouted : result.bounded ).push_back( unmergedIdx[rank] );

    if( result.scouted.empty() ) return result;   // nothing unmerged (or the bound is 0) — stray-content already answered it

    const std::string refsCsv = joinRefNames( result.stray.refs, result.scouted );
    result.scout   = mergescout::computeMergeScout( root, refsCsv, workingIng, excludes, maxFileBytes );
    result.scoutOk = result.scout.ok;
    if( !result.scoutOk )
        DEGRADED_PATH_ALERT( "landing-plan: merge-scout refused the selected landing set — reporting the sweep without arms/conflicts/order" );
    return result;
}

// ── XML emission (G4: minified, xmllint-clean; no `\n` outside CDATA) ───────────────────────────────────

using XmlEscaper = std::function<std::string( std::string_view )>;

inline void writePlanRef( std::FILE* out, const crossref::RefRow& r, bool scouted, const XmlEscaper& ex )
{
    std::fprintf( out, "<ref name=\"%s\" v=\"%s\" stray=\"%u\" files=\"%u\" scouted=\"%d\"/>",
                  ex( r.ref.name ).c_str(), crossref::verdictTag( r.verdict ), r.strayLines, r.strayFiles, scouted ? 1 : 0 );
}

// A ref this verb DROPS from the landing set, with the reason. Two element names, one emitter — the claims
// differ in KIND, so they must not share an element:
//   <excluded>      — "we looked, and you do not need this": the live line already re-implemented the work.
//                     Superseded is the only drop reason this verb adds on top of --stray-content's own
//                     (merged refs stay omitted exactly as --stray-content omits them, counted in merged=).
//   <undetermined>  — "we could NOT look": no merge-base, so nothing was measured. That is an ACTION ITEM
//                     (deepen the clone, re-run), not a verdict, and it carries no stray= because printing
//                     a count for a measurement that never happened is the same false-confidence bug one
//                     layer down. The reader must not be able to mistake absence of evidence for evidence.
// The branch is taken from the ref's OWN state rather than a caller-passed flag, so a row can never be
// emitted under the wrong element.
inline void writePlanDrop( std::FILE* out, const crossref::RefRow& r, const XmlEscaper& ex )
{
    if( !r.ok || r.verdict == crossref::Verdict::Unknown )
    {
        std::fprintf( out, "<undetermined name=\"%s\" v=\"%s\" reason=\"no merge base with HEAD (shallow clone or unrelated "
                           "history) — this ref could not be analysed, it is NOT known to be merged; deepen the clone and re-run\"/>",
                      ex( r.ref.name ).c_str(), crossref::verdictTag( crossref::Verdict::Unknown ) );
        return;
    }
    std::fprintf( out, "<excluded name=\"%s\" v=\"%s\" stray=\"%u\" reason=\"already re-implemented on the live line\"/>",
                  ex( r.ref.name ).c_str(), crossref::verdictTag( r.verdict ), r.strayLines );
}

inline void writePlan( std::FILE* out, const PlanResult& p )
{
    std::vector<char> esc;
    const XmlEscaper  ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };

    std::uint32_t supersededCount = 0;
    for( const crossref::RefRow& r : p.stray.refs ) if( r.verdict == crossref::Verdict::Superseded ) ++supersededCount;

    // G4: an XML comment may not contain a double hyphen, so this text (like writeStrayContent's and
    // writeWhereis's) uses an em dash for punctuation and names flags WITHOUT their leading dashes.
    std::fprintf( out, "<!-- ripwire landing-plan: stray-content's cheap per-blob sweep composed with merge-scout's "
                       "per-arm overlap oracle — of every local branch, which still hold REAL work (v=\"unmerged\"), "
                       "which were already re-implemented on the live line (v=\"superseded\", EXCLUDED below — landing "
                       "them re-does work that is already done) or are already merged (omitted entirely, counted in "
                       "merged= on the root element), and the fewest-conflicts-first order to land what remains. "
                       "scouted=\"0\" on an unmerged ref means it was NOT fed to merge-scout this run (the cost bound, "
                       "not a verdict) — it is still real, unscouted work; bounded= on the root element counts them "
                       "and detail lifts the bound. merge-scout is the EXPENSIVE step here (git-archive + full "
                       "ingest per arm) — stray-content's own sweep is the cheap one. An undetermined row is a ref that "
                       "could NOT be analysed at all (no merge base with HEAD, which on a SHALLOW clone is every ref): it "
                       "is neither scouted nor excluded nor merged, because nothing was measured — treat it as unfinished "
                       "business and deepen the clone, never as a clean branch. Read-only throughout: no "
                       "checkout, no ref write, no working-tree mutation. The root carries BOTH head= and at= and they "
                       "are the same commit: head= is the bare 9 hex chars this verb has always printed, at= is the "
                       "tool wide anchor and is head= plus a \"+dirty\" suffix when the working tree is not clean. Prefer "
                       "at= (it is the one spelling every other repo reading verb uses, and the only one that tells you "
                       "whether uncommitted work was in scope); head= is kept for callers already keyed to it. -->" );
    // r26-stamp Task A: head= (pre-existing, bare 9-char sha, unchanged) and at= (this round's sha[+dirty]
    // anchor) are BOTH kept here rather than converged onto one: head= is an established attribute name this
    // verb already shipped and other callers may already key off, so it stays byte-for-byte what it was;
    // at= is the new cross-verb-consistent name that ALSO carries the dirty flag head= never had (relevant
    // here specifically — merge-scout's own working-tree arm is dirty-sensitive too).
    // §P8 RE-EXAMINED, not merely inherited: the pair IS redundant (head= is a strict prefix of at=), but
    // dropping head= HERE alone would leave landing-plan the only member of its family (<stray-content>,
    // <abi>, <whereis>) without it — one inconsistency traded for a worse one — and gitstampcheck.sh pins it.
    // DOCUMENTED instead: the header above states the containment in the OUTPUT, where consumers read it.
    // Converge by retiring head= across the whole family at once, never one verb at a time.
    const std::string atAttr = p.atStamp.empty() ? std::string() : ( " at=\"" + p.atStamp + "\"" );
    std::fprintf( out, "<landing-plan head=\"%.9s\" refs=\"%zu\" unmerged=\"%zu\" superseded=\"%u\" merged=\"%u\" "
                       "undetermined=\"%zu\" scouted=\"%zu\" bounded=\"%zu\" scout-ok=\"%d\"%s>",
                  p.stray.headSha.c_str(), p.stray.refsScanned, p.scouted.size() + p.bounded.size(),
                  supersededCount, p.stray.mergedRefs, p.undetermined.size(), p.scouted.size(), p.bounded.size(),
                  p.scoutOk ? 1 : 0, atAttr.c_str() );

    for( std::size_t i : p.scouted )      writePlanRef( out, p.stray.refs[i], true,  ex );
    for( std::size_t i : p.bounded )      writePlanRef( out, p.stray.refs[i], false, ex );
    for( std::size_t i : p.undetermined ) writePlanDrop( out, p.stray.refs[i], ex );
    for( const crossref::RefRow& r : p.stray.refs ) if( r.ok && r.verdict == crossref::Verdict::Superseded ) writePlanDrop( out, r, ex );

    // The scout section: reuse mergescout.h's own arm/pair/landing emitters VERBATIM (byte-identical shape
    // to a hand-authored --merge-scout=... call over the same ref list) — this composition never re-derives
    // conflict/risk/landing-order logic, only selects which refs reach it.
    for( const mergescout::Arm& arm : p.scout.arms ) mergescout::writeScoutArm( out, arm, ex );
    const std::vector<mergescout::PairOverlap> pairs = mergescout::computeOverlaps( p.scout.arms );
    for( const mergescout::PairOverlap& pr : pairs ) mergescout::writeScoutPair( out, p.scout.arms, pr, ex );
    mergescout::writeScoutLanding( out, p.scout.arms, pairs, ex );

    std::fprintf( out, "</landing-plan>" );
}

}}   // namespace ctx::landingplan
