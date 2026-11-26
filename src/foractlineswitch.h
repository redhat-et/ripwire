// foractlineswitch.h — the SWITCH of the `--for` act line (lane BR1; foractline.h is the line). Its own small header, as forrowsform.h
// is for ROWLINES, because cli.h (--version's act=) decides with it and must not include the encoder's dependencies.
#pragma once

#include <cstdlib>
#include <string_view>

namespace rw::actline
{

// RIPWIRE_NO_ACTLINE (any value) turns the act line off: the A/B handle (the RIPWIRE_NO_SIGX / RIPWIRE_NO_ROWLINES precedent).
[[nodiscard]] inline bool actLineOn() noexcept { return std::getenv( "RIPWIRE_NO_ACTLINE" ) == nullptr; }
// The posture this process serves, as --version discloses it (act=).
[[nodiscard]] inline std::string_view defaultActName() noexcept { return actLineOn() ? "on" : "off"; }

}   // namespace rw::actline
