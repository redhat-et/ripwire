// foractlineswitch.h — the SWITCH of the `--for` act line (lane BR1; foractline.h is the line). Its own small header, as forrowsform.h
// is for ROWLINES, because cli.h (--version's act=) decides with it and must not include the encoder's dependencies.
#pragma once

#include <cstdlib>
#include <string_view>

namespace rw::actline
{

// The act line's legend clause (foractline.h, which static_asserts its "top 3" against kActRows). Here, beside the switch, so
// forpages.h can measure it without the encoder (lane ACT-EDGES: the full-legend bytes the wide clause adds).
inline constexpr std::string_view kActClause =
    "<!-- the act line: read= P:L-E of the top 3 sigs d rows by r=: Read ALL in ONE turn, parallel ranged Reads, except a served "
    "body; search only for what no row lists; absent if one lacks e= -->";
// ACT-8 (lane ACT-EDGES): the clause of the wide line, written instead of kActClause while actedges::actEdgesOn( kPartAct8 ).
inline constexpr std::string_view kActClauseWide =
    "<!-- the act line: read= P:L-E of the top 3 sigs d rows by r=, then the next ranged ones, up to 8 ranges: Read ALL in ONE turn, "
    "parallel ranged Reads, except a served body; search only for what no row lists; absent if one of the top 3 lacks e= -->";

// RIPWIRE_NO_ACTLINE (any value) turns the act line off: the A/B handle (the RIPWIRE_NO_SIGX / RIPWIRE_NO_ROWLINES precedent).
[[nodiscard]] inline bool actLineOn() noexcept { return std::getenv( "RIPWIRE_NO_ACTLINE" ) == nullptr; }
// The posture this process serves, as --version discloses it (act=).
[[nodiscard]] inline std::string_view defaultActName() noexcept { return actLineOn() ? "on" : "off"; }

}   // namespace rw::actline
