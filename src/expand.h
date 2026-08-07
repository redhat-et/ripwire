#pragma once

// expand.h — r6 EXPERIMENT (pre-registered: bench/locbench/results/r6_expansion/PREREG.md): structural
// expansion from a CONFIRMED TOP-RANKED FILE on the routed --for lens. INERT unless
// RIPWIRE_EXPAND="<S>,<N>" parses to values in range — the default binary is byte-identical unset.
//
// WHY THIS COMBINATION AND NOT THE FOUR THAT FAILED. Four pre-registered rounds have been rejected at
// +-0.00pp against the multi-file stratum:
//
//   r1_anchorhop / r1cpp_anchorhop   seed = mention anchors     edge = call/import    rejected
//   r4_siblift                       seed = top-ranked files    edge = same directory rejected
//   r5_pooling                       no seed, no edge (re-summarised every file)      rejected
//
// siblift had the right SEED and the wrong EDGE; anchorhop had the right EDGE and the wrong SEED. This
// is the untried diagonal: seed from the files the ranker already placed at the top, walk RESOLVED
// import/reference edges. r5's verdict narrowed the diagnosis to "all four re-weight evidence the query
// already produced, and for these siblings the query produced none" — expansion is the first candidate
// that introduces evidence from the CODE rather than from the issue text.
//
// The edge is buildPreciseIncludeAdj's, i.e. path-precise include/import resolution — deliberately NOT
// the permissive text match the feasibility probe used. That probe found the edge present for 70% of
// targets and its own write-up records that as an UPPER bound; counting a text match here would be the
// exact self-deception the PREREG forbids.

#include "model.h"
#include "resolve.h"   // buildPreciseIncludeAdj — resolved file->file edges, not basename guesses
#include "mention.h"   // kMentionTopGapStep / kMentionMaxSymbolsPerFile — the ONE slot-ladder vocabulary
#include <algorithm>
#include <cstdlib>
#include <vector>

namespace rw
{

inline constexpr std::size_t kExpandMaxSeeds = 8;   // out-of-range env means OFF, never a clamp-and-guess
inline constexpr std::size_t kExpandMaxPer   = 8;

// parse "<seedFiles>,<neighboursPerSeed>" — (0,0) = off for anything malformed or out of range.
inline std::pair<std::size_t, std::size_t> expandParams()
{
    const char* env = std::getenv( "RIPWIRE_EXPAND" );
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
    std::size_t seeds = 0, per = 0;
    for( const char c : s.substr( 0, comma ) )
    {
        if( c < '0' || c > '9' ) { return { 0, 0 }; }
        seeds = seeds * 10 + std::size_t( c - '0' );
        if( seeds > kExpandMaxSeeds ) { return { 0, 0 }; }
    }
    for( const char c : s.substr( comma + 1 ) )
    {
        if( c < '0' || c > '9' ) { return { 0, 0 }; }
        per = per * 10 + std::size_t( c - '0' );
        if( per > kExpandMaxPer ) { return { 0, 0 }; }
    }
    if( seeds == 0 || per == 0 ) { return { 0, 0 }; }
    return { seeds, per };
}

// Apply structural expansion to lensRank (size == ing.symbols.size()). Returns true if anything moved.
inline bool applyStructuralExpansion( const IngestResult& ing, std::vector<float>& lensRank,
                                      std::size_t seedFiles, std::size_t perSeed )
{
    if( seedFiles == 0 || perSeed == 0 || lensRank.size() != ing.symbols.size() || lensRank.empty() )
    {
        return false;
    }

    const std::size_t  F = ing.files.size();
    std::vector<float> fileBest( F, 0.f );
    for( std::size_t i = 0; i < lensRank.size(); ++i )
    {
        if( lensRank[i] > 0.f )
        {
            fileBest[ ing.symbols[i].fileId ] = std::max( fileBest[ ing.symbols[i].fileId ], lensRank[i] );
        }
    }
    std::vector<std::uint32_t> byBest;
    for( std::uint32_t f = 0; f < F; ++f )
    {
        if( fileBest[f] > 0.f )
        {
            byBest.push_back( f );
        }
    }
    if( byBest.empty() )
    {
        return false;
    }
    std::sort( byBest.begin(), byBest.end(), [ & ]( const std::uint32_t a, const std::uint32_t b )
               { return fileBest[a] != fileBest[b] ? fileBest[a] > fileBest[b] : a < b; } );

    // Resolved include/import adjacency, and its reverse: a sibling is as often the file that IMPORTS
    // the primary as the one it imports (the change flows both ways along a contract).
    const std::vector<std::vector<std::uint32_t>> adj = buildPreciseIncludeAdj( ing );
    std::vector<std::vector<std::uint32_t>>       rev( F );
    for( std::uint32_t f = 0; f < F && f < adj.size(); ++f )
    {
        for( const std::uint32_t to : adj[f] )
        {
            if( to < F )
            {
                rev[ to ].push_back( f );
            }
        }
    }

    const std::size_t nSeeds = std::min( seedFiles, byBest.size() );
    std::vector<char> isSeed( F, 0 );
    for( std::size_t s = 0; s < nSeeds; ++s )
    {
        isSeed[ byBest[s] ] = 1;
    }

    // Collect neighbours in a DETERMINISTIC order: seed rank, then the two edge directions, then file id.
    std::vector<std::uint32_t> lifted;
    std::vector<char>          taken( F, 0 );
    for( std::size_t s = 0; s < nSeeds; ++s )
    {
        const std::uint32_t seed = byBest[s];
        std::vector<std::uint32_t> cand;
        if( seed < adj.size() ) { cand.insert( cand.end(), adj[seed].begin(), adj[seed].end() ); }
        cand.insert( cand.end(), rev[seed].begin(), rev[seed].end() );
        std::sort( cand.begin(), cand.end() );
        cand.erase( std::unique( cand.begin(), cand.end() ), cand.end() );

        // Anti-noise guard, the one part of siblift NOT implicated in its failure: a neighbour with no
        // positive lexical score is never lifted. A structural edge alone is not evidence of relevance.
        std::vector<std::pair<float, std::uint32_t>> scored;
        for( const std::uint32_t c : cand )
        {
            if( c < F && !isSeed[c] && !taken[c] && fileBest[c] > 0.f )
            {
                scored.emplace_back( fileBest[c], c );
            }
        }
        std::sort( scored.begin(), scored.end(), []( const auto& a, const auto& b )
                   { return a.first != b.first ? a.first > b.first : a.second < b.second; } );
        for( std::size_t k = 0; k < scored.size() && k < perSeed; ++k )
        {
            taken[ scored[k].second ] = 1;
            lifted.push_back( scored[k].second );
        }
    }
    if( lifted.empty() )
    {
        return false;
    }

    // Slot ladder, mention-boost vocabulary. max() placement ⇒ monotone non-decreasing, #1 never displaced.
    const float topScore = fileBest[ byBest[0] ];
    bool        moved    = false;
    for( std::size_t i = 0; i < lifted.size(); ++i )
    {
        const float slot = topScore * ( 1.0f - kMentionTopGapStep * float( i + 1 ) );
        if( slot <= 0.f )
        {
            break;
        }
        std::vector<std::pair<float, NodeId>> symbols;
        for( std::size_t k = 0; k < ing.symbols.size(); ++k )
        {
            if( ing.symbols[k].fileId == lifted[i] && lensRank[k] > 0.f )
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
