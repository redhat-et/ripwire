#pragma once

// smallvec.h — THE ONE ALIAS. Every small-vector call site in ripwire names `rw::SmallVec<T, N>`, and this
// header decides which implementation that is. Change one macro and the whole tree changes container.
//
// WHY IT EXISTS. There are three plausible implementations of the same shape and no way to argue the
// choice to a conclusion — the honest answer is a measurement over the REAL workload, not a
// microbenchmark. Without an alias that experiment costs ~138 edits per arm and nobody runs it. With
// one, it is a build-configuration flag:
//
//     cmake -S . -B build_ank -DRIPWIRE_SMALLVEC=1 && cmake --build build_ank -j
//
// bench/svectorab.py drives the full A/B on top of exactly this switch. Read bench/SVECTORAB.md for what
// it measured and why arm 2 won.
//
// THE ARMS
//   0  std::vector<T>                 the pre-conversion baseline: 24 B, a malloc per non-empty list.
//   1  ankerl::svector<T, N>          third_party/svector.h (MIT). 16 B at <uint32,2>, and it fills its
//                                     own padding so the inline capacity is really 3, not 2. size()
//                                     branches on the SVO tag — and once spilled, dereferences into the
//                                     heap block to read the size. The complete, mature implementation:
//                                     the right choice for a T this tree's own type refuses.
//   2  rw::svector<T, N>              src/infra/svector.h. 16 B AND a branch-free size(), by unioning the
//                                     inline array with the heap pointer. THE DEFAULT, chosen by
//                                     measurement — see bench/SVECTORAB.md.
//
// There is no arm 3. It used to be the union experiment (`rwx::svector16`, bench/svector_union_arm.h);
// it won, so it was promoted into arm 2 and the separate copy deleted rather than left alive as a second
// implementation of the same idea.
//
// N is `std::uint32_t` because rw::svector's non-type parameter is, and std::vector ignores it. Passing a
// size_t literal would deduce differently per arm and stop the alias being a one-line flip.

#include <cstdint>
#include <vector>

#define RIPWIRE_SMALLVEC_STD    0
#define RIPWIRE_SMALLVEC_ANKERL 1
#define RIPWIRE_SMALLVEC_RW     2

#ifndef RIPWIRE_SMALLVEC
    #define RIPWIRE_SMALLVEC RIPWIRE_SMALLVEC_RW
#endif

#if RIPWIRE_SMALLVEC == RIPWIRE_SMALLVEC_ANKERL
    #include "../third_party/svector.h"
#else
    #include "infra/svector.h"
#endif

namespace rw
{

#if RIPWIRE_SMALLVEC == RIPWIRE_SMALLVEC_STD
template <class T, std::uint32_t N>
using SmallVec = std::vector<T>;                    // N is inert here, and that is the point of the arm
inline constexpr const char* kSmallVecArm = "std::vector";
#elif RIPWIRE_SMALLVEC == RIPWIRE_SMALLVEC_ANKERL
template <class T, std::uint32_t N>
using SmallVec = ankerl::svector<T, N>;
inline constexpr const char* kSmallVecArm = "ankerl::svector";
#else
template <class T, std::uint32_t N>
using SmallVec = svector<T, N>;
inline constexpr const char* kSmallVecArm = "rw::svector";
#endif

}   // namespace rw
