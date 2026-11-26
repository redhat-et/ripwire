#pragma once
// buildkey.h — which COMPILATION of the sources this binary is, as one string.
//
// quality::producerIdentity names the sources (src/ and queries/) and is the same for every build of one tree. A cache
// that stores what the code COMPUTED, not just what it read, needs more: the warm snapshot (warmsnap.h) stores floats —
// ranks, prior weights, the in-edge CSR values — and a dev build (-O2, no LTO) and a Release build (-O3, LTO) of one
// tree are not promised to compute the same bits. Everything but src/pagerank.cpp is built with -ffast-math, and the
// optimizer, after inlining, decides where `a*b+c` becomes one fused multiply-add.
//
// RIPWIRE_BUILD_KEY is CMakeLists.txt's digest of the compiler, its version, the target, the build type, LTO, PGO and
// every flag; RIPWIRE_BUILD_CONFIG is `$<CONFIG>`, for a multi-config generator. The macros after them are what this
// translation unit's compiler itself reports, so a build outside CMake (which has no key) still tells an optimized,
// NDEBUG or fast-math compilation from another. Both targets define the same two macros for every translation unit, so
// every reader in one binary sees one value — except src/pagerank.cpp, built without -ffast-math, which must never
// include this header (nothing it needs is here).
#include <string_view>

namespace rw
{

#ifndef RIPWIRE_BUILD_KEY
#define RIPWIRE_BUILD_KEY "unkeyed"
#endif
#ifndef RIPWIRE_BUILD_CONFIG
#define RIPWIRE_BUILD_CONFIG ""
#endif

inline constexpr std::string_view kBuildKey =
    "key=" RIPWIRE_BUILD_KEY "|config=" RIPWIRE_BUILD_CONFIG
#if defined( __VERSION__ )
    "|cc=" __VERSION__
#endif
#if defined( NDEBUG )
    "|ndebug"
#endif
#if defined( __OPTIMIZE__ )
    "|opt"
#endif
#if defined( __FAST_MATH__ )
    "|fast-math"
#endif
    ;

}   // namespace rw
