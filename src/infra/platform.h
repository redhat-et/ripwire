// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  platform.h
//
//  The compiler/platform substrate every other infra header sits on: the attribute
//  macros and the cache-line interference sizes. Namespace is `infra::platform`.
//
//  Split out of this tree's own fastmath.h (2026-08-09) along the line "describes the
//  MACHINE" vs "computes a NUMBER": ALWAYS_INLINE, memorycopy, and a cache-line width
//  are facts about the compilation target, not math, and a header that needs only
//  those should not have to pull in fastmath.h's number helpers to get them.
//  fastmath.h #includes this header, so its own includers still see ALWAYS_INLINE,
//  memorycopy, and the interference sizes exactly as before this split.
//
//  PORTING NOTE — this file is hand-copied, file for file, to and from a companion
//  C++ game-math tree that vendors the same infra set. Keep the sibling include below
//  BARE (`#include "Diagnostics.h"`, never a directory-prefixed path) — the
//  destination tree's layout differs and a hardcoded prefix breaks on arrival.
//
//  Every macro and constant below has a real call site above this layer; nothing is
//  kept "in case". (The companion tree also carries a `memorycopyinline` macro
//  immediately below `memorycopy` — there is no caller for it in this tree, so it is
//  not mirrored here.)
//

#pragma once

#include <cstddef>       // std::size_t for the hardware-interference-size constants

// ==========================================================================
// Compiler attributes
// ==========================================================================

#ifdef __clang__
#define ALWAYS_INLINE  [[clang::always_inline]] inline
#else
#define ALWAYS_INLINE  __attribute__((always_inline)) inline
#endif

#define memorycopy(dst,src,size)  __builtin_memcpy(dst,src,size)

// Diagnostics.h provides VERIFY, VERIFY_TEXT, VERIFY_NOT_REACHED, PANIC, and
// DEGRADED_PATH_ALERT. Included here, not merely alongside, because this header is
// the one every infra consumer already takes for the attribute macros and the
// cache-line constants — sparseCsr.h and radixSort.h document that dependency.
#include "Diagnostics.h"

// ==========================================================================
// infra::platform — facts about the machine this tree compiles for
// ==========================================================================

namespace infra::platform
{

// Cache-line size constants — follow the C++17 std::hardware_*_interference_size
// naming convention. Provided here as project-owned constexpr values because
// libc++ doesn't always ship the std:: versions (ABI-stability concerns) and we
// need the values correct for the production target — Apple Silicon (A11+ /
// M-series) uses 128-byte L1d cache lines vs 64 on commodity x86.
//
//   hardware_destructive_interference_size  : minimum offset between two objects
//       to avoid FALSE SHARING across cores. Pad cross-thread shared structs to
//       this — the per-thread radix histograms and the profiler's counter rows.
//
//   hardware_constructive_interference_size : maximum size of contiguous memory
//       likely to SHARE one L1 cache line. Align hot SoA array STARTS to this so
//       the first SIMD load lands inside a fresh line. This is the one the CSR
//       rowOffsets/colIndices/values arrays are allocated against.
//
// Numerically identical on every target we ship to; the two names exist so the
// call site documents which kind of layout problem it is preventing.
#if defined(_M_ARM) || defined(_M_ARM64) || defined(__arm__) || defined(__aarch64__)
    constexpr std::size_t hardware_destructive_interference_size  = 128;
    constexpr std::size_t hardware_constructive_interference_size = 128;
#else
    constexpr std::size_t hardware_destructive_interference_size  = 64;
    constexpr std::size_t hardware_constructive_interference_size = 64;
#endif

} // namespace infra::platform
