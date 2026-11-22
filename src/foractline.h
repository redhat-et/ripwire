// foractline.h — THE ACT LINE (lane BR1, owner ruling 178, 2026-11-21): a `--for` page that can name the ranges an agent will read next
// says so in one element, <act read="P:L-E,P:L-E,…"/>, right before its <sigs>, so they are read in ONE turn of parallel ranged Reads.
//
// WHY. Lane RX1 (results RX1_LOOKUP_CLASSES_1121 §1, §6, §7) measured agents acting on a --for answer: 58% of their pre-edit retrieval
// tokens are reads of ranges the answer listed — they trust it — but they issue them ONE PER REQUEST (1.02-1.27 calls per request), and
// every request re-sends the whole context. MODEL (RX1 §7, not measured): reading every listed range in one turn cuts 14.1% of the
// tokens to first edit on the tasks only ripwire answers, 7.6% overall, 12.6% on TR1. Its re-finds were mostly of rows WITHOUT a line
// range, which is the condition below. RX1 §7 also says why the gate is NOT confidence=: confidence="high" fires on 2 of 11 such cells.
//
// THE CONDITION. The CANDIDATES are the <d> rows of the page's top-level <sigs>, in rank order (r=; a row with no r= is the previous
// row's + 1, RANKSEQ's reading), less every row whose body this page already delivers whole — a <b> child of a top-level <fold> or
// <bodies> with the same p= and l= and no truncated= (kEditLinesRangedRead, wrap.h: a delivered body is edited as served, never Read
// again). The first kActRows of them are listed; the line is written iff there is at least one and EVERY one of them carries both l=
// and e= — a listed set with a hole in it would send the agent searching for the hole, which is the re-find this line exists to stop.
// What is never a candidate, and why: a <t> row in <sigs> (a demoted same-file sibling past answer row 10: a pointer, not the answer)
// and every <tail> row (a file with symbol names and no lines — listing it would ask for the whole-file read this line exists to
// stop). A path holding ',' is not listed either (the value could not be split back), and its page has no line.
//
// N = kActRows = 3, chosen from data (results BR1_BATCHED_READ_1121 READOUT §2; GA1 DEV n=89 page 1 at 81703e5fe, MEASURED): of the 99
// gold edit functions served as sigs <d> rows, 35 have their body delivered; the undelivered top-1/2/3/4/5 add 14/21/24/26/29 more, at a
// median element of 46/81/117/151/182 B. 3 is the largest N inside the ~120 B median the owner's build ruling set; 4 and 5 buy 2 and 5
// more functions for 34 and 65 B a page. Sharing a repeated path (P:L-E,L-E) saved 0 B at the median on the same set, so it is not done.
//
// WHERE IT RUNS. On the bytes about to be served, after paging and the body-pointer rewrite (so "delivered" is what THIS page carries)
// and BEFORE ROWLINES (forrowlines.h), which then encodes the rows as it always has and writes its clauses after this one — the
// decoder (test/rowlines.py) strips those from the end, so it is unchanged. Page 1 (or an unpaged answer) only: a continuation page
// holds no top rows and re-sends no legend. Not under an explicit token budget (the budget-fit path, runForLensFitted; MCP `for` with
// budget_tokens): the fit decided those bytes. Not on --json, a legend-first --legend=first answer, or a routed answer (none opens
// with <ctx>).
// One legend clause (kActClause), only when the line is written, where the answer's legend is (ClausePlace below: last before </ctx>
// at the moment it runs on the CLI, so before ROWLINES' clauses; after the leading legend run on legend-first MCP `for`); a legend-dictionary entry
// (forlegendentries.h), so a legend="ref" session drops it once served. est_tokens= is re-priced by the added bytes through the house
// reprice (compactlegend.h repriceEstTokensIn: ceil at the densest rate), so the price stays an upper bound, never an under-read.
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

#include "compactlegend.h"    // repriceEstTokensIn — the house reprice of a root that grew
#include "foractlineswitch.h" // actLineOn — the switch (cli.h's --version reads the same header)
#include "foranswerfirst.h"   // rootBody / topLevelBlocks — the one CDATA-safe scanner of a --for answer's blocks
#include "forrowlines.h"      // readSection — the one strict row reader
#include "serialize.h"        // attrOf — the one reader of a printed tag's attribute value

namespace rw::actline
{

inline constexpr std::size_t kActRows = 3;   // see the header: GA1 DEV page 1, the largest N inside a ~120 B median element
inline constexpr std::string_view kActClause =
    "<!-- act read=: P:L-E of the top 3 sigs d rows by r= whose body is not on this page: Read ALL in ONE turn, parallel ranged "
    "Reads; search only for what no row lists; absent if one lacks e= -->";

static_assert( kActRows == 3, "kActClause says \"top 3\": reword it with kActRows" );

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

// The (p=, l=) of every body the page delivers whole: the <b> children of its top-level <fold> and <bodies> blocks.
[[nodiscard]] inline std::vector<std::pair<std::string_view, std::string_view>> deliveredBodies( std::string_view doc, const std::vector<answerfirst::Block>& blocks )
{
    std::vector<std::pair<std::string_view, std::string_view>> out;
    for( const answerfirst::Block& b : blocks )
    {
        if( b.comment || ( b.name != "fold" && b.name != "bodies" ) ) { continue; }
        const std::optional<rowlines::Section> sec = rowlines::readSection( doc, b );
        if( !sec ) { continue; }
        for( const rowlines::Row& row : sec->rows )
        {
            const std::string_view tag = openTagText( row );
            if( row.tag && row.tag->name == "b" && rw::attrOf( tag, "truncated" ).empty() ) { out.emplace_back( rw::attrOf( tag, "p" ), rw::attrOf( tag, "l" ) ); }
        }
    }
    return out;
}

// The sigs <d> rows whose body the page does not deliver, in rank order (a row with no r= is the previous row's + 1); nullopt on an
// r= that is not a number (a shape this reader does not know: no line).
[[nodiscard]] inline std::optional<std::vector<Candidate>> rankedCandidates( const rowlines::Section& sec, const std::vector<std::pair<std::string_view, std::string_view>>& delivered )
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
        if( row.tag->name == "d" && std::ranges::find( delivered, std::pair{ c.p, c.l } ) == delivered.end() ) { rows.push_back( c ); }
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
    std::optional<std::vector<Candidate>> rows = sec ? rankedCandidates( *sec, deliveredBodies( doc, blocks ) ) : std::nullopt;
    if( !rows ) { return std::nullopt; }
    rows->resize( std::min( rows->size(), kActRows ) );   // a size_t: the STL's own size, at its boundary
    const auto ranged = []( const Candidate& c ) { return !c.p.empty() && !c.l.empty() && !c.e.empty() && c.p.find( ',' ) == std::string_view::npos; };
    if( rows->empty() || !std::ranges::all_of( *rows, ranged ) ) { return std::nullopt; }
    std::string value;
    for( const Candidate& c : *rows ) { value.append( value.empty() ? "" : "," ).append( c.p ).append( ":" ).append( c.l ).append( "-" ).append( c.e ); }
    return value;
}
}   // namespace detail

// Where the clause goes: where the answer's own legend is. The CLI answer-first document legend is the trailing comment run before
// </ctx> (DocumentEnd); MCP `for` is legend-first, its legend the comment run right after the root's open tag (Head) — a reader of
// that answer takes its legend from there (test/legendcoveragecheck.sh (G) does), so a clause at the end would define nothing.
enum class ClausePlace
{
    DocumentEnd,
    Head,
};

// Write the act line into `doc` (a finished answer-first --for page, an unpaged answer, or the MCP `for` bundle) in place. Returns
// whether it did.
inline bool insertActLine( std::string& doc, ClausePlace place = ClausePlace::DocumentEnd )
{
    const std::string_view view = doc;
    const std::optional<answerfirst::RootBody> rb = actLineOn() && view.starts_with( "<ctx" ) ? answerfirst::rootBody( view ) : std::nullopt;
    if( !rb ) { return false; }
    const std::string_view rootOpen = view.substr( 0, rb->openEnd );
    if( rootOpen.find( " page=\"" ) != std::string_view::npos && rootOpen.find( " page=\"1\"" ) == std::string_view::npos ) { return false; }
    const std::vector<answerfirst::Block> blocks = answerfirst::topLevelBlocks( view, rb->openEnd + 1, rb->closeAt );
    const std::optional<std::string>      value  = detail::readValue( view, blocks );
    if( !value ) { return false; }
    const std::size_t sigsAt = std::ranges::find_if( blocks, []( const answerfirst::Block& b ) { return !b.comment && b.name == "sigs"; } )->begin;
    // Head: the end of the leading comment run (or, with none, right before the line itself)
    const auto        lead   = std::ranges::find_if( blocks, []( const answerfirst::Block& b ) { return !b.comment; } );
    const std::size_t headAt = lead == blocks.begin() ? sigsAt : std::prev( lead )->end;
    const std::size_t clauseAt = place == ClausePlace::Head ? std::min( headAt, sigsAt ) : rb->closeAt;
    const std::size_t before   = doc.size();
    // the later position first, so the earlier one still holds (clauseAt == sigsAt: the clause, then the line)
    if( clauseAt > sigsAt ) { doc.insert( clauseAt, kActClause ); }
    doc.insert( sigsAt, "<act read=\"" + *value + "\"/>" );
    if( clauseAt <= sigsAt ) { doc.insert( clauseAt, kActClause ); }
    (void)rw::repriceEstTokensIn( doc, 0, doc.find( '>' ), before, doc.size() );
    return true;
}

}   // namespace rw::actline
