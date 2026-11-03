#pragma once
// pathgaps.h — what a reachable="0" path answer's search MET that the call graph holds no edge for (PATH-GAP honesty).
//
// THE DEFECT. --path=A,B (and the MCP path_between twin) answered `reachable="0" hint="no directed call path"` whenever
// the BFS over resolved call edges did not reach B, although that search had walked past calls the graph keeps NO edge
// for: a call the resolver DECLINED (two or more same-language candidates, none local, nothing chose one), a call left
// UNRESOLVED (an in-repo name whose every definition was filtered out), a function handed off as a VALUE (stored or
// passed, then invoked by whoever holds it) and a call made THROUGH a parameter or slot. Any of those can be the hop
// that joins A to B, so "no path" there was a wholeness claim the search could not make.
// A fifth population (train 26b, honesty-small condition 3): a call bound by NAME ALONE (FE-B via="name") has edges only to
// the candidates in reach of the caller, so a same-language, same-kind definition of that name elsewhere (another
// directory) is never searched — the fx/lpy case: run(obj) calls obj.process(), the edge goes to the same-directory
// A.process, and other/B.process, which calls the target, was invisible behind a plain "no directed call path".
//
// THE CONTRACT. pathSearchGaps walks the same directed cone the BFS walked (every symbol reachable from the from=
// definitions over resolved call edges) and counts those five populations inside it. When the count is non-zero the
// answer never says "no directed call path": it says the search was incomplete, gives the counts (searched=, gaps=),
// and names the cone symbols that carry them (<gap> rows, nearest to from= first, capped at kPathGapRows and
// disclosed) with a next= that reads their bodies. When the count is zero the old wording stands, byte for byte.
//
// What it does NOT mean: a <gap> row is not a hop and not evidence that a path exists — it is where the search could
// not see. AMBIGUOUS calls are deliberately NOT a gap: the resolver gives every candidate of a k-way split its own edge
// (graph.h buildGraph's splitPick), and the BFS follows all of them, so ambiguity never hides a path (it can only make
// a FOUND path a guess, which prov="split" / amb= already disclose). Calls to names with no in-repo definition at all
// (Undefined) are not counted either: the graph keeps no per-caller tally of them, and nearly all are library calls.
// Both are floors the legend sentence states. A via="name" call whose every same-language, same-kind definition of the
// name is in the searched cone (its own edge or another cone symbol's) is not a gap either: nothing it could bind to was unsearched.
//
// ONE analysis and ONE emitter for both transports (verbs_navigate.h runPath, mcpverbs.h pathText): the two used to
// carry their own copies of the hint and must not drift on this clause.

#include "graph.h"            // Graph — out-edges (the cone), declinedOut / unresolvedOut (the per-caller gap counts)
#include "model.h"
#include "nextverb.h"         // nextAttrXml — the one pasteable follow-up
#include "sarif.h"            // rootRelativeUri — p= relative to root=, as every other row
#include "serialize.h"        // escapeXml
#include "valuerefindex.h"    // ValueRefIndex::targetsOf — what a value reference may hand off
#include "filter.h"           // pathTierIndexOver — the near-sink rows' tier key within a depth
#include "arch.h"             // wildcardMatch — the ONE `*` match, which a glob endpoint reads
#include "closures.h"         // ClosureIndex — a near-sink row written inside another function's body (why=closure)
#include "hopbody.h"           // BODY-ON-ROUTE: RouteBody, routeBodiesXml — the one edge-kind-aware body printer
#include "backhops.h"          // HOP1: BackwardHops (slot + declined hops of a sink), DeclinedCrossRule, builtinSpelledCall
#include "infra/sortutil.h"   // svLess: the explicit byte order every string_view sort here takes (portablebuildcheck #6)
#include "infra/enumcount.h"  // enumCountIsExact — the kNearSinkKindCount / kBridgeViaCount sizes follow their enums
#include "langfacts.h"         // langFacts(l).transitiveIncludes — the import rule's C-family closure (K5 rule 2b)
#include "infra/namesplit.h"  // afterLast — a bound scope's final segment, the base index key (K5 rule 2c)

#include <algorithm>
#include <cctype>
#include <array>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <limits>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t kPathGapRows = 3;   // <gap> rows printed; gap_syms= counts them all, gap_syms_capped="1" says so

// The five gap populations, in the order gaps= lists them. A declarative table (CONTRIBUTING §3): the spelling lives once.
enum class PathGapKind : std::uint8_t { Declined, Unresolved, Value, Through, Name };
inline constexpr std::size_t                                    kPathGapKindCount = 5;
inline constexpr std::array<std::string_view, kPathGapKindCount> kPathGapKindNames = { "declined", "unresolved", "value", "through", "name" };
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
    std::vector<NodeId>     cone;           // every searched symbol, BFS order (searched == cone.size()): the near-sink rows' met=

    bool any() const noexcept { return calls > 0; }
};

// NAME gaps: per cone symbol, the callee names it reaches only by name (an edge whose Graph::outNameOnly bit is set) for
// which the tree holds a same-language, same-kind DEFINITION outside the cone — a namesake the search never walked. A
// namesake inside the cone was searched (another cone symbol reaches it), and every edge target of a cone symbol is in
// the cone, so "outside the cone" also means the call has no edge to it. Counted once per such name per caller. Only the
// names behind the cone's name-only edges are looked up.
inline void countUnlistedNamesakes( const IngestResult& ing, const Graph& g, std::span<const NodeId> cone, std::vector<PathGapCounts>& per )
{
    EXPECTS( g.outNameOnly.size() == g.outTargets.size(), "buildGraph allocates the hedge bits one per flattened edge" );
    struct Key
    {
        Lang             lang;
        SymKind          kind;
        std::string_view name;
    };
    // explicit byte order on the name (never string_view's operator< / <=>: libstdc++'s compare wraps n1 - n2 under
    // -fsanitize=integer, portablebuildcheck #6/#6b); == needs no order
    const auto keyLess = []( const Key& a, const Key& b )
    {
        if( a.lang != b.lang )
        {
            return a.lang < b.lang;
        }
        if( a.kind != b.kind )
        {
            return a.kind < b.kind;
        }
        return sortutil::svLess( a.name, b.name );
    };
    const auto keyEq = []( const Key& a, const Key& b ) { return a.lang == b.lang && a.kind == b.kind && a.name == b.name; };
    const auto keyOf    = [ & ]( NodeId t ) { const Symbol& s = ing.symbols[t]; return Key{ s.lang, s.kind, s.name }; };
    const auto hasHedge = [ & ]( NodeId u ) { return std::any_of( g.outNameOnly.begin() + g.outOff[u], g.outNameOnly.begin() + g.outOff[u + 1], []( std::uint8_t b ) { return edgeKindByte( b ) == kEdgeName; } ); };
    const auto isSym    = [ & ]( std::uint32_t k ) { return g.outTargets[k] < ing.symbols.size(); };
    std::vector<std::string_view> names;
    for( const NodeId u : cone )
    {
        for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
        {
            if( edgeKindByte( g.outNameOnly[k] ) == kEdgeName && isSym( k ) )
            {
                names.push_back( ing.symbols[ g.outTargets[k] ].name );
            }
        }
    }
    if( names.empty() )
    {
        return;
    }
    std::ranges::sort( names, sortutil::svLess );
    names.erase( std::ranges::unique( names ).begin(), names.end() );
    std::vector<char> searched( ing.symbols.size(), 0 );   // the cone, by symbol id
    for( const NodeId u : cone )
    {
        if( u < searched.size() )
        {
            searched[u] = 1;
        }
    }
    std::vector<Key> unsearched;   // the tree's definitions of exactly those names that the search never reached
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        const Symbol& s = ing.symbols[i];
        if( searched[i] == 0 && isDefinitionNotDeclaration( s ) && std::ranges::binary_search( names, std::string_view( s.name ), sortutil::svLess ) )
        {
            unsearched.push_back( Key{ s.lang, s.kind, s.name } );
        }
    }
    if( unsearched.empty() )
    {
        return;
    }
    std::ranges::sort( unsearched, keyLess );
    for( const NodeId u : cone )
    {
        if( !hasHedge( u ) )
        {
            continue;
        }
        std::vector<Key> hedged;   // the targets u reached by name alone
        for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
        {
            if( isSym( k ) && edgeKindByte( g.outNameOnly[k] ) == kEdgeName )
            {
                hedged.push_back( keyOf( g.outTargets[k] ) );
            }
        }
        std::ranges::sort( hedged, keyLess );
        hedged.erase( std::ranges::unique( hedged, keyEq ).begin(), hedged.end() );
        for( const Key& key : hedged )
        {
            per[u][ std::size_t( PathGapKind::Name ) ] += std::ranges::binary_search( unsearched, key, keyLess ) ? 1u : 0u;
        }
    }
}

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
    if( !g.outNameOnly.empty() )   // FE-B's hedge bits (absent on a graph built without them: no name population)
    {
        countUnlistedNamesakes( ing, g, queue, per );
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
    out.cone = std::move( queue );
    ENSURES( out.any() == !out.syms.empty(), "a non-zero total is carried by at least one cone symbol, and only then" );
    ENSURES( out.cone.size() == out.searched, "the cone is exactly the searched symbols" );
    return out;
}

// "kind:N,kind:N" over a per-kind count table — zero entries left out, table order. One spelling for gaps= and why=.
template<std::size_t K>
inline std::string kindCountsValue( const std::array<std::size_t, K>& c, const std::array<std::string_view, K>& names )
{
    std::string v;
    for( std::size_t k = 0; k < K; ++k )
    {
        if( c[k] > 0 )
        {
            v += ( v.empty() ? "" : "," ) + std::string( names[k] ) + ":" + std::to_string( c[k] );
        }
    }
    return v;
}

// gaps="declined:D,unresolved:U,value:V,through:T,name:M" — zero entries left out, table order.
inline std::string pathGapCountsValue( const PathGapCounts& c )
{
    return kindCountsValue( c, kPathGapKindNames );
}

// The legend sentence, carried only by an answer that prints the clause (absent otherwise: byte-identical).
inline constexpr std::string_view kPathGapsLegend =
    "searched=N gaps= gap_syms=: reachable=0 but the search is INCOMPLETE — the N symbols reachable from from= over resolved call edges hold calls the graph "
    "keeps no edge for (gaps= counts them: declined = several candidates and nothing chose one, unresolved = an in-repo name every definition of which was "
    "filtered out, value = a function stored or passed as a value and not otherwise reached, through = a call through a parameter or slot, name = a call "
    "bound by name alone (via=name) whose name the tree also defines, same language and kind, where the call has no edge: that namesake was never "
    "searched), so this is NOT proof that no path exists. <gap t= n= p= gaps=> rows are the symbols that carry them, nearest to from= first, "
    "gap_syms_capped=1 = more than shown; a row is where the search could not see, never a hop. Not counted: ambiguous calls (every candidate has an "
    "edge the search followed) and calls to names defined nowhere in the tree. next= reads the rows' bodies. ";
// HOP1 (#6): when to= itself has backward hops (backhops.h: a slot caller, or a declined call whose candidates hold it), the
// root next= is the callers verb on to= instead — the call that crosses the gap, where the gap rows' bodies only show the text.
inline constexpr std::string_view kPathGapsNextBodies   = "next= reads the rows' bodies. ";
inline constexpr std::string_view kPathGapsNextCallers  =
    "next= lists to='s callers: to= has a slot caller or a declined call naming it (at most 16 callers or candidates), none a resolved edge. ";
static_assert( kPathGapsLegend.ends_with( kPathGapsNextBodies ), "the callers form replaces exactly the bodies sentence" );
inline std::string pathGapsLegend( bool on, bool callersNext = false )
{
    if( !on )
    {
        return {};
    }
    if( !callersNext )
    {
        return std::string( kPathGapsLegend );
    }
    return std::string( kPathGapsLegend.substr( 0, kPathGapsLegend.size() - kPathGapsNextBodies.size() ) ) + std::string( kPathGapsNextCallers );
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
// `sinkCallers` (HOP1 #6): to='s "file:name" selector when to= has backward hops (pathGapsLegend's callers form); the root
// next= is then `--callers=` on it, else the gap rows' bodies as before.
inline PathGapsXml pathUnreachedXml( const IngestResult& ing, const PathSearchGaps& gaps, bool singleRoot, std::string_view rootPrefix,
                                     const PathHintSpelling& say, std::string_view sinkCallers = {} )
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
    std::string nextSelectors;   // the comma-joined file:name list; nextFlag quotes it when a shell would split or expand it
    for( std::size_t i = 0; i < shown; ++i )
    {
        const Symbol&          s  = ing.symbols[ gaps.syms[i].id ];
        const std::string_view rp = singleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix ) : std::string_view( ing.files[ s.fileId ] );
        out.rows += "<gap t=\"" + std::string( symTag( s.kind ) ) + "\" n=\"" + ex( s.name ) + "\" p=\"" + ex( rp ) + ":" + std::to_string( s.line )
                  + "\" gaps=\"" + pathGapCountsValue( gaps.syms[i].counts ) + "\"/>";
        // file:name, the selector spelling --expand resolves to this one definition (the same p= the row prints)
        nextSelectors += ( i == 0 ? "" : "," ) + std::string( rp ) + ":" + s.name;
    }
    out.rootAttrs = " searched=\"" + std::to_string( gaps.searched ) + "\" gaps=\"" + pathGapCountsValue( gaps.totals ) + "\" gap_syms=\""
                  + std::to_string( gaps.syms.size() ) + "\"" + ( gaps.syms.size() > shown ? " gap_syms_capped=\"1\"" : "" )
                  + " hint=\"no path through resolved call edges, but the search is incomplete: it met calls or hand-offs it could not follow in full (gaps=) — read the gap rows, or try "
                  + ex( say.connect ) + " (undirected: finds a shared caller)" + std::string( say.tail ) + "\""
                  + nextAttrXml( sinkCallers.empty() ? nextFlag( "--expand=", nextSelectors ) : nextFlag( "--callers=", sinkCallers ) );
    return out;
}

// HOP1 (#6): the selector the root next= names when to= has a backward hop the provider follows (anyFollowedBackHop): one
// definition's "file:name" (the p= its rows print), the name as written when it stands for several; "" when no to= definition
// has such a hop (the next= stays the gap bodies).
inline std::string pathSinkCallersSelector( const IngestResult& ing, const BackwardHops& hops, std::span<const NodeId> dstDefs, std::string_view dstName,
                                            bool singleRoot, std::string_view rootPrefix )
{
    if( dstDefs.empty() || !anyFollowedBackHop( hops, dstDefs ) )
    {
        return {};
    }
    if( dstDefs.size() > 1 )
    {
        return std::string( dstName );
    }
    const Symbol& s = ing.symbols[ dstDefs.front() ];
    return std::string( singleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix ) : std::string_view( ing.files[ s.fileId ] ) ) + ":" + s.name;
}

// ── SINK-SIDE FRONTIER (lane ix2-slice, commit 1): the reachable="0" answer's <near_sink> block ──────────────────────────
// THE GAP. The <gap> rows above are FORWARD-only: where the search from from= went blind. A reader closing the gap by hand
// also walks BACK from to=: who calls it, who calls those, and how the last of them is entered when nothing proven calls it.
// htop's `--path=ScreenManager_run,LinuxMachine_scanCPUTime` met a declined call in checkRecalculation, but nothing named
// the platform build Machine_scan (linux/LinuxMachine.c), the sink's only caller — the hop the declined call could have meant.
// (Mechanism learned from a peer's failure diagnosis, which reports the backward frontier beside the forward one; no code copied.)
//
// THE CONTRACT. pathNearSink walks the sink's PROVEN callers back over resolved call edges to depth kNearSinkDepth, and
// classifies, for every symbol it meets (to= itself included), how that symbol may ALSO be entered without an edge:
//   declined  a declined call (several candidates, none chosen) whose candidate list holds it (the callers verb's <dc> rows);
//   value     it is stored or passed as a value, and no call through a parameter or slot is matched to that hand-off;
//   through   it is passed as a value that a call through a parameter or slot is matched to (the invoker is named);
//   name      a call bound by name alone (via=name) went to a same-language, same-kind namesake and has no edge to it;
//   closure   it is a named function written inside another function's body (src/closures.h): that one runs it or hands it
//             on (koa's `const handleResponse = () => respond( ctx )` inside Application.handleRequest);
//   external  none of those and no proven caller either: no indexed way in was found (an entry point, a caller outside
//             the tree, a framework hook, a hand-off the index does not record, such as koa's local `.then( handleResponse )`, or dead).
// Each row names ONE such site (in= its enclosing definition, site= its file:line): a site whose enclosing definition the
// forward search reached comes first (met="1": the search met that hand-off and could not follow it), then by kind, then by
// path and line. The rows: every proven caller at depth 1..kNearSinkDepth, plus a to= definition that carries a reason; the
// ones carrying a reason first (met before not), then depth, then id; kNearSinkRows shown, rows= counts them all.
//
// What it does NOT mean: a row is not a hop of a path and not evidence that one exists; why= says how the row MAY be entered
// that the graph holds no edge for (the classification is a floor: unresolved calls carry no per-name record, and calls to
// names defined nowhere are not counted). met="1" is the closest thing to a bridge this answer offers, and it is a hedge.
// A reachable="1" answer never carries the block (byte-identical); the hint and the forward clause above are unchanged.
inline constexpr std::uint32_t kNearSinkDepth = 2;   // proven caller hops back from to= (1 = a direct caller)
inline constexpr std::size_t   kNearSinkRows  = 4;   // <ns> rows printed; rows= counts them all, rows_capped="1" says so

// The five un-edged reach kinds, in the order why= lists them (external is their absence, with no proven caller). Closure
// (commit 2, src/closures.h): the row is a named function written inside in='s body — its site is its own definition.
enum class NearSinkKind : std::uint8_t { Declined, Value, Through, Name, Closure };
inline constexpr std::size_t                                     kNearSinkKindCount = 5;
static_assert( enumCountIsExact<NearSinkKind, kNearSinkKindCount>(), "kNearSinkKindCount must equal the NearSinkKind count — raise it with the append" );
inline constexpr std::array<std::string_view, kNearSinkKindCount> kNearSinkKindNames = { "declined", "value", "through", "name", "closure" };
using NearSinkCounts = std::array<std::size_t, kNearSinkKindCount>;

struct NearSinkSite
{
    bool          valid  = false;      // a site was chosen
    std::uint32_t fileId = 0;          // the site's file and line: a reference's, or (closure) the row's own definition
    std::uint32_t line   = 0;
    std::uint32_t order  = 0;          // the last tie-break: the reference index, or (closure) the row id
    NodeId        in     = kNoNode;    // its enclosing definition (kNoNode: file scope)
    NearSinkKind  kind   = NearSinkKind::Declined;
    bool          met    = false;      // the forward search reached `in`
    std::uint32_t cands  = 0;          // a NAME-KEY lookup's width (the definitions its template can name): 0 = not a name-key site
};

struct NearSinkRow
{
    NodeId         id      = kNoNode;
    std::uint32_t  depth   = 0;   // proven call hops back from the nearest to= definition (0 = to= itself)
    std::size_t    callers = 0;   // its proven callers (in-edges), any depth
    NearSinkCounts counts{};
    NearSinkSite   site;          // the one site the row names (none when counts are all 0)
    std::size_t    nameWithheld = 0;   // by-name hits the K5 rules withheld (rule 2b/2c refused, or no non-builtin call): never "external"

    bool reasoned() const noexcept { return site.valid || callers == 0; }   // a why= (external included)
};

struct PathNearSink
{
    std::size_t              callers = 0;   // the sink's proven callers within kNearSinkDepth hops (to= excluded)
    std::vector<NearSinkRow> rows;          // served order, uncut (the emitter shows kNearSinkRows)
};

// builtinSpelledCall (a member call spelled like a builtin type's method) lives in backhops.h beside DeclinedCrossRule, the
// declined-record form both the bridge's crossings and the near-sink ways in read (HOP1 #11).

// ── BY-NAME HEDGE RULES (lane ix2-slice, card K5) ────────────────────────────────────────────────────────────────────
// A by-name hedge — near_sink why=name, a bridge's namesake crossing — reads: caller C's call of NAME was bound by name alone
// to one definition, so another same-language, same-kind definition of NAME (the NAMESAKE) may be the one it runs. The
// acceptance hand-check rejected this class most: a call spelled like a builtin type's method (`prerequisites.clear`,
// `self._invalid_css.update( … )`) and a namesake the search never comes near (a docs example's `compose`, a test file's
// `handler`). Both rules below hold for both hedges:
//   (1) SITE: the hedge's site is C's first call of NAME that is not builtinSpelledCall (the declined pass's own filter);
//       a caller whose every call of NAME is builtin-spelled offers no by-name hedge.
//   (2) OWNER IN REACH: the namesake's OWNER — the class that owns it in its own file (Symbol::scope, the extractor's) —
//       owns some definition in the forward reach set: near_sink takes PathSearchGaps::cone (every symbol the forward
//       search reached), the bridge every symbol its layered search has reached so far (layers 0..k before crossing k+1).
//       A namesake nothing reached shares an owner with is no way in. Lane ind4b: a FILE-OWNED namesake needs the caller's
//       file to be or import its file instead (2b), and a class-owned one is also admitted by override dispatch (2c) —
//       NamesakeRule::admits below.

// Each caller's call references in reference order, for the by-name site (rule 1).
class ByNameCallSites
{
public:
    // `callerMask` empty ⇒ every caller; else only the symbols whose mask byte is set
    ByNameCallSites( const IngestResult& ing, std::span<const char> callerMask )
        : ing_( ing )
    {
        const std::ptrdiff_t S = std::ssize( ing.symbols );
        EXPECTS( callerMask.empty() || std::ssize( callerMask ) == S, "a caller mask has one byte per symbol" );
        for( std::ptrdiff_t i = 0; i < std::ssize( ing.references ); ++i )
        {
            const Reference& r = ing.references[ std::size_t( i ) ];
            if( r.role == RefRole::Call && std::ptrdiff_t( r.fromSymbol ) < S && ( callerMask.empty() || callerMask[ r.fromSymbol ] != 0 ) )
            {
                calls_.emplace_back( r.fromSymbol, std::uint32_t( i ) );
            }
        }
        std::ranges::sort( calls_ );
    }

    // The first call reference `caller` makes of `name` that is not spelled like a builtin type's method; kNoSite if none.
    static constexpr std::uint32_t kNoSite = std::numeric_limits<std::uint32_t>::max();
    std::uint32_t siteOf( NodeId caller, std::string_view name ) const
    {
        for( auto it = std::ranges::lower_bound( calls_, std::pair<NodeId, std::uint32_t>( caller, 0u ) ); it != calls_.end() && it->first == caller; ++it )
        {
            const Reference& r = ing_.references[ it->second ];
            if( r.calleeName == name && !builtinSpelledCall( r ) )
            {
                return it->second;
            }
        }
        return kNoSite;
    }

private:
    const IngestResult&                           ing_;
    std::vector<std::pair<NodeId, std::uint32_t>> calls_;   // (caller, reference index), sorted
};

// The owners (rule 2) of a reach set: add() each reached symbol, then ask reaches() of a namesake. Membership only (no
// iteration), so the hash order never reaches an answer; the key is "<fileId>#<scope>" (scope "" = the file itself).
class NamesakeOwnerReach
{
public:
    void add( const Symbol& s )
    {
        owners_.try_emplace( keyOf( s ), char( 1 ) );
    }
    bool reaches( const Symbol& namesake ) const
    {
        return owners_.contains( keyOf( namesake ) );
    }

private:
    static std::string keyOf( const Symbol& s )
    {
        return std::to_string( s.fileId ) + "#" + s.scope;
    }
    HashMap<std::string, char> owners_;
};

// Lane ind4b sharpened rule 2 per namesake shape (one place for both hedges — near_sink and the bridge's crossing):
//   (2b) a FILE-OWNED namesake (scope "": a free function, or a method of a language whose extractor records no class
//        scope — JS/TS) is admitted only when the caller's file IS the namesake's file or imports it: a direct edge of the
//        index's precise import adjacency (Graph::importAdj), or for C/C++/ObjC any transitive #include. Owner reach no
//        longer admits one: a file the search touched is not evidence the caller can name its function (the koa accessor
//        and nunjucks `this.init` sites the IND4 Stage-0 hand-check rejected).
//   (2c) a CLASS-OWNED namesake is admitted when its class's owner is in reach (rule 2, unchanged) OR — override dispatch
//        — its class derives from the class owning the definition the call was bound to through PROVEN base edges only
//        (Graph::implementorBound == BaseBound::Proven, any depth): at every hop the deriving class's written base name is
//        bound, in that class's own file, to the next class — a same-file declaration, the file its import of THAT name
//        resolves to (Python FE-A memberImportFile, incl. a package re-export and the src/ layout suffix match; a JS/TS
//        named import; a C-family include; the Java/Kotlin/Go package) — buildGraph's provenBasesOf, the one base resolver.
//        A namesake whose base clause names another same-named class (in-tree elsewhere, or external: `ext.Base`,
//        `from ext import Base`) has no proven edge to the bound class however its file's imports reach the bound file, and
//        an edge no evidence binds (ByName) is withheld too: exact or no row. The residual is the binding's own: a
//        qualified base the lookup does not read (a dotted `a.b.X`) stays withheld (withheld="name"), and so
//        does a Python base name with any binding but its import in the class statement's scope chain (pythonBaseNameProven:
//        `Base = Other` at module, class-body or function scope, a parameter, a match capture, a `type` statement, a second import,
//        a star import that could bind it; a qualifier also imported as a module outside the chain, where the file-wide tables decide).
//        A re-export chain is followed only through files whose binding of the name is ONE plain import, at every hop
//        (pythonFileBindsOnlyByImport): a hop that renames, rebinds, star-imports after it, writes the module namespace dynamically
//        (`globals()`, `setattr`, `__getattr__`) or has no record of the name ends the chain, so the row is withheld.
// Rule 2c's derivation (below): the classes that derive from a bound definition's class through PROVEN base edges only
// (Graph::implementorBound == BaseBound::Proven), memoized per bound owner. The classes with a derived class are indexed by
// "<file>#<name>" on first ask (one pass over the implementors map); the walk visits each class once.
class ProvenSubclasses
{
public:
    explicit ProvenSubclasses( const IngestResult& ing, const Graph& g )
        : ing_( ing ), g_( g ) {}
    // does a class owning `ns`'s scope derive, over proven edges, from the class owning `bs`'s scope?
    bool derives( const Symbol& ns, const Symbol& bs ) const
    {
        return std::ranges::any_of( below( bs ), [ & ]( NodeId d ) { return ownsScope( ing_.symbols[d], ns.fileId, ns.scope ); } );
    }

private:
    // is `cls` the class whose members carry `scope` in file `fileId`? scope ends with its name, and is either the class's
    // own recorded scope (Python records a class under its own qualified name) or its scope, a separator, its name
    static bool ownsScope( const Symbol& cls, std::uint32_t fileId, std::string_view scope ) noexcept
    {
        if( cls.fileId != fileId || !scope.ends_with( cls.name ) )
        {
            return false;
        }
        if( cls.scope == scope )
        {
            return true;
        }
        const std::string_view outer = scope.substr( 0, scope.size() - cls.name.size() );
        if( outer.empty() )
        {
            return cls.scope.empty();
        }
        return ( outer.ends_with( "::" ) && outer.substr( 0, outer.size() - 2 ) == cls.scope )
               || ( outer.ends_with( "." ) && outer.substr( 0, outer.size() - 1 ) == cls.scope );
    }
    // the classes owning `bs`'s scope: those of its leaf name in its file that have a derived class
    std::vector<NodeId> ownersOf( const Symbol& bs ) const
    {
        if( !indexed_ )
        {
            indexed_ = true;
            for( NodeId b = 0; b < g_.implementors.size(); ++b )
            {
                if( !g_.implementors[b].empty() )
                {
                    basesByName_[ fileNameKey( key_, ing_.symbols[b].fileId, ing_.symbols[b].name ) ].push_back( b );
                }
            }
        }
        std::vector<NodeId>    out;
        const std::string_view leaf = namesplit::afterLast( namesplit::afterLast( bs.scope, "::" ), "." );
        if( const auto it = basesByName_.find( fileNameKey( key_, bs.fileId, leaf ) ); it != basesByName_.end() )
        {
            std::ranges::copy_if( it->second, std::back_inserter( out ), [ & ]( NodeId b ) { return ownsScope( ing_.symbols[b], bs.fileId, bs.scope ); } );
        }
        return out;
    }
    const std::vector<NodeId>& below( const Symbol& bs ) const
    {
        if( const auto it = below_.find( fileNameKey( key_, bs.fileId, bs.scope ) ); it != below_.end() )
        {
            return it->second;
        }
        std::vector<NodeId>   out;
        std::vector<NodeId>   stack = ownersOf( bs );
        HashMap<NodeId, char> seen;
        while( !stack.empty() )
        {
            const NodeId b = stack.back();
            stack.pop_back();
            const std::vector<NodeId>&       kids  = g_.implementors[b];
            const std::vector<std::uint8_t>& bound = g_.implementorBound[b];
            for( std::size_t k = 0; k < kids.size(); ++k )
            {
                if( bound[k] == std::uint8_t( BaseBound::Proven ) && seen.try_emplace( kids[k], char( 1 ) ).second )
                {
                    out.push_back( kids[k] );
                    stack.push_back( kids[k] );
                }
            }
        }
        return below_.try_emplace( fileNameKey( key_, bs.fileId, bs.scope ), std::move( out ) ).first->second;
    }
    const IngestResult&                               ing_;
    const Graph&                                      g_;
    mutable std::string                               key_;
    mutable bool                                      indexed_ = false;
    mutable HashMap<std::string, std::vector<NodeId>> basesByName_;   // "<file>#<class name>" → the classes with a derived class
    mutable HashMap<std::string, std::vector<NodeId>> below_;         // "<file>#<bound scope>" → the proven-derived classes
};

class NamesakeRule
{
public:
    NamesakeRule( const IngestResult& ing, const Graph& g )
        : ing_( ing ), g_( g ), derived_( ing, g ) {}
    void add( const Symbol& s )
    {
        owners_.add( s );
    }
    // May caller c's call, bound by name alone to `bound`, run `namesake` instead? (rules 2b / 2c above)
    bool admits( NodeId caller, NodeId bound, NodeId namesake ) const
    {
        const Symbol& ns = ing_.symbols[namesake];
        if( ns.scope.empty() )
        {
            const std::uint32_t from = ing_.symbols[caller].fileId;
            return from == ns.fileId || fileSees( from, ns.fileId, langFacts( ns.lang ).transitiveIncludes );
        }
        const Symbol& bs = ing_.symbols[bound];
        return owners_.reaches( ns ) || ( !bs.scope.empty() && derived_.derives( ns, bs ) );
    }

private:
    // does file `from` import file `to` — directly (the precise adjacency only), or (transitive: a C-family #include
    // closure) over any number of import edges? Memoized per `from`.
    bool fileSees( std::uint32_t from, std::uint32_t to, bool transitive ) const
    {
        const rw::FileAdjacency& adj = g_.importAdj;
        if( from >= adj.size() )
        {
            return false;
        }
        if( !transitive )
        {
            const std::span<const std::uint32_t> row = adj[from];
            return std::ranges::find( row, to ) != row.end();
        }
        if( reach_.empty() )
        {
            reach_.resize( adj.size() );
            reachDone_.resize( adj.size(), 0 );
        }
        if( reachDone_[from] == 0 )
        {
            reachDone_[from] = 1;
            std::vector<char>          seen( adj.size(), 0 );
            std::vector<std::uint32_t> stack{ from };
            seen[from] = 1;
            while( !stack.empty() )
            {
                const std::uint32_t v = stack.back();
                stack.pop_back();
                for( const std::uint32_t w : adj[v] )
                {
                    if( w < adj.size() && seen[w] == 0 )
                    {
                        seen[w] = 1;
                        stack.push_back( w );
                        reach_[from].push_back( w );
                    }
                }
            }
            std::ranges::sort( reach_[from] );
        }
        return std::ranges::binary_search( reach_[from], to );
    }
    const IngestResult&                                  ing_;
    const Graph&                                         g_;
    NamesakeOwnerReach                                   owners_;
    mutable std::vector<std::vector<std::uint32_t>>      reach_;          // file → the files its #includes reach (sorted), on first ask
    mutable std::vector<char>                            reachDone_;
    ProvenSubclasses                                     derived_;        // rule 2c
};

// Is site a preferred over site b for one row? met first, then kind (table order), then path, line, order.
inline bool nearSinkSiteBetter( const IngestResult& ing, const NearSinkSite& a, const NearSinkSite& b )
{
    if( !b.valid || !a.valid )
    {
        return a.valid && !b.valid;
    }
    if( a.met != b.met )
    {
        return a.met;
    }
    if( a.kind != b.kind )
    {
        return a.kind < b.kind;
    }
    if( a.fileId != b.fileId )
    {
        return ing.files[ a.fileId ] < ing.files[ b.fileId ];
    }
    return a.line != b.line ? a.line < b.line : a.order < b.order;
}

// The backward frontier of `dstDefs` (see the block comment above). `forwardCone` = PathSearchGaps::cone, the symbols the
// forward search reached. Deterministic: BFS in in-edge order from the to= definitions in the order given, one pass over the
// declined records, the value index in reference order, one pass over the name-only edges, and a total order on the rows.
inline PathNearSink pathNearSink( const IngestResult& ing, const Graph& g, std::span<const NodeId> dstDefs, std::span<const NodeId> forwardCone,
                                  const ValueRefIndex& values, const NameKeyHops& names )
{
    constexpr std::uint32_t kNone = std::numeric_limits<std::uint32_t>::max();
    const std::size_t       S     = ing.symbols.size();
    PathNearSink            out;
    std::vector<std::uint32_t> rowOf( S, kNone );   // symbol → its index in out.rows
    std::vector<char>          met( S, 0 );
    for( const NodeId u : forwardCone )
    {
        if( u < S )
        {
            met[u] = 1;
        }
    }
    const auto* ro = g.inEdges.rowOffsets();
    const auto* ci = g.inEdges.colIndices();
    EXPECTS( g.inEdges.rows() >= S, "the in-edge CSR has a row per symbol" );
    for( const NodeId t : dstDefs )
    {
        if( t < S && rowOf[t] == kNone )
        {
            rowOf[t] = std::uint32_t( out.rows.size() );
            out.rows.push_back( NearSinkRow{ t, 0, 0, {}, {} } );
        }
    }
    for( std::size_t head = 0; head < out.rows.size(); ++head )   // BFS: out.rows grows behind `head`, in depth order
    {
        const NodeId        u = out.rows[head].id;
        const std::uint32_t d = out.rows[head].depth;
        for( std::uint32_t k = ro[u]; k < ro[u + 1]; ++k )
        {
            const NodeId c = ci[k];
            if( c >= S || c == u )
            {
                continue;   // a non-symbol node (a doc file) is no caller
            }
            ++out.rows[head].callers;
            if( d < kNearSinkDepth && rowOf[c] == kNone )
            {
                rowOf[c] = std::uint32_t( out.rows.size() );
                out.rows.push_back( NearSinkRow{ c, d + 1, 0, {}, {} } );
            }
        }
    }
    out.callers = out.rows.size() - std::size_t( std::ranges::count_if( out.rows, []( const NearSinkRow& r ) { return r.depth == 0; } ) );
    const auto offerAt = [ & ]( std::uint32_t row, NearSinkKind kind, std::uint32_t fileId, std::uint32_t line, std::uint32_t order, NodeId in, std::uint32_t cands = 0 )
    {
        NearSinkRow& r = out.rows[row];
        ++r.counts[ std::size_t( kind ) ];
        const NearSinkSite cand{ true, fileId, line, order, in, kind, in < S && met[in] != 0, cands };
        if( nearSinkSiteBetter( ing, cand, r.site ) )
        {
            r.site = cand;
        }
    };
    const auto offer = [ & ]( std::uint32_t row, NearSinkKind kind, std::uint32_t ref, NodeId in )
    {
        offerAt( row, kind, ing.references[ref].fileId, ing.references[ref].line, ref, in );
    };

    // CLOSURE: a row written inside another function's body is entered from there (or wherever that one hands it on).
    {
        const ClosureIndex closures( ing );
        for( std::uint32_t row = 0; closures.any() && row < out.rows.size(); ++row )
        {
            const NodeId u = out.rows[row].id;
            if( const NodeId parent = closures.parentOf( u ); parent != kNoNode )
            {
                offerAt( row, NearSinkKind::Closure, ing.symbols[u].fileId, ing.symbols[u].line, u, parent );
            }
        }
    }

    // DECLINED: one pass over the stored candidate lists (which rows each list holds), then one over the records.
    std::vector<std::vector<std::uint32_t>> rowsOfList( g.declinedListCallCount.size() );
    for( std::size_t list = 0; list < rowsOfList.size(); ++list )
    {
        for( std::uint32_t slot = g.declinedListOff[list]; slot < g.declinedListOff[list + 1]; ++slot )
        {
            if( const NodeId cand = g.declinedListCand[slot]; cand < S && rowOf[cand] != kNone )
            {
                rowsOfList[list].push_back( rowOf[cand] );
            }
        }
    }
    const DeclinedCrossRule declinedRule( ing, g );   // HOP1 #11: the bridge's own builtin rule, receiver-typed sites kept
    for( std::uint32_t site = 0; site < g.declinedSiteList.size(); ++site )
    {
        const std::uint32_t list = g.declinedSiteList[site];
        if( list == kNoDeclinedList || list >= rowsOfList.size() )
        {
            continue;
        }
        for( const std::uint32_t row : rowsOfList[list] )
        {
            // a declined self-call is no way in, nor a call that reads as the builtin type's method it spells
            if( g.declinedSiteCaller[site] != out.rows[row].id && !declinedRule.builtinSpelled( site ) )
            {
                offer( row, NearSinkKind::Declined, g.declinedSiteRef[site], g.declinedSiteCaller[site] );
            }
        }
    }

    // NAME-KEY (string-keyed, the same vocabulary as a declined call: why=declined): a function that looks a method up by a name built
    // from a template (backhops.h NameKeyHops) which fits the row names it with no edge, whatever the width of its candidate set (the
    // bridge crosses at most kBridgeFanOut: a wider lookup is a way in the answer would otherwise call external). cands= says the width.
    for( std::uint32_t row = 0; row < out.rows.size(); ++row )
    {
        for( const std::uint32_t site : names.sitesNaming( out.rows[row].id ) )
        {
            const Reference& sr = ing.references[site];
            offerAt( row, NearSinkKind::Declined, sr.fileId, sr.line, site, sr.fromSymbol, std::uint32_t( names.targets( site ).size() ) );
        }
    }

    // VALUE / THROUGH: each value reference to a row; one matched to a call through a parameter or slot is a THROUGH site
    // there (the invoker), else a VALUE site where it is handed off. A reference made inside the row itself is no way in.
    for( std::uint32_t row = 0; row < out.rows.size(); ++row )
    {
        const NodeId u = out.rows[row].id;
        for( const std::uint32_t v : values.valueRefsTo( std::span<const NodeId>( &u, 1 ) ) )
        {
            const Reference& vr = ing.references[v];
            // a reference inside the row itself is no way in; nor is a WRAPPER decorator (`@property`, `@classmethod`,
            // `@overload` — valuerefindex.h vrIsWrapperDecorator, the dead-set's own rule): it hands the function back under its
            // own name, which is then read or called by name, not handed off
            if( vr.fromSymbol == u || vrIsWrapperDecorator( vr.fieldName ) )
            {
                continue;
            }
            const std::vector<std::uint32_t> throughs = values.throughsFor( v );
            if( throughs.empty() )
            {
                offer( row, NearSinkKind::Value, v, vr.fromSymbol );
            }
            for( const std::uint32_t t : throughs )
            {
                offer( row, NearSinkKind::Through, t, ing.references[t].fromSymbol );
            }
        }
    }

    // NAME: a caller whose call reached a same-language, same-kind namesake of a row by name alone, with no edge to the row.
    // Counted once per (row, caller); the site is that caller's call of the name, found in one reference pass below.
    if( !g.outNameOnly.empty() )
    {
        EXPECTS( g.outNameOnly.size() == g.outTargets.size(), "buildGraph allocates the hedge bits one per flattened edge" );
        NamesakeRule ownerReach( ing, g );   // K5 rule 2 (2b/2c): the owners the forward search reached
        for( const NodeId v : forwardCone )
        {
            if( v < S )
            {
                ownerReach.add( ing.symbols[v] );
            }
        }
        struct Key
        {
            Lang             lang;
            SymKind          kind;
            std::string_view name;
            std::uint32_t    row;
        };
        const auto keyLess = []( const Key& a, const Key& b )
        {
            if( a.lang != b.lang )
            {
                return a.lang < b.lang;
            }
            if( a.kind != b.kind )
            {
                return a.kind < b.kind;
            }
            return sortutil::svLess( a.name, b.name );
        };
        std::vector<Key> keys;
        keys.reserve( out.rows.size() );
        for( std::uint32_t row = 0; row < out.rows.size(); ++row )
        {
            const Symbol& s = ing.symbols[ out.rows[row].id ];
            keys.push_back( Key{ s.lang, s.kind, s.name, row } );
        }
        std::ranges::stable_sort( keys, keyLess );
        std::vector<std::pair<NodeId, std::uint32_t>> nameHits;   // (caller, row)
        std::vector<std::pair<NodeId, std::uint32_t>> withheld;   // (caller, row): a by-name hit the K5 rules drop (review M1)
        const std::size_t N = g.outOff.empty() ? 0 : g.outOff.size() - 1;
        for( NodeId c = 0; c < N && c < S; ++c )
        {
            for( std::uint32_t k = g.outOff[c]; k < g.outOff[c + 1]; ++k )
            {
                const NodeId w = g.outTargets[k];
                if( edgeKindByte( g.outNameOnly[k] ) != kEdgeName || w >= S )   // a markdown link (kEdgeLink) is a proven edge, no by-name hit
                {
                    continue;
                }
                const Symbol& ws = ing.symbols[w];
                const Key     probe{ ws.lang, ws.kind, ws.name, 0 };
                for( auto it = std::ranges::lower_bound( keys, probe, keyLess ); it != keys.end() && !keyLess( probe, *it ); ++it )
                {
                    const NodeId u = out.rows[ it->row ].id;
                    const auto   from = g.outTargets.begin() + g.outOff[c];
                    const auto   to   = g.outTargets.begin() + g.outOff[c + 1];
                    // outTargets ascend within a source; the namesake must pass K5 rule 2 (2b/2c)
                    if( u != w && u != c && !std::binary_search( from, to, u ) )
                    {
                        ( ownerReach.admits( c, w, u ) ? nameHits : withheld ).emplace_back( c, it->row );
                    }
                }
            }
        }
        std::ranges::sort( nameHits );
        nameHits.erase( std::ranges::unique( nameHits ).begin(), nameHits.end() );
        if( !nameHits.empty() )
        {
            // the call site: the caller's first call reference of the row's name that is not builtin-spelled (K5 rule 1)
            std::vector<char> isCaller( S, 0 );
            for( const auto& [ c, row ] : nameHits )
            {
                isCaller[c] = 1;
            }
            const ByNameCallSites sites( ing, isCaller );
            for( const auto& [ c, row ] : nameHits )
            {
                const std::uint32_t ref = sites.siteOf( c, ing.symbols[ out.rows[row].id ].name );
                // a hedged edge is always some call reference's; none (or only builtin-spelled ones) ⇒ no row claim
                if( ref != ByNameCallSites::kNoSite )
                {
                    offer( row, NearSinkKind::Name, ref, c );
                }
                else
                {
                    withheld.emplace_back( c, row );
                }
            }
        }
        std::ranges::sort( withheld );
        withheld.erase( std::ranges::unique( withheld ).begin(), withheld.end() );
        for( const auto& hit : withheld )
        {
            ++out.rows[ hit.second ].nameWithheld;
        }
    }

    // ix2-slice commit 4: within a depth, the path TIER (source, then test/bench, then docs) before id — a glob to= (on_*) makes
    // hundreds of depth-0 rows, and docs-tier files must not lead them (the tier is read by extension: a .py under docs/ is
    // still source tier, so docs/examples/*.py rows can lead — card)
    const std::vector<std::uint8_t> tierOfFile = pathTierIndexOver( ing, out.rows, [ & ]( const NearSinkRow& r ) { return ing.symbols[ r.id ].fileId; } );
    std::ranges::sort( out.rows, [ & ]( const NearSinkRow& a, const NearSinkRow& b )
    {
        if( a.reasoned() != b.reasoned() )
        {
            return a.reasoned();
        }
        if( a.site.met != b.site.met )
        {
            return a.site.met;
        }
        if( a.depth != b.depth )
        {
            return a.depth < b.depth;
        }
        const std::uint8_t ta = tierOfFile[ ing.symbols[ a.id ].fileId ];
        const std::uint8_t tb = tierOfFile[ ing.symbols[ b.id ].fileId ];
        return ta != tb ? ta < tb : a.id < b.id;
    } );
    // a to= definition with proven callers and no other way in is to_p= itself, not a frontier row; a to= DECLARATION (a
    // prototype: no body) is no frontier either — it is entered through the definition it declares, whose callers it shares
    std::erase_if( out.rows, [ & ]( const NearSinkRow& r ) { return r.depth == 0 && ( !r.reasoned() || !isDefinitionNotDeclaration( ing.symbols[ r.id ] ) ); } );
    ENSURES( out.rows.size() >= out.callers, "every proven caller within the depth is a row" );
    return out;
}

inline constexpr std::string_view kNearSinkLegend =
    "<near_sink callers= rows=>: the SINK-SIDE frontier — to='s proven callers walked back over resolved call edges up to depth= hops "
    "(callers= counts them), each <ns d= t= n= p=> row with callers= its own proven callers (absent at 0) and why= how it may ALSO be "
    "entered with no edge: declined = a declined call lists it as a candidate (not one spelled like a builtin type's method), value = "
    "it is stored or passed as a value (not by a wrapper decorator such as @property), through = a "
    "call through a parameter or slot is matched to that value, name = a by-name call went to a namesake and has no edge to it (a call "
    "not spelled like a builtin type's method; a row with no class needs the caller's file to be or import its file, a class method needs its class "
    "to own something the forward search reached or to derive from the bound definition's class, each base bound by its file's import), "
    "closure = it is a named function written inside in='s body (site= its own definition: in= runs it or hands it on), "
    "external = none of those and no proven caller: no indexed way in was found (an entry point, an out-of-tree or framework caller, "
    "a hand-off the index does not record, or dead); withheld=name:N = N callers whose by-name calls reach this namesake "
    "fail a name rule (either one): not counted as a way in, and never read as external; in= site= name one such site (its enclosing definition, file:line), met=1 when the forward search reached in= (it met that "
    "hand-off and could not follow it). A row is where the backward search could not see, never a hop and not proof a path exists; "
    "rows= counts them, rows_capped=1 = more than shown; next= on the block lists the first row's callers and declined sites. ";
// Present-only: rides with a SHOWN <ns> row whose site is a name-key lookup (via="name-key" cands=).
inline constexpr std::string_view kNearSinkNameKeyLegend =
    "ns via=name-key cands=K: the declined site is a NAME-KEYED lookup, not a call: in= looks a method up by a name built from a template "
    "(getattr(o, 'do_' + c), o['on' + e]) that fits this row, a template that can name K definitions including it; matched, never traced; "
    "the bridge crosses a lookup of at most 16, so a wider one is a way in with no bridge row. Or a posted message: in= passes a construction of a "
    "message class whose handler name (the repo's own __init_subclass__ rule) is this row's name, at site=; K the methods of that name. ";
inline std::string nearSinkLegend( const PathNearSink& ns )
{
    const std::size_t shown = std::min( ns.rows.size(), kNearSinkRows );
    const bool        nameKey = std::any_of( ns.rows.begin(), ns.rows.begin() + std::ptrdiff_t( shown ), []( const NearSinkRow& r ) { return r.site.valid && r.site.cands > 0; } );
    return ns.rows.empty() ? std::string() : std::string( kNearSinkLegend ) + ( nameKey ? std::string( kNearSinkNameKeyLegend ) : std::string() );
}

// The <near_sink> block (empty string when there is no row). `rootPrefix` empty ⇒ p= stays as indexed (multi-root).
inline std::string pathNearSinkXml( const IngestResult& ing, const PathNearSink& ns, bool singleRoot, std::string_view rootPrefix )
{
    if( ns.rows.empty() )
    {
        return {};
    }
    std::vector<char> esc;
    const auto ex  = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    const auto rel = [ & ]( std::uint32_t fileId ) -> std::string_view
    { return singleRoot ? sarif::rootRelativeUri( ing.files[ fileId ], rootPrefix ) : std::string_view( ing.files[ fileId ] ); };
    const std::size_t shown = std::min( ns.rows.size(), kNearSinkRows );
    std::string       rows;
    for( std::size_t i = 0; i < shown; ++i )
    {
        const NearSinkRow& r   = ns.rows[i];
        const Symbol&      s   = ing.symbols[ r.id ];
        // why="declined:D,value:V,through:T,name:M" (table order), "external" with no proven caller and no other way in —
        // a withheld by-name hit is a way in the index holds, so it is never external (review M1) — nothing with proven callers only
        const std::string  counted = kindCountsValue( r.counts, kNearSinkKindNames );
        const std::string  why     = counted.empty() && r.callers == 0 && r.nameWithheld == 0 ? std::string( "external" ) : counted;
        rows += "<ns d=\"" + std::to_string( r.depth ) + "\" t=\"" + std::string( symTag( s.kind ) ) + "\" n=\"" + ex( s.name ) + "\" p=\""
              + ex( rel( s.fileId ) ) + ":" + std::to_string( s.line ) + "\"" + ( r.callers > 0 ? " callers=\"" + std::to_string( r.callers ) + "\"" : std::string() )
              + ( why.empty() ? std::string() : " why=\"" + why + "\"" )
              + ( r.nameWithheld > 0 ? " withheld=\"name:" + std::to_string( r.nameWithheld ) + "\"" : std::string() );
        if( r.site.valid )
        {
            rows += ( r.site.in < ing.symbols.size() ? " in=\"" + ex( ing.symbols[ r.site.in ].name ) + "\"" : std::string() ) + " site=\""
                  + ex( rel( r.site.fileId ) ) + ":" + std::to_string( r.site.line ) + "\"" + ( r.site.met ? " met=\"1\"" : "" )
                  + ( r.site.cands > 0 ? " via=\"name-key\" cands=\"" + std::to_string( r.site.cands ) + "\"" : std::string() );
        }
        rows += "/>";
    }
    const Symbol& first = ing.symbols[ ns.rows.front().id ];
    return "<near_sink depth=\"" + std::to_string( kNearSinkDepth ) + "\" callers=\"" + std::to_string( ns.callers ) + "\" rows=\""
         + std::to_string( ns.rows.size() ) + "\"" + ( ns.rows.size() > shown ? " rows_capped=\"1\"" : "" )
         + nextAttrXml( nextFlag( "--callers=", std::string( rel( first.fileId ) ) + ":" + first.name ) ) + ">" + rows + "</near_sink>";
}

// ── GLOB ENDPOINT (lane ix2-slice, commit 4: IX-2 P4) ────────────────────────────────────────────────────────────────
// `--path=post_message,on_*` answered rc=1 "endpoint not found": the reader asking how a message reaches its handlers names
// the handler FAMILY, not one of its 279 members. An endpoint that names no definition and holds a `*` (and no file:
// qualifier) now stands for every function or method DEFINITION whose name fits it (`*` = any run of characters, possibly
// empty), so the one multi-target search answers it; from_glob="1"/to_glob="1" on the root says which endpoint was a
// pattern, and from_defs=/to_defs= count its matches. A name that does resolve is never read as a pattern.
// The definitions a path endpoint names: resolveAllByNameQualified, else — for a bare `*` pattern — every function or method
// definition whose name fits it, in id order. `*glob` says which happened.
inline std::vector<NodeId> resolvePathEndpoint( const IngestResult& ing, std::string_view spec, std::size_t* unprovenDefs, bool* glob )
{
    *glob                   = false;
    std::vector<NodeId> out = resolveAllByNameQualified( ing, spec, unprovenDefs );
    if( !out.empty() || spec.find( '*' ) == std::string_view::npos || spec.find( ':' ) != std::string_view::npos )
    {
        return out;
    }
    for( NodeId id = 0; id < ing.symbols.size(); ++id )
    {
        const Symbol& s = ing.symbols[id];
        if( ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && isDefinitionNotDeclaration( s ) && wildcardMatch( s.name, spec ) )
        {
            out.push_back( id );
        }
    }
    *glob = !out.empty();
    return out;
}

inline constexpr std::string_view kPathGlobLegend =
    "from_glob=1 / to_glob=1: that endpoint held a * and named no definition, so it stands for every function or method definition "
    "whose name fits the pattern (* = any run of characters); from_defs=/to_defs= count them. ";
inline std::string_view pathGlobLegend( bool on ) noexcept
{
    return on ? kPathGlobLegend : std::string_view();
}
inline std::string pathGlobAttrXml( bool fromGlob, bool toGlob )
{
    return std::string( fromGlob ? " from_glob=\"1\"" : "" ) + ( toGlob ? " to_glob=\"1\"" : "" );
}

// ── HEDGED PATH BRIDGE (lane ix2-slice, commit 4: IX-2 P1) ─────────────────────────────────────────────────────────
// THE GAP. The gap rows say where the forward search went blind and <near_sink> where the backward one did, but neither
// joins them: on htop the reader still has to see that checkRecalculation's declined `Machine_scan()` could mean the Linux
// build, whose callee is the sink. A human crosses exactly those hops.
//
// THE CONTRACT. Only on a reachable="0" answer, a second search may CROSS hops the graph holds no edge for — at most
// kBridgeCrossings of them, each fanning out to at most kBridgeFanOut candidates (a wider declined/value/namesake one is not followed; a slot one is bounded on its callers, below):
//   declined  from a symbol to each candidate of a declined call it makes (the call's stored candidate list);
//   value     from a symbol to each function it stores or passes as a value (ValueRefIndex::targetsOf);
//   closure   from a function to each named function written in its body (src/closures.h);
//   namesake  from a symbol whose call was bound by name alone to one definition, to the name's other same-language,
//             same-kind definitions (the namesakes the proven search never walked);
//   slot      (HOP1) from a function that calls through a struct field to each function stored in that field, read back
//             from the stored function's side (backhops.h BackwardHops: the --callers <vr via="slot"> join, slot-name its
//             field-name tier), only while that join names at most kBridgeFanOut calling functions (slot_callers=). That bound is
//             on the BACKWARD width only; how many functions the field holds (slot_fns=, the forward width) is printed, never
//             capped — a cap would delete the gold hop through a wide table (tmux's 92-entry cmd_entry.exec).
//   container (composed hops) from a function that calls through a container element (or a parameter's default) (`handlers[i]()`)
//             to each function that container may hold (backhops.h forwardHops: the --callers <vr called_by=> join read
//             forward), only while it may hold at most kBridgeFanOut (cands=) and its join names at most kBridgeFanOut callers.
// A chain whose EVERY crossing is COMPOSABLE may take kBridgeSlotCrossings of them (tmux's send-keys chain is three field
// calls deep: cmd_entry.exec, window_mode.command, the command table's .f); any other chain keeps kBridgeCrossings.
// Composable = a slot crossing (bounded on its callers), or (composed hops) a declined or container crossing that is NARROW:
// at most kBridgeNarrowFan candidates. A wider declined/container crossing still counts toward kBridgeCrossings, never past it.
// Layer by layer — every symbol reachable with k crossings over resolved edges before any with k+1 — so the chain printed
// has the FEWEST crossings, then is the first found in deterministic (id-ascending) order. <bridge proven="0" crossings=
// hops=> lists it as <s> rows like a path's, the crossing into a row named by via= (and cands= its fan-out).
//
// What it does NOT mean: a bridge is NOT a path — reachable= stays 0, hops= stays 0, and no count includes it. It is the
// closest chain the index can show, every crossing a hedge. Absent (with no clause) when no chain exists within the bounds.
inline constexpr std::uint32_t kBridgeCrossings     = 2;
inline constexpr std::uint32_t kBridgeSlotCrossings = 3;               // HOP1: a chain of composable crossings only may take one more
inline constexpr std::size_t   kBridgeFanOut        = kBackHopWidth;   // 16, the backward provider's own width bound
inline constexpr std::size_t   kBridgeNarrowFan     = 4;   // composed hops: a declined/container crossing this narrow composes like a slot one
static_assert( kImpactRingSlotDepth == kBridgeSlotCrossings, "the --impact ring's field-only depth mirrors the bridge's composable allowance" );
inline constexpr std::size_t   kBridgeMaxHops       = 8;   // a longer chain is no answer a reader would follow: none is printed

enum class BridgeVia : std::uint8_t { Edge, Declined, Value, Closure, Namesake, Container, Queue, NameKey, Slot, SlotName };   // Container, Queue, NameKey before the slot pair
inline constexpr std::size_t kBridgeViaCount = 10;
static_assert( enumCountIsExact<BridgeVia, kBridgeViaCount>(), "kBridgeViaCount must equal the BridgeVia count — raise it with the append" );
inline constexpr std::array      kBridgeViaNames = { std::string_view( "" ), std::string_view( "declined" ), std::string_view( "value" ), std::string_view( "closure" ),
                                                     std::string_view( "namesake" ), std::string_view( "container" ), std::string_view( "queue" ), std::string_view( "name-key" ), std::string_view( "slot" ),
                                                     std::string_view( "slot-name" ) };   // indexed by BridgeVia
static_assert( kBridgeViaNames.size() == kBridgeViaCount, "one name per BridgeVia value (the extent is deduced from the names)" );
static_assert( std::size_t( BridgeVia::SlotName ) + 1 == kBridgeViaCount && std::size_t( BridgeVia::Slot ) + 2 == kBridgeViaCount, "the two slot crossings close the enum" );
inline bool bridgeViaIsSlot( BridgeVia v ) noexcept
{
    return v >= BridgeVia::Slot;   // Slot or SlotName, the enum's last two (static_assert above)
}
// Whether a crossing composes past kBridgeCrossings (composed hops): a slot one (already bounded on its callers), or a declined /
// container one fanning out to at most kBridgeNarrowFan.
inline bool bridgeCrossingComposes( BridgeVia v, std::size_t fan ) noexcept
{
    return bridgeViaIsSlot( v ) || ( ( v == BridgeVia::Declined || v == BridgeVia::Container || v == BridgeVia::Queue || v == BridgeVia::NameKey ) && fan <= kBridgeNarrowFan );
}

struct PathBridge
{
    std::vector<NodeId>        hops;       // from= definition … to= definition
    std::vector<BridgeVia>     via;        // parallel: how the hop INTO each row was taken (Edge: a resolved call edge)
    std::vector<std::uint32_t> fan;        // parallel: a crossing's candidate count, or (slot) the calling functions the join names; 0 on an edge
    std::vector<std::uint32_t> fwd;        // parallel: (slot) the functions the field holds, uncapped (slot_fns=); 0 on any other row
    std::size_t                crossings = 0;

    bool found() const noexcept { return !hops.empty(); }
};

// The bridge crossing a forward hop of each kind takes, indexed by BackHopVia (a declined hop has no forward twin).
inline constexpr std::array kBridgeViaOfHop = { BridgeVia::Slot, BridgeVia::SlotName, BridgeVia::Declined, BridgeVia::Container, BridgeVia::Queue, BridgeVia::NameKey };
static_assert( kBridgeViaOfHop.size() == kBackHopViaCount, "one bridge crossing per hop kind" );

// SLOT and CONTAINER crossings out of `u`: the provider's forward hops (backhops.h forwardHops, each confirmed by the target's own
// backward hop naming u within the width bound — one copy of the join), fields first. `cross( to, via, width, stored )`
// decides whether the target is new. A slot crossing is bounded on its callers (width) and prints its forward width
// (slot_fns=, never capped); a container crossing is bounded on both and prints its forward width as cands=.
template<class Cross>
inline void bridgeHopCrossings( const ForwardHops& fwdHops, NodeId u, bool fieldCalls, Cross&& cross )
{
    for( const ForwardHop& h : fwdHops.forwardHops( u ) )
    {
        if( hopKind( h.via ).fieldCall != fieldCalls || h.width > kBridgeFanOut || ( !fieldCalls && h.stored > kBridgeFanOut ) )
        {
            continue;
        }
        // a field crossing is bounded on its callers and prints the field's holders; any other (container, queue readers,
        // a name-key template's definitions) prints its forward width as cands=
        cross( h.to, kBridgeViaOfHop[ std::size_t( h.via ) ], fieldCalls ? h.width : h.stored, fieldCalls ? h.stored : 0u );
    }
}

// DECLINED crossings of record `site`: each candidate of its stored list, unless the list is missing or wider than kBridgeFanOut,
// or the call reads as the builtin method it spells (DeclinedCrossRule, HOP1 #11). `cross( to, via, fan )` sees the fan, so a walk
// may narrow it further (composed hops: past the general crossing bound only fan <= kBridgeNarrowFan composes).
template<class Cross>
inline void bridgeDeclinedCrossings( const Graph& g, const DeclinedCrossRule& rule, std::uint32_t site, Cross&& cross )
{
    const std::uint32_t list = g.declinedSiteList[ site ];
    if( list == kNoDeclinedList || list + 1 >= g.declinedListOff.size() || rule.builtinSpelled( site ) )
    {
        return;   // a call with no stored candidate list names nothing to cross to; a builtin-spelled one is no hand-off
    }
    const std::size_t fan = g.declinedListOff[ list + 1 ] - g.declinedListOff[ list ];
    for( std::uint32_t slot = g.declinedListOff[ list ]; fan <= kBridgeFanOut && slot < g.declinedListOff[ list + 1 ]; ++slot )
    {
        cross( g.declinedListCand[ slot ], BridgeVia::Declined, fan );
    }
}

inline PathBridge pathBridge( const IngestResult& ing, const Graph& g, std::span<const NodeId> srcDefs, std::span<const NodeId> dstDefs,
                              const ValueRefIndex& values, const BackwardHops& backHops )
{
    constexpr std::uint32_t kUnseen = std::numeric_limits<std::uint32_t>::max();
    const std::size_t       S       = ing.symbols.size();
    PathBridge              out;
    if( S == 0 || g.outOff.size() < S + 1 )
    {
        return out;   // no graph over these symbols (an empty tree): no chain to show
    }
    // the crossings out of each symbol, as (from, index) pairs sorted by from: declined records, value references, closures
    std::vector<std::pair<NodeId, std::uint32_t>> declinedBy, valueBy, closureOf;
    for( std::uint32_t site = 0; site < g.declinedSiteList.size(); ++site )
    {
        declinedBy.emplace_back( g.declinedSiteCaller[site], site );
    }
    for( std::uint32_t i = 0; i < ing.references.size(); ++i )
    {
        if( ing.references[i].role == RefRole::Value && ing.references[i].fromSymbol < S )
        {
            valueBy.emplace_back( ing.references[i].fromSymbol, i );
        }
    }
    const ClosureIndex closures( ing );
    for( NodeId id = 0; closures.any() && id < S; ++id )
    {
        if( const NodeId p = closures.parentOf( id ); p != kNoNode )
        {
            closureOf.emplace_back( p, id );
        }
    }
    std::ranges::sort( declinedBy );
    std::ranges::sort( valueBy );
    std::ranges::sort( closureOf );
    // namesakes: the definitions by (lang, kind, name), id within
    std::vector<NodeId> defsByKey;
    for( NodeId id = 0; id < S; ++id )
    {
        if( isDefinitionNotDeclaration( ing.symbols[id] ) )
        {
            defsByKey.push_back( id );
        }
    }
    const auto keyLess = [ & ]( NodeId a, NodeId b )
    {
        const Symbol& x = ing.symbols[a];
        const Symbol& y = ing.symbols[b];
        if( x.lang != y.lang )
        {
            return x.lang < y.lang;
        }
        if( x.kind != y.kind )
        {
            return x.kind < y.kind;
        }
        return x.name != y.name ? sortutil::svLess( x.name, y.name ) : a < b;
    };
    std::ranges::sort( defsByKey, keyLess );
    const auto sameKey = [ & ]( NodeId a, NodeId b )
    { const Symbol& x = ing.symbols[a]; const Symbol& y = ing.symbols[b]; return x.lang == y.lang && x.kind == y.kind && x.name == y.name; };

    std::vector<std::uint32_t> layer( S, kUnseen );
    std::vector<NodeId>        parent( S, kNoNode );
    std::vector<BridgeVia>     viaOf( S, BridgeVia::Edge );
    std::vector<std::uint32_t> fanOf( S, 0 );
    std::vector<std::uint32_t> fwdOf( S, 0 );   // HOP1: a slot crossing's forward width (slot_fns=)
    std::vector<char>          isDst( S, 0 );
    std::vector<char>          composable( S, 0 );   // every crossing on the symbol's chain so far composes (slot, or a narrow declined/container; layer 0: none)
    // Known limit: within one layer a symbol is claimed by the FIRST chain to meet it (composable seeds sort first, but a mixed chain at a
    // shallower BFS depth still wins), so a composable chain through that symbol may lose its third crossing: a bridge is lost, never a wrong one.
    // a chain may not route THROUGH a de-prioritized symbol — a test, bench, demo or generated file, a minified bundle, or (since
    // train 31's head round-robin lane) a .d.ts / .pyi declaration twin whose package ships its implementation (filter.h's rank
    // tiers: any multiplier below 1) — only start or end at one: the runtime path a reader asks for runs through the code itself
    const std::vector<float>   tierMul = rankTierSymbolMultipliers( ing );
    const auto                 routable = [ & ]( NodeId v ) { return isDst[v] != 0 || tierMul[v] >= 1.f; };
    for( const NodeId t : dstDefs )
    {
        if( t < S )
        {
            isDst[t] = 1;
        }
    }
    const ForwardHops     fwdHops( ing, backHops );   // composed hops: the provider read forward (slot + container crossings), memoised per answer
    const ByNameCallSites byNameSites( ing, {} );   // K5 rule 1: a namesake crossing needs a call of the name not builtin-spelled
    NamesakeRule          ownerReach( ing, g );     // K5 rule 2 (2b/2c): the owners of every symbol layers 0..k reached
    std::vector<NodeId> frontier;
    for( const NodeId s : srcDefs )
    {
        if( s < S && layer[s] == kUnseen )
        {
            layer[s]    = 0;
            composable[s] = 1;
            frontier.push_back( s );
        }
    }
    NodeId hit = kNoNode;
    for( std::uint32_t k = 0; k <= kBridgeSlotCrossings && hit == kNoNode && !frontier.empty(); ++k )
    {
        // every symbol reachable from this layer's seeds over resolved call edges joins the layer
        std::vector<NodeId> queue = std::move( frontier );
        frontier.clear();
        for( std::size_t head = 0; head < queue.size() && hit == kNoNode; ++head )
        {
            const NodeId u = queue[head];
            if( isDst[u] != 0 )
            {
                hit = u;
                break;
            }
            for( std::uint32_t e = g.outOff[u]; e < g.outOff[u + 1]; ++e )
            {
                if( const NodeId v = g.outTargets[e]; v < S && layer[v] == kUnseen && routable( v ) )
                {
                    layer[v]    = k;
                    parent[v]   = u;
                    composable[v] = composable[u];
                    queue.push_back( v );
                }
            }
        }
        if( hit != kNoNode || k == kBridgeSlotCrossings )
        {
            break;
        }
        const bool composeOnly = k >= kBridgeCrossings;   // past the general bound only a composable chain crosses, and only by a composable crossing
        for( const NodeId u : queue )   // this layer is complete: its owners join the reach (cumulative over layers)
        {
            ownerReach.add( ing.symbols[u] );
        }
        // one crossing out of this layer seeds the next
        const auto cross = [ & ]( NodeId from, NodeId to, BridgeVia via, std::size_t fan, std::size_t fwd = 0 )
        {
            if( to < S && layer[to] == kUnseen && routable( to ) )
            {
                layer[to]    = k + 1;
                parent[to]   = from;
                viaOf[to]    = via;
                fanOf[to]    = std::uint32_t( fan );
                fwdOf[to]    = std::uint32_t( fwd );
                composable[to] = char( composable[from] != 0 && bridgeCrossingComposes( via, fan ) );
                frontier.push_back( to );
            }
        };
        for( const NodeId u : queue )
        {
            if( composeOnly && composable[u] == 0 )
            {
                continue;
            }
            const auto crossTo = [ & ]( NodeId to, BridgeVia via, std::size_t fan, std::size_t fwd ) { cross( u, to, via, fan, fwd ); };
            bridgeHopCrossings( fwdHops, u, /*fieldCalls=*/true, crossTo );   // HOP1: slot crossings
            const std::pair<NodeId, std::uint32_t> lo( u, 0u ), hi( u, std::numeric_limits<std::uint32_t>::max() );
            // composed hops: past the general bound, only a narrow declined or container crossing composes like a slot one
            const auto crossNarrow = [ & ]( NodeId to, BridgeVia via, std::size_t fan, std::size_t fwd = 0 ) { if( fan <= kBridgeNarrowFan ) { crossTo( to, via, fan, fwd ); } };
            for( auto it = std::ranges::lower_bound( declinedBy, lo ); it != declinedBy.end() && *it <= hi; ++it )
            {
                bridgeDeclinedCrossings( g, backHops.declinedRule(), it->second, [ & ]( NodeId to, BridgeVia via, std::size_t fan ) { composeOnly ? crossNarrow( to, via, fan ) : crossTo( to, via, fan, 0 ); } );
            }
            if( composeOnly )
            {
                bridgeHopCrossings( fwdHops, u, /*fieldCalls=*/false, crossNarrow );
                continue;
            }
            for( auto it = std::ranges::lower_bound( valueBy, lo ); it != valueBy.end() && *it <= hi; ++it )
            {
                if( vrIsWrapperDecorator( ing.references[ it->second ].fieldName ) )
                {
                    continue;   // a wrapper decorator hands the function back under its own name: no hand-off
                }
                const std::vector<NodeId> targets = values.targetsOf( it->second );
                for( std::size_t t = 0; targets.size() <= kBridgeFanOut && t < targets.size(); ++t )
                {
                    cross( u, targets[t], BridgeVia::Value, targets.size() );
                }
            }
            for( auto it = std::ranges::lower_bound( closureOf, lo ); it != closureOf.end() && *it <= hi; ++it )
            {
                cross( u, it->second, BridgeVia::Closure, 1 );
            }
            for( std::uint32_t e = g.outOff[u]; e < g.outOff[u + 1] && e < g.outNameOnly.size(); ++e )
            {
                const NodeId w = g.outTargets[e];
                if( edgeKindByte( g.outNameOnly[e] ) != kEdgeName || w >= S || byNameSites.siteOf( u, ing.symbols[w].name ) == ByNameCallSites::kNoSite )
                {
                    continue;   // not a by-name edge, or every call of the name is builtin-spelled (K5 rule 1)
                }
                auto first = std::ranges::lower_bound( defsByKey, w, [ & ]( NodeId a, NodeId b ) { return sameKey( a, b ) ? false : keyLess( a, b ); } );
                auto last  = first;
                while( last != defsByKey.end() && sameKey( *last, w ) )
                {
                    ++last;
                }
                const std::size_t fan = std::size_t( last - first ) - ( std::find( first, last, w ) != last ? 1u : 0u );
                for( auto it = first; fan <= kBridgeFanOut && it != last; ++it )
                {
                    if( *it != w && ownerReach.admits( u, w, *it ) )   // K5 rule 2 (2b/2c)
                    {
                        cross( u, *it, BridgeVia::Namesake, fan );
                    }
                }
            }
            bridgeHopCrossings( fwdHops, u, /*fieldCalls=*/false, crossTo );   // composed hops: container crossings, after every older kind
        }
        // the next layer's seeds in id order — a composable seed first (HOP1, composed hops), so a symbol both kinds of chain reach
        // keeps the one that may still cross past the general bound; with no composable crossing anywhere this is the plain id order.
        // The walk below them is order-independent of how they were met.
        std::ranges::sort( frontier, [ & ]( NodeId a, NodeId b ) { return composable[a] != composable[b] ? composable[a] > composable[b] : a < b; } );
    }
    if( hit == kNoNode )
    {
        return out;
    }
    for( NodeId n = hit; n != kNoNode; n = parent[n] )
    {
        out.hops.push_back( n );
        out.via.push_back( viaOf[n] );
        out.fan.push_back( fanOf[n] );
        out.fwd.push_back( fwdOf[n] );
        out.crossings += viaOf[n] != BridgeVia::Edge ? 1u : 0u;
    }
    std::ranges::reverse( out.hops );
    std::ranges::reverse( out.via );
    std::ranges::reverse( out.fan );
    std::ranges::reverse( out.fwd );
    if( out.hops.size() > kBridgeMaxHops + 1 )
    {
        return PathBridge{};   // past the hop bound: the legend says a bridge is shown only within it
    }
    // crossings >= 1 holds because every caller asks only on reachable=0 (a caller precondition, not something this function
    // makes true), so it is checked in debug and never promised in release (review nit)
    DASSERT( out.crossings >= 1
                 && ( out.crossings <= kBridgeCrossings || ( out.crossings <= kBridgeSlotCrossings && composable[ hit ] != 0 ) ),
             "only reached when the proven search was not (reachable=0), within the bound (composable chains: one more)" );
    return out;
}

inline constexpr std::string_view kPathBridgeLegend =
    "<bridge proven=\"0\" crossings= hops=>: a HEDGED chain from= to to= of at most 8 hops that crosses at most 2 the graph holds no "
    "edge for (3 when every crossing is a slot, or a declined or container one of at most 4 candidates), each declined, value, namesake or container one fanning out to at most 16 candidates, each slot one bounded on its callers (a declined call spelled like a builtin type's method is not crossed, "
    "unless its receiver is a this/self field whose class the source states and the tree defines), and "
    "runs through no test, bench, demo, generated or minified symbol, nor a .d.ts/.pyi declaration twin whose package ships its implementation; its <s> rows read like a path's, and via= on a row names the crossing INTO it: declined = "
    "one of cands= candidates of a declined call in the previous row, value = a function the previous row stores or passes as a value, "
    "closure = a function written in the previous row's body, namesake = another same-language, same-kind definition of a name the previous row "
    "calls by name alone, not spelled like a builtin type's method, in a file the previous row's file is or imports when it has no class, "
    "else whose class owns something the chain's earlier layers reached or derives from the bound definition's class in a file that imports "
    "that one, slot = the previous row calls through a struct field this row is stored in (same declared struct "
    "type; slot-name = field name only), slot_callers=N the functions that field join names, at most 16, and slot_fns=K the functions the field holds, NOT capped "
    "(a wide table is still crossed: K says how wide), container = the previous row calls through a container element (or a parameter's default) "
    "this row may be held in (cands= the functions it may hold) (via=name rows are proven edges bound by name). Fewest crossings first. It is NOT a path: reachable= and "
    "hops= on the root stay 0, no count includes it, and every crossing is a hedge. ";
// The bridge clause rides with a bridge; the queue clause (present-only) when it crosses a queue hand-off, the name-key clause
// (present-only) when it crosses a name-keyed lookup.
inline std::string pathBridgeLegend( const PathBridge& br )
{
    if( !br.found() )
    {
        return {};
    }
    return std::string( kPathBridgeLegend ) + std::string( std::ranges::contains( br.via, BridgeVia::Queue ) ? kQueueHopLegend : std::string_view() )
           + std::string( std::ranges::contains( br.via, BridgeVia::NameKey ) ? kNameKeyHopLegend : std::string_view() );
}

inline std::string pathBridgeXml( const IngestResult& ing, const Graph& g, const PathBridge& br, bool singleRoot, std::string_view rootPrefix )
{
    if( !br.found() )
    {
        return {};
    }
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    std::string       out = "<bridge proven=\"0\" crossings=\"" + std::to_string( br.crossings ) + "\" hops=\"" + std::to_string( br.hops.size() - 1 ) + "\">";
    for( std::size_t i = 0; i < br.hops.size(); ++i )
    {
        const Symbol&          s  = ing.symbols[ br.hops[i] ];
        const std::string_view rp = singleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix ) : std::string_view( ing.files[ s.fileId ] );
        out += "<s t=\"" + std::string( symTag( s.kind ) ) + "\" n=\"" + ex( s.name ) + "\" p=\"" + ex( rp ) + ":" + std::to_string( s.line ) + "\"";
        if( br.via[i] != BridgeVia::Edge )
        {
            // a slot crossing's width is the calling functions its field join names (HOP1), every other crossing's its candidates
            out += " via=\"" + std::string( kBridgeViaNames[ std::size_t( br.via[i] ) ] ) + ( bridgeViaIsSlot( br.via[i] ) ? "\" slot_callers=\"" : "\" cands=\"" )
                 + std::to_string( br.fan[i] ) + "\"";
            if( bridgeViaIsSlot( br.via[i] ) )
            {
                out += " slot_fns=\"" + std::to_string( br.fwd[i] ) + "\"";   // the forward width, uncapped: how many functions the field holds
            }
        }
        else if( i > 0 )
        {
            out += viaNameAttr( edgeNameOnly( g, br.hops[i - 1], br.hops[i] ) );   // FE-B: a proven hop bound by name says so
        }
        out += "/>";
    }
    return out + "</bridge>";
}

// ── ON-NAME-HANDLERS-V2: the message-handler rule on a reachable=0 --path ─────────────────────────────────────────────────
// When from= is a poster (handlerrule.h: a method of a class that reads the rule attribute) called at post sites whose
// message class names a to= handler, the answer says HOW the message gets there by name: the rule (where the repo writes the
// handler name and its spelling), the readers that pass the name on (the dispatch side, by name on the read's own line),
// and the posted classes with the width of each handler name. All of it is a HEDGE: matched by name, never traced, never in
// reachable=/hops=; a handler name with more than kHandlerRuleListMax definitions is a count with next=, never a cut list.
inline constexpr std::size_t kHandlerRuleShown   = 3;    // <hm> rows: the widest posted classes first
inline constexpr std::size_t kHandlerRuleReaders = 4;    // <hrd> rows
inline constexpr std::size_t kHandlerRuleListMax = 16;   // the bridge's own width limit: at most this many defs are listed as <h>

struct PathHandlerRow
{
    NodeId        cls   = kNoNode;
    std::uint32_t site  = 0;   // the first post site of that class
    std::uint32_t posts = 0;
    std::uint32_t cands = 0;
    std::string   handler;
};
struct PathHandlerRule
{
    const HandlerRule*          rule = nullptr;
    std::uint32_t               posts = 0;
    std::uint32_t               defs  = 0;
    std::vector<PathHandlerRow> rows;      // every posted class, widest first
    std::vector<NodeId>         listed;    // the handler defs when defs <= kHandlerRuleListMax
    bool found() const noexcept { return rule != nullptr && !rows.empty(); }
};

inline PathHandlerRule pathHandlerRule( const IngestResult& ing, const NameKeyHops& names, std::span<const NodeId> srcDefs, std::span<const NodeId> dstDefs )
{
    PathHandlerRule     out;
    const HandlerRules& hr = names.rules();
    if( !hr.any() )
    {
        return out;
    }
    std::vector<std::string_view> fromNames;
    for( const NodeId s : srcDefs )
    {
        fromNames.push_back( ing.symbols[s].name );
    }
    std::vector<std::string_view> toNames;
    for( const NodeId d : dstDefs )
    {
        toNames.push_back( ing.symbols[d].name );
    }
    std::ranges::sort( toNames, sortutil::svLess );
    toNames.erase( std::ranges::unique( toNames ).begin(), toNames.end() );
    std::vector<std::string> hit;   // the handler names a counted post site carries that to= names
    for( const HandlerPostSite& site : hr.sites() )
    {
        const Reference& r = ing.references[ site.ref ];
        if( !std::ranges::contains( fromNames, std::string_view( r.calleeName ) ) )
        {
            continue;
        }
        bool counted = false;
        for( std::size_t k = 0; k < site.classes.size(); ++k )
        {
            const std::string h = hr.handlerNameOf( site.classes[k] );
            if( !std::ranges::binary_search( toNames, std::string_view( h ), sortutil::svLess ) )
            {
                continue;
            }
            counted = true;
            hit.push_back( h );
            const auto row = std::ranges::find( out.rows, site.classes[k], &PathHandlerRow::cls );
            if( row != out.rows.end() )
            {
                ++row->posts;
                continue;
            }
            const std::vector<NodeId> t = hr.targets( site.ref );
            out.rows.push_back( PathHandlerRow{ site.classes[k], site.ref, 1, std::uint32_t( std::ranges::count_if( t, [ & ]( NodeId d ) { return ing.symbols[d].name == h; } ) ), h } );
        }
        out.posts += counted ? 1 : 0;
    }
    if( out.rows.empty() )
    {
        return out;
    }
    std::ranges::sort( hit, sortutil::svLess );
    hit.erase( std::ranges::unique( hit ).begin(), hit.end() );
    for( const NodeId d : dstDefs )
    {
        if( std::ranges::binary_search( hit, std::string_view( ing.symbols[d].name ), sortutil::svLess ) && hr.classes().ownerOf( d ) != kNoNode )
        {
            ++out.defs;
            out.listed.push_back( d );
        }
    }
    if( out.defs > kHandlerRuleListMax )
    {
        out.listed.clear();
    }
    std::ranges::stable_sort( out.rows, []( const PathHandlerRow& a, const PathHandlerRow& b ) { return a.cands > b.cands; } );
    out.rule = hr.ruleOf( out.rows.front().cls );   // the ONE rule pick (handlerrule.h): the nearest rule base
    return out;
}

// Owner.name for a definition inside a class, else the name.
inline std::string handlerRuleQualified( const IngestResult& ing, const HandlerRules& hr, NodeId d )
{
    const NodeId owner = hr.classes().ownerOf( d );
    return owner != kNoNode ? ing.symbols[ owner ].name + "." + ing.symbols[d].name : ing.symbols[d].name;
}

// The line `n` of `text` (1-based), or empty.
inline std::string_view handlerRuleLine( std::string_view text, std::uint32_t n )
{
    std::size_t at = 0;
    for( std::uint32_t k = 1; k < n && at != std::string_view::npos; ++k )
    {
        at = text.find( '\n', at );
        at = at == std::string_view::npos ? at : at + 1;
    }
    if( at == std::string_view::npos || at >= text.size() )
    {
        return {};
    }
    return text.substr( at, std::min( text.find( '\n', at ), text.size() ) - at );
}
// Does `line` pass word `w` as a call argument (`(w` or `, w` before a `,` or `)`)?
inline bool handlerRulePassesWord( std::string_view line, std::string_view w )
{
    for( std::size_t at = line.find( w ); at != std::string_view::npos && !w.empty(); at = line.find( w, at + 1 ) )
    {
        std::size_t b = at;
        while( b > 0 && line[ b - 1 ] == ' ' )
        {
            --b;
        }
        std::size_t e = at + w.size();
        while( e < line.size() && line[e] == ' ' )
        {
            ++e;
        }
        if( b > 0 && ( line[ b - 1 ] == '(' || line[ b - 1 ] == ',' ) && e < line.size() && ( line[e] == ',' || line[e] == ')' ) )
        {
            return true;
        }
    }
    return false;
}
// The definition a reader passes the name to: a call of a method of the reader's own class (same file) on the line of its
// read, or on a later line that passes the local the read was assigned to (`n = m.attr` … `self.f( n, m )`).
inline NodeId handlerRulePassee( const IngestResult& ing, const HandlerRules& hr, const HandlerReader& reader )
{
    const Symbol&          fn    = ing.symbols[ reader.fn ];
    const NodeId           owner = hr.classes().ownerOf( reader.fn );
    const std::string_view text( hr.text( fn.fileId ) );
    const std::string_view read  = handlerRuleLine( text, reader.line );
    std::string_view       local;
    if( const std::size_t eq = read.find( '=' ); eq != std::string_view::npos && read.find( "==" ) == std::string_view::npos )
    {
        local = read.substr( 0, eq );
        while( !local.empty() && ( local.front() == ' ' || local.front() == '\t' ) )
        {
            local.remove_prefix( 1 );
        }
        while( !local.empty() && local.back() == ' ' )
        {
            local.remove_suffix( 1 );
        }
        if( !std::ranges::all_of( local, []( char c ) { return std::isalnum( static_cast<unsigned char>( c ) ) || c == '_'; } ) )
        {
            local = {};
        }
    }
    for( const Reference& c : ing.references )
    {
        if( c.fromSymbol != reader.fn || c.role != RefRole::Call || c.line < reader.line
            || ( c.line != reader.line && !handlerRulePassesWord( handlerRuleLine( text, c.line ), local ) ) )
        {
            continue;
        }
        for( const Symbol& s : ing.symbols )
        {
            if( s.name == c.calleeName && s.fileId == fn.fileId && hr.classes().ownerOf( s.id ) == owner && s.id != reader.fn )
            {
                return s.id;
            }
        }
    }
    return kNoNode;
}

inline std::string pathHandlerRuleXml( const IngestResult& ing, const NameKeyHops& names, const PathHandlerRule& hrule, bool singleRoot, std::string_view rootPrefix )
{
    if( !hrule.found() || hrule.rule == nullptr )
    {
        return {};
    }
    const HandlerRules& hr = names.rules();
    const HandlerRule&  rule = *hrule.rule;
    std::vector<char>   esc;
    const auto          ex  = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    const auto          rel = [ & ]( std::uint32_t fileId ) -> std::string
    {
        return ex( singleRoot ? sarif::rootRelativeUri( ing.files[ fileId ], rootPrefix ) : std::string_view( ing.files[ fileId ] ) );
    };
    const auto loc = [ & ]( NodeId n ) { return rel( ing.symbols[n].fileId ) + ":" + std::to_string( ing.symbols[n].line ); };
    const std::string spelled = rule.prefix + ( rule.qualified ? "{snake(Owner)_}" : "" ) + "{snake(Class)}" + ( rule.nsKeyword ? " | " + rule.prefix + "{namespace}_{snake(Class)}" : std::string() );
    const std::size_t shown = std::min( hrule.rows.size(), kHandlerRuleShown );
    std::string out = "<handler_rule via=\"name-key\" base=\"" + ex( ing.symbols[ rule.base ].name ) + "\" attr=\"" + ex( rule.attr ) + "\" name=\"" + ex( spelled )
                    + "\" p=\"" + rel( rule.fileId ) + ":" + std::to_string( rule.line ) + "\" posts=\"" + std::to_string( hrule.posts ) + "\" classes=\""
                    + std::to_string( hrule.rows.size() ) + "\" handlers=\"" + std::to_string( hrule.defs ) + "\" shown=\"" + std::to_string( shown ) + "\"";
    if( hrule.listed.empty() )
    {
        out += nextAttrXml( nextFlag( "--regex=", "def " + hrule.rows.front().handler + "\\(" ) );
    }
    out += ">";
    std::size_t readers = 0;
    for( const HandlerReader& reader : rule.readers )
    {
        const NodeId rd = reader.fn;
        if( readers == kHandlerRuleReaders )
        {
            break;
        }
        ++readers;
        const NodeId passee = handlerRulePassee( ing, hr, reader );
        out += "<hrd n=\"" + ex( handlerRuleQualified( ing, hr, rd ) ) + "\" p=\"" + loc( rd ) + "\""
             + ( passee != kNoNode ? " passes=\"" + ex( handlerRuleQualified( ing, hr, passee ) ) + "\" passes_p=\"" + loc( passee ) + "\"" : std::string() ) + "/>";
    }
    for( std::size_t i = 0; i < shown; ++i )
    {
        const PathHandlerRow& row  = hrule.rows[i];
        const Reference&      site = ing.references[ row.site ];
        out += "<hm n=\"" + ex( handlerRuleQualified( ing, hr, row.cls ) ) + "\" h=\"" + ex( row.handler ) + "\" in=\"" + ex( handlerRuleQualified( ing, hr, site.fromSymbol ) )
             + "\" site=\"" + rel( site.fileId ) + ":" + std::to_string( site.line ) + "\" posts=\"" + std::to_string( row.posts ) + "\" cands=\"" + std::to_string( row.cands ) + "\"/>";
    }
    for( const NodeId d : hrule.listed )
    {
        out += "<h n=\"" + ex( handlerRuleQualified( ing, hr, d ) ) + "\" p=\"" + loc( d ) + "\"/>";
    }
    return out + "</handler_rule>";
}

// Present-only: rides exactly when <handler_rule> prints.
inline constexpr std::string_view kHandlerRuleLegend =
    "<handler_rule via=name-key base= attr= name= p= posts= classes= handlers= shown=>: HOW a posted message reaches a to= handler BY NAME, not a call: "
    "base='s __init_subclass__ writes attr= (p=) as name= (snake: an underscore between a lower and an upper letter, then lower case; Owner = the class it is "
    "nested in), read from this repo's own source; posts= calls of from= whose first argument constructs a subclass of base= that names a to= handler, "
    "classes= those classes, handlers= the to= definitions those names match (methods; which one runs depends on the receiver's class). "
    "<hrd n= p= passes=>: a function that reads attr= (outside tests) and, in passes=, the method it hands the name to: a call on the line of the read, or a later call passing the local it was read into (the lookup side; no such call found: no passes=). "
    "<hm n= h= in= site= posts= cands=>: one posted class (widest first, shown= of classes=), its handler name, its first post site, cands=K definitions of h=. "
    "<h n= p=>: every handler definition when handlers= is at most 16; above that next= lists one name's definitions. Matched, never traced; a hedge, never a hop. ";
inline std::string_view pathHandlerRuleLegend( const PathHandlerRule& hrule ) noexcept
{
    return hrule.found() ? kHandlerRuleLegend : std::string_view();
}


// ── BODY-ON-ROUTE (lane path-hop-body-fix1, textual-11): the bodies of the route a reachable=0 answer already names ──────────
// A reachable=0 answer names a route it never traced: the bridge rows (poster -> queue consumer -> dispatcher) and the handler_rule
// readers (where the handler name is read and dispatched). The question is usually what those functions DO (textual-11: the post
// puts onto _message_queue, the loop takes from it, _on_message dispatches and bubbles to _parent) and the answer printed only names.
// GAIN GATE (the FOR-ROUTE lesson: 25 KB of rows that gained nothing): only symbols the answer already prints on its route, the
// bridge rows within kRouteBodyMaxHops of from= (never to=, nor the row whose next step is a slot crossing into to=: that body holds a call
// through a field and no call to to=) and the <hrd> readers shown; each body under the per-body guard
// (kHopBodyCapBytes); at most kRouteBodyMax bodies, capped="1" + next= past it. HONESTY: the envelope says proven="0"; a body under a
// crossing carries that crossing's via= cands= (one candidate's body, never the proven callee), a reader's via="name-key"; nothing
// here enters reachable=, hops= or any proven count.
inline constexpr std::size_t kRouteBodyMaxHops = 2;   // bridge rows 0..2 (from= and the next two), never the to= row
inline constexpr std::size_t kRouteBodyMax     = 4;   // spew guard: bodies per answer; past it capped="1" next= the first unshown

// The route's <bodies of="route" proven="0"> element (routeBodiesXml, the one printer); "" when the answer names no route body.
inline RouteBodiesXml pathRouteBodies( const IngestResult& ing, const Graph& g, const PathBridge& br, const PathHandlerRule& hrule, std::string_view rootArg )
{
    std::vector<RouteBody> out;
    std::vector<NodeId>    seen;
    const auto add = [ & ]( NodeId n, std::string hedge )
    {
        if( n >= ing.symbols.size() || ing.symbols[n].kind == SymKind::ModuleScope || ing.symbols[n].endByte <= ing.symbols[n].sigStartByte
            || fold_detail::overlapsServed( ing, n, seen, /*orHolds=*/true ) )
        {
            return;
        }
        seen.push_back( n );
        out.push_back( { n, std::move( hedge ) } );
    };
    if( br.found() && br.hops.size() >= 2 )
    {
        const std::size_t last = std::min( kRouteBodyMaxHops, br.hops.size() - 2 );   // the to= row is the last one: never printed
        for( std::size_t i = 0; i <= last; ++i )
        {
            if( i + 2 == br.hops.size() && bridgeViaIsSlot( br.via[i + 1] ) )
            {
                continue;   // the row whose only next step is the slot crossing INTO to=: its body holds a call through a field, not a call to to= (train 41b)
            }
            std::string hedge;
            if( i > 0 && br.via[i] != BridgeVia::Edge )
            {
                hedge = " via=\"" + std::string( kBridgeViaNames[ std::size_t( br.via[i] ) ] ) + ( bridgeViaIsSlot( br.via[i] ) ? "\" slot_callers=\"" : "\" cands=\"" )
                      + std::to_string( br.fan[i] ) + "\"" + ( bridgeViaIsSlot( br.via[i] ) ? " slot_fns=\"" + std::to_string( br.fwd[i] ) + "\"" : std::string() );   // the bridge row's own widths
            }
            else if( i > 0 )
            {
                hedge = chainHopHedge( ing, g, br.hops[i - 1], br.hops[i] );   // an edge row: by name / link / split / impl, as on a reached chain
            }
            add( br.hops[i], std::move( hedge ) );
        }
    }
    if( hrule.found() && hrule.rule != nullptr )
    {
        std::size_t readers = 0;
        for( const HandlerReader& reader : hrule.rule->readers )
        {
            if( readers++ == kHandlerRuleReaders )
            {
                break;   // exactly the <hrd> rows pathHandlerRuleXml prints
            }
            add( reader.fn, " via=\"name-key\"" );
        }
    }
    return routeBodiesXml( ing, out, "route", " proven=\"0\"", kRouteBodyMax, rootArg );
}
static_assert( kRouteBodyMaxHops == 2 && kRouteBodyMax == 4 && kHopBodyCapBytes == 4000, "the route clause spells the bounds: re-word it with the knobs" );
inline std::string_view pathRouteBodiesLegend( bool on ) noexcept
{
    return on ? "bodies of=route proven=0: the bodies of the route this answer names but never traced: the bridge rows within 2 hops of "
                "from= (never to=, nor the row calling through a slot into it), then the hrd readers; at most 4 (capped=1, next= the first unshown), each whole up to 4000 bytes "
                "(truncated=1 past it); a hedge, never in reachable= or hops=. "
              : "";
}

}   // namespace rw
