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
//      word), no callees question (asksCallees) and no call-path question (asksPath); no breadth or indirection word (G13: how does,
//      callers, callback, handler, flow ...; lane THETA13's patterns) and not one lone ALL-CAPS constant (its sites span files).
//   4. NOT SPREAD PAST WHAT IT CAN NAME (lane THETA6-GUARD, then THETA6-FINISH, 11-24): any <dispatch> (a dynamic call's candidate
//      implementations) or a <reexports> hop (<rx p=>) in a file that holds no <def> keeps the full page. A <callers> 1-hop caller
//      (no d="2") in another non-test file (filter.h isTestPath) keeps the full page unless every cross-file edge fits on the edges
//      line (kSpreadEdgeMax). An answer whose files the tiny shape never names is a silent miss (priced 10 V): the agent has no word
//      that more exists. Measured with the rubric grader on NL1 dev / NL1H / NL2 / S1 / MF1 / LD: 0 rows lost (4 silent before).
// THE EDGES LINE (θ6b): the named symbol's cross-file non-test edges the render already computed — the callees in its served bodies
// (<calls><c p=>), then its callers (1-hop, then d="2") — as one <edges> CDATA line "calls P:L N, ..; called by P:L N, .. (+K more)",
// distinct files first. In NL2's three silent misses the second gold was a callee in another file the full page named only as an
// attribute; the line names it at ~40 B an edge.
// SAME-NAME COMPLETION: when ranked <d> rows past the top kTinyRows carry the named symbol's name (overloads, one method per class),
// up to kTinyRows more of them follow the top rows, so a multi-definition answer is not cut at row 8 without a word.
// And only where nothing else asked for a shape: page 1, no explicit --page-bytes (an explicit one is how "more" escapes the shape),
// no --token-budget / --max-tokens / --detail / --signatures-only / --auto-bodies / --sections / --compress / --with-graph.
//
// THE SHAPE. The root's identity attributes (task route root confidence margin_pct at schema) plus shape="tiny" and est_tokens= priced
// for the bytes served; the root= clause when the render had one; one tiny clause (the row grammar + "more"); the act line and its
// clause when the render had them; <sigs shown=K total=T> holding the top K ranked <d> rows as "P:L-E N" lines in one CDATA (no
// bodies, no metrics, no tail, no fold, no hops); the <edges> line when the named symbol has cross-file edges; and
// <more next="--for=… --page-bytes=N"/>, the exact call for the full page 1 (an explicit --page-bytes turns the shape off, so the call
// returns the page this question gets with the knob unset). One page: no page= / next= of a cut, so no continuation token can break.
//
// RIPWIRE_TINY_SHAPE (any value) turns it ON; RIPWIRE_TINY_SHAPE_FORCE skips the detector (measurement only). Unset, the answer is byte-identical to one served before this file existed
// (test/tinyshapecheck.sh (I)). --version discloses tiny=on only when it is on (the default line is unchanged).
// Gate: test/tinyshapecheck.sh.
#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdlib>
#include <optional>
#include <regex>
#include <span>
#include <string>
#include <string_view>
#include <utility>
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
// θ6b (lane THETA6-FINISH, 11-24): the edges line. A plain tiny answer names its first kEdgeCap cross-file edges (+K more); a named
// symbol with a caller in another file keeps the tiny shape only when ALL its cross-file edges fit in kSpreadEdgeMax. Swept on NL1 dev,
// NL1H, NL2, S1, MF1, LD with the rubric grader: cap 2/4/6 all keep every gold item; the callers rule at 8 loses mf1-fzf-03. The NL3
// seal's one silent miss was a cap-2 cut behind a name-only match: exact edges now rank first (θ6e), and the cap is the conservative 4
// (no cap binds on the tuning sets; 4 costs ~11 B a pick over 2).
inline constexpr std::size_t kEdgeCap       = 4;
inline constexpr std::size_t kSpreadEdgeMax = 6;

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

// Each tag inside `b` past the block's own open tag (CDATA skipped), as the tag's text up to its '>' (close tags included).
template <class Fn> inline void forEachTag( std::string_view doc, const answerfirst::Block& b, Fn&& fn )
{
    const std::string_view body = doc.substr( b.begin, b.end - b.begin );
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
        fn( body.substr( lt, gt - lt ) );
        at = gt + 1;
    }
}

// Each open tag `<name ...>` inside `b` (CDATA skipped), as the tag's text up to its '>'.
template <class Fn> inline void forEachChildTag( std::string_view doc, const answerfirst::Block& b, std::string_view name, Fn&& fn )
{
    const std::string open = "<" + std::string( name ) + " ";
    forEachTag( doc, b, [ & ]( std::string_view tag )
    {
        if( tag.starts_with( open ) ) { fn( tag ); }
    } );
}

// How far the render's relational blocks point past the named file `topFile` (escaped, as the rows print it): guard 4.
enum class Spread
{
    None,      // nothing past the named file but what the edges line can name
    Callers,   // a 1-hop caller in another non-test file: tiny only when every cross-file edge fits on the edges line
    Opaque,    // a <dispatch> (dynamic call candidates) or a <reexports> hop outside the <def> files: always the full page
};

// A 1-hop <callers> row (no d="2") in a file other than `topFile` that is not a test file.
[[nodiscard]] inline bool hasOtherFileCaller( std::string_view doc, const answerfirst::Block& callers, std::string_view topFile )
{
    bool found = false;
    forEachChildTag( doc, callers, "s", [ & ]( std::string_view tag )
    {
        const std::string_view at   = rw::attrOf( tag, "p" );
        const std::string_view file = at.substr( 0, std::min( at.rfind( ':' ), at.size() ) );
        found = found || ( rw::attrOf( tag, "d" ).empty() && !file.empty() && file != topFile && !isTestPath( rowlines::unescaped( file ) ) );
    } );
    return found;
}

// A <reexports> hop (<rx p=>) in a file that holds none of the block's <def>s.
[[nodiscard]] inline bool reexportsElsewhere( std::string_view doc, const answerfirst::Block& reexports )
{
    std::vector<std::string_view> defs;
    bool                          found = false;
    forEachChildTag( doc, reexports, "def", [ & ]( std::string_view tag ) { defs.push_back( rw::attrOf( tag, "p" ) ); } );
    forEachChildTag( doc, reexports, "rx", [ & ]( std::string_view tag ) { found = found || !std::ranges::contains( defs, rw::attrOf( tag, "p" ) ); } );
    return found;
}

[[nodiscard]] inline Spread spreadOf( std::string_view doc, const std::vector<answerfirst::Block>& blocks, std::string_view topFile )
{
    Spread s = Spread::None;
    for( const answerfirst::Block& b : blocks )
    {
        if( b.comment ) { continue; }
        if( b.name == "dispatch" || ( b.name == "reexports" && reexportsElsewhere( doc, b ) ) ) { return Spread::Opaque; }
        if( b.name == "callers" && hasOtherFileCaller( doc, b, topFile ) ) { s = Spread::Callers; }
    }
    return s;
}

// One edge of the named symbol into another non-test file: a callee its served body calls, or a caller of it (unescaped values).
struct Edge
{
    bool        callee   = true;
    bool        nameOnly = false;   // via="name": resolved by the name alone, so it may be the wrong definition (θ6e ranks it last)
    std::string file, line, name;
};

// Whether a <b> body's n= is one of the named symbols (by last name segment), as resolves() matches a row.
[[nodiscard]] inline bool namesASymbol( std::string_view nEsc, const std::vector<std::string>& syms )
{
    const std::string      name = rowlines::unescaped( nEsc );
    const std::string_view seg  = forroute::lastSegment( name );
    return !seg.empty() && std::ranges::any_of( syms, [ & ]( const std::string& s ) { return forroute::lastSegment( s ) == seg; } );
}

// The callees the named symbol's served bodies call (<bodies><b><calls><c>), in page order; when no body is a named symbol's, the
// bodies defined in the named file. A <c> without p= is in its body's file.
inline void bodyCallees( std::string_view doc, const answerfirst::Block& bodies, std::string_view topFile, const std::vector<std::string>& syms,
                         std::vector<Edge>& out )
{
    bool anyNamed = false;
    forEachChildTag( doc, bodies, "b", [ & ]( std::string_view tag ) { anyNamed = anyNamed || namesASymbol( rw::attrOf( tag, "n" ), syms ); } );
    bool             inPicked = false;
    std::string_view bodyFile;
    forEachTag( doc, bodies, [ & ]( std::string_view tag )
    {
        if( tag.starts_with( "<b " ) )
        {
            bodyFile = rw::attrOf( tag, "p" );
            inPicked = anyNamed ? namesASymbol( rw::attrOf( tag, "n" ), syms ) : bodyFile == topFile;
        }
        else if( tag.starts_with( "</b" ) ) { inPicked = false; }
        else if( inPicked && tag.starts_with( "<c " ) )
        {
            const std::string_view p = rw::attrOf( tag, "p" );
            out.push_back( { true, rw::attrOf( tag, "via" ) == "name", rowlines::unescaped( p.empty() ? bodyFile : p ), std::string( rw::attrOf( tag, "l" ) ),
                             rowlines::unescaped( rw::attrOf( tag, "n" ) ) } );
        }
    } );
}

// The named symbol's callers (<callers><s p=F:L>): the 1-hop rows, then the d="2" rows.
inline void blockCallers( std::string_view doc, const answerfirst::Block& callers, std::vector<Edge>& out )
{
    for( const bool twoHop : { false, true } )
    {
        forEachChildTag( doc, callers, "s", [ & ]( std::string_view tag )
        {
            const std::string at = rowlines::unescaped( rw::attrOf( tag, "p" ) );
            const std::size_t colon = at.rfind( ':' );
            if( ( rw::attrOf( tag, "d" ) == "2" ) != twoHop || colon == std::string::npos ) { return; }
            out.push_back( { false, rw::attrOf( tag, "via" ) == "name", at.substr( 0, colon ), at.substr( colon + 1 ), rowlines::unescaped( rw::attrOf( tag, "n" ) ) } );
        } );
    }
}

// θ6b (lane THETA6-FINISH): the edges the render already computed from the named symbol into OTHER non-test files — its body's
// callees, then its callers — de-duplicated by file:line; the exact-resolved edges first, then the name-only (via="name") ones (θ6e),
// each tier ordered distinct files first (a file's second edge after every file's first), so a capped line names as many files as
// it can with the edges most likely to be real. `topFile` is the top row's p= (escaped, as the rows print it).
[[nodiscard]] inline std::vector<Edge> crossFileEdges( std::string_view doc, const std::vector<answerfirst::Block>& blocks, std::string_view topFile,
                                                       const std::vector<std::string>& syms )
{
    std::vector<Edge> all;
    for( const answerfirst::Block& b : blocks )
    {
        if( !b.comment && b.name == "bodies" ) { bodyCallees( doc, b, topFile, syms, all ); }
    }
    for( const answerfirst::Block& b : blocks )
    {
        if( !b.comment && b.name == "callers" ) { blockCallers( doc, b, all ); }
    }
    const std::string                          named = rowlines::unescaped( topFile );
    std::vector<std::pair<std::size_t, Edge>>  ranked;   // (how many earlier kept edges of its tier share its file, the edge)
    for( Edge& e : all )
    {
        const auto sameFile = [ & ]( const std::pair<std::size_t, Edge>& k ) { return k.second.file == e.file; };
        const bool dup = std::ranges::any_of( ranked, [ & ]( const std::pair<std::size_t, Edge>& k ) { return sameFile( k ) && k.second.line == e.line; } );
        if( e.file.empty() || e.file == named || isTestPath( e.file ) || dup ) { continue; }
        const auto nth = static_cast<std::size_t>( std::ranges::count_if( ranked, [ & ]( const std::pair<std::size_t, Edge>& k ) { return sameFile( k ) && k.second.nameOnly == e.nameOnly; } ) );
        ranked.emplace_back( nth, std::move( e ) );
    }
    std::ranges::stable_sort( ranked, {}, []( const std::pair<std::size_t, Edge>& k ) { return std::pair( k.second.nameOnly, k.first ); } );
    std::vector<Edge> out;
    out.reserve( ranked.size() );
    for( auto& [ nth, e ] : ranked ) { out.push_back( std::move( e ) ); }
    return out;
}

// One group of the edges line: "calls P:L N, P:L N" (callees) or "called by P:L N" (callers) over the first `shown` edges; empty if none.
[[nodiscard]] inline std::string edgeGroup( const std::vector<Edge>& edges, std::size_t shown, bool callee )
{
    std::string group;
    for( const Edge& e : std::span( edges ).first( shown ) )
    {
        if( e.callee == callee ) { group.append( group.empty() ? "" : ", " ).append( e.file ).append( ":" ).append( e.line ).append( " " ).append( e.name ); }
    }
    return group.empty() ? group : ( callee ? "calls " : "called by " ) + group;
}

// The <edges> element: the first `cap` edges as "calls P:L N, ..; called by P:L N, .." plus "(+K more)" when cut; empty for none.
[[nodiscard]] inline std::string edgesElement( const std::vector<Edge>& edges, std::size_t cap )
{
    const std::size_t shown   = std::min( cap, edges.size() );
    const std::string callees = edgeGroup( edges, shown, true );
    const std::string callers = edgeGroup( edges, shown, false );
    std::string       text    = callees + ( callees.empty() || callers.empty() ? "" : "; " ) + callers;
    if( text.empty() || text.find( "]]>" ) != std::string::npos ) { return {}; }
    if( shown < edges.size() ) { text.append( " (+" ).append( std::to_string( edges.size() - shown ) ).append( " more)" ); }
    return "<edges shown=\"" + std::to_string( shown ) + "\" total=\"" + std::to_string( edges.size() ) + "\"><![CDATA[" + text + "]]></edges>";
}

// Guard 4's verdict: the tiny shape answers when nothing points past the named file, or when only other-file callers do and every
// cross-file edge fits on the edges line; never past a <dispatch> or an outside <reexports> hop.
[[nodiscard]] inline bool edgesCoverSpread( Spread spread, std::size_t edgeCount ) noexcept
{
    return spread == Spread::None || ( spread == Spread::Callers && edgeCount <= kSpreadEdgeMax );
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

// G13 (lane THETA13, adopted by THETA6-FINISH 11-24): a breadth or indirection word in the question (how does, callers, callback,
// handler, flow ...) asks for more than one location, so the call keeps the full page. The two patterns are THETA13's (feat.py REL and
// BREADTH) verbatim. Measured: fires on 3 tiny picks of 211; with the caps guard it turns the multi-file item cost (+4.2 % of session)
// into a saving and keeps the 1-file one (-1.27 %).
[[nodiscard]] inline bool asksBreadthOrIndirection( std::string_view q )
{
    static const std::regex kIndirection(
        R"(\b(who calls|callers?|called (from|by)|call sites?|calls? (into|out)|callees?|what (does|do) .{0,30}call|uses? of|usages?|)"
        R"(every (place|site|caller|use)|all (the )?(places|sites|callers|uses|implement)|implement(s|ed|ers|ations?|ors)?|overrid(e|es|den|)"
        R"(ing)|subclass(es)?|interface|trait|virtual|abstract|callback|hook(s|ed)?|handler(s)?|dispatch(ed|es|er)?|regist(er|ry|ered|)"
        R"(ration)|plugin|middleware|listener|event|signal|observer|visitor|polymorph|indirect|function pointer|vtable|blast|impact|)"
        R"(what breaks|affected|ripple|end[- ]to[- ]end|flow|path from|trace|pipeline|lifecycle|wired?|plumb))", std::regex::ECMAScript | std::regex::icase );
    static const std::regex kBreadth(
        R"(\b(orient|overview|map of|architecture|subsystems?|how does|how do|walk me|explain how|which files|what files|where .{0,40} (and|)"
        R"(then) |across|throughout)\b)", std::regex::ECMAScript | std::regex::icase );
    const std::string       text( q );
    return std::regex_search( text, kIndirection ) || std::regex_search( text, kBreadth );
}

// The caps guard (THETA13's, DEV-tested here): a question that is one ALL-CAPS identifier (a constant, an env var, a feature flag) is
// answered by its use sites across files more than by its one definition, so the call keeps the full page.
[[nodiscard]] inline bool loneConstant( std::string_view q )
{
    static const std::regex kConstant( R"([A-Z][A-Z0-9]*(_[A-Z0-9]+)+|[A-Z]{3,}[A-Z0-9]*)", std::regex::ECMAScript );
    std::string bare;
    for( const char c : q )
    {
        if( c != '`' && c != '(' && c != ')' ) { bare.push_back( c ); }
    }
    const std::size_t first = bare.find_first_not_of( " \t\n\r" );
    const std::size_t last  = bare.find_last_not_of( " \t\n\r" );
    return first != std::string::npos && std::regex_match( bare.substr( first, last - first + 1 ), kConstant );
}

[[nodiscard]] inline bool relational( std::string_view q )
{
    const std::string lq = rw::routeLower( q );
    return forroute::kindOf( q ) != forroute::RouteKind::None || forroute::detail::asksCallees( lq ) || forroute::detail::asksPath( lq );
}

// The question asks for more than one named location: a route kind or call cue (forroute), a breadth or indirection word (G13), or a
// lone constant (its sites, not its definition).
[[nodiscard]] inline bool asksBeyondOneLocation( std::string_view q )
{
    return relational( q ) || asksBreadthOrIndirection( q ) || loneConstant( q );
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
    if( !forced && ( rw::attrOf( rootOpen, "confidence" ) != "high" || detail::asksBeyondOneLocation( task ) ) ) { return std::nullopt; }
    const std::vector<answerfirst::Block> blocks = answerfirst::topLevelBlocks( doc, rb->openEnd + 1, rb->closeAt );
    const std::vector<detail::RangeRow>   ranked = detail::rankedRanges( doc, blocks );
    const std::vector<detail::RangeRow>   top( ranked.begin(), ranked.begin() + std::min( ranked.size(), kTinyRows ) );
    const std::vector<std::string>        syms = forced ? std::vector<std::string>{} : detail::namedSymbols( task );
    if( top.empty() || ( !forced && !detail::resolves( syms, top ) ) ) { return std::nullopt; }
    const detail::Spread            spread = forced ? detail::Spread::None : detail::spreadOf( doc, blocks, top.front().p );
    const std::vector<detail::Edge> edges  = detail::crossFileEdges( doc, blocks, top.front().p, syms );
    if( !detail::edgesCoverSpread( spread, edges.size() ) ) { return std::nullopt; }
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
    out.append( detail::edgesElement( edges, spread == detail::Spread::Callers ? kSpreadEdgeMax : kEdgeCap ) );
    out.append( "<more" ).append( nextAttrXml( moreCall ) ).append( "/>" );
    out.append( "</ctx>" );
    out.insert( priceAt, rw::pricedRootAttrTokens( out.size(), rw::kBytesPerTokenDefault, 0, nullptr ) );
    return out;
}

}   // namespace rw::tinyshape
