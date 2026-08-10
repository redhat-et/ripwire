#pragma once

// smallvec.h — THE ONE ALIAS. Every small-vector call site in ripwire names `rw::SmallVec<T, N>`, and this
// header decides which implementation that is. Change one macro and the whole tree changes container.
//
// WHY IT EXISTS. There are three (soon four) plausible implementations of the same shape and no way to
// argue the choice to a conclusion — the honest answer is a measurement over the REAL workload, not a
// microbenchmark. Without an alias that experiment costs ~138 edits per arm and nobody runs it. With one,
// it is a build-configuration flag:
//
//     cmake -S . -B build_ank -DRIPWIRE_SMALLVEC=1 && cmake --build build_ank -j
//
// bench/svectorab.py drives the full four-way A/B on top of exactly this switch. Read bench/SVECTORAB.md
// for what it measured and which arm won on which shape.
//
// THE ARMS
//   0  std::vector<T>                 the pre-conversion baseline: 24 B, a malloc per non-empty list.
//   1  ankerl::svector<T, N>          third_party/svector.h (MIT). 16 B at <uint32,2>, and it fills its
//                                     own padding so the inline capacity is really 3, not 2. size()
//                                     branches on the SVO tag bit. The complete, mature implementation —
//                                     25 operations against rw::svector's original 6.
//   2  rw::svector<T, N>              src/infra/svector.h. 24 B; spends 8 bytes on an explicit size field
//                                     to make size() branch-free. The shipped default (see below).
//   3  rwx::svector16<T, N>           bench/svector_union_arm.h — EXPERIMENT ONLY, never a shipped arm.
//                                     Unions inl_ with heap_ to reach 16 B while keeping size()
//                                     branch-free. Select it with -DRIPWIRE_SMALLVEC=3; the include is
//                                     spelled relatively below, so no extra include path is needed.
//
// N is `std::uint32_t` because rw::svector's non-type parameter is, and std::vector ignores it. Passing a
// size_t literal would deduce differently per arm and stop the alias being a one-line flip.
//
// THE DEFAULT IS DELIBERATELY THE STATUS QUO. Arm 2 reproduces the pre-alias binary exactly, so adding
// this header changed no behaviour and no output — the golden and determinism gates prove that rather
// than assert it. Moving the default is a separate commit that the measurement has to earn.

#include <cstdint>
#include <vector>

#define RIPWIRE_SMALLVEC_STD    0
#define RIPWIRE_SMALLVEC_ANKERL 1
#define RIPWIRE_SMALLVEC_RW     2
#define RIPWIRE_SMALLVEC_UNION  3

#ifndef RIPWIRE_SMALLVEC
    #define RIPWIRE_SMALLVEC RIPWIRE_SMALLVEC_RW
#endif

#if RIPWIRE_SMALLVEC == RIPWIRE_SMALLVEC_ANKERL
    #include "../third_party/svector.h"
#elif RIPWIRE_SMALLVEC == RIPWIRE_SMALLVEC_UNION
    // Spelled relatively, the same way bench/ reaches third_party/: a quoted include resolves against
    // the including file's own directory first, so this needs no -Ibench and stays inside the repo's
    // include closure (test/ripwirepubliccheck.sh arm 7 sweeps textually and cannot evaluate the #if).
    #include "../bench/svector_union_arm.h"
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
#elif RIPWIRE_SMALLVEC == RIPWIRE_SMALLVEC_UNION
template <class T, std::uint32_t N>
using SmallVec = rwx::svector16<T, N>;
inline constexpr const char* kSmallVecArm = "rwx::svector16";
#else
template <class T, std::uint32_t N>
using SmallVec = svector<T, N>;
inline constexpr const char* kSmallVecArm = "rw::svector";
#endif

}   // namespace rw
