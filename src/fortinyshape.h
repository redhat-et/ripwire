// fortinyshape.h — THETA6, THE "NAMED LOCATION" TINY SHAPE (PLAN_071 §1.5 θ6, TD §4.1; a DEV knob, default OFF).
//
// WHY. A question that names one symbol the index resolves with a sharp ranking ("where is `X` / what does `X` do") is answered by
// one grep and one Read in plain grep+read. The default --for page serves it 4-14 KB (bodies, tail, fold, hops); the agent then
// Reads the range anyway (Claude Code's Edit needs a prior Read). The tiny shape serves the ranges only — about 1-2 KB — and one
// continuation for the full page, so a question the shape under-serves costs one call, not a re-search.
//
// THE DETECTOR (all three, on the RAW render after the act line went in):
//   1. a NAMED SYMBOL that RESOLVES: a backtick span that is an identifier path (forroute.h rule E's reading, its trailing "()"/"!"
//      trimmed), or a bare word of the question that is an identifier path AND code-shaped (forroute isCodeShaped: _ :: . # or a
//      lower-to-upper step), whose last name segment (forroute lastSegment) is the last segment of the n= of one of the top kTinyRows
//      ranked <sigs> <d> rows;
//   2. HIGH CONFIDENCE by the existing signal: the root's confidence="high" (lexical.h kForConfidenceNote: a material relative score
//      drop inside the served head, or every positive match already shown — no new scorer);
//   3. NOT RELATIONAL: forroute's own cue readers find no route kind (kindOf == None: no transitive / radius / where-used / call
//      word), no callees question (asksCallees) and no call-path question (asksPath).
//   4. NOT SPREAD OVER FILES (lane THETA6-GUARD, 11-24): the render computed no relational block that points past the named file —
//      a <callers> 1-hop caller (no d="2") in another non-test file (filter.h isTestPath), any <dispatch> (a dynamic call's candidate
//      implementations), or a <reexports> hop (<rx p=>) in a file that holds no <def>. Such an answer names files the tiny rows
//      never list, and nothing in the tiny shape would tell the agent they exist (a silent miss, priced 10 V), so the call keeps
//      the full page. Measured on the in-sample sets: 0 completes lost on S1/MF1/LD (6 before), 0 golds on NL1 dev / NL1H.
// SAME-NAME COMPLETION: when ranked <d> rows past the top kTinyRows carry the named symbol's name (overloads, one method per class),
// up to kTinyRows more of them follow the top rows, so a multi-definition answer is not cut at row 8 without a word.
// And only where nothing else asked for a shape: page 1, no explicit --page-bytes (an explicit one is how "more" escapes the shape),
// no --token-budget / --max-tokens / --detail / --signatures-only / --auto-bodies / --sections / --compress / --with-graph.
//
// THE SHAPE. The root's identity attributes (task route root confidence margin_pct at schema) plus shape="tiny" and est_tokens= priced
// for the bytes served; the root= clause when the render had one; one tiny clause (the row grammar + "more"); the act line and its
// clause when the render had them; <sigs shown=K total=T> holding the top K ranked <d> rows as "P:L-E N" lines in one CDATA (no
// bodies, no metrics, no tail, no fold, no hops); and <more next="--for=… --page-bytes=N"/>, the exact call for the full page 1 (an
// explicit --page-bytes turns the shape off, so the call returns the page this question gets with the knob unset). One page: no
// page= / next= of a cut, so no continuation token can break.
//
// RIPWIRE_TINY_SHAPE (any value) turns it ON; RIPWIRE_TINY_SHAPE_FORCE skips the detector (measurement only). Unset, the answer is byte-identical to one served before this file existed
// (test/tinyshapecheck.sh (I)). --version discloses tiny=on only when it is on (the default line is unchanged).
// Gate: test/tinyshapecheck.sh.
#pragma once

#include <cstddef>
#include <cstdlib>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "foractline.h"     // kActClause / detail::rankedCandidates — the act line's ranked-row reader
#include "foranswerfirst.h" // rootBody / topLevelBlocks — the one CDATA-safe scanner of a --for answer's blocks
#include "forroute.h"       // the route cue readers and rule E's identifier predicates
#include "filter.h"         // isTestPath — the one language-neutral test-path convention
#include "forrowlines.h"    // readSection / unescaped — the one strict row reader
#include "nextverb.h"       // nextAttrXml — a continuation attribute
#include "serialize.h"      // attrOf / pricedRootAttrTokens / kBytesPerTokenDefault

namespace rw::tinyshape
{

// RIPWIRE_TINY_SHAPE_FORCE (any value): the shape on EVERY eligible call, the detector skipped: the measurement arm that labels which
// questions the shape serves completely (lane THETA6 Step 0), never a product posture. It implies the knob.
[[nodiscard]] inline bool tinyShapeForced() noexcept { return std::getenv( "RIPWIRE_TINY_SHAPE_FORCE" ) != nullptr; }
[[nodiscard]] inline bool tinyShapeOn() noexcept { return std::getenv( "RIPWIRE_TINY_SHAPE" ) != nullptr || tinyShapeForced(); }

inline constexpr std::size_t kTinyRows = 8;   // ranked rows listed (and searched for the named symbol): ~8 x 45 B of lines

inline constexpr std::string_view kTinyClause =
    "<!-- tiny shape (a named location): each sigs line is P:L-E N, a ranked definition (path:first-last line, name), best first; "
    "no bodies: Read the ranges; more next= is the call for the full answer -->";

// The root attributes the tiny root keeps: what names the question, the ranker and the tree, not what describes a dropped block.
inline constexpr std::string_view kKeptRootAttrs[] = { "task", "route", "root", "confidence", "margin_pct", "at", "schema" };

namespace detail
{
// One ranked <d> row of the raw <sigs>: its printed (escaped) p= l= e= n= values.
struct RangeRow
{
    std::string_view p, l, e, n;
};

// Every ranked <d> row of the raw <sigs>, in rank order (the caller lists the top kTinyRows and the same-name rows past them).
[[nodiscard]] inline std::vector<RangeRow> rankedRanges( std::string_view doc, const std::vector<answerfirst::Block>& blocks )
{
    std::vector<RangeRow> rows;
    const auto sigs = std::ranges::find_if( blocks, []( const answerfirst::Block& b ) { return !b.comment && b.name == "sigs"; } );
    const std::optional<rowlines::Section> sec = sigs == blocks.end() ? std::nullopt : rowlines::readSection( doc, *sigs );
    if( !sec ) { return rows; }
    for( const rowlines::Row& row : sec->rows )
    {
        if( !row.tag || row.tag->name != "d" ) { continue; }
        const std::string_view tag = actline::detail::openTagText( row );
        rows.push_back( { rw::attrOf( tag, "p" ), rw::attrOf( tag, "l" ), rw::attrOf( tag, "e" ), rw::attrOf( tag, "n" ) } );
    }
    return rows;
}

// Each open tag `<name ...>` inside `b` (CDATA skipped), as the tag's text up to its '>'.
template <class Fn> inline void forEachChildTag( std::string_view doc, const answerfirst::Block& b, std::string_view name, Fn&& fn )
{
    const std::string_view body = doc.substr( b.begin, b.end - b.begin );
    const std::string      open = "<" + std::string( name ) + " ";
    std::size_t            at   = body.find( '>' );   // past the block's own open tag
    while( at != std::string_view::npos && at < body.size() )
    {
        const std::size_t lt = body.find( '<', at );
        if( lt == std::string_view::npos ) { return; }
        if( body.substr( lt ).starts_with( "<![CDATA[" ) )
        {
            const std::size_t close = body.find( "]]>", lt );
            at = close == std::string_view::npos ? close : close + 3;
            continue;
        }
        const std::size_t gt = body.find( '>', lt );
        if( gt == std::string_view::npos ) { return; }
        if( body.substr( lt ).starts_with( open ) ) { fn( body.substr( lt, gt - lt ) ); }
        at = gt + 1;
    }
}

// Guard 4: a relational block of the render points past the named file `topFile` (escaped, as the rows print it).
[[nodiscard]] inline bool spreadsPastFile( std::string_view doc, const std::vector<answerfirst::Block>& blocks, std::string_view topFile )
{
    for( const answerfirst::Block& b : blocks )
    {
        if( b.comment ) { continue; }
        if( b.name == "dispatch" ) { return true; }
        bool spread = false;
        if( b.name == "callers" )
        {
            forEachChildTag( doc, b, "s", [ & ]( std::string_view tag )
            {
                const std::string_view at   = rw::attrOf( tag, "p" );
                const std::string_view file = at.substr( 0, std::min( at.rfind( ':' ), at.size() ) );
                spread = spread || ( rw::attrOf( tag, "d" ).empty() && !file.empty() && file != topFile && !isTestPath( rowlines::unescaped( file ) ) );
            } );
        }
        else if( b.name == "reexports" )
        {
            std::vector<std::string_view> defs;
            forEachChildTag( doc, b, "def", [ & ]( std::string_view tag ) { defs.push_back( rw::attrOf( tag, "p" ) ); } );
            forEachChildTag( doc, b, "rx", [ & ]( std::string_view tag ) { spread = spread || !std::ranges::contains( defs, rw::attrOf( tag, "p" ) ); } );
        }
        if( spread ) { return true; }
    }
    return false;
}

// The rows the tiny shape lists: the top kTinyRows, then up to kTinyRows more ranked rows that carry a named symbol's name.
[[nodiscard]] inline std::vector<RangeRow> listedRows( const std::vector<RangeRow>& ranked, const std::vector<std::string>& syms )
{
    std::vector<RangeRow> rows( ranked.begin(), ranked.begin() + std::min( ranked.size(), kTinyRows ) );
    std::size_t           more = 0;
    for( std::size_t i = kTinyRows; i < ranked.size() && more < kTinyRows; ++i )
    {
        const std::string      name = rowlines::unescaped( ranked[ i ].n );   // owned: lastSegment views into it
        const std::string_view seg  = forroute::lastSegment( name );
        if( std::ranges::any_of( syms, [ & ]( const std::string& s ) { return !seg.empty() && forroute::lastSegment( s ) == seg; } ) )
        {
            rows.push_back( ranked[ i ] );
            ++more;
        }
    }
    return rows;
}

// The question's named symbols, as rule E reads a backtick span, plus its bare code-shaped words.
[[nodiscard]] inline std::vector<std::string> namedSymbols( std::string_view q )
{
    std::vector<std::string> out;
    forroute::detail::forEachBacktickSpan( q, [ & ]( std::string_view raw )
    {
        const std::string_view span = forroute::detail::trimCallSuffix( raw );
        if( forroute::detail::isIdentPath( span ) ) { out.emplace_back( span ); }
    } );
    const std::string rest = forroute::detail::withoutBacktickSpans( q );
    std::size_t       i    = 0;
    while( i < rest.size() )
    {
        const std::size_t b = rest.find_first_not_of( " \t\n\r", i );
        if( b == std::string::npos ) { break; }
        const std::size_t e    = std::min( rest.find_first_of( " \t\n\r", b ), rest.size() );
        std::string_view  word = std::string_view( rest ).substr( b, e - b );
        while( !word.empty() && std::string_view( ".,;:?!)\"'" ).find( word.back() ) != std::string_view::npos ) { word.remove_suffix( 1 ); }
        while( !word.empty() && std::string_view( "(\"'" ).find( word.front() ) != std::string_view::npos ) { word.remove_prefix( 1 ); }
        word = forroute::detail::trimCallSuffix( word );
        if( forroute::detail::isIdentPath( word ) && forroute::detail::isCodeShaped( word ) ) { out.emplace_back( word ); }
        i = e;
    }
    return out;
}

[[nodiscard]] inline bool relational( std::string_view q )
{
    const std::string lq = rw::routeLower( q );
    return forroute::kindOf( q ) != forroute::RouteKind::None || forroute::detail::asksCallees( lq ) || forroute::detail::asksPath( lq );
}

[[nodiscard]] inline bool resolves( const std::vector<std::string>& syms, const std::vector<RangeRow>& rows )
{
    for( const std::string& s : syms )
    {
        const std::string_view seg = forroute::lastSegment( s );
        for( const RangeRow& r : rows )
        {
            if( !seg.empty() && forroute::lastSegment( rowlines::unescaped( r.n ) ) == seg ) { return true; }
        }
    }
    return false;
}

// The leading-legend comment whose text starts with `lead`, or empty.
[[nodiscard]] inline std::string_view leadComment( std::string_view doc, const std::vector<answerfirst::Block>& blocks, std::string_view lead )
{
    for( const answerfirst::Block& b : blocks )
    {
        if( !b.comment ) { break; }
        const std::string_view c = doc.substr( b.begin, b.end - b.begin );
        if( c.starts_with( lead ) ) { return c; }
    }
    return {};
}
}   // namespace detail

// The tiny answer for `doc` (a RAW --for render, the act line already in), or nullopt when the detector does not fire. `task` is the
// question; `moreCall` the call that returns the full page 1.
[[nodiscard]] inline std::optional<std::string> tinyAnswer( std::string_view doc, std::string_view task, std::string_view moreCall )
{
    const std::optional<answerfirst::RootBody> rb = doc.starts_with( "<ctx" ) ? answerfirst::rootBody( doc ) : std::nullopt;
    if( !rb ) { return std::nullopt; }
    const std::string_view rootOpen = doc.substr( 0, rb->openEnd );
    const bool             forced   = tinyShapeForced();
    if( !forced && ( rw::attrOf( rootOpen, "confidence" ) != "high" || detail::relational( task ) ) ) { return std::nullopt; }
    const std::vector<answerfirst::Block> blocks = answerfirst::topLevelBlocks( doc, rb->openEnd + 1, rb->closeAt );
    const std::vector<detail::RangeRow>   ranked = detail::rankedRanges( doc, blocks );
    const std::vector<detail::RangeRow>   top( ranked.begin(), ranked.begin() + std::min( ranked.size(), kTinyRows ) );
    const std::vector<std::string>        syms = forced ? std::vector<std::string>{} : detail::namedSymbols( task );
    if( top.empty() || ( !forced && ( !detail::resolves( syms, top ) || detail::spreadsPastFile( doc, blocks, top.front().p ) ) ) )
    {
        return std::nullopt;
    }
    const std::vector<detail::RangeRow> rows = detail::listedRows( ranked, syms );

    std::string lines;
    for( const detail::RangeRow& r : rows )
    {
        if( r.p.empty() || r.l.empty() ) { continue; }
        lines.append( lines.empty() ? "" : "\n" ).append( rowlines::unescaped( r.p ) ).append( ":" ).append( r.l );
        lines.append( r.e.empty() ? "" : "-" ).append( r.e ).append( " " ).append( rowlines::unescaped( r.n ) );
    }
    if( lines.empty() || lines.find( "]]>" ) != std::string::npos ) { return std::nullopt; }

    std::string out = "<ctx";
    for( const std::string_view name : kKeptRootAttrs )
    {
        const std::string_view v = rw::attrOf( rootOpen, name );
        if( !v.empty() ) { out.append( " " ).append( name ).append( "=\"" ).append( v ).append( "\"" ); }
    }
    out.append( " shape=\"tiny\"" );
    const std::size_t priceAt = out.size();
    out.append( ">" );
    out.append( detail::leadComment( doc, blocks, "<!-- root= " ) ).append( kTinyClause );
    const auto act = std::ranges::find_if( blocks, []( const answerfirst::Block& b ) { return !b.comment && b.name == "act"; } );
    if( act != blocks.end() ) { out.append( actline::kActClause ); }
    const std::string_view total = rw::attrOf( doc.substr( doc.find( "<sigs" ) ), "total" );
    out.append( "<sigs shown=\"" ).append( std::to_string( std::ranges::count( lines, '\n' ) + 1 ) ).append( "\"" );
    if( !total.empty() ) { out.append( " total=\"" ).append( total ).append( "\"" ); }
    out.append( "><![CDATA[" ).append( lines ).append( "]]></sigs>" );
    if( act != blocks.end() ) { out.append( doc.substr( act->begin, act->end - act->begin ) ); }
    out.append( "<more" ).append( nextAttrXml( moreCall ) ).append( "/>" );
    out.append( "</ctx>" );
    out.insert( priceAt, rw::pricedRootAttrTokens( out.size(), rw::kBytesPerTokenDefault, 0, nullptr ) );
    return out;
}

}   // namespace rw::tinyshape
