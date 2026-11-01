#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_quality.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings
#include <string_view>       // %.*s (precision, pointer) collapses to one view
#include "epmanifest.h"       // D1: collectManifestsAbove — the entry-point targets a setup.cfg / pyproject.toml names (unindexed by the crawl)
#include "infra/sortutil.h"   // svLess: the explicit byte order the test-only name vetting sorts by (portablebuildcheck #6)

// verbs_quality.h — the quality family, moved VERBATIM from main.cpp in the 2026-08-29 split:
// the delta-basis plumbing (noBaselineFatalMessage, loadRefPairDelta, resolveDeltaBasis),
// runQualityDelta, runDmm, the dead-code path filters, runQualityPanel, runQualityViews and
// runEditCheck. Same contract as every verbs_*.h: reopens main.cpp's unnamed namespace — one TU, one
// unnamed namespace, internal linkage unchanged, zero new API surface — under the RIPWIRE_MAIN_TU guard.

namespace
{

// The exit-1 "nothing to compare against" wording for --quality-delta, in one place. Three cases, and the
// distinction is what the w1 verifier caught: saying "no <file>" is TRUE only in the third. A stale sidecar DID
// exist — either it was just dropped by the self-heal, or the unlink failed and it is sitting there right now —
// and `sel.isStaleFileOnDisk()` (the seam's DISK fact, never the removeStaleFile intent) picks which. The
// stale halves mirror the MCP twin's errMsg in mcpverbs.h::computeQualityDelta, per-arm verbs aside; keeping
// this out of runQualityDelta keeps three branches out of a body that is already the file's largest.
std::string noBaselineFatalMessage( const std::string& baselineFile, const rw::quality::BaselineSelection& sel )
{
    // §B12.4 (CA4): the non-stale arm named only the missing sidecar and left out the OTHER half of the
    // condition it is reporting — this message is reached only when the git-HEAD fallback was attempted and
    // ALSO came back empty. Its MCP twin (mcpverbs.h::computeQualityDelta, the "and no git HEAD to
    // auto-compare against" errMsg) has always carried both halves for the identical state, so a CLI reader
    // could not tell the fallback had even been tried and would look for a bug in the sidecar. Same two
    // clauses, same order, same verb-name spelling convention as the stale arms below.
    if( sel.sidecarSymlinkRefused )
    {
        // Round 3 (pathguard.h): "no <file>" is false while a link sits at the name, so say what happened to it.
        return "ripwire: " + baselineFile + " is a symlink, which is refused on read exactly as on write (it was not opened), and there is no git HEAD to auto-compare against — "
               "replace the link with a regular copy of its target, or remove it and run `ripwire <dir> --quality-baseline` BEFORE the change you want to measure\n";
    }
    if( sel.sidecarUnreadable )
    {
        // Same "no <file>" falsehood about a file that is there — reached by every pre-v6 sidecar in a non-git root.
        return "ripwire: " + baselineFile + " exists but is not a readable baseline (unrecognizable, an older sidecar format, or a pre-Q1 sidecar without per-symbol loc "
               "records) and there is no git HEAD to auto-compare against — re-pin it with `ripwire <dir> --quality-baseline` BEFORE the change you want to measure\n";
    }
    if( sel.isSidecarForeign() )
    {
        // The producer rule (quality.h BaselineSource): the file is there and is a real floor, just not this
        // build's — "no <file>" would be false, and so would "delete it", since the build that pinned it may run.
        return "ripwire: " + baselineFile + " was pinned by another ripwire build (its producer stamp does not name this binary's sources, and a dead set depends on how "
               "calls were resolved) and there is no git HEAD to auto-compare against — it was left on disk: run --quality-delta with the build that pinned it, "
               "or re-pin on a clean tree (commit or stash first) with `ripwire <dir> --quality-baseline` BEFORE the change you want to measure\n";
    }
    if( !sel.isSidecarStale() )
    {
        return "ripwire: no " + baselineFile + " and no git HEAD to auto-compare against — run `ripwire <dir> --quality-baseline` BEFORE the change you want to measure\n";
    }

    return "ripwire: " + baselineFile + " was STALE (pinned at a different HEAD) and there is no current HEAD tree to fall back to — "
         + ( sel.isStaleFileOnDisk() ? "it is still on disk (could not be removed): delete it, or re-run `ripwire <dir> --quality-baseline` to re-pin it\n"
                                     : "it has been removed: re-run `ripwire <dir> --quality-baseline` BEFORE the change you want to measure\n" );
}

// ── R-I: --quality-delta=A..B, the WAVE-level form ───────────────────────────────────────────────────────
//
// What two COMMITTED trees leave behind for the comparison: the base tree's snapshot, and the target tree itself with
// its temp-dir teardown bound to the caller's scope. The target stays alive because computeDelta reads it, and reads
// file bytes through its materialized tree. The base tree does not: computeSnapshot is the only reader of it, so
// loadRefPairDelta scores it and releases its index, graph and temp dir before the target is materialized (#387 — both
// indexes together were most of what a 20,000-file repository's run held when the OOM killer took it).
//
// `sameRef` is the A==B case. It is a legal question with an empty answer, and it is answered by materializing
// ONE tree and comparing it with itself rather than by a special-cased early return: the empty delta then
// falls out of the ordinary machinery instead of being asserted by a branch nobody re-tests.
// qd-memory-degrade: a memory-guard stop in one phase of the range form. Recorded, never printed where it happens: the
// form first tries the changed files, and only if those do not fit either does it say anything (refPairStopRefusal).
struct PhaseStop
{
    bool              stopped = false;
    bool              hard    = false;   // the hard line (the limit itself); else a soft stop (soft below)
    std::string       where;             // "ingest of the base commit", "graph of the target commit", …
    rw::MemoryStop    soft;              // a soft stop's cause, copied off the cut ingest
};

struct RefPairDelta
{
    rw::quality::TmpTreeGuard targetGuard;           // declared BEFORE the tree so teardown outlives its use
    rw::quality::RefTree      targetTree;
    rw::quality::Snapshot     baseSnapshot;          // the floor: computeSnapshot over the base tree, which is gone
    bool                  sameRef = false;
    std::string           attrs;                     // XML:  ` base_ref="…" target_ref="…" churn="unavailable"`
    std::string           jsonAttrs;                 // JSON: the SAME three facts — built beside attrs so the
                                                     // two emitters cannot disclose different things
    std::string           rangeSpan;                 // R1: "<baseSha>..<targetSha>" — the range the rename
                                                     // record is read over, against the REAL repo (both trees
                                                     // here are temp dirs with no history of their own)
    // qd-memory-degrade — which kinds this answer runs, and, when the full trees did not fit, what it answers from instead
    rw::quality::KindMask     selected = rw::quality::kAllKinds;   // --quality-kinds (every kind when absent)
    rw::quality::KindMask     kinds    = rw::quality::kAllKinds;   // the kinds actually run: selected, less what the changed files cannot decide
    bool                      degraded = false;                    // answered from both commits' CHANGED files (ingest_scope="changed-files")
    std::string               memoryStop;                          // after a stop: "crawl" | "parse" | "hard"; empty when the projection decided
    bool                      memoryPressure = false;              // the stop was the OS pressure signal
    std::string               stopWhere;                           // the stop's phase, as its sentence names it
    std::uint64_t             needBytes = 0;                       // the projected need (the projection decided and measured it)
    std::uint64_t             ingestNeedBytes = 0;                 // the projection's ingest need (judged against half the limit)
    std::vector<std::string>  baseMacros;                          // the base commit's whole C-family macro-name set, when its full tree was read
    bool                      haveBaseMacros = false;
    std::vector<std::string>  targetFiles;                         // the target commit's files, for --scope's test (degraded + scoped only)
    std::string               baseSha, targetSha;
    PhaseStop                 stop;                                // the guard's stop in a full tree, when there was one
    std::uint64_t             ingestPeak = 0;                      // this process's peak at the end of the base commit's ingest (the projection's input)

    const rw::quality::RefTree& target() const noexcept { return targetTree; }
    const std::vector<std::string>* macroOverride() const noexcept { return degraded && haveBaseMacros ? &baseMacros : nullptr; }
    const std::vector<std::string>* scopeFiles() const noexcept { return degraded ? &targetFiles : nullptr; }
};

// #387: what loadRefPairDelta prints and returns when one commit's tree could not be materialized at all — the environment,
// exit 1, with the sha named. A memory-guard stop is not this: it is a PhaseStop, and the range form falls to the changed
// files (qd-memory-degrade).
int refPairUnavailable( const std::string& sha )
{
    rw::emitTo( stderr, "ripwire: --quality-delta: could not materialize or parse the tree at {}\n", sha.c_str() );
    return 1;
}

// The load outcome of one tree → a PhaseStop, or an exit code for the environment. Loaded = nothing to record.
std::optional<int> recordLoad( rw::quality::RefTreeLoad load, const rw::quality::RefTree& tree, const std::string& sha, std::string_view side, PhaseStop& stop )
{
    using rw::quality::RefTreeLoad;
    if( load == RefTreeLoad::Loaded )
    {
        return std::nullopt;
    }
    if( load == RefTreeLoad::Unavailable )
    {
        return refPairUnavailable( sha );
    }
    stop.stopped = true;
    stop.hard    = load == RefTreeLoad::OverHardLimit;
    stop.where   = "ingest of the " + std::string( side );
    stop.soft    = tree.ing.memoryStop;
    return std::nullopt;
}

// #387: the hard line between the range form's phases. main() checks it after the working-tree ingest and graph build,
// which this form dispatches before, so these are its only readings, in order: after each commit's ingest (loadRefTree,
// before the graph is built) and after its graph; for the base, after its snapshot and again once its index is
// released. Over the line the phase is RECORDED as a stop and nothing is printed (qd-memory-degrade: the changed files
// answer next, and refPairStopRefusal speaks only if they cannot) — where #387's refPairOverHardLimit refused on the spot.
bool hardLineStops( std::string_view phase, PhaseStop& stop )
{
    if( !rw::memguard::overHardLimit() )
    {
        return false;
    }
    stop.stopped = true;
    stop.hard    = true;
    stop.where   = std::string( phase );
    return true;
}

// The one line and exit 5 when the range form cannot answer at all: the stop (or the projection) that sent it to the
// changed files, and why those did not answer either. Every stop recorded so far is answered for by this refusal.
int refPairStopRefusal( const PhaseStop& stop, const RefPairDelta& refs, std::string_view why )
{
    using namespace rw;
    memguard::answerStops();
    DISCLOSE( Diagnostics::answerRefused, "--quality-delta=A..B: the full trees did not fit and the changed files did not answer either — exit 5, one stderr line" );
    if( stop.stopped && stop.hard )
    {
        rw::emitTo( stderr, "ripwire: {}\n", memguard::hardStopLine( stop.where, std::string( why ) + "; " ) );
    }
    else if( stop.stopped )
    {
        rw::emitTo( stderr, "ripwire: the memory guard stopped the {} {} in the {}; --quality-delta=A..B cannot answer from a partial index, and {} — {}\n",
                    memguard::phaseName( stop.soft.phase ), memguard::stopCause( stop.soft ), stop.where, why, memguard::kOverride );
    }
    else
    {
        rw::emitTo( stderr, "ripwire: memory limit {} ({}): the target phase of --quality-delta=A..B was projected to need ~{}; {}; stopped cleanly without an answer — {}\n",
                    memguard::limitSpelling( memguard::limits().hardBytes ), memguard::limitSourceClause(), memguard::limitSpelling( refs.needBytes ), why, memguard::kOverride );
    }
    return 5;
}

// #387: the base commit lives only in this function. Its snapshot is everything the comparison needs from it, so its
// index, graph and temp dir are released on return, before the target tree is materialized. qd-memory-degrade: it also
// keeps the base tree's C-family macro NAMES (defect-shape's one tree-wide input, names only) and reads this process's
// peak at the end of the ingest, for the projection. Exit code on an environment failure; a memory stop goes to `stop`.
std::optional<int> scoreBaseCommit( const std::string& root, const std::string& sha, const rw::Config& cfg, RefPairDelta& refs )
{
    using namespace rw;
    quality::TmpTreeGuard      baseGuard;
    quality::RefTree           baseTree;
    const quality::RefTreeLoad load = quality::loadRefTree( root, sha, cfg.excludes, cfg.maxFileBytes, "qdpair-base", baseGuard, baseTree );
    refs.ingestPeak = os::mem_footprint_peak();
    if( const std::optional<int> failed = recordLoad( load, baseTree, sha, "base commit", refs.stop ) )
    {
        return failed;
    }
    if( refs.stop.stopped || hardLineStops( "graph of the base commit", refs.stop ) )
    {
        return std::nullopt;
    }
    refs.baseSnapshot   = quality::computeSnapshot( baseTree.ing, baseTree.g, baseTree.root, nullptr, { refs.selected } );
    refs.baseMacros     = quality::cFamilyMacroNames( baseTree.ing );
    refs.haveBaseMacros = true;
    (void)hardLineStops( "snapshot of the base commit", refs.stop );
    return std::nullopt;
}

// #387: the target commit, held in `out` for computeDelta. For A==A it is also the floor, so its snapshot is taken here.
std::optional<int> loadTargetCommit( const std::string& root, const std::string& sha, const rw::Config& cfg, RefPairDelta& out )
{
    using namespace rw;
    const quality::RefTreeLoad load = quality::loadRefTree( root, sha, cfg.excludes, cfg.maxFileBytes, "qdpair-target", out.targetGuard, out.targetTree );
    if( const std::optional<int> failed = recordLoad( load, out.targetTree, sha, "target commit", out.stop ) )
    {
        return failed;
    }
    if( out.stop.stopped || hardLineStops( "graph of the target commit", out.stop ) )
    {
        return std::nullopt;
    }
    if( out.sameRef )
    {
        out.baseSnapshot = quality::computeSnapshot( out.targetTree.ing, out.targetTree.g, out.targetTree.root, nullptr, { out.selected } );
        (void)hardLineStops( "snapshot of the base commit", out.stop );
    }
    return std::nullopt;
}

// review C1: the degraded line's last clause — the kinds memory skipped, or, when it skipped none (a selector of kinds
// the changed files decide), that every selected kind ran: never an empty "skipped" list
std::string memorySkippedClause( rw::quality::KindMask memorySkipped )
{
    return memorySkipped != 0 ? "; skipped " + rw::quality::kindList( memorySkipped, ", " ) : std::string( "; every selected kind ran" );
}

// qd-memory-degrade — the stderr line of a degraded answer: the limit, why the full trees were not read, the kinds it
// skipped, the replay. One line, beside the gating line, so a caller reading only $? and stderr knows the answer is partial.
std::string degradedStderrLine( const RefPairDelta& refs, rw::quality::KindMask memorySkipped, std::string_view kindsNext )
{
    using namespace rw;
    const std::uint64_t limit = memguard::limits().hardBytes;
    std::string why = refs.memoryStop.empty()
                    ? "the target phase was projected to need ~" + memguard::limitSpelling( refs.needBytes )
                    : refs.memoryStop == "hard" ? "the memory limit was reached during the " + refs.stopWhere + "; the full need was not measured"
                    : "the memory guard stopped the " + refs.stopWhere + ( refs.memoryPressure ? " under critical system memory pressure" : "" ) + "; the full need was not measured";
    std::string line = "memory limit " + ( limit == 0 ? std::string( "unknown" ) : memguard::limitSpelling( limit ) ) + " (" + std::string( memguard::limitSourceClause() )
                     + "): --quality-delta=A..B answered from the changed files only (" + why + ")" + memorySkippedClause( memorySkipped );
    if( !kindsNext.empty() )
    {
        line += " — run them with " + std::string( kindsNext );
        if( refs.memoryStop.empty() )
        {
            const std::uint64_t machine = memguard::machineMemoryBytes();
            if( machine != 0 && refs.needBytes >= machine )
            {
                line += " (more than this machine's " + memguard::limitSpelling( machine ) + ": recoverable only on a larger machine)";
            }
        }
        else
        {
            line += " (its --max-memory is a guess, twice the limit: no need was measured)";
        }
    }
    return line;
}

// qd-memory-degrade — THE CHANGED-FILES ANSWER. The full trees are gone (released, or never read); both commits' changed
// files are ingested alone (never through a cache) and the base snapshot is taken from the base's. A kind runs here only
// if its rows are decided by those files: the LOCAL kinds always, defect-shape when the changed files define the same
// C-family macro names on both sides (then the tree's set is unchanged) and either the base's whole set was read or no
// changed file is C++ (the only scanner that reads it). Exit code on a refusal; nullopt when `out` is ready.
std::optional<int> loadChangedFiles( const std::string& root, const rw::Config& cfg, RefPairDelta& out, const PhaseStop& stop )
{
    using namespace rw;
    if( cfg.qualityAck )
    {
        return refPairStopRefusal( stop, out, "--quality-ack needs every kind's rows, so nothing was acked (the ledger is untouched)" );
    }
    out.kinds = out.selected & static_cast<quality::KindMask>( ~quality::kWholeTreeKinds );
    if( out.kinds == 0 )
    {
        return refPairStopRefusal( stop, out, "the selected kinds are whole-tree kinds, which the changed files cannot decide" );
    }
    if( memguard::overHardLimit() )
    {
        // the footprint still held after the full tree was released (on macOS the allocator keeps its pages): nothing of
        // the changed files was ingested, so the line says they were not tried — never that they did not fit
        return refPairStopRefusal( stop, out, "this process still held more than the limit after releasing the full tree, so the changed files were not tried" );
    }
    quality::ChangedFiles changed = quality::changedFilesBetween( root, out.baseSha, out.targetSha, !cfg.qualityScope.empty() );
    if( !changed.ok )
    {
        memguard::answerStops();
        rw::emitTo( stderr, "ripwire: --quality-delta={}..{}: the full trees did not fit the memory limit, and git could not list the changed files to answer from\n",
                    out.baseSha.c_str(), out.targetSha.c_str() );
        return 1;
    }
    if( !changed.refusal.empty() )
    {
        return refPairStopRefusal( stop, out, "the changed files cannot stand in for the trees: " + changed.refusal );
    }
    PhaseStop             subsetStop;
    quality::TmpTreeGuard baseGuard;
    quality::RefTree      baseTree;
    quality::RefTreeLoad  load = quality::loadRefSubset( root, out.baseSha, changed.base, cfg.excludes, cfg.maxFileBytes, "qdpair-base-changed", baseGuard, baseTree );
    if( const std::optional<int> failed = recordLoad( load, baseTree, out.baseSha, "changed files of the base commit", subsetStop ) )
    {
        return failed;
    }
    load = subsetStop.stopped ? quality::RefTreeLoad::Loaded
                              : quality::loadRefSubset( root, out.targetSha, changed.target, cfg.excludes, cfg.maxFileBytes, "qdpair-target-changed", out.targetGuard, out.targetTree );
    if( const std::optional<int> failed = recordLoad( load, out.targetTree, out.targetSha, "changed files of the target commit", subsetStop ) )
    {
        return failed;
    }
    if( subsetStop.stopped )
    {
        return refPairStopRefusal( subsetStop, out, "the changed files alone were cut too" );
    }
    // defect-shape's one tree-wide input (see the header comment of this function)
    const std::vector<std::string> baseChanged   = quality::cFamilyMacroNames( baseTree.ing );
    const std::vector<std::string> targetChanged = quality::cFamilyMacroNames( out.targetTree.ing );
    const auto anyCpp = []( const IngestResult& ing ) { return std::any_of( ing.files.begin(), ing.files.end(), []( const std::string& f ) { return langFacts( langOfPath( f ) ).defectShapeNeedsMacroSet; } ); };
    if( baseChanged != targetChanged || ( !out.haveBaseMacros && ( anyCpp( baseTree.ing ) || anyCpp( out.targetTree.ing ) ) ) )
    {
        out.kinds &= static_cast<quality::KindMask>( ~quality::kindBit( "defect-shape" ) );
    }
    if( out.kinds == 0 )   // the selection was defect-shape (with whole-tree kinds) and the changed files cannot decide it: never an empty pass
    {
        return refPairStopRefusal( stop, out, "the selected kinds need the whole tree (defect-shape too: the changed files' C-family macro names differ, or a C++ file changed without the base's whole set)" );
    }
    out.degraded     = true;
    out.baseSnapshot = quality::computeSnapshot( baseTree.ing, baseTree.g, baseTree.root, nullptr, { out.kinds, out.macroOverride() } );
    if( !cfg.qualityScope.empty() )
    {
        out.targetFiles = std::move( changed.targetTree );
    }
    out.memoryStop     = !stop.stopped ? std::string() : stop.hard ? std::string( "hard" ) : std::string( memguard::phaseName( stop.soft.phase ) );
    out.memoryPressure = stop.stopped && !stop.hard && stop.soft.byPressure;
    out.stopWhere      = stop.stopped ? ( stop.hard ? stop.where : std::string( memguard::phaseName( stop.soft.phase ) ) + " of the " + stop.where.substr( stop.where.find( "the " ) + 4 ) ) : std::string();
    memguard::answerStops();   // the degraded answer answers for the stop that sent it here
    return std::nullopt;
}

// qd-memory-degrade: the two full trees, as #387 reads them — the base scored and released, then the target — with the
// projection between them. A stop in either is recorded in out.stop; `projectedNoFit` says the projection chose the
// changed files before the target was read. The projection is asked only when the changed files could answer a selected
// kind for certain: a selection of whole-tree kinds (with or without defect-shape, which the changed files may not
// decide) gains nothing from pre-empting the full attempt — that is the replay kinds_next= names, and it runs in full,
// refused only by a real stop. Exit code on an environment failure only.
std::optional<int> loadFullTrees( const std::string& root, const rw::Config& cfg, RefPairDelta& out, bool& projectedNoFit )
{
    using namespace rw;
    // --quality-ack needs every kind's rows, which the changed files never give: like a whole-tree selection it is never
    // pre-empted by the projection, and only a real stop refuses it (review C2: base acked within the cap, head refused)
    const quality::KindMask certainLocal = cfg.qualityAck ? quality::KindMask( 0 )
                                         : static_cast<quality::KindMask>( out.selected & ~( quality::kWholeTreeKinds | quality::kindBit( "defect-shape" ) ) );
    if( !out.sameRef )
    {
        const std::uint64_t before = os::mem_footprint();
        if( const std::optional<int> failed = scoreBaseCommit( root, out.baseSha, cfg, out ) )
        {
            return failed;
        }
        // #387: the base tree's index, graph and temp dir were released when scoreBaseCommit returned.
        if( out.stop.stopped || hardLineStops( "base commit's snapshot, with its index released", out.stop ) || certainLocal == 0 )
        {
            return out.stop.stopped ? std::nullopt : loadTargetCommit( root, out.targetSha, cfg, out );
        }
        const std::uint64_t              basePeak = os::mem_footprint_peak();
        const std::uint64_t              after    = memguard::measuredFootprint();
        const memguard::TargetProjection proj     = memguard::projectTargetPhase( before, out.ingestPeak, basePeak, after );
        out.needBytes       = proj.needBytes;
        out.ingestNeedBytes = proj.ingestNeedBytes;
        projectedNoFit = !proj.fits;
        if( std::getenv( "RIPWIRE_STATS" ) )   // the projection's own readings, the calibration's instrument (kProjectionScalePct)
        {
            rw::emitTo( stderr, "ripwire: memory-projection before={} ingest_peak={} base_peak={} after={} need={} measured={} fits={}\n",
                        memguard::limitSpelling( before ), memguard::limitSpelling( out.ingestPeak ), memguard::limitSpelling( basePeak ),
                        memguard::limitSpelling( after ), memguard::limitSpelling( proj.needBytes ), proj.measured ? 1 : 0, proj.fits ? 1 : 0 );
        }
        if( projectedNoFit )
        {
            return std::nullopt;
        }
    }
    return loadTargetCommit( root, out.targetSha, cfg, out );
}

// A cut target is never scored: its index, graph and temp dir go before the changed files are read, and so does the full
// base snapshot (the changed files' own base snapshot replaces it).
void releaseFullTrees( RefPairDelta& out )
{
    out.targetTree   = {};
    out.baseSnapshot = {};
    rw::quality::TmpTreeGuard dropped;
    std::swap( dropped.p, out.targetGuard.p );   // its destructor removes the cut tree's temp dir now
}

// Resolve the spec and materialize both sides. Returns an EXIT CODE on any refusal or environment failure
// (already reported on stderr), or nullopt when `out` is ready to compare. Splitting user error from
// environment failure is the same line --dmm's handler draws: a revision that does not resolve is a typo the
// caller can fix, everything else is the machine.
//
// qd-memory-degrade — THE LADDER. Full trees first, exactly as before, so a run that fits is the run it always was. A
// memory-guard stop in either commit's full tree (a soft crawl/parse stop or the hard line), or a projection after the
// base phase that says the target phase will not fit, releases what was loaded and answers from both commits' changed
// files instead (loadChangedFiles); exit 5 only when those do not fit or cannot stand in for the trees.
std::optional<int> loadRefPairDelta( const std::string& root, std::string_view spec, const rw::Config& cfg, RefPairDelta& out )
{
    using namespace rw;

    const quality::RefSpec ref = quality::resolveRefSpec( root, spec );
    switch( ref.status )
    {
        case quality::RefSpecStatus::BadRev:
            // The did-you-mean here cannot be a spelling neighbourhood — git already owns the ref namespace and
            // has no cheap enumeration of it — so the adjacent help names the PROBE and the three causes that
            // actually produce this on an agent's machine, which is more use than a guessed nearest ref.
            // 0.6.7: the cause list below GUESSES; on a depth-limited clone the probe KNOWS, so the first line names it
            // (gitstamp::shallowRefHint — the same sentence pr-context and merge-scout print; "" on a full clone).
            rw::emitTo( stderr, "ripwire: --quality-delta: '{}' does not resolve to a commit in {}{}\n"
                                  "  check it with `git -C {} rev-parse --verify {}^{{commit}}`; the usual causes are a typo, a ref that\n"
                                  "  lives only on a remote you have not fetched, or a shallow clone whose history stops before it\n",
                          ref.badToken.c_str(), root.c_str(), rw::gitstamp::shallowRefHint( root ), root.c_str(), ref.badToken.c_str() );
            return 1;
        case quality::RefSpecStatus::BadRange:
            rw::emitTo( stderr, "ripwire: --quality-delta: '{}' uses the three-dot form; this compares two TREES, so spell it A..B "
                                  "(or --quality-delta=$(git merge-base A B)..B if the merge base is what you meant)\n", ref.badToken.c_str() );
            return 1;
        case quality::RefSpecStatus::NoGit:
        case quality::RefSpecStatus::NoParent:
            // Environment, not a typo — and unlike --dmm (a measurement that reports UNAVAILABLE and exits 0)
            // this verb has nothing to report at all, so it takes the same exit 1 the bare form's
            // "nothing to compare against" path takes.
            rw::emitTo( stderr, "ripwire: --quality-delta={}: {}\n", std::string_view( spec.data(), spec.size() ), ref.reason.c_str() );
            return 1;
        case quality::RefSpecStatus::Ok:
            break;
    }
    // resolveRefSpec only reports Ok for the working-tree form on an EMPTY spec, which the flag table refuses
    // before it reaches here; the guard is belt-and-braces so a future grammar change cannot silently compare
    // a materialized tree against a working tree whose keys are spelled against a different root.
    if( ref.targetIsWorkingTree || ref.baseSha.empty() || ref.targetSha.empty() )
    {
        rw::emitRaw( stderr, "ripwire: --quality-delta needs TWO commits (A..B); use the bare --quality-delta for the working tree\n" );
        return 1;
    }
    out.baseSha   = ref.baseSha;
    out.targetSha = ref.targetSha;
    out.kinds     = out.selected;

    // DISTINCT tags — see quality::loadRefTree's header. The base tree is gone before the target is extracted, but
    // a shared tag would still let one side's extraction delete the other's directory if that order ever changed.
    out.sameRef = ( ref.baseSha == ref.targetSha );
    bool projectedNoFit = false;
    if( const std::optional<int> failed = loadFullTrees( root, cfg, out, projectedNoFit ) )
    {
        return failed;
    }
    if( out.stop.stopped || projectedNoFit )
    {
        releaseFullTrees( out );
        if( const std::optional<int> refused = loadChangedFiles( root, cfg, out, out.stop ) )
        {
            return refused;
        }
    }

    // Both values are bare 40-char object names straight out of `rev-parse --verify` (resolveRefSpec accepts
    // nothing else), so they carry no XML-significant byte and are spliced rather than escaped — the same
    // reasoning gitstamp::atAttr states for its own hex value.
    out.attrs     = " base_ref=\"" + ref.baseSha + "\" target_ref=\"" + ref.targetSha + "\" churn=\"unavailable\"";
    out.jsonAttrs = ",\"base_ref\":\"" + ref.baseSha + "\",\"target_ref\":\"" + ref.targetSha + "\",\"churn\":\"unavailable\"";
    // R1: the same two resolved shas as a range, for the rename record. Empty when the target IS the working
    // tree — `A..` is not a range git will walk, and the working-tree form's own uncommitted+window query is
    // the right scope there anyway.
    out.rangeSpan = ref.targetSha.empty() ? std::string{} : ( ref.baseSha + ".." + ref.targetSha );
    return std::nullopt;
}

// WHAT this delta is measured AGAINST, and on WHICH tree — the one place --quality-delta decides that.
// Extracted from runQualityDelta when the ref-pair form landed: floor selection was previously a single
// straight-line arm inside that body, and adding a second, differently-shaped floor turned it into the kind
// of branch pile the verb itself measures (runQualityDelta's own complexity crossed the bar on this lane's
// --quality-delta before this extraction). Everything downstream — acks, counters, both emitters, the exit
// code — reads these three fields and does not care which floor produced them.
//
// `deltaRoot` is WHICH SIDE was judged, and every root-relative key and displayed symbol downstream is
// spelled against it rather than against the repo root. In the ref-pair form the judged tree is a
// materialized temp dir: its keys must match the floor tree's key-for-key (S2), and its PID-suffixed path
// must never reach stdout — a temp path in the output would make two runs of the same comparison differ
// byte for byte, which is a determinism bug even when every finding is correct.
struct DeltaBasis
{
    rw::quality::BaselineSelection       baseSel;
    std::vector<rw::quality::Regression> regs;
    std::string                          deltaRoot;   // see above — NOT interchangeable with the repo root
    // R1 IDENTITY — the ack ledger, plus the healing pre-pass that re-files BOTH sidecars into the identity
    // the current tree uses (quality::healIdentity). The ledger is read HERE, before computeDelta, because
    // the healing needs both sidecars at once and has to run before anything reads either: heal the baseline
    // after the delta is computed and the delta has already been taken against the stale identity.
    gtl::btree_map<std::string, rw::quality::AckRecord> acks;
    rw::quality::IdentityHealing                        healing;
    std::size_t                                         registerMacroExcluded = 0;   // P2.2: disclosed dead-code exemption count
    std::size_t                                         declinedCallExcluded  = 0;   // dead-code exemption by a declined call (quality.h isDeadCandidate)
    std::size_t                                         valueRefExcluded      = 0;   // dead-code exemption: held as a VALUE (valuerefindex.h)
    std::size_t                                         apiNewSurface         = 0;   // Q-DIAL-4: new PUBLIC symbols this change added — the count that replaced one never-gating row each
    std::size_t acksBadLines = 0;   // 2026-09-06: .ripwire_quality_acks lines skipped as unparseable (disclosed on the root)
    bool        ackHealingSkipped = false;   // qd-memory-degrade: a changed-files answer with a non-empty ledger (also_skipped ack-healing)
    // #228: WHICH basis produced baseSel.snapshot when the marker is one of the git-HEAD family, and WHY when
    // the fast one was refused for a reason the caller can act on. nullptr = the attribute is absent, which is
    // the ordinary archived comparison every git-HEAD marker has always meant. See quality::HeadBasis.
    const char* headBasis = nullptr;
    // Every CURRENT-tree clone group's (member-set hash, idiom verdict) — computeDelta already had both in
    // hand, so this is a copy rather than a second clone pass. Consumed ONLY by the legacy-ack backfill
    // (quality::backfillCloneAckProvenance) on the --quality-ack path; a read-only --quality-delta fills it
    // and never looks at it, which keeps the two runs' reported findings identical.
    std::vector<rw::quality::CloneIdiomFact> cloneIdioms;
};

// The REF-PAIR floor's comparison, once loadRefPairDelta has both sides: the base snapshot is the floor, tree B the judged
// tree, the ledger healed against it, the delta taken.
void refPairBasis( const rw::Config& cfg, const std::string& root, RefPairDelta& refs, DeltaBasis& out )
{
    using namespace rw;
    out.baseSel.snapshot = std::move( refs.baseSnapshot );
    out.baseSel.marker   = "ref-pair";
    out.deltaRoot        = refs.target().root;
    // R1 IDENTITY. The SPAN is what makes this honest here: both trees are materialized OUT of the repo
    // into temp dirs, so asking them about renames answers "not a git repo" — the renames are recorded in
    // the REAL repo, over exactly the range this comparison is about. `root` (the repo) supplies the
    // record; `refs.rangeSpan` scopes it to the pair. Everything else is identical to the working-tree
    // form, which is the point of having one healIdentity.
    // qd-memory-degrade: over the changed files the two tree-wide rescues are skipped (healIdentity's header) — said
    // as also_skipped ack-healing when the ledger holds any row they could have re-filed. The clone-idiom export is
    // asked for only where it is read (the --quality-ack backfill), so a kind selection without the clone kinds skips
    // the clone passes.
    out.acks              = quality::readAckRecords( quality::acksPath( root ) );
    out.ackHealingSkipped = refs.degraded && !out.acks.empty();
    out.healing = quality::healIdentity( out.baseSel.snapshot, out.acks, refs.target().ing, refs.target().g,
                                         out.deltaRoot, root, cfg.qualityAck, refs.rangeSpan, /*treeWideRescues=*/!refs.degraded );
    out.regs    = quality::computeDelta( refs.target().ing, refs.target().g, out.baseSel.snapshot,
                                         out.deltaRoot, cfg.excludes, cfg.maxFileBytes, &out.registerMacroExcluded, &out.apiNewSurface,
                                         cfg.qualityAck ? &out.cloneIdioms : nullptr, &out.declinedCallExcluded, &out.valueRefExcluded,
                                         quality::KindScope{ refs.kinds, refs.macroOverride() } );
}

// Returns an EXIT CODE when there is nothing to compare against (already reported), nullopt when `out` holds
// a usable comparison. `refs` is the CALLER's because it owns the materialized trees' teardown, and those
// trees must outlive every read of `out.regs`.
std::optional<int> resolveDeltaBasis( const MainDispatch& d, const std::string& baselineFile,
                                      RefPairDelta& refs, DeltaBasis& out )
{
    using namespace rw;
    const Config&       cfg  = d.cfg;
    const std::string&  root = d.root;

    // ── the REF-PAIR floor: two COMMITTED trees, neither of them the working tree ─────────────────────────
    if( !cfg.qualityDeltaRange.empty() )
    {
        if( const std::optional<int> refused = loadRefPairDelta( root, cfg.qualityDeltaRange, cfg, refs ) )
        {
            return refused;
        }
        // No sidecar is read, written or DELETED by this form. Deliberate, and disclosed in --help: the
        // sidecar's whole contract is "pinned at the current HEAD", which says nothing about a pair of
        // arbitrary commits — and the bare form's self-heal deleting a user's pinned floor as a side effect
        // of a wave-level measurement would be a side effect nobody asked for.
        refPairBasis( cfg, root, refs, out );
        return std::nullopt;
    }

    // ── the WORKING-TREE floors, unchanged ───────────────────────────────────────────────────────────────
    // Precedence: (1) an explicit `.ripwire_quality_baseline` sidecar (from --quality-baseline) wins whenever
    // it is pinned at the CURRENT HEAD — the mid-task convergence loop (baseline once, edit, re-check) is
    // unchanged; (2) else — no sidecar, or a STALE one (see R3 below) — if the root is a git repo with a HEAD
    // tree, auto-baseline against HEAD so the "before I push" loop works with no start-of-task ritual (T0.1);
    // (3) else degrade to the exit-1 "run --quality-baseline first" guidance (non-git / unborn /
    // detached-no-tree — unchanged).
    //
    // STALENESS + the self-heal live in ONE place, quality::selectBaseline — R3 owner ruling (2026-07-29): a
    // sidecar whose pinned sha != the CURRENT HEAD sha is STALE, full stop. The B10.1b "reachable ancestor is
    // a deliberately-pinned floor" carve-out this arm used to apply (gitIsAncestor) is REVOKED: a parallel
    // session's sidecar pinned at a commit that merely happened to be an ancestor of this session's HEAD made
    // THIS arm report 31 phantom regressions while the MCP quality_delta verb — same binary, same repo, same
    // second — correctly reported zero. That divergence was only possible because each arm carried its own
    // copy of the test; there is now exactly one, in quality.h.
    //
    // What remains this arm's own POLICY is the `removeStaleFile=true` argument: the stale sidecar is silently
    // UNLINKED (best-effort) so the NEXT run sees no file at all rather than rediscovering the same dead pin,
    // and the ONLY record is the `baseline=` XML attribute ("git-HEAD (stale sidecar removed)") — no stderr
    // spam, which is the B10.1b noise fix that survives the ruling intact. The read-only MCP arm passes false
    // and reports "…ignored" instead. When the unlink FAILS (read-only parent dir) this arm degrades to the
    // read-only story — marker "…ignored", one DISCLOSE from the seam — because the pin is still
    // on disk; `isStaleFileOnDisk()` is the fact, and the fatal message words itself from it, not the intent.
    out.deltaRoot = std::string( cfg.rootPath );
    out.baseSel   = quality::selectBaseline( root, baselineFile, /*removeStaleFile=*/true );
    if( !out.baseSel.isSidecarHonored() )
    {
        // #228 part 1 — the IDENTITY BASIS (quality.h): when the tracked tree already IS HEAD, the baseline is
        // this tree's own snapshot, so a no-op diff is empty by construction instead of by luck. Falls back to
        // the archived HEAD snapshot on any modified tree, unchanged.
        quality::HeadBasis basis = quality::computeHeadBasis( root, d.ing, d.g, cfg.rootPath, cfg.maxFileBytes, cfg.excludes );
        if( !basis.ok )
        {
            // w1 MED: this used to say "no <file>" in BOTH cases — factually false when the file is a STALE
            // sidecar that was just dropped, and doubly so when the self-heal unlink FAILED and the thing is
            // still sitting on disk. The stale-aware wording (and the MCP twin it mirrors) lives in
            // noBaselineFatalMessage above. Exit code is unchanged (1) in every branch.
            std::fputs( noBaselineFatalMessage( baselineFile, out.baseSel ).c_str(), stderr );
            return 1;
        }
        out.baseSel.snapshot   = std::move( basis.snapshot );
        out.headBasis          = basis.basis;
        if( basis.notAtHead != 0 )
        {
            // The basis is stated where it is not the obvious one: these files are in the tree and in the graph,
            // so they shape every verdict, but HEAD does not hold them and the baseline therefore does not
            // either — their own symbols read as new, exactly as they do against an archived HEAD.
            rw::emitTo( stderr, "ripwire: {} indexed file(s) are not tracked at HEAD — their symbols are judged as NEW; tracked symbols are compared "
                                  "with HEAD's own content in this same tree\n", basis.notAtHead );
        }
        if( out.baseSel.sidecarUnreadable )
        {
            // 2026-09-06 stranger audit: this used to print "no <file>" about a file sitting on disk.
            rw::emitTo( stderr, "ripwire: {} exists but is not a readable baseline (unrecognizable, an older sidecar format, or a pre-Q1 sidecar without per-symbol loc records) — IGNORED; "
                                  "auto-comparing the working tree vs git HEAD; re-pin it with --quality-baseline\n", baselineFile.c_str() );
        }
        else if( out.baseSel.isSidecarForeign() )
        {
            // Said on stderr like the unreadable case above and unlike the stale one: a stale pin is removed, so its
            // silence costs one run, while a foreign pin stays on disk and is ignored on every run until re-pinned.
            rw::emitTo( stderr, "ripwire: {} was pinned by another ripwire build (its producer stamp does not name this binary's sources, and a dead set depends on how "
                                  "calls were resolved) — IGNORED and left on disk; auto-comparing the working tree vs git HEAD; run --quality-delta with the build that "
                                  "pinned it, or re-pin on a clean tree (commit or stash first) with --quality-baseline\n", baselineFile.c_str() );
        }
        else if( !out.baseSel.isSidecarStale() && !out.baseSel.sidecarSymlinkRefused )
        { // the stale/healed case is silent by design — only the true "never baselined" case is informative. A refused
          // link (pathguard.h round 3) is not "never baselined" either, and pathguard has already said why on stderr.
            rw::emitTo( stderr, "ripwire: no {} — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)\n",
                          baselineFile.c_str() );
        }
    }
    // R1 IDENTITY — heal both sidecars into the current tree's identity BEFORE the delta is taken against
    // them. One root here: the judged tree and the git record are the same directory in this form.
    out.acks    = quality::readAckRecords( quality::acksPath( root ), out.acksBadLines );
    out.healing = quality::healIdentity( out.baseSel.snapshot, out.acks, d.ing, d.g,
                                         std::string( cfg.rootPath ), root, cfg.qualityAck );
    out.regs = quality::computeDelta( d.ing, d.g, out.baseSel.snapshot, cfg.rootPath, cfg.excludes, cfg.maxFileBytes, &out.registerMacroExcluded, &out.apiNewSurface,
                                      &out.cloneIdioms, &out.declinedCallExcluded, &out.valueRefExcluded );
    return std::nullopt;
}

// P1.2 — expand the reserved `diff` token into one literal path pattern per changed INDEXED file. It lives
// in the verb because reading git is the verb's job and quality::Scope is a pure value; and it runs BEFORE
// refuseUnusableScope, so the expanded set is what the "names nothing indexed" test sees.
//
// THREE refusals, all of the same shape and for the same reason — under a scope, a silent zero reads as
// "you're clean", which is the most dangerous sentence this verb can say.
std::optional<int> expandScopeDiff( rw::quality::Scope& scope, bool refPair, const rw::IngestResult& judged,
                                    const std::string& root, std::string_view deltaRoot, std::size_t& diffFileCount )
{
    if( !rw::quality::scopeUsesDiffToken( scope ) || !rw::quality::scopeSpecIsSpellable( scope.spec ) )
    {
        return std::nullopt;   // not our token, or a spec refuseUnusableScope is about to refuse anyway
    }
    if( refPair )
    {
        // The token names the WORKING TREE's changes, and this form compares two committed trees — the
        // working tree is not part of the comparison at all, so the answer would describe a different tree
        // than the one being judged.
        rw::emitRaw( stderr, "ripwire: --scope=diff scopes to the WORKING TREE's changes, but --quality-delta=A..B compares two COMMITTED trees —\n"
                              "  spell the scope as paths there (e.g. --scope=src/quality.h), or drop the range to measure the working tree\n" );
        return 1;
    }
    std::vector<char> changed( judged.files.size(), 0 );
    if( !rw::gitChangedFiles( root, judged, changed ) )
    {
        rw::emitTo( stderr, "ripwire: --scope=diff needs git to say what changed, and {} is not a readable git repository —\n"
                              "  name the paths instead (e.g. --scope=src/quality.h,src/verbs_quality.h)\n", root.c_str() );
        return 1;
    }
    std::vector<std::string> expanded;
    for( const std::string& p : scope.patterns )
    {
        if( p != rw::quality::kScopeDiffToken )
        {
            expanded.push_back( p );   // the token composes by UNION with any literal patterns beside it
        }
    }
    for( std::size_t fileIndex = 0; fileIndex < changed.size(); ++fileIndex )
    {
        if( changed[ fileIndex ] )
        {
            expanded.emplace_back( rw::relForHash( judged.files[ fileIndex ], deltaRoot ) );
            ++diffFileCount;
        }
    }
    if( diffFileCount == 0 )
    {
        rw::emitRaw( stderr, "ripwire: --scope=diff expanded to NO changed indexed file — the working tree matches the baseline (or the edits are in files\n"
                              "  this index does not carry), so the scope owns nothing and an exit 0 under it would say nothing about your change\n" );
        return 1;
    }
    std::sort( expanded.begin(), expanded.end() );
    expanded.erase( std::unique( expanded.begin(), expanded.end() ), expanded.end() );
    scope.patterns.swap( expanded );
    return std::nullopt;
}

// P1 — the scope flag's two REFUSALS, in their own symbol. They live in the verb rather than in cli.h for
// the reason --quality-panel=PRESET's refusal does: the vocabulary belongs to quality.h, and cli.h is a leaf
// that includes only ingest.h. Returns an exit code (already reported on stderr) or nullopt when the scope
// is usable. `judged` is the tree the findings were taken from — the working tree, or tree B in the
// ref-pair form — because "names nothing indexed" has to be asked of the corpus that was actually measured.
// `commitFiles` (qd-memory-degrade): a changed-files answer indexed only the changed files, so a scope naming an UNCHANGED
// file is not a typo there — the test reads the target commit's whole file list instead (its root-relative paths).
std::optional<int> refuseUnusableScope( const rw::Config& cfg, const rw::quality::Scope& scope,
                                        const rw::IngestResult& judged, std::string_view deltaRoot,
                                        const std::vector<std::string>* commitFiles = nullptr )
{
    if( !scope.active() )
    {
        return std::nullopt;
    }
    if( !rw::quality::scopeSpecIsSpellable( cfg.qualityScope ) )
    {
        // The spec is recorded VERBATIM as a whitespace-delimited by= token in the ack ledger and echoed into
        // an XML attribute. A pattern that cannot round-trip through both is refused here rather than mangled
        // at the emitter: matching against something the caller never typed is the one outcome worse than
        // not matching at all.
        rw::emitTo( stderr, "ripwire: --scope={} contains whitespace or an XML metacharacter — a scope is recorded verbatim in the ack ledger and in the report,\n"
                              "  so each pattern must be spellable as one token (e.g. --scope=src/quality.h,src/verbs_quality.h)\n", std::string_view( cfg.qualityScope.data(), cfg.qualityScope.size() ) );
        return 1;
    }
    // A scope that names nothing INDEXED is a typo, not a measurement — and a typo here reads as "you're
    // clean", which is the single most dangerous thing this verb can say. Refuse loudly, the same ruling
    // --dead-code=DIR already carries.
    for( const std::string& indexedPath : judged.files )
    {
        if( scope.matchesPath( rw::relForHash( indexedPath, deltaRoot ) ) )
        {
            return std::nullopt;
        }
    }
    if( commitFiles != nullptr && std::any_of( commitFiles->begin(), commitFiles->end(), [ & ]( const std::string& p ) { return scope.matchesPath( p ); } ) )
    {
        return std::nullopt;
    }
    rw::emitTo( stderr, "ripwire: --scope={} matches no indexed path — an exit 0 under a scope that owns nothing is a failure, not a clean tree\n"
                          "  (patterns are matched ROOT-RELATIVE, the same spelling p= prints: --scope=src or --scope=src/quality.h, not an absolute path)\n", std::string_view( cfg.qualityScope.data(), cfg.qualityScope.size() ) );
    return 1;
}

// P1 — the partition itself: move every finding the scope does not cover into `outOfScope`, and return how
// many of the disclosed rows WOULD have gated. Called before the in-scope ratchet so acked= counts this
// scope's suppressions rather than the whole tree's.
//
// F-05 fix (audit 2026-09-02, item 2): this USED to ack-ratchet outOfScope too ("a sibling's ALREADY-ACKED
// row is answered over there, so disclosing it again would be noise") — but kScopeLegend promises the
// out-of-scope element is "not dropped: … every one of them is printed", unconditionally, and an ack
// written by ANYONE (not just the row's own owner — applyAckRatchet does not check by= at all) made a row
// vanish from that element entirely: a sibling's exclusive debt, acked once under its OWN scope for an
// unrelated reason, silently stopped being disclosed to every other scope's report. Confirmed live: acking
// two of an owner's four exclusive findings under --scope=alpha made a LATER --scope=beta run's
// <out-of-scope> show zero of that owner's rows instead of the two still-unacked, non-straddling ones.
// Disclosure is now unconditional — outOfScope keeps every row the scope does not cover, acked or not.
// wouldGate stays ack-aware (an already-acked row would not have gated even inside its owner's own scope),
// computed via findSuppressingAck so nothing is removed from what gets printed.
std::size_t partitionByScope( const rw::quality::Scope& scope, std::vector<rw::quality::Regression>& regs,
                              std::vector<rw::quality::Regression>& outOfScope,
                              const gtl::btree_map<std::string, rw::quality::AckRecord>& acks )
{
    ASSUME_NO_ALIAS( regs, outOfScope );   // push_back into outOfScope while iterating regs: the same vector twice is UB
    if( !scope.active() )
    {
        return 0;
    }
    std::vector<rw::quality::Regression> mine;
    mine.reserve( regs.size() );
    for( rw::quality::Regression& r : regs )
    {
        ( rw::quality::scopeCovers( scope, r ) ? mine : outOfScope ).push_back( std::move( r ) );
    }
    regs.swap( mine );
    std::size_t wouldGate = 0;
    for( const rw::quality::Regression& r : outOfScope )
    {
        if( !rw::quality::rowGates( r ) )
        {
            continue;
        }
        if( rw::quality::findSuppressingAck( r, acks ) != nullptr )
        {
            continue;   // acked (by whoever) — would not have gated even in its own scope
        }
        ++wouldGate;
    }
    return wouldGate;
}

// P1 — THE RUBBER-STAMP GUARD, in its own symbol because it is the point of the whole flag. Under a scope an
// out-of-scope finding is not in the ack SELECTION at all: there is no spelling of --quality-ack that writes
// one. That leaves exactly one case worth a hard refusal rather than a silent skip — an --ack-only pattern
// that NAMES a row belonging to someone else. It is the difference between "the flag narrowed what I
// accepted" and "I asked for that row and did not get it", so the whole ack is refused, nothing is written,
// and the rows are named. `selected` is the caller's ack predicate, passed rather than rebuilt so the two
// sites can never disagree about what a pattern selects.
template<typename Selector>
std::optional<int> refuseForeignAckSelection( const rw::Config& cfg, const rw::quality::Scope& scope,
                                              const std::vector<rw::quality::Regression>& outOfScope,
                                              std::string_view deltaRoot, Selector&& selected )
{
    if( !scope.active() || cfg.qualityAckOnly.empty() )
    {
        return std::nullopt;
    }
    std::string named;
    std::size_t namedCount = 0;
    for( const rw::quality::Regression& r : outOfScope )
    {
        if( !selected( r, /*inScope=*/false ) )
        {
            continue;
        }
        ++namedCount;
        if( namedCount <= 8 )   // a listing, not a dump: the count in the sentence above it is the total
        {
            named += "\n    " + r.kind + " " + rw::quality::displaySym( r.sym, deltaRoot );
            if( !r.path.empty() )
            {
                named += " at " + r.path + ":" + std::to_string( r.line );
            }
        }
    }
    if( namedCount == 0 )
    {
        return std::nullopt;
    }
    rw::emitTo( stderr, "ripwire: --ack-only={} selects {} finding(s) OUT OF SCOPE for --scope={} — refusing, and writing nothing at all:{}{}\n"
                          "  those rows belong to whoever is editing those paths. Acking them here writes their debt into a committed ledger under YOUR\n"
                          "  reason string, which is how a per-finding ratchet becomes a rubber stamp. Narrow the pattern, or widen the scope if they really are yours.\n", std::string_view( cfg.qualityAckOnly.data(), cfg.qualityAckOnly.size() ), namedCount, scope.spec.c_str(),
                  named.c_str(), namedCount > 8 ? "\n    …" : "" );
    return 1;
}

// ── quality-delta legend, SECTIONED (density round 2026-09-02, lane B) ────────────────────────────
//
// WHY THIS SHAPE. --quality-delta ranks first in this tool's measured call mix — CLAUDE.md tells every
// agent to run it before calling work done — and its legend was ONE 8,574 B constant (10,512 B with the
// scope half) emitted
// unconditionally against a 572 B payload on a clean run — 93.7% of every "am I done?" checkpoint was
// fixed text the reader had already met. The fix generalizes the rule kScopeLegend below already
// followed alone: A DEFINITION IS EMITTED WHEN THE THING IT DEFINES IS IN THE DOCUMENT. Nothing is
// dropped and no limit is softened — a reader still can never meet an undefined name, because a name
// and its sentence appear together or not at all. What went away is (a) four baseline= markers this
// run did not use, (b) the identity/rekey/duplication paragraphs for attributes this run did not emit,
// and (c) prose that restated --help. --help is the catalog; this is the key to THIS document.
//
// G4, for every constant below: an XML comment may never contain the literal byte pair "--", so flag
// names are written bare ("quality-baseline", "the scope flag"), and no "%" appears anywhere because
// these reach stdout through one-argument writes. NO ATTRIBUTE=VALUE NUMERIC LITERAL may be spelled in
// this prose either: several gates grep the header counters (regressions=, gating=, stale=) and a
// quoted example here would be matched ahead of the real one.

// Always. The verb, the twelve kinds, the three axes, the exit predicate, and the two counters that are
// printed even at zero. Every row in the document — finding rows and stale-ack rows alike — carries
// kind=, so it is defined here rather than in either conditional row dictionary.
// P8 (L7): the bar= literals in emitRow mirror quality.h's constants — pinned here so a moved bar cannot drift the row
static_assert( rw::quality::kCcxBar == 15 && rw::quality::kLocBar == 60 && rw::quality::kNestBar == 4 && rw::quality::kParamBar == 5,
               "verbs_quality.h emitRow spells the four bars as literals — update them with quality.h" );

inline constexpr const char* kQdLegendCore =
    "<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. "
    "Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low "
    "score). TWELVE KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity "
    "(LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), "
    "error-masking, short-horizon-churn, new-clone-of-reused-helper, placeholder (added stub/TODO), "
    "defect-shape (defect= names it). "
    "THREE independent axes, in this "
    "order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a "
    "symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only "
    "because the code is NEW carries origin=\"new-symbol\"; (3) MATERIALITY — a small numeric delta is "
    "sev=\"minor\", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, or on "
    "format-arity, the gating= count; new-symbol rows never gate, except defect-shape format-arity, so exit 0 "
    "is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is "
    "preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a "
    "FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger "
    "whose target no longer applies. "
    "api-new-surface= COUNTS the new PUBLIC symbols (never gates, not in regressions=, printed even at zero). "
    "register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind "
    "because their own definition is a registered self-registering test/benchmark macro call. Never gates, "
    "never counted in regressions=, printed even at zero (zero means none excluded, not that the check did "
    "not run). "
    // P3 (L7): next= on gating rows, defined where the reader meets it
    "A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). "
    // P8 (L7): the threshold beside the number
    "bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). ";

// The macro FAMILIES, and why a member of one cannot be judged dead — printed only when the run actually
// excluded something, because on a repo with no such macro the roster explains an empty set.
inline constexpr const char* kQdRegisterMacroLegend =
    "The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark "
    "BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a "
    "static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. ";

// F-13 (audit 2026-09-02) — printed only when .ripwire_config itself has something wrong with it, which
// used to be a silent no-op: a typo'd key was skipped with no trace, and a register_macros= name that
// matched nothing in the corpus looked exactly like one that was quietly doing its job. config-warnings=
// is the one root count covering both; the specific keys/names are on stderr (never guessed at in the XML
// — a name a hand-edited config carries is not free text this attribute repeats).
inline constexpr const char* kQdRegisterMacroWarnLegend =
    "config-warnings= is a FLOOR, never gating and printed only when non-zero: it counts two DISCLOSED "
    ".ripwire_config problems, each also written to stderr — an unrecognized key (the only key this file "
    "reads is register_macros) and a register_macros= name that matched no indexed symbol, either a typo or "
    "a macro this corpus does not use. Neither refuses the run; a misconfigured exemption is not a broken "
    "tree, but a silent one used to read as a working one. ";

// One sentence per baseline= marker, and ONLY the marker this run actually used. The five are not
// interchangeable — three of them compare against HEAD, so anything already committed cannot appear —
// and the state a reader is in is the state they need spelled out.
inline constexpr const char* kQdBaseSidecar =
    "baseline=\"sidecar\" is the pinned .ripwire_quality_baseline snapshot, honored because it was pinned "
    "at the CURRENT git HEAD: the one floor YOU chose. ";
inline constexpr const char* kQdBaseHead =
    "baseline=\"git-HEAD\" means no sidecar existed, so the working tree was auto-compared against the "
    "HEAD tree — anything already committed cannot appear. ";
inline constexpr const char* kQdBaseHeadRemoved =
    "baseline=\"git-HEAD (stale sidecar removed)\" means a sidecar existed, was pinned at a DIFFERENT sha, "
    "and this run DELETED it from your working tree before falling back to the HEAD tree (re-pin with "
    "quality-baseline) — so anything already committed cannot appear. ";
inline constexpr const char* kQdBaseHeadUnreadable =
    "baseline=\"git-HEAD (sidecar unreadable)\" means a .ripwire_quality_baseline EXISTS but could not be read as one "
    "(no recognizable structure, an older sidecar format, or a pre-Q1 sidecar without per-symbol loc records), so it was IGNORED and the "
    "working tree was compared against the HEAD tree, and an allow-dirty pin's absorbed findings are not in force — re-pin it on a "
    "clean tree (commit or stash first) with quality-baseline. baseline_bad_lines= and "
    "acks_bad_lines=, when present, count sidecar lines of a known kind whose payload did not parse and were "
    "skipped (absent means none). ";
inline constexpr const char* kQdBaseHeadSymlinkRefused =
    "baseline=\"git-HEAD (symlinked sidecar refused)\" means .ripwire_quality_baseline is a SYMLINK, which is refused on "
    "read exactly as on write: it was not opened, so the working tree was compared against the HEAD tree — replace "
    "the link with a regular copy of its target, or remove it and re-pin with quality-baseline. ";
inline constexpr const char* kQdBaseHeadIgnored =
    "baseline=\"git-HEAD (stale sidecar ignored)\" is the same staleness verdict, but the file was left on "
    "disk (the read-only MCP arm, or an unlink that failed), and the comparison fell back to the HEAD "
    "tree — so anything already committed cannot appear. ";
// The producer rule (quality.h BaselineSource). Spelled for a reader who pinned on purpose and is looking at a
// floor they did not choose: why their file was not used, that it is still there, and the two ways back.
inline constexpr const char* kQdBaseHeadForeign =
    "baseline=\"git-HEAD (foreign sidecar ignored)\" means a .ripwire_quality_baseline pinned at the CURRENT HEAD was "
    "written by ANOTHER ripwire build: its producer stamp does not name this binary's sources, or it has none. A dead "
    "set depends on how calls were resolved, so that floor could invent a dead-code regression or hide a real one; it "
    "was IGNORED, left on disk, and the working tree was compared against the HEAD tree this build computed — so "
    "anything already committed cannot appear, and an allow-dirty pin's absorbed findings are not in force. Run the "
    "delta with the build that pinned it, or re-pin on a clean tree (commit or stash first) with quality-baseline. ";
// H11 — emitted ONLY when baseline_absorbed= is on the root, i.e. when the honored sidecar was pinned with
// --allow-dirty on a tree that already gated. NB: the sentence itself spells the flag WITHOUT its leading
// dashes, because this text lands inside an XML comment and G4 forbids a literal double-hyphen there (the
// same reason kQdBaseHeadRemoved says "re-pin with quality-baseline"). The attribute changes what a GREEN exit means, so its sentence
// has to say so in those words: without it a reader takes gating="0" for "clean", which is precisely the
// sentence the silent absorb used to manufacture.
inline constexpr const char* kQdBaselineAbsorbedLegend =
    "baseline_absorbed=\"N\" means that sidecar was pinned with the allow-dirty flag on a tree that ALREADY held N "
    "gating finding(s) against HEAD, and those N are inside the floor: a green exit beside this attribute "
    "reads \"clean since the pin\", never \"clean\". Re-pin on a committed tree to clear it. ";
inline constexpr const char* kQdBaseRefPair =
    "baseline=\"ref-pair\" means neither a sidecar nor the working tree: the verb was given a RANGE, so it "
    "compared two COMMITTED trees and no sidecar was read, written or deleted. base_ref= and target_ref= "
    "are the two RESOLVED shas, at full length because a wave number gets quoted into handoffs, and they "
    "are the anchor, so at= is omitted. churn= is reported unavailable there, which is the honest statement "
    "that one kind, short-horizon-churn, cannot be measured at all in that form: it needs git "
    "history at the tree being judged, and both trees are materialized OUT of the repo into temp dirs. Its "
    "silence in such a report is not evidence that nothing churned. ";
// #228 — emitted only when head_basis= is on the root, i.e. only when the identity basis produced the floor.
// The attribute exists because a zero from a self-comparison and a zero from an archived comparison are
// DIFFERENT CLAIMS, and the honesty rule is that a zero means "none found", never "none exists". Its absence
// on a git-HEAD run is not a silent no: it is the archived HEAD tree, which is what every git-HEAD marker
// meant before this attribute existed.
inline constexpr const char* kQdHeadBasisIdentityLegend =
    "head_basis=\"identity\" means the tracked files already WERE HEAD, so the floor is this tree's own "
    "snapshot: a comparison with itself. Files HEAD does not TRACK are crawled but are not in that floor, so "
    "their symbols read as new. Absent: the archived HEAD tree. ";
// The REFUSAL, named on the answer rather than left to silence — its own constant so the clean form, which is
// the posture this verb is most often called in, never pays for a sentence about a state it is not in.
inline constexpr const char* kQdHeadBasisArchivedLegend =
    "head_basis=\"archived-index-hidden\" means the tracked files match HEAD by git's own diff, but a tracked "
    "path carries skip-worktree or assume-unchanged, which git is SPECIFIED not to read: the tree could differ "
    "from HEAD in a way nothing can see, so the faster self-comparison was refused and the archived HEAD tree "
    "was used. That tree is not sparse-aware, so on a sparse checkout an excluded caller can read as vanished "
    "and gate; clear the bit, or read such a row as a population difference rather than a change. ";

// at= is absent in the ref-pair form, so its sentence is too.
inline constexpr const char* kQdAtLegend =
    "at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. ";

// Emitted only when the identity re-filing actually ran, i.e. when the run carries its renames= family.
inline constexpr const char* kQdIdentityLegend =
    "IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would "
    "destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT "
    "tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality "
    "of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many "
    "rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and "
    "acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear "
    "ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than "
    "the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current "
    "symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a "
    "regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through "
    "as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key "
    "on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the "
    "rename record but never content, because the baseline stores no content id at all; and a move git "
    "recorded no rename for still reads as new-symbol. ";

// How the two mechanisms decide, in full — printed only when an ack was actually SUPPRESSED by one of
// them (acked= is non-zero), which is the only state in which a reader has a suppression to audit. The
// determinism properties are the audit: an identity claim nobody can re-derive is not a disclosure.
inline constexpr const char* kQdIdentityMechLegend =
    "The two mechanisms in full, because a suppression is a claim about identity: git's rename record is "
    "read with rename detection and the similarity threshold PINNED in the command, never inherited from "
    "the repo config, over a fixed COMMIT window rather than a wall-clock one, so the answer is the same "
    "everywhere; the content match is equality of a body hash scrubbed of whitespace and of the symbol's "
    "own name, for a move git recorded no rename for. A body that CHANGED is a different finding and is "
    "matched by neither. ";

// Emitted only when the scheme re-keying actually moved or refused a row — i.e. when acks_rekeyed_by_scheme=
// or scheme_ambiguous= is on the root. Both are git-INDEPENDENT, so this is not folded into the paragraph
// above: it survives a run where git could not be read at all.
inline constexpr const char* kQdSchemeLegend =
    "A THIRD re-filing, git-independent: on 2026-08-25 the per-symbol quality key stopped being a "
    "canonical-id hash (which degraded to a BARE NAME for a scope-less symbol, folding every same-named one "
    "in the tree into a single identity) and became the path-qualified key the churn kind has used since "
    "the churn-keying round. Ack rows written under the old rule replay forward into the new one, both "
    "being pure functions of the same path, scope and name — no git, no similarity threshold. "
    "acks_rekeyed_by_scheme= counts the rows that replay moved, and is absent once a ledger has been "
    "written back under the new rule, which is the normal steady state rather than a failure. "
    "scheme_ambiguous= counts rows it REFUSED to move: the old key of a name that folded across N files "
    "maps to N new keys, so which symbol the ack was written for is unknowable from the ledger; those rows "
    "keep their old key and surface under stale= rather than being fanned out to all N or guessed. ";

// The sa ROW dictionary — emitted only when there are sa rows. The stale= axis itself is defined in the
// core paragraph, because the counter is on the root of every report whether or not any row follows it.
inline constexpr const char* kQdStaleLegend =
    "Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no "
    "symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). "
    "sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live "
    "symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), "
    "and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those "
    "rows are unnameable by construction rather than guessed at. "
    "Hygiene disclosure only — the ledger file is never auto-edited. ";

// Emitted only when the document actually has finding rows (in scope or disclosed out of scope).
inline constexpr const char* kQdRowLegend =
    "ROWS: sym= is the canonical id the finding regressed on; was= and now= carry the before/after value for "
    "the numeric kinds; p=\"path:line\" is the locator (root-relative; the first-sorting member for the "
    "clone kinds; omitted, never faked, when none resolves). churn= and surface= are per-kind "
    "classification facets (short-horizon-churn's self/ambient split; api-surface's new-symbol/"
    "contract-change tier). churn= facets never gate alone: the kind gates only on 2+ COMMITTED in-window "
    "rewrites of the edited lines. "
    "Every row the header's gating= counter counts also carries a gating attribute "
    "set to 1 — marked positively, never by the ABSENCE of sev or origin. ";

// Emitted only when a defect-shape row is in the document: the four facets defect= names, which one gates and
// why, what a file-anchored row's sym= is, and what the kind does NOT check (so no row is not a verdict there).
inline constexpr const char* kQdDefectShapeLegend =
    "defect-shape rows name a known defect SHAPE this change added, in defect=: format-arity (a literal "
    "std::format/print/format_to, fmt::, rw::emitTo/formatTo or Python \"literal\".format format whose "
    "fields do not match its arguments), utf8-cut (C++ display text cut at a byte cap and given an ellipsis "
    "with no UTF-8 boundary back-off in the function), dedup-first (C++ std::unique keeping the first of a "
    "run over a type with a severity field that neither the predicate nor the sort before it reads) and "
    "vacuous-assert (a Bash test script's absence assertion read off a command whose failure is never "
    "checked, so a crash reads as PASS). A site is new only when its normalized text occurs more often than "
    "at the baseline (repo-wide, per shape), so a moved or renamed one is not; was= and now= count the shape's sites "
    "in the anchor, the innermost definition or, for top-level code, the file (then sym= is the path). "
    "format-arity gates on any origin: a placeholder/argument mismatch is a defect, not debt. utf8-cut, "
    "dedup-first and vacuous-assert are always sev=\"minor\": report-only by facet, not by size. Python "
    "percent-formatting and f-strings are not checked, nor a format held in a named constant, a macro or a "
    "runtime wrapper, a pack expansion, an argument that may be a macro (a name the file #defines, a function-like "
    "macro the tree defines, or an ALL_CAPS name called; an object-like macro defined only in another file is not "
    "seen), a call with a preprocessor directive inside it or under a literal #if 0 (#if false, #if (0), #if 0 && X "
    "and the #else of #if 1 read as live), an escape that "
    "spells a brace, an unqualified format() call, a named dedup predicate, a utf8 cut in a function that "
    "backs off a continuation byte anywhere, or a vacuous-assert absence read off a FILE a run redirected "
    "into: no row there is no verdict. ";

// Emitted only when a placeholder row is in the document: why every one of them carries origin="new-symbol",
// including one that landed in a symbol that existed at the baseline.
inline constexpr const char* kQdPlaceholderLegend =
    "placeholder is new-symbol by construction: the finding is the stub or TODO the change added, never "
    "something that existed getting worse, so it never gates. ";

// Emitted only when an error-masking row is sev="minor" — the one way that kind is ever minor, so the
// sentence explains a state the reader is looking at and costs nothing on any other report.
inline constexpr const char* kQdMaskReportOnlyLegend =
    "An error-masking row is sev=\"minor\" when every construct it added is a widened shape that does not "
    "gate in that language yet: log-only (a broad handler whose body only logs and never names the error) "
    "or rethrow-only (the sole handler re-throws the error unchanged). ";

// Emitted only when a clone-family row (duplication / new-clone-of-reused-helper) is in the document,
// which is what puts members=, tokens= and idiom= on a first screen. A clean tree has none.
inline constexpr const char* kQdCloneLegend =
    "CLONE ROWS name the whole group rather than one symbol: members= is the member list and tokens= its "
    "shared normalized-token count (the same per-group pair the clones verb reports). idiom= names a "
    "RECOGNIZED BODY SHAPE every member spells, out of a closed set of three (threshold-ladder, "
    "switch-name-table, builder-chain). idiom= alone changes nothing; a group that ALSO shares no "
    "non-keyword identifier between any two members, sits in pairwise-distinct enclosing contexts, and "
    "stays under 80 normalized tokens is an idiom COLLISION rather than a copy, and is reported minor "
    "instead of gating. Break any one of those and it gates as before, idiom= and all: two bucketing "
    "ladders over the SAME enum are a copy. The shape is read off the body's token stream and not a parse "
    "tree, so a macro-assembled body classifies as whatever its raw tokens spell — the name is printed so "
    "the call can be overruled by reading. ";

// P1 — the SCOPE half of the quality-delta legend, printed ONLY when the report actually contains a
// scope partition or a foreign-ack row. That is a G4 (token density) decision, not a hedge: the
// paragraph defines scope=, the out-of-scope element and foreign-acks=, and on an unscoped run none
// of the three is in the document — charging every quality-delta call ~500 tokens to define
// attributes it did not emit is exactly the padding this legend exists to avoid. A reader can never
// meet one of those names undefined, because the names and this paragraph appear together or not at
// all. It lives out here rather than inline so runQualityDelta measures as the code it is.
// G4 again: no flag name spelled with the double dash anywhere inside an XML comment, so this says
// "the scope flag" throughout.
inline constexpr const char* kScopeLegend =
                        "SCOPE, present only when the scope flag was given, and it NARROWS WHAT THIS REPORT "
                        "CLAIMS: scope= is the pattern list it was given, verbatim. Every counter above "
                        "(regressions=, minor=, acked=, preexisting-worse=, new-symbol=, gating=) is then over "
                        "the IN-SCOPE findings alone, and the exit code follows gating= as always. The rest are "
                        "not dropped: scoped-out= counts the findings filed to somebody else, and every one of "
                        "them is printed inside an out-of-scope element carrying n= (the same count), would-gate= "
                        "and note= (the do-not-ack banner). scoped-out-gating= repeats would-gate= on the root "
                        "because it is the number a reader must not miss: it is how many disclosed rows WOULD "
                        "have fired the exit code, so exit 0 under a scope means \"nothing of YOURS is broken\", "
                        "never \"the tree is clean\". Rows inside that element carry the identical attributes to "
                        "the ones above it and never carry the gating attribute, since they are not what this "
                        "exit code fires on. HOW A FINDING IS FILED: by its p= path, matched root-relative "
                        "against the patterns; a clone kind is in scope when ANY member matches, not just the "
                        "first-sorting one; and a finding with no locator at all is filed OUT of scope, because "
                        "under a scope \"we cannot say where this is\" honestly reads as not provably yours. ";

// foreign-acks= is itself "present only when non-zero", so its paragraph follows the same rule the
// attribute does. Split out of kScopeLegend on 2026-09-02: a scoped run with no foreign ack was paying
// ~590 B to define an attribute, a why= value and a by= token none of which were in its document.
inline constexpr const char* kForeignAcksLegend =
                        "foreign-acks= is a SEPARATE axis, never gating and present only when non-zero: an "
                        "ack row records the scope that wrote it as a by= token, and this counts the acks that "
                        "are suppressing a finding whose path that recorded scope does not cover — a session "
                        "having accepted somebody else's debt. Those rows appear among the sa rows with "
                        "why set to foreign-scope and carry by= (the recorded scope). TWO FLOORS on that number: "
                        "only acks suppressing a finding RIGHT NOW can be checked (one whose finding no longer "
                        "fires has no path to test against), and a row with no by= at all is never counted, "
                        "since absence of provenance is not evidence of foreign provenance. ";

// The section table. One struct rather than seven parameters because every field is a property OF THE
// DOCUMENT being introduced, and a caller that has to remember an argument ORDER is the seam where a
// legend starts describing a run it is not attached to.
struct QualityDeltaLegendParts
{
    std::string_view                              marker;        // baseSel.marker — the ONE spelling table (quality::selectBaseline)
    bool                                          refPair;       // the RANGE form: base_ref=/target_ref= are the anchor, at= is absent
    std::string_view                              identityAttrs; // the exact string spliced into the root open tag
    bool                                          anySaRow;      // sa rows present => key= and the why= taxonomy are on screen
    bool                                          anyAcked;      // acked= is non-zero => there is a suppression to audit
    bool                                          anyRegisterMacro; // register-macro-excluded= is non-zero => the family roster describes a real set
    bool                                          anyRegisterMacroWarning; // F-13: config-warnings= is non-zero
    const std::vector<rw::quality::Regression>&   rows;          // in-scope findings
    const std::vector<rw::quality::Regression>&   disclosedRows; // out-of-scope findings — identical attribute set
    bool                                          scoped;        // a scope partition or a foreign-ack row is in the document
    bool                                          anyForeignAck; // foreign-acks= is on the root, with foreign-scope sa rows under it
    std::size_t                                   baselineAbsorbed; // H11: baseline_absorbed= on the root (0 = attribute absent)
    const char*                                   headBasis;     // #228: head_basis= value on the root (nullptr = attribute absent)
    bool                                          anyDeclinedCallExcluded = false;   // declined-call-excluded= is on the root
    bool                                          anyValueRefExcluded     = false;   // value-ref-excluded= is on the root
    bool                                          staleCollapsed          = false;   // idea #11: stale_by_kind=/stale_next= are on the root
    bool                                          kindsSkipped            = false;   // qd-memory-degrade: kinds_skipped=/skipped_why= are on the root
    bool                                          degraded                = false;   // ... ingest_scope= memory_limit= memory_need= also_skipped= kinds_next=
    bool                                          memoryStopped           = false;   // ... memory_stop= (and memory_pressure= when it was pressure)
    bool                                          memoryPeak              = false;   // ... memory_peak= (any range answer whose peak went over the limit)
    bool                                          memorySkippedShare      = false;   // ... memory_skipped= (skipped_why="selector,memory")
};

// qd-memory-degrade — present-only: each rides only with the attributes it defines. No double dash anywhere in them
// (they sit inside the legend comment): a flag is named by its words, never by its spelling.
inline constexpr const char* kQdKindsSkippedLegend =
    "kinds_skipped= names the kinds this answer did NOT run (alphabetical): no row of them is in this document, which is not a "
    "statement that none exists, and regressions=, gating= and every count cover only the kinds that ran; a count only a "
    "skipped kind feeds (register-macro-excluded=) is absent, never 0. skipped_why=\"selector\": the caller chose the kinds "
    "(the kinds selector), and stale acks were judged for the chosen kinds only; skipped_why=\"memory\": see ingest_scope=. ";
inline constexpr const char* kQdMemorySkippedLegend =
    "skipped_why=\"selector,memory\": both; memory_skipped= names memory's share (what kinds_next= runs), the rest the caller left out. ";
inline constexpr const char* kQdDegradedLegend =
    "ingest_scope=\"changed-files\": the two full trees did not fit the memory guard's limit (memory_limit=, the max-memory value "
    "that sets it), so both commits' CHANGED files were ingested alone and the kinds those files decide ran with the same code and "
    "bars as a full answer: their rows are the full answer's rows of those kinds, and the skipped kinds can only ADD rows. "
    "memory_need= is the full answer's projected need, from the base commit's measured peak (a run within that margin of the "
    "limit may be answered this way though it would have fit), or \"unmeasured\" after a stop. also_skipped= names the "
    "whole-answer facts not computed because they read the whole target tree: config-warnings (the .ripwire_config check), "
    "stale-acks (no stale= and no stale sa rows), ack-healing (acks matched by their recorded key only: a row that only a "
    "legacy-scheme re-key or a content-id match would hide in the full answer is shown here, and can gate). kinds_next= is the "
    "call that runs exactly the skipped kinds over the same two commits, at a max-memory just above memory_need= (after a stop: "
    "twice the limit, a guess, since no need was measured); it carries no output flag (rows only). EXIT 2 when a row of a kind that ran gates (final: the skipped kinds "
    "only add rows, though with ack-healing skipped that row may be one an identity-healed ack hides in the full answer); "
    "otherwise EXIT 6, a partial answer with no gating row, never 0 — even when every selected kind ran, since the also_skipped= "
    "facts are still missing. ";
inline constexpr const char* kQdMemoryStopLegend =
    "memory_stop= names the guard's stop that sent this answer to the changed files: crawl (the crawl line, an eighth of the "
    "limit grown) or parse (half the limit) is a soft line, memory_pressure=1 when the OS pressure signal stopped it instead, "
    "hard is the limit itself; a soft stop does not show the full need exceeds the limit. ";
inline constexpr const char* kQdMemoryPeakLegend =
    "memory_peak= is this process's peak footprint when it went OVER the memory limit: the answer and its exit code are what "
    "they would be without it (complete, or the changed-files answer ingest_scope= names), but the last stretch of the "
    "comparison ran past the limit the guard holds between phases. ";

// A DEFINITION IS EMITTED WHEN THE THING IT DEFINES IS IN THE DOCUMENT. Nothing is dropped and no limit is
// softened: a reader can never meet an undefined name, because a name and its sentence appear together or
// not at all. See the constants above for what each section covers and why it is conditional.
inline void emitQualityDeltaLegend( const QualityDeltaLegendParts& p, std::FILE* out = stdout )
{
    const auto anyCloneRow = [] ( const std::vector<rw::quality::Regression>& v )
    {
        for( const rw::quality::Regression& r : v )
        {
            if( r.kind == "duplication" || r.kind == "new-clone-of-reused-helper" ) { return true; }
        }
        return false;
    };
    const auto anyMinorMaskRow = [] ( const std::vector<rw::quality::Regression>& v )
    {
        return std::any_of( v.begin(), v.end(), []( const rw::quality::Regression& r ) { return r.kind == "error-masking" && r.isMinor; } );
    };
    const auto anyPlaceholderRow = [] ( const std::vector<rw::quality::Regression>& v )
    {
        return std::any_of( v.begin(), v.end(), []( const rw::quality::Regression& r ) { return r.kind == "placeholder"; } );
    };
    const auto anyDefectShapeRow = [] ( const std::vector<rw::quality::Regression>& v )
    {
        return std::any_of( v.begin(), v.end(), []( const rw::quality::Regression& r ) { return r.kind == "defect-shape"; } );
    };

    std::fputs( kQdLegendCore, out );

    // (1) the ONE floor in force. Keyed off the same pointer the element prints, so the sentence cannot
    // drift from the attribute. A marker with no sentence would be a disclosure gap, so the fallthrough is
    // the git-HEAD sentence — what every non-sidecar, non-ref-pair marker degrades to.
    if     ( p.marker == "sidecar"                          ) { std::fputs( kQdBaseSidecar,     out ); }
    else if( p.marker == "ref-pair"                         ) { std::fputs( kQdBaseRefPair,     out ); }
    else if( p.marker == "git-HEAD (stale sidecar removed)" ) { std::fputs( kQdBaseHeadRemoved, out ); }
    else if( p.marker == "git-HEAD (stale sidecar ignored)" ) { std::fputs( kQdBaseHeadIgnored, out ); }
    else if( p.marker == "git-HEAD (sidecar unreadable)"     ) { std::fputs( kQdBaseHeadUnreadable, out ); }
    else if( p.marker == "git-HEAD (symlinked sidecar refused)" ) { std::fputs( kQdBaseHeadSymlinkRefused, out ); }
    else if( p.marker == "git-HEAD (foreign sidecar ignored)"   ) { std::fputs( kQdBaseHeadForeign, out ); }
    else                                                      { std::fputs( kQdBaseHead,        out ); }
    if( p.baselineAbsorbed > 0 )
    {
        std::fputs( kQdBaselineAbsorbedLegend, out );   // H11 — the attribute that re-reads the exit code
    }
    // #228 — the attribute that says WHICH git-HEAD floor this is, one sentence per value it can carry.
    if( p.headBasis != nullptr )
    {
        std::fputs( std::string_view( p.headBasis ) == "identity" ? kQdHeadBasisIdentityLegend : kQdHeadBasisArchivedLegend, out );
    }

    // (2) at= is omitted in the ref-pair form, so its sentence follows the attribute, not the verb.
    if( !p.refPair )
    {
        std::fputs( kQdAtLegend, out );
    }
    if( p.anyRegisterMacro )
    {
        std::fputs( kQdRegisterMacroLegend, out );
    }
    if( p.anyRegisterMacroWarning )
    {
        std::fputs( kQdRegisterMacroWarnLegend, out );
    }
    if( p.anyDeclinedCallExcluded )
    {
        std::fputs( "declined-call-excluded= is a FLOOR, not a finding: symbols this run kept out of the dead-code kind only because a call "
                    "the resolver declined to bind (the map's declined=) could have meant them. Never gates; absent at zero. ", out );
    }
    if( p.anyValueRefExcluded )
    {
        rw::emitRaw( out, "value-ref-excluded= is a FLOOR, not a finding: symbols this run kept out of the dead-code kind only because a table, "
                             "field, argument or registering decorator holds them as a VALUE (matched by name; it is not a proven call; the callers "
                             "verb lists the sites; @classmethod-style wrappers do not count), "
                             "the --dead-code verb's own rule. Never gates; absent at zero. " );
    }

    // (3) the two identity re-filings, each keyed to the attribute family it defines. The second is
    // git-INDEPENDENT, so it is a separate condition rather than a clause of the first.
    if( !p.identityAttrs.empty() )
    {
        std::fputs( kQdIdentityLegend, out );
        if( p.anyAcked )
        {
            std::fputs( kQdIdentityMechLegend, out );
        }
    }
    if( p.identityAttrs.find( "acks_rekeyed_by_scheme=" ) != std::string_view::npos
        || p.identityAttrs.find( "scheme_ambiguous=" ) != std::string_view::npos )
    {
        std::fputs( kQdSchemeLegend, out );
    }

    // (4) key= and the why= taxonomy exist only in a document that has sa rows. stale= itself is a header
    // counter, always printed, and is defined in the core paragraph's axis list.
    if( p.anySaRow )
    {
        std::fputs( kQdStaleLegend, out );
    }

    // (5) the row dictionary, and its clone-family half. A clean tree emits neither attribute set, so at the
    // "done" checkpoint an agent actually makes, the reader pays for neither.
    if( !p.rows.empty() || !p.disclosedRows.empty() )
    {
        std::fputs( kQdRowLegend, out );
        if( anyCloneRow( p.rows ) || anyCloneRow( p.disclosedRows ) )
        {
            std::fputs( kQdCloneLegend, out );
        }
        if( anyMinorMaskRow( p.rows ) || anyMinorMaskRow( p.disclosedRows ) )
        {
            rw::emitRaw( out, kQdMaskReportOnlyLegend );
        }
        if( anyPlaceholderRow( p.rows ) || anyPlaceholderRow( p.disclosedRows ) )
        {
            rw::emitRaw( out, kQdPlaceholderLegend );
        }
        if( anyDefectShapeRow( p.rows ) || anyDefectShapeRow( p.disclosedRows ) )
        {
            rw::emitRaw( out, kQdDefectShapeLegend );
        }
    }

    if( p.scoped )
    {
        std::fputs( kScopeLegend, out );
    }
    if( p.anyForeignAck )
    {
        std::fputs( kForeignAcksLegend, out );
    }
    if( p.kindsSkipped )
    {
        std::fputs( kQdKindsSkippedLegend, out );
    }
    if( p.degraded )
    {
        std::fputs( kQdDegradedLegend, out );
    }
    if( p.memorySkippedShare )
    {
        std::fputs( kQdMemorySkippedLegend, out );
    }
    if( p.memoryStopped )
    {
        std::fputs( kQdMemoryStopLegend, out );
    }
    if( p.memoryPeak )
    {
        std::fputs( kQdMemoryPeakLegend, out );
    }
    if( p.staleCollapsed )
    {
        // idea #11: the collapse, named where its attributes are. No flag spelling (a double dash is illegal in a comment).
        std::fputs( "stale_by_kind= splits stale= by ack kind (kind:N, comma-separated): on an answer with no regression the stale "
                    "sa rows are collapsed to these counts when that saves at least a quarter of the bytes, and stale_next= is the call that prints them. ", out );
    }
    std::fputs( "-->", out );   // every section constant above ends with its own separating space
}

// F-13 — the one place both --dead-code and --quality-delta turn a RegisterMacroConfigDiagnostics into
// output: the specific keys/names on stderr (never guessed at in the XML — a hand-edited config's tokens
// are not free text an attribute repeats), and the shared `config-warnings="N"` attribute string, present
// only when non-zero (this file's standing convention for every optional root attribute). One function so
// the two verbs cannot report the same misconfiguration two different ways.
inline std::string registerMacroConfigWarningAttr( const rw::quality::RegisterMacroConfigDiagnostics& diag )
{
    if( diag.total() == 0 )
    {
        return std::string();
    }
    const auto joined = [] ( const std::vector<std::string>& v ) -> std::string
    {
        std::string out;
        for( std::size_t i = 0; i < v.size(); ++i )
        {
            if( i ) { out += ", "; }
            out += v[i];
        }
        return out;
    };
    if( !diag.unrecognizedKeys.empty() )
    {
        rw::emitTo( stderr, "ripwire: .ripwire_config has an unrecognized key (the only key this file reads is register_macros): {}\n",
                      joined( diag.unrecognizedKeys ).c_str() );
    }
    if( !diag.inertNames.empty() )
    {
        rw::emitTo( stderr, "ripwire: .ripwire_config's register_macros= names a macro matching no indexed symbol (typo, or unused): {}\n",
                      joined( diag.inertNames ).c_str() );
    }
    return " config-warnings=\"" + std::to_string( diag.total() ) + "\"";
}

// H10 (capture-audit 2026-09-04): the --quality-ack run that has NOTHING to accept. It used to re-serialise
// the ledger unconditionally ("acknowledged 0 finding(s)"), so a committed ledger with one hand-merged row out
// of btree order moved that row under a run that changed no fact — a spurious diff in the caller's tree. But
// the rewrite is also the ledger's HEALING path (duplicate lines collapsed to one canonical row, legacy kinds
// migrated, misfiled rows re-sorted), and healing IS a change worth a diff. So the rule is the byte-level one:
// a ledger already equal to its own canonical bytes is left alone and the run says so; a non-canonical one is
// rewritten and the run says that instead. Neither creates a ledger out of nothing. Returns the exit code.
int ackNothingToAccept( const std::string& acksFile, const gtl::btree_map<std::string, rw::quality::AckRecord>& acks,
                        const rw::quality::Scope& scope, std::size_t outOfScopeCount )
{
    // `acks.empty()` first, so a ledger that is not a regular file (already refused on read) is not read and disclosed twice.
    if( acks.empty() || rw::quality::renderAckRecords( acks ) == rw::docparse::detail::readRegularFile( "the quality-acks ledger", acksFile ).value_or( std::string() ) )
    {
        if( scope.active() && outOfScopeCount > 0 )
        {
            rw::emitTo( stderr, "ripwire: nothing to acknowledge — 0 finding(s) in --scope={} ({} out of scope, not yours); {} left untouched\n",
                          scope.spec.c_str(), outOfScopeCount, acksFile.c_str() );
        }
        else
        {
            rw::emitTo( stderr, "ripwire: nothing to acknowledge — the report has 0 finding(s); {} left untouched\n", acksFile.c_str() );
        }
        return 0;
    }
    if( !rw::quality::writeAckRecords( acksFile, acks ) )
    {
        rw::emitTo( stderr, "ripwire: could not write {}\n", acksFile.c_str() );
        return 1;
    }
    rw::emitTo( stderr, "ripwire: nothing to acknowledge — the report has 0 finding(s), but {} was not in canonical form "
                          "(duplicate, legacy or misfiled rows) and has been re-serialised\n", acksFile.c_str() );
    return 0;
}

// ─── H11 (capture-audit 2026-09-04) — WHAT A PIN ON THIS TREE WOULD ABSORB ────────────────────────────
//
// THE DEFECT. `--quality-baseline` snapshotted the WORKING TREE and wrote it as the floor, with no regard
// for whether that tree already held debt. Pinned mid-edit — which is exactly what the quality-bar skill's
// "run --quality-baseline FIRST" advice produces — every regression already in the tree became the floor,
// and the next --quality-delta read `baseline="sidecar" regressions="0" gating="0"` on a tree whose own
// --edit-check said `contract-change incompatible="4"`. A green report, silently manufactured, by the verb
// whose entire job is to say when you are not green.
//
// So the pin now ASKS the question first: taken against git HEAD, how many GATING findings does this tree
// already hold? Zero (a clean tree, or one whose edits gate nothing) ⇒ the pin is what it always was. More
// ⇒ refuse, naming the count and the first row, unless the caller says --allow-dirty — in which case the
// count is STAMPED into the sidecar so every later report can carry it.
//
// The ack ratchet is applied, and identity healed, exactly as the delta arm does it: a finding the caller
// has already accepted with a reason is not debt this pin is hiding from them, so it must not refuse over
// one. A root with no HEAD tree (non-git, unborn, detached-no-tree) can answer nothing here — the honest
// degrade is to pin as before, since there is no baseline to have absorbed anything against.
struct DirtyPinVerdict
{
    std::size_t              absorbed = 0;    // gating findings this tree already holds vs HEAD
    std::string              firstRow;        // the first of them, spelled for a human ("" when absorbed==0)
};

DirtyPinVerdict inspectDirtyBaselinePin( const MainDispatch& d, const std::string& acksFile )
{
    using namespace rw;
    const Config& cfg  = d.cfg;
    const std::string& root = d.root;

    DirtyPinVerdict verdict;
    // The SAME basis the delta arm takes (quality::computeHeadBasis) — the refusal this verdict feeds is a
    // statement about the delta, so computing it another way is how the two would come to disagree. #228: on a
    // tree whose tracked files are HEAD this now absorbs nothing, which is what unblocks --quality-baseline on
    // exactly the repositories that needed the escape hatch.
    quality::HeadBasis basis = quality::computeHeadBasis( root, d.ing, d.g, cfg.rootPath, cfg.maxFileBytes, cfg.excludes );
    if( !basis.ok )
    {
        return verdict;   // no HEAD tree to compare against — nothing can be absorbed, so nothing is claimed
    }
    gtl::btree_map<std::string, quality::AckRecord> acks = quality::readAckRecords( acksFile );
    quality::healIdentity( basis.snapshot, acks, d.ing, d.g, std::string( cfg.rootPath ), root, /*wantContentIds=*/false );
    std::vector<quality::Regression> regs =
        quality::computeDelta( d.ing, d.g, basis.snapshot, cfg.rootPath, cfg.excludes, cfg.maxFileBytes );
    quality::applyAckRatchet( regs, acks );

    for( const quality::Regression& r : regs )
    {
        if( !quality::rowGates( r ) )
        {
            continue;   // the exit predicate — the one rowGates every surface asks
        }
        ++verdict.absorbed;
        if( verdict.firstRow.empty() )
        {
            verdict.firstRow = r.kind + " " + quality::displaySym( r.sym, cfg.rootPath )
                             + " (was=" + std::to_string( r.was ) + " now=" + std::to_string( r.now ) + ")";
        }
    }
    return verdict;
}


// The --quality-baseline arm, whole. Extracted from runQualityDelta when H11 gave the pin a DECISION to make
// (see inspectDirtyBaselinePin above): the arm shares nothing with the delta arm below it but the two sidecar
// paths, which are parameters here, and leaving it inline would have grown a 228-branch function for a
// question that is entirely its own.
int runQualityBaselinePin( const MainDispatch& d, const std::string& baselineFile, const std::string& acksFile )
{
    using namespace rw;
    const DirtyPinVerdict pin = inspectDirtyBaselinePin( d, acksFile );
    if( pin.absorbed > 0 && !d.cfg.allowDirty )
    {
        rw::emitTo( stderr, "ripwire: --quality-baseline: this tree already holds {} gating finding(s) against HEAD — pinning here would absorb\n"
                              "  them into the floor, and every later --quality-delta would read clean. First: {}\n"
                              "  Commit the tree first, or pass --allow-dirty to pin anyway (the sidecar then records the {} absorbed, and every\n"
                              "  report against it carries baseline_absorbed=\"{}\").\n",
                      pin.absorbed, pin.firstRow.c_str(), pin.absorbed, pin.absorbed );
        return 1;
    }
    const quality::Snapshot snap  = quality::computeSnapshot( d.ing, d.g, d.cfg.rootPath );
    const bool              wrote = quality::writeBaseline( snap, baselineFile, gitHeadSha( d.root ), pin.absorbed );
    if( wrote && pin.absorbed > 0 )
    {
        rw::emitTo( stderr, "ripwire: --quality-baseline --allow-dirty: pinned with {} gating finding(s) ABSORBED into the floor "
                              "(stamped in the sidecar; every --quality-delta against it carries baseline_absorbed=\"{}\")\n",
                      pin.absorbed, pin.absorbed );
    }
    // §L10b LOW tail: this used to report ing.symbols.size() — every raw indexed symbol — while the sidecar
    // computeSnapshot() actually WRITES one row per DISTINCT canonId (overloads collapse to their MAX, and a
    // symbol with no canonId at all — g.canonId[i].empty() — is skipped entirely), a smaller number by
    // construction (12,854 vs 13,358 on this tree at the time this was found). ccxBySym is computed for every
    // one of those rows without exception, so its size is the true count of what the file holds.
    // Split from one ternary over two format strings into the two calls it always was. printf let a
    // 1-conversion format be handed 3 arguments and quietly ignore the extra two; std::format_string is
    // consteval and checks arity per format, so the shape has to be honest. Same bytes on both branches.
    if( wrote )
    {
        rw::emitTo( stderr, "ripwire: wrote {} (snapshot of {} per-symbol rows, {} indexed symbols total)\n",
                    baselineFile.c_str(), snap.ccxBySym.size(), d.ing.symbols.size() );
    }
    else
    {
        rw::emitTo( stderr, "ripwire: could not write {}\n", baselineFile.c_str() );
    }
    return wrote ? 0 : 1;
}


// runQualityViews was NOT a dispatch chain — it held two
// branches, one of which was 298 lines. That one body is now runQualityDelta below; the residual
// runQualityViews keeps only --dead-code. ONE extraction, verbatim: the 298-line body is unsplit, because
// its interior is a sequential pipeline over shared locals, not independent arms.
// qd-memory-degrade: --quality-kinds=K[,K] (range form only; cli.h refuses it elsewhere) — the kinds to run. The vocabulary
// is quality.h's, so an unknown name is refused here, before any tree is read. nullopt when absent or valid.
std::optional<int> applyKindSelector( const rw::Config& cfg, RefPairDelta& refs )
{
    if( cfg.qualityKinds.empty() )
    {
        return std::nullopt;
    }
    std::string bad;
    refs.selected = rw::quality::parseKindList( cfg.qualityKinds, bad );
    if( refs.selected != 0 )
    {
        return std::nullopt;
    }
    rw::emitTo( stderr, "ripwire: --quality-kinds: '{}' is not a kind — name one or more of: {}\n", bad, rw::quality::kindList( rw::quality::kAllKinds, ", " ) );
    return 1;
}

// L2 stale acks in the range form. A changed-files answer holds no whole target tree to check the ledger against, so it
// judges none (also_skipped= says so). Under --quality-kinds only the selected kinds' acks are judged, against a snapshot of
// those kinds: a dead-code ack read against a snapshot that never computed the dead set would read finding-gone, which is
// false (R9). Every kind selected: the ledger and snapshot every range answer has always used.
std::vector<rw::quality::StaleAck> refPairStaleAcks( const gtl::btree_map<std::string, rw::quality::AckRecord>& acks, const RefPairDelta& refs )
{
    using namespace rw;
    if( refs.degraded )
    {
        return {};
    }
    if( refs.selected == quality::kAllKinds )
    {
        return quality::computeStaleAcks( acks, quality::computeSnapshot( refs.target().ing, refs.target().g, refs.target().root ) );
    }
    gtl::btree_map<std::string, quality::AckRecord> selectedAcks;
    for( const auto& [ mapKey, rec ] : acks )
    {
        if( quality::kindSelected( refs.selected, std::string_view( rec.kind ).substr( 0, rec.kind.find( ':' ) ) ) )   // the kind, without an origin facet
        {
            selectedAcks.emplace( mapKey, rec );
        }
    }
    return selectedAcks.empty() ? std::vector<quality::StaleAck>{}
                                : quality::computeStaleAcks( selectedAcks, quality::computeSnapshot( refs.target().ing, refs.target().g, refs.target().root, nullptr, { refs.selected } ) );
}

// qd-memory-degrade — what an answer that did not run every kind says about it, built ONCE for both emitters (the
// identityDisclosure rule: the two surfaces cannot disclose different things). Empty strings on a full answer, which then
// keeps every byte it had. kindsNext is the replay of the kinds memory skipped (empty when none).
struct KindsDisclosure
{
    std::string           xml, json, kindsNext;
    rw::quality::KindMask memorySkipped = 0;
    std::uint64_t         peakOver      = 0;   // memory_peak=: the peak, when it went over the limit (0 = absent)
};
KindsDisclosure kindsDisclosure( const rw::Config& cfg, const RefPairDelta& refs, const DeltaBasis& basis, bool refPair )
{
    using namespace rw;
    KindsDisclosure out;
    if( !refPair )
    {
        return out;
    }
    const auto add = [ & ]( std::string_view name, const std::string& value, bool list )
    {
        out.xml += " " + std::string( name ) + "=\"" + value + "\"";
        if( !list )
        {
            out.json += ",\"" + std::string( name ) + "\":\"" + rw::jsonesc::escapeMcp( value ) + "\"";
            return;
        }
        out.json += ",\"" + std::string( name ) + "\":[";
        for( std::size_t at = 0; at <= value.size(); )
        {
            const std::size_t comma = std::min( value.find( ',', at ), value.size() );
            out.json += ( at == 0 ? "\"" : ",\"" ) + value.substr( at, comma - at ) + "\"";
            at = comma + 1;
        }
        out.json += "]";
    };
    // review C1: the kinds the CALLER left out and the kinds MEMORY skipped are two sets with two reasons — a selector's
    // exclusions are never disclosed as memory cuts, and kinds_next= replays exactly the memory set
    const quality::KindMask skipped  = static_cast<quality::KindMask>( quality::kAllKinds & ~refs.kinds );
    const quality::KindMask selector = static_cast<quality::KindMask>( quality::kAllKinds & ~refs.selected );
    if( refs.degraded )
    {
        out.memorySkipped = static_cast<quality::KindMask>( refs.selected & ~refs.kinds );
    }
    if( skipped != 0 )
    {
        add( "kinds_skipped", quality::kindList( skipped, "," ), true );
        const bool both = out.memorySkipped != 0 && selector != 0;   // then memory_skipped= names memory's share
        add( "skipped_why", both ? "selector,memory" : out.memorySkipped != 0 ? "memory" : "selector", false );
        if( both )
        {
            add( "memory_skipped", quality::kindList( out.memorySkipped, "," ), true );
        }
    }
    if( refs.degraded )
    {
        const std::uint64_t limit = memguard::limits().hardBytes;
        add( "ingest_scope", "changed-files", false );
        if( limit != 0 )
        {
            add( "memory_limit", memguard::limitSpelling( limit ), false );
        }
        if( !refs.memoryStop.empty() )
        {
            add( "memory_stop", refs.memoryStop, false );
            if( refs.memoryPressure )
            {
                add( "memory_pressure", "1", false );
            }
        }
        add( "memory_need", refs.memoryStop.empty() ? memguard::limitSpelling( refs.needBytes ) : std::string( "unmeasured" ), false );
        add( "also_skipped", basis.ackHealingSkipped ? "ack-healing,config-warnings,stale-acks" : "config-warnings,stale-acks", true );
        if( out.memorySkipped != 0 )
        {
            out.kindsNext = "--quality-delta=" + refs.baseSha + ".." + refs.targetSha + " --quality-kinds=" + quality::kindList( out.memorySkipped, "," );
            if( limit != 0 )
            {
                out.kindsNext += " --max-memory=" + memguard::limitSpelling( memguard::replayLimitBytes( refs.needBytes, refs.ingestNeedBytes, refs.memoryStop.empty() ) );
            }
            if( !cfg.qualityScope.empty() )
            {
                out.kindsNext += " " + rw::nextFlag( "--scope=", cfg.qualityScope );   // the same partition, so the union keeps its gating
            }
            add( "kinds_next", out.kindsNext, false );
        }
    }
    out.peakOver = memguard::peakOverLimit();
    if( out.peakOver != 0 )
    {
        memguard::peakSaidSlot().store( true, std::memory_order_relaxed );   // main() need not say it again
        add( "memory_peak", memguard::limitSpelling( out.peakOver ), false );
    }
    return out;
}

// qd-memory-degrade: the stderr lines of kindsDisclosure's facts — the degraded answer's one line, and the peak's.
void emitMemoryLines( const KindsDisclosure& kd, const RefPairDelta& refs )
{
    using namespace rw;
    if( refs.degraded )
    {
        rw::emitTo( stderr, "ripwire: {}\n", degradedStderrLine( refs, kd.memorySkipped, kd.kindsNext ) );
    }
    if( kd.peakOver != 0 )
    {
        rw::emitTo( stderr, "ripwire: memory peak {} went over the {} limit ({}): {}, but its last stretch ran past the limit the guard holds "
                            "between phases — {}\n",
                    memguard::limitSpelling( kd.peakOver ), memguard::limitSpelling( memguard::limits().hardBytes ), memguard::limitSourceClause(),
                    refs.degraded ? "the changed-files answer stands as stated above" : "the answer is complete", memguard::kOverride );
    }
}

// The exit code every --quality-delta emitter returns: 2 when a row gates; a changed-files answer with no gating row is 6
// (a partial answer, never a clean pass — the kinds it skipped could still gate); otherwise 0.
int qualityDeltaExit( std::size_t gatingCount, const RefPairDelta& refs ) noexcept
{
    return gatingCount > 0 ? 2 : refs.degraded ? 6 : 0;
}

std::optional<int> runQualityDelta( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::string&                root         = d.root;

    // --quality-baseline / --quality-delta (the convergence-loop oracle): snapshot ccx + clone groups + dead
    // candidates to .ripwire_quality_baseline; then report ONLY what a change made WORSE vs it. The "delta not
    // absolute" discipline — a refine loop targets the regression it introduced, not absolute numbers (the
    // defense against metric-gaming). exit 2 if any new debt, like --arch.
    if( cfg.qualityBaseline || cfg.qualityDelta )
    {
        // D1 fix (HIGH): resolve BOTH sidecars against the analyzed ROOT, not the process CWD —
        // see quality::rootQualifiedSidecar's comment for why a bare relative filename is unsafe here
        // (a foreign cwd's sidecar could be silently rewritten, or even deleted by the stale-baseline
        // self-heal below). Computed once; every read/write/remove site in this block uses it.
        const std::string baselineFile = quality::baselinePath( root );
        const std::string acksFile     = quality::acksPath( root );

        if( cfg.qualityBaseline )
        {
            return runQualityBaselinePin( d, baselineFile, acksFile );
        }

        // Precedence for the baseline: (1) an explicit `.ripwire_quality_baseline` sidecar (from
        // --quality-baseline) wins whenever it is pinned at the CURRENT HEAD — the mid-task convergence loop
        // (baseline once, edit, re-check) is unchanged; (2) else — no sidecar, or a STALE one (see R3 below) —
        // if the root is a git repo with a HEAD tree, auto-baseline against HEAD so the "before I push" loop
        // works with no start-of-task ritual (T0.1); (3) else degrade to the exit-1 "run --quality-baseline
        // first" guidance (non-git / unborn / detached-no-tree — unchanged).
        //
        // STALENESS + the self-heal now live in ONE place, quality::selectBaseline — R3 owner ruling
        // (2026-07-29): a sidecar whose pinned sha != the CURRENT HEAD sha is STALE, full stop. The B10.1b
        // "reachable ancestor is a deliberately-pinned floor" carve-out this arm used to apply (gitIsAncestor)
        // is REVOKED: a parallel session's sidecar pinned at a commit that merely happened to be an ancestor of
        // this session's HEAD made THIS arm report 31 phantom regressions while the MCP quality_delta verb —
        // same binary, same repo, same second — correctly reported zero. That divergence was only possible
        // because each arm carried its own copy of the test; there is now exactly one, in quality.h.
        //
        // What remains this arm's own POLICY is the `removeStaleFile=true` argument: the stale sidecar is
        // silently UNLINKED (best-effort) so the NEXT run sees no file at all rather than rediscovering the
        // same dead pin, and the ONLY record is the `baseline=` XML attribute ("git-HEAD (stale sidecar
        // removed)") — no stderr spam, which is the B10.1b noise fix that survives the ruling intact. The
        // read-only MCP arm passes false and reports "…ignored" instead. When the unlink FAILS (read-only
        // parent dir) this arm degrades to the read-only story — marker "…ignored", one DISCLOSE
        // from the seam — because the pin is still on disk; `baseSel.isStaleFileOnDisk()` is the fact, and the
        // fatal message below words itself from it rather than from the intent.
        // `refs` is declared HERE because it owns both materialized trees' teardown and they must outlive
        // every read of `regs` (DeltaBasis's header states that rule, and why the emitters below spell every
        // path and symbol against basis.deltaRoot rather than against `root`).
        // F-04 (round-4 audit) — SERIALIZE THE ACK LEDGER'S READ-MODIFY-WRITE, cross-process.
        //
        // --quality-ack reads the whole ledger (inside resolveDeltaBasis just below — the heal has to happen
        // before computeDelta), folds this run's accepted findings into that map, then rewrites the file from
        // it. Nothing serialized that. Three sessions acking DISJOINT rows in one shared checkout — the exact
        // scenario --scope exists for — lost two of the three acks on 8 of 8 measured runs, because whichever
        // process rewrote last overwrote a map the other two had already published into.
        //
        // The lock therefore has to span the READ as well as the write, which is why it is taken HERE and not
        // inside writeAckRecords: a lock held only around the final rewrite still lets two processes read the
        // same stale map first and then take turns clobbering. Engaged ONLY under --quality-ack — a read-only
        // --quality-delta never waits, never creates the lockfile, and is byte-for-byte the run it always was.
        // RAII: released when this function returns, on every path including the refusals below. quality.h's
        // SidecarWriteLock has the lockfile's location (per-user cache dir, never a repo-tree sidecar), the
        // wait budget, and the honest limits.
        std::optional<quality::SidecarWriteLock> ackLock;
        if( cfg.qualityAck )
        {
            ackLock.emplace( acksFile );
        }

        const bool   refPair = !cfg.qualityDeltaRange.empty();
        RefPairDelta refs;
        DeltaBasis   basis;
        if( const std::optional<int> refused = applyKindSelector( cfg, refs ) )
        {
            return refused;
        }
        if( const std::optional<int> refused = resolveDeltaBasis( d, baselineFile, refs, basis ) )
        {
            return refused;
        }
        const quality::BaselineSelection& baseSel   = basis.baseSel;
        const std::string&                deltaRoot = basis.deltaRoot;
        std::vector<quality::Regression>&  regs     = basis.regs;

        // ── P1 SCOPE — the OWNERSHIP partition for a working tree with several writers in it ─────────────
        quality::Scope                   scope = quality::parseScope( cfg.qualityScope );
        std::vector<quality::Regression> outOfScope;
        std::size_t                      diffFileCount = 0;   // P1.2: 0 = the reserved diff token was not used
        const IngestResult&              judged        = refPair ? refs.target().ing : ing;
        if( const std::optional<int> refused = expandScopeDiff( scope, refPair, judged, root, deltaRoot, diffFileCount ) )
        {
            return refused;
        }
        if( const std::optional<int> refused = refuseUnusableScope( cfg, scope, judged, deltaRoot, refs.scopeFiles() ) )
        {
            return refused;
        }

        // Signal-to-noise round — the per-finding ACK RATCHET. Suppress findings already accepted (with a
        // reason) in .ripwire_quality_acks, honestly (acked="N"); a finding that WORSENED past its acked
        // magnitude survives the filter and reappears. --quality-ack merges the currently-VISIBLE findings
        // into that file instead of printing the report (accepting what previous acks already hid would be
        // a silent blanket ack — only what the agent can see right now is what it can accept).
        // R1 IDENTITY: the ledger was read and HEALED inside resolveDeltaBasis (it had to be — the baseline
        // half of the same healing has to precede computeDelta), so this arm takes the already-current map
        // rather than re-reading the file and undoing it.
        gtl::btree_map<std::string, quality::AckRecord>& acks = basis.acks;
        quality::countAckRescues( regs, acks, basis.healing.ackRemap,
                                  basis.healing.ackedByRename, basis.healing.ackedByContent );
        // P1.4 PROVENANCE — the foreign-ack sweep reads the PRE-ratchet list on purpose (computeForeignAcks'
        // header states why: the question is about acks that are suppressing something right now).
        const std::vector<quality::StaleAck> foreignAcks = quality::computeForeignAcks( regs, acks );
        // P1 — the partition runs BEFORE the ratchet so acked="N" counts THIS scope's suppressions rather
        // than the whole tree's (partitionByScope owns the rest of the rule).
        const std::size_t scopedOutGating = partitionByScope( scope, regs, outOfScope, acks );
        const std::size_t ackedCount = quality::applyAckRatchet( regs, acks );
        if( cfg.qualityAck )
        {
            // --ack-only=SUBSTR[,SUBSTR]: ack a SUBSET instead of everything on screen. Without it, the only
            // way to accept one deliberate contract change was to accept the whole report — which is how a
            // ratchet quietly becomes a rubber stamp. A finding matches if a substring occurs in its kind or
            // in its canonical id (so "api-surface", "src/quality.h", or one exact id all work).
            // P1: `inScope` is a parameter rather than a capture because this predicate is asked about BOTH
            // halves of the partition — once to choose what to write, once to detect an ack selection that
            // NAMES a row belonging to someone else. It is also what keeps the `gating` pseudo-token honest
            // under a scope: an out-of-scope row does not gate, so `gating` must not select it.
            const auto ackSelected = [ & ]( const quality::Regression& r, bool inScope ) -> bool
            {
                if( cfg.qualityAckOnly.empty() )
                {
                    return true;
                }
                std::string_view rest = cfg.qualityAckOnly;
                while( !rest.empty() )
                {
                    const std::size_t     comma = rest.find( ',' );
                    const std::string_view pat  = rest.substr( 0, comma );
                    // kind, canonical id, or FACET. The facet is what makes this precise enough to be honest:
                    // "api-surface" also covers the never-gating new-symbol rows, so acking by kind would
                    // sweep in 59 findings to accept 8. --ack-only=contract-change accepts exactly the
                    // deliberate ones. The pseudo-token "gating" selects whatever would actually exit 2.
                    const bool gates = quality::rowGates( r ) && inScope;
                    if( !pat.empty() && ( r.kind.find( pat ) != std::string::npos || r.sym.find( pat ) != std::string::npos || ( !r.facet.empty() && r.facet.find( pat ) != std::string::npos ) || ( pat == "gating" && gates ) ) )
                    {
                        return true;
                    }
                    if( comma == std::string_view::npos )
                    {
                        break;
                    }
                    rest = rest.substr( comma + 1 );
                }
                return false;
            };

            // P1 — THE RUBBER-STAMP GUARD (refuseForeignAckSelection owns the rule and the message).
            if( const std::optional<int> refused = refuseForeignAckSelection( cfg, scope, outOfScope, deltaRoot, ackSelected ) )
            {
                return refused;
            }

            // THE LEGACY-ACK BACKFILL, run on the map this process already holds the write lock over and
            // BEFORE this run's own acks are folded in, so a row healed here can still be overwritten by a
            // live measurement of the same finding in the loop below — measured always beats reconstructed,
            // and ordering is what guarantees it rather than a check. It runs even when this run accepts
            // NOTHING: healing the ledger's provenance is the same class of forward repair the identity
            // remap already performs on every ack, and H10's ackNothingToAccept re-renders and notices.
            // quality::backfillCloneAckProvenance owns the rule, what it refuses to touch, and why.
            const quality::AckBackfill backfilled = quality::backfillCloneAckProvenance( acks, basis.cloneIdioms );
            // DISCLOSED, never silent: a reconstructed row is a weaker claim than a measured one, so a reader
            // is told how many rows just changed confidence class and how many could not be healed at all.
            // The unresolved count is a FLOOR on what is missing, not a total of what is wrong: a member set
            // that no longer clones in THIS tree is unanswerable here, not proven gone.
            if( backfilled.resolved > 0 || backfilled.refreshed > 0 || backfilled.unverified > 0 || backfilled.unresolved > 0 )
            {
                rw::emitTo( stderr, "ripwire: ack provenance backfill — {} clone row(s) reconstructed from the current tree, {} re-derived, {} left UNVERIFIED (their group was not found here — a floor, not proof it is gone), "
                                      "{} left legacy (member set not found cloning here — a floor, not proof it is gone), {} ineligible (no current-tree fact answers their kind), {} already measured (left alone). "
                                      "prov=recon is what the idiom is NOW, as of the last run that could check it — not what was measured when the row was accepted.\n",
                              backfilled.resolved, backfilled.refreshed, backfilled.unverified, backfilled.unresolved, backfilled.ineligible, backfilled.measured );
            }

            std::size_t ackWritten = 0, ackSkipped = 0;
            for( const quality::Regression& r : regs )
            {
                if( !ackSelected( r, /*inScope=*/true ) ) { ++ackSkipped;  continue; }
                ++ackWritten;
                // P0.3: the ack IDENTITY is ackKindToken, not the bare kind — a zero-magnitude finding
                // (was==now==0: dead-code, api-surface tier A) acks per ORIGIN, so acking the never-gating
                // new-symbol row can no longer blank-check the gating contract-change row on the same symbol.
                const std::string   ackKind = quality::ackKindToken( r );
                quality::AckRecord& rec     = acks[ quality::ackMapKey( ackKind, r.key ) ];
                // R1 IDENTITY: stamp the finding's SCRUBBED CONTENT ID alongside the key, so this ack can
                // still be found after a move git records no rename for. Absent (0) for the two clone kinds —
                // their key is a member-SET hash with no single body behind it — and the row is then written
                // exactly as it is today. A REFRESH, not a preserve: re-acking a finding re-reads the body, so
                // the stored cid always describes the code as accepted, never as it was two edits ago.
                const auto          cidIt   = basis.healing.cids.cidByKey.find( r.key );
                const std::uint64_t cid     = ( cidIt == basis.healing.cids.cidByKey.end() ) ? 0u : cidIt->second;
                // P1.4 PROVENANCE: `by` follows the SAME rule the reason does one line down — set from this
                // run when this run supplies one, PRESERVED otherwise. A later scope-less re-ack therefore
                // refreshes the magnitude without erasing the record of who accepted the row originally,
                // which is the only reading under which the foreign-ack sweep means anything.
                // REASON CLOBBER FIX (round 2026-08-29): a re-ack that supplies a DIFFERENT reason no longer
                // overwrites the row's existing one outright — composeAckReason folds it in as
                // "<new> | prior: <old>" (capped at one hop; a no-op when the reason is unchanged), so a
                // shared row re-acked by unrelated sessions keeps both justifications instead of the last
                // writer silently erasing the one before it. See quality.h's composeAckReason for the rule.
                // RE-SCORE PROVENANCE: was/now/facet/path/line are a REFRESH, not a preserve, same posture as
                // cid= above — a re-ack re-reads the finding, so the stored triple always describes the row AS
                // JUST ACCEPTED, never as it was some earlier run. See AckRecord's doc comment for what each
                // one is and why a later run can re-score from them alone.
                rec = quality::AckRecord{ ackKind, r.key, std::max( rec.ackNow, r.now ), cid,
                                          scope.active() ? scope.spec : rec.by,
                                          r.was, r.now, r.facet, r.path, r.line, quality::AckProvenance::Measured,
                                          cfg.qualityAckReason.empty() ? rec.reason
                                                                       : quality::composeAckReason( rec.reason, std::string( cfg.qualityAckReason ) ) };
                // SELF-CHECK, not a one-off test: every magnitude-bearing ack proves that the TABLE-DRIVEN
                // re-score formula agrees with the LIVE one on the row it just built. NOT a full round trip —
                // rescoreAckRecord runs here on the in-memory `rec` directly; it never goes through
                // renderAckRecords/readAckRecords, so this does not exercise the ledger's text grammar (order-
                // tolerant token parsing, splitAckLocator, the takeAckNamedToken family) at all — that half of
                // the contract is what qackconcurrencycheck.sh's grammar arm (2) and byte-identity arm (7) pin
                // instead, over the actual file. What THIS catches: rescoreNumericMajor's kMaterialityBars
                // lookup (by kind name) silently drifting from the bar/minorDelta/growthTiered literals
                // perSymbolKind was called with (computeDelta, above) — two spellings of the same three
                // constants that a future edit could change in only one place. A drift there means the live
                // formula (numericRegressionIsMajor, via perSymbolKind) and the re-score formula
                // (rescoreNumericMajor) have silently diverged — see quality.h's MaterialityBar table, the one
                // place both are meant to agree. ENSURES, not ASSUME: this is this function's OWN postcondition
                // on the row it just built, not a fact something else already guarantees.
                const std::optional<bool> rescored      = quality::rescoreAckRecord( rec );
                const bool                rescoreAgrees = !rescored.has_value() || *rescored == !r.isMinor;   // plain bool, so the promise below is a bare accessor-free read
                ENSURES( rescoreAgrees,
                         "ack provenance re-score (in-memory, not a ledger round trip) must reproduce the just-computed severity" );
            }
            if( ackWritten == 0 && !cfg.qualityAckOnly.empty() )
            {
                // M1 FOLLOW-UP (round train-18, rv-ack-provenance-backfill.md): this refusal used to discard
                // the backfill above unconditionally — `backfillCloneAckProvenance` already mutated `acks` in
                // memory, but returning here without ever calling writeAckRecords threw that healing away,
                // so a rubber-stamp-guarded --ack-only that (correctly) refused to accept anything ALSO
                // silently un-did an otherwise-independent repair to the ledger's provenance. Same
                // canonical-bytes rule H10's ackNothingToAccept applies when there is nothing to accept at
                // all: a ledger already equal to its own canonical bytes is left untouched (no spurious
                // diff); a non-canonical one — including one this run's backfill just healed — is rewritten
                // and the run says so. This never accepts a finding and the refusal's exit code is unchanged.
                const bool nonCanonical = !acks.empty()
                    && quality::renderAckRecords( acks ) != docparse::detail::readRegularFile( "the quality-acks ledger", acksFile ).value_or( std::string() );
                if( nonCanonical )
                {
                    // A failed heal is said, not folded into "nothing written" (CodeRabbit on #331): the same
                    // "could not write" ackNothingToAccept prints for the same failure. writeAckRecords has already
                    // DISCLOSEd on its answerRefused sink; the exit code is 1 either way.
                    if( !quality::writeAckRecords( acksFile, acks ) )
                    {
                        rw::emitTo( stderr, "ripwire: --ack-only={} matched none of the {} finding(s) — nothing accepted; could not write {} "
                                              "(it was not in canonical form, and re-serialising it failed)\n",
                                      std::string_view( cfg.qualityAckOnly.data(), cfg.qualityAckOnly.size() ), regs.size(), acksFile.c_str() );
                        return 1;
                    }
                    rw::emitTo( stderr, "ripwire: --ack-only={} matched none of the {} finding(s) — nothing accepted, but {} was not in canonical form "
                                          "(ack provenance backfill / legacy rows) and has been re-serialised\n",
                                  std::string_view( cfg.qualityAckOnly.data(), cfg.qualityAckOnly.size() ), regs.size(), acksFile.c_str() );
                    return 1;
                }
                rw::emitTo( stderr, "ripwire: --ack-only={} matched none of the {} finding(s) — nothing written\n", std::string_view( cfg.qualityAckOnly.data(), cfg.qualityAckOnly.size() ), regs.size() );
                return 1;
            }
            // H10: nothing to accept — leave a canonical ledger alone, heal a non-canonical one (ackNothingToAccept)
            if( regs.empty() )
            {
                return ackNothingToAccept( acksFile, acks, scope, outOfScope.size() );
            }
            const bool wroteAcks = quality::writeAckRecords( acksFile, acks );
            if( wroteAcks && !cfg.qualityAckOnly.empty() )
            {
                rw::emitTo( stderr, "ripwire: acknowledged {} of {} finding(s) ({} left UNACKED by --ack-only, {} already acked) → {}\n",
                              ackWritten, regs.size(), ackSkipped, ackedCount, acksFile.c_str() );
            }
            else if( wroteAcks )
            {
                rw::emitTo( stderr, "ripwire: acknowledged {} finding(s) ({} already acked) → {}\n",
                              regs.size(), ackedCount, acksFile.c_str() );
            }
            else
            {
                rw::emitTo( stderr, "ripwire: could not write {}\n", acksFile.c_str() );
            }
            // P1 — the skip is DISCLOSED, never silent: the count of rows this ack deliberately did not
            // touch is the whole reason the caller passed a scope, and a quiet success would leave them
            // believing the ledger now covers the report they were looking at.
            if( wroteAcks && scope.active() && !outOfScope.empty() )
            {
                rw::emitTo( stderr, "ripwire: {} finding(s) OUT OF SCOPE for --scope={} were left unacked — not yours to accept "
                                      "(they are still in the report, under the out-of-scope element)\n",
                              outOfScope.size(), scope.spec.c_str() );
            }
            return wroteAcks ? 0 : 1;
        }

        // L2 — stale-ack disclosure (rationale: quality.h's computeStaleAcks). Checked against the CURRENT
        // tree, not the baseline above, so it costs one more computeSnapshot; skipped when the ledger is
        // empty. Reported, never gated — the exit code below reads `regs` alone.
        // R-I: "the CURRENT tree" is the JUDGED tree, which in the ref-pair form is tree B — checking the
        // ledger against the working tree there would report acks as stale because of edits that have nothing
        // to do with the comparison being made.
        // qd-memory-degrade: refPairStaleAcks owns the two range-form departures (a changed-files answer judges none; a
        // kind selection judges its own kinds' acks only).
        const std::vector<quality::StaleAck> staleAcks = acks.empty() ? std::vector<quality::StaleAck>{}
                                                         : refPair ? refPairStaleAcks( acks, refs )
                                                         : quality::computeStaleAcks( acks, quality::computeSnapshot( ing, g, cfg.rootPath ) );

        // P1.4 — the <sa> family now carries THREE whys, and the third is counted SEPARATELY: stale= means
        // "this ack no longer applies", and a foreign ack applies fine — it is the SESSION that was wrong,
        // not the target. Merging the rows into one list keeps the two emitters from growing a second loop
        // each; keeping the COUNTS apart keeps stale= meaning what it has always meant.
        std::vector<quality::StaleAck> saRows = staleAcks;
        saRows.insert( saRows.end(), foreignAcks.begin(), foreignAcks.end() );
        // M21(a): name the rows the tree can still name, against the SAME tree computeStaleAcks judged
        // (tree B in the ref-pair form) — naming a stale ack after the working tree would print an identity
        // the verdict was never computed from. Costs one walk over ing.symbols, and only when there are rows.
        quality::stampStaleAckIdentity( saRows, refPair ? refs.target().ing : ing,
                                        refPair ? std::string_view( refs.target().root ) : std::string_view( cfg.rootPath ) );

        // r26 ORIGIN SPLIT — three counts over the VISIBLE (post-ack) findings, one pass:
        //   minorCount      — the materiality tier (unchanged axis).
        //   newSymbolCount  — findings that exist only because the code is NEW (quality.h's origin axis).
        //   gatingCount     — the EXIT PREDICATE (quality::rowGates): major AND preexisting-worse, or a defect-shape
        //                     format-arity row of any origin. Emitted as gating= so the header alone tells you
        //                     the exit code (it used to be "regressions > minor").
        // preexisting-worse = regressions − new-symbol by construction (the axis is a partition), so the two
        // header counters always sum to regressions= — an invariant the gate asserts.
        std::size_t minorCount = 0, newSymbolCount = 0, gatingCount = 0;
        for( const quality::Regression& r : regs )
        {
            if( r.isMinor )
            {
                ++minorCount;
            }
            if( r.isNewSymbol )
            {
                ++newSymbolCount;
            }
            if( quality::rowGates( r ) )
            {
                ++gatingCount;
            }
        }
        const std::size_t preexistingCount = regs.size() - newSymbolCount;
        // H11 — the absorbed-debt stamp on the honored sidecar, or 0. Read ONLY when the sidecar is the floor
        // in force: on the git-HEAD and ref-pair floors there is no pin whose contents could have absorbed
        // anything, and printing a 0 there would define an attribute about a file this run did not use.
        const std::size_t baselineAbsorbed = ( baseSel.marker == std::string_view( "sidecar" ) )
                                           ? quality::readBaselineAbsorbed( baselineFile ) : 0;
        const std::string baselineAbsorbedAttr = baselineAbsorbed == 0 ? std::string()
                                               : " baseline_absorbed=\"" + std::to_string( baselineAbsorbed ) + "\"";

        // R1 IDENTITY — the disclosure, built ONCE for both emitters (quality::identityDisclosure). An ack
        // that follows a rename is a claim about identity, and a claim is only honest if the reader can see
        // what it rested on; building the XML and JSON halves in one place is what keeps the two surfaces
        // from disclosing different things about the same run.
        const auto [ identityAttrs, identityJson ] = quality::identityDisclosure( basis.healing );

        // P1/P1.4 — the scope disclosure, built once for both emitters (quality::scopeDisclosure).
        const auto [ scopeAttrs, scopeJson ] = quality::scopeDisclosure( scope, outOfScope.size(), scopedOutGating, foreignAcks.size(), diffFileCount );

        // F-13 — the .ripwire_config disclosure, built once for both emitters (see the header comment on
        // registerMacroConfigWarningAttr just above runQualityViews for why the stderr wording lives there).
        // #387: the inert-name test reads the JUDGED tree's index, which in the ref-pair form is tree B — the working tree
        // is not indexed there at all (runQualityDeltaRangeBeforeIngest).
        // qd-memory-degrade: not over a changed-files index, which cannot tell an inert name from one the tree defines (also_skipped=)
        const rw::quality::RegisterMacroConfigDiagnostics configDiag = refs.degraded ? rw::quality::RegisterMacroConfigDiagnostics{}
                                                                                     : rw::quality::diagnoseRegisterMacroConfig( judged, root );
        const std::string configWarnAttr = registerMacroConfigWarningAttr( configDiag );
        // qd-memory-degrade: the kinds this answer did not run, why, and the replay — plus the peak, read once now that the
        // comparison is done (kindsDisclosure). Their stderr lines come first: an answer that is partial, or that ran past
        // the limit, says so on the channel a human reads before anything else.
        const KindsDisclosure kd = kindsDisclosure( cfg, refs, basis, refPair );
        emitMemoryLines( kd, refs );
        const bool deadRan = !refPair || quality::kindSelected( refs.kinds, "dead-code" );   // dead-code's side counts exist only when it ran

        // P2.5 — one stderr line NAMING the gating finding, in --token-budget's style ("ripwire: --token-budget
        // exceeded: est_tokens=… > budget=…"). stdout is the machine artifact and a caller that only checks
        // `$?` gets a number with no subject; this puts the WHICH on the channel a human reads, without
        // touching the XML contract. Names the first gating row in the already-sorted list (deterministic).
        //
        // §A4 (minor): emitted BEFORE the format fork, not after the XML tail — under --json the fork returned
        // first, so exactly the caller most likely to be a script reading `$?` got the bare exit=2 with no
        // subject. The line is about the EXIT CODE, which both formats share, so it belongs to neither.
        if( gatingCount > 0 )
        {
            const quality::Regression* first = nullptr;
            for( const quality::Regression& r : regs )
            {
                if( quality::rowGates( r ) ) { first = &r; break; }
            }
            if( first )
            {
                const std::string at = first->path.empty() ? std::string{}
                                                           : " at " + first->path + ":" + std::to_string( first->line );
                // M12: displaySym, not first->sym raw — the XML/JSON rows both normalize sym's path segment
                // for display (quality::displaySym); this stderr line was the one caller that skipped it,
                // so it named "./src/…::rw::…" beside a row that named the same finding "src/…::rw::…".
                // a gating row on NEW code is only ever defect-shape format-arity (rowGates); the line names that
                // part only when there is one, so every run without it keeps its bytes.
                const std::size_t newGating = static_cast<std::size_t>( std::count_if( regs.begin(), regs.end(), []( const quality::Regression& r )
                                                                                       { return r.isNewSymbol && quality::rowGates( r ); } ) );
                if( newGating == 0 )
                {
                    rw::emitTo( stderr, "ripwire: --quality-delta gating: {} preexisting-worse major finding(s); first: {} {}{} (was={} now={})\n",
                                  gatingCount, first->kind.c_str(), quality::displaySym( first->sym, deltaRoot ).c_str(), at.c_str(), first->was, first->now );
                }
                else
                {
                    rw::emitTo( stderr, "ripwire: --quality-delta gating: {} gating finding(s), {} of them defect-shape format-arity on new code; first: {} {}{} (was={} now={})\n",
                                  gatingCount, newGating, first->kind.c_str(), quality::displaySym( first->sym, deltaRoot ).c_str(), at.c_str(), first->was, first->now );
                }
            }
        }

        // L2: --json — same regressions, keys mirror the XML attr names (kind/sym/members/tokens/was/now/
        // sev/churn/surface). jsonUnsupportedVerb already refused --quality-baseline/--quality-ack, so
        // reaching here with cfg.json means the plain --quality-delta report.
        if( cfg.json )
        {
            const char* baseMarkerJ = baseSel.marker;   // R3: the one spelling table lives in quality::selectBaseline — the XML/JSON twins cannot drift apart
            // The JSON sibling of the XML at= anchor — "at":null (never a fake sha) on a non-git root, and
            // null in the ref-pair form too: the list was not computed "at" any working-tree state, and the
            // two refs below ARE its anchor.
            const std::string atValJ  = refPair ? std::string{} : gitstamp::stampAt( root );
            const std::string atJsonJ = atValJ.empty() ? std::string( "null" ) : ( "\"" + atValJ + "\"" );
            // R-I: the same two shas + the same unmeasurable-kind disclosure the XML root carries, spelled in
            // JSON. Empty for the bare form, so that object stays byte-identical to before.
            // F-13: config-warnings is the JSON sibling of the XML config-warnings= attribute — omitted
            // (never 0) when .ripwire_config carried nothing to disclose, same "absent means never happened,
            // 0 means checked and clean" rule scopeJson/identityJson already follow.
            const std::string configWarnJson = configDiag.total() == 0 ? std::string()
                                              : ",\"config-warnings\":" + std::to_string( configDiag.total() );
            // H11: the JSON twin of baseline_absorbed=, under the same absent-means-none rule as the XML half.
            const std::string absorbedJson = baselineAbsorbed == 0 ? std::string()
                                            : ",\"baseline_absorbed\":" + std::to_string( baselineAbsorbed );
            // #228: the JSON twin of head_basis=, under the same absent-means-the-ordinary-archived-tree rule.
            const std::string headBasisJson = ( basis.headBasis == nullptr ? std::string()
                                              : std::string( ",\"head_basis\":\"" ) + basis.headBasis + "\"" )
                                            + ( basis.declinedCallExcluded == 0 ? std::string()   // the XML twin's declined-call-excluded=, absent at zero
                                              : ",\"declined-call-excluded\":" + std::to_string( basis.declinedCallExcluded ) )
                                            + rw::countFieldOrEmpty( "value-ref-excluded", basis.valueRefExcluded, /*json=*/true );
            // qd-memory-degrade: stale and register-macro-excluded are absent (never 0) when their pass did not run
            const std::string staleJ = refs.degraded ? std::string() : ",\"stale\":" + std::to_string( staleAcks.size() );
            const std::string rmeJ   = deadRan ? ",\"register-macro-excluded\":" + std::to_string( basis.registerMacroExcluded ) : std::string();
            rw::emitTo( stdout, "{{\"baseline\":\"{}\",\"regressions\":{},\"minor\":{},\"acked\":{}{},"
                         "\"preexisting-worse\":{},\"new-symbol\":{},\"gating\":{}{},\"api-new-surface\":{},\"at\":{}{}{}{}{}{}{}{},\"r\":[",
                         jsonStr( baseMarkerJ ).c_str(), regs.size(), minorCount, ackedCount, staleJ,
                         preexistingCount, newSymbolCount, gatingCount, rmeJ, basis.apiNewSurface, atJsonJ.c_str(), refs.jsonAttrs.c_str(),
                         identityJson.c_str(), scopeJson.c_str(), configWarnJson.c_str(), absorbedJson.c_str(), headBasisJson.c_str(), kd.json );
            // P1: one row emitter, called for both halves of the scope partition — the disclosed rows carry
            // the identical key set, so nothing about a row changes by being someone else's. `gatingAllowed`
            // is the ONE difference: an out-of-scope row is not what the exit code fires on, so claiming
            // gating on it would contradict the exit code in the same document.
            const auto emitJsonRow = [ & ]( const quality::Regression& r, bool gatingAllowed )
            {
                rw::emitTo( stdout, "{{\"kind\":\"{}\"", jsonStr( r.kind ).c_str() );
                if( r.kind == "duplication" )
                {
                    rw::emitTo( stdout, ",\"members\":\"{}\",\"tokens\":{}", jsonStr( quality::displaySym( r.sym, deltaRoot ) ).c_str(), r.now );
                }
                else
                {
                    rw::emitTo( stdout, ",\"sym\":\"{}\"", jsonStr( quality::displaySym( r.sym, deltaRoot ) ).c_str() );
                    if( !( r.kind == "dead-code" ) && !( r.kind == "api-surface" && r.was == r.now ) )
                    {
                        rw::emitTo( stdout, ",\"was\":{},\"now\":{}", r.was, r.now );
                    }
                }
                if( !r.path.empty() )
                {
                    rw::emitTo( stdout, ",\"p\":\"{}:{}\"", jsonStr( r.path ).c_str(), r.line ); // P2.5 locator
                }
                if( gatingAllowed && quality::rowGates( r ) )
                {
                    rw::emitRaw( stdout, ",\"gating\":true" ); // P2.5 — the exit predicate, stated per row
                }
                if( r.isMinor )
                {
                    rw::emitRaw( stdout, ",\"sev\":\"minor\"" );
                }
                if( !r.facet.empty() )
                {
                    const char* facetName = quality::facetAttrName( r.kind );   // ONE kind→name table (quality.h)
                    if( facetName )
                    {
                        rw::emitTo( stdout, ",\"{}\":\"{}\"", facetName, jsonStr( r.facet ).c_str() );
                    }
                }
                if( r.isNewSymbol )
                {
                    rw::emitRaw( stdout, ",\"origin\":\"new-symbol\"" ); // absent = preexisting-worse (mirrors the XML)
                }
                rw::emitRaw( stdout, "}" );
            };
            bool firstR = true;
            for( const quality::Regression& r : regs )
            {
                if( !firstR )
                {
                    rw::emitRaw( stdout, "," );
                }
                firstR = false;
                emitJsonRow( r, /*gatingAllowed=*/true );
            }
            rw::emitRaw( stdout, "]," );
            if( scope.active() )
            {
                // The JSON sibling of the XML out-of-scope element: a SEPARATE array, never a flag on a row
                // in "r", so a consumer that reads "r" and checks "gating" cannot accidentally count someone
                // else's debt as this run's. Emitted (possibly empty) whenever a scope was given, so its
                // absence means "no scope", never "no disclosed rows".
                rw::emitRaw( stdout, "\"oos\":[" );
                bool firstO = true;
                for( const quality::Regression& r : outOfScope )
                {
                    if( !firstO )
                    {
                        rw::emitRaw( stdout, "," );
                    }
                    firstO = false;
                    emitJsonRow( r, /*gatingAllowed=*/false );
                }
                rw::emitRaw( stdout, "]," );
            }
            std::fputs( quality::staleAcksJsonArray( saRows ).c_str(), stdout );   // L2 — "sa":[...], same taxonomy as the XML sa= rows below
            rw::emitRaw( stdout, "}" );
            return qualityDeltaExit( gatingCount, refs );
        }

        std::vector<char> esc;
        const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // §B7.1 (CA4) — the heading used to open "only what changed for the WORSE vs
        // .ripwire_quality_baseline", which is FALSE in every state but one: three of the five floors this
        // verb can use are not that file, and in one of them the file was judged stale and DELETED from the
        // user's tree during this very run. The floor actually used is named by baseline= on the element
        // below, so the heading points at that attribute instead of asserting a floor.
        //
        // 2026-09-02 (lane B): the marker states are still defined on the first screen — the only place a
        // reader meets them — but ONE state per run, the one in force, rather than all five on every call.
        // emitQualityDeltaLegend above holds the section table and the reasoning; it is passed the same
        // values the root element below prints, so "the legend defines what the header emits" is read off
        // one set of values rather than restated as a second condition that could drift from it.
        // idea #11 — THE CLEAN-TREE PAYLOAD. A regression-free answer collapses its stale-ack rows to counts (stale= and
        // stale_by_kind=), and stale_next= is the call that prints them; on a tree that IS its HEAD (head_basis="identity":
        // the floor is this tree's own snapshot) with nothing else to disclose, the verdict is the whole answer. Foreign-
        // scope rows are never collapsed: they are about findings suppressed RIGHT NOW. --show-stale restores today's
        // document byte for byte, so every collapsed row and attribute is one flag away (PROCESS rule 5).
        const bool collapseStale = regs.empty() && outOfScope.empty() && !cfg.showStale && !staleAcks.empty();
        std::string staleCollapseAttrs;
        if( collapseStale )
        {
            const std::string kinds = quality::staleByKindValue( staleAcks );   // shared with the MCP twin (lane lean2b)
            std::string replay = cfg.qualityDeltaRange.empty() ? std::string( "--quality-delta" ) : rw::nextFlag( "--quality-delta=", cfg.qualityDeltaRange );
            if( scope.active() )
            {
                replay += " " + rw::nextFlag( "--scope=", cfg.qualityScope );
            }
            staleCollapseAttrs = " stale_by_kind=\"" + ex( kinds ) + "\"" + rw::nextAttrXml( replay + " --show-stale", "stale_next" );
        }
        const bool verdictOnly = collapseStale && !refPair && basis.headBasis != nullptr && std::string_view( basis.headBasis ) == "identity"
                              && !scope.active() && foreignAcks.empty() && ackedCount == 0 && configDiag.total() == 0 && baselineAbsorbed == 0
                              && basis.apiNewSurface == 0 && baseSel.sidecarBadLines == 0 && basis.acksBadLines == 0;
        // P1: ONE row emitter for both halves of the scope partition — a disclosed row carries the identical
        // attribute set, because nothing about a finding changes by belonging to someone else. `gatingAllowed`
        // is the one difference: an out-of-scope row is not what the exit code fires on, and a gating
        // attribute on it would contradict the header's own gating counter inside the same document.
        const auto emitRow = [ & ]( std::FILE* out, const quality::Regression& r, bool gatingAllowed )
        {
            // duplication carries a member LIST (members=) + token count; the per-symbol was/now kinds
            // (complexity/verbosity/nesting/params) carry was/now; api-surface + dead-code are sym-only.
            // sev="minor" marks a below-materiality delta (never gates); absent = major.
            const char* sev = r.isMinor ? " sev=\"minor\"" : "";
            // B10.2 — the optional classification facet: attribute NAME is chosen by kind (churn=
            // short-horizon-churn's self/ambient split; surface= api-surface's new-symbol/contract-change
            // tier; idiom= the duplication kind's recognized clone-body shape); r.facet carries only the
            // VALUE, and quality::facetAttrName is the ONE table that maps kind → attribute name for all
            // three emitters (this one, the --json twin above, and the MCP one).
            std::string facetAttr;
            if( !r.facet.empty() )
            {
                const char* facetName = quality::facetAttrName( r.kind );
                if( facetName )
                {
                    facetAttr = std::string( " " ) + facetName + "=\"" + r.facet + "\"";
                }
            }
            // r26 — the ORIGIN axis, emitted LAST so the existing attribute order is untouched. Present only
            // on new-symbol rows (absent = preexisting-worse), the same "mark the exception" convention sev=
            // uses. api-surface's own surface="new-symbol" facet is the same fact narrowed to that kind; it
            // stays for shape compatibility, and origin= is what the exit gate reads.
            const char* origin = r.isNewSymbol ? " origin=\"new-symbol\"" : "";
            // P2.5 — the two attributes that make a row ACTIONABLE, appended last so every pre-r27 attribute
            // keeps its position:
            //   p="path:line" — sym= is a canonical id whose display tail is often a bare one-letter local
            //     (`sym="cc"`), i.e. ungreppable. Omitted, never faked, when no locator was resolvable.
            //   gating="1"    — marks exactly the rows the header's gating= counts and the exit code fires on.
            //     Until now a gating row was identifiable ONLY by the ABSENCE of sev="minor" (and of
            //     origin="new-symbol") — absence-as-signal is the least machine-friendly encoding available.
            std::string locAttr;
            if( !r.path.empty() )
            {
                locAttr = " p=\"" + ex( r.path ) + ":" + std::to_string( r.line ) + "\"";
            }
            const char* gatingAttr = ( gatingAllowed && quality::rowGates( r ) ) ? " gating=\"1\"" : "";
            // P8 (L7): the threshold beside the number it judges — bar= on the four numeric kinds (quality.h's
            // kCcxBar/kLocBar/kNestBar/kParamBar), so was=/now= read without the legend.
            const char* barAttr = r.kind == "complexity" ? " bar=\"15\"" : r.kind == "verbosity" ? " bar=\"60\""
                                : r.kind == "nesting"    ? " bar=\"4\""  : r.kind == "params"    ? " bar=\"5\""  : "";
            // P3 (L7, nextverb.h): a GATING row hands the agent the body to fix — --expand=FILE:NAME (the file-qualified
            // selector, so a same-named symbol elsewhere cannot answer). The name is the sym key's last :: segment;
            // duplication rows name a SET (members=) and carry no single body to open, nor does a FILE-anchored
            // defect-shape row (top-level code: sym= is the path, and --expand=FILE:FILE matches no symbol).
            std::string nextAttr;
            if( *gatingAttr && !r.path.empty() && r.kind != "duplication" && !( r.kind == "defect-shape" && r.sym == r.path ) )
            {
                const std::size_t    sep  = r.sym.rfind( "::" );
                const std::string    bare = sep == std::string::npos ? r.sym : r.sym.substr( sep + 2 );
                nextAttr = rw::nextAttrXml( rw::nextFlag( "--expand=", r.path + ":" + bare ) );
            }
            if( r.kind == "duplication" )
            {
                rw::emitTo( out, "<r kind=\"duplication\" members=\"{}\" tokens=\"{}\"{}{}{}{}{}/>", ex( quality::displaySym( r.sym, deltaRoot ) ).c_str(), r.now, sev, facetAttr.c_str(), origin, locAttr.c_str(), gatingAttr );
            }
            else if( r.kind == "dead-code" )
            {
                rw::emitTo( out, "<r kind=\"{}\" sym=\"{}\"{}{}{}{}{}{}/>", r.kind.c_str(), ex( quality::displaySym( r.sym, deltaRoot ) ).c_str(), sev, facetAttr.c_str(), origin, locAttr.c_str(), gatingAttr, nextAttr.c_str() );
            // B10.2e: api-surface now carries two shapes — a brand-new/newly-public symbol (was=now=0, no
            // param comparison to show) and a param-count contract-change (was/now = the real counts). Print
            // was/now whenever they differ from each other so the contract-change case's was=/now= is visible
            // while the new-symbol case's meaningless was="0" now="0" is omitted, matching its old sym-only shape.
            }
            else if( r.kind == "api-surface" && r.was == r.now )
            {
                rw::emitTo( out, "<r kind=\"{}\" sym=\"{}\"{}{}{}{}{}{}/>", r.kind.c_str(), ex( quality::displaySym( r.sym, deltaRoot ) ).c_str(), sev, facetAttr.c_str(), origin, locAttr.c_str(), gatingAttr, nextAttr.c_str() );
            }
            else
            {
                rw::emitTo( out, "<r kind=\"{}\" sym=\"{}\" was=\"{}\" now=\"{}\"{}{}{}{}{}{}{}/>", r.kind.c_str(), ex( quality::displaySym( r.sym, deltaRoot ) ).c_str(), r.was, r.now, barAttr, sev, facetAttr.c_str(), origin, locAttr.c_str(), gatingAttr, nextAttr.c_str() );
            }
        };
        // Fix round 1 (rv-lean-trio item 5, owner ruling 5): a fold ships only when it PAYS (compactlegend.h foldPays: shorter
        // by its margin, as written AND as the compact layer delivers it). The whole XML document is one renderer over a FILE*,
        // so both candidates are rendered and measured, and the full document wins a fold that does not pay or a failed render
        // (fx, dirty tree, one stale ack: 1512 B folded vs 1481 B full).
        // `collapse` picks the stale rows' form: true serves only the foreign-scope rows and the stale_by_kind=/stale_next= counts.
        // R-I: at= is OMITTED for the ref-pair form (see the root below). Read ONCE: both candidates print the same stamp.
        const std::string atAttrs = refPair ? std::string() : gitstamp::atAttr( root );
        const auto emitDocument = [ & ]( std::FILE* out, bool collapse )
        {
            const std::vector<quality::StaleAck>& served = collapse ? foreignAcks : saRows;
            emitQualityDeltaLegend( { baseSel.marker, refPair, identityAttrs, !served.empty(), ackedCount > 0,
                                      basis.registerMacroExcluded > 0, configDiag.total() > 0, regs, outOfScope,
                                      scope.active() || !foreignAcks.empty(), !foreignAcks.empty(), baselineAbsorbed,
                                      basis.headBasis, basis.declinedCallExcluded > 0, basis.valueRefExcluded > 0, collapse,
                                      refs.kinds != quality::kAllKinds, refs.degraded, !refs.memoryStop.empty(), kd.peakOver != 0,
                                      kd.memorySkipped != 0 && refs.selected != quality::kAllKinds }, out );
            const char* baseMarker = baseSel.marker;    // R3: ditto — one seam decides staleness AND names it
            // 2026-09-06: what the sidecar readers skipped, on the root (absent means none) — see kQdBaseHeadUnreadable
            std::string sidecarHealthAttrs;
            if( baseSel.sidecarBadLines > 0 ) { sidecarHealthAttrs += " baseline_bad_lines=\"" + std::to_string( baseSel.sidecarBadLines ) + "\""; }
            if( basis.acksBadLines > 0 )      { sidecarHealthAttrs += " acks_bad_lines=\"" + std::to_string( basis.acksBadLines ) + "\""; }
            // #228: present-only, and its absence is the ordinary archived HEAD tree — the floor every git-HEAD
            // marker named on its own before this attribute existed.
            if( basis.headBasis != nullptr )  { sidecarHealthAttrs += std::string( " head_basis=\"" ) + basis.headBasis + "\""; }
            if( basis.declinedCallExcluded > 0 ) { sidecarHealthAttrs += " declined-call-excluded=\"" + std::to_string( basis.declinedCallExcluded ) + "\""; }
            sidecarHealthAttrs += rw::countAttrXmlOrEmpty( "value-ref-excluded", basis.valueRefExcluded );   // absent at zero, beside its sibling
            // at= anchors this regression list to the commit (+dirty state) it was computed against.
            // qd-memory-degrade: stale= and register-macro-excluded= are absent (never 0) when their pass did not run
            const std::string staleX = refs.degraded ? std::string() : " stale=\"" + std::to_string( staleAcks.size() ) + "\"";
            const std::string rmeX   = deadRan ? " register-macro-excluded=\"" + std::to_string( basis.registerMacroExcluded ) + "\"" : std::string();
            rw::emitTo( out, "<quality-delta baseline=\"{}\" regressions=\"{}\" minor=\"{}\" acked=\"{}\"{} preexisting-worse=\"{}\" new-symbol=\"{}\" gating=\"{}\"{} api-new-surface=\"{}\"{}{}{}{}{}{}{}>",
                         baseMarker, regs.size(), minorCount, ackedCount, staleX, preexistingCount, newSymbolCount, gatingCount, rmeX, basis.apiNewSurface,
                         // R-I: at= is OMITTED for the ref-pair form rather than stamped with the working tree's
                         // sha, which would anchor the list to a commit it was not computed from. base_ref= and
                         // target_ref= are the anchor there, and they carry FULL shas because a wave measurement
                         // gets quoted into handoffs where a 9-char prefix is one collision from unverifiable.
                         atAttrs.c_str(), refs.attrs.c_str(), identityAttrs.c_str(),
                         scopeAttrs.c_str(), configWarnAttr.c_str(), baselineAbsorbedAttr.c_str(), ( sidecarHealthAttrs + ( collapse ? staleCollapseAttrs : std::string() ) + kd.xml ).c_str() );
            for( const quality::Regression& r : regs )
            {
                emitRow( out, r, /*gatingAllowed=*/true );
            }
            if( scope.active() )
            {
                // P1 — the DISCLOSURE half. Dropping these rows would make a scoped report a quieter lie than
                // the unscoped one it replaces: the debt is real, it is in the same tree, and it will be in
                // someone's report. So they are printed, in their own element, marked non-gating, with the one
                // sentence a reader needs written where they meet it. Emitted even when EMPTY — an absent
                // element then means "no scope was given", never "nobody else has anything open".
                rw::emitTo( out, "<out-of-scope n=\"{}\" would-gate=\"{}\" note=\"not yours - do not ack: these rows lie outside the scope this run named. "
                             "They are disclosed rather than hidden, they never gate this exit code, and the ack refuses to write them.\">",
                             outOfScope.size(), scopedOutGating );
                for( const quality::Regression& r : outOfScope )
                {
                    emitRow( out, r, /*gatingAllowed=*/false );
                }
                rw::emitRaw( out, "</out-of-scope>" );
            }
            {   // L2 — one <sa> row per stale ack (quality::staleAcksXml). M21(a): the escaper is passed in
                // because sym= carries a canonical id (corpus text), unlike the closed-vocabulary kind=/why=.
                std::vector<char> saEsc;
                std::fputs( quality::staleAcksXml( served, [ & ]( std::string_view t ) { return std::string( escapeXml( t, saEsc ) ); } ).c_str(), out );
            }
            rw::emitRaw( out, "</quality-delta>" );
        };
        // the identity-tree VERDICT (verdictOnly above): the root line alone
        const auto emitVerdict = [ & ]( std::FILE* out )
        {
            rw::emitTo( out, "<!-- ripwire quality-delta: the tracked files ARE their git HEAD (head_basis=\"identity\"), so the floor (baseline= "
                             "names it) is this tree's own snapshot and nothing that existed can be worse: regressions= and gating= are 0, and this line stands in "
                             "for the full document because it saves at least a quarter of the bytes. stale= counts ack "
                             "ledger rows whose target no longer applies (never gating), by kind in stale_by_kind=; stale_next= is the call "
                             "that prints them with the full header (its exclusion and rename counts included). at=: commit+dirty+shallow. -->"
                             "<quality-delta baseline=\"{}\" regressions=\"0\" gating=\"0\" stale=\"{}\"{} head_basis=\"identity\"{}></quality-delta>",
                        baseSel.marker, staleAcks.size(), atAttrs, staleCollapseAttrs );
        };
        if( !collapseStale )
        {
            emitDocument( stdout, /*collapse=*/false );
            return qualityDeltaExit( gatingCount, refs );
        }
        const Rendered full   = renderToString( [ & ]( std::FILE* f ) { emitDocument( f, /*collapse=*/false ); } );
        const Rendered folded = renderToString( [ & ]( std::FILE* f ) { if( verdictOnly ) { emitVerdict( f ); } else { emitDocument( f, /*collapse=*/true ); } } );
        if( !full.ok || !folded.ok )
        {
            // renderToString DISCLOSEd the failed buffer; the full document is the superset, written straight to stdout
            emitDocument( stdout, /*collapse=*/false );
            return qualityDeltaExit( gatingCount, refs );
        }
        const std::string& chosen = foldPays( folded.text, full.text ) ? folded.text : full.text;   // compactlegend.h: the margin and why
        std::fwrite( chosen.data(), 1, chosen.size(), stdout );
        return qualityDeltaExit( gatingCount, refs );   // r26: only a PREEXISTING-worse AND major regression gates (== gating=)
    }
    return std::nullopt;
}

// #387: the range form compares two COMMITTED trees, each materialized and indexed by loadRefPairDelta, and reads the
// working tree only for its path. main() used to index and graph that tree anyway before dispatch, so a one-commit range
// on a 20,000-file repository held three indexes at once and was OOM-killed at 8 GiB. When --quality-delta=A..B is the
// verb that answers (dispatch winner; a typed task or --quality-baseline beside it still outranks it), main() calls this
// before the working-tree ingest, and the handler reads only the judged tree's index. --pin-census keeps the old path:
// it writes the working tree's census as a side effect of any run that asks for it.
std::optional<int> runQualityDeltaRangeBeforeIngest( const rw::Config& cfg, const char* dispatchWinner, const std::string& root,
                                                      const std::vector<rw::WorkspaceRoot>& ws )
{
    if( cfg.qualityDeltaRange.empty() || !cfg.pinCensus.empty() || dispatchWinner == nullptr || std::string_view( dispatchWinner ) != "--quality-delta" )
    {
        return std::nullopt;
    }
    const rw::IngestResult           noWorkingTree;
    const rw::Graph                  noGraph;
    const rw::QMetrics               noMetrics;
    const std::vector<std::uint32_t> noFanIn;
    std::vector<std::uint32_t>       noChurn;
    rw::RedactCounts                 redactCounts;
    rw::RedactCounts* const          redactPtr = cfg.noRedact ? nullptr : &redactCounts;
    const MainDispatch dsp{ cfg, noWorkingTree, noGraph, root, /*multiRoot=*/false, ws, noFanIn, nullptr, noMetrics,
                            nullptr, nullptr, nullptr, nullptr, nullptr, noChurn, redactCounts, redactPtr, nullptr,
                            false, nullptr, false };
    return runQualityDelta( dsp );
}

// ── --dmm ────────────────────────────────────────────────────────────────────────────────────────────────
// The Delta Maintainability Model scalar — the TRENDABLE complement to --quality-delta above, and it sits
// here because the two answer the same question at different resolutions ("which kinds got worse" vs "how
// did this change score, on one scale"). dmm.h owns the whole computation and the emission; this handler
// resolves the flag, splits the ONE user-error case (a revision that does not resolve → a refusal that
// names the offending token, exit 1) from every environment case (no git, a root commit, an archive that
// failed → an UNAVAILABLE report, exit 0), and never gates: a maintainability score with a threshold on it
// is a score people write code to.
std::optional<int> runDmm( const MainDispatch& d )
{
    using namespace rw;
    const Config& cfg = d.cfg;

    if( !cfg.dmm )
    {
        return std::nullopt;
    }

    const dmm::Result r = dmm::computeDmm( d.root, cfg.dmmRange, d.ing, cfg.excludes, cfg.maxFileBytes );
    if( r.status == dmm::Status::BadRev )
    {
        rw::emitTo( stderr, "ripwire: --dmm: '{}' does not resolve to a commit in {}{}\n", r.badToken.c_str(), d.root.c_str(),
                      rw::gitstamp::shallowRefHint( d.root ) );   // 0.6.7: the likeliest cause on a depth-limited clone, "" otherwise
        return 1;
    }
    if( r.status == dmm::Status::BadRange )
    {
        rw::emitTo( stderr, "ripwire: --dmm: '{}' uses the three-dot form; --dmm compares two TREES, so spell it A..B "
                              "(or --dmm=$(git merge-base A B)..B if the merge base is what you meant)\n", r.badToken.c_str() );
        return 1;
    }
    return dmm::writeDmmReport( r );
}

// §A10.6: strips a REPEATED leading "./" so `./src`, `././src`, and `src` all compare on the same text —
// used to normalize both the user's --dead-code=DIR filter and every indexed path it is matched against.
inline std::string_view deadCodeStripDotSlash( std::string_view p ) noexcept
{
    while( p.size() >= 2 && p[0] == '.' && p[1] == '/' )
    {
        p.remove_prefix( 2 );
    }
    return p;
}

// §A10.6: the --dead-code=DIR path filter, hoisted out of runQualityViews so the branch lives on its own
// symbol instead of inflating that function's complexity. `anchoredAtRoot` (a LEADING ./ on the RAW arg,
// decided by the caller before dirFilter is normalized) restricts the match to path position 0 — the
// repo ROOT — instead of the default component-anywhere match (leading dir, trailing filename, or an
// interior directory, all at '/' boundaries so `sr` never matches `src/`). Allocation-free: called once
// per indexed file and once per candidate symbol.
//
// W3FIX: position 0 is only the repo root when the indexed path is ROOT-RELATIVE, which it is for
// `ripwire .` (paths read "./src/x.h") and is NOT for `ripwire /abs/repo` (paths read "/abs/repo/src/x.h").
// So the anchored arm matched nothing at all under an absolute root spelling, and --dead-code=./src refused
// with "matches no indexed path" on a tree that plainly has one — the same root-spelling class arch.h's
// relForHash header comment describes for baseline hashes. The fix is that same normalization, reused rather
// than re-derived: strip the ingest root LEXICALLY first, then compare. `root` empty ⇒ the leading-./ strip
// alone, i.e. byte-identical to the pre-fix relative-root behavior.
inline bool deadCodeFilterMatchesPath( std::string_view path, std::string_view dirFilter, bool anchoredAtRoot,
                                       std::string_view root = {} ) noexcept
{
    const std::string_view p = anchoredAtRoot ? rw::relForHash( path, root ) : deadCodeStripDotSlash( path );
    if( anchoredAtRoot )
    {
        if( dirFilter.size() > p.size() || p.substr( 0, dirFilter.size() ) != dirFilter )
        {
            return false;
        }
        const std::size_t afterEnd = dirFilter.size();
        return afterEnd == p.size() || p[ afterEnd ] == '/';
    }
    for( std::size_t at = p.find( dirFilter ); at != std::string_view::npos; at = p.find( dirFilter, at + 1 ) )
    {
        const std::size_t afterEnd = at + dirFilter.size();
        const bool leftOnBoundary  = at == 0 || p[ at - 1 ] == '/';
        const bool rightOnBoundary = afterEnd == p.size() || p[ afterEnd ] == '/';
        if( leftOnBoundary && rightOnBoundary )
        {
            return true;
        }
    }
    return false;
}

// --quality-panel[=PRESET]: THE SINGLE COMMAND (qualitypanel.h owns the join, the preset selection AND its
// emission, the way --ensemble owns its own). Its own function rather than a block inside runQualityViews:
// that dispatcher is already the tree's third-most complex symbol, and this verb needs three statements the
// other branches there do not (a preset parse, a refusal, a churn mining pass).
//
// It is dispatched from runQualityViews rather than from runMaintenanceViews beside --ensemble because two of
// its six families need what that dispatcher has and this one does not: the call graph (the state family's
// closure) and the value-use references (both new families) — see needsValueUses below.
//
// THE PRESET REFUSAL LIVES HERE, not in validateModifierGuards, and that is deliberate: the preset vocabulary
// belongs to the verb (qualitypanel.h), and cli.h is a leaf that includes only ingest.h. Pulling the whole
// lens stack into the argument parser to spell three names would be a worse trade than refusing one step
// later. Refusing at all is the point — silently substituting `default` for a preset the caller did not name
// answers a different question under the label they typed.
//
// GIT IS OPTIONAL, exactly as it is for --ensemble: five of the six families need no history, so a failed
// mining pass hands the join a nullptr and the historical family is reported UNAVAILABLE rather than as
// "did not fire". --since is deliberately not plumbed in — the churn window is part of the disclosed
// threshold set and one fixed 12-month window keeps hrank= comparable between runs.
int runQualityPanel( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;

    qpanel::Preset preset = qpanel::Preset::Default;
    if( !cfg.qualityPanelPreset.empty() && !qpanel::parsePreset( cfg.qualityPanelPreset, preset ) )
    {
        rw::emitTo( stderr, "ripwire: --quality-panel: unknown preset '{}' (supported: strict|default|lenient; "
                              "bare --quality-panel is default)\n", std::string_view( cfg.qualityPanelPreset.data(), cfg.qualityPanelPreset.size() ) );
        return 1;
    }

    std::vector<std::uint32_t> churn( ing.files.size(), 0 );
    const rw::SinceScope       noScope;
    const bool                 churnOk = mineChurnPerFile( ing, d.root, d.multiRoot, d.ws, std::string_view(), noScope,
                                                           rw::ensemble::kEnsembleChurnSince, churn );
    return qpanel::writePanelReport( ing, d.g, churnOk ? &churn : nullptr, d.root, preset, cfg.pageLimit, cfg.pageOffset );
}

// --dead-code's row order, shared by its <d> and <to> rows: file path asc, then line asc, then name asc (stable across runs).
inline void sortDeadCodeRows( const rw::IngestResult& ing, std::vector<rw::NodeId>& rows )
{
    using namespace rw;
    std::sort( rows.begin(), rows.end(), [ & ]( NodeId a, NodeId b )
    {
        const Symbol& sa = ing.symbols[a];  const Symbol& sb = ing.symbols[b];
        const std::string& pa = ing.files[ sa.fileId ];  const std::string& pb = ing.files[ sb.fileId ];
        if( pa != pb )
        {
            return pa < pb;
        }
        if( sa.line != sb.line )
        {
            return sa.line < sb.line;
        }
        return sa.name < sb.name;
    } );
}

// One --dead-code row, `<TAG n= t= p= l=/>`; name and path may contain & < > " — both are escaped so output is valid XML.
inline void emitDeadCodeRow( const rw::IngestResult& ing, rw::NodeId id, std::string_view tag, bool singleRoot, std::string_view rootPrefix, std::vector<char>& esc )
{
    using namespace rw;
    const Symbol& s = ing.symbols[ id ];
    const auto en = rw::escapeXml( s.name, esc );
    rw::emitTo( stdout, "<{} n=\"{}\" t=\"{}\"", tag, std::string_view( en.data(), en.size() ), symTag( s.kind ) );
    const std::string_view rp = singleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix ) : std::string_view( ing.files[ s.fileId ] );
    const auto ep = rw::escapeXml( rp, esc );
    rw::emitTo( stdout, " p=\"{}\" l=\"{}\"/>", std::string_view( ep.data(), ep.size() ), s.line );
}

// D1 TESTONLY-DEAD: every in-edge of `id` comes from a test symbol (filter.h isTestSymbol: the shared test-path rule plus the
// in-file test conventions). Only callers decide it, so an edge a test reaches by name alone can only add a test caller.
inline bool everyCallerIsTest( const rw::IngestResult& ing, const rw::Graph& g, rw::NodeId id ) noexcept
{
    using namespace rw;
    const auto* ro = g.inEdges.rowOffsets();
    const auto* ci = g.inEdges.colIndices();
    return std::all_of( ci + ro[ id ], ci + ro[ id + 1 ], [ & ]( NodeId caller ) { return isTestSymbol( ing, caller ); } );
}

// D1: `name` spelled whole-word in `text` (file `fileId`) anywhere but inside the signature span of one of `rows` it names.
inline bool spelledOutsideOwnSignature( const rw::IngestResult& ing, std::string_view text, std::uint32_t fileId, std::string_view name,
                                        const std::vector<rw::NodeId>& rows ) noexcept
{
    using namespace rw;
    const auto isIdent = []( char c ) noexcept { return std::isalnum( static_cast<unsigned char>( c ) ) || c == '_'; };
    const auto ownSignature = [ & ]( std::size_t at )
    {
        return std::ranges::any_of( rows, [ & ]( NodeId id )
        {
            const Symbol& def = ing.symbols[ id ];
            return def.fileId == fileId && def.name == name && at >= def.sigStartByte && at < def.sigEndByte;
        } );
    };
    for( std::size_t at = text.find( name ); at != std::string_view::npos; at = text.find( name, at + 1 ) )
    {
        const std::size_t end      = at + name.size();
        const bool        bounded  = ( at == 0 || !isIdent( text[ at - 1 ] ) ) && ( end == text.size() || !isIdent( text[ end ] ) );
        if( bounded && !ownSignature( at ) )
        {
            return true;
        }
    }
    return false;
}

// D1: the text a library file contributes to the name vetting, or nullopt when it contributes none: a test file, a prose file
// (markdown, .txt: a mention there is documentation, not a use) or an unreadable one. A notebook is CODE in a JSON container,
// so its code and markdown cells are read as text (docparse::extractIpynb) — a def only a notebook calls is in use.
// CR 4396503875: an EXCLUDED file (libraryFileExcluded: a test or a prose file) and an UNREADABLE one both return nullopt here,
// and the vetting tells them apart through libraryFileExcluded — a failed read is not an exclusion.
inline bool libraryFileExcluded( const rw::IngestResult& ing, std::uint32_t fileId )
{
    using namespace rw;
    const std::string_view rel = rootRelPath( ing, fileId );
    const std::string      ext = docparse::lowerExtOf( rel );
    return isTestPath( rel ) || ( ext != ".ipynb" && docparse::isProseExtension( ext ) );
}
inline std::optional<std::string> libraryFileText( const rw::IngestResult& ing, std::uint32_t fileId )
{
    using namespace rw;
    if( libraryFileExcluded( ing, fileId ) )
    {
        return std::nullopt;
    }
    const std::string          ext   = docparse::lowerExtOf( rootRelPath( ing, fileId ) );
    std::optional<std::string> bytes = docparse::detail::readWholeFile( diskPath( ing, fileId ) );
    if( bytes && ext == ".ipynb" )
    {
        return docparse::extractIpynb( *bytes );
    }
    return bytes;
}

// CR 4396503875: the stderr lines of a vetting that could not read every library file (each file, then the consequence).
inline void reportUnreadLibraryFiles( const rw::IngestResult& ing, const std::vector<std::uint32_t>& unread )
{
    for( const std::uint32_t fileId : unread )
    {
        rw::emitTo( stderr, "ripwire: --dead-code: cannot read {} — its uses of the test-only candidates are unknown\n", rw::rootRelPath( ing, fileId ) );
    }
    rw::emitTo( stderr, "ripwire: --dead-code: {} library file(s) could not be read, so no test-only row is listed (a row fewer, never a use missed)\n", unread.size() );
}

// D1 name vetting: drop every row whose name a NON-test, non-prose indexed file spells whole-word outside the def's own
// signature, and every row whose module a library file glob-imports (`from ._impl import *` re-exports the module's public
// names through the package). Text, not references: an aliased import (`from m import dump as binary_dump`) and a module-level
// call carry no edge to the def, and a comment or string mention costs only a missed row, never a used function on the list.
// Each file is read once, uncached (the scan may cover the whole tree). The survivors are left in --dead-code's row order.
inline void dropTestOnlySpelledInLibrary( const rw::IngestResult& ing, std::vector<rw::NodeId>& testOnly )
{
    using namespace rw;
    std::vector<std::string_view> names;
    names.reserve( testOnly.size() );
    for( NodeId id : testOnly ) { names.push_back( ing.symbols[ id ].name ); }
    std::ranges::sort( names, sortutil::svLess );
    names.erase( std::ranges::unique( names ).begin(), names.end() );
    std::vector<std::string_view> spelled;
    std::vector<std::string>      globbed;   // module tails a library file glob-imports (owned: the file text is gone after its turn)
    std::vector<std::uint32_t>    unread;   // library files the index lists that this vetting could not read
    for( std::uint32_t fileId = 0; fileId < ing.files.size(); ++fileId )
    {
        if( libraryFileExcluded( ing, fileId ) )
        {
            continue;
        }
        const std::optional<std::string> text = libraryFileText( ing, fileId );
        if( !text )
        {   // CR 4396503875: a file whose uses are unknown vets nothing, so no test-only claim is made on its behalf
            unread.push_back( fileId );
            continue;
        }
        for( std::string_view name : names )
        {
            if( spelledOutsideOwnSignature( ing, *text, fileId, name, testOnly ) )
            {
                spelled.push_back( name );
            }
        }
        for( std::string_view tail : quality::pythonGlobImportTails( *text ) )
        {
            globbed.emplace_back( tail );
        }
    }
    if( !unread.empty() )
    {
        reportUnreadLibraryFiles( ing, unread );
        testOnly.clear();
        return;
    }
    std::ranges::sort( spelled, sortutil::svLess );
    std::ranges::sort( globbed, sortutil::svLess );
    std::erase_if( testOnly, [ & ]( NodeId id )
    {
        const Symbol& def = ing.symbols[ id ];
        return std::ranges::binary_search( spelled, std::string_view( def.name ), sortutil::svLess )
            || std::ranges::binary_search( globbed, quality::pythonModuleTail( rootRelPath( ing, def.fileId ) ), sortutil::svLess );
    } );
    sortDeadCodeRows( ing, testOnly );
}

// D1 fix round 1 (F2): drop every row a package manifest names as an entry point. setup.cfg and pyproject.toml entry-point
// tables (`console_scripts`, plugin groups) call their target by `module:attr`, an invocation no source file spells; the
// crawl does not index setup.cfg, so the name vetting never sees it. epmanifest.h already reads both formats (EP-MANIFEST); this
// asks it for the manifests above the candidates' files and keeps off any def whose name is a target's attribute (last dotted
// segment). The wide side on purpose: a same-named def in another module is dropped too, never listed.
inline void dropTestOnlyEntryPoints( const rw::IngestResult& ing, std::vector<rw::NodeId>& testOnly )
{
    using namespace rw;
    std::vector<std::string>        seenDirs;
    std::vector<epdetail::Manifest> manifests;
    for( NodeId id : testOnly )
    {
        epdetail::collectManifestsAbove( ing, ing.symbols[ id ].fileId, seenDirs, manifests );
    }
    const auto isEntryAttr = [ & ]( std::string_view name )
    {
        return std::ranges::any_of( manifests, [ & ]( const epdetail::Manifest& m )
        {
            return std::ranges::any_of( m.entries, [ & ]( const EpEntry& e )
            {
                const std::size_t colon = e.target.find( ':' );
                if( colon == std::string::npos ) { return false; }
                const std::string_view attr = std::string_view( e.target ).substr( colon + 1 );
                return attr.substr( attr.rfind( '.' ) == std::string_view::npos ? 0 : attr.rfind( '.' ) + 1 ) == name;
            } );
        } );
    };
    std::erase_if( testOnly, [ & ]( NodeId id ) { return isEntryAttr( ing.symbols[ id ].name ); } );
}


// The residual of §6.3's extraction: --dead-code, the only branch left in runQualityViews. main() calls it
// immediately after runQualityDelta, i.e. in the position the old two-branch chain evaluated it.
std::optional<int> runQualityViews( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — shared
    // across every lens dispatched from this function.
    const bool         qvSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  qvRootPrefix = qvSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  qvRootEsc;
    const std::string  qvRootAttr   = qvSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], qvRootEsc ) ) + "\"" ) : std::string();

    // --biggest-first (was --readability): the Posnett/Hindle/Devanbu (MSR 2011) closed-form lens, per
    // function, LARGEST Halstead volume/token-count/length first — a size proxy, not a readability order
    // (the ordering claim is WITHDRAWN, docs/EVALS.md §8; readability.h owns the measurement AND its
    // emission, the way --handoff owns its packet). It reads only the symbol table and the files on
    // disk, so it needs neither the graph nor git — and it is a LENS: exit 0 always, no verdict, no threshold.
    if( cfg.readability )
    {
        return writeReadabilityReport( ing, cfg.pageLimit, cfg.pageOffset, qvRootPrefix, qvRootAttr );
    }

    // --comment-coherence: two published content measures per documented function/method (Steidl c_coeff
    // + Scalabrino CIC) — commentcoherence.h owns the measurement AND its emission, the same shape as
    // --biggest-first. Symbol table + files on disk only; no graph, no git; a LENS: exit 0 always.
    if( cfg.commentCoherence )
    {
        return writeCommentCoherenceReport( ing, cfg.pageLimit, cfg.pageOffset, qvRootPrefix, qvRootAttr );
    }

    // --nonlocal-state: per function, the non-local MUTABLE state it or its transitive callees reach, reads
    // and writes kept apart (nonlocalstate.h owns the discovery, the closure AND its emission, the way
    // --biggest-first does). It needs the symbol table, the value-use references and the call graph — but
    // no git — and it is a LENS: exit 0 always, no verdict, no threshold, every count a disclosed floor.
    if( cfg.nonlocalState )
    {
        return nonlocal::writeNonLocalStateReport( ing, g, cfg.pageLimit, cfg.pageOffset, qvRootPrefix, qvRootAttr );
    }

    if( cfg.qualityPanel )
    {
        return runQualityPanel( d );
    }

    // --naming-calibration: §9.5 — the naming-* lint rules judged against the repo's OWN rename history
    // (renamemine.h owns the mining, the join, the scoring AND the emission, the way --biggest-first does).
    // It walks git and reads the symbol table; it needs no graph. Exit 0 always — a measurement, not a
    // verdict: test/namingcalibrationcheck.sh is where the per-rule floor lives.
    if( cfg.namingCalibration )
    {
        return renamemine::writeNamingCalibrationReport( ing, d.root );
    }

    // --naming-consistency: §9.2 TIER A convention normalization — the corpus's own case-convention vote,
    // read-only, graph-free (namingconsistency.h owns the scan, the decision and the emission). Exit 0
    // always — a lens, not a gate.
    if( cfg.namingConsistency )
    {
        return namingconsistency::writeNamingConsistencyReport( ing, cfg.pageLimit, cfg.pageOffset, qvRootPrefix, qvRootAttr );
    }

    // --dead-code[=DIR]: HIGH-CONFIDENCE candidates only. Zero callers is incomplete whole-program evidence,
    // so the default reports source-defined free functions with explicit internal (`static`) linkage. External
    // entry points, methods, header definitions and declarations are excluded. There is no broad product mode,
    // so do not overload the directory filter with lower-confidence behavior.
    // Output: deterministic (sorted by file path then line), terse XML consistent with other report verbs.
    if( cfg.deadCode )
    {
        const auto* inRo = g.inEdges.rowOffsets();    // in-edge CSR row offsets: inDeg(i) = inRo[i+1]-inRo[i]
        std::vector<std::string> sourceByFile( ing.files.size() );
        std::vector<char>        sourceLoaded( ing.files.size(), 0 );
        const auto sourceFor = [ & ]( std::uint32_t fileId ) -> const std::string&
        {
            if( sourceLoaded[fileId] )
            {
                return sourceByFile[fileId];
            }
            sourceLoaded[fileId] = 1;
            std::FILE* file = std::fopen( diskPath( ing, fileId ).c_str(), "rb" );
            if( !file )
            {
                return sourceByFile[fileId];
            }
            std::fseek( file, 0, SEEK_END );
            const long byteCount = std::ftell( file );
            std::fseek( file, 0, SEEK_SET );
            if( byteCount > 0 )
            {
                sourceByFile[fileId].resize( std::size_t( byteCount ) );
                const std::size_t bytesRead = std::fread( sourceByFile[fileId].data(), 1, std::size_t( byteCount ), file );
                sourceByFile[fileId].resize( bytesRead );
            }
            std::fclose( file );
            return sourceByFile[fileId];
        };
        // lane/safe-delete: the scan itself now lives in sourceHasStaticToken (near isHeaderPath, above) —
        // --safe-delete's dead_code_candidate= asks the identical question for one already-resolved symbol
        // and needs the same predicate, not a second derivation of it. This lambda keeps only what is
        // --dead-code's own: the per-file sourceFor() cache amortizing the scan across every candidate.
        const auto hasStaticToken = [ & ]( const Symbol& symbol ) -> bool
        {
            return quality::symbolHasStaticLinkage( symbol, sourceFor( symbol.fileId ) );
        };

        // P2.2 (agent-friction round, 2026-08-29): a symbol whose OWN signature text is a registered
        // self-registering macro call (doctest/Catch2 TEST_CASE family, GoogleTest TEST/TEST_F/TEST_P,
        // Google Benchmark BENCHMARK family, plus any name a .ripwire_config register_macros= line adds —
        // see quality::kBuiltinRegisterMacros) is EXEMPT here too, not only from --quality-delta's dead
        // kind. hasStaticToken alone does not structurally exclude these: it scans [sigStartByte,
        // sigEndByte), which for a doctest/Catch2 title INCLUDES the title text — a TEST_CASE titled
        // "handles static config" contains the whole-word token "static" and was reported as high-
        // confidence dead-code before this fix (test/registermacrocheck.sh pins the repro). Reuses this
        // block's own sourceFor() cache rather than re-reading files via forEachSymbolBody.
        const std::vector<std::string> registerMacroNames = quality::registeredMacroNames( d.root );
        // F-13 — same disclosure --quality-delta's runQualityDelta prints, built once here too: an
        // unrecognized .ripwire_config key or an inert register_macros= name used to be a silent no-op on
        // this verb as well.
        const quality::RegisterMacroConfigDiagnostics dcConfigDiag  = quality::diagnoseRegisterMacroConfig( ing, d.root );
        const std::string                             dcConfigWarn = registerMacroConfigWarningAttr( dcConfigDiag );
        const auto isRegisteredMacroSymbol = [ & ]( const Symbol& symbol ) -> bool
        {
            const std::string& src = sourceFor( symbol.fileId );
            if( symbol.sigStartByte >= src.size() )
            {
                return false;
            }
            return quality::startsWithRegisteredMacro( std::string_view( src ).substr( symbol.sigStartByte ), registerMacroNames );
        };
        std::size_t registerMacroExcluded = 0;   // P2.2: disclosed count — see the header comment below
        std::size_t runnerRootExcluded    = 0;   // 0.6.6 D4: disclosed count (runner-root-excluded=, absent at 0)
        std::size_t decoratedExcluded     = 0;   // 0.6.6 D4 review: decorated Python defs, counted apart (decorated-excluded=)
        std::size_t valueRefExcluded      = 0;   // reference-as-value round: held as a VALUE by a table/field/argument (value-ref-excluded=)
        const rw::ValueRefIndex dcVri( ing );    // valuerefs.h — the same rows --callers shows, under its visibility rules
        // The value walk's depth cut over EVERY armed family (ingest_valuerefs.h kVrMaxDepth): a table entry below it was never
        // seen, so a listed function may still be held as a value there — disclosed beside value-ref-excluded=, absent when none.
        const rw::ValueRefIndex::DepthCuts dcDepthCut = dcVri.depthCutsFor( {}, /*everyFamily=*/true );

        // Optional path filter (--dead-code=DIR). §P0.3: this was a bare SUFFIX test, so it could only ever
        // match a FILENAME — every directory argument produced count="0" with confidence="high", and a typo'd
        // directory was byte-identical to a real one. It now matches a directory PREFIX, a trailing path
        // component, or the whole path, all at directory boundaries so `src` never matches `srcmut/` —
        // UNLESS the filter carries a leading ./, which anchors it at the repo root instead (§A10.6,
        // deadCodeFilterMatchesPath above: `./src` matches only the top-level src/ subtree, never an
        // interior `*/src/*` component that the bare `src` spelling also, correctly, matches).
        //
        // W3FIX: `root` is handed to the anchored arm so "position 0" means the repo root under EVERY root
        // spelling. Without it the anchored match compared the filter against an ABSOLUTE indexed path and
        // could never hit, so `ripwire /abs/repo --dead-code=./src` refused where `ripwire . --dead-code=./src`
        // answered. The unanchored (component-anywhere) arm never read the root and is untouched.
        const std::string_view dirFilterRaw = cfg.deadCodeDir;
        std::string_view       dirFilter = deadCodeStripDotSlash( dirFilterRaw );
        while( !dirFilter.empty() && dirFilter.back() == '/' )
        {
            dirFilter.remove_suffix( 1 ); // `test/` ≡ `test`
        }
        const bool anchoredAtRoot = dirFilterRaw.size() >= 2 && dirFilterRaw[ 0 ] == '.' && dirFilterRaw[ 1 ] == '/';
        const auto filterMatchesPath = [ & ]( std::string_view path ) noexcept -> bool
        {
            return deadCodeFilterMatchesPath( path, dirFilter, anchoredAtRoot, d.root );
        };

        // A filter that names nothing in the indexed tree is a user error, not a measurement: refuse loudly
        // rather than ship `count="0" confidence="high"` about a directory that was never crawled.
        if( !dirFilter.empty() )
        {
            bool filterHitsIndex = false;
            for( const std::string& indexedPath : ing.files )
            {
                if( filterMatchesPath( indexedPath ) ) { filterHitsIndex = true; break; }
            }
            if( !filterHitsIndex )
            {
                rw::emitTo( stderr, "ripwire: --dead-code={} matches no indexed path — a zero here would be a failure, not a measurement "
                                      "(pass a directory or file that exists in the tree, e.g. ripwire <dir> --dead-code=src)\n", std::string_view( dirFilterRaw.data(), dirFilterRaw.size() ) );
                return 1;
            }
        }

        // D1 TESTONLY-DEAD: a library function (not itself test code) whose EVERY indexed caller is a test symbol
        // (filter.h isTestSymbol: the shared test-path rule plus the in-file test conventions). Not dead and never in
        // count=: a test reaches it, a library caller nowhere in the index does. Only callers decide it, so an edge a
        // test reaches by name alone can only add a test caller, never hide a library one. Decorated and value-held
        // defs stay off (a registry or table may be the library's use). The name vetting below drops any row whose
        // name a non-test code file spells at all (a module-level call, an aliased import, a value), so a site the call
        // graph did not attribute cannot leave a used function on this list.
        std::vector<NodeId> testOnly;
        const auto testOnlyCandidate = [ & ]( const Symbol& s ) -> bool
        {
            return !isTestSymbol( ing, s.id ) && !quality::isConftestFile( ing.files[ s.fileId ] ) && !quality::pythonDecoratedDef( s, sourceFor( s.fileId ) ) && !dcVri.isValueReferenced( s.id )
                && everyCallerIsTest( ing, g, s.id );
        };

        // collect candidates: in-degree == 0, not exported, sorted for determinism
        std::vector<NodeId> candidates;
        candidates.reserve( 64 );
        for( const Symbol& s : ing.symbols )
        {
            if( s.kind != SymKind::Function )
            {
                continue; // methods and non-callable nodes are out of scope
            }
            if( s.sigEndByte >= s.endByte )
            {
                continue; // declarations have no deletion evidence
            }
            if( isHeaderPath( ing.files[s.fileId] ) )
            {
                continue; // may be instantiated by external TUs
            }
            // D1 TESTONLY-DEAD: Python's module-private convention is internal-interface evidence for the test-only rows
            // ONLY; a zero-caller row (count=) still needs the `static` token, exactly as before.
            const bool staticLinkage = hasStaticToken( s );
            if( !staticLinkage && !quality::underscorePrivateDef( rootRelPath( ing, s.fileId ), s ) )
            {
                continue; // external linkage may be an entry point/API
            }

            // optional path filter: directory prefix, trailing component, or the whole path
            if( !dirFilter.empty() && !filterMatchesPath( ing.files[s.fileId] ) )
            {
                continue;
            }

            // in-degree == 0 → no call in the indexed tree reaches this symbol
            const std::uint32_t inDeg = inRo[ s.id + 1 ] - inRo[ s.id ];
            if( inDeg != 0 )
            {
                if( testOnlyCandidate( s ) )
                {
                    testOnly.push_back( s.id );   // vetted by name below, against every non-test reference
                }
                continue;
            }
            if( !staticLinkage )
            {
                continue; // Python private, zero callers: no `static` evidence, so never a count= row
            }
            if( isRegisteredMacroSymbol( s ) )
            {
                ++registerMacroExcluded;   // P2.2: self-registers via a static initializer — never dead-code
                continue;
            }
            if( quality::pythonDecoratedDef( s, sourceFor( s.fileId ) ) )
            {
                ++decoratedExcluded;   // 0.6.6 D4: decorated — a decorator may register it; its only "linkage" was a token
                continue;
            }
            if( quality::pythonRunnerRoot( ing.files[ s.fileId ], s, sourceFor( s.fileId ) ) )
            {
                ++runnerRootExcluded;   // 0.6.6 D4: a test runner reaches it — never dead-code
                continue;
            }
            // One entity, one reason: checked LAST, so a def a reason above already excluded is counted there only.
            if( dcVri.isValueReferenced( s.id ) )
            {
                ++valueRefExcluded;     // a dispatch table / field / argument holds it — not dead, not a proven call either
                continue;
            }
            candidates.push_back( s.id );
        }

        sortDeadCodeRows( ing, candidates );   // deterministic order: file path asc, then line asc, then name asc
        if( !testOnly.empty() )
        {
            dropTestOnlyEntryPoints( ing, testOnly );
            dropTestOnlySpelledInLibrary( ing, testOnly );
        }

        rw::emitTo( stdout, "<!-- ripwire dead-code: source functions with internal linkage and no caller found in the indexed tree — a name-based "
                     "graph reading, not a confidence judgement (dynamic dispatch, reflection and macro-generated callers are invisible to it). "
                     "A bare-name filter matches by path COMPONENT: filter=\"src\" keeps any path with a src segment at any depth "
                     "(test/x/src/y.cpp included); anchor with ./ (filter=\"./src\") to pin the root-level directory only. "
                     "register-macro-excluded= counts symbols excluded because their OWN definition is a registered "
                     "self-registering test/benchmark macro call (doctest/Catch2 TEST_CASE family, GoogleTest TEST/TEST_F/TEST_P, "
                     "Google Benchmark BENCHMARK family, plus any name a .ripwire_config register_macros= line adds): such a "
                     "symbol registers itself through a static initializer the call graph cannot see, so zero in-edges on it is "
                     "not evidence of anything — never a finding, never gating, absent nothing (0 is printed, not omitted). "
                     "config-warnings= counts two DISCLOSED .ripwire_config problems, each also written to stderr — an "
                     "unrecognized key, and a register_macros= name matching no indexed symbol — never gating, present "
                     "only when non-zero. "
                     "runner-root-excluded= counts Python defs excluded because a test runner reaches them (pytest "
                     "test*/xunit hooks in test_*.py or *_test.py; test*/setUp-family methods of a class whose own bases name a "
                     "TestCase); decorated-excluded= counts decorated Python defs, excluded because a decorator MAY register "
                     "them (wrappers such as @staticmethod/@property/@lru_cache are included, and register nothing): Python has "
                     "no internal linkage, so such a row rested on a `static` token alone. Both are FLOORS, never findings, "
                     "absent at 0. A `static` inside a comment, or in a language where it is not the storage class (a Python "
                     "parameter, a TypeScript literal, a Rust lifetime), is not linkage evidence. "
                     "Graph evidence is local to the indexed tree; verify before deleting. {}{}-->",
                     // Reference-as-value round: beside its hyphenated siblings above, exactly when the root carries it.
                     ( std::string( testOnly.empty() ? "" : "test-only=N (absent when 0): library functions whose every indexed caller "
                                                           "is test code (a test path, or an in-file test scope), listed as <to n= t= p= l=> rows "
                                                           "after the d rows on the first page; not dead and not in count=, the index holds no "
                                                           "library caller. Internal evidence as for d rows, or a Python leading-underscore name or "
                                                           "module/package (module-level defs); the name spelled whole-word in any non-test code file, outside its own "
                                                           "signature, or in a setup.cfg or pyproject entry point, or glob-imported (from m import *), keeps it off; "
                                                           "conftest.py defs are test code. A test helper "
                                                           "outside a test path, fixture files and test binaries named only in a build "
                                                           "file read as library callers (a miss), and a public helper package such as testing/ is listed as library code. A candidate, not proof: a use only in an unindexed "
                                                           "file (an .inc table, setup.py), a docs page or a name built at run time is invisible, so "
                                                           "verify before deleting. " )
                       + std::string( valueRefExcluded > 0 ? "value-ref-excluded=N (absent when 0): internal functions kept off this list because "
                                                           "a table, field or argument in ANOTHER function or at file scope holds them as a VALUE "
                                                           "(matched by name; it is not a proven call; the callers verb lists the sites); a function "
                                                           "that only stores itself is still listed. One entity, one reason: a def a reason above "
                                                           "already excluded is counted there only. "
                                                         : "" )
                       + rw::valueRefsDepthLegend( dcDepthCut.files > 0 ) ).c_str(),   // exactly when the root carries the depth disclosure
                     rw::graphCountFloorBrief( rw::graphGaugeClauses( g ) ).c_str() );
        // §P15/§P16: candidates is already deterministically sorted (path asc, line asc, name asc) and used to
        // print every candidate unconditionally — completeness was the whole contract, matching --uses' shape,
        // so it pages the same way: no historic display cap, discloseCap=false (un-paginated tag byte-identical).
        const PageWindow  dcPw = pageWindow( candidates.size(), cfg.pageLimit, cfg.pageOffset );
        char              dcAb[ kPageDisclosureCap ];
        // V2-7: a FILTERED zero must not be byte-identical to an unfiltered clean tree — with the ./-anchor
        // and component spellings now giving different answers for the same word, the root says which
        // filter produced this count. Absent = no filter, whole tree (never an empty filter="").
        std::string dcFilterAttr;
        if( !cfg.deadCodeDir.empty() )
        {
            std::vector<char> dcFiltEsc;
            dcFilterAttr = " filter=\"" + std::string( escapeXml( cfg.deadCodeDir, dcFiltEsc ) ) + "\"";
        }
        // 0.6.6 D4: runner-root-excluded= is absent at 0, so a tree with no Python test/decorated root is byte-identical
        const std::string runnerRootAttr = ( runnerRootExcluded == 0 ? std::string() : std::format( " runner-root-excluded=\"{}\"", runnerRootExcluded ) )
                                         + ( decoratedExcluded == 0 ? std::string() : std::format( " decorated-excluded=\"{}\"", decoratedExcluded ) )
                                         + ( valueRefExcluded == 0 ? std::string() : std::format( " value-ref-excluded=\"{}\"", valueRefExcluded ) )
                                         + rw::valueRefsDepthAttrXml( ing, dcDepthCut, rw::VrRender{ qvSingleRoot, qvRootPrefix } );   // absent when no cut
        const std::string testOnlyAttr = testOnly.empty() ? std::string() : std::format( " test-only=\"{}\"", testOnly.size() );   // D1: absent at 0
        rw::emitTo( stdout, "<dead-code count=\"{}\" evidence=\"internal-linkage+zero-callers\" register-macro-excluded=\"{}\"{}{}{}{}{}{}{}>",
                     candidates.size(), registerMacroExcluded, runnerRootAttr, testOnlyAttr,
                     dcFilterAttr.c_str(),
                     pageDisclosure( dcAb, sizeof( dcAb ), dcPw.end - dcPw.begin, candidates.size(), dcPw.end,
                                     cfg.pageLimit, cfg.pageOffset, false ),
                     qvRootAttr.c_str(), dcConfigWarn.c_str(),
                     rw::graphCountFloorAttrXml( g ).c_str()  );   // H5/M15: gauge + marker; "zero callers" is a claim about the name-based CSR — a floor
        std::vector<char> dcEsc;
        for( std::size_t candidateIndex = dcPw.begin; candidateIndex < dcPw.end; ++candidateIndex )
        {
            emitDeadCodeRow( ing, candidates[ candidateIndex ], "d", qvSingleRoot, qvRootPrefix, dcEsc );
        }
        for( std::size_t testOnlyIndex = 0; cfg.pageOffset == 0 && testOnlyIndex < testOnly.size(); ++testOnlyIndex )   // first page only (offset 0): never repeated
        {
            emitDeadCodeRow( ing, testOnly[ testOnlyIndex ], "to", qvSingleRoot, qvRootPrefix, dcEsc );
        }
        rw::emitRaw( stdout, "</dead-code>" );
        return 0;
    }
    return std::nullopt;
}

// --edit-check=SYM (B11/L5): "did MY edit change a contract someone depends on", at edit time, for ONE
// symbol — --quality-delta answers the same question per-DIFF at commit time; this is the fast targeted
// entry point. Resolves SYM exactly like --around/--lego
// (resolveFocus — file:name disambiguates), then compares the WORKING-TREE symbol against the git-HEAD
// baseline (computeHeadSnapshot — the SAME qheadsnap/qsnap cache family --quality-delta's T0.1 auto-baseline
// uses, so a warm run is a cache-blob read, never a fresh git-archive/ingest/clone-detection pass — that is
// what keeps this under the ≤100ms warm budget the gate asserts, unlike --quality-delta's own ~250ms+
// per-call clone recompute over the whole tree). Reuses B10.2's per-canonId MAX-aggregation over the overload
// set (same file+scope+name share one g.canonId) for the was/now params + publicness comparison — NOT a
// single arbitrarily-iterated overload — so a low-param overload can never manufacture a phantom
// contract-change (the exact trap B10 fixed in quality.h; re-implementing it single-overload here would
// reintroduce it). status is exactly one of unchanged / new-symbol / contract-change, and it is the JOIN of
// three facts, not of the was/now pair alone (editcheck.h's editCheckVerdict owns the derivation and its
// reasoning; change= names which fact carried a contract-change):
//   new-symbol       — SYM's canonical id has no baseline record at all (absent from base.locBySym, the same
//                       "existed at baseline in ANY form" test quality.h's api-surface kind uses). Never
//                       escalated: there was no contract to change.
//   contract-change   — SYM existed at baseline AND at least one of THREE was-vs-now facts moved: the params
//                       MAX, publicness, or the definition COUNT (defs_was= vs the root's defs=). The third
//                       exists because the MAX fold is blind to an overload REMOVED below it — both sides keep
//                       the same max while a call site stops binding, and answering "unchanged" there is a
//                       false reassurance from the one verb whose value is the headline word. change= names
//                       which fact carried it; it adds broken-callers as corroboration but never as the sole
//                       cause, because incompatible= describes the CURRENT tree rather than the edit.
//   unchanged         — SYM existed at baseline and none of the three moved (a body-only edit is unchanged by
//                       design: this checks the CONTRACT, not the body — that is --quality-delta's
//                       short-horizon-churn kind's job).
// A non-git root / no HEAD degrades to new-symbol (nothing to compare against) with a DISCLOSE —
// never a crash; only an unresolvable SYM refuses loudly (below).
//
// 1-hop callers (reuse the --callers 1-hop in-edge walk, unioned over the whole overload set) are listed with
// any call-site flagged INCOMPATIBLE when its argument count is reliably counted (argCountKnown) AND no
// surviving overload could accept it — every overload with a FIXED arity (arityExact!=0) disagrees, and none
// is a variadic/default-arg/implicit-receiver wildcard that an argument count could never disprove
// (editcheck.h::editCheckImplicitReceiver adds the Python/Ruby half that arityExact cannot express), evaluated
// against the CURRENT (post-edit) overload set.
//
// One-sided IN THE ARITY, not a proof of BINDING — and the emitted legend says so rather than promising
// "provably … never a guess". Call edges are name-based, so a receiver-qualified call to a same-named callee
// this tool does not index is measured against the one definition it does index; an untouched, compiling tree
// therefore carries a nonzero incompatible= on a handful of shared names. See editcheck.h's measurement note
// for the swept numbers and why no cheap sound filter exists.
//
// The contract-comparison core (EditCheckContract / editCheckOverloadSet / editCheckContractVsHead /
// editCheckIncompatibleFlags / editCheckCallers / the whole <edit-check> XML assembler) now lives in
// editcheck.h (L4) as editCheckBundleText() — shared verbatim with the MCP edit_check verb (mcpverbs.h's
// editCheckText()). This handler only resolves the CLI's symbol spec (the shared resolver + the did-you-mean
// refusal message + the §A6a ambiguity refusal) and hands the resolved node to that ONE assembler, this round
// also passing d.notesPtr so a note targeting SYM (or its file) surfaces as a <note> child, the same row
// grammar --for/--expand already use (editCheckBundleText's `ni` parameter defaults to nullptr, so the MCP
// call site is untouched and stays notes-inert for now).
//
// §A6a — an AMBIGUOUS bare name is REFUSED, not silently narrowed. resolveFocus() answers "the tower-front
// definition with this name", which is the right answer for --around's ego graph and the WRONG one here: this
// verb's whole value is "did I break a contract?", and answered about a definition the agent never edited it
// returns status="unchanged" — reassurance for the wrong symbol. Its siblings can union (--callers reports
// defs="3" and lists the union); a CONTRACT cannot be unioned, so the only honest answers are one definition
// or a refusal that says how to name one. The resolver moves to resolveAllByNameQualified (every match, not
// one tower pick) — byte-identical on any selector that matched exactly one definition site, and it accepts a
// canonical id too, which is the spelling the refusal has to offer when a file alone cannot separate two
// scopes in one file.
std::optional<int> runEditCheck( const MainDispatch& d )
{
    using namespace rw;
    const Config&        cfg = d.cfg;
    const IngestResult&  ing = d.ing;

    if( cfg.editCheckSym.empty() )
    {
        return std::nullopt;
    }

    // H1: the out-param is the decl→def widening's RESIDUE — same-named definitions this selector found and could not tie
    // to the file it named. callers=/incompatible= are read from the one definition picked below, so unreported, a drop
    // reached the reader as incompatible="0": a no-broken-callers reading about a definition nobody read. The --dry-run
    // preview re-resolves on the tree it measures and reports its own (editpreview.h).
    std::size_t               ecUnprovenDefs = 0;
    const std::vector<NodeId> matches        = resolveAllByNameQualified( ing, cfg.editCheckSym, &ecUnprovenDefs );
    if( matches.empty() )
    {
        // §B4.2: the shared refusal — see selectorrefuse.h. A `file:name` whose FILE half is the fault used
        // to read as "that symbol does not exist", which sends an agent hunting for a rename that never was.
        rw::emitTo( stderr, "{}\n", selectorNotFoundMessage( ing, "ripwire: --edit-check symbol not found: ",
                                                               cfg.editCheckSym, "--edit-check=" ).c_str() );
        return 1;
    }

    // the C/C++ declaration/definition fold is the post-hoc verb's (editcheck.h editCheckFoldDeclGroups); the preview
    // below splices over ONE definition span, so it keeps one group per (file, scope) and refuses as before
    const std::vector<EditCheckGroup> groups = editCheckGroups( ing, d.g, matches, /*foldDecls=*/!editPreviewRequested( cfg ) );
    if( groups.size() > 1 )
    {
        rw::emitTo( stderr, "ripwire: --edit-check: {}\n",
                      editCheckAmbiguousMessage( cfg.editCheckSym, groups, "--edit-check=", matches.size() ).c_str() );
        return 1;
    }
    const NodeId focus = groups[0].focusNode;

    // card A1 — the PRE-APPLY fork. Everything above (resolution, the not-found refusal, the §A6a ambiguity
    // refusal) is shared verbatim, because a preview that resolved its target differently from the post-hoc
    // verb would be answering about a different definition. Below the fork the preview splices the payload
    // over THIS definition's span, re-derives the tree, and calls the SAME assembler; refusals from it are
    // the same shape as this handler's own (stderr, exit 1, nothing on stdout).
    if( editPreviewRequested( cfg ) )
    {
        std::string payload, payloadErr;
        if( !rw::editpreview::readPayload( cfg.editPayload, cfg.maxFileBytes, payload, payloadErr ) )
        {
            rw::emitTo( stderr, "ripwire: --edit-check --dry-run: {}\n", payloadErr.c_str() );
            return 1;
        }
        const rw::editpreview::Outcome preview = rw::editpreview::run( ing, d.g, d.root, cfg.maxFileBytes, cfg.excludes,
                                                                        d.valueUses, cfg.editCheckSym, focus, payload, d.notesPtr,
                                                                        cfg.pageLimit, cfg.pageOffset );
        if( !preview.ok )
        {
            rw::emitTo( stderr, "ripwire: --edit-check --dry-run: {}\n", preview.message.c_str() );
            return 1;
        }
        std::fwrite( preview.xml.data(), 1, preview.xml.size(), stdout );
        return 0;
    }

    // 2026-09-10: --limit/--offset window the UNFLAGGED context rows and nothing else (editcheck.h,
    // editCheckRowWindow). cli.h's honorsPaging() lists this verb, so the pair reaches here rather than
    // being refused, and 0/0 — the un-spelled window — is the default cap, not "unbounded".
    const std::string xml = editCheckBundleText( ing, d.g, d.root, cfg.maxFileBytes, cfg.excludes, focus, d.notesPtr,
                                                  /*preview=*/false,
                                                  // idea #11: an unchanged, unflagged contract is its verdict line under EVERY legend
                                                  // posture (L1: the legend dial never moves the payload); --limit lists the rows
                                                  EditCheckPage{ cfg.pageLimit, cfg.pageOffset, /*verdictOnly=*/true, cfg.editCheckSym },
                                                  ecUnprovenDefs, d.notesDegraded );   // L3 follow-up (CodeRabbit 4053600616)
    std::fwrite( xml.data(), 1, xml.size(), stdout );
    return 0;
}

}   // namespace — verbs_quality.h section of main.cpp
