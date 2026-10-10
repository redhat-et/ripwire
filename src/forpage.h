#pragma once
// forpage.h — L-W (routing-loop round, owner decision 2026-09-12): --for's FILE-GRAIN WIDENING PAGE, its
// coverage= gauge, and the rule that makes --for's next= point at the page when the answer is thin.
//
// THE DEFECT THIS CLOSES. On the pre-registered follow-up ladder (RocksDB, frozen 30), every ripwire
// follow-up completed 0 answers through step 4: --for's next= pointed at --expand (a BODY, not a wider
// list), --top-k was INERT on --for, and --format=candidates is symbol-grain (40 symbols is about 18 files
// in 11 KB). The one follow-up that completed answers in that ladder was a file-grain page — one row per
// file, about 150 B each, +8 completes at ~6 KB — and local telemetry had --for -> --expand followed 0 of
// 259 times. So: `--for=TASK --limit=N` (offset=M pages it) is that page, `coverage=` on --for's root says
// how much of the query the top-ranked symbol actually carries, and when the answer is THIN the r=1 row's
// next= names the page instead of the body.
//
// ONE implementation for both dialects. The CLI --for (verbs_for.h) and the MCP `for` twin (mcpverbs.h) both
// call computeForFilePage/renderForFilePageXml on the SAME lensRank and the SAME LexTermEvidence, so the two
// surfaces cannot rank or render the page differently (the computeFileTail precedent).
//
// THE SCORE, stated so it can be re-derived. For a file f, over its top kForPageUnionSymbolCap positive-score
// symbols in lens order:
//     U_f = Σ_{u ∈ union of the symbols' term masks} idf(u)  /  Σ_{u ∈ query terms} idf(u)
// — the IDF-weighted share of the query's unique subtokens the file covers BETWEEN its symbols. It is bounded
// (≤ 1, a set share) and file-first by construction: a file whose symbols match several distinct terms
// outranks one that matches one term many times, and one huge file cannot monopolise the page because only
// its top few symbols contribute and a term counts once. Ties break by the file's best symbol's lens score
// (the same statistic the ranked head and the <tail> use), then by path — a total order, so the page is
// deterministic and --offset=M is the exact continuation of --limit=M (pageview.h). The mechanism is the one
// Graft's `ask --limit` rows use (file-first over a per-file union coverage); the arithmetic here is ripwire's.
//
// coverage= is the same share for ONE symbol (the r=1 row's) over ALL its fields — name, doc comment and body,
// because the persisted lexical statistics (lexindex.h) carry doc+body as one field and separating them would
// need a second read of the file. An unmatched query term weighs as the rarest possible term (BM25's own idf
// at df 0), never as nothing, so a query dragging a "(#12147)" token along reports the lower coverage that
// honestly describes it.
//
// THE THIN RULE (kForThinCoveragePct / kForThinMinFiles, stated in both legends): an answer is thin when the
// top-ranked symbol covers under 50% of the query's IDF mass, or when the ranked head (the top rows before any
// budget trim) spreads over fewer than 3 files. Thin ⇒ the root carries coverage= with its clause and next= names
// `--for=TASK --limit=40`; a CONFIDENT answer carries none of them (owner decision 2026-09-12: present-only) and
// keeps `--expand=FILE:NAME`. The thresholds are a registered hypothesis (PLAN_OUTPUT_ROUTING_LOOP §1.5 L-N),
// not a tuned number: the routing-loop ladder measures them, and a later round moves them with a measured reason.

#include "lexical.h"     // LexTermEvidence — the term masks + df the BM25 pass already accumulated
#include "model.h"
#include "nextverb.h"    // nextFlag / nextAttrXml — the ONE next= spelling
#include "pageview.h"    // pageWindow / pageDisclosure — the shared --limit/--offset vocabulary
#include "serialize.h"   // escapeXml, lensRowPath, ctxRootOpen, radixSortByScoreDescId
#include "testmap.h"     // splitChangedFilesOfSymbols — the ONE "distinct files of a symbol set" walk (--affected's)

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr int         kForPageRowsDefault    = 40;   // `--for --limit=N` with no N is never accepted (the flag refuses 0);
                                                            //   this is the N the r=1 row's widening next= spells
inline constexpr std::size_t kForPageUnionSymbolCap = 8;    // symbols per file whose term masks join that file's union
inline constexpr std::size_t kForPageSymNameCount   = 3;    // sym= names the file's top symbols by lens rank, this many
inline constexpr int         kForThinCoveragePct    = 50;   // coverage= below this ⇒ thin (see the header)
inline constexpr std::size_t kForThinMinFiles       = 3;    // a ranked head over fewer files than this ⇒ thin

// The IDF-weighted share (whole percent) of the query's unique subtokens present in `mask` (maskWords words).
// -1 when the evidence is unmeasured (no query terms — the empty-query shape lexicalScoresTiered returns early on).
inline int termShareWithin( const LexTermEvidence& ev, const std::uint64_t* mask ) noexcept
{
    const std::size_t termCount = ev.terms.size();
    if( termCount == 0 || ev.df.size() != termCount || ev.maskWords * 64 < termCount )
    {
        return -1;
    }
    double total = 0.0, matched = 0.0;   // fixed u-ascending order: the sum is deterministic
    for( std::size_t u = 0; u < termCount; ++u )
    {
        const double w = ev.idf( u );
        total += w;
        if( LexTermEvidence::hasBit( mask, u ) )
        {
            matched += w;
        }
    }
    if( !( total > 0.0 ) )
    {
        return -1;
    }
    return int( 100.0 * matched / total + 0.5 );
}

// coverage= for one symbol: its any-field mask (name, doc comment, body).
inline int forCoveragePct( const LexTermEvidence& ev, NodeId sym ) noexcept
{
    if( ev.maskWords == 0 || sym >= ev.symbolCount || ev.anyMask.size() != ev.symbolCount * ev.maskWords )
    {
        return -1;
    }
    return termShareWithin( ev, ev.anyMaskOf( sym ) );
}

// the r=1 symbol of a ranking: the highest score, lowest id on a tie (the (score desc, id asc) order every
// --for consumer selects with); kNoNode when nothing scored above zero — there is no top-ranked symbol then
inline NodeId topLensId( const std::vector<float>& rank ) noexcept
{
    NodeId best = kNoNode;
    for( std::size_t i = 0; i < rank.size(); ++i )
    {
        if( rank[i] > 0.0f && ( best == kNoNode || rank[i] > rank[best] ) )
        {
            best = NodeId( i );
        }
    }
    return best;
}

// The legend clause defining coverage= and the thin rule — FULL dialect (rides --for's confidence sentence and
// the MCP twin's, so one spelling) and COMPACT dialect. No "--" anywhere (an XML comment, G4): the flags are named
// without their dashes.
inline constexpr std::string_view kForCoverageLegend =
    " [coverage= is the IDF-weighted share (whole percent) of the query's subtokens in the top-ranked symbol's name, "
    "doc or body; an unmatched subtoken weighs as the rarest. It rides a THIN answer only (under 50, or a head over "
    "fewer than 3 files), whose r=1 row's next= names the file-grain page (limit=N, one row per file), not the body]";
inline constexpr std::string_view kForCompactCoverageClause =
    " [coverage=: IDF share (%) of the query's subtokens in the top symbol's name/doc/body, on a THIN answer only "
    "(under 50 or head files under 3); next= then names the file page (limit=N)]";

inline bool forAnswerIsThin( int coveragePct, std::size_t distinctHeadFiles ) noexcept
{
    return coveragePct < kForThinCoveragePct || distinctHeadFiles < kForThinMinFiles;
}

// distinct files among the ranked head — the top rows BEFORE any budget trim, so the rule reads a fact the
// header already fixed rather than one the ladder decides later. The walk is --affected's own (testmap.h), which
// partitions the files into test and non-test; the rule wants the whole count, so the two halves are summed.
inline std::size_t distinctFilesOf( const IngestResult& ing, const std::vector<NodeId>& headIds )
{
    const ChangedFileSplit split = splitChangedFilesOfSymbols( ing, headIds );
    return split.src.size() + split.tests.size();
}

// `--for=TASK --limit=N [--offset=M]`, the task quoted as a shell would need it (nextFlag). Built and emitted
// in FULL, whatever its length: nextAttrXml (nextverb.h) carries no ceiling on next= (2026-09-25 fix: a
// cut answer's next= used to be dropped past 120 B)
// — the paging quintet still says how to continue, but the attribute itself is never truncated or dropped.
// Folded onto pagedNext (nextverb.h), the same composer --tree/--zoom/--external-surface use, with
// offsetAtZero=false: --for's page 0 must stay `--limit=N` with no `--offset=0` tail (forwidencheck.sh arm 5).
inline std::string forPageInvocation( std::string_view task, int limit, int offset )
{
    return pagedNext( nextFlag( "--for=", task ), limit, std::size_t( std::max( offset, 0 ) ), /*offsetAtZero=*/false );
}

// the r=1 row's widening follow-up: the page at its default width
inline std::string forWidenNext( std::string_view task )
{
    return forPageInvocation( task, kForPageRowsDefault, 0 );
}

// ── THE BUDGETED-BUNDLE CANDIDATE PAGE (issue #294; the ruling + the #362 review round) ───────────
// What the caller passes, in one struct (the #362 review's request-struct ask: forCandidatePageDoc's
// parameter list was 12 deep; this is also the runPackTask quality gate's remedy — one struct, not
// eight loose scalars threaded through two callers).
struct ForCandidatePageReq
{
    std::string_view       task;
    std::string_view       verbName;       // "--for=" / "--pack-task=": next= names THEIR verb (#294 review)
    std::string_view       rankFlags;      // B2 (#362 review round 4): the argv fragment of every accepted flag
                                           //   that changed THIS ranking — a pasted next= without them re-ranks
                                           //   differently and walks a different list. CLI: --no-route,
                                           //   --no-mention-boost, --no-doc-mention, --cochange-boost; the MCP
                                           //   twins expose only no_route (their other lifts are env ablations,
                                           //   not request surface). The bundle-shaping set is refused beside
                                           //   a window instead (cli.h), so it never needs an echo.
    bool                   pasteHandle = true;   // B1 (#362 review round 4): every surface carries the pasteable
                                                //   handle now — the five page paths rank one list (a CLI window
                                                //   forces fullDistribution, exactly what the twins always scored
                                                //   with), so a CLI continuation of an MCP page walks the same
                                                //   candidates. The guard stays so a future caller cannot
                                                //   silently drop the handle.
    bool                   compactLegend = false;   // emit in the compact dialect (the default posture): the page is
                                                    //   compacted IN-DOC by the central layer (applyCompactDialect,
                                                    //   candidate-page) so the measured est_tokens=/over_ceiling=
                                                    //   describe the bytes actually emitted (#362 review, item 4 —
                                                    //   the CLI-side compaction used to reprice a page the trim loop
                                                    //   had measured against the full legend, and the stderr line
                                                    //   contradicted the page). Pre-compacted here, the outer layers
                                                    //   see schema= and pass it through (AlreadyCompact).
    std::string_view       routeNote;
    std::string_view       rootArg;
    rw::RedactCounts*      redactPtr = nullptr;
    std::string_view       atStamp;        // gitstamp::stampAt: the index this page answered from
    std::size_t            tokenBudget = 0;
    int                    pageLimit   = 0;
    int                    pageOffset  = 0;
};

inline std::string forCandidatePageDoc( const rw::IngestResult& ing, const std::vector<float>& lensRank,
                                        const rw::AdaptiveCut& forCut, const ForCandidatePageReq& p )
{
    using namespace rw;   // the file's idiom: function-scoped
    const std::string_view task        = p.task;
    const std::string_view verbName    = p.verbName;
    const std::string_view rankFlags   = p.rankFlags;
    const bool             pasteHandle = p.pasteHandle;
    const bool             compactLegend = p.compactLegend;
    const std::string_view routeNote  = p.routeNote;
    const std::string_view rootArg    = p.rootArg;
    rw::RedactCounts* const redactPtr = p.redactPtr;
    const std::string_view atStamp    = p.atStamp;
    const std::size_t      tokenBudget = p.tokenBudget;
    const int              pageLimit   = p.pageLimit;
    const int              pageOffset  = p.pageOffset;

    // the ranked candidate order: ALL ids sorted (score desc, id asc) — the same total order
    // packSignatures selects with — truncated to the positive-scored candidates (the set the
    // bundle's cut was against; total= counts it on EVERY page, so a re-decided denominator is
    // impossible by construction). candIdxOf maps an id back to its candidate index: the TRUE
    // resume point comes from the last PRINTED row's index + 1 (#362 review, item 2), not from
    // a served-count arithmetic that pseudo-symbols (a candidate slot with no printed row) skew.
    std::vector<NodeId>    candOrder;
    std::vector<std::uint32_t> candIdxOf( ing.symbols.size(), kNoNode );
    {
        const std::size_t S = ing.symbols.size();
        candOrder.resize( S );
        for( NodeId i = 0; i < S; ++i ) { candOrder[ i ] = i; }
        rw::sortutil::radixSortByScoreDescId( candOrder, lensRank );
        candOrder.resize( std::min( forCut.positiveHits, S ) );
        for( std::size_t k = 0; k < candOrder.size(); ++k ) { candIdxOf[ candOrder[ k ] ] = std::uint32_t( k ); }
    }
    const std::size_t candidateTotal = candOrder.size();
    PageWindow        win            = pageWindow( candidateTotal, pageLimit, pageOffset );
    // SINGLE-TIER WINDOWS (#362 review, item 4): a head window never crosses the cliff — it ends
    // AT the cliff, so every page is one tier and tier= never labels below-cliff rows as head.
    // (cliffRank is the head count itself: "a cut at rank i keeps ranks [1,i]" — lexical.h.)
    const bool below = forCut.cliffRank > 0 && win.begin >= forCut.cliffRank;
    if( forCut.cliffRank > 0 && win.begin < forCut.cliffRank && win.end > forCut.cliffRank )
    {
        win.end = forCut.cliffRank;
    }

    // window the rank copy: candidates inside [win.begin, win.end) keep their score, everything
    // else sorts below them (-1), so packSignatures' top-N selection serves exactly the window in
    // rank order — no new selection logic, and the H1 ladder still trims within the page.
    std::vector<float> pageRank( ing.symbols.size(), -1.0f );
    for( std::size_t i = win.begin; i < win.end; ++i ) { pageRank[ candOrder[ i ] ] = lensRank[ candOrder[ i ] ]; }

    // the sigs block's byte budget: the page's shell (head+tail+legend) is RESERVED ahead of it
    // (kForPageSpliceReserve, #362 review's named-constant ask), and the block never gets less
    // than kForPageSigsFloorBytes — the ONE-ROW floor (#362 review, item 3): a budget that cannot
    // fit a row serves the top row with over_ceiling="1" rather than an empty page whose next=
    // points back at itself (a stuck loop).
    constexpr std::size_t kForPageSpliceReserve    = 600;
    constexpr std::size_t kForPageSigsFloorBytes   = 512;
    const std::size_t sigsBytesBudget = tokenBudget > 0
        ? std::max<std::size_t>( std::size_t( double( tokenBudget ) * kMinBytesPerToken ) > kForPageSpliceReserve
                                   ? std::size_t( double( tokenBudget ) * kMinBytesPerToken ) - kForPageSpliceReserve : 0,
                                 kForPageSigsFloorBytes )
        : kForPageSigsFloorBytes;

    // SINK FORM (Diagnostics.h §4b — the contract selfcheckcheck (R) pins): the page document is the
    // sink. The degrade field is what the emitter reads and surfaces as reason= on the page itself,
    // so a degraded render tells the release reader IN THE ANSWER — never silently-empty stdout,
    // never a sink-less stderr-only note (selfcheckcheck: the pin goes DOWN, never up).
    struct ForPageRender
    {
        enum class DisclosureWhy : std::uint8_t { ChargeStreamRefused, ChargeStreamTorn };
        DisclosureWhy why = DisclosureWhy::ChargeStreamRefused;
        void disclose( DisclosureWhy w ) noexcept { why = w; }
    } forPageRender;

    // the printed rows: packSignatures reports the ids it EMITTED (shownIdsOut) — the honest shown
    // (rows printed) and the honest resume (the last printed row's candidate index + 1).
    std::vector<NodeId> shownIds;
    std::string         sigsDoc;
    bool                rendered = false;
    {
        const std::optional<RedactCounts> redactBefore = redactPtr != nullptr ? std::optional<RedactCounts>( *redactPtr ) : std::nullopt;
        const auto restoreRedact = [ & ]() noexcept { if( redactBefore ) { *redactPtr = *redactBefore; } };
        rw::MemoryStream stream;
        std::FILE* const buffer = rw::openChargeStream( stream );
        if( buffer == nullptr )
        {
            DISCLOSE( forPageRender, ForPageRender::DisclosureWhy::ChargeStreamRefused );
            restoreRedact();
        }
        else
        {
            packSignatures( buffer, ing, pageRank, int( win.end - win.begin ), sigsBytesBudget, /*metrics=*/true,
                            nullptr, nullptr, redactPtr,
                            nullptr, nullptr, nullptr, nullptr,      // Q3 enrichments: page rows are the core sig form
                            /*rankAdaptivePayload=*/true,
                            sigsBytesBudget,                          // H1 ladder over the page
                            nullptr, rootArg,
                            rw::SigLensRules::RelevanceFloor, nullptr,   // the PR's hasRelevanceFloor=true under 26b's SigLensRules (train-26c seam; the
                                                                         //   page rows take no e=/docs-after-code rule — open train decision, as reviewed)
                            /*shownIdsOut=*/&shownIds, /*cappedOut=*/nullptr, /*topRowNext=*/{}, /*cutOut=*/nullptr, /*spelling=*/{},
                            std::uint32_t( win.begin ) );             // rankBase: continuation rows carry their GLOBAL r= (#294 review)
            const rw::MemoryStreamBytes block = stream.finish();
            if( !block.isWhole )
            {
                DISCLOSE( forPageRender, ForPageRender::DisclosureWhy::ChargeStreamTorn );
                restoreRedact();
            }
            else
            {
                sigsDoc.assign( block.bytes );
                rendered = true;
            }
        }
    }

    // ── the assembly: one set of lambdas, reused by the degrade page AND the trim loop AND the ──
    // ── final assembly, so the three cannot drift (#362 review's reuse ask) ───────────────────
    // one scratch buffer PER attribute: the escape helper appends to the buffer and returns a view
    // of it, so two calls sharing one buffer inside one argument list race on realloc and mangle
    // each other (the bug this page's first CI round caught on route=).
    std::vector<char> escTask;  const std::string_view taskAttr  = escapeXml( task, escTask );
    std::vector<char> escRoute; const std::string_view routeAttr = escapeXml( routeNote, escRoute );
    std::vector<char> escRoot;  const std::string_view rootAttr  = escapeXml( rootArg, escRoot );
    std::vector<char> escAt;    // the at= scratch (one buffer per attribute)
    const auto buildHead = [ & ]( std::size_t shownNow, std::size_t nextOff, std::string_view extra ) {
        return "<sigs task=\"" + std::string( taskAttr ) + "\" route=\"" + std::string( routeAttr )
             + "\" shown=\"" + std::to_string( shownNow ) + "\" total=\"" + std::to_string( candidateTotal )
             // above_cliff (#362 review, item 4): the HEAD-TIER CANDIDATE COUNT — cliffRank IS that
             // count ("a cut at rank i keeps ranks [1,i]" — lexical.h), stated next to total= so an
             // agent decides from page 1 whether the below-cliff remainder is worth fetching.
             + "\" above_cliff=\"" + std::to_string( forCut.cliffRank )
             + "\" capped=\"" + ( shownNow < candidateTotal ? "1" : "0" )
             + "\" has_more=\"" + ( nextOff < candidateTotal ? "1" : "0" )
             + "\" next_offset=\"" + std::to_string( nextOff )
             + "\" offset=\"" + std::to_string( win.begin )
             + "\" limit=\"" + std::to_string( pageLimit > 0 ? pageLimit : 0 )
             + "\" tier=\"" + ( below ? "below-cliff" : "head" ) + "\""
             + std::string( extra );
    };
    // THE PASTEABLE CONTINUATION HANDLE — the file page's next= contract: the argv that walks to
    // next_offset. Dropped entirely past kNextAttrMaxBytes (a hint that pastes wrong is worse than
    // no hint) and dropped when has_more="0" (#362 review, item 3: a last page handing back a next
    // that returns an empty page carrying the same next= is a loop with no exit).
    const auto buildNextAttr = [ & ]( std::size_t nextOff ) {
        if( !pasteHandle ) { return std::string(); }   // no surface passes false today (B1); the guard stays honest
        if( nextOff >= candidateTotal ) { return std::string(); }
        std::string inv = nextFlag( verbName, task );   // THEIR verb: pasting continues the same verb (#294 review)
        inv += rankFlags;   // B2: the ranking's own flags ride the handle, or the paste re-ranks a different list
        inv += " --token-budget=" + std::to_string( tokenBudget );
        if( pageLimit > 0 ) { inv += " --limit=" + std::to_string( pageLimit ); }
        inv += " --offset=" + std::to_string( nextOff );
        if( inv.size() > kNextAttrMaxBytes ) { return std::string(); }
        return nextAttrXml( inv );
    };
    // next_tier (the ruling's suggestion 2): the tier the CONTINUATION page will carry — only
    // beside a next= (nothing further means no tier to advertise).
    const auto buildNextTierAttr = [ & ]( std::size_t nextOff ) {
        if( !pasteHandle ) { return std::string(); }   // rides beside next= only
        if( nextOff >= candidateTotal ) { return std::string(); }
        return std::string( " next_tier=\"" ) + ( ( forCut.cliffRank > 0 && nextOff >= forCut.cliffRank ) ? "below-cliff" : "head" ) + "\"";
    };
    // est_tokens is MEASURED from the page's own final bytes (legend included); the tail's digit
    // count feeds back into the total, so one re-derivation closes the loop (it converges immediately).
    const auto buildTail = [ & ]( const std::string& h, std::string_view legend, std::string_view r,
                                  bool overCeiling, std::size_t nextOff ) {
        std::size_t est = std::size_t( double( h.size() + legend.size() + r.size() + 96 ) / kMinBytesPerToken );
        std::string t;
        for( int pass = 0; pass < 3; ++pass )
        {
            t = " est_tokens=\"" + std::to_string( est )
              + "\" budget_tokens=\"" + std::to_string( tokenBudget )
              + "\" root=\"" + std::string( rootAttr ) + "\"" + buildNextAttr( nextOff ) + buildNextTierAttr( nextOff )
              + ( overCeiling ? " over_ceiling=\"1\"" : std::string() )
              + ( atStamp.empty() ? std::string() : " at=\"" + std::string( escapeXml( atStamp, escAt ) ) + "\"" ) + ">";
            const std::size_t fin = std::size_t( double( h.size() + t.size() + legend.size() + r.size() ) / kMinBytesPerToken );
            if( fin == est ) { break; }
            est = fin;
        }
        return std::pair<std::string, std::size_t>( t, est );
    };
    // THE LEGEND — the page's own vocabulary, defined the way every other answer defines its own:
    // a leading comment after the root tag, full dialect emitted here, compact dialect rewritten by
    // the central table (compactlegend.h: applyCompactDialect with the "for"/"pack-task" hint), so
    // --legend=full|compact works through the SAME machinery on both dialects (#362 review, item 5).
    // the legend text: NO double-hyphen anywhere (G4 — it rides inside an XML comment), so the
    // verbs are named dashless, the file page's own convention ("the two flags are named without
    // their dashes").
    const std::string dashlessVerb = verbName == "--pack-task=" ? std::string( "pack-task" )
                                                          : std::string( "for" );
    const std::string legend =
        "<!-- ripwire candidate-page ripwire.candidate-page/v1"
        ": the BUDGETED-BUNDLE CANDIDATE PAGE of the " + dashlessVerb + " lens — a resumable window over the SAME ranked candidate set the bundle cuts. task= the query; route= which ranker answered and why; root= the crawl root; at= the git index this page answered from (a continuation whose at= differs was served by a different index: re-run page 1). shown= rows PRINTED on this page; total= candidates in the whole set, on every page; above_cliff= the head-tier candidate count (cliffRank: a cut at rank i keeps ranks [1,i]); tier= THIS page's tier, head or below-cliff, one tier per page, the window ends at the cliff; next_tier= the next page's tier; capped= 1 when shown < total; has_more=/next_offset= the resume (the candidate index the next page starts at); offset=/limit= this page's window; r= each row's GLOBAL candidate rank (pages merge without duplicate r); next= the pasteable argv that walks to next_offset (dropped when has_more=0: nothing further); budget_tokens= the ceiling this page answers under; est_tokens= this page's measured size; over_ceiling= 1 when est_tokens exceeds budget_tokens (the budget could not fit the window: fewer rows were served, never silently more bytes); reason= names a degraded render (the sigs block was lost, not hidden) -->";

    // the honest degrade page: the emitter READS the sink — the full quintet with zero rows and
    // reason= naming what was lost, built by the SAME lambdas so it cannot drift (#362 review's ask).
    if( !rendered )
    {
        const std::string reason = " reason=\"" + std::string( forPageRender.why == ForPageRender::DisclosureWhy::ChargeStreamTorn
                                                    ? "sigs-charge-stream-torn" : "sigs-charge-stream-refused" ) + "\"";
        const std::string h = buildHead( 0, win.end, reason );
        const auto [ t, est ] = buildTail( h, legend, "</sigs>", /*overCeiling=*/false, win.end );
        return h + t + legend + "</sigs>";
    }
    // rows: packSignatures' <sigs> block minus its own open tag (kept verbatim with its close).
    const std::size_t openBeg  = sigsDoc.find( "<sigs" );
    const std::size_t openEnd  = sigsDoc.find( '>' );
    const std::size_t keepFrom = ( openBeg != std::string::npos && openEnd != std::string::npos ) ? openEnd + 1 : 0;
    std::string rowsNow = sigsDoc.substr( keepFrom );

    // THE TRUE RESUME (#362 review, item 2): the last PRINTED row's candidate index + 1 — NOT
    // win.begin + a served count: a pseudo-symbol (a candidate slot packSignatures serves without
    // printing a row) skews the arithmetic one short, and the next page re-serves the last row
    // (the duplicate seam). shownIds is packSignatures' own emitted-ids report, in rank order.
    std::size_t kept    = shownIds.size();
    std::size_t nextNow = ( kept > 0 ) ? std::size_t( candIdxOf[ shownIds.back() ] ) + 1 : win.end;
    // the forward guarantee (#362 review, item 3): next_offset ALWAYS moves past this page's
    // window start when anything was printed — a next= that points back at the page it came
    // from is a loop with no exit.
    if( kept > 0 && nextNow <= win.begin ) { nextNow = win.begin + 1; }

    // THE BUDGET TRIM (#362 review, item 1): the page IS an answer under the budget. The H1
    // ladder already trimmed within the block; if the assembled page still exceeds, drop
    // trailing WHOLE rows — cutting at the START of the last row (a cut at its close leaves
    // the row open and the document malformed) — never below ONE row while the window is
    // non-empty (item 3: a budget that cannot fit a row serves the top row with over_ceiling="1"
    // rather than an empty page whose next= points back at itself), and re-derive the page's own
    // arithmetic (shown/next_offset/has_more/next=) from what shipped.
    std::string h = buildHead( kept, nextNow, {} );
    auto [ t, est ] = buildTail( h, legend, rowsNow, /*overCeiling=*/false, nextNow );
    if( tokenBudget > 0 && est > tokenBudget )
    {
        const std::size_t rowFloor = ( win.end > win.begin ) ? std::size_t( 1 ) : std::size_t( 0 );
        while( kept > rowFloor && est > tokenBudget )
        {
            const std::size_t lastClose = rowsNow.rfind( "</d>" );
            const std::size_t rowStart  = rowsNow.rfind( "<d ", lastClose );
            if( lastClose == std::string::npos || rowStart == std::string::npos ) { break; }
            rowsNow = rowsNow.substr( 0, rowStart ) + "</sigs>";
            --kept;
            nextNow = ( kept > 0 ) ? std::size_t( candIdxOf[ shownIds[ kept - 1 ] ] ) + 1 : win.end;
            h = buildHead( kept, nextNow, {} );
            std::tie( t, est ) = buildTail( h, legend, rowsNow, /*overCeiling=*/false, nextNow );
            if( est <= tokenBudget ) { break; }
        }
        if( est > tokenBudget )
        {
            std::tie( t, est ) = buildTail( h, legend, rowsNow, /*overCeiling=*/true, nextNow );
        }
    }
    std::string pageOut = h + t + legend + rowsNow;
    // (#362 review, item 4) the dialect actually emitted: compact first (the central layer — it
    // reprices est_tokens= and settles over_ceiling= on the bytes it writes), so the page's own
    // numbers describe what ships; the outer layers see schema= and pass it through untouched.
    if( compactLegend )
    {
        applyCompactDialect( pageOut, "candidate-page" );
    }
    // the stderr notice reads the FINAL page: est_tokens straight off the emitted root, so the
    // line can never contradict the document (the full-dialect trim numbers used to).
    if( tokenBudget > 0 )
    {
        const std::size_t finalEst = rootUnsignedAttr( std::string_view( pageOut ).substr( pageOut.find( '<' ), pageOut.find( '>' ) + 1 ), "est_tokens" );
        if( finalEst > tokenBudget && pageOut.find( " over_ceiling=\"1\"" ) != std::string::npos )
        {
            rw::emitTo( stderr, "ripwire: for-page est_tokens={} exceeds the stated budget={} — the window cannot fit; "
                               "the top row is served with over_ceiling=1\n", finalEst, tokenBudget );
        }
    }
    return pageOut;
}


struct ForFileRow
{
    std::uint32_t fileId      = 0;
    std::uint32_t symbolCount = 0;      // positive-score symbols in the file (n=)
    float         best        = 0.f;    // the file's best symbol's lens score (the tie-break)
    double        share       = 0.0;    // U_f in [0,1] — the score
    NodeId        top[ kForPageSymNameCount ] = { kNoNode, kNoNode, kNoNode };
};

struct ForFilePage
{
    std::vector<ForFileRow> rows;   // EVERY positive-score file, page order — the window is applied at render
};

// one more positive-score symbol of a file, in lens order: its terms join the union while the file is under the
// contribution cap, its name joins sym= while the file is under the name count, and n= counts it either way
inline void forFileRowAbsorb( ForFileRow& row, std::uint64_t* unionWords, const LexTermEvidence& ev, NodeId id, bool evidenceOk )
{
    if( evidenceOk && row.symbolCount < kForPageUnionSymbolCap && id < ev.symbolCount )
    {
        const std::uint64_t* src = ev.anyMaskOf( id );
        for( std::size_t w = 0; w < ev.maskWords; ++w )
        {
            unionWords[w] |= src[w];
        }
    }
    if( row.symbolCount < kForPageSymNameCount )
    {
        row.top[ row.symbolCount ] = id;
    }
    ++row.symbolCount;
}

// (share desc, best desc, path asc): a total order — paths are unique per file
inline bool forFileRowBefore( const IngestResult& ing, const ForFileRow& a, const ForFileRow& b ) noexcept
{
    if( a.share != b.share ) { return a.share > b.share; }
    if( a.best != b.best )   { return a.best > b.best; }
    return ing.files[ a.fileId ] < ing.files[ b.fileId ];
}

// The page's ranking, from the finished lens ranking (every lift applied) and the term evidence.
inline ForFilePage computeForFilePage( const IngestResult& ing, const std::vector<float>& rank, const LexTermEvidence& ev )
{
    ForFilePage       out;
    const std::size_t S = std::min( ing.symbols.size(), rank.size() );
    const std::size_t F = ing.files.size();
    if( S == 0 || F == 0 )
    {
        return out;
    }
    std::vector<NodeId> order( S );
    for( NodeId i = 0; i < S; ++i )
    {
        order[i] = i;
    }
    sortutil::radixSortByScoreDescId( order, rank );

    const std::size_t          words      = ev.maskWords;
    const bool                 evidenceOk = words > 0 && ev.anyMask.size() == ev.symbolCount * words;
    std::vector<std::uint32_t> rowOfFile( F, UINT32_MAX );
    std::vector<std::uint64_t> unionMask;   // rows × words, grown as rows are opened
    for( std::size_t k = 0; k < S && rank[ order[k] ] > 0.0f; ++k )   // (score desc) order: the zero-score tail is contiguous
    {
        const NodeId        id = order[k];
        const std::uint32_t f  = ing.symbols[id].fileId;
        if( f >= F )
        {
            continue;
        }
        if( rowOfFile[f] == UINT32_MAX )
        {
            rowOfFile[f] = std::uint32_t( out.rows.size() );
            out.rows.push_back( ForFileRow{ f, 0u, rank[id], 0.0, { kNoNode, kNoNode, kNoNode } } );
            unionMask.resize( unionMask.size() + words, 0u );
        }
        forFileRowAbsorb( out.rows[ rowOfFile[f] ], unionMask.data() + std::size_t( rowOfFile[f] ) * words, ev, id, evidenceOk );
    }
    for( std::size_t r = 0; r < out.rows.size(); ++r )
    {
        const int pct     = evidenceOk ? termShareWithin( ev, unionMask.data() + r * words ) : -1;
        out.rows[r].share = pct < 0 ? 0.0 : double( pct ) / 100.0;
    }
    std::stable_sort( out.rows.begin(), out.rows.end(), [ & ]( const ForFileRow& a, const ForFileRow& b ) { return forFileRowBefore( ing, a, b ); } );
    return out;
}

// The full legend of the page document. No "--" anywhere: it rides inside an XML comment (G4), so the two
// flags are named without their dashes.
inline constexpr std::string_view kForPageLegend =
    ": the file-grain WIDENING page of the for lens (task= the query, route= which ranker answered and why, root= "
    "the crawl root), ONE row per file, every file holding a positive-score symbol for this task, ranked "
    "file-first: score= the IDF-weighted share of the query's subtokens the file's "
    "top 8 symbols cover between them (whole percent; a term counts once however often it recurs, so one huge "
    "file cannot monopolise), ties by the best symbol's lens score then path; n= positive-score symbols in the "
    "file; sym= its top symbols by lens rank; p= the file. coverage= is the lens root's gauge: the same share "
    "for the top-ranked symbol alone (name, doc and body). shown=/total=/capped=1 when this page cut the list; "
    "offset=/limit=/has_more=/next_offset= page it and next= is the next page, pasted as-is";
inline constexpr std::string_view kForPageLegendCompact =
    ": file-grain widening page (task= the query, route= the ranker that answered), one <f> row per positive-score "
    "file: score= IDF-weighted share of the query's "
    "subtokens the file's top 8 symbols cover together (%, a term counts once), ties by best symbol then path; "
    "n= positive symbols; sym= top symbols; coverage= the top symbol's own share; shown=/total=/capped=1 when cut; "
    "offset=/limit=/has_more=/next_offset= page it, next= the next page; root= the crawl root";

// What the page document is rendered from, beside the rows: the task and the lens root's own open tag (ctxRootOpen's
// output — task=/route=/root= and the scrub tells — re-tagged <files>, so the two roots spell and escape their shared
// attributes identically), the coverage= gauge, the window, and the dialect.
struct ForPageRenderParts
{
    std::string_view task;
    std::string_view rootOpen;
    int              coveragePct;
    int              limit;
    int              offset;
    std::string_view rootArg;
    bool             compactLegend;
};

inline std::string renderForFilePageXml( const IngestResult& ing, const ForFilePage& page, const ForPageRenderParts& p )
{
    std::vector<char> esc;
    std::string       x;
    x.reserve( 512 + page.rows.size() * 120 );
    const std::size_t total  = page.rows.size();
    const PageWindow  window = pageWindow( total, p.limit, p.offset );
    const std::size_t shown  = window.end - window.begin;

    x += "<files";
    if( p.rootOpen.size() > 5 && p.rootOpen.substr( 0, 4 ) == "<ctx" && p.rootOpen.back() == '>' )
    {
        x.append( p.rootOpen.data() + 4, p.rootOpen.size() - 5 );   // the attributes between "<ctx" and ">"
    }
    if( p.coveragePct >= 0 )
    {
        x += " coverage=\"" + std::to_string( p.coveragePct ) + "\"";
    }
    char disc[ kPageDisclosureCap ];
    x += pageDisclosure( disc, sizeof( disc ), shown, total, window.end, p.limit, p.offset, /*discloseCap=*/true );
    if( window.end < total )
    {
        x += nextAttrXml( forPageInvocation( p.task, p.limit > 0 ? p.limit : kForPageRowsDefault, int( window.end ) ) );
    }
    x += ">";
    x += p.compactLegend ? "<!-- ripwire for-page ripwire.for-page/v1" : "<!-- ripwire for-page";
    x += p.compactLegend ? kForPageLegendCompact : kForPageLegend;
    x += " -->";
    x += forRootRelPathsLegendShort( !p.rootArg.empty() );
    for( std::size_t r = window.begin; r < window.end; ++r )
    {
        const ForFileRow& row = page.rows[r];
        x += "<f p=\"";  x += escapeXml( lensRowPath( ing, row.fileId, p.rootArg ), esc );
        x += "\" score=\"" + std::to_string( int( row.share * 100.0 + 0.5 ) );
        x += "\" n=\"" + std::to_string( row.symbolCount ) + "\" sym=\"";
        for( std::size_t k = 0; k < kForPageSymNameCount && row.top[k] != kNoNode; ++k )
        {
            if( k > 0 ) { x += ","; }
            x += escapeXml( ing.symbols[ row.top[k] ].name, esc );
        }
        x += "\"/>";
    }
    x += "</files>";
    return x;
}

}   // namespace rw
