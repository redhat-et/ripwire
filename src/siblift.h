#pragma once

// siblift.h — r4 EXPERIMENT (pre-registered: bench/locbench/results/r4_siblift/PREREG.md): slot-ladder
// same-directory sibling lift on the routed --for lens. INERT unless RIPWIRE_SIBLIFT="<seed>,<sib>"
// parses to values in range — the default binary is byte-identical with the env unset.
//
// Mechanism (why this is NOT the rejected anchor-hop): seeds are the top LEXICALLY-RANKED files (the
// query's winners, not mention anchors); the edge is same-immediate-directory siblinghood (the r2 loss
// evidence: django/forms/*, src/transformers/* package siblings — not call/import hops); placement is
// the mention boost's slot ladder (forced max() placement below #1), not additive score mass a shared
// hub can accumulate. A sibling with NO positive lexical score never lifts — the anti-noise guard the
// hop candidates lacked. #1 is never displaced: every slot value sits strictly below the current top.

#include "model.h"
#include "mention.h"   // kMentionTopGapStep / kMentionMaxSymbolsPerFile — the ONE slot-ladder vocabulary
#include <algorithm>
#include <cstdlib>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t kSibliftMaxSeed = 4;   // env values outside [1, kSibliftMax*] mean OFF, never a clamp-and-guess
inline constexpr std::size_t kSibliftMaxSib  = 4;

// parse "<seedFiles>,<sibPerSeed>" — returns (0,0) = off for anything malformed or out of range.
inline std::pair<std::size_t, std::size_t> sibliftParams()
{
    const char* env = std::getenv( "RIPWIRE_SIBLIFT" );
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
    std::size_t seed = 0, sib = 0;
    for( const char c : s.substr( 0, comma ) )
    {
        if( c < '0' || c > '9' ) { return { 0, 0 }; }
        seed = seed * 10 + std::size_t( c - '0' );
        if( seed > 99 ) { break; }
    }
    for( const char c : s.substr( comma + 1 ) )
    {
        if( c < '0' || c > '9' ) { return { 0, 0 }; }
        sib = sib * 10 + std::size_t( c - '0' );
        if( sib > 99 ) { break; }
    }
    if( seed < 1 || seed > kSibliftMaxSeed || sib < 1 || sib > kSibliftMaxSib )
    {
        return { 0, 0 };
    }
    return { seed, sib };
}

namespace siblift_detail
{
inline std::string_view dirOf( std::string_view path ) noexcept
{
    const std::size_t slash = path.rfind( '/' );
    return slash == std::string_view::npos ? std::string_view() : path.substr( 0, slash );
}
} // namespace siblift_detail

// Apply the lift to lensRank (size == ing.symbols.size()). Returns true if anything moved.
inline bool applySiblingLift( const IngestResult& ing, std::vector<float>& lensRank, std::size_t seedFiles, std::size_t sibPerSeed )
{
    using namespace siblift_detail;
    if( seedFiles == 0 || sibPerSeed == 0 || lensRank.size() != ing.symbols.size() || lensRank.empty() )
    {
        return false;
    }

    // per-file best existing score — the seed ranking AND the sibling-evidence guard read this
    const std::size_t  F = ing.files.size();
    std::vector<float> fileBest( F, 0.f );
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        fileBest[ ing.symbols[i].fileId ] = std::max( fileBest[ ing.symbols[i].fileId ], lensRank[i] );
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
    const float topScore = fileBest[ byBest[0] ];

    // choose siblings: for each of the top seedFiles files, the sibPerSeed same-dir files with the
    // highest positive existing score, excluding every seed and anything already chosen
    const std::size_t          nSeeds = std::min( seedFiles, byBest.size() );
    std::vector<std::uint32_t> lifted;
    for( std::size_t s = 0; s < nSeeds; ++s )
    {
        const std::string_view dir = dirOf( ing.files[ byBest[s] ] );
        std::size_t taken = 0;
        for( const std::uint32_t f : byBest )   // byBest order = score desc, id asc — deterministic
        {
            if( taken >= sibPerSeed )
            {
                break;
            }
            const bool isSeed = std::find( byBest.begin(), byBest.begin() + std::ptrdiff_t( nSeeds ), f )
                                != byBest.begin() + std::ptrdiff_t( nSeeds );
            if( isSeed || dirOf( ing.files[f] ) != dir
                || std::find( lifted.begin(), lifted.end(), f ) != lifted.end() )
            {
                continue;
            }
            lifted.push_back( f );
            ++taken;
        }
    }
    if( lifted.empty() )
    {
        return false;
    }

    // slot ladder — the mention boost's vocabulary: lifted file i's top symbols land at
    // top*(1 - step*(i+1)), strictly below #1; max() keeps anything already scored higher in place
    bool moved = false;
    for( std::size_t i = 0; i < lifted.size(); ++i )
    {
        const float slot = topScore * ( 1.0f - kMentionTopGapStep * float( i + 1 ) );
        std::vector<std::pair<float, NodeId>> symbols;   // (existing score, id) of the sibling's symbols
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
