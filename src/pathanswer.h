#pragma once
// pathanswer.h — PATH-ANSWER: the ONE writer of a bound --path answer, for both transports (verbs_navigate.h runPathServed = the CLI
// --path and the --for graph-verb block, mcpverbs.h pathText = MCP path_between and the MCP `for` block). The two transports carried
// this pipeline as two near-copies (search, gaps, pairs, route, hop facts, bodies, alternatives, legend, root, rows) that every lane
// had to edit twice and keep in step by hand; PATH-AMBIG-VC routed MCP path_between through the CLI's endpoint binder
// (forgraphverb.h bindPathEndpoints), which made the two copies one clone, and --quality-delta gated it. What differs between the
// transports is only the surface (PathAnswerSurface): the root spelling, the redaction tally, the bodies an enclosing answer already
// serves, the --for gate, where the value-reference index comes from, and the unreached hint's dialect (`--connect=` on the CLI,
// "the connect verb" on MCP). The endpoints are resolved and refused by the caller; this writes the answer once they bound.

#include "defattrib.h"      // pathHopOwners, pathEndpointBinding, endpointDefinitionCount
#include "defslookup.h"     // pathAltsOf, defAltsLegend — the endpoints' inline alternatives
#include "forgraphverb.h"   // PathEndpointsBound, narrowedAttrXml, narrowedVerbLegend
#include "graph.h"
#include "graphlegend.h"    // the shared legend clauses and the counts_floor= marker
#include "hopbody.h"        // PATH-HOP-BODY / BODY-ON-ROUTE
#include "hoprecord.h"      // HopFacts, hopLegend, hopRootAttrsXml
#include "infra/emit.h"     // emitTo / emitRaw
#include "model.h"
#include "pathgaps.h"       // PATH-GAP, the near sink, the handler rule, the bridge, the glob endpoint
#include "pathpairs.h"      // TRACE-EP: the reaching definition pairs and their rows
#include "pathroute.h"      // PATH-ROUTE v2: the route verdict
#include "redact.h"         // RedactCounts
#include "sarif.h"          // rootRelativeUri
#include "serialize.h"      // escapeXml
#include "valuerefindex.h"  // ValueRefIndex, toValueRefs
#include "valuerefs.h"      // valueRefsDepthAttrXml

#include <cstddef>
#include <cstdio>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
// What one transport hands the writer. rootPrefix/rootAttr/bodyRoot are empty on a multi-root run; rootAttr is pre-escaped.
struct PathAnswerSurface
{
    bool                    singleRoot = false;
    std::string_view        rootPrefix;          // sarif::rootPrefixOf( root ): p= relative to root=
    std::string_view        rootAttr;            // ` root="…"`, last on the root element
    std::string_view        bodyRoot;            // the root a hop body is read under
    RedactCounts*           redact     = nullptr;
    std::span<const NodeId> served;              // bodies the enclosing answer already carries (the CLI --for block); a middle hop among them prints none
    bool                    inForBlock = false;  // inside a --for graph-verb block: no BODY-ON-ROUTE (the --for answer serves its own)
    bool                    mcp        = false;  // the unreached hint names "the connect verb" / "uses/impact" instead of the CLI flags
};

// Writes the <path> answer for endpoints that bound (ep.srcDefs and ep.dstDefs non-empty) to `out`. valueIndex() returns the
// ValueRefIndex the gap, near-sink, bridge and value-reference counts read; the CLI builds it on first call, MCP keeps one per index.
template<class ValueIndex>
inline void writePathAnswer( std::FILE* out, const IngestResult& ing, const Graph& g, const PathEndpointsBound& ep, const PathAnswerSurface& sf,
                             ValueIndex valueIndex )
{
    EXPECTS( !ep.srcDefs.empty() && !ep.dstDefs.empty(), "both transports refuse an endpoint that bound no definition first" );
    const std::vector<NodeId>& srcDefs      = ep.srcDefs;
    const std::vector<NodeId>& dstDefs      = ep.dstDefs;
    const bool                 srcGlob      = ep.srcGlob;
    const bool                 dstGlob      = ep.dstGlob;
    const std::size_t          unprovenDefs = ep.srcUnproven + ep.dstUnproven;   // H1: summed onto the root
    const std::vector<NodeId> path    = shortestPathAny( g, srcDefs, dstDefs );   // ONE BFS over every def pair

    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    const auto        loc = [ & ]( NodeId n ) -> std::string
    { const Symbol& s = ing.symbols[n];
      const std::string_view rp = sf.singleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], sf.rootPrefix ) : std::string_view( ing.files[ s.fileId ] );
      return ex( rp ) + ":" + std::to_string( s.line ); };

    // from_p/to_p = the def this run actually bound the name to; from_defs/to_defs = how many it could have
    // bound it to (>1 ⇒ qualify with file:name if this is not the one you meant).
    // R-E fix (2026-08-19): --path ships no legend of its own, so the shared root-relative clause IS its
    // whole first-screen legend here — root= would otherwise be the one attribute on this document with
    // nothing anywhere saying what it means. Same text, same helper, as every other verb's.
    // H5 (capture-audit 2026-09-04): reachable="0" hops="0" is a zero read off the name-based graph — the
    // same question --verify=calls(A,B) answers `not-established` + counts_floor="1" for. Same marker,
    // same brief sentence, on both transports (mcpverbs.h path_between mirrors this line).
    // Reference-as-value round: with no directed call path, how often to= is used as a VALUE — a run through such a
    // slot is not a hop the graph can show, so the count is the clue (the callers verb lists the binding sites).
    // PATH-GAP (src/pathgaps.h): an unreached to= is "no path" only when the search met no call the graph holds no edge
    // for; otherwise the answer says the search was incomplete and names where. One ValueRefIndex serves both counts.
    const ToValueRefs pthToValueRefs = path.empty() ? toValueRefs( ing, true, dstDefs, &valueIndex() ) : ToValueRefs{};
    const PathSearchGaps pthGaps = path.empty() ? pathSearchGaps( ing, g, srcDefs, valueIndex() ) : PathSearchGaps{};
    // HOP1 (src/backhops.h): the ONE backward hop provider the bridge's slot crossings and the root next= below read
    std::optional<BackwardHops> pthBackHops;
    if( path.empty() )
    {
        pthBackHops.emplace( ing, g, valueIndex() );
    }
    // ix2-slice: the sink-side frontier beside the forward gap rows (src/pathgaps.h pathNearSink), reachable="0" only; its name-key
    // ways in come from the same provider
    const PathNearSink   pthNear = path.empty() ? pathNearSink( ing, g, dstDefs, pthGaps.cone, valueIndex(), pthBackHops->names() ) : PathNearSink{};
    // ON-NAME-HANDLERS-V2: a poster from= whose posted message classes name to= handlers (src/pathgaps.h pathHandlerRule)
    const PathHandlerRule pthHandler = path.empty() ? pathHandlerRule( ing, pthBackHops->names(), srcDefs, dstDefs ) : PathHandlerRule{};
    // TRACE-EP (src/pathpairs.h): a reached answer whose names have several definitions lists EVERY reaching definition pair
    // (up to kPathPairChains chains, the rest alt=), never one silently; a glob endpoint keeps its any-of-these meaning
    const PathPairs pthPairs = path.empty() || srcGlob || dstGlob ? PathPairs{}
        : pathReachingPairs( ing, g, srcDefs, dstDefs, path, ep.spec, [ & ]( std::span<const NodeId> dstMembers )
          {
              if( !pthBackHops )
              {
                  pthBackHops.emplace( ing, g, valueIndex() );
              }
              return pathBridge( ing, g, srcDefs, dstMembers, valueIndex(), *pthBackHops );
          } );
    // PATH-ROUTE v2 (src/pathroute.h pathRouteChains): the chain the answer prints after the route verdict (refused: none; proven-preferred:
    // the proven chain), shared with the MCP twin
    const PathRouteChains   pthChains = pathRouteChains( ing, g, pthPairs, path, srcDefs, dstDefs );
    const PathRouteVerdict& pthRoute  = pthChains.verdict;
    const std::vector<NodeId>&  pthRows   = pthChains.rows;    // the rows the answer prints
    const std::vector<NodeId>&  pthShown  = pthChains.shown;   // the root's hops=
    const std::vector<NodeId>&  pthBind   = pthChains.bind;    // from_p=/to_p= (a refused chain still bound its endpoints)
    const NodeId                srcUsed   = pthChains.from;
    const NodeId                dstUsed   = pthChains.to;
    // HOP-CONTEXT-1 (src/hoprecord.h): every printed hop's call site, call text and callee signature — ONE reference pass
    const HopFacts          pthHops   = pathHopFacts( ing, g, pthPairs, pthRows, sf.redact, pthRoute.declinedRef );   // a declined last hop: its record's call
    // ix2-slice (IX-2 P1): the hedged bridge — the fewest-crossings chain over declined / value / closure / namesake / slot hops
    const PathBridge     pthBridge = path.empty() ? pathBridge( ing, g, srcDefs, dstDefs, valueIndex(), *pthBackHops ) : PathBridge{};
    // HOP1 (#6): to= has a backward hop the provider follows → the root next= is the callers verb on to=, not the gap bodies
    const std::string        pthSinkCallers = path.empty() && pthGaps.any() && !dstGlob ? pathSinkCallersSelector( ing, *pthBackHops, dstDefs, ep.dst, sf.singleRoot, sf.rootPrefix )
                                                                                         : std::string();
    // FE-B: exactly when a printed hop is via="name" (every printed chain when pairs are listed); link, anchor, split, owner alike
    const PathShownMarks pthMarks = pathShownMarks( ing, g, pthPairs, pthRows, pthRoute.declinedCands > 0 );
    const bool pthHasVia  = pthMarks.via;
    const bool pthHasLink = pthMarks.link;
    const bool pthHasMiss = pthMarks.miss;
    // attrib-multidef (defattrib.h): from_p=/to_p= only for an endpoint the path bound; prov="split" on a split-arm hop
    const PathEndpointBinding pthBound = pathEndpointBinding( g, endpointDefinitionCount( ing, srcDefs ), endpointDefinitionCount( ing, dstDefs ), pthBind );
    const bool                    pthHasSplit = pthMarks.split;
    // zed-03 (src/pathpairs.h): a bound endpoint that is a test/fixture copy while a source definition exists is disclosed
    const PathTestTwin        pthTwin = srcGlob || dstGlob ? PathTestTwin{} : pathTestTwins( ing, g, { srcDefs, ep.src, pthBound.from }, { dstDefs, ep.dst, pthBound.to }, pthBind );
    const std::vector<std::string_view> pthOwners = pathHopOwners( ing, pthRows );   // PATH-OWNERS: n="Owner.name" per hop
    const bool pthHasOwner = pthMarks.owner;
    // PATH-HOP-BODY (src/hopbody.h): a reached chain of 2 hops prints its middle hop's body (hedged when that hop is no proven
    // call); a longer one names the first in next=. BODY-ON-ROUTE (src/pathgaps.h pathRouteBodies): a reachable=0 answer prints
    // the bodies of the route it names (bridge rows, handler_rule readers), every one a hedge. ONE printer for both.
    const std::string_view   pthBodyRoot  = sf.bodyRoot;
    const bool               pthBodiesOn  = !pthRows.empty() && hopBodiesOn();
    const RouteBodiesXml pthHopBodyEl = pthBodiesOn ? pathHopBodiesXml( ing, pathMiddleHops( ing, g, pthShown, sf.served ), pthBodyRoot ) : RouteBodiesXml{};
    // GAIN GATE (fix1 fire table): never inside a --for graph-verb block — the --for answer serves its own bodies, and the one
    // in-sample fire there (LARGE-DEV vscode-03, +7.7 KB) named nothing its question asked for
    const RouteBodiesXml pthRouteEl   = path.empty() && !sf.inForBlock && hopBodiesOn()
                                                ? pathRouteBodies( ing, g, pthBridge, pthHandler, pthBodyRoot ) : RouteBodiesXml{};
    const std::string&       pthHopBodies = pthHopBodyEl.xml;
    // D2 part 5 (defslookup.h): the other definitions of an endpoint whose pick is not provably unique, inline — after the bodies, so a
    // definition a <bodies> element printed is not listed again
    std::vector<NodeId>  pthBodyIds   = pthHopBodyEl.ids;
    pthBodyIds.insert( pthBodyIds.end(), pthRouteEl.ids.begin(), pthRouteEl.ids.end() );
    const PathAlts       pthAlts      = pathAltsOf( ing, g, ep.src, ep.dst, srcGlob, dstGlob, pthBound.from ? srcUsed : kNoNode, pthBound.to ? dstUsed : kNoNode, pthPairs, pthBodyIds );
    std::string              pthRootAttrs = pathTestTwinRootAttrs( ing, pathPairsRootAttrs( ing, pthPairs, sf.singleRoot, sf.rootPrefix ).rootAttrs, pthTwin, sf.singleRoot, sf.rootPrefix );
    const std::string        pthHopNext   = pthBodiesOn && pthRootAttrs.find( " next=\"" ) == std::string::npos ? pathMiddleHopNext( ing, pthShown, pthBodyRoot ) : std::string();
    pthRootAttrs += pthHopNext.empty() ? std::string() : nextAttrXml( pthHopNext );
    pthRootAttrs += pathRouteRootAttrs( ing, pthRoute, srcUsed, pthRootAttrs.find( " next=\"" ) != std::string::npos, sf.singleRoot, sf.rootPrefix );
    emitTo( out, "<!-- ripwire path: one DIRECTED call path from= to to= (each <s> a hop); reachable= is 0 and hops= 0 when the "
                 "graph holds none. {}{}{}{}-->{}", ( defAltsLegend( pthAlts ) + unprovenDefsVerbLegend( UnprovenDefsVerb::Path, unprovenDefs > 0 ) + viaNameLegend( pthHasVia )
                                                     + viaLinkLegend( pthHasLink ) + anchorMissLegend( pthHasMiss )
                                                     + splitArmLegend( pthHasSplit ) + pathUnboundLegend( !pthBound.from || !pthBound.to )
                                                     + memberOwnerLegend( pthHasOwner ) + memberOwnerContainedLegend( pthMarks.ownerContained ) + std::string( pathPairsLegend( pthPairs ) ) + pathOrderLegend( pthPairs, pthTwin )
                                                     + std::string( pathHopBodiesLegend( !pthHopBodies.empty() ) ) + std::string( pathHopNextLegend( !pthHopNext.empty() ) )
                                                     + std::string( routeBodyHedgeLegend( pthHopBodyEl.hedged || pthRouteEl.hedged ) ) + std::string( pathRouteLegend( pthRoute ) )
                                                     + hopLegend( pthHops, "s" ) ).c_str(),
                 ( std::string( toValueRefsLegend( pthToValueRefs.count > 0 ) ) + valueRefsDepthLegend( pthToValueRefs.depthCut.files > 0 ) ).c_str(),
                 ( pathGapsLegend( pthGaps.any(), !pthSinkCallers.empty() ) + pathBridgeLegend( pthBridge )
                   + nearSinkLegend( pthNear ) + std::string( pathHandlerRuleLegend( pthHandler ) ) + std::string( pathRouteBodiesLegend( !pthRouteEl.xml.empty() ) )
                   + std::string( pathGlobLegend( srcGlob || dstGlob ) ) + std::string( narrowedVerbLegend( !ep.narrowed.empty() ) ) ).c_str(),
                 graphCountFloorBrief( graphGaugeClauses( g ) ).c_str(), rootRelPathsLegend( sf.singleRoot ) );
    emitTo( out, "<path from=\"{}\" to=\"{}\"{}{} from_defs=\"{}\" to_defs=\"{}\"{} reachable=\"{}\" hops=\"{}\"{}{}",
                 ex( ep.src ).c_str(), ex( ep.dst ).c_str(), pthBound.from ? " from_p=\"" + loc( srcUsed ) + "\"" : std::string(),
                 pthBound.to ? " to_p=\"" + loc( dstUsed ) + "\"" : std::string(),
                 srcDefs.size(), dstDefs.size(), ( unprovenDefsAttrXml( unprovenDefs ) + pathGlobAttrXml( srcGlob, dstGlob )
                                                   + narrowedAttrXml( ep.narrowed ) ).c_str(),   // H1: beside the defs counts it is not in; ix2-slice: a glob endpoint; GV-PATH-BIND
                 pthRows.empty() ? 0 : 1, pthShown.empty() ? std::size_t( 0 ) : pthShown.size() - 1,
                 ( pthRootAttrs + hopRootAttrsXml( pthHops ) + std::string( sf.rootAttr ) ).c_str(),
                 graphCountFloorAttrXml( g ).c_str() );
    // absent at zero: byte-identical otherwise; the depth cut beside it makes the count (or its absence) a floor
    emitTo( out, "{}{}", countAttrXmlOrEmpty( "to_value_refs", pthToValueRefs.count ),
                 valueRefsDepthAttrXml( ing, pthToValueRefs.depthCut, VrRender{ sf.singleRoot, sf.rootPrefix } ).c_str() );
    // P2.10: a dead end is exactly the moment to name the next verb. --path is DIRECTED; --connect searches
    // undirected and finds the shared-caller join a directed walk can never see.
    const PathGapsXml pthUnreached = path.empty()
        ? pathUnreachedXml( ing, pthGaps, sf.singleRoot, sf.rootPrefix,
                                sf.mcp ? PathHintSpelling{ "the connect verb on " + ep.src + "," + ep.dst, "uses/impact", "", pathDocEndpoints( ing, srcDefs, dstDefs ) }
                                       : PathHintSpelling{ "--connect=" + ep.src + "," + ep.dst, "--uses/--impact",
                                                           ( srcDefs.size() > 1 || dstDefs.size() > 1 ) ? "; several defs share these names — qualify as file:name to pick one" : "",
                                                           pathDocEndpoints( ing, srcDefs, dstDefs ) },
                                pthSinkCallers )
        : PathGapsXml{};
    emitTo( out, "{}>{}{}{}{}", pthUnreached.rootAttrs, pthUnreached.rows, pathBridgeXml( ing, g, pthBridge, sf.singleRoot, sf.rootPrefix ),
                 pathNearSinkXml( ing, pthNear, sf.singleRoot, sf.rootPrefix ),
                 path.empty() ? pathHandlerRuleXml( ing, pthBackHops->names(), pthHandler, sf.singleRoot, sf.rootPrefix ) : std::string() );
    // FE-B via="name", #409 via="link"/anchor="missing", attrib-multidef prov="split", PATH-OWNERS n="Owner.name": one emitter, shared with MCP path_between
    emitPathAnswerRows( out, ing, g, pthPairs, pthRows, pthOwners, sf.singleRoot, sf.rootPrefix, pthHops, pthRoute.declinedCands );   // TRACE-EP: pairs or today's rows, shared with MCP
    emitRaw( out, pthHopBodies.c_str() );    // PATH-HOP-BODY: after the hop rows they explain ("" when none)
    emitRaw( out, pthRouteEl.xml.c_str() );  // BODY-ON-ROUTE: after the route rows they explain (reachable=0 only)
    emitRaw( out, pthAlts.xml.c_str() );   // D2 part 5: empty when both picks are provably unique
    emitTo( out, "</path>" );
}
} // namespace rw
