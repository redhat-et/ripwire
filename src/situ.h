#pragma once

// situ.h — situational_awareness (--situ / MCP verb): after an edit, the three things to know about a change
// set, in one call —
//   (1) BLAST RADIUS  — everything that transitively depends on the changed symbols (in-edge reachability)
//   (2) TESTS TO RUN  — test files among those dependents (= --affected)
//   (3) CO-CHANGE MISS— files usually edited together with the change but NOT in the diff (forgot-to-update)
// Pure synthesis of transitiveCallers + isTestPath + cochangePartners — the daily-driver agent call. Text out.

#include "model.h"
#include "graph.h"
#include "filter.h"
#include "gitmine.h"
#include "prcontext.h"   // A3-F17b/A3-F13: reuse the ONE numstat-based mask builder (gitDiffChangedMaskNumstat)
#include "gitstamp.h"    // r26-stamp Task A: gitstamp::atAttr — the at="<sha>[+dirty]" root anchor
#include "testmap.h"     // §P11.4: TestRunnerIndex / runAttr — the run= hint on a named test row
#include "serialize.h"   // L2: jsonStr() — writeTestGateReportJson's escaping (self-contained: don't rely on
                         // include-order in whichever TU pulls situ.h in first)
#include "pageview.h"    // §A3a (PLAN_outputAudit2_2026-07-28.md): the ONE paging/truncation vocabulary — the
                         // <u> untested-row list migrates onto it instead of a bare kMaxUntestedRows literal
                         // (self-contained: serialize.h already pulls this in, but don't rely on that order)

#include <algorithm>
#include <cstdio>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace ctx
{

// `git -C root diff HEAD` → a changed-file mask (parallel to ing.files). Returns {mask, ok};
// ok=false ONLY when git itself fails (non-zero exit + no output = no repo / detached HEAD / git unavailable).
// ok=true + empty mask = CLEAN working tree (git ran cleanly but found zero changed files — valid, not an
// error). Callers use ok=false to distinguish "no git" from "clean tree". The reported repo-relative
// paths are suffix-matched to ingested (absolute) paths at a path boundary.
//
// THE ONE working-tree changed-file mask, for BOTH surfaces of every verb that takes one. The MCP arms
// (mcpindex.h, mcpverbs.h) have always called it; main.cpp's gitChangedFiles — which is what CLI --situ,
// --test-gate, --map-diff and --eval take — now delegates here too, and used to run `git diff --name-only`
// itself. That is why the two forms of ONE verb disagreed about a mass chmod: the CLI counted 272 mode-flipped
// files as changed and the MCP verb did not. The point of the seam is not that the two agree today, it is
// that there is only one place where they could stop agreeing.
//
// A3-F17b (mirrors the A3-F10 fix landed in prcontext.h): built from `git diff --numstat`, NOT `--name-only`.
// numstat reports "0<TAB>0<TAB>path" for a content-identical entry (a pure mode flip, e.g. a chmod), which a
// raw --name-only mask cannot distinguish from a real edit — a mass chmod (a real incident: 272 files) inflated
// the situ change set with pure noise. This DELEGATES to prcontext.h's gitDiffChangedMaskNumstat (A3-F13: the
// three git-diff mask builders collapse to that one helper) so the mode-only filter lives in exactly one place;
// we adapt its {mask, ok, skippedModeOnly} result to this function's {mask, ok} contract (no caller consumes
// the skipped count — --pr-context, which discloses it, reads the numstat builder directly). A pure RENAME is
// content-identical too and is deliberately NOT dropped: numstatRowPath separates the two on the " => " marker.
// baseRef "" ⇒ the working-tree diff vs HEAD (the --situ default).
inline std::pair<std::vector<char>, bool> gitDiffChangedMask( const std::string& root, const IngestResult& ing,
                                                              std::uint32_t onlyRoot = UINT32_MAX )   // multi-root §5
{
    const PrContextMask r = gitDiffChangedMaskNumstat( root, ing, "", onlyRoot );
    return { r.mask, r.ok };
}

// resolve a comma-separated list of file path-substrings into a changed-file mask (parallel to ing.files).
// §P8 seam 2: each item passes through stripLineLocator first, so the `path:line` locator that --hotspots/
// --clones/--grep/--lint/--quality-delta emit as their PRIMARY row spelling can be pasted straight into
// --situ/--test-gate (and the MCP situational_awareness verb) — the same strip --affected applies. A bare
// path is returned untouched, so every argument shape that already worked is byte-identical.
inline std::vector<char> changedMaskFromList( const IngestResult& ing, std::string_view csv )
{
    std::vector<char> mask( ing.files.size(), 0 );
    for( std::size_t start = 0; start < csv.size(); )
    {
        std::size_t c = csv.find( ',', start );
        if( c == std::string_view::npos ) c = csv.size();
        if( c > start ) { const std::uint32_t f = resolveFileSuffix( ing, stripLineLocator( csv.substr( start, c - start ) ) ); if( f != UINT32_MAX ) mask[f] = 1; }
        start = c + 1;
    }
    return mask;
}

// --situ is a fixed report, so each of its three sections has its own hard row cap. §B12.1 gave section [1]
// the "showing N of M <noun>" form; §H6 (W3FIX) gives the other two the SAME form from the SAME function
// rather than two more hand-written parentheticals — the sentence that exists three times is the sentence
// that gets fixed once. Empty when nothing was dropped, so an untruncated section is byte-unchanged.
inline constexpr std::size_t kSituBlastFilesShown = 8;    // section [1] — blast-radius file rows
inline constexpr std::size_t kSituTestRowsShown   = 25;   // section [2] — tests-to-run rows
inline constexpr std::size_t kSituPartnerRowsShown = 8;   // section [3] — co-change partner rows

inline std::string situShowingNote( std::size_t shownCap, std::size_t rowTotal, const char* rowNoun )
{
    if( rowTotal <= shownCap ) return {};
    return " (showing " + std::to_string( shownCap ) + " of " + std::to_string( rowTotal ) + " " + rowNoun + ")";
}

inline void writeSituation( std::FILE* out, const std::string& root, const IngestResult& ing, const Graph& g,
                            const std::vector<char>& changedFile,
                            std::uint32_t onlyRoot = UINT32_MAX )   // multi-root §5: co-change mined within that root only
{
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    const std::uint32_t N = std::uint32_t( ing.symbols.size() );

    std::uint32_t       nChanged = 0;
    for( std::uint32_t f = 0; f < F; ++f ) if( changedFile[f] ) ++nChanged;
    std::vector<NodeId> changedSyms;
    for( NodeId i = 0; i < N; ++i ) if( changedFile[ ing.symbols[i].fileId ] ) changedSyms.push_back( i );

    std::fprintf( out, "ctxpack situational-awareness — %u changed file(s), %zu symbols in them\n", nChanged, changedSyms.size() );
    if( changedSyms.empty() )
    { std::fprintf( out, "  (no indexed symbols in the changed files — nothing to analyze)\n" ); return; }

    // (1) blast radius — transitive callers (everything that reaches the changed symbols), per non-changed file
    const std::vector<NodeId>  reach = transitiveCallers( g, changedSyms );
    std::vector<std::uint32_t> fileReachers( F, 0 );
    for( NodeId n : reach ) if( !changedFile[ ing.symbols[n].fileId ] ) ++fileReachers[ ing.symbols[n].fileId ];
    std::vector<std::uint32_t> affected;
    for( std::uint32_t f = 0; f < F; ++f ) if( fileReachers[f] ) affected.push_back( f );
    std::sort( affected.begin(), affected.end(), [ & ]( std::uint32_t a, std::uint32_t b )
               { return fileReachers[a] != fileReachers[b] ? fileReachers[a] > fileReachers[b] : ing.files[a] < ing.files[b]; } );
    // §A3b (PLAN_outputAudit2_2026-07-28.md): the row list below stays capped at 8 — --situ is a fixed report,
    // not a paging verb (§A3a is the one that migrated) — but the header now SAYS so, the same "showing N of M"
    // convention --report's god-files section already uses three lines of code away, so a reader isn't left
    // to notice on their own that 17 files summed to only 58 of 68 symbols.
    // §B3 knock-on GAP: this used to say "(showing 8; full list: --pr-context)" — but pr-context's own
    // per-file <impact> list is ALSO capped (at 20, disclosed via shown=/capped=, §B3), so it never printed
    // a "full list" either. Reworded to what pr-context actually gives: a capped list of its own, per file.
    // §B12.1: "(showing 8" carried neither a UNIT nor a remainder, so a reader who noticed the 8 rows summed
    // to 59 of the stated 69 symbols had no way to tell whether 8 counted files, symbols or something else.
    // "showing 8 of 17 files" self-explains the gap without a second sentence.
    std::string blastNote = situShowingNote( kSituBlastFilesShown, affected.size(), "files" );
    if( !blastNote.empty() ) blastNote.insert( blastNote.size() - 1, "; --pr-context's own per-file blast-radius list is also capped, at 20" );
    std::fprintf( out, "  [1] blast radius: %zu symbols across %zu files transitively depend on these changes%s\n",
                  reach.size(), affected.size(), blastNote.c_str() );
    for( std::size_t i = 0; i < affected.size() && i < kSituBlastFilesShown; ++i )
        std::fprintf( out, "        %s  (%u dependent symbols)\n", ing.files[ affected[i] ].c_str(), fileReachers[ affected[i] ] );

    // (2) tests to run — the test files among the dependents (the --affected set)
    std::vector<std::uint32_t> tests;
    for( std::uint32_t f : affected ) if( isTestPath( ing.files[f] ) ) tests.push_back( f );
    // §H6 (W3FIX): this header printed the FULL count then listed at most 25 rows, silently — on the one
    // section whose sibling --test-gate calls its <t> rows "the COMPLETE obligation".
    std::fprintf( out, "  [2] tests to run (%zu)%s%s", tests.size(), situShowingNote( kSituTestRowsShown, tests.size(), "tests" ).c_str(),
                  tests.empty() ? ": (none transitively reach these files)\n" : ":\n" );
    // §P11.4: this section says "tests to run" and named files that are not commands. The runner is appended
    // where one is DERIVABLE and omitted where it is not — see testmap.h; a guessed command is worse than none.
    const TestRunnerIndex situRunners( ing );
    for( std::size_t i = 0; i < tests.size() && i < kSituTestRowsShown; ++i )
        std::fprintf( out, "        %s%s\n", ing.files[ tests[i] ].c_str(), runSuffixText( situRunners, tests[i] ).c_str() );
    // §B7.3: this section inherits --affected's blind spot without --affected's disclosure — a shell harness
    // runs the compiled BINARY as a subprocess, which is not a call edge, so no test/*.sh gate can EVER be
    // named above, however much of the change it exercises. Same number, same counter as --affected's
    // script_gates_unmodelled= (testmap.h), because it is literally the same blindness on the same traversal
    // — and it matters MOST on the empty listing above, which otherwise reads as "nothing tests this".
    std::fprintf( out, "        (%zu test/*.sh gates are NOT modelled: script-to-binary edges are not call edges, "
                       "so they never appear here — a path count, not every one invokes the binary)\n",
                  scriptGatesUnmodelledCount( ing ) );

    // (3) co-change partners NOT in the diff — "you usually edit these together; did you forget?"
    // A4-P10: mine the commit file-sets ONCE (not one `git log` popen per probed file) and answer every probe
    // from the shared sets — identical result (mining is deterministic for a fixed HEAD), no subprocess storm.
    const auto                     coSets = gitCommitFileSets( root, ing, "18 months ago", 30, nullptr, onlyRoot );
    HashMap<std::uint32_t, double> partnerDeg;
    std::uint32_t                  probed = 0;
    for( std::uint32_t f = 0; f < F && probed < 20; ++f )
    {
        if( !changedFile[f] ) continue;
        ++probed;
        std::uint32_t                commits = 0;
        const std::vector<CoPartner> ps      = cochangePartners( ing, ing.files[f], commits, coSets );
        for( const CoPartner& p : ps )
            if( !changedFile[ p.fileId ] ) { double& d = partnerDeg[ p.fileId ]; if( p.deg > d ) d = p.deg; }
    }
    std::vector<std::pair<std::uint32_t, double>> partners( partnerDeg.begin(), partnerDeg.end() );
    std::sort( partners.begin(), partners.end(), [ & ]( const auto& a, const auto& b )
               { return a.second != b.second ? a.second > b.second : ing.files[a.first] < ing.files[b.first]; } );
    // §H6 (W3FIX): same undisclosed cap as [2] — 18 partners, 8 rows on this repo's own src/graph.h probe.
    std::fprintf( out, "  [3] co-change — usually edited with these but NOT in your diff (%zu)%s:\n",
                  partners.size(), situShowingNote( kSituPartnerRowsShown, partners.size(), "files" ).c_str() );
    if( partners.empty() ) std::fprintf( out, "        (none, or no git history)\n" );
    for( std::size_t i = 0; i < partners.size() && i < kSituPartnerRowsShown; ++i )
        std::fprintf( out, "        %s  (co-edited in %.0f%% of commits)\n", ing.files[ partners[i].first ].c_str(), partners[i].second * 100.0 );
}

// ---- structured situational awareness for a DIFF (S5-D) — the same analyses as writeSituation, returned as
//      pure DATA (no JSON, no I/O) so the MCP layer can serialize it with its own escaper. The five facts the
//      situational_awareness(diff) verb reports. Each list is deterministically ordered. -------------------
struct SituationFacts
{
    std::vector<std::uint32_t>                    changed;        // the changed file ids (sorted), for context
    std::vector<std::uint32_t>                    blastRadius;    // non-changed files transitively reaching the diff (by # dependent symbols desc, path asc)
    std::vector<std::uint32_t>                    blastDependents;// §B6 M11: PARALLEL to blastRadius — how many dependent SYMBOLS each
                                                                  //   of those files contributes. It is already the sort key above, so
                                                                  //   consumers were shown an ordering whose magnitude they could not
                                                                  //   read: the CLI text report prints "(N dependent symbols)" per line
                                                                  //   and the MCP JSON emitted {"file":…} only, i.e. a blast radius with
                                                                  //   no size. Kept as a parallel array (SoA), not folded into a pair,
                                                                  //   so existing readers of blastRadius are untouched.
    std::vector<std::uint32_t>                    tests;          // test files among blastRadius (path asc) — the tests to run
    std::vector<std::pair<std::uint32_t, double>> forgotten;     // (file, co-change degree) usually edited together but NOT in the diff (deg desc, path asc)
    std::vector<std::pair<std::uint32_t, std::uint64_t>> hotspots; // (changed file, cx×churn score) for high-risk changed files (score desc, path asc)
    std::vector<std::string>                      modulesTouched; // distinct TOP-LEVEL directory of each changed file (sorted)
};

inline SituationFacts computeSituationFacts( const std::string& root, const IngestResult& ing, const Graph& g,
                                             const std::vector<char>& changedFile )
{
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    const std::uint32_t N = std::uint32_t( ing.symbols.size() );
    SituationFacts facts;

    for( std::uint32_t f = 0; f < F; ++f ) if( changedFile[f] ) facts.changed.push_back( f );

    std::vector<NodeId> changedSyms;
    for( NodeId i = 0; i < N; ++i ) if( changedFile[ ing.symbols[i].fileId ] ) changedSyms.push_back( i );

    // (1) blast radius — files (non-changed) with ≥1 symbol transitively reaching the changed set, ranked by
    //     dependent-symbol count then path. (2) tests — the test files among them.
    const std::vector<NodeId>  reach = transitiveCallers( g, changedSyms );
    std::vector<std::uint32_t> fileReachers( F, 0 );
    for( NodeId n : reach ) if( !changedFile[ ing.symbols[n].fileId ] ) ++fileReachers[ ing.symbols[n].fileId ];
    for( std::uint32_t f = 0; f < F; ++f ) if( fileReachers[f] ) facts.blastRadius.push_back( f );
    std::sort( facts.blastRadius.begin(), facts.blastRadius.end(), [ & ]( std::uint32_t a, std::uint32_t b )
               { return fileReachers[a] != fileReachers[b] ? fileReachers[a] > fileReachers[b] : ing.files[a] < ing.files[b]; } );
    // §B6 M11: the magnitude behind that ordering, captured in blastRadius order (so index i of the two
    // vectors is the same file). Filled AFTER the sort — never before it, or the pairing silently rotates.
    facts.blastDependents.reserve( facts.blastRadius.size() );
    for( std::uint32_t f : facts.blastRadius ) facts.blastDependents.push_back( fileReachers[f] );
    VERIFY( facts.blastDependents.size() == facts.blastRadius.size() );

    for( std::uint32_t f : facts.blastRadius ) if( isTestPath( ing.files[f] ) ) facts.tests.push_back( f );
    std::sort( facts.tests.begin(), facts.tests.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );

    // Σ cognitive complexity per changed file (the complexity axis of the hotspot signal).
    std::vector<std::uint64_t> ccxSum( F, 0 );
    for( NodeId i = 0; i < N; ++i ) ccxSum[ ing.symbols[i].fileId ] += ing.symbols[i].ccx;

    // (3) forgotten — co-change partners NOT in the diff; (4) hotspots — changed files with high cx×churn.
    //     Both reuse cochangePartners (its outCommits = the file's churn, the second hotspot axis). Probe each
    //     changed file once (capped), deterministically.
    // A4-P10: mine the commit file-sets ONCE and answer every probe from the shared sets (was one `git log`
    // popen per probed file — up to 40 — the O(files)-subprocess storm). Deterministic for a fixed HEAD.
    const auto                     coSets = gitCommitFileSets( root, ing, "18 months ago", 30 );
    HashMap<std::uint32_t, double> partnerDeg;
    std::uint32_t                  probed = 0;
    for( std::uint32_t f = 0; f < F && probed < 40; ++f )
    {
        if( !changedFile[f] ) continue;
        ++probed;
        std::uint32_t                commits = 0;
        const std::vector<CoPartner> ps      = cochangePartners( ing, ing.files[f], commits, coSets );
        for( const CoPartner& p : ps )
            if( !changedFile[ p.fileId ] ) { double& d = partnerDeg[ p.fileId ]; if( p.deg > d ) d = p.deg; }
        const std::uint64_t score = ccxSum[f] * std::uint64_t( commits );      // hotspot = complexity × churn
        if( score > 0 ) facts.hotspots.push_back( { f, score } );
    }
    facts.forgotten.assign( partnerDeg.begin(), partnerDeg.end() );
    std::sort( facts.forgotten.begin(), facts.forgotten.end(), [ & ]( const auto& a, const auto& b )
               { return a.second != b.second ? a.second > b.second : ing.files[a.first] < ing.files[b.first]; } );
    std::sort( facts.hotspots.begin(), facts.hotspots.end(), [ & ]( const auto& a, const auto& b )
               { return a.second != b.second ? a.second > b.second : ing.files[a.first] < ing.files[b.first]; } );

    // (5) modules touched — the distinct first directory component of each changed file RELATIVE to the scan
    //     root (e.g. root/src/graph.h → "src"; root/test/foo/x.cpp → "test"), sorted. The "which subsystems did
    //     this diff hit" summary. ing.files are absolute, so we strip the root prefix first; a file directly in
    //     the root (no subdir) yields its bare filename's parent, i.e. "(root)".
    {
        std::string rootPrefix = root;
        while( rootPrefix.size() > 1 && rootPrefix.back() == '/' ) rootPrefix.pop_back();   // normalize trailing '/'
        std::vector<std::string> mods;
        for( std::uint32_t f : facts.changed )
        {
            std::string_view p = ing.files[f];
            if( p.size() > rootPrefix.size() + 1 && p.compare( 0, rootPrefix.size(), rootPrefix ) == 0 && p[ rootPrefix.size() ] == '/' )
                p = p.substr( rootPrefix.size() + 1 );        // → path relative to root
            const std::size_t sl = p.find( '/' );
            mods.emplace_back( sl == std::string_view::npos ? std::string( "(root)" ) : std::string( p.substr( 0, sl ) ) );
        }
        std::sort( mods.begin(), mods.end() );
        mods.erase( std::unique( mods.begin(), mods.end() ), mods.end() );
        facts.modulesTouched = std::move( mods );
    }
    return facts;
}

// ---- --test-gate (A4-R2): TDAD-parity regression contract ----------------------------------------------------
// Packages the already-shipped --situ/--affected machinery into ONE gate-shaped contract, mirroring
// --quality-delta's convergence-loop shape: the REPORT is always printed, the EXIT CODE is the gate. Motivated
// by TDAD (arXiv 2603.17973) — giving the agent a static call-graph+test map to query cut agent-caused
// regressions 6.08%→1.82% (−70%), whereas prose instructions WITHOUT the map made agents worse. Two obligations
// for a change set (default = git diff):
//   TESTS TO RUN          — the test files that transitively reach the changed symbols (= the --affected answer).
//   UNTESTED BLAST RADIUS — the impacted (non-changed, non-test) symbols NOT reached by ANY test file.
// It reuses the situ machinery (transitiveCallers for the blast radius, isTestPath for the test partition,
// forwardReach for test coverage) — it does NOT re-implement blast-radius traversal, and it skips the co-change
// git mining (irrelevant to the gate). This gate NAMES tests; it cannot OBSERVE a run, so the exit contract is
// about the EXISTENCE of obligations, not their satisfaction: the agent loop is run the named tests, then rely
// on green tests.
struct TestGateResult
{
    std::uint32_t              changedFiles    = 0;   // # changed files (the <test-gate changed=> header)
    std::size_t                impactedSymbols = 0;   // blast-radius symbol count, non-changed files (impacted=)
    std::vector<std::uint32_t> tests;                 // test files to run (path asc) — the --affected answer
    std::vector<NodeId>        untested;              // impacted symbols reached by NO test (ccx desc, file asc, name asc)
    bool                       hasObligations  = false; // !tests.empty() || !untested.empty()
};

// The lane-independent half of computeTestGate: what the test files transitively call. A pure function of
// (ing, g), so a caller running the gate N times over N different change sets (--plan-lanes, N up to 16 on
// this repo's 5763 symbols) computes it ONCE and hands it in, instead of paying N redundant full forward
// traversals. Every pre-existing call site keeps its own inline computation via the default argument below,
// so their bytes are unchanged.
inline std::vector<char> testSeedForwardReach( const IngestResult& ing, const Graph& g )
{
    std::vector<NodeId> testSeeds;
    for( NodeId i = 0; i < NodeId( ing.symbols.size() ); ++i )
        if( isTestPath( ing.files[ ing.symbols[i].fileId ] ) ) testSeeds.push_back( i );
    return forwardReach( g, testSeeds );
}

// The gate's ONE computation, expressed over an explicit CHANGED-SYMBOL set rather than a changed-FILE mask.
// `isChangedSym` is the per-node "this is the change, not its radius" mask — the file-mask form below marks
// every symbol of every changed file, which is exactly what the mask-driven loop did inline before, so that
// path is byte-identical. A caller with per-SYMBOL claims (--plan-lanes) marks only its claims, so a lane that
// owns one symbol in a 3000-line file is not charged that whole file's obligations (PLAN_planLanes §7.4a).
// `testReachIn` is the hoisted testSeedForwardReach result, or nullptr to compute it here.
inline TestGateResult computeTestGateFor( const IngestResult& ing, const Graph& g,
                                          const std::vector<NodeId>& changedSyms, const std::vector<char>& isChangedSym,
                                          std::uint32_t changedFileCount, const std::vector<char>* testReachIn )
{
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    TestGateResult      r;
    r.changedFiles = changedFileCount;
    if( changedSyms.empty() ) return r;   // no indexed symbols in the change set → no obligations

    // blast radius — the ONE traversal (reused, not re-implemented): everything that transitively reaches the
    // changed symbols. Coverage — the forward dual from every test-file symbol (what the tests transitively call).
    const std::vector<NodeId> reach = transitiveCallers( g, changedSyms );

    const std::vector<char>  ownedReach = testReachIn ? std::vector<char>{} : testSeedForwardReach( ing, g );
    const std::vector<char>& testReach  = testReachIn ? *testReachIn : ownedReach;

    // tests to run — the test files among the impacted set (= --affected). untested — impacted, non-changed,
    // non-test symbols that no test transitively reaches.
    std::vector<char> testFileSeen( F, 0 );
    for( NodeId n : reach )
    {
        const std::uint32_t f = ing.symbols[n].fileId;
        if( isChangedSym[n] ) continue;                // the changed symbols are the change, not its radius
        ++r.impactedSymbols;
        if( isTestPath( ing.files[f] ) ) { if( !testFileSeen[f] ) { testFileSeen[f] = 1; r.tests.push_back( f ); } }
        else if( !testReach[n] )         { r.untested.push_back( n ); }
    }
    std::sort( r.tests.begin(), r.tests.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );
    std::sort( r.untested.begin(), r.untested.end(), [ & ]( NodeId a, NodeId b )
               {
                   if( ing.symbols[a].ccx != ing.symbols[b].ccx ) return ing.symbols[a].ccx > ing.symbols[b].ccx;     // riskiest first
                   const std::string& fa = ing.files[ ing.symbols[a].fileId ]; const std::string& fb = ing.files[ ing.symbols[b].fileId ];
                   if( fa != fb ) return fa < fb;
                   if( ing.symbols[a].name != ing.symbols[b].name ) return ing.symbols[a].name < ing.symbols[b].name;
                   return a < b;                                                                                       // total order
               } );
    r.hasObligations = !r.tests.empty() || !r.untested.empty();
    return r;
}

// The changed-FILE form — every pre-existing caller (--test-gate, --affected, the MCP test_gate verb). A file
// mask marks EVERY symbol of every changed file as "the change", which is what this function's own inline loop
// did before it was expressed over computeTestGateFor, so its output is byte-identical.
inline TestGateResult computeTestGate( const IngestResult& ing, const Graph& g, const std::vector<char>& changedFile )
{
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    const std::uint32_t N = std::uint32_t( ing.symbols.size() );

    std::uint32_t changedFileCount = 0;
    for( std::uint32_t f = 0; f < F; ++f ) if( changedFile[f] ) ++changedFileCount;

    std::vector<char>   isChangedSym( N, 0 );
    std::vector<NodeId> changedSyms;
    for( NodeId i = 0; i < N; ++i ) if( changedFile[ ing.symbols[i].fileId ] ) { isChangedSym[i] = 1; changedSyms.push_back( i ); }

    return computeTestGateFor( ing, g, changedSyms, isChangedSym, changedFileCount, nullptr );
}

// The changed-SYMBOL form (PLAN_planLanes §7.4a). `changedSyms` need not be sorted or unique; the mask is
// derived from it here so a caller cannot hand in a mask that disagrees with its own symbol list.
inline TestGateResult computeTestGateForSymbols( const IngestResult& ing, const Graph& g,
                                                 const std::vector<NodeId>& changedSyms, const std::vector<char>* testReachIn = nullptr )
{
    const std::uint32_t N = std::uint32_t( ing.symbols.size() );
    std::vector<char>   isChangedSym( N, 0 );
    std::vector<char>   fileSeen( ing.files.size(), 0 );
    std::uint32_t       changedFileCount = 0;
    for( NodeId n : changedSyms )
    {
        if( n >= N ) continue;                                   // out-of-range id → skip, never index past the end
        isChangedSym[n] = 1;
        const std::uint32_t f = ing.symbols[n].fileId;
        if( f < fileSeen.size() && !fileSeen[f] ) { fileSeen[f] = 1; ++changedFileCount; }
    }
    return computeTestGateFor( ing, g, changedSyms, isChangedSym, changedFileCount, testReachIn );
}

// The untested-row display DEFAULT page size. ONE definition: the XML and JSON reports must never disagree
// about how many offenders they truncated to, and two literal 25s in two emitters is exactly how that drifts
// apart. §A3a: this is now a raisable DEFAULT (via effectiveRowCap( pageLimit, kMaxUntestedRows )), not a hard
// ceiling — --test-gate joined pageview.h's paging vocabulary, so a caller with >25 offenders can walk the
// rest with --limit/--offset instead of seeing 25 of N with no disclosure that more exist.
inline constexpr std::size_t kMaxUntestedRows = 25;

// §A3a (PLAN_outputAudit2_2026-07-28.md): the report emitters below are COMPUTE/EMIT split rather than
// grown-in-place — `writeTestGate`/`writeTestGateJson`/`forEachUntestedRow` took the (ing, g, changedFile)
// triple and computed + rendered in one call; the paging window needs `computeTestGate`'s result BEFORE it
// can be sized, so the emit half now takes the already-computed `TestGateResult` (computeTestGate stays the
// ONE gate decision, unchanged, still called exactly once per report). This is a genuinely better seam —
// a caller that wants the SAME gate decision rendered twice (e.g. a future --format=columnar sibling) no
// longer pays for a second blast-radius traversal — and it is also why these are NEW names rather than the
// old ones with two more parameters bolted on: main.cpp was the only caller either way, so there is no
// compatibility reason to keep the old 5-arg self-computing shape reachable and unused (which would just
// trade one quality finding for another — an unused header function is a dead-code regression, not a fix).

// Walk the untested rows in window [win.begin, win.end), handing each to the caller's formatter. Both
// --test-gate reports share this so the window, the ordering and the symbol/file lookup live in one place;
// only the printf shape differs. `win` is computed ONCE by the caller (pageWindow() over effectiveRowCap()),
// so XML and JSON can never disagree about which rows are "shown" for a given --limit/--offset.
template<class EmitRow>
inline void walkUntestedRows( const IngestResult& ing, const TestGateResult& r, PageWindow win, EmitRow emit )
{
    for( std::size_t i = win.begin; i < win.end; ++i )
    {
        const Symbol& s = ing.symbols[ r.untested[i] ];
        emit( i - win.begin, s, ing.files[ s.fileId ] );
    }
}

// The legend both --test-gate dialects print — one string, because a sentence that exists twice is a
// sentence that will be fixed once. §B7.1/.2/.3 all land here: the two listings are named separately, the
// <t> block's page-invariance is stated (a concatenating walker would otherwise collect it once per page),
// limit=N is offered (§A10.1's raise clause, missed on the one verb that CREATES an exit-4 obligation), and
// script_gates_unmodelled= says what the walk is blind to — verbatim the sentence --affected already prints,
// because the number and the blindness are the same on both verbs.
inline constexpr const char* kTestGateLegend =
    "ctxpack test-gate (TDAD-parity, arXiv 2603.17973): the tests to run for this change + the "
    "UNTESTED blast radius. A queryable call-graph+test map cut agent-caused regressions -70% "
    "(6.08%->1.82%); this gate names the obligations, the agent runs the tests then relies on green. "
    "exit 4 if tests OR untested is non-empty. TWO INDEPENDENT LISTINGS, each with its own row count: "
    "shown_tests= counts the <t> tests-to-run rows and shown_untested= counts the <u> blast-radius rows "
    "(a single shown= could only ever have described one of them). The <t> rows are the COMPLETE obligation "
    "and are never windowed, so they REPEAT VERBATIM on every page — a walker that concatenates pages must "
    "take them from one page only; offset=/limit= window the <u> rows alone. The <u> listing shows 25 rows "
    "by default: raise the default cap with limit=N (offset=M pages). script_gates_unmodelled= counts "
    "test/*.sh runners in the corpus (a path count; not every one invokes the binary) - script-to-binary "
    "edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=. "
    // §B12.5 — the cross-verb UNIT collision, disclosed on each verb that spells it. Each legend was
    // locally honest and the three numbers are not comparable, which is exactly how a reader gets it wrong.
    "UNIT: untested= here counts impacted SYMBOLS. The seams verb spells untested= over cross-directory "
    "call EDGES and the flip verb over the defs a gate lights, so the three numbers count three different "
    "things and must never be compared or summed across verbs. -->";

// Emit the --test-gate report as minified XML (house shape) for an ALREADY-COMPUTED gate result. Deterministic
// + xmllint-clean; the header counts are always full. §A3a: the <u> untested-row list joins pageview.h's
// paging vocabulary — `pageLimit`/`pageOffset` (default 0/0 = the historic 25-row page) window it.
//
// §B7.1: the row disclosure is the NOUN-PREFIXED form (pageview.h, THE TRUNCATION VOCABULARY rule 1 + the
// rule-6 exception), not a bare shown=. The report emits 26 rows on a default page — one <t> plus 25 <u> —
// and a single shown="25" claimed to describe all of them while measuring only the second listing. The two
// counts are now separate names, and the paging half (pagingDisclosure) attaches to the <u> listing, which
// is the only one --limit/--offset windows.
inline void writeTestGateReport( std::FILE* out, const IngestResult& ing, const TestGateResult& r,
                                 const std::string& root = {}, int pageLimit = 0, int pageOffset = 0 )
{
    std::vector<char> esc;
    const auto         ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    std::fprintf( out, "<!-- %s", kTestGateLegend );
    const PageWindow  uw        = pageWindow( r.untested.size(), effectiveRowCap( pageLimit, int( kMaxUntestedRows ) ), pageOffset );
    const std::size_t shownRows = uw.end - uw.begin;
    char              uab[ kPageDisclosureCap ];
    // r26-stamp Task A: anchor tests/untested to the commit (+dirty state) the change set was diffed against
    // — "" (omitted) when the caller passes no root (root="" ⇒ non-git-style skip, same convention as gitstamp.h).
    std::fprintf( out, "<test-gate changed=\"%u\" impacted=\"%zu\" tests=\"%zu\" untested=\"%zu\""
                       " shown_tests=\"%zu\" tests_capped=\"0\" shown_untested=\"%zu\" untested_capped=\"%d\""
                       " script_gates_unmodelled=\"%zu\"%s%s>",
                  r.changedFiles, r.impactedSymbols, r.tests.size(), r.untested.size(),
                  r.tests.size(), shownRows, shownRows < r.untested.size() ? 1 : 0,
                  scriptGatesUnmodelledCount( ing ),
                  pagingDisclosure( uab, sizeof( uab ), r.untested.size(), uw.end, pageLimit, pageOffset ),
                  gitstamp::atAttr( root ).c_str() );
    // §P11.4: this gate EXITS 4 on the obligation, so its rows carry the command that discharges it — where
    // one is derivable. Absent run= = not derivable (testmap.h states why a fallback would be a lie).
    const TestRunnerIndex gateRunners( ing );
    for( std::uint32_t f : r.tests )
        std::fprintf( out, "<t p=\"%s\"%s/>", ex( ing.files[f] ).c_str(), runAttr( gateRunners, f, ex ).c_str() );
    walkUntestedRows( ing, r, uw, [ & ]( std::size_t, const Symbol& s, const std::string& path )
    {
        std::fprintf( out, "<u sym=\"%s\" p=\"%s\" ccx=\"%u\"/>", ex( s.name ).c_str(), ex( path ).c_str(), s.ccx );
    } );
    std::fprintf( out, "</test-gate>" );
}

// L2: --json sibling of writeTestGateReport — same TestGateResult in (the ONE gate decision, computed once
// by the caller), keys mirror the XML attr names (changed/impacted/tests/untested/p/sym/ccx). §A3a: the <u>
// paging disclosure mirrors the XML sibling key-for-key via pageview.h's table-selected emitter — the SAME
// window math and the SAME function as the XML sibling, punctuation only from the table, so the two reports
// can never disagree about which rows are "shown". jsonStr lives in serialize.h, already included by every
// caller of situ.h (main.cpp).
//
// §B7.1/.3: the JSON dialect MIRRORS whatever the XML says — shown_tests/tests_capped/shown_untested/
// untested_capped/script_gates_unmodelled, with the paging half attached to the untested listing alone
// (pagingDisclosure, kJsonPageSyntax). The legend a JSON caller cannot see is why the KEYS have to be
// self-describing: `shown` next to two arrays was ambiguous in a way `shown_untested` cannot be.
inline void writeTestGateReportJson( std::FILE* out, const IngestResult& ing, const TestGateResult& r,
                                     const std::string& root = {}, int pageLimit = 0, int pageOffset = 0 )
{
    // r26-stamp Task A: the JSON sibling of the XML at= anchor — "at":null (never a fake sha) on a non-git root.
    const std::string atVal  = gitstamp::stampAt( root );
    const std::string atJson = atVal.empty() ? std::string( "null" ) : ( "\"" + atVal + "\"" );

    const PageWindow   uw        = pageWindow( r.untested.size(), effectiveRowCap( pageLimit, int( kMaxUntestedRows ) ), pageOffset );
    const std::size_t  shownRows = uw.end - uw.begin;
    char pageJson[ kPageDisclosureCap ];
    pagingDisclosure( pageJson, sizeof( pageJson ), r.untested.size(), uw.end, pageLimit, pageOffset, kJsonPageSyntax );

    std::fprintf( out, "{\"changed\":%u,\"impacted\":%zu,\"tests\":%zu,\"untested\":%zu"
                       ",\"shown_tests\":%zu,\"tests_capped\":false,\"shown_untested\":%zu,\"untested_capped\":%s"
                       ",\"script_gates_unmodelled\":%zu%s,\"at\":%s,\"tests_to_run\":[",
                 r.changedFiles, r.impactedSymbols, r.tests.size(), r.untested.size(),
                 r.tests.size(), shownRows, shownRows < r.untested.size() ? "true" : "false",
                 scriptGatesUnmodelledCount( ing ), pageJson, atJson.c_str() );
    const TestRunnerIndex gateRunners( ing );                       // §P11.4, the JSON sibling of the XML run=
    const auto            jesc = []( std::string_view s ) { return jsonStr( s ); };
    for( std::size_t i = 0; i < r.tests.size(); ++i )
        std::fprintf( out, "%s{\"p\":\"%s\"%s}", i == 0 ? "" : ",", jsonStr( ing.files[ r.tests[i] ] ).c_str(),
                      runFieldJson( gateRunners, r.tests[i], jesc ).c_str() );
    std::fprintf( out, "],\"untested_blast_radius\":[" );
    walkUntestedRows( ing, r, uw, [ & ]( std::size_t i, const Symbol& s, const std::string& path )
    {
        std::fprintf( out, "%s{\"sym\":\"%s\",\"p\":\"%s\",\"ccx\":%u}", i == 0 ? "" : ",",
                     jsonStr( s.name ).c_str(), jsonStr( path ).c_str(), s.ccx );
    } );
    std::fprintf( out, "]}" );
}

}   // namespace ctx
