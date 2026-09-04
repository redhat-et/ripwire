#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_for.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

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

    LensRanking out;
    std::vector<float>& lensRank = out.rank;
    if( routeOn )
    {
        lensRank      = ( rc.which == LexMode::NameExact ) ? lexicalScoresNameExactRanked( ing, task, &tierMul )
                                                           : lexicalScoresTiered( ing, g.outOff, g.outTargets, task, forPruneK, ifaceExactPtr, &tierMul );
        out.routeNote  = " [routed: " + rc.reason + shapeDemotionNote( shape ) + "]";
        out.docTierTag = shapeDocTierTag( shape );   // §A4f: the machine form of the same fact, for --format=candidates
        out.routeTag   = ( rc.which == LexMode::NameExact ) ? "name-exact" : "subtoken+body";   // §A4f: the machine form of the same fact
        out.anchorDefs = std::move( const_cast<RouteChoice&>( rc ).anchorDefs );   // empty unless the route was DECIDED by names (lexical.h)
    }
    else
    {
        lensRank = lexicalScoresTiered( ing, g.outOff, g.outTargets, task, forPruneK, ifaceExactPtr, &tierMul );
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
            char nb[ 160 ];
            std::snprintf( nb, sizeof( nb ), " [mention anchor: %u file%s + %u symbols named in the task, score lifted to within 5%% of the top score]",
                           mentionInfo.fileCount, mentionInfo.fileCount == 1 ? "" : "s", mentionInfo.symbolCount );
            out.mentionNote  = nb;
            out.anchorLifts  = mentionInfo.fileCount + mentionInfo.symbolCount;   // §A4f: the count the candidates root emits
        }
    }

    // r4 sibling lift (EXPERIMENTAL, pre-registered — bench/locbench/results/r4_siblift/PREREG.md): lift the
    // strongest query-relevant same-directory siblings of the top-ranked files into the slot ladder. INERT
    // (byte-identical) unless RIPWIRE_SIBLIFT="<seed>,<sib>" parses in range. Routed path only.
    if( !cfg.noRoute )
    {
        if( const auto [ sibSeed, sibPer ] = sibliftParams(); sibSeed > 0 )
        {
            applySiblingLift( ing, lensRank, sibSeed, sibPer );
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
            applyStructuralExpansion( ing, lensRank, expSeeds, expPer );
        }
    }

    // B3 co-change prior boost (OPT-IN, EXPERIMENTAL): files that historically change WITH the top seeds get a
    // bounded secondary boost. Inert (byte-identical) without usable git history. Routed path only.
    if( !cfg.noRoute && ( cfg.cochangeBoost || std::getenv( "RIPWIRE_COCHANGE" ) ) )
    {
        PROFILE_SCOPE_DESCRIBE( "main: co-change prior boost (mine + apply)" );
        std::vector<std::vector<std::uint32_t>> coSets;
        if( multiRoot )
        {
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                if( !hasEnclosingGitRepo( ws[r].arg ) )
                {
                    continue;
                }
                auto part = gitRecentCommitFileSets( ws[r].arg, ing, kCoBoostCommitWindow, kCoBoostMaxFilesPerCommit, r );
                for( std::vector<std::uint32_t>& c : part )
                {
                    coSets.push_back( std::move( c ) );
                }
            }
        }
        else if( hasEnclosingGitRepo( root ) )
        {
            coSets = gitRecentCommitFileSets( root, ing, kCoBoostCommitWindow, kCoBoostMaxFilesPerCommit );
        }

        CoBoostInfo boostInfo;
        if( !coSets.empty() && applyCoChangeBoost( ing, coSets, lensRank, &boostInfo ) )
        {
            char nb[ 200 ];
            std::snprintf( nb, sizeof( nb ), " [cochange boost: promoted %u symbols in %u files that historically change with the top seeds (last %u commits)]",
                           boostInfo.boostedSymbolCount, boostInfo.boostedFileCount, kCoBoostCommitWindow );
            out.boostNote = nb;
        }
    }

    // R5 — doc-mention surfacing (default-on, route-agnostic; see mention.h applyDocMentionBoost):
    // reuses g.mentions (the same doc<->code backtick edges `--mentions=SYM` already exposes) to lift docs
    // that discuss the query's top-resolved symbols, strictly below those symbols' own scores. Runs LAST
    // (after route/anchor/query-mention/co-change) so it reads the fully-resolved rank.
    if( !cfg.noDocMention && !std::getenv( "RIPWIRE_NO_DOC_MENTION" ) )
    {
        DocMentionBoostInfo docMentionInfo;
        if( applyDocMentionBoost( g, lensRank, &docMentionInfo ) )
        {
            char nb[ 160 ];
            std::snprintf( nb, sizeof( nb ), " [doc mentions: %u doc%s discussing %u top-ranked symbol%s surfaced]",
                           docMentionInfo.docCount, docMentionInfo.docCount == 1 ? "" : "s",
                           docMentionInfo.anchorCount, docMentionInfo.anchorCount == 1 ? "" : "s" );
            out.docMentionNote = nb;
        }
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
        char nb[ 208 ];
        if( !ac.hitCeiling && ac.cliffRank < ac.kept )
        {
            std::snprintf( nb, sizeof( nb ), "<!-- adaptive: kept %zu of %d - sharp cliff at rank %zu (%d%% drop), clamped up to the floor of %zu -->",
                           ac.kept, topK, ac.cliffRank, ac.dropPct, ac.kept );
        }
        else if( !ac.hitCeiling )
        {
            std::snprintf( nb, sizeof( nb ), "<!-- adaptive: kept %zu of %d - cliff at rank %zu, %d%% drop -->",
                           ac.kept, topK, ac.cliffRank, ac.dropPct );
        }
        else if( ac.positiveHits <= ac.kept )
        {
            std::snprintf( nb, sizeof( nb ), "<!-- adaptive: kept %zu of %d - only %zu symbols matched this query (sharp query, short tail) -->",
                           ac.kept, topK, ac.positiveHits );
        }
        else
        {
            std::snprintf( nb, sizeof( nb ), "<!-- adaptive: kept %zu of %d - no relevance cliff (broad query saturates the score); capped at the ceiling -->",
                           ac.kept, topK );
        }
        std::fputs( nb, out );
        capN = int( ac.kept );
    }
    packCandidates( out, ing, rank, capN, redact, prov, candRootArg );   // R-R: root-relative p= + id=
}

// ── §A4a — the --for --json bundle, budgeted ────────────────────────────────────────────────────────────
// The JSON lens used to run NO size control at all: byte-identical at --token-budget=1000 and 20000 while
// the XML sibling shrank 4.7x, so the JSON/MCP audience — the one that most needs a budget — had none. It
// runs the same H1 ladder against the same budget the XML path computes, and SAYS what it did: "capped" is
// the ladder's own verdict (never inferred by the caller) and "est_tokens" is the delivered size, mirroring
// the XML `<sigs capped="1">` / header `est_tokens="N"` attributes.
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
    // DEEP-TAIL d2: the file-grain tail candidates (computed once, above the dialect split, from the same
    // resolved surface <sigs> selects). REQUIRED, not defaulted — a defaulted pointer is how a dialect
    // silently loses a surface its XML twin serves.
    const rw::FileTail*               fileTail;
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
    const std::string& docMention;
    const std::string& adaptive;
    const std::string& floor;       // LB-A: the relevance floor's shrink note, "" when it did not fire
    // the confidence disclosure is the exception to absent-unless-present: it is a FACT of every ranking
    // (the §A4e `weak` precedent — a root fact must be legible from either dialect, so the XML attrs get
    // real keys here rather than a string spliced somewhere JSON cannot reach).
    const char*        confidence;  // "high" | "low"
    int                marginPct;   // the whole-percent relative drop the confidence derives from (0 = none)
    bool               weak;
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
    std::string_view floorNote;        // LB-A: present only when the relevance floor actually shrank the quota
    // Ranking-confidence disclosure (paper-shape lane; arXiv 2607.24882 names abstention/confidence as the
    // unsolved retrieval axis). ALWAYS present — facts derived from the SAME adaptiveCut gap statistic
    // --adaptive cuts at, no new scorer, no behavior change. The attrs live HERE rather than in the
    // pre-built rootOpenStr because the ceiling ladder's route-dropped rung rebuilds the root open from
    // scratch (ctxRootOpen below) and would silently shed a fact spliced into the pre-built string.
    std::string_view confidenceAttrs;  // e.g. ` confidence="high" margin_pct="34"` — root facts, every ladder rung
    std::string_view confidenceNote;   // the legend sentence defining the two attributes (legend-coverage contract)
    bool             anchor     = false;   // --anchor's EXPERIMENTAL caveat paragraph
    bool             autoBundle = false;   // T3: auto mode is on (cfg.detail==0, no --signatures-only) — appends the bundle=auto legend
    bool             compactBundle = false;   // COMPACT conceptual serving: appends the bundle=compact legend INSTEAD of the auto one — never both, because only one of the two sections can be emitted
    bool             compactLegend = false;  // --legend=compact: versioned, shorter explanatory dialect
    bool             tailLegend    = true;    // deep-tail: the r=/<tail> legend clause. Cleared ONLY by the
                                              //   ceiling ladder's rung zero (with the confidence clause):
                                              //   the facts (r= attrs, the <tail> element) survive, only the
                                              //   explainer goes — the L1 "first rung that costs no unique
                                              //   information" ordering.
    std::string_view rootArg;              // R-E (2026-08-17): the single-root run's own root= — the ladder's
                                            // route-dropped rebuild below calls ctxRootOpen a second time and
                                            // must carry the SAME root as the pre-built rootOpenStr did.
};

// insert pre-formatted attributes (leading space, already attribute-safe — every caller's values come
// from a fixed enum + an int or a versioned schema id, never corpus text) before the root open tag's '>'.
inline std::string rootOpenWithExtraAttrs( std::string rootOpen, std::string_view attrs )
{
    if( attrs.empty() )
    {
        return rootOpen;
    }
    const std::size_t end = rootOpen.find( '>' );
    if( end != std::string::npos )
    {
        rootOpen.insert( end, attrs );
    }
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
struct ForConfidence
{
    std::string attrs;      // ` confidence="high|low" margin_pct="N"` — root facts, every ladder rung
    std::string note;       // the legend clause defining both (legend-coverage contract)
    const char* level = ""; // "high" | "low" — the JSON dialect's key value
    int         marginPct = 0;
};

inline ForConfidence deriveForConfidence( const rw::AdaptiveCut& cut, int servedTopN )
{
    ForConfidence out;
    const bool servedComplete = cut.positiveHits > 0 && cut.positiveHits <= std::size_t( servedTopN );
    out.level     = ( !cut.hitCeiling || servedComplete ) ? "high" : "low";
    out.marginPct = cut.hitCeiling ? 0 : cut.dropPct;
    char attrBuf[ 48 ];
    std::snprintf( attrBuf, sizeof( attrBuf ), " confidence=\"%s\" margin_pct=\"%d\"", out.level, out.marginPct );
    out.attrs = attrBuf;
    // no "--" anywhere (rides inside an XML comment, where "--" is ill-formed — G4). TERSE on purpose:
    // this rides EVERY --for header and its bytes are charged under an explicit budget, so each word
    // competes with a sig row (the W3-S short-spelling precedent). The full mapping: the --for help text.
    out.note = " [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole "
               "percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set "
               "as a starting point, not an answer]";
    return out;
}

inline void appendCompactForLegend( std::string& h, const ForLensHeaderParts& p, std::string_view extraNotes )
{
    h += "<!-- ripwire for ripwire.for/v1: task/route/root and bundle/bodies/reason are root facts; "
         "sigs and hops use total/requested, shown/printed and capped=1 for truncation; cx/ccx/in/churn/amp/clone/tested "
         "are the quality/reuse lens; calls are resolved callees and counts remain floors where stated";
    h.append( p.adaptiveNote );
    h.append( p.mentionNote );
    h.append( p.boostNote );
    h.append( p.docMentionNote );
    h.append( p.floorNote );
    h.append( p.confidenceNote );   // the compact dialect's reader meets the same two root facts
    if( p.tailLegend )
    {
        h.append( rw::kForFileTailLegend );   // deep-tail: r= + <tail> definitions ride the compact legend too
    }
    h.append( extraNotes );
    h += " -->";
    h += rw::forRootRelPathsLegendShort( !p.rootArg.empty() );
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
    "child names its callees (c n= l=). hops and calls disclose total=requested shown=printed capped=1 "
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
               + p.mentionNote.size() + p.boostNote.size() + p.docMentionNote.size() + p.floorNote.size()
               + p.confidenceAttrs.size() + p.confidenceNote.size() + extraNotes.size() );
    h += rootOpenWithSchema( rootOpenWithExtraAttrs( withRouteAttr ? std::string( p.rootOpenStr )
                                                                   : rw::ctxRootOpen( p.task, {}, p.rootArg ),
                                                     p.confidenceAttrs ),
                             p.compactLegend ? "ripwire.for/v1" : std::string_view() );
    if( p.compactLegend )
    {
        appendCompactForLegend( h, p, extraNotes );
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
         "(cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) "
         "— prefer composing/reusing these; watch the high-churn/high-amp/cloned ones";
    if( p.compactBundle )
    {
        h.append( kForCompactBundleLegend );   // COMPACT: replaces the auto legend on the conceptual route — never both
    }
    else if( p.autoBundle )
    {
        h.append( kForAutoBundleLegend );   // T3: present whenever auto mode is on, whatever the fit outcome — it explains bodies="0" too
    }
    if( p.tailLegend )
    {
        h.append( rw::kForFileTailLegend );   // deep-tail: defines r= and the <tail> element (sigs-charge-exempt, serialize.h)
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
    h += rw::forRootRelPathsLegendShort( !p.rootArg.empty() );
    return h;
}

inline std::string forLensJsonHeader( std::string_view task, const ForLensNotes& notes )
{
    using rw::jsonStr;
    std::string h = "{\"task\":\"" + jsonStr( task ) + "\"";
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
    if( !notes.boost.empty() )
    {
        h += ",\"boost\":\"" + jsonStr( notes.boost ) + "\"";
    }
    if( !notes.docMention.empty() )
    {
        h += ",\"doc_mention\":\"" + jsonStr( notes.docMention ) + "\"";
    }
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
// pre-feature bytes exactly (the L3 inertness contract).
inline std::string forLensNotesStanza( const rw::JsonSigNoteCounts& counts, bool active )
{
    if( !active )
    {
        return {};
    }
    return ",\"notes_total\":" + std::to_string( counts.total ) + ",\"notes_kept\":" + std::to_string( counts.kept );
}

// DEEP-TAIL d2, JSON dialect — the tail stanza and its explicit-regime fit, as a free function over
// emitForLensJson's locals (the forSigSideCeiling/ForLensHeaderParts precedent: that emitter is already
// carrying the whole envelope fixpoint). Default regime: the full row cap. Explicit regime: the hard
// ceiling stays hard — rows trim one by one into whatever the rendered bundle left, down to the honest
// empty shell (the always-present key is the disclosure; an absent key would read as "no tail exists").
inline std::string forLensJsonTailStanza( const rw::FileTail& tail, std::size_t tokenBudget,
                                          std::size_t ceilingAllowance, std::size_t baseNoTailBytes )
{
    std::string stanza = "," + rw::renderFileTailJson( tail, rw::kForFileTailShownCap );
    if( tokenBudget == 0 )
    {
        return stanza;
    }
    const std::size_t tailAllowed = ceilingAllowance > baseNoTailBytes ? ceilingAllowance - baseNoTailBytes : 0;
    for( std::size_t shown = tail.paths.size(); ; --shown )
    {
        stanza = "," + rw::renderFileTailJson( tail, shown );
        if( stanza.size() <= tailAllowed || shown == 0 )
        {
            break;
        }
    }
    return stanza;
}

inline int emitForLensJson( std::FILE* out, const std::string& header, const ForLensJsonInputs& in )
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
    const std::size_t bundleBudget = in.tokenBudget > 0
        ? std::size_t( double( in.tokenBudget ) * kMinBytesPerToken * kBudgetHeadroom )
        : kForPayloadBudgetBytes;
    const std::size_t fixedBytes = header.size() + kJsonEnvelopeBytes + kJsonSurfaceCountsBytes
                                  + ( in.noteIndex ? kJsonNotesStanzaBytes : 0 );
    const std::size_t sigsBudget = bundleBudget > fixedBytes ? bundleBudget - fixedBytes : 1;

    const JsonSigLens lens{ /*metrics=*/true, in.fanIn, in.impure, in.churnPerFile, in.cloneMember,
                            in.tested, in.amp, /*rankAdaptivePayload=*/true, in.noteIndex };
    JsonSigNoteCounts noteCounts;
    const auto packSigs = [ & ]( std::FILE* dst, std::size_t budget, bool* outCapped, std::size_t* outDroppedPositive )
    { packSignaturesJson( dst, in.ing, in.rank, in.topN, lens, in.redact, in.packBudgetBytes, budget, outCapped, &noteCounts,
                          in.rootArg, /*hasRelevanceFloor=*/true,        // LB-A: same admission rule as the XML twin (R-R: root-relative p/id)
                          outDroppedPositive ); };                      // A2: exact count, see droppedPositiveCount (serialize.h)

    // §B1.4: built once, used on both the degrade path below and the normal return — these three are plain
    // size_t values already computed by the caller (no rendering, no redaction seam), so unlike est_tokens
    // there is no "cannot compute it here" case that would justify omitting them on the degrade path too.
    const std::string surfaceCountsStanza = ",\"lego_total\":" + std::to_string( in.legoTotal )
                                           + ",\"compose_total\":" + std::to_string( in.composeTotal )
                                           + ",\"routes_total\":" + std::to_string( in.routesTotal );

    // DEEP-TAIL d2, JSON dialect: always-present (B1.4: a total of 0 must mean genuinely none). Default
    // row cap here (the degrade path below needs a stanza before any budget is knowable); the normal path
    // re-fits it after the sigs render (forLensJsonTailStanza above) — residual-funded, sigs untouched:
    // the reservation feeding sigsBudget above deliberately does NOT include these bytes.
    std::string tailStanza = "," + renderFileTailJson( *in.fileTail, kForFileTailShownCap );

    bool        sigsCapped         = false;
    std::size_t sigsDroppedPositive = 0;   // A2: set only by the memstream-buffered render below (nullptr on the ENOMEM degrade path)
    std::string sigsJson;
    {
        char*       jbuf = nullptr;
        std::size_t jsz  = 0;
        std::FILE*  jm   = rw::openChargeBuffer( &jbuf, &jsz );
        if( !jm )
        {
            // ENOMEM-class: emit unbudgeted rather than nothing, and report no est_tokens/capped at all —
            // a number this path cannot compute must never be fabricated.
            DEGRADED_PATH_ALERT( "main: open_memstream failed for the --for --json sigs block — emitting unbudgeted, est_tokens omitted" );
            std::fputs( header.c_str(), out );
            std::fwrite( kJsonBundleSigsKey.data(), 1, kJsonBundleSigsKey.size(), out );   // the posture disclosure survives the degrade (a plain constant — nothing here can fail to compute it)
            std::fwrite( surfaceCountsStanza.data(), 1, surfaceCountsStanza.size(), out );
            std::fwrite( tailStanza.data(), 1, tailStanza.size(), out );                   // the tail survives too (plain strings, nothing to fail)
            std::fputs( ",\"sigs\":", out );
            packSigs( out, 0, nullptr, nullptr );
            std::fputs( "}", out );
            return 0;
        }
        packSigs( jm, sigsBudget, &sigsCapped, &sigsDroppedPositive );
        std::fflush( jm );  std::fclose( jm );
        if( jbuf ) { sigsJson.assign( jbuf, jsz );  std::free( jbuf ); }
    }

    const std::string notesStanza = forLensNotesStanza( noteCounts, in.noteIndex != nullptr );
    // A2 (survey card, 2026-09-03) — the JSON twin of the XML root's dropped_positive= attribute: emitted ONLY
    // when nonzero (the pr_converged precedent, src/prconverge.h), so the overwhelming no-drop path pays 0
    // bytes here exactly as the ENOMEM degrade path above does (sigsDroppedPositive stays 0, never set).
    const std::string droppedPositiveStanza = sigsDroppedPositive > 0
        ? ",\"dropped_positive\":" + std::to_string( sigsDroppedPositive )
        : std::string();

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
    const std::size_t cappedClauseBytes = sigsCapped ? 14u : 15u;      // ,"capped":true / ,"capped":false
    const std::size_t envelopeTextBytes = cappedClauseBytes + 14u + 8u + 1u + kJsonBundleSigsKey.size();   // + ,"est_tokens": + ,"sigs": + } + ,"bundle":"sigs"
    const std::size_t ceilingAllowance  = in.tokenBudget > 0 ? ceilingAllowanceBytes( in.tokenBudget ) : 0;

    // DEEP-TAIL, explicit-regime fit (forLensJsonTailStanza above): residual-funded, sigs untouched.
    tailStanza = forLensJsonTailStanza( *in.fileTail, in.tokenBudget, ceilingAllowance,
                                        header.size() + sigsJson.size() + notesStanza.size()
                                            + surfaceCountsStanza.size() + envelopeTextBytes );
    const std::size_t bundleBytesBase   = header.size() + sigsJson.size() + notesStanza.size()
                                        + surfaceCountsStanza.size() + tailStanza.size() + envelopeTextBytes
                                        + droppedPositiveStanza.size();   // A2: 0 bytes on the (overwhelming) no-drop path

    std::size_t estTokens   = 0;
    std::size_t bundleBytes = bundleBytesBase;
    for( int solvePass = 0; solvePass < 4; ++solvePass )
    {
        const std::size_t digits    = std::to_string( estTokens ).size() - ( estTokens == 0 ? 1 : 0 );
        const bool        isOver    = in.tokenBudget > 0 && ( bundleBytesBase + digits ) > ceilingAllowance;
        const std::size_t withKey   = bundleBytesBase + digits + ( isOver ? 20u : 0u );   // ,"over_ceiling":true
        const std::size_t nextTokens = std::size_t( double( withKey ) / kBytesPerTokenDefault + 0.5 );
        bundleBytes = withKey;
        if( nextTokens == estTokens )
        {
            break;
        }
        estTokens = nextTokens;
    }
    VERIFY( bundleBytes >= bundleBytesBase );
    // W3FIX H2 — the JSON sibling of the XML header's over_ceiling note. The two dialects charge the SAME
    // header bytes to the SAME budget, so they must also agree about the case where that charge cannot make the
    // document fit: the envelope's own verbatim task echo is user-length, and past some task length no sigs
    // trim can bring the bundle under an explicit --token-budget's stated ceiling. Absent ⇒ within the ceiling
    // (the silence-means-nothing-happened convention every other key here uses), never "not measured".
    // §C2: the SAME verdict the charge above solved for — read from the solved bundleBytes so the key that is
    // written and the bytes that were charged can never disagree (they used to be two separate comparisons,
    // one of which did not count the key it was deciding to emit).
    std::string overCeiling;
    if( in.tokenBudget > 0 && bundleBytes > ceilingAllowance )
    {
        overCeiling = ",\"over_ceiling\":true";
    }
    VERIFY( overCeiling.size() == 0 || overCeiling.size() == 20 );   // the 20 the charge above reserved for it
    std::fputs( header.c_str(), out );
    std::fwrite( kJsonBundleSigsKey.data(), 1, kJsonBundleSigsKey.size(), out );
    std::fwrite( surfaceCountsStanza.data(), 1, surfaceCountsStanza.size(), out );
    std::fwrite( tailStanza.data(), 1, tailStanza.size(), out );
    std::fwrite( notesStanza.data(), 1, notesStanza.size(), out );
    std::fwrite( droppedPositiveStanza.data(), 1, droppedPositiveStanza.size(), out );   // A2
    std::fwrite( overCeiling.data(), 1, overCeiling.size(), out );
    std::fprintf( out, ",\"capped\":%s,\"est_tokens\":%zu,\"sigs\":", sigsCapped ? "true" : "false", estTokens );
    std::fwrite( sigsJson.data(), 1, sigsJson.size(), out );
    std::fputs( "}", out );
    return 0;
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
    bool               legendOff   = false;  // exhausted explicit ceiling: attr KEPT (its bytes are the reserve), legend + section dropped —
                                             //   the D10 fit contract and the T3 disclosure contract met at once (fordisclosurecheck #2).
                                             //   BOTH enrichment shapes set it: the body walk and the compact <hops> walk exhaust the same way,
                                             //   and a disclosure that survives only one serving path is not a disclosure.
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
    for( const rw::RouteAnchorDef& a : anchorDefs )
    {
        if( a.fileId == s.fileId && a.lowerName == lower )
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

// ── the auto bundle's SECTION SPLIT (classb-bytes-memo §2 2026-08-22; gate: forbudgetmonotoncheck) ────
// The sig side's claim on the --for bundle ceiling. It used to be the WHOLE ceiling in every regime: the
// sig section had first claim, while the bodies' allowance (kForAutoBodyBudgetBytes) existed only in the
// default regime — so an explicit --token-budget ABOVE the default re-inflated exactly the tail the
// default ladder trims (DJ-B1: <sigs> 1,782 B -> 9,483 B, 8 rows -> 40) and crowded the auto body walk
// from 6 served bodies down to 2: a bundle both BIGGER than the natural default and WORSE on the axis
// the r10 judging credited (full bodies of the decisive symbols). The invariant now enforced: a wider
// ceiling never buys less decisive content. In auto-bundle mode with no explicit --pack-top-n, the sig
// side's claim is capped at the DEFAULT sig budget — a no-op in the default regime (bundleBudget IS
// kForPayloadBudgetBytes there, so the default bundle stays byte-identical), and at any explicit ceiling
// >= kForPayloadBudgetBytes + kForAutoBodyBudgetBytes the sig render equals the default regime's byte
// for byte, so the bodies' leftover is provably >= the default's: every body the default serves still
// fits, and everything beyond the frozen share flows to bodies. An explicit --pack-top-n is an explicit
// SIG posture and keeps the legacy whole-ceiling claim — the frozen share would trim the rows the caller
// literally asked for down to the ladder floor. A free function over runForLens' locals (the
// ForLensHeaderParts precedent) — runForLens is already one of the largest functions in this file.
std::size_t forSigSideCeiling( bool autoBundleMode, int packTopN, std::size_t bundleBudget )
{
    if( autoBundleMode && packTopN == 0 )
    {
        return std::min( bundleBudget, rw::kForPayloadBudgetBytes );
    }
    return bundleBudget;
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
                                        const std::vector<rw::RouteAnchorDef>& anchorDefs )
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
    if( cfg.tokenBudget > 0 && leftBytes == 0 )
    {
        out.attr      = " bundle=\"auto\" bodies=\"0\" reason=\"budget\"";
        out.legendOff = true;
        return out;
    }
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
            { rw::packBodies( f, ing, autoBodyIds, /*budgetBytes=*/1, g.outOff, g.outTargets, cfg.compress, redactPtr,
                               /*ranges=*/nullptr, /*noteIndex=*/nullptr, nullptr, /*truncateOversizedFirst=*/false,
                               /*withFileContext=*/false, fabRootArg ); },
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
        { rw::packBodies( f, ing, autoBodyIds, autoBodyBudget, g.outOff, g.outTargets, cfg.compress, redactPtr,
                           /*ranges=*/nullptr, /*noteIndex=*/nullptr, &autoEmitted, /*truncateOversizedFirst=*/false,
                           /*withFileContext=*/false, fabRootArg ); },
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

ForAutoBodiesResult buildForCompactHops( const rw::Config& cfg, const rw::IngestResult& ing, const rw::Graph& g,
                                          const std::vector<rw::NodeId>& lensSurfaceIds, const std::vector<float>& lensRank,
                                          std::size_t committedBytes, std::size_t bundleBudget, rw::RedactCounts* redactPtr )
{
    ForAutoBodiesResult out;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool             fcSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view fcRootArg    = fcSingleRoot ? cfg.roots[0] : std::string_view();

    // candidates: EXACTLY the head buildForAutoBodies would have bodied — same rule, same order, so the
    // two shapes describe the same symbols and only differ in how much of each they serve.
    std::vector<rw::NodeId> hopIds;
    for( rw::NodeId sid : lensSurfaceIds )
    {
        if( hopIds.size() >= rw::kPackTaskBodyCandidates || lensRank[sid] <= 0.0f )
        {
            break;
        }
        hopIds.push_back( sid );
    }

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
        out.attr      = " bundle=\"compact\" bodies=\"0\" reason=\"budget\"";
        out.legendOff = true;
        return out;
    }

    // the surface allowance MINUS this surface's own fixed disclosure — see kForCompactSurfaceBudgetBytes.
    constexpr std::size_t kCompactFixedBytes = kForCompactBundleLegend.size() + kCompactAttrReserve + kCompactWrapReserve;
    const std::size_t     hopBudget          = std::min( leftBytes, rw::kForCompactSurfaceBudgetBytes > kCompactFixedBytes
                                                                        ? rw::kForCompactSurfaceBudgetBytes - kCompactFixedBytes
                                                                        : std::size_t( 1 ) );

    out.section = rw::chargeSection( [ & ]( std::FILE* f )
        { rw::packHops( f, ing, hopIds, hopBudget, g.outOff, g.outTargets, redactPtr, /*outShown=*/nullptr, &lensRank, fcRootArg ); },
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
    out.attr = hopIds.empty() ? " bundle=\"compact\" bodies=\"0\" reason=\"no_candidates\""
                              : " bundle=\"compact\" bodies=\"0\" reason=\"compact-route\"";
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
                                        rw::RedactCounts* redactPtr, std::size_t committedBytes, std::size_t bundleBudget )
{
    const std::size_t   committed = committedBytes + plan.attrReserve;
    ForAutoBodiesResult out       = plan.compact
        ? buildForCompactHops( cfg, ing, g, lensSurfaceIds, lensRank, committed, bundleBudget, redactPtr )
        : buildForAutoBodies( cfg, ing, g, lensSurfaceIds, lensRank, committed, bundleBudget, redactPtr, anchorDefs );
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

// DEEP-TAIL d2 — the XML tail render + its explicit-regime fit, a free function over runForLens' locals
// (that function is already one of the largest in this file — the forSigSideCeiling precedent). Default
// regime: the full row cap, bytes riding on top (est_tokens measures them). Explicit regime: rows fit the
// residual the rendered bundle actually left; the shell's bytes were reserved ahead of the body walk
// (kForFileTailShellReserve inside the enrichment's committed sum), so the disclosure always fits.
inline std::string renderForFileTailXml( const rw::FileTail& tail, std::size_t tokenBudget,
                                         std::size_t bundleBudget, std::size_t spentBytes )
{
    std::vector<char> esc;
    if( tokenBudget == 0 )
    {
        return rw::renderFileTailXml( tail, rw::kForFileTailShownCap, esc );
    }
    const std::size_t tailAllowed = std::max<std::size_t>( bundleBudget > spentBytes ? bundleBudget - spentBytes : 0u,
                                                           rw::kForFileTailShellReserve );
    return rw::renderFileTailXml( tail, rw::fileTailShownForBudget( tail, tailAllowed, esc ), esc );
}

std::optional<int> runForLens( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::string&                root         = d.root;
    const bool                        multiRoot    = d.multiRoot;
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
        LensRanking        lr        = computeLensRanking( d, cfg.forTask, forCompactPosture( cfg ),
                                                           /*fullDistribution=*/!cfg.candidates );   // deep-tail: the bundle serves the file-grain tail; candidates has no tail and keeps the H2 pruning
        std::vector<float> lensRank  = std::move( lr.rank );
        const std::string  routeNoteRaw = std::move( lr.routeNote ); // verbatim; lands ONLY in route= (attribute-escaped) + the JSON twin — L1: the comment no longer echoes it
        const std::string  mentionNote( std::move( lr.mentionNote ) );
        const std::string  boostNote( std::move( lr.boostNote ) );
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
            forTopN = int( ac.kept );
            char nb[ 200 ];
            if( !ac.hitCeiling && ac.cliffRank < ac.kept )
            {
                std::snprintf( nb, sizeof( nb ), " [adaptive: kept %zu of %d - sharp cliff at rank %zu (%d%% drop), clamped up to the floor of %zu]",
                               ac.kept, ceil, ac.cliffRank, ac.dropPct, ac.kept );
            }
            else if( !ac.hitCeiling )
            {
                std::snprintf( nb, sizeof( nb ), " [adaptive: kept %zu of %d - cliff at rank %zu, %d%% drop]",
                               ac.kept, ceil, ac.cliffRank, ac.dropPct );
            }
            else if( ac.positiveHits <= ac.kept )
            {
                std::snprintf( nb, sizeof( nb ), " [adaptive: kept %zu of %d - only %zu symbols matched this query (sharp query, short tail)]",
                               ac.kept, ceil, ac.positiveHits );
            }
            else
            {
                std::snprintf( nb, sizeof( nb ), " [adaptive: kept %zu of %d - no relevance cliff (broad query saturates the score); capped at the ceiling]",
                               ac.kept, ceil );
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
        const ForConfidence forConf = deriveForConfidence( forCut, forTopN );

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
        // buildForHeader and must honor that decision. Two distinct causes reach it: the chargeSection
        // degrade (surfaceOff — no attribute either) and an exhausted explicit ceiling (legendOff — the
        // root ATTRIBUTE is kept, paid for out of its own reserve). A tight explicit budget no longer
        // turns the disclosure off on EITHER serving shape — test/fordisclosurecheck.sh.
        ForLensHeaderParts headerParts{ cfg.forTask, rootOpenStr, taskNote, adaptiveNote,
                                        mentionNote, boostNote, docMentionNote, floorNote,
                                        forConf.attrs, forConf.note, cfg.anchor,
                                        plan.autoBodies, plan.compact, cfg.legend == "compact",
                                        /*tailLegend=*/true, flRootArg };
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
        // IS-A: socket → bricks — for the interfaces THIS task actually reaches (§P3: the implementors map is
        // pre-scoped to lensSurfaceIds; withPaths keeps two same-named impls apart, exactly as --lego=TYPE
        // spells them). No interface reached ⇒ no <lego> element. Kept alive for the §P3×§P4 narrowing below
        // (XML render) and the §B1.4 count (JSON) — this is pure membership bookkeeping, never a redacting
        // seam, so hoisting it above the --json branch changes no dialect's redaction tally.
        std::vector<std::vector<NodeId>> legoScoped = legoImplementorsOnSurface( ing, g.implementors, lensSurfaceIds );

        // DEEP-TAIL d2: the file-grain tail candidates — one shared walk (serialize.h computeFileTail) for
        // both dialects, computed from the SAME resolved surface <sigs> selects, so the two dialects (and
        // the MCP twin, which calls the same function) cannot select different tails.
        const FileTail forFileTail = computeFileTail( ing, lensRank, lensSurfaceIds, flRootArg );

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
                std::fprintf( stderr, "ripwire: --with-graph is not applied under --json (the mermaid graph block is XML-only for now) — emitted without it\n" );
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
                                                                                              docMentionNote, adaptiveNote, floorNote,
                                                                                              forConf.level,
                                                                                              forConf.marginPct, forWeak,
                                                                                              // abstention round 2: forCut is the SAME
                                                                                              // cut the confidence facts above derive
                                                                                              // from, so the counts and the verdict
                                                                                              // cannot disagree. lensRank is per-symbol
                                                                                              // over the whole index, so its size IS the
                                                                                              // scored corpus.
                                                                                              forCut.kept, forCut.positiveHits,
                                                                                              lensRank.size() } ),
                                                ForLensJsonInputs{ ing, lensRank, forTopN, fanInPtr, impurePtr, &forChurn,
                                                                   &forClone, testedPtr, ampPtr, redactPtr,
                                                                   cfg.packBudgetBytes, cfg.tokenBudget, notesPtr,
                                                                   legoTotal, composeTotal, routesTotal, flRootArg,
                                                                   &forFileTail } );
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

        {
            char*       lbuf = nullptr;
            std::size_t lsz  = 0;
            if( std::FILE* lm = rw::openChargeBuffer( &lbuf, &lsz ) )
            {
                packLego( lm, ing, legoScoped, lensRank, 12, redactPtr, impurePtr, kNoNode, /*withPaths=*/true, flRootArg );
                std::fflush( lm );  std::fclose( lm );
                if( lbuf ) { legoStr.assign( lbuf, lsz );  std::free( lbuf ); }
                legoPreRendered = true;
            }
            else
            {
                DEGRADED_PATH_ALERT( "main: open_memstream failed for the lego block — budget will not see its size" );
            }
        }
        if( !g.composeEdges.empty() )
        {
            char*       cbuf = nullptr;
            std::size_t csz  = 0;
            if( std::FILE* cm = rw::openChargeBuffer( &cbuf, &csz ) )
            {
                packCompose( cm, ing, g.composeEdges, lensSurfaceIds );
                std::fflush( cm );  std::fclose( cm );
                if( cbuf ) { composeStr.assign( cbuf, csz );  std::free( cbuf ); }
                composePreRendered = true;
            }
            else
            {
                DEGRADED_PATH_ALERT( "main: open_memstream failed for the compose block — budget will not see its size" );
            }
        }
        else
        {
            composePreRendered = true;                                // nothing to emit
        }
        if( !g.routeEdges.empty() )
        {
            // B6.3: route view for the same relevant symbol set (top-N by lensRank)
            char*       rbuf = nullptr;
            std::size_t rsz  = 0;
            if( std::FILE* rm = rw::openChargeBuffer( &rbuf, &rsz ) )
            {
                packRoutes( rm, ing, g.routeEdges, lensSurfaceIds );
                std::fflush( rm );  std::fclose( rm );
                if( rbuf ) { routeStr.assign( rbuf, rsz );  std::free( rbuf ); }
                routePreRendered = true;
            }
            else
            {
                DEGRADED_PATH_ALERT( "main: open_memstream failed for the routes block — budget will not see its size" );
            }
        }
        else
        {
            routePreRendered = true;                                  // nothing to emit
        }

        // the bundle budget: default kForPayloadBudgetBytes; an explicit --token-budget beats it
        const std::size_t bundleBudget = cfg.tokenBudget > 0
            ? std::size_t( double( cfg.tokenBudget ) * rw::kMinBytesPerToken * rw::kBudgetHeadroom )
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
        const std::size_t autoLegendBytes = plan.legendBytes;
        // CONFIDENCE: the same exemption a third time, for the same reason as D2's adaptiveNote — the
        // disclosure's contract is DISCLOSURE ONLY, and charging its bytes made the default-budget compact
        // bundle drop a tail <d> row (measured on this repo's own src, the "rank symbols by pagerank"
        // fixture query: one row gone at the trim boundary). DEFAULT REGIME ONLY, and this split is the
        // point where this exemption differs from its two precedents: an explicit --token-budget is a HARD
        // The disclosure is exempt from the SIG-TRIM allowance in BOTH regimes. Charging it under an
        // explicit ceiling (the first cut of this change) shrank the sig section BELOW the default
        // regime's — an explicit ceiling wider than the default re-trimming sigs is exactly the
        // inversion forSigSideCeiling exists to forbid (gate: forbudgetmonotoncheck, which caught it).
        // The est_tokens<=N promise is kept by the BODY side, not by this trim: committedBytes below
        // counts the emitted header verbatim, so leftBytes hands the bodies ~240 B less and the bundle
        // total never crosses the ceiling — charging the sig side as well was double-counting one cost.
        // est_tokens measures the emitted header in both regimes, so nothing under-reports either way.
        const std::size_t confidenceExemptBytes = forConf.attrs.size() + forConf.note.size();
        // DEEP-TAIL: the tail legend's bytes are exempt from the sig-trim charge in BOTH regimes, the
        // confidence-disclosure precedent verbatim — the tail's contract is that the ranked head is
        // byte-identical with and without it, and charging the clause here would shrink <sigs> to pay for
        // a disclosure. The bytes stay real everywhere downstream: est_tokens measures the emitted header,
        // and the explicit regime's tail rows are funded from the RESIDUAL (below), never from the sigs.
        const std::size_t fixedBytes = headerStr.size() - adaptiveNote.size() - autoLegendBytes
                                     - confidenceExemptBytes - rw::kForFileTailLegend.size()
                                     + legoStr.size() + composeStr.size() + routeStr.size() + 6;   // + "</ctx>"
        // the auto bundle's SECTION SPLIT — the sig side's claim is capped so an explicit ceiling wider
        // than the default cannot re-inflate the trimmed sig tail at the bodies' expense (the rule, its
        // measured defect and the invariant: forSigSideCeiling above; gate: forbudgetmonotoncheck).
        const std::size_t sigSideCeiling = forSigSideCeiling( autoBundleMode, cfg.packTopN, bundleBudget );
        const std::size_t sigsBudget = sigSideCeiling > fixedBytes ? sigSideCeiling - fixedBytes : 1;   // ≥1: 0 would mean "no budget"

        // The two attributes SPLICED into the header AFTER the ceiling ladder has chosen a rung — est_tokens
        // (" est_tokens=\"NNNNNNNN\"", bounded well under 24 B: 8 digits covers ~100M tokens) and, when the
        // query scored weak, weak="1" (exactly 9 B). Neither exists yet at ladder time, so the ladder cannot
        // measure them and reserves them instead; both are EXACT-counted into est_tokens itself further down.
        // Seam-verifier LOW (2026-07-29) found the est_tokens half unpriced (a 3-budget-point window landed
        // ~15.5% past the bare ceiling with no over_ceiling label); CA4 verifier L2 found the weak="1" half the
        // same way, 9 bytes spliced in after the number that is supposed to describe them.
        constexpr std::size_t kEstTokensAttrReserve = 24;
        constexpr std::size_t kWeakAttrBytes        = 9;   // exactly ` weak="1"`
        const std::size_t     headerSpliceReserve   = kEstTokensAttrReserve + ( forWeak ? kWeakAttrBytes : 0u );

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
        // (the same reason est_tokens is "omitted", not "wrong", on that path — see its DEGRADED_PATH_ALERT).
        std::size_t forDroppedPositive = 0;
        {
            char*       sbuf = nullptr;
            std::size_t ssz  = 0;
            if( std::FILE* sm = rw::openChargeBuffer( &sbuf, &ssz ) )
            {
                packSignatures( sm, ing, lensRank, forTopN, cfg.packBudgetBytes, true, fanInPtr, impurePtr, redactPtr,
                                &forChurn, &forClone, testedPtr, ampPtr,     // Q3: churn/clone/tested/amp folded onto the <d> blocks
                                /*rankAdaptivePayload=*/true,                // B0.3: tail entries excerpt-trimmed by global rank (serialize.h kForDoc*)
                                sigsBudget,                                  // H1: global payload budget (trim ladder; payload="capped" marker)
                                notesPtr,                                    // L3: field-notes surfacing (inert when null)
                                flRootArg,                                   // R-E: root-relative p=
                                /*hasRelevanceFloor=*/true,                  // LB-A: shrink past the zero-score tail, never pad
                                &forDroppedPositive );                       // A2: exact count, see droppedPositiveCount
                std::fflush( sm );  std::fclose( sm );
                if( sbuf ) { sigsStr.assign( sbuf, ssz );  std::free( sbuf ); }
                sigsPreRendered = true;
            }
            else
            {
                DEGRADED_PATH_ALERT( "main: open_memstream failed for the sigs block — est_tokens omitted from the header" );
            }
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
            std::snprintf( nb, sizeof( nb ), " dropped_positive=\"%zu\"", forDroppedPositive );
            droppedPositiveNote = nb;
        }
        const std::size_t droppedPositiveSpliceReserve = droppedPositiveNote.size();

        // §P3 × §P4: the budget trim above can drop files the lego scope still references — narrow the lego
        // block to the RENDERED sigs' files and re-render (a byte-subset of what the budget already charged
        // for, so the bundle only shrinks; before est_tokens so the header reports the delivered size).
        if( sigsPreRendered && legoPreRendered && !legoStr.empty()
            && narrowLegoToRenderedSigs( ing, legoScoped, sigsStr, flRootArg.empty() ? std::string_view() : rw::sarif::rootPrefixOf( flRootArg ) ) )
        {
            legoStr = captureXml( [ & ]( std::FILE* f ) { packLego( f, ing, legoScoped, lensRank, 12, redactPtr, impurePtr, kNoNode, /*withPaths=*/true, flRootArg ); } );
        }

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
        rw::ChargedSection graphSection, detailSection;
        if( cfg.withGraph )
        {
            graphSection = rw::chargeSection( [ & ]( std::FILE* f ) { packGraphBlock( f, ing, lensRank, g.outOff, g.outTargets ); },
                                               rw::kBytesPerTokenDefault );
        }

        // both kept alive past the render so the isRendered=false degrade path below re-emits the SAME set at
        // the SAME budget (the map path's emitSection lambda has the identical contract)
        std::vector<NodeId> detailIds;
        std::size_t         detailBodyBudget = 0;

        // --detail=N (lever 3): importance-weighted detail — spend FULL bodies on only
        // the top-N ranked symbols (the head the rank identifies), leaving the rest as the signatures emitted
        // above. Measured +63% tokens for the 3 relevant heads vs +355% for all-bodies. N is clamped to the
        // emitted head (forTopN, already narrowed by --adaptive) so a body never references a symbol outside
        // the lens. N=0 emits nothing → byte-identical to a run without --detail.
        if( cfg.detail > 0 )
        {
            const std::size_t S = ing.symbols.size();
            detailIds.resize( S );
            for( NodeId i = 0; i < S; ++i )
            {
                detailIds[i] = i;
            }
            rw::sortutil::radixSortByScoreDescId( detailIds, lensRank );   // (score desc, id asc) — same order as the sigs
            const std::size_t detN = std::min<std::size_t>( { std::size_t( cfg.detail ), std::size_t( forTopN ), S } );
            detailIds.resize( detN );
            // Composes with --max-tokens: when set, it bounds the body byte budget (same conservative rate the
            // map path uses). §F1: --token-budget SHAPES this lens (D10 — trims to fit, always exit 0), so it
            // has to bound the bodies as well; before this it bounded <sigs> ONLY and the bodies rode along on
            // --pack-budget-bytes, which is how a 2 000-token budget delivered 68 KB. The bodies get whatever
            // the ceiling has left after the header, <sigs>, the sibling blocks, the graph block, the closing
            // tag and the two header attributes spliced in below — and never MORE than the budget they already
            // had, so a run WITHOUT --token-budget is byte-identical.
            detailBodyBudget = cfg.maxTokens > 0
                ? std::size_t( double( cfg.maxTokens ) * rw::kMinBytesPerToken * rw::kBudgetHeadroom )
                : cfg.packBudgetBytes;
            if( cfg.tokenBudget > 0 )
            {
                const std::size_t spentBytes = headerStr.size() + sigsStr.size() + legoStr.size() + composeStr.size()
                                             + routeStr.size() + graphSection.xml.size() + 6 + headerSpliceReserve + droppedPositiveSpliceReserve
                                             + rw::kForFileTailShellReserve;   // deep-tail: the shell's reserved bytes (explicit regime only — this branch)
                const std::size_t leftBytes  = bundleBudget > spentBytes ? bundleBudget - spentBytes : 1;
                detailBodyBudget = std::min( detailBodyBudget, leftBytes );
            }
            detailSection = rw::chargeSection( [ & ]( std::FILE* f )
                { packBodies( f, ing, detailIds, detailBodyBudget, g.outOff, g.outTargets, cfg.compress, redactPtr,
                              /*ranges=*/nullptr, notesPtr, /*outEmitted=*/nullptr, /*truncateOversizedFirst=*/true,
                              /*withFileContext=*/false, flRootArg ); },   // L3: --detail bodies surface notes too (part of the --for bundle)
                rw::kBytesPerTokenBody );
        }

        // ── T3: the terminal-by-default auto <bodies> section (pre-registered: docs/EVALS.md §4) ────────────
        // The decision + render live in buildForAutoBodies (above runForLens — this function is already one
        // of the largest in the file); this site only wires its verdict in: keep the section + attribute, or
        // rebuild the header WITHOUT the legend when either off-switch fires, so the ladder's later rebuilds
        // honor the decision too. TWO switches, and they differ in exactly one thing — the root attribute:
        // surfaceOff (the chargeSection degrade) cleared it, legendOff (an exhausted explicit ceiling on
        // either serving shape) KEPT it, so the exhausted case still discloses on the root while paying
        // only the bytes it reserved up front.
        ForAutoBodiesResult enrich;   // .attr is spliced onto the <ctx> root after the ladder; its bytes are priced there
        if( autoBundleMode && sigsPreRendered )
        {
            enrich = buildForEnrichment( cfg, ing, g, lensSurfaceIds, lensRank, plan, routeAnchorDefs, redactPtr,
                                          headerStr.size() + sigsStr.size() + legoStr.size() + composeStr.size()
                                              + routeStr.size() + graphSection.xml.size() + 6 + headerSpliceReserve + droppedPositiveSpliceReserve
                                              + ( cfg.tokenBudget > 0 ? rw::kForFileTailShellReserve : 0u ),
                                          // deep-tail: under an explicit ceiling the tail SHELL's bytes are
                                          // reserved ahead of the body walk (the kAutoAttrReserve pattern) so
                                          // the disclosure always fits; the DEFAULT regime reserves nothing —
                                          // the tail rides on top there and the bodies stay byte-identical.
                                          bundleBudget );
            if( enrich.surfaceOff || enrich.legendOff )
            {
                headerParts.autoBundle = headerParts.compactBundle = false;
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
            }
        }
        const rw::ChargedSection& autoSection = enrich.section;
        const std::string&        autoAttr    = enrich.attr;

        // ── DEEP-TAIL d2: render the file-grain tail, funded LAST (see serialize.h kForFileTailShownCap) ──
        // Rendered after the bodies decision so the explicit regime spends only the RESIDUAL the rendered
        // bundle actually left — the sigs and the bodies are byte-identical to a tail-less bundle in the
        // default regime by construction (nothing above charges these bytes), and under a hard ceiling the
        // weakest-evidence section is the one that trims. The pre-ladder headerStr sizes the residual (a
        // ladder rung can only SHRINK the header, so the fit stays conservative and deterministic).
        const std::string tailStr = renderForFileTailXml( forFileTail, cfg.tokenBudget, bundleBudget,
                                                           headerStr.size() + sigsStr.size() + legoStr.size() + composeStr.size()
                                                               + routeStr.size() + graphSection.xml.size() + detailSection.xml.size()
                                                               + autoSection.xml.size() + autoAttr.size() + 6 + headerSpliceReserve + droppedPositiveSpliceReserve );

        // W3FIX H2 — the ceiling ladder (rungs + rationale: serialize.h climbCeilingLadder), same rungs in the
        // same order --pack-task climbs. The header IS charged to the budget above, but charging is not FITTING: at
        // an explicit --token-budget the header floor (fixed legend + the task echoed twice) can exceed the stated
        // ceiling by itself, sigsBudget then clamps to 1, and packSignatures' first-entry-whole floor still emits
        // ~1.5 KB — a silent 5.3x overrun on a 900-char task, against a --help that promises "trims to fit". Runs
        // BEFORE est_tokens so the estimate covers the disclosure; inert without an explicit --token-budget.
        if( cfg.tokenBudget > 0 && sigsPreRendered )
        {
            static constexpr rw::CeilingLadderNotes kNotes{
                " [task_echo: dropped (ceiling)]", " [task_echo + route_attr: dropped (ceiling)]",
                " [over_ceiling: the header floor (verbatim task echo + fixed legend) exceeds this budget"
                " - no payload left to trim]" };
            // §F1: the ladder prices what will actually be EMITTED, so the two sections charged above are in
            // this sum. headerSpliceReserve covers the est_tokens (and weak="1") attributes spliced in below —
            // see its definition for why a reserve rather than a measurement.
            const std::size_t ladderPayloadBytes = sigsStr.size() + legoStr.size() + composeStr.size() + routeStr.size()
                                                 + detailSection.xml.size() + autoSection.xml.size() + graphSection.xml.size()
                                                 + tailStr.size()                               // deep-tail: the tail is priced like every other section
                                                 + autoAttr.size() + 6 + headerSpliceReserve + droppedPositiveSpliceReserve;   // + "</ctx>" + the header splices below (autoAttr exact-counted; A2's own reserve is exact too)
            const std::size_t ladderCeiling      = rw::ceilingAllowanceBytes( cfg.tokenBudget );
            // RUNG ZERO — the confidence LEGEND clause, before any of the ladder's own rungs: it is the one
            // header string whose loss costs NO unique information (confidence=/margin_pct= stay on the root
            // as facts; only their explanation goes), so it must fall before the verbatim task echo does —
            // the L1 "first rung that costs unique information" ordering. Same silent-legend-drop shape as
            // the enrichment legendOff above (the ATTRIBUTE is the disclosure that survives a spent
            // ceiling). Cleared on headerParts itself so every later ladder rebuild stays note-free.
            // Measured need: fornotesbudgetcheck's 850-ceiling fixture holds 35 tokens of headroom and the
            // clause is ~55 — charged-not-exempt (the explicit-regime split above) still cannot fit it,
            // because the floor there is notes + first-entry-whole, neither of which may trim.
            if( headerStr.size() + ladderPayloadBytes > ladderCeiling
                && ( !headerParts.confidenceNote.empty() || headerParts.tailLegend ) )
            {
                headerParts.confidenceNote = {};
                headerParts.tailLegend     = false;   // deep-tail: the explainer falls with the confidence clause —
                                                      //   the r= attrs and the <tail> element (the facts) survive
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
            }
            headerStr = rw::climbCeilingLadder( buildForHeader, headerStr, ladderPayloadBytes, ladderCeiling,
                                                 /*hasRouteAttr=*/!routeNoteRaw.empty(), kNotes );
        }

        // T3: the bundle=auto disclosure attributes, spliced onto the <ctx> root AFTER the ladder (a rung
        // rebuild would lose an earlier splice — the same reason weak=/est_tokens= splice late). The literal
        // "><!--" boundary is unambiguous: escapeXml entity-escapes '<' inside attribute values, so the first
        // occurrence is the root element's own close. Spliced BEFORE est_tokens is computed, so the number
        // measures a header that already carries these bytes exactly.
        if( !autoAttr.empty() )
        {
            const std::size_t rootCloseAt = headerStr.find( "><!--" );
            if( rootCloseAt != std::string::npos )
            {
                headerStr.insert( rootCloseAt, autoAttr ); // else: unexpected shape, header left as-is (attr dropped, section still disclosed by its own element)
            }
        }

        // R4 + §L2: weak="1" — same insert-before-"-->" mechanism as est_tokens below, but unconditional on
        // sigsPreRendered (forWeak is known from lr.maxLexicalScore regardless of the sigs render path).
        // Absent entirely when the query cleared the threshold (never a fabricated "weak=0" — same
        // silence-means-fine convention as the other opt-in header notes above). It is spliced in AHEAD of
        // est_tokens now: it used to go in afterwards, i.e. 9 bytes of the document that the number describing
        // that document had not measured (CA4 verifier L2). Doing it first makes those 9 bytes part of
        // headerStr.size() below — an exact count, not a reserve.
        if( forWeak )
        {
            const std::size_t closeAt = headerStr.rfind( " -->" );
            if( closeAt != std::string::npos )
            {
                headerStr.insert( closeAt, " weak=\"1\"" ); // else: unexpected shape, header left as-is
            }
        }

        // A2 (survey card, 2026-09-03) — dropped_positive="N": how many symbols scored above the relevance
        // floor (LB-A's own admission rule) and were then removed by the payload ceiling, either the H1
        // ladder's step F or the collection-phase byte gate (droppedPositiveCount, serialize.h). Same
        // insert-before-"-->" splice as weak=/est_tokens= (its value is only known once packSignatures has
        // already run above) — ZERO stays 0 on this path (forDroppedPositive is never set on the direct-
        // emission degrade path), which is what keeps the no-drop path byte-identical: absent entirely, the
        // pr_converged="0" precedent (src/prconverge.h), never a fabricated "dropped_positive=\"0\"". The
        // bracket note is self-defining (legendcoveragecheck's "mentioned"/"defined" predicates both read the
        // name it carries), the same reason weak=/est_tokens= need no separate legend clause of their own.
        if( !droppedPositiveNote.empty() )
        {
            const std::size_t closeAt = headerStr.rfind( " -->" );
            if( closeAt != std::string::npos )
            {
                headerStr.insert( closeAt, droppedPositiveNote ); // else: unexpected shape, header left as-is
            }
        }

        if( sigsPreRendered )
        {
            // §F1: every section this lens emits is in this sum — <sigs>, <lego>, <compose>, <routes>, the
            // --detail bodies and the --with-graph block — each from its own RENDERED bytes.
            //
            // SELF-REFERENCE (the §L2 mechanism generalized): the est_tokens attribute is part of the document
            // est_tokens measures, so its own digit string belongs inside the byte total. The previous form
            // summed the bundle WITHOUT it and reported ~8 tokens under, which is why the measured rate read
            // 2.51 B/tok where this emitter's rate is 2.50. Bounded 4-pass fixpoint, same shape and same bound
            // as serialize()'s and buildRecall's; the attribute BUILT last is the attribute inserted. WHAT THE
            // LOOP GUARANTEES: on convergence (the `break`, reached in <=2 passes on every shape measured) the
            // number stated is exactly the number the document's own bytes were measured against; on the bound
            // it is the number measured against a header whose est_tokens field differed by at most a digit or
            // two, i.e. a residual under one token — never a fabricated number.
            // EACH KIND OF BYTE AT ITS OWN RATE, summed exactly the way the map path sums
            // mapEstTokens + extraPayloadTokens: markup (header, <sigs>, <lego>, <compose>, <routes>, the
            // mermaid graph block) at the mid-band kBytesPerTokenDefault, and the --detail bodies at the
            // kBytesPerTokenBody rate chargeSection already charged them at, because def-body text BPE-merges
            // far more aggressively than signature markup. Converting the WHOLE bundle at the markup rate
            // would over-read the bodies by ~1.5x — the same "one number for two kinds of bytes" defect §H7
            // is about, aimed the other way, and it would report a --for --detail bundle at 2.50 B/tok when
            // its real shape is ~3.6.
            // enrich.markupBytes is the compact <hops> section, folded in HERE rather than charged
            // separately — one rate, one rounding (see ForEnrichmentPlan for the off-by-one that proves it).
            const std::size_t markupBytes = headerStr.size() + sigsStr.size() + legoStr.size() + composeStr.size()
                                          + routeStr.size() + graphSection.xml.size() + enrich.markupBytes
                                          + tailStr.size() + 6;   // + "</ctx>" (deep-tail: the tail's bytes are measured at the markup rate)
            // T3: the auto bodies at the body rate — def-body text BPE-merges differently from markup, which
            // is why this sum splits by kind. enrich.bodyTokens is zero on the compact route (markup, above).
            const std::size_t bodyTokens  = detailSection.tokens + enrich.bodyTokens;
            std::size_t estTokens = rw::tokensForEmittedBytes( markupBytes, kBytesPerTokenDefault ) + bodyTokens;
            std::string attr      = " est_tokens=\"" + std::to_string( estTokens ) + "\"";
            for( int pass = 0; pass < 4; ++pass )
            {
                const std::size_t next = rw::tokensForEmittedBytes( markupBytes + attr.size(), kBytesPerTokenDefault ) + bodyTokens;
                if( next == estTokens )
                {
                    break;
                }
                estTokens = next;
                attr      = " est_tokens=\"" + std::to_string( estTokens ) + "\"";
            }
            const std::size_t closeAt = headerStr.rfind( " -->" );
            if( closeAt != std::string::npos )
            {
                headerStr.insert( closeAt, attr ); // else: unexpected shape, header left as-is
            }
        }

        std::fwrite( headerStr.data(), 1, headerStr.size(), stdout );
        if( sigsPreRendered )
        {
            std::fwrite( sigsStr.data(), 1, sigsStr.size(), stdout );
        }
        else
        {
            packSignatures( stdout, ing, lensRank, forTopN, cfg.packBudgetBytes, true, fanInPtr, impurePtr, redactPtr,
                            &forChurn, &forClone, testedPtr, ampPtr, /*rankAdaptivePayload=*/true, sigsBudget, notesPtr, flRootArg,
                            /*hasRelevanceFloor=*/true );   // LB-A: the direct-emission degrade path selects identically
        }
        if( legoPreRendered )
        {
            std::fwrite( legoStr.data(), 1, legoStr.size(), stdout );
        }
        else
        {
            packLego( stdout, ing, legoScoped, lensRank, 12, redactPtr, impurePtr, kNoNode, /*withPaths=*/true, flRootArg ); // same scope+identity on the degrade path (§P3; un-narrowed — sigs bytes unknown here)
        }
        if( composePreRendered )
        {
            std::fwrite( composeStr.data(), 1, composeStr.size(), stdout );
        }
        else if( !g.composeEdges.empty() )
        {
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

        // §F1: the last two sections, from the bytes already RENDERED and CHARGED above — so what the header
        // priced and what stdout receives are the same bytes by construction, not by two pieces of code
        // agreeing. The --detail bodies are ADDED after <sigs>/<lego>/<compose>/<routes>, so the rest of the
        // bundle keeps signatures-only. A section whose pre-render degraded (isRendered=false) is emitted here
        // directly at the SAME budget — uncharged for that one run, with an alert, never a fabricated number.
        if( cfg.detail > 0 )
        {
            rw::emitChargedSection( stdout, detailSection, [ & ]{ packBodies( stdout, ing, detailIds, detailBodyBudget, g.outOff, g.outTargets,
                                                                              cfg.compress, redactPtr, /*ranges=*/nullptr, notesPtr,
                                                                              /*outEmitted=*/nullptr, /*truncateOversizedFirst=*/true,
                                                                              /*withFileContext=*/false, flRootArg ); } );
        }
        else if( autoSection.isRendered && !autoSection.xml.empty() )
        {
            // T3: the auto <bodies> section — same slot as --detail's (after the signature-shaped sections, so
            // the rest of the bundle keeps its shape). Emitted from the exact bytes est_tokens charged; the
            // degrade path (isRendered=false) deliberately emits NOTHING — the pre-T3 bundle is the fallback
            // contract for this optional enrichment, unlike --detail's explicit request (see the block above).
            std::fwrite( autoSection.xml.data(), 1, autoSection.xml.size(), stdout );
        }

        // R8: --with-graph — a compact mermaid flowchart of the ranked bundle's anchor neighborhood,
        // right before </ctx>. Off by default (G5): omitted, this is a no-op and output is byte-identical.
        if( cfg.withGraph )
        {
            rw::emitChargedSection( stdout, graphSection, [ & ]{ packGraphBlock( stdout, ing, lensRank, g.outOff, g.outTargets ); } );
        }

        std::printf( "</ctx>" );
        reportRedactions( stderr, redactCounts );
        return 0;
    }
    return std::nullopt;
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
        const NodeId focus = resolveFocus( ing, cfg.legoType );
        if( focus == kNoNode )
        {
            // §B4.2: one shared refusal — a non-defining `file:name` says WHICH files define the type and
            // hands back a runnable retry; a genuinely unknown name still gets the near-miss it always had.
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --lego type not found: ",
                                                                   cfg.legoType, "--lego=" ).c_str() );
            return 1;
        }
        const std::vector<char> legoImpure = computeImpure( ing, g );
        const std::vector<float> flat( ing.symbols.size(), 0.f );   // single iface → rank is irrelevant (id tie-break)
        // R-E fix (2026-08-19): the document root DISCLOSES the root its p= are now relative to. The first
        // R-E landing made packLego's p= root-relative and left the root undisclosed, so a --lego bundle
        // carried relative paths against a root the reader could not name — the honesty rule this tool sells.
        std::printf( "%s", rw::ctxRootOpen( {}, {}, tvRootArg ).c_str() );
        packLego( stdout, ing, g.implementors, flat, 1, d.redactPtr, &legoImpure, focus, /*withPaths=*/true, tvRootArg );
        std::printf( "</ctx>" );
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
                std::fprintf( stderr, "ripwire: --exemplar: no symbol matches '%.*s'\n", int( cfg.exemplar.size() ), cfg.exemplar.data() );
            }
            else
            {
                std::fprintf( stderr, "ripwire: --exemplar: no %s in the corpus to exemplify\n", symTag( pick.targetKind ) );
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
        std::printf( "<!-- ripwire exemplar for \"%s\"%s: the repo's best-in-class %s to imitate — %s. "
                     "On the root, the three attributes that ARE that ordering's evidence: in=reuse-count "
                     "(callers), ccx=cognitive complexity, tested=1 when a test reaches it (OMITTED, never 0, "
                     "when none does). The body follows in a bodies section, its callee signatures in a calls "
                     "child; both disclose truncation the house way: total= is how many qualified, shown= how "
                     "many are printed, capped=1 when the two differ (calls omits shown= and capped= when its "
                     "list is complete). Copy its shape, not its text. -->",
                     ex( reqNote ).c_str(), kindNote.c_str(), symTag( pick.targetKind ), rw::kExemplarSelectionRule );
        // R-E fix (2026-08-19): root= — same reason as --lego above. p= went root-relative in the first R-E
        // landing with no attribute naming the root, on the one verb whose whole job is "open this file".
        const std::string exemplarRootAttr = tvSingleRoot ? ( " root=\"" + ex( tvRootArg ) + "\"" ) : std::string();
        std::printf( "<exemplar kind=\"%s\" candidates=\"%zu\" n=\"%s\" p=\"%s:%u\" in=\"%u\" ccx=\"%u\"%s%s%s%s>",
                     symTag( pick.targetKind ), pick.candidateCount, ex( wsym.name ).c_str(),
                     ex( tvSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ wsym.fileId ], tvRootPrefix ) : std::string_view( ing.files[ wsym.fileId ] ) ).c_str(), wsym.line,
                     fin( pick.winner ), wsym.ccx, exemplarRootAttr.c_str(), ts( pick.winner ) ? " tested=\"1\"" : "",
                     pick.lowConfidence ? " low_confidence=\"1\"" : "",
                     pick.overCcxBar    ? " over_ccx_bar=\"1\"" : "" );
        packBodies( stdout, ing, { pick.winner }, cfg.packBudgetBytes, g.outOff, g.outTargets, cfg.compress, redactPtr,
                   /*ranges=*/nullptr, /*noteIndex=*/nullptr, /*outEmitted=*/nullptr, /*truncateOversizedFirst=*/true,
                   /*withFileContext=*/false, tvRootArg );
        std::printf( "</exemplar>" );
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
        const std::size_t        budget = std::size_t( double( recallMaxTokens ) * rw::kMinBytesPerToken
                                                       * rw::kBudgetHeadroom );
        // §B2: --top-k=N now actually SHAPES how many docs recall emits (was accept-and-ignore — --help and
        // the --limit refusal both already promised this). Default stays 8 when the user never passed the flag.
        const int                 recallK = cfg.topKExplicit ? cfg.topK : 8;
        // recallFor (recall.h) is the ONE rank-then-build call MCP `memory_recall` also makes — the recall
        // lens's pathFieldDefaultW=1 and its root-prefix derivation live there, so the two front doors cannot
        // drift apart again (gate: test/recallparitycheck.sh).
        const RecallBundle       bundle = recallFor( ing, g.outOff, g.outTargets, cfg.recall, recallK, budget,
                                                     redactPtr, recallRootArg );   // docs only; R-R

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
        std::fprintf( stderr, "ripwire: --pack-task: a task string is required — e.g. --pack-task=\"add retry to the http client\"\n" );
        return 1;
    }
    const std::string task( cfg.packTask );

    // ── the routed+anchored lens ranking, shared verbatim with --for (all existing boosts apply) ───────────
    LensRanking lr = computeLensRanking( d, task );

    // Q3 per-file churn (mirror --for): only mined on the --for git pass, so here it stays empty/zero when
    // --for wasn't also given → the churn= attr is simply omitted by packSignatures (nullptr-safe).
    std::vector<std::uint32_t> forChurn = d.forChurn;
    if( forChurn.size() != ing.files.size() )
    {
        forChurn.assign( ing.files.size(), 0u );
    }

    PackTaskInputs in;
    in.budgetTokens         = cfg.tokenBudget;        // F5: stays std::size_t end-to-end (0 ⇒ the shared default)
    in.sigLadderBudgetBytes = cfg.packBudgetBytes;
    in.compress             = cfg.compress;
    in.fanIn                = d.fanInPtr;
    in.impure               = d.impurePtr;
    in.churn                = &forChurn;
    in.tested               = d.testedPtr;
    in.amp                  = d.ampPtr;
    in.redact               = d.redactPtr;
    in.notes                = d.notesPtr;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    in.rootArg = ( ing.realPaths.empty() && cfg.roots.size() == 1 ) ? cfg.roots[0] : std::string_view();

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
            std::fprintf( stderr, "ripwire: --with-graph is not applied in --partition mode (N+1 bundles, no single graph) — bundles emitted without it\n" );
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
            std::fprintf( stderr, "ripwire: --with-graph is not applied under --json (the mermaid graph block is XML-only for now) — emitted without it\n" );
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
    }

    std::string bundle = packTaskBundleText( ing, g, task, lr, in );
    if( cfg.withGraph && bundle.size() >= 6 && bundle.compare( bundle.size() - 6, 6, "</ctx>" ) == 0 )
    {
        std::fwrite( bundle.data(), 1, bundle.size() - 6, stdout );
        rw::emitChargedSection( stdout, graphSection, [ & ]{ packGraphBlock( stdout, ing, lr.rank, g.outOff, g.outTargets ); } );
        std::printf( "</ctx>" );
    }
    else
    {
        std::fwrite( bundle.data(), 1, bundle.size(), stdout );
    }
    reportRedactions( stderr, d.redactCounts );
    return 0;
}

}   // namespace — verbs_for.h section of main.cpp
