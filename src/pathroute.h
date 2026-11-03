#pragma once
// PATH-ROUTE v2 — THE ROUTE VERDICT of a reached --path answer: is the one chain the search found PROVEN, or stitched together from
// calls bound by name alone? ONE predicate, read by both transports (verbs_navigate.h runPathServed = the CLI --path and the --for
// <graph_verb> block; mcpverbs.h pathText = MCP path_between and the MCP `for` graph-verb block), so they cannot disagree.
//
// THE DEFECT (LD-2 django-06/-07): shortestPathAny is a plain BFS over every out-edge, proven and by-name alike, so the fewest-hops
// chain can be a shortcut through several via="name" hops whose receiver nothing proves (django-06: 12 hops, 5 by name, through the
// prefetch code; django-07: Model._save_table -> QuerySet.aggregate -> ... by name). The answer printed it as reachable=1 with
// nothing on the root saying so, and an agent trusts it over the true route it never sees.
//
// WHY THE EMITTER, NOT THE SEARCH (Stage 0, reports/path-route-v2.md): neither row has a route over proven edges only — the true
// chains cross a class-valued attribute (`self._iterable_class(self)`, no edge at all) and by-name receivers (`manager._insert`,
// `compiler.execute_sql`) — so a proven-first search would find the same by-name chain. The honest fix is the verdict.
//
// PROVEN FIRST: a chain of kPathRouteHedgeNameHops or more by-name hops is checked against the proven-only search (shortestPathAny
// provenOnly: the same BFS skipping by-name edges, over the same endpoint definitions); when one exists it is the answer
// (route_hedged="proven-preferred": a shorter chain exists only by name), so neither the hedge nor the refusal ever hides a proven route.
//
// THE RULE (thresholds measured over every reached --path / <graph_verb> chain in S1, MF1-DEV, MF1-DEV-2, LARGE-DEV, LD-2: no
// single-chain answer outside four LARGE-DEV / LD-2 rows carries more than 1 by-name hop; of those four, the two wrong chains carry
// 5 by-name hops (LD-2 django-06, LARGE-DEV cockroach-04) and the two with 3 split: cpython-02's is the true asyncio chain,
// django-07's is wrong — so 3 is hedged, never refused, and the refusal starts at 4; the SECOND cut is route_cands (fix1): every wrong
// chain the reviews refused carried route_cands 144..23712, every TRUE chain checked carried <= 16 (a TS / Go dependency-injection chain
// through interfaces with two implementors per hop is route_cands 2), so a 4-hop chain is refused only from kPathRouteRefuseCandsThreshold up):
//   * fewer than kPathRouteHedgeNameHops by-name hops: printed as before (each hop's via="name" row is its own hedge);
//   * kPathRouteHedgeNameHops or more: printed, HEDGED on the root (route_hedged="name-stitched" route_by_name= route_cands=); from
//     kPathRouteRefuseNameHops the root says route_hedged="unlikely" (the chain is probably not the real route, on the answer itself) and next= follows from='s callees to verify it;
//   * kPathRouteRefuseNameHops or more AND route_cands >= kPathRouteRefuseCandsThreshold: REFUSED as the answer — the chain's rows
//     are not printed (no wrong-branch hop rides in a route), the root says reachable="0" route_hedged="not-proven" (NOT "no path":
//     the search found one, nothing proves it) and next= follows from='s callees.
// route_cands counts IN-REPO same-named definitions only: a by-name call on a builtin or external receiver (`stack.pop()` bound to the
// repo's one `def pop`) counts 1, so a low count is never proof. Never a proven edge dropped from the search; never counted in
// reaches= / any proven count. A pairs answer (several definition pairs, pathpairs.h) keeps its own per-pair hedged= ranking and its
// first pair's chain gets the HEDGE only (its rows are the listing; there is no single chain to refuse).

#include "graph.h"
#include "hopbody.h"     // byNameCandidates — the hop hedge's cands= (how many same-named definitions a by-name call could bind)
#include "model.h"
#include "nextverb.h"    // nextAttrXml
#include "pathpairs.h"   // PathPairs, pathPairSelector

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t   kPathRouteHedgeNameHops  = 2;        // knob (knob-census ADDENDUM): by-name hops that hedge the root
inline constexpr std::size_t   kPathRouteRefuseNameHops = 4;        // knob: by-name hops (with route_cands >= the threshold below) that refuse the chain
inline constexpr std::uint64_t kPathRouteRefuseCandsThreshold = 64;  // knob: route_cands at which a chain of >= kPathRouteRefuseNameHops by-name hops is refused, not hedged (wrong chains 144..23712, true chains <= 16)
inline constexpr std::uint64_t kPathRouteCandsCeiling   = 1000000;  // route_cands= saturates here (a product of per-hop counts); route_cands_capped="1" says so

struct PathRouteVerdict
{
    std::size_t   hops     = 0;   // the judged chain's hops (0 = nothing judged)
    std::size_t   byName   = 0;   // its via="name" hops
    std::uint64_t cands    = 1;   // product of each by-name hop's cands= (saturating): how many equally plausible chains it stands for
    bool          hedged   = false;
    bool          refused  = false;
    std::vector<NodeId> proven;   // non-empty: the proven-only chain printed instead of the name-stitched one
};

// THE ONE PREDICATE. `chain` is the chain the answer would print (pathShownChain); in a pairs answer that is the first pair's chain,
// which is hedged (never refused, never replaced by a proven chain: the pairs ranking already puts the fewest-hedged pair first).
inline PathRouteVerdict pathRouteVerdict( const IngestResult& ing, const Graph& g, const PathPairs& pp, std::span<const NodeId> chain,
                                          const std::vector<NodeId>& srcDefs, const std::vector<NodeId>& dstDefs )
{
    PathRouteVerdict v;
    if( chain.size() < 2 || ( pp.active() && pp.pairs.front().isBridge() ) )   // a bridge is already marked bridge=1, never a path
    {
        return v;
    }
    v.hops = chain.size() - 1;
    for( std::size_t i = 1; i < chain.size(); ++i )
    {
        if( edgeNameOnly( g, chain[i - 1], chain[i] ) )
        {
            ++v.byName;
            const std::uint64_t k = byNameCandidates( ing, g, chain[i - 1], chain[i] );   // >= 1
            v.cands               = v.cands > kPathRouteCandsCeiling / k ? kPathRouteCandsCeiling : std::min( kPathRouteCandsCeiling, v.cands * k );
        }
    }
    if( v.byName < kPathRouteHedgeNameHops )
    {
        return v;
    }
    if( !pp.active() )
    {
        v.proven = shortestPathAny( g, srcDefs, dstDefs, /*provenOnly=*/true );
        if( !v.proven.empty() )
        {
            return v;   // proven-preferred: printed instead, never hedged nor refused
        }
    }
    v.hedged  = true;
    v.refused = !pp.active() && v.byName >= kPathRouteRefuseNameHops && v.cands >= kPathRouteRefuseCandsThreshold;
    return v;
}

// The chains an answer prints after the verdict, for both transports: rows = the hop rows (none when refused; the proven chain when
// proven-preferred; else the search's path), shown = the root's hops= chain, bind = the chain from_p=/to_p= are read off (a refused
// chain still bound its endpoints), from/to = the definitions bound. srcDefs/dstDefs are non-empty (the callers refuse an unresolved one).
struct PathRouteChains
{
    PathRouteVerdict    verdict;
    std::vector<NodeId> rows, shown, bind;
    NodeId              from = kNoNode, to = kNoNode;
};
inline PathRouteChains pathRouteChains( const IngestResult& ing, const Graph& g, const PathPairs& pp, const std::vector<NodeId>& path,
                                        const std::vector<NodeId>& srcDefs, const std::vector<NodeId>& dstDefs )
{
    EXPECTS( !srcDefs.empty() && !dstDefs.empty(), "both --path transports refuse an endpoint that resolves to no definition first" );
    PathRouteChains            c;
    const std::vector<NodeId>& found = pathShownChain( pp, path );
    c.verdict                        = pathRouteVerdict( ing, g, pp, found, srcDefs, dstDefs );
    if( !c.verdict.refused )
    {
        c.rows  = c.verdict.proven.empty() ? path : c.verdict.proven;
        c.shown = c.verdict.proven.empty() ? found : c.verdict.proven;
    }
    c.bind = c.verdict.refused ? found : c.shown;
    c.from = c.bind.empty() ? srcDefs.front() : c.bind.front();
    c.to   = c.bind.empty() ? dstDefs.front() : c.bind.back();
    return c;
}

// The root attributes the verdict adds ("" when it neither hedges nor refuses). A refused answer, and a hedge of kPathRouteRefuseNameHops
// or more by-name hops (unlikely, printed), names from='s callees in next= unless the root already carries a next= (`hasNext`).
inline std::string pathRouteRootAttrs( const IngestResult& ing, const PathRouteVerdict& v, NodeId from, bool hasNext, bool singleRoot,
                                       std::string_view rootPrefix )
{
    if( !v.proven.empty() )
    {
        return " route_hedged=\"proven-preferred\" route_len=\"" + std::to_string( v.hops ) + "\" route_by_name=\"" + std::to_string( v.byName ) + "\"";
    }
    if( !v.hedged && !v.refused )
    {
        return {};
    }
    std::string out = v.refused ? " route_hedged=\"not-proven\" route_len=\"" + std::to_string( v.hops ) + "\"" : std::string( v.byName >= kPathRouteRefuseNameHops ? " route_hedged=\"unlikely\"" : " route_hedged=\"name-stitched\"" );
    out += " route_by_name=\"" + std::to_string( v.byName ) + "\" route_cands=\"" + std::to_string( v.cands ) + "\"" + ( v.cands >= kPathRouteCandsCeiling ? " route_cands_capped=\"1\"" : "" );
    if( ( v.refused || v.byName >= kPathRouteRefuseNameHops ) && !hasNext && from < ing.symbols.size() )
    {
        out += nextAttrXml( nextFlag( "--callees=", pathPairSelector( ing, from, singleRoot, rootPrefix ) ) );   // shell-safe: a path with a space is quoted
    }
    return out;
}

// present-only (the full dialect's spelling; compactlegend.h carries the compact one). No `--` inside: it rides in an XML comment.
inline std::string_view pathRouteLegend( const PathRouteVerdict& v ) noexcept
{
    if( !v.proven.empty() )
    {
        return "route_hedged=proven-preferred route_len=N route_by_name=K: the shortest chain found is N hops, K of them bound by name alone; "
               "a chain over proven call edges only exists and is the one shown (hops= counts it). ";
    }
    if( v.refused )
    {
        return "route_hedged=not-proven route_len=N route_by_name=K route_cands=P: the shortest chain the search found is N hops, K of them "
               "bound by name alone (receiver unproven), standing for P same-named candidate chains (route_cands counts in-repo same-named definitions "
               "along the route; builtin and external receivers are not counted, so a low count is no proof; route_cands_capped=1: at least P), so it is NOT printed as the answer: "
               "reachable=0 here means not proven, never no route, and the true route may be another; next= follows from='s callees "
               "(the callers verb walks back from to=; connect on from=,to= shows the edges with their via= marks). ";
    }
    if( v.hedged && v.byName >= kPathRouteRefuseNameHops )
    {
        return "route_hedged=unlikely route_by_name=K route_cands=P: K of the shown chain's hops are bound by name alone (the via=name "
               "rows; receiver unproven), standing for P same-named candidate chains (route_cands counts in-repo same-named definitions "
               "along the route; builtin and external receivers are not counted, so a low count is no proof; route_cands_capped=1: at least P): "
               "with 4 or more by-name hops this chain is UNLIKELY to be the real route, and the true route may be another; "
               "next= names the step that verifies it (from='s callees, or a hop body to read) before relying on the chain. ";
    }
    if( v.hedged )
    {
        return "route_hedged=name-stitched route_by_name=K route_cands=P: K of the shown chain's hops are bound by name alone (the via=name "
               "rows; receiver unproven), standing for P same-named candidate chains (route_cands counts in-repo same-named definitions "
               "along the route; builtin and external receivers are not counted, so a low count is no proof; route_cands_capped=1: at least P): the route is a hedge, and the true route may be another. ";
    }
    return "";
}

}   // namespace rw
