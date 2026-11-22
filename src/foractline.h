// foractline.h — THE ACT LINE (lane BR1, owner ruling 178, 2026-11-21): a `--for` answer that can name the ranges an agent will read
// next says so in one element, <act read="P:L-E,…"/>, right after its answer block, so they are read in ONE turn of parallel ranged Reads.
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
// WHERE IT GOES AND WHEN IT RUNS. Right after <sigs>, or after the key-body group when that group follows <sigs> directly (KB1
// places the group directly after the first row block: forkeybodycheck K3), so every block-order contract that reads the answer
// block first still reads it first. It is inserted into the WHOLE answer-first document before the early stop and paging, so it
// is a block of the row stream like any other: paging carries it on the page it falls on, pricePage prices it, and the pages joined
// are the whole answer. Under an explicit token budget (CLI runForLensFitted, MCP `for` budget_tokens) it is inserted after the
// fit only when the answer still fits the budget with it (insertActLine's maxEstTokens), so a budget the answer fits returns the
// unbudgeted answer byte for byte and a shed answer never exceeds its budget for it. Under --legend=first the same line is written
// with its clause in the leading legend (ClausePlace::Head), so the legend-first answer stays a byte permutation of the
// answer-first one (forpagescheck P6, forsoftbudgetcheck STp). Not on --json or a routed answer's outer document (no <ctx> root).
// One legend clause (kActClause), only when the line is written; a legend-dictionary entry (forlegendentries.h), so a legend="ref"
// session drops it once served. est_tokens= is re-priced by the added bytes through the house reprice (compactlegend.h
// repriceEstTokensIn: ceil at the densest rate), so the price stays an upper bound, never an under-read.
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
#include "forpages.h"         // kKeyBodyLegendLead — the key-body group the line goes after
#include "forrowlines.h"      // readSection — the one strict row reader
#include "serialize.h"        // attrOf — the one reader of a printed tag's attribute value

namespace rw::actline
{

inline constexpr std::size_t kActRows = 3;   // see the header: GA1 DEV page 1, the largest N inside a ~120 B median element
inline constexpr std::string_view kActClause =
    "<!-- act read=: P:L-E of the top 3 sigs d rows by r=: Read ALL in ONE turn, parallel ranged Reads, except a body the answer "
    "serves; search only for what no row lists; absent if one lacks e= -->";

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

// Where the clause goes: where the answer's own legend is. The answer-first document legend is the trailing comment run before </ctx>
// (DocumentEnd); a legend-first answer (MCP `for`, CLI --legend=first) has its legend in the comment run right after the root's open tag
// (Head) — its reader takes the legend from there (test/legendcoveragecheck.sh (G) does), so a clause at the end would define nothing.
enum class ClausePlace
{
    DocumentEnd,
    Head,
};

namespace detail
{
// Where the line goes: right after <sigs>, or after the key-body group (its legend comment, then <bodies of="key">) when that group
// follows <sigs> directly — KB1 places the group directly after the first row block, and the line must not come between them.
[[nodiscard]] inline std::size_t lineAtAfter( std::string_view doc, const std::vector<answerfirst::Block>& blocks, std::size_t sigsIdx ) noexcept
{
    const std::size_t k        = sigsIdx + 1;
    const bool        keyGroup = k + 1 < blocks.size() && blocks[ k ].comment && doc.substr( blocks[ k ].begin ).starts_with( forpages::detail::kKeyBodyLegendLead )
                         && !blocks[ k + 1 ].comment && blocks[ k + 1 ].name == "bodies";
    return keyGroup ? blocks[ k + 1 ].end : blocks[ sigsIdx ].end;
}

// The root's est_tokens= as a number (0: none, or not a plain integer).
[[nodiscard]] inline std::size_t rootEstTokens( std::string_view doc ) noexcept
{
    const std::string_view v = rw::attrOf( doc.substr( 0, doc.find( '>' ) ), "est_tokens" );
    std::size_t            n = 0;
    return std::from_chars( v.data(), v.data() + v.size(), n ).ec == std::errc() ? n : 0;
}
}   // namespace detail

// Write the act line into `doc` (a finished --for answer: the whole answer-first document before paging, a budget's fitted answer, a
// legend-first answer or the MCP `for` bundle) in place. `maxEstTokens` > 0: write it only if the answer's est_tokens= stays within
// it (a budget's ceiling: the line never makes an answer exceed the budget it was fitted to). Returns whether it wrote it.
inline bool insertActLine( std::string& doc, ClausePlace place = ClausePlace::DocumentEnd, std::size_t maxEstTokens = 0 )
{
    const std::string_view view = doc;
    const std::optional<answerfirst::RootBody> rb = actLineOn() && view.starts_with( "<ctx" ) ? answerfirst::rootBody( view ) : std::nullopt;
    if( !rb ) { return false; }
    const std::string_view rootOpen = view.substr( 0, rb->openEnd );
    if( rootOpen.find( " page=\"" ) != std::string_view::npos && rootOpen.find( " page=\"1\"" ) == std::string_view::npos ) { return false; }
    const std::vector<answerfirst::Block> blocks = answerfirst::topLevelBlocks( view, rb->openEnd + 1, rb->closeAt );
    const std::optional<std::string>      value  = detail::readValue( view, blocks );
    if( !value ) { return false; }
    const auto        sigs   = std::ranges::find_if( blocks, []( const answerfirst::Block& b ) { return !b.comment && b.name == "sigs"; } );
    const std::size_t lineAt = detail::lineAtAfter( view, blocks, std::size_t( sigs - blocks.begin() ) );
    // Head: the end of the leading comment run (or, with none, right after the root's open tag) — always before the line
    const auto        lead     = std::ranges::find_if( blocks, []( const answerfirst::Block& b ) { return !b.comment; } );
    const std::size_t clauseAt = place == ClausePlace::Head ? ( lead == blocks.begin() ? rb->openEnd + 1 : std::prev( lead )->end ) : rb->closeAt;
    std::string       was      = maxEstTokens > 0 ? doc : std::string();
    const std::size_t before   = doc.size();
    // the later position first, so the earlier one still holds
    if( clauseAt > lineAt ) { doc.insert( clauseAt, kActClause ); }
    doc.insert( lineAt, "<act read=\"" + *value + "\"/>" );
    if( clauseAt <= lineAt ) { doc.insert( clauseAt, kActClause ); }
    (void)rw::repriceEstTokensIn( doc, 0, doc.find( '>' ), before, doc.size() );
    if( maxEstTokens > 0 && detail::rootEstTokens( doc ) > maxEstTokens )
    {
        doc.swap( was );   // over the budget with it: the fitted answer is served as it was fitted
        return false;
    }
    return true;
}

}   // namespace rw::actline
