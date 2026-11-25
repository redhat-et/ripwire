// fortinyshapeswitch.h — the SWITCH of the `--for` tiny named-location shape (THETA6; fortinyshape.h is the shape). Its own small
// header, as foractlineswitch.h is for the act line, because cli.h (--version's tiny=) decides with it and must not include the
// shape's dependencies.
#pragma once

#include <cstdlib>
#include <string_view>

#include "infra/envnumber.h"   // readEnvNumber — the one environment-number reader every knob shares

namespace rw::tinyshape
{

// RIPWIRE_TINY_SHAPE_FORCE (any value): the shape on EVERY eligible call, the detector skipped: the measurement arm that labels which
// questions the shape serves completely (lane THETA6 Step 0), never a product posture. It implies the shape.
[[nodiscard]] inline bool tinyShapeForced() noexcept { return std::getenv( "RIPWIRE_TINY_SHAPE_FORCE" ) != nullptr; }
// ON by default (owner decision 11-24, PR #742). RIPWIRE_TINY_SHAPE=0 turns it off: every answer is then the full page, byte-identical
// to the one served before the shape existed (test/tinyshapecheck.sh (I)). Any other value, or unset, leaves it on; the shared knob
// reader (infra/envnumber.h) decides what "0" is.
[[nodiscard]] inline bool tinyShapeSwitchedOff() noexcept
{
    const EnvNumber knob = readEnvNumber( "RIPWIRE_TINY_SHAPE" );
    return knob.parsed && knob.value == 0;
}
[[nodiscard]] inline bool tinyShapeOn() noexcept { return tinyShapeForced() || !tinyShapeSwitchedOff(); }
// The posture this process serves, as --version discloses it (tiny=).
[[nodiscard]] inline std::string_view defaultTinyName() noexcept { return tinyShapeOn() ? "on" : "off"; }

}   // namespace rw::tinyshape
