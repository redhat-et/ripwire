#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_change.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

// verbs_change.h — the change/diff-awareness family, moved VERBATIM from main.cpp in the 2026-08-29
// split: runAffected, runExercises, runChangeViews (--handoff/--situ/--test-gate/--pr-context/
// --export=cc.json), runFromTrace + the --run-trace capture machinery, and the cross-branch block —
// runMergeScout, --plan-lanes (readBriefFile/laneCorpusStats/runPlanLanes — calls the for family's
// computeLensRanking, which pins this section after verbs_for.h), buildHistoryIndex, runFlip,
// runAbiCheck, runCrossRef (--whereis/--stray-content), runDocDrift and runPlanLint. Same contract as every
// verbs_*.h: reopens main.cpp's unnamed namespace — one TU, one unnamed namespace, internal linkage
// unchanged, zero new API surface — under the RIPWIRE_MAIN_TU guard.

namespace
{

// §P9 N5 / §B7.3: --affected walks the CALL graph to find tests that reach a change; test/*.sh gates that
// invoke the compiled BINARY as a subprocess are invisible to that walk. The counter used to live here, one
// verb wide; --test-gate and --situ inherit the SAME blindness from the SAME traversal and had no such
// tell, so it moved down to testmap.h (rw::scriptGatesUnmodelledCount) where all three read one number.
using rw::scriptGatesUnmodelledCount;

// §A9.1 — the INVERSE blindness, disclosed on the inverse verb. --affected discloses the script gates its
// call-graph walk cannot see (script_gates_unmodelled= above); --exercises walks the SAME edges in the
// other direction and had no such tell, so on a corpus whose gates are all shell scripts its modal answer
// was a bare `reaches="0"` — indistinguishable from "this test covers nothing". A shell harness invokes the
// compiled binary as a SUBPROCESS; there is no call edge from the script to the code it exercises, so the
// zero is a limit of the model, not a measurement of the test.
//
// Returns the harness class of the matched SEED files: "script" (every seed is a shell script — the whole
// answer comes from subprocess harnesses), "mixed" (some are), or nullptr (none — a .cpp/.py harness, whose
// calls ARE modelled, so the count needs no caveat and that output stays byte-identical).
inline const char* exercisesHarnessKind( const rw::IngestResult& ing, const std::vector<std::uint32_t>& seedFiles )
{
    std::size_t scriptSeedCount = 0;
    for( const std::uint32_t f : seedFiles )
    {
        const std::string& fp = ing.files[f];
        if( fp.size() >= 3 && fp.compare( fp.size() - 3, 3, ".sh" ) == 0 )
        {
            ++scriptSeedCount;
        }
    }
    if( scriptSeedCount == 0 )
    {
        return nullptr;
    }
    return scriptSeedCount == seedFiles.size() ? "script" : "mixed";
}

// The disclosure itself: ` harness="script|mixed" note="…"`, or "" when every seed's calls ARE modelled —
// so a .cpp/.py harness's output keeps the pre-§A9 bytes exactly.
inline std::string exercisesHarnessAttr( const rw::IngestResult& ing, const std::vector<std::uint32_t>& seedFiles )
{
    const char* kind = exercisesHarnessKind( ing, seedFiles );
    if( kind == nullptr )
    {
        return {};
    }
    return std::string( " harness=\"" ) + kind + "\" note=\"a shell gate invokes the compiled binary as a subprocess; "
           "script-to-binary edges are not modelled, so reaches= counts call-graph reach only and cannot see what the "
           "subprocess covers\"";
}

std::optional<int> runAffected( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;

    // --affected=F1,F2,... / --affected=SYM: test files that transitively reach the changed files OR the
    // changed SYMBOL (impact analysis for review, and — §P11.2a — for change PLANNING).
    if( !cfg.affectedFiles.empty() )
    {
        // §P11.2a: the map was file-granular, so "which tests cover the function I am about to change?" had
        // to be widened to its whole FILE first, over-reporting the obligation. Only the SEED SET changes
        // here: everything below (transitiveCallers → isTestPath → path-sorted rows) is the same traversal
        // --affected always ran. The file-first argument rule and its per-item refusal live in
        // testmap.h::resolveAffectedSeeds; only the did-you-mean wording is main's (withDidYouMean is).
        const rw::AffectedSeeds sel = rw::resolveAffectedSeeds( ing, cfg.affectedFiles );
        if( !sel.ok )
        {
            // §M7 (W3FIX): resolveAffectedSeeds accepts file:name and path::scope::name too, so a bad item gets
            // the shared file-half diagnosis appended to this arm's own two-reading sentence (which explains
            // WHY the item was tried twice, and therefore has to come first).
            // H6/F18: the item was tried as a PATH first, so the PATH near-miss comes first too — the
            // pre-fix arm offered only selectorFaultClause's symbol suggestion and answered `--affected=tow.c`
            // with "did you mean 'TOOLS'?" while `two.c` sat in the file list.
            const std::string affectedNearPath = rw::nearestIndexedFileClause( ing, sel.badItem );
            std::fprintf( stderr, "ripwire: --affected: '%s' matches no indexed file path (as a path pattern) and no indexed "
                                  "symbol (as a symbol name; file:name and path::scope::name also accepted)%s%s\n",
                          sel.badItem.c_str(), affectedNearPath.c_str(),
                          affectedNearPath.empty() ? rw::selectorFaultClause( ing, sel.badItem, "--affected=" ).c_str() : "" );
            return 1;
        }
        const std::vector<NodeId>& seeds = sel.seeds;
        if( seeds.empty() ) { std::fprintf( stderr, "ripwire: --affected matched no symbols: %.*s\n", int( cfg.affectedFiles.size() ), cfg.affectedFiles.data() ); return 1; }
        const std::vector<NodeId>  reach = rw::transitiveCallers( g, seeds );
        std::vector<char>          fseen( ing.files.size(), 0 );
        std::vector<std::uint32_t> testFiles;
        for( NodeId n : reach ) { const std::uint32_t f = ing.symbols[n].fileId; if( !fseen[f] && rw::isTestPath( ing.files[f] ) ) { fseen[f] = 1; testFiles.push_back( f ); } }
        std::sort( testFiles.begin(), testFiles.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );
        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // M12: --affected carried no root= at all and printed every <test p=> row as the raw ingest-stored
        // path ("./test/…" on a relative root), unlike --situ/--test-gate/--pr-context/--handoff, whose
        // tests_to_run rows are all root-relative — the L1 finding: "same three tests, same file, two
        // spellings — the four tests_to_run lists cannot be diffed with sort | uniq".
        const bool        afSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
        const std::string afRootPrefix = afSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
        const std::string afRootAttr   = afSingleRoot ? ( " root=\"" + ex( cfg.roots[0] ) + "\"" ) : std::string();
        // No multi-root branch inside the lambda (situ.h's tgPathRel is spelled the same way, deliberately):
        // afRootPrefix is EMPTY under multi-root, and a merged `<label>/<rel>` identity carries neither a
        // leading "./" nor that prefix, so rootRelativeUri returns it byte-identical. One code path, one
        // spelling rule, and the multi-root case is a value rather than a branch.
        const auto         afPathRel   = [ & ]( std::uint32_t fileId ) -> std::string_view
        {
            return rw::sarif::rootRelativeUri( ing.files[ fileId ], afRootPrefix );
        };
        // seeded_by= is the honesty half of the file-first rule: the two readings answer DIFFERENT questions
        // over the same argument string and return different counts, so which one fired is a fact about the
        // measurement, not a detail. seeds= is the resolved seed-symbol count (1 for a lone function, ~84
        // for a header), which is what makes the two readings comparable at a glance.
        std::printf( "<!-- ripwire affected: test files that transitively reach the changed files/symbols (run these); seeded_by= says which reading the argument took. "
                     "script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) — "
                     "script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=/reached=. "
                     "%s-->%s", rw::kGraphCountFloorBriefLegend, rw::rootRelPathsLegend( afSingleRoot ) );
        std::printf( "<affected changed=\"%s\" seeded_by=\"%s\" seeds=\"%zu\" tests=\"%zu\" reached=\"%zu\" script_gates_unmodelled=\"%zu\"%s%s>",
                     ex( cfg.affectedFiles ).c_str(), rw::affectedSeededBy( sel ), seeds.size(), testFiles.size(), reach.size(), scriptGatesUnmodelledCount( ing ),
                     afRootAttr.c_str(),                          // M12: root= says what every <test p=> below is relative to
                     rw::graphCountFloorAttrXml( g ).c_str() );   // H5/M15: gauge + marker; tests=/reached= are a transitive-caller walk over the name-based CSR
        // §P11.4: run= where a REAL runner is derivable, absent where it is not. The index is constructed
        // here (not hoisted into MainDispatch) because it is lazy — a run with no test row reads no script.
        const rw::TestRunnerIndex runners( ing );
        for( std::uint32_t f : testFiles )
        {
            std::printf( "<test p=\"%s\"%s/>", ex( afPathRel( f ) ).c_str(), rw::runAttr( runners, f, ex ).c_str() );
        }
        std::printf( "</affected>" );
        return 0;
    }
    return std::nullopt;
}

// --exercises=TESTFILE (§P11.2b): the INVERSE of --affected. §P11.2 recorded the test<->code map as
// one-directional: the tool answered "which tests reach this code" and nothing answered "what does this
// test exercise?" — the FIRST question when a test fails and you hold its name and nothing else. One BFS
// over edges that already exist (graph.h forwardReach, the dual of the transitiveCallers --affected uses),
// minus the test partition.
//
// Its own handler rather than a branch of runChangeViews for the same reason as elsewhere:
// a verb with a resolve step, two refusals and a windowed emitter is a named handler, not an if-arm.
std::optional<int> runExercises( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;
    const Graph&        g   = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         exSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  exRootPrefix = exSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();

    if( !cfg.exercisesFlag )
    {
        return std::nullopt;
    }
    if( cfg.exercisesFile.empty() )
    {
        std::fprintf( stderr, "ripwire: --exercises needs a test file — e.g. --exercises=test/foo_harness.cpp "
                              "(the inverse of --affected: what that test transitively covers)\n" );
        return 1;
    }

    const ExerciseSeeds sel = resolveExerciseSeeds( ing, cfg.exercisesFile );
    if( !sel.anyFileMatched )
    {
        std::fprintf( stderr, "ripwire: --exercises: no indexed file path matches '%.*s' (the argument is a path pattern, "
                              "like --affected's; use --tree or --grep to find its spelling)%s\n",
                      int( cfg.exercisesFile.size() ), cfg.exercisesFile.data(),
                      rw::nearestIndexedFileClause( ing, cfg.exercisesFile ).c_str() );
        return 1;
    }
    if( sel.testFiles.empty() )
    {
        // The decided non-test behavior (--help states it): refuse, do not widen the verb. See testmap.h.
        std::fprintf( stderr, "ripwire: --exercises: '%.*s' matches %u indexed file(s), none of them a TEST path "
                              "(a test/ or tests/ directory segment, or a test_*/ *_test.* / *_spec.* filename). This verb "
                              "subtracts test code from its answer, which is meaningless for a non-test file — for \"what does "
                              "this call\", use --callees=SYM (1 hop) or --graph-query with a callees(...) closure\n",
                      int( cfg.exercisesFile.size() ), cfg.exercisesFile.data(), sel.nonTestMatches );
        return 1;
    }

    std::vector<NodeId> show = exercisedSymbols( ing, g, sel.seeds );
    const auto [ rank, prIters, prConverged ] = rankGraph( g );
    const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: the legend says "PageRank desc" — so disclose the run
    std::sort( show.begin(), show.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );

    // §P8 / src/pageview.h, THE TRUNCATION VOCABULARY: the symbol listing is the PRIMARY (--limit-windowed)
    // one, so it takes the paging half; the seed-file listing is a second, independent listing and discloses
    // through its own noun-prefixed pair (rules 1 and 6). 40 is --impact's default cap — this verb is its
    // forward dual and a reader crossing between them should not meet two different defaults.
    const PageWindow  epw       = pageWindow( show.size(), effectiveRowCap( cfg.pageLimit, 40 ), cfg.pageOffset );
    const std::size_t shownRows = epw.end - epw.begin;
    const std::size_t shownSeed = std::min<std::size_t>( sel.testFiles.size(), 20 );
    char              epab[ kPageDisclosureCap ];
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    // G4: an XML comment may not contain a double hyphen, so this text names sibling verbs WITHOUT their
    // leading dashes (the same reason every other doc comment in the tool writes "quality-delta", not the
    // flag spelling). xmllint is the gate that catches a regression here.
    const std::string harnessAttr = exercisesHarnessAttr( ing, sel.testFiles );   // §A9.1, empty for a .cpp/.py harness

    std::printf( "<!-- ripwire exercises: the NON-TEST symbols this test transitively calls into — what it covers (the inverse of the affected verb). "
                 "<t> = the seed test files the pattern matched; <s> = the covered symbols, PageRank desc. "
                 "harness=script|mixed says the seed set contains shell gates, whose subprocess coverage this walk cannot see. "
                 "%s%s-->%s", rw::kGraphCountFloorBriefLegend, rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str(), rw::rootRelPathsLegend( exSingleRoot ) );
    const std::string exRootAttr = exSingleRoot ? ( " root=\"" + ex( cfg.roots[0] ) + "\"" ) : std::string();
    std::printf( "<exercises of=\"%s\" seed_files=\"%zu\" shown_seed_files=\"%zu\" seed_files_capped=\"%u\" test_symbols=\"%zu\" reaches=\"%zu\"%s%s%s%s>",
                 ex( cfg.exercisesFile ).c_str(), sel.testFiles.size(), shownSeed,
                 unsigned( shownSeed < sel.testFiles.size() ), sel.seeds.size(), show.size(), harnessAttr.c_str(),
                 ( pageDisclosure( epab, sizeof( epab ), shownRows, show.size(), epw.end, cfg.pageLimit, cfg.pageOffset, true )
                   + rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ) ).c_str(),
                 exRootAttr.c_str(),
                 rw::graphCountFloorAttrXml( g ).c_str() );   // H5/M15: gauge + marker; reaches= is a transitive-callee walk over the name-based CSR
    const rw::TestRunnerIndex runners( ing );      // §P11.4: the seed rows are the tests you are about to re-run
    for( std::size_t i = 0; i < shownSeed; ++i )
    {
        const std::string_view rp = exSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ sel.testFiles[i] ], exRootPrefix ) : std::string_view( ing.files[ sel.testFiles[i] ] );
        std::printf( "<t p=\"%s\"%s/>", ex( rp ).c_str(), rw::runAttr( runners, sel.testFiles[i], ex ).c_str() );
    }
    for( std::size_t i = epw.begin; i < epw.end; ++i )
    {
        const Symbol&           s  = ing.symbols[ show[i] ];
        const std::string_view  rp = exSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], exRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
        std::printf( "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line );
    }
    std::printf( "</exercises>" );
    return 0;
}

std::optional<int> runChangeViews( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::string&                root         = d.root;
    const bool                        multiRoot    = d.multiRoot;
    const std::vector<WorkspaceRoot>& ws           = d.ws;

    // --handoff: the continuation packet for the NEXT session (handoff.h). Multi-root refused earlier in
    // main() with its siblings; this handler only ever sees one root.
    if( cfg.handoff )
    {
        return writeHandoffPacket( stdout, root, ing, g, cfg.tokenBudget );
    }

    // --situ[=FILES]: situational awareness for a change set — blast radius + tests to run + co-change misses,
    // in one call. The daily-driver "what should I know after this edit" verb. Default change set = git diff.
    if( cfg.situ )
    {
        // Multi-root: the default diff is the UNION of per-root `git diff`s, emitted
        // as PER-ROOT sections — each root's changed files, tests_to_run and co-change partners come from its
        // OWN repo, but the blast radius runs on the ONE merged graph, so a service-repo change correctly
        // lists client-repo impact when an evidence edge exists (per-repo history, joint graph).
        if( multiRoot )
        {
            // H6: the list is resolved against the ONE merged index, so its validity is a root-independent
            // fact — check it once, before any root's section is printed, rather than once per root (which
            // would print the same refusal N times) or not at all (the pre-fix silent all-zero mask).
            if( !cfg.situFiles.empty() )
            {
                const rw::ChangedList list = rw::changedMaskFromListChecked( ing, cfg.situFiles );
                if( rw::cliRefusesFileList( ing, "--situ", root, cfg.situFiles, list ) )
                {
                    return 1;
                }
            }
            bool anyGit = false;
            std::vector<std::vector<char>> perRootChanged( ws.size() );
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                if( !cfg.situFiles.empty() )
                {
                    perRootChanged[r] = rw::changedMaskFromList( ing, cfg.situFiles );
                    for( std::size_t f = 0; f < perRootChanged[r].size(); ++f )
                    {
                        if( perRootChanged[r][f] && ing.fileRoot[f] != r )
                        {
                            perRootChanged[r][f] = 0;
                        }
                    }
                    anyGit = true;   // explicit file list — no git needed
                }
                else
                {
                    perRootChanged[r].assign( ing.files.size(), 0 );
                    if( gitChangedFiles( ws[r].arg, ing, perRootChanged[r], r ) )
                    {
                        anyGit = true;
                    }
                }
            }
            if( !anyGit )
            { std::fprintf( stderr, "ripwire --situ: no files given and no git diff in any root (use --situ=F1,F2)\n" ); return 1; }
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                std::fprintf( stdout, "=== root %s (%s) ===\n", ws[r].label.c_str(), ws[r].arg.c_str() );
                bool any = false;
                for( char c : perRootChanged[r] )
                {
                    if( c )
                    {
                        any = true;
                        break;
                    }
                }
                if( !any ) { std::fprintf( stdout, "  (no changed files in this root)\n" ); continue; }
                rw::writeSituation( stdout, ws[r].arg, ing, g, perRootChanged[r], r );
            }
            return 0;
        }

        std::vector<char> changed;
        if( !cfg.situFiles.empty() )
        {
            // H6: the SAME refusal --test-gate takes over the SAME grammar. --situ used to read an
            // unresolvable path as an all-zero mask and print "0 changed file(s) — nothing to analyze" at
            // exit 0 — the false zero that tells an agent its edit has no blast radius.
            rw::ChangedList list = rw::changedMaskFromListChecked( ing, cfg.situFiles );
            if( rw::cliRefusesFileList( ing, "--situ", root, cfg.situFiles, list ) )
            {
                return 1;
            }
            changed = std::move( list.mask );
        }
        else
        {
            changed.assign( ing.files.size(), 0 );
            if( !gitChangedFiles( root, ing, changed ) )
            { std::fprintf( stderr, "ripwire --situ: no files given and no git diff (use --situ=F1,F2)\n" ); return 1; }
        }
        rw::writeSituation( stdout, root, ing, g, changed );
        return 0;
    }

    // --test-gate[=FILES] (A4-R2): TDAD-parity regression contract — the --situ/--affected machinery packaged as
    // one gate. Report (tests to run + untested blast radius) is ALWAYS printed; the EXIT CODE is the gate, like
    // --quality-delta. Default change set = git diff. exit 4 (not 2/3 — quality-delta=2, token-budget=3) when
    // there are obligations (impacted tests to run OR a non-empty untested blast radius); exit 0 when neither.
    if( cfg.testGate )
    {
        std::vector<char> changed;
        if( !cfg.testGateFiles.empty() )
        {
            // An unparseable FILES list REFUSES rather than reading as an all-zero mask ("your change
            // touches nothing") — the silent-zero defect and the refusal's whole argument live on
            // cliRefusesFileList in situ.h. Gate: testgaterefusecheck.sh.
            rw::ChangedList list = rw::changedMaskFromListChecked( ing, cfg.testGateFiles );
            if( rw::cliRefusesFileList( ing, "--test-gate", root, cfg.testGateFiles, list ) )
            {
                return 1;
            }
            changed = std::move( list.mask );
        }
        else
        {
            changed.assign( ing.files.size(), 0 );
            if( !gitChangedFiles( root, ing, changed ) )
            { std::fprintf( stderr, "ripwire --test-gate: no files given and no git diff (use --test-gate=F1,F2)\n" ); return 1; }
        }
        // §A3a: --test-gate joined the pageview.h paging vocabulary — the
        // <u> untested-row list honors --limit/--offset instead of a silent 25-row cap with no disclosure.
        // The gate decision (computeTestGate) is computed ONCE here and handed to whichever report emitter
        // runs, so the two report shapes can never disagree about tests/untested and never re-pay the
        // blast-radius traversal.
        const rw::TestGateResult tg = rw::computeTestGate( ing, g, changed );
        if( cfg.json )
        {
            rw::writeTestGateReportJson( stdout, ing, g, tg, root, cfg.pageLimit, cfg.pageOffset );
        }
        else
        {
            rw::writeTestGateReport( stdout, ing, g, tg, root, cfg.pageLimit, cfg.pageOffset );
        }
        return tg.hasObligations ? 4 : 0;
    }

    // --pr-context[=BASEREF]: Wave-4 no-LLM review-evidence bundle. Default change set = the working-tree
    // diff (git diff HEAD); --pr-context=BASEREF diffs against that ref. Composes the existing analysis
    // (callers / blast radius / affected tests / co-change / owners) into one deterministic per-file XML
    // section. Non-git / git-unavailable → clean degrade (explanatory comment, exit 0). The mask is built
    // via --numstat (not --name-only) so pure mode-flip entries (content-identical, e.g. a chmod) are
    // excluded from the changed set rather than counted as changed files (A3-F10).
    if( cfg.prContext )
    {
        const std::string baseLabel = cfg.prContextBase.empty() ? std::string( "working-tree" ) : std::string( cfg.prContextBase );

        // Multi-root: per-root diff SECTIONS over the ONE merged graph. Each root's
        // changed-file mask is built from its OWN `git diff` (gitDiffChangedMaskNumstat onlyRoot=r), and its
        // owners/co-change come from its own history (writePrContext onlyRoot=r) — git signals are per root,
        // never across (§5). The blast radius / tests / callers deliberately run on the merged graph inside
        // writePrContext, so a service-root change lists client-root impact through a real evidence edge. The
        // per-root <pr-context> sections are wrapped in ONE <pr-context-workspace> element so the document stays
        // single-rooted (G4: xmllint-clean). Trim ladder under --max-tokens: the budget is split PER ROOT,
        // proportional to each root's changed-file count (integer floor; the remainder goes to the
        // lexicographically-first label = ws[0], since ws is in canonical label order) — then each root runs the
        // landed PrTrim ladder against its share. This reuses writePrContext verbatim; it is simpler than forcing
        // one shared global trim level (which would need writePrContext to expose a forced-level render).
        if( multiRoot )
        {
            std::vector<rw::PrContextMask> masks( ws.size() );
            std::vector<std::uint32_t>      changedCount( ws.size(), 0 );
            std::uint32_t                   totalChanged = 0;
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                masks[r] = rw::gitDiffChangedMaskNumstat( ws[r].arg, ing, cfg.prContextBase, r );
                // P0.1/P2.8: this branch had NO refusal at all, so a typo'd — or option-shaped — base ref
                // rendered as an empty workspace bundle at exit 0. A root with no git history is not this
                // case (it still degrades to its own empty section); see prcontext.h §badRef.
                if( masks[r].badRef )
                {
                    std::fprintf( stderr, "ripwire: --pr-context: unknown base ref '%.*s' in root %s\n",
                                  int( cfg.prContextBase.size() ), cfg.prContextBase.data(), ws[r].arg.c_str() );
                    return 1;
                }
                for( char c : masks[r].mask )
                {
                    if( c )
                    {
                        ++changedCount[r];
                    }
                }
                totalChanged += changedCount[r];
            }

            // per-root token budget = proportional split of --max-tokens; remainder → ws[0] (lexicographically-first
            // label). A changed-but-rounded-to-0 root is clamped to 1 so it still runs the ladder (0 = UNLIMITED
            // sentinel in writePrContext, which would wrongly un-cap that root).
            std::vector<std::size_t> rootBudget( ws.size(), 0 );
            if( cfg.maxTokens > 0 && totalChanged > 0 )
            {
                std::size_t assigned = 0;
                for( std::uint32_t r = 0; r < ws.size(); ++r )
                { rootBudget[r] = std::size_t( cfg.maxTokens ) * changedCount[r] / totalChanged; assigned += rootBudget[r]; }
                rootBudget[0] += std::size_t( cfg.maxTokens ) - assigned;   // remainder → canonical-first label
                for( std::uint32_t r = 0; r < ws.size(); ++r )
                {
                    if( changedCount[r] > 0 && rootBudget[r] == 0 )
                    {
                        rootBudget[r] = 1;
                    }
                }
            }

            std::vector<char> prEsc;
            const std::string baseLabelEsc = std::string( escapeXml( std::string_view( baseLabel ), prEsc ) );
            std::printf( "<!-- ripwire pr-context (multi-root workspace): ONE <pr-context> section per root over the "
                         "MERGED graph — per-root changed files / owners / co-change from each repo's own history, "
                         "blast radius crossing roots via real evidence edges. base=%s. deterministic. -->", baseLabelEsc.c_str() );
            std::printf( "<pr-context-workspace base=\"%s\" roots=\"%zu\">", baseLabelEsc.c_str(), ws.size() );
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                rw::writePrContext( stdout, ws[r].arg, ing, g, masks[r].mask, baseLabel, masks[r].skippedModeOnly,
                                     rootBudget[r], r, ws[r].label, masks[r] );
            }
            std::printf( "</pr-context-workspace>" );
            return 0;
        }

        const rw::PrContextMask pcm = rw::gitDiffChangedMaskNumstat( root, ing, cfg.prContextBase );
        // P2.8: a base ref this repo does not contain is a REFUSAL, not a clean tree — it used to render
        // `<pr-context base="typo" files="0"/>` at exit 0, indistinguishable in CI from "nothing changed".
        // Kept ahead of the `!pcm.ok` degrade below, whose message would misname this failure.
        if( pcm.badRef )
        {
            std::fprintf( stderr, "ripwire: --pr-context: unknown base ref '%.*s'\n",
                          int( cfg.prContextBase.size() ), cfg.prContextBase.data() );
            return 1;
        }
        if( !pcm.ok )
        {
            // git unavailable / not a repo / bad ref: degrade to a single explanatory comment, exit 0. baseLabel
            // is the raw user-supplied --pr-context=REF, so it MUST be escaped before entering an XML attribute
            // (A4-F19b: a ref containing "/</& otherwise yields a non-well-formed document — the success path
            // escapes via writePrContext's ex(); this degrade path had forgotten to).
            std::vector<char>  prEsc;
            const std::string  baseLabelEsc = std::string( escapeXml( std::string_view( baseLabel ), prEsc ) );
            std::printf( "<!-- ripwire pr-context: not a git repository (or git unavailable / bad base ref) — nothing to bundle -->" );
            std::printf( "<pr-context base=\"%s\" files=\"0\"/>", baseLabelEsc.c_str() );
            return 0;
        }
        // R4 / lever 4: --max-tokens caps the (previously unbounded) bundle. 0 = no cap
        // → byte-identical to the pre-budget output; >0 → degrade DEPTH-first per file, structural counts kept
        // for ALL changed files, est_tokens/truncated= reported on the <pr-context> header (see writePrContext).
        return rw::writePrContext( stdout, root, ing, g, pcm.mask, baseLabel, pcm.skippedModeOnly,
                                    cfg.maxTokens > 0 ? std::size_t( cfg.maxTokens ) : 0,
                                    UINT32_MAX, std::string_view(), pcm );
    }

    // --export=cc.json[:FILE]: Wave-4 CodeCharta interchange export. Per-file metrics ripwire already
    // computes → the cc.json folder-tree a CodeCharta 3D city consumes. FILE or stdout, mirroring --html.
    if( cfg.exportCcJson )
    {
        std::vector<rw::CcFileMetrics> ccm = rw::ccComputeMetrics( ing, g );
        // churn: THE shared per-file pass (mineChurnPerFile — also --hotspots'/--ensemble's, and the
        // --html --color-by=churn lens below), multi-root §5 accumulation included. An empty `since`
        // leaves the scope inactive, so this is the default 18-month window: byte-identical to the
        // per-root loop this used to spell inline, and no longer a copy that can drift from the others.
        // 0 everywhere without git — clean degrade, churn simply omitted from the metrics below.
        std::vector<std::uint32_t> churn( ing.files.size(), 0 );
        const rw::SinceScope       ccScope;   // inactive: --export=cc.json has no --since form
        const bool ccChurnOk = mineChurnPerFile( ing, root, multiRoot, ws, std::string_view(), ccScope, "18 months ago", churn );
        if( ccChurnOk )
        {
            for( std::size_t f = 0; f < ccm.size() && f < churn.size(); ++f )
            {
                ccm[f].churn = churn[f];
            }
        }

        std::FILE* ccOut = stdout;
        if( !cfg.exportFile.empty() )
        {
            const std::string ccPath( cfg.exportFile );
            ccOut = std::fopen( ccPath.c_str(), "wb" );
            if( !ccOut )
            {
                DEGRADED_PATH_ALERT( "writeCcJson: could not open output file" );
                std::fprintf( stderr, "ripwire: --export=cc.json:%s: cannot open file for writing\n", ccPath.c_str() );
                return 1;
            }
        }
        rw::writeCcJson( ccOut, root, ing, ccm );
        if( ccOut != stdout )
        {
            std::fclose( ccOut );
        }
        return 0;
    }
    return std::nullopt;
}

// L2 — --from-trace helpers. tracein.h owns the pure frame extraction; the
// CORPUS resolution (a frame's path → indexed fileId, a frame's line → its enclosing symbol) and the whole
// bundle assembler now live in tracelocus.h (L4) as fromTraceBundleText() — shared verbatim with the MCP
// from_trace verb (mcpverbs.h's fromTraceText()). Only readTraceText (stdin/file reading — a CLI-only
// concern; the MCP verb takes the trace text as a request argument) stays here.

// read the --from-trace source into `text` — a FILE, or '-' for stdin (the --batch precedent). Returns false
// (after printing the reason) only when a NAMED file cannot be opened; '-' and an empty file are fine.
bool readTraceText( const std::string& src, std::string& text )
{
    if( src == "-" )
    {
        // R4: the same byte-safe reader the --mcp loop runs on. A stack trace / sanitizer report carries
        // non-ASCII routinely (a UTF-8 identifier, a quoted source line), and std::getline( std::cin, ... )
        // aborted the sanitizer build on the first such byte — see stdinline.h. Parity is exact.
        std::string l;
        while( rw::readByteSafeLine( stdin, l ) ) { text += l; text += '\n'; }
        return true;
    }
    std::FILE* f = std::fopen( src.c_str(), "rb" );
    if( !f ) { std::fprintf( stderr, "ripwire: --from-trace: cannot open '%s'\n", src.c_str() ); return false; }
    char buf[ 4096 ]; std::size_t n;
    while( ( n = std::fread( buf, 1, sizeof buf, f ) ) > 0 )
    {
        text.append( buf, n );
    }
    std::fclose( f );
    return true;
}

// L2 — --from-trace=FILE ('-'=stdin): trace-to-locus. Reads a stack trace /
// sanitizer report / compiler-error text and hands it to fromTraceBundleText() (tracelocus.h) — the ranked
// enclosing-symbol map, the suspects' signatures, and the innermost in-corpus symbol's full body. Composes
// with --token-budget. Unparseable input (zero frames) refuses loudly — never an empty map. Read-only,
// deterministic, no git.
std::optional<int> runFromTrace( const MainDispatch& d )
{
    using namespace rw;
    const Config&        cfg = d.cfg;
    const IngestResult&  ing = d.ing;
    const Graph&         g   = d.g;

    if( cfg.fromTrace.empty() )
    {
        return std::nullopt;
    }

    const std::string src( cfg.fromTrace );
    std::string       text;
    if( !readTraceText( src, text ) )
    {
        return 1;
    }

    FromTraceInputs in;
    in.bundleBudgetBytes = cfg.tokenBudget > 0
        ? std::size_t( double( cfg.tokenBudget ) * rw::kMinBytesPerToken * rw::kBudgetHeadroom )
        : rw::kForPayloadBudgetBytes;
    in.budgetTokens      = cfg.tokenBudget > 0 ? std::size_t( cfg.tokenBudget ) : 0;   // M11: budget_tokens= on the root
    in.sigLadderBudgetBytes = cfg.packBudgetBytes;
    in.bodyBudgetBytes      = cfg.maxTokens > 0
        ? std::size_t( double( cfg.maxTokens ) * rw::kMinBytesPerToken * rw::kBudgetHeadroom )
        : cfg.packBudgetBytes;
    in.compress = cfg.compress;
    in.fanIn    = d.fanInPtr;
    in.impure   = d.impurePtr;
    in.tested   = d.testedPtr;
    in.amp      = d.ampPtr;
    in.redact   = d.redactPtr;
    in.notes    = d.notesPtr;
    in.rootArg  = ( ing.realPaths.empty() && cfg.roots.size() == 1 ) ? std::string_view( cfg.roots[0] )
                                                                    : std::string_view();   // R-R

    const FromTraceResult res = fromTraceBundleText( ing, g, text, src == "-" ? "<stdin>" : src, in );
    if( !res.ok )
    {
        std::fprintf( stderr, "ripwire: --from-trace: no stack-trace / sanitizer / compiler frames found in '%s' — nothing to map\n",
                      src == "-" ? "<stdin>" : src.c_str() );
        return 1;
    }
    std::fwrite( res.xml.data(), 1, res.xml.size(), stdout );
    reportRedactions( stderr, d.redactCounts );
    return 0;
}

// ── VT-1 — --run-trace="CMD": the exec-mode entry of the --from-trace family ─────────────────────────────
// An agent's fix loop today is three steps: run the build/test via its own shell, read the (possibly huge)
// output, paste the error into --from-trace. This collapses it to ONE call: execute CMD, capture its output,
// and on failure serve the EXISTING from-trace bundle (fromTraceBundleText — reuse, never a second mapper)
// plus a token-frugal <lines> view of the trace-relevant output lines. Trust model: `sh -c` at user
// privileges with the inherited environment, exactly like make — no sandbox, and the legend says so.
// Determinism, honestly scoped: the <run> record (duration_ms) and the captured output are MEASURED; every
// byte derived FROM the captured text (the lines cut, the mapping) is a deterministic function of it.

inline constexpr std::uint32_t kRunTraceTimeoutSecDefault = 600;                 // the cap when --run-timeout is not given
inline constexpr std::size_t   kRunTraceHeadCapBytes      = 8u * 1024 * 1024;    // capture cap: first 8 MB kept …
inline constexpr std::size_t   kRunTraceTailCapBytes      = 24u * 1024 * 1024;   // … plus the last 24 MB; the dropped middle is COUNTED
inline constexpr std::size_t   kRunTraceRelevantLinesCap  = 40;                  // <lines view="relevant"> cap (first/last half split past it)
inline constexpr std::size_t   kRunTraceTailLines         = 10;                  // success record: the disclosed tail length
inline constexpr std::size_t   kRunTraceFallbackTailLines = 25;                  // failure with zero relevant lines: fall back to this tail
inline constexpr int           kRunTraceExitCommandFailed = 4;                   // ripwire's own exit when the COMMAND failed/timed out (report served)

// the error-line marks the relevant-lines cut recognizes beyond frame-shaped lines: compiler/linker primary
// diagnostics, test failures, sanitizer banners, shell spawn errors. Substring match over a fixed table —
// deterministic; the legend names the classes rather than restating the spellings.
inline constexpr std::string_view kRunTraceErrorMarks[] =
{
    "error", "Error", "ERROR", "fatal", "FAIL", "fail", "Assertion", "assert", "Traceback", "panic",
    "Segmentation fault", "not found", "No such file", "Exception", "Sanitizer", "SUMMARY:", "Abort", "abort",
    "undefined reference", "Undefined symbols",
};

// everything one command execution produced, capture caps applied. The exit facts are decoded, never
// re-derived downstream: isExitedNormally/exitCode vs termSignal vs isTimedOut are three different truths.
struct RunCapture
{
    bool          isSpawnFailed    = false;   // ripwire's own machinery (pipe/fork) failed — nothing was executed
    bool          isTimedOut       = false;   // the cap killed the process group
    bool          isExitedNormally = false;   // WIFEXITED — exitCode is meaningful
    int           exitCode         = -1;
    int           termSignal       = 0;       // WTERMSIG when the command died to a signal (incl. our SIGKILL)
    std::uint64_t durationMs       = 0;
    std::uint64_t totalBytes       = 0;       // bytes the command actually produced (pre-cap)
    std::uint64_t droppedBytes     = 0;       // middle bytes the head+tail cap dropped — disclosed, never silent
    std::string   head;                        // first kRunTraceHeadCapBytes
    std::string   tail;                        // overflow past the head cap, trimmed from the front to the tail cap
};

// append one read() chunk under the head+tail cap. The head fills once; overflow accumulates in the tail,
// which is trimmed from the FRONT so the newest bytes always survive (a build log's failure is at the end).
void runCaptureAppend( RunCapture& cap, const char* data, std::size_t byteCount )
{
    cap.totalBytes += byteCount;
    std::size_t take = 0;
    if( cap.head.size() < kRunTraceHeadCapBytes )
    {
        take = std::min( byteCount, kRunTraceHeadCapBytes - cap.head.size() );
        cap.head.append( data, take );
    }
    if( take < byteCount )
    {
        cap.tail.append( data + take, byteCount - take );
        if( cap.tail.size() > 2 * kRunTraceTailCapBytes )
        {
            cap.droppedBytes += cap.tail.size() - kRunTraceTailCapBytes;
            cap.tail.erase( 0, cap.tail.size() - kRunTraceTailCapBytes );
        }
    }
}

// the captured text, reassembled for classification + mapping. A drop splices head onto tail: one newline at
// the seam keeps two partial lines from fusing into a frankenline (the drop itself is dropped_bytes=).
std::string runCaptureText( RunCapture& cap )
{
    if( cap.tail.size() > kRunTraceTailCapBytes )
    {
        cap.droppedBytes += cap.tail.size() - kRunTraceTailCapBytes;
        cap.tail.erase( 0, cap.tail.size() - kRunTraceTailCapBytes );
    }
    if( cap.tail.empty() )
    {
        return cap.head;
    }
    std::string text = cap.head;
    if( cap.droppedBytes > 0 )
    {
        text += '\n';
    }
    text += cap.tail;
    return text;
}

// fork/exec `sh -c CMD` in its own process group, drain the pipe under a poll() deadline, SIGKILL the whole
// group at the cap, and decode the exit honestly. Zero new dependencies — POSIX only (G3/G5).
RunCapture runCommandCapture( const std::string& cmd, std::uint32_t timeoutSec )
{
    RunCapture cap;
    int fds[2];
    if( pipe( fds ) != 0 )
    {
        cap.isSpawnFailed = true;
        return cap;
    }

    const auto t0 = std::chrono::steady_clock::now();
    const auto elapsedMs = [ & ]() -> std::int64_t
    { return std::chrono::duration_cast<std::chrono::milliseconds>( std::chrono::steady_clock::now() - t0 ).count(); };

    const pid_t childPid = fork();
    if( childPid < 0 )
    {
        close( fds[0] );  close( fds[1] );
        cap.isSpawnFailed = true;
        return cap;
    }
    if( childPid == 0 )
    {
        // child: own process group (the timeout kills the whole tree), stdin from /dev/null (a command that
        // reads its terminal must not hang the report), both streams into ONE pipe (interleaved, as a
        // terminal would see them), then the shell. _exit(127) mirrors sh's own command-not-found code.
        setpgid( 0, 0 );
        const int devNull = open( "/dev/null", O_RDONLY );
        if( devNull >= 0 ) { dup2( devNull, STDIN_FILENO );  close( devNull ); }
        dup2( fds[1], STDOUT_FILENO );  dup2( fds[1], STDERR_FILENO );
        close( fds[0] );  close( fds[1] );
        execl( "/bin/sh", "sh", "-c", cmd.c_str(), static_cast<char*>( nullptr ) );
        _exit( 127 );
    }

    setpgid( childPid, childPid );   // parent side of the same race — both settings agree, whichever runs first
    close( fds[1] );

    // ── drain the pipe under the deadline; after a kill, keep draining briefly (an orphaned grandchild may
    //    still hold the write side open — stop at the drain deadline rather than hanging on its EOF) ───────
    const std::int64_t timeoutMs     = std::int64_t( timeoutSec ) * 1000;
    const std::int64_t drainWindowMs = 2000;
    std::int64_t       drainDeadlineMs = 0;
    char               buf[ 65536 ];
    for( ;; )
    {
        const std::int64_t nowMs = elapsedMs();
        if( !cap.isTimedOut && nowMs >= timeoutMs )
        {
            cap.isTimedOut  = true;
            drainDeadlineMs = nowMs + drainWindowMs;
            kill( -childPid, SIGKILL );
            kill( childPid, SIGKILL );
        }
        if( cap.isTimedOut && elapsedMs() >= drainDeadlineMs )
        {
            break;
        }
        const std::int64_t untilMs = ( cap.isTimedOut ? drainDeadlineMs : timeoutMs ) - elapsedMs();
        struct pollfd pfd { fds[0], POLLIN, 0 };
        const int ready = poll( &pfd, 1, int( std::clamp<std::int64_t>( untilMs, 0, 1000 ) ) );
        if( ready > 0 )
        {
            const ssize_t n = read( fds[0], buf, sizeof buf );
            if( n <= 0 ) { break; }                       // EOF: every writer closed the pipe
            runCaptureAppend( cap, buf, std::size_t( n ) );
        }
        else if( ready < 0 && errno != EINTR )
        {
            break;
        }
    }
    close( fds[0] );

    // ── harvest the exit status, still under the cap: EOF can precede exit (a command that closed its own
    //    stdout/stderr and kept running), so the wait polls the SAME deadline instead of blocking past it ──
    int status = 0;
    for( ;; )
    {
        const pid_t waited = waitpid( childPid, &status, cap.isTimedOut ? 0 : WNOHANG );
        if( waited == childPid || waited < 0 )
        {
            break;
        }
        if( elapsedMs() >= timeoutMs )
        {
            cap.isTimedOut = true;
            kill( -childPid, SIGKILL );
            kill( childPid, SIGKILL );
            continue;                                      // next iteration blocks: the group is dead
        }
        poll( nullptr, 0, 20 );
    }
    cap.durationMs = std::uint64_t( elapsedMs() );
    if( WIFEXITED( status ) )
    {
        cap.isExitedNormally = true;
        cap.exitCode         = WEXITSTATUS( status );
    }
    else if( WIFSIGNALED( status ) )
    {
        cap.termSignal = WTERMSIG( status );
    }
    return cap;
}

// split the captured text into its NON-EMPTY lines (views into `text`) — wsdetail::segmentsOf is the shared
// split primitive (workspace.h), reused rather than re-rolled. Blank lines carry no signal for either the
// relevant cut or the tail, so lines= counts non-empty captured lines (the legend says so).
std::vector<std::string_view> runTraceSplitLines( std::string_view text )
{
    return rw::wsdetail::segmentsOf( text, '\n' );
}

// is this output line trace-relevant? An error mark (fixed table) or a frame-shaped line (the SAME per-line
// extractor the mapper runs, so "frames that mapped" and "lines shown" can never disagree about shape).
bool isRunTraceRelevantLine( std::string_view line )
{
    const bool hasErrorMark = std::any_of( std::begin( kRunTraceErrorMarks ), std::end( kRunTraceErrorMarks ),
                                           [ line ]( std::string_view mark ) { return line.find( mark ) != std::string_view::npos; } );
    return hasErrorMark || rw::tracein::extractFrames( line ).frameShapedLines > 0;
}

// the <lines> element: view="relevant" on failure (error-marked / frame-shaped lines, first+last halves kept
// past the cap, the omitted middle disclosed INLINE), view="tail" on success or when nothing classified.
// Empty capture ⇒ empty string (the <run> record's lines="0" already says why).
std::string renderRunTraceLines( const std::vector<std::string_view>& lines, bool isFailure )
{
    std::vector<std::size_t> picked;
    bool isRelevantView = false;
    bool isCapped       = false;
    std::size_t relevantCount = 0;

    if( isFailure )
    {
        std::vector<std::size_t> relevant;
        for( std::size_t i = 0; i < lines.size(); ++i )
        {
            if( isRunTraceRelevantLine( lines[i] ) )
            {
                relevant.push_back( i );
            }
        }
        relevantCount = relevant.size();
        if( !relevant.empty() )
        {
            isRelevantView = true;
            if( relevant.size() <= kRunTraceRelevantLinesCap )
            {
                picked = relevant;
            }
            else
            {
                isCapped = true;
                const std::size_t half = kRunTraceRelevantLinesCap / 2;
                picked.assign( relevant.begin(), relevant.begin() + std::ptrdiff_t( half ) );
                picked.insert( picked.end(), relevant.end() - std::ptrdiff_t( half ), relevant.end() );
            }
        }
    }
    if( !isRelevantView )
    {
        const std::size_t tailLines = isFailure ? kRunTraceFallbackTailLines : kRunTraceTailLines;
        const std::size_t begin     = lines.size() > tailLines ? lines.size() - tailLines : 0;
        for( std::size_t i = begin; i < lines.size(); ++i )
        {
            picked.push_back( i );
        }
    }
    if( picked.empty() )
    {
        return {};
    }

    std::string cdata;
    const std::size_t halfCount = kRunTraceRelevantLinesCap / 2;
    for( std::size_t k = 0; k < picked.size(); ++k )
    {
        if( k > 0 )
        {
            cdata += '\n';
        }
        if( isCapped && k == halfCount )
        {
            cdata += "[... ";
            cdata += std::to_string( relevantCount - kRunTraceRelevantLinesCap );
            cdata += " relevant lines omitted (middle) ...]\n";
        }
        rw::appendCdataSafe( lines[ picked[k] ], cdata );
    }

    std::string out = "<lines view=\"";
    out += isRelevantView ? "relevant" : "tail";
    out += "\" shown=\"";  out += std::to_string( picked.size() );
    if( isFailure )
    {
        out += "\" relevant=\"";  out += std::to_string( relevantCount );
    }
    out += "\" total=\"";  out += std::to_string( lines.size() );
    out += "\"";
    if( isCapped )
    {
        out += " capped=\"1\"";
    }
    out += "><![CDATA[";  out += cdata;  out += "]]></lines>";
    return out;
}

// the <run> record — the command's exit ALWAYS disclosed: exit= when it exited, signal= when a signal killed
// it, timed_out="1" when that signal was the cap's. framesFound carries the frameless-failure disclosure.
std::string renderRunTraceRecord( const RunCapture& cap, std::uint32_t timeoutSec, std::size_t lineCount, bool isFrameless )
{
    std::string r = "<run";
    if( cap.isTimedOut )
    {
        r += " timed_out=\"1\"";
    }
    if( cap.isExitedNormally )
    {
        r += " exit=\"";  r += std::to_string( cap.exitCode );  r += "\"";
    }
    else if( cap.termSignal != 0 )
    {
        r += " signal=\"";  r += std::to_string( cap.termSignal );  r += "\"";
    }
    r += " duration_ms=\"";  r += std::to_string( cap.durationMs );
    r += "\" timeout_s=\"";  r += std::to_string( timeoutSec );
    r += "\" lines=\"";      r += std::to_string( lineCount );
    r += "\" bytes=\"";      r += std::to_string( cap.totalBytes );
    r += "\"";
    if( cap.droppedBytes > 0 )
    {
        r += " dropped_bytes=\"";  r += std::to_string( cap.droppedBytes );  r += "\"";
    }
    if( isFrameless )
    {
        r += " frames=\"0\"";
    }
    r += "/>";
    return r;
}

// which of the three run-trace documents is this comment for? The legend body is shared; only the closing
// sentence differs, and each states its own truth plainly.
enum class RunTraceDocKind : std::uint8_t { Success, FramelessFailure, Bundle };

// the run-trace legend comment. NOTE the double-dash rule: an XML comment may not contain "--", so flag
// names appear single-dashed here and the command echo goes through xmlCommentText (the srcNote precedent).
std::string runTraceLegendComment( std::string_view cmd, RunTraceDocKind kind )
{
    std::string c = "<!-- ripwire run-trace: executed \"";
    c += rw::xmlCommentText( cmd );
    c += "\" under sh -c (the make trust model: your user, inherited environment, stdin=/dev/null, NO sandbox), "
         "stdout+stderr captured interleaved. On <run>: exit= the command's OWN exit code; signal= the signal that "
         "killed it; timed_out=\"1\" = the timeout_s= cap killed the whole process group (an honest TIMEOUT, never an "
         "empty success); duration_ms= wall clock; lines= the capture's non-empty line count; bytes= the whole "
         "capture; dropped_bytes= middle bytes the capture cap dropped (head+tail kept). duration_ms and the "
         "captured output are MEASURED, not deterministic "
         "(and not claimed to be); every byte derived FROM the captured text - the <lines> cut and any mapping - is a "
         "deterministic function of it. <lines view=\"tail\"> = the last shown= of total= output lines; "
         "view=\"relevant\" = shown= of the relevant= error-marked / frame-shaped lines out of total= (capped=\"1\" = "
         "first+last halves kept, the omitted middle disclosed inline). ";
    switch( kind )
    {
        case RunTraceDocKind::Success:
            c += "The command exited 0: nothing failed, so there is NOTHING TO MAP - no trace bundle is served for a "
                 "passing command.";
            break;
        case RunTraceDocKind::FramelessFailure:
            c += "The command FAILED but the captured output carried no stack-trace / sanitizer / compiler frames "
                 "(frames=\"0\" on <run>): nothing to map onto the corpus - the run record and lines here are the whole "
                 "answer.";
            break;
        case RunTraceDocKind::Bundle:
            c += "The command FAILED and the captured text carried mappable frames: the <trace>/<sigs>/<bodies> bundle "
                 "below is the byte-deterministic from-trace mapping of that text (its own legend precedes it above).";
            break;
    }
    c += " -->";
    return c;
}

// VT-1 — --run-trace="CMD": execute, capture, and on failure map. One call, one document, the whole
// fix-loop entry. Exit: 0 = the command succeeded; kRunTraceExitCommandFailed (4) = it failed or timed out
// (the report is on stdout either way); 1 = ripwire's own spawn machinery failed.
std::optional<int> runRunTrace( const MainDispatch& d )
{
    using namespace rw;
    const Config& cfg = d.cfg;
    if( cfg.runTrace.empty() )
    {
        return std::nullopt;
    }

    const std::string   cmd( cfg.runTrace );
    const std::uint32_t timeoutSec = cfg.runTimeoutSec > 0 ? std::uint32_t( cfg.runTimeoutSec ) : kRunTraceTimeoutSecDefault;

    RunCapture cap = runCommandCapture( cmd, timeoutSec );
    if( cap.isSpawnFailed )
    {
        std::fprintf( stderr, "ripwire: --run-trace: cannot spawn '/bin/sh -c' (pipe/fork failed) — nothing was executed\n" );
        return 1;
    }
    if( cap.isTimedOut )
    {
        std::fprintf( stderr, "ripwire: --run-trace: TIMEOUT — the command exceeded the %u s cap; its process group was killed\n", timeoutSec );
    }

    const std::string                   text    = runCaptureText( cap );
    const std::vector<std::string_view> lines   = runTraceSplitLines( text );
    const bool isSuccess = !cap.isTimedOut && cap.isExitedNormally && cap.exitCode == 0;
    const std::string label = "run-trace: " + cmd;

    // ── exit 0: the minimal success record — no bundle, and the legend says plainly why ─────────────────
    if( isSuccess )
    {
        std::string doc = ctxRootOpen( label, {} );
        doc += runTraceLegendComment( cmd, RunTraceDocKind::Success );
        doc += renderRunTraceRecord( cap, timeoutSec, lines.size(), /*isFrameless=*/false );
        doc += renderRunTraceLines( lines, /*isFailure=*/false );
        doc += "</ctx>";
        std::fwrite( doc.data(), 1, doc.size(), stdout );
        return 0;
    }

    // ── failure: the run record + relevant-lines cut ride INSIDE the from-trace bundle as its prelude, so
    //    the whole answer is ONE document under ONE budget ledger ─────────────────────────────────────────
    const std::string linesBlock = renderRunTraceLines( lines, /*isFailure=*/true );

    FromTraceInputs in;
    in.bundleBudgetBytes = cfg.tokenBudget > 0
        ? std::size_t( double( cfg.tokenBudget ) * rw::kMinBytesPerToken * rw::kBudgetHeadroom )
        : rw::kForPayloadBudgetBytes;
    in.budgetTokens      = cfg.tokenBudget > 0 ? std::size_t( cfg.tokenBudget ) : 0;   // M11: budget_tokens= on the root
    in.sigLadderBudgetBytes = cfg.packBudgetBytes;
    in.bodyBudgetBytes      = cfg.packBudgetBytes;
    in.compress = cfg.compress;
    in.fanIn    = d.fanInPtr;
    in.impure   = d.impurePtr;
    in.tested   = d.testedPtr;
    in.amp      = d.ampPtr;
    in.redact   = d.redactPtr;
    in.notes    = d.notesPtr;
    in.rootArg  = ( d.ing.realPaths.empty() && cfg.roots.size() == 1 ) ? std::string_view( cfg.roots[0] )
                                                                      : std::string_view();   // R-R

    std::string prelude = runTraceLegendComment( cmd, RunTraceDocKind::Bundle );
    prelude += renderRunTraceRecord( cap, timeoutSec, lines.size(), /*isFrameless=*/false );
    prelude += linesBlock;
    in.preludeXml = prelude;

    const FromTraceResult res = fromTraceBundleText( d.ing, d.g, text, label, in );
    if( res.ok )
    {
        std::fwrite( res.xml.data(), 1, res.xml.size(), stdout );
        reportRedactions( stderr, d.redactCounts );
        return kRunTraceExitCommandFailed;
    }

    // ── failure with NO mappable frames: still a full report — never a refusal, never a silent success ──
    std::string doc = ctxRootOpen( label, {} );
    doc += runTraceLegendComment( cmd, RunTraceDocKind::FramelessFailure );
    doc += renderRunTraceRecord( cap, timeoutSec, lines.size(), /*isFrameless=*/true );
    doc += linesBlock;
    doc += "</ctx>";
    std::fwrite( doc.data(), 1, doc.size(), stdout );
    return kRunTraceExitCommandFailed;
}



// L1 — --merge-scout=REF[,REF...]: the read-only cross-branch overlap
// oracle. mergescout.h owns the computation (materialize-and-diff, pairwise conflicts/risks, greedy
// landing order); this handler just resolves the flag, refuses loudly on a bad REF, and writes the XML.
// The multi-root refusal for --merge-scout lives with its siblings (--quality-delta/--test-gate/etc.)
// earlier in main(), before the single-root ingest pipeline runs — this handler never sees roots.size()>=2.
std::optional<int> runMergeScout( const MainDispatch& d )
{
    using namespace rw;
    const Config&        cfg = d.cfg;
    const IngestResult&  ing = d.ing;
    const std::string&   root = d.root;

    if( cfg.mergeScoutFlag )
    {
        if( cfg.mergeScout.empty() )
        {
            std::fprintf( stderr, "ripwire: --merge-scout needs REF[,REF...] (e.g. --merge-scout=branchA,branchB)\n" );
            return 1;
        }
        const mergescout::ScoutResult result = mergescout::computeMergeScout( root, cfg.mergeScout, ing, cfg.excludes, cfg.maxFileBytes );
        if( !result.ok )
        {
            // X9(a): a non-git root gets its OWN message — there is no offending ref to name, and "unknown
            // ref ''" would be a confusing refusal for a completely different reason (no git history at all).
            if( result.nonGitRoot )
            {
                std::fprintf( stderr, "ripwire: --merge-scout: %s is not a git repository (or has no HEAD commit) — nothing to scout\n", root.c_str() );
            }
            else
            {
                std::fprintf( stderr, "ripwire: --merge-scout: unknown ref '%s'\n", result.badRef.c_str() );
            }
            return 1;
        }
        mergescout::writeMergeScout( stdout, result );
        return 0;
    }
    return std::nullopt;
}

// ── --plan-lanes ──────────────────────────────────────────────────────────────────────────────────────────
// lanes.h owns the whole computation — the claim key, the synthetic-arm composition onto merge-scout's own
// conflict machinery, the three pair classes, the landing order, the JSON emitter. This handler resolves the
// flags, refuses loudly (writing NOTHING to stdout — a refusal must not ship a payload), and supplies the two
// inputs lanes.h is deliberately not allowed to compute for itself: the lens RANKING (computeLensRanking is
// THE ranking implementation, per the "do not reimplement ranking" mandate) and the per-file churn lens.

// One non-blank line per lane — the whole --brief format in v1 (anything richer is a v2 question, driven by
// real orchestration friction rather than designed up front). `ok=false` ⇒ the path could not be opened.
struct BriefFile { std::vector<std::string> lines; bool ok = false; };

BriefFile readBriefFile( const std::string& path )
{
    BriefFile  out;
    std::FILE* fp = std::fopen( path.c_str(), "rb" );
    if( !fp )
    {
        return out; // caller refuses loudly, naming the path
    }
    out.ok = true;

    char buf[ 4096 ];
    while( std::fgets( buf, sizeof( buf ), fp ) )
    {
        std::string line( buf );
        while( !line.empty() && ( line.back() == '\n' || line.back() == '\r' ) )
        {
            line.pop_back();
        }
        const std::size_t first = line.find_first_not_of( " \t" );
        if( first == std::string::npos )
        {
            continue; // blank (or whitespace-only) → not a lane
        }
        out.lines.push_back( line.substr( first, line.find_last_not_of( " \t" ) - first + 1 ) );
    }
    std::fclose( fp );
    return out;
}

// The corpus header's own five numbers, read from the SAME places serialize.h's `<!-- files= symbols= edges=
// ambiguous= unresolved= -->` preamble reads them, so a plan and the map it describes can never disagree.
rw::lanes::CorpusStats laneCorpusStats( const rw::IngestResult& ing, const rw::Graph& g )
{
    rw::lanes::CorpusStats c;
    c.files   = ing.files.size();
    c.symbols = ing.symbols.size();
    c.edges   = g.outTargets.size();
    for( std::uint32_t v : g.ambOut )
    {
        c.ambiguous += v;
    }
    for( std::uint32_t v : g.unresolvedOut )
    {
        c.unresolved += v;
    }
    return c;
}

std::optional<int> runPlanLanes( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg  = d.cfg;
    const IngestResult& ing  = d.ing;
    const Graph&        g    = d.g;
    const std::string&  root = d.root;

    if( !cfg.planLanesFlag )
    {
        return std::nullopt;
    }

    // cli.h has already enforced task-XOR-brief and the 2..16 range on the auto-carve form. What is left to
    // refuse here is what only the tree can answer: an unreadable brief, a brief whose lane count is out of
    // range, and an empty corpus (nothing to carve, and a plan over nothing would read as a clean answer).
    lanes::LanesInputs in;
    in.ing   = &ing;
    in.g     = &g;
    in.root  = &root;
    in.notes = d.notesPtr;

    BriefFile brief;
    if( !cfg.laneBrief.empty() )
    {
        const std::string briefPath( cfg.laneBrief );
        brief = readBriefFile( briefPath );
        if( !brief.ok )
        {
            std::fprintf( stderr, "ripwire: --plan-lanes: cannot read --brief=%s\n", briefPath.c_str() );
            return 1;
        }
        if( brief.lines.size() < lanes::kMinLanes || brief.lines.size() > lanes::kMaxLanes )
        {
            std::fprintf( stderr, "ripwire: --plan-lanes --brief=%s has %zu non-blank line(s) — one line per lane, and the lane "
                                  "count must be %u..%u (1 is not a fan-out)\n",
                          briefPath.c_str(), brief.lines.size(), lanes::kMinLanes, lanes::kMaxLanes );
            return 1;
        }
        in.autoCarve = false;
        in.laneTasks = brief.lines;
        in.requested = std::uint32_t( brief.lines.size() );
    }
    else
    {
        in.autoCarve = true;
        in.task      = std::string( cfg.laneTask );
        in.requested = std::uint32_t( cfg.planLaneCount );
    }

    if( ing.symbols.empty() )
    {
        std::fprintf( stderr, "ripwire: --plan-lanes: no indexed symbols under %s — there is nothing to split into lanes\n", root.c_str() );
        return 1;
    }

    // the rankings — ONE per lane in brief mode, one for the whole task in auto-carve. Same computeLensRanking
    // --for and --pack-task use, so every routing/mention/doc-mention behaviour applies identically here.
    LensRanking                     carveRanking;
    std::vector<std::vector<float>> laneRanks;
    if( in.autoCarve )
    {
        carveRanking  = computeLensRanking( d, in.task );
        in.carveRank  = &carveRanking.rank;
    }
    else
    {
        laneRanks.reserve( in.laneTasks.size() );
        for( const std::string& laneTask : in.laneTasks )
        {
            laneRanks.push_back( computeLensRanking( d, laneTask ).rank );
        }
        in.laneRanks = &laneRanks;
    }

    // the churn axis of claims.files' hotspot data — the SAME `git log --name-only` window --hotspots ranks on.
    // A non-git root simply leaves it zero (every hotspot_rank then emits null, never a fabricated rank).
    std::vector<std::uint32_t> churn( ing.files.size(), 0u );
    if( !gitChurnCounts( root, ing, churn, "12 months ago" ) )
    {
        DEGRADED_PATH_ALERT( "plan-lanes: no git churn history for this root — claims.files churn/hotspot_rank report 0/null" );
    }
    in.churn  = &churn;
    in.tested = d.testedPtr;
    in.corpus = laneCorpusStats( ing, g );

    lanes::writePlanLanes( stdout, lanes::computePlanLanes( in ) );
    return 0;
}

// --with-history (src/gitoracle.h): build the name-history index for a verb that wants it, or an empty one
// when the flag is absent. ONE body for both consumers below — they had grown the same four lines each,
// including the same stderr note, which is exactly the clone this repo's own --quality-delta flags. The
// caller OWNS the returned index and must outlive every view of it (both handlers keep it on the stack for
// the whole compute-then-write sequence). `verbNote` names what degrades, so the message stays specific.
rw::gitoracle::HistoryIndex buildHistoryIndex( const rw::Config& cfg, const std::string& root, const char* verbNote )
{
    if( !cfg.withHistory )
    {
        return {};
    }

    rw::gitoracle::HistoryIndex idx = rw::gitoracle::probeNameHistory( root );
    if( idx.nonGitRoot )
    {
        std::fprintf( stderr, "ripwire: --with-history: %s has no git history — %s\n", root.c_str(), verbNote );
    }
    return idx;
}

// `--flags --flip=NAME` — one gate's flip blast radius. Its own handler (not a branch inside runCrossRef)
// because unlike every other verb in that group it is INDEX-backed on both sides: it joins the lexical gate
// harvest to the call graph, so it consumes d.ing AND d.g. cli.h already refused a bare --flip and a --flip
// without --flags; what is left to refuse here is a name that is not a gate in THIS tree — loudly, with the
// near-misses the compute pass found, never an empty-looking success.
int runFlip( const MainDispatch& d )
{
    using namespace rw;
    const std::string& root = d.root;

    // Single-root only, and REFUSED rather than answered wrong: the gate harvest reads each ingested file by
    // its ing.files spelling, which in a merged workspace is the LABELED identity path, not a path on disk —
    // so a multi-root run harvests zero gates. Plain --flags returns an empty-looking `gates="0"` there
    // (a pre-existing gap in that verb); --flip must not turn the same gap into "no gate named X".
    if( d.multiRoot )
    {
        std::fprintf( stderr, "ripwire: --flip is single-root only (the gate harvest reads on-disk paths, which a merged "
                              "workspace relabels) — run it once per root\n" );
        return 1;
    }

    const flipimpact::FlipResult result = flipimpact::computeFlip( d.ing, d.g, root, d.cfg.excludes, d.cfg.flipGate );
    if( !result.ok )
    {
        std::string msg = "ripwire: --flip: no gate named '" + std::string( d.cfg.flipGate ) + "' in " + root;
        if( !result.nearMisses.empty() )
        {
            msg += " (did you mean";
            for( std::size_t i = 0; i < result.nearMisses.size(); ++i )
            {
                msg += ( i ? ", '" : " '" ) + result.nearMisses[i] + "'";
            }
            msg += "?)";
        }
        std::fprintf( stderr, "%s\n", msg.c_str() );
        std::fprintf( stderr, "ripwire: run `ripwire %s --flags` for the gate table\n", root.c_str() );
        return 1;
    }
    flipimpact::writeFlip( stdout, result, d.ing, root, d.cfg.detail ? SIZE_MAX : flipimpact::kMaxFlipRows );
    return 0;
}

// `--stray-content --abi` — the cross-branch ABI-BREAK gate (abicheck.h). Its own handler (not inlined into
// runCrossRef) because unlike --stray-content/--whereis it IS index-backed on the HEAD side: it needs
// d.ing to enumerate which structs HEAD declares and to model their working-tree fields, the same baseline
// --layout itself reads. cli.h already refused a bare --abi (without --stray-content); what is left to
// refuse here is the ref-namespace/root shape --stray-content already refuses for the same reason.
int runAbiCheck( const MainDispatch& d )
{
    using namespace rw;
    const std::string& root = d.root;

    const abicheck::AbiResult result = abicheck::computeAbiCheck( root, d.ing, d.cfg.strayFilter );
    if( !result.ok )
    {
        if( result.nonGitRoot )
        {
            std::fprintf( stderr, "ripwire: --abi: %s is not a git repository (or has no HEAD commit) — no refs to compare\n", root.c_str() );
        }
        else
        {
            std::fprintf( stderr, "ripwire: --abi: more than %u refs match — narrow it with --stray-content=SUBSTR\n", crossref::kMaxRefs );
        }
        return 1;
    }
    // --detail=N is this verb's ONE "show me everything" lever: it lifts the per-ref display cap AND prints
    // the kinds the default triage counts but does not list (rename/spelling/stub/head-moved).
    const bool listAll = d.cfg.detail != 0;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — --abi
    // is single-root by construction (cli.h already refuses the multi-root shape upstream).
    const std::string_view abiRootArg = d.ing.realPaths.empty() ? std::string_view( root ) : std::string_view();
    abicheck::writeAbiCheck( stdout, result, listAll ? SIZE_MAX : abicheck::kMaxStructsPerRef, listAll, abiRootArg );
    return abicheck::abiContractBroken( result ) ? 2 : 0;   // exit 2 = a real byte-contract drift on some branch
}

// The CROSS-BRANCH content verbs: --stray-content and --whereis. Both are
// git-driven rather than index-driven — they read OTHER refs' blobs, which this process never ingested — so
// neither consumes `d.ing`/`d.g`; they take only the root. Both are single-root by the same reasoning
// --merge-scout is: "which branch has this" is a question about ONE repository's ref graph, and a merged
// multi-root graph has no single ref namespace to answer it in. The one exception is `--stray-content --plan`
// just below: it composes the sweep with --merge-scout, which DOES need `d.ing` (the working tree's own
// already-ingested IngestResult, for merge-scout's implicit dirty-working-tree arm) — same reasoning
// runMergeScout itself uses.
// §A7: every place the parsed index defines `name`, keyed the way git spells a tree entry (arch.h::relForHash
// — the SAME root-relative join --abi uses to match ing.files against git paths). This is what lets --whereis
// stop GUESSING on HEAD rows: the tree scan reads committed blobs, the index knows where the definitions are,
// and the join is a single pass over the symbol table with no extra I/O.
inline std::vector<rw::crossref::IndexDefSite> whereisIndexDefSites( const rw::IngestResult& ing, std::string_view name, const std::string& root )
{
    std::vector<rw::crossref::IndexDefSite> sites;
    for( const rw::Symbol& s : ing.symbols )
    {
        if( s.name == name )
        {
            sites.push_back( rw::crossref::IndexDefSite{ std::string( rw::relForHash( ing.files[ s.fileId ], root ) ), s.line } );
        }
    }
    return sites;
}

std::optional<int> runCrossRef( const MainDispatch& d )
{
    using namespace rw;
    const Config&      cfg  = d.cfg;
    const std::string& root = d.root;

    if( cfg.strayContent && cfg.landingPlan )
    {
        if( d.multiRoot )
        {
            std::fprintf( stderr, "ripwire: --plan is single-root only (one repo = one ref namespace) — run it per root\n" );
            return 1;
        }
        const landingplan::PlanResult result = landingplan::computePlan( root, cfg.strayFilter, d.ing, cfg.excludes, cfg.maxFileBytes,
                                                                          cfg.detail ? SIZE_MAX : landingplan::kMaxPlanScout );
        if( !result.ok )
        {
            if( result.nonGitRoot )
            {
                std::fprintf( stderr, "ripwire: --plan: %s is not a git repository (or has no HEAD commit) — no refs to compare\n", root.c_str() );
            }
            else
            {
                std::fprintf( stderr, "ripwire: --plan: more than %u refs match — narrow it with --stray-content=SUBSTR\n", crossref::kMaxRefs );
            }
            return 1;
        }
        landingplan::writePlan( stdout, result );
        return 0;
    }

    if( cfg.strayContent )
    {
        if( d.multiRoot )
        {
            std::fprintf( stderr, "ripwire: --stray-content is single-root only (one repo = one ref namespace) — run it per root\n" );
            return 1;
        }
        if( cfg.abiFlag )
        {
            return runAbiCheck( d ); // --stray-content --abi: the cross-branch ABI-break gate
        }
        const crossref::StrayResult result = crossref::computeStrayContent( root, cfg.strayFilter );
        if( !result.ok )
        {
            if( result.nonGitRoot )
            {
                std::fprintf( stderr, "ripwire: --stray-content: %s is not a git repository (or has no HEAD commit) — no refs to compare\n", root.c_str() );
            }
            else if( result.filterMatchedNothing )
            {
                // H7: refs="0" unknown="0" at exit 0 is the most reassuring answer this verb can give — "no
                // branch carries stray work" — from a sweep that matched no branch NAME at all.
                std::fprintf( stderr, "ripwire: --stray-content=%.*s matches no local ref — a zero here would be a failure, not a "
                                      "measurement\n  (the filter is a substring match against refs/heads names; run bare "
                                      "--stray-content to list them, e.g. --stray-content=feat/)\n",
                              int( cfg.strayFilter.size() ), cfg.strayFilter.data() );
            }
            else
            {
                std::fprintf( stderr, "ripwire: --stray-content: more than %u refs match — narrow it with --stray-content=SUBSTR\n", crossref::kMaxRefs );
            }
            return 1;
        }
        // §P15/§P16: real paging over the outer, deterministically-sorted refs listing (see crossref.h's
        // writeStrayContentPage) — confirmed byte-stable across repeated runs on this repo before migrating.
        crossref::writeStrayContentPage( stdout, result, cfg.detail ? SIZE_MAX : crossref::kStrayFilesPerRef,
                                         cfg.pageLimit, cfg.pageOffset );
        return 0;
    }

    if( !cfg.evalStray.empty() )
    {
        const crossref::EvalReport rep = crossref::evalStray( root, std::string( cfg.evalStray ) );
        if( !rep.ok )
        {
            if( !rep.badRefs.empty() )
            {
                // H13: the file read fine and this IS a git repo — the refusal is that one or more
                // labelled refs do not exist here at all, so "absent = merged" cannot honestly apply to
                // them (that default is only for a ref this repo genuinely scanned and found merged).
                std::string names;
                for( const std::string& r : rep.badRefs )
                {
                    if( !names.empty() ) { names += ", "; }
                    names += r;
                }
                std::fprintf( stderr, "ripwire: --eval-stray: %zu labelled ref(s) do not exist in %s -- not merged, just "
                                      "absent: %s (fix the labels file or add the ref)\n",
                              rep.badRefs.size(), root.c_str(), names.c_str() );
                return 1;
            }
            std::fprintf( stderr, "ripwire: --eval-stray: cannot read '%.*s', or %s is not a git repository\n",
                          int( cfg.evalStray.size() ), cfg.evalStray.data(), root.c_str() );
            return 1;
        }
        crossref::writeStrayEval( stdout, rep );
        return ( rep.correct == rep.cases.size() ) ? 0 : 3;   // exit 3 = some labelled case regressed
    }

    if( cfg.darkFlags )
    {
        if( cfg.flipFlag )
        {
            return runFlip( d ); // --flags --flip=NAME: one gate's radius
        }
        const darkflags::FlagsResult result = darkflags::computeFlags( d.ing, root, cfg.excludes, cfg.darkFlagsFilter );
        // H7: a NAME filter that owns no declared gate refuses, in the wording --doc-drift/--dead-code set —
        // `gates="0" dark_gates="0" files="1550"` reads as "this repo has no dark gates", and the scan
        // denominator beside it makes the false zero look measured.
        if( result.filterMatchedNothing )
        {
            std::fprintf( stderr, "ripwire: --flags=%.*s matches no declared gate — a zero here would be a failure, not a "
                                  "measurement\n  (the filter is a substring match against GATE NAMES; run bare --flags to "
                                  "list them, e.g. --flags=RIPWIRE)\n",
                          int( cfg.darkFlagsFilter.size() ), cfg.darkFlagsFilter.data() );
            return 1;
        }
        darkflags::writeFlags( stdout, result, cfg.detail ? SIZE_MAX : darkflags::kMaxSitesShown );
        return 0;
    }

    if( cfg.whereisFlag )
    {
        if( cfg.whereis.empty() )
        {
            std::fprintf( stderr, "ripwire: --whereis needs a symbol (e.g. --whereis=adoptValidatedLowBandContours)\n" );
            return 1;
        }
        if( d.multiRoot )
        {
            std::fprintf( stderr, "ripwire: --whereis is single-root only (one repo = one ref namespace) — run it per root\n" );
            return 1;
        }
        // H7 / lens 6 F5: the documented @FILE:LINE seed grammar is RESOLVED here, before anything is
        // scanned. It used to fall through as a literal string — `--whereis=@src/graph.h:999999` grepped
        // "@src/graph.h:999999" across 4,617 blobs and reported a true, useless hits="0" shaped exactly like
        // a name this repo never had, while --owners/--mentions/--edit-check resolve the same spelling and
        // refuse a bad line with the shared seed message. resolveAllByNameQualified is that resolver, and
        // selectorNotFoundMessage speaks its per-fault diagnosis, so neither is a second opinion.
        std::string whereisSel( cfg.whereis );
        std::string whereisSeed;
        if( whereisSel.front() == '@' )
        {
            const std::vector<NodeId> seeded = resolveAllByNameQualified( d.ing, whereisSel );
            if( seeded.empty() )
            {
                std::fprintf( stderr, "%s\n", selectorNotFoundMessage( d.ing, "ripwire: --whereis: ", cfg.whereis, "--whereis=" ).c_str() );
                return 1;
            }
            whereisSeed = whereisSel;
            whereisSel  = d.ing.symbols[ seeded.front() ].name;
        }

        // --with-history: ONE git-history walk (memoized per repo+HEAD sha), giving --whereis the lane a tree
        // scan structurally cannot have — whether HEAD's history ever REMOVED this name. Owned here, in the
        // handler, so the index outlives both the compute and the write that hold non-owning views of it.
        const gitoracle::HistoryIndex history = buildHistoryIndex( cfg, root, "the fate lane reports probed=\"0\"" );

        // §A7: HEAD's rows are documented as the PARSED answer, so hand the tree scan what the index knows.
        const std::vector<crossref::IndexDefSite> indexDefs = whereisIndexDefSites( d.ing, whereisSel, root );

        crossref::WhereResult result = crossref::computeWhereis( root, whereisSel, cfg.strayFilter,
                                                                 crossref::WhereisEvidence{ cfg.withHistory ? &history : nullptr, indexDefs } );
        if( !result.ok )
        {
            std::fprintf( stderr, "ripwire: --whereis: %s is not a git repository (or has no HEAD commit) — no refs to search\n", root.c_str() );
            return 1;
        }
        result.seedSpec = std::move( whereisSeed );
        // The tree zero stays an answer; the near-miss only says WHICH zero it is (a name this repo never
        // had, or a keystroke away from one it has). Computed only on the zero, so a real hit list is
        // byte-identical.
        if( result.hits.empty() )
        {
            result.nearMiss = didYouMean( d.ing, whereisSel );
        }
        crossref::writeWhereisPage( stdout, result, cfg.detail ? SIZE_MAX : crossref::kWhereisHits, cfg.pageLimit, cfg.pageOffset );
        return 0;
    }
    return std::nullopt;
}

// --doc-drift[=SUBSTR]: the markdown docs' CHECKABLE anchors, verified
// against the live index. Index-backed (it needs the crawled file list and the symbol table), so unlike the
// cross-branch verbs above it DOES consume `d.ing` — and unlike them it is multi-root safe: every anchor is
// resolved through the same labeled file identities the rest of the pipeline uses. Always exits 0; drift is
// a report, not a gate (a doc is allowed to be behind while you are mid-change).
std::optional<int> runDocDrift( const MainDispatch& d )
{
    using namespace rw;
    if( !d.cfg.docDrift )
    {
        return std::nullopt;
    }

    // --with-history (opt-in): the git-history name oracle that splits the mention lane's why="undefined"
    // into "this repo deleted it" (rot) and "this repo never had it" (a plan doc naming unbuilt work, not
    // rot). Owned here so both the compute and the write hold non-owning views; without the flag this is an
    // empty index and a nullptr, which is byte-for-byte the pre-flag behaviour.
    const gitoracle::HistoryIndex history =
        buildHistoryIndex( d.cfg, d.root, "the mention lane falls back to why=\"undefined\"" );

    const docdrift::DriftResult result = docdrift::computeDocDrift( d.ing, d.root, d.cfg.excludes, d.cfg.docDriftFilter,
                                                                    d.cfg.withHistory ? &history : nullptr );
    // F-04: a filter naming no markdown document at all refuses rather than printing docs="0" drift="0" —
    // the same ruling --scope and --dead-code=DIR already apply to their own filters (verbs_quality.h).
    if( result.filterMatchedNothing )
    {
        std::fprintf( stderr, "ripwire: --doc-drift=%.*s matches no document — an exit 0 under a filter that owns nothing is a "
                              "failure, not a clean tree\n  (filter is a substring match against ROOT-RELATIVE markdown paths, "
                              "e.g. --doc-drift=README or --doc-drift=docs/COMMANDS.md)\n",
                      int( d.cfg.docDriftFilter.size() ), d.cfg.docDriftFilter.data() );
        return 1;
    }
    docdrift::writeDocDriftPage( stdout, result, d.cfg.detail ? SIZE_MAX : docdrift::kMaxAnchorsShown, d.cfg.gateabilityFlag,
                                 d.cfg.pageLimit, d.cfg.pageOffset );
    return 0;
}

// P3.2 — --plan-lint=FILE: the house PLAN format's STRUCTURE check (src/planlint.h owns the grammar, the
// checks and their stated limits in full). Unlike --doc-drift this needs NO index at all — FILE is read
// directly off disk, exactly like --from-trace's FILE — so it sits right beside --doc-drift in the
// dispatch chain by THEME, not by a shared dependency on `d.ing`/`d.g`. Exit 2 (a gate, not a report) when
// the file shows the recognized dialect and carries a gating row; exit 1 only when FILE could not be read.
std::optional<int> runPlanLint( const MainDispatch& d )
{
    using namespace rw;
    if( d.cfg.planLintFile.empty() )
    {
        return std::nullopt;
    }
    const std::string       file( d.cfg.planLintFile );
    const planlint::LintResult res = planlint::computePlanLint( file );
    if( !res.ok )
    {
        // F-09: a stat()-detected non-regular-file (a directory, most commonly) gets its own specific reason
        // instead of the generic "cannot open" — the two causes are indistinguishable to a caller otherwise.
        if( !res.refuseReason.empty() )
        {
            std::fprintf( stderr, "ripwire: --plan-lint: '%s' %s\n", file.c_str(), res.refuseReason.c_str() );
        }
        else
        {
            std::fprintf( stderr, "ripwire: --plan-lint: cannot open '%s' (or it exceeds the size cap)\n", file.c_str() );
        }
        return 1;
    }
    planlint::writePlanLint( stdout, res );
    return ( res.dialectDetected && planlint::gatingCount( res ) > 0 ) ? 2 : 0;
}


}   // namespace — verbs_change.h section of main.cpp
