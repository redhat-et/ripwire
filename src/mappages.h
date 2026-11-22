#pragma once
// mappages.h — CL1 (outputceiling.h): the flagless map is served in PAGES when it is over the output ceiling.
//
// WHY. `ripwire DIR` printed a 200-row ranked map plus an inventory of every unlisted file; on GA1 DEV (base 36a95d732, one tree
// per repo) 3 of 11 maps were over 30,000 characters (Newtonsoft.Json 52,858) and 5 over 24,000. Past ~30,000 characters Claude
// Code's Bash tool shows the agent a file path and a 2,000-character preview, so the map an agent orients with never arrived.
//
// WHAT A PAGE IS. The map is rendered WHOLE, exactly as before, and only then cut — so every page of every call is a window onto
// ONE deterministic document, and concatenating the pages' rows rebuilds it (test/outputceilingcheck.sh (M*)). The map's own
// units are the cut points: the root's children (one <f> group per file, <entry>, <inv>), and — inside a child too large to
// share a page, which on a big tree is <inv> — that child's rows (<ls>), the container's open tag re-sent around the part each
// page holds. A comment travels with the element after it. A unit larger than the page is served whole on a page of its own
// rather than split mid-element. Page 1 keeps the header comments (the legend) in front of the root; a continuation page re-sends
// none of them, only the root and one comment defining the page attributes.
//
// THE DISCLOSURE, on the root: page="K" pages="N" withheld_bytes="W" (the whole map's bytes this page does not carry) has_more="0|1", next= the
// call that serves page K+1 (--page-bytes=P:K+1 plus the crawl-scope flags, so it maps the same corpus), and est_tokens=
// re-priced for the page at the whole map's own byte-per-token rate. A map that fits is byte-identical to before.
#include <algorithm>
#include <charconv>
#include <cstddef>
#include <system_error>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "serialize.h"   // pricedRootAttrTokens — est_tokens= prices the page as delivered
#include "nextverb.h"    // nextAttrXml — the ONE next= spelling

namespace rw::mappages
{

inline constexpr std::string_view kMapPageLegend =
    "<!-- map page= pages=: this map is served in pages, cut between its rows (file groups; inside the inventory, its ls rows); "
    "has_more=\"1\": next= (page_next= when the root already carries a next=) serves the next page of the same map; withheld_bytes=: the whole map's bytes this page does not carry -->";

namespace detail
{
// One cut unit: bytes [begin,end) of the document; `container` indexes the split child it sits in (-1: a root child).
struct Unit
{
    std::size_t begin = 0, end = 0;
    int         container = -1;
};
struct Container
{
    std::string open;   // the child's open tag, re-sent around each page's part of it
    std::string close;  // its close tag
};
struct Doc
{
    std::size_t            rootOpenBegin = 0, rootOpenEnd = 0, rootCloseBegin = 0;
    std::vector<Unit>      units;
    std::vector<Container> containers;
};

// The end of the markup item at `at` (a comment, CDATA, or a tag), or npos when it is not closed. Quoted attribute values are
// skipped, so a '>' inside one never ends a tag.
inline std::size_t itemEnd( std::string_view d, std::size_t at ) noexcept
{
    if( d.compare( at, 4, "<!--" ) == 0 )
    {
        const std::size_t e = d.find( "-->", at + 4 );
        return e == std::string_view::npos ? e : e + 3;
    }
    if( d.compare( at, 9, "<![CDATA[" ) == 0 )
    {
        const std::size_t e = d.find( "]]>", at + 9 );
        return e == std::string_view::npos ? e : e + 3;
    }
    bool quoted = false;
    for( std::size_t i = at + 1; i < d.size(); ++i )
    {
        if( d[i] == '"' ) { quoted = !quoted; }
        else if( d[i] == '>' && !quoted ) { return i + 1; }
    }
    return std::string_view::npos;
}

// The end of the element whose open tag ends at `open`, walking its content to the matching close by depth (comments and CDATA
// never nest), or npos when it is not closed inside [.., to). Element text between tags is skipped: markup in it is escaped.
inline std::size_t elementEnd( std::string_view d, std::size_t open, std::size_t to ) noexcept
{
    std::size_t end   = open;
    int         depth = 1;
    while( depth > 0 )
    {
        while( end < to && d[end] != '<' )
        {
            ++end;
        }
        const std::size_t e = end < to ? itemEnd( d, end ) : std::string_view::npos;
        if( e == std::string_view::npos || e > to )
        {
            return std::string_view::npos;
        }
        const bool isMarkupOnly = d.compare( end, 4, "<!--" ) == 0 || d.compare( end, 9, "<![CDATA[" ) == 0;
        depth += d.compare( end, 2, "</" ) == 0 ? -1 : ( !isMarkupOnly && d[e - 2] != '/' ) ? 1 : 0;
        end = e;
    }
    return end;
}

// The children of the element whose content is [from, to): each child's [begin,end), a comment folded into the child after it.
// nullopt when the content does not parse (text between elements, an unclosed item) — the caller then serves the map whole.
inline std::optional<std::vector<Unit>> childrenOf( std::string_view d, std::size_t from, std::size_t to, int container )
{
    std::vector<Unit> out;
    std::size_t       at = from, pendingComment = std::string_view::npos;
    while( at < to )
    {
        const std::size_t open = d[at] == '<' ? itemEnd( d, at ) : std::string_view::npos;
        if( open == std::string_view::npos || open > to )
        {
            return std::nullopt;
        }
        if( d.compare( at, 4, "<!--" ) == 0 )
        {
            pendingComment = std::min( pendingComment, at );
            at = open;
            continue;
        }
        const bool        isElement = d[at + 1] != '/' && d[at + 1] != '!';
        const std::size_t end       = !isElement ? std::string_view::npos : d[open - 2] == '/' ? open : elementEnd( d, open, to );
        if( end == std::string_view::npos )
        {
            return std::nullopt;
        }
        out.push_back( { std::min( pendingComment, at ), end, container } );
        pendingComment = std::string_view::npos;
        at = end;
    }
    if( pendingComment != std::string_view::npos )
    {
        return std::nullopt;
    }
    return out;
}

// The map document read for paging, or nullopt when its shape is not the map's (comments, then <r …>…</r>).
inline std::optional<Doc> readDoc( std::string_view d, std::size_t pageBytes )
{
    Doc doc;
    std::size_t at = 0;
    while( d.compare( at, 4, "<!--" ) == 0 )
    {
        at = itemEnd( d, at );
        if( at == std::string_view::npos ) { return std::nullopt; }
    }
    if( d.compare( at, 3, "<r " ) != 0 ) { return std::nullopt; }
    doc.rootOpenBegin = at;
    doc.rootOpenEnd   = itemEnd( d, at );
    constexpr std::string_view kClose = "</r>";
    if( doc.rootOpenEnd == std::string_view::npos || d.size() < kClose.size() || d.substr( d.size() - kClose.size() ) != kClose ) { return std::nullopt; }
    doc.rootCloseBegin = d.size() - kClose.size();
    const std::optional<std::vector<Unit>> top = childrenOf( d, doc.rootOpenEnd, doc.rootCloseBegin, -1 );
    if( !top ) { return std::nullopt; }
    for( const Unit& u : *top )
    {
        // a child too large to share a page is cut between ITS children instead (on a big tree, <inv>'s <ls> rows)
        // (a child led by a comment is never split: the comment must stay in front of the element it describes)
        const bool        led     = d.compare( u.begin, 4, "<!--" ) == 0;
        const std::size_t openEnd = led ? std::string_view::npos : itemEnd( d, u.begin );
        const std::size_t closeAt = d.rfind( "</", u.end - 1 );
        const bool        nested  = !led && u.end - u.begin > pageBytes / 2 && openEnd != std::string_view::npos && d[openEnd - 2] != '/'
                                 && closeAt != std::string_view::npos && closeAt >= openEnd;
        std::optional<std::vector<Unit>> rows = nested ? childrenOf( d, openEnd, closeAt, int( doc.containers.size() ) ) : std::nullopt;
        if( !rows || rows->empty() )
        {
            doc.units.push_back( u );
            continue;
        }
        doc.containers.push_back( { std::string( d.substr( u.begin, openEnd - u.begin ) ), std::string( d.substr( closeAt, u.end - closeAt ) ) } );
        doc.units.insert( doc.units.end(), rows->begin(), rows->end() );
    }
    return doc;
}

// The half-open unit ranges of each page: greedy, at least one unit a page, a container's open/close charged where it is entered.
inline std::vector<std::pair<std::size_t, std::size_t>> pageRanges( const Doc& doc, std::size_t pageBytes, std::size_t firstFixed, std::size_t restFixed )
{
    std::vector<std::pair<std::size_t, std::size_t>> pages;
    std::size_t begin = 0;
    while( begin < doc.units.size() )
    {
        std::size_t used = pages.empty() ? firstFixed : restFixed;
        std::size_t end  = begin;
        int         open = -1;
        while( end < doc.units.size() )
        {
            const Unit& u    = doc.units[end];
            std::size_t cost = u.end - u.begin;
            if( u.container >= 0 && u.container != open )
            {
                cost += doc.containers[ std::size_t( u.container ) ].open.size() + doc.containers[ std::size_t( u.container ) ].close.size();
            }
            if( end > begin && used + cost > pageBytes ) { break; }
            used += cost;
            open = u.container;
            ++end;
        }
        pages.emplace_back( begin, end );
        begin = end;
    }
    return pages;
}
// The bytes of units [first, last), each split child's open tag re-sent around the part of it they hold.
inline std::string pageRows( std::string_view doc, const Doc& d, std::size_t first, std::size_t last )
{
    std::string rows;
    int         open = -1;
    for( std::size_t i = first; i < last; ++i )
    {
        const Unit& u = d.units[i];
        if( u.container != open )
        {
            rows += open >= 0 ? d.containers[ std::size_t( open ) ].close : std::string();
            rows += u.container >= 0 ? d.containers[ std::size_t( u.container ) ].open : std::string();
            open = u.container;
        }
        rows.append( doc.substr( u.begin, u.end - u.begin ) );
    }
    rows += open >= 0 ? d.containers[ std::size_t( open ) ].close : std::string();
    return rows;
}

// Takes est_tokens= out of `root` (the open tag without its '>') to be re-priced for the page at the whole map's own rate:
// where it stood, and the whole map's price (0 when absent or unreadable — the page is then served unpriced, never mispriced).
struct EstTokens
{
    std::size_t at          = std::string::npos;
    std::size_t wholeTokens = 0;
};
inline EstTokens takeEstTokens( std::string& root )
{
    constexpr std::string_view kEst = " est_tokens=\"";
    EstTokens out;
    out.at = root.find( kEst );
    if( out.at == std::string::npos )
    {
        return out;
    }
    const std::size_t q = root.find( '"', out.at + kEst.size() );
    if( q == std::string::npos || std::from_chars( root.data() + out.at + kEst.size(), root.data() + q, out.wholeTokens ).ec != std::errc() )
    {
        return EstTokens{};
    }
    root.erase( out.at, q + 1 - out.at );
    return out;
}
} // namespace detail

enum class Outcome { Whole, Paged, PastLast };
struct PageResult
{
    Outcome     outcome = Outcome::Whole;
    std::size_t pages   = 1;
};

// Cut the finished map `doc` to page `page` (1-based) of at most ~pageBytes bytes, in place. `call` is the flag list that maps
// the same corpus (crawl-scope flags), which next= extends with --page-bytes=P:K. `deliveredBytes` is what the whole map costs
// as the reader gets it: the compact legend layer rewrites the header AFTER this cut, so `doc` (the full legend) over-states it,
// and the difference is credited to page 1, where the legend rides. A map that fits as delivered, or whose shape is not the
// map's, is left untouched (Whole).
inline PageResult pageMap( std::string& doc, std::size_t pageBytes, std::size_t page, std::string_view call, std::size_t deliveredBytes )
{
    if( pageBytes == 0 || deliveredBytes <= pageBytes ) { return { Outcome::Whole, 1 }; }
    const std::optional<detail::Doc> parsed = detail::readDoc( doc, pageBytes );
    if( !parsed || parsed->units.size() < 2 ) { return { Outcome::Whole, 1 }; }
    const detail::Doc& d = *parsed;
    // page= pages= withheld_bytes= has_more= next= (whose value carries `call`) and a re-priced est_tokens=
    const std::size_t kAttrReserve = 200 + call.size() * 2;
    const std::size_t rootOpen  = d.rootOpenEnd - d.rootOpenBegin;
    const std::size_t fixedRest = kMapPageLegend.size() + rootOpen + kAttrReserve + 4;
    const std::size_t legendCredit = doc.size() > deliveredBytes ? std::min( doc.size() - deliveredBytes, d.rootOpenBegin ) : 0;
    const auto        ranges    = detail::pageRanges( d, pageBytes, d.rootOpenBegin - legendCredit + fixedRest, fixedRest );
    if( page == 0 || page > ranges.size() ) { return { Outcome::PastLast, ranges.size() }; }
    if( ranges.size() == 1 ) { return { Outcome::Whole, 1 }; }

    const auto [ first, last ] = ranges[ page - 1 ];
    const std::string rows = detail::pageRows( doc, d, first, last );
    std::string       root = doc.substr( d.rootOpenBegin, d.rootOpenEnd - d.rootOpenBegin - 1 );
    const auto [ estAt, wholeTokens ] = detail::takeEstTokens( root );
    const std::size_t pages = ranges.size();
    std::string attrs = " page=\"" + std::to_string( page ) + "\" pages=\"" + std::to_string( pages ) + "\"";
    std::string out   = page == 1 ? doc.substr( 0, d.rootOpenBegin ) : std::string();
    out += kMapPageLegend;
    const std::size_t pageNoWithheld = out.size() + root.size() + attrs.size() + rows.size() + 4;
    attrs += " withheld_bytes=\"" + std::to_string( doc.size() > pageNoWithheld ? doc.size() - pageNoWithheld : 0 ) + "\"";
    // the root's own next= (the data-sections follow-up, when the map cut them) keeps its name; the page then rides page_next=
    const std::string_view nextName = root.find( " next=\"" ) == std::string::npos ? "next" : "page_next";
    attrs += page < pages ? " has_more=\"1\"" + nextAttrXml( std::string( call ) + ( call.empty() ? "" : " " ) + "--page-bytes=" + std::to_string( pageBytes )
                                                             + ":" + std::to_string( page + 1 ), nextName )
                          : std::string( " has_more=\"0\"" );
    out += root;
    out += attrs;
    if( estAt != std::string::npos && wholeTokens > 0 )
    {
        const double rate = double( doc.size() ) / double( wholeTokens );
        const std::size_t bytesSoFar = out.size() + 1 + rows.size() + 4;
        out.insert( d.rootOpenBegin * ( page == 1 ) + kMapPageLegend.size() + estAt, pricedRootAttrTokens( bytesSoFar, rate, 0, nullptr ) );
    }
    out += '>';
    out += rows;
    out += "</r>";
    doc.swap( out );
    return { Outcome::Paged, pages };
}

}   // namespace rw::mappages
