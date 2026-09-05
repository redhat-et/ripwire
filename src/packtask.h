#pragma once

// packtask.h — the shared task-bundle assembler behind --pack-task (CLI) and the MCP explore/pack_task verb
// (L4). ONE function builds the fixed 5-section budget-shared bundle (routed lens
// ranking > full bodies > 1-hop callers > field notes > tests_to_run) so the two front doors can never drift
// in shape — main.cpp's runPackTask() and mcpverbs.h's packTaskText() both call packTaskBundleText() below
// with their own already-computed LensRanking. The ranking PRIMITIVES (chooseForRanker / lexicalScores /
// applyMentionBoost / applyCoChangeBoost) are the SAME low-level calls either side makes — only the
// surrounding CLI-flag vs MCP-env plumbing differs, exactly like the existing `for` CLI/MCP split.
//
// Included BEFORE mcp.h in main.cpp so mcpverbs.h can reach packTaskBundleText() — this header stays
// self-contained (its own #includes only) so include ORDER elsewhere in main.cpp never matters to it.

#include "model.h"
#include "graph.h"
#include "graphlegend.h"   // R-E fix (2026-08-19): rw::rootRelPathsLegend — the ONE root= definition
#include "lexical.h"       // RouteAnchorDef — the resolved form of the route's own `anchors:` clause
#include "serialize.h"     // packSignatures / packBodies / escapeXml / kMinBytesPerToken / kBudgetHeadroom
#include "redact.h"
#include "notes.h"
#include "filter.h"        // isTestPath
#include "clones.h"        // findClones — the Q3 clone-membership lens (pure `ing` function, no git — safe for both callers)
#include "resolve.h"       // canonicalId — note-target keying
#include "arch.h"          // relForHash — note-target keying
#include "testmap.h"       // §A9.5 / §P11.4: TestRunnerIndex / runAttr — the run= hint on a named test row

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// per-symbol lens rank + the routing/mention/co-change header note fragments — populated identically by the
// CLI's computeLensRanking() (main.cpp, cfg-flag driven) and the MCP for/explore verbs' own routed ranking
// (mcpverbs.h, env-var driven): same underlying chooseForRanker/lexicalScores/applyMentionBoost/
// applyCoChangeBoost calls either side.
struct LensRanking
{
    std::vector<float> rank;
    std::string        routeNote;
    std::string        mentionNote;
    std::string        boostNote;
    std::string        docMentionNote;             // R5: doc<->code mention-edge surfacing (see mention.h
                                                    // applyDocMentionBoost) — "" unless a resolved symbol's
                                                    // g.mentions docs actually got lifted.
    float              maxLexicalScore = 0.0f;    // R4: top raw BM25 score BEFORE --anchor/mention/cochange
                                                   // reshape it — the honest "how much real textual evidence
                                                   // is there" number the weak="1" signal reads.
    // §A4f: the same two facts routeNote/mentionNote carry as PROSE, in a form a machine surface can emit.
    // The notes are sentences for the XML header comment; --format=candidates has no comment to splice them
    // into, so it needs the tag and the count themselves.
    const char*        routeTag    = "no-route";   // "name-exact" | "subtoken+body" | "no-route" (--no-route)
    std::uint32_t      anchorLifts = 0;            // §B8 mention-anchor lifts folded into `rank` (0 = the anchor moved nothing)
    const char*        docTierTag  = nullptr;      // the query-SHAPE document demotion, machine form (filter.h
                                                    // shapeDocTierTag); nullptr = no shape fired, nothing demoted
    // The route's own anchors, RESOLVED to definitions (lexical.h RouteAnchorDef) — the machine form of the
    // `anchors:` clause routeNote already carries as prose. Non-empty on the name-exact route only, and only
    // for words that named something. The T3 auto-body allowance reads it so the bundle serves the anchor's
    // OWN body or none at all (docs/EVALS.md, the anchor-only substitution round).
    std::vector<RouteAnchorDef> anchorDefs;
};

inline constexpr int         kPackTaskDefaultTokens  = 6000;   // the default budget when no explicit budget is given
inline constexpr int         kPackTaskRankTopN       = 12;     // ranking = the top-12 head, not the full 40 — leaves budget for the later sections
inline constexpr std::size_t kPackTaskBodyCandidates = 6;      // top-K heads that get FULL bodies (byte budget trims further)
inline constexpr std::size_t kPackTaskSectionFloor   = 64;     // a section is only attempted when this many bytes remain
// RE-MEASURED 1024 -> 1600 (2026-09-04, capture-audit M11): the header comment alone was 1511 B at a 2040-token
// budget on this tree — the legend outgrew the reserve over the rounds while every bundle still fit by the
// single-entry tolerance; the M11 root clause (~250 B) was the straw, surfacing as --partition's core 6% past
// its ceiling. The reserve must cover the header the ladder cannot trim, or the sections are sized against
// bytes that are not there.
inline constexpr std::size_t kPackTaskHeaderReserve  = 1600;   // the <ctx><!-- report --> + "</ctx>" (a bounded comment)

// §B8.3 (trap #8, "a disclosure has BYTES") — the byte floor packTaskListSection holds back for its own
// wrapper, now that the wrapper carries capped= too. These were bare literals 64 and 96 at the four call
// sites, sized for the pre-capped= tag; the bit costs 11 bytes (` capped="0"`), which on a large corpus
// (6-digit shown=/total=) took <far>'s open+close tag past 64 — a section quietly overspending its own share
// to pay for the attribute that says it was capped. Named, and sized with visible headroom.
inline constexpr std::size_t kPackTaskWrapReserve     = 80;    // <notes>/<tests>/<far>: open tag + close tag
inline constexpr std::size_t kPackTaskWrapReserveWide = 112;   // <callers>: the same plus its of_top= attribute

// The anchor-resolved body allowance's DERIVATION, checked by the compiler instead of asserted in prose:
// serialize.h's kForAnchorBodyBudgetBytes is "what one whole default --pack-task bundle costs", i.e. what
// kPackTaskDefaultTokens buys at kBytesPerTokenBody. This is the only translation unit where all three are
// visible, which is why the check lives here and not beside the constant it pins.
//
// A tolerance BAND, not equality (CONTRIBUTING §3): kBytesPerTokenBody is 3.80, which has no exact binary
// representation, so 6000 * 3.80 lands a hair either side of 22800 depending on how the compiler contracts
// the multiply — an == here would be a build that fails on some hosts and passes on others. +/- 1 B is far
// tighter than any drift worth catching (the failure this guards is somebody editing 22800 to 30000, or
// re-pricing kBytesPerTokenBody, and forgetting the other half of the sentence).
static_assert( double( kForAnchorBodyBudgetBytes ) >= double( kPackTaskDefaultTokens ) * kBytesPerTokenBody - 1.0
            && double( kForAnchorBodyBudgetBytes ) <= double( kPackTaskDefaultTokens ) * kBytesPerTokenBody + 1.0,
               "kForAnchorBodyBudgetBytes must stay equal to kPackTaskDefaultTokens * kBytesPerTokenBody — "
               "one anchor-resolved body may cost at most what one whole default --pack-task bundle costs. "
               "Changing either term without the other silently repeals the registered derivation "
               "(docs/EVALS.md, the T3 body-budget round)." );

// F1 (graphrag harvest 2026-08-15): FIXED proportional quotas over the post-header remaining budget, computed
// UP FRONT — one per section, sum to 1.0 — instead of the old `min( remaining, bundleBudget * frac )` per
// section. That old form let an early section (ranking) swallow the WHOLE remaining budget whenever remaining
// was already smaller than its own frac share (the common case at small --token-budget values), leaving every
// later section a hard zero: `--pack-task=... --token-budget=900` on the ripwire tree reported
// "bodies: omitted | callers: omitted | notes: none | tests: none" — disclosed, but with no floor. Each
// section below now gets its OWN fixed share of the post-header remaining budget; a section that finishes
// under its share rolls the leftover FORWARD into the next section's quota (see the `carry` chain in
// packTaskBundleText), so an early section that needs little still leaves real room for the sections after it.
// tests_to_run — the last section — still absorbs whatever is left of `remaining` after the other four (the
// pre-existing cascade-to-the-end behavior, unchanged): its implicit share is kQuotaTests plus every carry.
// integer percent, not double fractions — five decimal literals summing to 1.0 in floating point is not
// guaranteed bit-exact, and a static_assert is the whole point of naming the split (catch a typo'd share at
// compile time, not by re-deriving the finding at runtime).
inline constexpr int kPackTaskQuotaRankingPct = 40;
inline constexpr int kPackTaskQuotaBodiesPct  = 30;
inline constexpr int kPackTaskQuotaCallersPct = 15;
inline constexpr int kPackTaskQuotaNotesPct   = 5;
inline constexpr int kPackTaskQuotaTestsPct   = 10;   // the cascaded remainder shares this name only in spirit —
                                                        // tests never CAPS at this share, it only starts there.
static_assert( kPackTaskQuotaRankingPct + kPackTaskQuotaBodiesPct + kPackTaskQuotaCallersPct
             + kPackTaskQuotaNotesPct + kPackTaskQuotaTestsPct == 100, "pack-task section quotas must sum to 100%" );

struct PackTaskSection { std::string xml; std::size_t kept = 0; };

// W3FIX H2/M1 — the pieces the header comment is made of, so the header can be REBUILT in three shapes (as
// built / task echo dropped / that plus route=) for serialize.h's climbCeilingLadder to price. A free function
// over a parts struct rather than a lambda inside the assembler: the ladder needs to call it up to three times,
// and the assembler is already the largest function in this file.
struct PackTaskHeaderParts
{
    std::string_view task;             // §B1.7's subject — the VERBATIM query, for the root attribute
    std::string_view rootOpenStr;      // ctxRootOpen( task, routeNote ), pre-built (its size is charged)
    std::string_view taskNote;         // the comment's scrubbed echo of `task` (xmlCommentText)
    std::string_view mentionNote, boostNote, docMentionNote;   // L1: no routeNote — route= is the one copy
    std::string_view report;           // the per-section truncation ledger
    std::string_view rootArg;          // R-E (2026-08-17): the single-root run's own root= — the ladder's
                                        // route-dropped rebuild below calls ctxRootOpen a second time and
                                        // must carry the SAME root as the pre-built rootOpenStr did.
};

// One spelling of --pack-task's header, three shapes of it. `withTaskEcho=false` replaces the comment's echo
// with a note pointing at the task= attribute that still holds the verbatim copy — nothing is lost, only the
// duplicate. Byte-identical to the pre-ladder header when both flags are true and extraNotes is empty.
inline std::string packTaskHeaderText( const PackTaskHeaderParts& p, bool withRouteAttr, bool withTaskEcho,
                                       std::string_view extraNotes )
{
    std::string h = withRouteAttr ? std::string( p.rootOpenStr ) : ctxRootOpen( p.task, {}, p.rootArg );
    h += "<!-- ripwire task bundle for ";
    if( withTaskEcho ) { h += "\"";  h.append( p.taskNote );  h += "\""; }
    else
    {
        h += "[task_echo: dropped (ceiling) - the verbatim copy is the task= attribute above]";
    }
    // L1 (density audit 2026-08-08): the scrubbed route-note echo that rode here duplicated the verbatim
    // route= attribute byte-for-byte in meaning; the attribute is the one copy (test/routeoncecheck.sh).
    h.append( p.mentionNote );
    h.append( p.boostNote );
    h.append( p.docMentionNote );
    h += ": one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, "
         // F1 (graphrag harvest 2026-08-15): each section holds a FIXED, up-front proportional quota of the
         // budget rather than competing for whatever a strict cascade left it — the old shape let ranking
         // (the first section) swallow the WHOLE remaining budget at small --token-budget values, zeroing
         // bodies/callers/notes/tests even though they were "just" capped, never actually reserved anything.
         // Stated tersely, matching trap #8's own precedent (a fixed-size addition, priced once, absorbed by
         // estchargecheck A11's self-tuning ladder): the split and the roll-forward rule, nothing more.
         "quotas per section are FIXED (rank40/body30/caller15/note5/test10, percent of budget), unused quota "
         "ROLLS FORWARD to the next section — a small budget still zeroes a section, but never past its own share. "
         // §B8.3, the half wave 2 did NOT close. packTaskListSection was fixed to EMIT shown=/total=/capped=
         // (see its own comment below), and <bodies>/<calls> carry the same trio — but the vocabulary was
         // defined only in src/pageview.h, which no reader of this bundle holds. Live before this line: a
         // 881 B legend containing the words `shown` and `total` ZERO times, above a document opening
         // `<bodies shown="4" total="6" capped="1">`. Defined here, once, for every section that carries it,
         // because this is the screen the reader meets them on. Deliberately ONE clause: trap #8 — this rides
         // in EVERY bundle at EVERY budget and is charged against the ceiling it describes, and this addition
         // is +88 B measured with `wc -c` — legend 881 → 969 B AND whole document 9473 → 9561 B on the src/
         // fixture, the same delta twice, which is trap #19's signature of a fixed-size addition rather than a
         // re-measurement. estchargecheck A11's self-tuning ladder absorbs it by moving its operating point.
         "each truncates rank-adaptively; every truncation reported here (no silent caps): on every section "
         "shown=rows kept, total=rows that qualified, capped=1 when they differ. "
         // §H5 sub-finding: bodies fill TOP-RANK-FIRST, so a larger budget can admit a large high-rank body and
         // thereby keep fewer, bigger ones — a falling count is not lost content, and the reader should not have
         // to infer that from a number that went down. Stated once, here, where the count itself is printed.
         "bodies fill rank-first, so a bigger budget can keep FEWER, larger bodies — the count is not a quality measure. "
         // §B7.5 (CA4): this dictionary is EXPLICIT — it says "Row keys:" and then lists three of them — so
         // every key it omits reads as "not a row key" rather than "look elsewhere". It omitted l=, cx= and
         // ccx=, which every ranking row carries, plus t=/p=/rel= on the name-only rows, and left the whole
         // <far> element and of_top= undefined. of_top= is the one that needed care: it appears on TWO
         // sections with DIFFERENT denominators (far divides into the ranked pool, callers into the bodies
         // set), so a single gloss would have been wrong on one of them — each is named separately.
         // Kept DELIBERATELY terse, on kMaxTokensFitLegend's precedent: this rides in EVERY bundle at every
         // budget and is charged against the very ceiling it describes. Trap #8 fired TWICE on this one
         // addition while it was being written — a 538 B first draft pushed the 600-token fixture bundle onto
         // the over_ceiling rung, and a 266 B second draft pushed estchargecheck's A11 CONTROL (the bare
         // bundle at token-budget=800, which must stay conformant for that arm to mean anything) from 2072 B
         // to 2338 B against a 2171 B allowance. The headroom that existed was 99 B and this form is +85 B,
         // measured, not estimated. Every key is still named; the prose around them is what went.
         // deep-tail d1 (2026-08-29): r= joins the explicit dictionary — same trap-#8 terseness, one key
         // (the full deep-tail contract lives in the --for legend's own clause, docs/EVALS.md registration).
         "Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0)"
         ", l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee, r=rank in this ranking "
         "(sort by r= for true ranker order); far=ranked but over 1 hop out; "
         "of_top denominator is per-section. "
         // graphrag-recon.md idea #1 (2026-08-20, S-effort harvest pick): callers corroborated by SEVERAL
         // top-K anchors outrank one tied to a single anchor — a pure re-sort of the SAME d1 edges, no new
         // graph walk, no pooling. Kept to one clause, same trap-#8 discipline as the rest of this legend.
         "callers: sorted by shared desc (ties=site order); shared=# of top-K anchors reached, omitted at 1. "
         // M11: the root's machine-readable price, defined where the ledger prose below states the byte figures.
         "On the root: est_tokens= prices the delivered bundle in tokens (markup at the map rate, bodies at the body rate), "
         "budget_tokens= is the token target; over_ceiling= is 1 when the header floor alone exceeds it (the bundle is then complete, not trimmed). ";
    h.append( p.report );
    h.append( extraNotes );
    h += " -->";
    // R-E fix (2026-08-19): root= landed on this bundle's <ctx> with nothing defining it (legendcoverage
    // arm (A), "pack-task | ctx@root"). The shared clause, emitted exactly when the attribute is.
    h += rootRelPathsLegend( !p.rootArg.empty() );
    return h;
}

// A budgeted LIST section (callers / far / notes / tests share this shape): greedily keep the leading
// `entries` (already in rank/sort order) that fit under `budget` after a fixed wrapper reserve, then wrap them
// in <tag EXTRA shown="kept" total="entries.size()" capped="0|1">…</tag>. "" ⇒ 0 kept (the caller reports
// "omitted (budget)").
//
// §B8.3 — this used to spell the KEPT count `count=`, with no capped= bit at all. Under pageview.h THE
// TRUNCATION VOCABULARY, `count=` is one of the listed TOTAL spellings (rule 2) and `shown=` is the printed-row
// count (rule 1), so these four elements said "total" and meant "shown"; and rule 3's bit — the one a caller
// must never have to infer from a missing attribute — was absent on every one of them, while the JSON twin
// emitted <noun>_total/<noun>_kept for the same sections. Fixing the shared helper fixes <callers>, <far>,
// <notes> and <tests> in one place, which is why it is fixed here and not at four call sites.
inline PackTaskSection packTaskListSection( std::string_view tag, std::string_view extraAttr,
                                            const std::vector<std::string>& entries, std::size_t budget, std::size_t wrapReserve )
{
    PackTaskSection out;
    if( entries.empty() || budget <= wrapReserve )
    {
        return out;
    }
    std::size_t used = wrapReserve;
    for( const std::string& e : entries )
    {
        if( used + e.size() > budget )
        {
            break;
        }
        used += e.size();
        ++out.kept;
    }
    if( out.kept == 0 )
    {
        return out;
    }
    char open[ 160 ];
    std::snprintf( open, sizeof( open ), "<%.*s%.*s shown=\"%zu\" total=\"%zu\" capped=\"%d\">",
                   int( tag.size() ), tag.data(), int( extraAttr.size() ), extraAttr.data(), out.kept, entries.size(),
                   out.kept < entries.size() ? 1 : 0 );
    out.xml = open;
    for( std::size_t i = 0; i < out.kept; ++i )
    {
        out.xml += entries[i];
    }
    out.xml += "</";  out.xml.append( tag );  out.xml += ">";
    return out;
}

// §H5, the direction the finding did not name: the XML names each over-budget skip in a
// `<!-- body omitted (over budget): NAME -->` comment and the JSON dialect named none of them. Same set, same
// reason, spelled for a parser. The key is OMITTED (not `[]`) when nothing was skipped, matching the
// silence-means-nothing-happened convention route/mention/boost/over_ceiling already use in this dialect.
inline std::string packTaskOmittedBodiesJson( const IngestResult& ing, const rw::EmittedBodies& emitted )
{
    if( emitted.omitted.empty() )
    {
        return {};
    }
    std::string out = ",\"bodies_omitted\":[";
    for( std::size_t i = 0; i < emitted.omitted.size(); ++i )
    {
        if( i )
        {
            out += ",";
        }
        out += "\"" + jsonStr( ing.symbols[ emitted.omitted[i] ].name ) + "\"";
    }
    return out + "]";
}

// optional Q3/redaction/notes inputs the bundle folds in when the caller has them; every field defaults to
// "not available" and each is handled by a graceful degrade downstream (packSignatures' own
// nullptr-omits-the-attr contract), so a caller with NONE of these (a bare MCP call) still gets a complete,
// correctly-shaped bundle — matching how a plain CLI `--pack-task` run (without `--for`/`--metrics` also set)
// already leaves fanIn/impure/churn/tested/amp unset today.
struct PackTaskInputs
{
    std::size_t                        budgetTokens         = 0;       // 0 = kPackTaskDefaultTokens
    std::size_t                        sigLadderBudgetBytes = 0;       // per-doc-comment ladder budget for packSignatures (0 = unlimited; the CLI passes cfg.packBudgetBytes)
    bool                                compress             = false;   // --compress passthrough for packBodies
    const std::vector<std::uint32_t>*  fanIn  = nullptr;
    const std::vector<char>*           impure = nullptr;
    const std::vector<std::uint32_t>*  churn  = nullptr;   // per-FILE (git-mined; nullptr ⇒ omitted, no git pass required)
    const std::vector<std::uint8_t>*   tested = nullptr;   // per-symbol
    const std::vector<std::uint32_t>*  amp    = nullptr;   // per-symbol
    // R14 (§B10.1): the recorded residual W3-N1's "REQUIRED redact, no default" could not reach. Its TWIN is
    // `FromTraceInputs::redact` (tracelocus.h) — R14 named only this one, and the pair is now stated at both.
    // See tracelocus.h for why dropping the initialiser makes it WORSE (indeterminate, not required) and what
    // the real fix is (the CalleeCallsSink no-defaults-on-any-member shape).
    RedactCounts*                      redact = nullptr;
    const notes::NoteIndex*            notes  = nullptr;

    // §6 --partition: a PRE-COMPUTED Q3 clone-membership lens. findClones() is a pure function of `ing`, so a
    // fan-out that assembles N+1 bundles from the SAME index would otherwise pay for N+1 identical clone
    // passes. nullptr ⇒ this function computes its own (every existing caller, unchanged).
    const std::vector<std::uint8_t>*   cloneMember = nullptr;

    // §6 --partition: override the ranking WINDOW width (default kPackTaskRankTopN). A partitioned bundle's
    // rank vector is masked to its own slice, so a window wider than the slice would pull in zero-score
    // symbols the bundle was never about. 0 ⇒ kPackTaskRankTopN (every existing caller, unchanged).
    std::size_t                        rankTopN = 0;

    // §F1 (CA4 wave-1 verifier): bytes the CALLER will splice in before this bundle's own "</ctx>" — today
    // exactly one thing, the CLI's --with-graph mermaid block (main.cpp runPackTask). It was appended AFTER
    // this function had already divided the budget and priced the ceiling ladder, so a fixed ~399 B rode in
    // uncharged: MEASURED `--pack-task --token-budget=800 --with-graph` = 2 445 B against a 2 171 B allowance,
    // 12.6% over with NO over_ceiling label, while the bare form at the same budget was conformant. Charged
    // here, at the two places the budget is spent: the section shares trim to leave room for it, and the ladder
    // prices it, so the label fires when the trim cannot get there. 0 ⇒ every other caller, byte-identical.
    std::size_t                        trailingSectionBytes = 0;

    // R-E (2026-08-17 harvest): the single-root run's OWN root argument — same convention serialize()'s
    // rootArg takes (empty ⇒ multi-root, or a caller that never resolved one, e.g. an MCP call against a
    // workspace this struct's caller has not single-rooted). Threaded through every `<f p=…>`/`<test p=…>`
    // row this bundle renders (packSignatures/packBodies/the D1 caller rows/the far-tier name-only rows) so
    // CLI (runPackTask) and MCP (mcpverbs.h's packTaskText) cannot diverge — one assembler, one root.
    std::string_view                   rootArg;
};

// R2: the anchors' 1-hop neighbors, EITHER direction (g.inEdges = symbols that CALL an anchor; g.outOff/
// outTargets = symbols an anchor CALLS), anchors themselves excluded (`d0Mark`) and deduped — a neighbor
// reachable both ways keeps whichever direction is discovered first (caller before callee). `shared[i]` is
// the corroboration weight (graphrag-recon.md idea #1, adapted from nano-graphrag's relation_counts): how
// many of the anchor set's bodyIds this neighbor is 1-hop adjacent to — 1 when only one anchor reaches it.
struct D1Neighbors { std::vector<NodeId> ids;  std::vector<std::uint8_t> isCaller;  std::vector<std::uint32_t> shared; };

// the mutable state one direction's walk needs — bundled (not individual params) so collectNeighborsOf and
// computeD1Neighbors both stay comfortably under the params-regression bar.
struct D1WalkCtx
{
    const IngestResult*      ing;
    const Graph*             g;
    const std::vector<char>* d0Mark;
    std::vector<char>*       seenNeighbor;
    D1Neighbors*             out;
};

// `b`'s RAW (unfiltered — may include dupes/anchors) neighbor ids in ONE direction: true = g.inEdges (symbols
// that CALL `b`), false = g.outOff/outTargets (symbols `b` CALLS). Split out of collectNeighborsOf below so
// neither function's cognitive complexity crosses the ccx bar.
inline std::vector<NodeId> rawNeighborIdsOf( const D1WalkCtx& ctx, NodeId b, bool viaCallerEdges )
{
    std::vector<NodeId> ids;
    if( viaCallerEdges )
    {
        if( b >= ctx.ing->symbols.size() )
        {
            return ids;
        }
        const auto* ro = ctx.g->inEdges.rowOffsets();
        const auto* ci = ctx.g->inEdges.colIndices();
        ids.assign( ci + ro[b], ci + ro[b + 1] );
        return ids;
    }
    if( b + 1 >= ctx.g->outOff.size() )
    {
        return ids;
    }
    ids.assign( ctx.g->outTargets.begin() + ctx.g->outOff[b], ctx.g->outTargets.begin() + ctx.g->outOff[b + 1] );
    return ids;
}

// append `b`'s neighbors in ONE direction as d1 entries (tagged "caller"/"callee" per `viaCallerEdges`),
// skipping an id already an anchor or already collected. The ONE walk both directions share.
inline void collectNeighborsOf( D1WalkCtx& ctx, NodeId b, bool viaCallerEdges )
{
    for( NodeId c : rawNeighborIdsOf( ctx, b, viaCallerEdges ) )
    {
        if( c >= ctx.seenNeighbor->size() || ( *ctx.seenNeighbor )[c] || ( *ctx.d0Mark )[c] )
        {
            continue;
        }
        (*ctx.seenNeighbor)[c] = 1;  ctx.out->ids.push_back( c );  ctx.out->isCaller.push_back( viaCallerEdges ? 1 : 0 );
    }
}

// deterministic (file, line, name) display order — the same tie-break the pre-R2 callers-only list used.
inline D1Neighbors sortNeighborsBySite( const IngestResult& ing, D1Neighbors&& in )
{
    std::vector<std::uint32_t> perm( in.ids.size() );
    for( std::uint32_t i = 0; i < perm.size(); ++i )
    {
        perm[i] = i;
    }
    std::sort( perm.begin(), perm.end(), [ & ]( std::uint32_t a, std::uint32_t b )
    {
        const Symbol& sa = ing.symbols[ in.ids[a] ];  const Symbol& sb = ing.symbols[ in.ids[b] ];
        if( sa.fileId != sb.fileId )
        {
            return ing.files[sa.fileId] < ing.files[sb.fileId];
        }
        return sa.line != sb.line ? sa.line < sb.line : sa.name < sb.name;
    } );
    D1Neighbors out;
    out.ids.resize( in.ids.size() );  out.isCaller.resize( in.ids.size() );
    for( std::size_t i = 0; i < perm.size(); ++i ) { out.ids[i] = in.ids[ perm[i] ];  out.isCaller[i] = in.isCaller[ perm[i] ]; }
    return out;
}

// graphrag-recon.md idea #1 (adapted from nano-graphrag's `relation_counts`, _op.py:777-787): for each d1
// neighbor, how many of the anchor set's `bodyIds` is it 1-hop adjacent to (either direction, deduped per
// anchor so a mutual caller+callee pair with one anchor still counts once)? A pure count over the SAME CSR
// edges collectNeighborsOf already reads — no new graph walk, no pooling, no change to --for's own ranking.
// Indexed by NodeId (not d1 position) so the caller can look it up before OR after any reordering of d1.
inline std::vector<std::uint32_t> computeD1SharedCounts( const IngestResult& ing, const Graph& g,
                                                          const std::vector<NodeId>& bodyIds,
                                                          const std::vector<char>& d0Mark )
{
    std::vector<std::uint32_t> shared( ing.symbols.size(), 0 );
    std::vector<char>          touchedByThisAnchor( ing.symbols.size(), 0 );
    std::vector<NodeId>        touchedList;
    const D1WalkCtx ctx{ &ing, &g, nullptr, nullptr, nullptr };   // rawNeighborIdsOf only reads ing/g
    for( NodeId b : bodyIds )
    {
        touchedList.clear();
        for( bool viaCallerEdges : { true, false } )
        {
            for( NodeId n : rawNeighborIdsOf( ctx, b, viaCallerEdges ) )
            {
                if( n >= touchedByThisAnchor.size() || ( n < d0Mark.size() && d0Mark[n] ) || touchedByThisAnchor[n] )
                {
                    continue;
                }
                touchedByThisAnchor[n] = 1;  touchedList.push_back( n );  ++shared[n];
            }
        }
        for( NodeId n : touchedList )
        {
            touchedByThisAnchor[n] = 0;   // reset only what this anchor touched — no O(N) clear per anchor
        }
    }
    return shared;
}

// stable re-sort of an already d1-computed (and site-ordered) neighbor list by DESCENDING corroboration
// weight — a neighbor reached by several top-K anchors sorts ahead of one tied to a single anchor, before the
// caller-section's byte budget is applied. std::stable_sort keeps the incoming (site) order as the tie-break,
// matching the brief's "ties broken by the existing order" — the minimal, deterministic re-sort this is.
inline D1Neighbors sortNeighborsByCorroboration( D1Neighbors&& in, const std::vector<std::uint32_t>& sharedByNode )
{
    in.shared.resize( in.ids.size() );
    for( std::size_t i = 0; i < in.ids.size(); ++i )
    {
        in.shared[i] = in.ids[i] < sharedByNode.size() ? sharedByNode[ in.ids[i] ] : 0;
    }
    std::vector<std::uint32_t> perm( in.ids.size() );
    for( std::uint32_t i = 0; i < perm.size(); ++i )
    {
        perm[i] = i;
    }
    std::stable_sort( perm.begin(), perm.end(), [ & ]( std::uint32_t a, std::uint32_t b )
    {
        return in.shared[a] > in.shared[b];
    } );
    D1Neighbors out;
    out.ids.resize( perm.size() );  out.isCaller.resize( perm.size() );  out.shared.resize( perm.size() );
    for( std::size_t i = 0; i < perm.size(); ++i )
    {
        out.ids[i] = in.ids[ perm[i] ];  out.isCaller[i] = in.isCaller[ perm[i] ];  out.shared[i] = in.shared[ perm[i] ];
    }
    return out;
}

inline D1Neighbors computeD1Neighbors( const IngestResult& ing, const Graph& g,
                                       const std::vector<NodeId>& bodyIds, const std::vector<char>& d0Mark )
{
    D1Neighbors out;
    std::vector<char> seenNeighbor( ing.symbols.size(), 0 );
    D1WalkCtx ctx{ &ing, &g, &d0Mark, &seenNeighbor, &out };
    for( NodeId b : bodyIds )
    {
        collectNeighborsOf( ctx, b, /*viaCallerEdges=*/true );
    }
    for( NodeId b : bodyIds )
    {
        collectNeighborsOf( ctx, b, /*viaCallerEdges=*/false );
    }
    D1Neighbors sited = sortNeighborsBySite( ing, std::move( out ) );
    const std::vector<std::uint32_t> sharedByNode = computeD1SharedCounts( ing, g, bodyIds, d0Mark );
    return sortNeighborsByCorroboration( std::move( sited ), sharedByNode );
}

// R2: one d1 row — its OWN one-line signature (d1's detail tier — never a full body) + declaration site +
// which direction it was reached from. `rawSig` is the RAW (unescaped) text the L2 --json tail reuses
// verbatim — one extraction, two shapes, never re-derived.
struct D1Rows { std::vector<std::string> xml;  std::vector<std::string> rawSig; };
struct D1Row  { std::string xml;              std::string rawSig; };

// the two per-neighbor FACTS buildD1Row needs beyond the id itself — which direction it was reached from,
// and its corroboration weight (graphrag-recon.md idea #1) — bundled so the params count doesn't creep
// (same rationale as D1WalkCtx above: a params regression is cheaper to avoid than to explain away).
struct D1RowMeta { bool isCaller; std::uint32_t shared; };

// fetch (and cache) file `fileId`'s full source text — a small per-file cache so multiple d1 rows landing in
// the same file don't re-read it.
inline const std::string& d1ReadSrcCached( const IngestResult& ing, std::uint32_t fileId,
                                           HashMap<std::uint32_t, std::string>& cache )
{
    if( auto it = cache.find( fileId ); it != cache.end() )
    {
        return it->second;
    }
    std::string body;
    if( std::FILE* in = std::fopen( diskPath( ing, fileId ).c_str(), "rb" ) )
    {
        char buf[ 4096 ];  std::size_t n;
        while( ( n = std::fread( buf, 1, sizeof( buf ), in ) ) > 0 )
        {
            body.append( buf, n );
        }
        std::fclose( in );
    }
    return cache.emplace( fileId, std::move( body ) ).first->second;
}

// resolve `s`'s own one-line signature, lighter than a d0/eligible entry's (kForCapTailSigBytes, not the
// full ladder) — "" on any unreadable/invalid span (a graceful degrade: the row still gets its name+p+rel).
inline std::string resolveD1Signature( const IngestResult& ing, const Symbol& s,
                                       HashMap<std::uint32_t, std::string>& srcCache,
                                       RedactCounts* redact )   // §B0/W3-N1: REQUIRED — a d1 sig is emitted text
{
    if( s.fileId >= ing.files.size() )
    {
        return {};
    }
    const std::string& src = d1ReadSrcCached( ing, s.fileId, srcCache );
    const std::size_t  a = s.sigStartByte, b = s.sigEndByte;
    if( a >= src.size() || b > src.size() || a >= b )
    {
        return {};
    }
    std::string sig = cleanSig( src.data(), a, b, redact );
    truncateUtf8WithEllipsis( sig, kForCapTailSigBytes );
    return sig;
}

// R-E (2026-08-17 harvest): rootPrefix empty ⇒ p= keeps the ing.files[] spelling unchanged (multi-root, or
// no single root to strip) — same convention every other lens's pathRel uses. This is the SHARED CLI/MCP
// assembler (packTaskBundleText, called by both runPackTask and mcpverbs.h's packTaskText), so fixing it
// here fixes both dialects in one place — they cannot drift.
template<class EscFn>
inline D1Row buildD1Row( const IngestResult& ing, NodeId id, D1RowMeta meta,
                         HashMap<std::uint32_t, std::string>& srcCache, EscFn&& ex, RedactCounts* redact,
                         std::string_view rootPrefix = {} )
{
    const Symbol& s   = ing.symbols[id];
    std::string   sig = resolveD1Signature( ing, s, srcCache, redact );
    const std::string_view rp = rootPrefix.empty() ? std::string_view( ing.files[ s.fileId ] ) : rw::sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix );

    // §B14 — composed on std::string. `ex()` escapes BEFORE this point, so an snprintf into a fixed buffer
    // would truncate the ESCAPED form and emit an unterminated `<s …` row at exit 0 (measured on base: at a
    // 600-byte corpus path, 11 of 11 `<s>` rows unterminated across <callers> and <far>). serialize.h's
    // FIXED-BUFFER RULE states the escaper-side test.
    D1Row row;
    row.xml  = "<s t=\"";   row.xml += symTag( s.kind );
    row.xml += "\" n=\"";   row.xml += ex( s.name );
    row.xml += "\" p=\"";   row.xml += ex( rp );
    row.xml += ":";         row.xml += std::to_string( s.line );
    row.xml += "\" rel=\""; row.xml += meta.isCaller ? "caller" : "callee";
    row.xml += "\"";
    // graphrag-recon.md idea #1: corroboration weight, a count (like amp=/in=), never a judgment — see the
    // <callers> ordering-rule clause in packTaskHeaderText's legend for what it means and how ties break.
    // shared==1 is the uncorroborated default every d1 row already satisfies by construction (it is 1-hop
    // from AT LEAST one anchor) — emitted only when >1, so a bundle with a single anchor (no corroboration
    // possible) costs not one extra byte, matching the house "never a false 0"/economy-of-attributes rule.
    if( meta.shared > 1 )
    {
        row.xml += " shared=\""; row.xml += std::to_string( meta.shared ); row.xml += "\"";
    }
    if( sig.empty() )
    {
        row.xml += "/>";
    }
    else
    {
        row.xml += ">";
        row.xml += ex( sig );
        row.xml += "</s>";
    }
    row.rawSig = std::move( sig );
    return row;
}

template<class EscFn>
inline D1Rows renderD1CallerRows( const IngestResult& ing, const D1Neighbors& d1, EscFn&& ex, RedactCounts* redact,
                                  std::string_view rootPrefix = {} )
{
    D1Rows out;
    out.xml.reserve( d1.ids.size() );  out.rawSig.reserve( d1.ids.size() );
    HashMap<std::uint32_t, std::string> srcCache;
    for( std::size_t i = 0; i < d1.ids.size(); ++i )
    {
        D1Row row = buildD1Row( ing, d1.ids[i], D1RowMeta{ d1.isCaller[i] != 0, d1.shared[i] }, srcCache, ex, redact, rootPrefix );
        out.xml.emplace_back( std::move( row.xml ) );
        out.rawSig.emplace_back( std::move( row.rawSig ) );
    }
    return out;
}

// R2: a bare NAME-ONLY `<s .../>` row per id (no signature, no doc) — the d2plus tier.
template<class EscFn>
inline std::vector<std::string> renderNameOnlyRows( const IngestResult& ing, const std::vector<NodeId>& ids, EscFn&& ex,
                                                     std::string_view rootPrefix = {} )
{
    std::vector<std::string> rows;
    rows.reserve( ids.size() );
    for( NodeId id : ids )
    {
        const Symbol& s = ing.symbols[id];
        const std::string_view rp = rootPrefix.empty() ? std::string_view( ing.files[ s.fileId ] ) : rw::sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix );
        std::string   row = "<s t=\"";                                   // §B14 — std::string, not char[512]
        row += symTag( s.kind );
        row += "\" n=\"";   row += ex( s.name );
        row += "\" p=\"";   row += ex( rp );
        row += ":";         row += std::to_string( s.line );
        row += "\"/>";
        rows.emplace_back( std::move( row ) );
    }
    return rows;
}

// R2: which of `topRanked` keep full signature+doc detail (d0 ∪ d1 ⇒ eligible, section 1) vs which get
// demoted to a bare name row (d2plus, the <far> sub-block) — a pure partition, no rendering.
inline void partitionByEligibility( const std::vector<NodeId>& topRanked, const std::vector<char>& d0Mark,
                                    const std::vector<char>& d1Mark,
                                    std::vector<NodeId>& eligibleIds, std::vector<NodeId>& d2plusIds )
{
    for( NodeId id : topRanked )
    {
        ( ( id < d0Mark.size() && d0Mark[id] ) || ( id < d1Mark.size() && d1Mark[id] ) ? eligibleIds : d2plusIds ).push_back( id );
    }
}

// R2: everything outside `eligibleIds` is pinned to -1 (below any real, non-negative score) so
// packSignatures' own internal top-N selection naturally lands on exactly `eligibleIds`, in their original
// relative order — no pull-up of a lower-ranked, still-ineligible candidate to fill the gap.
inline std::vector<float> buildMaskedRank( const IngestResult& ing, const std::vector<float>& rank,
                                           const std::vector<NodeId>& eligibleIds )
{
    std::vector<float> masked( ing.symbols.size(), -1.0f );
    for( NodeId id : eligibleIds )
    {
        if( id < masked.size() )
        {
            masked[id] = rank[id];
        }
    }
    return masked;
}

// a generic "render into a memstream, DEGRADED_PATH_ALERT + \"\" on failure" wrapper — shared by every
// packTaskBundleText section (and renderRankingWithFar below) so none of them hand-roll the memstream dance.
template<class Emit>
inline std::string packTaskRenderToString( Emit&& emit )
{
    char* buf = nullptr;  std::size_t sz = 0;
    std::FILE* m = open_memstream( &buf, &sz );
    if( !m ) { DEGRADED_PATH_ALERT( "pack-task: open_memstream failed — section skipped from the budget" ); return {}; }
    emit( m );
    std::fflush( m );  std::fclose( m );
    std::string s;  if( buf ) { s.assign( buf, sz );  std::free( buf ); }
    return s;
}

// R2: section 1 as ONE cohesive unit — the distance-masked packSignatures call (eligibleIds only) PLUS the
// d2plus <far> splice just inside </sigs> (still section 1, never a 6th top-level section). Grouped into a
// small input struct (not individual params) so this stays comfortably under the params-regression bar.
struct RankingSectionInputs
{
    const std::vector<NodeId>*        eligibleIds;
    const std::vector<NodeId>*        d2plusIds;
    const std::vector<NodeId>*        topRanked;
    const std::vector<float>*         maskedRank;
    std::size_t                       sigsBudget;
    const PackTaskInputs*             in;
    const std::vector<std::uint8_t>*  forClone;
};
struct RankingSection
{
    std::string sigsStr;        // final, post-<far>-splice <sigs>…</sigs>
    bool        capped = false;
    std::size_t farTotal = 0, farKept = 0;
    std::string farXml;         // the raw <far>…</far> (or "" if omitted) — for the header's listStatus
    std::size_t droppedPositive = 0;   // A2 (survey card, 2026-09-03): rank>0 eligibleIds cut by the ladder's step F
};

template<class EscFn>
inline RankingSection renderRankingWithFar( const IngestResult& ing, const RankingSectionInputs& ri, EscFn&& ex )
{
    RankingSection out;
    out.sigsStr = ri.eligibleIds->empty() ? std::string( "<sigs></sigs>" ) : packTaskRenderToString( [ & ]( std::FILE* m )
    {
        packSignatures( m, ing, *ri.maskedRank, int( ri.eligibleIds->size() ), ri.in->sigLadderBudgetBytes, /*metrics=*/true,
                        ri.in->fanIn, ri.in->impure, ri.in->redact,
                        ri.in->churn, ri.forClone, ri.in->tested, ri.in->amp,
                        /*rankAdaptivePayload=*/true, /*payloadBudgetBytes=*/ri.sigsBudget,
                        /*noteIndex=*/nullptr,       // notes are a DEDICATED section (4), never inline here (avoids double-emit)
                        ri.in->rootArg,
                        /*hasRelevanceFloor=*/false, // R2: eligibleIds is ALREADY the curated set (d0∪d1 depth mask),
                                                     //   not a floor-narrowed topN — droppedPositiveCount re-checks
                                                     //   rank>0 per symbol regardless, so this is unaffected either way
                        &out.droppedPositive );      // A2: exact count, see droppedPositiveCount (serialize.h)
    } );
    // §P8 vocabulary: the ladder's marker is `<sigs shown="S" total="T" capped="1">` (src/pageview.h, THE
    // TRUNCATION VOCABULARY, rule 5) — it was payload="capped", and THIS was the string-match that made a
    // string enum load-bearing. Read off the OPENING TAG only, so a capped= on any nested child can never
    // be read as the ranking section's own verdict.
    {
        const std::size_t tagEnd = out.sigsStr.find( '>' );
        out.capped = tagEnd != std::string::npos && out.sigsStr.compare( 0, 6, "<sigs " ) == 0
                  && out.sigsStr.substr( 0, tagEnd ).find( " capped=\"1\"" ) != std::string::npos;
    }

    const std::vector<std::string> farRows = renderNameOnlyRows( ing, *ri.d2plusIds, ex, ri.in->rootArg );
    char farAttr[ 32 ];  std::snprintf( farAttr, sizeof( farAttr ), " of_top=\"%zu\"", ri.topRanked->size() );
    const std::size_t     sigsLeftover = ri.sigsBudget > out.sigsStr.size() ? ri.sigsBudget - out.sigsStr.size() : 0;
    const PackTaskSection far          = packTaskListSection( "far", farAttr, farRows, sigsLeftover, kPackTaskWrapReserve );
    out.farTotal = farRows.size();
    out.farKept  = far.kept;
    out.farXml   = far.xml;

    if( !far.xml.empty() && out.sigsStr.size() >= 7 && out.sigsStr.compare( out.sigsStr.size() - 7, 7, "</sigs>" ) == 0 )
    {
        out.sigsStr.insert( out.sigsStr.size() - 7, far.xml );
    }
    else if( !far.xml.empty() )
    {
        DEGRADED_PATH_ALERT( "pack-task: <sigs> did not end with the expected closing tag — <far> omitted" );
    }
    return out;
}

// ── W2-K: budget-cliff smoothing ────────────────────────────────────────────────────────────────────────
// E4's sweep found bodies_shown NON-monotonic in --token-budget (5 bodies at 4000, 2 at 4500, on ripwire-src,
// reproduced on both a pre- and post-harvest binary). The orchestrator's kill clause required a SHARED
// mechanism, not a corpus artifact, before funding a fix — measured here (RW_W2K_DEBUG instrumentation,
// discarded): at budgetTokens=3500..5000 on this exact task, ranking is "full" (never capped: <sigs> never
// truncates) and its unspent share (`carry`, rolled into bodies) is STRICTLY INCREASING the whole way
// (244 -> 669 -> 1093 -> 1518), so bodiesBudget itself is ALSO strictly increasing (2112 -> 2856 -> 3598 ->
// 4342) — the cross-section "ranking eats its own share" theory in exp-e4.md does not hold for this cliff.
// The real cause is the one packBodies' own §H5 comment already names and defends as NOT a defect: bodies
// fill top-rank-first via a STREAMING SKIP-AND-CONTINUE walk (admit a candidate if it fits the budget
// remaining so far, else skip and try the next), and that walk is providably not monotone in its own total
// budget — a bigger budget can newly admit ONE large, high-rank candidate that then starves several smaller,
// lower-rank ones the smaller budget had room for. Worked counter-example (rank order, fixed costs):
// costs=[10,3,3,3,3,3], budget=9 -> skip the 10, admit three 3's, count=3; budget=10 -> admit the 10 (just
// fits), remaining=0, count=1. Bigger budget, fewer bodies, with NOTHING about ranking involved.
// §H5's own conclusion — "rank priority is the retrieval contract, count is not a quality measure" — is still
// right for a SINGLE evaluation, and this fix does not relitigate it: the top-ranked candidate is still
// preferred whenever a choice exists. What changes is WHICH admission strategy earns that preference. A
// streaming walk is one strategy; it happens to not be monotone. Below is a DIFFERENT strategy — maximize the
// COUNT of candidates admitted within the budget, tie-broken toward the higher-ranked ones — that keeps the
// same "prefer top rank" spirit but IS monotone by construction: the set of budgets for which a given subset
// fits only grows as the budget grows, so the best COUNT achievable over that growing set cannot fall.
// Bounded by kPackTaskBodyCandidates (today 6), so brute-force 2^N subset enumeration is exact and cheap —
// no heuristic, no new tuned constant. Scoped entirely to --pack-task's OWN pre-selection of which of its
// already-ranked candidates to hand packBodies: packBodies' general per-call streaming contract — the one
// EVERY OTHER caller (--expand, MCP `exemplar`, --detail, --around) relies on — is untouched and
// byte-identical; only the LIST this one caller passes it changes.
struct MonotoneRoll { std::size_t charge = 0, carry = 0; };

// A section's unspent SHARE only rolls FORWARD to the next section when the section was not itself
// budget-constrained (kept every one of its — always budget-INDEPENDENT — candidates): only then is its
// actual consumed size a fixed constant as the budget grows, so `granted - consumed` is provably
// non-decreasing. When the section WAS constrained, its actual consumed bytes can wobble with the granted
// share's own coarse admission/trim granularity (the same class of effect the bodies fix above targets, just
// smaller stakes for the strict-prefix callers/notes/tests sections) — so a constrained section is charged
// its WHOLE granted share and donates NOTHING forward: conservative, never negative, never shrinking.
inline MonotoneRoll monotoneRoll( bool sectionCapped, std::size_t granted, std::size_t consumed )
{
    if( sectionCapped )
    {
        return { granted, 0 };
    }
    return { consumed, granted > consumed ? granted - consumed : 0 };
}

// ── §W2-K.2 (verifier FINDING K2, 2026-08-19): the ALLOCATION ORDER, and the reflow lap ─────────────────────
// At the default 6,000-token budget on ripwire's own tree the bundle lost 7 of its 20 caller signatures with
// ~44% of the budget unspent, and fill fell to 46.0% at 8,000. The mechanism is monotoneRoll's conservative
// half doing exactly what it says: a section that caps is charged its WHOLE granted share and donates nothing.
// That half cannot simply be relaxed — a capped section's consumed bytes move with its granted share, so
// donating `granted - consumed` hands the next section a SAWTOOTH budget, and a sawtooth budget is how the
// pre-wave binary produced its own 20 -> 13 caller cliff between 6000 and 8000.
//
// What CAN change is who stands where. The waste is not spread evenly across the five sections. Four of them
// admit a strict PREFIX of same-shaped, fine-grained rows (a signature, a caller line, a note, a test path —
// tens to low hundreds of bytes each), so they can leave at most one row's worth of their share unspent.
// <bodies> is the lumpy one: its items are whole function bodies differing by two orders of magnitude
// (measured on this repo for "rank the call graph": 129 … 7,833 bytes), so it is the section that routinely
// cannot spend thousands of bytes — and, sitting SECOND in the cascade, it was burying them in front of four
// sections that could have. Allocating it LAST is the fix: it still gets its own quota plus everything the
// fine-grained sections could not use, but the share IT cannot use is now stranded behind every other section
// instead of ahead of them, which costs exactly nothing. Emission order is untouched — the document still
// reads sigs, bodies, callers, notes, tests; this is the BUDGET order. Measured, same repo and task: callers
// at the default budget 13/20 -> 20/20, fill 52.5% -> 59.8%; at 8,000 tokens 43.5% -> 90.6%.
//
// Monotonicity survives BY CONSTRUCTION, not by measurement: every section's granted share is still
// `quotaOf(pct) + carry` and every carry is still a capped-section-donates-nothing carry, so each share stays
// a non-decreasing function of budgetTokens and each kept count is non-decreasing in its own share. Nothing
// about the RULE changed — only the order the five sections stand in.
//
// Ordering alone opens the mirror of the defect, which is what this helper closes. When the body candidates
// are cheap, <bodies> caps nothing, spends a fraction of the tail it was handed, and — with no section behind
// it — strands the rest while an earlier section may have capped for want of exactly that. So whatever
// `remaining` still holds after the last section is offered BACK, once, to the sections that capped, in the
// fixed order they were allocated in. `remaining` is a non-decreasing function of budgetTokens by the cascade
// argument above and each top-up is `granted + reflow`, so every count this lap can raise is raised
// monotonically too. There is no lap three: a second reflow would be a sawtooth of the first.
//
// This is one section's turn at that lap. A section STILL capped after its top-up passes nothing on — the
// first lap's conservative rule again, for the first lap's reason.
inline std::size_t reflowListSection( PackTaskSection& section, std::string_view tag, std::string_view extraAttr,
                                      const std::vector<std::string>& entries, std::size_t& budget,
                                      std::size_t wrapReserve, std::size_t reflow )
{
    if( reflow == 0 || section.kept >= entries.size() )
    {
        return reflow;
    }
    budget += reflow;
    section = packTaskListSection( tag, extraAttr, entries, budget, wrapReserve );
    return section.kept < entries.size() || budget <= section.xml.size() ? 0 : budget - section.xml.size();
}

// the exact bytes packBodies would emit for ONE node alone, minus the fixed <bodies ...></bodies> wrapper
// (`wrapperLen`, measured once by the caller) — i.e. this node's own share of `children`. Called under the
// caller's RedactTallyFreeze, so a probe never bills the redaction tally a second time (§B10.2's rule).
inline std::size_t probeBodyCost( const IngestResult& ing, const Graph& g, NodeId id, bool compress,
                                  RedactCounts* redact, std::size_t wrapperLen, std::string_view rootArg = {} )
{
    EmittedBodies     dummy;
    const std::string one = packTaskRenderToString( [ & ]( std::FILE* m )
    {
        packBodies( m, ing, { id }, SIZE_MAX, g.outOff, g.outTargets, compress, redact, nullptr, nullptr, &dummy,
                   /*truncateOversizedFirst=*/true, /*withFileContext=*/false, rootArg );
    } );
    return one.size() > wrapperLen ? one.size() - wrapperLen : 0;
}

// a mask's "keep the higher ranks" tie-break score: bit i (rank i, 0 = top) contributes a MORE significant
// bit the LOWER i is, so among equal-count masks the one preserving more of the front of the rank order
// always compares higher — a total order, so the tie-break is deterministic.
inline std::uint32_t bodyMaskRankScore( std::uint32_t mask, std::size_t n )
{
    std::uint32_t score = 0;
    for( std::size_t i = 0; i < n; ++i )
    {
        if( mask & ( 1u << i ) )
        {
            score |= ( 1u << ( n - 1 - i ) );
        }
    }
    return score;
}

// packBodies only ever sees the pre-selected subset (selectMonotoneBodySubset, below), so its own <bodies
// shown=/total=/capped=> wrapper and its per-item "<!-- body omitted (over budget) -->" markers describe
// THAT smaller request, not the true candidate set (bodyIds) — total= undercounts and capped="0" is a lie
// whenever the pre-selection itself dropped a candidate packBodies never even saw. Restated here from the
// TRUE candidate list against `emitted.kept` (what actually got shown, not the intended selection — robust
// to any probe/render mismatch), so §H5's per-item disclosure ("the XML names each over-budget skip in a
// comment; the JSON lists bodies_omitted") still holds for candidates OUR pre-selection dropped, not only
// ones packBodies itself would have dropped. A no-op (bodiesXml returned unchanged) when every candidate
// was shown — the common case once the budget clears the whole set.
template<class EscFn>
inline std::string restatePackTaskBodiesWrapper( const IngestResult& ing, const std::string& bodiesXml,
                                                  const std::vector<NodeId>& bodyIds, EmittedBodies& emitted, EscFn&& ex,
                                                  bool compress = false )
{
    if( bodiesXml.empty() || emitted.kept.size() >= bodyIds.size() )
    {
        return bodiesXml;
    }
    std::vector<char> keptMark( ing.symbols.size(), 0 );
    for( const EmittedBody& b : emitted.kept )
    {
        if( b.id < keptMark.size() )
        {
            keptMark[b.id] = 1;
        }
    }
    std::string markers;
    for( NodeId id : bodyIds )
    {
        if( id < keptMark.size() && !keptMark[id] )
        {
            markers += "<!-- body omitted (over budget): ";
            markers += ex( xmlCommentText( ing.symbols[id].name ) );
            markers += " -->";
            emitted.omitted.push_back( id );
        }
    }
    const std::size_t openEnd = bodiesXml.find( '>' );
    const bool         closesRight = bodiesXml.size() >= 9 && bodiesXml.compare( bodiesXml.size() - 9, 9, "</bodies>" ) == 0;
    if( openEnd == std::string::npos || !closesRight )
    {
        DEGRADED_PATH_ALERT( "pack-task: <bodies> did not have the expected open/close shape — restated omissions dropped" );
        return bodiesXml;
    }
    // compress="1" restated with shown=/total=: this wrapper REPLACES packBodies' own open tag, so the
    // per-bundle compression disclosure (serialize.h packBodies) must survive the rewrite or the restated
    // bundle would silently claim uncompressed bodies (test/forcompresscheck.sh arm 5).
    char open[ 112 ];
    std::snprintf( open, sizeof( open ), "<bodies shown=\"%zu\" total=\"%zu\" capped=\"1\"%s>", emitted.kept.size(), bodyIds.size(),
                   compress ? " compress=\"1\"" : "" );
    std::string out = open;
    out += bodiesXml.substr( openEnd + 1, bodiesXml.size() - 9 - ( openEnd + 1 ) );
    out += markers;
    out += "</bodies>";
    return out;
}

// THE FIX: the admissible subset of `bodyIds` (rank order, already <= kPackTaskBodyCandidates) that
// maximizes COUNT within `bodiesBudget`, tie-broken toward keeping the higher-ranked members and then toward
// the smaller total cost (more carry left for callers). See the section comment above for why this — not
// packBodies' own streaming admission — is what makes bodies_shown monotone in budgetTokens.
//
// §W2-K.2 (verifier FINDING K1, 2026-08-19) — COUNT-monotone is not the same as RELEVANCE-monotone, and the
// first shipped shape traded the second away without noticing. On this gate's OWN fixture, raising the budget
// 900 -> 1200 DELETED the body of the function the task literally names (`cliffProbeTargetFunction`, cost 3225)
// and substituted two one-line helpers (cost 129 each) that scored a higher COUNT — and it stayed deleted
// through 4000. "Bigger budget, worse answer" is exactly the defect W2-K set out to remove; a pure max-count
// objective just moved it from the counter, where packtaskmonotoncheck can see it, to the content, where it
// could not.
//
// The corrected objective: **the top-ranked candidate is ADMITTED, not entered into the count contest.** Its
// cost is reserved off the top and the remaining pool maximizes count over the rest (same tie-breaks). When it
// does not fit WHOLE it is still the only thing rendered, and packBodies' truncate-the-first-oversized-one
// floor shows as much of it as the pool holds — a partial view of the symbol the task named beats two complete
// one-liners it did not.
//
// That floor is also what keeps the count monotone, and this is the whole subtlety of the fix. A constraint
// alone ("admit rank 0 whenever ANY admissible subset contains it, else maximize count freely") is NOT monotone
// in count: just below cost[0] the free maximum can be 5 cheap bodies, and the first pool that can afford
// rank 0 drops to 1 + (whatever the leftover buys). Measured on this fixture: 5 at budget 3500 -> 4 at 4000,
// which reds this gate. Forcing rank 0 in at EVERY pool removes the discontinuity instead of stepping over it:
//   pool <  cost[0]  ->  shown = 1            (rank 0 alone, truncated to fit)
//   pool >= cost[0]  ->  shown = 1 + maxCount( rest, pool - cost[0] ),  non-decreasing in pool
//   at the crossing  ->  1 -> 1 + k, k >= 0
// so bodies_shown is still non-decreasing in budgetTokens BY CONSTRUCTION, not by measurement. The price is
// paid at the small-budget end (a truncated top body instead of several complete lesser ones), which is the
// side of the trade the retrieval contract wants to be on.
inline std::vector<NodeId> selectMonotoneBodySubset( const IngestResult& ing, const Graph& g,
                                                      const std::vector<NodeId>& bodyIds, std::size_t bodiesBudget,
                                                      bool compress, RedactCounts* redact, std::string_view rootArg = {} )
{
    if( bodyIds.empty() )
    {
        return {};
    }
    const std::size_t        n = bodyIds.size();   // kPackTaskBodyCandidates today — small by construction
    std::vector<std::size_t> cost( n, 0 );
    std::size_t               wrapperLen = 0;
    {
        const RedactTallyFreeze freeze( redact );   // every probe below is off the books
        EmittedBodies            dummy;
        wrapperLen = packTaskRenderToString( [ & ]( std::FILE* m )
        {
            packBodies( m, ing, {}, SIZE_MAX, g.outOff, g.outTargets, compress, redact, nullptr, nullptr, &dummy );
        } ).size();
        for( std::size_t i = 0; i < n; ++i )
        {
            cost[i] = probeBodyCost( ing, g, bodyIds[i], compress, redact, wrapperLen, rootArg );
        }
    }
    // reserve the measured wrapper cost PLUS kPackTaskWrapReserve's existing generous margin (digit-width
    // slop, escaping slop) — the same named constant packTaskListSection already reserves for its own
    // shown=/total=/capped= wrapper, reused here rather than inventing a new one.
    const std::size_t pool = bodiesBudget > wrapperLen + kPackTaskWrapReserve ? bodiesBudget - wrapperLen - kPackTaskWrapReserve : 0;

    // §W2-K.2: rank 0 does not fit whole — it is STILL the one thing rendered, truncated by packBodies' own
    // oversized-first floor. Returning the max-count subset of the OTHERS here is what deleted the task-named
    // body (FINDING K1) and is also what makes the count non-monotone at this exact boundary.
    if( cost[0] > pool )
    {
        return { bodyIds[0] };
    }

    std::uint32_t bestMask = 0, bestScore = 0;
    std::size_t   bestCount = 0, bestCost = SIZE_MAX;
    for( std::uint32_t mask = 1u; mask < ( 1u << n ); mask += 2u )   // §W2-K.2: bit 0 set — rank 0 is admitted, not contested
    {
        std::size_t count = 0, total = 0;
        for( std::size_t i = 0; i < n; ++i )
        {
            if( mask & ( 1u << i ) )
            {
                ++count;
                total += cost[i];
            }
        }
        if( total > pool )
        {
            continue;
        }
        const std::uint32_t score  = bodyMaskRankScore( mask, n );
        const bool           better = count > bestCount
                                    || ( count == bestCount && score > bestScore )
                                    || ( count == bestCount && score == bestScore && total < bestCost );
        if( better )
        {
            bestMask = mask;  bestScore = score;  bestCount = count;  bestCost = total;
        }
    }

    std::vector<NodeId> chosen;
    chosen.reserve( bestCount );
    for( std::size_t i = 0; i < n; ++i )
    {
        if( bestMask & ( 1u << i ) )
        {
            chosen.push_back( bodyIds[i] );
        }
    }
    return chosen;
}

// THE bundle assembler: builds the fixed 5-section budget-shared bundle (ranking > bodies > callers > notes >
// tests) for `task`, given an already-computed LensRanking, and returns the whole <ctx>…</ctx> XML document
// as a string — never touches stdout (the caller owns the sink: the CLI fwrites it, MCP wraps it as a
// JSON-RPC text result). The Q3 clone-membership lens (`forClone`) is computed HERE, once, from `ing` alone
// (findClones needs no git) — both callers get identical clone data with zero duplicated logic.
// `surfaceOut`, when given, receives the ids this bundle actually NAMES — its ranking window (incl. the
// name-only <far> tier) ∪ its full-body anchors ∪ their 1-hop callers/callees (which is also where the inline
// <c> callee signatures come from). §6 --partition measures cross-bundle overlap from it, so the number it
// reports is derived from the same selection the XML was rendered from rather than a re-derivation. It is the
// PRE-budget-trim surface (a trimmed tail names slightly fewer) — an honest ceiling, documented as one.
inline std::string packTaskBundleText( const IngestResult& ing, const Graph& g, const std::string& task,
                                       const LensRanking& lr, const PackTaskInputs& inArg,
                                       std::string* jsonOut = nullptr, std::vector<NodeId>* surfaceOut = nullptr )
{
    // P2.4 — reuse-count self-supply. --pack-task's CLI/MCP call-sites only compute fan-in when --for or
    // --metrics was ALSO given, so the bundle used to print in="0" on every row while --for reported the real
    // count for the same symbol in the same run. The in-edge CSR is already built and sitting in `g`, so the
    // honest value costs one O(symbols) pass over rowOffsets — no second graph pass, no git, no ingest.
    // `localFanIn` is declared BEFORE `in` so it outlives the pointer `in` holds into it.
    std::vector<std::uint32_t> localFanIn;
    PackTaskInputs             in = inArg;
    if( !in.fanIn ) { localFanIn = fanInFromInEdges( ing, g );  in.fanIn = &localFanIn; }

    const std::vector<float>& rank     = lr.rank;
    const int                 rankTopN = in.rankTopN > 0 ? int( in.rankTopN ) : kPackTaskRankTopN;

    // top ranked ids (score desc, id asc). Body candidates = the top heads with a POSITIVE score.
    std::vector<NodeId> order( ing.symbols.size() );
    for( NodeId i = 0; i < order.size(); ++i )
    {
        order[i] = i;
    }
    sortutil::radixSortByScoreDescId( order, rank );
    std::vector<NodeId> bodyIds;
    for( std::size_t k = 0; k < order.size() && bodyIds.size() < kPackTaskBodyCandidates; ++k )
    {
        if( rank[order[k]] <= 0.0f )
        {
            break;
        }
        bodyIds.push_back( order[k] );
    }

    // ── R2: distance-aware detail allocation ────────────────────────────────────────────────────────────────
    // The bundle's detail LEVEL is a function of graph distance from the anchor set (bodyIds, d0), not a flat
    // per-section cut: d0 (the anchors themselves) already get the maximal tier — a full body (section 2,
    // above/below, unchanged). d1 (any symbol one call-graph hop from an anchor, caller OR callee) gets
    // signature-level detail. Everything else considered by the ranking pool but NOT within 1 hop of any
    // anchor (d2+) is demoted to a bare name-only row — still surfaced (no silent loss), just cheaper.
    std::vector<char> d0Mark( ing.symbols.size(), 0 );
    for( NodeId b : bodyIds )
    {
        if( b < d0Mark.size() )
        {
            d0Mark[b] = 1;
        }
    }

    const D1Neighbors  d1 = computeD1Neighbors( ing, g, bodyIds, d0Mark );
    std::vector<char> d1Mark( ing.symbols.size(), 0 );
    for( NodeId n : d1.ids )
    {
        if( n < d1Mark.size() )
        {
            d1Mark[n] = 1;
        }
    }

    // the ranking pool: the same top-rankTopN window --for would show for this task (unmasked). Partition it
    // into ELIGIBLE (d0 ∪ d1 — keeps full signature+doc detail in section 1) and d2plus (demoted to a bare
    // name row in the <far> sub-block, section 1 §below).
    const std::size_t       topRankedN = std::min<std::size_t>( std::size_t( rankTopN ), order.size() );
    const std::vector<NodeId> topRanked( order.begin(), order.begin() + topRankedN );
    std::vector<NodeId> eligibleIds, d2plusIds;
    partitionByEligibility( topRanked, d0Mark, d1Mark, eligibleIds, d2plusIds );

    // Q3 clone-membership lens — a pure function of `ing`, computed once here for both callers (or handed in
    // already computed by a fan-out that assembles several bundles from one index; see in.cloneMember).
    std::vector<std::uint8_t> ownClone;
    if( !in.cloneMember )
    {
        ownClone.assign( ing.symbols.size(), 0u );
        for( const CloneGroup& cg : findClones( ing, 40 ) )
        {
            for( NodeId m : cg.members )
            {
                if( m < ownClone.size() )
                {
                    ownClone[m] = 1u;
                }
            }
        }
    }
    const std::vector<std::uint8_t>& forClone = in.cloneMember ? *in.cloneMember : ownClone;

    // ── the header's USER-LENGTH text, hoisted above the budget so the budget can CHARGE it ─────────────────
    //    W3FIX M3: the '--' collapse each echo site hand-rolled scrubbed dashes and nothing else — a C0 byte or
    //    invalid UTF-8 in the task made xmllint reject the document, and a '\n' wrote a raw newline outside
    //    CDATA. xmlCommentText (serialize.h) is the ONE scrub for all three, byte-identical on clean input.
    const std::string taskNote       = xmlCommentText( task );
    // L1 (density audit 2026-08-08): no scrubbed routeNote here any more — the comment used to echo the
    // route= attribute's text verbatim-but-scrubbed (~230-260 duplicated B per routed call). route= is the
    // one copy (test/routeoncecheck.sh pins it).
    const std::string mentionNote    = xmlCommentText( lr.mentionNote );
    const std::string boostNote      = xmlCommentText( lr.boostNote );
    const std::string docMentionNote = xmlCommentText( lr.docMentionNote );

    // ── the deterministic byte budget (default 6K tokens; in.budgetTokens overrides) ────────────────────────
    const std::size_t budgetTokens = in.budgetTokens > 0 ? in.budgetTokens : std::size_t( kPackTaskDefaultTokens );
    const std::size_t bundleBudget = rw::budgetBytesForTokens( budgetTokens );
    // §B1.7 fixup + W3FIX M1: the header's user-length text is bytes kPackTaskHeaderReserve (a fixed 1024)
    // cannot bound. The fixup charged the verbatim task=/route= ATTRIBUTES and left the SIBLING one line away —
    // the comment's echo of the same text — free, so the ceiling still blew out ~3.4x on a long task. Charge
    // every user-length part EXACTLY (measured, not estimated); the reserve now covers only what it says it
    // covers, the fixed legend + report + "</ctx>". rootOpenStr is emitted verbatim at the assembly below.
    const std::string rootOpenStr = ctxRootOpen( task, lr.routeNote, in.rootArg );
    // §F1: in.trailingSectionBytes is the caller's spliced-in tail (see PackTaskInputs) — a FIXED cost with no
    // trim knob of its own, so it belongs in the floor the section shares are divided under, exactly like the
    // header's own user-length parts. 0 for every caller that splices nothing.
    const std::size_t headerFloor = kPackTaskHeaderReserve + rootOpenStr.size() + taskNote.size()
                                  + mentionNote.size() + boostNote.size() + docMentionNote.size()
                                  + in.trailingSectionBytes;
    std::size_t       remaining   = bundleBudget > headerFloor ? bundleBudget - headerFloor : 1;

    // F1 — the kPackTaskQuota*Pct shares above, applied to `quotaBase` (see their own comment for why). `carry`
    // (threaded through sections 1-4 below) is an under-filled section's unspent quota, rolled FORWARD.
    const std::size_t quotaBase = remaining;
    const auto quotaOf = [ & ]( int pct ) -> std::size_t { return std::max<std::size_t>( 1, std::min( remaining, quotaBase * std::size_t( pct ) / 100 ) ); };
    const auto sectionBudget = [ & ]( int pct, std::size_t carryIn ) -> std::size_t { return std::min( remaining, quotaOf( pct ) + carryIn ); };

    const auto countSub = []( const std::string& hay, std::string_view needle ) -> std::size_t
    {
        std::size_t n = 0, p = 0;
        while( ( p = hay.find( needle, p ) ) != std::string::npos ) { ++n;  p += needle.size(); }
        return n;
    };
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    // ── section 1 — routed+anchored ranking, now DISTANCE-MASKED (R2): only d0∪d1 members of the topRanked
    //    window keep full signature+doc detail; d2plus is a bare name-only <far> sub-block spliced just
    //    inside </sigs> (still section 1, never a 6th top-level section) — see renderRankingWithFar above.
    const std::vector<float>  maskedRank = buildMaskedRank( ing, rank, eligibleIds );
    const std::size_t         sigsBudget = sectionBudget( kPackTaskQuotaRankingPct, /*carryIn=*/0 );
    const RankingSectionInputs rankIn{ &eligibleIds, &d2plusIds, &topRanked, &maskedRank, sigsBudget, &in, &forClone };
    RankingSection             rankOut   = renderRankingWithFar( ing, rankIn, ex );

    std::string        sigsStr    = rankOut.sigsStr;
    bool                sigsCapped = rankOut.capped;
    std::size_t         farTotal   = rankOut.farTotal;
    std::size_t         farKept    = rankOut.farKept;
    // §W2-K: monotoneRoll (see its own comment) — eligibleIds never depends on budgetTokens, so when ranking
    // is NOT capped its consumed bytes are a fixed constant and its unspent share safely rolls forward; when
    // capped, the whole granted share is charged and nothing rolls forward.
    const MonotoneRoll sigsRoll = monotoneRoll( sigsCapped, sigsBudget, sigsStr.size() );
    remaining = remaining > sigsRoll.charge ? remaining - sigsRoll.charge : 0;
    std::size_t carry = sigsRoll.carry;

    // ── section 2 — full bodies of the top-K ranked symbols. DECLARED here (its `total` is the denominator of
    //    <callers of_top=> below and the emit order is fixed: sigs, bodies, callers, notes, tests) but ALLOCATED
    //    and RENDERED LAST — see "§W2-K.2 (K2): the allocation order" where it happens, for why.
    std::string        bodiesStr;
    rw::EmittedBodies emittedBodies;
    const std::size_t  bodiesTotal = bodyIds.size();
    std::size_t        bodiesKept  = 0;

    // ── section 3 — d1: the anchors' 1-hop callers+callees (computed above), each shown with its OWN one-line
    //    SIGNATURE (R2: d1's detail tier) + its declaration site — never a full body (that stays d0-only).
    const D1Rows d1Rendered = renderD1CallerRows( ing, d1, ex, in.redact, in.rootArg );
    const std::vector<std::string>& callerRows = d1Rendered.xml;
    const std::vector<std::string>& d1SigRaw   = d1Rendered.rawSig;   // unescaped — the L2 --json tail reuses these verbatim
    char callersAttr[ 32 ];  std::snprintf( callersAttr, sizeof( callersAttr ), " of_top=\"%zu\"", bodiesTotal );
    std::size_t       callersBudget = sectionBudget( kPackTaskQuotaCallersPct, carry );
    PackTaskSection   callers       = packTaskListSection( "callers", callersAttr, callerRows, callersBudget, kPackTaskWrapReserveWide );
    const std::size_t callersTotal  = callerRows.size();
    // §W2-K: callerRows is fixed by the graph (d1), not by budgetTokens — same monotoneRoll treatment.
    const MonotoneRoll callersRoll = monotoneRoll( callers.kept < callersTotal, callersBudget, callers.xml.size() );
    carry     = callersRoll.carry;   // rolls into notes next
    remaining = remaining > callersRoll.charge ? remaining - callersRoll.charge : 0;

    // ── section 4 — field notes on the top-K symbols + their files (L3; inert when in.notes is null) ────────
    std::vector<std::string> noteEntries;
    // L2 --json: raw (target, [(date,text)...]) capture alongside the XML rendering — ONE computation path,
    // two shapes; only populated when the caller asked for the JSON tail below.
    std::vector<std::pair<std::string, std::vector<std::pair<std::string, std::string>>>> noteEntriesData;
    if( in.notes )
    {
        HashMap<std::string, std::uint8_t> seenTarget;
        seenTarget.reserve( bodyIds.size() * 2 );
        const auto emitTarget = [ & ]( const std::string& target )
        {
            if( target.empty() || seenTarget.find( target ) != seenTarget.end() )
            {
                return;
            }
            seenTarget[ target ] = 1;
            const std::vector<std::uint32_t>* idxs = in.notes->find( target );
            if( !idxs || idxs->empty() )
            {
                return;
            }
            std::string entry = "<target id=\"" + ex( target ) + "\">";
            for( std::uint32_t ni : *idxs )
            {
                const notes::Note& n = in.notes->notes[ ni ];
                std::string safe;
                safe.reserve( n.text.size() );
                appendCdataSafe( n.text, safe );
                entry += "<note d=\"" + ex( n.date ) + "\"><![CDATA[" + safe + "]]></note>";
            }
            entry += "</target>";
            noteEntries.push_back( std::move( entry ) );
            if( jsonOut )
            {
                std::vector<std::pair<std::string, std::string>> raw;
                for( std::uint32_t ni : *idxs )
                {
                    raw.emplace_back( in.notes->notes[ni].date, in.notes->notes[ni].text );
                }
                noteEntriesData.emplace_back( target, std::move( raw ) );
            }
        };
        for( NodeId b : bodyIds )
        {
            const Symbol& s = ing.symbols[b];
            if( s.fileId < ing.files.size() )
            {
                emitTarget( canonicalId( relForHash( ing.files[s.fileId], in.notes->root ), s.scope, s.name ) ); // D5: root-relative note key
            }
        }
        for( NodeId b : bodyIds )
        {
            const Symbol& s = ing.symbols[b];
            if( s.fileId < ing.files.size() )
            {
                emitTarget( std::string( relForHash( ing.files[s.fileId], in.notes->root ) ) ); // D5: root-relative note key
            }
        }
    }
    std::size_t       notesBudget = sectionBudget( kPackTaskQuotaNotesPct, carry );
    PackTaskSection   notes       = packTaskListSection( "notes", "", noteEntries, notesBudget, kPackTaskWrapReserve );
    const std::size_t notesTotal  = noteEntries.size();
    // §W2-K: noteEntries is fixed by bodyIds+in.notes, not by budgetTokens — same monotoneRoll treatment.
    const MonotoneRoll notesRoll = monotoneRoll( notes.kept < notesTotal, notesBudget, notes.xml.size() );
    carry     = notesRoll.carry;   // rolls into tests next
    remaining = remaining > notesRoll.charge ? remaining - notesRoll.charge : 0;

    // ── section 5 — tests_to_run for the top files (the --affected mining: tests that transitively reach) ───
    std::vector<std::string>   testRows;
    std::vector<std::uint32_t> testFiles;   // hoisted for the L2 --json tail below
    {
        std::vector<NodeId> testSeeds;
        for( NodeId b : bodyIds )
        {
            if( b < ing.symbols.size() && !rw::isTestPath( ing.files[ing.symbols[b].fileId] ) )
            {
                testSeeds.push_back( b );
            }
        }
        if( testSeeds.empty() )
        {
            testSeeds = bodyIds;
        }
        const std::vector<NodeId>  reach = transitiveCallers( g, testSeeds );
        std::vector<char>          fseen( ing.files.size(), 0 );
        for( NodeId n : reach )
        {
            const std::uint32_t f = ing.symbols[n].fileId;
            if( f < fseen.size() && !fseen[f] && rw::isTestPath( ing.files[f] ) ) { fseen[f] = 1;  testFiles.push_back( f ); }
        }
        std::sort( testFiles.begin(), testFiles.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );
        // §A9.5 / §P11.4: the one-call bundle names the tests you owe; it now also names how to RUN them,
        // from the same TestRunnerIndex --affected / --situ / --test-gate / --exercises read. Built here,
        // inside the section's scope, because it is lazy — a bundle with no test row reads no runner script.
        const rw::TestRunnerIndex runners( ing );
        for( std::uint32_t f : testFiles )
        {
            // §B14 — std::string, not char[512]. This row carried TWO unbounded interpolands (the test path
            // AND the runner command), so it was the widest of the six breaching sites.
            const std::string_view rp = in.rootArg.empty() ? std::string_view( ing.files[f] ) : rw::sarif::rootRelativeUri( ing.files[f], rw::sarif::rootPrefixOf( in.rootArg ) );
            std::string row = "<test p=\"";
            row += ex( rp );
            row += "\"";
            row += rw::runAttr( runners, f, ex );
            row += "/>";
            testRows.emplace_back( std::move( row ) );
        }
    }
    std::size_t       testsBudget = sectionBudget( kPackTaskQuotaTestsPct, carry );
    PackTaskSection   tests       = packTaskListSection( "tests", "", testRows, testsBudget, kPackTaskWrapReserve );
    const std::size_t testsTotal  = testRows.size();
    const MonotoneRoll testsRoll  = monotoneRoll( tests.kept < testsTotal, testsBudget, tests.xml.size() );
    carry     = testsRoll.carry;
    remaining = remaining > testsRoll.charge ? remaining - testsRoll.charge : 0;

    // ── §W2-K.2 (K2): section 2 is EMITTED second and ALLOCATED last — reflowListSection above carries the
    //    finding, the measurement and the monotonicity argument for why. ──────────────────────────────────────
    const std::size_t bodiesBudget = sectionBudget( kPackTaskQuotaBodiesPct, carry );
    if( !bodyIds.empty() && bodiesBudget >= kPackTaskSectionFloor )
    {
        // §W2-K: pre-select the admissible subset (selectMonotoneBodySubset, above) instead of handing
        // packBodies the full candidate list — this is what makes bodies_shown monotone. The selection is
        // never empty for a non-empty candidate list (§W2-K.2: rank 0 is always in it, truncated by
        // packBodies' oversized-first floor when the pool cannot hold it whole), so there is no fall-back to
        // the full list here — that would hand the decision back to packBodies' own streaming walk over
        // MULTIPLE candidates, reintroducing the exact non-monotonicity this fix removes (measured: it did,
        // on memgraph, at the 900/1200/1600 floor).
        // §H5: `emittedBodies` is packBodies' own report of what it emitted. It is the ONE answer to "which
        // bodies?" — the XML is those bytes, the JSON tail below re-serializes the same record, and bodiesKept
        // counts it.
        const std::vector<NodeId> renderIds = selectMonotoneBodySubset( ing, g, bodyIds, bodiesBudget, in.compress, in.redact, in.rootArg );
        bodiesStr  = packTaskRenderToString( [ & ]( std::FILE* m )
        {
            packBodies( m, ing, renderIds, bodiesBudget, g.outOff, g.outTargets, in.compress, in.redact,
                        /*ranges=*/nullptr, /*noteIndex=*/nullptr, &emittedBodies, /*truncateOversizedFirst=*/true,
                        /*withFileContext=*/false, in.rootArg );
        } );
        bodiesKept = emittedBodies.kept.size();
        // §W2-K: restate total=/capped= and splice in omission markers for whatever OUR pre-selection
        // dropped that packBodies itself never saw — see restatePackTaskBodiesWrapper's own comment.
        bodiesStr  = restatePackTaskBodiesWrapper( ing, bodiesStr, bodyIds, emittedBodies, ex, in.compress );
    }
    else
    {
        // R9 fix (W3-S, 2026-08-19): bodiesStr used to stay empty here — no candidates at all, or a
        // budget too tight even for the section wrapper — so the WHOLE <bodies> element was absent
        // from the bundle; only <ctx bundle="auto" bodies="0" ...> (--for's twin of this branch) spoke
        // to it, and pack-task's <ctx> carries no such attribute at all. "A zero means none found,
        // never none exists" (CONTRIBUTING #3) applies to elements, not only counts.
        //
        // Deliberately NOT a packBodies() call: an earlier version of this fix routed through
        // packBodies with truncateOversizedFirst=false so it could reuse the per-item "body omitted
        // (over budget)" comment packBodies already writes — but that comment is UNBUDGETED (it does
        // not check its own bytes against anything), so up to kPackTaskBodyCandidates (6) of them
        // could add several hundred bytes nothing in monotoneRoll's carry-forward accounted for,
        // which is exactly how packtaskcheck.sh's own ceiling arm caught it (--token-budget=2000 came
        // back 5692 B against a 5428 B allowance). The bare wrapper tag is a FIXED, small cost — the
        // same shape restatePackTaskBodiesWrapper hand-formats a few lines below for the same reason
        // (it cannot call packBodies again either) — so it is safe to emit unconditionally here.
        char tag[ 112 ];
        std::snprintf( tag, sizeof( tag ), "<bodies shown=\"0\" total=\"%zu\" capped=\"%d\"%s></bodies>",
                       bodyIds.size(), bodyIds.empty() ? 0 : 1, in.compress ? " compress=\"1\"" : "" );
        bodiesStr = tag;
        // bodiesKept stays 0 (its declared default) — matches shown="0" exactly.
    }
    // §W2-K: bodyIds (the candidate SET) never depends on budgetTokens either, so the same monotoneRoll
    // treatment applies at this handoff too.
    const MonotoneRoll bodiesRoll = monotoneRoll( bodiesKept < bodiesTotal, bodiesBudget, bodiesStr.size() );
    remaining = remaining > bodiesRoll.charge ? remaining - bodiesRoll.charge : 0;

    // ── §W2-K.2 (K2): the reflow lap — see reflowListSection above for the finding and the argument ──────────
    std::size_t reflow = remaining;
    if( reflow > 0 && sigsCapped )
    {
        RankingSectionInputs rankIn2 = rankIn;
        rankIn2.sigsBudget           = sigsBudget + reflow;
        rankOut                       = renderRankingWithFar( ing, rankIn2, ex );
        sigsStr = rankOut.sigsStr;  sigsCapped = rankOut.capped;  farTotal = rankOut.farTotal;  farKept = rankOut.farKept;
        reflow  = sigsCapped || rankIn2.sigsBudget <= sigsStr.size() ? 0 : rankIn2.sigsBudget - sigsStr.size();
    }
    reflow = reflowListSection( callers, "callers", callersAttr, callerRows, callersBudget, kPackTaskWrapReserveWide, reflow );
    reflow = reflowListSection( notes,   "notes",   "",          noteEntries, notesBudget,   kPackTaskWrapReserve,     reflow );
    reflow = reflowListSection( tests,   "tests",   "",          testRows,    testsBudget,   kPackTaskWrapReserve,     reflow );

    const std::string& callersStr = callers.xml;
    const std::size_t  callersKept = callers.kept;
    const std::string& notesStr   = notes.xml;
    const std::size_t  notesKept  = notes.kept;
    const std::string& testsStr   = tests.xml;
    const std::size_t  testsKept  = tests.kept;

    // ── L2 --json tail: the SAME section decisions (kept/capped counts computed above), re-shaped as JSON.
    //    One computation path, two serializations — the JSON reports the identical truncation the XML header
    //    reports. Emitters that already exist for other verbs (packSignaturesJson/packBodiesJson) render into
    //    a memstream because they take a FILE*; this function's contract stays "never touches stdout". ────────
    //
    // §B10.2: this whole block is a SECOND rendering of text the XML sections above already redacted and
    // already tallied, so it must not re-bill the counter — see redact.h RedactTallyFreeze for the finding and
    // for why "pass nullptr" is the wrong fix. (packBodiesJson no longer redacts at all: §H5 gave it
    // packBodies' already-redacted text. The freeze covers packSignaturesJson and the d1 signature reuse.)
    if( jsonOut )
    {
        const RedactTallyFreeze tallyFreeze( in.redact );
        std::string&            j = *jsonOut;
        // R-E (2026-08-17 harvest): the JSON dialect's pathRel — same rootArg every XML row above already used.
        const std::string       jRootPrefix = in.rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( in.rootArg );
        const auto               jPathRel   = [ & ]( std::uint32_t fileId ) -> std::string_view
        {
            return in.rootArg.empty() ? std::string_view( ing.files[ fileId ] ) : rw::sarif::rootRelativeUri( ing.files[ fileId ], jRootPrefix );
        };
        j = "{\"task\":\"" + jsonStr( task ) + "\"";
        if( !lr.routeNote.empty() )
        {
            j += ",\"route\":\"" + jsonStr( lr.routeNote ) + "\"";
        }
        // The scrub disclosure travels WITH the two fields it describes: `task` and `route` are XML-scrubbed
        // copies (xmlSafeByte maps C0 except \t\n\r to a space, invalid UTF-8 to '?'), and a consumer holding
        // only the JSON is owed that fact from the JSON. ctxRootJsonScrubKeys is ctxRootOpen's twin — same two
        // strings, same single predicate — so a call site cannot emit the field without the disclosure. Absent
        // on clean input, so no ordinary document moves a byte. This closes the residual bodydialectcheck's
        // arm (H) pinned as a SET; that arm is built to go RED when this lands, naming the pin to delete.
        j += ctxRootJsonScrubKeys( task, lr.routeNote );
        if( !lr.mentionNote.empty() )
        {
            j += ",\"mention\":\"" + jsonStr( lr.mentionNote ) + "\"";
        }
        if( !lr.boostNote.empty() )
        {
            j += ",\"boost\":\"" + jsonStr( lr.boostNote ) + "\"";
        }
        if( !lr.docMentionNote.empty() )
        {
            j += ",\"doc_mention\":\"" + jsonStr( lr.docMentionNote ) + "\"";
        }
        // R-E follow-up (2026-08-19): the JSON dialect's OWN root disclosure. Every `p` in this tail was
        // already root-relative (the XML twin's root= is suppressed for --json), so a consumer holding only
        // the JSON had relative paths and nothing saying what they were relative to — the mirror of the
        // "root= with no legend" gap the round closed on the XML side. Same value, same single-root-only
        // condition, spelled as this dialect spells things. Absent on a multi-root run, exactly as root= is.
        if( !in.rootArg.empty() )
        {
            j += ",\"root\":\"" + jsonStr( in.rootArg ) + "\"";
        }
        // §B1.6: all THREE budget facts the XML header states ("budget=N bytes (T-token target, ceiling C)").
        // budget_ceiling_bytes was the one number with no JSON key — the hard byte ceiling the token target
        // implies, which is what a consumer checks the bundle against; budget_bytes is the WORKING budget
        // after the headroom factor, and is always the smaller of the two. Same expression as the XML line
        // below, so the two serializations cannot report different ceilings.
        { char b[ 128 ];  std::snprintf( b, sizeof( b ), ",\"budget_tokens\":%zu,\"budget_bytes\":%zu,\"budget_ceiling_bytes\":%zu",
                                         budgetTokens, bundleBudget, std::size_t( double( budgetTokens ) * rw::kMinBytesPerToken ) );  j += b; }

        // R2: the SAME distance mask the XML <sigs> used (eligibleIds only) — one eligibility decision, two shapes.
        j += std::string( ",\"ranking_capped\":" ) + ( sigsCapped ? "true" : "false" ) + ",\"ranking\":";
        j += eligibleIds.empty() ? "[]" : packTaskRenderToString( [ & ]( std::FILE* m )
        {
            packSignaturesJson( m, ing, maskedRank, int( eligibleIds.size() ),
                                JsonSigLens{ /*metrics=*/true, in.fanIn, in.impure, in.churn, &forClone,
                                             in.tested, in.amp, /*rankAdaptivePayload=*/true },
                                in.redact,   // §B0: the same redaction the XML <sigs> above already applied
                                /*budgetBytes=*/0, /*payloadBudgetBytes=*/0, /*outCapped=*/nullptr, /*outNotes=*/nullptr,
                                in.rootArg );
        } );

        // R2: d2plus — the topRanked members NOT within 1 hop of an anchor, name-only (mirrors XML's <far>).
        const std::size_t farShown = std::min( farKept, d2plusIds.size() );
        { char b[ 128 ];  std::snprintf( b, sizeof( b ), ",\"far_total\":%zu,\"far_kept\":%zu,\"far_of_top\":%zu,\"far\":[",
                                         farTotal, farShown, topRanked.size() );  j += b; }
        for( std::size_t i = 0; i < farShown; ++i )
        {
            const Symbol& s = ing.symbols[ d2plusIds[i] ];
            j += ( i == 0 ? "" : "," );
            j += "{\"t\":\"" + std::string( symTag( s.kind ) ) + "\",\"n\":\"" + jsonStr( s.name )
               + "\",\"p\":\"" + jsonStr( std::string( jPathRel( s.fileId ) ) ) + ":" + std::to_string( s.line ) + "\"}";
        }
        j += "]";

        // §H5 — the bodies the XML section ACTUALLY emitted, re-serialized. This used to re-slice the first
        // `bodies_kept` ids in RANK order, but packBodies emits grouped by FILE and stops on a BYTE budget, so
        // the two dialects reported different SETS under one bodies_kept — and packBodiesJson emitted each body
        // WHOLE, against no budget at all (MEASURED: XML 8 100 B vs JSON 42 200 B under a stated 11 800 B
        // ceiling). Both halves are gone by construction: there is one selection, and this is its record.
        { char b[ 96 ];  std::snprintf( b, sizeof( b ), ",\"bodies_total\":%zu,\"bodies_kept\":%zu,\"bodies\":",
                                        bodiesTotal, emittedBodies.kept.size() );  j += b; }
        j += packTaskRenderToString( [ & ]( std::FILE* m ) { packBodiesJson( m, ing, emittedBodies, in.rootArg ); } );
        j += packTaskOmittedBodiesJson( ing, emittedBodies );   // §H5 — see its header

        const std::size_t callersShown = std::min( callersKept, d1.ids.size() );
        { char b[ 128 ];  std::snprintf( b, sizeof( b ), ",\"callers_total\":%zu,\"callers_kept\":%zu,\"callers_of_top\":%zu,\"callers\":[",
                                         callersTotal, callersShown, bodiesTotal );  j += b; }
        for( std::size_t i = 0; i < callersShown; ++i )
        {
            const Symbol& s = ing.symbols[ d1.ids[i] ];
            j += ( i == 0 ? "" : "," );
            j += "{\"t\":\"" + std::string( symTag( s.kind ) ) + "\",\"n\":\"" + jsonStr( s.name )
               + "\",\"p\":\"" + jsonStr( std::string( jPathRel( s.fileId ) ) ) + ":" + std::to_string( s.line )
               + "\",\"rel\":\"" + ( d1.isCaller[i] ? "caller" : "callee" ) + "\""
               // JSON twin of buildD1Row's XML shared= attribute — same economy rule (omitted at the
               // uncorroborated default of 1), composed from the SAME primitive overloadsAttr uses
               // (countFieldIfAbove, serialize.h) rather than re-deriving an equivalent ternary.
               + countFieldIfAbove( d1.shared[i], 1, ",\"shared\":" );
            if( !d1SigRaw[i].empty() )
            {
                j += ",\"sig\":\"" + jsonStr( d1SigRaw[i] ) + "\"";
            }
            j += "}";
        }
        j += "]";

        const std::size_t notesShown = std::min( notesKept, noteEntriesData.size() );
        { char b[ 96 ];  std::snprintf( b, sizeof( b ), ",\"notes_total\":%zu,\"notes_kept\":%zu,\"notes\":[", notesTotal, notesShown );  j += b; }
        for( std::size_t i = 0; i < notesShown; ++i )
        {
            j += ( i == 0 ? "" : "," );
            j += "{\"target\":\"" + jsonStr( noteEntriesData[i].first ) + "\",\"notes\":[";
            const auto& raw = noteEntriesData[i].second;
            for( std::size_t k = 0; k < raw.size(); ++k )
            {
                j += std::string( k == 0 ? "" : "," ) + "{\"d\":\"" + jsonStr( raw[k].first ) + "\",\"text\":\"" + jsonStr( raw[k].second ) + "\"}";
            }
            j += "]}";
        }
        j += "]";

        const std::size_t testsShown = std::min( testsKept, testFiles.size() );
        { char b[ 96 ];  std::snprintf( b, sizeof( b ), ",\"tests_total\":%zu,\"tests_kept\":%zu,\"tests_to_run\":[", testsTotal, testsShown );  j += b; }
        // §A9.5: the JSON sibling of the XML run= above — situ's tests_to_run already carries it, and one
        // computation path must not serialize two different obligations.
        const rw::TestRunnerIndex jsonRunners( ing );
        const auto                 jrun = [ & ]( std::string_view s ) { return jsonStr( s ); };
        for( std::size_t i = 0; i < testsShown; ++i )
        {
            j += std::string( i == 0 ? "" : "," ) + "{\"p\":\"" + jsonStr( std::string( jPathRel( testFiles[i] ) ) ) + "\""
               + rw::runFieldJson( jsonRunners, testFiles[i], jrun ) + "}";
        }
        j += "]";

        // W3FIX M1 — the JSON sibling of the XML header's over_ceiling sentence. §B1.6 gave this dialect
        // budget_ceiling_bytes so a consumer could CHECK the bundle itself; that check silently fails on a long
        // task, because the envelope's own task echo is part of what it must measure. Absent ⇒ within the
        // ceiling (the silence-means-nothing-happened convention route/mention/boost use above), never "not
        // measured". Measured on the FINISHED document, so the key's own bytes are part of what it reports on.
        constexpr std::size_t kOverCeilingKeyBytes = 22;   // `,"over_ceiling":true` + the closing brace
        if( j.size() + kOverCeilingKeyBytes > rw::ceilingAllowanceBytes( budgetTokens ) )
        {
            j += ",\"over_ceiling\":true";
        }
        j += "}";
    }

    const auto listStatus = []( std::size_t total, const std::string& body, std::size_t kept ) -> std::string
    {
        char b[ 64 ];
        if( total == 0 )       { return "none"; }
        if( body.empty() )     { return "omitted (budget)"; }
        std::snprintf( b, sizeof( b ), kept < total ? "kept %zu of %zu" : "%zu of %zu", kept, total );
        return b;
    };
    std::string report = "budget=";
    { char b[ 160 ];  std::snprintf( b, sizeof( b ), "%zu bytes (%zu-token target, ceiling %zu) | ",
                                    bundleBudget, budgetTokens, std::size_t( double( budgetTokens ) * rw::kMinBytesPerToken ) );  report += b; }
    report += std::string( "ranking: " ) + ( sigsCapped ? "capped" : "full" ) + " | ";
    report += "bodies: "  + listStatus( bodiesTotal,  bodiesStr,  bodiesKept )  + ( bodiesTotal > 0 && !bodiesStr.empty() && bodiesKept < bodiesTotal ? " (capped)" : "" ) + " | ";
    report += "callers: " + listStatus( callersTotal, callersStr, callersKept ) + " | ";
    report += "notes: "   + listStatus( notesTotal,   notesStr,   notesKept )   + " | ";
    report += "tests: "   + listStatus( testsTotal,   testsStr,   testsKept );
    report += " | far: "  + listStatus( farTotal,      rankOut.farXml, farKept );   // R2: d2plus name-only tier (nested in <sigs>)
    // A2 (survey card, 2026-09-03) — the pack-task twin of --for's dropped_positive= root fact: how many
    // rank>0 eligibleIds the section-1 ladder cut. Emitted ONLY when nonzero (the pr_converged precedent,
    // src/prconverge.h) — the report string's own bytes are already absorbed by kPackTaskHeaderReserve's
    // generous fixed allowance (see its own comment), so this costs no separate budget accounting, and the
    // no-drop path (rankOut.droppedPositive == 0) is byte-identical to the pre-A2 report exactly as before.
    if( rankOut.droppedPositive > 0 )
    {
        char b[ 96 ];  std::snprintf( b, sizeof( b ), " | dropped_positive=\"%zu\"", rankOut.droppedPositive );
        report += b;
    }

    const PackTaskHeaderParts headerParts{ task, rootOpenStr, taskNote, mentionNote, boostNote,
                                            docMentionNote, report, in.rootArg };
    const auto buildHeader = [ & ]( bool withRouteAttr, bool withTaskEcho, std::string_view extraNotes )
    { return packTaskHeaderText( headerParts, withRouteAttr, withTaskEcho, extraNotes ); };
    const std::string headerStr = buildHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );

    std::string whole;
    whole.reserve( headerStr.size() + sigsStr.size() + bodiesStr.size() + callersStr.size() + notesStr.size() + testsStr.size() + 8 );
    whole += headerStr;
    whole += sigsStr;
    whole += bodiesStr;
    whole += callersStr;
    whole += notesStr;
    whole += testsStr;
    whole += "</ctx>";

    // §B1.7 fixup (bundleidcheck), rewritten by W3FIX M1 — the ceiling ladder (rungs + rationale: serialize.h
    // climbCeilingLadder / ceilingAllowanceBytes). The fixup dropped the verbatim route= attribute
    // UNCONDITIONALLY and printed "route_attr: dropped (ceiling)" whether or not the drop achieved anything —
    // a sentence that reads as a remedy, on a document still 1.9x over. It dropped the wrong bytes first (the
    // task text is in the document TWICE, so the comment echo is a pure DUPLICATE while route= is the only copy
    // of the routing reason in the machine surface), and it claimed a remedy it never measured. Both fixed by
    // the shared ladder; the bar is the stated ceiling PLUS the single-entry overshoot the design allows, so a
    // lens never "remedies" an overshoot its own contract permits.
    {
        static constexpr CeilingLadderNotes kNotes{
            " | task_echo: dropped (ceiling)", " | task_echo + route_attr: dropped (ceiling)",
            " | over_ceiling: the header floor (verbatim task echo + fixed legend) exceeds this budget"
            " - no section left to trim" };
        // §F1: + in.trailingSectionBytes — the ladder prices the document the CALLER will emit, which includes
        // the tail it splices in before "</ctx>". Pricing `whole` alone is what let --with-graph land 12.6% past
        // the allowance wearing no label.
        // M11: the PRICED ROOT — est_tokens= (markup at the map rate, bodies at the body rate, the caller's
        // trailing section included exactly as the ladder prices it), budget_tokens= (the target, the same
        // unit), over_ceiling="1" when the ladder's last rung fired. The ledger prose keeps its byte figures;
        // this is the machine-readable twin a parser that drops comments still gets. The attributes are
        // PRICED INTO THE LADDER: their widest possible spelling (the pre-ladder estimate's digits — the
        // ladder only shrinks the header — plus the two optional attributes) rides in the measured bytes, so
        // a bundle the ladder calls conformant is conformant WITH its root attributes on (packtaskcheck's
        // ceiling arm caught the 4-byte overshoot of the first, unpriced version).
        const auto rootAttrsFor = [ & ]( const std::string& doc, bool overCeiling ) -> std::string
        {
            const std::size_t markupBytes = doc.size() + in.trailingSectionBytes - std::min( bodiesStr.size(), doc.size() );
            std::string       attrs       = rw::pricedRootAttr( markupBytes, rw::kBytesPerTokenDefault, bodiesStr.size(), nullptr );
            attrs += " budget_tokens=\"" + std::to_string( budgetTokens ) + "\"";
            if( overCeiling ) { attrs += " over_ceiling=\"1\""; }
            return attrs;
        };
        const std::size_t rootAttrsBound = rootAttrsFor( whole, /*overCeiling=*/true ).size();
        const std::string chosen = climbCeilingLadder( buildHeader, headerStr,
                                                       whole.size() - headerStr.size() + in.trailingSectionBytes + rootAttrsBound,
                                                       rw::ceilingAllowanceBytes( budgetTokens ),
                                                       /*hasRouteAttr=*/!lr.routeNote.empty(), kNotes );
        if( chosen != headerStr )
        {
            whole.replace( 0, headerStr.size(), chosen );
        }
        // the ladder's LAST rung is the only text that spells the marker with a colon (kNotes above); the
        // legend's own definition of over_ceiling= must never read as the label (bundleidcheck trap #15)
        rw::spliceRootAttrs( whole, rootAttrsFor( whole, chosen.find( "over_ceiling:" ) != std::string::npos ) );
    }

    // §6 --partition: the bundle's own surface (see the contract above). topRanked already contains bodyIds
    // (bodies are the positive-score head of the SAME order), so the union is topRanked ∪ d2plus ∪ d1.
    if( surfaceOut )
    {
        surfaceOut->clear();
        surfaceOut->reserve( topRanked.size() + d2plusIds.size() + d1.ids.size() + bodyIds.size() );
        surfaceOut->insert( surfaceOut->end(), topRanked.begin(),  topRanked.end() );
        surfaceOut->insert( surfaceOut->end(), d2plusIds.begin(),  d2plusIds.end() );
        surfaceOut->insert( surfaceOut->end(), bodyIds.begin(),    bodyIds.end() );
        surfaceOut->insert( surfaceOut->end(), d1.ids.begin(),     d1.ids.end() );
        std::sort( surfaceOut->begin(), surfaceOut->end() );
        surfaceOut->erase( std::unique( surfaceOut->begin(), surfaceOut->end() ), surfaceOut->end() );
    }
    return whole;
}

}   // namespace rw
