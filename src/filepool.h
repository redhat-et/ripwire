#pragma once

// filepool.h — r5 EXPERIMENT (pre-registered: bench/locbench/results/r5_pooling/PREREG.md): file-level
// evidence POOLING on the routed --for lens. INERT unless RIPWIRE_POOL="<K>,<blend*100>" parses to
// values in range — the default binary is byte-identical with the env unset.
//
// Mechanism (why this is NOT the rejected siblift). siblift PICKED A NEIGHBOUR and moved it, and its
// post-mortem found the chooser was the weak link: "score-adjacent is not gold-adjacent". This
// candidate chooses nothing. A file's rank today is set by its single best symbol — a max-pool, which
// cannot tell ONE STRONG HIT from FIVE MODERATE ONES. Multi-file gold sets are predicted to be the
// second kind (django/forms/{fields,forms,renderers}.py). Pooling re-summarises every file in the
// corpus by the same rule, so there is no neighbour selection that can be wrong.
//
// The ladder only ever RAISES: placement is max( slot, existing ), so a file already ranked above its
// slot is untouched and #1 is never displaced. That monotonicity is what bounds the blast radius of a
// wrong pooled score to "a file appears earlier than it deserves", never "a correct file is pushed
// down by a competitor's boost".

#include "model.h"
#include "mention.h"   // kMentionTopGapStep / kMentionMaxSymbolsPerFile — the ONE slot-ladder vocabulary
#include <algorithm>
#include <cstdlib>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t kPoolMaxTopK    = 32;   // env values outside range mean OFF, never a clamp-and-guess
inline constexpr std::size_t kPoolLiftFiles  = 10;   // FIXED, not a grid axis: the @10 window is what this targets

// parse "<topK>,<blendPercent>" — returns (0,0) = off for anything malformed or out of range.
// blend==0 is LEGAL and is the identity control the PREREG requires: it must reproduce baseline exactly.
inline std::pair<std::size_t, std::size_t> filePoolParams()
{
    const char* env = std::getenv( "RIPWIRE_POOL" );
    if( !env )
    {
        return { 0, 0 };
    }
    const std::string_view s( env );
    const std::size_t comma = s.find( ',' );
    if( comma == std::string_view::npos || comma == 0 || comma + 1 >= s.size() )
    {
        return { 0, 0 };
    }
    std::size_t topK = 0, blend = 0;
    for( const char c : s.substr( 0, comma ) )
    {
        if( c < '0' || c > '9' ) { return { 0, 0 }; }
        topK = topK * 10 + std::size_t( c - '0' );
        if( topK > kPoolMaxTopK ) { return { 0, 0 }; }
    }
    for( const char c : s.substr( comma + 1 ) )
    {
        if( c < '0' || c > '9' ) { return { 0, 0 }; }
        blend = blend * 10 + std::size_t( c - '0' );
        if( blend > 100 ) { return { 0, 0 }; }
    }
    if( topK == 0 ) { return { 0, 0 }; }
    return { topK, blend };
}

// Apply pooling to lensRank (size == ing.symbols.size()). Returns true if anything moved.
inline bool applyFilePooling( const IngestResult& ing, std::vector<float>& lensRank, std::size_t topK, std::size_t blendPct )
{
    if( topK == 0 || lensRank.size() != ing.symbols.size() || lensRank.empty() )
    {
        return false;
    }

    // Gather each file's POSITIVE symbol scores. A non-positive symbol contributes nothing and a file
    // with no positive symbol is never placed — the one part of siblift not implicated in its failure.
    const std::size_t                 F = ing.files.size();
    std::vector<std::vector<float>>   perFile( F );
    for( std::size_t i = 0; i < lensRank.size(); ++i )
    {
        if( lensRank[i] > 0.f )
        {
            perFile[ ing.symbols[i].fileId ].push_back( lensRank[i] );
        }
    }

    std::vector<float> fileBest( F, 0.f );   // today's max-pool
    std::vector<float> pooled  ( F, 0.f );   // sum of the top-K
    float              bestMax = 0.f, bestPooled = 0.f;
    for( std::uint32_t f = 0; f < F; ++f )
    {
        std::vector<float>& v = perFile[f];
        if( v.empty() )
        {
            continue;
        }
        std::sort( v.begin(), v.end(), std::greater<float>() );
        fileBest[f] = v[0];
        const std::size_t take = std::min( topK, v.size() );
        for( std::size_t k = 0; k < take; ++k )
        {
            pooled[f] += v[k];
        }
        bestMax    = std::max( bestMax,    fileBest[f] );
        bestPooled = std::max( bestPooled, pooled[f] );
    }
    if( bestMax <= 0.f || bestPooled <= 0.f )
    {
        return false;
    }

    // Put the pooled score on the SAME SCALE as the max-pool before blending, so blend is a pure
    // interpolation between two comparable rankings and not a silent change of units.
    const float scale = bestMax / bestPooled;
    const float blend = float( blendPct ) / 100.0f;

    std::vector<std::uint32_t> order;
    std::vector<float>         effective( F, 0.f );
    for( std::uint32_t f = 0; f < F; ++f )
    {
        if( fileBest[f] <= 0.f )
        {
            continue;
        }
        effective[f] = ( 1.0f - blend ) * fileBest[f] + blend * ( pooled[f] * scale );
        order.push_back( f );
    }
    if( order.empty() )
    {
        return false;
    }
    // Baseline order (today's max-pool) and pooled order, so a file can be placed ONLY IF pooling
    // PROMOTES it. This is what makes blend=0 a true identity: with blend=0 the two orders are equal,
    // nothing is promoted, and the binary is byte-identical to baseline — which the PREREG requires as
    // the harness's own control. It also bounds the mechanism to the files the hypothesis is about
    // (under-ranked by max-pool), instead of re-slotting the whole top of the list.
    std::vector<std::uint32_t> baseOrder = order;
    std::sort( baseOrder.begin(), baseOrder.end(), [ & ]( const std::uint32_t a, const std::uint32_t b )
               { return fileBest[a] != fileBest[b] ? fileBest[a] > fileBest[b] : a < b; } );
    std::vector<std::size_t> baseRank( F, ~std::size_t( 0 ) );
    for( std::size_t i = 0; i < baseOrder.size(); ++i )
    {
        baseRank[ baseOrder[i] ] = i;
    }

    std::sort( order.begin(), order.end(), [ & ]( const std::uint32_t a, const std::uint32_t b )
               { return effective[a] != effective[b] ? effective[a] > effective[b] : a < b; } );

    // Slot ladder, mention-boost vocabulary: the i-th pooled file's top symbols land at
    // top*(1 - step*(i+1)), strictly below #1. max() keeps anything already scored higher in place, so
    // this is monotone non-decreasing on every symbol it touches.
    const float topScore = fileBest[ baseOrder[0] ];
    bool        moved    = false;
    const std::size_t nLift = std::min( kPoolLiftFiles, order.size() );
    for( std::size_t i = 0; i < nLift; ++i )
    {
        if( baseRank[ order[i] ] <= i )
        {
            continue;   // pooling did not promote this file — leave it exactly where the baseline put it
        }
        const float slot = topScore * ( 1.0f - kMentionTopGapStep * float( i + 1 ) );
        if( slot <= 0.f )
        {
            break;
        }
        std::vector<std::pair<float, NodeId>> symbols;
        for( std::size_t k = 0; k < ing.symbols.size(); ++k )
        {
            if( ing.symbols[k].fileId == order[i] && lensRank[k] > 0.f )
            {
                symbols.emplace_back( lensRank[k], NodeId( k ) );
            }
        }
        std::sort( symbols.begin(), symbols.end(), []( const auto& a, const auto& b )
                   { return a.first != b.first ? a.first > b.first : a.second < b.second; } );
        for( std::size_t k = 0; k < symbols.size() && k < kMentionMaxSymbolsPerFile; ++k )
        {
            if( slot > lensRank[ symbols[k].second ] )
            {
                lensRank[ symbols[k].second ] = slot;
                moved = true;
            }
        }
    }
    return moved;
}

} // namespace rw
