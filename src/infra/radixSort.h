// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  radixSort.h
//
//  Cache-friendly stable radix sorts for unsigned integer and finite float keys.
//
//  Two paths are provided:
//      sortKeySmall  — records are cheap to copy; move the whole item each pass.
//      sortKeyLarge  — payloads are large; sort uint32 indices against keys.
//
//  Bodies live in radixSort.inl so callers can specialize on record/key types.
//
//  Performance notes (what the implementation already does):
//    * Single-read histogram — all byte-digit histograms are accumulated in one
//      pass over the keys, so the data is read once before any scatter.
//    * No-op pass skip — a digit whose whole column lands in one bin is skipped,
//      which collapses small/bucketed key ranges to 1-2 passes.
//    * SIMD byte histograms (NEON on arm64, SSE2 on x86_64) — contiguous
//      uint32/uint64/float keys histogram via a single vector load + byte
//      spill; the IEEE float order-flip is in SIMD. Parity vs the scalar path
//      is gated by test/radixsimdcheck.sh. Measured on x86 (Rosetta proxy,
//      -O2 -DNDEBUG): float 1.44-1.52x over scalar, uint32/uint64 a wash
//      (kept for backend uniformity at no measured cost).
//    * uint32 histogram counters (count is capped at UINT32_MAX) so the 256-bin
//      tables stay L1-resident across clear/accumulate/offset scans.
//    * Packed <word,index> pairs (sortKeyLargePairs) turn the index scatter into
//      a sequential read, the most cache-friendly layout once keys spill L1.
//
//  Possible future tricks (measure before adding — the current paths already
//  beat timsort 3-6x on random float keys):
//    * 11-bit digits (2048 bins, 3 passes for 32-bit instead of 4) trade the
//      NEON byte path for one fewer full scatter; a likely win for large N.
//    * Software write-combining buffers per bin to tame the scattered stores.
//    * Software gather prefetch on the keys[idx] index path — tried and dropped:
//      at game sizes (hundreds of keys) the gathered set is L1-resident, so the
//      prefetch instructions only added overhead. Revisit if N grows large.
//    * AVX2 byte histograms (32-byte load, same spill) — tried and dropped:
//      measured 0.86-0.94x of the SSE2 kernels under the only x86 available
//      here (Rosetta 2 translation — a proxy, not real silicon). Do not re-add
//      without a measured win on physical x86.
//

#pragma once

#include "fastmath.h" // ALWAYS_INLINE / memorycopy / VERIFY_TEXT / cache-line size (via platform.h) / fastmath::isFiniteFast
#include <cstddef>
#include <cstdint>
#include <type_traits>
#include <utility>

// The byte-histogram fast paths in radixSort.inl are written in vector intrinsics under
// these backend macros, so this header owns the backend choice (and the intrinsics
// include) rather than inheriting it from whatever happened to be included first. The
// byte-spill trick indexes lanes by memory order, so a big-endian target (NEON can be
// either) takes the scalar path; x86 is always little-endian.
#if ( defined( __ARM_NEON ) || defined( __ARM_NEON__ ) ) && \
    ( !defined( __BYTE_ORDER__ ) || __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__ )
#include <arm_neon.h>
#define RADIXSORT_NEON 1
#define RADIXSORT_SSE2 0
#elif defined( __SSE2__ ) || defined( _M_X64 )
#include <emmintrin.h>
#define RADIXSORT_NEON 0
#define RADIXSORT_SSE2 1
#else
#define RADIXSORT_NEON 0
#define RADIXSORT_SSE2 0
#endif

namespace radix
{

// Direct stable sort for packed <key, small-payload> records.
// `scratch` must point to count writable Items. `keyOf(item)` must return an
// unsigned 8/16/32/64-bit integral key or a finite float key.
template<class Item, class KeyOf>
void sortKeySmall( Item* items, Item* scratch, std::size_t count, KeyOf&& keyOf ) noexcept;

// Stable sort for <key, large-payload> layouts. Keys may be unsigned
// 8/16/32/64-bit integers or finite floats. The large payload array is not
// touched; `indices` receives 0..count-1 in key order. `scratch` must point to
// count writable uint32_t values.
template<class Key>
void sortKeyLarge( const Key* keys, uint32_t* indices, uint32_t* scratch, std::size_t count ) noexcept;

// Same as sortKeyLarge, but sorts a caller-provided index list in-place. This
// is useful for filtered subsets or secondary stable passes.
template<class Key>
void sortKeyLargeIndexed( const Key* keys, uint32_t* indices, uint32_t* scratch, std::size_t count ) noexcept;

// Packed <sort-word, index> pair used by sortKeyLargePairs.
struct alignas( 8 ) WordIndex
{
    uint32_t word; // order-preserving sort word (see detail::sortWordOf)
    uint32_t index; // original element position
};
static_assert( sizeof( WordIndex ) == 8 );

// Cache-friendly stable index sort for 32-bit-word keys (unsigned 8/16/32-bit
// or finite float). Bakes <word,index> pairs once, then radix-sorts the pairs
// with fully sequential reads — no keys[idx] gather and no per-pass float flip,
// unlike sortKeyLarge. Faster once the gathered key set spills L1; prefer it for
// large counts, at the cost of 2x the scratch. `indices` receives 0..count-1 in
// key order; `scratch` must point to 2*count writable WordIndex pairs.
template<class Key>
void sortKeyLargePairs( const Key* keys, uint32_t* indices, WordIndex* scratch, std::size_t count ) noexcept;

// Quantize a finite float into an unsigned 16-bit bucket. Values outside
// [minValue, maxValue] are clamped. This is intended for fast approximate sorts
// where the last bit of float precision is not useful.
constexpr uint16_t quantizeFloatToU16( float value, float minValue, float maxValue ) noexcept;

// Common fast path for signed gameplay-ish float keys. Bucket width is
// 2048/65535 ~= 0.03125 in source units.
constexpr uint16_t quantizeFloatToU16Signed1024( float value ) noexcept;

} // namespace radix

#include "radixSort.inl"
