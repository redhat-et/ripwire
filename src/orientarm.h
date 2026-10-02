#pragma once
// orientarm.h — which registered arm of the orient sections this build is (fix #8; docs/EVALS.md "A default map that orients").
// One constant, read by orientmap.h (what O3 does to a demoted file's ranked rows) and by the legends that say so
// (serialize.h kOrientLegend*, compactlegend.h). The O-narrow and PLACEBO arm builds flip kArm and nothing else here.
#include <cstdint>
#include <string_view>

namespace rw::orient
{

enum class Arm : std::uint8_t { O, Narrow, Placebo };
inline constexpr Arm kArm = Arm::O;

}   // namespace rw::orient
