#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_for.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings
#include "forpage.h"    // L-W: the --for --limit=N file page, coverage=, the thin rule and the widening next=
#include "forowner.h"   // the question's owner (owner-hop's found set) and the one owner body of an explanatory question
#include "forfold.h"    // body-fold: the whole bodies of the top ranked rows, appended to a compact-route answer
#include "formembers.h" // member-names: mem= on the shown owner rows of a compact-route answer
#include "forslots.h"   // FOR-SLOTS: slots= on the shown initializer rows of a compact-route answer
#include "forgraphverb.h" // FOR-ROUTE-DECLINED: the graph verb a `path from A to B` / `callers of X` task names, appended
#include "forctorhop.h" // OWNER-CTOR-HOP: ctor_l=/ctor_calls= on the r=1 method row of a compact-route answer
#include "fordispatchhop.h"   // mf1-nx wave 4: a task-named call declined at an interface receiver carries its implementations
#include "forselfhook.h"      // lane self-hook: a served Python override names where its base classes reach it through self
#include "forcallerhop.h"   // mf1-nx: a name-exact answer about ONE function carries that function's callers
#include "epmanifest.h"     // ep-manifest: the manifest entry-point groups that register a shown row
#include "listedin.h"       // manifest-noncode: the build/package/registry manifest lines that list a shown file (creation tasks)
#include <algorithm>         // std::ranges::find: the ep manifest re-picked from the rows <sigs> emits
#include <optional>          // the redaction-tally snapshots a degraded pre-render restores
#include <string_view>       // %.*s (precision, pointer) collapses to one view

// FOR-ROUTE-DECLINED: the compact-legend layer's key for a captured verb answer (main.cpp, defined with that layer)
static std::string_view compactLegendHint( const rw::Config& c, std::string_view doc );

// verbs_for.h — the QUERY family (§A2's contiguous dispatch block), moved VERBATIM from main.cpp in
// the 2026-08-29 split: computeLensRanking (THE shared lens ranking — the change family's
// --plan-lanes calls it too, which is why this section is included before verbs_change.h),
// emitCandidates, the --for header/JSON/auto-bodies/compact-hops machinery, runForLens,
// runTargetedViews (--lego/--exemplar/--recall/--query hoist) and runPackTask. Same contract as every
// verbs_*.h: reopens main.cpp's unnamed namespace — one TU, one unnamed namespace, internal linkage
// unchanged, zero new API surface — under the RIPWIRE_MAIN_TU guard.

namespace
{



// The routed → anchored → mention-anchored → (opt-in) co-change-boosted lens rank for a task, plus the header
// note fragments each stage contributes. This is THE ranking the --for lens consumes; extracted so runForLens
// and runPackTask (L4) share ONE ranking implementation (the plan's "do not reimplement ranking" mandate).
// rw::LensRanking itself now lives in packtask.h (L4) — shared with the MCP explore/pack_task verb's own
// routed-ranking path (mcpverbs.h), which populates the SAME struct via the same low-level ranking calls.

// r4/r6 (2026-09-10 lift-disclosure round): apply the lift and build its disclosure note in one call — "" for
// either "the lift did not run" or "it ran and moved nothing" (the same silence-means-nothing-happened
// convention mentionNote/boostNote/docMentionNote already follow). Pulled OUT of computeLensRanking (below,
// already one of the largest functions in this file) rather than inlined at the call site like its three
// siblings: those three predate this round and are not this change's to restructure, but two MORE
// inlined branch-and-format blocks measurably worsened computeLensRanking's own complexity
// (--quality-delta, 2026-09-10) for no reason the format text itself needs — the branch belongs beside the
// mechanism it discloses, not beside the other three unrelated boosts it happens to run next to.
inline std::string applySiblingLiftNoted( const rw::IngestResult& ing, std::vector<float>& lensRank, std::size_t sibSeed, std::size_t sibPer )
{
    rw::SibliftLiftInfo liftInfo;
    if( !rw::applySiblingLift( ing, lensRank, sibSeed, sibPer, &liftInfo ) )
    {
        return {};
    }
    char nb[ 180 ];
    rw::formatTo( nb, sizeof( nb ), " [sibling lift: promoted {} symbol{} in {} same-directory file{} of the top-ranked files (RIPWIRE_SIBLIFT={},{})]",
                   liftInfo.symbolCount, liftInfo.symbolCount == 1 ? "" : "s",
                   liftInfo.fileCount, liftInfo.fileCount == 1 ? "" : "s", sibSeed, sibPer );
    return nb;
}

inline std::string applyStructuralExpansionNoted( const rw::IngestResult& ing, std::vector<float>& lensRank, std::size_t expSeeds, std::size_t expPer )
{
    rw::ExpandLiftInfo liftInfo;
    if( !rw::applyStructuralExpansion( ing, lensRank, expSeeds, expPer, &liftInfo ) )
    {
        return {};
    }
    char nb[ 200 ];
    rw::formatTo( nb, sizeof( nb ), " [structural expansion: promoted {} symbol{} in {} file{} reached via resolved import/reference edges from the top-ranked files (RIPWIRE_EXPAND={},{})]",
                   liftInfo.symbolCount, liftInfo.symbolCount == 1 ? "" : "s",
                   liftInfo.fileCount, liftInfo.fileCount == 1 ? "" : "s", expSeeds, expPer );
    return nb;
}

// Compute the lens rank for `task` exactly as the --for path does (all existing boosts: routing, --anchor,
// the B8 mention anchor, the B3 opt-in co-change prior). Pure function of (d, task): reads d.cfg for the same
// flags --for reads, so both callers get identical rankings for the same query + flags.
// `compactCandidate` — the caller is --for in a posture that may serve the COMPACT bundle, whose <hops>
// section ORDERS a cut callee listing by this very rank vector. That makes it a FULL-DISTRIBUTION
// consumer, like --adaptive and --anchor: a callee is not necessarily in the bundle's own top-K, so a
// MaxScore-pruned score for it is not merely approximate, it is whatever the pruning left behind — and
// the order of two callees would then depend on a performance optimization. postingscheck arm (e) found
// exactly that (the same query returned two different callee orders with and without RIPWIRE_NO_PRUNE),
// which is the gate doing its job: pruning is contracted to be BYTE-NEUTRAL, not nearly so. Measured
// cost of giving it up on this route: none detectable — 384.7 vs 378.2 ms on django, 283.2 vs 269.8 ms
// on webpack, 159.3 vs 159.0 ms on this repo, exhaustive at or inside the noise of pruned every time.
rw::LensRanking computeLensRanking( const MainDispatch& d, std::string_view task, bool compactCandidate = false,
                                    bool fullDistribution = false )   // deep-tail: the file-grain tail reads the WHOLE
                                                                      //   positive-score distribution (its total= is a
                                                                      //   real count, and its order runs far past the
                                                                      //   head), so the --for bundle path forces
                                                                      //   exhaustive scoring — the --adaptive/--anchor
                                                                      //   rule, for the same reason. Callers with no
                                                                      //   tail (pack-task, candidates) keep the H2
                                                                      //   MaxScore pruning.
{
    using namespace rw;
    const Config&                     cfg       = d.cfg;
    const IngestResult&               ing       = d.ing;
    const Graph&                      g         = d.g;
    const std::string&                root      = d.root;
    const bool                        multiRoot = d.multiRoot;
    const std::vector<WorkspaceRoot>& ws        = d.ws;

    // H2 (B0 r2): --for's consumers only read the top-K of this rank, so lexicalScores may skip symbols that
    // provably cannot enter that top-K (exact MaxScore pruning — emitted bytes identical). --adaptive/--anchor
    // are full-distribution consumers and force exhaustive scoring.
    // The route decides the ranker AND (with compactCandidate) whether pruning may run at all, so it is
    // chosen ONCE here and reused below rather than classified twice — chooseForRanker is pure over
    // (ing, task), so hoisting it is byte-neutral by construction.
    const bool        routeOn      = !cfg.noRoute;
    const RouteChoice rc           = routeOn ? chooseForRanker( ing, task ) : RouteChoice{};
    const bool        compactRoute = routeOn && compactCandidate && rc.which == LexMode::SubtokenBody;

    std::size_t       forPruneK = 0;
    std::vector<char> ifaceExact;
    if( !cfg.adaptive && !cfg.anchor && !compactRoute && !fullDistribution )
    {
        forPruneK = cfg.candidates ? ( cfg.topK > 0 ? std::size_t( cfg.topK ) : 0 )
                                   : std::size_t( cfg.packTopN > 0 ? cfg.packTopN : 40 );
        if( forPruneK > 0 && !cfg.candidates )     // candidates bypasses the lens bundle → no lego set
        {
            ifaceExact.assign( ing.symbols.size(), 0 );
            for( std::size_t i = 0; i < g.implementors.size() && i < ifaceExact.size(); ++i )
            {
                if( !g.implementors[i].empty() )
                {
                    ifaceExact[i] = 1;
                }
            }
        }
    }
    const std::vector<char>* ifaceExactPtr = ifaceExact.empty() ? nullptr : &ifaceExact;

    // Query SHAPE (queryshape.h): a pasted trace / sanitizer report / compiler diagnostic, or a pasted
    // issue-template form. ROUTED PATH ONLY — route= is the one place this can be disclosed, so under
    // --no-route the classifier is not even asked and the ranking is byte-identical to what it always was.
    const queryshape::Verdict shape = routeOn ? queryshape::classify( task ) : queryshape::Verdict{};

    // §P4 tier de-prioritization (filter.h): fixtures / present/ decks / generated captures score down,
    // folded INTO BM25 scoring (pruning-bound-safe) and BEFORE the B8 mention anchor — a fixture the task
    // literally NAMES is still lifted near the top. Plus, when a shape fired, the document tier.
    const std::vector<float> tierMul = rankTierSymbolMultipliersShaped( ing, shape.fires() );
    // Change logs and translations go LAST in the doc-mention lift below (filter.h docNoiseSymbolMultipliers), unless
    // the task asks about what those files hold. BM25 is untouched. Routed path only, like the shape.
    const std::vector<float> docNoiseMul = routeOn ? docNoiseSymbolMultipliers( ing, task ) : std::vector<float>{};

    LensRanking out;
    std::vector<float>& lensRank = out.rank;
    if( routeOn )
    {
        lensRank      = ( rc.which == LexMode::NameExact ) ? lexicalScoresNameExactRanked( ing, task, &tierMul )
                                                           : lexicalScoresTiered( ing, g.outOff, g.outTargets, task, forPruneK, ifaceExactPtr, &tierMul,
                                                                                  0, 0, {}, &out.evidence );   // L-W: the term evidence rides out
        if( rc.which == LexMode::NameExact )
        {
            // L-W: the name-exact ranker scores WHOLE names, so the subtoken evidence coverage= and the file page
            // read comes from one exhaustive subtoken pass whose scores are discarded — pure lookups over the
            // persisted statistics (lexindex.h), a small fraction of a --for call (measured ~520 ms warm on a
            // 2,000-file C++ tree, most of it the cache load), paid on the identifier route only.
            lexicalScoresTiered( ing, g.outOff, g.outTargets, task, /*pruneTopK=*/0, nullptr, &tierMul, 0, 0, {}, &out.evidence );
        }
        // §L10b + verify-wave2 F6: no leading space+"[" AND no trailing "]". This string lands ONLY in the
        // route= attribute value (and its JSON "route" twin) now, never spliced into free comment prose, so
        // the brackets that used to demarcate it inside a sentence just left the value opening with a stray
        // " [" and closing on an unbalanced "]". L10b took the leading half only, so every route value on
        // every dialect shipped one dangling bracket. A bracket is a PAIR or it is neither; the ATTRIBUTE
        // QUOTE is the delimiter here. The two stop-anchor helpers that grepped `routed: [^]]*`
        // (test/adaptivecheck.sh routeof(), test/routecheck.sh reasonOf()) are re-pinned to `[^"]*` in the
        // same commit — the quote is the real end of the value and was all along.
        out.routeNote  = routeNoteOf( rc, shape, /*noRoute=*/false );   // row 6: the code itself, no "routed: " prose prefix — ONE producer (filter.h)
        out.docTierTag = shapeDocTierTag( shape );   // §A4f: the machine form of the same fact, for --format=candidates
        out.routeTag   = ( rc.which == LexMode::NameExact ) ? "name-exact" : "subtoken+body";   // §A4f: the machine form of the same fact
        out.anchorDefs = std::move( const_cast<RouteChoice&>( rc ).anchorDefs );   // empty unless the route was DECIDED by names (lexical.h)
    }
    else
    {
        lensRank = lexicalScoresTiered( ing, g.outOff, g.outTargets, task, forPruneK, ifaceExactPtr, &tierMul, 0, 0, {}, &out.evidence );
    }

    // input blow-up guard disclosure (lexical.h kMaxUniqueQueryTerms/dedupeQueryTerms): a task string with
    // more distinct terms than the cap allows still scores — on the terms it kept — rather than refusing, so
    // the cut rides the SAME CapDisclosure channel every other indexing cap on this bundle uses (mention.h),
    // never a silent truncation.
    {
        CapDisclosure termsCap;
        termsCap.note( "terms_capped", "terms_total", out.evidence.termsCapped, out.evidence.termsSeenTotal );
        absorbCapDisclosure( termsCap, out.capNote, out.capAttrs, out.capJson );
    }

    // R4: capture the RAW routed lexical score's max BEFORE --anchor/mention/cochange reshape lensRank — the
    // honesty signal reads the actual textual evidence, not a graph-expanded or query-mention-boosted number
    // (those can promote a symbol the query's words never touched, which would mask a genuinely weak query).
    // The §P4 tier factor is divided back out for the same reason (maxScoreUndoingTier, filter.h).
    if( !lensRank.empty() )
    {
        out.maxLexicalScore = maxScoreUndoingTier( lensRank, tierMul );
    }

    // --anchor (EXPERIMENTAL): lexically-anchored graph expansion (byte-identical without the flag).
    if( cfg.anchor )
    {
        lensRank = anchoredLexicalRank( g, lensRank );
    }

    // B8 query-mention anchoring: lift a file / dotted module / Scope.symbol the task literally NAMES near the
    // top (inert — byte-identical — when the text names nothing indexed). Routed path only.
    if( !cfg.noRoute && !cfg.noMentionBoost && !std::getenv( "RIPWIRE_NO_MENTION" ) )
    {
        MentionBoostInfo mentionInfo;
        if( applyMentionBoost( ing, task, lensRank, &mentionInfo ) )
        {
            char nb[ 220 ];
            rw::formatTo( nb, sizeof( nb ), " [mention anchor: {} file{} + {} symbols named in the task, score lifted to within 5% of the top score; "
                           "mention_anchored= on the root repeats this total]",
                           mentionInfo.fileCount, mentionInfo.fileCount == 1 ? "" : "s", mentionInfo.symbolCount );
            out.mentionNote  = nb;
            out.anchorLifts  = mentionInfo.fileCount + mentionInfo.symbolCount;   // §A4f: the count the candidates root emits
        }
        // Collected whether or not the anchor MOVED anything: a task whose named file fell outside the
        // extraction window lifts nothing, and is the run that most needs telling.
        absorbCapDisclosure( mentionInfo.caps, out.capNote, out.capAttrs, out.capJson );
    }

    // r4 sibling lift (EXPERIMENTAL, pre-registered — bench/locbench/results/r4_siblift/PREREG.md): lift the
    // strongest query-relevant same-directory siblings of the top-ranked files into the slot ladder. INERT
    // (byte-identical) unless RIPWIRE_SIBLIFT="<seed>,<sib>" parses in range. Routed path only.
    if( !cfg.noRoute )
    {
        if( const auto [ sibSeed, sibPer ] = sibliftParams(); sibSeed > 0 )
        {
            out.sibliftNote = applySiblingLiftNoted( ing, lensRank, sibSeed, sibPer );
        }
    }

    // r5 file-level evidence pooling (EXPERIMENTAL, pre-registered —
    // bench/locbench/results/r5_pooling/PREREG.md): rank files by POOLED symbol evidence instead of
    // their single best symbol, so a file with five moderate hits can outrank one with a single sharp
    // one. Chooses no neighbour, which is the axis siblift failed on. INERT (byte-identical) unless
    // RIPWIRE_POOL="<K>,<blend*100>" parses in range. Routed path only.
    if( !cfg.noRoute )
    {
        if( const auto [ poolK, poolBlend ] = filePoolParams(); poolK > 0 )
        {
            applyFilePooling( ing, lensRank, poolK, poolBlend );
        }
    }

    // r6 structural expansion (EXPERIMENTAL, pre-registered —
    // bench/locbench/results/r6_expansion/PREREG.md): lift the RESOLVED import/reference neighbours of
    // the top-ranked files. siblift had this seed with a same-directory edge; anchorhop had this edge
    // seeded from mention anchors; both were rejected. This is the untried diagonal, and the first
    // candidate that adds evidence the QUERY did not supply. INERT unless RIPWIRE_EXPAND="<S>,<N>".
    if( !cfg.noRoute )
    {
        if( const auto [ expSeeds, expPer ] = expandParams(); expSeeds > 0 )
        {
            out.expandNote = applyStructuralExpansionNoted( ing, lensRank, expSeeds, expPer );
        }
    }

    // B3 co-change prior boost (OPT-IN, EXPERIMENTAL): files that historically change WITH the top seeds get a
    // bounded secondary boost. Inert (byte-identical) without usable git history. Routed path only.
    if( !cfg.noRoute && ( cfg.cochangeBoost || std::getenv( "RIPWIRE_COCHANGE" ) ) )
    {
        PROFILE_SCOPE_DESCRIBE( "main: co-change prior boost (mine + apply)" );
        std::vector<std::vector<std::uint32_t>> coSets;
        CommitWindowCensus coCensus;   // the kCoBoostMaxFilesPerCommit census (gitmine.h)
        if( multiRoot )
        {
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                if( !hasEnclosingGitRepo( ws[r].arg ) )
                {
                    continue;
                }
                auto part = gitRecentCommitFileSets( ws[r].arg, ing, kCoBoostCommitWindow, kCoBoostMaxFilesPerCommit, r, &coCensus );
                for( std::vector<std::uint32_t>& c : part )
                {
                    coSets.push_back( std::move( c ) );
                }
            }
        }
        else if( hasEnclosingGitRepo( root ) )
        {
            coSets = gitRecentCommitFileSets( root, ing, kCoBoostCommitWindow, kCoBoostMaxFilesPerCommit, UINT32_MAX, &coCensus );
        }

        CoBoostInfo boostInfo;
        // NOT guarded by coSets.empty(): applyCoChangeBoost records the commit-cap census BEFORE its own
        // empty check and then returns false, so calling it unconditionally is what makes the cap honest.
        // coSets is empty exactly when EVERY commit exceeded kCoBoostMaxFilesPerCommit -- the case where the
        // cap bit hardest -- and a `!coSets.empty() &&` short-circuit meant coboost_commits_capped was the
        // one disclosure never emitted at 100% drop. The return value still gates the boost NOTE alone.
        if( applyCoChangeBoost( ing, coSets, lensRank, &boostInfo, &coCensus ) )
        {
            char nb[ 200 ];
            rw::formatTo( nb, sizeof( nb ), " [cochange boost: promoted {} symbols in {} files that historically change with the top seeds (last {} commits)]",
                           boostInfo.boostedSymbolCount, boostInfo.boostedFileCount, kCoBoostCommitWindow );
            out.boostNote = nb;
        }
        absorbCapDisclosure( boostInfo.caps, out.capNote, out.capAttrs, out.capJson );
    }

    // R5 — doc-mention surfacing (default-on, route-agnostic; see mention.h applyDocMentionBoost):
    // reuses g.mentions (the same doc<->code backtick edges `--mentions=SYM` already exposes) to lift docs
    // that discuss the query's top-resolved symbols, strictly below those symbols' own scores. Runs LAST
    // (after route/anchor/query-mention/co-change) so it reads the fully-resolved rank.
    if( !cfg.noDocMention && !std::getenv( "RIPWIRE_NO_DOC_MENTION" ) )
    {
        DocMentionBoostInfo docMentionInfo;
        if( applyDocMentionBoost( g, lensRank, &docMentionInfo, docNoiseMul ) )
        {
            char nb[ 220 ];
            rw::formatTo( nb, sizeof( nb ), " [doc mentions: {} doc{} discussing {} top-ranked symbol{} surfaced; doc_mentions= on the root repeats the doc count]",
                           docMentionInfo.docCount, docMentionInfo.docCount == 1 ? "" : "s",
                           docMentionInfo.anchorCount, docMentionInfo.anchorCount == 1 ? "" : "s" );
            out.docMentionNote  = nb;
            out.docMentionCount = docMentionInfo.docCount;   // §L10b: machine form for the doc_mentions= root attribute
        }
        absorbCapDisclosure( docMentionInfo.caps, out.capNote, out.capAttrs, out.capJson );
    }
    return out;
}

// §P8/§P12.2 — --adaptive used to silently no-op under --format=candidates: both candidates dispatch sites
// (the --for one below and --query's in runDefaultMap) returned before the cliff-cut logic ever ran, so the
// flag was accepted and produced byte-identical output. It now cuts the SAME scored list candidates already
// exports — one leading XML comment (candidates owns its own document root, so this mirrors how --query's
// own default-map adaptive note is emitted: a comment ahead of the root, never inline inside it) plus the
// clamped row cap. `ceiling` is the verb's own natural cap (--top-k, not the 40-row --for lens cap).
// `scanFullDistribution` mirrors each CALLER's own default-map --adaptive behavior (true for --for, whose
// 40-row cap can hide the true cliff; false for --query, whose ceiling already covers the full top-k).
// One function (not inlined at each call site) so the two PRE-EXISTING dispatch functions this composes
// into (runForLens/runDefaultMap) each gain a single call instead of the whole cut-and-print sequence.
inline void emitCandidates( std::FILE* out, const rw::IngestResult& ing, const std::vector<float>& rank,
                             int topK, bool adaptive, bool scanFullDistribution,
                             rw::CandidateProvenance prov,   // §A4f: route/anchored/weak — the caller owns which ranker ran
                             rw::RedactCounts* redact,       // §B0/W3-N1: REQUIRED — <sig> is emitted text
                             std::string_view candRootArg )  // R-R: the single-root root its p=/id= are relative to
{
    int capN = topK;
    if( adaptive )
    {
        const rw::AdaptiveCut ac = rw::adaptiveCut( rank, 5, std::size_t( topK ), scanFullDistribution );
        // T14: same homonym-pool decline as --for's own bundle (lexical.h isAdaptiveHomonymDecline) — this
        // export shares the identical adaptiveCut call and must not narrow a large homonym pool on tie-break
        // order either. `prov.route` is the caller's own routing fact ("name-exact"/"subtoken+body"/"no-
        // route"/…) — read through isNameExactRouteTag, the one predicate every call site now shares
        // (review rv-t14a.md finding 1: runForLens's OWN inline check answered a different question and
        // mislabeled "no-route" as name-exact; this site was already correct, now on the shared function).
        const bool declined = rw::isAdaptiveHomonymDecline( rw::isNameExactRouteTag( prov.route ), ac, 5 );
        char nb[ 208 ];
        if( declined )
        {
            rw::formatTo( nb, sizeof( nb ), "<!-- adaptive: declined - {} symbols share this exact name; the score gap here is tie-break order, not relevance - kept the default top-{} -->",
                           ac.positiveHits, topK );
        }
        else if( !ac.hitCeiling && ac.cliffRank < ac.kept )
        {
            rw::formatTo( nb, sizeof( nb ), "<!-- adaptive: kept {} of {} - sharp cliff at rank {} ({}% drop), clamped up to the floor of {} -->",
                           ac.kept, topK, ac.cliffRank, ac.dropPct, ac.kept );
        }
        else if( !ac.hitCeiling )
        {
            rw::formatTo( nb, sizeof( nb ), "<!-- adaptive: kept {} of {} - cliff at rank {}, {}% drop -->",
                           ac.kept, topK, ac.cliffRank, ac.dropPct );
        }
        else if( ac.positiveHits <= ac.kept )
        {
            rw::formatTo( nb, sizeof( nb ), "<!-- adaptive: kept {} of {} - only {} symbols matched this query (sharp query, short tail) -->",
                           ac.kept, topK, ac.positiveHits );
        }
        else
        {
            rw::formatTo( nb, sizeof( nb ), "<!-- adaptive: kept {} of {} - no relevance cliff (broad query saturates the score); capped at the ceiling -->",
                           ac.kept, topK );
        }
        std::fputs( nb, out );
        capN = declined ? topK : int( ac.kept );
    }
    packCandidates( out, ing, rank, capN, redact, prov, candRootArg );   // R-R: root-relative p= + id=
}

// ── §A4a — the --for --json bundle, budgeted ────────────────────────────────────────────────────────────
// The JSON lens used to run NO size control at all: byte-identical at --token-budget=1000 and 20000 while
// the XML sibling shrank 4.7x, so the JSON/MCP audience — the one that most needs a budget — had none. It
// runs the same H1 ladder against the same budget the XML path computes, and SAYS what it did: "capped" is
// the ladder's own verdict (never inferred by the caller) and "est_tokens" is the delivered size, mirroring
// the XML `<sigs shown= total= capped="1">` / header `est_tokens="N"` attributes.
//
// The sigs array is rendered into memory first for exactly the reason the XML path buffers it: the TRUE
// delivered byte count must be known before the header that reports it is written. Its own function (not a
// branch inside runForLens) because it is a whole second serialization of the bundle — inlined, it made the
// XML path harder to read for a reader who only cares about XML.
struct ForLensJsonInputs
{
    const rw::IngestResult&          ing;
    const std::vector<float>&         rank;
    int                               topN;
    const std::vector<std::uint32_t>* fanIn;
    const std::vector<char>*          impure;
    const std::vector<std::uint32_t>* churnPerFile;
    const std::vector<std::uint8_t>*  cloneMember;
    const std::vector<std::uint8_t>*  tested;
    const std::vector<std::uint32_t>* amp;
    rw::RedactCounts*                redact;            // §B0: the run's redaction tally — nullptr under --no-redact
    std::size_t                       packBudgetBytes;   // per-entry streaming budget (--pack-budget-bytes)
    std::size_t                       tokenBudget;       // --token-budget=N, 0 ⇒ the kForPayloadBudgetBytes default
    const rw::notes::NoteIndex*      noteIndex;         // §B1.3: L3 field notes, as the XML bundle already
                                                         // receives them. nullptr ⇒ no notes keys at all.
    // §B1.4 (capture-audit-4): existence counts for the three sections that stay XML-only under --json —
    // the notes_total convention verbatim: "what the tree matched" BEFORE any display-side cap/dedup, not a
    // promise of exactly how many rows the XML sibling would print. legoTotal in particular can exceed the
    // XML's own row count (packLego dedups same-named interfaces and caps at topN=12) — that is by design,
    // not drift: the point is telling 0 (genuinely nothing on this surface) from N>0 (dropped, ask for XML),
    // not mirroring packLego's display-only collapsing. Always present (never conditional), because a key
    // that is sometimes ABSENT reintroduces the exact ambiguity this fix exists to remove.
    std::size_t                       legoTotal;
    std::size_t                       composeTotal;
    std::size_t                       routesTotal;
    // R-R (2026-08-24): the run's root, so this bundle's "p"/"id" are root-relative like the XML twin's.
    // The R-E harvest reached the XML --for bundle but left this JSON sibling's packSignaturesJson call
    // spelling `/*rootArg=*/{}` — the two dialects of ONE question disagreed about the spelling of a path.
    std::string_view                  rootArg;
    // DEEP-TAIL d2: the file-grain tail (FOLD C: page 0 of the --for file page, computed once above the dialect split, so
    // both dialects serve the same rows). REQUIRED, not defaulted — a defaulted pointer is how a dialect
    // silently loses a surface its XML twin serves.
    const rw::FileTail*               fileTail;
    const rw::LexTermEvidence*        evidence;   // FOLD C: the term evidence the tail's page rows rank by (the lens run's own)
    // L3 follow-up (CodeRabbit 4053600616): read BEFORE the caller nulls noteIndex for emptiness (d.notesDegraded,
    // MainDispatch) — REQUIRED like fileTail above, for the same reason: a defaulted bool is how a degrade
    // silently drops off this dialect while the XML twin keeps carrying it.
    bool                               notesDegraded;
    // code above docs (serialize.h reorderDocsAfterCode): the XML twin's verdict, REQUIRED for the same reason
    bool                               docsAfterCode;
    // head round-robin (serialize.h reorderHeadRoundRobin): the XML twin's verdict, REQUIRED for the same reason
    bool                               headRoundRobin;
    // knob-honesty-068: what the "sigs_next" continuation echoes (serialize.h SigsCutContinuation) — REQUIRED like the two
    // above: a capped JSON bundle names the call that serves its cut rows exactly as the XML twin's <sigs next=> does.
    std::string_view                  task;
    int                               packTopN;
    std::string_view                  rankFlags;   // forRankShapingFlags( cfg ), owned by the caller for the call's duration
};

// The lens bundle's opening keys. Every note is absent-unless-present — the same silence-means-nothing-
// happened convention the XML header comment uses, so a reader never has to tell an empty string from a
// missing stage. §A4e: `weak` is the one that used to be XML-only (string-spliced into a comment, hence
// structurally unreachable from JSON); it is a real key here.
struct ForLensNotes
{
    const std::string& route;
    const std::string& mention;
    const std::string& boost;
    const std::string& siblift;    // r4 EXPERIMENT — "" unless RIPWIRE_SIBLIFT actually promoted a symbol
    const std::string& expand;     // r6 EXPERIMENT — "" unless RIPWIRE_EXPAND actually promoted a symbol
    const std::string& docMention;
    // §L10b: the XML twins of mention_anchored=/doc_mentions= (verbs_for.h ForLensHeaderParts) — same
    // absent-unless-present convention as `mention`/`docMention` above (0 only when the note above is
    // also ""; the emitter below gates on the STRING, not these, so a genuine zero can never occur here).
    std::uint32_t       mentionAnchored = 0;
    std::uint32_t       docMentions     = 0;
    const std::string& adaptive;
    const std::string& floor;       // LB-A: the relevance floor's shrink note, "" when it did not fire
    // the confidence disclosure is the exception to absent-unless-present: it is a FACT of every ranking
    // (the §A4e `weak` precedent — a root fact must be legible from either dialect, so the XML attrs get
    // real keys here rather than a string spliced somewhere JSON cannot reach).
    const char*        confidence;  // "high" | "low"
    int                marginPct;   // the whole-percent relative drop the confidence derives from (0 = none)
    int                coveragePct; // L-W: the XML root's coverage= (-1 = absent: nothing scored)
    bool               weak;
    // M10: gitstamp::stampAt(root) — the raw sha[+dirty] value, "" on multi-root/non-git (never "null" as
    // a STRING; the JSON emitter below distinguishes empty-string-absent from a real value the same way
    // every other JSON dialect's at= sibling does — see writeTestGateReportJson/situationDiffJson).
    const std::string& at;
    // ── HARNESS-FACING instrumentation, JSON dialect ONLY (docs/EVALS.md, "Agent Retrieval Bench —
    // abstention round 2: the adaptive cut's corpus-support facts", PRE-REGISTERED 2026-08-30) ───────
    // The adaptive cut computes these three and, before this, emitted none of them on any surface. They
    // are the raw counts BEHIND confidence=/margin_pct=, not a second opinion about them: same
    // adaptiveCut call, same score vector, no new scorer and no second pass. Round one closed threshold
    // tuning over confidence=/margin_pct= as a recorded NEGATIVE and named exactly these as the next
    // candidate, so they exist here to be MEASURED against the benchmark's selective splits — not yet
    // to be read by an agent. Hence this dialect and nowhere else: the XML bundle's header rides a
    // measured byte ceiling (fornotesbudgetcheck.sh fits at est_tokens=800 exactly), and a fact that may
    // turn out to carry no signal has not earned bytes off every ranked answer. MCP `for` serves the XML
    // (forTaskText), so no agent surface moves. Promotion to XML root attributes — with the legend
    // clause, --help and skills text the surface-audit checklist demands — is what a POSITIVE
    // calibration outcome licenses, and is deliberately NOT done here.
    std::size_t        keptCount;   // AdaptiveCut::kept — the cliff-clamped head size, in [floor, ceiling]
    std::size_t        scored;      // AdaptiveCut::positiveHits — indexed symbols with a routed score > 0
    std::size_t        corpus;      // symbols the lens scored at all — the denominator `scored` means nothing without
    // The XML root's cap attributes, already spelled as JSON key pairs by mention.h's CapDisclosure so the
    // two dialects cannot drift into two vocabularies. "" on every run where no indexing cap fired.
    std::string_view   capJson;
};

// W3FIX H2 — the pieces --for's header comment is made of, so the header can be REBUILT in three shapes (as
// built / task echo dropped / that plus route=) for serialize.h's climbCeilingLadder to price. A free function
// over a parts struct rather than a lambda inside runForLens: the ladder calls it up to three times, and
// runForLens is already one of the largest functions in this file. Mirrors packtask.h PackTaskHeaderParts.
struct ForLensHeaderParts
{
    std::string_view task;             // §B1.7's subject — the VERBATIM query, for the root attribute
    std::string_view rootOpenStr;      // ctxRootOpen( task, routeNoteRaw ), pre-built (its size is charged)
    std::string_view taskNote;         // the comment's scrubbed echo of `task` (xmlCommentText)
    std::string_view adaptiveNote, mentionNote, boostNote, docMentionNote;
    std::string_view sibliftNote, expandNote;   // r4/r6 EXPERIMENTS — present only when the env-gated lift actually promoted something
    std::string_view floorNote;        // LB-A: present only when the relevance floor actually shrank the quota
    // Ranking-confidence disclosure (paper-shape lane; arXiv 2607.24882 names abstention/confidence as the
    // unsolved retrieval axis). ALWAYS present — facts derived from the SAME adaptiveCut gap statistic
    // --adaptive cuts at, no new scorer, no behavior change. The attrs live HERE rather than in the
    // pre-built rootOpenStr because the ceiling ladder's route-dropped rung rebuilds the root open from
    // scratch (ctxRootOpen below) and would silently shed a fact spliced into the pre-built string.
    std::string_view confidenceAttrs;  // e.g. ` confidence="high" margin_pct="34"` — root facts, every ladder rung
    std::string_view confidenceNote;   // the legend sentence defining the two attributes (legend-coverage contract)
    std::string_view gitAtAttr;        // M10: ` at="<sha>[+dirty]"` (gitstamp::atAttr) — "" on multi-root/non-git;
                                        // same ALWAYS-present, never-budget-dropped treatment as confidenceAttrs
                                        // above, for the same reason (a root fact, not a content row).
    std::string_view mentionDocAttrs;  // §L10b: ` mention_anchored="N"`/` doc_mentions="N"`, EACH present only
                                        // when its own note fired (unlike confidenceAttrs/gitAtAttr, these are
                                        // not facts of every ranking) — machine form of mentionNote/docMentionNote,
                                        // spliced the same way so the ladder's route-dropped rebuild keeps it.
    bool             anchor     = false;   // --anchor's EXPERIMENTAL caveat paragraph
    bool             autoBundle = false;   // T3: auto mode is on (cfg.detail==0, no --signatures-only) — appends the bundle=auto legend
    bool             compactBundle = false;   // COMPACT conceptual serving: appends the bundle=compact legend INSTEAD of the auto one — never both, because only one of the two sections can be emitted
    bool             compactLegend = false;  // --legend=compact: versioned, shorter explanatory dialect
    bool             tailLegend    = true;    // deep-tail: the r=/<tail> legend clause. forbudget-soft: never dropped any more
                                              //   (the ceiling ladder's rung zero went with the hard ceiling); kept as the
                                              //   one switch the header writers read
    bool             idRouteLegend = true;    // row 6 (2026-09-12): the sc=/route= readings (graphlegend.h kForIdRouteLegend);
                                              //   never dropped either, for the same reason
    std::string_view rootArg;              // R-E (2026-08-17): the single-root run's own root= — the ladder's
                                            // route-dropped rebuild below calls ctxRootOpen a second time and
                                            // must carry the SAME root as the pre-built rootOpenStr did.
    bool             hdrLegend  = false;    // R2-AF (round 2, S4): present-only — set when forHdrRows (mention.h
                                            // rw::forNamedHeaderRows) is non-empty. NOT ceiling-droppable (unlike
                                            // tailLegend/idRouteLegend/confidenceNote): the rows themselves are a
                                            // small, bounded lookup outside the H1 payload budget, so their
                                            // definition rides with them rather than falling to the ceiling.
    bool             scPresent = true;      // PR #215 review: does any row this bundle serves carry sc=? The two
                                            // dialects' sc= readings are present-only on it, and the dropped-legend
                                            // note names sc= only when it had something to define. Defaults TRUE —
                                            // an over-approximation costs a reader nothing but a clause, while an
                                            // under-approximation is an undefined first-screen attribute.
    bool             composePresent = false;  // L1 fix: may a <compose><field> row ride this bundle? The compact dialect defines
                                            // <field> present-only on it; the same over-approximation as scPresent (an edge
                                            // touching a ranked symbol), decided before the header is built.
    bool             legoPresent = false;    // TRAIN 9: may an <iface implementors=> row ride this bundle? Same
                                            // over-approximation and same timing as composePresent: a ranked symbol
                                            // with implementors, asked before the header is built rather than after
                                            // the section is rendered (the header is priced, and re-priced, from here).
    bool             layerPresent = false;   // TRAIN 9: does any ranked row's file sit under a built-in arch layer
                                            // directory, so its <d> row carries layer=? Same over-approximation again.
    bool             modScopePresent = false;   // #60: does any ranked row name a file's MODULE SCOPE (t="modscope",
                                            // n=<file-scope>)? It reaches this bundle as a <d> row and, more often,
                                            // as a <h n="<file-scope>"> hop row. Same over-approximation, same reason.
    bool             endLinePresent = false;   // may a <d> row carry e= (serialize.h defEndLine)? A code row with a known
                                            // extent among the row head — read from the same head walk as
                                            // modScopePresent; a file the emitter then fails to read is the residual.
    bool             viaPresent = false;     // FE-B: may a <calls><c> row of this bundle carry via="name"? Some head row
                                            // (the same row head modScopePresent reads) has a name-only out-edge
                                            // (serialize.h namesOnlyOutAny). Over-approximates the 16-per-symbol cap.
    bool             ownerPresent = false;   // owner-hop: the compact <hops> carries a qword= row or a qword_cut= disclosure
                                            // (forOwnerHopPlan, decided before the header, cleared with the section)
    bool             viaByOwnerOnly = false; // owner-hop: viaPresent holds ONLY because the owner rows joined the via question
                                            // (the six ranked hop ids alone answer no) — the via clause is then the owner
                                            // rows' disclosure, exempt from the sig trim exactly as the qword clause is
    bool             bodySlotPresent = false; // for-body-slot: an explanatory question on the compact route named an owner
                                            // (forowner.h forBodySlotOwner), so a <bodies> element rides — served, or skipped
                                            // under a target with its next= — and the slot clause defines it (present-only)
    bool             splitPresent = false;   // attrib-multidef Q1: may a <calls><c> row carry prov="split"? viaPresent's twin
                                            // question over the same ids (serialize.h splitArmsOutAny); set after construction
    bool             hopsCallsNextPresent = false; // body-fold rider: a ranked <hops> row's cut <calls> carries next= (set after the
                                            // hops render, cleared with the section)
    bool             bodyFoldPresent = false; // body-fold: a compact-route answer in the default regime has fold candidates
                                            // (forfold.h forBodyFoldCandidates), so a <fold> rides and its clause defines it;
                                            // set after construction, cleared with the section
    bool             foldFollowPresent = false; // WRAPPER-FOLLOW (forfold.h renderFollows): the fold carries a <b follow_of=> (set after
                                            // the fold renders), so its clause defines it
    bool             memberNamesPresent = false; // member-names (formembers.h): a shown owner row carries mem= (set after the
                                            // <sigs> splice), so its clause defines it
    bool             initSlotsPresent = false;   // FOR-SLOTS (forslots.h): a shown initializer row carries slots= (set after the
                                            // <sigs> splice), so its clause defines it
    bool             slotJoinPresent = false;    // IX1-V2 (forslots.h spliceSlotJoinRows): a shown row carries slot_by= / slot_fields=
    bool             slotNamePresent = false;    // fix1 F-4: a printed slot caller carries the field-name-only mark (`~`)
    bool             ctorHopPresent = false;     // OWNER-CTOR-HOP (forctorhop.h): the r=1 row carries ctor_l= (set after the splice)
    bool             callerHopPresent = false; // mf1-nx: a name-exact answer whose body candidates are ONE function in the default
                                            // regime (forcallerhop.h forCallerHopTargets), so a <callers> rides and its clause
                                            // defines it; set after construction, cleared with the section
    bool             callerHopRanked = false;  // UPWARD-2HOP: that <callers> is the ranked seed's (by="rank"), so ITS clause rides instead
    bool             dispatchHopPresent = false; // mf1-nx wave 4 (fordispatchhop.h): a <dispatch> rides; its clause defines it
    bool             selfHookPresent = false;    // lane self-hook (forselfhook.h): a <selfhooks> rides; its clause defines it
    bool             epPresent = false;        // ep-manifest (epmanifest.h): a manifest entry-point group registers a shown row in
                                            // the default regime, so an <ep> rides and its clause defines it; cleared with it
    bool             listedPresent = false;    // manifest-noncode (listedin.h): a manifest lists a shown file on a creation task, so a
                                            // <listed> rides and its clause defines it; cleared with it
};

// Splice a pre-formatted fragment in front of a structural boundary, or leave the document exactly as it
// was. Every late splice in this file is this operation: three root attributes go in front of the FIRST
// "><!--" (escapeXml entity-escapes '<' inside attribute values, so that occurrence is unambiguously the
// root element's own close), three note clauses go in front of the LAST " -->", and rootOpenWithExtraAttrs
// below goes in front of a root open tag's '>'. All of them share the same fallback — an unexpected shape
// leaves the document untouched rather than inserting at a guessed offset — and that fallback is the whole
// of the error handling, which is why it belongs in one place instead of seven.
// EMPTY IS A NO-OP, so a caller whose fragment did not fire needs no `if` of its own.
inline void spliceBefore( std::string& doc, std::string_view boundary, bool fromEnd, std::string_view part )
{
    if( part.empty() )
    {
        return;
    }
    const std::size_t at = fromEnd ? doc.rfind( boundary ) : doc.find( boundary );
    if( at != std::string::npos )
    {
        doc.insert( at, part );
    }
}

// insert pre-formatted attributes (leading space, already attribute-safe — every caller's values come
// from a fixed enum + an int or a versioned schema id, never corpus text) before the root open tag's '>'.
inline std::string rootOpenWithExtraAttrs( std::string rootOpen, std::string_view attrs )
{
    spliceBefore( rootOpen, ">", /*fromEnd=*/false, attrs );
    return rootOpen;
}

inline std::string rootOpenWithSchema( std::string rootOpen, std::string_view schema )
{
    if( schema.empty() )
    {
        return rootOpen;
    }
    return rootOpenWithExtraAttrs( std::move( rootOpen ), " schema=\"" + std::string( schema ) + "\"" );
}

// ── Ranking-confidence disclosure for --for (paper-shape lane; arXiv 2607.24882 names abstention/
// confidence as the unsolved retrieval axis) ─────────────────────────────────────────────────────────
// The MAPPING, from facts adaptiveCut already computed — pure, deterministic, and stated in the legend
// sentence it also builds. high on either of two grounds: a MATERIAL cliff inside the served window
// (!hitCeiling — the sharp-query shape, margin_pct= is that drop), or the served head already contains
// EVERY positive match (nothing beyond it for a cut to get wrong; the caller passes the FINAL head size,
// after the relevance floor trimmed the zero-score tail). Everything else is low: a flat head with a
// longer positive tail — the shape where a fixed head is a guess — including the zero-hit query
// (positiveHits==0 fails the completeness ground's >0 guard deliberately: a ranking of nothing is not a
// trustworthy ranking). margin_pct reports the IN-WINDOW drop only (0 under hitCeiling): a material drop
// far beyond the served head cannot justify trust in the head, and quoting it here would claim exactly
// that. A free function over the cut rather than more lines in runForLens, which is already one of the
// largest functions in this file (the forLensHeaderText precedent).
// A6/H14: ForConfidence + deriveForConfidence moved to lexical.h, beside the adaptiveCut they read — the
// MCP `for` twin serves confidence=/margin_pct= from the SAME derivation now instead of omitting the
// routing trust gauge entirely (capture-audit H14). Nothing about the numbers changed.
using rw::ForConfidence;
using rw::deriveForConfidence;

// A1′ (owner decision 2026-09-12): --for's COMPACT legend, pinned like every other verb's (test/compactlegendcheck.sh, the
// ripwire.for/v1 row) and PRESENT-ONLY — every clause below is emitted only when the document carries the
// attribute it defines, and every reading is the shortest honest one. It used to spend 1,177–1,216 B here
// (the same sentences as the default dialect with a schema id in front) and was exempt from the per-verb
// pin by name; a compact dialect exempt from being compact is not one. The data notes (relevance floor,
// doc mentions, mention anchor, co-change boost) keep their NUMBERS and lose their explanation
// (compactForNote below); adaptive/siblift/expansion notes are kept verbatim — their text IS the data
// (cliff rank, drop, the env knob). No "--" anywhere: an XML comment (G4).
//
// WHAT RIDES WHERE. Root facts that the root's own attributes state (bundle=/bodies=/reason=) get one
// clause; the lens columns one clause (cx/ccx/in/churn/amp/clone/tested are always computed on this
// surface, clone=/tested= appear only where 1); sc= and next= ride the <d> clause; route= only when the
// root carries it (the ladder's rung (c) drops the attribute, and then its reading goes with it); the
// confidence, sc=/route= and tail clauses always ride (forbudget-soft: no ceiling ladder sheds them); the compact bundle's hops/calls/noedge clause and the auto bundle's bodies clause are
// mutually exclusive by construction (planForEnrichment).
inline constexpr std::string_view kForCompactLegendRoot =
    "bundle=/bodies=/reason= the body posture; ";
inline constexpr std::string_view kForCompactLegendRows =
    "d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; "
    "total= shown= capped=1 if cut";
// …and the same clause for a bundle whose served rows carry NO scope (a corpus of free functions, a markdown
// tree): 22 B of sc= reading removed, nothing else. Two constants rather than one built at runtime because this
// dialect's whole contract is a pinned byte count per schema, and a pin reads a constant.
inline constexpr std::string_view kForCompactLegendRowsNoScope =
    "d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1; "
    "total= shown= capped=1 if cut";
static_assert( kForCompactLegendRows.find( rw::kForZeroAbsentCompactNote ) != std::string_view::npos
               && kForCompactLegendRowsNoScope.find( rw::kForZeroAbsentCompactNote ) != std::string_view::npos,
               "the compact zero reading is the exempt note, verbatim (graphlegend.h forZeroNoteBytes)" );
// L1 fix round (2026-09-19, rv-r1-L1 HIGH-1): task= (the root's echo of the query), next= (the follow-up on a <d> row), pure=
// (a <d> row flag) and the <compose><field> rows rode every default answer with no reading in either dialect;
// legendcoveragecheck's default rows now fail on that. Charged like the rows clause; runForLens caps the compact charge at
// the full dialect's, so defining them never costs the default a row (compactlegendcheck (P1)).
inline constexpr std::string_view kForCompactLegendFacts =
    "; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste";
// The <compose> block's rows (serialize.h packCompose), present-only on composePresent.
inline constexpr std::string_view kForCompactLegendCompose =
    "; field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer";
// TRAIN 9: two attributes the merged stack put on a DEFAULT --for first screen that neither member saw alone.
// L2's --sections=lego,compose serves the lego section WHOLE, so <iface implementors=> reaches the rows; and a
// query that ranks a file under a built-in arch layer dir (test/, bench/, infra/, render/ …) puts layer= on its
// <d> row. Both present-only, on the same terms as the compose clause above: absent, they cost nothing.
inline constexpr std::string_view kForCompactLegendLego =
    "; iface implementors=N: types implementing it, m= its method contract";
inline constexpr std::string_view kForCompactLegendLayer =
    "; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=";

// ONE spelling for both dialects (graphlegend.h kForRouteCodeLegend): the compact dialect and the default one
// say the same thing about route=, so they cannot drift into two readings of one code.
inline constexpr std::string_view kForCompactLegendRoute = rw::kForRouteCodeLegend;
inline constexpr std::string_view kForCompactLegendConfidence =
    "; confidence=/margin_pct= head score drop (low=flat)";
inline constexpr std::string_view kForCompactLegendHops =
    "; h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved";
// owner-hop: present-only, right after the hops clause, on the same plan the rows come from. Says it is BY NAME (a lookup in
// the ranked head, never a resolution), widens noedge= to the owners, and defines the two disclosures an owner cut carries.
// What qword= does NOT mean: that the row is the only, or the true, implementation of the question's subject.
inline constexpr std::string_view kForCompactLegendOwner =
    "; h qword= its name (case-folded, leading _#$@ dropped) equals that question word (by name, not resolved, not the only one), first, calls to 100 (capped=1 next= all); "
    "qword_cut= owners not so served, next= the first";
// owner-hop: the full dialect's reading of the same two attributes (present-only, after the clause above; no "--": a comment)
inline constexpr std::string_view kForOwnerHopLegend =
    "; hops row qword= the question word that row's NAME equals (ASCII case-folded, leading _ # $ @ dropped; by name in the "
    "ranked head, a lookup, not a resolution; it "
    "does not mean the symbol is the only or the true implementation): such an owner row comes first (a word on a short "
    "common-verb list such as get, set, run or write ranks after the other owner words) and its calls child "
    "lists up to 100 callee names (capped=1 with next= naming the full list when the guard or the budget cut it); an owner "
    "with no resolved callee is counted in noedge= like any ranked symbol. hops qword_cut=N: owners not served as a qword "
    "row (the three-row cap or the budget; one of the six ranked candidates still keeps its plain row), next= the first";
// …and the one question both dialects ask: the clause in this dialect, or nothing (ownerPresent is set only on the compact
// route and cleared with the section, so it never rides without the hops clause in front of it).
inline std::string_view ownerHopLegend( const ForLensHeaderParts& p, bool compact ) noexcept
{
    if( !p.ownerPresent )
    {
        return {};
    }
    return compact ? kForCompactLegendOwner : kForOwnerHopLegend;
}
// …and what the sig-trim ledger exempts for the owner rows in this dialect: the qword clause, plus the via="name" clause when
// the owner rows alone switched it on (a base answer without them never carried it, so charging it cost <sigs> a row:
// fastify-13 Context r23, pdoc AstInfo r38). ownerPresent and viaPresent are cleared with their sections, so neither part
// is exempted for a clause the header did not write.
inline std::size_t ownerLegendExemptBytes( const ForLensHeaderParts& p, bool compact )
{
    const bool        viaByOwner = p.viaPresent && p.viaByOwnerOnly;
    const std::size_t viaBytes   = !viaByOwner ? 0u : ( compact ? rw::kForCompactViaNameClause.size() : rw::forViaNameClause().size() );
    return ownerHopLegend( p, compact ).size() + viaBytes;
}
inline constexpr std::string_view kForCompactLegendBodies =
    "; b t= n= p= l= full bodies, c n= l= callee signatures";
// for-body-slot: the compact dialect's reading of the ONE owner body (the full dialect's is forowner.h kForBodySlotLegend + the
// root clause below), present-only (bodySlotPresent), right after the owner clause. No "--": it rides inside an XML comment.
// FIX1 R3: it states what the full one states — what each pick= means and what reason=owner does NOT mean (the subject, the
// whole answer): the default posture is this dialect, so this is the only reading most readers get.
inline constexpr std::string_view kForCompactLegendBodySlot =
    "; b t= n= p= l= full bodies, c n= l= callee signatures; bodies=1 reason=owner: ONE body, the question's owner by the rule "
    "(pick=name: its name is a question word; pick=member: a method so named of a ranked class), chosen by name not resolved; "
    "not necessarily the subject, not a claim it is the whole answer; shown=0 capped=1 next= when a budget skipped it";
static_assert( kForCompactLegendBodySlot.starts_with( kForCompactLegendBodies ), "the slot's compact clause defines <b> as the bodies clause does" );
inline constexpr std::string_view kForBodySlotRootClause = "; when it rides this root reads bodies=1 reason=owner";
inline std::string bodySlotLegend( const ForLensHeaderParts& p, bool compact )
{
    if( !p.bodySlotPresent )
    {
        return {};
    }
    return compact ? std::string( kForCompactLegendBodySlot ) : std::string( rw::kForBodySlotLegend ) + std::string( kForBodySlotRootClause );
}
// body-fold rider (forbudget-soft N3): a ranked hop's cut <calls> listing carries next= (serialize.h packHops), defined present-only
// (hopsCallsNextPresent: read off the rendered <hops>), so an answer without a cut listing is byte-identical to before
inline constexpr std::string_view kForCompactHopsCallsNextClause = "; h calls capped=1 next= the call listing every callee";
inline constexpr std::string_view kForHopsCallsNextClause =
    "; a hop row's cut calls listing (capped=1) carries next=, the call that lists every callee";
// does a RANKED hop row (an <h> without qword=: an owner row's cut listing is the owner clause's) carry a cut <calls> with next=
inline bool rankedHopCallsNextPresent( std::string_view hops ) noexcept
{
    for( std::size_t at = hops.find( "<h " ); at != std::string_view::npos; at = hops.find( "<h ", at + 3 ) )
    {
        const std::size_t tagEnd = hops.find( '>', at );
        const std::size_t rowEnd = hops.find( "</h>", at );
        if( tagEnd == std::string_view::npos || rowEnd == std::string_view::npos )
        {
            return false;
        }
        const std::string_view tag  = hops.substr( at, tagEnd - at );
        const std::size_t      open = hops.find( "<calls ", tagEnd );
        const std::size_t      shut = open == std::string_view::npos ? open : hops.find( '>', open );
        if( tag.find( " qword=\"" ) == std::string_view::npos && open < rowEnd && shut != std::string_view::npos
            && hops.substr( open, shut - open ).find( " capped=\"1\" next=\"" ) != std::string_view::npos )
        {
            return true;
        }
    }
    return false;
}
// A present-only clause in this dialect: "" unless its element or attribute rides, else the compact or the full spelling.
inline constexpr std::string_view presentOnlyClause( bool present, bool compact, std::string_view compactClause, std::string_view fullClause ) noexcept
{
    return !present ? std::string_view() : ( compact ? compactClause : fullClause );
}

// mf1-nx / UPWARD-2HOP: the caller hop's present-only clause — the named-route one, or the ranked seed's (by="rank")
inline constexpr std::string_view callerHopClause( const ForLensHeaderParts& p, bool compact ) noexcept
{
    return p.callerHopRanked ? presentOnlyClause( p.callerHopPresent, compact, rw::kForCompactRankedCallerHopLegend, rw::kForRankedCallerHopLegend )
                             : presentOnlyClause( p.callerHopPresent, compact, rw::kForCompactCallerHopLegend, rw::kForCallerHopLegend );
}
// mf1-nx: the name-exact route's hop clauses, present-only, in order — the caller hop's (named-route or ranked, above), then the dispatch hop's (wave 4)
inline std::string hopClauses( const ForLensHeaderParts& p, bool compact )
{
    std::string out( callerHopClause( p, compact ) );
    out += presentOnlyClause( p.dispatchHopPresent, compact, rw::kForCompactDispatchHopLegend, rw::kForDispatchHopLegend );
    out += presentOnlyClause( p.selfHookPresent, compact, rw::kForCompactSelfHookLegend, rw::kForSelfHookLegend );
    return out;
}
// FOR-SLOTS (slots=) and OWNER-CTOR-HOP (ctor_l=/ctor_calls=): the two <sigs>-row splices' clauses, then ep-manifest's <ep> clause (epmanifest.h), each present-only, in that order
inline std::string peerRowClauses( const ForLensHeaderParts& p, bool compact )
{
    std::string out( presentOnlyClause( p.initSlotsPresent, compact, rw::kForCompactInitSlotsLegend, rw::kForInitSlotsLegend ) );
    out += presentOnlyClause( p.slotJoinPresent, compact, rw::kForCompactSlotJoinLegend, rw::kForSlotJoinLegend );   // IX1-V2
    out += presentOnlyClause( p.slotNamePresent, compact, rw::kForCompactSlotNameLegend, rw::kForSlotNameLegend );   // fix1 F-4
    out += presentOnlyClause( p.ctorHopPresent, compact, rw::kForCompactCtorHopLegend, rw::kForCtorHopLegend );
    out += presentOnlyClause( p.epPresent, compact, rw::kForCompactEpManifestLegend, rw::kForEpManifestLegend );   // ep-manifest
    out += presentOnlyClause( p.listedPresent, compact, rw::kForCompactListedInLegend, rw::kForListedInLegend );   // manifest-noncode
    return out;
}
inline std::string_view hopsCallsNextLegend( const ForLensHeaderParts& p, bool compact ) noexcept
{
    return presentOnlyClause( p.hopsCallsNextPresent, compact, kForCompactHopsCallsNextClause, kForHopsCallsNextClause );
}
// body-fold: the fold's clause in this dialect, present-only (bodyFoldPresent), right after the slot clause
// WRAPPER-FOLLOW: the follow_of= clause rides right after it, present-only (foldFollowPresent)
inline std::string bodyFoldLegend( const ForLensHeaderParts& p, bool compact )
{
    return std::string( presentOnlyClause( p.bodyFoldPresent, compact, rw::kForCompactBodyFoldLegend, rw::kForBodyFoldLegend ) )
         + std::string( presentOnlyClause( p.foldFollowPresent, compact, rw::kForCompactFoldFollowLegend, rw::kForFoldFollowLegend ) );
}
inline constexpr std::string_view kForCompactLegendTail =
    "; t p= file outside sigs (weaker), t sym= its top symbols (a pointer, not the answer), r= rank (gap = trimmed)";
// R2-AF (round 2, S4): the COMPACT dialect's `<hdr p= of=/>` clause — verbatim, round-2 amendment §R7.
// 96 B, present-only like every clause in this dialect (appendCompactForLegend below).
inline constexpr std::string_view kForCompactLegendHdr =
    "; hdr p= of=: the named file's one same-dir same-stem decl/impl partner, listed first (a lookup)";

// The data notes in their compact spelling: the numbers stay, the sentence goes. Unknown shapes pass
// through VERBATIM — a note this table does not know is never shortened into something it did not say.
// ONE note (" [...]"); compactForNote below splits a channel that carries several.
inline std::string compactOneForNote( std::string_view note )
{
    // " [relevance floor: kept 7 of 40 - the other 33 scored zero…]" → " [floor: kept 7 of 40]"
    if( note.starts_with( " [relevance floor: kept " ) )
    {
        const std::size_t cut = note.find( " - " );
        return cut == std::string_view::npos ? std::string( note ) : " [floor: kept " + std::string( note.substr( 24, cut - 24 ) ) + "]";
    }
    // " [doc mentions: 2 docs discussing 1 top-ranked symbol surfaced; doc_mentions= …]" → " [doc mentions: 2 docs, 1 symbol; doc_mentions=]"
    if( note.starts_with( " [doc mentions: " ) )
    {
        const std::size_t disc = note.find( " discussing " );
        const std::size_t top  = note.find( " top-ranked symbol" );
        if( disc != std::string_view::npos && top != std::string_view::npos && top > disc )
        {
            return " [doc mentions: " + std::string( note.substr( 16, disc - 16 ) ) + ", " + std::string( note.substr( disc + 12, top - disc - 12 ) )
                 + " symbol" + ( note.substr( top + 18 ).starts_with( "s" ) ? "s" : "" ) + "; doc_mentions=]";
        }
        return std::string( note );
    }
    // " [mention anchor: 1 file + 2 symbols named in the task, …; mention_anchored= …]" → " [mention anchor: 1 file + 2 symbols; mention_anchored=]"
    if( note.starts_with( " [mention anchor: " ) )
    {
        const std::size_t cut = note.find( " named in the task" );
        return cut == std::string_view::npos ? std::string( note ) : std::string( note.substr( 0, cut ) ) + "; mention_anchored=]";
    }
    // " [cochange boost: promoted N symbols in M files that historically …]" → " [cochange boost: promoted N symbols in M files]"
    if( note.starts_with( " [cochange boost: promoted " ) )
    {
        const std::size_t cut = note.find( " that " );
        return cut == std::string_view::npos ? std::string( note ) : std::string( note.substr( 0, cut ) ) + "]";
    }
    return std::string( note );
}

// A note channel can carry SEVERAL notes back to back (the doc-mention channel also carries its cap note,
// mention.h absorbCapDisclosure). Each " [...]" is compacted on its own, so a later note is never
// swallowed by an earlier note's rewrite (which keeps only the first note's numbers).
inline std::string compactForNote( std::string_view note )
{
    std::string out;
    while( !note.empty() )
    {
        const std::size_t next = note.find( "] [" );
        const std::size_t len  = next == std::string_view::npos ? note.size() : next + 1;
        out += compactOneForNote( note.substr( 0, len ) );
        note.remove_prefix( len );
    }
    return out;
}

// Does THIS answer's root carry route=? The reading of a code is present-only in both dialects, so both ask the
// question the same way: the ladder's rung (c) may have dropped the attribute (withRouteAttr), and a run the
// router never ran for (no-route, or a verb with no route at all) never had one. Read off the built root open
// rather than re-derived from the route reason, so the clause can only appear beside the attribute it defines.
inline bool forRouteAttrPresent( const ForLensHeaderParts& p, bool withRouteAttr ) noexcept
{
    return withRouteAttr && p.rootOpenStr.find( " route=\"" ) != std::string_view::npos;
}

// …and the THIN question, asked the same way: does this root carry L-W's coverage=? Four sites spelled the
// same find() (two legend appends and two dropped-note selections), which is three chances to change it in two.
inline bool forCoverageAttrPresent( const ForLensHeaderParts& p ) noexcept
{
    return p.confidenceAttrs.find( " coverage=\"" ) != std::string_view::npos;
}

inline void appendCompactForLegend( std::string& h, const ForLensHeaderParts& p, bool withRouteAttr, std::string_view extraNotes )
{
    h += "<!-- ripwire for schema=ripwire.for/v1: ";
    h += kForCompactLegendRoot;
    // PR #215 review: the rows clause is present-only on sc= like every other clause in this dialect. Its 22 B of
    // "sc= scope, id=p::sc::n" rode a bundle whose rows carried no scope at all (a corpus of free functions) —
    // a present-only dialect that defines an attribute nothing printed is the same waste it exists to remove.
    h += p.scPresent ? kForCompactLegendRows : kForCompactLegendRowsNoScope;
    h += kForCompactLegendFacts;
    // the ceiling-droppable trio — rung zero clears confidenceNote/tailLegend/idRouteLegend together and splices the note below
    if( p.idRouteLegend && forRouteAttrPresent( p, withRouteAttr ) )
    {
        h += kForCompactLegendRoute;
    }
    if( !p.confidenceNote.empty() )
    {
        h += kForCompactLegendConfidence;
        if( forCoverageAttrPresent( p ) )
        {
            h += rw::kForCompactCoverageClause;   // L-W: defined where the root carries it, in this dialect's short form
        }
    }
    if( p.compactBundle )
    {
        h += kForCompactLegendHops;
    }
    else if( p.autoBundle )
    {
        h += kForCompactLegendBodies;
    }
    h += hopsCallsNextLegend( p, /*compact=*/true );   // body-fold rider: present-only, right after the hops clause
    h += ownerHopLegend( p, /*compact=*/true );   // owner-hop: present-only, right after the hops clause
    h += bodySlotLegend( p, /*compact=*/true );   // for-body-slot: present-only, after the owner clause
    h += bodyFoldLegend( p, /*compact=*/true );   // body-fold: present-only, after the slot clause
    h += presentOnlyClause( p.memberNamesPresent, /*compact=*/true, rw::kForCompactMemberNamesLegend, rw::kForMemberNamesLegend );   // member-names: after the fold clause
    h += peerRowClauses( p, /*compact=*/true );   // FOR-SLOTS + OWNER-CTOR-HOP: present-only, after mem=
    h += hopClauses( p, /*compact=*/true );  // mf1-nx: present-only, after the fold clause
    // The unconditionally-droppable-free tail of this dialect: five clauses that ride exactly when the bit beside
    // them is set, in THIS order, which is the contract a reader and every byte pin depend on. A table rather than
    // five identical ifs — the list has grown once per lane (hdr, compose, then train 9's lego and layer) and the
    // next one is a row, not another block. hdr is never ceiling-dropped (R2-AF round 2, S4); tail is.
    const struct { bool on; std::string_view clause; } kPresentOnly[] = {
        { p.tailLegend, kForCompactLegendTail },         { p.hdrLegend, kForCompactLegendHdr },
        { p.composePresent, kForCompactLegendCompose },  { p.legoPresent, kForCompactLegendLego },
        { p.layerPresent, kForCompactLegendLayer },
        { p.modScopePresent, rw::kForCompactModScopeClause },   // #60
        { p.endLinePresent, rw::kForCompactEndLineLegend },
        { p.viaPresent, rw::kForCompactViaNameClause },        // FE-B
        { p.splitPresent, rw::kForCompactSplitClause },        // attrib-multidef Q1
    };
    for( const auto& [ on, clause ] : kPresentOnly )
    {
        if( on )
        {
            h += clause;
        }
    }
    // the data notes, numbers kept — see compactForNote
    h += compactForNote( p.adaptiveNote );
    h += compactForNote( p.mentionNote );
    h += compactForNote( p.boostNote );
    h += compactForNote( p.sibliftNote );
    h += compactForNote( p.expandNote );
    h += compactForNote( p.docMentionNote );
    h += compactForNote( p.floorNote );
    h.append( extraNotes );
    h += " -->";
    // M10: at= folded into the SAME trailing comment as root= (one wrapper, not two) — the
    // weak=/dropped_positive=/est_tokens= splice below still targets the LAST comment's closing "-->"
    // (headerStr.rfind), unchanged from before this attribute existed.
    h += rw::forRootRelPathsLegendShort( !p.rootArg.empty(), !p.gitAtAttr.empty() );
}

// T3 — the legend sentence for the terminal-by-default bundle, a named constant so the sigs-budget
// exemption below (the D2 adaptiveNote precedent) subtracts EXACTLY the bytes the legend adds. No "--"
// anywhere in it: it rides inside an XML comment, where "--" is ill-formed (G4). It also defines the
// <bodies>/<calls> disclosure trio, because those attributes now appear on --for's first screen and the
// legend-coverage contract is that every first-screen attribute is defined in the emitting verb's legend.
inline constexpr std::string_view kForAutoBundleLegend =
    "; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section "
    "(bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget "
    "whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The "
    "bodies element discloses the house way: total=requested, shown=printed, capped=1 when they "
    "differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only "
    "when that list is cut";

// The clause defining the degraded reason, spliced into the header ONLY on that path (no "--": it rides in a comment).
inline constexpr std::string_view kForDegradedBundleNote =
    "; reason=degraded: the signature block could not be measured, so no bodies were served and est_tokens is omitted";

// COMPACT conceptual serving — the legend that REPLACES the one above on the subtoken+body route
// (pre-registered: docs/EVALS.md, the T3 route-narrowing round). Same constraints as its sibling: a
// named constant so the sigs-budget exemption subtracts exactly what it adds, and no "--" anywhere,
// because it rides inside an XML comment where "--" is ill-formed (G4) — which is why the two flags it
// mentions are named without their dashes.
//
// IT IS DELIBERATELY TERSE, and the terseness is enforced rather than merely intended: the compact
// surface has ONE byte allowance (kForCompactSurfaceBudgetBytes) that this legend is charged against,
// so every byte spent explaining the section is a byte of edge context the section cannot serve. That
// is the honest shape for a disclosure — it competes with the content it describes instead of riding
// free — and the static_assert below is what stops a future edit from quietly eating the payload.
inline constexpr std::string_view kForCompactBundleLegend =
    "; bundle=compact: conceptual query, so this map ships one-hop EDGE context, no bodies (bodies=0, "
    "reason=compact-route or no_candidates). hops rows are h l=line p=file n=name, and a row's calls "
    "child names its callees (c n= l=; l= comma-joins the lines of same-named callees, shown= counts callees). hops and calls disclose total=requested shown=printed capped=1 "
    "when the BUDGET cut a listing; noedge=N counts ranked symbols with no RESOLVED callee found (never "
    "none exists). For a body: expand=p:n pasted off a row; the auto-bodies flag puts the bodies back";

// One spelling of --for's header, three shapes of it. `withTaskEcho=false` replaces the comment's echo with a
// note pointing at the task= attribute that still holds the verbatim copy — the duplicate goes, nothing else.
// Byte-identical to the pre-ladder header when both flags are true and extraNotes is empty (golden-neutral).
inline std::string forLensHeaderText( const ForLensHeaderParts& p, bool withRouteAttr, bool withTaskEcho,
                                      std::string_view extraNotes )
{
    std::string h;
    h.reserve( 640 + std::max( kForAutoBundleLegend.size(), kForCompactBundleLegend.size() ) + p.rootOpenStr.size() + p.taskNote.size() + p.adaptiveNote.size()
               + p.mentionNote.size() + p.boostNote.size() + p.sibliftNote.size() + p.expandNote.size() + p.docMentionNote.size() + p.floorNote.size()
               + p.confidenceAttrs.size() + p.confidenceNote.size() + p.gitAtAttr.size() + p.mentionDocAttrs.size() + extraNotes.size() );
    h += rootOpenWithSchema( rootOpenWithExtraAttrs( rootOpenWithExtraAttrs( rootOpenWithExtraAttrs( withRouteAttr ? std::string( p.rootOpenStr )
                                                                   : rw::ctxRootOpen( p.task, {}, p.rootArg ),
                                                     p.confidenceAttrs ),
                                                     p.gitAtAttr ),
                                                     p.mentionDocAttrs ),
                             p.compactLegend ? "ripwire.for/v1" : std::string_view() );
    if( p.compactLegend )
    {
        appendCompactForLegend( h, p, withRouteAttr, extraNotes );
        return h;
    }
    h += "<!-- ripwire lens for ";
    if( withTaskEcho ) { h += "\"";  h.append( p.taskNote );  h += "\""; }
    else
    {
        h += "[task_echo: dropped (ceiling) - the verbatim copy is the task= attribute above]";
    }
    // L1 (density audit 2026-08-08): the comment used to append a SCRUBBED copy of the route note here —
    // ~230-260 B saying, on every routed call, exactly what the verbatim route= attribute above already says.
    // The attribute is the surviving copy (verbatim + machine-addressable); the ceiling ladder's rung (c)
    // now truly is "the first rung that costs unique information" (serialize.h climbCeilingLadder).
    h.append( p.adaptiveNote );
    h.append( p.mentionNote );      // B8: present only when the task named something indexed (else "")
    h.append( p.boostNote );        // B3: present only when the co-change prior actually promoted something
    h.append( p.sibliftNote );      // r4: present only when RIPWIRE_SIBLIFT actually promoted a symbol
    h.append( p.expandNote );       // r6: present only when RIPWIRE_EXPAND actually promoted a symbol
    h.append( p.docMentionNote );   // R5: present only when a resolved symbol's mentioning docs surfaced
    h.append( p.floorNote );        // LB-A: present only when the relevance floor shrank the quota (else "")
    h.append( p.confidenceNote );   // ALWAYS present — defines the confidence=/margin_pct= root facts
    if( p.anchor )
    {
        h += " [anchored, EXPERIMENTAL: lexical + graph-expanded rank; honest numbers: on the 80-commit co-change "
             "eval it MATCHES lexical-alone (within 0.3pt) and stays below whole-name BM25 - it adds lexically-"
             "invisible neighbours without hurting, no measured recall lift; see bench/ANSWERQUALITY.md]";
    }
    h += ": reusable building blocks + quality facts for what you're about to touch "
         "(cx=complexity ccx=cognitive in=reuse-count, each absent when 0; churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) "
         "— prefer composing/reusing these; watch the high-churn/high-amp/cloned ones";
    // BOTH readings are present-only (PR #215 review): sc= when a served row carries one, route= when the root
    // carries the attribute. A reading with nothing to define is bytes the bundle could have spent on a row, and
    // it is what made the dropped-legend note name attributes that never rode. ONE decision, shared with the MCP
    // twin and with the exemption ledger below: rw::forIdRouteLegendParts.
    {
        const rw::ForIdRouteLegendParts idRoute =
            rw::forIdRouteLegendParts( p.idRouteLegend, p.scPresent, forRouteAttrPresent( p, withRouteAttr ) );
        h.append( idRoute.sc );
        h.append( idRoute.route );
    }
    // P3 (L7): the r=1 <d> row carries next= (nextverb.h). NOT defined here on purpose: every byte of this header
    // is un-charged by the token ladder, and fornotesbudgetcheck's tight rungs leave it ~0 tokens of headroom
    // (V1 N1) — a 115 B clause blew --token-budget=950 by 29 tokens. The definition lives in --help (--for) and
    // in test/legendcoverage_baseline.txt with this reason; the attribute's value is a pasteable invocation.
    if( p.compactBundle )
    {
        h.append( kForCompactBundleLegend );   // COMPACT: replaces the auto legend on the conceptual route — never both
    }
    else if( p.autoBundle )
    {
        h.append( kForAutoBundleLegend );   // T3: present whenever auto mode is on, whatever the fit outcome — it explains bodies="0" too
    }
    h.append( hopsCallsNextLegend( p, /*compact=*/false ) );   // body-fold rider: present-only, right after the bundle clause
    h.append( ownerHopLegend( p, /*compact=*/false ) );   // owner-hop: present-only, right after the bundle clause
    h.append( bodySlotLegend( p, /*compact=*/false ) );   // for-body-slot: present-only, after the owner clause
    h.append( bodyFoldLegend( p, /*compact=*/false ) );   // body-fold: present-only, after the slot clause
    h.append( presentOnlyClause( p.memberNamesPresent, /*compact=*/false, rw::kForCompactMemberNamesLegend, rw::kForMemberNamesLegend ) );   // member-names
    h.append( peerRowClauses( p, /*compact=*/false ) );   // FOR-SLOTS + OWNER-CTOR-HOP
    h.append( hopClauses( p, /*compact=*/false ) );  // mf1-nx: present-only, after the fold clause
    if( p.tailLegend )
    {
        h.append( rw::kForFileTailLegend );   // deep-tail: defines r= and the <tail> element (sigs-charge-exempt, serialize.h)
    }
    if( p.hdrLegend )
    {
        h.append( rw::kForHdrLegend );   // R2-AF (round 2, S4): present-only, never ceiling-dropped
    }
    if( p.modScopePresent )
    {
        h.append( rw::kForModScopeClause );   // #60: present-only, on the same bit the compact strip reads
    }
    if( p.endLinePresent )
    {
        h.append( rw::kForEndLineLegend );   // e=: present-only, on the same bit the compact strip reads
    }
    if( p.viaPresent )
    {
        h.append( rw::forViaNameClause() );   // FE-B: present-only, on the same bit the compact strip reads
    }
    if( p.splitPresent )
    {
        h.append( rw::kForSplitClause );   // attrib-multidef Q1: likewise
    }
    h.append( extraNotes );
    h += " -->";
    // W3-S item 5 (2026-08-19): the --for lens carries root= on its <ctx> with nothing defining it — the
    // same "an attribute the document never explains" gap the root-relative round closed on eighteen other
    // legends via the shared rw::kRootRelPathsLegend clause (graphlegend.h), missed here because this
    // header is built in main.cpp rather than through a shared emitter. Pasting THAT clause verbatim was
    // tried and reverted: at 159 B it took a --token-budget=800 bundle's est_tokens from inside the ceiling
    // to 811 (+1.4%) and red test/fornotesbudgetcheck.sh — a real "a disclosure has BYTES" trap, on a
    // contract that says est_tokens <= the stated budget in both dialects.
    //
    // Trade-off chosen: a SHORTER spelling for this one call site, not a floor recalibration. Recalibrating
    // the shared budget constants (kMinBytesPerToken / kBudgetHeadroom / kCeilingFirstEntryTolerance,
    // serialize.h) would move every OTHER --for/--pack-task gate pinned against them
    // (bundleidcheck.sh/partitioncheck.sh/estchargecheck.sh among others) for one verb's 21-byte gap — a
    // blast radius wildly out of proportion to the fix. A second wording is normally exactly the kind of
    // echo-site drift kRootRelPathsLegend's own header warns against (it was hoisted OUT of eighteen
    // per-verb copies for that reason) — but --for is the one call site with a MEASURED, hard byte
    // constraint the other eighteen do not carry, and the two dialects (CLI --for, MCP `for`) share this
    // ONE short form, so there are still only two spellings in the whole tool, not nineteen.
    // Measured: 159 B (kRootRelPathsLegend) -> 126 B (kForRootRelPathsLegendShort), saving 33 B. On the
    // --token-budget=800 fixture fornotesbudgetcheck.sh builds: WITHOUT any root= clause, est_tokens=799
    // (1 B of headroom under the 800 ceiling); WITH kRootRelPathsLegend appended, est_tokens=811 (RED, the
    // regression this comment records); WITH the short form below, est_tokens=800 (fits exactly — the
    // clause is now the FIRST byte of headroom this bundle had left, not eleven tokens past it).
    // `on` is p.rootArg's OWN presence, the same convention rootRelPathsLegend(bool) itself uses elsewhere
    // (never re-derived from withRouteAttr or anything else the ceiling ladder decided above).
    // M10: at= folded into the SAME trailing comment as root= (one wrapper, not two) — the
    // weak=/dropped_positive=/est_tokens= splice above still targets the LAST comment's closing "-->"
    // (headerStr.rfind), unchanged from before this attribute existed.
    h += rw::forRootRelPathsLegendShort( !p.rootArg.empty(), !p.gitAtAttr.empty() );
    return h;
}

inline std::string forLensJsonHeader( std::string_view task, const ForLensNotes& notes )
{
    using rw::jsonStr;
    // M10: "at":null (never a fake sha) on multi-root/non-git — same convention as writeTestGateReportJson's
    // own at= sibling in this tool. A root fact, so it rides first, beside task=.
    std::string h = "{\"at\":" + ( notes.at.empty() ? std::string( "null" ) : ( "\"" + notes.at + "\"" ) )
                   + ",\"task\":\"" + jsonStr( task ) + "\"";
    if( !notes.route.empty() )
    {
        h += ",\"route\":\"" + jsonStr( notes.route ) + "\"";
    }
    // the XML twin of these two fields carries task_scrubbed=/route_scrubbed= when the scrub lost bytes; this
    // dialect is the faithful one and says so from its own side (serialize.h ctxRootJsonScrubKeys). Absent on
    // clean input, so no ordinary document moves a byte.
    h += rw::ctxRootJsonScrubKeys( task, notes.route );
    if( !notes.mention.empty() )
    {
        h += ",\"mention\":\"" + jsonStr( notes.mention ) + "\"";
    }
    // §L10b: the XML twin's mention_anchored=. Gated on the COUNT since the cap-disclosure lane — the note
    // above can now carry a cap clause on a run that anchored nothing, and "mention_anchored":0 would be a
    // fabricated zero.
    if( notes.mentionAnchored > 0 )
    {
        h += ",\"mention_anchored\":" + std::to_string( notes.mentionAnchored );
    }
    if( !notes.boost.empty() )
    {
        h += ",\"boost\":\"" + jsonStr( notes.boost ) + "\"";
    }
    if( !notes.siblift.empty() )
    {
        h += ",\"siblift\":\"" + jsonStr( notes.siblift ) + "\"";
    }
    if( !notes.expand.empty() )
    {
        h += ",\"expand\":\"" + jsonStr( notes.expand ) + "\"";
    }
    if( !notes.docMention.empty() )
    {
        h += ",\"doc_mention\":\"" + jsonStr( notes.docMention ) + "\"";
    }
    // §L10b: the XML twin's doc_mentions=, gated on the COUNT for the same reason as mention_anchored above.
    if( notes.docMentions > 0 )
    {
        h += ",\"doc_mentions\":" + std::to_string( notes.docMentions );
    }
    // …and the cap keys, verbatim from CapDisclosure — the XML root's own facts, same names, same order.
    h.append( notes.capJson );
    if( !notes.adaptive.empty() )
    {
        h += ",\"adaptive\":\"" + jsonStr( notes.adaptive ) + "\"";
    }
    // LB-A: the XML twin appends this note to the header comment; the faithful dialect gets its own key.
    if( !notes.floor.empty() )
    {
        h += ",\"relevance_floor\":\"" + jsonStr( notes.floor ) + "\"";
    }
    // ranking-confidence facts — always present (a fact of every ranking, mirroring the XML root attrs).
    h += ",\"confidence\":\"";
    h += notes.confidence;
    h += "\",\"margin_pct\":" + std::to_string( notes.marginPct );
    if( notes.coveragePct >= 0 )
    {
        h += ",\"coverage\":" + std::to_string( notes.coveragePct );   // L-W: the XML root's third ranking fact, same presence rule
    }
    // the adaptive cut's own counts — the abstention round-2 instrumentation described on ForLensNotes.
    // ALWAYS present (a count of zero is a measurement: "nothing scored", never "the field was dropped"),
    // and JSON-only BY DESIGN, which the struct's comment states in full rather than repeating here.
    h += ",\"kept\":" + std::to_string( notes.keptCount );
    h += ",\"scored\":" + std::to_string( notes.scored );
    h += ",\"corpus\":" + std::to_string( notes.corpus );
    if( notes.weak )
    {
        h += ",\"weak\":true";
    }
    return h;
}

// §B1.3: the auto-surfaced field notes ride the rows inside the sigs array; this stanza is their DISCLOSURE
// — `notes_total` counts what the tree matched, `notes_kept` what survived the byte ladder, the same pair
// --pack-task --json reports. Empty unless a NoteIndex exists, so a tree with no .ripwire_notes keeps its
// pre-feature bytes exactly (the L3 inertness contract). notes_degraded= is a SEPARATE, independent splice at
// the call site (below) rather than a third parameter here — `active` gates notes_total/kept, a fully-degraded
// read (every line unparsed) can leave `active` false with nothing to count, and the two facts must not be
// entangled into one signature.
inline std::string forLensNotesStanza( const rw::JsonSigNoteCounts& counts, bool active )
{
    if( !active )
    {
        return {};
    }
    return ",\"notes_total\":" + std::to_string( counts.total ) + ",\"notes_kept\":" + std::to_string( counts.kept );
}

// R1 (terminality round A, verify-wave1) — the CEILING THIS BUNDLE WAS SHAPED AGAINST, in the dialect whose
// whole audience is machines. H9 put budget_tokens= on the XML root and this twin never got it, so a --json
// caller could see a bundle that had plainly been re-shaped (`capped`, a shorter sigs array) and could not
// read WHICH ceiling did it, nor check est_tokens against the number it had itself passed. Present exactly
// when the XML twin's is (an explicit --token-budget), absent otherwise — an attribute on a run where the
// flag was inert would be its own false disclosure — and CHARGED like every other byte here, for the reason
// the XML twin's H9 comment gives at length: a budget disclosure that pushed the bundle past its own budget
// would be the funniest possible way to fail this finding. A free function over emitForLensJson's locals,
// the forLensNotesStanza / forLensJsonTailStanza precedent directly above and below.
inline std::string forLensJsonBudgetStanza( std::size_t tokenBudget )
{
    if( tokenBudget == 0 )
    {
        return {};
    }
    return ",\"budget_tokens\":" + std::to_string( tokenBudget );
}

// #61 (redhat-et/ripwire#61, YogevKr, 2026-09-08) — THE OVER-CEILING PREDICATE for the XML dialect, and the
// SECOND ceiling a `--for` root can name. Written as a free function for the reason its JSON sibling above
// is: runForLens is one of the largest bodies in this file, and the rule this expresses is a contract of its
// own rather than a step in that emitter.
//
// --max-tokens reaches this verb through cli.h's isForDetailBudget carve-out and shapes the BODIES
// (runForLens's detailBodyBudget) — the header, signatures, legend and symbol table are never charged
// against it — so `--for=Q --detail=30 --max-tokens=300` shipped `max_tokens="300"` beside
// `est_tokens="2640"`: a ceiling named on a document 8.8x past it, in silence, while `<bodies capped="1">`
// disclosed the body cut honestly right beside it.
//
// THE PARTIAL APPLICATION STAYS; THE SILENCE DOES NOT. METHODOLOGY §9 #2 — "when a ceiling would cut
// something above the cliff, compress first, move prose into attributes second, and if it still does not
// fit, exceed the ceiling with over_ceiling="1" rather than drop the row that would have terminated the
// search". Thirty small functions totalling ~3.4K tokens, COMPLETE, are the terminating answer; a rung that
// trimmed them to fit 300 tokens would make the tool worse and would still have been perfectly honest. What
// was missing is §9 #6, "a ceiling attribute names the ceiling actually applied": the VERDICT. So this is
// the same rule, the same unit and the same attribute budget_tokens already answers to (packtask.h F2) —
// over_ceiling="1" whenever est_tokens exceeds a ceiling THIS ROOT STATES. The default map has computed the
// identical verdict since §F5 (main.cpp, maxTokensFit.isOverCeiling); this path had no equivalent, which is
// the "as the default map does" the reporter's Expected behavior cites.
//
// CONVERGENCE is unchanged and for the unchanged reason: the attribute and its legend clause only ADD bytes,
// so a document over EITHER ceiling stays over it and the caller's est_tokens fixpoint never oscillates.
// forbudget-soft: the W3FIX ceiling ladder's last rung (ladderFired) went with the hard --token-budget ceiling, and the
// --for callers pass tokenBudget 0 (budget_tokens= names a soft target) — max_tokens= is the ceiling this predicate labels.
// Gate: test/formaxtokenscheck.sh.
inline bool forLensOverCeiling( std::size_t tokenBudget, int maxTokens, bool hasBodyCeiling, std::size_t estTokens ) noexcept
{
    return ( tokenBudget > 0 && estTokens > tokenBudget )
        || ( hasBodyCeiling && maxTokens > 0 && estTokens > std::size_t( maxTokens ) );
}

// PR #135 — THE PRICED ROOT, as a function of the header shape the ceiling ladder chose. Everything runForLens
// splices onto its header after the ladder lives here, in its original order: the late root attributes and
// clauses, the est_tokens= clause, then the est_tokens fixpoint with over_ceiling="1" and the clause defining it.
// It is one function so the ladder can price the header it will EMIT, not the one it builds. The label rides
// whenever est_tokens exceeds budget_tokens (F2), and est_tokens prices markup at 2.50 B/tok while the allowance
// is 2.36 x 1.15 = 2.714 B/tok. So a bundle in that band carried 70 bytes the ladder never saw, and one it had
// fitted within 70 B of the allowance shipped past it with no rung fired: estchargecheck #11 A7, 5 429 B against
// 5 428 B (the sweep beside it reds the same defect on a git-less corpus at 12 of 52 budgets).
// `measured` is ForLensBlockCharge::isMeasured: the direct-emission degrade path gets the splices but no number, because its
// header goes to stdout before the bundle it would describe has been measured.
// The DISCLOSE sink for runForLens's pre-rendered blocks. est_tokens= prices the whole bundle, so ANY block the charge
// buffer could not measure — <sigs> or a sibling (<lego>, <compose>, <routes>) streamed directly and uncharged — leaves
// it unmeasurable, and ForLensRootFinish::measured (this flag) then omits it rather than print a number that left
// those bytes out. The sigs block also drops the auto bodies and the ladder, which key on sigsPreRendered itself.
struct ForLensBlockCharge
{
    enum class DisclosureWhy : std::uint8_t
    {
        SigsUnmeasured,           // <sigs> streams directly: no bundle measurement at all
        SiblingBlockUnmeasured,   // <lego>/<compose>/<routes> streams directly: its bytes are outside the charge
    };
    bool isMeasured = true;
    void disclose( DisclosureWhy ) noexcept   // every reason records the same fact
    {
        isMeasured = false;
    }
};

struct ForLensRootFinish
{
    std::string_view autoAttr, sigsCeilingAttr, capAttrs;                 // root attributes, before the first "><!--"
    bool             weak = false;                                       // weak="1", before the last " -->"
    std::string_view droppedPositiveNote, sigsCeilingNote, capNote;      // clauses, before the last " -->"
    std::string_view sectionsStubNote;   // L2 (round-1 lever B1): kForSectionStubLegend, present only when this run actually stubbed <lego>/<compose>
    // L3 follow-up (CodeRabbit 4053600616): notes.h's ONE marker — the attribute before "><!--" like its
    // siblings above, the reading before " -->" like its siblings below. Absent on a clean read.
    std::string_view notesDegradedAttr, notesDegradedNote;
    bool             measured = false;
    std::string_view estTokensLegend, overCeilingLegend;
    std::size_t      nonHeaderMarkupBytes = 0;                           // every markup byte outside the header, "</ctx>" included
    std::size_t      bodyTokens           = 0;                           // the body-rate sections, already priced
    std::size_t      tokenBudget          = 0;
    int              maxTokens            = 0;
    bool             bodyCeiling          = false;
    // forbudget-soft: the default answer's ranked head passed the runaway guard (SigsCutReport::rowDropCut): over_ceiling="1".
    // Its reading (forRunawayGuardNote) rides the <sigs> clauses (sigsCeilingNote) already — never kOverCeilingLegend, whose
    // est_tokens-versus-a-named-ceiling reading is not what happened.
    bool             guardOver            = false;
};

// PR #215 review: the finished header AND the number it prints, handed back together. finishForLensHeader
// below is this function's header half and stays the name every emit site calls; the ceiling ladder's exact-
// ceiling test needs the OTHER half, because "does this document fit what its root promises" is the question
// `est_tokens <= budget_tokens` asks and nothing else answers it. Computing it a second time beside this
// fixpoint is how the two came to disagree on the RATE in the first place, so there is one fixpoint and two
// readers of it. `estTokens` is the number the document will actually carry — the second-stage value when
// over_ceiling="1" rides, since those bytes are part of the document the number prices.
struct ForLensPricedHeader
{
    std::string header;
    std::size_t estTokens = 0;   // 0 on the unmeasured degrade path (`f.measured` false — no number is printed there)
};

inline ForLensPricedHeader finishForLensHeaderPriced( std::string header, const ForLensRootFinish& f )
{
    // T3: the bundle=auto disclosure attributes, then budget_bytes= (its presence is decided by the sigs render),
    // then the INDEXING-cap attributes (root facts of the RANKING, so on the root est_tokens prices rather than in
    // the ladder's input). All three go in BEFORE est_tokens is computed, so the number measures a header that
    // already carries these bytes exactly. An attribute dropped by an unexpected shape costs nothing a reader can
    // be misled by: the auto section is still disclosed by its own element. See spliceBefore for the boundary.
    spliceBefore( header, "><!--", /*fromEnd=*/false, f.autoAttr );
    spliceBefore( header, "><!--", /*fromEnd=*/false, f.sigsCeilingAttr );
    spliceBefore( header, "><!--", /*fromEnd=*/false, f.capAttrs );
    spliceBefore( header, "><!--", /*fromEnd=*/false, f.notesDegradedAttr );   // L3 follow-up (CodeRabbit 4053600616)

    // R4 + §L2: weak="1" goes in AHEAD of est_tokens, so its 9 bytes are an exact count inside header.size()
    // below rather than bytes of the document the number describing it had not measured (CA4 verifier L2).
    // Absent entirely when the query cleared the threshold — never a fabricated "weak=0".
    spliceBefore( header, " -->", /*fromEnd=*/true, f.weak ? std::string_view( " weak=\"1\"" ) : std::string_view() );

    // A2 dropped_positive="N" (absent at zero, the pr_converged precedent — never a fabricated "0"), then the
    // budget_bytes= clause, whose attribute rides only a trimmed <sigs>, then the cap clause, which DEFINES its
    // attributes by carrying them verbatim (the legendcoveragecheck contract dropped_positive= also uses).
    spliceBefore( header, " -->", /*fromEnd=*/true, f.droppedPositiveNote );
    spliceBefore( header, " -->", /*fromEnd=*/true, f.sigsCeilingNote );
    spliceBefore( header, " -->", /*fromEnd=*/true, f.capNote );
    spliceBefore( header, " -->", /*fromEnd=*/true, f.sectionsStubNote );
    spliceBefore( header, " -->", /*fromEnd=*/true, f.notesDegradedNote );   // L3 follow-up (CodeRabbit 4053600616)
    if( !f.measured )
    {
        return { std::move( header ), 0 };
    }

    // N1: the legend clause defining est_tokens= goes into the LAST comment first, so header.size() below
    // already counts it exactly.
    spliceBefore( header, " -->", /*fromEnd=*/true, f.estTokensLegend );

    // SELF-REFERENCE (the §L2 mechanism generalized): the est_tokens attribute is part of the document est_tokens
    // measures, so its own digit string belongs inside the byte total. Bounded 4-pass fixpoint, same shape and
    // bound as serialize()'s and buildRecall's; the attribute BUILT last is the attribute inserted. On convergence
    // (the `break`, reached in <=2 passes on every shape measured) the number stated is exactly the number the
    // document's own bytes were measured against; on the bound, a residual under one token — never fabricated.
    // EACH KIND OF BYTE AT ITS OWN RATE: markup (header, <sigs>, <lego>, <compose>, <routes>, the mermaid graph
    // block, the tail, a compact <hops>) at kBytesPerTokenDefault, and the --detail / auto bodies at the
    // kBytesPerTokenBody rate chargeSection already charged them at (one rate for both kinds is §H7's defect).
    const auto priceFixpoint = [ & ]( std::size_t markup, std::size_t overBytes )
    {
        std::size_t est = rw::tokensForEmittedBytes( markup + overBytes, rw::kBytesPerTokenDefault ) + f.bodyTokens;
        std::string a   = " est_tokens=\"" + std::to_string( est ) + "\"";
        for( int pass = 0; pass < 4; ++pass )
        {
            const std::size_t next = rw::tokensForEmittedBytes( markup + a.size() + overBytes, rw::kBytesPerTokenDefault ) + f.bodyTokens;
            if( next == est )
            {
                break;
            }
            est = next;
            a   = " est_tokens=\"" + std::to_string( est ) + "\"";
        }
        return std::pair<std::size_t, std::string>{ est, a };
    };
    auto        priced = priceFixpoint( header.size() + f.nonHeaderMarkupBytes, 0 );
    std::string overAttr;

    // F2 (capture-audit verify-wave2 2026-09-05): over_ceiling= is a PROPERTY OF THE EMITTED DOCUMENT, not of a
    // rung — over_ceiling="1" whenever est_tokens exceeds A CEILING THE ROOT NAMES (#61: forLensOverCeiling), on
    // every rung; absent means inside all of them. Decided from the fixpoint because its own 17 bytes are part of
    // the document the number prices, and in two stages because its DEFINITION is header bytes too: splicing the
    // clause unconditionally would charge every budgeted bundle for an attribute it does not carry. Monotone —
    // adding bytes only RAISES est_tokens — so one extra stage is exact and the flag never oscillates. The
    // definition rides the legend of the document that carries the attribute.
    const bool namedCeilingOver = forLensOverCeiling( f.tokenBudget, f.maxTokens, f.bodyCeiling, priced.first );
    if( namedCeilingOver || f.guardOver )
    {
        // each clause rides only where its reading is true: the est_tokens one when that predicate holds; the runaway guard's
        // reading rode the <sigs> clauses already (sigsCeilingNote) — both when both hold
        spliceBefore( header, " -->", /*fromEnd=*/true, namedCeilingOver ? f.overCeilingLegend : std::string_view() );
        overAttr = " over_ceiling=\"1\"";
        priced   = priceFixpoint( header.size() + f.nonHeaderMarkupBytes, overAttr.size() );
    }

    // N1: onto the <ctx> root — the same "><!--" boundary the bundle= attributes above use — where --pack-task /
    // --from-trace / --handoff / --expand put theirs (M11), not inside the comment.
    spliceBefore( header, "><!--", /*fromEnd=*/false, priced.second + overAttr );
    return { std::move( header ), priced.first };
}

inline std::string finishForLensHeader( std::string header, const ForLensRootFinish& f )
{
    return finishForLensHeaderPriced( std::move( header ), f ).header;
}

// DEEP-TAIL d2, JSON dialect — the tail stanza and its explicit-regime fill, as a free function over
// emitForLensJson's locals (the ForLensHeaderParts precedent: that emitter is already carrying the whole envelope
// fixpoint). Default regime: the full row cap (page 0's 40 rows, FOLD C). Explicit regime (forbudget-soft round C,
// reserve first): the tail keeps at least its share — `shareBytes`, what the rows at the target cut left of the bundle
// budget — so rows are added until the stanza reaches it (rw::fileTailShownToFill); a cut tail carries "next".
inline std::string forLensJsonTailStanza( const rw::FileTail& tail, std::size_t tokenBudget, std::size_t shareBytes )
{
    if( tokenBudget == 0 )
    {
        return "," + rw::renderFileTailJson( tail, tail.paths.size() );   // every row computeFileTail collected
    }
    const auto render = [ & ]( std::size_t shown ) { return "," + rw::renderFileTailJson( tail, shown ); };
    return render( rw::fileTailShownToFill( tail, shareBytes, render ) );
}

// One RENDER of the --json bundle (emitForLensJson below).
// ── round C (owner decision 2026-10-14, RESERVE SECTIONS FIRST): the JSON twin's row refill, a free function over
// emitForLensJsonPass' locals (the forLensJsonTailStanza precedent). The tail is funded from the rows at the soft target's cut;
// the rows past the cut then fill what it left of T — never below the cut (rw::forSoftRowDropFill). Re-rendered only when that
// narrows the rows; the first render's redaction count and note tallies are replaced, and a failed re-render keeps the first
// render (and every reading taken from it) whole.
struct ForJsonRefillState   // the first render's outputs, by reference: the refill replaces them together or not at all
{
    std::string&              json;
    rw::SigsCutReport&        cut;
    bool&                     capped;
    std::size_t&              droppedPositive;
    rw::JsonSigNoteCounts&    notes;
    std::vector<rw::NodeId>&  shown;
};
// FIX1 R2 (review rv-forbudget-soft): the JSON tail's SHARE under a soft target — what the rows at the cut leave of the bundle
// budget, and never less than what the retired hard ceiling left it (its allowance, N x kMinBytesPerToken x the first-entry
// tolerance, less the envelope it charged and the rows at the cut): owner decision 2 (a trailing section keeps at least the share
// it had at the same N). One function for the refill's reserve and the final fill, so the two read the same number.
inline std::size_t forLensJsonTailShare( std::size_t tokenBudget, std::size_t bundleBytes, std::size_t fixedBytes, std::size_t cutRowsBytes ) noexcept
{
    const std::size_t softShare    = rw::forSoftSectionsShare( bundleBytes, cutRowsBytes );                                   // T less the rows at the cut
    const std::size_t retiredShare = rw::forSoftSectionsShare( rw::ceilingAllowanceBytes( tokenBudget ), fixedBytes + cutRowsBytes );   // the hard ceiling's
    return softShare > retiredShare ? softShare : retiredShare;
}

struct ForJsonRefillBudgets
{
    std::size_t fixedBytes;     // the envelope the sigs budget charged (header, reserves, counts, notes)
    std::size_t bundleBytes;    // budgetBytesForTokens( N )
    std::size_t sigsTarget;     // the ladder's target (the cut)
    std::size_t firstRowDrop;   // the first render's row budget (T plus the frame)
};
template< class PackSigs >
inline void forLensJsonSoftRefill( const PackSigs& packSigs, const ForLensJsonInputs& in, ForJsonRefillState st, ForJsonRefillBudgets b,
                                   const rw::SigsCutContinuation& cutNext, const std::optional<rw::RedactCounts>& redactBeforeSigs )
{
    const std::size_t  cutRows  = st.json.size() - std::min( st.json.size(), st.cut.pastTargetBytes );
    // the tail at its RESERVE: its share, capped at the head-scoped tail's whole stanza (the same at every N; the XML twin's
    // rule) — not its filled bytes nor the cut-scoped tail's size, both of which step with N: rows stay monotone in N
    const std::size_t  tailBytes = std::min( forLensJsonTailShare( in.tokenBudget, b.bundleBytes, b.fixedBytes, cutRows ),
                                             forLensJsonTailStanza( *in.fileTail, 0, 0 ).size() );
    const std::size_t  rowDrop   = rw::forSoftRowDropFill( b.bundleBytes, tailBytes );
    if( rowDrop >= b.firstRowDrop )
    {
        return;
    }
    const std::string                     firstJson = st.json;
    const rw::SigsCutReport               firstCut  = st.cut;
    const bool                            firstCap  = st.capped;
    const std::size_t                     firstDrop = st.droppedPositive;
    const rw::JsonSigNoteCounts           firstNote = st.notes;
    const std::vector<rw::NodeId>         firstIds  = st.shown;
    const std::optional<rw::RedactCounts> redactFirst = in.redact != nullptr ? std::optional<rw::RedactCounts>( *in.redact ) : std::nullopt;
    if( redactBeforeSigs )
    {
        *in.redact = *redactBeforeSigs;
    }
    st.notes                   = rw::JsonSigNoteCounts {};
    st.cut                     = rw::SigsCutReport {};
    st.cut.continuationRequest = &cutNext;
    st.cut.rowDropBudgetBytes  = rowDrop;
    rw::MemoryStream refillStream;
    std::FILE* const rm = rw::openChargeStream( refillStream );
    if( rm != nullptr )
    {
        packSigs( rm, b.sigsTarget, &st.capped, &st.droppedPositive, &st.shown, &st.cut );
    }
    const rw::MemoryStreamBytes refill = rm != nullptr ? refillStream.finish() : rw::MemoryStreamBytes {};
    if( rm != nullptr && refill.isWhole )
    {
        st.json.assign( refill.bytes );
        return;
    }
    st.json = firstJson;  st.cut = firstCut;  st.capped = firstCap;  st.droppedPositive = firstDrop;  st.notes = firstNote;  st.shown = firstIds;
    if( redactFirst )
    {
        *in.redact = *redactFirst;
    }
}

inline int emitForLensJsonPass( std::FILE* out, const std::string& header, const ForLensJsonInputs& in )
{
    using namespace rw;

    // the SAME budget arithmetic the XML bundle runs: default kForPayloadBudgetBytes, an explicit
    // --token-budget wins, and the envelope's own bytes are charged before the sigs budget.
    //
    // T3 disclosure (test/fordisclosurecheck.sh #3): this dialect renders no bodies by design — the XML
    // sibling's auto <bodies> section stays XML-only — and per the B1.4 rule ("0 must mean genuinely none,
    // not not-computed-this-run") it has to SAY so, or a reader cannot tell "no bodies here" from "bodies
    // ride the other dialect". One always-present envelope key names the serving posture, the same
    // vocabulary the XML root's bundle= attribute uses ("auto" = bodies inline; "sigs" = signatures only).
    constexpr std::string_view kJsonBundleSigsKey = ",\"bundle\":\"sigs\"";   // 16 B, charged below
    //
    // §C1 (capture-audit-4) — this was 40, and the text it covers is `,"capped":false` (15) +
    // `,"est_tokens":` (14) + the digits + `,"sigs":` (8) + `}` (1) = 38 fixed (54 with the 16 B bundle
    // key above). So 40 reserved room for a
    // TWO-digit est_tokens and under-reserved from five digits up — which is every real bundle. The two
    // halves are now named separately because they are two different jobs: the RESERVATION below must be an
    // upper bound (it is subtracted from the budget before the sigs are built), while the CHARGE further
    // down is measured exactly from the bytes that get written. Conflating them is what let a single
    // constant be wrong for one job while looking right for the other.
    //
    // Ten digits is 9 999 999 999 tokens — a ~36 GB bundle. The bound is stated rather than computed so the
    // reservation stays a compile-time constant, as its two sibling stanzas below already are.
    constexpr std::size_t kJsonEnvelopeFixedBytes = 38 + kJsonBundleSigsKey.size();
    constexpr std::size_t kJsonEnvelopeDigitsMax  = 10;
    constexpr std::size_t kJsonEnvelopeBytes      = kJsonEnvelopeFixedBytes + kJsonEnvelopeDigitsMax;   // 64, the RESERVATION
    // §B1.3: the notes stanza `,"notes_total":N,"notes_kept":M` is charged too — but ONLY when a NoteIndex
    // exists, so a tree with no .ripwire_notes keeps its budget arithmetic (and therefore its bytes) exactly
    // as before. That is the L3 inertness contract, not a rounding convenience.
    constexpr std::size_t kJsonNotesStanzaBytes = 40;
    // §B1.4: `,"lego_total":N,"compose_total":N,"routes_total":N` — UNLIKE the notes stanza, these three keys
    // are always present (never conditional), because the whole point is that 0 must mean "genuinely none
    // on this surface", not "not computed this run" — reserved generously (each count is realistically
    // 0..a few hundred, well under 7 digits) rather than measured exactly at charge time.
    constexpr std::size_t kJsonSurfaceCountsBytes = 96;
    const std::size_t bundleBudget = in.tokenBudget > 0 ? budgetBytesForTokens( in.tokenBudget )
                                                        : kForPayloadBudgetBytes;
    const std::size_t fixedBytes = header.size() - std::min( header.size(), rw::forZeroNoteBytes( header ) )   // lean-answers: exempt
                                  + kJsonEnvelopeBytes + kJsonSurfaceCountsBytes
                                  + ( in.noteIndex ? kJsonNotesStanzaBytes : 0 );
    // forbudget-soft: the XML twin's two budgets (forSigsBudgets): the default target + the runaway guard, or a soft target
    // over the rows. One dialect here, so the soft tier's header is this one.
    const ForSigsBudgets sigsBudgets = forSigsBudgets( in.tokenBudget > 0 ? bundleBudget : 0u, fixedBytes, fixedBytes, /*tierAtDefault=*/false );   // no bodies ride here
    const std::size_t    sigsBudget  = sigsBudgets.target;
    // knob-honesty-068: the cut's continuation — exempt in every regime now (the XML twin's rule: no byte promise to pay into)
    const rw::SigsCutContinuation cutNext{ in.task, in.packTopN, in.rankFlags, fixedBytes, /*json=*/true,
                                           /*pasteHandle=*/true };

    const JsonSigLens lens{ /*metrics=*/true, in.fanIn, in.impure, in.churnPerFile, in.cloneMember,
                            in.tested, in.amp, /*rankAdaptivePayload=*/true, in.noteIndex,
                            /*endLines=*/rw::endLinesFitCeiling( in.tokenBudget, /*bodyCeiling=*/false ),   // serialize.h
                            in.docsAfterCode, in.headRoundRobin };
    JsonSigNoteCounts noteCounts;
    const auto packSigs = [ & ]( std::FILE* dst, std::size_t budget, bool* outCapped, std::size_t* outDroppedPositive,
                                 std::vector<rw::NodeId>* outShownIds, rw::SigsCutReport* outCut )
    { packSignaturesJson( dst, in.ing, in.rank, in.topN, lens, in.redact, in.packBudgetBytes, budget, outCapped, &noteCounts,
                          in.rootArg, /*hasRelevanceFloor=*/true,        // LB-A: same admission rule as the XML twin (R-R: root-relative p/id)
                          outDroppedPositive,                            // A2: exact count, see droppedPositiveCount (serialize.h)
                          outShownIds,                                   // lane 2: the emitted rows' ids — the tail excludes these files
                          outCut ); };                                   // cut-fix lane A: the XML tag's shown/total/docs_dropped;
                                                                         //   knob-honesty-068: carries cutNext IN ("sigs_next")

    // §B1.4: built once, used on both the degrade path below and the normal return — these three are plain
    // size_t values already computed by the caller (no rendering, no redaction seam), so unlike est_tokens
    // there is no "cannot compute it here" case that would justify omitting them on the degrade path too.
    // H14 (capture-audit 2026-09-04): the three counts, and the DECLARATION of what they count. The XML
    // form carries <compose>/<field> rows, <d>/<doc> doc-mention rows and a <routes> block; this dialect
    // has always carried their COUNTS and none of their rows, under a --help sentence promising the "SAME
    // content" — so `compose_total:10` beside no compose array read as a bug or as an empty result, and an
    // agent using --json to pick a type to reuse got the number 10 and nothing to reuse. Emitting the rows
    // is registered as follow-up work; the honesty half lands now, in the shape the lens itself proposed:
    // the sections this dialect does not serve are NAMED on the root, so a reader knows to ask the XML form
    // for them rather than concluding they are empty. Gate: test/mcpattrparitycheck.sh's --for --json arm,
    // which fails both on an undeclared drop AND on a name here that IS served.
    const std::string surfaceCountsStanza = ",\"lego_total\":" + std::to_string( in.legoTotal )
                                           + ",\"compose_total\":" + std::to_string( in.composeTotal )
                                           + ",\"routes_total\":" + std::to_string( in.routesTotal )
                                           + ",\"lens\":\"compose,lego,routes,docs\"";

    // DEEP-TAIL d2, JSON dialect: always-present (B1.4: a total of 0 must mean genuinely none). Default
    // row cap here (the degrade path below needs a stanza before any budget is knowable); the normal path
    // re-fits it after the sigs render (forLensJsonTailStanza above) — residual-funded, sigs untouched:
    // the reservation feeding sigsBudget above deliberately does NOT include these bytes.
    std::string tailStanza = "," + renderFileTailJson( *in.fileTail, in.fileTail->paths.size() );

    bool        sigsCapped         = false;   // the LADDER's verdict: decides the budget_bytes= stanza
    rw::SigsCutReport sigsCut;               // cut-fix lane A: what the array cut (gate or ladder) — "capped" and the sigs_* keys
    sigsCut.continuationRequest = &cutNext;  // knob-honesty-068: IN — "sigs_next" / "sigs_next_offset" on a capped array
    sigsCut.rowDropBudgetBytes  = sigsBudgets.rowDrop;   // forbudget-soft: IN — the guard / the soft target's rows
    sigsCut.pastTargetDisclosed = in.tokenBudget == 0;
    std::size_t sigsDroppedPositive = 0;   // A2: set only by the memstream-buffered render below (nullptr on the ENOMEM degrade path)
    std::vector<rw::NodeId> jsonShownIds;   // lane 2: the sigs rows actually emitted (the XML twin's shownSigIds)
    std::string sigsJson;
    {
        rw::MemoryStream sigsStream;
        bool             isSigsBuffered = false;
        // the buffered render redacts into the run's tally; a fallback that renders the rows again must not count them twice
        const std::optional<rw::RedactCounts> redactBeforeSigs = in.redact != nullptr ? std::optional<rw::RedactCounts>( *in.redact ) : std::nullopt;
        if( std::FILE* const jm = rw::openChargeStream( sigsStream ) )
        {
            packSigs( jm, sigsBudget, &sigsCapped, &sigsDroppedPositive, &jsonShownIds, &sigsCut );
            const rw::MemoryStreamBytes block = sigsStream.finish();   // a write lost inside the block is not a whole block
            isSigsBuffered = block.isWhole;
            if( isSigsBuffered )
            {
                sigsJson.assign( block.bytes );
            }
        }
        // round C (RESERVE SECTIONS FIRST, the XML twin's rule): the rows past the soft target's cut fill what the tail left of T
        if( isSigsBuffered && in.tokenBudget > 0 && sigsCut.pastTarget > 0 )
        {
            forLensJsonSoftRefill( packSigs, in, ForJsonRefillState{ sigsJson, sigsCut, sigsCapped, sigsDroppedPositive, noteCounts, jsonShownIds },
                                   ForJsonRefillBudgets{ fixedBytes, bundleBudget, sigsBudget, sigsBudgets.rowDrop }, cutNext, redactBeforeSigs );
        }
        ForLensBlockCharge sigsCharge;   // the sink: an unmeasured block takes the omitting path below
        if( !isSigsBuffered )
        {
            DISCLOSE( sigsCharge, ForLensBlockCharge::DisclosureWhy::SigsUnmeasured,
                      "main: open_memstream failed (or its buffer lost a write) for the --for --json sigs block — emitting unbudgeted, est_tokens omitted" );
        }
        if( !sigsCharge.isMeasured )
        {
            // ENOMEM-class, at the open or inside the buffer: emit unbudgeted rather than nothing, and report no
            // est_tokens/capped at all — a number this path cannot compute must never be fabricated.
            if( redactBeforeSigs )
            {
                *in.redact = *redactBeforeSigs;   // the rows below are the ones the summary counts
            }
            std::fputs( header.c_str(), out );
            std::fwrite( kJsonBundleSigsKey.data(), 1, kJsonBundleSigsKey.size(), out );   // the posture disclosure survives the degrade (a plain constant — nothing here can fail to compute it)
            std::fwrite( surfaceCountsStanza.data(), 1, surfaceCountsStanza.size(), out );
            std::fwrite( tailStanza.data(), 1, tailStanza.size(), out );                   // the tail survives too (plain strings, nothing to fail)
            std::fputs( ",\"sigs\":", out );
            packSigs( out, 0, nullptr, nullptr, nullptr, nullptr );
            std::fputs( "}", out );
            return 0;
        }
    }

    std::string notesStanza = forLensNotesStanza( noteCounts, in.noteIndex != nullptr );
    // L3 follow-up (CodeRabbit 4053600616): independent of the stanza above (see its own comment) — absent on
    // a clean read.
    if( in.notesDegraded )
    {
        notesStanza += rw::notes::kNotesDegradedJsonKey;
    }
    // A2 (survey card, 2026-09-03) — the JSON twin of the XML root's dropped_positive= attribute: emitted ONLY
    // when nonzero (the pr_converged precedent, src/prconverge.h), so the overwhelming no-drop path pays 0
    // bytes here exactly as the ENOMEM degrade path above does (sigsDroppedPositive stays 0, never set).
    const std::string droppedPositiveStanza = sigsDroppedPositive > 0
        ? ",\"dropped_positive\":" + std::to_string( sigsDroppedPositive )
        : std::string();
    // cut-fix lane A — the XML <sigs shown= total= capped="1" docs_dropped=> in this dialect: the array cannot carry keys, so
    // they ride the root beside "capped" (the lego_total/compose_total precedent for a section's counts). Present only when
    // the XML twin carries the attribute; their bytes were reserved inside the array's own budget (packSignaturesJson).
    std::string sigsCutStanza;
    if( sigsCut.isCapped )
    {
        sigsCutStanza += ",\"sigs_shown\":" + std::to_string( sigsCut.shown ) + ",\"sigs_total\":" + std::to_string( sigsCut.total );
        if( rw::sigsCutHasNextOffset( sigsCut ) )   // knob-honesty-068: the resume index, then the call serving the cut rows
        {
            sigsCutStanza += ",\"sigs_next_offset\":" + std::to_string( sigsCut.lastShownRank );
        }
        sigsCutStanza += rw::nextFieldJson( sigsCut.next, "sigs_next" );
    }
    if( sigsCut.pastTargetDisclosed && sigsCut.pastTarget > 0 )   // forbudget-soft: the XML tag's past_target=
    {
        sigsCutStanza += ",\"sigs_past_target\":" + std::to_string( sigsCut.pastTarget );
    }
    if( sigsCut.docsDropped > 0 )
    {
        sigsCutStanza += ",\"docs_dropped\":" + std::to_string( sigsCut.docsDropped );
    }
    if( sigsCut.docsAfterCode > 0 )   // the XML tag's docs_after_code= (the reorder's disclosure; uncharged, like the XML attribute)
    {
        sigsCutStanza += ",\"docs_after_code\":" + std::to_string( sigsCut.docsAfterCode );
    }
    if( sigsCut.filesFirst > 0 )   // the XML tag's files_first= (the head round-robin's disclosure; uncharged likewise)
    {
        sigsCutStanza += ",\"files_first\":" + std::to_string( sigsCut.filesFirst );
    }
    const bool sigsCappedKey = sigsCut.isCapped;   // "capped": the XML tag's capped="1" (the ladder's verdict OR a gate cut)

    // §C1 + §C2 — the CHARGE, measured from the bytes this function is about to write rather than from the
    // reservation's upper bound. Two members were wrong:
    //   • the envelope was charged at the flat reservation (40) instead of its real width, which depends on
    //     `capped`'s spelling (`false` is one byte wider than `true`) and on est_tokens' own digit count;
    //   • `,"over_ceiling":true` was WRITTEN to `out` and left OUT of bundleBytes, so est_tokens did not
    //     charge the key describing the fact that est_tokens had blown its ceiling. That is §H7's
    //     self-reference shape at the one place it is most misleading.
    //
    // est_tokens counting its own digits is a fixed point, so it is SOLVED rather than approximated: start
    // with no digits, re-measure, repeat. Each pass can only widen the document, and a wider document can
    // only keep or grow the digit count, so the iteration is monotone and terminates — three passes cover
    // every value below 10^10 (a 10-digit est_tokens would need a ~36 GB bundle). The over_ceiling decision
    // rides the same fixed point in the safe direction: the key is emitted only when the document is already
    // over, and adding its 20 bytes can only keep it over, never bring it back under.
    const std::size_t cappedClauseBytes = sigsCappedKey ? 14u : 15u;   // ,"capped":true / ,"capped":false
    const std::size_t envelopeTextBytes = cappedClauseBytes + 14u + 8u + 1u + kJsonBundleSigsKey.size();   // + ,"est_tokens": + ,"sigs": + } + ,"bundle":"sigs"
    // forbudget-soft: the one over-ceiling this dialect can carry is the runaway guard's (a soft target is never "over")
    const bool        guardOver         = sigsCut.rowDropCut && in.tokenBudget == 0;

    const std::string budgetStanza      = forLensJsonBudgetStanza( in.tokenBudget );   // R1
    // The XML root's budget_bytes= twin (runForLens, below its own long note): the DEFAULT byte ceiling,
    // named on a bundle the ladder actually cut. budgetStanza directly above names the caller's own
    // --token-budget and rides only when one was passed; this rides only when one was NOT, so the two are
    // exclusive and a trimmed bundle always names exactly one ceiling. Zero bytes when nothing was cut
    // (the droppedPositiveStanza shape directly above — §9 #6 with the pr_converged economy). The R1
    // charging rule applies unchanged: these bytes are charged, never exempt.
    const std::string sigsCeilingStanza = ( sigsCapped && in.tokenBudget == 0 )
                                            ? ",\"budget_bytes\":" + std::to_string( kForPayloadBudgetBytes )
                                            : std::string();

    // DEEP-TAIL (FOLD C: page 0 of the file page), the explicit-regime fill (forLensJsonTailStanza above): reserve first — funded
    // from what the rows AT THE CUT left of the bundle budget (the same share the refill above priced the rows against)
    // lane 2: the rank rows exclude the files of the rows emitted (after a refill: the rows it kept — the XML twin's rule)
    const std::size_t  jsonCutRows = sigsJson.size() - std::min( sigsJson.size(), sigsCut.pastTargetBytes );
    const rw::FileTail jsonTail    = rw::computeFileTail( in.ing, in.rank, *in.evidence, jsonShownIds, in.rootArg, in.task );
    tailStanza = forLensJsonTailStanza( jsonTail, in.tokenBudget, forLensJsonTailShare( in.tokenBudget, bundleBudget, fixedBytes, jsonCutRows ) );
    const std::size_t bundleBytesBase   = header.size() + sigsJson.size() + notesStanza.size()
                                        + surfaceCountsStanza.size() + tailStanza.size() + envelopeTextBytes
                                        + droppedPositiveStanza.size()   // A2: 0 bytes on the (overwhelming) no-drop path
                                        + sigsCutStanza.size()           // cut-fix lane A: 0 bytes when nothing was cut
                                        + budgetStanza.size()            // R1: 0 bytes without an explicit --token-budget
                                        + sigsCeilingStanza.size();      // 0 bytes when the ladder did not fire

    std::size_t estTokens   = 0;
    std::size_t bundleBytes = bundleBytesBase;
    for( int solvePass = 0; solvePass < 4; ++solvePass )
    {
        const std::size_t digits    = std::to_string( estTokens ).size() - ( estTokens == 0 ? 1 : 0 );
        const std::size_t baseBytes = bundleBytesBase + digits;
        // R1: the same predicate on the same pair the post-loop emission reads — when isOver is false,
        // withKey == baseBytes and baseTokens == the settled estTokens, so the reservation and the key can
        // never disagree; when it is true the 20 bytes only make the document more over, never less.
        const bool        isOver    = guardOver;
        const std::size_t withKey   = baseBytes + ( isOver ? 20u : 0u );   // ,"over_ceiling":true
        const std::size_t nextTokens = std::size_t( double( withKey ) / kBytesPerTokenDefault + 0.5 );
        bundleBytes = withKey;
        if( nextTokens == estTokens )
        {
            break;
        }
        estTokens = nextTokens;
    }
    ASSUME( bundleBytes >= bundleBytesBase );
    // W3FIX H2 — the JSON sibling of the XML header's over_ceiling note. The two dialects charge the SAME
    // header bytes to the SAME budget, so they must also agree about the case where that charge cannot make the
    // document fit: the envelope's own verbatim task echo is user-length, and past some task length no sigs
    // trim can bring the bundle under an explicit --token-budget's stated ceiling. Absent ⇒ within the ceiling
    // (the silence-means-nothing-happened convention every other key here uses), never "not measured".
    // §C2: the SAME verdict the charge above solved for — read from the solved bundleBytes so the key that is
    // written and the bytes that were charged can never disagree (they used to be two separate comparisons,
    // one of which did not count the key it was deciding to emit).
    const std::string overCeiling = guardOver ? std::string( ",\"over_ceiling\":true" ) : std::string();
    ASSUME( overCeiling.size() == 0 || overCeiling.size() == 20 );   // the 20 the charge above reserved for it
    std::fputs( header.c_str(), out );
    std::fwrite( kJsonBundleSigsKey.data(), 1, kJsonBundleSigsKey.size(), out );
    std::fwrite( surfaceCountsStanza.data(), 1, surfaceCountsStanza.size(), out );
    std::fwrite( tailStanza.data(), 1, tailStanza.size(), out );
    std::fwrite( notesStanza.data(), 1, notesStanza.size(), out );
    std::fwrite( droppedPositiveStanza.data(), 1, droppedPositiveStanza.size(), out );   // A2
    std::fwrite( sigsCutStanza.data(), 1, sigsCutStanza.size(), out );                   // cut-fix lane A: shown/total/docs_dropped
    std::fwrite( budgetStanza.data(), 1, budgetStanza.size(), out );                     // R1: beside the label it is compared against
    std::fwrite( sigsCeilingStanza.data(), 1, sigsCeilingStanza.size(), out );           // the ceiling the ladder applied, when it fired
    std::fwrite( overCeiling.data(), 1, overCeiling.size(), out );
    rw::emitTo( out, ",\"capped\":{},\"est_tokens\":{},\"sigs\":", sigsCappedKey ? "true" : "false", estTokens );
    std::fwrite( sigsJson.data(), 1, sigsJson.size(), out );
    std::fputs( "}", out );
    return 0;
}

// The --json bundle: one render (forbudget-soft: no charged "sigs_next" to pay for, so no payment-mode re-renders).
inline int emitForLensJson( std::FILE* out, const std::string& header, const ForLensJsonInputs& in )
{
    return emitForLensJsonPass( out, header, in );
}

// ── T3: the terminal-by-default auto <bodies> section (pre-registered: docs/EVALS.md §4) ─────────────────
// The single biggest measured non-terminal chain is map-then-read: the agent runs --for, then opens the
// file the map named. The terminal bundle that already served bodies (--pack-task) went uncalled for a
// month, so the DEFAULT gets richer instead: the top-ranked symbols' FULL bodies ride inline after the
// signatures, assembled by the SAME packBodies walk --pack-task uses (rank-first, skip-whole with a visible
// marker, disclosed shown=/total=/capped=), candidates capped at the pack-task cap so the shapes converge.
// Whole-body-or-not-at-all: truncateOversizedFirst=false, so a rank-1 def larger than the whole body budget
// is DROPPED and disclosed, never cut mid-def.
//
// BUDGET: an explicit --token-budget is a hard ceiling — the bodies get only what the rendered bundle
// genuinely left under it (`committedBytes`; the sigs/lego/compose/routes/graph bytes are computed exactly
// as before — auto mode never shrinks them). A ceiling the signature bundle already exhausted serves no
// body and STILL discloses — as the root attribute alone (bodies="0" reason="budget"; the legend and the
// empty <bodies> shell are dropped there, because only the attribute has reserved bytes at a spent
// ceiling — see the leftBytes==0 branch below). The registration promises the attribute for "no body fits
// the remaining budget" (docs/EVALS.md §4 T3) and there is no leftover-budget value that licenses
// silence. The exhausted branch used to turn the whole surface off silently;
// the 2026-08-22 Lane-AA transcript mine caught it in the wild on 5 of 26 real --for calls (a
// sphinx-sized corpus exhausts a 4000-token allowance with signatures alone, and est_tokens' mid-band
// rate reads BELOW the stated budget while the conservative byte allowance is spent — so the output
// looked both under budget and undisclosed). Gate: test/fordisclosurecheck.sh. WITHOUT an
// explicit budget, the default bundle gains the fixed kForAutoBodyBudgetBytes allowance on top of
// kForPayloadBudgetBytes — the per-call cost the T3 registration's guard covers, disclosed through
// est_tokens, which charges these bytes at the body rate. Every input is deterministic (ranked surface,
// rendered byte counts, constants), so body inclusion is a pure function of (corpus, query, budget).
//
// DEGRADE: a chargeSection memstream failure keeps the OLD behavior — surfaceOff, no bundle= attribute for
// that run (an est_tokens that cannot see the section must not describe it), with the alert on stderr.
// A free function over runForLens' locals (the ForLensHeaderParts precedent) — runForLens is already one of
// the largest functions in this file, and the decision reads better as one value than as inline branches.
struct ForAutoBodiesResult
{
    rw::ChargedSection section;             // rendered auto <bodies> bytes; empty when nothing is emitted
    std::string        attr;                // the <ctx> root disclosure; empty ⇒ no attribute (surface off / degrade)
    bool               surfaceOff = false;  // true ⇒ the caller rebuilds the header WITHOUT the bundle=auto legend
    bool               hopsCutMarker = false;   // forbudget-soft: a soft target left no row room for the compact <hops>: the
                                                //   counted marker (shown="0" … next=) is served and its present-only clause rides.
                                                //   The bundle legend always stays (a soft target never sheds the header); this
                                                //   replaced legendOff, the hard ceiling's attribute-only shape (fordisclosurecheck #2).
    // THE est_tokens SPLIT, filled by buildForEnrichment: exactly one of these is non-zero, because a
    // section is either markup (compact <hops>: summed with the rest of the markup and rounded ONCE) or
    // body text (T3 <bodies>: charged at the body rate, which is why the sum splits by kind at all).
    std::size_t        markupBytes = 0;
    std::size_t        bodyTokens  = 0;
};

// ── ANCHOR-ONLY: the allowance serves the anchor's OWN body, or none (docs/EVALS.md, T3 substitution round) ──
//
// Is `sid` the definition the route's `anchors:` clause names? Both halves are load-bearing. NAME alone is
// not enough, and that is the whole finding of the round this implements: over the standing 12-query
// symbol-lookup set, 11 of 19 served body blocks — 43.9% of all served body BYTES — were some other symbol,
// and the substitutes are overwhelmingly SAME-NAMED things in other files (a doc section, a `types.d.ts`
// one-line stub, a re-export shim, a changelog entry that merely mentions the class). FILE alone is not
// enough either: an unrelated symbol in the anchor's own file is not what the query asked for.
//
// The file matched is NameAnchor::fileId — where the name is DEFINED, which is exactly the definition
// routeAnchorEvidence prints the path of. So the rule follows the header's own disclosed choice rather
// than inventing a second one; when a name has several definitions the reason already says so with its
// "+N".
//
// WHICH definition that is, is decided by lexical.h's noteWholeNameDef, and this narrowing is the reason
// the answer matters. It was "the first in NodeId order", i.e. path order, and on a header-heavy C++ tree
// that is a forward declaration — so this function faithfully restricted the bodies to the DECLARATION's
// file, filtered out the definition the ranking had just put at p=1, and served the caller the text of
// `class X;`. Since 2026-08-25 the claim goes to the first BODY-CARRYING definition, and the two halves of
// a name-exact bundle finally name the same symbol. Nothing here changed to achieve that: the narrowing
// was never the defect, the choice it narrows TO was.
bool isRouteAnchorSymbol( const rw::IngestResult& ing, rw::NodeId sid, const std::vector<rw::RouteAnchorDef>& anchorDefs )
{
    const rw::Symbol& s     = ing.symbols[sid];
    const std::string lower = rw::routeLower( s.name );
    // An Elixir callable is indexed as `name/N` and anchored by its arity-less spelling too (lexical.h
    // noteWholeNameDef registers both), so the definition the anchor names IS the `name/N` row: without this
    // second spelling the anchor resolved to the right file and then filtered its own definition out of the
    // body head, and `--for=generate_app` served bodies="0" reason="no_candidates" (PR #81 review item 5,
    // test/elixirnamearitycheck.sh arm D). Empty for every other language: one comparison, as before.
    const std::string lowerBase = ( s.lang == rw::Lang::Elixir && rw::elixirBaseName( s.name ).size() != s.name.size() )
                                ? rw::routeLower( rw::elixirBaseName( s.name ) ) : std::string{};
    for( const rw::RouteAnchorDef& a : anchorDefs )
    {
        if( a.fileId == s.fileId && ( a.lowerName == lower || ( !lowerBase.empty() && a.lowerName == lowerBase ) ) )
        {
            return true;
        }
    }
    return false;
}

// Narrow a ranked auto-body candidate head to the route's anchor. Whatever this drops cannot be served "in
// the anchor's place", because there is no place: if the anchor's own body does not fit, the caller's budget
// branch renders the honest zero it already renders — `bodies="0" reason="budget"` plus the per-item
// over-budget comment naming what was dropped. That is strictly more informative than a smaller namesake's
// body, which reads like an answer and is not one.
//
// Since the T3 body-budget round this narrowing also decides the RATE the surviving body is funded at:
// when it leaves exactly one candidate, the caller raises the allowance to kForAnchorBodyBudgetBytes (the
// anchor-resolved allowance, serialize.h). So this function no longer only chooses WHICH body may be
// served — collapsing the set to one is itself the signal that the tool is certain, and the caller reads
// it as such. It still never widens anything by itself, and the honest zero above is unchanged: it now
// arrives at a higher ceiling.
//
// A NO-OP when `anchorDefs` is empty, and it must stay one. Two different routes arrive that way and both
// keep the rank-first walk: a subtoken+body (conceptual) query, which nothing anchored; and a camel/snake
// query whose token names no symbol at all, which the route's own reason already marks `syntax`. There is no
// anchor definition to restrict TO in either case, and restricting to an empty set would turn "no substitute"
// into "no bodies, ever" on a class this round never measured.
void restrictBodiesToRouteAnchor( const rw::IngestResult& ing, std::vector<rw::NodeId>& candidateIds,
                                  const std::vector<rw::RouteAnchorDef>& anchorDefs )
{
    if( anchorDefs.empty() )
    {
        return;
    }
    std::vector<rw::NodeId> anchorOnly;
    for( rw::NodeId sid : candidateIds )
    {
        if( isRouteAnchorSymbol( ing, sid, anchorDefs ) )
        {
            anchorOnly.push_back( sid );
        }
    }
    candidateIds = std::move( anchorOnly );
}

// knob-honesty-068: the flags that change WHICH rows the lens ranks (and so total=/the order <sigs> cuts), pre-spelled for the
// capped block's continuation (serialize.h SigsCutContinuation::rankFlags) — the re-run must rank the same list.
inline std::string forRankShapingFlags( const rw::Config& cfg )
{
    std::string f;
    f += cfg.anchor         ? " --anchor"           : "";
    f += cfg.noRoute        ? " --no-route"         : "";
    f += cfg.adaptive       ? " --adaptive"         : "";
    f += cfg.noMentionBoost ? " --no-mention-boost" : "";
    f += cfg.cochangeBoost  ? " --cochange-boost"   : "";
    f += cfg.noDocMention   ? " --no-doc-mention"   : "";
    return f;
}

// The FIRST-BODY FLOOR's byte budget: the first --detail body served whole when it is at most a quarter of the
// bundle budget, else head-cut at that quarter (packBodies' truncateOversizedFirst path, which carries lines= and
// the next= that serves the rest — a disclosed, recoverable cut). Only the FIRST body is floored: the rest of
// --detail still takes whatever the ceiling leaves, exactly as before. 0 when there is no servable first body.
inline constexpr std::size_t kForDetailFloorShareDivisor = 4;   // the floor's cap = bundleBudget / this
std::size_t forDetailFirstBodyFloor( const rw::IngestResult& ing, const std::vector<rw::NodeId>& detailIds, std::size_t bundleBudget )
{
    for( const rw::NodeId id : detailIds )   // packBodies' own skip rule: an invalid id or a module scope is no body
    {
        if( id >= ing.symbols.size() || ing.symbols[id].kind == rw::SymKind::ModuleScope )
        {
            continue;
        }
        const rw::Symbol&     s   = ing.symbols[id];
        const std::size_t raw = s.endByte > s.sigStartByte ? s.endByte - s.sigStartByte : 0;
        return std::min( raw, bundleBudget / kForDetailFloorShareDivisor );
    }
    return 0;
}

// The auto-body candidate head: the top-kPackTaskBodyCandidates positive-score rows of the ranked
// surface — the same "top heads with a positive score" rule packTaskBundleText applies, on the same
// (score desc, id asc) order sigs selected with.
//
// ANCHOR-ONLY ROUTES RESTRICT *BEFORE* TAKING THE HEAD (N08, candidate-head bound, 2026-08-25). When
// the route named an anchor, restrictBodiesToRouteAnchor narrows the candidate set to the anchor's own
// file (see that function for the rule and for why it is a no-op on every other route) — and that
// narrowing has to run on the FULL positive-score surface, not on the six rows already chosen from it.
// Restricting AFTER the top-K cut lets a same-named symbol in a completely unrelated file crowd the
// anchor's own definition out of the head before restriction ever gets a look at it: on rocksdb,
// `Slice`'s anchor resolves correctly to include/rocksdb/slice.h, but seven `Slice`-named rows in the
// unrelated java/ bindings outscore it (BM25's length-normalization term favours their unscoped, single-
// token whole-name match), so the pre-restriction head was seven Java rows and zero rocksdb ones — the
// anchor's own definition was never even a candidate. Restricting first makes the anchor's own
// definitions the ONLY things the top-K walk can select from, so the gold is served whenever anything in
// its own file is on the positive-score surface at all, regardless of how many unrelated namesakes
// outrank it elsewhere. A no-anchor route (anchorDefs empty) takes the unrestricted head exactly as
// before — restrictBodiesToRouteAnchor's own empty-input no-op guard is what used to make this order
// irrelevant there, and it still does.
//
// A free function over buildForAutoBodies' locals (the ForLensHeaderParts precedent) — that caller is
// already one of the largest functions in this file, and this candidate-head computation is a complete,
// independently-testable step.
std::vector<rw::NodeId> computeAutoBodyCandidateIds( const rw::IngestResult& ing, const std::vector<rw::NodeId>& lensSurfaceIds,
                                                     const std::vector<float>& lensRank, const std::vector<rw::RouteAnchorDef>& anchorDefs )
{
    std::vector<rw::NodeId> candidateSurface;
    if( !anchorDefs.empty() )
    {
        candidateSurface.reserve( lensSurfaceIds.size() );
        for( rw::NodeId sid : lensSurfaceIds )
        {
            if( lensRank[sid] <= 0.0f )
            {
                break;
            }
            candidateSurface.push_back( sid );
        }
        restrictBodiesToRouteAnchor( ing, candidateSurface, anchorDefs );
    }
    const std::vector<rw::NodeId>& headSource = anchorDefs.empty() ? lensSurfaceIds : candidateSurface;

    std::vector<rw::NodeId> autoBodyIds;
    for( rw::NodeId sid : headSource )
    {
        if( autoBodyIds.size() >= rw::kPackTaskBodyCandidates || lensRank[sid] <= 0.0f )
        {
            break;
        }
        autoBodyIds.push_back( sid );
    }
    return autoBodyIds;
}

ForAutoBodiesResult buildForAutoBodies( const rw::Config& cfg, const rw::IngestResult& ing, const rw::Graph& g,
                                        const std::vector<rw::NodeId>& lensSurfaceIds, const std::vector<float>& lensRank,
                                        std::size_t committedBytes, std::size_t bundleBudget, rw::RedactCounts* redactPtr,
                                        const std::vector<rw::RouteAnchorDef>& anchorDefs, bool viaLegendInHead, bool splitLegendInHead = false )
{
    ForAutoBodiesResult out;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool             fabSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view fabRootArg    = fabSingleRoot ? cfg.roots[0] : std::string_view();

    const std::vector<rw::NodeId> autoBodyIds = computeAutoBodyCandidateIds( ing, lensSurfaceIds, lensRank, anchorDefs );

    std::size_t leftBytes = bundleBudget > committedBytes ? bundleBudget - committedBytes : 0;
    if( cfg.tokenBudget == 0 )
    {
        leftBytes += rw::kForAutoBodyBudgetBytes;   // the default bundle's body allowance (see serialize.h)

        // THE ANCHOR-RESOLVED ALLOWANCE: when the restriction above has left exactly ONE candidate, fund
        // that one body at a one-body rate instead of a six-candidate pool's share. Why, the derivation of
        // the number, and the bounds all live ONCE, beside the constant in serialize.h. What belongs here
        // is only what is true of this call site: each conjunct is load-bearing, each has its own gate arm
        // (anchorbodycheck 7c/7e and the conceptual arm 5b), and none may be relaxed as a simplification.
        //   • the enclosing cfg.tokenBudget == 0 — an explicit --token-budget is a HARD ceiling and never
        //     sees this constant. T3's own registration binds that, and it is the one condition whose
        //     absence would be invisible in the default output that everybody looks at.
        //   • !anchorDefs.empty() — the conceptual/subtoken+body and --no-route paths anchor nothing, and
        //     a route that resolved no anchor has no "the symbol the caller meant" to be certain about.
        //   • size() == 1 — this is what makes "at most one body" a fact about the INPUT rather than an
        //     accounting argument: packBodies is handed a one-element list, so there is no second item for
        //     the raise to spend on. With 2+ same-named definitions in the anchor's own file the bundle is
        //     serving a SET, not the answer, and a pool is the right funding for a set.
        // max(), not +=: the ceiling is this rate, never this rate plus whatever the bundle had left, so a
        // long root path or a short signature side cannot push a single body past the registered number.
        if( !anchorDefs.empty() && autoBodyIds.size() == 1 )
        {
            leftBytes = std::max( leftBytes, rw::kForAnchorBodyBudgetBytes );
        }
    }

    // Exhausted explicit ceiling (the signature bundle consumed every byte): the disclosure survives,
    // but as the ATTRIBUTE ALONE. The attribute's bytes are exactly what the caller reserved up front
    // (kAutoAttrReserve is inside committedBytes), so it fits by construction; the legend (~half a KB,
    // exempt from the sigs trim charge, never trimmed by the ladder) and the empty <bodies> shell
    // (whose per-item over-budget comments are unbudgeted) have NO reserved bytes here, and keeping
    // them at an already-spent ceiling is what fornotesbudgetcheck/forrootlegendcheck measured as a
    // 45% est_tokens overrun — D10's "trims to fit" is a contract too. reason="budget" is the tell
    // for why nothing but the attribute appears. This branch used to turn the WHOLE surface off with
    // no attribute at all — the silent shape the 2026-08-22 Lane-AA mine caught on 5 of 26 real
    // --for calls (see the BUDGET paragraph above); the T3 registration makes no exception for it.
    // forbudget-soft: under a soft target an exhausted allowance no longer drops the legend — the walk below renders the
    // honest empty shell (<bodies shown="0" total=N capped="1">) at a 1-byte budget and the root says reason="budget".
    if( autoBodyIds.empty() )
    {
        // R9 fix (W3-S, 2026-08-19): this used to return with `out.section` untouched (default-constructed,
        // isRendered=false), so the caller's `autoSection.isRendered && !autoSection.xml.empty()` guard
        // dropped the WHOLE <bodies> element — only the <ctx bundle="auto" bodies="0" reason="no_candidates">
        // attribute below spoke to it. "A zero means none found, never none exists" (CONTRIBUTING #3)
        // applies to elements too. packBodies handles an empty id list natively (requestedCount=0,
        // shownCount=0), so this renders the same honest "<bodies shown="0" total="0" capped="0"></bodies>"
        // shell the "budget" branch below already gets for free, rather than a second hand-rolled tag.
        out.attr    = " bundle=\"auto\" bodies=\"0\" reason=\"no_candidates\"";
        out.section = rw::chargeSection( [ & ]( std::FILE* f )
            { rw::packBodies( f, ing, autoBodyIds, /*budgetBytes=*/1, g.outOff, g.outTargets, rw::withAnchorEdge( rw::CalleeEdgeBytes( g.outNameOnly, &g.outProv, nullptr ), &g.outAnchorMiss ), cfg.compress, redactPtr,
                               /*ranges=*/nullptr, /*noteIndex=*/nullptr, nullptr, /*truncateOversizedFirst=*/false,
                               /*withFileContext=*/false, fabRootArg, &lensRank, rw::CalleeLegendsInHead( viaLegendInHead, splitLegendInHead ) ); },
            rw::kBytesPerTokenBody );
        if( !out.section.isRendered )
        {
            out.surfaceOff = true;                      // degrade: pre-T3 output exactly (alert already on stderr)
            out.section    = rw::ChargedSection{};
            out.attr.clear();                           // the attr was staged above the render — an attribute describing a section that failed to render must not outlive it
        }
        return out;
    }

    // noteIndex=nullptr, deliberately: every auto-body symbol is by construction in the <sigs> head, whose
    // <d> row ALREADY surfaces its field notes — repeating them on the body would spend allowance bytes on
    // duplicates AND desync the --json dialect's notes_kept from the XML sibling's note count
    // (fornotesjsoncheck), since the JSON bundle renders no bodies.
    // floor of 1, never 0: to packBodies a zero budget means "unlimited" (the packSignatures convention),
    // and the exhausted-ceiling case must render the empty shell, not every candidate body.
    const std::size_t  autoBodyBudget = std::max<std::size_t>( 1, std::min( leftBytes, cfg.packBudgetBytes ) );
    rw::EmittedBodies autoEmitted;
    out.section = rw::chargeSection( [ & ]( std::FILE* f )
        { rw::packBodies( f, ing, autoBodyIds, autoBodyBudget, g.outOff, g.outTargets, rw::withAnchorEdge( rw::CalleeEdgeBytes( g.outNameOnly, &g.outProv, nullptr ), &g.outAnchorMiss ), cfg.compress, redactPtr,
                           /*ranges=*/nullptr, /*noteIndex=*/nullptr, &autoEmitted, /*truncateOversizedFirst=*/false,
                           /*withFileContext=*/false, fabRootArg, &lensRank, rw::CalleeLegendsInHead( viaLegendInHead, splitLegendInHead ) ); },
        rw::kBytesPerTokenBody );

    if( !out.section.isRendered )
    {
        out.surfaceOff = true;                      // degrade: pre-T3 output exactly (alert already on stderr)
        out.section    = rw::ChargedSection{};
    }
    else if( autoEmitted.kept.empty() )
    {
        // R9 fix (W3-S, 2026-08-19): `out.section` ALREADY holds packBodies' own honest
        // "<bodies shown="0" total="N" capped="1"></bodies>" render from the chargeSection() call just
        // above — this branch used to overwrite it with an empty section ("drop the empty section
        // whole"), so the element vanished from the document even though the bytes to say so honestly
        // had already been paid for and charged. Keep it; only the attr= reason below is new
        // information (WHY zero: the budget, not the candidate set).
        out.attr = " bundle=\"auto\" bodies=\"0\" reason=\"budget\"";
    }
    else
    {
        out.attr = " bundle=\"auto\" bodies=\"" + std::to_string( autoEmitted.kept.size() ) + "\"";
    }
    return out;
}

// ── COMPACT CONCEPTUAL SERVING: the <hops> surface (pre-registered: docs/EVALS.md, T3 route-narrowing) ──
//
// The conceptual route's replacement for buildForAutoBodies above, and deliberately its twin in shape so
// the call site wires ONE verdict either way: same ForAutoBodiesResult, same candidate head (the
// positive-score head of the ranked surface, capped at kPackTaskBodyCandidates), same two budget regimes,
// same surfaceOff degrade contract. What differs is what the allowance buys — one-hop callee signatures
// instead of body CDATA — and that the allowance covers this surface's OWN disclosure (see
// kForCompactSurfaceBudgetBytes): the legend and the root attribute are subtracted here, before packHops
// ever sees a byte, so the compact bundle cannot grow by explaining itself.
//
// THE ROOT ATTRIBUTE'S TWO REASONS ARE NOT THE SAME FACT. `reason="compact-route"` means the route chose
// this shape and the edges are the answer; `reason="no_candidates"` means nothing scored above zero, so
// there was nothing to take edges FROM. Collapsing them would make a ranking miss look like a serving
// decision, which is the honesty rule (#3) in its most literal form.
constexpr std::size_t kAutoAttrReserve    = 48;   // ' bundle="auto" bodies="0" reason="no_candidates"' — the widest spelling
constexpr std::size_t kCompactAttrReserve = 56;   // ' bundle="compact" bodies="0" reason="no_candidates"' — the widest spelling
constexpr std::size_t kCompactWrapReserve = 56;   // '<hops shown="N" total="N" capped="1">' + '</hops>' — the section's own envelope
static_assert( rw::kForCompactSurfaceBudgetBytes > kCompactAttrReserve + kCompactWrapReserve + 512,
               "the compact surface allowance must leave real room for edges after its own disclosure — "
               "if a legend edit tripped this, shorten the legend rather than raising the allowance" );

// COMPACT conceptual serving: is this the route the ROUTER chose the subtoken+body ranker for? Read from
// the router's own machine tag rather than re-derived from the query, so there is exactly one classifier.
// "no-route" is deliberately NOT this route: --no-route means the router never ran, so there is no route
// decision to condition a default on, and that path keeps its golden neutrality (byte-identical output).
inline bool isConceptualRoute( const char* routeTag )
{
    return routeTag != nullptr && std::strcmp( routeTag, "subtoken+body" ) == 0;
}

// …and MAY this --for call serve the compact bundle at all? Decided from cfg alone, because the route is
// not known until the ranking has run and the RANKING needs this answer first: the compact bundle orders a
// cut callee listing by the rank vector, which makes it a full-distribution consumer (see
// computeLensRanking). Answering "maybe" here is safe and cheap — a name-exact query simply never goes
// compact, and computeLensRanking re-checks the route before it acts on this.
inline bool forCompactPosture( const rw::Config& cfg )
{
    return cfg.detail == 0 && !cfg.signaturesOnly && !cfg.autoBodies && !cfg.candidates;
}

// WHICH ENRICHMENT THE BUNDLE GAINS, decided once and carried as a value rather than re-derived at each
// of the four places that need it (the legend's sigs-budget exemption, the root attribute's reserve, the
// builder call, and the est_tokens split). runForLens is the largest function in this file; four
// independent ternaries on the same predicate is exactly how it got that way.
//
// The compact section's bytes are MARKUP bytes, which is why the plan carries no rate: <hops> holds tags,
// identifiers and line numbers, never source text, so it is summed with the rest of the markup at one rate
// and rounded once. Charging it separately at the same rate rounds twice, and two roundings of one rate do
// not equal one rounding of it — the weak-query bundle came out at 529 tokens where round(1321/2.50) is
// 528, an off-by-one in the number contracted to BE the document's own measurement
// (test/estchargecheck.sh #11 A9/A10 asserts that identity, not a band).
struct ForEnrichmentPlan
{
    bool        compact      = false;   // the conceptual route serves <hops>; otherwise T3's <bodies>
    bool        autoBodies   = false;   // T3's <bodies> allowance is on — the two are mutually exclusive
    std::size_t legendBytes  = 0;       // whichever legend rides the header (exempt from the sigs trim)
    std::size_t attrReserve  = 0;       // the root attribute's widest spelling for THIS shape
};

// Every input the decision needs, so the CALLER states facts and this function does the deciding — the
// alternative (a caller-side `autoBundleMode && conceptualRoute && !cfg.autoBodies`) puts the rule in the
// one function in this file that can least afford another branch.
inline ForEnrichmentPlan planForEnrichment( bool autoBundleMode, bool conceptualRoute, bool autoBodiesFlag )
{
    if( !autoBundleMode )
    {
        return ForEnrichmentPlan{};                     // --detail=N or --signatures-only: no enrichment at all
    }
    if( conceptualRoute && !autoBodiesFlag )
    {
        return ForEnrichmentPlan{ true, false, kForCompactBundleLegend.size(), kCompactAttrReserve };
    }
    return ForEnrichmentPlan{ false, true, kForAutoBundleLegend.size(), kAutoAttrReserve };
}

// L1 (2026-09-19): the enrichment legend THIS DIALECT puts on the header — appendCompactForLegend's hops/bodies clause
// under --legend=compact, the plan's full enrichment legend otherwise. The sig ledger subtracts it from the emitted
// header as an exemption, and it used plan.legendBytes (the FULL size) in both dialects — so under compact it
// subtracted ~450 B the header never carried, handed them to <sigs>, and a budgeted compact bundle shipped over its
// ceiling with over_ceiling="1" (fornotesbudgetcheck at --token-budget=1100: est_tokens=1272; forrootlegendcheck at
// 850: 1120). Latent while compact was opt-in; the default since L1. The same rule the confidence/tail/route
// exemptions already follow: subtract what was EMITTED.
inline std::size_t enrichmentLegendBytesEmitted( const ForEnrichmentPlan& plan, bool compactLegendOn ) noexcept
{
    if( !compactLegendOn || ( !plan.compact && !plan.autoBodies ) )
    {
        return plan.legendBytes;
    }
    return plan.compact ? kForCompactLegendHops.size() : kForCompactLegendBodies.size();
}

// The compact route's <hops> rows: the positive-score head of the ranked surface, capped at kPackTaskBodyCandidates. One
// spelling, read by buildForCompactHops and by the header's via="name" question (FE-B), so the two cannot disagree.
inline std::vector<rw::NodeId> forCompactHopIds( const std::vector<rw::NodeId>& lensSurfaceIds, const std::vector<float>& lensRank )
{
    std::vector<rw::NodeId> hopIds;
    for( rw::NodeId sid : lensSurfaceIds )
    {
        if( hopIds.size() >= rw::kPackTaskBodyCandidates || lensRank[sid] <= 0.0f )
        {
            break;
        }
        hopIds.push_back( sid );
    }
    return hopIds;
}
// ── THE QUESTION'S OWNER (lane owner-hop-068) ─────────────────────────────────────────────────────────────────────
// The hop candidates above are the six best-RANKED rows, and a question that names the function it is about ("How does
// the JWT middleware verify a token?" -> jwt(), rank 12 behind a dozen symbols that repeat the question's other words)
// never got that function's callees — the graded gold items of two round-1 rows (getCookie, HTTPException, set;
// validateAsync*). An OWNER is a symbol of the ranked pool (the first kForLensDefaultTopN rows with a positive score) that
//   * is a callable DEFINITION — a function or method with a body (a C prototype and its body are one entity: the
//     body's row is the owner, the prototype is no second one) — and not a test symbol (rw::isTestSymbol);
//   * has a name that, with leading _ # $ @ removed and ASCII case folded, EQUALS a whole word of the question (words
//     split on every byte that is not a letter, digit, '_' or a non-ASCII byte; length >= 3; not a route stopword) —
//     whole name only: "log" never makes catalog or dialog owners; `__init__` folds to init__ and matches no word;
//   * names a word with at least one such definition inside the head tier (rank <= kForDocExcerptRankCount). The gate
//     is per WORD: once a word qualifies, EVERY same-named definition in the pool is an owner, each its own row (two
//     classes' _notify are two entities, never one picked silently).
// This is a NAME lookup over the ranked head, not a resolution: qword= says the name equals the word, never that the
// symbol is the only or the true implementation of the subject. The case fold matches the question's word only; it never
// merges two entities. Language-neutral by construction: a name, a kind, a body span and the test partition are what
// every indexed language already sets.
// SLOTS: owners with a proven callee edge (the hop-slot rule, rw::hopSlotHasProvenEdge) take up to kForOwnerHopRows rows
// in rank order — except that a word on kOwnerCommonWords (verbs and function words a question USES: get, then, write …)
// ranks after every other word, so "how does the gateway get and then write the token" seats gateway first (gate (V)).
// The rest are disclosed (qword_cut= + next=). An owner with no proven edge never takes a slot; it is counted in noedge=
// once (it is appended to the hop nodes only when it is not already one of the six). RIPWIRE_NO_OWNER_HOP=1 turns the
// whole plan off — the A/B handle, the RIPWIRE_NO_DOCS_AFTER_CODE precedent.
inline constexpr std::size_t kForOwnerHopRows = 3;
// kOwnerCommonWords, ownerFoldName, ownerQuestionWords and the found set itself (forOwnerCandidates) live in forowner.h: the
// body slot (lane for-body-slot) and the MCP twin read the same owners.

struct ForOwnerPlan
{
    std::vector<rw::NodeId>  rowIds;      // the owner rows, slot order (<= kForOwnerHopRows)
    std::vector<std::string> rowWords;    // the folded question word of each row
    std::vector<rw::NodeId>  noEdgeIds;   // owners with no proven edge that are NOT among the six candidates
    std::size_t              capCut      = 0;   // owners with a proven edge past the row cap
    rw::NodeId               firstCapCut = rw::kNoNode;
    bool any() const noexcept { return !rowIds.empty() || capCut > 0; }   // a qword row or a qword_cut= disclosure (the legend's bit)
    bool changesNodes() const noexcept { return any() || !noEdgeIds.empty(); }   // …or an edgeless owner to count in noedge=
};

// What the --for header already decided for the enrichment section it introduces: FE-B's "the header defines
// via=\"name\"" (ForLensHeaderParts::viaPresent) and the owner plan its qword clause read. One aggregate, so the section
// builders render exactly what the header promised without a parameter per promise.
struct ForSectionPromises
{
    bool                viaLegendInHead = false;
    const ForOwnerPlan* owners          = nullptr;   // nullptr ⇒ no owner rows (an empty plan reads the same)
    bool                splitLegendInHead = false;   // attrib-multidef Q1: the header defines prov="split" (splitPresent)
};

inline ForOwnerPlan forOwnerHopPlan( const rw::IngestResult& ing, const rw::Graph& g, std::string_view task,
                                     const std::vector<rw::NodeId>& lensSurfaceIds, const std::vector<float>& lensRank,
                                     const std::vector<rw::NodeId>& hopIds )
{
    ForOwnerPlan plan;
    if( std::getenv( "RIPWIRE_NO_OWNER_HOP" ) != nullptr )
    {
        return plan;
    }
    std::vector<rw::OwnerCandidate> found = rw::forOwnerCandidates( ing, rw::ownerQuestionWords( task ), lensSurfaceIds, lensRank );
    for( rw::OwnerCandidate& o : found )
    {
        if( !rw::hopSlotHasProvenEdge( g.outOff, g.outNameOnly, o.id ) )
        {
            if( std::ranges::find( hopIds, o.id ) == hopIds.end() )
            {
                plan.noEdgeIds.push_back( o.id );   // counted in noedge= once; a candidate already is
            }
            continue;
        }
        if( plan.rowIds.size() < kForOwnerHopRows )
        {
            plan.rowIds.push_back( o.id );
            plan.rowWords.push_back( std::move( o.word ) );
            continue;
        }
        if( plan.capCut++ == 0 )
        {
            plan.firstCapCut = o.id;
        }
    }
    ENSURES( plan.rowIds.size() == plan.rowWords.size() && plan.rowIds.size() <= kForOwnerHopRows, "one word per seated owner, at most the cap" );
    return plan;
}

// The <hops> node list with the owner plan applied: owner rows first, then the six candidates minus the owners MOVED out
// of them (moved, never duplicated), then the edgeless owners that are not candidates (each counted in noedge= once).
inline std::vector<rw::NodeId> forOwnerHopNodes( const ForOwnerPlan& plan, const std::vector<rw::NodeId>& hopIds )
{
    std::vector<rw::NodeId> nodes = plan.rowIds;
    for( rw::NodeId id : hopIds )
    {
        if( std::ranges::find( plan.rowIds, id ) == plan.rowIds.end() )
        {
            nodes.push_back( id );
        }
    }
    nodes.insert( nodes.end(), plan.noEdgeIds.begin(), plan.noEdgeIds.end() );
    return nodes;
}

// packHops' owner description of a plan. Default regime: the owner rows ride ON TOP of the hop budget (completeness first —
// every ranked row keeps the budget it had, and the name guard is the only stop). Explicit ceiling: the owners are funded
// first from what the ceiling left, minus the widest qword_cut/next= disclosure the walk could write (the envelope is the
// ranked rows' own reserve, the attribute and envelope reserves, and is not charged twice).
inline rw::HopOwners forHopOwners( const rw::Config& cfg, const rw::IngestResult& ing, const ForOwnerPlan& plan,
                                   std::size_t leftBytes, std::string_view rootArg )
{
    rw::HopOwners owners;
    owners.rows        = plan.rowIds.size();
    owners.words.assign( plan.rowWords.begin(), plan.rowWords.end() );
    owners.capCut      = plan.capCut;
    owners.firstCapCut = plan.firstCapCut;
    if( cfg.tokenBudget == 0 || !plan.any() )
    {
        return owners;
    }
    std::vector<char> esc;
    const std::string rootPrefix = rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( rootArg );
    std::size_t       cutReserve = 0;   // ' qword_cut="NNN" next="--callees=' + the longest target + '"'
    std::vector<rw::NodeId> cuttable = plan.rowIds;
    if( plan.firstCapCut != rw::kNoNode )
    {
        cuttable.push_back( plan.firstCapCut );
    }
    for( rw::NodeId id : cuttable )
    {
        const rw::Symbol&      s   = ing.symbols[ id ];
        const std::string_view rel = rootArg.empty() ? std::string_view( ing.files[ s.fileId ] )
                                                     : rw::sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix );   // packHops' pathRel
        cutReserve = std::max( cutReserve, rw::ownerCalleesNext( ing, s, rel, rootArg, esc ).size() + 28 );
    }
    owners.budgetBytes = leftBytes > cutReserve ? leftBytes - cutReserve : 1;   // 1, never 0 (0 reads as "ride on top")
    owners.fundFirst   = true;
    return owners;
}

// --detail=N's bodies: the top min(N, forTopN) symbols by (score desc, id asc) — the order the sigs use. One spelling, read
// by the --detail section and by the header's via="name" question (FE-B).
inline std::vector<rw::NodeId> forDetailIds( const rw::IngestResult& ing, const std::vector<float>& lensRank, int detail, int forTopN )
{
    const std::size_t        S = ing.symbols.size();
    std::vector<rw::NodeId> ids( S );
    for( rw::NodeId i = 0; i < S; ++i )
    {
        ids[i] = i;
    }
    rw::sortutil::radixSortByScoreDescId( ids, lensRank );
    ids.resize( std::min<std::size_t>( { std::size_t( detail ), std::size_t( forTopN ), S } ) );
    return ids;
}

// fix round 4 (rule 5, review rv-wrap-recipe-k29 F1): the compact <hops> section an exhausted explicit ceiling
// leaves out, as a counted marker instead of nothing — `<hops shown="0" total="N" capped="1" next="--for=TASK"/>`.
// total= counts the CANDIDATE head the section covers (ids the ingest knows) — not the owner rows: at a spent ceiling the
// answer must stay byte-identical with and without the owner-hop plan (ownerhopcheck (B2), owner-hop's signed contract:
// "owner rows add nothing"), and the next= answer serves those owner rows too. How many candidates have proven edges
// (noedge=) is not known without the render, so the marker does not claim it. next= is the same question without
// --token-budget, whose own compact allowance serves the hop rows. No candidates => no marker (nothing was cut). Markup
// bytes, charged through buildForEnrichment's markupBytes like the rendered section.
inline constexpr std::string_view kForHopsBudgetCutLegend =
    "; hops shown=0 capped=1: this budget left out the call-hop rows (one hop of callees for each of total= top rows); next= serves them";
// …and the compact dialect's spelling (train 27, compactlegendcheck P1-B): that dialect defines total= shown= capped=1 and next=
// in its un-droppable clauses (kForCompactLegendRows / kForCompactLegendFacts), so its hops clause says only what the element
// is — every reading is the shortest honest one.
inline constexpr std::string_view kForHopsBudgetCutLegendCompact =
    "; hops: this budget left out the call-hop rows (one hop of callees for each of total= top rows)";
static_assert( kForHopsBudgetCutLegendCompact.size() < kForHopsBudgetCutLegend.size(),
               "the compact hops clause is the shorter honest spelling of the full one" );
// the hops cut's continuation (` next="--for=TASK"`) — one spelling for the marker and the partial-cut splice
inline std::string forHopsCutNextAttr( const rw::Config& cfg )
{
    return rw::nextAttrXml( rw::nextFlag( "--for=", cfg.forTask ) );
}
rw::ChargedSection forHopsBudgetCutMarker( const rw::Config& cfg, const rw::IngestResult& ing, const std::vector<rw::NodeId>& hopIds )
{
    rw::ChargedSection marker;
    std::size_t        total = 0;
    for( const rw::NodeId id : hopIds )
    {
        total += id < ing.symbols.size() ? 1u : 0u;
    }
    if( total == 0 )
    {
        return marker;
    }
    marker.xml        = "<hops shown=\"0\" total=\"" + std::to_string( total ) + "\" capped=\"1\""
                      + forHopsCutNextAttr( cfg ) + "/>";
    marker.tokens     = rw::tokensForEmittedBytes( marker.xml.size(), rw::kBytesPerTokenDefault );
    marker.isRendered = true;
    return marker;
}

// fix round 4 (rule 5): an explicit-budget <hops> the budget CUT names the call that serves the rest. A cut with no
// next= of its own (the qword_cut= disclosure already carries one) gets ` next=` spliced into the open tag; the bytes
// were held back from the rows' budget (buildForCompactHops' rowRoom), so the section stays inside what it was given.
// A rendered section with shown="0" capped="1" is spliced the same way and then reads as the exhausted-ceiling marker
// does (counted, continued). An uncut section (capped="0") is untouched.
void forHopsCutDisclose( rw::ChargedSection& section, std::string_view cutNext )
{
    std::string&            x   = section.xml;
    const std::size_t       end = x.find( '>' );
    if( !section.isRendered || end == std::string::npos || x.compare( 0, 5, "<hops" ) != 0 )
    {
        return;
    }
    const std::string_view open( x.data(), end );
    if( open.find( " capped=\"1\"" ) == std::string_view::npos || open.find( " next=" ) != std::string_view::npos )
    {
        return;
    }
    x.insert( end, cutNext );
    section.tokens = rw::tokensForEmittedBytes( x.size(), rw::kBytesPerTokenDefault );
}

ForAutoBodiesResult buildForCompactHops( const rw::Config& cfg, const rw::IngestResult& ing, const rw::Graph& g,
                                          const std::vector<rw::NodeId>& lensSurfaceIds, const std::vector<float>& lensRank,
                                          std::size_t committedBytes, std::size_t bundleBudget, rw::RedactCounts* redactPtr,
                                          const ForSectionPromises& promised )
{
    static const ForOwnerPlan kNoOwners{};
    const ForOwnerPlan&       ownerPlan       = promised.owners != nullptr ? *promised.owners : kNoOwners;
    const bool                viaLegendInHead = promised.viaLegendInHead;
    ForAutoBodiesResult out;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool             fcSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view fcRootArg    = fcSingleRoot ? cfg.roots[0] : std::string_view();

    // candidates: EXACTLY the head buildForAutoBodies would have bodied — same rule, same order, so the
    // two shapes describe the same symbols and only differ in how much of each they serve.
    const std::vector<rw::NodeId> hopIds = forCompactHopIds( lensSurfaceIds, lensRank );

    std::size_t leftBytes = bundleBudget > committedBytes ? bundleBudget - committedBytes : 0;
    if( cfg.tokenBudget == 0 )
    {
        leftBytes += rw::kForCompactSurfaceBudgetBytes;   // the default bundle's compact allowance (serialize.h)
    }
    // Exhausted explicit ceiling: the ATTRIBUTE ALONE, exactly as buildForAutoBodies does it (and for the
    // same reasons — read that branch's comment for the full argument). This shape used to be the silent
    // one here: `surfaceOff = true`, no attribute, the reader given no way to know an enrichment section
    // was considered and skipped. That is the very defect the T3 disclosure round fixed on the body path
    // (2026-08-22 Lane-AA mine, 5 of 26 real --for calls), and the compact route inherited a fresh copy of
    // it because the two shapes were written a day apart. The attribute's bytes are the caller's reserve
    // (kCompactAttrReserve, inside committedBytes via plan.attrReserve), so it fits by construction; the
    // legend and the <hops> envelope have no reserve at a spent ceiling and are dropped. A THIRD reason
    // spelling, per the two-reasons rule above: "compact-route" = the route chose edges, "no_candidates" =
    // nothing scored, "budget" = the ceiling was already spent. Collapsing any pair would report one fact
    // as another. Gate: test/fordisclosurecheck.sh (compact arm).
    if( cfg.tokenBudget > 0 && leftBytes == 0 )
    {
        out.attr = " bundle=\"compact\" bodies=\"0\" reason=\"budget\"";
        // fix round 4 (rule 5, review rv-wrap-recipe-k29 F1): the hop rows this budget left out are NAMED, not dropped
        // silently — an empty <hops> carrying the count and the call that serves them (the same question without the
        // budget, which serves every hop row). forbudget-soft: the legend stays; the marker's clause rides (hopsCutMarker).
        out.section       = forHopsBudgetCutMarker( cfg, ing, hopIds );
        out.hopsCutMarker = !out.section.xml.empty();
        return out;
    }

    // fix round 4: under an explicit ceiling a cut <hops> carries next= (forHopsCutNextAttr), so its bytes come out of the
    // rows' budget first; the default regime is unchanged (cutNext empty)
    const std::string     cutNext            = cfg.tokenBudget > 0 ? forHopsCutNextAttr( cfg ) : std::string();
    const std::size_t     rowRoom            = leftBytes > cutNext.size() ? leftBytes - cutNext.size() : 1u;
    // forbudget-soft (D-3): the DEFAULT answer serves every hop row — the section is bounded by its own structure (at most
    // kPackTaskBodyCandidates rows of at most 16 callees each), so the 1,000 B allowance no longer cuts it; the runaway guard's
    // byte value is the only bound. An explicit soft target fills the rows from what the target left after <sigs> (rowRoom),
    // with no allowance of its own: a target wide enough for the whole section serves it whole, as the default does.
    const std::size_t     hopBudget          = cfg.tokenBudget == 0 ? rw::kForRunawayGuardBytes : rowRoom;

    // THE QUESTION'S OWNER (forOwnerHopPlan): owner rows first, the candidates they were not, the edgeless owners last;
    // an empty plan leaves both exactly as they were (forOwnerHopNodes / forHopOwners).
    const std::vector<rw::NodeId> hopNodes = forOwnerHopNodes( ownerPlan, hopIds );
    const rw::HopOwners           owners   = forHopOwners( cfg, ing, ownerPlan, leftBytes, fcRootArg );

    out.section = rw::chargeSection( [ & ]( std::FILE* f )
        { rw::packHops( f, ing, hopNodes, hopBudget, g.outOff, g.outTargets, rw::withAnchorEdge( rw::CalleeEdgeBytes( g.outNameOnly, &g.outProv, nullptr ), &g.outAnchorMiss ), redactPtr, &lensRank, fcRootArg,
                        rw::CalleeLegendsInHead( viaLegendInHead, promised.splitLegendInHead ), &owners ); },   // g.outNameOnly also feeds the hop-slot rule (serialize.h noProvenEdge)
        // MARKUP rate, not the body rate — and this is an honesty choice, not a copy-paste slip. The body
        // rate (3.80 B/tok) prices SOURCE TEXT; the compact section contains none, only tags, identifiers
        // and line numbers, which tokenize like the rest of the bundle. Charging structured markup at the
        // body rate would divide by a larger number and report FEWER tokens than the section really costs,
        // which is the one direction a disclosure may never round (CONTRIBUTING #3). It also makes the
        // compact document uniformly markup-rate, so its est_tokens satisfies the flat identity rather
        // than a mixed-rate one — see test/estchargecheck.sh #11 A9/A10.
        rw::kBytesPerTokenDefault );
    if( !out.section.isRendered )
    {
        out.surfaceOff = true;                            // degrade: pre-compact output exactly (alert already on stderr)
        out.section    = rw::ChargedSection{};
        return out;
    }
    out.attr = hopNodes.empty() ? " bundle=\"compact\" bodies=\"0\" reason=\"no_candidates\""
                              : " bundle=\"compact\" bodies=\"0\" reason=\"compact-route\"";
    if( !cutNext.empty() )
    {
        forHopsCutDisclose( out.section, cutNext );
    }
    return out;
}

// ONE verdict, two shapes: the compact route's <hops> surface or T3's <bodies> allowance. Both builders
// return the same struct, so the caller's wiring (section, root attribute, surface-off header rebuild) is
// written once and cannot drift between them.
//
// `committedBytes` is what the bundle has already spent — the real header (legend included), the rendered
// sections and "</ctx>", plus the post-ladder splices — and this function adds the plan's own root-attribute
// reserve, because the compact spelling is the longer of the two and the caller should not have to know that.
ForAutoBodiesResult buildForEnrichment( const rw::Config& cfg, const rw::IngestResult& ing, const rw::Graph& g,
                                        const std::vector<rw::NodeId>& lensSurfaceIds, const std::vector<float>& lensRank,
                                        const ForEnrichmentPlan& plan, const std::vector<rw::RouteAnchorDef>& anchorDefs,
                                        rw::RedactCounts* redactPtr, std::size_t committedBytes, std::size_t bundleBudget,
                                        const ForSectionPromises& promised )   // FE-B via="name" in the head + the owner plan
{
    const std::size_t   committed = committedBytes + plan.attrReserve;
    ForAutoBodiesResult out       = plan.compact
        ? buildForCompactHops( cfg, ing, g, lensSurfaceIds, lensRank, committed, bundleBudget, redactPtr, promised )
        : buildForAutoBodies( cfg, ing, g, lensSurfaceIds, lensRank, committed, bundleBudget, redactPtr, anchorDefs, promised.viaLegendInHead,
                              promised.splitLegendInHead );
    if( plan.compact )
    {
        out.markupBytes = out.section.xml.size();
    }
    else
    {
        out.bodyTokens = out.section.tokens;
    }
    return out;
}

// UPWARD-2HOP (forcallerhop.h forRankedCallerHopTargets): the ranked caller hop is a LATE splice, on the late splices' posture (the
// compact auto bundle, XML, the default regime, the whole answer measured, no hops cut marker), never beside the name-exact hop,
// only on an error-shaped task; it reads the rows <sigs> EMITTED (r= order), so its clause's "r=1..3" holds. `held` is the
// named hop's render, returned unchanged when that hop rode.
struct RankedHopPosture
{
    bool        bundleCompact = false;   // the auto bundle on the compact route
    bool        sigsRendered  = false;
    bool        surfaceOff    = false;
    bool        hopsCutMarker = false;
    bool        namedHop      = false;   // the name-exact hop already rode
    const char* routeTag      = "";
};
inline rw::CallerHopRender rankedCallerHop( const RankedHopPosture& p, const rw::Config& cfg, const rw::IngestResult& ing, const rw::Graph& g,
                                            const std::vector<rw::NodeId>& shownSigIds, std::string_view rootArg, rw::CallerHopRender held )
{
    if( p.namedHop || !p.bundleCompact || !p.sigsRendered || p.surfaceOff || p.hopsCutMarker || rw::isNameExactRouteTag( p.routeTag ) || cfg.json
        || cfg.tokenBudget > 0 || !rw::forCallerHopOn() || !rw::forRankedCallerHopTask( cfg.forTask ) )
    {
        return held;
    }
    const std::vector<rw::NodeId> ids = rw::forRankedCallerHopTargets( ing, g, shownSigIds, cfg.forTask );
    return ids.empty() ? held : rw::renderForCallerHop( ing, g, ids, rootArg, /*ranked=*/true );
}

// mf1-nx (forcallerhop.h): the ONE function whose callers ride — `nameExactBodies` is the posture runForLensPass knows (the auto
// <bodies> bundle on the name-exact route); this adds the regime (XML, no explicit --token-budget, the A/B switch) and the target rule.
inline std::vector<rw::NodeId> forCallerHopIds( const rw::Config& cfg, const rw::IngestResult& ing, const rw::Graph& g, const std::vector<rw::NodeId>& lensSurfaceIds,
                                                const std::vector<float>& lensRank, const std::vector<rw::RouteAnchorDef>& anchorDefs, bool nameExactBodies )
{
    if( !nameExactBodies || cfg.json || cfg.tokenBudget > 0 || !rw::forCallerHopOn() )
    {
        return {};
    }
    return rw::forCallerHopTargets( ing, g, computeAutoBodyCandidateIds( ing, lensSurfaceIds, lensRank, anchorDefs ) );
}

// DEEP-TAIL d2 — the XML tail render + its explicit-regime fill, a free function over runForLens' locals (that function
// is already one of the largest in this file — the ForLensHeaderParts precedent). Default regime: page 0's full 40 rows
// (FOLD C), bytes riding on top (est_tokens measures them). Explicit regime (forbudget-soft round C, reserve first): the
// tail keeps at least its SHARE — the bundle budget less `spentBytes` (the rows at the target cut and the sections served
// before the tail), never below the empty shell — so rows are added until the element reaches it (its last row may cross
// it: a soft target makes no byte promise). A cut tail carries next= (the page after its last row) in every regime.
inline std::string renderForFileTailXml( const rw::FileTail& tail, std::size_t tokenBudget,
                                         std::size_t bundleBudget, std::size_t spentBytes )
{
    std::vector<char> esc;
    if( tokenBudget == 0 )
    {
        return rw::renderFileTailXml( tail, tail.paths.size(), esc );   // every row computeFileTail collected
    }
    const std::size_t share  = std::max<std::size_t>( bundleBudget > spentBytes ? bundleBudget - spentBytes : 0u, rw::kForFileTailShellReserve );
    const auto        render = [ & ]( std::size_t shown ) { return rw::renderFileTailXml( tail, shown, esc ); };
    return render( rw::fileTailShownToFill( tail, share, render ) );
}


// R2-AF (round 2, S4): render the task's named-file/decl-impl-partner rows (rw::forNamedHeaderRows,
// mention.h — the resolution rule and its rationale live there) as `<hdr p= of=/>`, root-relative like
// every other --for path, no wrapping element (§R7: "first row(s) inside the root", a lookup rather than
// a ranked/graph list with its own total=/shown=/capped= triple). "" when the task names nothing with a
// unique partner — the common case, byte-identical to before this feature.
inline std::string renderForHdrRowsXml( const rw::IngestResult& ing, const std::vector<rw::ForNamedHeaderRow>& rows,
                                        std::string_view rootArg )
{
    if( rows.empty() )
    {
        return {};
    }
    std::string x = rw::forHdrRowsXml( ing, rows, rootArg );   // forpage.h: the one render, shared with the MCP twin
    // runForLens charges x.size() in every budget sum and emits x itself, so "no row" and "no bytes" must agree
    ENSURES( !x.empty(), "renderForHdrRowsXml: rows resolved but nothing rendered" );
    return x;
}

// the CLI half of the shared page (forpage.h owns the doc): write it to stdout. One implementation,
// three dialects — the CLI bundle verbs and the MCP twins all build the SAME document.
inline int emitForCandidatePage( const rw::IngestResult& ing, const std::vector<float>& lensRank, const rw::AdaptiveCut& forCut,
                                 const rw::ForCandidatePageReq& req )
{
    // the CLI half of the shared page (forpage.h owns the doc): write it to stdout. One
    // implementation, three dialects — the CLI bundle verbs and the MCP twins all build the SAME
    // document. rw::emitRaw (#362 review's ask): the repo's own stdout writer, not the raw stream call.
    const std::string doc = rw::forCandidatePageDoc( ing, lensRank, forCut, req );
    rw::emitRaw( stdout, doc.c_str() );
    return 0;
}

// B2 (#362 review round 4): the argv fragment of every accepted flag that changes the lens ranking,
// echoed into the page's next= so a pasted continuation re-ranks identically. The bundle-shaping
// set (--adaptive/--anchor/--signatures-only/…) is REFUSED beside a window (cli.h), so it never
// appears here; these four are accepted because they select the ranking, not the bundle's shape.
inline std::string forPageRankFlagArgv( const rw::Config& cfg )
{
    std::string s;
    if( cfg.noRoute )         { s += " --no-route"; }
    if( cfg.noMentionBoost )  { s += " --no-mention-boost"; }
    if( cfg.noDocMention )    { s += " --no-doc-mention"; }
    if( cfg.cochangeBoost )   { s += " --cochange-boost"; }
    return s;
}

// #362 review round 4, follow-up (quality bar): the windowed-page predicate, named once — the
// inline spelling appeared twice (runForLens's bundle path, runPackTask's B1 gate) and the second
// read pushed runPackTask past its complexity bar.
inline bool candidatePageWindowed( const rw::Config& cfg )
{
    return cfg.tokenBudget != 0 && ( cfg.pageLimit > 0 || cfg.pageOffset > 0 );
}

// The --for lens's RENDER over the ranking runForLens computed once (`lr`). `forAtStamp` (train 26c, CodeRabbit on #383): the
// at= stamp, read ONCE per run by runForLens. forbudget-soft: one render per run — the C3 payment modes (unpaid / paid /
// overrun re-renders of a charged <sigs> continuation) went with the hard ceiling they priced against.
struct ForLensPassMode
{
    std::string_view forAtStamp;
};
// the verb sections (verbs_navigate.h) come later in this translation unit; the --for block calls their CLI entry points
std::optional<int> runPath( const MainDispatch& d );
std::optional<int> runPathServed( const MainDispatch& d, std::span<const rw::NodeId> served, bool inForBlock );
std::optional<int> runCallHierarchy( const MainDispatch& d );
std::optional<int> runConnect( const MainDispatch& d );

// FOR-ROUTE-DECLINED (src/forgraphverb.h): a task spelled `path from A to B` / `callers of X` / `common callers of A and B`
// gets that verb's DEFAULT answer inside <graph_verb endpoints="subject">, just before </ctx>, on the graph this run built
// (no re-index). Every byte before it is the ordinary answer; nothing resolves → nothing is printed. XML only (the
// --json / columnar dialects keep their single document; the verb is one call away there).
inline void appendSubjectGraphVerbBlock( const MainDispatch& d, std::span<const rw::NodeId> served )
{
    const rw::Config& cfg = d.cfg;
    if( cfg.json || cfg.columnar || cfg.candidates || d.multiRoot )
    {
        return;
    }
    const std::optional<rw::GraphSubjectArgs> args = rw::chooseGraphSubjectArgs( d.ing, cfg.forTask );
    if( !args )
    {
        return;
    }
    if( cfg.tokenBudget > 0 )   // --token-budget (the budget --for honours; shapingflagcheck (A) pins the --max-tokens read sites, so this reads only the one)
    {
        // a token budget is a request the block must obey (S2): the verb does not run, the tag names it (held="budget", verb= is the call)
        rw::emitRaw( stdout, rw::graphSubjectOpenXml( *args, rw::GraphSubjectOpen{ .held = true } ).c_str() );
        return;
    }
    rw::Config sub = cfg;   // the verb runs as its own bare call: its default caps, no page window, no --for shaping
    sub.forTask    = {};
    sub.pageLimit  = 0;   // defensive, like the json guard above: a paged --for (--limit/--offset) never reaches this site
    sub.pageOffset = 0;
    const auto [ flag, value ] = rw::graphSubjectVerbFlag( *args );
    switch( args->form )
    {
        case rw::GraphSubjectForm::Path: sub.pathSpec = value; break;
        case rw::GraphSubjectForm::Callers: sub.callers = value; break;
        case rw::GraphSubjectForm::Common: sub.connectSpec = value; break;
    }
    const MainDispatch sd{ sub, d.ing, d.g, d.root, d.multiRoot, d.ws, d.fanIn, d.fanInPtr, d.qmetrics, d.ampPtr, d.cboPtr, d.testedPtr,
                           d.lcom4Ptr, d.impurePtr, d.forChurn, d.redactCounts, d.redactPtr, d.notesPtr, d.notesDegraded, d.grepPhases, d.valueUses };
    const auto runVerb = [ & ]
    {
        switch( args->form )
        {
            case rw::GraphSubjectForm::Path: (void)runPathServed( sd, served, /*inForBlock=*/true ); break;
            case rw::GraphSubjectForm::Callers: (void)runCallHierarchy( sd ); break;
            case rw::GraphSubjectForm::Common: (void)runConnect( sd ); break;
        }
    };
    // The bare verb's answer is shaped by main.cpp's whole-stdout compact layer (runWithCompactLegend), which skips --for; so
    // the verb is captured here and compacted by the same applyCompactDialect + compactLegendHint, and the block carries the
    // bytes the bare call prints. CR 4396503866: the verb is captured under EVERY legend, because the open tag's name_test_hops= is
    // read off the rows it printed. A capture that cannot be set up emits the verb's FULL legend and an open tag without it.
    std::fflush( stdout );   // everything before the block is out before stdout is pointed at the capture
    std::FILE* const capture = std::tmpfile();
    const int        saved   = capture != nullptr ? rw::os::dup( STDOUT_FILENO ) : -1;
    if( capture == nullptr || saved < 0 || rw::os::dup2( rw::os::fileno( capture ), STDOUT_FILENO ) < 0 )
    {
        if( sub.legend == "compact" )
        {
            DISCLOSE( Diagnostics::answerUnchanged, "the full legend is a correct superset of the compact one: only the cost grows",
                      "appendSubjectGraphVerbBlock: no capture buffer — the graph verb's FULL legend is emitted" );
        }
        if( args->form == rw::GraphSubjectForm::Path )   // CR 4396503866: the open tag cannot read the rows, so a by-name hop into a test file goes unmarked
        {
            rw::emitTo( stderr, "ripwire: --for: no capture buffer for the graph verb — the graph_verb block omits name_test_hops= (a path hop matched by name into a test file is not marked)\n" );
        }
        if( saved >= 0 ) { rw::os::close( saved ); }
        if( capture != nullptr ) { std::fclose( capture ); }
        rw::emitRaw( stdout, rw::graphSubjectOpenXml( *args ).c_str() );
        std::fflush( stdout );
        runVerb();
    }
    else
    {
        runVerb();
        std::fflush( stdout );
        rw::os::dup2( saved, STDOUT_FILENO );
        rw::os::close( saved );
        std::string doc;
        std::rewind( capture );
        char buf[ 65536 ];
        for( std::size_t got; ( got = std::fread( buf, 1, sizeof( buf ), capture ) ) > 0; )
        {
            doc.append( buf, got );
        }
        std::fclose( capture );
        if( sub.legend == "compact" )
        {
            (void)rw::applyCompactDialect( doc, ::compactLegendHint( sub, doc ) );   // not shaped → the bytes as emitted (the DEFAULT posture's rule)
        }
        // the open tag goes out after the verb ran: name_test_hops= (S5) is read off the rows it printed
        const std::size_t nameTest = args->form == rw::GraphSubjectForm::Path ? rw::graphSubjectNameTestHops( doc ) : 0;
        rw::emitRaw( stdout, rw::graphSubjectOpenXml( *args, rw::GraphSubjectOpen{ .nameTestHops = nameTest } ).c_str() );
        std::fwrite( doc.data(), 1, doc.size(), stdout );
    }
    rw::emitRaw( stdout, std::string( rw::kGraphSubjectCloseXml ).c_str() );
}

std::optional<int> runForLensPass( const MainDispatch& d, rw::LensRanking lr, const ForLensPassMode& mode )
{
    using namespace rw;
    const std::string forAtStamp( mode.forAtStamp );
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::string&                root         = d.root;
    const std::vector<WorkspaceRoot>& ws           = d.ws;
    const std::vector<std::uint32_t>* fanInPtr     = d.fanInPtr;
    const std::vector<char>*          impurePtr    = d.impurePtr;
    const std::vector<std::uint8_t>*  testedPtr    = d.testedPtr;
    const std::vector<std::uint32_t>* ampPtr       = d.ampPtr;
    std::vector<std::uint32_t>&       forChurn     = d.forChurn;
    RedactCounts&                     redactCounts = d.redactCounts;
    RedactCounts*                     redactPtr    = d.redactPtr;
    const rw::notes::NoteIndex*      notesPtr     = d.notesPtr;   // L3: surfaces <note> children on the emitted symbols/files
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool             flSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view flRootArg    = flSingleRoot ? cfg.roots[0] : std::string_view();

    // --for=TASK: the task lens — a ranked, signatures-only inventory of the building blocks relevant
    // to the task (with descriptive cx/in metrics), framed for reuse. The evidence-optimal bundle
    // (signatures > bodies, ranked best-first, "compose from these" — CrossCodeEval/eWASH/De-Hallucinator).
    // Emits multiple sibling blocks (sigs, lego, compose) — wrapped in <ctx> so the output is a single
    // valid XML document (G4). The default map (plain ripwire <dir>) never reaches this path.
    if( !cfg.forTask.empty() )
    {
        // ROUTING (now the DEFAULT): a deterministic, confidence-gated query-shape classifier picks the BASE
        // ranker for THIS query — name-exact BM25 when the query NAMES a symbol (identifier syntax, or every
        // content word is a symbol name), else the subtoken+body default (lexical.h chooseForRanker). The
        // confidence gate makes routing SAFE on both query shapes (--eval-retrieval: routed tracks the better
        // ranker on identifier AND conceptual queries), so it defaults ON. --no-route forces subtoken+body (the
        // pre-default behavior). Compose order with --anchor: ROUTE picks the base lens rank, then ANCHOR
        // expands that base via the graph walk. Under --no-route lensRank is the subtoken+body default exactly
        // as before → byte-identical output (golden neutrality preserved for the un-routed path).
        // H2 (B0 r2): --for's consumers only read the top-K of this rank (K = the bundle's self-limit:
        // forTopN, or --top-k for the candidates export) PLUS every interface (packLego ranks all
        // implementor-bearing symbols by this vector), so lexicalScores may safely skip symbols that
        // provably cannot enter that top-K (exact MaxScore pruning — emitted bytes are identical).
        // Full-distribution consumers force exhaustive scoring: --adaptive scans the whole positive
        // score distribution for the cliff, --anchor seeds PPR personalization from it.
        // ROUTING + anchoring + the B8 mention anchor + the opt-in B3 co-change prior all live in
        // computeLensRanking (shared with runPackTask so the ranking is defined once). Compose order with
        // --anchor: ROUTE picks the base lens rank, then ANCHOR expands it; mention/co-change run after.
        // (the ranking itself — computeLensRanking — runs ONCE, in runForLens: every payment-mode render shares it)
        std::vector<float> lensRank  = std::move( lr.rank );
        const bool         forBodyCeiling   = cfg.maxTokens > 0 && cfg.detail > 0;   // the kShapingVerbs carve-out, read once (e= and the docs reorder share it via serialize.h explicitCeilingTighterThanDefault)
        // code above docs (filter.h): the routed path on a question that does not ask about docs — the shown set's REORDER
        const bool         forDocsAfterCode = !cfg.noRoute && !taskAsksAboutDocs( cfg.forTask ) && !std::getenv( "RIPWIRE_NO_DOCS_AFTER_CODE" )
                                              && rw::docsAfterCodeFitsCeiling( cfg.tokenBudget > 0 ? std::size_t( cfg.tokenBudget ) : 0u, forBodyCeiling );   // not under a tight explicit ceiling (uncharged note)
        const std::string  routeNoteRaw = std::move( lr.routeNote ); // verbatim; lands ONLY in route= (attribute-escaped) + the JSON twin — L1: the comment no longer echoes it
        const std::string  mentionNote( std::move( lr.mentionNote ) );
        const std::string  boostNote( std::move( lr.boostNote ) );
        const std::string  sibliftNote( std::move( lr.sibliftNote ) );
        const std::string  expandNote( std::move( lr.expandNote ) );
        const std::string  docMentionNote( std::move( lr.docMentionNote ) );
        const bool         conceptualRoute = isConceptualRoute( lr.routeTag );   // see the predicate for what "no-route" means here
        // the route's own anchors, resolved — read ONLY by the T3 auto-body allowance below (anchor-only)
        const std::vector<RouteAnchorDef> routeAnchorDefs( std::move( lr.anchorDefs ) );
        // R4: weak-result honesty signal — the top match's RAW lexical score (pre-anchor/mention/cochange,
        // see computeLensRanking) falls below kWeakLexicalScoreThreshold, so the ranking below this header
        // rests on thin-to-no textual evidence. Read below (with est_tokens) into the header comment.
        const bool         forWeak = lr.maxLexicalScore < kWeakLexicalScoreThreshold;

        // R6 (A4-R6) — --format=candidates: a FLAT top-K export of THIS ranked set for an external reranker
        // (identity + score + signature, no lens extras). A single <candidates> root (G4-clean), so it bypasses
        // the whole <ctx> lens bundle below. Capped by --top-k. Deterministic (score desc, id asc).
        //
        // §P12.2 fix: --adaptive used to no-op here (this block returned before the cliff-cut logic below ever
        // ran). emitCandidates() now cuts BEFORE the bypass, full-distribution scan like --for's own
        // default-map cut (the ceiling is --top-k, not the 40-row lens cap).
        // L-W: `--for=TASK --limit=N` (offset=M pages it) is the FILE-GRAIN WIDENING PAGE — one <f> row per
        // positive-score file, ranked file-first (forpage.h says how), the follow-up the routing-loop ladder
        // showed completes answers where a body cannot. It owns its own <files> root, so it bypasses the whole
        // <ctx> bundle below; cli.h refuses every bundle-shaping flag beside it rather than ignoring one.
        // PAGING-POC (issue #294): under --token-budget an explicit window is NOT the file page — it is
        // the BUDGETED-BUNDLE CANDIDATE PAGE, served by the shared inline below. The file
        // page keeps every windowless-budget call exactly as forwidencheck pins it.
        if( ( cfg.pageLimit > 0 || cfg.pageOffset > 0 ) && cfg.tokenBudget == 0 )
        {
            const ForFilePage page    = computeForFilePage( ing, lensRank, lr.evidence );
            const std::string pageXml = renderForFilePageXml( ing, page, ForPageRenderParts{ cfg.forTask, ctxRootOpen( cfg.forTask, routeNoteRaw, flRootArg ),
                                                                                              forCoveragePct( lr.evidence, topLensId( lensRank ) ),
                                                                                              cfg.pageLimit, cfg.pageOffset, flRootArg, cfg.legend == "compact" } );
            std::fwrite( pageXml.data(), 1, pageXml.size(), stdout );
            return 0;
        }

        if( cfg.candidates )
        {
            // §A4e/§A4f: the export carries the ranking's provenance — which ranker ran, how many mention
            // anchors moved it, and (the signal that used to be XML-comment-only) whether the whole ranking
            // rests on evidence too thin to trust.
            emitCandidates( stdout, ing, lensRank, cfg.topK, cfg.adaptive, /*scanFullDistribution=*/true,
                            CandidateProvenance{ lr.routeTag, lr.anchorLifts, forWeak, lr.docTierTag }, redactPtr, flRootArg );
            reportRedactions( stderr, redactCounts );    // W3-N1: <sig> is now a redacting seam — this export must disclose its own tally
            return 0;
        }

        // G4: the task text is echoed into an XML comment, where "--" is ill-formed (and "-->" would terminate
        // the comment early). W3FIX M3: the hand-rolled '--' collapse scrubbed dashes and NOTHING else, so a C0
        // byte or invalid UTF-8 in the task made xmllint reject the document and a '\n' put a raw newline outside
        // CDATA — xmlCommentText (serialize.h) is the ONE scrub for all three, shared with --pack-task / MCP
        // `for` / --exemplar / --from-trace. Byte-identical on control-free input. (L1: the route note no
        // longer rides in the comment — route= carries it verbatim, attribute-escaped by ctxRootOpen, and
        // the JSON sibling keeps the same RAW text.)
        const std::string taskNote = xmlCommentText( cfg.forTask );
        int forTopN = cfg.packTopN > 0 ? cfg.packTopN : kForLensDefaultTopN;   // F-03: the cap the MCP `for` twin reads too

        // Ranking-confidence disclosure (paper-shape lane; arXiv 2607.24882 — abstention/confidence is the
        // unsolved retrieval axis: a retriever must be able to tell the caller when its own ranking is not
        // trustworthy). DERIVED, NEVER SCORED: this is the SAME adaptiveCut gap statistic --adaptive cuts
        // at, computed once here (the --adaptive block below reuses it — one call, identical parameters, so
        // the disclosure and the cut cannot disagree). Disclosure only: nothing below reads `forCut` to
        // change what is served. The mapping to high/low happens after the relevance floor, where the final
        // served head size is known.
        const AdaptiveCut forCut = adaptiveCut( lensRank, 5, std::size_t( forTopN ), /*scanFullDistribution=*/true );

        // T14 (docs/research/adaptive-short-query.md): a name-exact route against a large pool of
        // identically-named, unrelated symbols can clear the cliff on TIE-BREAK order rather than
        // relevance — see lexical.h isAdaptiveHomonymDecline for the measured threshold and why. Computed
        // from the SAME forCut above (no second scorer), read by both the --adaptive block below (whether
        // to actually decline the narrowing) and deriveForConfidence below (confidence must not say "high"
        // on a cliff it declined to trust).
        //
        // review rv-t14a.md finding 1 (HIGH): this used to read `!conceptualRoute`, a DIFFERENT question
        // (isConceptualRoute only recognizes "subtoken+body") whose negation is also true on the THIRD
        // route state, "no-route" (--no-route's struct default, packtask.h LensRanking::routeTag) — so
        // --no-route --adaptive mislabeled an un-routed ranking as name-exact and declined + fabricated a
        // same-name count on a genuine cliff. isNameExactRouteTag is the one predicate emitCandidates and
        // MCP `for` already used their own way; all three now share it (lexical.h).
        const bool forHomonymDecline = isAdaptiveHomonymDecline( isNameExactRouteTag( lr.routeTag ), forCut, 5 );

        // --adaptive (lever 2): cut the returned set at the relevance CLIFF — the largest
        // relative score gap in [floor, ceiling] (Adaptive-k). A sharp query keeps few; a flat/broad query
        // (no knee) hits the ceiling and is kept as-is (cap-and-note). floor=5, ceiling=forTopN. The cut
        // narrows forTopN BEFORE packSignatures selects, so the emitted set is exactly the kept head. The
        // note is legible in the header so the reader knows WHY the set is the size it is. Without --adaptive,
        // forTopN is untouched → byte-identical output (golden neutral).
        std::string adaptiveNote;
        if( cfg.adaptive )
        {
            const int         ceil = cfg.packTopN > 0 ? cfg.packTopN : kForLensDefaultTopN;
            // scanFullDistribution=true: --for caps at 40, so a sharp query's real cliff often sits BELOW the
            // cap while the top-40 head is flat — a scan bounded at the cap finds no knee and keeps 40/40
            // (the recorded "inert on --for"). Scan the RAW lexical (BM25) distribution BEFORE the cap so the
            // true cliff is seen, then clamp kept into [floor, ceiling]. lensRank IS the raw lexical score here
            // (subtoken+body or name-exact; --anchor's blend is opt-in and handled by keeping this the same call).
            // `forCut` above is exactly this call (same scores, floor, ceiling, full-distribution scan),
            // hoisted so the confidence disclosure derives from the statistic --adaptive acts on.
            const AdaptiveCut& ac = forCut;
            char nb[ 200 ];
            if( forHomonymDecline )
            {
                // decline to narrow: forTopN stays at `ceil` (the pre-cut default), never ac.kept — the
                // fallback IS the default top-K, not a smaller, equally-arbitrary slice of the same pool.
                // Stated in the ANSWER (this note), not only stderr — T14 requirement 1.
                rw::formatTo( nb, sizeof( nb ), " [adaptive: declined - {} symbols share this exact name; the "
                               "score gap here is tie-break order, not relevance - kept the default top-{}]",
                               ac.positiveHits, ceil );
            }
            else
            {
                forTopN = int( ac.kept );
                if( !ac.hitCeiling && ac.cliffRank < ac.kept )
                {
                    rw::formatTo( nb, sizeof( nb ), " [adaptive: kept {} of {} - sharp cliff at rank {} ({}% drop), clamped up to the floor of {}]",
                                   ac.kept, ceil, ac.cliffRank, ac.dropPct, ac.kept );
                }
                else if( !ac.hitCeiling )
                {
                    rw::formatTo( nb, sizeof( nb ), " [adaptive: kept {} of {} - cliff at rank {}, {}% drop]",
                                   ac.kept, ceil, ac.cliffRank, ac.dropPct );
                }
                else if( ac.positiveHits <= ac.kept )
                {
                    rw::formatTo( nb, sizeof( nb ), " [adaptive: kept {} of {} - only {} symbols matched this query (sharp query, short tail)]",
                                   ac.kept, ceil, ac.positiveHits );
                }
                else
                {
                    rw::formatTo( nb, sizeof( nb ), " [adaptive: kept {} of {} - no relevance cliff (broad query saturates the score); capped at the ceiling]",
                                   ac.kept, ceil );
                }
            }
            adaptiveNote = nb;
        }

        // LB-A (r10 §5) — THE RELEVANCE FLOOR: shrink the quota past its zero-score tail rather than pad
        // with it. ADMISSION, NOT RANKING — no score moves, only where the (score desc, id asc) head
        // stops. Applied HERE because lensRank is final at this point and forTopN is the one knob every
        // consumer below reads. The measurement and the rest of the reasoning: serialize.h,
        // relevanceFloorCut. The note lands in the header comment beside --adaptive's.
        auto [ flooredTopN, floorNote ] = relevanceFloorCut( lensRank, forTopN );
        forTopN = flooredTopN;

        // the mapping, the two derived strings, and the reasoning behind both live ONCE in
        // deriveForConfidence (above runForLens) — forTopN is final here (floor cut applied), which is
        // what the completeness ground needs.
        // THE BUNDLE'S RESOLVED SURFACE: the top-N ids by lensRank — the exact set <sigs> selects. Three
        // consumers now: the S5-E HAS-A compose view, the B6.3 route view, and (§P3) the <lego> scope
        // filter, which keeps only interfaces this surface actually reaches. §B1.4 (capture-audit-4):
        // HOISTED above the --json branch — both dialects need it now, XML to RENDER lego/compose/routes,
        // JSON to COUNT them without rendering (see below). Computed once, kept alive for the
        // direct-emission degrade paths further down too.
        std::vector<NodeId> lensSurfaceIds;
        {
            const std::size_t S = ing.symbols.size();
            lensSurfaceIds.resize( S );
            for( NodeId i = 0; i < S; ++i )
            {
                lensSurfaceIds[i] = i;
            }
            // A4-F23c: score-only sort left ties straddling the cut stdlib-dependent. Use the (score desc, id
            // asc) total order (same key packSignatures selects with) so the surface set is deterministic.
            rw::sortutil::radixSortByScoreDescId( lensSurfaceIds, lensRank );
            const std::size_t cap = std::min<std::size_t>( std::size_t( forTopN ), S );
            lensSurfaceIds.resize( cap );
        }

        ForConfidence forConf = deriveForConfidence( forCut, forTopN, forHomonymDecline );

        // ── THE BUDGETED-BUNDLE CANDIDATE PAGE (paging PoC, issue #294): budget + explicit window ⇒ the
        // resumable candidate page (shared inline; the un-paged bundle below stays byte-identical).
        if( cfg.tokenBudget != 0 && ( cfg.pageLimit > 0 || cfg.pageOffset > 0 ) )
        {
            // W3-N1/#294 review: the page redacts through packSignatures — the tally must be reported,
            // exactly like the --json early return below (a redacted credential must never be silent).
            const std::string rankFlags = forPageRankFlagArgv( cfg );
            const int pageRc = emitForCandidatePage( ing, lensRank, forCut, rw::ForCandidatePageReq{ cfg.forTask, "--for=", rankFlags,
                                         /*pasteHandle=*/true, /*compactLegend=*/cfg.legend != "full",
                                         routeNoteRaw, flRootArg, redactPtr,
                                         flSingleRoot ? std::string_view( gitstamp::stampAt( std::string( root ) ) ) : std::string_view(),
                                         cfg.tokenBudget, cfg.pageLimit, cfg.pageOffset } );
            reportRedactions( stderr, redactCounts );   // W3-N1: the page redacts — the tally reports
            return pageRc;
        }
        // L-W: coverage= rides the SAME sentence and the SAME byte exemption as confidence=/margin_pct= — but ONLY
        // on a THIN answer (owner decision 2026-09-12: present-only). The thin verdict is decided HERE, from the
        // resolved surface above and the top symbol's term share, and it drives three things at once: the
        // attribute, its legend clause (present-only, so the clause never explains an absent attribute) and the
        // r=1 row's next= (the widening page instead of the body). A confident answer carries none of them and is
        // byte-identical to the pre-L-W bundle. Nothing scored ⇒ no top symbol ⇒ thin by the files clause, and no
        // coverage= to print (a fabricated 0 is what non-negotiable #3 forbids).
        const int  forCoverage   = forCoveragePct( lr.evidence, topLensId( lensRank ) );
        const bool forThin       = forAnswerIsThin( forCoverage, distinctFilesOf( ing, lensSurfaceIds ) );
        const bool forCoverageOn = forThin && forCoverage >= 0;
        if( forCoverageOn )
        {
            forConf.attrs += " coverage=\"" + std::to_string( forCoverage ) + "\"";
            forConf.note  += kForCoverageLegend;
        }
        // The confidence pair's own bytes, captured BEFORE the budget clause below is appended — see the
        // charging note there for why the two disclosures are charged differently.
        const std::size_t confidenceOwnBytes = forConf.attrs.size() + forConf.note.size();
        // P1 (L7): the two halves separately, captured at the SAME early point — the compact dialect emits its own
        // short clause (kForCompactLegendConfidence) in place of the early note, and the exemption below must
        // subtract what that dialect emitted, never the appended budget clause (which is charged, see below).
        const std::size_t confidenceEarlyAttrsBytes = forConf.attrs.size();
        const std::size_t confidenceEarlyNoteBytes  = forConf.note.size();

        // H9 (capture-audit 2026-09-04): the CEILING this bundle was shaped against, named on the root.
        // `--for --token-budget=1500` re-shapes the whole answer — the root goes `bundle="compact"
        // bodies="0" reason="budget"` — and the audit found that N itself appeared nowhere, so a reader
        // could see THAT a budget cut the bundle but never WHICH one, and could not tell a 1500-token cut
        // from a 15,000-token one. `--pack-task`, the sibling that takes the same flag, has always printed
        // `budget_tokens=`; this is the same attribute, on the verb that was missing it. `--max-tokens` is
        // read by --for only under --detail=N (cli.h's kShapingVerbs carve-out), so `max_tokens=` is
        // charged to exactly that shape and absent otherwise — an attribute that appeared on a run where
        // the flag was inert would be its own false disclosure.
        //
        // CHARGING, and why it splits from the confidence pair's. Both ride forConf, but only the
        // confidence half is EXEMPT from the byte budget (confidenceExemptBytes is taken from
        // confidenceOwnBytes above, captured before this append): confidence= must survive a tight ceiling
        // because it qualifies the ANSWER — the fordisclosurecheck precedent. These two attributes qualify
        // the BUDGET, and a budget disclosure that made the bundle exceed its own budget would be the
        // funniest possible way to fail this finding. So they are charged like any other bytes, and the
        // clause is written terse for the reason forLensHeaderText's W3-S note records at length: this
        // header has a MEASURED hard byte constraint (fornotesbudgetcheck), where 150 bytes of prose is
        // 2% of a 1550-token ceiling. Gate: test/budgetpolicycheck.sh arm (B).
        const bool forGateBudget  = cfg.tokenBudget > 0;
        const bool forEndLines = rw::endLinesFitCeiling( forGateBudget ? std::size_t( cfg.tokenBudget ) : 0u, forBodyCeiling );   // e= rides?
        if( forGateBudget )
        {
            forConf.attrs += " budget_tokens=\"" + std::to_string( cfg.tokenBudget ) + "\"";
        }
        // round C: the body ceiling's two disclosures (this attribute and its note below), measured so a soft target's cut can
        // be priced without them — a body ceiling never moves a row (formaxtokenscheck (E))
        std::size_t forBodyCeilingDisclosureBytes = 0;
        if( forBodyCeiling )
        {
            const std::size_t before = forConf.attrs.size();
            forConf.attrs += " max_tokens=\"" + std::to_string( cfg.maxTokens ) + "\"";
            forBodyCeilingDisclosureBytes += forConf.attrs.size() - before;
        }
        // forbudget-soft (owner decision 2026-10-14): budget_tokens= is a SOFT target now — rows stop once it is reached and
        // nothing else is shaped by it — so its reading says so (kForSoftBudgetNote); max_tokens= stays the hard body ceiling.
        // No "--" in these strings: they ride inside an XML comment, where a double hyphen is ill-formed (G4). The flags are
        // named without their dashes for exactly that reason.
        if( forGateBudget )
        {
            forConf.note += rw::kForSoftBudgetNote;
        }
        if( forBodyCeiling )
        {
            const std::size_t before = forConf.note.size();
            forConf.note += " [max_tokens=: the token ceiling the detail bodies were shaped against]";
            forBodyCeilingDisclosureBytes += forConf.note.size() - before;
        }

        // §L10b: mention_anchored=/doc_mentions= — the machine form of mentionNote/docMentionNote, EACH
        // present only when its own note fired (unlike confidence=/at=, these are not facts of every
        // ranking — a query that anchors or surfaces no docs carries neither). Same lr.anchorLifts the
        // candidates root's anchored= already reads (§A4f); lr.docMentionCount is new (§L10b, packtask.h).
        // Both gates read the COUNTS, not the note strings — mention_anchored="0" is the fabricated zero
        // non-negotiable #3 forbids, and a note can now be non-empty on a run that anchored nothing.
        std::string mentionDocAttrsStr;
        if( lr.anchorLifts > 0 )
        {
            mentionDocAttrsStr += " mention_anchored=\"" + std::to_string( lr.anchorLifts ) + "\"";
        }
        if( lr.docMentionCount > 0 )
        {
            mentionDocAttrsStr += " doc_mentions=\"" + std::to_string( lr.docMentionCount ) + "\"";
        }
        // The INDEXING caps do NOT join this string — they are spliced onto the root after the sigs ladder,
        // where budget_bytes= goes and for its reason (see there).

        // M10: --for reads git for the per-file churn= column (folded onto the bundle below, mined once in
        // main.cpp's resolveHistoryWalk pass) and, before this fix, carried no anchor — an agent
        // quoting churn= into a handoff had nothing checkable to pin it to. Single-root only (same gate
        // flRootArg itself uses): "" on multi-root or a non-git root, same silence-means-omitted convention
        // every other stamped verb follows. ALWAYS present when non-empty, like confidence= — a root fact,
        // never budget-dropped, which is why it rides the SAME byte-exempt reserve as confidence= below.
        // Computed once per RUN, in runForLens (both dialects need it: XML wraps it as an attribute, JSON quotes
        // it bare), so a --token-budget run that renders in up to three payment modes pays the stamp's two git
        // subprocesses once, not once per render (CodeRabbit on #383, verbs_for.h:3843; test/forrankordercheck.sh (10c)).
        const std::string forAtAttrStr = forAtStamp.empty() ? std::string() : ( " at=\"" + forAtStamp + "\"" );

        // R2-AF (round 2, S4): resolved once, ahead of the header build below, so its legend clause can be
        // present-only in BOTH dialects. The rows are RENDERED here too (forHdrXml) and emitted, as that same
        // string, right after headerStr is flushed and before <sigs>. PRICED like every other emitted section
        // (CodeRabbit 4054594308): its bytes join est_tokens (rootFinish.nonHeaderMarkupBytes), both halves of
        // the ceiling ladder, and the residual the --detail bodies, the auto enrichment and the explicit-regime
        // tail are sized from. Rendered after the ceiling decisions they used to be missing from every one of
        // those sums, so a task naming several long paths printed an est_tokens that left out ~1.6 KB of rows.
        // NOT charged against the <sigs> trim allowance (fixedBytes/sigsBudget below), which keeps the ranked
        // head byte-identical with and without the rows and identical to the MCP twin's (mcpverbs.h forTaskText,
        // whose sig ledger does not see them either): a lookup the task asked for by name is not paid for in
        // ranked rows. What bounds it is forNamedHeaderRows' own ENSURES(out.size()<=allNamed.size())
        // (mention.h): at most one row per distinct file the task text names, deduplicated. The "+365 B" figure
        // is this ROUND's own measurement rule (read by the external eval/scoring harness that grades this
        // round, not by ripwire) and MUST NOT be enforced here: a runtime byte cap on these rows could drop a
        // correct row or make a correct answer wrong, which owner policy forbids a cap from doing (caps are
        // blow-up guards only). Not part of the --json dialect (that branch returns above the emission); the
        // extra resolve and render on a --json call are cheap and unused, not wrong.
        const std::vector<rw::ForNamedHeaderRow> forHdrRows = rw::forNamedHeaderRows( ing, cfg.forTask );
        const std::string                        forHdrXml  = renderForHdrRowsXml( ing, forHdrRows, flRootArg );
        // HEAD ROUND-ROBIN (serialize.h reorderHeadRoundRobin): the routed subtoken+body answer to a question that names no
        // indexed file. Only the shown <sigs> rows reorder: the fold and the hops keep walking lensSurfaceIds in score order —
        // measured on the rank-gates 44 rows (lane hrr report): hops and fold that followed the reordered head lost two graded
        // ✓ rows (their strongest rows' callees and bodies left the hop window); in score order they lose none.
        const bool forHeadRR = rw::forHeadRoundRobinOn( conceptualRoute, rw::taskNamesIndexedFile( ing, cfg.forTask ),
                                                        cfg.tokenBudget > 0 ? std::size_t( cfg.tokenBudget ) : 0u, forBodyCeiling );

        // H1 (B0 r2): the bundle is emitted under a GLOBAL payload budget (serialize.h kForPayloadBudgetBytes; an
        // EXPLICIT --token-budget=N overrides it at the same conservative byte rate the --max-tokens fitter uses).
        // Trimming happens inside <sigs> only, so the header is built as a string and the sibling blocks (lego,
        // compose) are rendered FIRST — their exact byte cost is subtracted from the bundle budget before
        // packSignatures enforces the remainder. Emission ORDER is unchanged (header, sigs, lego, compose, bodies,
        // </ctx>): when nothing trims, the output is byte-identical to the pre-H1 path. W3FIX H2: the header goes
        // through forLensHeaderText (above) rather than being appended once, because the ceiling ladder below has
        // to PRICE a header without the comment's task echo or without route= and then emit that exact shape.
        const std::string        rootOpenStr = ctxRootOpen( cfg.forTask, routeNoteRaw, flRootArg );
        // T3 (pre-registered: docs/EVALS.md §4, T3 round): terminal-by-default — the auto <bodies> mode is on
        // unless the caller took an explicit body posture (--detail=N) or opted out (--signatures-only). The
        // --json and --format=candidates dialects never reach the auto machinery (candidates returned above;
        // --json returns before it below), so this mode is an XML-bundle fact only.
        const bool         autoBundleMode = cfg.detail == 0 && !cfg.signaturesOnly;
        // COMPACT conceptual serving (docs/EVALS.md, the T3 route-narrowing round) — see planForEnrichment.
        const ForEnrichmentPlan plan = planForEnrichment( autoBundleMode, conceptualRoute, cfg.autoBodies );
        // NOT const: the enrichment block below may drop the LEGEND (autoBundle/compactBundle=false) and
        // rebuild the header without it — the ladder's later rebuilds read this struct through
        // buildForHeader and must honor that decision. One cause reaches it now: the chargeSection degrade
        // (surfaceOff — no attribute either); forbudget-soft retired the exhausted-ceiling switch (a soft target
        // keeps the legend and, on the compact route, serves the hops cut marker instead — hopsCutMarker below).
        // A tight explicit budget never turns the disclosure off — test/fordisclosurecheck.sh.
        // PR #215 review: does any row this bundle could serve carry sc=? Both dialects' sc= readings are
        // present-only on this, and the dropped-legend note names sc= only when there was a reading to lose.
        // Decided from the RANKED SET and before the header is built, because the un-budgeted path ships the
        // header built here and never rebuilds it. Deliberately an OVER-approximation: the byte ladder may still
        // trim the only scoped row, and a reading with nothing to define costs 29 B, while the reverse costs a
        // reader an attribute with no definition anywhere in the document.
        bool forScPresent = false;
        for( std::size_t i = 0; i < ing.symbols.size() && !forScPresent; ++i )
        {
            forScPresent = lensRank[i] > 0 && rw::hasScopeAttr( ing.symbols[i] );
        }
        // packCompose emits an edge whose owner or member type is on the lens surface, a subset of the ranked set.
        const auto isRanked = [ & ]( rw::NodeId id ) noexcept { return id < lensRank.size() && lensRank[ id ] > 0; };
        const bool forComposePresent = std::ranges::any_of( g.composeEdges, [ & ]( const rw::ComposeEdge& ce )
                                                            { return isRanked( ce.ownerSym ) || isRanked( ce.typeSym ); } );
        // TRAIN 9: the same shape for the two attributes the merged stack put on a default first screen. Both are
        // over-approximations by design — a clause with nothing to define costs a reader one clause, an undefined
        // first-screen attribute costs them the meaning (the scPresent note above states the trade).
        bool forLegoPresent  = false;
        bool forLayerPresent = false;
        for( std::size_t i = 0; i < ing.symbols.size() && !( forLegoPresent && forLayerPresent ); ++i )
        {
            if( lensRank[i] <= 0 )
            {
                continue;
            }
            if( i < g.implementors.size() && !g.implementors[i].empty() )
            {
                forLegoPresent = true;
            }
            if( *rw::builtinLayer( rw::rootRelPath( ing, ing.symbols[i].fileId ) ) != '\0' )
            {
                forLayerPresent = true;
            }
        }
        // #60: the same shape again, and READ FROM THE RANKED SET like its three siblings above. The first
        // draft tested the whole symbol table on the theory that a <h> hop's owner need not be ranked; that
        // was simply wrong — the compact bundle's hop candidates ARE the positive-score head of the ranked
        // surface (buildForCompactHops), so an owner reaches this document as a <d> row or as a <h> row of
        // one, and both are ranked. Corpus-wide cost ~40 tokens of clause on EVERY --for answer from any
        // tree holding one top-level call (this repo; 72% of vue-core's files), which is the mirror-image
        // waste of the rule this header states: a legend that defines something the document did not emit.
        // #60: THE ROW SET, not the ranked set — and this one is deliberately NOT its siblings' shape.
        // `scPresent`/`legoPresent`/`layerPresent` test rank>0 corpus-wide and let the over-approximation
        // fall the safe way, which costs a clause nobody needed. This clause is ~154 B (compact) / ~250 B
        // (full) on the tool's most-used verb, and rank>0 is true for a module-scope owner on any tree
        // holding one top-level call — every --for answer on THIS repository paid it, with no owner row in
        // any of them (measured over six queries). So it reads the rows the document can actually carry:
        // `lensSurfaceIds` is the rank-ordered surface, `<d>` rows are its top-forTopN head (the adaptive
        // cut has already narrowed forTopN here, "so the emitted set is exactly the kept head") and the
        // compact `<hops>` rows are its rank>0 head capped at kPackTaskBodyCandidates — so the union is one
        // head walk. What is left over-approximating is only the H1 BYTE ladder trimming inside that head,
        // which is the residual a header built before its payload cannot avoid.
        const std::size_t forRowHead = std::max( std::size_t( forTopN > 0 ? forTopN : 0 ), rw::kPackTaskBodyCandidates );
        bool              forModScopePresent = false;
        bool              forEndLinePresent  = false;
        for( std::size_t i = 0; i < lensSurfaceIds.size() && i < forRowHead && !( forModScopePresent && forEndLinePresent ); ++i )
        {
            const rw::NodeId sid = lensSurfaceIds[i];
            if( lensRank[sid] <= 0.0f )
            {
                continue;
            }
            forModScopePresent = forModScopePresent || ing.symbols[sid].kind == rw::SymKind::ModuleScope;
            forEndLinePresent  = forEndLinePresent || ( forEndLines && rw::mayCarryEndLine( ing.symbols[sid] ) );
        }
        // FE-B: may a <calls> row of this bundle carry via="name"? Only the sections that render <calls> can, and each one's
        // node set is known before the header: the compact route's hop ids, T3's auto-body candidates, or --detail's head
        // (autoBundleMode excludes --detail). Their name-only out-edges decide it — over-approximating only the byte ladder
        // and the 16-per-symbol cap inside those sections, never the rows the header itself lists.
        // owner-hop: THE QUESTION'S OWNER plan (forOwnerHopPlan), decided here, before the header, because the header's
        // qword clause and its via="name" question both read it; the compact route's <hops> renders exactly this plan.
        const ForOwnerPlan ownerPlan = ( autoBundleMode && plan.compact )
            ? forOwnerHopPlan( ing, g, cfg.forTask, lensSurfaceIds, lensRank, forCompactHopIds( lensSurfaceIds, lensRank ) )
            : ForOwnerPlan{};
        // for-body-slot: THE ONE OWNER BODY of an explanatory question (forowner.h forBodySlotOwner), decided here for the same
        // reason as the owner plan above: the header's slot clause reads it. The compact route only (an XML answer whose caller
        // chose no body posture: autoBundleMode excludes --detail/--signatures-only, plan.compact excludes --auto-bodies and the
        // name-exact route, which already serves the anchor's body).
        const rw::ForBodySlotOwner slotOwner = ( autoBundleMode && plan.compact && !cfg.json && rw::forBodySlotAsked( cfg.forTask ) )
            ? rw::forBodySlotOwner( ing, g.outOff, g.outTargets, cfg.forTask, lensSurfaceIds, lensRank )
            : rw::ForBodySlotOwner{};
        bool forViaPresent = false;
        bool forViaByOwnerOnly = false;   // owner-hop: the six ranked hop ids alone answer no, the owner rows switch it on
        bool forSplitPresent = false;     // attrib-multidef Q1: the same question for prov="split", over the same ids
        if( !g.outNameOnly.empty() || !g.outProv.empty() )
        {
            std::vector<rw::NodeId> viaIds;
            if( autoBundleMode && plan.compact )
            {
                // only the hops packHops gives a slot can carry a row (the hop-slot rule drops a hop whose every callee
                // edge is name-only, so its via="name" rows never print)
                const auto unslotted = [ & ]( rw::NodeId id ) { return !rw::hopSlotHasProvenEdge( g.outOff, g.outNameOnly, id ); };
                viaIds = forCompactHopIds( lensSurfaceIds, lensRank );
                std::erase_if( viaIds, unslotted );
                const bool rankedVia = rw::namesOnlyOutAny( g.outOff, g.outNameOnly, viaIds );   // the question without owners
                std::vector<rw::NodeId> ownerViaIds = ownerPlan.rowIds;   // owner rows carry <calls> too
                std::erase_if( ownerViaIds, unslotted );
                forViaByOwnerOnly = !rankedVia && rw::namesOnlyOutAny( g.outOff, g.outNameOnly, ownerViaIds );
                viaIds.insert( viaIds.end(), ownerViaIds.begin(), ownerViaIds.end() );
            }
            else if( autoBundleMode && plan.autoBodies )
            {
                viaIds = computeAutoBodyCandidateIds( ing, lensSurfaceIds, lensRank, routeAnchorDefs );
            }
            else if( cfg.detail > 0 )
            {
                viaIds = forDetailIds( ing, lensRank, cfg.detail, forTopN );
            }
            forViaPresent   = rw::namesOnlyOutAny( g.outOff, g.outNameOnly, viaIds );
            forSplitPresent = rw::splitArmsOutAny( g.outOff, g.outNameOnly, g.outProv, viaIds );
        }
        ForLensHeaderParts headerParts{ cfg.forTask, rootOpenStr, taskNote, adaptiveNote,
                                        mentionNote, boostNote, docMentionNote, sibliftNote, expandNote, floorNote,
                                        forConf.attrs, forConf.note, forAtAttrStr, mentionDocAttrsStr,
                                        cfg.anchor, plan.autoBodies, plan.compact, cfg.legend == "compact",
                                        /*tailLegend=*/true, /*idRouteLegend=*/true, flRootArg,
                                        /*hdrLegend=*/!forHdrRows.empty(), forScPresent, forComposePresent,
                                        forLegoPresent, forLayerPresent, forModScopePresent, forEndLinePresent, forViaPresent,
                                        ownerPlan.any(), forViaByOwnerOnly, slotOwner.any() };
        headerParts.splitPresent = forSplitPresent;   // attrib-multidef Q1 (a trailing member: the aggregate above keeps its order)
        // body-fold (forfold.h): the bodies of the top ranked rows, appended — decided here because the header's fold clause reads it.
        // The compact route's XML answer in the DEFAULT regime only: an explicit --token-budget is a size the caller named (that
        // answer stays byte-identical), and autoBundleMode already excludes --detail/--signatures-only/--auto-bodies. --max-tokens is
        // NOT read here (FIX1 B1: --for's notice says this answer ignores it — the detail bodies' ceiling — so it must not turn the
        // fold off either; shapingflagcheck (A)/(F)).
        const std::vector<rw::NodeId> foldIds = ( autoBundleMode && plan.compact && !cfg.json && cfg.tokenBudget <= 0 && rw::forBodyFoldOn() )
            ? rw::forBodyFoldCandidates( ing, lensSurfaceIds, lensRank, std::size_t( std::max( forTopN, 0 ) ), slotOwner.id )
            : std::vector<rw::NodeId>{};
        headerParts.bodyFoldPresent = !foldIds.empty();
        // mf1-nx (forcallerhop.h): the callers of the ONE function a name-exact answer bodies — decided here because the header's
        // clause reads it. The name-exact route's auto-bodies XML answer in the DEFAULT regime only, as the fold: an explicit
        // --token-budget is a size the caller named (that answer stays byte-identical), and autoBundleMode excludes --detail,
        // --signatures-only and --auto-bodies on the compact route (plan.autoBodies is the name-exact route's bundle).
        const std::vector<rw::NodeId> callerHopIds = forCallerHopIds( cfg, ing, g, lensSurfaceIds, lensRank, routeAnchorDefs,
                                                                      autoBundleMode && plan.autoBodies && isNameExactRouteTag( lr.routeTag ) );
        headerParts.callerHopPresent = !callerHopIds.empty();
        // mf1-nx wave 4 (fordispatchhop.h): the task-named calls a body candidate made through an interface receiver — the caller
        // hop's posture (name-exact auto bodies, default regime, XML), decided here because the header's clause reads it
        const std::vector<std::uint32_t> dispatchSites = ( autoBundleMode && plan.autoBodies && isNameExactRouteTag( lr.routeTag ) && !cfg.json
                                                           && cfg.tokenBudget <= 0 && rw::forDispatchHopOn() )
            ? rw::forDispatchSites( ing, g, computeAutoBodyCandidateIds( ing, lensSurfaceIds, lensRank, routeAnchorDefs ), cfg.forTask )
            : std::vector<std::uint32_t>{};
        headerParts.dispatchHopPresent = !dispatchSites.empty();
        // ep-manifest (epmanifest.h): the manifest entry-point groups that register a row of the ranked head — rendered here
        // because the header's clause reads it. The default regime and XML only, as the fold and the caller hop.
        rw::EpRender            epManifest;
        std::vector<rw::NodeId> epHead;   // the ranked head the clause was priced for; narrowed to the rows <sigs> emits once it renders
        // manifest-noncode (listedin.h): the manifest lines listing a file of that same ranked head, same regime, same re-pick
        rw::ListedRender listedIn;
        const bool       peerManifestRegime = autoBundleMode && !cfg.json && cfg.tokenBudget <= 0;
        if( peerManifestRegime && ( rw::forEpManifestOn() || rw::forListedInOn() ) )
        {
            for( std::size_t i = 0; i < lensSurfaceIds.size() && i < std::size_t( std::max( forTopN, 0 ) ); ++i )
            {
                if( lensSurfaceIds[i] < lensRank.size() && lensRank[ lensSurfaceIds[i] ] > 0.0f )
                {
                    epHead.push_back( lensSurfaceIds[i] );
                }
            }
            if( rw::forEpManifestOn() )
            {
                epManifest = rw::renderForEpManifest( ing, epHead );
            }
            if( rw::forListedInOn() )
            {
                listedIn = rw::renderForListedIn( ing, epHead, cfg.forTask );
            }
        }
        headerParts.epPresent     = !epManifest.xml.empty();
        headerParts.listedPresent = !listedIn.xml.empty();
        const auto buildForHeader = [ & ]( bool withRouteAttr, bool withTaskEcho, std::string_view extraNotes )
        { return forLensHeaderText( headerParts, withRouteAttr, withTaskEcho, extraNotes ); };
        std::string headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );

        // Q3 quality lens: fold churn (per-file) + clone-membership (per-symbol) onto the --for bundle, next
        // to the ccx/tested/amp already computed above. A4-P6: churn (12-month) was already computed above in
        // the SAME 18-month co-change popen (gitCoChangeAndChurn), so there is no second git subprocess here.
        // git-less ⇒ forChurn stays all-0 → churn= omitted. Guard sizing defensively (always sized above).
        if( forChurn.size() != ing.files.size() )
        {
            forChurn.assign( ing.files.size(), 0u );
        }
        // clone membership: 1 if the symbol is in any duplicate-clone group (same threshold as --clones default).
        std::vector<std::uint8_t> forClone( ing.symbols.size(), 0u );
        for( const CloneGroup& cg : findClones( ing, 40 ) )
        {
            for( NodeId m : cg.members )
            {
                if( m < forClone.size() )
                {
                    forClone[m] = 1u;
                }
            }
        }

        // IS-A: socket → bricks — for the interfaces THIS task actually reaches (§P3: the implementors map is
        // pre-scoped to lensSurfaceIds; withPaths keeps two same-named impls apart, exactly as --lego=TYPE
        // spells them). No interface reached ⇒ no <lego> element. Kept alive for the §P3×§P4 narrowing below
        // (XML render) and the §B1.4 count (JSON) — this is pure membership bookkeeping, never a redacting
        // seam, so hoisting it above the --json branch changes no dialect's redaction tally.
        std::vector<std::vector<NodeId>> legoScoped = legoImplementorsOnSurface( ing, g.implementors, lensSurfaceIds );

        // L-W (L-N): the r=1 row's next= names the file-grain widening page on the THIN verdict decided beside the
        // header above, and the body otherwise; "" keeps the --expand hint.
        const std::string forTopRowNext = forThin ? forWidenNext( cfg.forTask ) : std::string();

        // DEEP-TAIL d2, FOLD C (forbudget-soft round C): the file-grain tail is page 0 of the --for file page — one shared
        // model (forpage.h computeFileTail) for both dialects and the MCP twin, from the SAME ranking and term evidence the
        // `--limit=40` page uses, so the tail, its next= page and the page itself cannot disagree.
        const FileTail forFileTail = computeFileTail( ing, lensRank, lr.evidence, lensSurfaceIds, flRootArg, cfg.forTask );   // the DEGRADE paths' tail
        // H2H-Graft lane 2 (2026-09-07): the tail's rank rows exclude only the files of the sigs rows actually EMITTED (a row the
        // ladder trimmed must land in the tail, never nowhere).
        std::vector<NodeId> shownSigIds;

        // L2: --json — the ranking ("sigs") bundle, plus (§B1.4) a COUNT of what <lego>/<compose>/<routes>
        // would have held on this same surface. They still stay XML-only — rendering them for real would
        // mean a second redaction pass over interface method bodies the JSON dialect otherwise never takes —
        // but a reader can now tell "0, genuinely nothing here" from "dropped, ask for the XML dialect",
        // the notes_total precedent applied verbatim. jsonUnsupportedVerb already refused
        // --format=candidates/columnar/--detail, so reaching here with cfg.json means the plain lens bundle.
        if( cfg.json )
        {
            // §B1.3: --with-graph has no JSON dialect yet (the mermaid block is XML-only) — warn once and
            // continue without it, the same warn-and-continue shape --partition's --with-graph note (below,
            // runPackTask) already uses, rather than silently dropping the flag's effect with no tell at all.
            if( cfg.withGraph )
            {
                rw::emitRaw( stderr, "ripwire: --with-graph is not applied under --json (the mermaid graph block is XML-only for now) — emitted without it\n" );
            }

            std::size_t legoTotal = 0;
            for( const std::vector<NodeId>& impls : legoScoped )
            {
                if( !impls.empty() )
                {
                    ++legoTotal;
                }
            }

            std::vector<char> onSurfaceFlags( ing.symbols.size(), 0 );
            for( NodeId sid : lensSurfaceIds )
            {
                if( sid < onSurfaceFlags.size() )
                {
                    onSurfaceFlags[sid] = 1;
                }
            }
            const auto isOnSurface = [ & ]( NodeId sid ) noexcept -> bool
            { return sid < onSurfaceFlags.size() && onSurfaceFlags[sid] != 0; };

            // mirrors packCompose/packRoutes' own inSet membership test (serialize.h) verbatim, minus the
            // escaping/redaction/XmlWriter machinery — a COUNT, never a render, so it never touches redactCounts.
            std::size_t composeTotal = 0;
            for( const ComposeEdge& ce : g.composeEdges )
            {
                if( ce.ownerSym < ing.symbols.size() && ( isOnSurface( ce.ownerSym ) || isOnSurface( ce.typeSym ) ) )
                {
                    ++composeTotal;
                }
            }
            std::size_t routesTotal = 0;
            for( const RouteEdge& re : g.routeEdges )
            {
                if( isOnSurface( re.fromSym ) || isOnSurface( re.toSym ) )
                {
                    ++routesTotal;
                }
            }

            const int jsonRc = emitForLensJson( stdout,
                                                forLensJsonHeader( cfg.forTask, ForLensNotes{ routeNoteRaw, mentionNote, boostNote,
                                                                                              sibliftNote, expandNote,
                                                                                              docMentionNote, lr.anchorLifts, lr.docMentionCount,
                                                                                              adaptiveNote, floorNote,
                                                                                              forConf.level,
                                                                                              forConf.marginPct, forCoverageOn ? forCoverage : -1, forWeak,
                                                                                              forAtStamp,
                                                                                              // abstention round 2: forCut is the SAME
                                                                                              // cut the confidence facts above derive
                                                                                              // from, so the counts and the verdict
                                                                                              // cannot disagree. lensRank is per-symbol
                                                                                              // over the whole index, so its size IS the
                                                                                              // scored corpus.
                                                                                              forCut.kept, forCut.positiveHits,
                                                                                              lensRank.size(), lr.capJson } ),
                                                ForLensJsonInputs{ ing, lensRank, forTopN, fanInPtr, impurePtr, &forChurn,
                                                                   &forClone, testedPtr, ampPtr, redactPtr,
                                                                   cfg.packBudgetBytes, cfg.tokenBudget, notesPtr,
                                                                   legoTotal, composeTotal, routesTotal, flRootArg,
                                                                   &forFileTail, &lr.evidence, d.notesDegraded, forDocsAfterCode, forHeadRR, cfg.forTask,
                                                                   cfg.packTopN, forRankShapingFlags( cfg ) } );
            // §B0: this early return skipped the end-of-function tally below, so a --for --json run redacted
            // SILENTLY — the one stderr line that tells the user a secret was in their tree never appeared.
            reportRedactions( stderr, redactCounts );
            return jsonRc;
        }

        // H1: render lego + compose into memory first (they are independent of <sigs>), so the sigs
        // budget below is EXACT. open_memstream failure (ENOMEM-class) degrades to direct emission
        // after the sigs — same bytes, the budget just can't see the sibling blocks' size then.
        std::string legoStr, composeStr, routeStr, sigsStr;
        bool        legoPreRendered = false, composePreRendered = false, routePreRendered = false, sigsPreRendered = false;

        // ONE pre-render for the four blocks below: into a charge buffer, and into `into` only when the buffer finished
        // whole. false means the open failed or a write was lost inside the buffer (rw::MemoryStream::finish), and the
        // direct-emission path further down renders that block straight to stdout, whole — the budget just cannot see it.
        // A false return also restores the run's redaction tally to what it was before the render: the direct path
        // renders the block again, and a secret it redacts must be counted once, not once per rendering.
        // The caller discloses a false return through `blockCharge` (ForLensBlockCharge), so each block keeps its own message.
        const auto preRender = [ & ]( const auto& render, std::string& into ) -> bool
        {
            const std::optional<RedactCounts> redactBefore = redactPtr != nullptr ? std::optional<RedactCounts>( *redactPtr ) : std::nullopt;
            const auto restoreRedact = [ & ]() noexcept { if( redactBefore ) { *redactPtr = *redactBefore; } };
            rw::MemoryStream stream;
            std::FILE* const buffer = rw::openChargeStream( stream );
            if( buffer == nullptr )
            {
                restoreRedact();
                return false;
            }
            render( buffer );
            const rw::MemoryStreamBytes block = stream.finish();
            if( !block.isWhole )
            {
                restoreRedact();
                return false;
            }
            into.assign( block.bytes );
            return true;
        };
        ForLensBlockCharge blockCharge;   // a sibling block the budget could not see: est_tokens= is then omitted, not wrong
        // L2' (round-2 lever, ported from lane/r1-for-sections-stub): the stub's total= — each renderer's OWN
        // pre-cap row count, written by the SAME call that renders the real body (never a second, drifting
        // tally). Overwritten below if the §P3×§P4 narrow-and-re-render fires, so it always reflects the set
        // that would actually be restored.
        std::size_t legoPreCapCount = 0, composePreCapCount = 0;
        legoPreRendered = preRender( [ & ]( std::FILE* lm ) { packLego( lm, ing, legoScoped, lensRank, 12, redactPtr, impurePtr, kNoNode, /*withPaths=*/true, flRootArg, rw::LegoTargetedArgs().withDecidedOutside( g.baseOutsideClauses ), &legoPreCapCount, &g.implementors ); },
                                     legoStr );
        if( !legoPreRendered )
        {
            DISCLOSE( blockCharge, ForLensBlockCharge::DisclosureWhy::SiblingBlockUnmeasured,
                      "main: open_memstream failed (or its buffer lost a write) for the lego block — budget will not see its size" );
        }
        if( !g.composeEdges.empty() )
        {
            composePreRendered = preRender( [ & ]( std::FILE* cm ) { packCompose( cm, ing, g.composeEdges, lensSurfaceIds, &composePreCapCount ); },
                                            composeStr );
            if( !composePreRendered )
            {
                DISCLOSE( blockCharge, ForLensBlockCharge::DisclosureWhy::SiblingBlockUnmeasured,
                          "main: open_memstream failed (or its buffer lost a write) for the compose block — budget will not see its size" );
            }
        }
        else
        {
            composePreRendered = true;                                // nothing to emit
        }
        if( !g.routeEdges.empty() )
        {
            // B6.3: route view for the same relevant symbol set (top-N by lensRank)
            routePreRendered = preRender( [ & ]( std::FILE* rm ) { packRoutes( rm, ing, g.routeEdges, lensSurfaceIds ); },
                                          routeStr );
            if( !routePreRendered )
            {
                DISCLOSE( blockCharge, ForLensBlockCharge::DisclosureWhy::SiblingBlockUnmeasured,
                          "main: open_memstream failed (or its buffer lost a write) for the routes block — budget will not see its size" );
            }
        }
        else
        {
            routePreRendered = true;                                  // nothing to emit
        }

        // the bundle budget: default kForPayloadBudgetBytes; an explicit --token-budget beats it
        const std::size_t bundleBudget = cfg.tokenBudget > 0
            ? rw::budgetBytesForTokens( std::size_t( cfg.tokenBudget ) )
            : rw::kForPayloadBudgetBytes;
        // D2 (audit regressions, 2026-08-08): the adaptive note's own bytes are EXEMPT from the <sigs> trim
        // charge (headerStr contains adaptiveNote verbatim, so subtracting its size prices the header as the
        // plain run's). --adaptive's contract is that only its CUT changes the emitted set ("without it,
        // output is byte-identical"); charging the note made a NO-CUT (flat) query drop one <d> whenever the
        // corpus path length landed the trim boundary inside the note's ~110 B — adaptivecheck PHASE3's
        // "kept 40 of 40" header over a set one row short of the plain run's, i.e. a disclosed-inert mode
        // that was not inert. The note is still real bytes everywhere it matters downstream: est_tokens and
        // the ceiling ladder measure the emitted header, so nothing under-reports; only the global default
        // budget can overshoot, by at most the note (~0.5% of kForPayloadBudgetBytes), disclosed here.
        // T3: the bundle=auto legend's bytes are EXEMPT from the <sigs> trim charge, exactly like the
        // adaptive note above (the D2 precedent): the contract is that auto mode changes NOTHING about the
        // signatures — the same corpus/query/budget produces byte-identical <sigs> with and without
        // --signatures-only, in BOTH budget regimes. The legend is still real bytes downstream: under an
        // explicit --token-budget the whole auto surface (legend + root attribute + bodies) must fit the
        // leftover under the stated ceiling or is turned off entirely (see the auto block below), and
        // est_tokens always measures the emitted header.
        // COMPACT: the same exemption, for whichever of the two legends is actually on the header — the
        // contract "the ranked map is byte-identical with and without the enrichment" has to hold for the
        // compact shape too, or the round would be changing signatures while claiming to change only bodies.
        const std::size_t autoLegendBytes = enrichmentLegendBytesEmitted( plan, cfg.legend == "compact" );
        // CONFIDENCE: the same exemption a third time, for the same reason as D2's adaptiveNote — the
        // disclosure's contract is DISCLOSURE ONLY, and charging its bytes made the default-budget compact
        // bundle drop a tail <d> row (measured on this repo's own src, the "rank symbols by pagerank"
        // fixture query: one row gone at the trim boundary). DEFAULT REGIME ONLY, and this split is the
        // point where this exemption differs from its two precedents: an explicit --token-budget is a HARD
        // The disclosure is exempt from the SIG-TRIM allowance in BOTH regimes. Charging it under an
        // explicit ceiling (the first cut of this change) shrank the sig section BELOW the default
        // regime's — an explicit ceiling wider than the default re-trimming sigs is exactly the
        // inversion the frozen sig share existed to forbid (gate: forbudgetmonotoncheck, which caught it).
        // The est_tokens<=N promise is kept by the BODY side, not by this trim: committedBytes below
        // counts the emitted header verbatim, so leftBytes hands the bodies ~240 B less and the bundle
        // total never crosses the ceiling — charging the sig side as well was double-counting one cost.
        // est_tokens measures the emitted header in both regimes, so nothing under-reports either way.
        // P1 (L7): under --legend=compact the header carries the SHORT confidence clause and the compact tail legend
        // (appendCompactForLegend), so the exemption must subtract what was emitted — the full constants left the
        // ledger 64 B short and the subtraction below underflowed (UBSan: "297 - 361 cannot be represented").
        const bool        compactLegendOn      = cfg.legend == "compact";
        const std::size_t confidenceEmitted    = compactLegendOn ? ( confidenceEarlyNoteBytes == 0 ? 0 : kForCompactLegendConfidence.size() + ( forCoverageOn ? kForCompactCoverageClause.size() : 0 ) )
                                                                 : confidenceEarlyNoteBytes;
        const std::size_t confidenceExemptBytes = confidenceEarlyAttrsBytes + confidenceEmitted + forAtAttrStr.size();   // == confidenceOwnBytes + at= in the full dialect
        const std::size_t tailLegendEmitted    = compactLegendOn ? kForCompactLegendTail.size() : rw::kForFileTailLegend.size();
        // DEEP-TAIL: the tail legend's bytes are exempt from the sig-trim charge in BOTH regimes, the
        // confidence-disclosure precedent verbatim — the tail's contract is that the ranked head is
        // byte-identical with and without it, and charging the clause here would shrink <sigs> to pay for
        // a disclosure. The bytes stay real everywhere downstream: est_tokens measures the emitted header,
        // and the explicit regime's tail rows are funded from the RESIDUAL (below), never from the sigs.
        // Row 6 (2026-09-12): the sc=/route= reading (graphlegend.h kForIdRouteLegend) joins the exemption on the
        // same contract — disclosure only; charging it shrank the explicit-ceiling sig section below the default's
        // (forbudgetmonotoncheck #1/#5 caught it, 6507 B against 6141 B at --token-budget=8000). Subtract what was
        // EMITTED in this dialect, exactly as the confidence and tail clauses above do.
        // A1′: the compact dialect emits ONLY the route clause here (sc= rides its always-on row clause), and only when
        // the root carries route= — subtract exactly what appendCompactForLegend appended. The DEFAULT dialect emits the
        // sc= rule always and the same route clause under the same present-only condition (forRouteAttrPresent).
        // …and the SAME decision the append made (rw::forIdRouteLegendParts), so the ledger cannot subtract a
        // clause the header never wrote. The compact dialect emits only the route reading here — its sc= reading
        // rides the always-on rows clause — so it exempts only that part.
        const rw::ForIdRouteLegendParts idRouteParts =
            rw::forIdRouteLegendParts( headerParts.idRouteLegend, headerParts.scPresent, !routeNoteRaw.empty() );
        const std::size_t idRouteLegendEmitted = compactLegendOn ? idRouteParts.route.size() : idRouteParts.bytes();
        // e= (forsigspancheck): its legend clause is a disclosure on the same contract — exempt, so the ranked rows a ceiling
        // admits are the ones it admitted without it (owner ruling: e= is exempt from the row budget).
        const std::size_t endLineLegendEmitted = !headerParts.endLinePresent ? 0u
                                               : ( compactLegendOn ? rw::kForCompactEndLineLegend.size() : rw::kForEndLineLegend.size() );
        // owner-hop: the qword clause — and the via="name" clause when only the owner rows switched it on — are disclosures
        // on the same contract: exempt, so <sigs> is byte-identical with and without the owner rows (the rows ride on top of
        // the hop budget; their reading never costs a signature row). Gate: ownerhopcheck (S).
        const std::size_t ownerLegendEmitted = ownerLegendExemptBytes( headerParts, compactLegendOn );
        // for-body-slot: the slot clause on the same contract — the body rides on top of the complete answer, so its reading never
        // costs a signature row (forbodyslotcheck (D4): <sigs> byte-identical with RIPWIRE_NO_BODY_SLOT=1)
        const std::size_t bodySlotLegendEmitted = bodySlotLegend( headerParts, compactLegendOn ).size();
        // body-fold: the fold clause on the same contract — the fold rides on top of the complete answer (<sigs> byte-identical with
        // RIPWIRE_NO_BODY_FOLD=1 but for its next= attribute pair), so its reading never costs a signature row
        const std::size_t bodyFoldLegendEmitted = bodyFoldLegend( headerParts, compactLegendOn ).size();
        // mf1-nx: the caller hop's clause on the same contract — the hop rides on top of the complete answer (<sigs>, the tail and
        // the bodies byte-identical with RIPWIRE_NO_CALLER_HOP=1), so its reading never costs a signature row
        const std::size_t callerHopLegendEmitted = callerHopClause( headerParts, compactLegendOn ).size()
                                                 + presentOnlyClause( headerParts.epPresent, compactLegendOn, rw::kForCompactEpManifestLegend, rw::kForEpManifestLegend ).size()   // ep-manifest: same contract
                                                 + presentOnlyClause( headerParts.dispatchHopPresent, compactLegendOn, rw::kForCompactDispatchHopLegend, rw::kForDispatchHopLegend ).size()   // mf1-nx wave 4: same contract
                                                 + presentOnlyClause( headerParts.listedPresent, compactLegendOn, rw::kForCompactListedInLegend, rw::kForListedInLegend ).size();   // manifest-noncode: same contract
        // attrib-multidef Q1: the prov="split" clause is a disclosure on the same contract — exempt, as e= is, so <sigs> (rows and
        // its continuation's budget) is byte-identical with and without it (fordisclosurecheck #2: auto vs --signatures-only)
        const std::size_t splitLegendEmitted = !headerParts.splitPresent ? 0u
                                             : ( compactLegendOn ? rw::kForCompactSplitClause.size() : rw::kForSplitClause.size() );
        const std::size_t exemptBytes = adaptiveNote.size() + autoLegendBytes + confidenceExemptBytes + tailLegendEmitted + idRouteLegendEmitted
                                      + endLineLegendEmitted + ownerLegendEmitted + bodySlotLegendEmitted + splitLegendEmitted
                                      + bodyFoldLegendEmitted + callerHopLegendEmitted;
        if( exemptBytes > headerStr.size() )
        {
            DISCLOSE( "runForLens: header exemptions exceed the emitted header — the sig ledger would underflow; charging the header whole" );
        }
        std::size_t chargedHeaderBytes = exemptBytes > headerStr.size() ? headerStr.size() : headerStr.size() - exemptBytes;
        chargedHeaderBytes -= std::min( chargedHeaderBytes, rw::forZeroNoteBytes( headerStr ) );   // lean-answers: the zero reading never costs a row
        // L1 fix round (rv-r1-L1 HIGH-1 / MED-5): THE DEFAULT NEVER CHARGES ITS SIGNATURES MORE HEADER THAN --legend=full WOULD.
        // The compact header now defines task=/next=/pure=/<field> (kForCompactLegendFacts), and charging those bytes cost the
        // default a signature row --legend=full carried (compactlegendcheck (P1): 19 vs 20 rows at --token-budget=3000); making
        // them exempt instead bought the default rows it could not pay for (over its budget where full fit, 72 functions at 850
        // tokens: 995 vs 816). So the compact charge is capped at the FULL dialect's charge for the same header, computed by the
        // same rule: rows(default) ⊇ rows(full) by construction, and a default that pays more header than full never gets more
        // room for rows than full had.
        // forbudget-soft: the FULL dialect's charge for this header, in both dialects — a soft target's text tier is the default
        // target's sig share as THIS number prices it, so the compact and full answers shrink their rows alike (forSigsBudgets)
        std::size_t fullChargedHeaderBytes = chargedHeaderBytes;
        if( compactLegendOn )
        {
            ForLensHeaderParts fullParts = headerParts;
            fullParts.compactLegend = false;
            const std::string fullHeader      = forLensHeaderText( fullParts, /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
            const std::size_t fullHeaderBytes = fullHeader.size();
            const std::size_t fullExempt      = adaptiveNote.size() + enrichmentLegendBytesEmitted( plan, false )
                                              + confidenceEarlyAttrsBytes + confidenceEarlyNoteBytes + forAtAttrStr.size()
                                              + rw::kForFileTailLegend.size() + idRouteParts.bytes()
                                              + ( headerParts.endLinePresent ? rw::kForEndLineLegend.size() : 0u )
                                              + ownerLegendExemptBytes( headerParts, /*compact=*/false )
                                              + bodySlotLegend( headerParts, /*compact=*/false ).size()
                                              + bodyFoldLegend( headerParts, /*compact=*/false ).size()   // body-fold
                                              + callerHopClause( headerParts, /*compact=*/false ).size()  // mf1-nx
                                              + presentOnlyClause( headerParts.epPresent, /*compact=*/false, rw::kForCompactEpManifestLegend, rw::kForEpManifestLegend ).size()  // ep-manifest
                                              + presentOnlyClause( headerParts.dispatchHopPresent, /*compact=*/false, rw::kForCompactDispatchHopLegend, rw::kForDispatchHopLegend ).size()  // mf1-nx wave 4
                                              + presentOnlyClause( headerParts.listedPresent, /*compact=*/false, rw::kForCompactListedInLegend, rw::kForListedInLegend ).size()  // manifest-noncode
                                              + ( headerParts.splitPresent ? rw::kForSplitClause.size() : 0u );   // attrib-multidef Q1
            std::size_t       fullCharged     = fullExempt > fullHeaderBytes ? fullHeaderBytes : fullHeaderBytes - fullExempt;
            fullCharged -= std::min( fullCharged, rw::forZeroNoteBytes( fullHeader ) );   // lean-answers: exempt, as above
            chargedHeaderBytes     = std::min( chargedHeaderBytes, fullCharged );
            fullChargedHeaderBytes = fullCharged;
        }
        // lego-charge: <lego>/<compose> cost what they are SERVED as — a collapsing section its stub, not its full render
        // (rw::forSectionsSigChargePlan states both rules and why --sections= keeps the default's charge without a ceiling).
        // A section the degrade path will stream unmeasured has no bytes here (legoStr/composeStr empty): blockCharge discloses it.
        // forbudget-soft: the DEFAULT charge in both regimes — a soft target charges the <sigs> rows alone, and the default
        // target's share it tiers its text by is the default answer's (forSigsBudgets), sections priced as the default prices them.
        const bool                    forSoftTarget = cfg.tokenBudget > 0;   // an explicit --token-budget: a SOFT target over the rows
        const rw::ForStubbableSection legoChargeIn{ .hasContent = !legoStr.empty(), .preCapTotal = legoPreCapCount, .rendered = legoPreRendered,
                                                    .renderedBytes = legoStr.size() };
        const rw::ForStubbableSection composeChargeIn{ .hasContent = !composeStr.empty(), .preCapTotal = composePreCapCount,
                                                       .rendered = composePreRendered, .renderedBytes = composeStr.size() };
        const rw::ForSectionStubPlan  sigChargePlan = rw::forSectionsSigChargePlan( cfg.sections, /*explicitCeiling=*/false, cfg.forTask, legoChargeIn, composeChargeIn );
        const std::size_t sectionsChargedBytes = sigChargePlan.servedBytes( legoChargeIn, composeChargeIn ) + routeStr.size() + 6;   // + "</ctx>"
        const std::size_t fixedBytes           = chargedHeaderBytes + sectionsChargedBytes;

        // §F1's graph block, rendered HERE (before <sigs>) rather than beside the bodies: it reads only lensRank, so the
        // bytes are the same wherever it renders. Emission order is unchanged (detail, then graph).
        rw::ChargedSection graphSection, detailSection;
        if( cfg.withGraph )
        {
            graphSection = rw::chargeSection( [ & ]( std::FILE* f ) { packGraphBlock( f, ing, lensRank, g.outOff, g.outTargets ); },
                                               rw::kBytesPerTokenDefault );
            if( !graphSection.isRendered )
            {
                // the block streams uncharged below: the lens's own contract omits an est_tokens that left it out
                DISCLOSE( blockCharge, ForLensBlockCharge::DisclosureWhy::SiblingBlockUnmeasured, "runForLens: the graph block streams uncharged — est_tokens omitted" );
            }
        }
        const std::vector<NodeId> detailIds = cfg.detail > 0 ? forDetailIds( ing, lensRank, cfg.detail, forTopN ) : std::vector<NodeId>{};   // (score desc, id asc) — same order as the sigs
        // the first --detail body's floor under a soft target (head-cut with next= when it is over a quarter of the target): the
        // target fills the rows first, and the floor keeps the one body the caller asked for from being cut to nothing
        const std::size_t detailFloorBudget = forSoftTarget ? forDetailFirstBodyFloor( ing, detailIds, bundleBudget ) : 0u;
        // THE TWO <sigs> BUDGETS (forbudget-soft; serialize.h kForPayloadBudgetBytes / kForRunawayGuardBytes): the target the
        // text-shrink steps aim at, and where the row-drop step aims — the runaway guard (default), or the soft target's rows.
        // round C (reserve first): a soft target's cut is priced with the full dialect's header and every fixed section — the
        // graph block included, which the retired ceiling reserved out of the sig claim — so both dialects cut alike
        const std::size_t    cutHeaderBytes = fullChargedHeaderBytes - std::min( fullChargedHeaderBytes, forBodyCeilingDisclosureBytes );
        const ForSigsBudgets sigsBudgets = forSigsBudgets( forSoftTarget ? bundleBudget : 0u, fixedBytes,
                                                          cutHeaderBytes + sectionsChargedBytes + graphSection.xml.size(),
                                                          /*tierAtDefault=*/autoBundleMode && cfg.packTopN == 0 );
        const std::size_t    sigsBudget  = sigsBudgets.target;

        // The two attributes SPLICED into the header AFTER the ceiling ladder has chosen a rung — est_tokens
        // (" est_tokens=\"NNNNNNNN\"", bounded well under 24 B: 8 digits covers ~100M tokens) and, when the
        // query scored weak, weak="1" (exactly 9 B). Neither exists yet at ladder time, so the ladder cannot
        // measure them and reserves them instead; both are EXACT-counted into est_tokens itself further down.
        // Seam-verifier LOW (2026-07-29) found the est_tokens half unpriced (a 3-budget-point window landed
        // ~15.5% past the bare ceiling with no over_ceiling label); CA4 verifier L2 found the weak="1" half the
        // same way, 9 bytes spliced in after the number that is supposed to describe them.
        constexpr std::size_t kEstTokensAttrReserve = 24;
        constexpr std::size_t kWeakAttrBytes        = 9;   // exactly ` weak="1"`
        // N1 (capture-audit verify-wave1 2026-09-04): est_tokens= moved from the header COMMENT onto the <ctx>
        // root (a comment-stripping parser read no price at all — the flagship budgeted verb was the one M11
        // outlier), so the legend now needs a clause defining it; the clause is fixed text, reserved here and
        // exact-counted below. over_ceiling="1" and ITS clause are not reserved here: F2 made them reachable from
        // every rung, so their bytes are not a constant — the ladder prices them per shape (PR #135,
        // finishForLensHeader). Reserved on the last rung only, they let a bundle ship 70 B past its allowance.
        // L1 fix round (rv-r1-L1 HIGH-1): the compact dialect never defined the ceilings the root names — budget_tokens= /
        // max_tokens= rode every budgeted default answer undefined (the full dialect's confidence clause carries them). The
        // compact clause names the ones THIS root carries; the full dialect's bytes are unchanged (compactlegendcheck A-PIN).
        const bool compactEstLegend = cfg.legend == "compact";
        const std::string_view kForEstTokensLegend =
            !compactEstLegend                   ? std::string_view( " est_tokens= prices this bundle in tokens" )
            : forGateBudget && forBodyCeiling   ? std::string_view( " est_tokens= prices this bundle in tokens; budget_tokens=/max_tokens= the soft row target (rows stop once it is reached)/body ceiling asked" )
            : forGateBudget                     ? std::string_view( " est_tokens= prices this bundle in tokens; budget_tokens= the soft row target asked (rows stop once it is reached)" )
            : forBodyCeiling                    ? std::string_view( " est_tokens= prices this bundle in tokens; max_tokens= the body ceiling asked" )
                                                : std::string_view( " est_tokens= prices this bundle in tokens" );
        // F2: spliced ONLY onto a document that actually carries over_ceiling="1" (the attribute is now
        // reachable from every rung, not just the ladder's last), so a bundle inside its budget keeps every
        // byte it had. Defines the attribute in the same unit the root prints both numbers in.
        // R1: the wording lives in serialize.h beside pricedRootAttr now — the MCP `for` twin needs the SAME
        // sentence and could not reach a constant local to this function. Bound to a local name unchanged so
        // the byte arithmetic in this block still reads against one identifier.
        // #61: which sentence depends on which ceilings this root NAMES (forGateBudget / forBodyCeiling, both
        // settled far above at the H9 splice), so the binding is const rather than constexpr. Keyed on the
        // attributes present, not on which ceiling was exceeded — see overCeilingLegendFor. A budget-only run
        // still selects kOverCeilingLegend, so nothing about --for --token-budget moves by a byte.
        // forbudget-soft: budget_tokens= is a soft target, never a ceiling this root is "over" — only max_tokens= is
        const std::string_view kForOverCeilingLegend = rw::overCeilingLegendFor( /*namesBudgetTokens=*/false, forBodyCeiling );
        const std::size_t     headerSpliceReserve   = kEstTokensAttrReserve + kForEstTokensLegend.size() + ( forWeak ? kWeakAttrBytes : 0u );

        // D10: --token-budget SHAPES this bundle (exit-0 trim) rather than gating it (exit-3 like the
        // default map/--query) — but the shaped result must still be checkable against the budget it shaped
        // against. <sigs> is now buffered too (same open_memstream pattern as lego/compose/routes above) so the
        // TRUE delivered byte count is known before the header is finalized; est_tokens="N" uses the same
        // mid-band content rate estimateTokens() uses for the default map (kBytesPerTokenDefault), not the
        // conservative kMinBytesPerToken the budget CEILING is sized with — this reports what was actually
        // produced, not the worst-case bound. open_memstream failure degrades to direct emission (no est_tokens
        // attribute — same as before this change; never a fabricated number).
        // A2 (survey card, 2026-09-03): how many rank>0 candidates the H1 ladder just below cut — set ONLY on
        // this (memstream-buffered) render, never on the direct-emission degrade path further down, because
        // headerStr is already flushed to stdout by the time that path runs and cannot be edited retroactively
        // (the same reason est_tokens is "omitted", not "wrong", on that path — see its DISCLOSE).
        std::size_t forDroppedPositive = 0;
        // knob-honesty-068: a capped <sigs> names the call that serves it uncut (serialize.h SigsCutContinuation). forbudget-soft:
        // it is EXEMPT in every regime now — the default has no byte promise (a target and a runaway guard), and an explicit
        // budget is a soft target with none either — so no row is ever dropped to pay for the handle and the lens renders ONCE
        // (the C3 unpaid/paid/overrun re-renders are gone with the hard ceiling they priced against).
        const std::string             forRankFlags       = forRankShapingFlags( cfg );
        const rw::SigsCutContinuation forSigsNext{ cfg.forTask, cfg.packTopN, forRankFlags, fixedBytes, /*json=*/false,
                                                   /*pasteHandle=*/true };
        bool        forSigsCapped      = false;   // did the H1 ladder trim <sigs>? — decides the budget_bytes= legend clause below
        rw::SigsCutReport forSigsCut;             // cut-fix lane A: the <sigs> tag's shown/total/docs_dropped — its clauses below
        forSigsCut.continuationRequest = &forSigsNext;   // knob-honesty-068: IN — the capped block's continuation
        forSigsCut.rowDropBudgetBytes  = sigsBudgets.rowDrop;   // forbudget-soft: IN — where step F aims (guard / soft target)
        forSigsCut.pastTargetDisclosed = !forSoftTarget;        //   …and the default's rows past its target are disclosed
        // round C: the render is named so a soft target can narrow its rows past the cut once the sections are served (below);
        // the redaction tally around it is snapshotted so a second render replaces this one's count instead of adding to it
        const std::optional<RedactCounts> redactBeforeSigs = redactPtr != nullptr ? std::optional<RedactCounts>( *redactPtr ) : std::nullopt;
        const auto renderSigs = [ & ]( std::FILE* sm )
            {
                packSignatures( sm, ing, lensRank, forTopN, cfg.packBudgetBytes, true, fanInPtr, impurePtr, redactPtr,
                                &forChurn, &forClone, testedPtr, ampPtr,     // Q3: churn/clone/tested/amp folded onto the <d> blocks
                                /*rankAdaptivePayload=*/true,                // B0.3: tail entries excerpt-trimmed by global rank (serialize.h kForDoc*)
                                sigsBudget,                                  // H1: global payload budget (trim ladder; payload="capped" marker)
                                notesPtr,                                    // L3: field-notes surfacing (inert when null)
                                flRootArg,                                   // R-E: root-relative p=
                                rw::forLensRules( forDocsAfterCode, forEndLines, forHeadRR ),   // LB-A floor, e= (endLinesFitCeiling), docs reorder, head RR
                                &forDroppedPositive,                         // A2: exact count, see droppedPositiveCount
                                &shownSigIds,                                // lane 2: the rows actually emitted — the tail's rank rows exclude THESE files
                                &forSigsCapped,                              // did the ladder fire? — the budget_bytes= clause rides only then
                                forTopRowNext,                               // L-W: the widening page on a thin answer, else the body
                                &forSigsCut,                                 // cut-fix lane A: which cut readings the tag owes;
                                                                             //   knob-honesty-068: carries forSigsNext IN
                                SigRowSpelling{ .elideZeroMetrics = true } );   // lean-answers lane: zero cx=/ccx=/in= omitted (legend: absent = 0)
            };
        sigsPreRendered = preRender( renderSigs, sigsStr );
        const std::optional<RedactCounts> redactAfterSigs = redactPtr != nullptr ? std::optional<RedactCounts>( *redactPtr ) : std::nullopt;
        if( !sigsPreRendered )
        {
            DISCLOSE( blockCharge, ForLensBlockCharge::DisclosureWhy::SigsUnmeasured,
                      "main: open_memstream failed (or its buffer lost a write) for the sigs block — est_tokens omitted from the header" );
            // what a render into a failed buffer measured belongs to bytes that will not be printed: dropped, exactly as a
            // failed open never sets it, and the direct-emission path below renders the block whole
            forDroppedPositive = 0;
            forSigsCapped      = false;
            forSigsCut         = rw::SigsCutReport {};
            shownSigIds.clear();
        }

        // A2: the splice text, built ONCE here (right after forDroppedPositive becomes known) rather than at
        // the insert site far below — unlike weak=/est_tokens=, whose PRESENCE is decided before packSignatures
        // ever runs (so their reserve is a worst-case bound, kEstTokensAttrReserve/kWeakAttrBytes above), this
        // one is decided BY packSignatures' own return, so its reserve can be the EXACT string that will be
        // spliced — no bound needed, and no second snprintf later. Every downstream section (bodies,
        // enrichment, tail, the explicit-ceiling ladder) must see this reserved, or a query that trips the
        // attribute can push the bundle past its stated --token-budget by the note's own width — measured:
        // w3fixbudgetcheck's ceiling biconditional and fornotesbudgetcheck's 1500-token fixture both went red
        // with an early, verbose spelling (a bracketed English explanation, ~120 B) even WITH this reserve
        // in place — the reserve keeps the document inside the conservative BYTE ceiling, but est_tokens is a
        // separate, denser measurement these fixtures pin with only ~30 tokens of headroom, and a real 50-token
        // addition genuinely does not fit either fixture's calibration. Bare spelling instead (~24 B, matching
        // weak="1"'s own economy) rather than re-anchoring two unrelated fixtures' calibration for one flag:
        // legendcoveragecheck's ATTR scanner matches literal `<tag attr="v">` shapes and never sees text
        // embedded in a comment either way (proven: the gate is green with or without a bracket note here),
        // so the bracket bought no legend coverage — only bytes. The full explanation lives in the round's
        // registration (docs/EVALS.md, "A2 round") and the bare form is self-explanatory enough on its own.
        std::string droppedPositiveNote;
        if( forDroppedPositive > 0 )
        {
            char nb[ 40 ];
            rw::formatTo( nb, sizeof( nb ), " dropped_positive=\"{}\"", forDroppedPositive );
            droppedPositiveNote = nb;
        }
        // ── budget_bytes= — THE CEILING A DEFAULT RUN NEVER NAMED (METHODOLOGY §9 #6) ──────────────────
        // H9 above put budget_tokens= on the root, but ONLY when the caller passed --token-budget. A run
        // without that flag is still budgeted — kForPayloadBudgetBytes is enforced on EVERY --for — so the
        // default bundle disclosed THAT the ladder had cut it (<sigs shown= total= capped="1">) while the
        // number that did the cutting appeared nowhere, and a reader could not tell the built-in ceiling
        // from a caller's own. §9 #6: "a ceiling attribute names the ceiling actually applied". Compare
        // --pack-task, whose default lands on its root as budget_tokens="6000"; same class of ceiling, two
        // different honesty outcomes until now.
        //
        // THE UNIT IS BYTES, and that is the whole reason the attribute is not simply budget_tokens=. What
        // the default applies is a BYTE constant: bundleBudget is kForPayloadBudgetBytes verbatim here, and
        // the ladder compares rendered bytes against it. A token spelling would have to divide by a rate,
        // and the two rates in play disagree on purpose — est_tokens prices at kBytesPerTokenDefault (2.50)
        // while a ceiling is SIZED at the conservative kMinBytesPerToken — so any token number printed here
        // would be one the tool never applied, which is the exact failure §9 #6 names. In the EXPLICIT
        // regime the caller's own number is the honest one and budget_tokens= already carries it, so this
        // attribute is default-regime-only: the two never both ride, and never neither.
        //
        // SCOPE, stated in the clause because the root also carries est_tokens: this ceiling bounds the
        // RANKED PAYLOAD (sigs + lego + compose + routes + the charged header). The auto bodies ride
        // kForAutoBodyBudgetBytes ON TOP of it, so a bundle whose est_tokens prices out above this number
        // is not over any ceiling — which is also why it is not wired into over_ceiling, whose rule is
        // stated over the TOKEN ceilings the root names.
        //
        // COST: zero unless the ceiling actually bit. Both the attribute and the clause defining it ride on
        // forSigsCapped — the ladder's own verdict, returned by packSignatures above — which is the
        // pr_converged shape (src/prconverge.h) and the same conditional splice kForOverCeilingLegend and
        // kForEstTokensLegend use, for the measured reason recorded there: fornotesbudgetcheck's rungs are
        // tight enough that an unconditional ~130 B of disclosure re-anchors two unrelated fixtures.
        // Spliced AFTER the sigs render (with dropped_positive= / autoAttr below), never before it, so the
        // ladder's own input is untouched and the <sigs> block stays byte-identical to the pre-fix render —
        // forbudgetmonotoncheck pins exactly that identity across ceilings. No "--" in the clause: it rides
        // inside an XML comment, where a double hyphen is ill-formed (G4).
        const bool        forDefaultCeiling = forSigsCapped && cfg.tokenBudget == 0;
        // forbudget-soft: the default answer's ONLY row cut — the runaway guard (a soft target's row stop is no "over")
        const bool        forGuardCut       = forSigsCut.rowDropCut && !forSoftTarget;
        const std::string sigsCeilingAttr   = forDefaultCeiling
            ? " budget_bytes=\"" + std::to_string( rw::kForPayloadBudgetBytes ) + "\""
            : std::string();
        // cut-fix lane A: the <sigs> tag's two cut readings (docs_dropped=, shrunk-not-dropped) ride the same splice, present
        // only when the tag carries the case (serialize.h sigsCutLegendNotes), so the reserve below already covers them.
        // forbudget-soft: on an answer whose ranked head ran PAST the target (past_target=), the number shaped row text and
        // removed no row — its reading says "target" there; elsewhere the payload fit it and the ceiling reading stays true
        std::string       sigsCeilingNote   = ( forDefaultCeiling ? std::string( forSigsCut.pastTarget > 0 ? rw::kForBudgetBytesTargetNote : rw::kForBudgetBytesNote )
                                                                  : std::string() )
            + rw::sigsCutReportLegend( forSigsCut )    // + the continuation's and the docs reorder's readings (docs_after_code=)
            + ( forGuardCut ? rw::forRunawayGuardNote() : std::string() );   // forbudget-soft: the runaway guard's reading, where it cut
        // ── the INDEXING-cap disclosure (mention.h CapDisclosure), at the same splice point and for the
        // same reason: a --for header is charged against the payload ceiling, so a disclosure folded into
        // the notes above is paid for in ranked rows. Measured on sixteen real invocations, that cost three
        // bundles a <d> row; riding this post-render splice costs bytes and never costs evidence.
        // COST: zero unless a cap actually bit.
        const std::string capAttrsStr = lr.capAttrs;
        const std::string capNoteStr  = lr.capNote;
        // L3 follow-up (CodeRabbit 4053600616): known this early (d.notesDegraded needs no render), folded into
        // the SAME reserve as the splices above so the ladder's remaining-budget arithmetic sees it too.
        const std::string notesDegradedAttrStr = d.notesDegraded ? std::string( rw::notes::kNotesDegradedAttr ) : std::string();
        const std::string notesDegradedNoteStr = d.notesDegraded ? ( " [" + std::string( rw::notes::kNotesDegradedReading ) + "]" ) : std::string();
        const std::size_t droppedPositiveSpliceReserve = droppedPositiveNote.size() + sigsCeilingNote.size() + sigsCeilingAttr.size()
                                                       + capAttrsStr.size() + capNoteStr.size()
                                                       + notesDegradedAttrStr.size() + notesDegradedNoteStr.size();

        // §P3 × §P4: the budget trim above can drop files the lego scope still references — narrow the lego
        // block to the RENDERED sigs' files and re-render (a byte-subset of what the budget already charged
        // for, so the bundle only shrinks; before est_tokens so the header reports the delivered size).
        if( sigsPreRendered && legoPreRendered && !legoStr.empty()
            && narrowLegoToRenderedSigs( ing, legoScoped, rw::sigsRowsAtTarget( sigsStr, forSigsCut ),   // forbudget-soft: scoped at the target
                                         flRootArg.empty() ? std::string_view() : rw::sarif::rootPrefixOf( flRootArg ) ) )
        {
            legoStr = captureXml( [ & ]( std::FILE* f ) { packLego( f, ing, legoScoped, lensRank, 12, redactPtr, impurePtr, kNoNode, /*withPaths=*/true, flRootArg, rw::LegoTargetedArgs().withDecidedOutside( g.baseOutsideClauses ), &legoPreCapCount, &g.implementors ); } );
        }

        // L2 (round-1 lever B1, §9.3 disclosed cut): collapse <lego>/<compose> to a counted stub BY DEFAULT —
        // total= is that section's own pre-cap row count, shown="0" discloses that nothing was rendered here,
        // and next= is the ONE restoring spelling (E41 rule b: nextverb.h's capped composer) that returns
        // BOTH sections byte-identical to this un-stubbed render, in ONE call. --sections=lego,compose
        // (cli.h validateSectionsModifier) opts a caller back into the pre-stub render of either or both. No
        // stub for a section that would have been EMPTY.
        //
        // FAULT-INJECTION FIX (independent review, 2026-09-19): total= — and therefore the stub-or-full
        // decision itself — must be reachable WITHOUT the buffered render legoStr/composeStr came from,
        // because that render can fail (open_memstream degrades, legoPreRendered/composePreRendered==false)
        // and the section is then emitted directly to stdout further down (the ORIGINAL degrade path, unaware
        // of --sections=). legoPreCapRowCount/composePreCapRowCount (serialize.h) compute the SAME count with
        // no FILE* and no buffering — provably identical to packLego/packCompose's own tally (see their own
        // comments) — so both paths read the identical number. They no longer share the DECISION: the degrade
        // path has no measured bytes, so priceSectionStub never collapses there and the section streams whole
        // (CodeRabbit 4054594306 — a stub is taken only when it is proven cheaper). legoScoped/g.composeEdges/lensSurfaceIds are read here in
        // whichever state they are already in (post-narrow on the happy path, since narrowing already ran
        // above; un-narrowed on the degrade path, since narrowing never runs there either) — the same state
        // each path's own render (buffered or direct-to-stdout) would use.
        const std::size_t legoStubTotal    = legoPreRendered    ? legoPreCapCount    : rw::legoPreCapRowCount( ing, legoScoped );
        const std::size_t composeStubTotal = composePreRendered ? composePreCapCount : rw::composePreCapRowCount( ing, g.composeEdges, lensSurfaceIds );
        // R2-L2' (round-2, priced re-registration of L2/B1, rv-prereg2 Amendment 1 R4): a CANDIDATE (has content, not opted
        // back in by --sections=) collapses ONLY WHEN CHEAPER — rw::planForSectionStubs / priceSectionStub (serialize.h) hold
        // the one rule both surfaces share, its ONE restoring invocation (used at every site below: the buffered substitution
        // and the degrade-path fallback), and the DEGRADE path it documents: no rendered bytes to gate on there, so the
        // section never collapses and is streamed whole below.
        // round C (reserve first): a soft target serves the sections whole when they fit what the rows at its cut left
        const std::size_t sigsAtCutBytes = sigsStr.size() - std::min( sigsStr.size(), forSigsCut.pastTargetBytes );
        const std::size_t sectionsShare  = bundleBudget - std::min( bundleBudget, forHdrXml.size() + sigsAtCutBytes + routeStr.size() + graphSection.xml.size() );
        const rw::ForSectionStubPlan stubPlan = rw::planForSectionStubs(
            forSoftTarget && legoPreRendered && composePreRendered ? rw::forSoftSectionsOptIn( cfg.sections, legoStr.size(), composeStr.size(), sectionsShare )
                                                                   : std::string_view( cfg.sections ),
            cfg.forTask,
            rw::ForStubbableSection{ .hasContent = legoPreRendered ? !legoStr.empty() : legoStubTotal > 0, .preCapTotal = legoStubTotal,
                                     .rendered = legoPreRendered, .renderedBytes = legoStr.size() },
            rw::ForStubbableSection{ .hasContent = composePreRendered ? !composeStr.empty() : composeStubTotal > 0, .preCapTotal = composeStubTotal,
                                     .rendered = composePreRendered, .renderedBytes = composeStr.size() } );
        const std::string&             sectionsNextInvocation = stubPlan.nextInvocation;
        const rw::SectionStubPricing&  legoPricing            = stubPlan.lego;
        const rw::SectionStubPricing&  composePricing         = stubPlan.compose;
        const bool                     legoWillStub           = stubPlan.legoWillStub;
        const bool                     composeWillStub        = stubPlan.composeWillStub;
        // postcondition of the rule itself: whichever section actually collapses is, by construction, smaller
        // than what it replaced (the WHOLE point of pricing it) — never a stub that grew the answer.
        ENSURES( !( legoPreRendered && legoWillStub )    || legoPricing.stubXml.size()    < legoStr.size(),
                 "R2-L2': a lego stub collapsed without being smaller than the section it replaced" );
        ENSURES( !( composePreRendered && composeWillStub ) || composePricing.stubXml.size() < composeStr.size(),
                 "R2-L2': a compose stub collapsed without being smaller than the section it replaced" );
        // lego-charge: the <sigs> budget priced a collapsing lego at its PRE-narrow stub; the narrow only empties implementor
        // lists, so the stub served now is never longer than the one charged (total= can only shrink).
        ENSURES( !( legoWillStub && sigChargePlan.legoWillStub ) || legoPricing.stubXml.size() <= sigChargePlan.lego.stubXml.size(),
                 "lego-charge: the served lego stub is longer than the stub the <sigs> budget was charged for" );
        std::string sectionsStubNote;   // present-only legend clause (kForSectionStubLegend), spliced below
        if( legoWillStub || composeWillStub )
        {
            sectionsStubNote = rw::kForSectionStubLegend;
        }
        // count-floor: the lego COUNT clause rides only on a document whose served <lego> carries its attributes (a short
        // list or a floor) — the same post-render, present-only splice, so an answer without them keeps every byte.
        if( legoPreRendered && !legoWillStub && legoStr.find( rw::kLegoCountAttrPrefix ) != std::string::npos )
        {
            sectionsStubNote += rw::kForLegoCountLegend;
        }
        if( legoPreRendered && legoWillStub )
        {
            legoStr = legoPricing.stubXml;
        }
        if( composePreRendered && composeWillStub )
        {
            composeStr = composePricing.stubXml;
        }
        const std::size_t sectionsStubSpliceReserve = sectionsStubNote.size();

        // ── §F1 (CA4 wave-1 verifier): the lens's LAST TWO payload sections, rendered and CHARGED here ──────
        // §H7 gave the default map the structural property "a section cannot be APPENDED without being
        // charged" — and this lens kept two sections outside it, emitted straight to stdout AFTER est_tokens
        // was already written: --detail=N bodies and --with-graph's mermaid block. MEASURED at the pause:
        // `--for --token-budget=2000 --detail=20` streamed 68 035 B against a 4 248 B allowance (16x) with
        // est_tokens="1674" unmoved and stderr empty, while the self-check that concluded "no bypass found"
        // was taken on the BARE --for — the one shape where both sections are absent. Both now go through
        // rw::chargeSection for the reason the map's four do: a section that renders through the funnel is
        // charged by construction, not by a second piece of code remembering to add it.
        //
        // ORDER HERE (not the emission order, which is unchanged: detail, then graph): the graph block has no
        // budget knob, so its size is a FIXED cost; the bodies are the one section with a byte budget, so they
        // are the section that absorbs whatever the ceiling has left. Pricing the fixed cost first is what lets
        // the bodies' budget be exact.
        // (graphSection is rendered above, before <sigs> — fix round 4 reserves its bytes out of the sig side.)

        // both kept alive past the render so the isRendered=false degrade path below re-emits the SAME set at
        // the SAME budget (the map path's emitSection lambda has the identical contract); detailIds is computed above
        std::size_t detailBodyBudget = 0;
        // forbudget-soft: WHAT THE TRAILING SECTIONS ARE FUNDED FROM (bodies, hops, tail), in the default answer's priority
        // order. DEFAULT: the bundle as it stood at the 7.5 KB target — the rows served past it (past_target=) are not charged
        // to the sections after them, so no section shrinks because the head was kept whole. SOFT TARGET (round C, reserve
        // first): the same rule at the soft target's cut — the rows the retired hard ceiling served at this N — so each section
        // keeps at least the share that ceiling gave it; the header and every disclosure are never charged there.
        const std::size_t sigsFundedBytes = sigsStr.size() - std::min( sigsStr.size(), forSigsCut.pastTargetBytes );
        const std::size_t rowsSpentBytes  = forHdrXml.size() + sigsFundedBytes + legoStr.size() + composeStr.size() + routeStr.size() + graphSection.xml.size();
        const std::size_t headerSpentBytes = forSoftTarget ? 0u
                                                           : headerStr.size() + 6 + headerSpliceReserve + droppedPositiveSpliceReserve + sectionsStubSpliceReserve;

        // --detail=N (lever 3): importance-weighted detail — spend FULL bodies on only
        // the top-N ranked symbols (the head the rank identifies), leaving the rest as the signatures emitted
        // above. Measured +63% tokens for the 3 relevant heads vs +355% for all-bodies. N is clamped to the
        // emitted head (forTopN, already narrowed by --adaptive) so a body never references a symbol outside
        // the lens. N=0 emits nothing → byte-identical to a run without --detail.
        if( cfg.detail > 0 )
        {
            // Composes with --max-tokens: when set, it bounds the body byte budget (same conservative rate the
            // map path uses). §F1: --token-budget SHAPES this lens (D10 — trims to fit, always exit 0), so it
            // has to bound the bodies as well; before this it bounded <sigs> ONLY and the bodies rode along on
            // --pack-budget-bytes, which is how a 2 000-token budget delivered 68 KB. The bodies get whatever
            // the ceiling has left after the header, <sigs>, the sibling blocks, the graph block, the closing
            // tag and the two header attributes spliced in below — and never MORE than the budget they already
            // had, so a run WITHOUT --token-budget is byte-identical.
            detailBodyBudget = cfg.maxTokens > 0
                ? rw::budgetBytesForTokens( std::size_t( cfg.maxTokens ) )
                : cfg.packBudgetBytes;
            if( forSoftTarget )
            {
                // the soft target's rows left this much; never below the first body's floor (forDetailFirstBodyFloor: head-cut
                // with next= when oversized), so the one body the caller asked for always ships
                const std::size_t leftBytes = bundleBudget > rowsSpentBytes ? bundleBudget - rowsSpentBytes : 1;
                detailBodyBudget = std::min( detailBodyBudget, std::max( leftBytes, detailFloorBudget ) );
            }
            detailSection = rw::chargeSection( [ & ]( std::FILE* f )
                { packBodies( f, ing, detailIds, detailBodyBudget, g.outOff, g.outTargets, rw::withAnchorEdge( rw::CalleeEdgeBytes( g.outNameOnly, &g.outProv, nullptr ), &g.outAnchorMiss ), cfg.compress, redactPtr,
                              /*ranges=*/nullptr, notesPtr, /*outEmitted=*/nullptr, /*truncateOversizedFirst=*/true,
                              /*withFileContext=*/false, flRootArg, &lensRank, rw::CalleeLegendsInHead( headerParts.viaPresent, headerParts.splitPresent ) ); },   // L3: --detail bodies surface notes too (part of the --for bundle)
                rw::kBytesPerTokenBody );
            if( !detailSection.isRendered )
            {
                DISCLOSE( blockCharge, ForLensBlockCharge::DisclosureWhy::SiblingBlockUnmeasured, "runForLens: the --detail bodies stream uncharged — est_tokens omitted" );
            }
        }

        // ── T3: the terminal-by-default auto <bodies> section (pre-registered: docs/EVALS.md §4) ────────────
        // The decision + render live in buildForAutoBodies (above runForLens — this function is already one
        // of the largest in the file); this site only wires its verdict in: keep the section + attribute, or
        // rebuild the header WITHOUT the legend when its off-switch fires, so the ladder's later rebuilds
        // honor the decision too. One switch since forbudget-soft: surfaceOff (the chargeSection degrade), which
        // clears the root attribute as well; a spent soft target keeps the legend and serves the hops cut marker
        // (hopsCutMarker), whose clause rides and which clears the readings only hop rows could need.
        ForAutoBodiesResult enrich;   // .attr is spliced onto the <ctx> root after the ladder; its bytes are priced there
        if( autoBundleMode && sigsPreRendered )
        {
            // the DEFAULT regime funds the bodies from the bundle at its target (sigsFundedBytes) — the tail rides on top there and
            // the bodies stay what they were; a soft target funds them from the rows' leftover (headerSpentBytes is 0)
            enrich = buildForEnrichment( cfg, ing, g, lensSurfaceIds, lensRank, plan, routeAnchorDefs, redactPtr,
                                          headerSpentBytes + rowsSpentBytes,
                                          bundleBudget, ForSectionPromises{ headerParts.viaPresent, &ownerPlan, headerParts.splitPresent } );
            if( enrich.surfaceOff )
            {
                headerParts.autoBundle = headerParts.compactBundle = false;
                headerParts.viaPresent = false;   // FE-B: the section that could carry it is gone (autoBundleMode excludes --detail)
                headerParts.splitPresent = false;   // attrib-multidef Q1: likewise
                headerParts.ownerPresent = false;   // owner-hop: the same section
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
            }
            else if( headerParts.compactBundle && rankedHopCallsNextPresent( enrich.section.xml ) )
            {
                headerParts.hopsCallsNextPresent = true;   // body-fold rider: the clause rides beside the next= it defines
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
            }
        }
        else if( autoBundleMode )
        {
            // The <sigs> pre-render degraded (disclosed above through blockCharge), so no body is served: the bodies
            // decision and the ladder both need the measured signatures. The root says so with a THIRD reason beside
            // budget/no_candidates, defined in the same header — the legend promising bodies used to ship with neither
            // a bodies section nor any attribute saying why.
            enrich.attr = headerParts.compactBundle ? " bundle=\"compact\" bodies=\"0\" reason=\"degraded\"" : " bundle=\"auto\" bodies=\"0\" reason=\"degraded\"";
            headerStr   = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, kForDegradedBundleNote );
        }
        // ── for-body-slot: THE ONE OWNER BODY, after the compact <hops> (forowner.h states the pick; the header carries its clause).
        // DEFAULT regime: a required section of the complete answer, riding on top — <sigs>, <hops> and <tail> are byte-identical
        // to RIPWIRE_NO_BODY_SLOT=1, est_tokens prices it at the body rate, the runaway guard never reads it. SOFT TARGET (reserve
        // first): funded after the hops from what the rows AT THE CUT left of T; it rides only when its whole render fits that
        // share, else it is SKIPPED — shown="0" capped="1" next= the call that serves it, root reason="budget" — and the tail's
        // share and the rows' refill below both charge what it served, so the rows past the cut give way to it.
        rw::BodySlotRender slot;
        if( slotOwner.any() && autoBundleMode && sigsPreRendered && !enrich.surfaceOff )
        {
            const std::size_t slotSpent = rowsSpentBytes + plan.attrReserve + enrich.section.xml.size();   // the rows at the cut + the hops
            slot = rw::renderForBodySlot( rw::BodySlotInputs{ ing, g.outOff, g.outTargets, g.outNameOnly, lensRank, flRootArg, redactPtr, notesPtr,
                                                              headerParts.viaPresent, cfg.compress, &g.outProv, headerParts.splitPresent, &g.outAnchorMiss },
                                          slotOwner, forSoftTarget ? std::optional<std::size_t>( rw::forSoftSectionsShare( bundleBudget, slotSpent ) )
                                                                   : std::nullopt );
            if( slot.served )
            {
                enrich.attr = " bundle=\"compact\" bodies=\"1\" reason=\"owner\"";   // never bodies="1" beside reason="compact-route"
            }
            else if( slot.skipped )
            {
                enrich.attr = " bundle=\"compact\" bodies=\"0\" reason=\"budget\"";
            }
            else
            {
                // the render's buffer failed: no body rides and nothing names one — the clause goes with it (the T3 degrade contract)
                headerParts.bodySlotPresent = false;
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
            }
        }
        else if( headerParts.bodySlotPresent )
        {
            headerParts.bodySlotPresent = false;   // the compact section degraded (surfaceOff) or the rows were never measured
            headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, enrich.surfaceOff ? std::string_view() : kForDegradedBundleNote );
        }
        ASSUME( !slot.served || headerParts.bodySlotPresent, "a served owner body rides with the clause that defines it" );
        // ── body-fold: THE TOP RANKED BODIES, after the slot (forfold.h states the walk). The default regime only (foldIds above):
        // it rides on top of the complete answer — <sigs>, <hops>, <tail> and the slot are the RIPWIRE_NO_BODY_FOLD=1 bytes but for
        // the <sigs> next= pair spliced below — and est_tokens prices it (bodies at the body rate, the envelope and skips as markup).
        rw::BodyFoldRender fold;
        if( headerParts.bodyFoldPresent )
        {
            if( sigsPreRendered && !enrich.surfaceOff && !enrich.hopsCutMarker )
            {
                fold = rw::renderForBodyFold( rw::BodyFoldInputs{ ing, cfg.forTask, slot.served ? slotOwner.id : rw::kNoNode, lensRank, flRootArg, redactPtr, cfg.compress, &g }, foldIds );
                if( fold.follows > 0 && !fold.xml.empty() )
                {
                    headerParts.foldFollowPresent = true;   // WRAPPER-FOLLOW: the clause rides beside the attribute it defines
                    headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
                }
            }
            if( fold.xml.empty() )
            {
                // the compact section degraded (surfaceOff) or the rows were never measured: no fold, and its clause goes with it
                headerParts.bodyFoldPresent = false;
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, enrich.surfaceOff ? std::string_view() : kForDegradedBundleNote );
            }
        }
        // ── mf1-nx: THE CALLER HOP, the ONE function's callers (forcallerhop.h states the rows). The default regime only
        // (callerHopIds above): it rides on top of the complete answer — every other byte is the RIPWIRE_NO_CALLER_HOP=1 answer's —
        // and est_tokens prices it as markup. No hop when the bodies section degraded or the rows were never measured.
        rw::CallerHopRender callerHop;
        if( headerParts.callerHopPresent )
        {
            if( sigsPreRendered && !enrich.surfaceOff )
            {
                callerHop = rw::renderForCallerHop( ing, g, callerHopIds, flRootArg );
            }
            if( callerHop.xml.empty() )
            {
                headerParts.callerHopPresent = false;   // its clause goes with it
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, enrich.surfaceOff ? std::string_view() : kForDegradedBundleNote );
            }
        }
        // mf1-nx wave 4: THE DISPATCH HOP rides on top of the complete answer like the caller hop (RIPWIRE_NO_DISPATCH_HOP=1 is the
        // rest of it byte for byte); none when the bodies section degraded or no production candidate is left to name
        rw::DispatchHopRender dispatchHop;
        if( headerParts.dispatchHopPresent )
        {
            if( sigsPreRendered && !enrich.surfaceOff )
            {
                dispatchHop = rw::renderForDispatchHop( ing, g, dispatchSites,
                                                        rw::BodyFoldInputs{ ing, cfg.forTask, rw::kNoNode, lensRank, flRootArg, redactPtr, cfg.compress } );
            }
            if( dispatchHop.xml.empty() )
            {
                headerParts.dispatchHopPresent = false;   // its clause goes with it
                // the degraded note is true only when the sigs were never measured (CR 4419328428): an empty hop over measured sigs is healthy
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true,
                                            ( !sigsPreRendered && !enrich.surfaceOff ) ? kForDegradedBundleNote : std::string_view() );
            }
        }
        // lane self-hook (forselfhook.h): decided HERE, after every body section rendered, because it reads what they served: nothing
        // above was priced with it, so it draws on no byte that funds a body (RIPWIRE_NO_SELF_HOOK=1 is the rest of the answer byte for byte)
        std::string selfHookXml;
        if( autoBundleMode && !cfg.json && cfg.tokenBudget <= 0 && rw::forSelfHookOn() && sigsPreRendered && !enrich.surfaceOff )
        {
            std::vector<rw::NodeId> servedBodies = fold.bodies;
            if( slot.served )
            {
                servedBodies.push_back( slotOwner.id );
            }
            if( plan.autoBodies )
            {
                // the auto <bodies> section's candidates that its rendered bytes hold (a candidate the allowance cut is not served)
                for( const rw::NodeId id : computeAutoBodyCandidateIds( ing, lensSurfaceIds, lensRank, routeAnchorDefs ) )
                {
                    const rw::Symbol& s    = ing.symbols[id];
                    const std::string key = " l=\"" + std::to_string( s.line ) + "\" p=\"" + std::string( flRootArg.empty() ? std::string_view( ing.files[s.fileId] ) : rw::sarif::rootRelativeUri( ing.files[s.fileId], flRootArg ) ) + "\" n=\"" + s.name + '"';
                    if( enrich.section.xml.find( key ) != std::string::npos )
                    {
                        servedBodies.push_back( id );
                    }
                }
            }
            selfHookXml = rw::renderForSelfHooks( rw::SelfHookInputs{ ing, g, flRootArg, cfg.forTask }, servedBodies );
            if( !selfHookXml.empty() )
            {
                headerParts.selfHookPresent = true;   // the clause rides beside the element it defines
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
            }
        }
        // ep-manifest: rides on top of the complete answer like the caller hop; none when the bodies section degraded
        if( headerParts.epPresent && ( !sigsPreRendered || enrich.surfaceOff ) )
        {
            epManifest.xml.clear();
            headerParts.epPresent = false;   // its clause goes with it
            headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, enrich.surfaceOff ? std::string_view() : kForDegradedBundleNote );
        }
        if( headerParts.listedPresent && ( !sigsPreRendered || enrich.surfaceOff ) )   // manifest-noncode: same rule as <ep>
        {
            listedIn.xml.clear();
            headerParts.listedPresent = false;
            headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, enrich.surfaceOff ? std::string_view() : kForDegradedBundleNote );
        }
        const rw::ChargedSection& autoSection = enrich.section;
        const std::string&        autoAttr    = enrich.attr;
        if( enrich.hopsCutMarker )
        {
            // fix round 4: the hops budget-cut marker's present-only clause says what the empty element is
            sectionsStubNote += headerParts.compactLegend ? kForHopsBudgetCutLegendCompact : kForHopsBudgetCutLegend;
            // forbudget-soft: the marker carries no row, so the readings only hop rows could need (the via="name" and the
            // owner qword clauses) have nothing to define — cleared as the old attribute-only shape cleared them, so a
            // spent target answers byte-identically with and without the owner plan (ownerhopcheck (B2)); the bundle legend stays.
            // train 28 (CR pre-pass): attrib-multidef's prov="split" reading the same way — the lane cleared it on the retired
            // spent-ceiling switch this marker replaced — unless a served body slot's rows lean on the header's definition
            const bool splitOnlyHops = headerParts.splitPresent && !slot.served;
            if( headerParts.viaPresent || headerParts.ownerPresent || splitOnlyHops )
            {
                headerParts.viaPresent   = false;
                headerParts.ownerPresent = false;
                headerParts.splitPresent = headerParts.splitPresent && !splitOnlyHops;
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
            }
        }

        // ── DEEP-TAIL d2: render the file-grain tail (FOLD C: page 0 of the file page; serialize.h kForFileTailShownCap / kForFileTailPageRows) ──
        // Rendered after the bodies decision. Default regime: the full 40 rows ride on top — the sigs and the bodies are
        // byte-identical to a tail-less bundle by construction (nothing above charges these bytes). A soft target: the tail is
        // the last trailing section, funded from what the rows AT THE CUT and the sections before it left (reserve first).
        // its rank rows exclude the shown rows' files — under a soft target the rows AT THE CUT, the ones a refill below keeps
        const FileTail    forFileTailShown = sigsPreRendered ? computeFileTail( ing, lensRank, lr.evidence,
                                                                                forSoftTarget ? rowsAtTargetIds( shownSigIds, lensRank, forSigsCut.pastTarget )
                                                                                              : shownSigIds,
                                                                                flRootArg, cfg.forTask )
                                                             : forFileTail;
        // round C: the --detail bodies are the caller's own request under their own ceiling (--max-tokens / the pack budget), so
        // they neither fund nor are funded by the reserved sections: the tail's share and the rows' refill both leave them out,
        // and a body ceiling never moves a row (formaxtokenscheck (E))
        const std::size_t tailSpentBytes = forSoftTarget ? rowsSpentBytes + autoSection.xml.size() + slot.xml.size()
                                                         : rowsSpentBytes + detailSection.xml.size() + autoSection.xml.size() + slot.xml.size();
        std::string       tailStr        = renderForFileTailXml( forFileTailShown, cfg.tokenBudget, bundleBudget, tailSpentBytes );

        // ── round C (owner decision 2026-10-14, RESERVE SECTIONS FIRST): the rows past the soft target's cut fill what the
        // trailing sections left of T. The sections above were funded as if the rows stopped at the cut (sigsFundedBytes), so
        // each kept at least the share the retired hard ceiling gave it; the rows are now narrowed to T less those sections'
        // served bytes — never below the cut (a row budget at or under the target IS the cut: serialize.h sigsRowDropEffective).
        // Re-rendered only when that budget is narrower than the first render's, which changes only rows past the cut: the
        // sections' scope (sigsRowsAtTarget) and funding read the rows AT the cut. The first render's redaction count is
        // replaced, never added to; a re-render whose buffer fails keeps the first render and its readings whole.
        if( forSoftTarget && sigsPreRendered && forSigsCut.pastTarget > 0 )
        {
            // the tail is charged at its RESERVE — its share, capped at the whole render of the head-scoped tail (forFileTail: the
            // rows outside the 40-row surface, the same at every N) — not at its filled bytes nor at the cut-scoped tail's size:
            // both step with N (a whole row at a time, as a file moves between the rank rows and the page rows), and
            // the rows past the cut would then fall as N grows. With this reserve the rows are monotone in N.
            std::vector<char> tailEsc;
            const std::size_t tailReserve    = std::min( std::max<std::size_t>( bundleBudget > tailSpentBytes ? bundleBudget - tailSpentBytes : 0u,
                                                                                rw::kForFileTailShellReserve ),
                                                         rw::renderFileTailXml( forFileTail, forFileTail.paths.size(), tailEsc ).size() );
            const std::size_t sectionsServed = forHdrXml.size() + legoStr.size() + composeStr.size() + routeStr.size() + graphSection.xml.size()
                                             + autoSection.xml.size() + slot.xml.size() + tailReserve;   // not the --detail bodies (above)
            const std::size_t rowDropFill    = rw::forSoftRowDropFill( bundleBudget, sectionsServed );
            if( rowDropFill < sigsBudgets.rowDrop )
            {
                const rw::SigsCutReport   firstCut       = forSigsCut;
                const std::size_t         firstDropped   = forDroppedPositive;
                const bool                firstCapped    = forSigsCapped;
                const std::vector<NodeId> firstShown     = shownSigIds;
                const std::optional<RedactCounts> redactNow = redactPtr != nullptr ? std::optional<RedactCounts>( *redactPtr ) : std::nullopt;
                rw::redactTakeBack( redactPtr, redactBeforeSigs, redactAfterSigs );   // the first render's count comes back out
                forSigsCut                     = rw::SigsCutReport {};
                forSigsCut.continuationRequest = &forSigsNext;
                forSigsCut.rowDropBudgetBytes  = rowDropFill;
                forSigsCut.pastTargetDisclosed = false;
                std::string refill;
                if( preRender( renderSigs, refill ) )
                {
                    sigsStr = std::move( refill );
                    // the first render's spelling of the same attribute (no second fixed buffer: fixedbufsweep's census)
                    droppedPositiveNote = forDroppedPositive > 0 ? " dropped_positive=\"" + std::to_string( forDroppedPositive ) + "\""
                                                                 : std::string();
                    sigsCeilingNote = rw::sigsCutReportLegend( forSigsCut );   // a soft target: no default ceiling, no guard reading
                    // lane 2: a row the refill dropped lands in the tail's rank rows — re-listed against the rows now shown, at
                    // the same share (the share, not the rows, is what the refill priced)
                    tailStr = renderForFileTailXml( computeFileTail( ing, lensRank, lr.evidence, shownSigIds, flRootArg, cfg.forTask ),
                                                    cfg.tokenBudget, bundleBudget, tailSpentBytes );
                }
                else
                {
                    forSigsCut         = firstCut;
                    forDroppedPositive = firstDropped;
                    forSigsCapped      = firstCapped;
                    shownSigIds        = firstShown;
                    if( redactNow )
                    {
                        *redactPtr = *redactNow;
                    }
                }
            }
        }

        // ep-manifest (CodeRabbit 4381174525): the groups were picked from the ranked head BEFORE <sigs> rendered, and the
        // renderer may drop a head row (the budget gate, the trim ladder, a soft target's refill). The manifest is re-picked from
        // the head rows <sigs> finally emits, so its legend's "registers a shown row" holds; nothing dropped = no change, and a
        // manifest left with no group goes with its clause (as the degraded branch above).
        if( ( headerParts.epPresent || headerParts.listedPresent ) && sigsPreRendered )
        {
            std::vector<rw::NodeId> epEmitted;
            for( const rw::NodeId id : epHead )
            {
                if( std::ranges::find( shownSigIds, id ) != shownSigIds.end() )
                {
                    epEmitted.push_back( id );
                }
            }
            if( epEmitted.size() != epHead.size() && headerParts.epPresent )
            {
                epManifest = rw::renderForEpManifest( ing, epEmitted );
                if( epManifest.xml.empty() )
                {
                    headerParts.epPresent = false;   // its clause goes with it
                    headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
                }
            }
            if( epEmitted.size() != epHead.size() && headerParts.listedPresent )   // manifest-noncode: "lists a shown file" holds the same way
            {
                listedIn = rw::renderForListedIn( ing, epEmitted, cfg.forTask );
                if( listedIn.xml.empty() )
                {
                    headerParts.listedPresent = false;
                    headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
                }
            }
        }
        // body-fold C3: the <sigs> continuation pair, once the fold rode (forfold.h spliceFoldSigsNext; before the root is priced)
        if( !fold.xml.empty() )
        {
            rw::spliceFoldSigsNext( sigsStr, sigsCeilingNote, fold.firstSkipNext );
        }
        // The text the answer already serves whole, ONE reading for the three late splices below (member-names, FOR-SLOTS, OWNER-CTOR-HOP):
        // the fold's bodies and member slices, plus the body slot's owner (the fold lists it too when the fold rode). A body section added
        // here reaches every splice at once; each splice takes the set by const reference and never writes it.
        const auto servedAnswerBodies = [ & ]()
        {
            rw::MemberNamesServed served{ fold.bodies, fold.sliced };
            if( slot.served )
            {
                served.bodies.push_back( slotOwner.id );
            }
            return served;
        };
        // ── member-names (formembers.h): mem= on the shown owner rows, spliced into the rendered rows AFTER they were chosen (a name
        // never costs a row) and before the root is priced (est_tokens prices the names with <sigs>). The fold's posture — the compact
        // route, XML, the default regime — and the whole answer measured (the splice reads the shown ids against the rendered rows).
        if( autoBundleMode && plan.compact && !cfg.json && cfg.tokenBudget <= 0 && rw::forMemberNamesOn() && sigsPreRendered
            && !enrich.surfaceOff && !enrich.hopsCutMarker )
        {
            const rw::MemberNamesServed answerBodies = servedAnswerBodies();
            if( rw::spliceMemberNames( sigsStr, ing, shownSigIds, cfg.forTask, answerBodies ) > 0 )
            {
                headerParts.memberNamesPresent = true;   // the clause rides beside the attribute it defines
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
            }
        }
        // ── FOR-SLOTS (forslots.h): slots= on the shown initializer rows, the same posture and the same "text already served" rule
        if( autoBundleMode && plan.compact && !cfg.json && cfg.tokenBudget <= 0 && rw::forInitSlotsOn() && sigsPreRendered
            && !enrich.surfaceOff && !enrich.hopsCutMarker )
        {
            const rw::MemberNamesServed answerBodies = servedAnswerBodies();
            if( rw::spliceInitSlots( sigsStr, ing, shownSigIds, answerBodies ) > 0 )
            {
                headerParts.initSlotsPresent = true;   // the clause rides beside the attribute it defines
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
            }
        }
        // ── SLOT JOIN ROWS (forslots.h, IX1-V2): slot_by= / slot_fields= on the shown function and struct rows, the same posture
        if( autoBundleMode && plan.compact && !cfg.json && cfg.tokenBudget <= 0 && rw::forSlotJoinRowsOn() && sigsPreRendered
            && !enrich.surfaceOff && !enrich.hopsCutMarker )
        {
            if( rw::spliceSlotJoinRows( sigsStr, ing, shownSigIds, &headerParts.slotNamePresent ) > 0 )
            {
                headerParts.slotJoinPresent = true;   // the clause rides beside the attributes it defines
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
            }
        }
        // ── OWNER-CTOR-HOP (forctorhop.h): the r=1 method's owner constructor on its row, the same posture and served-text rule
        if( autoBundleMode && plan.compact && !cfg.json && cfg.tokenBudget <= 0 && rw::forCtorHopOn() && sigsPreRendered
            && !enrich.surfaceOff && !enrich.hopsCutMarker )
        {
            const rw::MemberNamesServed answerBodies = servedAnswerBodies();
            if( rw::spliceCtorHop( sigsStr, ing, g, shownSigIds, answerBodies ) > 0 )
            {
                headerParts.ctorHopPresent = true;   // the clause rides beside the attributes it defines
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
            }
        }
        // ── UPWARD-2HOP (forcallerhop.h forRankedCallerHopTargets): an error-shaped task's ranked caller hop, a late splice on the
        // rows <sigs> EMITTED (rankedCallerHop states the posture); its clause rides beside it
        callerHop = rankedCallerHop( RankedHopPosture{ .bundleCompact = autoBundleMode && plan.compact, .sigsRendered = sigsPreRendered,
                                                       .surfaceOff = enrich.surfaceOff, .hopsCutMarker = enrich.hopsCutMarker,
                                                       .namedHop = headerParts.callerHopPresent, .routeTag = lr.routeTag },
                                     cfg, ing, g, shownSigIds, flRootArg, std::move( callerHop ) );
        if( !callerHop.xml.empty() && !headerParts.callerHopPresent )
        {
            headerParts.callerHopPresent = true;   // the ranked clause rides beside the element it defines
            headerParts.callerHopRanked  = true;
            headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
        }
        // PR #135: the priced root this header will carry — every late splice and the est_tokens fixpoint, in
        // finishForLensHeader (above runForLens, with each splice's rationale).
        const ForLensRootFinish rootFinish{
            .autoAttr             = autoAttr,
            .sigsCeilingAttr      = sigsCeilingAttr,
            .capAttrs             = capAttrsStr,
            .weak                 = forWeak,
            .droppedPositiveNote  = droppedPositiveNote,
            .sigsCeilingNote      = sigsCeilingNote,
            .capNote              = capNoteStr,
            .sectionsStubNote     = sectionsStubNote,   // L2': kForSectionStubLegend, present-only (round-2: only when a section actually collapsed under the priced size gate)
            .notesDegradedAttr    = notesDegradedAttrStr,
            .notesDegradedNote    = notesDegradedNoteStr,
            .measured             = blockCharge.isMeasured,   // every pre-rendered block whole: sigs AND its siblings
            .estTokensLegend      = kForEstTokensLegend,
            .overCeilingLegend    = kForOverCeilingLegend,
            // F2: everything OUTSIDE the header at the markup rate. enrich.markupBytes is the compact <hops> section,
            // folded in here rather than charged separately — one rate, one rounding (ForEnrichmentPlan).
            .nonHeaderMarkupBytes = forHdrXml.size() + sigsStr.size() + legoStr.size() + composeStr.size() + routeStr.size() + graphSection.xml.size()
                                  + enrich.markupBytes + tailStr.size() + slot.markupBytes + fold.markupBytes + callerHop.xml.size() + epManifest.xml.size() + ( dispatchHop.xml.size() - dispatchHop.bodyBytes ) + selfHookXml.size() + listedIn.xml.size() + 6,   // + "</ctx>" (deep-tail: the tail at the markup rate)
            // T3: the body-rate sections; enrich.bodyTokens is zero on the compact route (markup, above); for-body-slot: the
            // owner body at the body rate (a skipped slot's element is markup, above)
            .bodyTokens           = detailSection.tokens + enrich.bodyTokens + slot.bodyTokens + fold.bodyTokens   // body-fold: its bodies
                                  + rw::tokensForEmittedBytes( dispatchHop.bodyBytes, rw::kBytesPerTokenBody ),   // mf1-nx wave 4: a dispatch body
            // forbudget-soft: a soft target is never "over" — budget_tokens= names a target, so it is not a ceiling this root
            // labels against; max_tokens= (the detail bodies' hard ceiling) still is, and the runaway guard's cut is the default's
            .tokenBudget          = 0,
            .maxTokens            = cfg.maxTokens,
            .bodyCeiling          = forBodyCeiling,
            .guardOver            = forGuardCut };

        // forbudget-soft: no header ladder. The W3FIX ceiling ladder (task echo / route= / legend clauses dropped "(ceiling)",
        // over_ceiling's header-floor note) existed to land a HARD ceiling; an explicit --token-budget is a soft target over the
        // rows now (owner decision 2026-10-14), so the header — every legend clause and the verbatim task echo — always ships.
        headerStr = finishForLensHeader( std::move( headerStr ), rootFinish );

        std::fwrite( headerStr.data(), 1, headerStr.size(), stdout );
        // R2-AF (round 2, S4): first rows inside the root, right after the legend — see forHdrRows above.
        // The SAME string every sum above charged (rendered once, beside forHdrRows) — "" when there is no row.
        std::fwrite( forHdrXml.data(), 1, forHdrXml.size(), stdout );
        if( sigsPreRendered )
        {
            std::fwrite( sigsStr.data(), 1, sigsStr.size(), stdout );
        }
        else
        {
            rw::SigsCutReport degradeSigsCut;   // knob-honesty-068: carries the continuation request IN, as on the buffered path
            degradeSigsCut.continuationRequest = &forSigsNext;
            degradeSigsCut.rowDropBudgetBytes  = sigsBudgets.rowDrop;   // forbudget-soft: the same two budgets
            degradeSigsCut.pastTargetDisclosed = !forSoftTarget;
            packSignatures( stdout, ing, lensRank, forTopN, cfg.packBudgetBytes, true, fanInPtr, impurePtr, redactPtr,
                            &forChurn, &forClone, testedPtr, ampPtr, /*rankAdaptivePayload=*/true, sigsBudget, notesPtr, flRootArg,
                            rw::forLensRules( forDocsAfterCode, forEndLines, forHeadRR ), nullptr, nullptr, nullptr,   // the degrade path selects identically
                            forTopRowNext,                                           // L-W: same next= rule on the degrade path
                            &degradeSigsCut,                                         // knob-honesty-068: and the same <sigs next=>
                            SigRowSpelling{ .elideZeroMetrics = true } );            // lean-answers lane: the same row spelling
        }
        if( legoPreRendered )
        {
            std::fwrite( legoStr.data(), 1, legoStr.size(), stdout );
        }
        else if( legoStubTotal > 0 )
        {
            // the degrade path: the buffered render never ran, so the section was never measured and
            // priceSectionStub refused to collapse it (serialize.h, CodeRabbit 4054594306) — streamed WHOLE,
            // the same bytes --sections=lego would restore. Same scope+identity (§P3; un-narrowed — the sigs
            // bytes are unknown here). legoStubTotal == 0 emits nothing, packLego's own no-op.
            ASSUME( !legoWillStub, "runForLens: an unmeasured lego section was marked for collapse" );
            packLego( stdout, ing, legoScoped, lensRank, 12, redactPtr, impurePtr, kNoNode, /*withPaths=*/true, flRootArg, rw::LegoTargetedArgs().withDecidedOutside( g.baseOutsideClauses ), nullptr, &g.implementors );
        }
        if( composePreRendered )
        {
            std::fwrite( composeStr.data(), 1, composeStr.size(), stdout );
        }
        else if( composeStubTotal > 0 )
        {
            // the degrade path, as for lego above: unmeasured, so never collapsed — streamed whole.
            ASSUME( !composeWillStub, "runForLens: an unmeasured compose section was marked for collapse" );
            packCompose( stdout, ing, g.composeEdges, lensSurfaceIds );
        }
        if( routePreRendered )
        {
            std::fwrite( routeStr.data(), 1, routeStr.size(), stdout );
        }
        else if( !g.routeEdges.empty() )
        {
            packRoutes( stdout, ing, g.routeEdges, lensSurfaceIds );
        }

        // DEEP-TAIL d2: the file-grain tail, BEFORE the body sections — a prefix-budgeted consumer meets
        // the file-grain recall before the big CDATA. Bytes already charged (ladder + est_tokens above).
        std::fwrite( tailStr.data(), 1, tailStr.size(), stdout );
        // ep-manifest: the entry-point groups after the tail, before the caller hop ("" when none)
        std::fwrite( epManifest.xml.data(), 1, epManifest.xml.size(), stdout );
        // manifest-noncode: the manifest lines listing a shown file, beside <ep> ("" when none)
        std::fwrite( listedIn.xml.data(), 1, listedIn.xml.size(), stdout );
        // mf1-nx: the caller hop after the tail and before the body CDATA, from the bytes est_tokens priced ("" when none)
        std::fwrite( callerHop.xml.data(), 1, callerHop.xml.size(), stdout );
        // mf1-nx wave 4: the dispatch hop after the caller hop, before the body CDATA ("" when none)
        std::fwrite( dispatchHop.xml.data(), 1, dispatchHop.xml.size(), stdout );
        // lane self-hook: where the base classes reach a served override, before the body CDATA ("" when none)
        std::fwrite( selfHookXml.data(), 1, selfHookXml.size(), stdout );

        // §F1: the last two sections, from the bytes already RENDERED and CHARGED above — so what the header
        // priced and what stdout receives are the same bytes by construction, not by two pieces of code
        // agreeing. The --detail bodies are ADDED after <sigs>/<lego>/<compose>/<routes>, so the rest of the
        // bundle keeps signatures-only. A section whose pre-render degraded (isRendered=false) is emitted here
        // directly at the SAME budget — uncharged for that one run, with an alert, never a fabricated number.
        if( cfg.detail > 0 )
        {
            rw::emitChargedSection( stdout, detailSection, [ & ]{ packBodies( stdout, ing, detailIds, detailBodyBudget, g.outOff, g.outTargets, rw::withAnchorEdge( rw::CalleeEdgeBytes( g.outNameOnly, &g.outProv, nullptr ), &g.outAnchorMiss ),
                                                                              cfg.compress, redactPtr, /*ranges=*/nullptr, notesPtr,
                                                                              /*outEmitted=*/nullptr, /*truncateOversizedFirst=*/true,
                                                                              /*withFileContext=*/false, flRootArg, &lensRank, rw::CalleeLegendsInHead( headerParts.viaPresent, headerParts.splitPresent ) ); } );
        }
        else if( autoSection.isRendered && !autoSection.xml.empty() )
        {
            // T3: the auto <bodies> section — same slot as --detail's (after the signature-shaped sections, so
            // the rest of the bundle keeps its shape). Emitted from the exact bytes est_tokens charged; the
            // degrade path (isRendered=false) deliberately emits NOTHING — the pre-T3 bundle is the fallback
            // contract for this optional enrichment, unlike --detail's explicit request (see the block above).
            std::fwrite( autoSection.xml.data(), 1, autoSection.xml.size(), stdout );
        }
        // for-body-slot: the owner body (or its skip disclosure) after the hops, from the bytes est_tokens priced ("" when none)
        std::fwrite( slot.xml.data(), 1, slot.xml.size(), stdout );
        // body-fold: the top ranked bodies after the slot, from the bytes est_tokens priced ("" when none)
        std::fwrite( fold.xml.data(), 1, fold.xml.size(), stdout );

        // R8: --with-graph — a compact mermaid flowchart of the ranked bundle's anchor neighborhood,
        // right before </ctx>. Off by default (G5): omitted, this is a no-op and output is byte-identical.
        if( cfg.withGraph )
        {
            rw::emitChargedSection( stdout, graphSection, [ & ]{ packGraphBlock( stdout, ing, lensRank, g.outOff, g.outTargets ); } );
        }
        appendSubjectGraphVerbBlock( d, servedAnswerBodies().bodies );   // FOR-ROUTE-DECLINED: "" unless the task is spelled as a graph question that resolves; the bodies this answer carries print no second copy in its path hop bodies

        rw::emitRaw( stdout, "</ctx>" );
        reportRedactions( stderr, redactCounts );
        return 0;
    }
    return std::nullopt;
}

// The --for lens: the ranking runs once, the render once (forbudget-soft: no payment-mode re-renders — the lens has no hard
// ceiling left to land a charged continuation under).
std::optional<int> runForLens( const MainDispatch& d )
{
    const rw::Config& cfg = d.cfg;
    if( cfg.forTask.empty() )
    {
        return std::nullopt;
    }
    rw::LensRanking lr = computeLensRanking( d, cfg.forTask, forCompactPosture( cfg ),
                                             /*fullDistribution=*/!cfg.candidates );   // deep-tail: the bundle serves the file-grain tail; candidates has no tail and keeps the H2 pruning
    // the at= stamp (gitstamp.h): one read per run — every payment-mode render below shares it, like the ranking
    const bool        forSingleRoot = d.ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string forAtStamp    = forSingleRoot ? rw::gitstamp::stampAt( d.root ) : std::string();
    return runForLensPass( d, std::move( lr ), ForLensPassMode{ .forAtStamp = forAtStamp } );
}

std::optional<int> runTargetedViews( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::vector<std::uint32_t>& fanIn        = d.fanIn;
    const QMetrics&                   qmetrics     = d.qmetrics;
    RedactCounts&                     redactCounts = d.redactCounts;
    RedactCounts*                     redactPtr    = d.redactPtr;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — shared
    // by --lego and --exemplar, both dispatched from this function.
    const bool             tvSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view tvRootArg    = tvSingleRoot ? cfg.roots[0] : std::string_view();
    const std::string      tvRootPrefix = tvSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();

    // --lego=TYPE: the TARGETED Lego view — resolve ONE named interface/base and emit its signature, full
    // method contract (where sound), and EVERY implementor (own-language only, via the langCompatible guard
    // in buildGraph) with p= file paths so the agent can open them. Same <lego> schema as --for; mirrors the
    // single-symbol verbs (--around/--expand). file:name disambiguates a same-named type across languages.
    if( !cfg.legoType.empty() )
    {
        // H1: the out-param is the decl→def widening's residue — same-named definitions a file:name type found and could
        // not tie to the file it named. implementors= is read off the one node picked here, so unreported, a drop reached
        // the reader as implementors="0" about a forward declaration.
        std::size_t  legoUnprovenDefs = 0;
        const NodeId focus            = resolveLegoFocus( ing, g.implementors, cfg.legoType, &legoUnprovenDefs );
        if( focus == kNoNode )
        {
            // §B4.2: one shared refusal — a non-defining `file:name` says WHICH files define the type and
            // hands back a runnable retry; a genuinely unknown name still gets the near-miss it always had.
            rw::emitTo( stderr, "{}\n", selectorNotFoundMessage( ing, "ripwire: --lego type not found: ",
                                                                   cfg.legoType, "--lego=" ).c_str() );
            return 1;
        }
        const std::vector<char> legoImpure = computeImpure( ing, g );
        const std::vector<float> flat( ing.symbols.size(), 0.f );   // single iface → rank is irrelevant (id tie-break)
        // R-E fix (2026-08-19): the document root DISCLOSES the root its p= are now relative to. The first
        // R-E landing made packLego's p= root-relative and left the root undisclosed, so a --lego bundle
        // carried relative paths against a root the reader could not name — the honesty rule this tool sells.
        // H5: --lego had no legend at all. The #66 clause rides as its own adjacent comment (graphlegend.h
        // graphUnindexedLegendComment) because kLegoLegend is one closed literal: the attribute below is
        // conditional on g.unindexedFiles, so its definition has to be too.
        // H1: the unproven_defs= clause takes the same route for the same reason (graphlegend.h unprovenDefsVerbComment).
        rw::emitTo( stdout, "{}{}{}{}{}{}", rw::ctxRootOpen( {}, {}, tvRootArg ).c_str(), rw::kLegoLegend,
                     rw::graphUnindexedLegendComment( rw::graphGaugeClauses( g ) ).c_str(),
                     rw::unprovenDefsVerbComment( rw::UnprovenDefsVerb::Lego, legoUnprovenDefs > 0, "<!-- ripwire lego: " ).c_str(),
                     rw::implementorsFloorLegendComment( ing, g.implementors, focus, g.baseOutsideClauses ),   // count-floor: present-only, as the two above
                     rw::legoClosureLegendComment( g.implementors, g.implementorBound, focus ).c_str() );   // lane lego-transitive: present-only, the deeper rows
        const std::string legoTargetedAttr = rw::unprovenDefsAttrXml( legoUnprovenDefs ) + rw::graphCountFloorAttrXml( g );   // outlives the call
        packLego( stdout, ing, g.implementors, flat, 1, d.redactPtr, &legoImpure, focus, /*withPaths=*/true, tvRootArg,
                  rw::LegoTargetedArgs( legoTargetedAttr, cfg.pageLimit, cfg.pageOffset, &g.implementorBound ).withMainRows( g.rubyMainMixins ).withDecidedOutside( g.baseOutsideClauses ) );   // H1 + M15: residue, gauge, marker; the deeper-row page
        rw::emitRaw( stdout, "</ctx>" );
        reportRedactions( stderr, d.redactCounts );      // W3-N1: a contract <m> sig is a redacting seam — disclose the tally
        return 0;
    }

    // --exemplar=KIND|TASK (Q7): return the repo's BEST-IN-CLASS instance of what the agent is about to write
    // — same KIND, high fan-in, low cognitive complexity, tested — as an imitation target (signature + body).
    // Selection is by ROLE (kind + those metrics), a DETERMINISTIC composite sort with an id tie-break; it is
    // NEVER ranked by textual similarity to the query (similar-snippet retrieval measurably hurts).
    // The argument is either a kind token (fn|method|cls|class|struct|iface|var) or a TASK string whose top
    // lexical match's kind is used — one flag, two natural inputs, both resolving to a target kind by ROLE.
    // A3-F5: selection now enforces a hard ccx ceiling, a fixture-path penalty, and a task→kind confidence
    // floor — see exemplar.h for the three invariants; this block only RESOLVES the input and EMITS the pick.
    if( !cfg.exemplar.empty() )
    {
        const ExemplarPick pick = selectExemplar( ing, g, fanIn, qmetrics.tested, cfg.exemplar );

        if( pick.winner == kNoNode )
        {
            if( pick.targetKind == SymKind::Other )
            { // task string matched nothing lexical at all
                rw::emitTo( stderr, "ripwire: --exemplar: no symbol matches '{}'\n", std::string_view( cfg.exemplar.data(), cfg.exemplar.size() ) );
            }
            else
            {
                rw::emitTo( stderr, "ripwire: --exemplar: no {} in the corpus to exemplify\n", symTag( pick.targetKind ) );
            }
            return 1;   // no-candidate case degrades cleanly (clear message, nonzero exit, no crash)
        }

        // emit: a self-describing header (why THIS one), the winner's signature+body via packBodies. Extra
        // attributes surface the A3-F5 degrade paths honestly: low_confidence (weak task→kind fell back to fn)
        // and over_ccx_bar (nothing was under the complexity ceiling — the pick is the least-bad, not clean).
        const auto fin = [ & ]( NodeId i ) -> std::uint32_t { return ( i < fanIn.size() ) ? fanIn[i] : 0u; };
        const auto ts  = [ & ]( NodeId i ) -> std::uint8_t  { return ( i < qmetrics.tested.size() ) ? qmetrics.tested[i] : std::uint8_t( 0 ); };
        const Symbol&     wsym = ing.symbols[ pick.winner ];
        std::vector<char> esc;
        const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // G4: collapse '--' runs so the comment can't terminate early. W3FIX M3: escapeXml below already kept
        // C0/invalid-UTF-8 out, but a '\n' in the task is a LEGAL XML char that escapeXml passed through, so
        // `--exemplar=$'a\nb'` emitted a raw newline outside CDATA. xmlCommentText is the shared scrub (it runs
        // BEFORE ex(), so entity escaping is unchanged and control-free input stays byte-identical).
        const std::string reqNote = xmlCommentText( cfg.exemplar );
        const std::string kindNote = pick.fromTask ? ( " (task -> kind=" + std::string( symTag( pick.targetKind ) )
                                                       + ( pick.lowConfidence ? ", low-confidence: weak match, fell back to fn" : "" ) + ")" )
                                                    : std::string();   // stable storage for %s
        // §B6 M13: the rule is exemplar.h's kExemplarSelectionRule, RENDERED — this legend used to lead with
        // complexity while the composite leads with the fixture penalty, and the MCP twin said a third thing.
        // §B7.9 (CA4): the root element carries in=, ccx= and (conditionally) tested=, and this legend
        // defined candidates=, low_confidence= and over_ccx_bar= but not those three — the three that are
        // the SELECTION EVIDENCE the sentence above claims to be showing ("tested before untested, higher
        // fan-in, lower complexity" is the rule; in=/ccx=/tested= are its inputs, unreadable without a gloss).
        // tested= is absence-meaningful and says so, per the house rule for an omitted-not-zero attribute.
        // The truncation-trio clause closes the four baseline lines this verb held (bodies@shown/total/capped
        // + calls@total, the "cheapest bulk win" shape the baseline header names) — packBodies emits both
        // children, and calls@total only surfaces when the winner has callees, so the gap was tree-dependent.
        // FE-B: the winner's <calls> rows may carry via="name" — defined HERE, on the first screen, not beside the rows
        const bool exemplarVia = rw::namesOnlyOutAny( g.outOff, g.outNameOnly, std::span<const NodeId>( &pick.winner, 1 ) );
        rw::emitTo( stdout, "<!-- ripwire exemplar for \"{}\"{}: the repo's best-in-class {} to imitate — {}. "
                     "On the root, the three attributes that ARE that ordering's evidence: in=reuse-count "
                     "(callers), ccx=cognitive complexity, tested=1 when a test reaches it (OMITTED, never 0, "
                     "when none does). The body follows in a bodies section, its callee signatures in a calls "
                     "child; both disclose truncation the house way: total= is how many qualified, shown= how "
                     "many are printed, capped=1 when the two differ (calls omits shown= and capped= when its "
                     "list is complete). Copy its shape, not its text.{} -->",
                     ex( reqNote ).c_str(), kindNote.c_str(), symTag( pick.targetKind ), rw::kExemplarSelectionRule,
                     exemplarVia ? rw::forViaNameClause() : std::string() );
        // R-E fix (2026-08-19): root= — same reason as --lego above. p= went root-relative in the first R-E
        // landing with no attribute naming the root, on the one verb whose whole job is "open this file".
        const std::string exemplarRootAttr = tvSingleRoot ? ( " root=\"" + ex( tvRootArg ) + "\"" ) : std::string();
        rw::emitTo( stdout, "<exemplar kind=\"{}\" candidates=\"{}\" n=\"{}\" p=\"{}:{}\" in=\"{}\" ccx=\"{}\"{}{}{}{}>",
                     symTag( pick.targetKind ), pick.candidateCount, ex( wsym.name ).c_str(),
                     ex( tvSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ wsym.fileId ], tvRootPrefix ) : std::string_view( ing.files[ wsym.fileId ] ) ).c_str(), wsym.line,
                     fin( pick.winner ), wsym.ccx, exemplarRootAttr.c_str(), ts( pick.winner ) ? " tested=\"1\"" : "",
                     pick.lowConfidence ? " low_confidence=\"1\"" : "",
                     pick.overCcxBar    ? " over_ccx_bar=\"1\"" : "" );
        packBodies( stdout, ing, { pick.winner }, cfg.packBudgetBytes, g.outOff, g.outTargets, g.outNameOnly, cfg.compress, redactPtr,
                   /*ranges=*/nullptr, /*noteIndex=*/nullptr, /*outEmitted=*/nullptr, /*truncateOversizedFirst=*/true,
                   /*withFileContext=*/false, tvRootArg, /*calleeRank=*/nullptr, exemplarVia );
        rw::emitRaw( stdout, "</exemplar>" );
        reportRedactions( stderr, redactCounts );
        return 0;
    }

    // --recall=TASK: retrieve the most relevant DOCUMENTS (memory notes / design docs) for a task and emit
    // their FULL bodies, token-budgeted — the memory-as-graph recall verb (pull the relevant few, not the
    // whole corpus). Same deterministic lexical ranking as --for; relatedness is lexical, not graph (eval).
    if( !cfg.recall.empty() )
    {
        // §P2 — the two budget flags obey the documented two-personality rule (D10): --max-tokens SHAPES (byte
        // ceiling at the map family's densest rate × headroom — the old ×4 B/tok overshot ~85×), --token-budget
        // GATES inside emitRecallBudgeted (exit 3, header line only — never the artifact it rejected).
        // R-R: the run's own root, derived ONCE and spent twice inside recallFor — the ranker relativizes the
        // path tokens it scores against it, and buildRecall relativizes the separator line it prints against
        // it. Two consumers of one fact, because a bundle whose ranking and whose display disagreed about the
        // spelling of a file is exactly the drift the root-relative emission lane spent a round removing.
        // Empty for multi-root, where ing.files already hold the labelled root-relative spelling.
        const std::string_view   recallRootArg = ( ing.realPaths.empty() && cfg.roots.size() == 1 )
                                                     ? std::string_view( cfg.roots[0] ) : std::string_view();
        // Recall is uniquely body-heavy: an unset ceiling used to let a broad docs query stream hundreds of
        // thousands of tokens. Keep explicit --max-tokens authoritative, but make the common agent path safe.
        const bool               defaultRecallBudget = cfg.maxTokens == 0;
        const std::size_t        recallMaxTokens = defaultRecallBudget ? rw::kDefaultRecallMaxTokens
                                                                       : std::size_t( cfg.maxTokens );
        // H9: the TOKEN count is what travels now — recall.h's recallBytesForTokens owns the one conversion,
        // so the header discloses the ceiling actually applied instead of only the 8000 default.
        // §B2: --top-k=N now actually SHAPES how many docs recall emits (was accept-and-ignore — --help and
        // the --limit refusal both already promised this). Default stays 8 when the user never passed the flag.
        const int                 recallK = cfg.topKExplicit ? cfg.topK : 8;
        // recallFor (recall.h) is the ONE rank-then-build call MCP `memory_recall` also makes — the recall
        // lens's pathFieldDefaultW=1 and its root-prefix derivation live there, so the two front doors cannot
        // drift apart again (gate: test/recallparitycheck.sh).
        // F4: --token-budget's GATING ceiling travels to the header too, so both ceilings this run applied are
        // named where an attribute reader finds them (it used to live only in the withheld prose and stderr).
        const RecallBundle       bundle = recallFor( ing, g.outOff, g.outTargets, cfg.recall, recallK, recallMaxTokens,
                                                     redactPtr, recallRootArg,     // docs only; R-R
                                                     cfg.tokenBudget > 0 ? std::size_t( cfg.tokenBudget ) : 0u );

        const int                rc     = emitRecallBudgeted( stdout, bundle, cfg.tokenBudget );
        reportRedactions( stderr, redactCounts );
        return rc;
    }
    return std::nullopt;
}

// L4 — --pack-task="TASK": the budget-shared task bundle. ONE call assembling
// the whole 3-5 call orientation dance under ONE deterministic byte budget (default 6K tokens; --token-budget
// overrides), in a FIXED section order with a header that reports EVERY truncation (the overbudgetcheck "no
// silent caps" precedent). Reuses: the shared lens ranking (computeLensRanking — all --for boosts apply), the
// --detail body machinery (packBodies), the --callers in-edge walk, L3 field notes (notesPtr), and the
// --affected test-mining (transitiveCallers + isTestPath). Existing verbs stay byte-identical (this path is
// only reached when --pack-task is given). Section budgets are consumed in the fixed ALLOCATION order
// ranking > bodies > callers > notes > tests: each section gets whatever the higher-priority sections left, so
// a tiny budget naturally degrades to ranking-only (each dropped section is named in the header — no silent cap).
//
// BUDGET CONTRACT (the gate asserts it): the internal target is `budgetTokens × kMinBytesPerToken ×
// kBudgetHeadroom` bytes; the emitted bundle never exceeds the token CEILING `budgetTokens × kMinBytesPerToken`
// except by at most one section's trailing entry (packBodies always emits its first body whole), so a small
// documented tolerance covers the overshoot.
// The section assembler itself (PackTaskSection / packTaskListSection / the 5-section budget-share machinery /
// kPackTask* constants) now lives in packtask.h (L4) as packTaskBundleText() — shared verbatim with the MCP
// explore/pack_task verb (mcpverbs.h's packTaskText()). This handler only resolves CLI-specific inputs
// (flags, MainDispatch pointers) and hands them to that ONE assembler.
// (#362 review, item 2): the budgeted-window branch, extracted — runPackTask's own complexity was
// the quality gate's finding (19 -> 28 as the paging round grew the branch inline). One helper, one
// job: refuse a partitioned window, serve the candidate page, report the redaction tally.
inline std::optional<int> runPackTaskPage( const MainDispatch& d, const rw::LensRanking& lr, const std::string& task,
                                           const rw::PackTaskInputs& in )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;
    if( cfg.partitionCount > 0 )
    {
        rw::emitRaw( stderr, "ripwire: --partition and a --limit/--offset window are mutually exclusive — a partitioned bundle has N+1 slices and no single candidate order to page; drop one\n" );
        return 1;
    }
    const AdaptiveCut   packCut    = adaptiveCut( lr.rank, 5, std::size_t( cfg.packTopN > 0 ? cfg.packTopN : kForLensDefaultTopN ), true );
    const std::string   packAtStamp = in.rootArg.empty() ? std::string() : gitstamp::stampAt( std::string( in.rootArg ) );
    const std::string   packRankFlags = forPageRankFlagArgv( cfg );
    const int packPageRc = emitForCandidatePage( ing, lr.rank, packCut, rw::ForCandidatePageReq{ task, "--pack-task=", packRankFlags,
                                 /*pasteHandle=*/true, /*compactLegend=*/cfg.legend != "full",
                                 lr.routeNote, in.rootArg,
                                 d.redactPtr, packAtStamp, cfg.tokenBudget, cfg.pageLimit, cfg.pageOffset } );
    reportRedactions( stderr, d.redactCounts );   // W3-N1: the page redacts — the tally reports
    return packPageRc;
}

std::optional<int> runPackTask( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;
    const Graph&        g   = d.g;

    if( !cfg.packTaskFlag )
    {
        return std::nullopt;
    }
    if( cfg.packTask.empty() )   // refuse loudly without a task string (never fall through to the default map)
    {
        rw::emitRaw( stderr, "ripwire: --pack-task: a task string is required — e.g. --pack-task=\"add retry to the http client\"\n" );
        return 1;
    }
    const std::string task( cfg.packTask );

    // ── the routed+anchored lens ranking, shared verbatim with --for (all existing boosts apply) ───────────
    // B1 (#362 review round 4): a window pages the WHOLE positive-score distribution — a pruned ranking is
    // exact only for its top-K, so total= and the far pages would depend on a performance optimisation
    // (measured: 931 vs 1232 candidates on src/). The rule --for's bundle path already follows. The un-paged
    // bundle keeps the H2 pruning: its consumers read only the head.
    const bool packWindowPages = candidatePageWindowed( cfg );
    LensRanking lr = computeLensRanking( d, task, /*compactCandidate=*/false, /*fullDistribution=*/packWindowPages );

    // Q3 per-file churn (mirror --for): only mined on the --for git pass, so here it stays empty/zero when
    // --for wasn't also given → the churn= attr is simply omitted by packSignatures (nullptr-safe).
    std::vector<std::uint32_t> forChurn = d.forChurn;
    if( forChurn.size() != ing.files.size() )
    {
        forChurn.assign( ing.files.size(), 0u );
    }

    PackTaskInputs in;
    in.budgetTokens         = cfg.tokenBudget;        // F5: stays std::size_t end-to-end (0 ⇒ the shared default)
    in.softTarget           = cfg.tokenBudget > 0 && cfg.partitionCount == 0;   // forbudget-soft: the caller's budget is a soft target
    in.compactLegend        = cfg.legend == "compact" && !cfg.json;   // L1 fix round: the ladder prices what the compact layer delivers
    in.sigLadderBudgetBytes = cfg.packBudgetBytes;
    in.compress             = cfg.compress;
    in.fanIn                = d.fanInPtr;
    in.impure               = d.impurePtr;
    in.churn                = &forChurn;
    in.tested               = d.testedPtr;
    in.amp                  = d.ampPtr;
    in.redact               = d.redactPtr;
    in.notes                = d.notesPtr;
    in.notesDegraded        = d.notesDegraded;   // L3 follow-up (CodeRabbit 4053600616)
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    in.rootArg = ( ing.realPaths.empty() && cfg.roots.size() == 1 ) ? cfg.roots[0] : std::string_view();

    // ── THE BUDGETED-BUNDLE CANDIDATE PAGE (paging PoC, issue #294): --pack-task under --token-budget
    // with an explicit window pages its ranked candidates, mirroring --for (the shared inline). The cliff
    // statistic is computed here ONCE (the same call --for's disclosure uses); --partition and a window
    // refuse together — a partitioned bundle has N+1 slices and no single candidate order to page.
    // (#362 review, item 2): the branch body lives in runPackTaskPage — this stays the one-line gate
    if( cfg.tokenBudget != 0 && ( cfg.pageLimit > 0 || cfg.pageOffset > 0 ) )
    {
        return runPackTaskPage( d, lr, task, in );
    }

    // --partition=N: the FAN-OUT form. Same lens ranking, same PackTaskInputs, same
    // assembler; partition.h only decides WHICH slice each of the N+1 bundles is masked to and how the
    // per-agent budget divides. Handled before the single-bundle emission below because it replaces the
    // document, not a section of it. cli.h has already bounded N to 2..16 and refused a bare --partition.
    if( cfg.partitionCount > 0 )
    {
        const std::uint32_t partitionCount = std::uint32_t( cfg.partitionCount );
        // --with-graph splices its mermaid block into ONE bundle's </ctx>; there are N+1 here and no single
        // place it belongs. Say so on stderr rather than dropping it silently (it is not worth failing the
        // whole run over — the bundles themselves are unaffected).
        if( cfg.withGraph )
        {
            rw::emitRaw( stderr, "ripwire: --with-graph is not applied in --partition mode (N+1 bundles, no single graph) — bundles emitted without it\n" );
        }
        if( cfg.json )
        {
            std::string js;
            packpartition::packTaskPartitionText( ing, g, task, lr, in, partitionCount, &js );
            std::fwrite( js.data(), 1, js.size(), stdout );
        }
        else
        {
            const std::string doc = packpartition::packTaskPartitionText( ing, g, task, lr, in, partitionCount );
            std::fwrite( doc.data(), 1, doc.size(), stdout );
        }
        reportRedactions( stderr, d.redactCounts );
        return 0;
    }

    // L2: --json — same section decisions, JSON shape, computed by the SAME packTaskBundleText call the XML
    // path uses (its optional jsonOut tail), so truncation reporting can never drift between the two shapes.
    if( cfg.json )
    {
        // §B1.3 (capture-audit-4): --with-graph has no JSON dialect yet (the mermaid block is XML-only,
        // spliced in only on the plain-text path below) — warn once and continue without it, the same
        // warn-and-continue shape the --partition branch above already uses, rather than silently dropping
        // the flag's effect with no tell at all.
        if( cfg.withGraph )
        {
            rw::emitRaw( stderr, "ripwire: --with-graph is not applied under --json (the mermaid graph block is XML-only for now) — emitted without it\n" );
        }
        std::string js;
        packTaskBundleText( ing, g, task, lr, in, &js );
        std::fwrite( js.data(), 1, js.size(), stdout );
        reportRedactions( stderr, d.redactCounts );
        return 0;
    }

    // R8: --with-graph — a compact mermaid flowchart of the ranked bundle's anchor neighborhood, spliced
    // in right before the bundle's closing </ctx> (the extracted packTaskBundleText owns the tag; splitting
    // here keeps the MCP explore/pack_task path graph-free, which has no --with-graph surface). Off by
    // default (G5): omitted, this is a no-op and output is byte-identical.
    //
    // §F1: RENDERED AND CHARGED FIRST. Spliced in after the assembler had already divided the budget and
    // priced its ceiling ladder, its ~399 B rode in uncharged — MEASURED `--pack-task --token-budget=800
    // --with-graph` = 2 445 B against a 2 171 B allowance, 12.6% over with no over_ceiling, where the bare form
    // at the same budget was conformant. in.trailingSectionBytes hands the assembler the size BEFORE it spends
    // the budget (PackTaskInputs documents both places it lands). The degrade path (isRendered=false) splices
    // nothing and streams the block directly, so the bytes are identical and only the charge is lost.
    rw::ChargedSection graphSection;
    if( cfg.withGraph )
    {
        graphSection        = rw::chargeSection( [ & ]( std::FILE* f ) { packGraphBlock( f, ing, lr.rank, g.outOff, g.outTargets ); },
                                                  rw::kBytesPerTokenDefault );
        in.trailingSectionBytes = graphSection.xml.size();   // 0 on the degrade path — the pre-§F1 accounting for that one run
        in.isTrailingUncharged  = !graphSection.isRendered;  // that degrade was disclosed by the section's sink; the root says so
    }

    std::string bundle = packTaskBundleText( ing, g, task, lr, in );
    if( cfg.withGraph && bundle.size() >= 6 && bundle.compare( bundle.size() - 6, 6, "</ctx>" ) == 0 )
    {
        std::fwrite( bundle.data(), 1, bundle.size() - 6, stdout );
        rw::emitChargedSection( stdout, graphSection, [ & ]{ packGraphBlock( stdout, ing, lr.rank, g.outOff, g.outTargets ); } );
        rw::emitRaw( stdout, "</ctx>" );
    }
    else
    {
        std::fwrite( bundle.data(), 1, bundle.size(), stdout );
    }
    reportRedactions( stderr, d.redactCounts );
    return 0;
}

}   // namespace — verbs_for.h section of main.cpp
