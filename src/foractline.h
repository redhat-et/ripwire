// foractline.h — THE ACT LINE (lane BR1, owner ruling 178, 2026-11-21): a `--for` answer that can name the ranges an agent will read
// next says so in one element, <act read="P:L-E,…"/>, right after its <sigs>, so they are read in ONE turn of parallel ranged Reads.
//
// WHY. Lane RX1 (results RX1_LOOKUP_CLASSES_1121 §1, §6, §7) measured agents acting on a --for answer: 58% of their pre-edit retrieval
// tokens are reads of ranges the answer listed — they trust it — but they issue them ONE PER REQUEST (1.02-1.27 calls per request), and
// every request re-sends the whole context. MODEL (RX1 §7, not measured): reading every listed range in one turn cuts 14.1% of the
// tokens to first edit on the tasks only ripwire answers, 7.6% overall, 12.6% on TR1. Its re-finds were mostly of rows WITHOUT a line
// range, which is the condition below. RX1 §7 also says why the gate is NOT confidence=: confidence="high" fires on 2 of 11 such cells.
//
// THE CONDITION. The <d> rows of the answer's top-level <sigs>, in rank order (r=; a row with no r= is the previous row's + 1,
// RANKSEQ's reading); the first kActRows are listed, and the line is written iff there is at least one and EVERY one of them carries
// both l= and e= — a listed set with a hole in it would send the agent searching for the hole, which is the re-find this line exists
// to stop. Never a candidate: a <t> row in <sigs> (a demoted same-file sibling past answer row 10: a pointer, not the answer) and
// every <tail> row (a file with symbol names and no lines — listing it would ask for a whole-file read). A path holding ',' is not
// listed (the value could not be split back), and that answer has no line.
// A FUNCTION OF THE RANKED ROWS ONLY (lane BR1b, 2026-11-22). BR1 first left out a row whose body the page delivered (a fold or key
// body). That made the line depend on the fold, the body slot and the page cut, and broke contracts that are real: "the answer before
// the fold is the fold-off answer" (forbodyfoldcheck F5), "the slot changes nothing outside itself" (forbodyslotcheck D4), "a budget
// the answer fits returns it byte for byte" (TOKEN-BUDGET-MONOTONE), "pages joined are the whole answer" (forpagescheck P2). A
// delivered body still needs no Read — the clause says so and kEditLinesRangedRead (wrap.h) routes it to a direct Edit.
//
// N = kActRows = 3, chosen from data (results BR1_BATCHED_READ_1121 READOUT §2/§8; GA1 DEV n=89 page 1, MEASURED): 3 is the largest N
// inside the ~120 B median element the owner's build ruling set. Sharing a repeated path (P:L-E,L-E) saved 0 B at the median.
//
// WHERE IT GOES AND WHEN IT RUNS. Into the RAW render (legend-first), before the answer-first permutation, KB1, the early stop and
// paging — so every later stage treats it as it treats every block: --legend=first and the answer-first order stay byte permutations
// of each other; the line sits right after <sigs> and KB1 later puts its key group directly after the first row block (forkeybodycheck
// K3); paging carries it as a block of the row stream that no page counts (forpages.h markActLine), and G's page-1 model does not count
// it either (foranswerfirst.h layoutBlocks), so no page cut and no promotion moves for it. Under an explicit token budget it goes into
// an answer the budget fits WHOLE (still raw), only while it still fits with the line: a budget the answer fits returns the unbudgeted
// answer, line included, byte for byte (TOKEN-BUDGET-MONOTONE), and a budget that had to shed content spends nothing on it. MCP `for` has
// no fitter: under budget_tokens the line rides only while est_tokens= stays within it. The clause joins the leading legend run, and the
// permutation moves it with the rest of the document legend. Its first word is "the", not "act": a comment whose first word names an
// element is that element's BLOCK-LOCAL legend (foranswerfirstcheck R8), and this one defines the line for the whole answer.
// Not on --json (no <ctx> root), nor on a routed answer's outer document.
// One legend clause (kActClause), only when the line is written; a legend-dictionary entry (forlegendentries.h), so a legend="ref"
// session drops it once served. est_tokens= is re-priced EXACTLY for the added bytes (detail::repriceAdded: the rule pricePage and
// formaxtokenscheck's judge price a document by).
// RIPWIRE_NO_ACTLINE (any value) turns it off — the A/B handle (the RIPWIRE_NO_SIGX / RIPWIRE_NO_ROWLINES precedent): the answer is
// then byte-identical to one served before this pass existed. --version discloses the posture (act=on|off).
// Gate: test/actlinecheck.sh.
#pragma once

#include <algorithm>
#include <charconv>
#include <cstddef>
#include <iterator>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "foractlineswitch.h" // actLineOn — the switch (cli.h's --version reads the same header)
#include "forbudgetfit.h"     // ForAnswerLedger — the render's priced ledger the line re-prices through and keeps current
#include "foranswerfirst.h"   // rootBody / topLevelBlocks — the one CDATA-safe scanner of a --for answer's blocks
#include "forpages.h"         // detail::rootPriceSpan — the one reader of where a document's price sits (pricePage's)
#include "forrowlines.h"      // readSection — the one strict row reader
#include "serialize.h"        // attrOf — the one reader of a printed tag's attribute value

namespace rw::actline
{

inline constexpr std::size_t kActRows = 3;   // see the header: GA1 DEV page 1, the largest N inside a ~120 B median element
inline constexpr std::string_view kActClause =
    "<!-- the act line: read= P:L-E of the top 3 sigs d rows by r=: Read ALL in ONE turn, parallel ranged Reads, except a served "
    "body; search only for what no row lists; absent if one lacks e= -->";

static_assert( kActRows == 3 && kActClause.find( "top 3 " ) != std::string_view::npos,
               "the legend clause kActClause states \"top 3\": reword it with kActRows (test/capdisclose.map: legend)" );

namespace detail
{
// One sigs <d> row the line may list: p= l= e= as printed (still escaped, so they go into the attribute as they stand) and its rank.
struct Candidate
{
    std::string_view p, l, e;   // e empty = the row has no e= (an emitter never prints e="")
    int              rank = 0;
};

// The open tag of a read row, as printed IN THE DOCUMENT: what serialize.h's attrOf (the one reader of a printed attribute) reads.
// Not row.xml: that is the row's own COPY, and a view into it dies with the Section (a returned p=/l= would dangle). readSection
// reads the tag off the document view, so its name sits in the document one byte after the '<'.
[[nodiscard]] inline std::string_view openTagText( const rowlines::Row& row ) noexcept
{
    return row.tag ? std::string_view( row.tag->name.data() - 1, row.tag->size ) : std::string_view();
}

// The sigs <d> rows in rank order (a row with no r= is the previous row's + 1); nullopt on an r= that is not a number (a shape this
// reader does not know: no line).
[[nodiscard]] inline std::optional<std::vector<Candidate>> rankedCandidates( const rowlines::Section& sec )
{
    std::vector<Candidate> rows;
    int                    prevRank = 0;
    for( const rowlines::Row& row : sec.rows )
    {
        if( !row.tag ) { continue; }   // a comment child (MCP keeps its notes inside <sigs>)
        const std::string_view tag  = openTagText( row );
        const std::string_view r    = rw::attrOf( tag, "r" );
        int                    rank = prevRank + 1;
        if( !r.empty() && std::from_chars( r.data(), r.data() + r.size(), rank ).ec != std::errc() ) { return std::nullopt; }
        prevRank = rank;
        const Candidate c{ rw::attrOf( tag, "p" ), rw::attrOf( tag, "l" ), rw::attrOf( tag, "e" ), rank };
        if( row.tag->name == "d" ) { rows.push_back( c ); }
    }
    if( !std::ranges::is_sorted( rows, {}, &Candidate::rank ) )   // served in rank order (89 of 89 GA1 DEV pages): the guard is the common path
    {
        std::ranges::stable_sort( rows, {}, &Candidate::rank );
    }
    return rows;
}

// The read= value for the page whose root's top-level blocks are `blocks`; nullopt when the condition (header) does not hold.
[[nodiscard]] inline std::optional<std::string> readValue( std::string_view doc, const std::vector<answerfirst::Block>& blocks )
{
    const auto sigs = std::ranges::find_if( blocks, []( const answerfirst::Block& b ) { return !b.comment && b.name == "sigs"; } );
    const std::optional<rowlines::Section> sec = sigs == blocks.end() ? std::nullopt : rowlines::readSection( doc, *sigs );
    std::optional<std::vector<Candidate>> rows = sec ? rankedCandidates( *sec ) : std::nullopt;
    if( !rows ) { return std::nullopt; }
    rows->resize( std::min( rows->size(), kActRows ) );   // a size_t: the STL's own size, at its boundary
    const auto ranged = []( const Candidate& c ) { return !c.p.empty() && !c.l.empty() && !c.e.empty() && c.p.find( ',' ) == std::string_view::npos; };
    if( rows->empty() || !std::ranges::all_of( *rows, ranged ) ) { return std::nullopt; }
    std::string value;
    for( const Candidate& c : *rows ) { value.append( value.empty() ? "" : "," ).append( c.p ).append( ":" ).append( c.l ).append( "-" ).append( c.e ); }
    return value;
}
}   // namespace detail

namespace detail
{
// The root's est_tokens= as a number (0: none, or not a plain integer).
[[nodiscard]] inline std::size_t rootEstTokens( std::string_view doc ) noexcept
{
    const std::string_view v = rw::attrOf( doc.substr( 0, doc.find( '>' ) ), "est_tokens" );
    std::size_t            n = 0;
    return std::from_chars( v.data(), v.data() + v.size(), n ).ec == std::errc() ? n : 0;
}

// Re-price the root after `added` markup bytes went in, EXACTLY as the document is priced (forpages.h pricePage, formaxtokenscheck's
// judge): markup at kBytesPerTokenDefault, the <bodies> section at its own rate, the attribute's own digits by the fixpoint. Whatever
// the old price held beyond its markup is kept as it was (the bodies, or a block the whole answer prices outside), so only the added
// bytes move it — never the ceil-at-the-densest-rate over-read a later "est_tokens= equals the delivered price" arm would catch.
// The span is pricePage's own reader (forpages.h rootPriceSpan), so the two cannot disagree about where the price and the bodies are.
// The fallback for a caller with no priced ledger: every caller that serves a priced root passes one (the CLI its render's, MCP `for`
// priceForTaskRoot's), so this runs on no served path today. Its limit, kept in view: when the old price held LESS than its markup
// (blocks spliced after the price, e.g. a <syms> "not in est_tokens"), the clamp below sets the rest to 0 and the line's reprice
// charges those blocks too — MCP `for` did exactly that before it passed its ledger (MEASURED: +490 for 264 B; actlinecheck (M)(F)).
inline void repriceAdded( std::string& doc, std::size_t added )
{
    const std::optional<forpages::detail::RootPriceSpan> s   = forpages::detail::rootPriceSpan( doc );
    const std::size_t                                    old = rootEstTokens( doc );
    if( !s || old == 0 ) { return; }
    const std::size_t markupNow  = doc.size() - s->bodyBytes - s->attrLen;   // the attribute itself excluded: the fixpoint adds it back
    const std::size_t pricedWas  = rw::tokensForEmittedBytes( markupNow - added + s->attrLen, rw::kBytesPerTokenDefault );
    const std::size_t restTokens = old > pricedWas ? old - pricedWas : 0;
    doc.replace( s->at, s->attrLen, rw::pricedRootAttrTokens( markupNow, rw::kBytesPerTokenDefault, restTokens, nullptr ) );
}
}   // namespace detail

// Write the act line into `doc` — a RAW render of a --for answer (legend-first: its legend is the comment run right after the root's
// open tag; under a budget, one it fits whole), before the answer-first permutation, KB1 and paging. The clause joins that leading legend
// run (the permutation then moves it with the rest of the document legend); the line goes right after <sigs> (KB1 later puts its key
// group directly after the first row block, so between them). `maxEstTokens` > 0 (a CLI budget's limit, MCP budget_tokens): write it
// only if the answer's est_tokens= stays within it. `ledger`: the render's priced ledger (CLI; MCP `for`: what priceForTaskRoot converged), re-priced through and kept current. Returns whether
// it wrote it.
inline bool insertActLine( std::string& doc, std::size_t maxEstTokens = 0, ForAnswerLedger* ledger = nullptr )
{
    const std::string_view view = doc;
    const std::optional<answerfirst::RootBody> rb = actLineOn() && view.starts_with( "<ctx" ) ? answerfirst::rootBody( view ) : std::nullopt;
    if( !rb ) { return false; }
    const std::string_view rootOpen = view.substr( 0, rb->openEnd );
    if( rootOpen.find( " page=\"" ) != std::string_view::npos && rootOpen.find( " page=\"1\"" ) == std::string_view::npos ) { return false; }
    const std::vector<answerfirst::Block> blocks = answerfirst::topLevelBlocks( view, rb->openEnd + 1, rb->closeAt );
    const std::optional<std::string>      value  = detail::readValue( view, blocks );
    if( !value ) { return false; }
    const std::size_t lineAt = std::ranges::find_if( blocks, []( const answerfirst::Block& b ) { return !b.comment && b.name == "sigs"; } )->end;
    // the end of the leading comment run (or, with none, right after the root's open tag) — always before the line
    const auto        lead     = std::ranges::find_if( blocks, []( const answerfirst::Block& b ) { return !b.comment; } );
    const std::size_t clauseAt = lead == blocks.begin() ? rb->openEnd + 1 : std::prev( lead )->end;
    std::string       was      = maxEstTokens > 0 ? doc : std::string();
    const std::size_t before   = doc.size();
    doc.insert( lineAt, "<act read=\"" + *value + "\"/>" );   // the later position first, so clauseAt still holds
    doc.insert( clauseAt, kActClause );
    const std::size_t added = doc.size() - before;
    if( ledger != nullptr && ledger->priced )
    {
        // the render's own converged ledger (the house reprice, as SIGX and KB1 use it), and the ledger FOLLOWS: every later stage
        // that re-prices through it (SIGX, KB1, the budget fit) then charges these bytes too
        repriceRootAfterCut( doc, PricedRootInputs{ ledger->markupBytes, ledger->bodyTokens }, before );
        ledger->markupBytes += added;
    }
    else
    {
        detail::repriceAdded( doc, added );
    }
    if( maxEstTokens > 0 && detail::rootEstTokens( doc ) > maxEstTokens )
    {
        doc.swap( was );   // over the budget with it: the answer is served as it was shaped
        return false;
    }
    return true;
}

}   // namespace rw::actline
