#pragma once
// pathgaps.h — what a reachable="0" path answer's search MET that the call graph holds no edge for (PATH-GAP honesty).
//
// THE DEFECT. --path=A,B (and the MCP path_between twin) answered `reachable="0" hint="no directed call path"` whenever
// the BFS over resolved call edges did not reach B, although that search had walked past calls the graph keeps NO edge
// for: a call the resolver DECLINED (two or more same-language candidates, none local, nothing chose one), a call left
// UNRESOLVED (an in-repo name whose every definition was filtered out), a function handed off as a VALUE (stored or
// passed, then invoked by whoever holds it) and a call made THROUGH a parameter or slot. Any of those can be the hop
// that joins A to B, so "no path" there was a wholeness claim the search could not make.
//
// THE CONTRACT. pathSearchGaps walks the same directed cone the BFS walked (every symbol reachable from the from=
// definitions over resolved call edges) and counts those four populations inside it. When the count is non-zero the
// answer never says "no directed call path": it says the search was incomplete, gives the counts (searched=, gaps=),
// and names the cone symbols that carry them (<gap> rows, nearest to from= first, capped at kPathGapRows and
// disclosed) with a next= that reads their bodies. When the count is zero the old wording stands, byte for byte.
//
// What it does NOT mean: a <gap> row is not a hop and not evidence that a path exists — it is where the search could
// not see. AMBIGUOUS calls are deliberately NOT a gap: the resolver gives every candidate of a k-way split its own edge
// (graph.h buildGraph's splitPick), and the BFS follows all of them, so ambiguity never hides a path (it can only make
// a FOUND path a guess, which prov="split" / amb= already disclose). Calls to names with no in-repo definition at all
// (Undefined) are not counted either: the graph keeps no per-caller tally of them, and nearly all are library calls.
// Both are floors the legend sentence states.
//
// ONE analysis and ONE emitter for both transports (verbs_navigate.h runPath, mcpverbs.h pathText): the two used to
// carry their own copies of the hint and must not drift on this clause.

#include "graph.h"            // Graph — out-edges (the cone), declinedOut / unresolvedOut (the per-caller gap counts)
#include "model.h"
#include "nextverb.h"         // nextAttrXml — the one pasteable follow-up
#include "sarif.h"            // rootRelativeUri — p= relative to root=, as every other row
#include "serialize.h"        // escapeXml
#include "valuerefindex.h"    // ValueRefIndex::targetsOf — what a value reference may hand off

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t kPathGapRows = 3;   // <gap> rows printed; gap_syms= counts them all, gap_syms_capped="1" says so

// The four gap populations, in the order gaps= lists them. A declarative table (CONTRIBUTING §3): the spelling lives once.
enum class PathGapKind : std::uint8_t { Declined, Unresolved, Value, Through };
inline constexpr std::size_t                                    kPathGapKindCount = 4;
inline constexpr std::array<std::string_view, kPathGapKindCount> kPathGapKindNames = { "declined", "unresolved", "value", "through" };
using PathGapCounts = std::array<std::size_t, kPathGapKindCount>;

struct PathGapSym
{
    NodeId        id    = kNoNode;
    std::uint32_t depth = 0;       // hops from the nearest from= definition
    std::size_t   calls = 0;       // the sum of counts — the row order's second key
    PathGapCounts counts{};
};

struct PathSearchGaps
{
    std::size_t             searched = 0;   // symbols the directed search reached, the from= definitions included
    std::size_t             calls    = 0;   // every gap in the cone: the sum of totals
    PathGapCounts           totals{};
    std::vector<PathGapSym> syms;           // cone symbols carrying >= 1 gap: nearest first, then more gaps, then id

    bool any() const noexcept { return calls > 0; }
};

// The directed cone of `srcs` (the same out-edges shortestPathAny walks, every one of them — no early stop at a target,
// because this runs only when there was none) and the gap populations inside it. Deterministic: BFS in id-ascending
// out-edge order, a reference pass in index order, and a total order on the rows.
inline PathSearchGaps pathSearchGaps( const IngestResult& ing, const Graph& g, std::span<const NodeId> srcs, const ValueRefIndex& values )
{
    constexpr std::uint32_t kUnseen = std::numeric_limits<std::uint32_t>::max();
    const std::size_t       N       = g.wOutDeg.size();
    EXPECTS( g.outOff.size() == N + 1, "the out-edge CSR has one offset per node plus the end" );
    std::vector<std::uint32_t> depth( N, kUnseen );
    std::vector<NodeId>        queue;
    queue.reserve( 64 );
    for( const NodeId s : srcs )
    {
        if( s < N && depth[s] == kUnseen )
        {
            depth[s] = 0;
            queue.push_back( s );
        }
    }
    for( std::size_t head = 0; head < queue.size(); ++head )
    {
        const NodeId u = queue[head];
        for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
        {
            const NodeId v = g.outTargets[k];
            if( v < N && depth[v] == kUnseen )
            {
                depth[v] = depth[u] + 1;
                queue.push_back( v );
            }
        }
    }

    PathSearchGaps out;
    out.searched = queue.size();
    std::vector<PathGapCounts> per( N );   // only cone entries are ever written
    const auto inCone = [ & ]( NodeId n ) noexcept { return n < N && depth[n] != kUnseen; };
    for( const NodeId u : queue )
    {
        per[u][ std::size_t( PathGapKind::Declined ) ]   = u < g.declinedOut.size() ? g.declinedOut[u] : 0;
        per[u][ std::size_t( PathGapKind::Unresolved ) ] = u < g.unresolvedOut.size() ? g.unresolvedOut[u] : 0;
    }
    for( std::uint32_t i = 0; i < ing.references.size(); ++i )
    {
        const Reference& r = ing.references[i];
        if( !inCone( r.fromSymbol ) )
        {
            continue;
        }
        if( r.role == RefRole::Through )
        {
            ++per[ r.fromSymbol ][ std::size_t( PathGapKind::Through ) ];
        }
        else if( r.role == RefRole::Value )
        {
            // A function handed off as a value is a gap only when the search did not reach it by a call anyway.
            const std::vector<NodeId> targets = values.targetsOf( i );
            if( std::ranges::any_of( targets, [ & ]( NodeId t ) { return t < N && !inCone( t ); } ) )
            {
                ++per[ r.fromSymbol ][ std::size_t( PathGapKind::Value ) ];
            }
        }
    }
    for( const NodeId u : queue )
    {
        std::size_t here = 0;
        for( std::size_t k = 0; k < kPathGapKindCount; ++k )
        {
            here          += per[u][k];
            out.totals[k] += per[u][k];
        }
        if( here > 0 )
        {
            out.calls += here;
            out.syms.push_back( PathGapSym{ u, depth[u], here, per[u] } );
        }
    }
    std::ranges::sort( out.syms, []( const PathGapSym& a, const PathGapSym& b )
    {
        if( a.depth != b.depth )
        {
            return a.depth < b.depth;
        }
        if( a.calls != b.calls )
        {
            return a.calls > b.calls;
        }
        return a.id < b.id;
    } );
    ENSURES( out.any() == !out.syms.empty(), "a non-zero total is carried by at least one cone symbol, and only then" );
    return out;
}

// gaps="declined:D,unresolved:U,value:V,through:T" — zero entries left out, table order.
inline std::string pathGapCountsValue( const PathGapCounts& c )
{
    std::string v;
    for( std::size_t k = 0; k < kPathGapKindCount; ++k )
    {
        if( c[k] > 0 )
        {
            v += ( v.empty() ? "" : "," ) + std::string( kPathGapKindNames[k] ) + ":" + std::to_string( c[k] );
        }
    }
    return v;
}

// The legend sentence, carried only by an answer that prints the clause (absent otherwise: byte-identical).
inline constexpr std::string_view kPathGapsLegend =
    "searched=N gaps= gap_syms=: reachable=0 but the search is INCOMPLETE — the N symbols reachable from from= over resolved call edges hold calls the graph "
    "keeps no edge for (gaps= counts them: declined = several candidates and nothing chose one, unresolved = an in-repo name every definition of which was "
    "filtered out, value = a function stored or passed as a value and not otherwise reached, through = a call through a parameter or slot), so this is NOT "
    "proof that no path exists. <gap t= n= p= gaps=> rows are the symbols that carry them, nearest to from= first, gap_syms_capped=1 = more than shown; a row "
    "is where the search could not see, never a hop. Not counted: ambiguous calls (every candidate has an edge the search followed), calls bound by "
    "name alone (via=name: the search follows the candidates such a call lists, never a namesake it does not list) and calls to names defined nowhere "
    "in the tree. next= reads the rows' bodies. ";
inline std::string_view pathGapsLegend( bool on ) noexcept
{
    return on ? kPathGapsLegend : std::string_view();
}

struct PathGapsXml
{
    std::string rootAttrs;   // searched= gaps= gap_syms= [gap_syms_capped=] hint= next=, or the plain no-path hint alone
    std::string rows;        // the <gap> rows, the path element's only children when reachable="0" ("" with the plain hint)
};

// The transport's own spellings of the follow-ups, so one function writes both dialects: `connect` is the undirected verb
// ("--connect=A,B" on the CLI, "the connect verb on A,B" on MCP), `usesImpact` the non-call one ("--uses/--impact" /
// "uses/impact"), `tail` the CLI's several-defs clause (plain text, "" on MCP) — exactly as the no-gap hint had them.
struct PathHintSpelling
{
    std::string      connect;
    std::string_view usesImpact;
    std::string_view tail;
};

// The reachable="0" clause: the gap clause when the search met a gap, else the plain hint, byte-identical to before.
// `rootPrefix` empty ⇒ p= stays as indexed (multi-root), exactly as the hop rows spell it.
inline PathGapsXml pathUnreachedXml( const IngestResult& ing, const PathSearchGaps& gaps, bool singleRoot, std::string_view rootPrefix,
                                     const PathHintSpelling& say )
{
    std::vector<char> esc;
    const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    PathGapsXml out;
    if( !gaps.any() )
    {
        out.rootAttrs = " hint=\"no directed call path — try " + ex( say.connect ) + " (undirected: finds a shared caller), or "
                      + std::string( say.usesImpact ) + " for non-call references" + std::string( say.tail ) + "\"";
        return out;
    }
    const std::size_t shown = std::min( gaps.syms.size(), kPathGapRows );
    std::string next = "--expand=";
    for( std::size_t i = 0; i < shown; ++i )
    {
        const Symbol&          s  = ing.symbols[ gaps.syms[i].id ];
        const std::string_view rp = singleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix ) : std::string_view( ing.files[ s.fileId ] );
        out.rows += "<gap t=\"" + std::string( symTag( s.kind ) ) + "\" n=\"" + ex( s.name ) + "\" p=\"" + ex( rp ) + ":" + std::to_string( s.line )
                  + "\" gaps=\"" + pathGapCountsValue( gaps.syms[i].counts ) + "\"/>";
        // file:name, the selector spelling --expand resolves to this one definition (the same p= the row prints)
        next += ( i == 0 ? "" : "," ) + std::string( rp ) + ":" + s.name;
    }
    out.rootAttrs = " searched=\"" + std::to_string( gaps.searched ) + "\" gaps=\"" + pathGapCountsValue( gaps.totals ) + "\" gap_syms=\""
                  + std::to_string( gaps.syms.size() ) + "\"" + ( gaps.syms.size() > shown ? " gap_syms_capped=\"1\"" : "" )
                  + " hint=\"no path through resolved call edges, but the search is incomplete: it met calls with no edge (gaps=) — read the gap rows, or try "
                  + ex( say.connect ) + " (undirected: finds a shared caller)" + std::string( say.tail ) + "\"" + nextAttrXml( next );
    return out;
}

}   // namespace rw
