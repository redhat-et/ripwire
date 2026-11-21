// forsigx.h — SIGX (lane TL1, M1; AF3's frozen C2(10)): page 1 of an answer-first --for answer carries the SHORT form of the
// sigs rows past rank 10, and their signature, doc and lens ride after the rows.
//
// THE MOVE. Every direct-child <d> row of the top-level <sigs> whose r= is above kSigxKeepRank keeps only l= e= n= p= r= (in their
// own order) and is emitted self-closing; every other attribute (in its own order) and the element text (the <doc> excerpt and the
// signature) are re-emitted VERBATIM as <x r="R" …>text</x> (<x r="R" …/> when there is no text) in ONE <sigx> block placed after the
// last top-level row block, before the trailing legend comments, rows in sigs order. A row with nothing to move is unchanged and gets
// no <x>. Rows r <= 10, <t> pointer rows and every other block are untouched. A block-local legend comment (kSigxLegend) is glued in
// front of <sigx> (the house convention: foranswerfirst.h declaredBlock), and the root's est_tokens= is re-priced over the added bytes
// (exactly, through the render's ledger: serialize.h repriceRootAfterCut; without a ledger, compactlegend.h repriceEstTokensIn at the
// densest markup rate, an upper bound).
//
// LOSSLESS, NOT A PERMUTATION. No byte of a row is dropped: moving each <x>'s attributes and text back onto its <d r=R> and deleting
// the block (and its legend) rebuilds the unmoved answer byte for byte, est_tokens= aside. test/forsigxcheck.sh (S1) does exactly
// that against the RIPWIRE_NO_SIGX=1 twin, and (S1n) proves the rebuild can fail. The bytes added are the <x r="R"> envelope per row,
// the block's tags and its legend.
//
// WHY. Measured before this was built (results AF3_ADDCOMPACT_1118, re-simulated by TL1 on today's binary): the median <sigs> is
// ~7.3 KB, and ranks 11-40 are about half of it, so the tail rows a 6 KB / 12 KB page reaches move ~19 rows earlier. Dev (design
// 154, held-out 49, T5b 41, T5c 34): complete within 6 KB 50->59 / 22->25 / 13->15 / 18->22, within 12 KB 73->75 / 32->33 / 26->29
// / 25->26. NOT FLIP-FREE BY CONSTRUCTION: a gold group carried only by a moved attribute (mem= on an r=25 row) or moved signature
// text leaves its page (design mf1-mdbook-03 leaves 12 KB). Cross-gold on the full answer is unchanged (no file is added); on a 6 KB
// / 12 KB prefix it rises (rows arrive earlier) — an owner call, registered in the lane's PREREG.
//
// WHERE IT RUNS. Only on the unbudgeted answer-first --for answer (verbs_for.h runForLens), after the permutation and before paging,
// so a page, --page-bytes=0 and --legend=last all window the SAME document (forpagescheck P2). Not under --legend=first, a budget (the
// fit priced the bytes; adding bytes after it would break it), --signatures-only (AF3's spec), the MCP twin or a non-XML format.
// RIPWIRE_NO_SIGX (any value) turns it off — the A/B handle, the RIPWIRE_NO_BODY_SLOT precedent.
#pragma once

#include <algorithm>
#include <charconv>
#include <cstddef>
#include <cstdlib>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "compactlegend.h"    // repriceEstTokensIn — the one added-bytes reprice
#include "forbudgetfit.h"     // forHeldBlocksPrice — what a budget holds beside est_tokens=
#include "foranswerfirst.h"   // topLevelBlocks / rootBody — the one CDATA-safe scanner of a --for answer's blocks

namespace rw::sigx
{

inline constexpr std::size_t kSigxKeepRank = 10;   // AF3 C2(K): rows r <= K stay whole; K = 10 is the frozen value
// e= STAYS ON THE ROW (lane ER1, 2026-11-21; AF3's C2(10) moved it with the lens). A short row is a place to read next, and a start
// line without its end is a place to search from: on GA1 DEV (n=89, page 1) the gold functions page 1 names with a usable l=..e=
// range were 80 of 123 while --signatures-only, whose rows keep e=, reached 96 (results NA1_NEXT_ACTION_1121 §5.2). Cost: the
// ` e="N"` run per short row that has one, on page 1 instead of in <sigx>; the whole answer's bytes do not move (the attribute
// changes element, not count). A row with no e= (extent unknown: serialize.h defEndLine) still has none. Gate: test/forendlinecheck.sh.
inline constexpr std::string_view kSigxKeptAttrs[] = { "l", "e", "n", "p", "r" };
inline constexpr std::string_view kSigxLegend =
    "<!-- sigx: a sigs row d with r above 10 keeps l= e= n= p= r= on the first page; its other attributes (the same names as on d) and "
    "its doc and signature follow the rows, verbatim, as x r=R -->";

inline bool sigxOn() noexcept { return std::getenv( "RIPWIRE_NO_SIGX" ) == nullptr; }

// One attribute of an open tag: ` name="value"` as the span [begin, end) and its name.
struct TagAttr
{
    std::size_t      begin = 0, end = 0;
    std::string_view name;
};
// The attributes of the open tag `tag` (`<d …>` or `<d …/>`), in order; nullopt on a shape this pass does not read (a value with no
// closing quote, text that is not ` name="…"`). Attribute values are escaped by the emitter, so they hold no raw `"` or `>`.
[[nodiscard]] inline std::optional<std::vector<TagAttr>> tagAttrs( std::string_view tag )
{
    std::vector<TagAttr> out;
    std::size_t          i   = tag.find( ' ' );
    const std::size_t    end = tag.size() - ( tag.ends_with( "/>" ) ? 2 : 1 );   // the '/' of "/>" or the '>'
    while( i < end )
    {
        const std::size_t eq = tag.find( "=\"", i );
        const std::size_t q  = eq < end ? tag.find( '"', eq + 2 ) : std::string_view::npos;
        if( tag[ i ] != ' ' || q >= end || tag.substr( i + 1, eq - i - 1 ).find( ' ' ) != std::string_view::npos ) { return std::nullopt; }
        out.push_back( { i, q + 1, tag.substr( i + 1, eq - i - 1 ) } );
        i = q + 1;
    }
    return i == end ? std::optional<std::vector<TagAttr>>( std::move( out ) ) : std::nullopt;
}

// The r= attribute of an attribute list: its ` r="N"` span and N (rank 0 when absent or not a plain number).
struct RankAttr
{
    std::size_t      rank = 0;
    std::string_view span;
};
[[nodiscard]] inline RankAttr rankAttr( std::string_view tag, const std::vector<TagAttr>& attrs ) noexcept
{
    const auto it = std::ranges::find_if( attrs, []( const TagAttr& a ) { return a.name == "r"; } );
    if( it == attrs.end() ) { return {}; }
    RankAttr out{ 0, tag.substr( it->begin, it->end - it->begin ) };
    for( const char c : out.span.substr( 4, out.span.size() - 5 ) )   // ` r="` … `"`
    {
        if( c < '0' || c > '9' ) { return {}; }
        out.rank = out.rank * 10 + std::size_t( c - '0' );
    }
    return out;
}

// A <d> row read as its open tag and its element text (empty for a self-closing row); nullopt on any other shape.
struct DRow
{
    std::string_view tag, text;
};
[[nodiscard]] inline std::optional<DRow> dRow( std::string_view row ) noexcept
{
    const std::size_t gt = row.find( '>' );
    if( gt == std::string_view::npos || !row.starts_with( "<d " ) ) { return std::nullopt; }
    const std::string_view tag = row.substr( 0, gt + 1 );
    if( tag.ends_with( "/>" ) ) { return DRow{ tag, {} }; }
    if( !row.ends_with( "</d>" ) ) { return std::nullopt; }
    return DRow{ tag, row.substr( gt + 1, row.size() - gt - 1 - 4 ) };
}

// One <d> row split: its page-1 short form and its deferred <x>. nullopt: the row stays as it is (r <= kSigxKeepRank, nothing to
// move, or a shape this pass does not read).
struct SplitRow
{
    std::string kept;
    std::string moved;
};
[[nodiscard]] inline std::optional<SplitRow> splitRow( std::string_view row )
{
    const std::optional<DRow>                 d     = dRow( row );
    const std::optional<std::vector<TagAttr>> attrs = d ? tagAttrs( d->tag ) : std::nullopt;
    const RankAttr                            r     = attrs ? rankAttr( d->tag, *attrs ) : RankAttr{};
    if( r.rank <= kSigxKeepRank ) { return std::nullopt; }
    std::string keep = "<d", move;
    for( const TagAttr& a : *attrs )
    {
        const bool kept = std::ranges::find( kSigxKeptAttrs, a.name ) != std::ranges::end( kSigxKeptAttrs );
        ( kept ? keep : move ).append( d->tag.substr( a.begin, a.end - a.begin ) );
    }
    if( move.empty() && d->text.empty() ) { return std::nullopt; }   // nothing to move
    SplitRow out{ keep + "/>", "<x" + std::string( r.span ) + move };
    out.moved += d->text.empty() ? "/>" : ">" + std::string( d->text ) + "</x>";
    return out;
}

// The root's est_tokens= over `out`, an answer that grew from `pricedBytes` by added markup: exactly through a converged ledger (the
// emitter's own fixpoint), else at the densest markup rate (an upper bound).
inline void repriceAddedMarkup( std::string& out, const ForAnswerLedger* ledger, std::size_t pricedBytes )
{
    if( ledger != nullptr && ledger->priced )
    {
        repriceRootAfterCut( out, PricedRootInputs{ ledger->markupBytes, ledger->bodyTokens }, pricedBytes );
        return;
    }
    (void)repriceEstTokensIn( out, 0, out.find( '>', out.find( "<ctx" ) ), pricedBytes, out.size() );
}

// Rewrite `doc` (a finished answer-first --for answer) in place. Returns whether it changed. `ledger`: the render's priced ledger —
// when it converged, est_tokens= is re-priced EXACTLY over the added markup (serialize.h repriceRootAfterCut, the fixpoint the emitter
// priced with, so formaxtokenscheck's byte accounting holds); without one, at the densest markup rate (an upper bound).
inline bool compactSigs( std::string& doc, const ForAnswerLedger* ledger = nullptr )
{
    const std::string_view                       view = doc;
    const std::optional<answerfirst::RootBody>   rb   = answerfirst::rootBody( view );
    if( !rb ) { return false; }
    const std::vector<answerfirst::Block> blocks = answerfirst::topLevelBlocks( view, rb->openEnd + 1, rb->closeAt );
    const auto sigs = std::ranges::find_if( blocks, []( const answerfirst::Block& b ) { return !b.comment && b.name == "sigs"; } );
    const auto last = std::ranges::find_if( blocks.rbegin(), blocks.rend(), []( const answerfirst::Block& b ) { return !b.comment; } );
    if( sigs == blocks.end() || last == blocks.rend() ) { return false; }
    const std::size_t open  = view.find( '>', sigs->begin ) + 1;
    const std::size_t close = view.rfind( "</", sigs->end - 1 );
    if( view[ open - 2 ] == '/' || close <= open ) { return false; }
    std::string sigsOut, deferred;
    std::size_t copied = sigs->begin;
    for( const answerfirst::Block& k : answerfirst::topLevelBlocks( view, open, close ) )
    {
        const std::optional<SplitRow> s = k.comment || k.name != "d" ? std::nullopt : splitRow( view.substr( k.begin, k.end - k.begin ) );
        if( !s ) { continue; }
        sigsOut.append( view.substr( copied, k.begin - copied ) ).append( s->kept );
        deferred += s->moved;
        copied = k.end;
    }
    if( deferred.empty() ) { return false; }
    sigsOut.append( view.substr( copied, sigs->end - copied ) );
    const std::size_t at = last->end;   // after the last row block, before the trailing legend comments
    std::string out;
    out.reserve( doc.size() + deferred.size() + kSigxLegend.size() + 64 );
    out.append( view.substr( 0, sigs->begin ) ).append( sigsOut ).append( view.substr( sigs->end, at - sigs->end ) );
    out.append( kSigxLegend ).append( "<sigx>" ).append( deferred ).append( "</sigx>" ).append( view.substr( at ) );
    repriceAddedMarkup( out, ledger, doc.size() );
    doc.swap( out );
    return true;
}

// TOKEN-BUDGET-MONOTONE rule 4 ("a budget the answer fits returns it byte for byte"): on the budgeted path, a budget that fitted the
// answer WHOLE (nothing shed) returns the compacted answer too — when its re-priced est_tokens= still fits `budgetTokens`. A budget
// between the two prices sheds as before (the compacted answer does not fit it). Returns whether `doc` was compacted.
inline bool compactSigsWithin( std::string& doc, std::size_t budgetTokens, const ForAnswerLedger* ledger )
{
    std::string c = doc;
    if( !compactSigs( c, ledger ) ) { return false; }
    const std::size_t      rootEnd = c.find( '>', c.find( "<ctx" ) );
    const std::string_view est     = attrOf( std::string_view( c ).substr( 0, rootEnd + 1 ), "est_tokens" );
    std::size_t            tokens  = 0;
    const auto [ end, ec ]         = std::from_chars( est.data(), est.data() + est.size(), tokens );
    // the price a budget holds is est_tokens= plus the blocks printed outside it (forbudgetfit.h fitsWhole's own sum)
    if( est.empty() || ec != std::errc() || end != est.data() + est.size() || tokens + forHeldBlocksPrice( c ) > budgetTokens ) { return false; }
    doc.swap( c );
    return true;
}

}   // namespace rw::sigx
