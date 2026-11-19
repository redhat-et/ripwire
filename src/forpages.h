// forpages.h — AF1 (owner decision 2026-11-18): a finished answer-first `--for` answer is served in PAGES.
//
// THE DECISION. `--for` answers ANSWER-FIRST by default (foranswerfirst.h, item R) and stop after about 12 KB of rows with
// a disclosed, resumable next=. The coordinator's pricing on T6's re-run answers turned the single stop into PAGING: an
// agent that stops at the page that completed its answer, with the legend sent once, beats a single 12 KB stop at every
// follow-up cost and keeps every complete answer complete (held-out n=49: 6 KB pages -4,691 tokens/question, 12 KB pages
// -3,906; a single 12 KB stop -3,020 at the grep floor and 7 of 39 complete answers lost). Pre-registered in
// results/AF1_ANSWERFIRST_1118/PREREG.md before this file was written.
//
// WHAT A PAGE IS. The answer is rendered WHOLE, permuted answer-first, and only then cut, so every page of every call is a
// window onto ONE deterministic document: the row stream of page k is bytes [c(k-1), c(k)) of that document, and the
// stream is the root's body minus its trailing DOCUMENT legend. Cuts fall at row_cuts granularity (after a top-level
// element, after each child of a section, after a section's close) — never right after a comment (a block-local legend
// travels with its block) and never right after a section's open tag (no page opens an empty section). Page 1 is the
// largest cut <= P counted from byte 0 (the root open tag counts, as in T6's measurement); page k the largest cut
// <= c(k-1) + P; a unit larger than P is served whole rather than split.
//
// WHERE THE LEGEND SITS, and why. 5ee3ddb38 made answer-first opt-in because, as a default, it moved the READINGS of the
// cuts and floors out of the prefix (measured for AF1: a bare 12 KB answer-first prefix shows a marker with no definition
// inside it on 137 of 154 design cells; legend-first, 0). A PAGE is not a truncated prefix: page 1 keeps the WHOLE
// document legend after its rows and before </ctx>, so every attribute the page carries is defined inside the page —
// and since that legend is the whole answer's, it defines every later page's attributes too. The page's OWN disclosure
// (page= pages= withheld_bytes= next=) rides the ROOT, in the first bytes, so the cut is the first thing a reader meets:
// root, then rows, then the dictionary — the collapse condition 5ee3ddb38 wrote beside kLegendPostures.
//
// A CONTINUATION PAGE RE-SENDS NO LEGEND. It is the ref posture (legenddict.h): rows first, a slim root, and a closing
// <about legend="ref" have="page1" …/> naming what the reader holds — page 1's legend — and the dictionary that holds
// every definition. The measured cost this has to beat: a windowed verb's continuation page costs 1.01x a whole answer,
// 26.4 % of it re-sent legend.
//
// IT IS A WINDOW, NOT A CUT. Concatenating every page's rows reproduces the whole answer's rows byte for byte
// (test/forpagescheck.sh (P2), with a dropped-row negative control). --page-bytes=0 serves the whole answer in one call.
#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "serialize.h"       // pricedRootAttrTokens / tokensForEmittedBytes — est_tokens= prices the page as delivered
#include "foranswerfirst.h"  // topLevelBlocks / declaredBlock — the one CDATA-safe scanner of a --for answer's blocks
#include "legenddict.h"      // detail::aboutPointer — the ref posture's closing pointer
#include "nextverb.h"        // nextAttrXml — the ONE next= spelling

namespace rw::forpages
{

// The owner's figure; 6,000 is pre-registered beside it. ONE constant: AF2's guarded promotion (foranswerfirst.h G) guards the
// DEFAULT page, so every page size windows the same document and --page-bytes=0 stays the reference for all of them.
inline constexpr std::size_t kForPageBytesDefault = answerfirst::kAnswerPageBytesDefault;

// The page asked: its size in bytes (0 = the whole answer) and its 1-based index; `call` is the same --for call without
// --page-bytes (forUnbudgetedCall), which every page's next= extends.
struct PageAsk
{
    std::size_t      pageBytes = kForPageBytesDefault;
    std::size_t      page      = 1;
    std::string_view call;
};

struct PageResult
{
    enum class Outcome : std::uint8_t
    {
        Whole,           // the answer fits one page, or paging saves nothing: served unchanged
        Paged,           // `doc` is now the asked page
        PastLast,        // the asked page does not exist: `pages` says how many do
        NotApplicable,   // not an answer-first --for document this pass understands: served unchanged
    };
    Outcome     outcome = Outcome::NotApplicable;
    std::size_t pages   = 1;
};

namespace detail
{
// One admissible cut: the byte the page may END at, and the section block (index into the top-level blocks) still OPEN
// there — npos when the cut sits between top-level blocks.
struct Cut
{
    std::size_t at      = 0;
    std::size_t openSec = std::string_view::npos;
};

// The admissible cuts of the row stream (blocks [0, streamEnd)). A section's interior is scanned with the same
// CDATA-safe scanner; an interior it does not understand is one unit (cut only after its close).
// The cuts INSIDE section block k: after each child but the last (the section's own close is cut after instead).
inline void interiorCuts( std::string_view doc, const answerfirst::Block& b, std::size_t k, std::vector<Cut>& cuts )
{
    const std::size_t openEnd = doc.find( '>', b.begin ) + 1;
    if( openEnd < 2 || doc[ openEnd - 2 ] == '/' ) { return; }   // self-closing: no interior
    const std::size_t closeAt = doc.rfind( "</", b.end - 1 );
    if( closeAt == std::string_view::npos || closeAt <= openEnd ) { return; }
    const std::vector<answerfirst::Block> kids = answerfirst::topLevelBlocks( doc, openEnd, closeAt );
    for( std::size_t j = 0; j + 1 < kids.size(); ++j )
    {
        if( !kids[ j ].comment ) { cuts.push_back( { kids[ j ].end, k } ); }
    }
}

inline std::vector<Cut> streamCuts( std::string_view doc, const std::vector<answerfirst::Block>& blocks, std::size_t streamBlocks )
{
    std::vector<Cut> cuts;
    for( std::size_t k = 0; k < streamBlocks; ++k )
    {
        if( blocks[ k ].comment ) { continue; }   // glued to what follows
        interiorCuts( doc, blocks[ k ], k, cuts );
        cuts.push_back( { blocks[ k ].end, std::string_view::npos } );
    }
    return cuts;
}

// The page boundaries: indices into `cuts` of each page's last cut. Page 1 is measured from byte 0, page k from the
// previous page's end; every page takes at least one cut.
inline std::vector<std::size_t> pageEnds( const std::vector<Cut>& cuts, std::size_t pageBytes )
{
    std::vector<std::size_t> ends;
    std::size_t from = 0, i = 0;
    while( i < cuts.size() )
    {
        std::size_t last = i;
        while( last + 1 < cuts.size() && cuts[ last + 1 ].at <= from + pageBytes ) { ++last; }
        ends.push_back( last );
        from = cuts[ last ].at;
        i    = last + 1;
    }
    return ends;
}

// ` name="value"` as it stands in the root open tag, or empty. Values are escapeXml'd, so the first '"' closes one.
[[nodiscard]] inline std::string_view rootAttr( std::string_view rootOpen, std::string_view name )
{
    std::size_t at = 0;
    while( ( at = rootOpen.find( name, at ) ) != std::string_view::npos )
    {
        if( at > 0 && rootOpen[ at - 1 ] == ' ' && rootOpen.compare( at + name.size(), 2, "=\"" ) == 0 )
        {
            const std::size_t close = rootOpen.find( '"', at + name.size() + 2 );
            return close == std::string_view::npos ? std::string_view{} : rootOpen.substr( at - 1, close + 1 - ( at - 1 ) );
        }
        at += name.size();
    }
    return {};
}

// The section open tag of block `k`, verbatim, and its close tag.
[[nodiscard]] inline std::string_view openTagOf( std::string_view doc, const answerfirst::Block& b )
{
    return doc.substr( b.begin, doc.find( '>', b.begin ) + 1 - b.begin );
}
[[nodiscard]] inline std::string closeTagOf( const answerfirst::Block& b ) { return "</" + std::string( b.name ) + ">"; }

// The page disclosure on the root: page= pages= withheld_bytes= and, on every page but the last, next=.
[[nodiscard]] inline std::string pageAttrs( const PageAsk& ask, std::size_t page, std::size_t pages, std::size_t withheld )
{
    std::string a = " page=\"" + std::to_string( page ) + "\" pages=\"" + std::to_string( pages ) + "\" withheld_bytes=\"" + std::to_string( withheld ) + "\"";
    if( page < pages )
    {
        a += nextAttrXml( std::string( ask.call ) + " --page-bytes=" + std::to_string( ask.pageBytes ) + ":" + std::to_string( page + 1 ) );
    }
    return a;
}

// The one clause page 1 adds to the document legend. Defines the four root attributes the page carries.
[[nodiscard]] inline std::string pageClause( std::size_t pageBytes )
{
    return "<!-- page=K of pages=N: an answer-first page, its rows stopped at a row boundary near " + std::to_string( pageBytes )
         + " B; withheld_bytes= row bytes after this page; root next= is the next page: the same rows in the same order, no legend"
           " (this one defines them), ending <about legend=\"ref\" have=\"page1\"/>; the page-bytes=0 flag is the whole answer in one call -->";
}
// est_tokens= PRICES THE PAGE AS DELIVERED, in the emitter's own two rates: markup at kBytesPerTokenDefault, the <bodies>
// section at kBytesPerTokenBody, the attribute's own digits inside the markup it prices (pricedRootAttrTokens' fixpoint).
// Scaling the whole answer's number by the bytes kept was tried first and UNDER-read: formaxtokenscheck (B) priced a
// --detail=30 page at 4,587 tokens where the scaled number said 4,016, because the bytes a page drops are not the
// answer's average mix. Every byte of the page is charged, so a block the whole answer leaves unpriced (<lit>,
// <graph_verb> …) is priced here: a page never claims to be cheaper than it is.
inline void pricePage( std::string& page )
{
    constexpr std::string_view kKey = " est_tokens=\"";
    const std::size_t rootEnd = page.find( '>', page.find( "<ctx" ) );
    const std::size_t at      = page.find( kKey );
    if( at == std::string::npos || at > rootEnd ) { return; }
    const std::size_t close = page.find( '"', at + kKey.size() );
    if( close == std::string::npos || close > rootEnd ) { return; }
    page.erase( at, close + 1 - at );   // priced afresh below, its own bytes included by the fixpoint
    const std::size_t bodiesAt  = page.find( "<bodies" );
    const std::size_t bodiesEnd = bodiesAt == std::string::npos ? std::string::npos : page.find( "</bodies>", bodiesAt );
    const std::size_t bodyBytes = bodiesEnd == std::string::npos ? 0 : bodiesEnd + std::string_view( "</bodies>" ).size() - bodiesAt;
    const std::string attr = pricedRootAttrTokens( page.size() - bodyBytes, kBytesPerTokenDefault,
                                                   bodyBytes > 0 ? tokensForEmittedBytes( bodyBytes, kBytesPerTokenBody ) : 0, nullptr );
    page.insert( at, attr );
}
} // namespace detail

// Cut one finished answer-first --for document to the asked page, in place. See the header.
namespace detail
{
// One answer-first document, read for paging: its root, its top-level blocks, where the row stream ends and the cuts in it.
struct Stream
{
    std::string_view                view;
    std::size_t                     openAt = 0, openEnd = 0, closeAt = 0;
    std::vector<answerfirst::Block> blocks;
    std::size_t                     streamBlocks = 0;   // blocks [0, streamBlocks) are rows; the rest is the document legend
    std::vector<Cut>                cuts;
};

// The stream ends where the trailing run of DOCUMENT legend comments begins. A document legend comment anywhere inside the
// stream means the answer is not answer-first: not a shape this pass pages (nullopt), and the answer is served unchanged.
[[nodiscard]] inline std::optional<Stream> readStream( std::string_view view )
{
    Stream st{ .view = view };
    st.openAt  = view.find( "<ctx" );
    st.openEnd = st.openAt == std::string_view::npos ? std::string_view::npos : view.find( '>', st.openAt );
    st.closeAt = view.rfind( "</ctx>" );
    if( st.openEnd == std::string_view::npos || st.closeAt == std::string_view::npos || st.closeAt <= st.openEnd ) { return std::nullopt; }
    st.blocks       = answerfirst::topLevelBlocks( view, st.openEnd + 1, st.closeAt );
    st.streamBlocks = st.blocks.size();
    while( st.streamBlocks > 0 && st.blocks[ st.streamBlocks - 1 ].comment ) { --st.streamBlocks; }
    for( std::size_t k = 0; k < st.streamBlocks; ++k )
    {
        if( st.blocks[ k ].comment && answerfirst::declaredBlock( view, st.blocks, k ) == std::string_view::npos ) { return std::nullopt; }
    }
    st.cuts = streamCuts( view, st.blocks, st.streamBlocks );
    if( st.cuts.empty() ) { return std::nullopt; }
    return st;
}

// Page 1: the whole root plus the page disclosure, rows [0, end), the close of a section left open, the whole document legend
// and the page clause.
[[nodiscard]] inline std::string firstPage( const Stream& st, const PageAsk& ask, const Cut& end, std::size_t pages )
{
    const std::string_view v = st.view;
    const std::size_t      legendAt = st.blocks[ st.streamBlocks - 1 ].end;
    std::string out;
    out.reserve( end.at + ( st.closeAt - legendAt ) + 1024 );
    out.append( v.substr( 0, st.openEnd ) );
    out += pageAttrs( ask, 1, pages, st.cuts.back().at - end.at );
    out += '>';
    out.append( v.substr( st.openEnd + 1, end.at - ( st.openEnd + 1 ) ) );
    if( end.openSec != std::string_view::npos ) { out += closeTagOf( st.blocks[ end.openSec ] ); }
    out.append( v.substr( legendAt, st.closeAt - legendAt ) );   // the document legend, whole
    out += pageClause( ask.pageBytes );
    out.append( v.substr( st.closeAt ) );
    return out;
}

// Page k >= 2: a slim root (task= at= schema= est_tokens= + the disclosure), the re-opened section the page starts inside,
// rows [start, end), the close of a section left open, and the ref posture's pointer — no legend.
[[nodiscard]] inline std::string continuationPage( const Stream& st, const PageAsk& ask, const Cut& start, const Cut& end, std::size_t pages )
{
    const std::string_view v        = st.view;
    const std::string_view rootOpen = v.substr( st.openAt, st.openEnd - st.openAt );   // without its '>'
    std::string out = "<ctx";
    for( const std::string_view name : { "task", "at", "schema", "est_tokens" } ) { out.append( rootAttr( rootOpen, name ) ); }
    out += pageAttrs( ask, ask.page, pages, st.cuts.back().at - end.at );
    out += '>';
    if( start.openSec != std::string_view::npos ) { out.append( openTagOf( v, st.blocks[ start.openSec ] ) ); }
    out.append( v.substr( start.at, end.at - start.at ) );
    if( end.openSec != std::string_view::npos ) { out += closeTagOf( st.blocks[ end.openSec ] ); }
    out += legenddict::detail::aboutPointer( "page1" );
    out += "</ctx>";
    return out;
}
} // namespace detail

// Cut one finished answer-first --for document to the asked page, in place. See the header.
inline PageResult pageAnswer( std::string& doc, const PageAsk& ask )
{
    const std::optional<detail::Stream> st = ask.pageBytes == 0 ? std::nullopt : detail::readStream( doc );
    if( !st ) { return {}; }
    const std::vector<std::size_t> ends  = detail::pageEnds( st->cuts, ask.pageBytes );
    const std::size_t              pages = ends.size();
    if( ask.page == 0 || ask.page > pages || ( pages == 1 && ask.page != 1 ) ) { return { PageResult::Outcome::PastLast, pages }; }
    if( pages == 1 ) { return { PageResult::Outcome::Whole, 1 }; }
    const detail::Cut& end = st->cuts[ ends[ ask.page - 1 ] ];
    std::string out = ask.page == 1 ? detail::firstPage( *st, ask, end, pages )
                                    : detail::continuationPage( *st, ask, st->cuts[ ends[ ask.page - 2 ] ], end, pages );
    if( ask.page == 1 && out.size() >= doc.size() ) { return { PageResult::Outcome::Whole, pages }; }   // paging saves nothing on page 1
    detail::pricePage( out );
    doc.swap( out );
    return { PageResult::Outcome::Paged, pages };
}

}   // namespace rw::forpages
