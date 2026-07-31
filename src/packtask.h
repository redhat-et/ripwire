#pragma once

// packtask.h — the shared task-bundle assembler behind --pack-task (CLI) and the MCP explore/pack_task verb
// (L4, PLAN_audit5Public2026.md). ONE function builds the fixed 5-section budget-shared bundle (routed lens
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
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace ctx
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
    std::string        docMentionNote;             // AUDIT5 R5: doc<->code mention-edge surfacing (see mention.h
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
};

inline constexpr int         kPackTaskDefaultTokens  = 6000;   // the default budget when no explicit budget is given
inline constexpr int         kPackTaskRankTopN       = 12;     // ranking = the top-12 head, not the full 40 — leaves budget for the later sections
inline constexpr std::size_t kPackTaskBodyCandidates = 6;      // top-K heads that get FULL bodies (byte budget trims further)
inline constexpr std::size_t kPackTaskSectionFloor   = 64;     // a section is only attempted when this many bytes remain
inline constexpr std::size_t kPackTaskHeaderReserve  = 1024;   // the <ctx><!-- report --> + "</ctx>" (a bounded comment)

// §B8.3 (trap #8, "a disclosure has BYTES") — the byte floor packTaskListSection holds back for its own
// wrapper, now that the wrapper carries capped= too. These were bare literals 64 and 96 at the four call
// sites, sized for the pre-capped= tag; the bit costs 11 bytes (` capped="0"`), which on a large corpus
// (6-digit shown=/total=) took <far>'s open+close tag past 64 — a section quietly overspending its own share
// to pay for the attribute that says it was capped. Named, and sized with visible headroom.
inline constexpr std::size_t kPackTaskWrapReserve     = 80;    // <notes>/<tests>/<far>: open tag + close tag
inline constexpr std::size_t kPackTaskWrapReserveWide = 112;   // <callers>: the same plus its of_top= attribute

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
    std::string_view routeNote, mentionNote, boostNote, docMentionNote;
    std::string_view report;           // the per-section truncation ledger
};

// One spelling of --pack-task's header, three shapes of it. `withTaskEcho=false` replaces the comment's echo
// with a note pointing at the task= attribute that still holds the verbatim copy — nothing is lost, only the
// duplicate. Byte-identical to the pre-ladder header when both flags are true and extraNotes is empty.
inline std::string packTaskHeaderText( const PackTaskHeaderParts& p, bool withRouteAttr, bool withTaskEcho,
                                       std::string_view extraNotes )
{
    std::string h = withRouteAttr ? std::string( p.rootOpenStr ) : ctxRootOpen( p.task, {} );
    h += "<!-- ripwire task bundle for ";
    if( withTaskEcho ) { h += "\"";  h.append( p.taskNote );  h += "\""; }
    else                 h += "[task_echo: dropped (ceiling) - the verbatim copy is the task= attribute above]";
    h.append( p.routeNote );
    h.append( p.mentionNote );
    h.append( p.boostNote );
    h.append( p.docMentionNote );
    h += ": one-call orientation under ONE budget — sections in FIXED order ranking > bodies > callers > notes > tests, "
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
         "Row keys: n=name (chain it), id=canonical(when scoped), in=reuse-count (absent = not measured, never a false 0)"
         ", l=line, p=path, t=kind, cx=cyclomatic, ccx=cognitive, rel=caller|callee; far=ranked but over 1 hop out; "
         "of_top denominator is per-section. ";
    h.append( p.report );
    h.append( extraNotes );
    h += " -->";
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
    if( entries.empty() || budget <= wrapReserve ) return out;
    std::size_t used = wrapReserve;
    for( const std::string& e : entries ) { if( used + e.size() > budget ) break;  used += e.size();  ++out.kept; }
    if( out.kept == 0 ) return out;
    char open[ 160 ];
    std::snprintf( open, sizeof( open ), "<%.*s%.*s shown=\"%zu\" total=\"%zu\" capped=\"%d\">",
                   int( tag.size() ), tag.data(), int( extraAttr.size() ), extraAttr.data(), out.kept, entries.size(),
                   out.kept < entries.size() ? 1 : 0 );
    out.xml = open;
    for( std::size_t i = 0; i < out.kept; ++i ) out.xml += entries[i];
    out.xml += "</";  out.xml.append( tag );  out.xml += ">";
    return out;
}

// §H5, the direction the finding did not name: the XML names each over-budget skip in a
// `<!-- body omitted (over budget): NAME -->` comment and the JSON dialect named none of them. Same set, same
// reason, spelled for a parser. The key is OMITTED (not `[]`) when nothing was skipped, matching the
// silence-means-nothing-happened convention route/mention/boost/over_ceiling already use in this dialect.
inline std::string packTaskOmittedBodiesJson( const IngestResult& ing, const ctx::EmittedBodies& emitted )
{
    if( emitted.omitted.empty() ) return {};
    std::string out = ",\"bodies_omitted\":[";
    for( std::size_t i = 0; i < emitted.omitted.size(); ++i )
    {
        if( i ) out += ",";
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
};

// R2: the anchors' 1-hop neighbors, EITHER direction (g.inEdges = symbols that CALL an anchor; g.outOff/
// outTargets = symbols an anchor CALLS), anchors themselves excluded (`d0Mark`) and deduped — a neighbor
// reachable both ways keeps whichever direction is discovered first (caller before callee).
struct D1Neighbors { std::vector<NodeId> ids;  std::vector<std::uint8_t> isCaller; };

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
        if( b >= ctx.ing->symbols.size() ) return ids;
        const auto* ro = ctx.g->inEdges.rowOffsets();
        const auto* ci = ctx.g->inEdges.colIndices();
        ids.assign( ci + ro[b], ci + ro[b + 1] );
        return ids;
    }
    if( b + 1 >= ctx.g->outOff.size() ) return ids;
    ids.assign( ctx.g->outTargets.begin() + ctx.g->outOff[b], ctx.g->outTargets.begin() + ctx.g->outOff[b + 1] );
    return ids;
}

// append `b`'s neighbors in ONE direction as d1 entries (tagged "caller"/"callee" per `viaCallerEdges`),
// skipping an id already an anchor or already collected. The ONE walk both directions share.
inline void collectNeighborsOf( D1WalkCtx& ctx, NodeId b, bool viaCallerEdges )
{
    for( NodeId c : rawNeighborIdsOf( ctx, b, viaCallerEdges ) )
    {
        if( c >= ctx.seenNeighbor->size() || (*ctx.seenNeighbor)[c] || (*ctx.d0Mark)[c] ) continue;
        (*ctx.seenNeighbor)[c] = 1;  ctx.out->ids.push_back( c );  ctx.out->isCaller.push_back( viaCallerEdges ? 1 : 0 );
    }
}

// deterministic (file, line, name) display order — the same tie-break the pre-R2 callers-only list used.
inline D1Neighbors sortNeighborsBySite( const IngestResult& ing, D1Neighbors&& in )
{
    std::vector<std::uint32_t> perm( in.ids.size() );
    for( std::uint32_t i = 0; i < perm.size(); ++i ) perm[i] = i;
    std::sort( perm.begin(), perm.end(), [ & ]( std::uint32_t a, std::uint32_t b )
    {
        const Symbol& sa = ing.symbols[ in.ids[a] ];  const Symbol& sb = ing.symbols[ in.ids[b] ];
        if( sa.fileId != sb.fileId ) return ing.files[sa.fileId] < ing.files[sb.fileId];
        return sa.line != sb.line ? sa.line < sb.line : sa.name < sb.name;
    } );
    D1Neighbors out;
    out.ids.resize( in.ids.size() );  out.isCaller.resize( in.ids.size() );
    for( std::size_t i = 0; i < perm.size(); ++i ) { out.ids[i] = in.ids[ perm[i] ];  out.isCaller[i] = in.isCaller[ perm[i] ]; }
    return out;
}

inline D1Neighbors computeD1Neighbors( const IngestResult& ing, const Graph& g,
                                       const std::vector<NodeId>& bodyIds, const std::vector<char>& d0Mark )
{
    D1Neighbors out;
    std::vector<char> seenNeighbor( ing.symbols.size(), 0 );
    D1WalkCtx ctx{ &ing, &g, &d0Mark, &seenNeighbor, &out };
    for( NodeId b : bodyIds ) collectNeighborsOf( ctx, b, /*viaCallerEdges=*/true );
    for( NodeId b : bodyIds ) collectNeighborsOf( ctx, b, /*viaCallerEdges=*/false );
    return sortNeighborsBySite( ing, std::move( out ) );
}

// R2: one d1 row — its OWN one-line signature (d1's detail tier — never a full body) + declaration site +
// which direction it was reached from. `rawSig` is the RAW (unescaped) text the L2 --json tail reuses
// verbatim — one extraction, two shapes, never re-derived.
struct D1Rows { std::vector<std::string> xml;  std::vector<std::string> rawSig; };
struct D1Row  { std::string xml;              std::string rawSig; };

// fetch (and cache) file `fileId`'s full source text — a small per-file cache so multiple d1 rows landing in
// the same file don't re-read it.
inline const std::string& d1ReadSrcCached( const IngestResult& ing, std::uint32_t fileId,
                                           HashMap<std::uint32_t, std::string>& cache )
{
    if( auto it = cache.find( fileId ); it != cache.end() ) return it->second;
    std::string body;
    if( std::FILE* in = std::fopen( diskPath( ing, fileId ).c_str(), "rb" ) )
    {
        char buf[ 4096 ];  std::size_t n;
        while( ( n = std::fread( buf, 1, sizeof( buf ), in ) ) > 0 ) body.append( buf, n );
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
    if( s.fileId >= ing.files.size() ) return {};
    const std::string& src = d1ReadSrcCached( ing, s.fileId, srcCache );
    const std::size_t  a = s.sigStartByte, b = s.sigEndByte;
    if( a >= src.size() || b > src.size() || a >= b ) return {};
    std::string sig = cleanSig( src.data(), a, b, redact );
    truncateUtf8WithEllipsis( sig, kForCapTailSigBytes );
    return sig;
}

template<class EscFn>
inline D1Row buildD1Row( const IngestResult& ing, NodeId id, bool isCaller,
                         HashMap<std::uint32_t, std::string>& srcCache, EscFn&& ex, RedactCounts* redact )
{
    const Symbol& s   = ing.symbols[id];
    std::string   sig = resolveD1Signature( ing, s, srcCache, redact );

    // §B14 — composed on std::string. `ex()` escapes BEFORE this point, so an snprintf into a fixed buffer
    // would truncate the ESCAPED form and emit an unterminated `<s …` row at exit 0 (measured on base: at a
    // 600-byte corpus path, 11 of 11 `<s>` rows unterminated across <callers> and <far>). serialize.h's
    // FIXED-BUFFER RULE states the escaper-side test.
    D1Row row;
    row.xml  = "<s t=\"";   row.xml += symTag( s.kind );
    row.xml += "\" n=\"";   row.xml += ex( s.name );
    row.xml += "\" p=\"";   row.xml += ex( ing.files[ s.fileId ] );
    row.xml += ":";         row.xml += std::to_string( s.line );
    row.xml += "\" rel=\""; row.xml += isCaller ? "caller" : "callee";
    row.xml += "\"";
    if( sig.empty() ) row.xml += "/>";
    else { row.xml += ">";  row.xml += ex( sig );  row.xml += "</s>"; }
    row.rawSig = std::move( sig );
    return row;
}

template<class EscFn>
inline D1Rows renderD1CallerRows( const IngestResult& ing, const D1Neighbors& d1, EscFn&& ex, RedactCounts* redact )
{
    D1Rows out;
    out.xml.reserve( d1.ids.size() );  out.rawSig.reserve( d1.ids.size() );
    HashMap<std::uint32_t, std::string> srcCache;
    for( std::size_t i = 0; i < d1.ids.size(); ++i )
    {
        D1Row row = buildD1Row( ing, d1.ids[i], d1.isCaller[i] != 0, srcCache, ex, redact );
        out.xml.emplace_back( std::move( row.xml ) );
        out.rawSig.emplace_back( std::move( row.rawSig ) );
    }
    return out;
}

// R2: a bare NAME-ONLY `<s .../>` row per id (no signature, no doc) — the d2plus tier.
template<class EscFn>
inline std::vector<std::string> renderNameOnlyRows( const IngestResult& ing, const std::vector<NodeId>& ids, EscFn&& ex )
{
    std::vector<std::string> rows;
    rows.reserve( ids.size() );
    for( NodeId id : ids )
    {
        const Symbol& s = ing.symbols[id];
        std::string   row = "<s t=\"";                                   // §B14 — std::string, not char[512]
        row += symTag( s.kind );
        row += "\" n=\"";   row += ex( s.name );
        row += "\" p=\"";   row += ex( ing.files[ s.fileId ] );
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
        ( ( id < d0Mark.size() && d0Mark[id] ) || ( id < d1Mark.size() && d1Mark[id] ) ? eligibleIds : d2plusIds ).push_back( id );
}

// R2: everything outside `eligibleIds` is pinned to -1 (below any real, non-negative score) so
// packSignatures' own internal top-N selection naturally lands on exactly `eligibleIds`, in their original
// relative order — no pull-up of a lower-ranked, still-ineligible candidate to fill the gap.
inline std::vector<float> buildMaskedRank( const IngestResult& ing, const std::vector<float>& rank,
                                           const std::vector<NodeId>& eligibleIds )
{
    std::vector<float> masked( ing.symbols.size(), -1.0f );
    for( NodeId id : eligibleIds ) if( id < masked.size() ) masked[id] = rank[id];
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
                        /*noteIndex=*/nullptr );   // notes are a DEDICATED section (4), never inline here (avoids double-emit)
    } );
    // §P8 vocabulary: the ladder's marker is now `<sigs capped="1">` (src/pageview.h, THE TRUNCATION
    // VOCABULARY, rule 5) — it was payload="capped", and THIS was the string-match that made a string enum
    // load-bearing. Matched with the element name attached so a capped= on any nested child can never be
    // read as the ranking section's own verdict.
    out.capped = out.sigsStr.find( "<sigs capped=\"1\">" ) != std::string::npos;

    const std::vector<std::string> farRows = renderNameOnlyRows( ing, *ri.d2plusIds, ex );
    char farAttr[ 32 ];  std::snprintf( farAttr, sizeof( farAttr ), " of_top=\"%zu\"", ri.topRanked->size() );
    const std::size_t     sigsLeftover = ri.sigsBudget > out.sigsStr.size() ? ri.sigsBudget - out.sigsStr.size() : 0;
    const PackTaskSection far          = packTaskListSection( "far", farAttr, farRows, sigsLeftover, kPackTaskWrapReserve );
    out.farTotal = farRows.size();
    out.farKept  = far.kept;
    out.farXml   = far.xml;

    if( !far.xml.empty() && out.sigsStr.size() >= 7 && out.sigsStr.compare( out.sigsStr.size() - 7, 7, "</sigs>" ) == 0 )
        out.sigsStr.insert( out.sigsStr.size() - 7, far.xml );
    else if( !far.xml.empty() )
        DEGRADED_PATH_ALERT( "pack-task: <sigs> did not end with the expected closing tag — <far> omitted" );
    return out;
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
    for( NodeId i = 0; i < order.size(); ++i ) order[i] = i;
    sortutil::radixSortByScoreDescId( order, rank );
    std::vector<NodeId> bodyIds;
    for( std::size_t k = 0; k < order.size() && bodyIds.size() < kPackTaskBodyCandidates; ++k )
    {
        if( rank[ order[k] ] <= 0.0f ) break;
        bodyIds.push_back( order[k] );
    }

    // ── R2: distance-aware detail allocation ────────────────────────────────────────────────────────────────
    // The bundle's detail LEVEL is a function of graph distance from the anchor set (bodyIds, d0), not a flat
    // per-section cut: d0 (the anchors themselves) already get the maximal tier — a full body (section 2,
    // above/below, unchanged). d1 (any symbol one call-graph hop from an anchor, caller OR callee) gets
    // signature-level detail. Everything else considered by the ranking pool but NOT within 1 hop of any
    // anchor (d2+) is demoted to a bare name-only row — still surfaced (no silent loss), just cheaper.
    std::vector<char> d0Mark( ing.symbols.size(), 0 );
    for( NodeId b : bodyIds ) if( b < d0Mark.size() ) d0Mark[b] = 1;

    const D1Neighbors  d1 = computeD1Neighbors( ing, g, bodyIds, d0Mark );
    std::vector<char> d1Mark( ing.symbols.size(), 0 );
    for( NodeId n : d1.ids ) if( n < d1Mark.size() ) d1Mark[n] = 1;

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
            for( NodeId m : cg.members )
                if( m < ownClone.size() ) ownClone[m] = 1u;
    }
    const std::vector<std::uint8_t>& forClone = in.cloneMember ? *in.cloneMember : ownClone;

    // ── the header's USER-LENGTH text, hoisted above the budget so the budget can CHARGE it ─────────────────
    //    W3FIX M3: the '--' collapse each echo site hand-rolled scrubbed dashes and nothing else — a C0 byte or
    //    invalid UTF-8 in the task made xmllint reject the document, and a '\n' wrote a raw newline outside
    //    CDATA. xmlCommentText (serialize.h) is the ONE scrub for all three, byte-identical on clean input.
    const std::string taskNote       = xmlCommentText( task );
    const std::string routeNote      = xmlCommentText( lr.routeNote );
    const std::string mentionNote    = xmlCommentText( lr.mentionNote );
    const std::string boostNote      = xmlCommentText( lr.boostNote );
    const std::string docMentionNote = xmlCommentText( lr.docMentionNote );

    // ── the deterministic byte budget (default 6K tokens; in.budgetTokens overrides) ────────────────────────
    const std::size_t budgetTokens = in.budgetTokens > 0 ? in.budgetTokens : std::size_t( kPackTaskDefaultTokens );
    const std::size_t bundleBudget = std::size_t( double( budgetTokens ) * ctx::kMinBytesPerToken * ctx::kBudgetHeadroom );
    // §B1.7 fixup + W3FIX M1: the header's user-length text is bytes kPackTaskHeaderReserve (a fixed 1024)
    // cannot bound. The fixup charged the verbatim task=/route= ATTRIBUTES and left the SIBLING one line away —
    // the comment's echo of the same text — free, so the ceiling still blew out ~3.4x on a long task. Charge
    // every user-length part EXACTLY (measured, not estimated); the reserve now covers only what it says it
    // covers, the fixed legend + report + "</ctx>". rootOpenStr is emitted verbatim at the assembly below.
    const std::string rootOpenStr = ctxRootOpen( task, lr.routeNote );
    // §F1: in.trailingSectionBytes is the caller's spliced-in tail (see PackTaskInputs) — a FIXED cost with no
    // trim knob of its own, so it belongs in the floor the section shares are divided under, exactly like the
    // header's own user-length parts. 0 for every caller that splices nothing.
    const std::size_t headerFloor = kPackTaskHeaderReserve + rootOpenStr.size() + taskNote.size()
                                  + routeNote.size() + mentionNote.size() + boostNote.size() + docMentionNote.size()
                                  + in.trailingSectionBytes;
    std::size_t       remaining   = bundleBudget > headerFloor ? bundleBudget - headerFloor : 1;

    const auto cap = [ & ]( double frac ) -> std::size_t { return std::max<std::size_t>( 1, std::min( remaining, std::size_t( double( bundleBudget ) * frac ) ) ); };
    constexpr double kShareRanking = 0.45, kShareBodies = 0.30, kShareCallers = 0.12, kShareNotes = 0.05;   // tests = the cascaded remainder

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
    const std::size_t         sigsBudget = cap( kShareRanking );
    const RankingSectionInputs rankIn{ &eligibleIds, &d2plusIds, &topRanked, &maskedRank, sigsBudget, &in, &forClone };
    const RankingSection       rankOut   = renderRankingWithFar( ing, rankIn, ex );

    std::string        sigsStr    = rankOut.sigsStr;
    const bool          sigsCapped = rankOut.capped;
    const std::size_t   farTotal   = rankOut.farTotal;
    const std::size_t   farKept    = rankOut.farKept;
    remaining = remaining > sigsStr.size() ? remaining - sigsStr.size() : 0;

    // ── section 2 — full bodies of the top-K ranked symbols (K adapts: packBodies self-trims to `remaining`) ─
    // §H5: `emittedBodies` is packBodies' own report of what it emitted. It is the ONE answer to "which
    // bodies?" — the XML is those bytes, the JSON tail below re-serializes the same record, and bodiesKept
    // counts it. The previous `countSub( bodiesStr, "<b " )` was both a second answer and a fragile one: body
    // text rides in CDATA verbatim, so a corpus body containing that literal inflated the count.
    std::string        bodiesStr;
    ctx::EmittedBodies emittedBodies;
    const std::size_t  bodiesTotal = bodyIds.size();
    std::size_t        bodiesKept  = 0;
    if( !bodyIds.empty() && cap( kShareBodies ) >= kPackTaskSectionFloor )
    {
        const std::size_t bodiesBudget = cap( kShareBodies );
        bodiesStr  = packTaskRenderToString( [ & ]( std::FILE* m )
        {
            packBodies( m, ing, bodyIds, bodiesBudget, g.outOff, g.outTargets, in.compress, in.redact,
                        /*ranges=*/nullptr, /*noteIndex=*/nullptr, &emittedBodies );
        } );
        bodiesKept = emittedBodies.kept.size();
        remaining  = remaining > bodiesStr.size() ? remaining - bodiesStr.size() : 0;
    }

    // ── section 3 — d1: the anchors' 1-hop callers+callees (computed above), each shown with its OWN one-line
    //    SIGNATURE (R2: d1's detail tier) + its declaration site — never a full body (that stays d0-only).
    const D1Rows d1Rendered = renderD1CallerRows( ing, d1, ex, in.redact );
    const std::vector<std::string>& callerRows = d1Rendered.xml;
    const std::vector<std::string>& d1SigRaw   = d1Rendered.rawSig;   // unescaped — the L2 --json tail reuses these verbatim
    char callersAttr[ 32 ];  std::snprintf( callersAttr, sizeof( callersAttr ), " of_top=\"%zu\"", bodiesTotal );
    const PackTaskSection callers = packTaskListSection( "callers", callersAttr, callerRows, cap( kShareCallers ), kPackTaskWrapReserveWide );
    const std::string&    callersStr   = callers.xml;
    const std::size_t     callersTotal = callerRows.size();
    const std::size_t     callersKept  = callers.kept;
    remaining = remaining > callersStr.size() ? remaining - callersStr.size() : 0;

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
            if( target.empty() || seenTarget.find( target ) != seenTarget.end() ) return;
            seenTarget[ target ] = 1;
            const std::vector<std::uint32_t>* idxs = in.notes->find( target );
            if( !idxs || idxs->empty() ) return;
            std::string entry = "<target id=\"" + ex( target ) + "\">";
            for( std::uint32_t ni : *idxs )
            {
                const notes::Note& n = in.notes->notes[ ni ];
                std::string safe;  safe.reserve( n.text.size() );
                appendCdataSafe( n.text, safe );
                entry += "<note d=\"" + ex( n.date ) + "\"><![CDATA[" + safe + "]]></note>";
            }
            entry += "</target>";
            noteEntries.push_back( std::move( entry ) );
            if( jsonOut )
            {
                std::vector<std::pair<std::string, std::string>> raw;
                for( std::uint32_t ni : *idxs ) raw.emplace_back( in.notes->notes[ ni ].date, in.notes->notes[ ni ].text );
                noteEntriesData.emplace_back( target, std::move( raw ) );
            }
        };
        for( NodeId b : bodyIds )
        {
            const Symbol& s = ing.symbols[b];
            if( s.fileId < ing.files.size() ) emitTarget( canonicalId( relForHash( ing.files[ s.fileId ], in.notes->root ), s.scope, s.name ) );   // D5: root-relative note key
        }
        for( NodeId b : bodyIds )
        {
            const Symbol& s = ing.symbols[b];
            if( s.fileId < ing.files.size() ) emitTarget( std::string( relForHash( ing.files[ s.fileId ], in.notes->root ) ) );   // D5: root-relative note key
        }
    }
    const PackTaskSection notes        = packTaskListSection( "notes", "", noteEntries, cap( kShareNotes ), kPackTaskWrapReserve );
    const std::string&    notesStr     = notes.xml;
    const std::size_t     notesTotal   = noteEntries.size();
    const std::size_t     notesKept    = notes.kept;
    remaining = remaining > notesStr.size() ? remaining - notesStr.size() : 0;

    // ── section 5 — tests_to_run for the top files (the --affected mining: tests that transitively reach) ───
    std::vector<std::string>   testRows;
    std::vector<std::uint32_t> testFiles;   // hoisted for the L2 --json tail below
    {
        std::vector<NodeId> testSeeds;
        for( NodeId b : bodyIds )
            if( b < ing.symbols.size() && !ctx::isTestPath( ing.files[ ing.symbols[b].fileId ] ) ) testSeeds.push_back( b );
        if( testSeeds.empty() ) testSeeds = bodyIds;
        const std::vector<NodeId>  reach = transitiveCallers( g, testSeeds );
        std::vector<char>          fseen( ing.files.size(), 0 );
        for( NodeId n : reach )
        {
            const std::uint32_t f = ing.symbols[n].fileId;
            if( f < fseen.size() && !fseen[f] && ctx::isTestPath( ing.files[f] ) ) { fseen[f] = 1;  testFiles.push_back( f ); }
        }
        std::sort( testFiles.begin(), testFiles.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );
        // §A9.5 / §P11.4: the one-call bundle names the tests you owe; it now also names how to RUN them,
        // from the same TestRunnerIndex --affected / --situ / --test-gate / --exercises read. Built here,
        // inside the section's scope, because it is lazy — a bundle with no test row reads no runner script.
        const ctx::TestRunnerIndex runners( ing );
        for( std::uint32_t f : testFiles )
        {
            // §B14 — std::string, not char[512]. This row carried TWO unbounded interpolands (the test path
            // AND the runner command), so it was the widest of the six breaching sites.
            std::string row = "<test p=\"";
            row += ex( ing.files[f] );
            row += "\"";
            row += ctx::runAttr( runners, f, ex );
            row += "/>";
            testRows.emplace_back( std::move( row ) );
        }
    }
    // last section: all leftover budget cascades to it (no per-section cap).
    const PackTaskSection tests      = packTaskListSection( "tests", "", testRows, remaining, kPackTaskWrapReserve );
    const std::string&    testsStr   = tests.xml;
    const std::size_t     testsTotal = testRows.size();
    const std::size_t     testsKept  = tests.kept;

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
        j = "{\"task\":\"" + jsonStr( task ) + "\"";
        if( !lr.routeNote.empty() )      j += ",\"route\":\""       + jsonStr( lr.routeNote )      + "\"";
        // The scrub disclosure travels WITH the two fields it describes: `task` and `route` are XML-scrubbed
        // copies (xmlSafeByte maps C0 except \t\n\r to a space, invalid UTF-8 to '?'), and a consumer holding
        // only the JSON is owed that fact from the JSON. ctxRootJsonScrubKeys is ctxRootOpen's twin — same two
        // strings, same single predicate — so a call site cannot emit the field without the disclosure. Absent
        // on clean input, so no ordinary document moves a byte. This closes the residual bodydialectcheck's
        // arm (H) pinned as a SET; that arm is built to go RED when this lands, naming the pin to delete.
        j += ctxRootJsonScrubKeys( task, lr.routeNote );
        if( !lr.mentionNote.empty() )    j += ",\"mention\":\""     + jsonStr( lr.mentionNote )    + "\"";
        if( !lr.boostNote.empty() )      j += ",\"boost\":\""       + jsonStr( lr.boostNote )      + "\"";
        if( !lr.docMentionNote.empty() ) j += ",\"doc_mention\":\"" + jsonStr( lr.docMentionNote ) + "\"";
        // §B1.6: all THREE budget facts the XML header states ("budget=N bytes (T-token target, ceiling C)").
        // budget_ceiling_bytes was the one number with no JSON key — the hard byte ceiling the token target
        // implies, which is what a consumer checks the bundle against; budget_bytes is the WORKING budget
        // after the headroom factor, and is always the smaller of the two. Same expression as the XML line
        // below, so the two serializations cannot report different ceilings.
        { char b[ 128 ];  std::snprintf( b, sizeof( b ), ",\"budget_tokens\":%zu,\"budget_bytes\":%zu,\"budget_ceiling_bytes\":%zu",
                                         budgetTokens, bundleBudget, std::size_t( double( budgetTokens ) * ctx::kMinBytesPerToken ) );  j += b; }

        // R2: the SAME distance mask the XML <sigs> used (eligibleIds only) — one eligibility decision, two shapes.
        j += std::string( ",\"ranking_capped\":" ) + ( sigsCapped ? "true" : "false" ) + ",\"ranking\":";
        j += eligibleIds.empty() ? "[]" : packTaskRenderToString( [ & ]( std::FILE* m )
        {
            packSignaturesJson( m, ing, maskedRank, int( eligibleIds.size() ),
                                JsonSigLens{ /*metrics=*/true, in.fanIn, in.impure, in.churn, &forClone,
                                             in.tested, in.amp, /*rankAdaptivePayload=*/true },
                                in.redact );   // §B0: the same redaction the XML <sigs> above already applied
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
               + "\",\"p\":\"" + jsonStr( ing.files[ s.fileId ] ) + ":" + std::to_string( s.line ) + "\"}";
        }
        j += "]";

        // §H5 — the bodies the XML section ACTUALLY emitted, re-serialized. This used to re-slice the first
        // `bodies_kept` ids in RANK order, but packBodies emits grouped by FILE and stops on a BYTE budget, so
        // the two dialects reported different SETS under one bodies_kept — and packBodiesJson emitted each body
        // WHOLE, against no budget at all (MEASURED: XML 8 100 B vs JSON 42 200 B under a stated 11 800 B
        // ceiling). Both halves are gone by construction: there is one selection, and this is its record.
        { char b[ 96 ];  std::snprintf( b, sizeof( b ), ",\"bodies_total\":%zu,\"bodies_kept\":%zu,\"bodies\":",
                                        bodiesTotal, emittedBodies.kept.size() );  j += b; }
        j += packTaskRenderToString( [ & ]( std::FILE* m ) { packBodiesJson( m, ing, emittedBodies ); } );
        j += packTaskOmittedBodiesJson( ing, emittedBodies );   // §H5 — see its header

        const std::size_t callersShown = std::min( callersKept, d1.ids.size() );
        { char b[ 128 ];  std::snprintf( b, sizeof( b ), ",\"callers_total\":%zu,\"callers_kept\":%zu,\"callers_of_top\":%zu,\"callers\":[",
                                         callersTotal, callersShown, bodiesTotal );  j += b; }
        for( std::size_t i = 0; i < callersShown; ++i )
        {
            const Symbol& s = ing.symbols[ d1.ids[i] ];
            j += ( i == 0 ? "" : "," );
            j += "{\"t\":\"" + std::string( symTag( s.kind ) ) + "\",\"n\":\"" + jsonStr( s.name )
               + "\",\"p\":\"" + jsonStr( ing.files[ s.fileId ] ) + ":" + std::to_string( s.line )
               + "\",\"rel\":\"" + ( d1.isCaller[i] ? "caller" : "callee" ) + "\"";
            if( !d1SigRaw[i].empty() ) j += ",\"sig\":\"" + jsonStr( d1SigRaw[i] ) + "\"";
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
                j += std::string( k == 0 ? "" : "," ) + "{\"d\":\"" + jsonStr( raw[k].first ) + "\",\"text\":\"" + jsonStr( raw[k].second ) + "\"}";
            j += "]}";
        }
        j += "]";

        const std::size_t testsShown = std::min( testsKept, testFiles.size() );
        { char b[ 96 ];  std::snprintf( b, sizeof( b ), ",\"tests_total\":%zu,\"tests_kept\":%zu,\"tests_to_run\":[", testsTotal, testsShown );  j += b; }
        // §A9.5: the JSON sibling of the XML run= above — situ's tests_to_run already carries it, and one
        // computation path must not serialize two different obligations.
        const ctx::TestRunnerIndex jsonRunners( ing );
        const auto                 jrun = [ & ]( std::string_view s ) { return jsonStr( s ); };
        for( std::size_t i = 0; i < testsShown; ++i )
            j += std::string( i == 0 ? "" : "," ) + "{\"p\":\"" + jsonStr( ing.files[ testFiles[i] ] ) + "\""
               + ctx::runFieldJson( jsonRunners, testFiles[i], jrun ) + "}";
        j += "]";

        // W3FIX M1 — the JSON sibling of the XML header's over_ceiling sentence. §B1.6 gave this dialect
        // budget_ceiling_bytes so a consumer could CHECK the bundle itself; that check silently fails on a long
        // task, because the envelope's own task echo is part of what it must measure. Absent ⇒ within the
        // ceiling (the silence-means-nothing-happened convention route/mention/boost use above), never "not
        // measured". Measured on the FINISHED document, so the key's own bytes are part of what it reports on.
        constexpr std::size_t kOverCeilingKeyBytes = 22;   // `,"over_ceiling":true` + the closing brace
        if( j.size() + kOverCeilingKeyBytes > ctx::ceilingAllowanceBytes( budgetTokens ) ) j += ",\"over_ceiling\":true";
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
                                    bundleBudget, budgetTokens, std::size_t( double( budgetTokens ) * ctx::kMinBytesPerToken ) );  report += b; }
    report += std::string( "ranking: " ) + ( sigsCapped ? "capped" : "full" ) + " | ";
    report += "bodies: "  + listStatus( bodiesTotal,  bodiesStr,  bodiesKept )  + ( bodiesTotal > 0 && !bodiesStr.empty() && bodiesKept < bodiesTotal ? " (capped)" : "" ) + " | ";
    report += "callers: " + listStatus( callersTotal, callersStr, callersKept ) + " | ";
    report += "notes: "   + listStatus( notesTotal,   notesStr,   notesKept )   + " | ";
    report += "tests: "   + listStatus( testsTotal,   testsStr,   testsKept );
    report += " | far: "  + listStatus( farTotal,      rankOut.farXml, farKept );   // R2: d2plus name-only tier (nested in <sigs>)

    const PackTaskHeaderParts headerParts{ task, rootOpenStr, taskNote, routeNote, mentionNote, boostNote,
                                            docMentionNote, report };
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
        const std::string chosen = climbCeilingLadder( buildHeader, headerStr,
                                                       whole.size() - headerStr.size() + in.trailingSectionBytes,
                                                       ctx::ceilingAllowanceBytes( budgetTokens ),
                                                       /*hasRouteAttr=*/!lr.routeNote.empty(), kNotes );
        if( chosen != headerStr ) whole.replace( 0, headerStr.size(), chosen );
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

}   // namespace ctx
