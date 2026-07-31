// connectcore_harness.cpp — unit + mutation harness for connectSubgraph() (src/graph.h), the graph core of
// --connect (DESIGN_connectSubgraph.md §2/§3: metric-closure 2-approx Steiner over the UNDIRECTED view,
// true call direction reported). graph.h is header-only, so this builds tiny synthetic Graphs by hand
// (out-CSR + in-CSR, exactly buildGraph's layout) and asserts the RESULT STRUCTURE — independent of the
// ctxpack binary, main.cpp, and any corpus.
//
// Cases proved (each maps to a design clause):
//   A   the motivating shape (§1): two siblings under a shared dispatch caller connect THROUGH that caller —
//       which the directed pairwise search (shortestPath) provably misses on the same graph.
//   B   an island terminal lands in its OWN component (honest <unconnected> partition, §2.5) — never dropped.
//   C   direction attributes are TRUE caller→callee even though the search walked the edge caller-ward (§2).
//   D   MST tie-break determinism (§2.3): two equal-cost joins → the (dist, minId, maxId) winner is taken,
//       so the losing join's middle node NEVER appears in the Steiner set.
//   E   radius bound respected (§2.2): a chain longer than R splits the terminals into separate groups; a
//       raised radius reconnects them; out-of-band radii clamp to [kMinRadius, kMaxRadius].
//   F   byte-determinism: two runs (and a permuted terminal order) serialize identically.
//   G   MUTATION check: flipping ONE edge's direction in the fixture flips the reported direction — proving
//       case C is non-vacuous (the direction really is read from the CSR, not synthesized by the walk).
//   H   degrade paths: empty terminals → empty result; out-of-range ids dropped; >16 terminals clamped.
//
// Exit 0 = all pass; nonzero = a failure (per-case PASS/FAIL lines on stdout).

#include "../src/graph.h"

#include <cstdio>
#include <string>
#include <utility>
#include <vector>

using namespace ctx;

static int g_fail = 0;
static void check( bool cond, const char* msg )
{
    std::printf( "  %s  %s\n", cond ? "PASS" : "FAIL", msg );
    if( !cond ) g_fail = 1;
}

// build a Graph from directed (caller, callee) pairs — the same CSR layout buildGraph produces:
// out-edges ascending by target within a source, in-CSR rows ascending by caller (fill preserves the
// (from,to) sort). Unit weights; extra Graph members left default (connectSubgraph never reads them).
static Graph makeGraph( std::size_t n, std::vector<std::pair<NodeId, NodeId>> edges )
{
    std::sort( edges.begin(), edges.end() );
    edges.erase( std::unique( edges.begin(), edges.end() ), edges.end() );

    Graph g;
    g.wOutDeg.assign( n, 0.f );
    g.outOff.assign( n + 1, 0 );
    for( const auto& [ from, to ] : edges ) ++g.outOff[ from + 1 ];
    for( std::size_t i = 0; i < n; ++i ) g.outOff[ i + 1 ] += g.outOff[ i ];
    g.outTargets.resize( edges.size() );
    g.outVals.assign( edges.size(), 1.f );
    {
        std::vector<std::uint32_t> cur( g.outOff.begin(), g.outOff.begin() + n );
        for( const auto& [ from, to ] : edges )
        {
            g.outTargets[ cur[ from ]++ ] = to;
            g.wOutDeg[ from ] += 1.f;
        }
    }

    // in-edge CSR (row = callee), filled in (from,to) order so each row's callers ascend — as buildGraph does.
    std::vector<std::uint32_t> inDeg( n, 0 );
    for( const auto& [ from, to ] : edges ) ++inDeg[ to ];
    g.inEdges = sparseCsr<float>( n, n, edges.size() );
    {
        auto* ro = g.inEdges.rowOffsets();  auto* ci = g.inEdges.colIndices();  auto* val = g.inEdges.values();
        ro[ 0 ] = 0;
        for( std::size_t i = 0; i < n; ++i ) ro[ i + 1 ] = ro[ i ] + inDeg[ i ];
        std::vector<std::uint32_t> cur( ro, ro + n );
        for( const auto& [ from, to ] : edges ) { const std::uint32_t pos = cur[ to ]++; ci[ pos ] = from; val[ pos ] = 1.f; }
    }
    return g;
}

// canonical text form of a ConnectResult — the byte-determinism comparator.
static std::string serialize( const ConnectResult& r )
{
    std::string s = "radius=" + std::to_string( r.radius ) + " truncated=" + std::to_string( r.truncated ) + "\n";
    s += "terminals:";
    for( NodeId t : r.terminals ) s += " " + std::to_string( t );
    s += "\ncomponentOf:";
    for( std::uint32_t c : r.componentOf ) s += " " + std::to_string( c );
    s += "\n";
    for( const ConnectGroup& grp : r.groups )
    {
        s += "group t:";
        for( NodeId t : grp.terminals ) s += " " + std::to_string( t );
        s += " s:";
        for( NodeId v : grp.steiner ) s += " " + std::to_string( v );
        s += " e:";
        for( const ConnectEdge& e : grp.edges ) s += " " + std::to_string( e.from ) + ">" + std::to_string( e.to );
        s += " p:";
        for( const ConnectPath& p : grp.paths )
            s += " " + std::to_string( p.termA ) + "-" + std::to_string( p.termB ) + "@" + std::to_string( p.dist );
        s += "\n";
    }
    return s;
}

static bool hasEdge( const ConnectGroup& grp, NodeId from, NodeId to )
{
    for( const ConnectEdge& e : grp.edges ) if( e.from == from && e.to == to ) return true;
    return false;
}
static bool hasNode( const std::vector<NodeId>& v, NodeId x )
{
    for( NodeId n : v ) if( n == x ) return true;
    return false;
}

int main()
{
    // ── fixture G1: orch(0) → a(1), orch → b(2), b → c(3); island(4) isolated ────────────────────────────
    const Graph g1 = makeGraph( 5, { { 0, 1 }, { 0, 2 }, { 2, 3 } } );

    // ── A: the motivating shape — siblings {a,b} join THROUGH the shared caller orch ─────────────────────
    {
        check( shortestPath( g1, 1, 2 ).empty(), "A directed pairwise search misses the sibling pair (reachable=0)" );
        const ConnectResult r = connectSubgraph( g1, { 1, 2 } );
        check( r.groups.size() == 1 && r.groups[0].terminals == std::vector<NodeId>{ 1, 2 },
               "A siblings land in ONE group" );
        check( r.groups[0].steiner == std::vector<NodeId>{ 0 },
               "A the shared dispatch caller orch is the Steiner node" );
        check( r.groups[0].edges.size() == 2 && hasEdge( r.groups[0], 0, 1 ) && hasEdge( r.groups[0], 0, 2 ),
               "A edges are exactly orch->a and orch->b" );
        check( r.groups[0].paths.size() == 1 && r.groups[0].paths[0].dist == 2,
               "A one MST leg of undirected length 2" );
    }
    // full triple {a,b,c}: nodes {a,b,c,orch}, edges orch->a, orch->b, b->c (design §7 assertion 1)
    {
        const ConnectResult r = connectSubgraph( g1, { 1, 2, 3 } );
        check( r.groups.size() == 1
               && r.groups[0].terminals == std::vector<NodeId>{ 1, 2, 3 }
               && r.groups[0].steiner   == std::vector<NodeId>{ 0 },
               "A triple {a,b,c} -> one group, orch the only intermediary" );
        check( r.groups[0].edges.size() == 3
               && hasEdge( r.groups[0], 0, 1 ) && hasEdge( r.groups[0], 0, 2 ) && hasEdge( r.groups[0], 2, 3 ),
               "A triple edges exactly {orch->a, orch->b, b->c}" );
    }

    // ── B: an island terminal gets its OWN component — present, honest, never dropped ────────────────────
    {
        const ConnectResult r = connectSubgraph( g1, { 1, 4 } );
        check( r.terminals == std::vector<NodeId>{ 1, 4 }, "B both terminals present in the result" );
        check( r.componentOf == std::vector<std::uint32_t>{ 0, 1 }, "B island assigned its own component" );
        check( r.groups.size() == 2
               && r.groups[1].terminals == std::vector<NodeId>{ 4 }
               && r.groups[1].steiner.empty() && r.groups[1].edges.empty(),
               "B island group is a bare singleton (the <unconnected> shape)" );
    }

    // ── C: true caller→callee direction, though the search walked a→orch caller-ward ─────────────────────
    {
        const ConnectResult r = connectSubgraph( g1, { 1, 3 } );   // a..c crosses orch via two caller-ward hops
        check( r.groups.size() == 1 && hasEdge( r.groups[0], 0, 1 ) && !hasEdge( r.groups[0], 1, 0 ),
               "C orch->a reported caller->callee (never a->orch)" );
        check( hasEdge( r.groups[0], 0, 2 ) && hasEdge( r.groups[0], 2, 3 ) && r.groups[0].edges.size() == 3,
               "C full a..c leg keeps every edge's true direction" );
    }

    // ── D: MST tie-break — two equal-cost joins, the (dist, minId, maxId) winner ─────────────────────────
    // terminals A(0), B(1), C(2); middles m1(3): A,B — m2(4): A,C — m3(5): B,C. All pairwise dists are 2.
    // Prim from A picks (2,0,1)=(A,B) then (2,0,2)=(A,C): m1 and m2 are Steiner, m3 must NEVER appear.
    {
        const Graph g2 = makeGraph( 6, { { 3, 0 }, { 3, 1 }, { 4, 0 }, { 4, 2 }, { 5, 1 }, { 5, 2 } } );
        const ConnectResult r = connectSubgraph( g2, { 0, 1, 2 } );
        check( r.groups.size() == 1 && r.groups[0].steiner == std::vector<NodeId>{ 3, 4 },
               "D tie-break picks the (dist,minId,maxId) joins: steiner {m1,m2}" );
        check( !hasNode( r.groups[0].steiner, 5 ), "D the losing equal-cost join m3 is absent" );
        check( r.groups[0].paths.size() == 2
               && r.groups[0].paths[0].termA == 0 && r.groups[0].paths[0].termB == 1
               && r.groups[0].paths[1].termA == 0 && r.groups[0].paths[1].termB == 2,
               "D MST legs are (A,B) then (A,C), never (B,C)" );
    }

    // ── E: radius bound — a chain of 8 hops splits at R=6, reconnects at R=8; clamping is honest ─────────
    {
        std::vector<std::pair<NodeId, NodeId>> chain;
        for( NodeId i = 0; i < 8; ++i ) chain.push_back( { i, NodeId( i + 1 ) } );
        const Graph g3 = makeGraph( 9, chain );

        const ConnectResult far = connectSubgraph( g3, { 0, 8 } );   // default radius 6 < 8 hops
        check( far.radius == connectcfg::kDefaultRadius && far.groups.size() == 2,
               "E dist-8 terminals split into two groups at the default radius 6" );
        const ConnectResult near = connectSubgraph( g3, { 0, 8 }, 8 );
        check( near.groups.size() == 1 && near.groups[0].steiner.size() == 7 && near.groups[0].edges.size() == 8,
               "E radius 8 reconnects them through the 7 chain intermediaries" );
        check( connectSubgraph( g3, { 0, 8 }, 99 ).radius == connectcfg::kMaxRadius,
               "E an oversized radius clamps to kMaxRadius" );
        check( connectSubgraph( g3, { 0, 8 }, 0 ).radius == connectcfg::kMinRadius,
               "E radius 0 clamps to kMinRadius" );
    }

    // ── F: byte-determinism — identical runs and a permuted terminal order serialize identically ─────────
    {
        const std::string run1 = serialize( connectSubgraph( g1, { 1, 2, 3, 4 } ) );
        const std::string run2 = serialize( connectSubgraph( g1, { 1, 2, 3, 4 } ) );
        const std::string perm = serialize( connectSubgraph( g1, { 4, 3, 2, 1 } ) );
        check( run1 == run2, "F two identical runs are byte-identical" );
        check( run1 == perm, "F a permuted terminal order yields the same bytes (sorted terminals)" );
    }

    // ── G: MUTATION — flip orch→a to a→orch in the fixture; the reported direction MUST flip ─────────────
    {
        const Graph gFlip = makeGraph( 5, { { 1, 0 }, { 0, 2 }, { 2, 3 } } );   // a calls orch now
        const ConnectResult r    = connectSubgraph( gFlip, { 1, 2 } );
        const ConnectResult base = connectSubgraph( g1,    { 1, 2 } );
        check( r.groups.size() == 1 && hasEdge( r.groups[0], 1, 0 ) && !hasEdge( r.groups[0], 0, 1 ),
               "G flipped fixture reports a->orch (direction is read from the CSR)" );
        check( serialize( r ) != serialize( base ),
               "G flipped-edge result differs from the baseline (case C is non-vacuous)" );
    }

    // ── H: honest degrades — empty terminals, out-of-range ids, >16-terminal clamp ───────────────────────
    {
        const ConnectResult empty = connectSubgraph( g1, {} );
        check( empty.terminals.empty() && empty.groups.empty() && empty.componentOf.empty(),
               "H empty terminal list -> empty result (no crash, no fabrication)" );
        const ConnectResult oob = connectSubgraph( g1, { 1, 99 } );
        check( oob.terminals == std::vector<NodeId>{ 1 } && oob.groups.size() == 1,
               "H out-of-range terminal id dropped, the valid one kept" );
        std::vector<NodeId> many;
        for( NodeId i = 0; i < 20; ++i ) many.push_back( i );
        const ConnectResult capped = connectSubgraph( makeGraph( 20, {} ), many );
        check( capped.terminals.size() == connectcfg::kMaxTerminals && capped.terminals.back() == 15,
               "H >16 terminals clamp to the 16 lowest ids (caller enforces the usage error)" );
        const ConnectResult dup = connectSubgraph( g1, { 2, 2, 2 } );
        check( dup.terminals == std::vector<NodeId>{ 2 } && dup.groups.size() == 1,
               "H duplicate terminals dedup to one" );
    }

    if( g_fail ) { std::fprintf( stderr, "connectcore_harness: FAIL\n" ); return 1; }
    std::printf( "connectcore_harness: ALL PASS\n" );
    return 0;
}
