// foractedgesswitch.h — the SWITCH of lane ACT-EDGES (11-26; foractedges.h is the EDGES and WHERE lines, foractline.h the wide act
// line): ACT-8, the EDGES line and the WHERE line on a `--for` page 1. Its own small header, as forrouteswitch.h is for ROUTING,
// because foranswerfirst.h and forpages.h (which count the act line's bytes) decide with it and must not include the act line's
// encoder (it includes them).
//
// WHY (tmp/orch-1125/hard-orient/RESULT.md, PA1 R BD + TR1 D, 34 hard GA1 sessions): after the answer, 30 % of retrieval cost was a
// named range read one per turn, 11 % a callers/callees hunt from the answer's symbols, 8 % a test/doc/build-file hunt. The three
// lines name those targets on page 1, where the agent plans its first turn.
#pragma once

#include <cstddef>
#include <string_view>

#include "foractlineswitch.h"   // kActClause / kActClauseWide — the act line's two clauses
#include "infra/envnumber.h"   // readEnvNumber — the one environment-number reader every knob shares

namespace rw::actedges
{

// ON by default (owner 11-25 "these look great", ship ON in one PR). RIPWIRE_ACT_EDGES=0 turns all three off: every answer is then
// byte-identical to the one served before this lane (test/actedgescheck.sh (O)). The A/B arms (each part measured alone): a number
// 1..6 is a mask of the parts it keeps, kPartAct8 (1) | kPartEdges (2) | kPartWhere (4). Any other value, or unset, keeps all three.
inline constexpr unsigned kPartAct8  = 1;
inline constexpr unsigned kPartEdges = 2;
inline constexpr unsigned kPartWhere = 4;
inline constexpr unsigned kPartsAll  = kPartAct8 | kPartEdges | kPartWhere;
[[nodiscard]] inline unsigned actEdgesParts() noexcept
{
    const EnvNumber knob = readEnvNumber( "RIPWIRE_ACT_EDGES" );
    return knob.parsed && knob.value < kPartsAll ? unsigned( knob.value ) : kPartsAll;
}
[[nodiscard]] inline bool actEdgesOn( unsigned part ) noexcept
{
    return ( actEdgesParts() & part ) != 0;
}

// ACT-8: the act line lists the top kActRows (foractline.h, 3) sigs rows as before, then the next ranged sigs rows by rank up to
// kActRowsWide ranges in all (HARD-ORIENT p1_devcheck.md: BD pre-edit held reads an act range covers 40 % -> 72 % at 8; every gold
// file in act GA3 47 -> 68 of 99, GA1 66 -> 76 of 89).
inline constexpr std::size_t kActRowsWide = 8;
// The ranges the line held before ACT-8 (foractline.h kActRows, which static_asserts it equals this): the part no page counts.
inline constexpr std::size_t kActShippedRanges = 3;

// THE BYTES OF AN <act/> ELEMENT NO PAGE COUNTS (forpages.h markActLine, foranswerfirst.h layoutBlocks). Before this lane every byte
// of the line was uncounted, so it never cost a page a row. The wide line's added ranges are counted: they come out of the bottom of
// the page (owner rule "answers to the top, then cut the bottom"). So the uncounted part is the element as it would be with its
// first `shipped` ranges only: `<act read="` + those ranges + `"/>`. Off, or a shape this reader does not know: the whole element.
inline constexpr std::string_view kActOpen = "<act read=\"", kActClose = "\"/>";
[[nodiscard]] inline std::size_t uncountedActBytes( std::string_view element, std::size_t shipped ) noexcept
{
    constexpr std::string_view kOpen = kActOpen, kClose = kActClose;
    if( !actEdgesOn( kPartAct8 ) || !element.starts_with( kOpen ) || !element.ends_with( kClose ) )
    {
        return element.size();
    }
    const std::string_view value = element.substr( kOpen.size(), element.size() - kOpen.size() - kClose.size() );
    std::size_t            at    = 0;
    for( std::size_t n = 0; n < shipped; ++n )
    {
        const std::size_t comma = value.find( ',', at );
        if( comma == std::string_view::npos )
        {
            return element.size();   // `shipped` ranges or fewer: nothing was added
        }
        at = comma + 1;
    }
    return kOpen.size() + ( at - 1 ) + kClose.size();
}

// The top-level element names of the two lines foractedges.h writes.
[[nodiscard]] inline bool isLaneLine( std::string_view name ) noexcept
{
    return name == "edges" || name == "where";
}

// The clauses of the two lines foractedges.h writes (here so forpages.h can measure them without that header).
inline constexpr std::string_view kEdgesClause =
    "<!-- the edges line: per act-line symbol (its first 3 ranges) NAME: called by P:L N (non-test callers), calls P:L N (callees in "
    "other non-test files); exact-resolved first, then by name; not ones an act range holds; (+K) K more of that kind -->";
inline constexpr std::string_view kWhereClause =
    "<!-- the where line: beside the act files, tests= that call an act symbol or are named after an act file, docs= that name one in "
    "backticks, changelog= nearest at or above the top act file, build= the build file listing the first test or an act file; "
    "X_total= all found; absent = none found -->";

// THE FULL-LEGEND BYTES THIS LANE ADDS to a page-1 document `view`: the edges and where clauses and the wide act clause's extra over
// the shipped one. θ5's refill (forpages.h coreEnds) sizes page 1 by the page the FULL legend would deliver; without this the long
// clauses would grow that target and pull rows ONTO page 1 under the core legend. With it, the target is the page before this lane,
// so the lines' bytes come out of the bottom of page 1 (owner rule "answers to the top, then cut the bottom").
[[nodiscard]] inline std::size_t fullLegendExtraBytes( std::string_view view ) noexcept
{
    std::size_t extra = 0;
    extra += view.find( kEdgesClause ) != std::string_view::npos ? kEdgesClause.size() : 0;
    extra += view.find( kWhereClause ) != std::string_view::npos ? kWhereClause.size() : 0;
    extra += view.find( actline::kActClauseWide ) != std::string_view::npos ? actline::kActClauseWide.size() - actline::kActClause.size() : 0;
    return extra;
}

}   // namespace rw::actedges
