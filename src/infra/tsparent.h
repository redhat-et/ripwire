#pragma once
// tsparent.h — ts_node_parent's exact answer without a descent from the root per step.
//
// WHY THIS EXISTS. tree-sitter nodes hold no parent pointer: the vendored ts_node_parent (third_party/deps/tree_sitter/
// lib/src/node.c:547) walks DOWN from the tree root, scanning each level's children for the one holding the node. One
// parent costs a whole descent, and a climb of k ancestors costs k of them, each re-scanning the same wide levels (a flat
// Go file scope, a C++ namespace, a class body). Stage 0 of the parent-carry lane (reports/s0-parent-carry-1110.md in the
// orchestration notes) measured ts_node_parent at 7.8-16 % of a cold run in Go, Rust, C++, Python and the TS residual, 98 %
// of it in that sibling scan, nearly all from climbs of a few steps over the same node's ancestors.
//
// WHAT IT DOES. parentOf( n ) answers from a per-file cache of ONE root-descent path (AncestorCache::chain: the root first,
// each entry the parent of the next). A node on the chain answers in a lookup; any other non-empty node of the same tree
// descends from the DEEPEST chain entry whose byte range holds it, instead of from the root, and the chain becomes the
// path to that node. Outside an AncestorCacheScope, for another tree, or for a zero-width node, it is ts_node_parent.
//
// WHY THE ANSWER IS ts_node_parent's. The descent ts_node_child_with_descendant takes towards a NON-EMPTY node d picks, at
// each level, the first relevant child that is not a leaf and ends at or past d's end. A chain entry A_j that holds d's
// range sits on that same path: every child before the chain's A_i at a level ends at or before A_i's start, so at or
// before d's start, so before d's end, and is skipped exactly as it was for the chain's own target; A_i itself ends past
// d's end. So the root's descent to d passes through A_1..A_j, and resuming it at A_j changes nothing but its cost. A
// zero-width d (a MISSING token) takes tree-sitter's separate empty-descendant branch, which may choose differently, so it
// never touches the chain. The cache only reads a scope's own tree, which outlives the scope: a re-parse tree freed and
// reallocated inside the scope cannot share the live tree's address, so no entry can dangle.
//
// VERIFY BUILD. -DRIPWIRE_VERIFY_PARENT_CACHE (e.g. CMAKE_CXX_FLAGS) makes every parentOf also call ts_node_parent and
// DASSERT that both are the same node (id, tree and the position/alias context), and prints the number of answers it
// checked at exit. It is how the lane proved the rule above per grammar on the measured repos; it is never a shipped mode.
//
// noexcept by construction: the chain's capacity is reserved once per scope and never grown; a path deeper than that keeps
// its first kChainCapacity entries (still a root-descent prefix, still exact) and the rest is descended without caching.

#include <cstddef>
#include <cstdint>
#include <vector>

#include <tree_sitter/api.h>

#if defined( RIPWIRE_VERIFY_PARENT_CACHE )
#include <atomic>
#include <cstdio>
#include <cstring>
#include "Diagnostics.h"
#include "emit.h"
#endif

namespace rw
{

struct AncestorCache
{
    static constexpr std::size_t kChainCapacity = 512;   // deeper than any real file's nesting but the adversarial ones

    const TSTree*       tree = nullptr;   // the scope's tree; the only one the chain describes
    std::vector<TSNode> chain;            // a root-descent path: chain[0] is the root, chain[i-1] is chain[i]'s parent
    std::size_t         next = 0;         // the entry the next question most likely names: the last answer's (a climb's next step)
};

// the cache the current file's capture installed (null outside one: parentOf is then ts_node_parent)
inline thread_local AncestorCache* tAncestorCache = nullptr;

namespace detail
{
inline bool tsRangeHolds( TSNode outer, std::uint32_t start, std::uint32_t end ) noexcept
{
    return ts_node_start_byte( outer ) <= start && end <= ts_node_end_byte( outer );
}

inline TSNode cachedParentOf( AncestorCache& cache, TSNode n ) noexcept
{
    std::vector<TSNode>& chain = cache.chain;
    const auto answerAt = [ & ]( std::size_t i ) noexcept
    {   cache.next = i == 0 ? 0 : i - 1;
        return i == 0 ? TSNode{} : chain[ i - 1 ]; };
    if( cache.next < chain.size() && ts_node_eq( chain[ cache.next ], n ) )
    {
        return answerAt( cache.next );   // a climb: O(1) per step instead of a scan of the chain per step
    }
    for( std::size_t i = chain.size(); i-- > 0; )
    {
        if( ts_node_eq( chain[ i ], n ) )
        {
            return answerAt( i );
        }
    }
    const std::uint32_t start = ts_node_start_byte( n );
    const std::uint32_t end   = ts_node_end_byte( n );
    if( start == end )
    {
        return ts_node_parent( n );   // the empty-descendant branch: see the header note
    }
    std::size_t keep = chain.size();
    while( keep > 0 && !tsRangeHolds( chain[ keep - 1 ], start, end ) )
    {
        --keep;
    }
    if( keep == 0 )
    {
        const TSNode root = ts_tree_root_node( n.tree );
        if( ts_node_eq( root, n ) )
        {
            return TSNode{};
        }
        chain.clear();
        chain.push_back( root );   // the root holds every node of its tree, so the loop below never meets keep == 0 again
        keep = 1;
    }
    chain.resize( keep );
    TSNode node = chain.back();
    while( true )
    {
        const TSNode next = ts_node_child_with_descendant( node, n );
        if( ts_node_is_null( next ) || next.id == n.id )
        {
            break;   // ts_node_parent's own stop: the node reached, or no child holds it (then the deepest node met answers)
        }
        node = next;
        if( chain.size() < AncestorCache::kChainCapacity )
        {
            chain.push_back( node );
        }
    }
    if( ts_node_eq( chain.back(), node ) && chain.size() < AncestorCache::kChainCapacity )
    {
        chain.push_back( n );   // n itself, so its own parent and the climb above it answer from the chain
    }
    cache.next = chain.empty() ? 0 : chain.size() - ( ts_node_eq( chain.back(), n ) ? 2 : 1 );   // the parent's entry, when cached
    return node;
}

#if defined( RIPWIRE_VERIFY_PARENT_CACHE )
struct ParentCacheVerifyCount
{
    std::atomic<std::uint64_t> checked{ 0 };
    ~ParentCacheVerifyCount() { rw::emitTo( stderr, "parent-cache verify: {} answers checked\n", checked.load() ); }   // dev-only probe
};
inline ParentCacheVerifyCount gParentCacheVerifyCount;
#endif
}   // namespace detail

// ts_node_parent( n ), answered from the installed cache when it can be (see the header note)
inline TSNode parentOf( TSNode n ) noexcept
{
    AncestorCache* const cache  = tAncestorCache;
    const TSNode         parent = cache != nullptr && n.tree == cache->tree && !ts_node_is_null( n ) ? detail::cachedParentOf( *cache, n ) : ts_node_parent( n );
#if defined( RIPWIRE_VERIFY_PARENT_CACHE )
    const TSNode truth = ts_node_parent( n );
    DASSERT( std::memcmp( &truth, &parent, sizeof( TSNode ) ) == 0, "parentOf disagrees with ts_node_parent" );
    detail::gParentCacheVerifyCount.checked.fetch_add( 1, std::memory_order_relaxed );
#endif
    return parent;
}

// Installs a cache for `root`'s tree for one file's capture, and restores whatever was installed before on every exit path.
// `root`'s tree must outlive the scope (the capture functions receive it alive and free it after they return).
struct AncestorCacheScope
{
    AncestorCache  cache;
    AncestorCache* previous;
    explicit AncestorCacheScope( TSNode root ) : previous( tAncestorCache )
    {
        cache.tree = root.tree;
        cache.chain.reserve( AncestorCache::kChainCapacity );
        tAncestorCache = &cache;
    }
    AncestorCacheScope( const AncestorCacheScope& )            = delete;
    AncestorCacheScope& operator=( const AncestorCacheScope& ) = delete;
    ~AncestorCacheScope() { tAncestorCache = previous; }
};

}   // namespace rw
