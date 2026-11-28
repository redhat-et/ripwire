#pragma once
// rankcache.h — the graph's plain PageRank, served instead of recomputed (RANK-SPEED step 1).
//
// rankGraph( g ) — uniform teleport, alpha 0.85 — is a pure function of four Graph fields: the in-edge CSR, the weighted
// out-degrees, the name-quality prior weights and the count of unranked units (graph.h rankGraphTeleport / rankGraph). Nothing
// about a query reaches it. TAIL-SYM-TERMS' tie-break (forpage.h tailTermTieRank) asked for it once per --for render anyway,
// and a served --for renders more than once (a routed answer's carried page re-renders the lens), so every call paid the whole
// power iteration: 0.88 s of a 1.45 s lens pass on vscode, served (M2, RIPWIRE_PROFILE build, 2026-11-26).
//
// Two sources, both of them the bits rankGraph( g ) returns, never an approximation:
//   1. the warm snapshot's stored default rank (warmsnap_graph.h storedDefaultRank): readGraph sets it beside the graph it
//      loaded, buildGraphRecorded beside the graph it built — rankGraph( g ) of exactly that graph, written by the run that
//      recorded it. It is PEEKED here, never taken: the default map's own reader (warmsnap::defaultRank) still finds it.
//      The size test is the one defaultRank applies.
//   2. else one computed rank per graph CONTENT, remembered for the life of the process: the key is a hash of the four
//      inputs above, so a graph rebuilt in place (the MCP server's index after an edit) misses and recomputes rather than
//      reading a stale rank by address. The hash reads each input once — a small fraction of one power iteration's reads,
//      and the iteration runs 28-52 of them (pagerank.cpp).
//
// Determinism: both sources hand back the vector rankGraph( g ) computes on this graph, bit for bit; pagerank.cpp's fixed
// reduction blocks make that vector a function of the inputs alone. fire321 + the served-output md5 arms check it.

#include "graph.h"
#include "warmsnap_graph.h"   // storedDefaultRank — the warm snapshot's rankGraph( g ), stored beside the graph it ranks
#include "unordered_dense.h"  // ankerl::unordered_dense::detail::wyhash::hash — the content key

#include <cstdint>
#include <mutex>
#include <vector>

namespace rw
{

namespace rankcache_detail
{

// The content key of rankGraph's inputs: every array it reads, and the two sizes that shape them.
inline std::uint64_t plainRankInputsKey( const Graph& g ) noexcept
{
    using ankerl::unordered_dense::detail::wyhash::hash;
    const sparseCsr<float>& in  = g.inEdges;
    const std::size_t       N   = g.wOutDeg.size();
    std::uint64_t           key = hash( std::uint64_t( N ) ) ^ hash( std::uint64_t( in.nnz() ) * 31u + g.unrankedNodeCount );
    const auto absorb = [ &key ]( const void* p, std::size_t bytes ) noexcept
    {
        key = hash( key ^ ( bytes == 0 || p == nullptr ? 0u : hash( p, bytes ) ) );
    };
    absorb( in.rowOffsets(), in.rowOffsets() == nullptr ? 0 : ( in.rows() + 1 ) * sizeof( std::uint32_t ) );
    absorb( in.colIndices(), in.nnz() * sizeof( std::uint32_t ) );
    absorb( in.values(), in.nnz() * sizeof( float ) );
    absorb( g.wOutDeg.data(), N * sizeof( double ) );
    absorb( g.priorWeight.data(), g.priorWeight.size() * sizeof( float ) );
    return key;
}

struct PlainRankMemo
{
    std::mutex         lock;
    bool               held = false;
    std::uint64_t      key  = 0;
    std::vector<float> rank;
};
inline PlainRankMemo& plainRankMemo() noexcept
{
    static PlainRankMemo memo;
    return memo;
}

}   // namespace rankcache_detail

// rankGraph( g ).rank, from the warm snapshot when it stored this graph's, else computed at most once per graph content.
inline std::vector<float> plainGraphRank( const Graph& g )
{
    if( const std::optional<RankedGraph>& stored = warmsnap::storedDefaultRank(); stored && stored->rank.size() == g.wOutDeg.size() )
    {
        return stored->rank;
    }
    rankcache_detail::PlainRankMemo& memo = rankcache_detail::plainRankMemo();
    const std::uint64_t              key  = rankcache_detail::plainRankInputsKey( g );
    {
        const std::lock_guard<std::mutex> held( memo.lock );
        if( memo.held && memo.key == key && memo.rank.size() == g.wOutDeg.size() )
        {
            return memo.rank;
        }
    }
    std::vector<float> rank = std::move( rankGraph( g ).rank );
    const std::lock_guard<std::mutex> held( memo.lock );
    memo.held = true;
    memo.key  = key;
    memo.rank = rank;
    return rank;
}

}   // namespace rw
