//
//  valueGates.h — the VALUE-STYLE gate family (--flip's hard case, test/flipcheck.sh).
//
//  These gates are never tested with `#if`. Each is bound to an `inline constexpr bool` and then consumed
//  by `if constexpr( … )`, so the code they guard is a C++ BRANCH, not a preprocessor region — which is
//  why `--flags` honestly reports regions="0" for the whole family and why a flip-impact verb that follows
//  only `#if` regions would say "nothing lights up" here. `--flip` must follow the binding instead.
//
//  Shape copied from the motivating repo's River-Raid-feel family: one master, children that #define to it,
//  one `constexpr bool` per child.
//
#pragma once

#ifndef FIXTURE_VALUE_ALL
#define FIXTURE_VALUE_ALL 0
#endif

#ifndef FIXTURE_VALUE_WAVE
#define FIXTURE_VALUE_WAVE  FIXTURE_VALUE_ALL
#endif

#ifndef FIXTURE_VALUE_TURNS
#define FIXTURE_VALUE_TURNS FIXTURE_VALUE_ALL
#endif

namespace fixval
{

inline constexpr bool kWave  = FIXTURE_VALUE_WAVE  != 0;
inline constexpr bool kTurns = FIXTURE_VALUE_TURNS != 0;

}   // namespace fixval
