#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings
#include "infra/sortutil.h"   // sortUnique
#include <string_view>       // %.*s (precision, pointer) collapses to one view


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
#include "compactlegend.h"   // L1 fix round: compactDeliveredBytes — the ceiling ladder at the delivered price
#include "serialize.h"     // packSignatures / packBodies / escapeXml / kMinBytesPerToken / kBudgetHeadroom
#include "redact.h"
#include "notes.h"
#include "filter.h"        // isTestPath
#include "clones.h"        // findClones — the Q3 clone-membership lens (pure `ing` function, no git — safe for both callers)
#include "resolve.h"       // canonicalId — note-target keying
#include "arch.h"          // relForHash — note-target keying
#include "testmap.h"       // §A9.5 / §P11.4: TestRunnerIndex / runAttr — the run= hint on a named test row
#include "forpage.h"       // PB1: computeFileTail / renderFileTailXml — --for's file tail, the same rows
#include "nextverb.h"      // PB1: nextFlag / nextAttrXml — a dropped candidate's next=--expand
#include "mention.h"       // PB1: taskNamesIndexedFile — the head round robin's verdict, as --for takes it
#include "situ.h"          // <partners>: mergeSeedPartners — --situ's own merge of co-change partners across seeds

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <limits>       // std::numeric_limits — the mask-width static_assert: an index shifted into a mask must fit it
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
    std::string        sibliftNote;                // r4 EXPERIMENT (siblift.h) — "" unless RIPWIRE_SIBLIFT
                                                    // actually promoted a symbol.
    std::string        expandNote;                 // r6 EXPERIMENT (expand.h) — "" unless RIPWIRE_EXPAND
                                                    // actually promoted a symbol.
    std::string        docMentionNote;             // R5: doc<->code mention-edge surfacing (see mention.h
                                                    // applyDocMentionBoost) — "" unless a resolved symbol's
                                                    // g.mentions docs actually got lifted.
    std::uint32_t      docMentionCount = 0;        // §L10b: docMentionInfo.docCount, the machine form of the
                                                    // note above (0 = the boost moved nothing) — the doc_mentions=
                                                    // root attribute reads this, mirroring anchorLifts below.
    // The INDEXING caps that cut this ranking, accumulated across the three lift passes in the order they
    // run (mention.h CapDisclosure). Both "" on the overwhelmingly common run where no cap bit, so a bundle
    // that lost nothing pays nothing. The prose half already rides mentionNote/boostNote/docMentionNote,
    // which is how --pack-task and both JSON dialects get the same fact for free.
    std::string        capAttrs;                   // ` mention_syms_capped="1" …` — spliced onto the XML root
    std::string        capJson;                    // `,"mention_syms_capped":true,…` — the --json twin
    std::string        capNote;                    // the self-defining prose clause (mention.h capDisclosureNote).
                                                    // Deliberately NOT folded into the three notes above: on --for
                                                    // it is spliced in AFTER the sigs ladder has run, so a
                                                    // disclosure is paid for in bytes and never in ranked rows.
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
    // SUBJECT-ANCHOR (subjectanchor.h): the definitions of each symbol a conceptual route's descriptive subject names, subject order
    std::vector<std::vector<NodeId>> subjectCallerCandidates;
    // CONFIDENCE-ANCHOR (subjectanchor.h): a name-exact route whose anchor no source-class definition backs
    bool anchorNoSource = false;
    // FRAME-HIGH-CONFIDENCE (subjectanchor.h routeAnchorHeadsRows): the name-exact route's anchor, as a ranked head row can match it
    RouteAnchorKeys anchorKeys;
    // L-W (forpage.h): the term evidence behind the RAW lexical pass — which query subtokens each symbol
    // matched and how rare each is — read back out of the scorer (lexical.h LexTermEvidence) so coverage=
    // and the --for --limit=N file page are computed from the same integers that ranked the head.
    LexTermEvidence             evidence;
};

inline constexpr int         kPackTaskDefaultTokens  = 6000;   // the default budget when no explicit budget is given
inline constexpr int         kPackTaskRankTopN       = 12;     // a --partition slice's ranking window (partition.h; lanes.h brief claims)
inline constexpr int         kPackTaskHeadRows       = kForLensDefaultTopN;   // PB1: the ranking = --for's 40-row head (PT1 design D1)
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
// PB1 (PT1 design D1): the split moved to the locating surface. The head is --for's 40 rows (PT1 measured that block at a
// median 4,594 B on SUB1's tasks), one key body replaced six, the callers are that body's only, and the file tail — new —
// takes its own share plus everything the sections before it leave (it is filled LAST, to the ceiling).
inline constexpr int kPackTaskQuotaRankingPct = 45;
inline constexpr int kPackTaskQuotaBodiesPct  = 20;
inline constexpr int kPackTaskQuotaCallersPct = 8;
inline constexpr int kPackTaskQuotaNotesPct   = 2;
inline constexpr int kPackTaskQuotaTestsPct   = 5;
inline constexpr int kPackTaskQuotaTailPct    = 20;   // the tail never CAPS at this share: it absorbs every carry and leftover
static_assert( kPackTaskQuotaRankingPct + kPackTaskQuotaBodiesPct + kPackTaskQuotaCallersPct
             + kPackTaskQuotaNotesPct + kPackTaskQuotaTestsPct + kPackTaskQuotaTailPct == 100, "pack-task section quotas must sum to 100%" );
// The head's row drop (step F) aims here, not at its share: rows past the share are kept (shrunk to pointer rows by the ladder)
// until this bound, so the 40 rows survive a long-signature corpus while the key body keeps its share.
inline constexpr int kPackTaskHeadRowDropPct  = 60;
static_assert( kPackTaskHeadRowDropPct >= kPackTaskQuotaRankingPct
               && kPackTaskHeadRowDropPct + kPackTaskQuotaBodiesPct + kPackTaskQuotaTailPct <= 100,
               "the head's row-drop bound must sit at or above its share and leave the key body AND THE TAIL theirs" );
// THE TAIL'S SHARE IS A FLOOR, RESERVED BEFORE ANY SECTION SPENDS — and this is the defect that made it one.
// PT1's design sentence was "the tail takes its own share plus everything the sections before it leave", and the
// first build implemented only the second half: the tail was the leftover, with no floor, while the head was
// allowed up to kPackTaskHeadRowDropPct (60%) of the post-header budget instead of its own 45% share, and
// monotoneRoll charges a cut section its whole granted share. On a corpus with a long task echo and long
// signatures the leftover was nothing. MEASURED on LocBench's 303 tasks (results/PB1_PACKTASK_1119 §5a): the
// tail declared a 20% share and received 0.6% — a median `shown="0"` of `total="512"` files — and on 82 of the
// 84 tasks D1 failed to complete, the gold file it needed was in that cut tail. Completion is counted in FILES
// and the tail is the section that names files, so starving it is not a tuning shortfall, it is a bug.
// The reserve is withheld from the spendable pool up front and handed back to the tail at the end, so the tail
// still absorbs every leftover as well. A --partition slice reserves nothing: it carries no tail.
// Gate: test/packtailsharecheck.sh.

// E1 / review of #214: one entry, one unit again. The <tests> section is CUT over single rows — one row per
// test file, whose rendered bytes are exactly what the cut measures — and only the KEPT prefix is grouped
// afterwards (see the tests section below), so shown=/total= count rows and test files at the same time and
// the per-entry `units` arithmetic this struct carried for one release is gone with the estimate that needed it.
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
    std::string_view sibliftNote, expandNote;   // r4/r6 EXPERIMENTS — present only when the env-gated lift actually promoted something
    std::string_view report;           // the per-section truncation ledger
    // M1 (terminality round A, 2026-09-05): root attributes this bundle owes, spliced onto BOTH root
    // spellings below (the pre-built one and the ladder's route-dropped rebuild). Today that is exactly
    // dropped_positive= — see its comment at the emission site for why it moved out of `report`.
    std::string_view rootExtraAttrs;
    std::string_view rootArg;          // R-E (2026-08-17): the single-root run's own root= — the ladder's
                                        // route-dropped rebuild below calls ctxRootOpen a second time and
                                        // must carry the SAME root as the pre-built rootOpenStr did.
    std::string_view runClause;        // M21(b)/E1: testmap.h's run=/run_unknown=/<g> clause — ROWS-GATED (empty when
                                        // the tests section kept no row), so a bundle that omits tests pays nothing
    bool             softBudget = false;   // forbudget-soft: the caller's own budget — a soft target (kPackTaskSoftBudgetSentence)
    std::string_view pathFromNote;     // PATH-FROM-UPSTREAM's clause (forgraphverb.h), its OWN data comment after the legend: the compact
                                        // dialect strips the legend comment, and rows it moved must stay disclosed there (S9, rv-py-mod2)
};

// P10 (L7): the bundle legend's BODY, one constant, spliced by the standalone header (packTaskHeaderText) and
// stated ONCE by the partitioned document's outer legend (partition.h) — inner bundles carry no legend of their
// own (--pack-task --partition=3 used to print it 4x: 9,646 B of a 34,164 B answer, lens 8 table 1).
inline constexpr const char* kPackTaskBundleLegendBody =
    // PB1 (PT1 design D1, 2026-11-19): the sections and their split, the --for head and file tail this bundle now carries, the one
    // key body and its pointer rows, and ONE conversion between budget_tokens= and est_tokens=.
    // TERSE ON PURPOSE, and re-tightened once (compactlegendcheck (U) measured the compact form 216 B over its 990 B target).
    // Trap #8 is the reason: this rides in EVERY bundle at EVERY budget and is charged against the very ceiling it describes, so
    // prose costs the reader bytes it could have spent on rows. Nothing was CUT to get under the bar — every attribute the answer
    // can emit still has its reading here, which is what legendcoveragecheck pins; what went was the wording around them.
    ": one-call orientation under ONE budget — sections in FIXED order ranking > key body > callers > notes > tests > tail, "
         "quotas per section are FIXED (rank45/body20/caller8/note2/test5/tail20, pct of budget), unspent quota ROLLS FORWARD; the tail's share is a "
         "FLOOR and it is filled LAST with every leftover. Every truncation is reported (no silent caps): per section shown=rows kept, "
         "total=rows that qualified, capped=1 when the BUDGET cut the difference. "
         "ranking: the for head for this task (its 40 rows, its order). "
         "bodies: ONE body served by design — the task's backticked symbol, else the top-ranked bodied one. <b>=it, and shown=/total= "
         "count SERVED bodies only; <bn t= n= p= l= next=>=a candidate not served, next= its expand call — by design, not a cut, so "
         "capped=1 only if the served body did not fit or was itself cut (truncated=1 on it). bodyless=N: of the candidates, those with "
         "no body by construction (a module-scope owner), never shown. "
         "callers: the key body's 1-hop callers (of_top=1). "
         "tail: file-grain rows, weaker than the ranked rows (files the ranking did not show, then the file page), sym= their top "
         "symbols; capped=1 next= the file page from the first row not printed. "
         "Row keys: n=name (chain it), sc=enclosing scope (when scoped; full id p::sc::n), in=reuse-count (absent = not measured, "
         "never a false 0), l=line, e=end line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller, r=rank (rows in r= order). "
         "On the root: dropped_positive=N (present only when nonzero) is the ranked candidates the ceiling cut; est_tokens= is the "
         "delivered bytes at the rate the budget is converted at (2.36 B/token, the densest language: an upper bound); "
         "budget_tokens= is the token target; over_ceiling= is 1 when est_tokens exceeds it (the bundle is then complete, not trimmed). ";
inline constexpr std::string_view kPackTaskHardBudgetSentence =
    "budget_tokens= is the token target; over_ceiling= is 1 when est_tokens exceeds it (the bundle is then complete, not trimmed). ";
inline constexpr std::string_view kPackTaskSoftBudgetSentence =
    "budget_tokens= is the soft token target asked: each section stops once its share is reached; est_tokens may exceed it "
    "(the header always ships; no over_ceiling). ";
static_assert( std::string_view( kPackTaskBundleLegendBody ).ends_with( kPackTaskHardBudgetSentence ),
               "the soft bundle swaps exactly the legend body's last sentence" );

// r4/r6 (2026-09-10 lift-disclosure round): append the two experimental lift notes' JSON keys — same
// absent-unless-present convention as the mention/boost/doc_mention keys beside them. Factored out (unlike
// those three, which predate this round) purely to keep packTaskBundleText's own complexity/verbosity from
// growing on a shape that is otherwise just two more copies of the same three-line conditional.
inline void appendLiftJsonKeys( std::string& j, const std::string& sibliftNote, const std::string& expandNote )
{
    if( !sibliftNote.empty() )
    {
        j += ",\"siblift\":\"" + jsonStr( sibliftNote ) + "\"";
    }
    if( !expandNote.empty() )
    {
        j += ",\"expand\":\"" + jsonStr( expandNote ) + "\"";
    }
}

// One spelling of --pack-task's header, three shapes of it. `withTaskEcho=false` replaces the comment's echo
// with a note pointing at the task= attribute that still holds the verbatim copy — nothing is lost, only the
// duplicate. Byte-identical to the pre-ladder header when both flags are true and extraNotes is empty.
// M1: splice the bundle's owed root attributes onto whichever <ctx …> spelling this header ended up with.
// Both spellings must carry them — the ladder's route-dropped rung rebuilds the root from scratch, and a
// completeness fact that disappears on the rung where the ceiling bit is the exact shape of dishonesty this
// tool forbids. A root that is not an open tag is left alone (the degrade path stays byte-identical). Spliced at the
// root's own '>' (ctxRootOpenAppendAttrs): under a cut history walk the root string ends with a comment.
inline void appendPackTaskRootExtras( std::string& rootOpen, std::string_view extras )
{
    ctxRootOpenAppendAttrs( rootOpen, extras );
}

inline std::string packTaskHeaderText( const PackTaskHeaderParts& p, bool withRouteAttr, bool withTaskEcho,
                                       std::string_view extraNotes )
{
    std::string h = withRouteAttr ? std::string( p.rootOpenStr ) : ctxRootOpen( p.task, {}, p.rootArg );
    appendPackTaskRootExtras( h, p.rootExtraAttrs );
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
    h.append( p.sibliftNote );
    h.append( p.expandNote );
    h.append( p.docMentionNote );
    // P10 (L7): the body is ONE constant — the partitioned document states it once for all slices. forbudget-soft: a soft
    // target's bundle swaps the body's last sentence (the hard budget's reading) for the soft one.
    const std::string_view body( kPackTaskBundleLegendBody );
    if( p.softBudget )
    {
        h.append( body.substr( 0, body.size() - kPackTaskHardBudgetSentence.size() ) );
        h.append( kPackTaskSoftBudgetSentence );
    }
    else
    {
        h.append( body );
    }
    h.append( p.runClause );          // M21(b)/E1: the <test> row's run=/run_unknown= rule and the <g> group row, testmap.h's ONE wording — rows-gated
    h.append( p.report );
    h.append( extraNotes );
    h += " -->";
    if( !p.pathFromNote.empty() )
    {
        h += "<!--";  h.append( p.pathFromNote );  h += " -->";
    }
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
    rw::formatTo( open, sizeof( open ), "<{}{} shown=\"{}\" total=\"{}\" capped=\"{}\">", std::string_view( tag.data(), tag.size() ), std::string_view( extraAttr.data(), extraAttr.size() ), out.kept, entries.size(),
                   out.kept < entries.size() ? 1 : 0 );
    out.xml = open;
    for( std::size_t i = 0; i < out.kept; ++i )
    {
        out.xml += entries[i];
    }
    out.xml += "</";  out.xml.append( tag );  out.xml += ">";
    return out;
}

// ── THE <tests> SECTION — the one list whose entries are not independent ────────────────────────────────
// Every other section here is a list of rows the budget can cut anywhere: entry i costs entry i's bytes,
// whatever its neighbours are. Test rows are not like that. E1 serves a run of runner-less rows with equal
// attributes as ONE <g> row, so admitting one more FILE can cost a whole new row or just `,path` on the row
// already there — the cost of the k-th file depends on the k-1 before it, and packTaskListSection's
// "used += e.size()" has no way to say that.
//
// The first attempt grouped FIRST and handed the group rows to that helper under a per-row byte cap, with a
// cap estimate of `attrs + 48 + Σ( path + 1 )` computed on UNESCAPED paths. Review of #214: a corpus whose
// test paths hold '&' or '<' renders wider than the estimate admitted, the helper broke at the first
// over-budget entry, and the whole tail of the section went with it — `run=` singles included. Measured on a
// ten-test fixture at --token-budget=1440, `_`-named paths served 5 files and the same fixture with `&` in
// every name served NONE: the section vanished rather than shrank.
//
// So this section CUTS WHERE THE BYTES ARE. It asks the only question that matters — what is the largest
// PREFIX of the row list whose GROUPED, ESCAPED rendering fits the budget — and answers it by rendering
// candidate prefixes and measuring them. Cutting a prefix and grouping it afterwards would also have been
// safe (grouping only shrinks), but it cuts over the single rows' bytes and then spends fewer of them: on
// that same fixture it served 2 files where grouping-first served 5, which throws away the win E1 exists for.
//
// The search is a bisection, which is exact because `bodyOf` is monotone in k: extending the prefix by one
// row either appends a row or extends the last group by `,path` (a group of one is rendered as a single
// <test> row, and the two-member <g> that replaces it is strictly wider), so the rendered size never falls
// as k rises. ~log2(n) renders of an O(n) body, against a list that is a few hundred rows at most.
//
// shown=/total= therefore count test FILES — one qualifying file, one entry, on both sides of the cut — and
// a <g n="N"> row carries N of them, which is exactly what the bundle legend now says.
template<class EscapeFn>
inline PackTaskSection packTaskTestsSection( const rw::TestRunnerIndex& runners, std::span<const rw::TestRowOut> rows,
                                             std::size_t budget, std::size_t wrapReserve, EscapeFn esc,
                                             std::vector<std::vector<std::uint32_t>>* partitionOut )
{
    PackTaskSection out;
    if( partitionOut )
    {
        partitionOut->clear();
    }
    const auto bodyOf = [ & ]( std::size_t k, std::vector<std::vector<std::uint32_t>>* keepPart ) -> std::string
    {
        const std::span<const rw::TestRowOut>   prefix( rows.data(), k );
        std::vector<std::vector<std::uint32_t>> part = rw::partitionTestRows( runners, prefix );
        std::string                             body;
        for( const rw::RenderedTestRow& r : rw::testRowsRendered( runners, prefix, rw::TestRowShape{ rw::RowDialect::Xml, "test" }, esc, &part ) )
        {
            body += r.text;
        }
        if( keepPart )
        {
            *keepPart = std::move( part );
        }
        return body;
    };
    if( rows.empty() || budget <= wrapReserve )
    {
        return out;
    }
    std::size_t lo = 0;              // always fits (an empty body is wrapReserve alone)
    std::size_t hi = rows.size();    // may not
    while( lo < hi )
    {
        const std::size_t mid = lo + ( hi - lo + 1 ) / 2;   // lo < mid <= hi
        if( wrapReserve + bodyOf( mid, nullptr ).size() <= budget )
        {
            lo = mid;
        }
        else
        {
            hi = mid - 1;
        }
    }
    out.kept = lo;
    if( out.kept == 0 )
    {
        return out;
    }
    const std::string body = bodyOf( out.kept, partitionOut );
    char              open[ 160 ];
    rw::formatTo( open, sizeof( open ), "<tests shown=\"{}\" total=\"{}\" capped=\"{}\">", out.kept, rows.size(), out.kept < rows.size() ? 1 : 0 );
    out.xml = std::string( open ) + body + "</tests>";
    return out;
}


// optional Q3/redaction/notes inputs the bundle folds in when the caller has them; every field defaults to
// "not available" and each is handled by a graceful degrade downstream (packSignatures' own
// nullptr-omits-the-attr contract), so a caller with NONE of these (a bare MCP call) still gets a complete,
// correctly-shaped bundle — matching how a plain CLI `--pack-task` run (without `--for`/`--metrics` also set)
// already leaves fanIn/impure/churn/tested/amp unset today.
// The DISCLOSE sink for a pack-task section whose render degraded (infra/emit.h renderToString: Rendered::ok == false,
// empty text). Such a section is EMPTY because its render failed — not because the budget omitted it, and not because
// nothing matched — so the bundle marks the section itself (render_failed="1") and names it on the root
// (render_failed="ranking,bodies"), in the XML and the JSON dialect alike. A body-cost PROBE that fails prices that body
// as unaffordable (it is then omitted like any over-budget body) and is named on the root as "body-probe".
struct PackTaskRenderFaults
{
    enum class DisclosureWhy : std::uint8_t
    {
        RankingRenderFailed,
        BodiesRenderFailed,
        BodyProbeRenderFailed,
        // PB1 2026-11-19: the SHAPE surprises, which are not render failures — the block rendered fine and this
        // code then could not recognise it. They were sink-less DISCLOSE( msg ) sites, i.e. silent in Release,
        // and selfcheckcheck's ratchet counts those with a stated target of ZERO. A sink is what makes the
        // degrade reach a release user, so they take one.
        HeadShapeUnknown,
        BodiesShapeUnknown,
    };
    std::uint8_t failedMask = 0;   // bit i ⇔ DisclosureWhy value i
    void disclose( DisclosureWhy why ) noexcept
    {
        failedMask = std::uint8_t( failedMask | ( 1u << unsigned( why ) ) );
    }
    bool hasFailed( DisclosureWhy why ) const noexcept
    {
        return ( failedMask & ( 1u << unsigned( why ) ) ) != 0;
    }
    // "ranking,bodies,body-probe" in DisclosureWhy order — the root attribute's value ("" when nothing failed)
    std::string names() const
    {
        static constexpr const char* kNames[] = { "ranking", "bodies", "body-probe", "head-shape", "bodies-shape" };
        static_assert( std::size( kNames ) == unsigned( DisclosureWhy::BodiesShapeUnknown ) + 1,
                       "every DisclosureWhy needs a name: the root prints these and an unnamed bit would read as nothing" );
        std::string out;
        for( unsigned i = 0; i < std::size( kNames ); ++i )
        {
            if( ( failedMask & ( 1u << i ) ) != 0 )
            {
                out += out.empty() ? "" : ",";
                out += kNames[ i ];
            }
        }
        return out;
    }
};

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
    // L3 follow-up (CodeRabbit 4053600616): read BEFORE the caller nulls `notes` for emptiness, so a sidecar
    // that left EVERY line unparsed (notes empty, but the read was not clean) still reaches this bundle's root
    // — the same reason MainDispatch carries notesDegraded beside notesPtr (main.cpp).
    bool                                notesDegraded = false;

    // Query relevance for ORDERING each emitted body's <calls> callee listing when the 16-row cap or the
    // byte budget CUTS it — serialize.h CalleeCallsSink::rank carries the finding and the measurement.
    // packTaskBundleText fills this from its own LensRanking (below, beside the fanIn self-supply), so
    // every caller — CLI --pack-task and the MCP verb alike — gets the ranked cut without spelling it.
    const std::vector<float>*          calleeRank = nullptr;

    // §6 --partition: a PRE-COMPUTED Q3 clone-membership lens. findClones() is a pure function of `ing`, so a
    // fan-out that assembles N+1 bundles from the SAME index would otherwise pay for N+1 identical clone
    // passes. nullptr ⇒ this function computes its own (every existing caller, unchanged).
    const std::vector<std::uint8_t>*   cloneMember = nullptr;

    // §6 --partition: override the ranking WINDOW width (default kPackTaskRankTopN). A partitioned bundle's
    // rank vector is masked to its own slice, so a window wider than the slice would pull in zero-score
    // symbols the bundle was never about. 0 ⇒ kPackTaskRankTopN (every existing caller, unchanged).
    std::size_t                        rankTopN = 0;

    // P10 (L7): this bundle is one slice of a --partition=N document — emit its <ctx> root with NO legend comment
    // (the outer legend states the bundle legend once); ceiling/dropped notes ride one short data comment.
    bool                               innerBundle = false;

    // §F1 (CA4 wave-1 verifier): bytes the CALLER will splice in before this bundle's own "</ctx>" — today
    // exactly one thing, the CLI's --with-graph mermaid block (main.cpp runPackTask). It was appended AFTER
    // this function had already divided the budget and priced the ceiling ladder, so a fixed ~399 B rode in
    // uncharged: MEASURED `--pack-task --token-budget=800 --with-graph` = 2 445 B against a 2 171 B allowance,
    // 12.6% over with NO over_ceiling label, while the bare form at the same budget was conformant. Charged
    // here, at the two places the budget is spent: the section shares trim to leave room for it, and the ladder
    // prices it, so the label fires when the trim cannot get there. 0 ⇒ every other caller, byte-identical.
    std::size_t                        trailingSectionBytes = 0;
    // The caller's trailing section could not be charged (its chargeSection degraded, so trailingSectionBytes is 0 and
    // it streams directly): est_tokens leaves those bytes out and the root labels itself est_measured="0".
    bool                               isTrailingUncharged  = false;
    // Where this bundle's section renders record a failure (see PackTaskRenderFaults). packTaskBundleText points it at
    // its own local; nullptr ⇒ a render failure is still returned as empty text, just not recorded.
    PackTaskRenderFaults*              renderFaults         = nullptr;

    // forbudget-soft (owner decision 2026-10-14): the caller passed this budget (CLI --pack-task --token-budget, MCP explore
    // budget_tokens) — a SOFT target. The section cascade is the default's, unchanged; the ceiling ladder does not run (the
    // task echo and route= always ship) and nothing is labelled over_ceiling. false: the default budget (kPackTaskDefaultTokens)
    // and the --partition slices, which keep the hard ceiling (packtaskcheck 4b, partitioncheck 5).
    bool                               softTarget = false;

    // L1 fix round (rv-r1-L1 MED-4): the run's legend posture is compact, so the ceiling ladder's rungs (drop the task echo,
    // then route=, then label over_ceiling) are judged on the bytes the compact layer DELIVERS — the task echo lives in the
    // prose the layer strips, and dropping it for a full-dialect price cut a fact the compact answer had room for. The
    // section shares are unchanged (their reserve is posture-free), so rows(default) == rows(full) here.
    bool                               compactLegend = false;

    // R-E (2026-08-17 harvest): the single-root run's OWN root argument — same convention serialize()'s
    // rootArg takes (empty ⇒ multi-root, or a caller that never resolved one, e.g. an MCP call against a
    // workspace this struct's caller has not single-rooted). Threaded through every `<f p=…>`/`<test p=…>`
    // row this bundle renders (packSignatures/packBodies/the D1 caller rows/the far-tier name-only rows) so
    // CLI (runPackTask) and MCP (mcpverbs.h's packTaskText) cannot diverge — one assembler, one root.
    std::string_view                   rootArg;

    // PB1: KB1's key body for this task (forkeybody.h keyBodyFor), resolved by the caller — the first bodied source definition
    // the question's backtick spans (or its rule-E2 symbol) place. kNoNode: none placed, the top positive-score head serves.
    NodeId                             keyBody = kNoNode;
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

// every packTaskBundleText section (and renderRankingWithFar below) renders through infra/emit.h's ONE
// renderToString seam. A section whose render degrades comes back EMPTY; this wrapper records WHICH one in the
// bundle's PackTaskRenderFaults, so the caller can mark the section and the root instead of letting an empty
// string read as a budget omission (or, in the JSON dialect, as a missing value after its key).
struct PackTaskRendered
{
    std::string text;
    bool        ok = false;
};

template<PackTaskRenderFaults::DisclosureWhy kWhy, class Emit>
inline PackTaskRendered packTaskRender( Emit&& emit, PackTaskRenderFaults* faults )
{
    rw::Rendered r = rw::renderToString( std::forward<Emit>( emit ) );
    if( !r.ok )
    {
        ASSUME( r.text.empty() );   // renderToString's contract: a failed render hands back no partial buffer
        if( faults != nullptr )
        {
            DISCLOSE( *faults, kWhy, "pack-task: a section's render failed — the section is marked render_failed and named on the root" );
        }
    }
    return PackTaskRendered{ std::move( r.text ), r.ok };
}

// WHERE packBodies' OWN `<bodies …>` OPEN TAG STARTS AND ENDS — by structure, never by punctuation.
// The document is `<!-- legend --><!-- legend --><bodies …>…</bodies>`: packBodies writes zero or more
// COMMENT nodes ahead of the tag, and since #60 one of them (kBodylessBodiesLegend) contains
// `n=<file-scope>` — an angle bracket inside legend prose. `find( '>' )` used to be the end of the open
// tag; with that comment present it is a byte inside the comment, so the wrapper spliced mid-legend and
// emitted TWO opens and one close: malformed XML, past every gate (nothing ran xmllint over a --pack-task
// document holding an owner). The lesson generalises past this one legend — a document that can carry a
// tag-like NAME in prose can never be parsed by matching punctuation — so this skips comment nodes
// explicitly and then takes the '>' that closes the element it actually found.
// #60: how many of these candidates have NO BODY BY CONSTRUCTION — a module-scope owner, whose Symbol
// extent is empty (ingest_model.h assignSymbols). Such a candidate can never be in `emitted.kept`, so
// counting it as an over-budget omission is the same false cap --expand was fixed for, one verb over: the
// wrapper below used to write `<!-- body omitted (over budget): <file-scope> -->` and restamp capped="1"
// over a body that never existed. The ledger and the monotone roll read this same count, so the document
// cannot say capped="0" bodyless="1" in the tag and "(capped)" in its own ledger.
inline std::size_t countBodylessCandidates( const IngestResult& ing, const std::vector<NodeId>& bodyIds ) noexcept
{
    std::size_t n = 0;
    for( NodeId id : bodyIds )
    {
        n += ( id < ing.symbols.size() && ing.symbols[id].kind == SymKind::ModuleScope ) ? 1u : 0u;
    }
    return n;
}

// P10 (partitioncheck): packBodies writes kTruncatedBodyLegend, then kOverCeilingBodyLegend, right after the <bodies …>
// open tag of a bundle whose body it cut or served past the budget, and a partitioned answer would then repeat those
// readings once per slice. A slice drops them and the outer <ctx-partitions> legend states each once (partition.h).
// POSITIONAL, never a search: a reading is removed only where packBodies put it, so a CDATA body that quotes the same
// sentence is never touched. Bits: kBodyReadingTruncated / kBodyReadingOverCeiling (what the kept bodies carry).
inline constexpr std::uint8_t kBodyReadingTruncated   = 1u;
inline constexpr std::uint8_t kBodyReadingOverCeiling = 2u;
inline void hoistBodyReadings( std::string& bodiesXml )
{
    const SectionOpenTag tag = findSectionOpenTag( bodiesXml, "<bodies" );
    if( tag.end == std::string::npos )
    {
        return;
    }
    for( const std::string_view legend : { std::string_view( kTruncatedBodyLegend ), std::string_view( kOverCeilingBodyLegend ) } )
    {
        if( bodiesXml.compare( tag.end + 1, legend.size(), legend ) == 0 )
        {
            bodiesXml.erase( tag.end + 1, legend.size() );
        }
    }
}


// ── W2-K: monotone section shares ─────────────────────────────────────────────────────────────────────────
// Every section share below is `quota + carry`, and a section only donates its unspent share forward when it was not itself
// cut — so each share, and each kept count, is a non-decreasing function of budgetTokens (packtaskmonotoncheck).
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
        return { std::max( granted, consumed ), 0 };   // PB1: the head keeps rows past its target up to its row-drop bound
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

// ── PB1 (PT1 design D1, owner-approved 2026-11-19): the ranking section is --for's head ─────────────────────────────────
// PT1 (results/PT1_PACKTASK_1119/READOUT.md §1) traced why --pack-task named 89 of SUB1's 165 gold files where --for page 1
// named 148: the SAME ranker, then a fixed 12-row window in raw score order with every row past one hop of the six bodies
// demoted to a name-only <far> row, and no file-grain tail. 19 gold files sat at r 13-40, 4 more were --for head rows
// only through its round robin by file, and 37 were ranked at file grain only. The budget cut no ranking row in 52/52.
// So the section is now --for's own head: packSignatures over the UNMASKED rank, kPackTaskHeadRows rows, the --for lens's
// rules (relevance floor, e=, docs after code, the round robin by file — each under the same verdict --for applies), and
// the ladder's row drop bounded so the head cannot starve the key body. The <far> tier is gone with the mask that fed it.
// THE ROW SHAPE (PT1 §2: --for page 1's 40-row block is "about 10 full rows and 30 pointer rows", a median 4,594 B on SUB1's
// tasks). The first kPackTaskFullHeadRows rows print whole (doc, signature, lens facts); every row past them is a POINTER ROW,
// `<d l= n= [sc=] p= r=/>` — its name and place, the --expand selector's parts, nothing else. Rows are never reordered and none
// is added: the r= sequence is --for's own. Only when even that shape is over the head's bound are rows dropped, lowest rank
// first, and the <sigs> tag then says shown= total= capped="1" with next= the --for call that serves all of them.
//
// THE SHAPE IS A LADDER, NOT A CONSTANT, and rows are the LAST thing it sheds. A long task echo is charged exactly, so a
// 900-character task against a 1,200-token budget collapses `remaining` to its floor — and the first draft of this pass
// answered that by keeping ONE row at FULL detail (2,961 B on w3fixbudgetcheck's fixture, more payload than the same
// bundle served for a SHORT task: "bytes riding free"). The order is now text first, rows last, and never below the floor:
//   1. the largest full-row prefix (kPackTaskFullHeadRows down to 0) whose rendering fits the bound; everything past it
//      is a pointer row, so a tight bound shrinks ROW TEXT before it costs a single file its name;
//   2. only then rows, lowest rank first, and never below kPackTaskHeadFloorRows — --for's own "rank 1..4 always ship"
//      floor (forbudgetfit.h kForBudgetRowFloor), which this head shares because it IS --for's head.
inline constexpr std::size_t kPackTaskFullHeadRows  = 10;
inline constexpr std::size_t kPackTaskHeadFloorRows = 4;   // == forbudgetfit.h kForBudgetRowFloor (the rank 1..4 floor)
struct PackHeadInputs
{
    int                               topN         = 0;
    std::size_t                       boundBytes   = 0;   // the head's ceiling: rows past it are dropped, lowest rank first
    SigLensRules                      rules        = SigLensRules::None;
    std::string_view                  task;
    const PackTaskInputs*             in           = nullptr;
    const std::vector<std::uint8_t>*  forClone     = nullptr;
};
struct PackHead
{
    std::string         sigsStr;
    bool                capped          = false;
    std::size_t         droppedPositive = 0;
    std::vector<NodeId> shownIds;   // the rows printed, printed order — the tail excludes their files, as --for's does
    SigsCutReport       cut;
};

// `<d …>…</d>` → `<d l= n= sc= p= r=/>` (the attributes it has of those, in that order).
inline std::string packTaskPointerRow( std::string_view openTag )
{
    std::string row = "<d";
    for( const std::string_view a : { std::string_view( "l" ), std::string_view( "n" ), std::string_view( "sc" ), std::string_view( "p" ), std::string_view( "r" ) } )
    {
        const std::string_view v = attrOf( openTag, a );
        if( !v.empty() )
        {
            row += " ";  row += a;  row += "=\"";  row += v;  row += "\"";
        }
    }
    return row + "/>";
}

// Remove one attribute from an open tag, if it carries it. Returns true when something was removed.
// The ADDRESS of the value attrOf (serialize.h) already finds is what locates the span to erase: a second
// hand-rolled ` name="` find here is the same seven lines handoffwindow.h's printedAttrOf already spells, and
// --quality-delta's clone detector matched them at 109 tokens the first time this was written that way.
inline bool stripOpenTagAttr( std::string& xml, std::string_view name )
{
    const std::string_view v = attrOf( xml, name );
    if( v.data() == nullptr )
    {
        return false;
    }
    const std::size_t at    = std::size_t( v.data() - xml.data() );   // attrOf returns a view INTO xml
    const std::size_t start = at - ( name.size() + 3 );               // back over ` name="`
    xml.erase( start, ( at + v.size() + 1 ) - start );                // forward over the closing quote
    return true;
}

// Replace (or append before the closing '>') one attribute of an open tag.
inline void setOpenTagAttr( std::string& tag, std::string_view name, std::string_view value )
{
    const std::string key = " " + std::string( name ) + "=\"";
    const std::size_t at  = tag.find( key );
    if( at != std::string::npos )
    {
        const std::size_t close = tag.find( '"', at + key.size() );
        tag.replace( at + key.size(), close - ( at + key.size() ), value );
        return;
    }
    tag.insert( tag.size() - 1, key + std::string( value ) + "\"" );
}

// The row-shape ladder and the bound, over the rendered <sigs> block (rows in `shownIds` order, one row element each).
inline void packTaskShapeHead( PackHead& h, std::size_t boundBytes, std::string_view task, PackTaskRenderFaults& faults )
{
    const SectionOpenTag open = findSectionOpenTag( h.sigsStr, "<sigs" );
    if( open.end == std::string::npos || !h.sigsStr.ends_with( "</sigs>" ) || h.sigsStr[ open.end - 1 ] == '/' )
    {
        return;   // an empty or unexpected block is left as rendered
    }
    std::string              tag( h.sigsStr.substr( open.start, open.end + 1 - open.start ) );
    std::vector<std::string> rowsFull, rowsPtr;
    std::string              lead;   // comments ahead of the first row (a reading packSignatures wrote), kept verbatim
    const std::size_t        bodyEnd = h.sigsStr.size() - 7;
    for( std::size_t i = open.end + 1; i < bodyEnd; )
    {
        if( h.sigsStr.compare( i, 4, "<!--" ) == 0 )
        {
            const std::size_t e = h.sigsStr.find( "-->", i );
            if( e == std::string::npos )
            {
                DISCLOSE( faults, PackTaskRenderFaults::DisclosureWhy::HeadShapeUnknown, "pack-task: <sigs> held an unterminated comment — the block is left as rendered" );
                return;   // refuse rather than guess where it ends, exactly as findSectionOpenTag does
            }
            if( rowsFull.empty() ) { lead += h.sigsStr.substr( i, e + 3 - i ); }
            else { rowsFull.back() += h.sigsStr.substr( i, e + 3 - i );  rowsPtr.back() += h.sigsStr.substr( i, e + 3 - i ); }
            i = e + 3;
            continue;
        }
        const std::size_t gt = h.sigsStr.find( '>', i );
        if( gt == std::string::npos || h.sigsStr[i] != '<' )
        {
            DISCLOSE( faults, PackTaskRenderFaults::DisclosureWhy::HeadShapeUnknown, "pack-task: <sigs> held a child the head pass does not know — the block is left as rendered" );
            return;
        }
        // A ROW is packSignatures' `<d …>…</d>` / `<d …/>`, or a row the LADDER already shrank past anything a
        // pointer row would say — the touch tier's `<t p= sym= r=/>`, which arrives self-closed and minimal. Only a
        // <d> row is re-spelled as a pointer row; any other self-closed row is kept verbatim.
        // Before this, one `<t>` row made the whole pass bail, so on exactly the corpora where the ladder has to
        // shrink (the long-signature ones) the head kept its full rows AND its byte bound went unapplied — the
        // budget then rode on the tail re-cut alone. The shownIds disagreement below stays the backstop for a
        // shape neither branch knows.
        const bool             isD     = h.sigsStr.compare( i, 3, "<d " ) == 0;
        const std::string_view openRow = std::string_view( h.sigsStr ).substr( i, gt + 1 - i );
        std::size_t            end     = gt + 1;
        if( h.sigsStr[ gt - 1 ] != '/' )
        {
            const std::size_t close = isD ? h.sigsStr.find( "</d>", gt ) : std::string::npos;
            if( close == std::string::npos )
            {
                DISCLOSE( faults, PackTaskRenderFaults::DisclosureWhy::HeadShapeUnknown, "pack-task: a <sigs> row did not close where the head pass expects — the block is left as rendered" );
                return;
            }
            end = close + 4;
        }
        // BOTH spellings of every row are kept: the ladder below chooses how many print whole, and a row that cannot
        // be re-spelled (anything but a <d> row) is already at its pointer size, so the two forms are the same string.
        rowsFull.emplace_back( h.sigsStr.substr( i, end - i ) );
        rowsPtr.emplace_back( isD ? packTaskPointerRow( openRow ) : rowsFull.back() );
        i = end;
    }
    if( rowsFull.size() != h.shownIds.size() )
    {
        DISCLOSE( faults, PackTaskRenderFaults::DisclosureWhy::HeadShapeUnknown, "pack-task: <sigs> rows and the shown ids disagree — the head pass keeps the block as rendered" );
        return;
    }
    const std::size_t totalRows = rowsFull.size();
    const std::size_t fixed     = tag.size() + lead.size() + 7;
    // STEP 1 — the largest full-row prefix that fits. fullCount counts down, so the result is the most detail the bound
    // holds and never more; at 0 every row is a pointer row, which is this section's smallest honest shape.
    std::size_t fullCount = std::min( totalRows, kPackTaskFullHeadRows );
    const auto  bytesFor  = [ & ]( std::size_t fulls, std::size_t keptRows ) -> std::size_t
    {
        std::size_t n = fixed;
        for( std::size_t k = 0; k < keptRows; ++k )
        {
            n += ( k < fulls ? rowsFull : rowsPtr )[k].size();
        }
        return n;
    };
    while( fullCount > 0 && bytesFor( fullCount, totalRows ) > boundBytes )
    {
        --fullCount;
    }
    // STEP 2 — only now rows, lowest rank first, and never below --for's own rank 1..4 floor.
    const std::size_t floorRows = std::min( totalRows, kPackTaskHeadFloorRows );
    std::size_t       kept      = totalRows;
    while( kept > floorRows && bytesFor( fullCount, kept ) > boundBytes )
    {
        --kept;
    }
    std::vector<std::string> rows;
    rows.reserve( kept );
    for( std::size_t k = 0; k < kept; ++k )
    {
        rows.emplace_back( k < fullCount ? rowsFull[k] : rowsPtr[k] );
    }
    if( kept < totalRows )
    {
        const std::size_t total = std::max<std::size_t>( totalRows, h.cut.total );
        setOpenTagAttr( tag, "shown", std::to_string( kept ) );
        setOpenTagAttr( tag, "total", std::to_string( total ) );
        setOpenTagAttr( tag, "capped", "1" );
        h.cut.next = nextFlag( "--for=", task );
        std::string nextValue;
        appendNextValueXml( nextValue, h.cut.next );   // nextverb.h: the ONE next= value escape
        setOpenTagAttr( tag, "next", nextValue );
        h.cut.isCapped = true;  h.cut.shown = kept;  h.cut.total = total;
        h.capped       = true;
        h.shownIds.resize( kept );
    }
    std::string out = tag + lead;
    for( std::size_t k = 0; k < kept; ++k )
    {
        out += rows[k];
    }
    h.sigsStr = out + "</sigs>";
}

inline PackHead renderPackHead( const IngestResult& ing, const std::vector<float>& rank, const PackHeadInputs& hi )
{
    PackHead out;
    out.sigsStr = packTaskRender<PackTaskRenderFaults::DisclosureWhy::RankingRenderFailed>( [ & ]( std::FILE* m )
    {
        packSignatures( m, ing, rank, hi.topN, hi.in->sigLadderBudgetBytes, /*metrics=*/true, hi.in->fanIn, hi.in->impure, hi.in->redact,
                        // payloadBudgetBytes IS the head's bound: the ladder's TEXT-shrink steps (drop docs, shrink signatures,
                        // the touch tier) must aim at it, and only then does packTaskShapeHead's pointer-row pass and row drop
                        // run against the same number. Passing 0 here left the ladder unbudgeted, so under a tight budget — a
                        // long task echo collapses `remaining` to its floor — the one surviving row kept its FULL text and the
                        // payload grew with the header instead of shrinking (w3fixbudgetcheck arm 4: "bytes riding free").
                        hi.in->churn, hi.forClone, hi.in->tested, hi.in->amp, /*rankAdaptivePayload=*/true, /*payloadBudgetBytes=*/hi.boundBytes,
                        /*noteIndex=*/nullptr,   // notes are a DEDICATED section, never inline here (avoids double-emit)
                        hi.in->rootArg, hi.rules, &out.droppedPositive, &out.shownIds, &out.capped, /*topRowNext=*/{}, &out.cut );
    }, hi.in->renderFaults ).text;
    if( out.sigsStr.empty() )
    {
        out.sigsStr = "<sigs render_failed=\"1\"></sigs>";   // the section is there and says why it is empty
        out.shownIds.clear();
        return out;
    }
    PackTaskRenderFaults headFaultsFallback;   // a caller that asked for no fault record gets a local one: never silent
    packTaskShapeHead( out, hi.boundBytes, hi.task, hi.in->renderFaults ? *hi.in->renderFaults : headFaultsFallback );
    return out;
}

// The verdicts --for takes for its head rules, taken here from the bundle's own inputs (no Config): the docs reorder on a routed
// question that does not ask about docs, e= and the round robin under the same budget rule. `budgetTokens` is the caller's
// explicit budget (a soft target) or 0 for the default, as --for passes cfg.tokenBudget.
inline SigLensRules packTaskHeadRules( const IngestResult& ing, const std::string& task, const LensRanking& lr, std::size_t budgetTokens )
{
    const bool routed        = lr.routeTag != nullptr && std::strcmp( lr.routeTag, "no-route" ) != 0;
    const bool conceptual    = lr.routeTag != nullptr && std::strcmp( lr.routeTag, "subtoken+body" ) == 0;
    const bool docsAfterCode = routed && !taskAsksAboutDocs( task ) && std::getenv( "RIPWIRE_NO_DOCS_AFTER_CODE" ) == nullptr
                               && docsAfterCodeFitsCeiling( budgetTokens, false );
    return forLensRules( docsAfterCode, endLinesFitCeiling( budgetTokens, false ),
                         forHeadRoundRobinOn( conceptual, taskNamesIndexedFile( ing, task ), budgetTokens, false ) );
}

// ── PB1: ONE body, the key one ───────────────────────────────────────────────────────────────────────────────────────────
// PT1 §2: body 1's file was a changed file in 28/52, body 2's in 20/45, bodies 3-6 in 26/117 — the lesser five spent 35% of
// the answer at a 22% hit rate, the bytes the file tail needs. The key body is KB1's (forkeybody.h): the first definition the
// question's backtick spans (or its rule-E2 symbol) place, else the top positive-score head. Every other candidate — the old
// six-head set — rides as a `<bn … next="--expand=…"/>` pointer inside <bodies>: counted in total=, never in shown=.
// KB1's pick arrives as PackTaskInputs::keyBody (the callers run forkeybody.h, which this header cannot include: subjectanchor.h
// reaches back here through forcallerhop.h). It is taken when this bundle's rank does not mask it out — a --partition slice pins
// every symbol outside the slice to -1 — else the top positive-score head that HAS a body: a module-scope owner stays a
// candidate (total=/bodyless= count it) but cannot be the one served row, since it has no body to serve (#60).
inline NodeId packTaskKeyBody( const IngestResult& ing, NodeId keyed, const std::vector<float>& rank, const std::vector<NodeId>& heads )
{
    if( keyed != kNoNode && keyed < rank.size() && rank[keyed] >= 0.0f && ing.symbols[keyed].kind != SymKind::ModuleScope )
    {
        return keyed;
    }
    for( NodeId id : heads )
    {
        if( ing.symbols[id].kind != SymKind::ModuleScope )
        {
            return id;
        }
    }
    return kNoNode;
}

// The --expand selector of one definition, as the answer spells p= — hopbody.h expandSelectorOf's spelling (p:l:n), which this
// header cannot include for the same reason.
inline std::string packTaskExpandSelector( const IngestResult& ing, NodeId id, std::string_view rootArg )
{
    const Symbol& s = ing.symbols[id];
    return nextFlag( "--expand=", lensRowPath( ing, s.fileId, rootArg ) + ":" + std::to_string( s.line ) + ":" + s.name );
}

// The body candidates: the key body first, then the top positive-score heads, each once, at most
// kPackTaskBodyCandidates. Module-scope owners STAY in the set — they have no body by construction, so they can
// never be `shown`, but `total=` counts them and `bodyless=` says how many of total= they are (#60's contract,
// gated by xmlwellformed #60 and subjectanchorcheck F10). Only the SERVED body has to be a bodied symbol.
inline std::vector<NodeId> packTaskBodyCandidates( const IngestResult& ing, const std::vector<NodeId>& order, const std::vector<float>& rank,
                                                   NodeId keyId )
{
    std::vector<NodeId> out;
    if( keyId != kNoNode )
    {
        out.push_back( keyId );
    }
    for( std::size_t k = 0; k < order.size() && out.size() < kPackTaskBodyCandidates; ++k )
    {
        const NodeId id = order[k];
        if( rank[id] <= 0.0f )
        {
            break;
        }
        if( id != keyId )
        {
            out.push_back( id );
        }
    }
    ( void )ing;
    return out;
}

// THE ROW TAG IS `<bn …/>`, NOT `<b …/>`. A `<b>` row is a SERVED body and `<bodies shown=>` counts exactly those:
// five bodyless `<b>` rows under `shown="1"` is a section contradicting itself, which is what the truncation
// vocabulary (test/truncvocabcheck.sh arm (E), pageview.h rule 5) reads shown= against. A candidate the bundle did
// not serve is a different kind of row — a pointer to the call that would serve it — so it gets its own name and is
// counted in total= and in the ledger instead: `<bn t= n= p= l= next="--expand=p:l:n"/>`.
template<class EscFn>
inline std::string packTaskBodyPointers( const IngestResult& ing, const std::vector<NodeId>& ids, EscFn&& ex, std::string_view rootArg )
{
    std::string out;
    for( NodeId id : ids )
    {
        const Symbol& s = ing.symbols[id];
        out += "<bn t=\"";  out += symTag( s.kind );
        out += "\" n=\"";   out += ex( s.name );
        out += "\" p=\"";   out += ex( lensRowPath( ing, s.fileId, rootArg ) );
        out += "\" l=\"";   out += std::to_string( s.line );
        out += "\"";        out += nextAttrXml( packTaskExpandSelector( ing, id, rootArg ) );
        out += "/>";
    }
    return out;
}

// packBodies' own `<bodies …>` tag describes the one id it was handed; this restates it over the true candidate set and puts the
// pointers inside. Everything before the tag (packBodies' legend comments) is kept verbatim; compress="1" survives the rewrite.
// `shown` is taken BY REFERENCE because the degrade path below changes the answer: a shape this cannot lift the served body out
// of loses that body, and a `shown="1"` over a section with no body in it is a WRONG ANSWER, not a cosmetic one (the same rule
// that makes a false capped= a defect). The count is restated to 0, the key body's own next= pointer goes in beside the others
// so nothing is silently dropped, and the caller reads the zero back for the ledger and the JSON dialect.
// CAPPED= IS A BUDGET VERDICT, NOT `shown != total`, and the truncation vocabulary enforces exactly that equivalence
// (test/truncvocabcheck.sh arm (E): `capped="1"` iff `shown < total` or a served row was itself cut). This section serves
// ONE body BY DESIGN, so total= is what QUALIFIED to be served — 1 when a bodied key body exists, 0 when none does — and
// the other candidates are not casualties of the budget. They ride as `<bn>` pointer rows, so the arithmetic and the bit
// agree and a candidate is never reported as a cut the budget did not make. `bodyless=` keeps #60's meaning: of the
// candidate set, those with no body by construction ("a bodyless owner is not an over-budget cut").
//
// BUT A SERVED BODY THAT WAS TRUNCATED IS A CUT, and the first form of this rule missed it: capped= read only
// `served < servedTotal`, so a body emitted and then cut short reported `capped="0"`. MEASURED over this lane's 596 dev
// answers: 194 of them (33%) carried `<b … truncated="1">` under `<bodies capped="0">` — a truncation the document did not
// admit to, which is the same defect class as a false cap with the sign flipped. It is the reading truncvocabcheck already
// spells for this element ("rows all present but one is CUT: capped=1 with shown == total") and bodydialectcheck enforces.
// capped= is now `served < servedTotal || servedCut`.
struct PackBodiesTag
{
    std::size_t served      = 0;       // shown= : bodies actually emitted (0 or 1)
    std::size_t servedTotal = 0;       // total= : bodies that qualified to be served
    std::size_t candidates  = 0;       // the whole candidate set: the served body plus every <bn> pointer row
    bool        servedCut   = false;   // the served body was emitted but TRUNCATED — a cut, and it must say so
    std::size_t bodyless    = 0;       // of candidates=: no body by construction (a module-scope owner)
    bool        compress    = false;   // the per-bundle compression disclosure must survive the rewrite
};
// `served` is read back by the caller because the degrade path below changes the answer: a shape this cannot lift the served
// body out of loses that body, and a `shown="1"` over a section with no body in it is a WRONG ANSWER, not a cosmetic one.
// The count is restated to 0, the key body's own next= pointer goes in beside the others so nothing is silently dropped,
// and the caller reads the zero back for the ledger, the section charge and the JSON dialect.
inline std::string restatePackTaskBodies( std::string_view bodiesXml, PackBodiesTag& t, std::string_view keyPointer, std::string_view pointers,
                                          PackTaskRenderFaults& faults )
{
    const SectionOpenTag tag         = findSectionOpenTag( bodiesXml, "<bodies" );
    const bool           closesRight = bodiesXml.ends_with( "</bodies>" );
    if( bodiesXml.empty() )
    {
        // NOT a degrade: the share was under kPackTaskSectionFloor, so packBodies was never called and there is
        // nothing to lift out. The key body rides as a pointer like any other candidate and shown= is honestly 0.
        // (This case used to take the branch below and print its disclosure on every --partition slice, which is
        // a degrade alert for a path that is working as designed — ASan run, 2026-11-19.)
        t.served = 0;
    }
    else if( tag.end == std::string::npos || !closesRight )
    {
        DISCLOSE( faults, PackTaskRenderFaults::DisclosureWhy::BodiesShapeUnknown,
                  "pack-task: <bodies> did not have the expected open/close shape — the served body is dropped and shown= restated to 0" );
        t.served = 0;
    }
    // 40, not 32, for each: ' bodyless="' + '"' is 12 B and the count is a std::size_t, 20 digits at absolute most, so 32 B
    // of text needs 33 with the NUL. formatTo truncates rather than overruns, but a cut here drops the closing quote and the
    // document stops being well-formed (test/fixedbufsweep.sh's TABLE states the rule).
    char bodylessAttr[ 40 ] = { 0 };
    if( t.bodyless > 0 )
    {
        rw::formatTo( bodylessAttr, sizeof( bodylessAttr ), " bodyless=\"{}\"", t.bodyless );   // #60, absent at zero
    }
    // THE POINTER ROWS ARE NOT GIVEN A COUNT ATTRIBUTE, deliberately. They are already one row each, every row names the
    // call that serves it, and the ledger line below states the number ("kept 1 of 1, 5 as next="). A `next_rows=` here
    // would also wedge a new attribute between capped= and bodyless=, which is the exact pair #60's own arm
    // (test/xmlwellformed.sh) and subjectanchorcheck F10 read as the bodyless verdict — so the cheapest honest spelling is
    // the one that adds no attribute at all. bodyless= stays the last count on this tag.
    char open[ 176 ];
    rw::formatTo( open, sizeof( open ), "<bodies shown=\"{}\" total=\"{}\" capped=\"{}\"{}{}>", t.served, t.servedTotal,
                  t.served < t.servedTotal || t.servedCut ? 1 : 0, rw::cstr( bodylessAttr ), t.compress ? " compress=\"1\"" : "" );
    if( bodiesXml.empty() || tag.end == std::string::npos || !closesRight )
    {
        return std::string( open ) + std::string( keyPointer ) + std::string( pointers ) + "</bodies>";
    }
    std::string out( bodiesXml.substr( 0, tag.start ) );
    out += open;
    out += bodiesXml.substr( tag.end + 1, bodiesXml.size() - 9 - ( tag.end + 1 ) );
    if( t.served == 0 )
    {
        out += keyPointer;   // the key body was not served (a share under the floor): it is a pointer like the rest
    }
    out += pointers;
    out += "</bodies>";
    return out;
}

// ── PB1: the file-grain tail, filled LAST to the bundle's ceiling ─────────────────────────────────────────────────────────
// --for's <tail> (forpage.h computeFileTail): the positive-score files the head did not show, then the file page's rows. Cut at a
// row boundary to the bytes left once every other section is served — the largest row count whose rendering fits — so the cut
// is a byte rule, deterministic, and disclosed by the element itself (shown= total= capped="1" next= the file page from its
// first unprinted row).
inline std::size_t packTaskTailRowsToFit( const FileTail& t, std::size_t budget, std::vector<char>& esc )
{
    std::size_t lo = 0, hi = t.paths.size();
    while( lo < hi )
    {
        const std::size_t mid = lo + ( hi - lo + 1 ) / 2;
        if( renderFileTailXml( t, mid, esc ).size() <= budget )
        {
            lo = mid;
        }
        else
        {
            hi = mid - 1;
        }
    }
    return lo;
}
// ── THE --json TAIL, ITS OWN FUNCTION ────────────────────────────────────────────────────────────────────────
// The JSON dialect re-serializes the SAME section decisions the XML above already made, so it needs those
// decisions and nothing else. Its inputs are a PARTS RECORD, the idiom verbs_quality.h's QualityDeltaLegendParts
// already spells: a flat record of already-computed values, const references for the containers, one comment per
// field, no std::function and no owning copies — it is read once, inside one call, and every source outlives it.
// WHY IT MOVED (owner ruling, 2026-11-19): packTaskBundleText was 878 lines at a cognitive complexity of 348
// against a 226 baseline, and the sizing showed only +27 of that +122 was new logic — the rest was nesting
// weight. Moving this block and the ceiling ladder out is the decomposition that lowers the number; renaming the
// body would only have moved the finding onto a new symbol, which is not a fix.
struct PackTaskJsonParts
{
    const IngestResult&                      ing;
    const LensRanking&                       lr;
    const PackTaskInputs&                    in;
    const std::string&                       task;
    PackTaskRenderFaults&                    renderFaults;    // a failed probe inside the tail records here
    const std::vector<float>&                rank;
    const std::vector<std::uint8_t>&         forClone;        // &p.forClone is the JsonSigLens clone lens
    const std::vector<NodeId>&               bodyIds;         // the candidate set, in rank order
    const D1Neighbors&                       d1;              // the key body's 1-hop callers
    const std::vector<std::string>&          d1SigRaw;        // their unescaped signatures, reused verbatim
    const rw::EmittedBodies&                 emittedBodies;   // what packBodies actually emitted
    const PackHead&                          head;            // the ranking's shown rows and its cut report
    const PackTaskSection&                   notes;
    const std::vector<std::pair<std::string, std::vector<std::pair<std::string, std::string>>>>& noteEntriesData;
    const std::vector<std::uint32_t>&        testFiles;
    std::vector<std::vector<std::uint32_t>>& testPartition;   // testRowsRendered takes its ADDRESS, so non-const
    const std::string&                       tailJson;        // the file tail's JSON twin, "" on a --partition slice
    const std::string&                       mentionNote;
    const std::string&                       boostNote;
    const std::string&                       sibliftNote;
    const std::string&                       expandNote;
    const std::string&                       docMentionNote;
    NodeId                                   keyId;
    std::size_t                              budgetTokens;
    std::size_t                              bundleBudget;
    std::size_t                              bodiesTotal;
    std::size_t                              bodiesKept;
    std::size_t                              callersTotal;
    std::size_t                              callersKept;
    std::size_t                              notesTotal;
    std::size_t                              notesKept;
    std::size_t                              testsTotal;
    std::size_t                              testsKept;
    const std::string&                       partnersJson;    // <partners>' JSON twin (packTaskPartnersJson), "" on a --partition slice
};

inline void packTaskJsonTail( std::string& j, const PackTaskJsonParts& p )
{
    // R-E (2026-08-17 harvest): the JSON dialect's pathRel — same rootArg every XML row above already used.
    const std::string       jRootPrefix = p.in.rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( p.in.rootArg );
    const auto               jPathRel   = [ & ]( std::uint32_t fileId ) -> std::string_view
    {
        return p.in.rootArg.empty() ? std::string_view( p.ing.files[ fileId ] ) : rw::sarif::rootRelativeUri( p.ing.files[ fileId ], jRootPrefix );
    };
    j = "{\"task\":\"" + jsonStr( p.task ) + "\"";
    if( !p.lr.routeNote.empty() )
    {
        j += ",\"route\":\"" + jsonStr( p.lr.routeNote ) + "\"";
    }
    // The scrub disclosure travels WITH the two fields it describes: `task` and `route` are XML-scrubbed
    // copies (xmlSafeByte maps C0 except \t\n\r to a space, invalid UTF-8 to '?'), and a consumer holding
    // only the JSON is owed that fact from the JSON. ctxRootJsonScrubKeys is ctxRootOpen's twin — same two
    // strings, same single predicate — so a call site cannot emit the field without the disclosure. Absent
    // on clean input, so no ordinary document moves a byte. This closes the residual bodydialectcheck's
    // arm (H) pinned as a SET; that arm is built to go RED when this lands, naming the pin to delete.
    j += ctxRootJsonScrubKeys( p.task, p.lr.routeNote );
    if( !p.lr.mentionNote.empty() )
    {
        j += ",\"mention\":\"" + jsonStr( p.lr.mentionNote ) + "\"";
    }
    if( !p.lr.boostNote.empty() )
    {
        j += ",\"boost\":\"" + jsonStr( p.lr.boostNote ) + "\"";
    }
    appendLiftJsonKeys( j, p.lr.sibliftNote, p.lr.expandNote );
    j += p.lr.capJson;                       // the --json twin of the root cap attrs; "" unless a cap fired
    if( !p.lr.docMentionNote.empty() )
    {
        j += ",\"doc_mention\":\"" + jsonStr( p.lr.docMentionNote ) + "\"";
    }
    // R-E follow-up (2026-08-19): the JSON dialect's OWN root disclosure. Every `p` in this tail was
    // already root-relative (the XML twin's root= is suppressed for --json), so a consumer holding only
    // the JSON had relative paths and nothing saying what they were relative to — the mirror of the
    // "root= with no legend" gap the round closed on the XML side. Same value, same single-root-only
    // condition, spelled as this dialect spells things. Absent on a multi-root run, exactly as root= is.
    if( !p.in.rootArg.empty() )
    {
        j += ",\"root\":\"" + jsonStr( p.in.rootArg ) + "\"";
    }
    // §B1.6: all THREE budget facts the XML header states ("budget=N bytes (T-token target, ceiling C)").
    // budget_ceiling_bytes was the one number with no JSON key — the hard byte ceiling the token target
    // implies, which is what a consumer checks the bundle against; budget_bytes is the WORKING budget
    // after the headroom factor, and is always the smaller of the two. Same expression as the XML line
    // below, so the two serializations cannot report different ceilings.
    { char b[ 128 ];  rw::formatTo( b, sizeof( b ), ",\"budget_tokens\":{},\"budget_bytes\":{},\"budget_ceiling_bytes\":{}",
                                     p.budgetTokens, p.bundleBudget, rw::declaredByteCeiling( p.budgetTokens )  );  j += b; }

    // PB1: the rows the XML <sigs> printed (head.shownIds), in score order — one selection, two shapes.
    j += std::string( ",\"ranking_capped\":" ) + ( p.head.capped ? "true" : "false" ) + ",\"ranking\":";
    const std::vector<float> shownRank   = buildMaskedRank( p.ing, p.rank, p.head.shownIds );
    // A FAILED RANKING RENDER IS `null`, NOT `[]`. renderPackHead clears shownIds when its render faults, so the
    // empty-list shortcut below would turn "this section could not be rendered" into "this section found nothing" —
    // two different answers, and CONTRIBUTING #3's rule is that a zero means none found, never none exists. The XML
    // twin already says it with <sigs render_failed="1">; the mask is the one fact both dialects read.
    const bool               rankingFailed = p.renderFaults.hasFailed( PackTaskRenderFaults::DisclosureWhy::RankingRenderFailed );
    const PackTaskRendered   rankingJson = rankingFailed ? PackTaskRendered{ "null", true }
                                         : p.head.shownIds.empty() ? PackTaskRendered{ "[]", true } : packTaskRender<PackTaskRenderFaults::DisclosureWhy::RankingRenderFailed>( [ & ]( std::FILE* m )
    {
        packSignaturesJson( m, p.ing, shownRank, int( p.head.shownIds.size() ),
                            JsonSigLens{ /*metrics=*/true, p.in.fanIn, p.in.impure, p.in.churn, &p.forClone,
                                         p.in.tested, p.in.amp, /*rankAdaptivePayload=*/true },
                            p.in.redact,   // §B0: the same redaction the XML <sigs> above already applied
                            /*budgetBytes=*/0, /*payloadBudgetBytes=*/0, /*outCapped=*/nullptr, /*outNotes=*/nullptr,
                            p.in.rootArg );
    }, p.in.renderFaults );
    j += rankingJson.ok ? rankingJson.text : std::string( "null" );   // null, never an empty value after its key

    // §H5 — the bodies the XML section ACTUALLY emitted, re-serialized. This used to re-slice the first
    // `bodies_kept` ids in RANK order, but packBodies emits grouped by FILE and stops on a BYTE budget, so
    // the two dialects reported different SETS under one bodies_kept — and packBodiesJson emitted each body
    // WHOLE, against no budget at all (MEASURED: XML 8 100 B vs JSON 42 200 B under a stated 11 800 B
    // ceiling). Both halves are gone by construction: there is one selection, and this is its record.
    // bodies_total IS THE XML'S total=, not the candidate count. The two dialects have to report the same cut or a
    // consumer reading the JSON sees a capped section where the XML says none: before this it read the 6-candidate
    // set against an XML total= of 1, and packtaskmonotoncheck's fill-floor arm (which reads the JSON) called a
    // bundle "capped" that nothing had cut. The candidates not served are bodies_next[], the <bn> rows' own twin.
    { char b[ 112 ];  rw::formatTo( b, sizeof( b ), ",\"bodies_total\":{},\"bodies_kept\":{},\"bodies_candidates\":{},\"bodies\":",
                                    p.keyId != kNoNode ? 1 : 0, p.emittedBodies.kept.size(), p.bodiesTotal  );  j += b; }
    const PackTaskRendered bodiesJson = packTaskRender<PackTaskRenderFaults::DisclosureWhy::BodiesRenderFailed>( [ & ]( std::FILE* m ) { packBodiesJson( m, p.ing, p.emittedBodies, p.in.rootArg ); },
                                                        p.in.renderFaults );
    j += bodiesJson.ok && !p.renderFaults.hasFailed( PackTaskRenderFaults::DisclosureWhy::BodiesRenderFailed ) ? bodiesJson.text : std::string( "null" );
    // PB1: the XML pointer rows' twin — the --expand of every candidate not served, key first when it was not
    if( p.bodiesKept < p.bodiesTotal )
    {
        j += ",\"bodies_next\":[";
        for( std::size_t i = p.bodiesKept == 0 ? 0 : 1, n = 0; i < p.bodyIds.size(); ++i, ++n )
        {
            j += std::string( n == 0 ? "" : "," ) + "\"" + jsonStr( packTaskExpandSelector( p.ing, p.bodyIds[i], p.in.rootArg ) ) + "\"";
        }
        j += "]";
    }
    if( p.renderFaults.failedMask != 0 )
    {
        j += ",\"render_failed\":\"" + p.renderFaults.names() + "\"";   // the sections a null above stands for, and any failed probe
    }

    const std::size_t callersShown = std::min( p.callersKept, p.d1.ids.size() );
    { char b[ 128 ];  rw::formatTo( b, sizeof( b ), ",\"callers_total\":{},\"callers_kept\":{},\"callers_of_top\":{},\"callers\":[",
                                     p.callersTotal, callersShown, p.keyId != kNoNode ? 1 : 0  );  j += b; }
    for( std::size_t i = 0; i < callersShown; ++i )
    {
        const Symbol& s = p.ing.symbols[ p.d1.ids[i] ];
        j += ( i == 0 ? "" : "," );
        j += "{\"t\":\"" + std::string( symTag( s.kind ) ) + "\",\"n\":\"" + jsonStr( s.name )
           + "\",\"p\":\"" + jsonStr( std::string( jPathRel( s.fileId ) ) ) + ":" + std::to_string( s.line )
           + "\",\"rel\":\"" + ( p.d1.isCaller[i] ? "caller" : "callee" ) + "\""
           // JSON twin of buildD1Row's XML shared= attribute — same economy rule (omitted at the
           // uncorroborated default of 1), composed from the SAME primitive overloadsAttr uses
           // (countFieldIfAbove, serialize.h) rather than re-deriving an equivalent ternary.
           + countFieldIfAbove( p.d1.shared[i], 1, ",\"shared\":" );
        if( !p.d1SigRaw[i].empty() )
        {
            j += ",\"sig\":\"" + jsonStr( p.d1SigRaw[i] ) + "\"";
        }
        j += "}";
    }
    j += "]";

    const std::size_t notesShown = std::min( p.notesKept, p.noteEntriesData.size() );
    { char b[ 96 ];  rw::formatTo( b, sizeof( b ), ",\"notes_total\":{},\"notes_kept\":{},\"notes\":[", p.notesTotal, notesShown );  j += b; }
    for( std::size_t i = 0; i < notesShown; ++i )
    {
        j += ( i == 0 ? "" : "," );
        j += "{\"target\":\"" + jsonStr( p.noteEntriesData[i].first ) + "\",\"notes\":[";
        const auto& raw = p.noteEntriesData[i].second;
        for( std::size_t k = 0; k < raw.size(); ++k )
        {
            j += std::string( k == 0 ? "" : "," ) + "{\"d\":\"" + jsonStr( raw[k].first ) + "\",\"text\":\"" + jsonStr( raw[k].second ) + "\"}";
        }
        j += "]}";
    }
    j += "]";
    // L3 follow-up (CodeRabbit 4053600616): the JSON twin of the XML root's notes_degraded= — absent on a
    // clean read, same condition droppedPositiveAttr above tests.
    if( p.in.notesDegraded )
    {
        j += std::string( notes::kNotesDegradedJsonKey );
    }

    // E1: tests_total/tests_kept count test FILES exactly as the XML section's total=/shown= do — one entry
    // per file on both sides of the cut. The JSON tail renders the SAME kept prefix through the SAME
    // partition the XML body was grouped by, so the two dialects cannot list different rows.
    { char b[ 96 ];  rw::formatTo( b, sizeof( b ), ",\"tests_total\":{},\"tests_kept\":{},\"tests_to_run\":[", p.testsTotal, p.testsKept );  j += b; }
    // §A9.5: the JSON sibling of the XML run= above — situ's tests_to_run already carries it, and one
    // computation path must not serialize two different obligations.
    const rw::TestRunnerIndex   jsonRunners( p.ing, p.in.rootArg );
    const auto                  jrun = [ & ]( std::string_view s ) { return jsonStr( s ); };
    const std::vector<rw::TestRowOut> jKeptRows = rw::testRowsOutOf( std::span( p.testFiles ).first( std::min( p.testsKept, p.testFiles.size() ) ), jPathRel );
    bool jFirstTest = true;
    for( const rw::RenderedTestRow& r : rw::testRowsRendered( jsonRunners, jKeptRows, rw::TestRowShape{ rw::RowDialect::Json, "p" }, jrun, &p.testPartition ) )
    {
        j += std::string( jFirstTest ? "" : "," ) + r.text;
        jFirstTest = false;
    }
    j += "]";
    j += p.partnersJson;   // <partners>: the same kept prefix the XML element printed, or partners_none
    j += p.tailJson;   // PB1: the file tail's JSON twin (forpage.h renderFileTailJson), the same shown count; "" on a partition slice

    // W3FIX M1 — the JSON sibling of the XML header's over_ceiling sentence. §B1.6 gave this dialect
    // budget_ceiling_bytes so a consumer could CHECK the bundle itself; that check silently fails on a long
    // task, because the envelope's own task echo is part of what it must measure. Absent ⇒ within the
    // ceiling (the silence-means-nothing-happened convention route/mention/boost use above), never "not
    // measured". Measured on the FINISHED document, so the key's own bytes are part of what it reports on.
    constexpr std::size_t kOverCeilingKeyBytes = 22;   // `,"over_ceiling":true` + the closing brace
    if( !p.in.softTarget && j.size() + kOverCeilingKeyBytes > rw::ceilingAllowanceBytes( p.budgetTokens ) )   // forbudget-soft: never on a soft target
    {
        j += ",\"over_ceiling\":true";
    }
    j += "}";
}

// ── SETTLING THE ROOT: THE CEILING LADDER AND THE PRICED ROOT ATTRIBUTES ─────────────────────────────────────
// The last step of the assembly, and its own function since the owner's 2026-11-19 ruling on this lane: given the
// finished document and the header it was built with, climb the ceiling ladder, splice the priced root attributes
// the chosen rung implies, and (on a caller-spliced tail) define est_measured= inside the root it qualifies.
// Six inputs and NO parts record: this block reads only the ranking's route note, the bundle's inputs, the token
// budget, the header it has, and the header BUILDER — which arrives as a template parameter because
// climbCeilingLadderBy already takes it as a callable, so nothing here needs std::function or an allocation.
template<class BuildHeaderFn>
inline void packTaskSettleRoot( std::string& whole, const std::string& headerStr, BuildHeaderFn&& buildHeader,
                                const LensRanking& lr, const PackTaskInputs& in, std::size_t budgetTokens )
{
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
    // F2 (capture-audit verify-wave2 2026-09-05): over_ceiling= is no longer "the ladder's last rung
    // fired" — it is the PROPERTY the root's own two numbers state. --pack-task carried the same defect
    // --for did, measured on w3fixbudgetcheck's corpus: `budget_tokens="1200" est_tokens="1215"` and
    // `budget_tokens="1600" est_tokens="1713"`, both unlabelled, because the last rung had not fired.
    // Same rule, same unit, both task lenses: over_ceiling="1" whenever est_tokens > budget_tokens.
    // The number is read back through pricedRootAttr's outTokens, so the decision is made from the
    // number the root will PRINT and never from a second estimate.
    const auto rootAttrsFor = [ & ]( const std::string& doc, bool lastRungFired ) -> std::string
    {
        // PB1 — ONE CONVERSION. The budget is converted to bytes at kMinBytesPerToken (x kBudgetHeadroom, the fill line),
        // and est_tokens= used to price the result at 2.50 for markup and 3.80 for bodies: SUB1's 52 answers spent 91% of
        // their bytes and read est_tokens 3,975 of budget_tokens 6000 — a third unspent in tokens. The root now prices
        // every delivered byte at the rate the budget was converted at, so a full bundle reads ~90% of its budget and
        // est_tokens > budget_tokens exactly when the bytes pass declaredByteCeiling. It is an upper bound (the densest
        // language's rate), the same side of the error every budget here is sized on.
        std::size_t       estTokens   = 0;
        std::string       attrs       = rw::pricedRootAttrTokens( doc.size() + in.trailingSectionBytes, rw::kMinBytesPerToken, 0, &estTokens );
        attrs += " budget_tokens=\"" + std::to_string( budgetTokens ) + "\"";
        // forbudget-soft: a soft target (the caller's own budget) is never "over"; the default budget keeps the label
        if( !in.softTarget && ( lastRungFired || ( budgetTokens > 0 && estTokens > budgetTokens ) ) ) { attrs += " over_ceiling=\"1\""; }
        if( in.isTrailingUncharged ) { attrs += " est_measured=\"0\""; }   // defined by the comment spliced in below
        return attrs;
    };
    const std::size_t             rootAttrsBound = rootAttrsFor( whole, /*lastRungFired=*/true ).size();
    // L1 fix round: under the compact posture a rung fits when the DELIVERED document does — the candidate header plus
    // the rendered sections, its widest root attributes spliced, compacted by the layer that will print it.
    const std::string restOfWhole = in.compactLegend ? whole.substr( headerStr.size() ) : std::string();
    const auto deliveredFits = [ & ]( std::size_t ceiling )
    {
        return [ &, ceiling ]( std::string_view header )
        {
            std::string candidate = std::string( header ) + restOfWhole;
            rw::spliceRootAttrs( candidate, rootAttrsFor( candidate, /*lastRungFired=*/true ) );
            const std::size_t delivered = rw::compactDeliveredBytes( candidate, "pack-task" );
            return ( delivered > 0 ? delivered : candidate.size() ) + in.trailingSectionBytes <= ceiling;
        };
    };
    // The FREE rung (drop the task echo) buys nothing here: the echo lives in prose the compact layer never delivers, so
    // judging the as-built header at the exact ceiling would take a rung whose note claims a drop the reader cannot
    // see. Under the compact posture the as-built answer stands when it fits the allowance; route= (a delivered root
    // attribute) and the over_ceiling rung keep their meaning (compactlegendcheck (FX4)).
    // forbudget-soft: a soft target climbs no ladder — the header as built ships (echo, route= and every clause)
    const rw::CeilingLadderChoice chosen = in.softTarget ? rw::CeilingLadderChoice{ headerStr, rw::CeilingRung::AsBuilt }
                                         : in.compactLegend && !in.innerBundle
        ? rw::climbCeilingLadderBy( buildHeader, headerStr, deliveredFits( rw::ceilingAllowanceBytes( budgetTokens ) ),
                                    deliveredFits( rw::ceilingAllowanceBytes( budgetTokens ) ), /*hasRouteAttr=*/!lr.routeNote.empty(), kNotes )
        : climbCeilingLadder( buildHeader, headerStr,
                                                               whole.size() - headerStr.size() + in.trailingSectionBytes + rootAttrsBound,
                                                               // TWO CEILINGS (PR #215 review item 1). This root labels itself
                                                               // over_ceiling="1" on `estTokens > budgetTokens` — priced at
                                                               // kBytesPerTokenDefault — while every rung was judged at
                                                               // kMinBytesPerToken x 1.15, so this lens had --for's defect in the
                                                               // same words: a bundle whose root will say it overflowed kept its
                                                               // verbatim task echo because the echo rung was against a ceiling
                                                               // 15% looser than the verdict. The free rungs now aim at what the
                                                               // root promises; route= and the label keep the tolerance.
                                                               rw::declaredByteCeiling( budgetTokens ),   // PB1: the ceiling est_tokens= is priced against
                                                               rw::ceilingAllowanceBytes( budgetTokens ),
                                                               /*hasRouteAttr=*/!lr.routeNote.empty(), kNotes );
    if( chosen.header != headerStr )
    {
        whole.replace( 0, headerStr.size(), chosen.header );
    }
    // M3 (0.6.1): the rung ARRIVES, and is never recovered from the chosen text. This read
    // `chosen.find( "over_ceiling:" ) != npos` — the marker word from kNotes, 13 characters, searched for in
    // a header that echoes the caller's task VERBATIM by contract. So `--token-budget=100000
    // --pack-task='why does over_ceiling: fire on this root'` shipped `est_tokens="11329"
    // budget_tokens="100000" over_ceiling="1"`: a root labelled over a ceiling it states itself to be 9x
    // inside, decided by the caller's own words. The same task without the colon carried no label, which is
    // what makes it a forgery rather than a coincidence. --for had this defect and had it fixed; this lens
    // shared the ladder and kept it, because the fixed-payload wrapper returned only a string. It returns the
    // rung now (serialize.h CeilingLadderChoice). The token comparison beside it is unchanged and is still
    // what labels an honest overshoot the ladder did not fire on. Gate: test/ceilingverdictcheck.sh (6)-(8).
    rw::spliceRootAttrs( whole, rootAttrsFor( whole, chosen.rung == rw::CeilingRung::OverCeiling ) );
    if( in.isTrailingUncharged )
    {
        // est_measured= is defined where it is met: the clause rides first inside the root it qualifies
        const std::size_t rootOpenEnd = whole.find( '>', whole.find( "<ctx" ) );
        ASSUME( rootOpenEnd != std::string::npos );   // this function composed the <ctx …> start tag itself, above
        whole.insert( rootOpenEnd + 1, rw::kEstModelledLegend );
    }
}
}

// ── <partners>: the files that historically change WITH the files this task will touch ───────────────────────────────────
// The files an agent is likely to FORGET: across 752 real bug-fix commits the median fix edits two files, and developers
// miss a related change 45.7% of the time (research/RESEARCH_AUDIT_1126_*). The block is --situ's [3] turned around: the
// seeds are not a diff but the ranking's first kCoBoostSeedCount distinct files (the key body's file first), and their
// partners are merged by --situ's own rule (situ.h mergeSeedPartners). Names and support counts only — never a body.
//
// THE WINDOW is the co-change boost's, the last kCoBoostCommitWindow commits (gitRecentCommitFileSets), not --situ's 18
// months: it is bounded on any repo (a date window read kubernetes' 12.8 K commits in 1.0 s, on every bundle) and a pure
// function of HEAD, so the block does not move with the wall clock. The walk is a signal walk, so #777's bot policy applies,
// and the element states THIS walk's own counts (bots_skipped=/agent_commits=/renames=, gitLogFileSets' outHistory) inside
// the budget. Not #777's trailing sentence: it is 618 B outside the budget (packtaskcheck's ceiling arm breached on it at
// --token-budget=2000, 5,737 B against 5,428 B), and its process-wide maximum is never reset in the MCP server.
//
// THE BUDGET. The six shares already sum to 100, so the block has no share of its own: it is granted up to
// kPackTaskPartnersCapPct of the post-header budget, out of what the pool's sections left and then the tail's reserve, just
// before the tail is filled, and it tops up in the reflow lap like the list sections. MEASURED on this repo at the default
// budget: granted only the pool's leftover, a real task served 0 of its 4 partners (the head and tail spend everything), so
// it draws on the tail too. The tail's floor is then 20% less the block's bytes (at most 3 points, a few tail rows), and only
// on a tree with history: packtailsharecheck's fixture has none, so its floor arms are unchanged. A cut is
// disclosed on the element (shown= of total=, partners_cut=); the shell is emitted even when no row fits, because the
// element IS the disclosure.
//
// NO BLOCK, AND WHY — one root attribute, partners_none=: no_git (no repository above the root), no_history (the window
// held no commit touching an indexed file), shallow (a depth-limited clone whose window held none), multi_root (no one
// root to walk), no_seed (nothing ranked). Mined with no partner found is a MEASUREMENT, so it is the element with
// total="0", never the attribute — and so is a window whose commits the bulk cut took (bulk_skipped=N: every commit over
// 30 indexed files is left out, as in every co-change miner here, and the element counts them rather than hiding it). A --partition slice carries neither: the outer document has no per-slice history.
inline constexpr std::size_t kPackTaskPartnersCapPct = 3;
struct PackPartners
{
    std::vector<SeedPartner> rows;          // mergeSeedPartners' order: (best seed's deg desc, path asc)
    std::size_t              commits = 0;   // commits the window held (after the 30-file bulk cut)
    std::uint32_t            bulkSkipped = 0;   // commits the bulk cut left out (touched more than 30 indexed files): bulk_skipped=
    GitHistoryCensus         history;           // THIS walk's #777 policy counts: bots_skipped= (bots_included=), agent_commits=, renames=
    std::uint32_t            seeds   = 0;   // distinct seed files probed
    bool                     tail    = false;   // one seed: the corroborated tail applied (floor_tail="corroborated", why= per row)
    bool                     shallow = false;
    bool                     mined   = false;   // the block renders
    std::string_view         none;              // why it does not, when it does not ("" on a --partition slice)
};

inline PackPartners packTaskPartners( const IngestResult& ing, const Graph& g, const std::vector<NodeId>& order, const std::vector<float>& rank,
                                      NodeId keyId, const PackTaskInputs& in )
{
    PackPartners out;
    if( in.innerBundle )
    {
        return out;
    }
    if( in.rootArg.empty() )
    {
        out.none = "multi_root";
        return out;
    }
    const std::string root( in.rootArg );
    if( !hasEnclosingGitRepo( root ) )
    {
        out.none = "no_git";
        return out;
    }
    std::vector<char> seedMask( ing.files.size(), 0 );
    const auto        addSeed = [ & ]( NodeId id )
    {
        if( id >= ing.symbols.size() || ing.symbols[id].fileId >= seedMask.size() || seedMask[ ing.symbols[id].fileId ] != 0 )
        {
            return;
        }
        seedMask[ ing.symbols[id].fileId ] = 1;
        ++out.seeds;
    };
    addSeed( keyId );
    for( std::size_t i = 0; i < order.size() && out.seeds < kCoBoostSeedCount && rank[ order[i] ] > 0.0f; ++i )
    {
        addSeed( order[i] );
    }
    if( out.seeds == 0 )
    {
        out.none = "no_seed";
        return out;
    }
    CommitWindowCensus census;   // the bulk cut is a cut: counted here and disclosed as bulk_skipped= on the element
    const auto         sets = gitRecentCommitFileSets( root, ing, kCoBoostCommitWindow, kCoBoostMaxFilesPerCommit, UINT32_MAX, &census, &out.history );
    out.commits     = sets.size();
    out.bulkSkipped = census.bulkDropped;
    out.shallow     = gitstamp::isShallow( root );
    if( sets.empty() && out.bulkSkipped == 0 )   // a window whose every commit was bulk is a MEASUREMENT (total="0" bulk_skipped=N), not "no history"
    {
        out.none = out.shallow ? "shallow" : "no_history";
        return out;
    }
    CoCouplingCache coupling( ing );
    SeedPartners merged = mergeSeedPartners( ing, seedMask, sets, kCoBoostSeedCount, coupling, &g );
    out.rows  = std::move( merged.rows );
    out.tail  = merged.tail;
    out.mined = true;
    return out;
}

// #777's history_policy counts for THIS walk, present-only, in #777's own names: bots_skipped= (bots_included= under
// --include-bots), agent_commits=, renames=. One spelling for both dialects: XML passes `="`/`"`, JSON `":`/"" (keys partners_*).
inline std::string packTaskPartnersPolicyAttrs( const GitHistoryCensus& h, std::string_view open, std::string_view close )
{
    std::string out;
    const auto  add = [ & ]( std::string_view name, std::uint32_t n )
    {
        if( n > 0 )
        {
            out += open == "=\"" ? " " : ",\"partners_";
            out.append( name );
            out.append( open );
            out += std::to_string( n );
            out.append( close );
        }
    };
    add( gitIncludeBots() ? "bots_included" : "bots_skipped", h.botCommits );
    add( "agent_commits", h.agentCommits );
    add( "renames", h.exactMoves );
    return out;
}

// The rows, rendered once (the budget and the reflow lap re-cut the same entries).
template <class EscFn>
inline std::vector<std::string> packTaskPartnerRows( const IngestResult& ing, const PackPartners& pp, std::string_view rootArg, EscFn&& ex )
{
    std::vector<std::string> rows;
    rows.reserve( pp.rows.size() );
    const std::string prefix = rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( rootArg );
    for( const SeedPartner& p : pp.rows )
    {
        const std::string_view path = rootArg.empty() ? std::string_view( ing.files[ p.fileId ] ) : rw::sarif::rootRelativeUri( ing.files[ p.fileId ], prefix );
        rows.push_back( "<f p=\"" + ex( path ) + "\" together=\"" + std::to_string( p.together ) + "\""
                        + ( pp.tail ? " why=\"" + std::string( coWhyName( p.why ) ) + "\"" : std::string() ) + "/>" );
    }
    return rows;
}

// The element at `budget`: the list section's cut, partners_cut= when it dropped a row, and the bare shell (still
// counting total=) when not one row fits. "" only when the block is not mined.
inline PackTaskSection packTaskPartnersSection( const PackPartners& pp, const std::vector<std::string>& rows, std::size_t budget )
{
    if( !pp.mined )
    {
        return {};
    }
    char extra[ 240 ];
    rw::formatTo( extra, sizeof( extra ), " window=\"{} commits\" commits=\"{}\" seeds=\"{}\" floor=\"{}\"{}{}{}{}", kCoBoostCommitWindow, pp.commits, pp.seeds, kCoSupportFloor,
                  pp.tail ? " floor_tail=\"corroborated\"" : "",
                  pp.bulkSkipped > 0 ? " bulk_skipped=\"" + std::to_string( pp.bulkSkipped ) + "\"" : std::string(),
                  packTaskPartnersPolicyAttrs( pp.history, "=\"", "\"" ), gitstamp::shallowAttr( pp.shallow ) );
    const std::string cutAttr   = " partners_cut=\"" + std::to_string( rows.size() ) + "\"";
    const std::string shellOpen = "<partners" + std::string( extra ) + " shown=\"0\" total=\"" + std::to_string( rows.size() ) + "\" capped=\""
                                + ( rows.empty() ? "0\"" : "1\"" + cutAttr ) + ">";
    // the wrapper's worst case: the shell's open tag (its partners_cut= at the widest count) plus the close tag
    const std::size_t wrapReserve = shellOpen.size() + std::string_view( "</partners>" ).size();
    PackTaskSection   section     = packTaskListSection( "partners", extra, rows, budget, wrapReserve );
    if( section.xml.empty() )
    {
        section.xml  = shellOpen + "</partners>";
        section.kept = 0;
        return section;
    }
    if( section.kept < rows.size() )
    {
        std::string open = section.xml.substr( 0, section.xml.find( '>' ) + 1 );
        setOpenTagAttr( open, "partners_cut", std::to_string( rows.size() - section.kept ) );
        section.xml.replace( 0, section.xml.find( '>' ) + 1, open );
    }
    return section;
}

// The JSON twin: the same kept prefix, or the same partners_none reason. "" on a --partition slice.
inline std::string packTaskPartnersJson( const IngestResult& ing, const PackPartners& pp, std::size_t kept, std::string_view rootArg )
{
    if( !pp.mined )
    {
        return pp.none.empty() ? std::string() : ",\"partners_none\":\"" + std::string( pp.none ) + "\"";
    }
    std::string j;
    { char b[ 300 ];  rw::formatTo( b, sizeof( b ), ",\"partners_window\":\"{} commits\",\"partners_commits\":{},\"partners_seeds\":{},\"partners_floor\":{}{},\"partners_total\":{},\"partners_kept\":{}{}{}",
                                    kCoBoostCommitWindow, pp.commits, pp.seeds, kCoSupportFloor, pp.tail ? ",\"partners_floor_tail\":\"corroborated\"" : "", pp.rows.size(), kept,
                                    pp.bulkSkipped > 0 ? ",\"partners_bulk_skipped\":" + std::to_string( pp.bulkSkipped ) : std::string(),
                                    pp.shallow ? ",\"partners_shallow\":true" : "" );  j += b; }
    j += packTaskPartnersPolicyAttrs( pp.history, "\":", "" );
    j += ",\"partners\":[";
    const std::string prefix = rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( rootArg );
    for( std::size_t i = 0; i < kept && i < pp.rows.size(); ++i )
    {
        const std::string_view path = rootArg.empty() ? std::string_view( ing.files[ pp.rows[i].fileId ] ) : rw::sarif::rootRelativeUri( ing.files[ pp.rows[i].fileId ], prefix );
        j += std::string( i == 0 ? "" : "," ) + "{\"p\":\"" + jsonStr( path ) + "\",\"together\":" + std::to_string( pp.rows[i].together )
           + ( pp.tail ? ",\"why\":\"" + std::string( coWhyName( pp.rows[i].why ) ) + "\"" : std::string() ) + "}";
    }
    j += "]";
    return j;
}

// The block as the assembler carries it, and its three turns there — the grant before the tail, the reflow lap, and the ledger +
// root disclosure — each its own function so the assembler spends one line per turn (its complexity is the gated number).
struct PackPartnersBlock
{
    PackPartners             data;
    std::vector<std::string> rows;
    std::size_t              budget = 0;
    PackTaskSection          section;   // "" unless data.mined
};

// The first lap: up to the cap, out of `remaining`, charged by monotoneRoll (its candidate set never depends on budgetTokens and
// `remaining` is non-decreasing in it, so the kept count is monotone). Returns what is left.
inline std::size_t grantPackPartners( PackPartnersBlock& b, std::size_t remaining, std::size_t quotaBase )
{
    if( !b.data.mined )
    {
        return remaining;
    }
    b.budget                = std::min( remaining, quotaBase * kPackTaskPartnersCapPct / 100 );
    b.section               = packTaskPartnersSection( b.data, b.rows, b.budget );
    const MonotoneRoll roll = monotoneRoll( b.section.kept < b.rows.size(), b.budget, b.section.xml.size() );
    return remaining > roll.charge ? remaining - roll.charge : 0;
}

// The reflow lap's turn: reflowListSection's rule over this block's own cut. Returns what it passes on.
inline std::size_t reflowPackPartners( PackPartnersBlock& b, std::size_t reflow )
{
    if( reflow == 0 || !b.data.mined || b.section.kept >= b.rows.size() )
    {
        return reflow;
    }
    b.budget += reflow;
    b.section = packTaskPartnersSection( b.data, b.rows, b.budget );
    return b.section.kept < b.rows.size() || b.budget <= b.section.xml.size() ? 0 : b.budget - b.section.xml.size();
}

// The ledger clause (the other sections' "kept K of T" wording) and, when there is no block, the root's partners_none=.
inline void notePackPartners( const PackPartnersBlock& b, std::string& report, std::string& rootAttrs )
{
    if( b.data.mined )
    {
        const std::size_t total = b.rows.size(), kept = b.section.kept;
        report += " | partners: " + ( total == 0 ? std::string( "none" )
                                                 : ( kept < total ? "kept " : "" ) + std::to_string( kept ) + " of " + std::to_string( total ) );
        return;
    }
    if( !b.data.none.empty() )
    {
        rootAttrs += " partners_none=\"" + std::string( b.data.none ) + "\"";   // why there is no <partners> (PackPartners)
    }
}

// The full legend's reading, rows-gated like the run= clause: present exactly when the element or the root attribute is.
inline constexpr std::string_view kPackPartnersLegend =
    " partners (after tests, before the tail): files that changed in the same commits as the ranking's first seeds= distinct "
    "files (not the seeds), the ones a change there usually also edits; <f p= together=>: together= commits it shares with its "
    "best seed (floor= or more, 3), rows by that seed's share of commits; floor_tail=corroborated (one seed): the list is filled to 10 with partners sharing "
    "2 commits that are corroborated, below every other row, and each row's why= says which: support (3+), confidence (in at least half the seed's commits) "
    "or link (an include, import or call edge either way, a test-of pair, or the same directory of 20 files or fewer); window= commits= the history read; bulk_skipped=N commits left out "
    "for touching over 30 indexed files; bots_skipped=N (bots_included= under include-bots) bot-authored commits left out, "
    "agent_commits=N kept commits a coding agent co-authored, renames= the exact file moves followed (each present when nonzero); shallow=1 a depth-limited clone, so a floor; up to 3 pct of the budget, out of what the sections above left, then the tail's; "
    "partners_cut=N rows the budget cut. ";
inline constexpr std::string_view kPackPartnersNoneLegend =
    " partners_none= why no partners block: no_git (no repository), no_history (no commit in the window touched an indexed "
    "file), shallow (a depth-limited clone with none), multi_root (no single root), no_seed (nothing ranked). ";
inline std::string_view packTaskPartnersLegend( const PackPartners& pp )
{
    return pp.mined ? kPackPartnersLegend : pp.none.empty() ? std::string_view() : kPackPartnersNoneLegend;
}

// THE bundle assembler: builds the budget-shared bundle (ranking > key body > callers > notes > tests > file tail) for
// `task`, given an already-computed LensRanking, and returns the whole <ctx>…</ctx> XML document as a string — never
// touches stdout (the caller owns the sink: the CLI fwrites it, MCP wraps it as a JSON-RPC text result). The Q3
// clone-membership lens (`forClone`) is computed HERE, once, from `ing` alone (findClones needs no git) — both callers
// get identical clone data with zero duplicated logic.
// `surfaceOut`, when given, receives the ids this bundle actually NAMES — its shown ranking rows ∪ its body candidates
// (the key body and the pointers) ∪ the key body's 1-hop callers. §6 --partition measures cross-bundle overlap from it,
// so the number it reports is derived from the same selection the XML was rendered from rather than a re-derivation.
// It is the PRE-budget-trim callers list (a trimmed section names slightly fewer) — an honest ceiling, documented as one.
inline std::string packTaskBundleText( const IngestResult& ing, const Graph& g, const std::string& task,
                                       const LensRanking& lr, const PackTaskInputs& inArg,
                                       std::string* jsonOut = nullptr, std::vector<NodeId>* surfaceOut = nullptr,
                                       std::size_t* testsKeptOut = nullptr, std::uint8_t* bodyReadingsOut = nullptr )
{
    // P2.4 — reuse-count self-supply. --pack-task's CLI/MCP call-sites only compute fan-in when --for or
    // --metrics was ALSO given, so the bundle used to print in="0" on every row while --for reported the real
    // count for the same symbol in the same run. The in-edge CSR is already built and sitting in `g`, so the
    // honest value costs one O(symbols) pass over rowOffsets — no second graph pass, no git, no ingest.
    // `localFanIn` is declared BEFORE `in` so it outlives the pointer `in` holds into it.
    std::vector<std::uint32_t> localFanIn;
    PackTaskInputs             in = inArg;
    PackTaskRenderFaults       renderFaults;   // every section render below records into it (see PackTaskRenderFaults)
    in.renderFaults                   = &renderFaults;
    if( !in.fanIn ) { localFanIn = fanInFromInEdges( ing, g );  in.fanIn = &localFanIn; }

    const std::vector<float>& rank     = lr.rank;
    in.calleeRank                      = &rank;   // this bundle HAS a query: its bodies' <calls> listings are cut by relevance, not by node id
    // PB1: --for's 40-row head; a --partition slice passes its own (kPackTaskRankTopN, the slice window)
    const int                 rankTopN = in.rankTopN > 0 ? int( in.rankTopN ) : kPackTaskHeadRows;

    // top ranked ids (score desc, id asc). Body candidates = the key body, then the top heads with a POSITIVE score.
    std::vector<NodeId> order( ing.symbols.size() );
    for( NodeId i = 0; i < order.size(); ++i )
    {
        order[i] = i;
    }
    sortutil::radixSortByScoreDescId( order, rank );
    const NodeId              keyId   = packTaskKeyBody( ing, in.keyBody, rank, packTaskBodyCandidates( ing, order, rank, kNoNode ) );
    const std::vector<NodeId> bodyIds = packTaskBodyCandidates( ing, order, rank, keyId );

    // PB1: the <callers> section is the key body's own 1-hop CALLERS — its wiring sites. Its callees already ride the body's
    // <calls> listing, and the other candidates' neighbourhoods went with their bodies (each is a next= pointer now).
    std::vector<char> d0Mark( ing.symbols.size(), 0 );
    if( keyId != kNoNode )
    {
        d0Mark[keyId] = 1;
    }
    D1Neighbors d1;
    {
        const D1Neighbors both = computeD1Neighbors( ing, g, keyId != kNoNode ? std::vector<NodeId>{ keyId } : std::vector<NodeId>{}, d0Mark );
        for( std::size_t i = 0; i < both.ids.size(); ++i )
        {
            if( both.isCaller[i] != 0 )
            {
                d1.ids.push_back( both.ids[i] );  d1.isCaller.push_back( 1 );  d1.shared.push_back( both.shared[i] );
            }
        }
    }

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
    // PATH-FROM-UPSTREAM's clause leaves the prose note for its own data comment (PackTaskHeaderParts::pathFromNote)
    const std::size_t pathFromAt     = lr.mentionNote.find( " [path from: " );
    const std::size_t pathFromEnd    = pathFromAt == std::string::npos ? std::string::npos : lr.mentionNote.find( ']', pathFromAt );
    const std::size_t pathFromLen    = pathFromEnd == std::string::npos ? 0 : pathFromEnd + 1 - pathFromAt;
    const std::string pathFromNote   = pathFromLen == 0 ? std::string() : xmlCommentText( std::string_view( lr.mentionNote ).substr( pathFromAt, pathFromLen ) );
    const std::string mentionNote    = xmlCommentText( pathFromLen == 0 ? lr.mentionNote
                                                                        : std::string( lr.mentionNote ).erase( pathFromAt, pathFromLen ) );
    const std::string boostNote      = xmlCommentText( lr.boostNote );
    const std::string sibliftNote    = xmlCommentText( lr.sibliftNote );
    const std::string expandNote     = xmlCommentText( lr.expandNote );
    // …plus the indexing-cap clause, which rides the LAST note so it reads after the boosts it qualifies.
    // "" on every run where no cap fired, and charged exactly here like every other user-length part.
    const std::string docMentionNote = xmlCommentText( lr.docMentionNote + lr.capNote );

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
                                  + mentionNote.size() + boostNote.size() + sibliftNote.size() + expandNote.size() + docMentionNote.size()
                                  + ( pathFromNote.empty() ? 0 : pathFromNote.size() + 8 ) + in.trailingSectionBytes;
    std::size_t       remaining   = bundleBudget > headerFloor ? bundleBudget - headerFloor : 1;

    // F1 — the kPackTaskQuota*Pct shares above, applied to `quotaBase` (see their own comment for why). `carry`
    // (threaded through sections 1-4 below) is an under-filled section's unspent quota, rolled FORWARD.
    const std::size_t quotaBase = remaining;
    // The tail's floor, taken off the spendable pool before the first section is granted anything. quotaBase stays
    // the FULL post-header budget so every other share keeps its own percentage of it (45+20+8+2+5 = 80 = the pool
    // that is left once the tail's 20 is reserved, so nothing is over-committed by construction).
    const std::size_t tailReserve = in.innerBundle ? 0u
                                  : std::min( remaining, quotaBase * std::size_t( kPackTaskQuotaTailPct ) / 100 );
    remaining = remaining > tailReserve ? remaining - tailReserve : 0;
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

    // ── section 1 — the ranking: --for's head (PB1; renderPackHead above). The text-shrink steps aim at the section's
    //    share; rows are dropped only past kPackTaskHeadRowDropPct, so a long head keeps its rows and the cut it takes is
    //    shown=/total=/capped= on <sigs> with the call that serves it uncut (next=).
    const std::size_t   sigsBudget = sectionBudget( kPackTaskQuotaRankingPct, /*carryIn=*/0 );
    const std::size_t   rowDropBudget = std::max( sigsBudget, std::min( remaining, quotaOf( kPackTaskHeadRowDropPct ) ) );
    // THE HEAD'S RULES ARE THE LENS'S, NOT THE CALLER'S BUDGET'S. Passing the caller's explicit budget here made
    // `--pack-task --token-budget=6000` serve different sections from the DEFAULT --pack-task, whose budget is also
    // 6000: forHeadRoundRobinOn() reads the ceiling and returns false at 6000, so the default (which passed 0) emitted
    // files_first= and the explicit twin did not. That contradicts this verb's documented contract — "an explicit 6000
    // serves the default's sections byte for byte" (kPackTaskHardBudgetSentence's own comment) — and forsoftbudgetcheck
    // (P2) pins it. It also silently disabled, for every explicit budget, the head round robin by file that PT1 measured
    // as one of D1's two locating mechanisms.
    // 0, not budgetTokens, because the DEFAULT's verdicts are the ones both paths must share and the default has no
    // caller budget to read. The byte budget still cuts the section; these predicates only decide whether the head
    // spends bytes on e=, the docs reorder and the round robin, and that decision is the same bundle either way.
    const SigLensRules  headRules  = packTaskHeadRules( ing, task, lr, 0u );
    PackHead head = renderPackHead( ing, rank, PackHeadInputs{ rankTopN, rowDropBudget, headRules, task, &in, &forClone } );
    const std::string& sigsStr    = head.sigsStr;   // a reference: the head's reflow lap below may widen it
    const bool         sigsCapped = head.capped;     // the FIRST lap's verdict — what the section shares were charged by
    // §W2-K: monotoneRoll (see its own comment) — when ranking is NOT capped its consumed bytes are a fixed constant and its
    // unspent share safely rolls forward; when capped, at least the whole granted share is charged and nothing rolls forward.
    const MonotoneRoll sigsRoll = monotoneRoll( sigsCapped, sigsBudget, sigsStr.size() );
    remaining = remaining > sigsRoll.charge ? remaining - sigsRoll.charge : 0;
    std::size_t carry = sigsRoll.carry;

    // ── section 2 — the key body, and a next= pointer for every other candidate. DECLARED here (the emit order is fixed:
    //    sigs, bodies, callers, notes, tests, tail) but ALLOCATED after tests — see "§W2-K.2 (K2): the allocation order".
    std::string        bodiesStr;
    rw::EmittedBodies emittedBodies;
    const std::size_t  bodiesTotal = bodyIds.size();
    std::size_t        bodiesKept  = 0;
    std::uint8_t       bodyReadings = 0;   // kBodyReading* bits the kept bodies carry: partition.h's outer-legend gate

    // ── section 3 — the key body's 1-hop callers (computed above), each shown with its OWN one-line SIGNATURE + its
    //    declaration site — never a full body. of_top= is the anchor count: 1 (the key body), 0 when there is none.
    const D1Rows d1Rendered = renderD1CallerRows( ing, d1, ex, in.redact, in.rootArg );
    const std::vector<std::string>& callerRows = d1Rendered.xml;
    const std::vector<std::string>& d1SigRaw   = d1Rendered.rawSig;   // unescaped — the L2 --json tail reuses these verbatim
    char callersAttr[ 32 ];  rw::formatTo( callersAttr, sizeof( callersAttr ), " of_top=\"{}\"", keyId != kNoNode ? 1 : 0 );
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
    std::vector<std::uint32_t>              testFiles;      // hoisted for the L2 --json tail below
    std::vector<rw::TestRowOut>             ptRows;         // the seam's row values — one per test FILE, the unit the section cuts in
    std::vector<std::vector<std::uint32_t>> testPartition;  // E1: the KEPT prefix's single/group partition, reused by the JSON tail so both dialects serve the same rows
    std::size_t       testsBudget = sectionBudget( kPackTaskQuotaTestsPct, carry );
    {
        std::vector<NodeId> testSeeds;
        for( NodeId b : bodyIds )
        {
            if( b < ing.symbols.size() && !rw::isTestPath( rw::rootRelPath( ing, ing.symbols[b].fileId ) ) )
            {
                testSeeds.push_back( b );
            }
        }
        if( testSeeds.empty() )
        {
            testSeeds = bodyIds;
        }
        // DELIBERATELY NOT --affected's row set, and not testmap.h::affectedAnswerForFile. That answers
        // "which tests cover this CHANGE"; the seeds here are the top-RANKED bodies of a task bundle, which
        // is a different question: `changed=` is meaningless for them, and "partner of a ranked file" would
        // be a claim nothing supports. The edit receipt was unified with --affected (2026-09-09) precisely
        // because it DOES answer the same question and had drifted; this one must not be "fixed" to match.
        // NOT a clean bill of health: the fallback above (testSeeds = bodyIds when every ranked body is
        // itself a test) has the SAME reached-minus-seeds blind spot the receipt just lost — a test among
        // the seeds cannot appear in its own reach. That is worth fixing on its own terms; it is the
        // UNIFICATION that is refused here, not the defect.
        const std::vector<NodeId>  reach = transitiveCallers( g, testSeeds );
        std::vector<char>          fseen( ing.files.size(), 0 );
        for( NodeId n : reach )
        {
            const std::uint32_t f = ing.symbols[n].fileId;
            if( f < fseen.size() && !fseen[f] && rw::isTestPath( rw::rootRelPath( ing, f ) ) ) { fseen[f] = 1;  testFiles.push_back( f ); }
        }
        std::sort( testFiles.begin(), testFiles.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );
        // §A9.5 / §P11.4: the one-call bundle names the tests you owe; it now also names how to RUN them,
        // from the same TestRunnerIndex --affected / --situ / --test-gate / --exercises read. Built here,
        // inside the section's scope, because it is lazy — a bundle with no test row reads no runner script.
        // §B14 — std::string rows, not char[512]: a row carries TWO unbounded interpolands (the test path AND
        // the runner command), so it was the widest of the six breaching sites.
        const std::string ptPrefix = in.rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( in.rootArg );
        ptRows = rw::testRowsOutOf( testFiles, [ & ]( std::uint32_t f ) -> std::string_view
        {
            return in.rootArg.empty() ? std::string_view( ing.files[f] ) : rw::sarif::rootRelativeUri( ing.files[f], ptPrefix );
        } );
    }
    // E1 / review of #214: the section cuts over its own GROUPED, ESCAPED rendering — see packTaskTestsSection
    // above for the defect that forced it and for why a bisection answers it exactly.
    const rw::TestRunnerIndex runners( ing, in.rootArg );   // A3: root-relative run=, same root the p= above are relative to
    PackTaskSection   tests       = packTaskTestsSection( runners, ptRows, testsBudget, kPackTaskWrapReserve, ex, &testPartition );
    const std::size_t testsTotal  = ptRows.size();
    const MonotoneRoll testsRoll  = monotoneRoll( tests.kept < testsTotal, testsBudget, tests.xml.size() );
    carry     = testsRoll.carry;
    remaining = remaining > testsRoll.charge ? remaining - testsRoll.charge : 0;

    // ── §W2-K.2 (K2): section 2 is EMITTED second and ALLOCATED after the fine-grained sections — reflowListSection above
    //    carries the finding. PB1: ONE body, the key one, whole when its share holds it, else cut by packBodies' oversized-first
    //    floor (a partial view of the symbol the question names beats none); every other candidate is a pointer row. ─────────
    const std::size_t bodiesBudget = sectionBudget( kPackTaskQuotaBodiesPct, carry );
    if( !bodyIds.empty() )
    {
        const std::string pointers   = packTaskBodyPointers( ing, std::vector<NodeId>( bodyIds.begin() + 1, bodyIds.end() ), ex, in.rootArg );
        // the key body's OWN pointer, built unconditionally: it rides whenever the body is not served — a share under the
        // floor, a failed render, or a <bodies> shape the restate cannot lift the body out of. A candidate counted in
        // total= but reachable from nowhere in the document would be a dead end, so no path may drop it silently.
        const std::string keyPointer = packTaskBodyPointers( ing, { bodyIds.front() }, ex, in.rootArg );
        // the pointers are the section's disclosure, never its price: the key body gets the whole share (less the wrapper), and the
        // pointer bytes are charged to the bundle with the rest of the section (the tail, filled last, is what absorbs them)
        const std::size_t bodyBudget = bodiesBudget > kPackTaskWrapReserve ? bodiesBudget - kPackTaskWrapReserve : 0;
        const PackTaskRendered bodies = bodyBudget < kPackTaskSectionFloor ? PackTaskRendered{ {}, true }
            : packTaskRender<PackTaskRenderFaults::DisclosureWhy::BodiesRenderFailed>( [ & ]( std::FILE* m )
              {
                  // CB1: the monotone line cap, ON here and nowhere else yet. This is the one place a WHOLE large
                  // body can ride unbounded: PB1's D1 gives the key body the entire bodies share, so a 202-line
                  // function was MEASURED riding whole at 8,039 B of a 12,744 B bundle. The byte share cuts it only
                  // when the share is too small (MEASURED: lines="1-9/202" at --token-budget=1200), so between
                  // "fits the share" and "far too big" there was no bound at all. --for's key body is NOT capped
                  // here: it already has the 4,000 B cut, which CB1 §4 measured as 73-150 lines depending on the
                  // repo's line width. Re-denominating THAT to lines is the predictability win, and it is a
                  // separate change because it moves bytes on every route/fold/launch body that shares the printer.
                  packBodies( m, ing, { bodyIds.front() }, bodyBudget, g.outOff, g.outTargets, g.outNameOnly, in.compress, in.redact,
                              /*ranges=*/nullptr, /*noteIndex=*/nullptr, &emittedBodies, /*truncateOversizedFirst=*/true,
                              /*withFileContext=*/false, in.rootArg, in.calleeRank, /*legendsInHead=*/{},
                              /*bodyLineCap=*/kCappedBodyLines );
              }, in.renderFaults );
        if( !bodies.ok )
        {
            emittedBodies = EmittedBodies{};   // nothing was emitted, so nothing was kept: the JSON tail re-serializes this record
            char tag[ 144 ];
            rw::formatTo( tag, sizeof( tag ), "<bodies shown=\"0\" total=\"{}\" capped=\"{}\" render_failed=\"1\">",
                          keyId != kNoNode ? 1 : 0, keyId != kNoNode ? 1 : 0 );
            bodiesStr = std::string( tag ) + keyPointer + pointers + "</bodies>";
        }
        else
        {
            bodiesKept = emittedBodies.kept.size();
            // restatePackTaskBodies may ZERO bodiesKept (an unrecognised <bodies> shape drops the served body) — so the
            // ledger, the monotoneRoll charge and the JSON dialect below all read the count the XML actually printed.
            const std::size_t keptBefore = bodiesKept;
            PackBodiesTag     bodiesTag{ .served      = bodiesKept,
                                         .servedTotal = keyId != kNoNode ? 1u : 0u,
                                         .candidates  = bodiesTotal,
                                         .servedCut   = std::any_of( emittedBodies.kept.begin(), emittedBodies.kept.end(),
                                                                     []( const EmittedBody& e ) { return e.isTruncated; } ),
                                         .bodyless    = countBodylessCandidates( ing, bodyIds ),
                                         .compress    = in.compress };
            bodiesStr  = restatePackTaskBodies( bodies.text, bodiesTag, keyPointer, pointers, renderFaults );
            bodiesKept = bodiesTag.served;
            if( keptBefore > 0 && bodiesKept == 0 )
            {
                emittedBodies = EmittedBodies{};   // the XML dropped it, so the JSON twin must not claim it either
            }
            for( const EmittedBody& e : emittedBodies.kept )
            {
                bodyReadings |= ( e.isTruncated ? kBodyReadingTruncated : 0u ) | ( e.isOverCeiling ? kBodyReadingOverCeiling : 0u );
            }
            if( bodyReadings != 0 && in.innerBundle )
            {
                hoistBodyReadings( bodiesStr );   // P10: a partition slice's readings ride the outer legend once
            }
        }
    }
    else
    {
        // R9 fix (W3-S, 2026-08-19): no candidate at all still emits the element — "a zero means none found, never none
        // exists" (CONTRIBUTING #3) applies to elements, not only counts.
        bodiesStr = in.compress ? "<bodies shown=\"0\" total=\"0\" capped=\"0\" compress=\"1\"></bodies>" : "<bodies shown=\"0\" total=\"0\" capped=\"0\"></bodies>";
    }
    // §W2-K: bodyIds (the candidate SET) never depends on budgetTokens, so the same monotoneRoll treatment applies here too.
    // "capped" here is the same BUDGET verdict the tag prints, not shown != total: the pointer rows are by design.
    const MonotoneRoll bodiesRoll = monotoneRoll( keyId != kNoNode && bodiesKept == 0, bodiesBudget, bodiesStr.size() );
    remaining = remaining > bodiesRoll.charge ? remaining - bodiesRoll.charge : 0;

    // ── <partners> (emitted after tests): mined here, granted its bytes just before the tail below (see PackPartners above) ──
    PackPartnersBlock partners{ .data = packTaskPartners( ing, g, order, rank, keyId, in ) };
    partners.rows = packTaskPartnerRows( ing, partners.data, in.rootArg, ex );

    // ── section 6 — the file-grain tail (PB1): filled LAST, with everything the sections above left, cut at a row boundary ──
    //    (packTaskTailRowsToFit). A --partition slice carries none: its rank is masked to the slice, and the outer document's
    //    core states the task's files once.
    std::string tailStr;
    std::string tailJson;
    std::size_t tailShown = 0, tailTotal = 0;
    bool        tailCapped = false;
    bool        tailNextDropped = false;   // the echo the element could not afford — disclosed in the ledger below
    FileTail    tail;
    if( !in.innerBundle )
    {
        remaining += tailReserve;   // the tail's own share, back on top of whatever the sections above left
        // <partners>: up to its cap, out of what the sections above left and then the tail's reserve. Its candidate set never
        // depends on budgetTokens and `remaining` is non-decreasing in it, so the same monotoneRoll treatment keeps it monotone.
        remaining = grantPackPartners( partners, remaining, quotaBase );
        tail = computeFileTail( ing, rank, lr.evidence, head.shownIds, in.rootArg, task );
        // the whole tail fits with bytes to spare while the head is cut: the head takes them first (W2-K.2's lap, the head's
        // turn), and the tail is rebuilt from the rows the wider head shows — a file can only move from the tail into the head.
        if( sigsCapped && renderFileTailXml( tail, tail.paths.size(), esc ).size() < remaining )
        {
            const std::size_t spare = remaining - renderFileTailXml( tail, tail.paths.size(), esc ).size();
            PackHead wider = renderPackHead( ing, rank, PackHeadInputs{ rankTopN, rowDropBudget + spare, headRules, task, &in, &forClone } );
            if( wider.sigsStr.size() > head.sigsStr.size() && wider.sigsStr.size() - head.sigsStr.size() <= spare )
            {
                remaining -= wider.sigsStr.size() - head.sigsStr.size();
                head = std::move( wider );
                tail = computeFileTail( ing, rank, lr.evidence, head.shownIds, in.rootArg, task );
            }
        }
        tailShown = packTaskTailRowsToFit( tail, remaining, esc );
        tailStr   = renderFileTailXml( tail, tailShown, esc );
        // THE TAIL'S next= ECHOES THE TASK, so it is a user-length PAYLOAD part — the same shape W3FIX M1 charged in the
        // header while this one rode free below it. MEASURED on test/fixture at --token-budget=1200: a 900-character task
        // bought a 971 B <tail> where a short task paid 87 B, all of it the echo, so a longer header bought MORE payload
        // (w3fixbudgetcheck arm 4, "bytes riding free"). When the element does not fit the bytes the sections above left,
        // the ECHO is the first thing dropped — the same order the ceiling ladder drops the header's own echo — and the
        // element still discloses total=, shown= and capped=. The root's task= stays the one verbatim copy of the task.
        if( tailStr.size() > remaining )
        {
            tailNextDropped = stripOpenTagAttr( tailStr, "next" );
        }
        tailTotal = tail.total;
        // the shell alone may not fit a budget the sections above spent: it is still emitted (the element is the disclosure)
        remaining  = remaining > tailStr.size() ? remaining - tailStr.size() : 0;
        if( tailShown < tail.paths.size() )
        {
            remaining = 0;   // the tail took what it could; nothing is left to reflow
        }
    }

    // ── §W2-K.2 (K2): the reflow lap — see reflowListSection above for the finding and the argument. PB1: the ranking is not
    //    re-rendered (the tail was cut from its shown rows), so the lap tops up the fine-grained list sections only. ────────
    std::size_t reflow = remaining;
    reflow = reflowListSection( callers, "callers", callersAttr, callerRows, callersBudget, kPackTaskWrapReserveWide, reflow );
    reflow = reflowListSection( notes,   "notes",   "",          noteEntries, notesBudget,   kPackTaskWrapReserve,     reflow );
    reflow = reflowPackPartners( partners, reflow );   // <partners>' turn, before the tests' (the last)
    // The tests section's own reflow lap — reflowListSection's rule (top up a section the first lap capped,
    // once, and pass nothing further on) over packTaskTestsSection's cut. It is the LAST section to reflow, so
    // its leftover goes nowhere and is not computed.
    if( reflow > 0 && tests.kept < testsTotal )
    {
        testsBudget += reflow;
        tests = packTaskTestsSection( runners, ptRows, testsBudget, kPackTaskWrapReserve, ex, &testPartition );
    }

    const std::string& callersStr = callers.xml;
    const std::size_t  callersKept = callers.kept;
    const std::string& notesStr   = notes.xml;
    const std::size_t  notesKept  = notes.kept;
    const std::string& testsStr   = tests.xml;
    const std::size_t  testsKept  = tests.kept;

    // ── PB1: the document is assembled by `finish` for a given tail row count, so the tail can be re-cut to what is DELIVERED:
    //    the header is sized above by a fixed reserve (kPackTaskHeaderReserve), and the compact posture delivers a different
    //    legend than the one that reserve was measured on. The tail is the one section cut last, so it is the one re-cut. ──────
    const auto finish = [ & ]( std::size_t tailRows ) -> std::string
    {
    if( !in.innerBundle )
    {
        tailShown  = tailRows;
        tailStr    = renderFileTailXml( tail, tailShown, esc );
        if( tailNextDropped )
        {
            stripOpenTagAttr( tailStr, "next" );   // the echo this bundle could not afford stays dropped on every re-cut
        }
        tailCapped = tailShown < tail.total;
        tailJson   = jsonOut ? "," + renderFileTailJson( tail, tailShown ) : std::string();
    }
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
        const RedactTallyFreeze tallyFreeze( in.redact );   // §B10.2: this second rendering must not re-bill the tally
        const std::string       partnersJson = packTaskPartnersJson( ing, partners.data, partners.section.kept, in.rootArg );
        packTaskJsonTail( *jsonOut, PackTaskJsonParts{ ing, lr, in, task, renderFaults, rank, forClone, bodyIds, d1, d1SigRaw,
                                                       emittedBodies, head, notes, noteEntriesData, testFiles, testPartition,
                                                       tailJson, mentionNote, boostNote, sibliftNote, expandNote, docMentionNote,
                                                       keyId, budgetTokens, bundleBudget, bodiesTotal, bodiesKept, callersTotal,
                                                       callersKept, notesTotal, notesKept, testsTotal, testsKept, partnersJson } );
    }

    const auto listStatus = []( std::size_t total, const std::string& body, std::size_t kept ) -> std::string
    {
        char b[ 64 ];
        if( total == 0 )       { return "none"; }
        if( body.empty() )     { return "omitted (budget)"; }
        // Split from a ternary over two format strings: std::format_string is consteval, so each format
        // has to be a literal at its own call site. Same bytes on both branches.
        if( kept < total ) { rw::formatTo( b, sizeof( b ), "kept {} of {}", kept, total ); }
        else               { rw::formatTo( b, sizeof( b ), "{} of {}", kept, total ); }
        return b;
    };
    std::string report = "budget=";
    { char b[ 160 ];  rw::formatTo( b, sizeof( b ), "{} bytes ({}-token target, ceiling {}) | ",
                                    bundleBudget, budgetTokens, rw::declaredByteCeiling( budgetTokens )  );  report += b; }
    const bool isRankingFailed = renderFaults.hasFailed( PackTaskRenderFaults::DisclosureWhy::RankingRenderFailed );
    report += std::string( "ranking: " ) + ( isRankingFailed ? "render-failed" : head.capped ? "capped" : "full" ) + " | ";
    // PB1: one body is served; every other candidate is counted here AND rides <bodies> as a next= pointer row
    { char b[ 96 ];
      if( bodiesTotal == 0 ) { rw::formatTo( b, sizeof( b ), "none" ); }
      else { rw::formatTo( b, sizeof( b ), "kept {} of {}{}, {} as next=", bodiesKept, keyId != kNoNode ? 1 : 0,
                           ( keyId != kNoNode && bodiesKept == 0 ) || ( bodyReadings & kBodyReadingTruncated ) != 0 ? " (capped)" : "",
                           bodiesTotal - bodiesKept ); }
      report += "bodies: ";  report += b;  report += " | "; }
    report += "callers: " + listStatus( callersTotal, callersStr, callersKept ) + " | ";
    report += "notes: "   + listStatus( notesTotal,   notesStr,   notesKept )   + " | ";
    report += "tests: "   + listStatus( testsTotal, testsStr, testsKept );   // E1: test files, as the section's shown=/total= say
    if( !in.innerBundle )   // PB1: the file tail (a partition slice has none)
    {
        report += " | tail: " + listStatus( tailTotal, tailStr, tailShown )
                // NO '>' IN THE KEPT LEDGER. The ledger rides the compact answer as a DATA comment that consumers parse,
                // and more than one of them slices it with `<!-- ledger: [^>]*-->` (compactlegendcheck FX4 among them), so a
                // '>' anywhere inside truncates the slice to nothing and the whole disclosure reads as absent. The clause
                // used to say "next= on <tail>", which is both redundant — it IS the tail's clause — and a parse hazard.
                + ( tailCapped ? ( tailNextDropped ? " (capped; next= dropped: the task echo did not fit the bytes left)" : " (capped; next= on the tail)" ) : "" );
    }
    // cut-fix lane A: the <sigs> tag's cut readings, the --for twin's clauses verbatim (serialize.h sigsCutLegendNotes),
    // present only when the tag carries the case; absorbed by kPackTaskHeaderReserve like the ledger around them.
    report += rw::sigsCutReportLegend( head.cut );   // PB1: every reading the --for head's tag can carry (files_first=, docs_after_code=, next=…)
    // A2 (survey card, 2026-09-03) — the pack-task twin of --for's dropped_positive= root fact: how many
    // rank>0 eligibleIds the section-1 ladder cut. Emitted ONLY when nonzero (the pr_converged precedent,
    // src/prconverge.h) — its bytes are absorbed by kPackTaskHeaderReserve's generous fixed allowance (see
    // its own comment), so this costs no separate budget accounting, and the no-drop path
    // (rankOut.droppedPositive == 0) is byte-identical to the pre-A2 header exactly as before.
    //
    // M1 (terminality round A, 2026-09-05): it rides the <ctx> ROOT, not the ledger comment. A2 put it in
    // `report` while its --for twin put it on the root (verbs_for.h droppedPositiveNote), and the asymmetry
    // stayed invisible until the MCP legend default became compact: the compact dialect strips prose
    // comments, so a COMPLETENESS fact living in prose vanished from the default answer — measured on
    // src/ at budget_tokens=300, dropped_positive="2" under legend:"full" and NOTHING under the default
    // (test/droppedpositivecheck.sh #6). METHODOLOGY §9 #4: honesty lives in attributes, precisely so a
    // legend posture can never decide whether a caller is told. Same spelling as the --for twin, so
    // mcpattrparitycheck sees one name on both roots; the ledger prose keeps the per-section counts, which
    // ARE legend and which compact is entitled to drop.
    std::string droppedPositiveAttr;
    if( head.droppedPositive > 0 )
    {
        char b[ 96 ];  rw::formatTo( b, sizeof( b ), " dropped_positive=\"{}\"", head.droppedPositive );
        droppedPositiveAttr = b;
    }
    // The indexing caps that cut this ranking belong on the root as ATTRIBUTES, not only inside the prose
    // note at line 1226. --pack-task is the agent-facing bundle: a human reading the XML comment saw
    // lr.capNote and an agent parsing attributes saw nothing, which is backwards for who consumes this.
    // Appending here rather than at each buildHeader site is deliberate -- this string is what
    // appendPackTaskRootExtras splices, so the partition-slice root (in.innerBundle) inherits it too, the
    // same way M1 gave that path dropped_positive=. Same attribute names as the --for and MCP twins, so
    // mcpattrparitycheck still sees one spelling on every root.
    droppedPositiveAttr += lr.capAttrs;
    notePackPartners( partners, report, droppedPositiveAttr );   // the ledger's partners clause, or the root's partners_none=
    if( renderFaults.failedMask != 0 )
    {
        // Not a budget fact: these sections' renders FAILED. Marked on the root (and on the section element itself),
        // with the clause that defines it riding the ledger, so an empty section never reads as an omission.
        droppedPositiveAttr += " render_failed=\"" + renderFaults.names() + "\"";
        report += " | render_failed= names sections whose render FAILED (the section is empty and marked render_failed=\"1\"; "
                  "not a budget omission; body-probe = a body priced out because its cost could not be measured)";
    }
    // L3 follow-up (CodeRabbit 4053600616): notes.h's ONE marker, spelled identically on every notes-surfacing
    // emitter — absent on a clean read (no sidecar, or every line parsed), so the L3 inertness contract holds.
    if( in.notesDegraded )
    {
        droppedPositiveAttr += std::string( notes::kNotesDegradedAttr );
        report += " | ";  report += notes::kNotesDegradedReading;
    }

    // The clause is now BUILT (the root-relative sentence is conditional, so the seam composes a string
    // rather than handing back one of two constants), and PackTaskHeaderParts holds VIEWS — so it is owned
    // by a named local here, like report and droppedPositiveAttr above it. Binding the view straight to the
    // returned temporary is a dangling read the moment the full expression ends, and it showed as exactly
    // that: packtaskcheck's bundle was both malformed and non-deterministic (two runs, two sha256s).
    const std::string runClauseStr = rw::runHintClauseIfRows( tests.kept, rw::runsAreRootRelative( ing, in.rootArg ) )   // the ONE gate: the section's own kept count
                                   + std::string( packTaskPartnersLegend( partners.data ) );                               // rows-gated the same way
    const PackTaskHeaderParts headerParts{ task, rootOpenStr, taskNote, mentionNote, boostNote,
                                            docMentionNote, sibliftNote, expandNote, report, droppedPositiveAttr, in.rootArg,
                                            runClauseStr, /*softBudget=*/in.softTarget && !in.innerBundle, pathFromNote };
    const auto buildHeader = [ & ]( bool withRouteAttr, bool withTaskEcho, std::string_view extraNotes )
    {
        if( in.innerBundle )   // P10 (L7): a partition slice — the outer <ctx-partitions> legend speaks once for all of them
        {
            std::string h = withRouteAttr ? std::string( rootOpenStr ) : ctxRootOpen( task, {}, in.rootArg );
            appendPackTaskRootExtras( h, droppedPositiveAttr );   // M1: the partition slice owes it too
            if( !report.empty() || !extraNotes.empty() )
            {
                h += "<!-- slice ";  h.append( report );  h.append( extraNotes );  h += " -->";   // data only (the budget ledger + ceiling notes; dropped_positive= is on the root, M1)
            }
            if( !pathFromNote.empty() )
            {
                h += "<!--";  h.append( pathFromNote );  h += " -->";
            }
            return h;
        }
        return packTaskHeaderText( headerParts, withRouteAttr, withTaskEcho, extraNotes );
    };
    const std::string headerStr = buildHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );

    std::string whole;
    whole.reserve( headerStr.size() + sigsStr.size() + bodiesStr.size() + callersStr.size() + notesStr.size() + testsStr.size()
                   + partners.section.xml.size() + tailStr.size() + 8 );
    whole += headerStr;
    whole += sigsStr;
    whole += bodiesStr;
    whole += callersStr;
    whole += notesStr;
    whole += testsStr;
    whole += partners.section.xml;
    whole += tailStr;
    whole += "</ctx>";

    packTaskSettleRoot( whole, headerStr, buildHeader, lr, in, budgetTokens );
    return whole;
    };
    std::string whole = finish( tailShown );
    if( !in.innerBundle && jsonOut == nullptr && tailShown > 0 )
    {
        const std::size_t compacted = in.compactLegend ? rw::compactDeliveredBytes( whole, "pack-task" ) : 0u;
        const std::size_t delivered = ( compacted > 0 ? compacted : whole.size() ) + in.trailingSectionBytes;
        if( delivered > bundleBudget )
        {
            const std::size_t over = delivered - bundleBudget;
            whole = finish( packTaskTailRowsToFit( tail, tailStr.size() > over ? tailStr.size() - over : 0, esc ) );
        }
    }

    // §6 --partition: the bundle's own surface (see the contract above). topRanked already contains bodyIds
    // (bodies are the positive-score head of the SAME order), so the union is topRanked ∪ d2plus ∪ d1.
    // E1 / review of #214: the number of test FILES this bundle's <tests> section actually kept. A caller
    // that must gate the run-hint clause for SEVERAL bundles at once (partition.h's outer legend) needs the
    // count, not a substring search over the rendered bytes — `<tests ` occurs in this document's own legend
    // and can occur inside a CDATA body, and a grep for it charged the clause with zero rows.
    if( testsKeptOut )
    {
        *testsKeptOut = testsKept;
    }
    if( bodyReadingsOut )
    {
        *bodyReadingsOut = bodyReadings;   // lane/cutfix-bodies: the same report-not-grep rule, for the body readings
    }
    if( surfaceOut )
    {
        surfaceOut->clear();
        surfaceOut->reserve( head.shownIds.size() + d1.ids.size() + bodyIds.size() );
        surfaceOut->insert( surfaceOut->end(), head.shownIds.begin(), head.shownIds.end() );
        surfaceOut->insert( surfaceOut->end(), bodyIds.begin(),    bodyIds.end() );
        surfaceOut->insert( surfaceOut->end(), d1.ids.begin(),     d1.ids.end() );
        sortutil::sortUnique( *surfaceOut );
    }
    return whole;
}

}   // namespace rw
