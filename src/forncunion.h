#pragma once
// forncunion.h — NC-UNION: a name-exact --for answer that scored nothing and printed no definition body gets the plain ranker's rows.
//
// WHEN. The route read the task as a name (`route="name-exact(…)"`), nothing scored (`reason="no_candidates"`), and the committed
// answer prints no `<b>` definition body anywhere (outside comments and CDATA, the <syms> rows included). Such an answer is a ladder of
// near misses (the shortkey rungs, the literal lines), and the words of the task, ranked the way --no-route ranks them, often find the
// code the task is about (a type used through an alias, a schema-generated name). When the answer DOES print a body (a shortkey leaf or
// gen rung, a re-export hop), the name resolved after all: the reason is stale, and the plain ranker would only add siblings of the
// definition already shown (measured: the one such call gained three Wrong rows and no item), so nothing is appended.
//
// WHAT. The committed answer's bytes are unchanged except its est_tokens= value. Before </ctx> (after <syms>, before a --with-graph
// block) a `<words ranker="no-route" rows= tails=>` block carries the plain answer's <sigs> <d> rows whose (n=, p=) the committed
// answer does not print as a d, y, s, h or u row, then the plain answer's <tail> <t> pointers whose p= is not a committed tail, both in
// the plain answer's order and spelling. Nothing new is printed: no body, no callee row, no <y>. The block is markup and in est_tokens:
// the root's est_tokens= is re-priced with the same fixpoint the root was priced with (the attribute's own digits included).
//
// WHERE NOT. XML only, single root, and not under --token-budget or --max-tokens (the block has no budgeted form): --json, columnar,
// --candidates, multi-root and budgeted answers are byte-identical. RIPWIRE_NO_NC_UNION=1 turns it off everywhere (the A/B handle).
// The MCP `for` verb does not run it (its twin stays the committed answer).
#include "forfilesyms.h" // filesyms_detail::attrOf — the one attribute reader the answer-reading blocks share
#include "serialize.h"   // tokensForEmittedBytes, kBytesPerTokenDefault — the root's own pricing rate

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
inline bool forNcUnionOn()
{
    return std::getenv( "RIPWIRE_NO_NC_UNION" ) == nullptr;
}

// The gate the block runs under, read from the router's own tag and the root's body-posture attribute (one classifier, one verdict).
inline bool ncUnionRouteGate( const char* routeTag, std::string_view autoAttr )
{
    return routeTag != nullptr && std::strcmp( routeTag, "name-exact" ) == 0 && autoAttr.find( " reason=\"no_candidates\"" ) != std::string_view::npos;
}

inline constexpr std::string_view kForNcUnionLegend =
    "<!-- ripwire for words: the route read the task as a name (name-exact), nothing scored and no definition body is printed above, so the "
    "plain ranker (ranker=no-route: the one --no-route serves) adds its <d> rows whose n= and p= no row above prints, then its <t> tail pointers whose p= no "
    "tail above has, in its rank order and spelling: e= a row's last line, sc= its owner scope, layer= its arch layer, implementors= m= an "
    "interface's implementors and method contract, r= the plain rank, next= that row's follow-up; rows= tails= count them. Leads beside the "
    "committed answer above, which is unchanged; in est_tokens. RIPWIRE_NO_NC_UNION=1 turns it off -->";
inline constexpr std::string_view kForNcUnionLegendCompact =
    "<!-- words: name-exact scored nothing, no body above: the ranker=no-route ranker's d rows then t tails not printed above, its order and "
    "spelling (e= last line, sc= scope, layer= arch layer, implementors= m= interface, r= its rank); rows= tails= counts; in est_tokens; "
    "RIPWIRE_NO_NC_UNION=1 off -->";
// Every attribute the block adds, and every row attribute a plain-ranker row may carry beyond a no_candidates answer's own legend; both
// legends spell each as name= (the legendcoveragecheck predicate), checked at compile time.
inline constexpr std::array<std::string_view, 9> kForNcUnionAttrs { "ranker", "rows", "tails", "e", "sc", "layer", "implementors", "m", "r" };
static_assert( legendDefinesAll( kForNcUnionLegend, kForNcUnionAttrs ), "kForNcUnionLegend must spell every attribute the block can add as name=" );
static_assert( legendDefinesAll( kForNcUnionLegendCompact, kForNcUnionAttrs ), "kForNcUnionLegendCompact must spell every attribute the block can add as name=" );

namespace ncunion_detail
{
// Every start or empty tag outside comments and CDATA, in order: fn( at, close ) with text[at] == '<' and text[close] == '>'. A served
// body's own `<b>` lives in CDATA, so it is code, not a tag.
template<class Fn>
void forEachTag( std::string_view text, Fn&& fn )
{
    for( std::size_t i = text.find( '<' ); i != std::string_view::npos && i + 1 < text.size(); i = text.find( '<', i + 1 ) )
    {
        const std::string_view rest   = text.substr( i );
        const std::string_view skipTo = rest.starts_with( "<!--" ) ? "-->" : rest.starts_with( "<![CDATA[" ) ? "]]>" : "";
        const std::size_t      close  = text.find( skipTo.empty() ? std::string_view( ">" ) : skipTo, i );
        if( close == std::string_view::npos )
        {
            return;
        }
        if( skipTo.empty() && text[i + 1] != '/' )
        {
            fn( i, close );
        }
        i = close;
    }
}

inline bool tagIs( std::string_view text, std::size_t at, std::string_view name )
{
    return text.substr( at + 1 ).starts_with( name ) && at + 1 + name.size() < text.size()
        && ( text[at + 1 + name.size()] == ' ' || text[at + 1 + name.size()] == '>' || text[at + 1 + name.size()] == '/' );
}

// p= without a `:line` suffix (a <y> row spells p="file:line").
inline std::string_view rowPath( std::string_view p )
{
    const std::size_t colon = p.rfind( ':' );
    if( colon == std::string_view::npos || colon + 1 == p.size() )
    {
        return p;
    }
    for( const char c : p.substr( colon + 1 ) )
    {
        if( c < '0' || c > '9' )
        {
            return p;
        }
    }
    return p.substr( 0, colon );
}

// One printed row's identity: its name and its file, both as the answer spells them (escaped forms compare equal on both sides).
using RowKey = std::pair<std::string_view, std::string_view>;

struct Printed
{
    std::vector<RowKey>           rows;    // the committed d / y / s / h / u rows
    std::vector<std::string_view> tails;   // the committed <t> p= values
    bool                          body = false;
};

inline Printed printedOf( std::string_view answer )
{
    Printed out;
    forEachTag( answer, [ & ]( std::size_t at, std::size_t close )
    {
        const std::string_view tag = answer.substr( at + 1, close - at - 1 );
        if( tagIs( answer, at, "b" ) )
        {
            out.body = true;
        }
        else if( tagIs( answer, at, "t" ) )
        {
            out.tails.push_back( filesyms_detail::attrOf( tag, "p" ) );
        }
        else if( tagIs( answer, at, "d" ) || tagIs( answer, at, "y" ) || tagIs( answer, at, "s" ) || tagIs( answer, at, "h" ) || tagIs( answer, at, "u" ) )
        {
            out.rows.emplace_back( filesyms_detail::attrOf( tag, "n" ), rowPath( filesyms_detail::attrOf( tag, "p" ) ) );
        }
    } );
    return out;
}

template<class T>
bool contains( const std::vector<T>& v, const T& x )
{
    return std::find( v.begin(), v.end(), x ) != v.end();
}

// The whole elements of `kind` inside the first `section` element of the plain answer, in order: a self-closed tag, or the tag through its
// close tag. Empty when the answer has no such section.
inline std::vector<std::string_view> sectionElements( std::string_view plain, std::string_view section, std::string_view kind )
{
    std::vector<std::string_view> out;
    std::size_t                   open = std::string_view::npos;
    forEachTag( plain, [ & ]( std::size_t at, std::size_t )
    {
        if( open == std::string_view::npos && tagIs( plain, at, section ) )
        {
            open = at;
        }
    } );
    if( open == std::string_view::npos )
    {
        return out;
    }
    const std::string closeSection = "</" + std::string( section ) + ">";
    const std::size_t sectionEnd   = plain.find( closeSection, open );
    const std::string_view body    = plain.substr( open, sectionEnd == std::string_view::npos ? std::string_view::npos : sectionEnd - open );
    const std::string closeKind    = "</" + std::string( kind ) + ">";
    forEachTag( body, [ & ]( std::size_t at, std::size_t close )
    {
        if( !tagIs( body, at, kind ) )
        {
            return;
        }
        if( body[close - 1] == '/' )
        {
            out.push_back( body.substr( at, close + 1 - at ) );
            return;
        }
        const std::size_t end = body.find( closeKind, close );
        if( end != std::string_view::npos )
        {
            out.push_back( body.substr( at, end + closeKind.size() - at ) );
        }
    } );
    return out;
}

inline std::string_view startTagOf( std::string_view element )
{
    return element.substr( 1, element.find( '>' ) - 1 );
}
}   // namespace ncunion_detail

// Does the committed answer print a definition body (a `<b` tag outside comments and CDATA)?
inline bool ncUnionAnswerPrintsBody( std::string_view committed )
{
    return ncunion_detail::printedOf( committed ).body;
}

// The appended block, or "" when the plain answer adds nothing the committed answer does not print.
inline std::string renderNcUnionBlock( std::string_view committed, std::string_view plain, bool compactLegend )
{
    using namespace ncunion_detail;
    const Printed                 printed = printedOf( committed );
    std::vector<RowKey>           seenRows  = printed.rows;
    std::vector<std::string_view> seenTails = printed.tails;
    std::vector<std::string_view> rows, tails;
    for( const std::string_view d : sectionElements( plain, "sigs", "d" ) )
    {
        const std::string_view tag = startTagOf( d );
        const RowKey           key { filesyms_detail::attrOf( tag, "n" ), rowPath( filesyms_detail::attrOf( tag, "p" ) ) };
        if( !contains( seenRows, key ) )
        {
            seenRows.push_back( key );
            rows.push_back( d );
        }
    }
    for( const std::string_view t : sectionElements( plain, "tail", "t" ) )
    {
        const std::string_view p = filesyms_detail::attrOf( startTagOf( t ), "p" );
        if( !contains( seenTails, p ) )
        {
            seenTails.push_back( p );
            tails.push_back( t );
        }
    }
    if( rows.empty() && tails.empty() )
    {
        return {};
    }
    std::string out = "<words ranker=\"no-route\" rows=\"" + std::to_string( rows.size() ) + "\" tails=\"" + std::to_string( tails.size() ) + "\">";
    out += compactLegend ? kForNcUnionLegendCompact : kForNcUnionLegend;
    for( const std::string_view r : rows )
    {
        out += r;
    }
    for( const std::string_view t : tails )
    {
        out += t;
    }
    out += "</words>";
    return out;
}

// What the root's est_tokens= was priced from (verbs_for.h finishForLensHeaderPriced): every markup byte it measured — the priced
// header itself, attribute included, plus the sections outside it — and the body-rate tokens.
struct NcUnionPricing
{
    std::size_t markupBytes = 0;
    std::size_t bodyTokens  = 0;
};

// Re-price the root's est_tokens= for `extraMarkupBytes` more markup, with the root's own fixpoint (the attribute's digits are bytes of
// the document it prices). No attribute on the root (an unmeasured answer omits it, never fabricates it): unchanged.
inline void repriceNcUnionRoot( std::string& answer, const NcUnionPricing& priced, std::size_t extraMarkupBytes )
{
    static constexpr std::string_view kAttr = " est_tokens=\"";
    const std::size_t          rootEnd  = answer.find( '>' );
    const std::size_t          at       = answer.find( kAttr );
    if( rootEnd == std::string::npos || at == std::string::npos || at > rootEnd )
    {
        return;
    }
    const std::size_t valueAt = at + kAttr.size();
    const std::size_t quote   = answer.find( '"', valueAt );
    if( quote == std::string::npos )
    {
        return;
    }
    const std::size_t oldAttrBytes = quote + 1 - at;
    const std::size_t baseBytes    = priced.markupBytes - oldAttrBytes + extraMarkupBytes;
    const auto        attrFor      = []( std::size_t est ) { return std::string( kAttr ) + std::to_string( est ) + "\""; };
    std::size_t       est          = tokensForEmittedBytes( baseBytes + oldAttrBytes, kBytesPerTokenDefault ) + priced.bodyTokens;
    for( int pass = 0; pass < 4; ++pass )
    {
        const std::size_t next = tokensForEmittedBytes( baseBytes + attrFor( est ).size(), kBytesPerTokenDefault ) + priced.bodyTokens;
        if( next == est )
        {
            break;
        }
        est = next;
    }
    answer.replace( at, oldAttrBytes, attrFor( est ) );
}
}   // namespace rw
