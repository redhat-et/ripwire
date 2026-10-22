// SPDX-License-Identifier: Apache-2.0
#pragma once
// ── PATH-TOKEN RANK FUSION for the --for head (lane rank-fusion, train 33; IDEAS_LIST RF4) ──────────────────────────
//
// WHAT. A second, file-grain ranked list — the query's subtokens found in a file's PATH (basename stem weight 1, a
// directory component weight 1/2, each scaled by that subtoken's idf over the eligible files) — fused with the head's own
// distinct-file order by reciprocal rank (RRF, k = 60, this list's weight alpha = 0.1; no score calibration). The fused
// order decides which files r=2..8 name; r=1 stays the top score row (the head round-robin's own contract). A fused head
// file whose best row sits outside the score head brings that ONE row in (added, never swapped for another row).
//
// WHY A LIST, NOT A WEIGHT. The rank-gates C2 arm scored the basename as a BM25 weight and was killed: the boost lands on
// every symbol of a matching file (.d.ts twins, eight router.ts files) and moves rows across the whole ranking. As its own
// list fused by RANK, a path match can only reorder which files open the head, by a bounded amount: at alpha = 0.1 a file
// ranked first by path gains 0.1/61 ≈ 0.0016, about the gap between a score head's rank 1 and rank 8 (1/61 − 1/68).
//
// MEASURED (reports/rank-fusion.md §1, offline, 44-row rank-gates harness): at alpha 0.1 three of the 20 missed gold files
// enter the head-8 (tmux-02 cmd-copy-mode.c, fastify-13 handle-request.js, textual-14 screen.py), no ✓-row gold file
// leaves it, and a random list fused at the same alpha moves none. alpha 0.12 already loses a ✓ gold file: the weight
// is the measured knife-edge, kept as a constant (the twin RIPWIRE_NO_PATH_FUSION=1 restores the score head).
//
// SCOPE. Only where the head round-robin applies (serialize.h forHeadRoundRobinOn: the routed subtoken+body answer to a
// question that names no indexed file, no explicit budget or body ceiling). Only the <sigs> rows read the fused rank: the
// fold, the hops, lego/compose and the file tail keep the score order (the head round-robin's measured rule).
// Eligible files: at least one positive-score symbol, not a down-tiered path (test/bench/demo/generated), not a
// declaration twin, not prose, and not under one of kPathFusionSkipDirs (example/sample/doc trees the tiers do not hold).
// NOT: a stemmer (exact subtokens only), a language rule (the tokenizer is the BM25 one), a score change outside the
// promoted rows.

#include "docparse.h"    // docparse::lowerExtOf / isProseExtension — the ONE prose vocabulary
#include "filter.h"      // isRankTierDownPath, declarationTwinFileMultipliers, hasDirSegment
#include "lexical.h"     // subtokens — the BM25 query split, so a path word is a query word exactly as scoring reads it
#include "model.h"
#include "serialize.h"   // lensRowPath, kHeadRoundRobinRows
#include "infra/Diagnostics.h"
#include "infra/sortutil.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr double kPathFusionRrfK    = 60.0;   // RRF's k (Cormack et al.; gortex hybrid.go uses the same)
inline constexpr double kPathFusionAlpha   = 0.1;    // the path list's RRF weight; the head's own order weighs 1
inline constexpr double kPathFusionBaseW   = 1.0;    // a query subtoken in the basename stem
inline constexpr double kPathFusionDirW    = 0.5;    // …in a directory component instead
// example/sample/doc/spec/benchmark trees: neither the test/bench tier nor the demo tier lists them, and on the measured
// harness their file names (screen.py demos, router examples) are exactly what a path match would promote over the code
inline constexpr std::string_view kPathFusionSkipDirs[] = { "doc/", "docs/", "example/", "examples/", "sample/", "samples/",
                                                             "spec/", "benchmark/", "benchmarks/" };

// May the path list fuse into this head? The head round-robin's verdict, and the twin unset.
inline bool forPathFusionOn( bool headRoundRobin ) noexcept
{
    return headRoundRobin && std::getenv( "RIPWIRE_NO_PATH_FUSION" ) == nullptr;
}

struct ForPathFusion
{
    std::vector<float> rank;          // the <sigs> rank: lensRank with at most kHeadRoundRobinRows−1 rows raised
    int                topN   = 0;    // the <sigs> quota: the score head's plus the rows the fusion brought in
    std::size_t        placed = 0;    // positions r=2..8 whose file differs from the score head's file there: path_fused= (≥ 1
                                      //   whenever a fusion is returned — an unchanged head returns nullopt)
};

namespace pathfuse
{

// a path's basename stem (up to the first '.') and its directory part, root-relative
struct PathParts
{
    std::string_view stem;
    std::string_view dirs;
};
inline PathParts pathParts( std::string_view p ) noexcept
{
    const std::size_t      slash = p.rfind( '/' );
    const std::string_view base  = slash == std::string_view::npos ? p : p.substr( slash + 1 );
    const std::size_t      dot   = base.find( '.' );
    return { dot == std::string_view::npos ? base : base.substr( 0, dot ), slash == std::string_view::npos ? std::string_view() : p.substr( 0, slash ) };
}

inline bool eligiblePath( std::string_view p, float declMul )
{
    if( declMul != 1.0f || isRankTierDownPath( p ) || docparse::isProseExtension( docparse::lowerExtOf( p ) ) )
    {
        return false;
    }
    return std::ranges::none_of( kPathFusionSkipDirs, [ & ]( std::string_view seg ) { return hasDirSegment( p, seg ); } );
}

// the path list: eligible files with a positive path score, (score desc, path length asc, path asc)
inline std::vector<std::uint32_t> pathList( const std::vector<std::string>& paths, const std::vector<char>& eligible,
                                            const std::vector<std::string>& qToks )
{
    const std::size_t F = paths.size();
    // per file, per unique query subtoken: 2 = in the stem, 1 = in a directory only, 0 = absent
    std::vector<std::uint8_t>  where( F * qToks.size(), 0 );
    std::vector<std::uint32_t> df( qToks.size(), 0 );
    std::vector<std::string>   scratch;
    std::size_t                N = 0;
    for( std::size_t f = 0; f < F; ++f )
    {
        if( !eligible[f] )
        {
            continue;
        }
        ++N;
        const PathParts parts = pathParts( paths[f] );
        scratch.clear();
        subtokens( parts.stem, scratch );
        const std::size_t stemEnd = scratch.size();
        subtokens( parts.dirs, scratch );
        for( std::size_t u = 0; u < qToks.size(); ++u )
        {
            const auto hit = std::ranges::find( scratch, qToks[u] );
            if( hit == scratch.end() )
            {
                continue;
            }
            where[ f * qToks.size() + u ] = std::size_t( hit - scratch.begin() ) < stemEnd ? 2 : 1;
            ++df[u];
        }
    }
    struct Scored
    {
        double        score;
        std::uint32_t f;
    };
    std::vector<Scored> scored;
    for( std::size_t f = 0; f < F; ++f )
    {
        double s = 0.0;
        for( std::size_t u = 0; u < qToks.size(); ++u )   // fixed u order: the sum is deterministic
        {
            const std::uint8_t w = where[ f * qToks.size() + u ];
            if( w != 0 )
            {
                s += std::log( double( N ) / double( df[u] ) ) * ( w == 2 ? kPathFusionBaseW : kPathFusionDirW );
            }
        }
        if( s > 0.0 )
        {
            scored.push_back( { s, std::uint32_t( f ) } );
        }
    }
    std::ranges::sort( scored, [ & ]( const Scored& a, const Scored& b )
    {
        if( a.score != b.score ) { return a.score > b.score; }
        if( paths[a.f].size() != paths[b.f].size() ) { return paths[a.f].size() < paths[b.f].size(); }
        return paths[a.f] < paths[b.f];
    } );
    std::vector<std::uint32_t> out;
    out.reserve( scored.size() );
    for( const Scored& s : scored )
    {
        out.push_back( s.f );
    }
    return out;
}

}   // namespace pathfuse

// The fused <sigs> rank, or nullopt when the fused head names the same first 8 files as the score head (the caller then
// serves lensRank unchanged: byte-identical). `topN` is the final quota (floor and adaptive cuts applied).
inline std::optional<ForPathFusion> forPathFusion( const IngestResult& ing, const std::vector<float>& lensRank, int topN,
                                                    std::string_view task, std::string_view rootArg )
{
    const std::size_t S = std::min( ing.symbols.size(), lensRank.size() );
    const std::size_t F = ing.files.size();
    if( S == 0 || F == 0 || topN <= 0 )
    {
        return std::nullopt;
    }
    std::vector<std::string> qToks;
    subtokens( task, qToks );
    std::ranges::sort( qToks );
    qToks.erase( std::unique( qToks.begin(), qToks.end() ), qToks.end() );
    if( qToks.empty() )
    {
        return std::nullopt;
    }

    // score order (score desc, id asc) — the key packSignatures selects with
    std::vector<NodeId> order( S );
    for( NodeId i = 0; i < S; ++i )
    {
        order[i] = i;
    }
    sortutil::radixSortByScoreDescId( order, lensRank );
    std::vector<NodeId> bestOf( F, kNoNode );   // each file's best positive-score symbol
    for( const NodeId id : order )
    {
        if( !( lensRank[id] > 0.0f ) )
        {
            break;   // the zero-score tail is contiguous
        }
        const std::uint32_t f = ing.symbols[id].fileId;
        if( f < F && bestOf[f] == kNoNode )
        {
            bestOf[f] = id;
        }
    }

    // A: the score head's distinct files in score order, over the quota's rows; prose files after code (the docs reorder)
    std::vector<std::string> paths( F );
    for( std::uint32_t f = 0; f < F; ++f )
    {
        paths[f] = lensRowPath( ing, f, rootArg );
    }
    std::vector<std::uint32_t> headA, proseA;
    std::vector<char>          inA( F, 0 );
    for( std::size_t k = 0; k < order.size() && k < std::size_t( topN ); ++k )
    {
        const std::uint32_t f = ing.symbols[ order[k] ].fileId;
        if( f >= F || inA[f] )
        {
            continue;
        }
        inA[f] = 1;
        ( docparse::isIndexedDocExtension( docparse::lowerExtOf( paths[f] ) ) ? proseA : headA ).push_back( f );
    }
    headA.insert( headA.end(), proseA.begin(), proseA.end() );
    if( headA.empty() )
    {
        return std::nullopt;
    }

    // D: the path list over the eligible files
    const std::vector<float> declMul = declarationTwinFileMultipliers( ing );
    std::vector<char>        eligible( F, 0 );
    for( std::uint32_t f = 0; f < F; ++f )
    {
        eligible[f] = bestOf[f] != kNoNode && pathfuse::eligiblePath( paths[f], f < declMul.size() ? declMul[f] : 1.0f ) ? 1 : 0;
    }
    const std::vector<std::uint32_t> listD = pathfuse::pathList( paths, eligible, qToks );
    if( listD.empty() )
    {
        return std::nullopt;
    }

    // RRF: 1/(k+rA) + alpha/(k+rD), ties by path; r=1 pinned to the score head's first file
    std::vector<double> fused( F, 0.0 );
    std::vector<char>   any( F, 0 );
    for( std::size_t r = 0; r < headA.size(); ++r )
    {
        fused[ headA[r] ] += 1.0 / ( kPathFusionRrfK + double( r + 1 ) );
        any[ headA[r] ] = 1;
    }
    for( std::size_t r = 0; r < listD.size(); ++r )
    {
        fused[ listD[r] ] += kPathFusionAlpha / ( kPathFusionRrfK + double( r + 1 ) );
        any[ listD[r] ] = 1;
    }
    std::vector<std::uint32_t> cand;
    for( std::uint32_t f = 0; f < F; ++f )
    {
        if( any[f] && f != headA.front() )
        {
            cand.push_back( f );
        }
    }
    std::ranges::sort( cand, [ & ]( std::uint32_t a, std::uint32_t b )
    {
        if( fused[a] != fused[b] ) { return fused[a] > fused[b]; }
        return paths[a] < paths[b];
    } );
    std::vector<std::uint32_t> head{ headA.front() };
    for( std::size_t i = 0; i < cand.size() && head.size() < kHeadRoundRobinRows; ++i )
    {
        head.push_back( cand[i] );
    }
    const std::size_t cmpN = std::min( head.size(), headA.size() );
    if( head.size() == std::min( headA.size(), kHeadRoundRobinRows ) && std::equal( head.begin(), head.begin() + std::ptrdiff_t( cmpN ), headA.begin() ) )
    {
        return std::nullopt;   // same files, same order: the score head stands
    }

    // promote each fused head file's best row (j = 2..8) just above every row of a file outside the head, in fused order
    std::vector<char> inHead( F, 0 );
    for( const std::uint32_t f : head )
    {
        inHead[f] = 1;
    }
    float outsideMax = -std::numeric_limits<float>::infinity();
    for( std::size_t i = 0; i < S; ++i )
    {
        const std::uint32_t f = ing.symbols[i].fileId;
        if( f < F && !inHead[f] )
        {
            outsideMax = std::max( outsideMax, lensRank[i] );
        }
    }
    const NodeId pin = bestOf[ headA.front() ];   // the score head's r=1 row (its first file's best; a prose top row reorders below code)
    if( pin == kNoNode )
    {
        return std::nullopt;
    }
    // …and above the quota's last row, so a row brought in from outside the quota enters the <sigs> selection (top-N by rank)
    // without pushing any quota row out: the selection becomes the old quota plus the rows brought in
    const float quotaMin = lensRank[ order[ std::min( order.size(), std::size_t( topN ) ) - 1 ] ];
    ForPathFusion out;
    out.rank = lensRank;
    float floorScore = std::max( outsideMax, quotaMin );
    for( std::size_t j = head.size(); j-- > 1; )
    {
        const NodeId b = bestOf[ head[j] ];
        if( b == kNoNode )
        {
            return std::nullopt;   // a head file with no positive row: nothing to place — keep the score head
        }
        const float t = std::max( lensRank[b], std::nextafter( floorScore, std::numeric_limits<float>::infinity() ) );
        out.rank[b]   = t;
        floorScore    = t;
    }
    if( !( floorScore < lensRank[pin] ) )
    {
        return std::nullopt;   // no room below r=1 (a tie at the top): the pin wins, the score head stands
    }
    std::vector<char> inQuota( S, 0 );
    for( std::size_t k = 0; k < order.size() && k < std::size_t( topN ); ++k )
    {
        inQuota[ order[k] ] = 1;
    }
    int added = 0;
    for( std::size_t j = 1; j < head.size(); ++j )
    {
        added += inQuota[ bestOf[ head[j] ] ] ? 0 : 1;
        out.placed += ( j >= headA.size() || headA[j] != head[j] ) ? 1u : 0u;
    }
    out.topN = topN + added;
    ENSURES( out.placed > 0, "a returned fusion moved at least one head file (an unchanged head returned nullopt above)" );
    ENSURES( out.rank[pin] == lensRank[pin], "r=1 is never raised: the pin" );
    return out;
}

}   // namespace rw
