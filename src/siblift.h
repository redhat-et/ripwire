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
#include "infra/emit.h"          // rw::emitTo — a malformed/out-of-range RIPWIRE_SIBLIFT is REPORTED on stderr in every build flavour: a rejected user value is config feedback, not a degrade path (DEGRADED_PATH_ALERT compiles out under NDEBUG, so a Release binary would have gone silent again)
#include <algorithm>
#include <cstdlib>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t kSibliftMaxSeed = 4;   // env values outside [1, kSibliftMax*] mean OFF, never a clamp-and-guess
inline constexpr std::size_t kSibliftMaxSib  = 4;

// The parse, unchanged in every numeric outcome — split out so sibliftParams() (below) can tell "env
// unset" (silent — this feature has no default) apart from "env SET but rejected" (a config problem,
// disclosed). The grammar itself is mention.h's parseCappedCsvPair, shared with expand.h/filepool.h.
inline std::pair<std::size_t, std::size_t> sibliftParamsParse( std::string_view s )
{
    const auto [ seed, sib ] = parseCappedCsvPair( s, kSibliftMaxSeed, kSibliftMaxSib );
    if( seed < 1 || sib < 1 ) { return { 0, 0 }; }
    return { seed, sib };
}

// parse "<seedFiles>,<sibPerSeed>" — returns (0,0) = off for anything malformed or out of range. The
// defect this closes: an env value that fails to parse used to return (0,0) exactly like the env being
// unset, so a typo'd RIPWIRE_SIBLIFT silently ran the tool with NO lift and no way to tell that apart
// from "the lift was never asked for". Env SET + rejected is a recoverable config problem (CONTRIBUTING
// §3's degrade shape: clamp/fall back and say so), not the unset case, which stays wordless on purpose —
// this experiment has no on-by-default behavior to be silent ABOUT.
inline std::pair<std::size_t, std::size_t> sibliftParams()
{
    const char* env = std::getenv( "RIPWIRE_SIBLIFT" );
    if( !env )
    {
        return { 0, 0 };
    }
    const auto [ seed, sib ] = sibliftParamsParse( std::string_view( env ) );
    if( seed == 0 || sib == 0 )
    {
        rw::emitTo( stderr, "ripwire: RIPWIRE_SIBLIFT is set but malformed or out of range (want \"<seedFiles 1-4>,<sibPerSeed 1-4>\") — sibling lift OFF\n" );
    }
    return { seed, sib };
}

// What a successful lift actually moved — populated only when applySiblingLift returns true, so a caller
// can disclose the fact (never a total equal to the shown count; absence means the lift was never asked
// for, or asked for and moved nothing).
struct SibliftLiftInfo
{
    std::uint32_t fileCount   = 0;   // sibling files with at least one symbol actually promoted
    std::uint32_t symbolCount = 0;   // symbols whose score actually rose
};

namespace siblift_detail
{
inline std::string_view dirOf( std::string_view path ) noexcept
{
    const std::size_t slash = path.rfind( '/' );
    return slash == std::string_view::npos ? std::string_view() : path.substr( 0, slash );
}
} // namespace siblift_detail

// Apply the lift to lensRank (size == ing.symbols.size()). Returns true if anything moved; `info`, when
// non-null, is populated with what moved so the caller can disclose it (absent unless the lift actually
// promoted something — a lift that fired but changed nothing costs zero disclosure bytes).
inline bool applySiblingLift( const IngestResult& ing, std::vector<float>& lensRank, std::size_t seedFiles, std::size_t sibPerSeed,
                              SibliftLiftInfo* info = nullptr )
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
        const float          slot     = topScore * ( 1.0f - kMentionTopGapStep * float( i + 1 ) );
        const std::uint32_t  promoted = promoteFileSymbolsToSlot( ing, lensRank, lifted[i], slot );
        if( promoted > 0 )
        {
            moved = true;
            if( info )
            {
                info->symbolCount += promoted;
                ++info->fileCount;
            }
        }
    }
    return moved;
}

} // namespace rw
