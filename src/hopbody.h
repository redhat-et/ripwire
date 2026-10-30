#pragma once
// hopbody.h — THE BODY OF A MIDDLE HOP (lane path-hop-body, train 41): two answers that name a function and stop short of what it does.
//
// WHY. A reached --path answer prints each hop as a <s t= n= p=> row and nothing else. When the path is short, the question is often
// what happens INSIDE the middle hop: hono's `Hono.fetch -> Hono.#dispatch -> compose` names #dispatch, and the whole request flow
// (path extraction, router match, Context, the one-handler fast path, compose, error handling) lives in its body, which the answer
// never printed (readout-40 G: 0 of 7 items; the same body through --expand: 6 of 7). The --for body fold has the twin gap: it serves
// `fetch`, a one-line wrapper around `this.#dispatch(...)`, and stops there.
//
// WHAT. (1) PATH-HOP-BODY: a reached --path whose shown chain has at most kPathHopBodyMaxHops hops prints, after its hop rows, the body
// of each INTERMEDIATE hop (never an endpoint, never one whose text the answer already carries: fold_detail::overlapsServed) inside <bodies of="hops" shown= total= capped=>,
// each <b> the --expand body element (no callee rows, no file context). A chain past the gate prints no body and the root carries
// next= (the first middle hop's --expand) unless another continuation already owns next=. (2) WRAPPER-FOLLOW: a body the --for fold
// serves that is a THIN DELEGATOR (thinDelegate: a function or method whose text holds exactly one call site of any kind, that call a
// proven edge, at most kThinBodyLines statement lines) is followed by its callee's body, <b follow_of=>, at most kWrapperFollowDepth
// levels and kWrapperFollowMax bodies per answer. (3) BODY-ON-ROUTE (fix1, textual-11): a reachable=0 answer prints the bodies of the
// route it already names (pathgaps.h pathRouteBodies: the bridge rows within kRouteBodyMaxHops of from=, the handler_rule readers),
// every one a hedge. ONE printer serves (1) and (3) (routeBodiesXml): a body whose hop is no proven call carries that hop's hedge.
// THE BOUND IS A SPEW GUARD, NEVER A COMPLETENESS CUT (owner rule): each body is whole up to kHopBodyCapBytes; a longer one is cut at a
// line end by packBodies' own truncation, which says so on the element (truncated="1" lines="1-K/T" next= the call serving the rest).

#include "defattrib.h"  // edgeSplitArm — the hop row's prov="split", read for a body's hedge
#include "graph.h"
#include "langfacts.h"  // dashDashComments / leadingDocstring — the statement-line rule's per-language columns
#include "lexical.h"    // lexicalScanText — the body text the index read
#include "model.h"
#include "nextverb.h"   // nextFlag
#include "sarif.h"      // rootPrefixOf / rootRelativeUri — the --expand selector's path
#include "serialize.h"  // packBodies, chargeSection, escapeXml

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// The per-body spew guard (bytes of source text): whole below it, cut at a line end and disclosed above it. Measured over the in-sample
// --path rows and the --for fold follows (reports/path-hop-body.md): the bodies these answers need are 0.4-3.6 KB.
inline constexpr std::size_t kHopBodyCapBytes = 4000;
// The hop-count gate: a chain of at most this many hops prints its middle hop's body (kPathHopBodyMaxHops - 1 = one body). Measured
// (reports/path-hop-body.md, the curve over the in-sample --path rows): 2 hops buys hono-12 its 6 items; 3 hops adds flake8-14
// (+1.6 KB, already complete), 4 hops fzf-14 and tmux-14 (+13 KB, both already complete) and nothing else; past the gate next= names the body.
inline constexpr std::size_t kPathHopBodyMaxHops = 2;
// A thin delegator's body: at most this many statement lines (a line holding more than brackets and separators, not a comment).
inline constexpr std::size_t kThinBodyLines = 3;
// How many delegations the fold follows from one served body (fetch -> #dispatch is one; a handle -> fetch -> #dispatch two).
inline constexpr std::size_t kWrapperFollowDepth = 2;
// THE FOLLOW SPEW GUARD (review, fix1): at most this many follow bodies in one --for answer (the slot owner and every fold piece
// each follow up to kWrapperFollowDepth levels: unbounded, that was ~8 x 4.1 KB). Past it the fold says so: <follow_cut n= next=>.
inline constexpr std::size_t kWrapperFollowMax = 3;

namespace fold_detail
{
// does a's text lie inside b's: the same file and b's span holds a's (two equal spans: the later id is the inner one). A body
// inside another the answer serves is already there — the fold serves each text once (FIX1 N2).
inline bool spanInside( const IngestResult& ing, NodeId a, NodeId b ) noexcept
{
    const Symbol& x = ing.symbols[a];
    const Symbol& y = ing.symbols[b];
    return a != b && x.fileId == y.fileId && y.sigStartByte <= x.sigStartByte && x.endByte <= y.endByte
        && ( y.sigStartByte < x.sigStartByte || x.endByte < y.endByte || b < a );
}
// does a's text overlap a body in `ids` the answer already serves: a is one of them or lies inside one, or (orHolds) holds one
inline bool overlapsServed( const IngestResult& ing, NodeId a, std::span<const NodeId> ids, bool orHolds ) noexcept
{
    for( const NodeId b : ids )
    {
        if( a == b || spanInside( ing, a, b ) || ( orHolds && spanInside( ing, b, a ) ) )
        {
            return true;
        }
    }
    return false;
}
}   // namespace fold_detail

// The A/B switch (the RIPWIRE_NO_BODY_FOLD precedent): both mechanisms ride unless RIPWIRE_NO_HOP_BODY is set.
inline bool hopBodiesOn()
{
    return std::getenv( "RIPWIRE_NO_HOP_BODY" ) == nullptr;
}

// One body through packBodies (the --expand body shape, no callee rows: the empty CSR has no out-edge for any id), unwrapped from its
// <bodies> envelope; the legend comments packBodies writes ahead of or inside the envelope stay in front of the <b>. capBytes 0 =
// whole; else a body over it is cut at a line end with truncated="1" lines= next= (packBodies' first-body truncation). nullopt when
// the buffer failed or the span rendered nothing.
inline std::optional<std::string> renderBodyElement( const IngestResult& ing, NodeId id, std::size_t capBytes, bool compress, RedactCounts* redact,
                                                     std::string_view rootArg, const std::vector<float>* rank )
{
    static const std::vector<std::uint32_t> kNoOff;
    static const std::vector<NodeId>        kNoTargets;
    static const std::vector<std::uint8_t>  kNoNameOnly;
    ChargedSection sec = chargeSection( [ & ]( std::FILE* f )
        { packBodies( f, ing, { id }, capBytes, kNoOff, kNoTargets, CalleeEdgeBytes( kNoNameOnly ), compress, redact,
                      /*ranges=*/nullptr, /*notes=*/nullptr, /*outEmitted=*/nullptr, /*truncateOversizedFirst=*/capBytes > 0,
                      /*withFileContext=*/false, rootArg, rank, {} ); },
        kBytesPerTokenBody );
    if( !sec.isRendered )
    {
        return std::nullopt;
    }
    std::string&      x     = sec.xml;
    const std::size_t open  = x.find( "<bodies shown=" );
    const std::size_t close = open == std::string::npos ? std::string::npos : x.find( '>', open );
    constexpr std::string_view kClose = "</bodies>";
    if( close == std::string::npos || !x.ends_with( kClose ) || x.find( "<b t=\"", close ) == std::string::npos )
    {
        return std::nullopt;   // an unreadable span renders an empty envelope: nothing to serve
    }
    return x.substr( 0, open ) + x.substr( close + 1, x.size() - kClose.size() - close - 1 );
}

// Is `line` a statement line: anything but whitespace and bracket/separator characters, and not a whole-line comment. `*` opens a
// comment line only as a block-comment continuation (`* text`, `*/`, a bare `*`), never a C store `*p = v;`; `--` only in Lua (F3).
inline bool isStatementLine( std::string_view line, Lang lang ) noexcept
{
    const std::size_t a = line.find_first_not_of( " \t\r" );
    if( a == std::string_view::npos )
    {
        return false;
    }
    const std::string_view t           = line.substr( a );
    const bool             starComment = t == "*" || t.starts_with( "* " ) || t.starts_with( "*\t" ) || t.starts_with( "*/" );
    if( t.starts_with( "//" ) || t.starts_with( "#" ) || t.starts_with( "/*" ) || starComment || ( langFacts( lang ).dashDashComments && t.starts_with( "--" ) ) )
    {
        return false;
    }
    return t.find_first_not_of( "{}()[];, \t\r" ) != std::string_view::npos;
}

// The triple quote that opens a Python docstring on this trimmed line (after an optional r/u/b/f prefix), a single quote for a
// one-line '…' / "…" docstring, or "" when the line is not a string literal.
inline std::string_view pythonDocstringQuote( std::string_view t ) noexcept
{
    std::size_t k = 0;
    while( k < t.size() && k < 2 && std::string_view( "rRuUbBfF" ).find( t[k] ) != std::string_view::npos )
    {
        ++k;
    }
    const std::string_view q = t.substr( k );
    for( const std::string_view open : { std::string_view( "\"\"\"" ), std::string_view( "'''" ), std::string_view( "\"" ), std::string_view( "'" ) } )
    {
        if( q.starts_with( open ) )
        {
            return open;
        }
    }
    return {};
}

// The statement lines of a body (isStatementLine), a leading Python docstring not counted (F4: only the FIRST statement can be one);
// counting stops past `stopAbove` (the caller needs no exact count beyond its bound).
inline std::size_t bodyStatementLines( std::string_view body, Lang lang, std::size_t stopAbove ) noexcept
{
    std::size_t      statements = 0;
    std::string_view docClose;                        // inside a leading multi-line docstring: its closing quote
    bool             docAllowed = langFacts( lang ).leadingDocstring;
    while( !body.empty() && statements <= stopAbove )
    {
        const std::size_t      nl   = body.find( '\n' );
        const std::string_view line = body.substr( 0, nl );
        body                        = nl == std::string_view::npos ? std::string_view() : body.substr( nl + 1 );
        if( !docClose.empty() )
        {
            docClose = line.find( docClose ) != std::string_view::npos ? std::string_view() : docClose;
            continue;
        }
        if( !isStatementLine( line, lang ) )
        {
            continue;
        }
        const std::string_view q = docAllowed ? pythonDocstringQuote( line.substr( line.find_first_not_of( " \t\r" ) ) ) : std::string_view();
        docAllowed               = false;
        if( q.empty() )
        {
            ++statements;
            continue;
        }
        const std::string_view tr   = line.substr( line.find_first_not_of( " \t\r" ) );
        const std::size_t      open = tr.find( q );
        docClose = q.size() == 3 && tr.find( q, open + q.size() ) == std::string_view::npos ? q : std::string_view();
    }
    return statements;
}

// The call sites W's own text holds: every call reference inside its span (resolved, by name, declined, external or undefined alike:
// a call the graph holds no edge for is still a call), nested lambdas included, and the start byte of the first. Only a Call-role use
// counts (not a read, a type, an inherit, a doc link or a HAS-A member). One scan of ing.references, run last, after the cheap tests.
struct SpanCalls
{
    std::size_t   count = 0;
    std::uint32_t firstByte = 0;
};
inline SpanCalls callSitesInSpan( const IngestResult& ing, const Symbol& s ) noexcept
{
    SpanCalls out;
    for( const Reference& r : ing.references )
    {
        if( r.fileId == s.fileId && r.role == RefRole::Call && !r.isInherit && !r.isDocLink && !r.isCompose && r.startByte >= s.sigStartByte
            && r.startByte < s.endByte )
        {
            out.firstByte = out.count++ == 0 || r.startByte < out.firstByte ? r.startByte : out.firstByte;
        }
    }
    return out;
}

// Is the call at `callByte` W's LAST statement: no statement line of `body` (W's text past the signature, starting at bodyByte) starts
// after the call's line outside the call's own parentheses. `let n = 0; for (…) { f(j); n++ } return n` (a loop aggregator, review F6)
// and `t = a * b; audit(t); return t * t` (logic beside one call) are not delegators; `return f(\n a,\n b)` is.
inline bool callIsLastStatement( std::string_view body, std::size_t bodyByte, std::size_t callByte, Lang lang ) noexcept
{
    if( callByte < bodyByte || callByte >= bodyByte + body.size() )
    {
        return callByte < bodyByte;   // a call in the signature (a default argument) has no body statement after it to check here
    }
    const std::size_t at       = callByte - bodyByte;
    const std::size_t lineEnd  = body.find( '\n', at );
    if( lineEnd == std::string_view::npos )
    {
        return true;
    }
    long depth = 0;
    for( std::size_t k = at; k < lineEnd; ++k )
    {
        depth += body[k] == '(' ? 1 : body[k] == ')' ? -1 : 0;
    }
    std::string_view rest = body.substr( lineEnd + 1 );
    while( !rest.empty() )
    {
        const std::size_t      nl   = rest.find( '\n' );
        const std::string_view line = rest.substr( 0, nl );
        if( depth <= 0 && isStatementLine( line, lang ) )
        {
            return false;
        }
        for( const char c : line )
        {
            depth += c == '(' ? 1 : c == ')' ? -1 : 0;
        }
        rest = nl == std::string_view::npos ? std::string_view() : rest.substr( nl + 1 );
    }
    return true;
}

// THE THIN DELEGATOR: the callee `id` wraps, or kNoNode. Decided only when provably unique (the inverted honesty rule): W is a
// function or method (F5); its text holds exactly ONE call site of any kind (callSitesInSpan, F2: a declined, external or undefined
// call beside it makes W no delegator), and that call is W's one resolved out-edge, a proven call (not by name alone, not a link);
// the call is W's last statement (callIsLastStatement, F6); the callee has a body; and W's body past the signature holds at most
// kThinBodyLines statement lines (a leading Python docstring is not one, F4). Anything else is not a delegator and nothing is followed.
inline NodeId thinDelegate( const IngestResult& ing, const Graph& g, NodeId id )
{
    if( id >= ing.symbols.size() || id + 1 >= g.outOff.size() || g.outOff[id + 1] - g.outOff[id] != 1 )
    {
        return kNoNode;
    }
    const std::uint32_t e = g.outOff[id];
    const NodeId        t = g.outTargets[e];
    if( t == id || t >= ing.symbols.size() || ( e < g.outNameOnly.size() && g.outNameOnly[e] != 0 )
        || ( id < g.ambOut.size() && g.ambOut[id] != 0 ) || ( id < g.unresolvedOut.size() && g.unresolvedOut[id] != 0 ) )
    {
        return kNoNode;
    }
    const Symbol& s  = ing.symbols[id];
    const Symbol& ts = ing.symbols[t];
    if( ( s.kind != SymKind::Function && s.kind != SymKind::Method ) || ts.kind == SymKind::ModuleScope || ts.endByte <= ts.sigStartByte
        || s.endByte <= s.sigEndByte )
    {
        return kNoNode;
    }
    std::string        scratch;
    const std::string* text = lexicalScanText( ing, s.fileId, scratch );
    if( text == nullptr || s.endByte > text->size() || s.sigEndByte < s.sigStartByte )
    {
        return kNoNode;
    }
    const std::string_view body       = std::string_view( *text ).substr( s.sigEndByte, s.endByte - s.sigEndByte );
    const std::size_t      statements = bodyStatementLines( body, s.lang, kThinBodyLines );
    if( statements == 0 || statements > kThinBodyLines )
    {
        return kNoNode;
    }
    const SpanCalls calls = callSitesInSpan( ing, s );
    if( calls.count != 1 || !callIsLastStatement( body, s.sigEndByte, calls.firstByte, s.lang ) )
    {
        return kNoNode;   // F2: one call site of ANY kind in W's text; F6: and it is W's last statement (W hands off, it does not compute)
    }
    return t;
}

// The --expand selector of one definition, as the answer spells p= (root-relative on a single root), unescaped.
inline std::string expandSelectorOf( const IngestResult& ing, NodeId id, std::string_view rootArg )
{
    const Symbol&     s          = ing.symbols[id];
    const std::string rootPrefix = rootArg.empty() ? std::string() : sarif::rootPrefixOf( rootArg );
    const std::string path       = rootArg.empty() ? std::string( ing.files[s.fileId] ) : std::string( sarif::rootRelativeUri( ing.files[s.fileId], rootPrefix ) );
    return nextFlag( "--expand=", path + ":" + std::to_string( s.line ) + ":" + s.name );
}

// Insert `attrs` in front of the '>' of the first open tag that starts with `openPrefix` (the fold's <b follow_of=>, the body slot's
// <bodies pick=>); an unexpected shape leaves the document as it was.
inline void insertOpenTagAttrs( std::string& xml, std::string_view openPrefix, std::string_view attrs )
{
    const std::size_t at = xml.find( openPrefix );
    if( at == std::string::npos )
    {
        return;
    }
    const std::size_t close = xml.find( '>', at );
    if( close != std::string::npos )
    {
        xml.insert( close, attrs );
    }
}

// ONE BODY ON A ROUTE and the hedge its hop carries, spelled as the attributes its <b> prints ("" = reached by a proven call edge).
// THE HONESTY RULE (review F1 + BODY-ON-ROUTE): a body whose hop is not a proven call — by name, a link, a split arm, a bridge
// crossing (declined / value / queue / name-key / slot …), a handler_rule reader — prints that hop's hedge ON the <b> row, so one
// candidate's body never reads as the proven callee; nothing here enters reachable=, hops= or any proven count.
struct RouteBody
{
    NodeId      id = kNoNode;
    std::string hedge;   // e.g. ` via="name" cands="2"`, ` via="queue" cands="3"`; "" on a proven call
};

// How many definitions a by-name call from `from` could bind to `to`'s name: its by-name out-edges to that name (>= 1).
inline std::size_t byNameCandidates( const IngestResult& ing, const Graph& g, NodeId from, NodeId to ) noexcept
{
    std::size_t n = 0;
    for( std::uint32_t e = g.outOff[from]; e < g.outOff[std::size_t( from ) + 1]; ++e )
    {
        const NodeId t = g.outTargets[e];
        n += t < ing.symbols.size() && ing.symbols[t].name == ing.symbols[to].name && e < g.outNameOnly.size() && edgeKindByte( g.outNameOnly[e] ) == kEdgeName ? 1u : 0u;
    }
    return std::max<std::size_t>( n, 1 );
}

// The hedge of the chain hop from -> to, as the hop row spells it: "" on a proven call edge; via="name" cands=K on a by-name edge,
// via="link" on a markdown link, prov="split" on a split arm, via="impl" on the one-implementor edge (pathpairs.h pathHopHedged's set), via="bridge" when the graph holds no edge (a bridge pair's crossing).
inline std::string chainHopHedge( const IngestResult& ing, const Graph& g, NodeId from, NodeId to )
{
    if( edgeIndex( g, from, to ) == SIZE_MAX )
    {
        return " via=\"bridge\"";
    }
    if( edgeNameOnly( g, from, to ) )
    {
        return " via=\"name\" cands=\"" + std::to_string( byNameCandidates( ing, g, from, to ) ) + "\"";
    }
    if( edgeIsLink( g, from, to ) )
    {
        return " via=\"link\"";
    }
    if( edgeSplitArm( g, from, to ) )
    {
        return " prov=\"split\"";
    }
    return edgeViaImpl( g, from, to ) ? " via=\"impl\"" : "";
}

// THE PATH'S MIDDLE HOPS: the intermediate rows of `chain` (never an endpoint), in chain order, deduped, minus `served` (a body the
// enclosing answer already carries), each with the hedge of the edge into it (chainHopHedge). Empty when the chain is past the hop
// gate or has no middle.
inline std::vector<RouteBody> pathMiddleHops( const IngestResult& ing, const Graph& g, std::span<const NodeId> chain, std::span<const NodeId> served )
{
    std::vector<RouteBody> out;
    if( chain.size() < 3 || chain.size() - 1 > kPathHopBodyMaxHops )
    {
        return out;
    }
    for( std::size_t i = 1; i + 1 < chain.size(); ++i )
    {
        const NodeId n = chain[i];
        if( n < ing.symbols.size() && ing.symbols[n].kind != SymKind::ModuleScope && ing.symbols[n].endByte > ing.symbols[n].sigStartByte
            && std::ranges::find( out, n, &RouteBody::id ) == out.end() && !fold_detail::overlapsServed( ing, n, served, /*orHolds=*/true ) )
        {
            out.push_back( { n, chainHopHedge( ing, g, chain[i - 1], n ) } );
        }
    }
    return out;
}

// next= for a reached chain past the hop gate: the first middle hop's --expand (unescaped), "" when the chain has no middle or is
// within the gate (its bodies print).
inline std::string pathMiddleHopNext( const IngestResult& ing, std::span<const NodeId> chain, std::string_view rootArg )
{
    if( chain.size() < 3 || chain.size() - 1 <= kPathHopBodyMaxHops )
    {
        return {};
    }
    return expandSelectorOf( ing, chain[1], rootArg );
}

// THE ONE BODY PRINTER (the reached path's middle hops and the unreached route alike): <bodies of=OF{rootAttrs} shown= total= capped=
// [next=]> holding at most maxBodies bodies, each whole up to kHopBodyCapBytes (a longer one is cut, truncated="1"), each <b> carrying
// its hop's hedge. Past maxBodies (a spew guard): capped="1" and next= the first unshown body's --expand. "" when none renders.
struct RouteBodiesXml
{
    std::string         xml;
    bool                hedged = false;   // some <b> carries a hedge (its legend clause rides)
    std::vector<NodeId> ids;              // the definitions whose <b> rendered (not the ones asked for): what <alts> must not list again
};
inline RouteBodiesXml routeBodiesXml( const IngestResult& ing, std::span<const RouteBody> bodies, std::string_view of, std::string_view rootAttrs,
                                      std::size_t maxBodies, std::string_view rootArg )
{
    RouteBodiesXml out;
    std::string    children;
    std::size_t    shown = 0;
    bool           cut   = false;
    std::string    next;
    for( const RouteBody& rb : bodies )
    {
        if( shown == maxBodies )
        {
            next = expandSelectorOf( ing, rb.id, rootArg );
            break;
        }
        if( std::optional<std::string> b = renderBodyElement( ing, rb.id, kHopBodyCapBytes, /*compress=*/false, /*redact=*/nullptr, rootArg, nullptr ) )
        {
            if( !rb.hedge.empty() )
            {
                insertOpenTagAttrs( *b, "<b t=\"", rb.hedge );
                out.hedged = true;
            }
            cut = cut || b->find( " truncated=\"1\"" ) != std::string::npos;
            children += *b;
            out.ids.push_back( rb.id );
            ++shown;
        }
    }
    if( shown == 0 )
    {
        return {};
    }
    out.xml = "<bodies of=\"" + std::string( of ) + "\"" + std::string( rootAttrs ) + " shown=\"" + std::to_string( shown ) + "\" total=\""
            + std::to_string( bodies.size() ) + "\" capped=\"" + ( cut || shown < bodies.size() ? "1" : "0" ) + "\""
            + ( next.empty() ? std::string() : nextAttrXml( next ) ) + ">" + children + "</bodies>";
    return out;
}

// THE PATH'S <bodies of="hops"> ELEMENT: every middle hop's body (a reached chain has at most kPathHopBodyMaxHops - 1 of them).
inline RouteBodiesXml pathHopBodiesXml( const IngestResult& ing, std::span<const RouteBody> hops, std::string_view rootArg )
{
    return routeBodiesXml( ing, hops, "hops", {}, kPathHopBodyMaxHops, rootArg );
}

// The full dialect's clause for <bodies of="hops">, present-only (no "--": it rides inside the path's XML comment).
static_assert( kHopBodyCapBytes == 4000 && kPathHopBodyMaxHops == 2, "the path and fold clauses spell both bounds: re-word them with the knob" );
inline std::string_view pathHopBodiesLegend( bool on ) noexcept
{
    return on ? "bodies of=hops: the body of the middle hop of the shown chain (never an endpoint), when it has 2 hops; "
                "b t= l= p= n= as expand prints it (no callee rows), whole up to 4000 bytes (a longer one is cut, truncated=1). "
              : "";
}
// present-only beside a hedged <b> (either element): the hop into it was no proven call
inline std::string_view routeBodyHedgeLegend( bool on ) noexcept
{
    return on ? "b via= cands= prov=: the hop into this body is no proven call (by name: one of cands= same-named definitions; a link; a "
                "split arm; a bridge crossing, slot_fns= the functions that field holds; a handler_rule reader), so the body is a hedge, never the proven callee; "
                "a b with none of these is a proven call from the row above it, inside a route that stays proven=0. "
              : "";
}
inline std::string_view pathHopNextLegend( bool on ) noexcept
{
    return on ? "next=: the chain has more than 2 hops, so no middle hop body prints; the first middle hop's expand. " : "";
}

}   // namespace rw
