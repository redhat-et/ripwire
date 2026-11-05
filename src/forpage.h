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

#include "mention.h"     // ForNamedHeaderRow — forHdrRowsXml below renders the resolver's rows
#include "infra/enumcount.h" // enumCountIsExact — TailPageRowFate's count beside the enum
#include "filter.h"      // taskAsksAboutDocs — the code-first tail asks the docs reorder's own question
#include "lexical.h"     // LexTermEvidence — the term masks + df the BM25 pass already accumulated
#include "model.h"
#include "nextverb.h"    // nextFlag / nextAttrXml — the ONE next= spelling
#include "pageview.h"    // pageWindow / pageDisclosure — the shared --limit/--offset vocabulary
#include "serialize.h"   // escapeXml, lensRowPath, ctxRootOpen, radixSortByScoreDescId
#include "testmap.h"     // splitChangedFilesOfSymbols — the ONE "distinct files of a symbol set" walk (--affected's)

#include <algorithm>
#include <cstddef>
#include <numeric>
#include <ranges>
#include <span>
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

// ── THE ATTRIBUTE SHED (#520, the budget ruling 2026-11-03: "the goal is complete answers in efficient bytes and
// cutting answers is most often counter productive") ─────────────────────────────────────────────────────────────
// A page that still exceeds an explicit --token-budget at its ONE-ROW floor sheds the row's OPTIONAL attributes
// instead of cutting the answer: the row and what identifies it (n= l= p= the kind and the signature text, r=) always
// ship. Two rungs, the cheapest first, stopping at the first that fits: the metrics, the layer and the row's own
// follow-up, then the enclosing scope (p= l= n= still name the definition; the full id loses only its sc:: middle).
// When neither fits, the unshed page ships with over_ceiling="1": a shed that still misses the budget only trades
// attributes for a legend clause.
// The compact legend is built from the attributes present, so each shed attribute takes its clause with it.
inline constexpr std::string_view kForPageShedRungMetrics[] = { "cx", "ccx", "layer", "next" };
inline constexpr std::string_view kForPageShedRungScope[]   = { "cx", "ccx", "layer", "next", "sc" };
inline constexpr std::string_view kForPageShedAttr          = " attrs_shed=\"1\"";
inline constexpr std::string_view kForPageShedLegend =
    " attrs_shed= 1 when the one-row floor still exceeded budget_tokens, so the row's optional attributes"
    " (cx= ccx= layer= its next=, then sc=) were dropped; the row itself is never dropped";

// Drop the named attributes from every element open tag in `rows` (the page's row block: no CDATA, attribute values
// escaped, so a quote always closes a value). Text between tags is copied verbatim.
inline void shedRowAttrs( std::string& rows, std::span<const std::string_view> names )
{
    std::string       out;
    out.reserve( rows.size() );
    const std::size_t n = rows.size();
    std::size_t       i = 0;
    while( i < n )
    {
        const std::size_t lt = rows.find( '<', i );
        if( lt == std::string::npos ) { out.append( rows, i, n - i ); break; }
        out.append( rows, i, lt - i );
        std::size_t j = lt + 1;
        while( j < n && rows[ j ] != ' ' && rows[ j ] != '>' && rows[ j ] != '/' ) { ++j; }
        out.append( rows, lt, j - lt );
        // the attribute list: ` name="value"` repeated; anything else ends it and is copied as text
        while( j < n && rows[ j ] == ' ' )
        {
            const std::size_t eq = rows.find( '=', j );
            if( eq == std::string::npos || eq + 1 >= n || rows[ eq + 1 ] != '"' ) { break; }
            const std::size_t close = rows.find( '"', eq + 2 );
            if( close == std::string::npos ) { break; }
            const std::string_view name( rows.data() + j + 1, eq - j - 1 );
            if( std::find( names.begin(), names.end(), name ) == names.end() ) { out.append( rows, j, close + 1 - j ); }
            j = close + 1;
        }
        i = j;
    }
    rows = std::move( out );
}

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
    const auto emittedEst = [ & ]() {
        return rootUnsignedAttr( std::string_view( pageOut ).substr( pageOut.find( '<' ), pageOut.find( '>' ) + 1 ), "est_tokens" );
    };
    // THE ATTRIBUTE SHED (see kForPageShedRungMetrics): only past the one-row floor of an explicit budget, judged on the
    // bytes this dialect emits — a page that fits never reaches it and stays byte-identical.
    if( tokenBudget > 0 && kept == 1 && emittedEst() > tokenBudget )
    {
        // a shed that cannot reach the budget is not byte-efficient (the full legend's clause can outweigh what it drops):
        // then the unshed page ships, over_ceiling="1" as before — never a page that sheds and still misses
        std::string unshed = pageOut;
        bool        fits   = false;
        std::string legendShed = legend;
        legendShed.insert( legendShed.size() - std::string_view( " -->" ).size(), kForPageShedLegend );
        for( const std::span<const std::string_view> rung : { std::span<const std::string_view>( kForPageShedRungMetrics ),
                                                              std::span<const std::string_view>( kForPageShedRungScope ) } )
        {
            std::string rowsShed = rowsNow;
            shedRowAttrs( rowsShed, rung );
            h = buildHead( kept, nextNow, kForPageShedAttr );
            std::tie( t, est ) = buildTail( h, legendShed, rowsShed, /*overCeiling=*/false, nextNow );
            if( est > tokenBudget ) { std::tie( t, est ) = buildTail( h, legendShed, rowsShed, /*overCeiling=*/true, nextNow ); }
            pageOut = h + t + legendShed + rowsShed;
            if( compactLegend ) { applyCompactDialect( pageOut, "candidate-page" ); }
            if( emittedEst() <= tokenBudget ) { fits = true; break; }
        }
        if( !fits ) { pageOut = std::move( unshed ); }
    }
    // the stderr notice reads the FINAL page: est_tokens straight off the emitted root, so the
    // line can never contradict the document (the full-dialect trim numbers used to).
    if( tokenBudget > 0 )
    {
        const std::size_t finalEst = emittedEst();
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
    NodeId        top[ kForPageSymNameCount ] = { kNoNode, kNoNode, kNoNode };   // the names sym= prints (no reST label)
    NodeId        lead        = kNoNode;   // the file's best symbol, whatever it is (the row opened at it)
    std::uint32_t named       = 0;         // top[] entries filled
};

struct ForFilePage
{
    std::vector<ForFileRow> rows;   // EVERY positive-score file, page order — the window is applied at render
};

// one more positive-score symbol of a file, in lens order: its terms join the union while the file is under the
// contribution cap, its name joins sym= while the file is under the name count, and n= counts it either way
// `nameable` false (a reST label, filter.h isRestLabelUnit): the label names the title beside it, which sym= already
// carries, so it joins n= and the term union but takes no name slot (DOCS-REST M2: 274 of 739 reST rows spent one).
inline void forFileRowAbsorb( ForFileRow& row, std::uint64_t* unionWords, const LexTermEvidence& ev, NodeId id, bool evidenceOk,
                              bool nameable = true )
{
    if( evidenceOk && row.symbolCount < kForPageUnionSymbolCap && id < ev.symbolCount )
    {
        const std::uint64_t* src = ev.anyMaskOf( id );
        for( std::size_t w = 0; w < ev.maskWords; ++w )
        {
            unionWords[w] |= src[w];
        }
    }
    if( row.symbolCount == 0 )
    {
        row.lead = id;
    }
    if( nameable && row.named < kForPageSymNameCount )
    {
        row.top[ row.named++ ] = id;
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
        forFileRowAbsorb( out.rows[ rowOfFile[f] ], unionMask.data() + std::size_t( rowOfFile[f] ) * words, ev, id, evidenceOk,
                          !isRestLabelUnit( ing, ing.symbols[id] ) );
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
    "file for this task (not the file's whole symbol count, which the expand flag reports as sibs_total=); "
    "sym= its top symbols by lens rank; p= the file. coverage= is the lens root's gauge: the same share "
    "for the top-ranked symbol alone (name, doc and body). shown=/total=/capped=1 when this page cut the list; "
    "offset=/limit=/has_more=/next_offset= page it and next= is the next page, pasted as-is";
inline constexpr std::string_view kForPageLegendCompact =
    ": file-grain widening page (task= the query, route= the ranker that answered), one <f> row per positive-score "
    "file: score= IDF-weighted share of the query's "
    "subtokens the file's top 8 symbols cover together (%, a term counts once), ties by best symbol then path; "
    "n= positive symbols for this task (not expand's sibs_total= file count); sym= top symbols; coverage= the top symbol's own "
    "share; shown=/total=/capped=1 when cut; "
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


// R2-AF (round 2, S4): the <hdr p= of=/> rows of a --for answer (rw::forNamedHeaderRows, mention.h, resolves them) — ONE render
// for the CLI --for (verbs_for.h renderForHdrRowsXml) and the MCP `for` twin, root-relative like every other --for path.
// "" when the task names nothing with a unique partner.
inline std::string forHdrRowsXml( const IngestResult& ing, const std::vector<ForNamedHeaderRow>& rows, std::string_view rootArg )
{
    std::string x;
    std::vector<char> esc;
    for( const ForNamedHeaderRow& row : rows )
    {
        // local invariant: forNamedHeaderRows only ever returns fileIds it read out of ing.files itself (mention.h), so an
        // out-of-range id here would mean that resolver's own contract broke — trapped where the bad index would be used
        ASSUME( row.partnerFile < ing.files.size() && row.namedFile < ing.files.size() );
        x += "<hdr p=\"";
        x += escapeXml( lensRowPath( ing, row.partnerFile, rootArg ), esc );
        x += "\" of=\"";
        x += escapeXml( lensRowPath( ing, row.namedFile, rootArg ), esc );
        x += "\"/>";
    }
    return x;
}

// ── FOLD C (forbudget-soft round C, owner decision 2026-10-14): the --for answer's <tail> carries page 0 of this page ──
// One model and one renderer for the CLI --for (XML + JSON) and the MCP `for` twin. The tail lists, in this order:
//   1. RANK rows (deep-tail d2, unchanged): the files of positive-score symbols NOT among the shown sigs rows, in the
//      best-symbol projection of the lens's own (score desc, id asc) order — the files of trimmed rows first; at most
//      kForFileTailShownCap; each `<t p=… sym=…/>` with the file's top symbols by lens rank (tail-sym, train 30: the page
//      row's own top[], so a rank row and a page row of one file name the same symbols). H2H-Graft lane 2: a row the ranked
//      head did not show lands here.
//   2. PAGE rows (FOLD C): the first kForFileTailPageWalk rows of the file page (computeForFilePage, the same ranking and term
//      evidence; FOR-TAIL-WIDE 2026-11-04: 4 pages, it was page 0 of `--for=TASK --limit=40`), minus the files already listed
//      above; a row from page 0 with sym= (its top symbols by lens rank), a later row p= only. The measured arm M4 appended
//      this page to the answer: 6 of 6 predicted rows reached an R0-missing item; the rank rows stay because two graded rows
//      (textual-13/14) reach their item only through them, and M4 kept them too.
// total= every positive-score file (the page's total=); a cut tail's next= is the page from the first page row it did not
// print — a superset of what it left out, so every cut is recoverable in one call.
static_assert( kForFileTailPageRows == std::size_t( kForPageRowsDefault ), "the --for tail carries the file page's first page" );

struct FileTail
{
    std::vector<std::string>  paths;     // printed order: the rank rows, then the page rows (display form, R-R)
    std::vector<std::string>  syms;      // a row's sym= (comma-joined, unescaped): the file's top lens symbols, either row kind
    std::vector<std::size_t>  pageNext;  // per row: the page offset continuing a tail that ends at it (0 on a rank row
                                         //   before any page row: the whole page continues it)
    std::size_t               total = 0; // every positive-score file: the page's total=
    std::size_t               pageSeen = 0;   // page rows the tail walked (listed here or above): a whole tail continues there
    std::size_t               pageSkip = SIZE_MAX;   // code first: the first walked page row left unlisted (a doc row past the
                                                     //   plain page window); next= never continues past it
    std::string               task;      // the --for task: a cut tail's next= names the page
    // FOR-TAIL-WIDE (fix round 1, review F1/F2): the rows the old 40-row walk lists are a PREFIX — rank rows, page rows 1-40 (on a
    // code question: its first 40 code rows), then their doc rows — and the widened rows (p= only) follow all of them, in page
    // order. `oldRows` counts that prefix; oldPageSeen/oldPageSkip are what that walk's own counters read, so fileTailOldWalk
    // rebuilds the 40-row walk's tail byte for byte (the soft-target reserve charges THAT, never the widened rows).
    std::size_t               oldRows = 0;
    std::size_t               oldPageSeen = 0;
    std::size_t               oldPageSkip = SIZE_MAX;
};

// a file page row's sym= value: the file's top symbols by lens rank (row.top[], at most kForPageSymNameCount), comma-joined,
// unescaped — "" for a row with none. The ONE spelling both tail row kinds print.
inline std::string forFileRowSymNames( const IngestResult& ing, const ForFileRow& row )
{
    std::string sym;
    for( std::size_t k = 0; k < kForPageSymNameCount && row.top[k] != kNoNode; ++k )
    {
        ASSUME( row.top[k] < ing.symbols.size(), "forFileRowSymNames: a page row names a symbol outside the index" );
        sym += k > 0 ? "," : "";
        sym += ing.symbols[ row.top[k] ].name;
    }
    return sym;
}

inline constexpr std::uint32_t kNoPageRow = UINT32_MAX;

// fileId -> its row in `page`, kNoPageRow for a file holding no positive-score symbol
inline std::vector<std::uint32_t> forPageRowOfFile( const ForFilePage& page, std::size_t fileCount )
{
    std::vector<std::uint32_t> rowOf( fileCount, kNoPageRow );
    for( std::size_t r = 0; r < page.rows.size(); ++r )
    {
        if( page.rows[r].fileId < fileCount )
        {
            rowOf[ page.rows[r].fileId ] = std::uint32_t( r );
        }
    }
    return rowOf;
}

// a rank row's sym=: the page row of file `f` (opened by the same lens walk at `ranked`, the file's best symbol), "" if none
inline std::string forPageSymOfFile( const IngestResult& ing, const ForFilePage& page, const std::vector<std::uint32_t>& rowOf,
                                     std::uint32_t f, NodeId ranked )
{
    if( f >= rowOf.size() || rowOf[f] == kNoPageRow )
    {
        return {};
    }
    const ForFileRow& row = page.rows[ rowOf[f] ];
    ASSUME( row.lead == ranked, "forPageSymOfFile: the page row of a rank row's file does not open at the symbol that ranked it" );
    return forFileRowSymNames( ing, row );
}

// The code-first walk's window rule, shared by both row kinds: a doc row met while `walked` < `window` is listed, a Sphinx .txt
// page only while fewer than kForFileTailSphinxTxtRows of them are (`txtListed`); such a page takes no window row.
inline bool docRowInWindow( bool txt, std::size_t& walked, std::size_t window, std::size_t txtListed ) noexcept
{
    const bool inWindow = walked < window && ( !txt || txtListed < kForFileTailSphinxTxtRows );
    walked += txt ? 0 : 1;   // the pages that arrived with Sphinx .txt take no window row
    return inWindow;
}

// One walked row's code-first verdict: a doc row (`docs` set and a doc-language lead), a Sphinx .txt page, and whether it is listed
// under docRowInWindow (a code row always is). Counts the row into `walked` either way, as the plain walk's window does.
struct TailRowAdmit
{
    bool isDoc    = false;
    bool txt      = false;
    bool inWindow = true;
};
inline TailRowAdmit admitTailRow( const IngestResult& ing, NodeId lead, const FileTail* docs, std::size_t& walked, std::size_t window ) noexcept
{
    TailRowAdmit a;
    a.isDoc    = docs != nullptr && lead < ing.symbols.size() && isDocLang( ing.symbols[ lead ].lang );
    a.txt      = a.isDoc && isSphinxTxtUnit( ing, ing.symbols[ lead ] );
    a.inWindow = !a.isDoc || docRowInWindow( a.txt, walked, window, docs->total );
    walked += a.isDoc ? 0 : 1;
    return a;
}

// List file `f` as a tail row: into `wide` when given (a row past the old walk's cut), else into `docs` for a doc row, else into
// `out`. A Sphinx .txt page counts in docs->total wherever it is listed (the kForFileTailSphinxTxtRows allowance is one count).
inline void listTailRow( FileTail& out, FileTail* docs, const TailRowAdmit& a, std::vector<char>& listed, std::uint32_t f, std::string path,
                         std::string sym, std::size_t next, FileTail* wide = nullptr )
{
    listed[f]    = 1;
    FileTail& to = wide != nullptr ? *wide : a.isDoc ? *docs : out;
    if( a.txt )
    {
        docs->total += 1;   // only the docs tail counts, and only its Sphinx .txt pages (a.txt implies a code-first walk)
    }
    to.paths.push_back( std::move( path ) );
    to.syms.push_back( std::move( sym ) );
    to.pageNext.push_back( next );
}

// 1. the rank rows: the best-symbol projection of the lens order, outside the shown head's files; marks each file it lists.
//    tail-sym (train 30): each row's sym= is that file's page row's top symbols (`page` holds EVERY positive-score file and
//    a rank row's file has a positive-score symbol, so its row exists) — reused from computeForFilePage, never recomputed.
//    The same (score desc, id asc) walk opens the page row at the file's best symbol, so the first name is the symbol that
//    ranked this row; the rest are the file's next symbols by lens rank. A pointer into the file, not the answer.
//    CODE FIRST (`docs` non-null, a code question; computeFileTail): a doc file does not take one of the kForFileTailShownCap
//    slots. The walk goes on until that many CODE files are listed; a doc file it meets within the first kForFileTailShownCap
//    files (the rows the plain walk would have shown; a Sphinx .txt page counts no row there, and at most
//    kForFileTailSphinxTxtRows of those pages go, docs->total counting them) goes to `docs`, which computeFileTail appends
//    after every code row.
inline void fileTailRankRows( FileTail& out, std::vector<char>& listed, const IngestResult& ing, const std::vector<float>& rank,
                              const ForFilePage& page, const std::vector<char>& inHead, std::string_view rootArg,
                              FileTail* docs = nullptr )
{
    const std::size_t                F         = ing.files.size();
    const std::vector<std::uint32_t> pageRowOf = forPageRowOfFile( page, F );
    const std::size_t                S         = std::min( ing.symbols.size(), rank.size() );
    std::vector<NodeId>              order( S );
    std::iota( order.begin(), order.end(), NodeId( 0 ) );
    sortutil::radixSortByScoreDescId( order, rank );
    std::size_t walked = 0;   // distinct files met, code and doc, a Sphinx .txt page not counted: the plain walk's window
    for( std::size_t k = 0; k < S && out.paths.size() < kForFileTailShownCap && rank[ order[k] ] > 0.0f; ++k )   // the zero-score tail is contiguous
    {
        const std::uint32_t f = ing.symbols[ order[k] ].fileId;
        if( f >= F || listed[f] || ( f < inHead.size() && inHead[f] ) )
        {
            continue;
        }
        const TailRowAdmit a = admitTailRow( ing, order[k], docs, walked, kForFileTailShownCap );
        if( a.inWindow )
        {
            const std::size_t next = a.isDoc && pageRowOf[f] != kNoPageRow ? std::size_t( pageRowOf[f] ) + 1 : 0;   // a doc row: where the page holds it
            listTailRow( out, docs, a, listed, f, lensRowPath( ing, f, rootArg ), forPageSymOfFile( ing, page, pageRowOf, f, order[k] ), next );
        }
    }
}

// Does the page walk still have a row to read? Plain: while r is inside the walked window; code first: until kForFileTailPageWalk
// CODE rows were met (doc rows ride their own allowance).
inline bool tailPageWalkOpen( bool codeFirst, std::size_t r, std::size_t pageSeen, std::size_t codeSeen ) noexcept
{
    return codeFirst ? codeSeen < kForFileTailPageWalk : r < pageSeen;
}

// What the old 40-row walk (page 0) would have listed at this row: `code` for a code row (plain walk: page index < 40; code first:
// among the first 40 CODE rows), `doc` for a doc row (a window row met while fewer than 40 were walked). Both read BEFORE the row
// counts, off the same counters admitTailRow advances.
// `open`: was the old walk still reading at this row (its loop test: code first, fewer than 40 code rows met; plain, r < 40)?
struct TailOldWalk
{
    bool code = false, doc = false, open = false;
};
inline TailOldWalk tailOldWalkAt( bool codeFirst, std::size_t r, std::size_t codeSeen, std::size_t windowSeen ) noexcept
{
    const bool open = ( codeFirst ? codeSeen : r ) < kForFileTailPageRows;
    return { open, windowSeen < kForFileTailPageRows, open };
}

// The old walk's own continuation counters at one walked row (review F1): pageSeen grows while it was open; pageSkip marks the
// first unlisted row it met that it would not have listed (a doc row past its 40-row window, or past the Sphinx .txt allowance).
inline void tailOldWalkCounters( FileTail& out, const TailOldWalk& old, bool oldListed, std::size_t r ) noexcept
{
    if( old.open )
    {
        out.oldPageSeen = std::max( out.oldPageSeen, r + 1 );
        out.oldPageSkip = oldListed ? out.oldPageSkip : std::min( out.oldPageSkip, r );
    }
}

// 2. the page rows: the file page's first kForFileTailPageWalk rows (FOR-TAIL-WIDE: 4 pages; it was page 0), minus the files
//    already listed, in the page's own order. sym= rides a row the old 40-row walk listed (the old cut: page index <
//    kForFileTailPageRows; code first, the page's first kForFileTailPageRows CODE rows and the doc rows within that window);
//    a row past it prints p= only (about a third to a half of a full row: 46.8 B mean on the 321 in-sample calls, 70.6 B on
//    vscode, against 127.4 B per sym= row) and goes to `wide`, which computeFileTail appends after every row the old walk lists
//    (review F2: so a budgeted fill never shows a p=-only row before a sym= row of the old walk). Past the old cut a file the
//    head already shows (`inHead`, the same mask the rank rows skip) is not listed (review F4: the head names it already).
//    CODE FIRST (`docs` non-null): the walk covers the page's first kForFileTailPageWalk CODE rows, so a doc row never takes a
//    code row's place. A doc row within the plain walk's window (the first kForFileTailPageWalk page rows, a Sphinx .txt page
//    not counted: those pages arrived after the window was tuned, and at most kForFileTailSphinxTxtRows of them in all, counted
//    in docs->total) goes to `docs`; one past it is left out and pageSkip marks the first such row, so next= continues no
//    later than there.
// One walked page row's fate: listed above -> Skip; a doc row past every window -> SkipMarked (next= continues no later than it);
// a widened row naming a file the head shows -> SkipHead (review F4); else listed, with sym= when the old walk lists it.
enum class TailPageRowFate : std::uint8_t
{
    Skip,
    SkipMarked,
    SkipHead,
    ListSym,
    ListWide
};
inline constexpr std::size_t kTailPageRowFateCount = static_cast<std::size_t>( TailPageRowFate::ListWide ) + 1;
static_assert( enumCountIsExact<TailPageRowFate, kTailPageRowFateCount>(), "kTailPageRowFateCount must name the LAST TailPageRowFate — move it with the append" );
inline TailPageRowFate tailPageRowFate( bool unlisted, const TailRowAdmit& a, bool symRow, bool headFile ) noexcept
{
    if( !unlisted )
    {
        return TailPageRowFate::Skip;
    }
    if( !a.inWindow )
    {
        return TailPageRowFate::SkipMarked;
    }
    if( symRow )
    {
        return TailPageRowFate::ListSym;
    }
    return headFile ? TailPageRowFate::SkipHead : TailPageRowFate::ListWide;
}

// A file id's byte in a per-file mask; an id past the mask reads as `absent`.
inline bool tailMaskAt( const std::vector<char>& mask, std::size_t f, bool absent ) noexcept
{
    return f < mask.size() ? mask[f] != 0 : absent;
}
// Per fate, two bits: what the old 40-row walk listed at the row (a row listed above counts as its own: Skip and ListSym) and what
// this walk lists now (ListSym and ListWide). Indexed by TailPageRowFate: Skip, SkipMarked, SkipHead, ListSym, ListWide.
inline constexpr std::uint8_t kTailFateOldListed = 1, kTailFateListed = 2;
inline constexpr std::uint8_t kTailFateBits[] { kTailFateOldListed, 0, 0, kTailFateOldListed | kTailFateListed, kTailFateListed };
static_assert( std::size( kTailFateBits ) == kTailPageRowFateCount, "kTailFateBits is indexed by TailPageRowFate — one entry per enumerator" );

struct TailPageWalkInputs
{
    const IngestResult&      ing;
    const ForFilePage&       page;
    std::string_view         rootArg;
    const std::vector<char>& inHead;   // the shown head's files (computeFileTail): skipped past the old cut
};
inline void fileTailPageRows( FileTail& out, std::vector<char>& listed, const TailPageWalkInputs& in, FileTail& wide, FileTail* docs = nullptr )
{
    static_assert( kForFileTailPageWalk >= kForFileTailPageRows, "the tail walks at least the page its sym= rows come from" );
    const IngestResult& ing  = in.ing;
    const ForFilePage&  page = in.page;
    out.total       = page.rows.size();
    out.pageSeen    = std::min( page.rows.size(), kForFileTailPageWalk );
    out.oldPageSeen = std::min( page.rows.size(), kForFileTailPageRows );
    std::size_t codeSeen = 0, windowSeen = 0;   // window: page rows met, a Sphinx .txt page not counted (rank rows' rule)
    for( std::size_t r = 0; r < page.rows.size() && tailPageWalkOpen( docs != nullptr, r, out.pageSeen, codeSeen ); ++r )
    {
        const ForFileRow&  row = page.rows[r];
        // the old cut (page 0): the row the 40-row walk listed (a Sphinx .txt page's own cap is in a.inWindow either way)
        const TailOldWalk  old = tailOldWalkAt( docs != nullptr, r, codeSeen, windowSeen );
        const TailRowAdmit a      = admitTailRow( ing, row.lead, docs, windowSeen, kForFileTailPageWalk );
        const bool         symRow = a.isDoc ? old.doc : old.code;
        codeSeen += std::size_t( !a.isDoc );
        out.pageSeen = std::max( out.pageSeen, r + 1 );
        const TailPageRowFate fate = tailPageRowFate( !tailMaskAt( listed, row.fileId, true ), a, symRow, tailMaskAt( in.inHead, row.fileId, false ) );
        const std::uint8_t bits = kTailFateBits[ std::size_t( fate ) ];
        tailOldWalkCounters( out, old, ( bits & kTailFateOldListed ) != 0, r );   // what the old walk listed
        if( fate == TailPageRowFate::SkipMarked )
        {
            out.pageSkip = std::min( out.pageSkip, r );
        }
        else if( ( bits & kTailFateListed ) != 0 )
        {
            listTailRow( out, docs, a, listed, row.fileId, lensRowPath( ing, row.fileId, in.rootArg ),
                         symRow ? forFileRowSymNames( ing, row ) : std::string(), r + 1, symRow ? nullptr : &wide );
        }
    }
}

// Where the code-first order below applies, so its legend clause (serialize.h kForFileTailCodeFirstLegend) rides only there: a
// code question (taskAsksForDocText false) over an index that holds a doc unit. With no doc unit indexed, no tail row is a doc
// row, and the plain order and the code-first order are the same rows in the same order.
inline bool tailOrdersCodeFirst( const IngestResult& ing, std::string_view task )
{
    return !taskAsksForDocText( task )
        && std::any_of( ing.symbols.begin(), ing.symbols.end(), []( const Symbol& s ) noexcept { return isDocLang( s.lang ); } );
}

// FOR-TAIL-WIDE: does the tail's page walk go past page 0 — i.e. does the file page (every file holding a positive-score symbol)
// hold more than kForFileTailPageRows rows? The present-only test of kForFileTailWideLegend: a tail of a page that fits page 0
// lists exactly the rows the 40-row walk listed, every one with sym=, so its answer keeps its bytes. One pass over the ranking,
// stopping at the first file past page 0.
inline bool fileTailWalksPastPage0( const IngestResult& ing, const std::vector<float>& rank )
{
    std::vector<char> seen( ing.files.size(), 0 );
    std::size_t       files = 0;
    const std::size_t S     = std::min( ing.symbols.size(), rank.size() );
    for( std::size_t i = 0; i < S; ++i )
    {
        const std::uint32_t f = ing.symbols[i].fileId;
        if( rank[i] > 0.0f && f < seen.size() && !seen[f] )
        {
            seen[f] = 1;
            if( ++files > kForFileTailPageRows )
            {
                return true;
            }
        }
    }
    return false;
}

inline void appendFileTailRows( FileTail& out, FileTail& from )
{
    for( std::size_t i = 0; i < from.paths.size(); ++i )
    {
        out.paths.push_back( std::move( from.paths[i] ) );
        out.syms.push_back( std::move( from.syms[i] ) );
        out.pageNext.push_back( from.pageNext[i] );
    }
}

inline FileTail computeFileTail( const IngestResult& ing, const std::vector<float>& rank, const LexTermEvidence& ev,
                                 const std::vector<NodeId>& headIds, std::string_view rootArg, std::string_view task )
{
    FileTail          out;
    std::vector<char> listed( ing.files.size(), 0 );
    out.task = std::string( task );
    const ForFilePage page = computeForFilePage( ing, rank, ev );   // one ranking feeds both row kinds' sym=
    // CODE FIRST on a code question (filter.h taskAsksForDocText false): doc rows take no code row's slot;
    // they follow every code row, in their own allowance (the default regime prints every collected row; an explicit budget
    // fills code rows first). A docs question keeps the plain interleaved walk, byte-identical.
    FileTail                docRows, wideRows;
    FileTail*               docs   = taskAsksForDocText( task ) ? nullptr : &docRows;
    const std::vector<char> inHead = fileMaskOfSymbols( ing, headIds );   // once, for both row kinds
    fileTailRankRows( out, listed, ing, rank, page, inHead, rootArg, docs );
    fileTailPageRows( out, listed, TailPageWalkInputs{ ing, page, rootArg, inHead }, wideRows, docs );
    appendFileTailRows( out, docRows );
    out.oldRows = out.paths.size();   // review F2: the old walk's rows are a prefix; the widened rows follow, in page order
    appendFileTailRows( out, wideRows );
    ENSURES( out.paths.size() == out.syms.size() && out.paths.size() == out.pageNext.size() && out.paths.size() <= out.total,
             "computeFileTail: the rows, their sym= and their continuations disagree, or more rows than positive-score files" );
    return out;
}

// FOR-TAIL-WIDE (review F1): the tail the old 40-row walk would have built — the prefix of `t` it lists, with that walk's own
// pageSeen/pageSkip — byte for byte the pre-widening tail. The soft-target reserve charges this, so the widened rows never
// narrow <sigs>; they fill the tail's own share only.
inline FileTail fileTailOldWalk( const FileTail& t )
{
    FileTail old;
    old.paths.assign( t.paths.begin(), t.paths.begin() + std::ptrdiff_t( t.oldRows ) );
    old.syms.assign( t.syms.begin(), t.syms.begin() + std::ptrdiff_t( t.oldRows ) );
    old.pageNext.assign( t.pageNext.begin(), t.pageNext.begin() + std::ptrdiff_t( t.oldRows ) );
    old.total    = t.total;
    old.pageSeen = t.oldPageSeen;
    old.pageSkip = t.oldPageSkip;
    old.task     = t.task;
    old.oldRows  = t.oldRows;
    return old;
}

// FOR-TAIL-WIDE (review F3): the shown rows that print p= only because they sit past the old walk's cut (a suffix). The tail
// discloses the count (`p_only=` / "p_only"), present only when it is above zero.
inline std::size_t fileTailPathOnlyShown( const FileTail& t, std::size_t shown ) noexcept
{
    return shown > t.oldRows ? shown - t.oldRows : 0;
}

// The shown sigs rows a soft target's trailing sections are funded from (round C, reserve first): the shown ids without the
// `pastTarget` rows past its cut — the lowest-ranked shown rows in the lens's (score desc, id asc) order, which is the order
// the ladder's past-target count is taken in. The tail's rank rows exclude THESE files under a soft target: the rows past
// the cut may be narrowed after the tail is funded, and a narrowed row's file must still land somewhere (H2H lane 2).
inline std::vector<NodeId> rowsAtTargetIds( std::vector<NodeId> shown, const std::vector<float>& rank, std::size_t pastTarget )
{
    if( pastTarget == 0 || pastTarget > shown.size() )
    {
        return shown;
    }
    const auto score = [ & ]( NodeId id ) { return id < rank.size() ? rank[id] : 0.0f; };
    std::stable_sort( shown.begin(), shown.end(), [ & ]( NodeId a, NodeId b )
                      { return score( a ) != score( b ) ? score( a ) > score( b ) : a < b; } );
    shown.resize( shown.size() - pastTarget );
    return shown;
}

// the call serving the files a tail of `shown` rows left out: the file page from the first page row it did not print
inline std::string fileTailNextInvocation( const FileTail& t, std::size_t shown )
{
    std::size_t offset = shown >= t.paths.size() ? std::min( t.pageSeen, t.pageSkip ) : 0;   // a whole tail covered every page row it walked
    for( std::size_t i = 0; i < shown && i < t.pageNext.size(); ++i )
    {
        offset = std::max( offset, t.pageNext[i] );
    }
    for( std::size_t i = shown; i < t.pageNext.size(); ++i )   // code first: a cut doc row may sit earlier in the page than a
    {                                                           // shown code row (a no-op on the plain walk's ascending rows)
        if( t.pageNext[i] > 0 )
        {
            offset = std::min( offset, t.pageNext[i] - 1 );
        }
    }
    offset = std::min( offset, t.pageSkip );
    return forPageInvocation( t.task, kForPageRowsDefault, int( offset ) );
}

// The XML shape: `<tail total="T" shown="K" capped="0|1"[ next="…"]><t p="…" sym="…"/>…</tail>` — §P8 vocabulary, always
// emitted (a total of 0 means genuinely none remain, never not-computed — the B1.4 rule for elements). next= rides a cut
// tail only (shown < total). `shownCap` lets the explicit-budget caller serve fewer rows than were collected.
inline std::string renderFileTailXml( const FileTail& t, std::size_t shownCap, std::vector<char>& esc )
{
    const std::size_t shown = std::min( shownCap, t.paths.size() );
    std::string x = "<tail total=\"" + std::to_string( t.total )
                  + "\" shown=\"" + std::to_string( shown )
                  + "\" capped=\"" + ( shown < t.total ? "1" : "0" ) + "\"";
    if( shown < t.total )
    {
        x += nextAttrXml( fileTailNextInvocation( t, shown ) );
    }
    if( const std::size_t pOnly = fileTailPathOnlyShown( t, std::min( shownCap, t.paths.size() ) ); pOnly > 0 )
    {
        x += " p_only=\"" + std::to_string( pOnly ) + "\"";   // review F3: the rows past the old walk's cut, sym= shed
    }
    x += ">";
    for( std::size_t i = 0; i < shown; ++i )
    {
        x += "<t p=\"";  x += escapeXml( t.paths[i], esc );
        if( !t.syms[i].empty() )
        {
            x += "\" sym=\"";  x += escapeXml( t.syms[i], esc );
        }
        x += "\"/>";
    }
    x += "</tail>";
    return x;
}

// The JSON twin: `"tail":{"total":T,"shown":K[,"next":"…"],"files":[…],"sym":[…]}` (the caller supplies the leading comma).
// "sym" is index-aligned with "files" (additive: a reader of the paths-only shape keeps reading "files").
inline std::string renderFileTailJson( const FileTail& t, std::size_t shownCap )
{
    const std::size_t shown = std::min( shownCap, t.paths.size() );
    std::string j = "\"tail\":{\"total\":" + std::to_string( t.total )
                  + ",\"shown\":" + std::to_string( shown )
                  + ( shown < t.total ? nextFieldJson( fileTailNextInvocation( t, shown ) ) : std::string() );
    const auto list = [ & ]( const char* key, const std::vector<std::string>& v )
    {
        j += key;
        for( std::size_t i = 0; i < shown; ++i )
        {
            if( i > 0 )
            {
                j += ",";
            }
            j += '"';
            jsonesc::escapeInto( v[i], j, false, true, false );   // same core appendJsonStrField uses
            j += '"';
        }
        j += "]";
    };
    list( ",\"files\":[", t.paths );
    list( ",\"sym\":[", t.syms );
    if( const std::size_t pOnly = fileTailPathOnlyShown( t, shown ); pOnly > 0 )   // review F3: JSON has no legend, so the why rides
    {
        j += ",\"p_only\":" + std::to_string( pOnly ) + ",\"p_only_why\":\"" + std::string( kForFileTailPathOnlyWhy ) + "\"";
    }
    j += "}";
    return j;
}

// The explicit-budget fill (reserve first, forbudget-soft round C): the FEWEST rows whose rendered size reaches
// `shareBytes` — the tail keeps at least its share, so its last row may cross it — or every collected row. `render`
// is the dialect's renderer at a row count. Deterministic. FOR-TAIL-WIDE: a binary search, about log2(rows) + 1 renders (the
// linear scan rendered every prefix: quadratic once the walk grew to 4 pages). Valid because every count below paths.size()
// is a cut tail (shown < paths.size() <= total, so next= rides each), whose size grows with each row: a row adds at least
// `<t p=""/>` (9 B), next='s offset moves by at most a digit or two.
template< class Render >
inline std::size_t fileTailShownToFill( const FileTail& t, std::size_t shareBytes, const Render& render )
{
    const auto counts = std::views::iota( std::size_t{ 0 }, t.paths.size() );   // every row count below "every collected row"
    return std::size_t( std::ranges::partition_point( counts, [ & ]( std::size_t n ) { return render( n ).size() < shareBytes; } ) - counts.begin() );
}

}   // namespace rw
