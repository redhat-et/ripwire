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

// PATH-FEWEST-UNPROVEN (Fable ideas pass 11-11 card 8; Opus ideas pass C3 (c); rule frozen in ORCH tmp/path-fewest-unproven/RULE.md).
// THE DEFECT (LD-2 django-07): the plain BFS keeps the FIRST chain of the shortest length it meets. Model.save -> execute_sql printed
// _save_table -> QuerySet.aggregate -> Query.get_aggregation (3 by-name hops), a false route, while the true chain is as long with 2
// unproven hops: a by-name `manager._insert` and a DECLINED last call (cands=3) whose stored candidate list holds the to= definition.
// THE RULE (pathFewestUnproven, single-chain answers only; a pairs answer keeps its own fewest-hedged ranking): among the chains of
// the found length, the least (unproven hops, route_cands, test-path intermediates) prints — the last hop may be a declined call
// whose list holds the to= definition BY ID with <= kPathDeclinedLastCands candidates (declinedCrossingCands, the met-bridge's own
// test); equal keys keep today's chain. A replaced chain says so (route_tie= route_tie_other=); a declined last hop says
// via="declined" cands= on its row and route_declined="1" on the root and counts as an unproven hop in the verdict below; any shown
// chain through test-path intermediates (neither endpoint in tests) says route_tests=N. Nothing is refused for it.

#include "backhops.h"    // DeclinedCrossRule, declinedCrossingCands — the met-bridge's by-id declined crossing test (the declined last hop)
#include "graph.h"
#include "hopbody.h"     // byNameCandidates — the hop hedge's cands= (how many same-named definitions a by-name call could bind)
#include "lexical.h"     // subtokens — the owner-word key
#include "model.h"
#include "nextverb.h"    // nextAttrXml
#include "pathpairs.h"   // PathPairs, pathPairSelector
#include "infra/sortutil.h"   // svLess — the by-name candidate count's sorted name list

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <span>
#include <compare>
#include <utility>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t   kPathRouteHedgeNameHops  = 2;        // knob (knob-census ADDENDUM): by-name hops that hedge the root
inline constexpr std::size_t   kPathRouteRefuseNameHops = 4;        // knob: by-name hops (with route_cands >= the threshold below) that refuse the chain
inline constexpr std::uint64_t kPathRouteRefuseCandsThreshold = 64;  // knob: route_cands at which a chain of >= kPathRouteRefuseNameHops by-name hops is refused, not hedged (wrong chains 144..23712, true chains <= 16)
inline constexpr std::uint64_t kPathRouteCandsCeiling   = 1000000;  // route_cands= saturates here (a product of per-hop counts); route_cands_capped="1" says so

inline constexpr std::uint32_t kPathDeclinedLastCands = 3;        // knob (knob-census ADDENDUM): widest declined call a chain may end on (django-07: 3)

// Which key replaced the plain search's chain (PATH-FEWEST-UNPROVEN): the first of (unproven hops, route_cands, test intermediates) that differed.
enum class PathTie : std::uint8_t
{
    None,
    FewerUnproven,
    FewerCands,
    SourceFirst,
    OwnerWord,
};

struct PathRouteVerdict
{
    std::size_t   hops     = 0;   // the judged chain's hops (0 = nothing judged)
    std::size_t   byName   = 0;   // its via="name" hops
    std::uint64_t cands    = 1;   // product of each by-name hop's cands= (saturating): how many equally plausible chains it stands for
    bool          hedged   = false;
    bool          refused  = false;
    std::vector<NodeId> proven;   // non-empty: the proven-only chain printed instead of the name-stitched one
    std::uint32_t declinedCands = 0;           // > 0: the judged chain's LAST hop is a declined call with that many candidates (an unproven hop)
    PathTie       tie           = PathTie::None;   // the plain search's chain was replaced by an equal-length one (shown chain only)
    std::uint32_t tieOther      = 0;           // that replaced chain's unproven hops
    std::uint32_t testHops      = 0;           // intermediates of the shown chain in a test or fixture path (neither endpoint is)
    std::uint32_t tieEqual      = 0;           // other final-step chains as proven as the shown one (same unproven hops and route_cands), a floor
    std::size_t   unproven() const noexcept { return byName + ( declinedCands > 0 ? 1u : 0u ); }
};

// ---- PATH-FEWEST-UNPROVEN: the equal-length chain with the fewest unproven hops --------------------------------------------------
// A chain's key, compared lexicographically: unproven hops (pathHopHedged, or the declined last hop), route_cands (the verdict's product:
// a by-name hop's cands=, the declined hop's candidate count), test-path intermediates (counted only when testsOn), then (increment 2)
// intermediates whose name shares no subtoken with a to= definition's owner name (offWord: the django-07 tie of _do_update/_update
// against _do_insert/_insert, to= SQLInsertCompiler.execute_sql).
struct PathChainKey
{
    std::uint32_t unproven = 0;
    std::uint64_t cands    = 1;
    std::uint32_t tests    = 0;
    std::uint32_t offWord  = 0;
    friend auto operator<=>( const PathChainKey&, const PathChainKey& ) = default;   // member order = the key order
    // the first two keys only: the graph's facts (tests and offWord are readings of paths and names); equal = as proven
    std::pair<std::uint32_t, std::uint64_t> proof() const noexcept { return { unproven, cands }; }
};
inline std::uint64_t pathCandsTimes( std::uint64_t acc, std::uint64_t k ) noexcept
{
    return acc > kPathRouteCandsCeiling / k ? kPathRouteCandsCeiling : std::min( kPathRouteCandsCeiling, acc * k );
}
// Whether the hop's `to` is an intermediate that counts toward tests / offWord.
struct PathHopMarks
{
    bool intermediateInTests = false;
    bool intermediateOffWord = false;
};
// The key of hop from -> to added to a prefix key: `byNameCands()` is byNameCandidates( from, to ), read only on a by-name edge.
template<class ByNameCands>
inline PathChainKey pathHopKey( const Graph& g, PathChainKey k, NodeId from, NodeId to, ByNameCands&& byNameCands, PathHopMarks marks )
{
    k.unproven += pathHopHedged( g, from, to ) ? 1u : 0u;
    k.cands = edgeNameOnly( g, from, to ) ? pathCandsTimes( k.cands, byNameCands() ) : k.cands;
    k.tests += marks.intermediateInTests ? 1u : 0u;
    k.offWord += marks.intermediateOffWord ? 1u : 0u;
    return k;
}
// The subtokens of the to= definitions' owner names (lexical.h subtokens: >= 2 bytes, lowercased); a handful, read by linear find.
inline std::vector<std::string> pathToOwnerWords( const IngestResult& ing, const std::vector<NodeId>& dstDefs )
{
    std::vector<std::string> words;
    for( const NodeId d : dstDefs )
    {
        if( d < ing.symbols.size() && !ing.symbols[d].scope.empty() )
        {
            subtokens( scopeLastSegment( ing.symbols[d].scope ), words );
        }
    }
    return words;
}
// Does `n`'s name share no subtoken with `ownerWords`? (false when there are no owner words: the key then never differs)
inline bool pathNameOffWord( const IngestResult& ing, NodeId n, const std::vector<std::string>& ownerWords )
{
    return !ownerWords.empty() && !holdsSubtokenWord( ing.symbols[n].name, ownerWords );
}
// What the key of a chain reads besides the graph: whether test intermediates count, and the to= owner words.
struct PathKeyReading
{
    bool                     testsOn = false;
    std::vector<std::string> ownerWords;
};
inline PathChainKey pathChainKey( const IngestResult& ing, const Graph& g, std::span<const NodeId> chain, const PathKeyReading& reading )
{
    PathChainKey k;
    for( std::size_t i = 1; i < chain.size(); ++i )
    {
        const bool mid = i + 1 < chain.size();
        k = pathHopKey( g, k, chain[i - 1], chain[i], [ & ] { return byNameCandidates( ing, g, chain[i - 1], chain[i] ); },
                        PathHopMarks{ reading.testsOn && mid && pathDefInTests( ing, chain[i] ), mid && pathNameOffWord( ing, chain[i], reading.ownerWords ) } );
    }
    return k;
}
// Test-path intermediates of a shown chain whose endpoints are both outside tests (route_tests=); 0 otherwise.
inline std::uint32_t pathTestIntermediates( const IngestResult& ing, std::span<const NodeId> chain )
{
    if( chain.size() < 3 || pathDefInTests( ing, chain.front() ) || pathDefInTests( ing, chain.back() ) )
    {
        return 0;
    }
    return std::uint32_t( std::count_if( chain.begin() + 1, chain.end() - 1, [ & ]( NodeId n ) { return pathDefInTests( ing, n ); } ) );
}

struct FewestUnprovenChain
{
    std::vector<NodeId> chain;               // empty: today's chain stands
    std::uint32_t       declinedCands = 0;   // > 0: its last hop is a declined call with that many candidates
    PathTie             tie           = PathTie::None;
    std::uint32_t       otherUnproven = 0;   // today's chain's unproven hops
    std::uint32_t       equalCount    = 0;   // other final-step candidates as proven as the winner (same unproven, route_cands)
};

namespace pathfewest_detail
{
// One final step of a depth-L chain: an edge into a to= definition (`end`), or a declined call by `via` into `to`.
struct FinalCand
{
    PathChainKey  key;
    NodeId        end   = kNoNode;
    NodeId        via   = kNoNode;
    NodeId        to    = kNoNode;
    std::uint32_t cands = 0;
};

// THE LAYERED SEARCH: one BFS from srcDefs over every out-edge to depth L, in the plain search's edge order; each node keeps the least
// key over its predecessors one layer up, replaced only by a STRICTLY smaller key, so equal keys keep the first-found predecessor (the
// plain search's). Work per loop (owner 11-04): the BFS visits each edge of the depth-L cone once; the per-node facts (test path, owner
// word) are read once per node; the by-name candidate counts once per expanded node (one sorted name list, then equal_range per edge).
class LayeredSearch
{
public:
    LayeredSearch( const IngestResult& ing, const Graph& g, std::uint32_t depth, const PathKeyReading& reading )
        : m_ing( ing ), m_g( g ), m_L( depth ), m_reading( reading ), m_n( g.wOutDeg.size() ),
          m_dist( m_n, kUnseen ), m_prev( m_n, kNoNode ), m_best( m_n ), m_isDst( m_n, 0 ), m_inTests( m_n, -1 ), m_offWord( m_n, -1 )
    {
    }
    void run( const std::vector<NodeId>& srcDefs, const std::vector<NodeId>& dstDefs )
    {
        for( const NodeId d : dstDefs )
        {
            if( d < m_n )
            {
                m_isDst[d] = 1;
            }
        }
        for( const NodeId s : srcDefs )
        {
            if( s < m_n && m_dist[s] == kUnseen )
            {
                m_dist[s] = 0;
                m_queue.push_back( s );
            }
        }
        for( std::size_t head = 0; head < m_queue.size(); ++head )
        {
            if( m_dist[ m_queue[ head ] ] < m_L )
            {
                expand( m_queue[ head ] );   // depth L is the last layer: reached, never expanded
            }
        }
    }
    // The final-step candidates in a fixed order: edge-reached to= definitions in discovery order, then declined records in record
    // order (one pass over the declined records; a list of more than kPathDeclinedLastCands candidates is no final step).
    std::vector<FinalCand> finals( const std::vector<NodeId>& dstDefs ) const
    {
        std::vector<FinalCand> out;
        for( const NodeId v : m_queue )
        {
            if( m_dist[v] == m_L && m_isDst[v] )
            {
                out.push_back( FinalCand{ m_best[v], v, kNoNode, kNoNode, 0 } );
            }
        }
        const DeclinedCrossRule rule( m_ing, m_g );
        for( std::uint32_t site = 0; site < m_g.declinedSiteList.size(); ++site )
        {
            const NodeId u = m_g.declinedSiteCaller[ site ];
            if( u < m_n && m_dist[u] != kUnseen && m_dist[u] + 1 == m_L )
            {
                addDeclined( out, rule, site, u, dstDefs );
            }
        }
        return out;
    }
    // The chain src .. f's last node (f.to after a declined call).
    std::vector<NodeId> chainOf( const FinalCand& f ) const
    {
        std::vector<NodeId> chain;
        if( f.via != kNoNode )
        {
            chain.push_back( f.to );
        }
        for( NodeId at = f.via != kNoNode ? f.via : f.end; at != kNoNode; at = m_prev[at] )
        {
            chain.push_back( at );
        }
        std::reverse( chain.begin(), chain.end() );
        return chain;
    }

private:
    static constexpr std::uint32_t kUnseen = UINT32_MAX;
    void expand( NodeId u )
    {
        for( std::uint32_t k = m_g.outOff[u]; k < m_g.outOff[u + 1]; ++k )
        {
            const NodeId v = m_g.outTargets[k];
            if( m_dist[v] == kUnseen )
            {
                m_dist[v] = m_dist[u] + 1;
                m_queue.push_back( v );
            }
            const bool last = m_dist[v] == m_L;
            if( m_dist[v] != m_dist[u] + 1 || ( last && !m_isDst[v] ) )
            {
                continue;   // not one layer down, or the last layer away from a to= definition
            }
            const PathChainKey kv = pathHopKey( m_g, m_best[u], u, v, [ & ] { return byNameCands( u, v ); },
                                                PathHopMarks{ !last && m_reading.testsOn && once( m_inTests, v, [ & ] { return pathDefInTests( m_ing, v ); } ),
                                                              !last && once( m_offWord, v, [ & ] { return pathNameOffWord( m_ing, v, m_reading.ownerWords ); } ) } );
            if( m_prev[v] == kNoNode || kv < m_best[v] )
            {
                m_best[v] = kv;
                m_prev[v] = u;
            }
        }
    }
    void addDeclined( std::vector<FinalCand>& out, const DeclinedCrossRule& rule, std::uint32_t site, NodeId u, const std::vector<NodeId>& dstDefs ) const
    {
        for( const NodeId d : dstDefs )
        {
            const std::uint32_t c = d < m_n ? declinedCrossingCands( m_g, rule, site, d ) : 0u;
            if( c > 0 && c <= kPathDeclinedLastCands )
            {
                PathChainKey kd = m_best[u];
                ++kd.unproven;
                kd.cands = pathCandsTimes( kd.cands, c );
                out.push_back( FinalCand{ kd, kNoNode, u, d, c } );
            }
        }
    }
    // a per-node fact read once: `memo[v]` is -1 until `read()` fills it
    template<class Read>
    static bool once( std::vector<std::int8_t>& memo, NodeId v, Read&& read )
    {
        memo[v] = memo[v] < 0 ? std::int8_t( read() ? 1 : 0 ) : memo[v];
        return memo[v] == 1;
    }
    // byNameCandidates( u, v ) from ONE sorted list of u's by-name targets' names, built on u's first by-name edge (byNameCandidates
    // per edge rescans the out-edges: O(degree^2) on a by-name hub)
    std::uint64_t byNameCands( NodeId u, NodeId v )
    {
        if( m_byNameOf != u )
        {
            m_byNameOf = u;
            m_byNameNames.clear();
            for( std::uint32_t e = m_g.outOff[u]; e < m_g.outOff[u + 1]; ++e )
            {
                const NodeId t = m_g.outTargets[e];
                if( t < m_ing.symbols.size() && e < m_g.outNameOnly.size() && edgeKindByte( m_g.outNameOnly[e] ) == kEdgeName )
                {
                    m_byNameNames.push_back( m_ing.symbols[t].name );
                }
            }
            std::ranges::sort( m_byNameNames, sortutil::svLess );   // the explicit byte comparator (portablebuildcheck #6)
        }
        const auto [ lo, hi ] = std::ranges::equal_range( m_byNameNames, std::string_view( m_ing.symbols[v].name ), sortutil::svLess );
        return std::max<std::uint64_t>( std::uint64_t( hi - lo ), 1 );   // byNameCandidates' own count, >= 1
    }

    const IngestResult&           m_ing;
    const Graph&                  m_g;
    std::uint32_t                 m_L;
    const PathKeyReading&         m_reading;
    std::size_t                   m_n;
    std::vector<std::uint32_t>    m_dist;
    std::vector<NodeId>           m_prev;
    std::vector<PathChainKey>     m_best;
    std::vector<char>             m_isDst;
    std::vector<std::int8_t>      m_inTests;   // pathDefInTests, read once per node (-1 = not read yet)
    std::vector<std::int8_t>      m_offWord;   // pathNameOffWord, read once per node
    std::vector<NodeId>           m_queue;
    std::vector<std::string_view> m_byNameNames;
    NodeId                        m_byNameOf = kNoNode;
};

// The first key on which the winner beats today's chain.
inline PathTie tieOf( const PathChainKey& w, const PathChainKey& today ) noexcept
{
    return w.unproven < today.unproven ? PathTie::FewerUnproven
         : w.cands < today.cands       ? PathTie::FewerCands
         : w.tests < today.tests       ? PathTie::SourceFirst
                                       : PathTie::OwnerWord;
}
}   // namespace pathfewest_detail

// `path` = the plain BFS chain (shortestPathAny, L hops). The candidates at depth L: every to= definition an edge reaches, and every
// declined call made at depth L-1 whose list holds a to= definition (declinedCrossingCands, <= kPathDeclinedLastCands); the least key
// wins, today's chain on a tie. Run only when today's chain has an unproven hop or a test intermediate (an all-proven, all-source
// chain already has the least key that matters).
inline FewestUnprovenChain pathFewestUnproven( const IngestResult& ing, const Graph& g, const std::vector<NodeId>& path,
                                               const std::vector<NodeId>& srcDefs, const std::vector<NodeId>& dstDefs )
{
    using namespace pathfewest_detail;
    FewestUnprovenChain out;
    const std::size_t   N = g.wOutDeg.size();
    if( path.size() < 2 || N == 0 )
    {
        return out;
    }
    const auto           anyInTests = [ & ]( const std::vector<NodeId>& defs ) { return std::ranges::any_of( defs, [ & ]( NodeId n ) { return n < N && pathDefInTests( ing, n ); } ); };
    const PathKeyReading reading{ !anyInTests( srcDefs ) && !anyInTests( dstDefs ), pathToOwnerWords( ing, dstDefs ) };
    const PathChainKey   today = pathChainKey( ing, g, path, reading );
    if( today.unproven == 0 && today.tests == 0 )
    {
        return out;
    }
    LayeredSearch search( ing, g, std::uint32_t( path.size() - 1 ), reading );
    search.run( srcDefs, dstDefs );
    const std::vector<FinalCand> finals = search.finals( dstDefs );
    const FinalCand*             win    = nullptr;
    for( const FinalCand& f : finals )
    {
        win = f.key < ( win != nullptr ? win->key : today ) ? &f : win;
    }
    if( win == nullptr )
    {
        return out;   // today's chain has the least key (ties keep it)
    }
    out.chain = search.chainOf( *win );
    ENSURES( out.chain.size() == path.size(), "the replacing chain has the found length" );
    out.declinedCands = win->cands;
    out.tie           = tieOf( win->key, today );
    out.otherUnproven = today.unproven;
    out.equalCount    = std::uint32_t( std::ranges::count_if( finals, [ & ]( const FinalCand& f ) { return &f != win && f.key.proof() == win->key.proof(); } ) );
    return out;
}

// THE ONE PREDICATE. `chain` is the chain the answer would print (pathShownChain); in a pairs answer that is the first pair's chain,
// which is hedged (never refused, never replaced by a proven chain: the pairs ranking already puts the fewest-hedged pair first).
// `declinedCands` > 0: the chain's last hop is a declined call (pathFewestUnproven) with that many candidates — no graph edge, an
// unproven hop of its own: it counts toward the hedge and refusal thresholds and its candidates multiply route_cands.
inline PathRouteVerdict pathRouteVerdict( const IngestResult& ing, const Graph& g, const PathPairs& pp, std::span<const NodeId> chain,
                                          const std::vector<NodeId>& srcDefs, const std::vector<NodeId>& dstDefs, std::uint32_t declinedCands = 0 )
{
    PathRouteVerdict v;
    if( chain.size() < 2 || ( pp.active() && pp.pairs.front().isBridge() ) )   // a bridge is already marked bridge=1, never a path
    {
        return v;
    }
    v.hops          = chain.size() - 1;
    v.declinedCands = declinedCands;
    for( std::size_t i = 1; i < chain.size(); ++i )
    {
        if( edgeNameOnly( g, chain[i - 1], chain[i] ) )
        {
            ++v.byName;
            v.cands = pathCandsTimes( v.cands, byNameCandidates( ing, g, chain[i - 1], chain[i] ) );   // >= 1
        }
    }
    v.cands = declinedCands > 0 ? pathCandsTimes( v.cands, declinedCands ) : v.cands;
    if( v.unproven() < kPathRouteHedgeNameHops )
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
    v.refused = !pp.active() && v.unproven() >= kPathRouteRefuseNameHops && v.cands >= kPathRouteRefuseCandsThreshold;
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
    // PATH-FEWEST-UNPROVEN: a single-chain answer's equal-length chain with the least (unproven, route_cands, test intermediates) key
    const FewestUnprovenChain  fewest   = pp.active() ? FewestUnprovenChain{} : pathFewestUnproven( ing, g, path, srcDefs, dstDefs );
    const std::vector<NodeId>& searched = fewest.chain.empty() ? path : fewest.chain;
    const std::vector<NodeId>& found    = pathShownChain( pp, searched );
    c.verdict                           = pathRouteVerdict( ing, g, pp, found, srcDefs, dstDefs, fewest.declinedCands );
    if( !c.verdict.refused )
    {
        c.rows  = c.verdict.proven.empty() ? searched : c.verdict.proven;
        c.shown = c.verdict.proven.empty() ? found : c.verdict.proven;
    }
    if( c.verdict.refused || !c.verdict.proven.empty() )
    {
        c.verdict.declinedCands = 0;   // the declined chain is not what prints: no row, no root mark (route_cands= keeps its count)
    }
    else
    {
        c.verdict.tie      = fewest.tie;   // the shown chain replaced the plain search's: route_tie= says so
        c.verdict.tieOther = fewest.otherUnproven;
        c.verdict.tieEqual = fewest.equalCount;
        c.verdict.testHops = pathTestIntermediates( ing, c.shown );
    }
    c.bind = c.verdict.refused ? found : c.shown;
    c.from = c.bind.empty() ? srcDefs.front() : c.bind.front();
    c.to   = c.bind.empty() ? dstDefs.front() : c.bind.back();
    return c;
}

// The root attributes the verdict adds ("" when it neither hedges nor refuses). A refused answer, and a hedge of kPathRouteRefuseNameHops
// or more by-name hops (unlikely, printed), names from='s callees in next= unless the root already carries a next= (`hasNext`).
inline std::string pathRouteVerdictAttrs( const IngestResult& ing, const PathRouteVerdict& v, NodeId from, bool hasNext, bool singleRoot,
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
    std::string out = v.refused ? " route_hedged=\"not-proven\" route_len=\"" + std::to_string( v.hops ) + "\"" : std::string( v.unproven() >= kPathRouteRefuseNameHops ? " route_hedged=\"unlikely\"" : " route_hedged=\"name-stitched\"" );
    out += " route_by_name=\"" + std::to_string( v.byName ) + "\" route_cands=\"" + std::to_string( v.cands ) + "\"" + ( v.cands >= kPathRouteCandsCeiling ? " route_cands_capped=\"1\"" : "" );
    if( ( v.refused || v.unproven() >= kPathRouteRefuseNameHops ) && !hasNext && from < ing.symbols.size() )
    {
        out += nextAttrXml( nextFlag( "--callees=", pathPairSelector( ing, from, singleRoot, rootPrefix ) ) );   // shell-safe: a path with a space is quoted
    }
    return out;
}

// PATH-FEWEST-UNPROVEN's root marks ("" when none fires): route_tie= route_tie_other= (a replaced chain), route_declined= (a declined
// last hop), route_tests= (test-path intermediates).
inline std::string pathFewestRootAttrs( const PathRouteVerdict& v )
{
    static constexpr std::string_view kTieName[] = { "", "fewer-unproven", "fewer-cands", "source-first", "owner-word" };
    std::string out;
    if( v.tie != PathTie::None )
    {
        out += " route_tie=\"" + std::string( kTieName[ std::size_t( v.tie ) ] ) + "\" route_tie_other=\"" + std::to_string( v.tieOther ) + "\"";
        out += v.tieEqual > 0 ? " route_equal=\"" + std::to_string( v.tieEqual ) + "\"" : std::string();
    }
    out += v.declinedCands > 0 ? " route_declined=\"1\"" : "";
    out += v.testHops > 0 ? " route_tests=\"" + std::to_string( v.testHops ) + "\"" : std::string();
    return out;
}

inline std::string pathRouteRootAttrs( const IngestResult& ing, const PathRouteVerdict& v, NodeId from, bool hasNext, bool singleRoot,
                                       std::string_view rootPrefix )
{
    return pathRouteVerdictAttrs( ing, v, from, hasNext, singleRoot, rootPrefix ) + pathFewestRootAttrs( v );
}

// present-only (the full dialect's spelling; compactlegend.h carries the compact one). No `--` inside: it rides in an XML comment.
inline std::string_view pathRouteVerdictLegend( const PathRouteVerdict& v ) noexcept
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
    if( v.hedged && v.unproven() >= kPathRouteRefuseNameHops )
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

// PATH-FEWEST-UNPROVEN's clauses, each present only with its attribute (full dialect; compactlegend.h carries the compact rows).
inline std::string pathFewestLegend( const PathRouteVerdict& v )
{
    std::string out;
    if( v.tie != PathTie::None )
    {
        out += "route_tie=fewer-unproven|fewer-cands|source-first|owner-word route_tie_other=K: the plain search met another chain of the same length "
               "first, with K unproven hops (via=name, link, split, impl or declined rows); this one is shown instead because it has fewer unproven "
               "hops (fewer-unproven), else a smaller route_cands (fewer-cands), else fewer intermediates in test or fixture paths (source-first), "
               "else more intermediates whose name shares a word with to='s owner name (owner-word, a reading of names, not of the graph). "
               "The other chain is not printed and is no more proven than this one; the connect verb on from=,to= shows both. ";
        out += v.tieEqual > 0 ? "route_equal=N: at least N other chains of the same length are exactly as proven (same unproven hops and route_cands) "
                                "and not printed: the shown one is a pick among equals, the true route may be one of them. "
                              : "";
    }
    if( v.declinedCands > 0 )
    {
        out += "route_declined=1: the last row (via=declined cands=N) is a DECLINED call, no graph edge: the index found N in-tree candidates "
               "and chose none, and its candidate list holds the to= definition (checked by id, N at most 3); a hedge, counted as an unproven "
               "hop in route_hedged= (route_cands= includes N). ";
    }
    if( v.testHops > 0 )
    {
        out += "route_tests=N: N intermediate rows of the shown chain are definitions in a test or fixture path while neither endpoint is: "
               "test code is rarely the production route, and the true route may be another; the chain is kept, not refused. ";
    }
    return out;
}
// The route legend of an answer: the verdict's clause, then the fewest-unproven clauses ("" when nothing fires).
inline std::string pathRouteLegend( const PathRouteVerdict& v )
{
    return std::string( pathRouteVerdictLegend( v ) ) + pathFewestLegend( v );
}

}   // namespace rw
