#pragma once
// orientarm.h — which registered arm of the orient sections this build is (fix #8; docs/EVALS.md "A default map that orients").
// One constant, read by orientmap.h (what O3 does to a demoted file's ranked rows) and by the legends that say so
// (serialize.h kOrientLegend*, compactlegend.h). The O-narrow and PLACEBO arm builds flip kArm and nothing else here.
#include <cstdint>
#include <string_view>

namespace rw::orient
{

enum class Arm : std::uint8_t { O, Narrow, Placebo };
inline constexpr Arm kArm = Arm::Narrow;   // O-narrow v3 (PREREG_orient_narrow_v3): the shipping candidate; O is abandoned (O2 verdict)

}   // namespace rw::orient
