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
// <= c(k-1) + P; a unit larger than P is served whole rather than split. KB1 (forkeybody.h): the key-body group is not counted
// by the page it starts on.
//
// WHERE THE LEGEND SITS, and why. 5ee3ddb38 made answer-first opt-in because, as a default, it moved the READINGS of the
// cuts and floors out of the prefix (measured for AF1: a bare 12 KB answer-first prefix shows a marker with no definition
// inside it on 137 of 154 design cells; legend-first, 0). A PAGE is not a truncated prefix: page 1 keeps the document
// legend after its rows and before </ctx>, so every attribute the page carries is defined inside the page — and it defines
// every later page's attributes too, except the clauses only a later page's rows use (LD1, forpagelegend.h: those travel
// with the page whose rows carry them; THE RULE: what page N carries is defined on page N or page 1). The page's OWN disclosure
// (page= pages= withheld_bytes= next=) rides the ROOT, in the first bytes, so the cut is the first thing a reader meets:
// root, then rows, then the dictionary — the collapse condition 5ee3ddb38 wrote beside kLegendPostures.
//
// A CONTINUATION PAGE RE-SENDS NO LEGEND page 1 holds — only the clauses page 1 shed that its own rows carry, in one comment
// before its pointer (LD1). It is the ref posture (legenddict.h): rows first, a slim root, and a closing
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
#include "forpagelegend.h"   // LD1: a clause only a later page uses travels with that page
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
    std::size_t free    = 0;   // KB1: key-body group bytes before `at` that no page counts (readStream; 0 without a key group)
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

// KB1 (forkeybody.h): the key-body block's legend comment opens with this; the block it declares is <bodies of="key">.
inline constexpr std::string_view kKeyBodyLegendLead = "<!-- bodies of=key:";

// The bytes of [begin, end) that lie before `at`: what page 1 does not count of the key-body group (KB1).
[[nodiscard]] constexpr std::size_t uncountedBefore( std::size_t at, std::size_t begin, std::size_t end ) noexcept
{
    return at <= begin ? 0 : std::min( at, end ) - begin;
}

// The page boundaries: indices into `cuts` of each page's last cut. Page 1 is measured from byte 0, page k from the
// previous page's end; every page takes at least one cut. KB1: a page measures its bytes without the key-body group (Cut::free; BR1b:
// and without the act line, markActLine), so the
// page the group starts on (page 1 at the default size, forkeybody.h) ends at the row it ended at without it, the group is never split
// across pages, and every other page holds the same rows.
inline std::vector<std::size_t> pageEnds( const std::vector<Cut>& cuts, std::size_t pageBytes )
{
    std::vector<std::size_t> ends;
    std::size_t from = 0, i = 0;
    while( i < cuts.size() )
    {
        std::size_t last = i;
        while( last + 1 < cuts.size() && cuts[ last + 1 ].at - cuts[ last + 1 ].free <= from + pageBytes ) { ++last; }
        ends.push_back( last );
        from = cuts[ last ].at - cuts[ last ].free;
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

// Where one page sits in the answer: its index, the page count, the row bytes after it, and its SECTION disclosure (sectionAttrs).
struct PageAt
{
    std::size_t      page = 1, pages = 1, withheld = 0;
    std::string_view sections;
};

// The page disclosure on the root: page= pages= withheld_bytes=, continued=/deferred= and, on every page but the last, next=.
[[nodiscard]] inline std::string pageAttrs( const PageAsk& ask, const PageAt& at )
{
    std::string a = " page=\"" + std::to_string( at.page ) + "\" pages=\"" + std::to_string( at.pages ) + "\" withheld_bytes=\"" + std::to_string( at.withheld ) + "\"";
    a += at.sections;
    if( at.page < at.pages )
    {
        a += nextAttrXml( std::string( ask.call ) + " --page-bytes=" + std::to_string( ask.pageBytes ) + ":" + std::to_string( at.page + 1 ) );
    }
    return a;
}

// The one clause page 1 adds to the document legend. Defines the four root attributes the page carries.
// AF1-fix: it also defines continued= and deferred= (sectionAttrs), and says what est_tokens= and every OTHER root attribute
// describe on a page: est_tokens= is the page's own price (pricePage, every byte — a block the whole answer prices outside its
// est_tokens, such as <shortkey>, is inside a page's), every other root attribute is the whole answer's.
[[nodiscard]] inline std::string pageClause( std::size_t pageBytes )
{
    return "<!-- page=K of pages=N: an answer-first page, its rows stopped at a row boundary near " + std::to_string( pageBytes )
         + " B; withheld_bytes= row bytes after this page; continued= the section whose rows go on past this page; deferred= the"
           " sections that start on a later page, each named once (absent: none); est_tokens= prices this page, every byte of it;"
           " every other root attribute, and the open tag of a continued or re-opened section, counts the WHOLE answer; root next="
           " is the next page: the same rows in the same"
           " order, no legend but what only its rows use (this one defines the rest), ending"
           " <about legend=\"ref\" have=\"page1\"/>; the page-bytes=0 flag is the"
           " whole answer in one call -->";
}
// What a document's price is read from: where the root's est_tokens= attribute sits (the space before it through its closing
// quote) and the bytes of its <bodies> section (priced at kBytesPerTokenBody; the rest is markup). nullopt: the <ctx> root's open
// tag carries no est_tokens=. The ONE reader of both, for pricePage and for the act line's repriceAdded (foractline.h; lane BR1C:
// that reprice had grown a 314-token copy of this reader).
struct RootPriceSpan
{
    std::size_t at = 0, attrLen = 0, bodyBytes = 0;
};
[[nodiscard]] inline std::optional<RootPriceSpan> rootPriceSpan( std::string_view doc ) noexcept
{
    constexpr std::string_view kKey = " est_tokens=\"";
    const std::size_t rootEnd = doc.find( '>', doc.find( "<ctx" ) );
    const std::size_t at      = doc.find( kKey );
    if( at == std::string_view::npos || at > rootEnd ) { return std::nullopt; }
    const std::size_t close = doc.find( '"', at + kKey.size() );
    if( close == std::string_view::npos || close > rootEnd ) { return std::nullopt; }
    const std::size_t bodiesAt  = doc.find( "<bodies" );
    const std::size_t bodiesEnd = bodiesAt == std::string_view::npos ? std::string_view::npos : doc.find( "</bodies>", bodiesAt );
    const std::size_t bodyBytes = bodiesEnd == std::string_view::npos ? 0 : bodiesEnd + std::string_view( "</bodies>" ).size() - bodiesAt;
    return RootPriceSpan{ at, close + 1 - at, bodyBytes };
}

// est_tokens= PRICES THE PAGE AS DELIVERED, in the emitter's own two rates: markup at kBytesPerTokenDefault, the <bodies>
// section at kBytesPerTokenBody, the attribute's own digits inside the markup it prices (pricedRootAttrTokens' fixpoint).
// Scaling the whole answer's number by the bytes kept was tried first and UNDER-read: formaxtokenscheck (B) priced a
// --detail=30 page at 4,587 tokens where the scaled number said 4,016, because the bytes a page drops are not the
// answer's average mix. Every byte of the page is charged, so a block the whole answer leaves unpriced (<lit>,
// <graph_verb> …) is priced here: a page never claims to be cheaper than it is.
inline void pricePage( std::string& page )
{
    const std::optional<RootPriceSpan> s = rootPriceSpan( page );
    if( !s ) { return; }
    // priced afresh, the attribute's own bytes included by the fixpoint
    page.replace( s->at, s->attrLen, pricedRootAttrTokens( page.size() - s->attrLen - s->bodyBytes, kBytesPerTokenDefault,
                                                           s->bodyBytes > 0 ? tokensForEmittedBytes( s->bodyBytes, kBytesPerTokenBody ) : 0, nullptr ) );
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
    std::size_t                     keyBegin = 0, keyEnd = 0;   // KB1: the key-body group (legend comment + <bodies of="key">), or empty
    std::vector<std::size_t>        gone;   // LD1: the document-legend clauses page 1 sheds to the later pages that use them (scope::shed)
};

// KB1: find the key-body group (its legend comment, then <bodies of="key">) among the stream's blocks and mark every cut with the group
// bytes before it, which no page counts (pageEnds).
inline void markKeyGroup( Stream& st )
{
    for( std::size_t k = 0; k + 1 < st.streamBlocks; ++k )
    {
        const answerfirst::Block& c = st.blocks[ k ];
        if( c.comment && st.view.substr( c.begin ).starts_with( kKeyBodyLegendLead ) && !st.blocks[ k + 1 ].comment && st.blocks[ k + 1 ].name == "bodies" )
        {
            st.keyBegin = c.begin;
            st.keyEnd   = st.blocks[ k + 1 ].end;
            for( Cut& cut : st.cuts ) { cut.free = uncountedBefore( cut.at, st.keyBegin, st.keyEnd ); }
            return;
        }
    }
}

// BR1b (foractline.h): no page counts the act line either — it is the answer's reading instruction, not a row — so a page ends at the
// row it ended at without it and the line never costs a page a row (MEASURED without this, GA1 DEV n=89 page 1: 76 answers lost 1-2
// rows, 116 in all). It is one element, so no cut falls inside it.
inline void markActLine( Stream& st )
{
    for( std::size_t k = 0; k < st.streamBlocks; ++k )
    {
        const answerfirst::Block& b = st.blocks[ k ];
        if( !b.comment && b.name == "act" )
        {
            for( Cut& cut : st.cuts ) { cut.free += uncountedBefore( cut.at, b.begin, b.end ); }
            return;
        }
    }
}

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
    markKeyGroup( st );
    markActLine( st );   // after markKeyGroup, which assigns free= (this adds to it)
    return st;
}

// THE PAGE'S SECTION DISCLOSURE (AF1-fix, 2026-11-18). A page is a window, so a section that starts past the cut is simply
// not in it — and the root it rides keeps the WHOLE answer's attributes (bundle= bodies= reason= …), which name sections the
// page does not hold. Without this, page 1 of a compact-route answer said bodies="0" bundle="compact" and carried no <hops>,
// the edge context that bundle IS (compactroutecheck (2)); a --detail=3 page carried no <bodies> (detailcheck); a name-exact
// page said bodies="1" and held no body (anchorbodycheck (7b)). The integrator read those as silent drops, and on the page
// alone they were. So every page but the last names, on its root, what it does not hold:
//   continued="X"   the section left open at the cut: its rows go on on the next page, and its open tag counts the whole
//                   section (shown= on a continued <tail> is the whole tail's, not this page's);
//   deferred="A B"  every top-level element that STARTS on a later page, each name once, in answer order.
// Present or disclosed-deferred: a reader of page 1 holds either the section or its name and the next= that reaches it.
[[nodiscard]] inline std::string sectionAttrs( const Stream& st, const Cut& end )
{
    std::string a;
    if( end.openSec != std::string_view::npos ) { a += " continued=\"" + std::string( st.blocks[ end.openSec ].name ) + "\""; }
    std::vector<std::string_view> later;
    for( std::size_t k = 0; k < st.streamBlocks; ++k )
    {
        const answerfirst::Block& b = st.blocks[ k ];
        if( !b.comment && b.begin >= end.at && std::ranges::find( later, b.name ) == later.end() ) { later.push_back( b.name ); }
    }
    if( later.empty() ) { return a; }
    a += " deferred=\"";
    for( std::size_t i = 0; i < later.size(); ++i )
    {
        if( i > 0 ) { a += ' '; }
        a.append( later[ i ] );
    }
    a += '"';
    return a;
}

// Page 1: the whole root plus the page disclosure, rows [0, end), the close of a section left open, the document legend less the
// clauses that travel with a later page (LD1, forpagelegend.h: `gone`), and the page clause.
[[nodiscard]] inline std::string firstPage( const Stream& st, const PageAsk& ask, const Cut& end, std::size_t pages )
{
    const std::string_view v = st.view;
    const std::size_t      legendAt = st.blocks[ st.streamBlocks - 1 ].end;
    std::string out;
    out.reserve( end.at + ( st.closeAt - legendAt ) + 1024 );
    out.append( v.substr( 0, st.openEnd ) );
    const std::string sections = sectionAttrs( st, end );
    out += pageAttrs( ask, { .page = 1, .pages = pages, .withheld = st.cuts.back().at - end.at, .sections = sections } );
    out += '>';
    out.append( v.substr( st.openEnd + 1, end.at - ( st.openEnd + 1 ) ) );
    if( end.openSec != std::string_view::npos ) { out += closeTagOf( st.blocks[ end.openSec ] ); }
    out += scope::firstPageLegend( v.substr( legendAt, st.closeAt - legendAt ), st.gone );   // the document legend, less what travels
    out += pageClause( ask.pageBytes );
    out.append( v.substr( st.closeAt ) );
    return out;
}

// Page k >= 2: a slim root (task= at= schema= est_tokens= + the disclosure), the re-opened section the page starts inside,
// rows [start, end), the close of a section left open, the clauses page 1 shed that THESE rows carry (LD1, forpagelegend.h), and
// the ref posture's pointer — no other legend.
[[nodiscard]] inline std::string continuationPage( const Stream& st, const PageAsk& ask, const Cut& start, const Cut& end, std::size_t pages )
{
    const std::string_view v        = st.view;
    const std::string_view rootOpen = v.substr( st.openAt, st.openEnd - st.openAt );   // without its '>'
    std::string out = "<ctx";
    for( const std::string_view name : { "task", "at", "schema", "est_tokens" } ) { out.append( rootAttr( rootOpen, name ) ); }
    const std::string sections = sectionAttrs( st, end );
    out += pageAttrs( ask, { .page = ask.page, .pages = pages, .withheld = st.cuts.back().at - end.at, .sections = sections } );
    out += '>';
    if( start.openSec != std::string_view::npos ) { out.append( openTagOf( v, st.blocks[ start.openSec ] ) ); }
    out.append( v.substr( start.at, end.at - start.at ) );
    if( end.openSec != std::string_view::npos ) { out += closeTagOf( st.blocks[ end.openSec ] ); }
    out += scope::laterPageComment( st.gone, out );   // the slim root's task= is escaped: it spells no element or ` attr="`
    out += legenddict::detail::aboutPointer( "page1" );
    out += "</ctx>";
    return out;
}
// LD1 (forpagelegend.h): which document-legend clauses page 1 sheds, decided on every page's rows as that page serves them (page 1
// with its root, page k with the section it re-opens), comments and CDATA blanked — so each page of one answer asks the same.
[[nodiscard]] inline std::vector<std::size_t> shedFor( const Stream& st, const std::vector<std::size_t>& ends )
{
    std::vector<std::string>      rows;
    std::vector<std::string_view> views;
    for( std::size_t k = 0; k < ends.size(); ++k )
    {
        const Cut&             to   = st.cuts[ ends[ k ] ];
        const Cut*             from = k == 0 ? nullptr : &st.cuts[ ends[ k - 1 ] ];
        const std::string_view head = from == nullptr || from->openSec == std::string_view::npos ? std::string_view() : openTagOf( st.view, st.blocks[ from->openSec ] );
        const std::size_t      at   = from == nullptr ? 0 : from->at;
        rows.push_back( scope::rowsOnly( std::string( head ) + std::string( st.view.substr( at, to.at - at ) ) ) );
    }
    views.reserve( views.size() + rows.size() );
    for( const std::string& r : rows ) { views.push_back( r ); }
    const std::size_t legendAt = st.blocks[ st.streamBlocks - 1 ].end;
    return scope::shed( st.view.substr( legendAt, st.closeAt - legendAt ), views );
}
} // namespace detail

// ES (lane RT2, results/RT2_ROUTE_1118/PREREG.md §ES): page 1 ENDED EARLY, right after stream block `blockIdx`, because that
// block proved itself complete (the caller's test). It is still a page of THIS answer and says so the AF1-fix way: page="1"
// pages=N (the answer's own pagination at this size), withheld_bytes= every row byte it does not carry, deferred= every section
// that starts later, plus early="proven". Its legend is `blockLegend` (the clause the block needs, from the caller) and the early
// page's own clause — not the whole document legend. Its next= is the FULL page 1 (a spelled --page-bytes never ends early), so
// no row is more than one call away. nullopt: not a pageable answer-first document, or nothing would be saved.
[[nodiscard]] inline std::optional<std::string> earlyFirstPage( std::string_view doc, const PageAsk& ask, std::size_t blockIdx, std::string_view blockLegend )
{
    const std::optional<detail::Stream> st = ask.pageBytes == 0 ? std::nullopt : detail::readStream( doc );
    if( !st || blockIdx >= st->streamBlocks || st->blocks[ blockIdx ].comment )
    {
        return std::nullopt;
    }
    const std::size_t      pages    = detail::pageEnds( st->cuts, ask.pageBytes ).size();
    const detail::Cut      end{ st->blocks[ blockIdx ].end, std::string_view::npos };
    const std::string_view rootOpen = doc.substr( st->openAt, st->openEnd - st->openAt );
    std::string out = "<ctx";
    for( const std::string_view name : { "task", "at", "schema", "est_tokens" } )
    {
        out.append( detail::rootAttr( rootOpen, name ) );
    }
    out += " page=\"1\" pages=\"" + std::to_string( pages ) + "\" withheld_bytes=\"" + std::to_string( st->cuts.back().at - end.at ) + "\" early=\"proven\"";
    out += detail::sectionAttrs( *st, end );
    out += nextAttrXml( std::string( ask.call ) + " --page-bytes=" + std::to_string( ask.pageBytes ) + ":1" );
    out += '>';
    out.append( doc.substr( st->openEnd + 1, end.at - ( st->openEnd + 1 ) ) );
    out.append( blockLegend );
    out += "<!-- page=1 early=proven: an answer-first page 1 ENDED EARLY after its first block, because that block proved itself"
           " complete (shown= equals total=, nothing capped, and no evidence of a miss was found); pages= the answer's pages at "
         + std::to_string( ask.pageBytes ) + " B, withheld_bytes= its row bytes not on this page, deferred= the sections that start"
           " later; est_tokens= prices this page; root next= is the FULL page 1, whose own next= is page 2 -->";
    out += "</ctx>";
    if( out.size() >= doc.size() )
    {
        return std::nullopt;
    }
    detail::pricePage( out );
    return out;
}

// Cut one finished answer-first --for document to the asked page, in place. See the header.
inline PageResult pageAnswer( std::string& doc, const PageAsk& ask )
{
    std::optional<detail::Stream> st = ask.pageBytes == 0 ? std::nullopt : detail::readStream( doc );
    if( !st ) { return {}; }
    const std::vector<std::size_t> ends  = detail::pageEnds( st->cuts, ask.pageBytes );
    const std::size_t              pages = ends.size();
    if( ask.page == 0 || ask.page > pages || ( pages == 1 && ask.page != 1 ) ) { return { PageResult::Outcome::PastLast, pages }; }
    if( pages == 1 ) { return { PageResult::Outcome::Whole, 1 }; }
    const detail::Cut& end = st->cuts[ ends[ ask.page - 1 ] ];
    st->gone = detail::shedFor( *st, ends );   // LD1
    std::string out = ask.page == 1 ? detail::firstPage( *st, ask, end, pages )
                                    : detail::continuationPage( *st, ask, st->cuts[ ends[ ask.page - 2 ] ], end, pages );
    if( ask.page == 1 && out.size() >= doc.size() ) { return { PageResult::Outcome::Whole, pages }; }   // paging saves nothing on page 1
    detail::pricePage( out );
    doc.swap( out );
    return { PageResult::Outcome::Paged, pages };
}

}   // namespace rw::forpages
