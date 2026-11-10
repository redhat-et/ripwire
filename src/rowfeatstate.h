#pragma once
// ROW-FEATURE-DUMP, the capture half (dev-only; the emit half is rowfeatures.h). RIPWIRE_ROW_FEATURES=<path> asks --for
// (CLI and MCP `for`) to append one TSV line per printed answer row to <path>, carrying what the ranker held for that row.
// This header is the state the ranking and the <sigs> render write into: score snapshots after each lift stage of the lens
// ranking, the tier multipliers, the route, and the <sigs> row order before and after the head round-robin. Every writer is
// a no-op unless the switch is set (one getenv per process), and none of them changes a byte the answer prints.
#include "model.h"

#include <array>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw::rowfeat
{
// The lens ranking's stages, in the order computeLensRanking (and its MCP twin) runs them. Each snapshot is the whole rank
// vector after that stage; a stage that did not run leaves no snapshot and reads as the stage before it (delta 0).
enum class Stage : std::uint8_t
{
    Lexical,        // the routed base ranker (subtoken+body or name-exact BM25), tier multiplier folded in
    Anchor,         // --anchor (experimental graph expansion)
    Mention,        // B8 query-mention anchor + FOR-FILE-ANCHOR file subject lift
    PathCut,        // PATH-FROM-UPSTREAM
    Experimental,   // RIPWIRE_SIBLIFT / RIPWIRE_POOL / RIPWIRE_EXPAND (inert unless set)
    CoChange,       // B3 co-change prior (opt-in)
    DocMention,     // R5 doc-mention lift: the FINAL rank
};
inline constexpr std::size_t kStages = 7;

struct State
{
    std::array<std::vector<float>, kStages> stage;
    std::vector<float>                      tier;        // rankTierSymbolMultipliersShaped, per symbol
    std::string                             route;       // "subtoken+body" | "name-exact" | "" (unrouted)
    std::vector<std::pair<std::string, std::uint32_t>> anchors;   // RouteAnchorDef (lowerName, fileId)
    // <sigs> rows (the XML lens path), live rows in order: before the head round-robin, after it, and as written
    std::vector<NodeId>        sigsBefore, sigsAfterRR, sigsShown;
    std::vector<std::uint32_t> sigsPreRank;   // parallel to sigsBefore: the r= the row held in score order
    bool                       sigsRR = false;   // the head round-robin rule was on for this render
    std::vector<std::uint32_t> fanIn;          // the in= vector the <sigs> render read
    std::vector<std::uint8_t>  tested;         // the tested= vector the <sigs> render read
};

inline const char* outPath() noexcept
{
    static const char* const p = []
    {
        const char* v = std::getenv( "RIPWIRE_ROW_FEATURES" );
        return ( v != nullptr && *v != '\0' ) ? v : nullptr;
    }();
    return p;
}
inline bool on() noexcept
{
    return outPath() != nullptr;
}
inline State& state()
{
    static State s;
    return s;
}
inline void stage( Stage k, const std::vector<float>& rank )
{
    if( on() )
    {
        state().stage[ std::size_t( k ) ] = rank;
    }
}
inline void tier( const std::vector<float>& mul )
{
    if( on() )
    {
        state().tier = mul;
    }
}
// The route the base ranker took and the definitions that decided it (lexical.h RouteAnchorDef: lowerName, fileId).
template< class AnchorDefs >
inline void noteRoute( std::string_view routeTag, const AnchorDefs& defs )
{
    if( !on() )
    {
        return;
    }
    State& s = state();
    s.route  = std::string( routeTag );
    s.anchors.clear();
    for( const auto& d : defs )
    {
        s.anchors.emplace_back( d.lowerName, d.fileId );
    }
}
// The <sigs> render's inputs (a fresh render replaces the previous one's: the last render is the printed one).
inline void sigsInputs( const std::vector<std::uint32_t>* fanIn, const std::vector<std::uint8_t>* tested, bool headRoundRobin )
{
    if( !on() )
    {
        return;
    }
    State& s = state();
    s.fanIn  = fanIn ? *fanIn : std::vector<std::uint32_t>{};
    s.tested = tested ? *tested : std::vector<std::uint8_t>{};
    s.sigsRR = headRoundRobin;
    s.sigsBefore.clear();
    s.sigsAfterRR.clear();
    s.sigsShown.clear();
    s.sigsPreRank.clear();
}
// `which`: 0 = before the head round-robin (records the r= too), 1 = after it, 2 = as written.
template< class Entries >
inline void sigsOrder( int which, const Entries& entries )
{
    if( !on() )
    {
        return;
    }
    State&               s   = state();
    std::vector<NodeId>& ids = which == 0 ? s.sigsBefore : which == 1 ? s.sigsAfterRR : s.sigsShown;
    ids.clear();
    for( const auto& e : entries )
    {
        if( !e.dropped )
        {
            ids.push_back( e.id );
            if( which == 0 )
            {
                s.sigsPreRank.push_back( e.displayRank );
            }
        }
    }
}
}   // namespace rw::rowfeat
