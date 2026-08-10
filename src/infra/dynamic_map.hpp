// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

// =============================================================================
//  dynamic_map.hpp
//
//  A dynamic (insert + erase) sorted associative container with a std::map-like
//  interface, built as a B+ tree whose per-node key scan reuses the SIMD
//  "count keys vs x" kernel from the static S+ tree
//  (https://en.algorithmica.org/hpc/data-structures/s-tree/), with both a
//  strictly-less (rank_lt) and a less-or-equal (rank_le) variant. On AArch64 the
//  scan compiles to NEON; on x86_64 to SSE (SSE2 for 32-bit and float keys, SSE4.2
//  for 64-bit integer keys); elsewhere it is a portable scalar loop.
//
//  Properties:
//    * NO PER-OPERATION DYNAMIC ALLOCATION. Two node pools are allocated exactly
//      once at construction (sized from a capacity bound) and recycled through
//      intrusive free lists. find/insert/erase never touch the allocator.
//    * NODE LAYOUT TUNED FOR THE SEARCH PATH. keys[] live first and cache-line
//      aligned so the SIMD scan loads aligned and touches the fewest lines;
//      values are a separate in-node array (struct-of-arrays) so a key scan never
//      pulls value bytes into cache; child references are 32-bit handles, not
//      64-bit pointers; and no parent link is stored (the root-to-leaf path comes
//      from the recursion stack).
//    * TEMPLATED NODE WIDTH `B`. The number of keys per node is a compile-time
//      parameter, constrained to be a whole multiple of the NEON lane count for
//      the key type so the fixed-width SIMD scan divides the node evenly. Default
//      is 16 (one 64-byte line of 32-bit keys); 32 is a natural choice on targets
//      with 128-byte cache lines.
//    * NODES ALIGNED TO 16 (the NEON load granularity). An earlier version
//      cache-line-aligned nodes; measurement showed the padding LOWERED cache
//      density and slowed lookups, so it was removed (see the node-layout note).
//
//  CONTRACTS (each VERIFY'd at the public seams; free in release):
//    * Keys: arithmetic types only (SIMD set int32/uint32/float/int64/uint64/
//      double; other arithmetic via the scalar path). The key's numeric max is
//      reserved as padding; the descent stays correct even if that value occurs
//      as a real key. FLOATING KEYS MUST BE FINITE -- +/-inf and NaN break the
//      sentinel ordering (inf sorts above the max-padding; NaN compares false
//      against everything) and give silently wrong find/insert results.
//    * Compare must be std::less<Key> (static_assert'd). The sentinel scheme
//      orders by the numeric ordering; a custom comparator would silently count
//      padding slots into every rank.
//    * Capacity is a HARD bound, enforced: an insert of a NEW key while
//      size() == capacity() is rejected ({end(), false}); operator[] on a new
//      key at capacity PANICs (it must return a reference). Node-pool
//      exhaustion beyond that is a sizing bug and PANICs (always on, cold path).
//    * Value must be default constructible (slots stay live for a node's life).
//    * A moved-from map supports ONLY destruction, move-assignment-into,
//      empty()/size()/capacity(). Anything else traps in debug.
//
//  Header-only, C++17.
// =============================================================================

#ifndef DYNAMIC_MAP_HPP
#define DYNAMIC_MAP_HPP

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iterator>
#include <limits>
#include <new>
#include <stdexcept>
#include <type_traits>
#include <utility>

#if defined(__aarch64__) || defined(_M_ARM64)
    #include <arm_neon.h>
    #define DYNMAP_HAS_NEON 1
#else
    #define DYNMAP_HAS_NEON 0
#endif

#if defined(__x86_64__) || defined(_M_X64)
    #include <emmintrin.h>           // SSE2 -- baseline on x86_64, always present
    #if defined(__SSE4_2__)
        #include <nmmintrin.h>       // SSE4.2 -- _mm_cmpgt_epi64 for the 64-bit integer kernels
    #endif
    #define DYNMAP_HAS_SSE2 1
#else
    #define DYNMAP_HAS_SSE2 0
#endif

// Precondition guard. In the game build the project's VERIFY (math/Diagnostics.h)
// is already defined and is used (logs + traps in debug, optimiser-assume in
// release). Standalone builds (the unit tests) have no VERIFY, so we fall back to
// assert -- which keeps every guard LIVE in the standalone test binaries.
#if defined(VERIFY)
    #define DYNMAP_VERIFY(expr) VERIFY(expr)
#else
    #include <cassert>
    #define DYNMAP_VERIFY(expr) assert(expr)
#endif

// Unrecoverable-state trap (node-pool exhaustion past the declared capacity, or
// operator[] denied at capacity). ALWAYS active -- never an assume -- because the
// alternative is an out-of-bounds write through a 0xFFFFFFFF handle. Cold paths
// only. Uses the project PANIC when available, else a loud abort.
#if defined(PANIC)
    #define DYNMAP_PANIC(msg) PANIC(msg)
#else
    #include <cstdio>
    #include <cstdlib>
    #define DYNMAP_PANIC(msg)                                                     \
        do                                                                        \
        {                                                                         \
            std::fprintf(stderr, "dynamic_map PANIC: %s\n", msg);                 \
            std::abort();                                                         \
        } while (0)
#endif

namespace stree
{
namespace dyn
{

// -----------------------------------------------------------------------------
//  Cache-line size constant -- DIAGNOSTIC ONLY (the test harness prints it).
//
//  Nodes are deliberately NOT cache-line aligned: an earlier version aligned
//  them via this constant (and before that forced 128 on AArch64); measurement
//  showed the alignment padding lowers cache density and slows lookups, so
//  nodes are alignas(16) -- the NEON load granularity -- and pack tightly. See
//  the node-layout note below. The constant stays for introspection only.
// -----------------------------------------------------------------------------
#if defined(__cpp_lib_hardware_interference_size)
    inline constexpr std::size_t kCacheLine =
        std::hardware_constructive_interference_size;
#else
    inline constexpr std::size_t kCacheLine = 64;
#endif

// Node handle: a 32-bit index into a pool. NIL marks "no node".
using handle_t = std::uint32_t;
constexpr handle_t NIL = 0xFFFFFFFFu;

// Sentinel "infinity" used to pad unused key slots so the fixed-width SIMD scan
// counts only real keys.
template <typename Key>
struct sentinel
{
    static constexpr Key value()
    {
        return std::numeric_limits<Key>::max();
    }
};

// =============================================================================
//  Per-node key ranking (the only SIMD part), templated on the node width B.
//
//  rank_lt(keys, x) = number of slots with key <  x   (leaf lower_bound)
//  rank_le(keys, x) = number of slots with key <= x   (internal descent)
//
//  Both scan all B slots; padding slots hold the sentinel and never contribute
//  (the one max-collision case is handled by clamping at the call site). The
//  scalar template is the portable contract; the NEON specializations match it
//  exactly using the count-of-true-lanes trick (a true vcltq/vcleq lane reads as
//  -1, so the negated horizontal sum is the count). Each NEON kernel loops over
//  B / lanes vectors, which is why B must be a multiple of the lane count.
// =============================================================================
template <typename Key, int B, typename Enable = void>
struct node_rank
{
    static unsigned lt(const Key* keys, Key x)
    {
        unsigned count = 0;

        for (int i = 0; i < B; ++i)
        {
            count += (keys[i] < x) ? 1u : 0u;
        }

        return count;
    }

    static unsigned le(const Key* keys, Key x)
    {
        unsigned count = 0;

        for (int i = 0; i < B; ++i)
        {
            count += (keys[i] <= x) ? 1u : 0u;
        }

        return count;
    }
};

#if DYNMAP_HAS_NEON

// 32-bit-lane key types: four lanes per 128-bit vector, so step the scan by 4.
#define DYNMAP_DEFINE_RANK_32(KEY, VDUP, VLD, VCLT, VCLE)                      \
    template <int B>                                                          \
    struct node_rank<KEY, B, void>                                            \
    {                                                                         \
        static unsigned lt(const KEY* k, KEY x)                               \
        {                                                                     \
            auto xv = VDUP(x);                                                \
            int32x4_t acc = vdupq_n_s32(0);                                   \
            for (int j = 0; j < B; j += 4)                                    \
            {                                                                 \
                acc = vaddq_s32(acc,                                          \
                    vreinterpretq_s32_u32(VCLT(VLD(k + j), xv)));             \
            }                                                                 \
            return static_cast<unsigned>(-vaddvq_s32(acc));                   \
        }                                                                     \
                                                                              \
        static unsigned le(const KEY* k, KEY x)                               \
        {                                                                     \
            auto xv = VDUP(x);                                                \
            int32x4_t acc = vdupq_n_s32(0);                                   \
            for (int j = 0; j < B; j += 4)                                    \
            {                                                                 \
                acc = vaddq_s32(acc,                                          \
                    vreinterpretq_s32_u32(VCLE(VLD(k + j), xv)));             \
            }                                                                 \
            return static_cast<unsigned>(-vaddvq_s32(acc));                   \
        }                                                                     \
    };

// 64-bit-lane key types: two lanes per 128-bit vector, so step the scan by 2.
#define DYNMAP_DEFINE_RANK_64(KEY, VDUP, VLD, VCLT, VCLE)                      \
    template <int B>                                                          \
    struct node_rank<KEY, B, void>                                            \
    {                                                                         \
        static unsigned lt(const KEY* k, KEY x)                               \
        {                                                                     \
            auto xv = VDUP(x);                                                \
            int64x2_t acc = vdupq_n_s64(0);                                   \
            for (int j = 0; j < B; j += 2)                                    \
            {                                                                 \
                acc = vaddq_s64(acc,                                          \
                    vreinterpretq_s64_u64(VCLT(VLD(k + j), xv)));             \
            }                                                                 \
            return static_cast<unsigned>(-vaddvq_s64(acc));                   \
        }                                                                     \
                                                                              \
        static unsigned le(const KEY* k, KEY x)                               \
        {                                                                     \
            auto xv = VDUP(x);                                                \
            int64x2_t acc = vdupq_n_s64(0);                                   \
            for (int j = 0; j < B; j += 2)                                    \
            {                                                                 \
                acc = vaddq_s64(acc,                                          \
                    vreinterpretq_s64_u64(VCLE(VLD(k + j), xv)));             \
            }                                                                 \
            return static_cast<unsigned>(-vaddvq_s64(acc));                   \
        }                                                                     \
    };

DYNMAP_DEFINE_RANK_32(std::int32_t,  vdupq_n_s32, vld1q_s32, vcltq_s32, vcleq_s32)
DYNMAP_DEFINE_RANK_32(std::uint32_t, vdupq_n_u32, vld1q_u32, vcltq_u32, vcleq_u32)
DYNMAP_DEFINE_RANK_32(float,         vdupq_n_f32, vld1q_f32, vcltq_f32, vcleq_f32)

DYNMAP_DEFINE_RANK_64(std::int64_t,  vdupq_n_s64, vld1q_s64, vcltq_s64, vcleq_s64)
DYNMAP_DEFINE_RANK_64(std::uint64_t, vdupq_n_u64, vld1q_u64, vcltq_u64, vcleq_u64)
DYNMAP_DEFINE_RANK_64(double,        vdupq_n_f64, vld1q_f64, vcltq_f64, vcleq_f64)

#undef DYNMAP_DEFINE_RANK_32
#undef DYNMAP_DEFINE_RANK_64

#endif // DYNMAP_HAS_NEON

#if DYNMAP_HAS_SSE2

// x86 kernels: same count-of-true-lanes structure as NEON (a true compare lane reads as -1, so the
// negated horizontal sum is the count) with two x86-specific twists. (1) SSE has no unsigned integer
// compares, so unsigned keys are XOR-biased by the sign bit into signed order first -- the bias vector
// is all-zero for signed keys and the XOR folds away. (2) SSE2 has no integer <=, so rank_le counts
// the STRICT > lanes instead and returns B minus that ("<= x" == "not > x"; padding sentinels compare
// > x for every x below the sentinel, exactly matching the scalar contract). Rank order under the
// sign-bit bias is preserved because std::less on the unsigned type is (static_assert'd) the ordering.

// horizontal sums of 4x32 / 2x64 accumulated lane sums (SSE2-only shuffles, no SSE3 hadd).
inline int dynmap_sse_hsum32(__m128i acc)
{
    __m128i sum = _mm_add_epi32(acc, _mm_shuffle_epi32(acc, _MM_SHUFFLE(1, 0, 3, 2)));
    sum         = _mm_add_epi32(sum, _mm_shuffle_epi32(sum, _MM_SHUFFLE(2, 3, 0, 1)));
    return _mm_cvtsi128_si32(sum);
}

inline long long dynmap_sse_hsum64(__m128i acc)
{
    const __m128i sum = _mm_add_epi64(acc, _mm_shuffle_epi32(acc, _MM_SHUFFLE(1, 0, 3, 2)));
    return _mm_cvtsi128_si64(sum);
}

// 32-bit-lane integer keys: four lanes per vector; BIAS is the sign bit for unsigned, zero for signed.
#define DYNMAP_DEFINE_RANK_SSE_I32(KEY, BIAS)                                  \
    template <int B>                                                          \
    struct node_rank<KEY, B, void>                                            \
    {                                                                         \
        static unsigned lt(const KEY* k, KEY x)                               \
        {                                                                     \
            const __m128i bias = BIAS;                                        \
            const __m128i xv   = _mm_xor_si128(_mm_set1_epi32(int(x)), bias); \
            __m128i acc        = _mm_setzero_si128();                         \
            for (int j = 0; j < B; j += 4)                                    \
            {                                                                 \
                const __m128i kv = _mm_xor_si128(                             \
                    _mm_load_si128(reinterpret_cast<const __m128i*>(k + j)),  \
                    bias);                                                    \
                acc = _mm_add_epi32(acc, _mm_cmplt_epi32(kv, xv));            \
            }                                                                 \
            return static_cast<unsigned>(-dynmap_sse_hsum32(acc));            \
        }                                                                     \
                                                                              \
        static unsigned le(const KEY* k, KEY x)                               \
        {                                                                     \
            const __m128i bias = BIAS;                                        \
            const __m128i xv   = _mm_xor_si128(_mm_set1_epi32(int(x)), bias); \
            __m128i acc        = _mm_setzero_si128();                         \
            for (int j = 0; j < B; j += 4)                                    \
            {                                                                 \
                const __m128i kv = _mm_xor_si128(                             \
                    _mm_load_si128(reinterpret_cast<const __m128i*>(k + j)),  \
                    bias);                                                    \
                acc = _mm_add_epi32(acc, _mm_cmpgt_epi32(kv, xv));            \
            }                                                                 \
            return static_cast<unsigned>(B + dynmap_sse_hsum32(acc));         \
        }                                                                     \
    };

DYNMAP_DEFINE_RANK_SSE_I32(std::int32_t,  _mm_setzero_si128())
DYNMAP_DEFINE_RANK_SSE_I32(std::uint32_t, _mm_set1_epi32(int(0x80000000)))

#undef DYNMAP_DEFINE_RANK_SSE_I32

// floats: direct SSE2 compares exist for both < and <=, so no bias and no B-minus-gt detour.
template <int B>
struct node_rank<float, B, void>
{
    static unsigned lt(const float* k, float x)
    {
        const __m128 xv = _mm_set1_ps(x);
        __m128i acc     = _mm_setzero_si128();
        for (int j = 0; j < B; j += 4)
        {
            acc = _mm_add_epi32(acc, _mm_castps_si128(_mm_cmplt_ps(_mm_load_ps(k + j), xv)));
        }
        return static_cast<unsigned>(-dynmap_sse_hsum32(acc));
    }

    static unsigned le(const float* k, float x)
    {
        const __m128 xv = _mm_set1_ps(x);
        __m128i acc     = _mm_setzero_si128();
        for (int j = 0; j < B; j += 4)
        {
            acc = _mm_add_epi32(acc, _mm_castps_si128(_mm_cmple_ps(_mm_load_ps(k + j), xv)));
        }
        return static_cast<unsigned>(-dynmap_sse_hsum32(acc));
    }
};

template <int B>
struct node_rank<double, B, void>
{
    static unsigned lt(const double* k, double x)
    {
        const __m128d xv = _mm_set1_pd(x);
        __m128i acc      = _mm_setzero_si128();
        for (int j = 0; j < B; j += 2)
        {
            acc = _mm_add_epi64(acc, _mm_castpd_si128(_mm_cmplt_pd(_mm_load_pd(k + j), xv)));
        }
        return static_cast<unsigned>(-dynmap_sse_hsum64(acc));
    }

    static unsigned le(const double* k, double x)
    {
        const __m128d xv = _mm_set1_pd(x);
        __m128i acc      = _mm_setzero_si128();
        for (int j = 0; j < B; j += 2)
        {
            acc = _mm_add_epi64(acc, _mm_castpd_si128(_mm_cmple_pd(_mm_load_pd(k + j), xv)));
        }
        return static_cast<unsigned>(-dynmap_sse_hsum64(acc));
    }
};

#if defined(__SSE4_2__)

// 64-bit-lane integer keys need _mm_cmpgt_epi64 (SSE4.2). Below x86-64-v2 these stay on the scalar
// template -- build with -march=x86-64-v2 (or your build's native-arch option) to light them up; the production
// instantiation (quality.h ScratchMap, uint64_t keys) is the one that benefits. Only > exists, so
// lt counts x > k and le counts B minus (k > x).
#define DYNMAP_DEFINE_RANK_SSE_I64(KEY, BIAS)                                  \
    template <int B>                                                          \
    struct node_rank<KEY, B, void>                                            \
    {                                                                         \
        static unsigned lt(const KEY* k, KEY x)                               \
        {                                                                     \
            const __m128i bias = BIAS;                                        \
            const __m128i xv   = _mm_xor_si128(                               \
                _mm_set1_epi64x(static_cast<long long>(x)), bias);            \
            __m128i acc        = _mm_setzero_si128();                         \
            for (int j = 0; j < B; j += 2)                                    \
            {                                                                 \
                const __m128i kv = _mm_xor_si128(                             \
                    _mm_load_si128(reinterpret_cast<const __m128i*>(k + j)),  \
                    bias);                                                    \
                acc = _mm_add_epi64(acc, _mm_cmpgt_epi64(xv, kv));            \
            }                                                                 \
            return static_cast<unsigned>(-dynmap_sse_hsum64(acc));            \
        }                                                                     \
                                                                              \
        static unsigned le(const KEY* k, KEY x)                               \
        {                                                                     \
            const __m128i bias = BIAS;                                        \
            const __m128i xv   = _mm_xor_si128(                               \
                _mm_set1_epi64x(static_cast<long long>(x)), bias);            \
            __m128i acc        = _mm_setzero_si128();                         \
            for (int j = 0; j < B; j += 2)                                    \
            {                                                                 \
                const __m128i kv = _mm_xor_si128(                             \
                    _mm_load_si128(reinterpret_cast<const __m128i*>(k + j)),  \
                    bias);                                                    \
                acc = _mm_add_epi64(acc, _mm_cmpgt_epi64(kv, xv));            \
            }                                                                 \
            return static_cast<unsigned>(B + dynmap_sse_hsum64(acc));         \
        }                                                                     \
    };

DYNMAP_DEFINE_RANK_SSE_I64(std::int64_t,  _mm_setzero_si128())
DYNMAP_DEFINE_RANK_SSE_I64(std::uint64_t, _mm_set1_epi64x(static_cast<long long>(0x8000000000000000ull)))

#undef DYNMAP_DEFINE_RANK_SSE_I64

#endif // __SSE4_2__

#endif // DYNMAP_HAS_SSE2

// =============================================================================
//  Node layouts (templated on width B).
//
//  Both node types are aligned to 16 (NEON vector granularity), NOT to a full
//  cache line. Member order follows the search path: keys[] FIRST and 16-aligned
//  (so the SIMD scan loads from a vector boundary); child handles / values next
//  (touched only after the rank picks one index); count and links last. Child
//  references are 32-bit handles (half a pointer, more children per line,
//  relocatable). No parent link. Values are a separate array from keys (SoA
//  in-node) so a key scan never reads value bytes.
//
//  Why 16 and not a cache line: cache-line alignment rounds each node's size up
//  to a multiple of 64, burning dead padding (e.g. B=16 leaf 208->256, internal
//  144->192) that lowers cache density and slows lookups. 16-byte alignment is
//  all the NEON loads need; pooled nodes still pack tightly. Measured a modest
//  win across the board (B=32 find 99->91, iter 6.1->5.6 ns) with no regression.
//
//  "count last" is MEASURED, not an oversight (A/B 2026-06): moving count+links
//  between keys[] and values[] reads nicely on paper (count is read on every
//  node visit) but pushes values[] 16 bytes further out -- find(hit) regressed
//  67->88 ns (u32, B=20) because the hit's value load left the line(s) the key
//  scan had just pulled. The count read is cheap where it is: its line is
//  shared with the tail of values[] (hits near the leaf end get it free) and
//  with next/prev on ordered walks. Re-measure before reordering.
// =============================================================================
template <typename Key, int B>
struct alignas(16) internal_node
{
    Key            keys[B];          // scan region, 16-aligned
    handle_t       children[B + 1];  // B + 1 child handles (one read per descent)
    std::uint16_t  count;            // number of keys in use, 0..B
    std::uint16_t  pad_;             // explicit, deterministic padding
    handle_t       free_link;        // intrusive free-list link when unused
};

template <typename Key, typename Value, int B>
struct alignas(16) leaf_node
{
    Key            keys[B];          // scan region, 16-aligned
    Value          values[B];        // parallel values (SoA, off the scan path; one read per hit)
    handle_t       next;             // next leaf (ordered iteration / range)
    handle_t       prev;             // previous leaf
    std::uint16_t  count;
    std::uint16_t  pad_;
    handle_t       free_link;
};

// =============================================================================
//  dynamic_map
//
//  Template parameters: Key, Value, node width B (default 16), Compare.
// =============================================================================
template <typename Key,
          typename Value,
          int B = 16,
          typename Compare = std::less<Key>>
class dynamic_map
{
    static_assert(std::is_arithmetic<Key>::value,
                  "dynamic_map requires an arithmetic Key (reserves numeric max "
                  "as padding; use the static_map for string-like keys).");
    static_assert(std::is_default_constructible<Value>::value,
                  "dynamic_map keeps all value slots live for a node's lifetime, "
                  "so Value must be default constructible.");
    static_assert(std::is_same<Compare, std::less<Key>>::value,
                  "dynamic_map supports only std::less<Key>: the padding sentinel "
                  "is the key's numeric max, which is the greatest element only "
                  "under the numeric ordering. Any other comparator would count "
                  "padding slots into every rank and silently corrupt the tree.");

    // Number of key lanes in a 128-bit vector (NEON or SSE) for this key (4 for
    // 32-bit, 2 for 64-bit). B must be a whole multiple so the SIMD scan divides
    // the node evenly with no tail.
    static constexpr int kVectorLanes =
        (sizeof(Key) <= 16) ? static_cast<int>(16 / sizeof(Key)) : 1;

    static_assert(B % kVectorLanes == 0,
                  "node width B must be a multiple of the 128-bit SIMD lane count "
                  "for Key (16 / sizeof(Key)) so the SIMD scan fits evenly.");
    static_assert(B >= 4 && (B % 2 == 0),
                  "node width B must be even and at least 4.");

public:
    using key_type    = Key;
    using mapped_type  = Value;
    using value_type   = std::pair<const Key, Value>;
    using size_type    = std::size_t;
    using key_compare  = Compare;

    static constexpr int node_width = B;

private:
    static constexpr int MAX_KEYS = B;
    static constexpr int MIN_KEYS = B / 2;

    using Internal = internal_node<Key, B>;
    using Leaf     = leaf_node<Key, Value, B>;
    using Rank     = node_rank<Key, B>;

    // --- pools (allocated once) ---
    Internal* internal_pool_ = nullptr;
    Leaf*     leaf_pool_     = nullptr;
    std::uint32_t internal_capacity_ = 0;
    std::uint32_t leaf_capacity_     = 0;

    handle_t internal_free_ = NIL;
    handle_t leaf_free_     = NIL;

    // --- tree state ---
    handle_t  root_     = NIL;
    int       height_   = 1;  // number of levels; 1 => root is a leaf
    size_type size_     = 0;
    size_type capacity_ = 0;  // the declared element bound (enforced at insert)

    // ------------------------------------------------------------------ pools
    // The chokepoint every leaf access funnels through. The VERIFY catches NIL
    // handles, foreign handles, and use-after-move in one place -- and in release
    // it is an assume the optimiser can use.
    Leaf& leaf_at(handle_t h)
    {
        DYNMAP_VERIFY(h < leaf_capacity_);
        return leaf_pool_[h];
    }

    const Leaf& leaf_at(handle_t h) const
    {
        DYNMAP_VERIFY(h < leaf_capacity_);
        return leaf_pool_[h];
    }

    handle_t alloc_leaf()
    {
        // Within the declared capacity (enforced at insert) the pool sizing
        // guarantees a free node, so reaching NIL here means a corrupt invariant
        // -- and indexing with NIL would be a wild write. Always-on trap.
        if (leaf_free_ == NIL)
        {
            DYNMAP_PANIC("leaf pool exhausted -- declared capacity bound violated");
        }

        handle_t h = leaf_free_;
        leaf_free_ = leaf_pool_[h].free_link;

        Leaf& leaf = leaf_pool_[h];
        leaf.count = 0;
        leaf.next = NIL;
        leaf.prev = NIL;
        fill_sentinel(leaf.keys);

        return h;
    }

    handle_t alloc_internal()
    {
        if (internal_free_ == NIL)
        {
            DYNMAP_PANIC("internal pool exhausted -- declared capacity bound violated");
        }

        handle_t h = internal_free_;
        internal_free_ = internal_pool_[h].free_link;

        Internal& node = internal_pool_[h];
        node.count = 0;
        fill_sentinel(node.keys);

        return h;
    }

    // Reset a value slot so a vacated slot does not pin Value resources. For
    // trivially-destructible payloads (the common void* / int case) there is
    // nothing to release and the store is skipped entirely.
    static void release_value(Value& v)
    {
        if constexpr (!std::is_trivially_destructible<Value>::value)
        {
            v = Value{};
        }
    }

    void free_leaf(handle_t h)
    {
        // Release value resources so a recycled leaf does not pin memory.
        for (int i = 0; i < MAX_KEYS; ++i)
        {
            release_value(leaf_pool_[h].values[i]);
        }

        leaf_pool_[h].free_link = leaf_free_;
        leaf_free_ = h;
    }

    void free_internal(handle_t h)
    {
        internal_pool_[h].free_link = internal_free_;
        internal_free_ = h;
    }

    static void fill_sentinel(Key* keys)
    {
        for (int i = 0; i < MAX_KEYS; ++i)
        {
            keys[i] = sentinel<Key>::value();
        }
    }

    // Equality under the (static_assert'd) std::less numeric ordering. Direct ==
    // rather than the two-comparison form: identical for every legal (finite)
    // key, and the finite-key contract is VERIFY'd at the public seams.
    static bool keys_equal(const Key& a, const Key& b)
    {
        return a == b;
    }

    // The finite-key contract test for floating keys, as a bit test so it
    // SURVIVES -ffast-math (a plain isfinite() folds to true under fast-math;
    // same rationale as fastmath::isFiniteFast, kept local so the header stays
    // standalone). Non-floating keys are trivially fine.
    static bool key_is_finite(const Key& k)
    {
        if constexpr (std::is_same<Key, float>::value)
        {
            std::uint32_t bits;
            std::memcpy(&bits, &k, sizeof bits);
            return (bits & 0x7F800000u) != 0x7F800000u;
        }
        else if constexpr (std::is_same<Key, double>::value)
        {
            std::uint64_t bits;
            std::memcpy(&bits, &k, sizeof bits);
            return (bits & 0x7FF0000000000000ull) != 0x7FF0000000000000ull;
        }
        else
        {
            (void) k;
            return true;
        }
    }

    // In-node child index for descent: count of separators <= x, clamped to the
    // number of children. The clamp is LOAD-BEARING for x == numeric max (a legal
    // key equal to the padding sentinel): rank_le then counts padding slots too,
    // and without the clamp the descent would index past children[count].
    unsigned child_index(const Internal& node, const Key& x) const
    {
        unsigned i = Rank::le(node.keys, x);

        return (i > node.count) ? node.count : i;
    }

    // In-leaf lower-bound position: count of keys < x. NO clamp needed: the
    // strict < never counts a padding slot (sentinel < x is false for every
    // legal x, including x == sentinel itself), so the rank is <= count by
    // construction.
    unsigned leaf_lower(const Leaf& leaf, const Key& x) const
    {
        return Rank::lt(leaf.keys, x);
    }

public:
    // -------------------------------------------------------------------------
    //  Construction. `capacity` is the maximum number of elements the container
    //  will ever hold at once; pools are sized from it and never grow.
    // -------------------------------------------------------------------------
    explicit dynamic_map(size_type capacity, const Compare& = Compare())
        : capacity_(capacity)
    {
        std::uint64_t leaves = capacity / MIN_KEYS + 4;

        std::uint64_t internal = 0;
        std::uint64_t level = leaves;
        while (level > 1)
        {
            // Parents needed to fan in `level` children, over-estimated by
            // dividing by MIN_KEYS (<= the true min child count MIN_KEYS+1).
            // Guard strict descent: at MIN_KEYS==2 (B==4) the bare formula has a
            // fixed point at level==2 (2/2+1==2) and would spin forever; for
            // B>=6 the formula already decreases, so the guard is a no-op there.
            std::uint64_t parents = level / MIN_KEYS + 1;
            if( parents >= level )
            {
                parents = level - 1;
            }
            level = parents;
            internal += level;
        }
        internal += 4; // slack for split cascades + the root

        // Handles are 32-bit; a capacity large enough to wrap the node counts
        // would silently size an undersized pool.
        DYNMAP_VERIFY(leaves <= 0xFFFFFFFFu && internal <= 0xFFFFFFFFu);

        leaf_capacity_     = static_cast<std::uint32_t>(leaves);
        internal_capacity_ = static_cast<std::uint32_t>(internal);

        leaf_pool_     = new Leaf[leaf_capacity_];
        internal_pool_ = new Internal[internal_capacity_];

        for (std::uint32_t i = 0; i < leaf_capacity_; ++i)
        {
            leaf_pool_[i].free_link = (i + 1 < leaf_capacity_) ? (i + 1) : NIL;
        }
        leaf_free_ = (leaf_capacity_ > 0) ? 0 : NIL;

        for (std::uint32_t i = 0; i < internal_capacity_; ++i)
        {
            internal_pool_[i].free_link =
                (i + 1 < internal_capacity_) ? (i + 1) : NIL;
        }
        internal_free_ = (internal_capacity_ > 0) ? 0 : NIL;

        root_ = alloc_leaf();
        height_ = 1;
    }

    ~dynamic_map()
    {
        delete[] leaf_pool_;
        delete[] internal_pool_;
    }

    dynamic_map(const dynamic_map&) = delete;
    dynamic_map& operator=(const dynamic_map&) = delete;

    dynamic_map(dynamic_map&& other) noexcept
    {
        steal(std::move(other));
    }

    dynamic_map& operator=(dynamic_map&& other) noexcept
    {
        if (this != &other)
        {
            delete[] leaf_pool_;
            delete[] internal_pool_;
            steal(std::move(other));
        }
        return *this;
    }

private:
    void steal(dynamic_map&& o) noexcept
    {
        internal_pool_ = o.internal_pool_;
        leaf_pool_ = o.leaf_pool_;
        internal_capacity_ = o.internal_capacity_;
        leaf_capacity_ = o.leaf_capacity_;
        internal_free_ = o.internal_free_;
        leaf_free_ = o.leaf_free_;
        root_ = o.root_;
        height_ = o.height_;
        size_ = o.size_;
        capacity_ = o.capacity_;

        // Leave the source in a CONSISTENT empty-husk state: every field that
        // referenced the stolen pools is cleared, so a stray operation on the
        // moved-from map hits the leaf_at()/descent VERIFYs instead of walking
        // stale handles into freed (or stolen) memory. Contract: a moved-from
        // map supports only destruction, move-assignment-into, and the trivial
        // size queries.
        o.internal_pool_ = nullptr;
        o.leaf_pool_ = nullptr;
        o.leaf_capacity_ = 0;
        o.internal_capacity_ = 0;
        o.internal_free_ = NIL;
        o.leaf_free_ = NIL;
        o.size_ = 0;
        o.capacity_ = 0;
        o.root_ = NIL;
        o.height_ = 1;
    }

public:
    // ------------------------------------------------------------- capacity
    bool empty() const noexcept
    {
        return size_ == 0;
    }

    size_type size() const noexcept
    {
        return size_;
    }

    // The declared element bound from construction. Inserting a NEW key while
    // full() is rejected ({end(), false}); pre-check with remaining()/full()
    // where rejection is not acceptable (operator[] PANICs instead -- it has no
    // failure channel).
    size_type capacity() const noexcept
    {
        return capacity_;
    }

    size_type remaining() const noexcept
    {
        return capacity_ - size_;
    }

    bool full() const noexcept
    {
        return size_ >= capacity_;
    }

    // Number of levels: 1 means the root is a leaf. Drops after compact().
    int height() const noexcept
    {
        return height_;
    }

    // Leaf-chain length (walks the chain; counts 0 for an empty map even though
    // an empty root leaf is live). Diagnostic; O(number of leaves).
    size_type leaf_count() const noexcept
    {
        size_type n = 0;
        for (handle_t h = (size_ ? leftmost_leaf() : NIL); h != NIL;
             h = leaf_pool_[h].next)
        {
            ++n;
        }
        return n;
    }

    // -------------------------------------------------------------- iterator
    //  One iterator body, parameterised on const-ness, yields both `iterator`
    //  (mutable mapped value) and `const_iterator`. NOTE: because the node layout
    //  is SoA (keys[] and values[] are separate arrays), there is no physical
    //  std::pair in the container -- operator*/operator-> synthesise a pair of
    //  references. `&it->second` is a valid Value* and `&it->first` a valid Key*,
    //  but you cannot take a value_type* into the map. Iterators and the
    //  references they hand out are invalidated by insert/erase/compact (a leaf
    //  split relocates elements); this is vector/flat_map semantics, NOT the
    //  node-stable guarantee of std::map.
    template <bool IsConst>
    class basic_iterator
    {
        using owner_ptr  = std::conditional_t<IsConst, const dynamic_map*,
                                                       dynamic_map*>;
        using mapped_ref = std::conditional_t<IsConst, const Value&, Value&>;

    public:
        using iterator_category = std::bidirectional_iterator_tag;
        using value_type        = std::pair<const Key, Value>;
        using difference_type   = std::ptrdiff_t;
        using reference         = std::pair<const Key&, mapped_ref>;

        // Arrow proxy: holds the synthesised reference pair so `it->first` /
        // `it->second` resolve (and, for a mutable iterator, assign through).
        struct pointer
        {
            reference  kv;
            reference* operator->() { return &kv; }
        };

        basic_iterator() = default;

        // Mutable -> const conversion (one-way), like std::map.
        template <bool C, typename = std::enable_if_t<IsConst && !C>>
        basic_iterator(const basic_iterator<C>& o)
            : owner_(o.owner_), leaf_h_(o.leaf_h_), index_(o.index_)
        {
        }

        reference operator*() const
        {
            auto& leaf = owner_->leaf_at(leaf_h_);
            return reference(leaf.keys[index_], leaf.values[index_]);
        }

        pointer operator->() const
        {
            return pointer{ **this };
        }

        const Key& key() const
        {
            return owner_->leaf_at(leaf_h_).keys[index_];
        }

        mapped_ref mapped() const
        {
            return owner_->leaf_at(leaf_h_).values[index_];
        }

        basic_iterator& operator++()
        {
            auto& leaf = owner_->leaf_at(leaf_h_);

            if (index_ + 1 < leaf.count)
            {
                ++index_;
            }
            else
            {
                leaf_h_ = leaf.next;
                index_ = 0;
            }
            return *this;
        }

        basic_iterator operator++(int)
        {
            basic_iterator tmp = *this;
            ++(*this);
            return tmp;
        }

        basic_iterator& operator--()
        {
            if (leaf_h_ == NIL)
            {
                DYNMAP_VERIFY(owner_ && owner_->size_ > 0); // --end() on an empty map
                leaf_h_ = owner_->rightmost_leaf();
                index_ = owner_->leaf_at(leaf_h_).count - 1;
            }
            else if (index_ > 0)
            {
                --index_;
            }
            else
            {
                leaf_h_ = owner_->leaf_at(leaf_h_).prev; // NIL here == --begin(): leaf_at traps it
                index_ = owner_->leaf_at(leaf_h_).count - 1;
            }
            return *this;
        }

        basic_iterator operator--(int)
        {
            basic_iterator tmp = *this;
            --(*this);
            return tmp;
        }

        template <bool C>
        bool operator==(const basic_iterator<C>& o) const
        {
            return owner_ == o.owner_ && leaf_h_ == o.leaf_h_ &&
                   index_ == o.index_;
        }

        template <bool C>
        bool operator!=(const basic_iterator<C>& o) const
        {
            return !(*this == o);
        }

    private:
        friend class dynamic_map;
        template <bool> friend class basic_iterator;

        basic_iterator(owner_ptr owner, handle_t leaf_h, int index)
            : owner_(owner), leaf_h_(leaf_h), index_(index)
        {
        }

        owner_ptr owner_ = nullptr;
        handle_t  leaf_h_ = NIL;
        int       index_ = 0;
    };

    using iterator       = basic_iterator<false>;
    using const_iterator = basic_iterator<true>;

    // ---------------------------------------------------------- value iterator
    //  Forward iterator over VALUES ONLY. Most iteration over these maps reads
    //  the mapped value and ignores the key, and because the node layout is SoA
    //  (values[] is a separate array from keys[]), a values-only walk never
    //  touches the key cache lines and hands back a real `Value&` -- no synthesised
    //  pair, no key load. It caches the current leaf's values[] base + count, so
    //  the inner loop is a contiguous pointer walk that only re-seats at a leaf
    //  boundary (after compact(), leaves are pool-ordered, so this streams).
    //  Same invalidation rules as basic_iterator (insert/erase/compact relocate).
    template <bool IsConst>
    class basic_value_iterator
    {
        using owner_ptr = std::conditional_t<IsConst, const dynamic_map*,
                                                      dynamic_map*>;
        using val_ptr   = std::conditional_t<IsConst, const Value*, Value*>;
        using val_ref   = std::conditional_t<IsConst, const Value&, Value&>;

    public:
        using iterator_category = std::forward_iterator_tag;
        using value_type        = Value;
        using difference_type   = std::ptrdiff_t;
        using reference         = val_ref;
        using pointer           = val_ptr;

        basic_value_iterator() = default;

        // Mutable -> const conversion (one-way).
        template <bool C, typename = std::enable_if_t<IsConst && !C>>
        basic_value_iterator(const basic_value_iterator<C>& o)
            : owner_(o.owner_), base_(o.base_), leaf_h_(o.leaf_h_),
              next_(o.next_), index_(o.index_), count_(o.count_)
        {
        }

        val_ref operator*()  const { return base_[index_]; }
        val_ptr operator->() const { return base_ + index_; }

        basic_value_iterator& operator++()
        {
            if (++index_ >= count_)   // ran off this leaf -> seat the next one
            {
                leaf_h_ = next_;
                seat();
            }
            return *this;
        }

        basic_value_iterator operator++(int)
        {
            basic_value_iterator tmp = *this;
            ++(*this);
            return tmp;
        }

        template <bool C>
        bool operator==(const basic_value_iterator<C>& o) const
        {
            // owner_ participates so iterators from different maps never compare
            // equal -- matching basic_iterator's semantics.
            return owner_ == o.owner_ && leaf_h_ == o.leaf_h_ && index_ == o.index_;
        }

        template <bool C>
        bool operator!=(const basic_value_iterator<C>& o) const
        {
            return !(*this == o);
        }

    private:
        friend class dynamic_map;
        template <bool> friend class basic_value_iterator;

        basic_value_iterator(owner_ptr owner, handle_t leaf_h)
            : owner_(owner), leaf_h_(leaf_h)
        {
            seat();
        }

        // Load the current leaf's values[] base / count / next, or become end().
        void seat()
        {
            if (leaf_h_ == NIL)
            {
                base_ = nullptr;
                count_ = 0;
                next_ = NIL;
                index_ = 0;
                return;
            }
            auto& leaf = owner_->leaf_at(leaf_h_);
            base_  = leaf.values;
            count_ = leaf.count;
            next_  = leaf.next;
            index_ = 0;
        }

        owner_ptr owner_  = nullptr;
        val_ptr   base_   = nullptr;
        handle_t  leaf_h_ = NIL;
        handle_t  next_   = NIL;
        int       index_  = 0;
        int       count_  = 0;
    };

    using value_iterator       = basic_value_iterator<false>;
    using const_value_iterator = basic_value_iterator<true>;

    // Rebuild a mutable iterator at the same position as a const one (the
    // enclosing class is a friend, so it can read the const iterator's slot).
    iterator unconst(const_iterator c)
    {
        DYNMAP_VERIFY(c.owner_ == this); // an iterator from ANOTHER map is a stale-handle bug
        return iterator(this, c.leaf_h_, c.index_);
    }

    const_iterator begin() const
    {
        if (size_ == 0)
        {
            return end();
        }
        return const_iterator(this, leftmost_leaf(), 0);
    }

    const_iterator end() const
    {
        return const_iterator(this, NIL, 0);
    }

    iterator begin()
    {
        if (size_ == 0)
        {
            return end();
        }
        return iterator(this, leftmost_leaf(), 0);
    }

    iterator end()
    {
        return iterator(this, NIL, 0);
    }

    const_iterator cbegin() const { return begin(); }
    const_iterator cend()   const { return end(); }

    // Reverse iteration. std::reverse_iterator composes with the proxy-pair
    // reference because the proxy is returned BY VALUE (binding it is fine);
    // operator-- already handles the --end() seat-at-rightmost case.
    using reverse_iterator       = std::reverse_iterator<iterator>;
    using const_reverse_iterator = std::reverse_iterator<const_iterator>;

    reverse_iterator       rbegin()        { return reverse_iterator(end()); }
    reverse_iterator       rend()          { return reverse_iterator(begin()); }
    const_reverse_iterator rbegin()  const { return const_reverse_iterator(end()); }
    const_reverse_iterator rend()    const { return const_reverse_iterator(begin()); }
    const_reverse_iterator crbegin() const { return rbegin(); }
    const_reverse_iterator crend()   const { return rend(); }

    // ------------------------------------------------------- values-only walk
    // A forward iterator that visits only the leaf value[] arrays.  Most
    // iteration consumers only read the mapped value; walking values[] alone
    // moves half the bytes of the proxy-pair iterator (values[] is a separate
    // 8B/entry SoA array, never interleaved with keys) and never touches the
    // keys[] cache lines, so it is both cheaper and more cache-friendly.
    value_iterator       values_begin()       { return size_ ? value_iterator(this, leftmost_leaf())       : value_iterator(this, NIL); }
    value_iterator       values_end()         { return value_iterator(this, NIL); }
    const_value_iterator values_begin() const { return size_ ? const_value_iterator(this, leftmost_leaf()) : const_value_iterator(this, NIL); }
    const_value_iterator values_end()   const { return const_value_iterator(this, NIL); }
    const_value_iterator values_cbegin() const { return values_begin(); }
    const_value_iterator values_cend()   const { return values_end(); }

    // Lightweight range views so `for (auto& v : m.values())` works.
    struct values_view
    {
        dynamic_map* m;
        value_iterator begin() const { return m->values_begin(); }
        value_iterator end()   const { return m->values_end(); }
    };
    struct const_values_view
    {
        const dynamic_map* m;
        const_value_iterator begin() const { return m->values_begin(); }
        const_value_iterator end()   const { return m->values_end(); }
    };
    values_view       values()       { return values_view{ this }; }
    const_values_view values() const { return const_values_view{ this }; }

    // ---------------------------------------------------------------- lookup
    const_iterator lower_bound(const Key& x) const
    {
        DYNMAP_VERIFY(leaf_pool_ != nullptr);  // moved-from map (see steal())
        DYNMAP_VERIFY(key_is_finite(x));       // inf/NaN break the sentinel ordering

        handle_t h = root_;

        for (int level = height_ - 1; level > 0; --level)
        {
            const Internal& node = internal_pool_[h];
            h = node.children[child_index(node, x)];
        }

        const Leaf& leaf = leaf_pool_[h];
        unsigned pos = leaf_lower(leaf, x);

        if (pos == leaf.count)
        {
            handle_t nxt = leaf.next;
            if (nxt == NIL)
            {
                return end();
            }
            return const_iterator(this, nxt, 0);
        }

        return const_iterator(this, h, static_cast<int>(pos));
    }

    const_iterator upper_bound(const Key& x) const
    {
        const_iterator it = lower_bound(x);

        if (it != end() && keys_equal(it.key(), x))
        {
            ++it;
        }
        return it;
    }

    const_iterator find(const Key& x) const
    {
        const_iterator it = lower_bound(x);

        if (it != end() && keys_equal(it.key(), x))
        {
            return it;
        }
        return end();
    }

    bool contains(const Key& x) const
    {
        return find(x) != end();
    }

    size_type count(const Key& x) const
    {
        return contains(x) ? 1 : 0;
    }

    std::pair<const_iterator, const_iterator> equal_range(const Key& x) const
    {
        const_iterator lo = lower_bound(x);
        const_iterator hi = lo;
        if (hi != end() && keys_equal(hi.key(), x))
        {
            ++hi;
        }
        return { lo, hi };
    }

    std::pair<iterator, iterator> equal_range(const Key& x)
    {
        auto [lo, hi] = static_cast<const dynamic_map*>(this)->equal_range(x);
        return { lo == cend() ? end() : unconst(lo),
                 hi == cend() ? end() : unconst(hi) };
    }

    key_compare key_comp() const
    {
        return key_compare{};
    }

    const Value& at(const Key& x) const
    {
        const_iterator it = find(x);
        if (it == end())
        {
            throw std::out_of_range("dynamic_map::at: key not found");
        }
        return it.mapped();
    }

    // Non-const lookup overloads: reuse the const descent, then re-seat the
    // result as a mutable iterator so callers can assign through it->second.
    iterator find(const Key& x)
    {
        const_iterator it = static_cast<const dynamic_map*>(this)->find(x);
        return (it == end()) ? end() : unconst(it);
    }

    iterator lower_bound(const Key& x)
    {
        const_iterator it = static_cast<const dynamic_map*>(this)->lower_bound(x);
        return (it == end()) ? end() : unconst(it);
    }

    iterator upper_bound(const Key& x)
    {
        const_iterator it = static_cast<const dynamic_map*>(this)->upper_bound(x);
        return (it == end()) ? end() : unconst(it);
    }

    Value& at(const Key& x)
    {
        return const_cast<Value&>(static_cast<const dynamic_map*>(this)->at(x));
    }

    // --------------------------------------------------------------- mutate
    // insert/insert_or_assign return a MUTABLE iterator, exactly like std::map.
    // All inserts take Value BY VALUE (sink parameter): rvalues move in with no
    // copy, lvalues pay the same single copy as before -- and the copy happens
    // BEFORE any node mutation, so `m.insert(k, m.at(other))` (a value aliasing
    // an element of this same map) is safe; the old const& surface read the
    // argument AFTER shifting slots and could store a moved-from neighbor.
    //
    // Capacity contract: inserting a NEW key while full() returns {end(), false}
    // and changes nothing (graceful degrade -- check full()/remaining() to avoid
    // it). Hits on existing keys never fail.
    std::pair<iterator, bool> insert(const Key& key, Value value)
    {
        return emplace_impl(key, std::move(value), /*overwrite=*/false);
    }

    // std::map-style pair insert (e.g. insert({k, v}) or insert(value_type(...))).
    std::pair<iterator, bool> insert(const value_type& kv)
    {
        return emplace_impl(kv.first, Value(kv.second), /*overwrite=*/false);
    }

    std::pair<iterator, bool> insert(value_type&& kv)
    {
        return emplace_impl(kv.first, std::move(kv.second), /*overwrite=*/false);
    }

    std::pair<iterator, bool> insert_or_assign(const Key& key, Value value)
    {
        return emplace_impl(key, std::move(value), /*overwrite=*/true);
    }

    // try_emplace-shaped convenience. NOTE: unlike std::map::try_emplace, the
    // Value is constructed BEFORE the descent (the tree stores values in fixed
    // slots, so deferred construction buys nothing here) -- on a key hit the
    // constructed temporary is discarded. Fine for the cheap payloads this
    // container targets; documented so nobody relies on construction-on-miss.
    template <typename... Args>
    std::pair<iterator, bool> try_emplace(const Key& key, Args&&... args)
    {
        return emplace_impl(key, Value(std::forward<Args>(args)...),
                            /*overwrite=*/false);
    }

    // Range insert: each element through the normal single-element path.
    template <typename InputIt>
    void insert(InputIt first, InputIt last)
    {
        for (; first != last; ++first)
        {
            emplace_impl(first->first, Value(first->second), /*overwrite=*/false);
        }
    }

    Value& operator[](const Key& key)
    {
        auto [it, inserted] = emplace_impl(key, Value{}, /*overwrite=*/false);
        (void) inserted;

        // operator[] has no failure channel; the only way to land on end() is
        // the at-capacity rejection of a new key. That is a contract violation
        // with no graceful option, so trap loudly rather than return a wild ref.
        if (it == end())
        {
            DYNMAP_PANIC("operator[] on a NEW key with the map at capacity");
        }
        return it.mapped();
    }

    size_type erase(const Key& key)
    {
        DYNMAP_VERIFY(leaf_pool_ != nullptr);  // moved-from map (see steal())
        DYNMAP_VERIFY(key_is_finite(key));

        bool erased = false;
        erase_rec(root_, height_ - 1, key, erased);

        if (erased)
        {
            --size_;

            if (height_ > 1 && internal_pool_[root_].count == 0)
            {
                handle_t only_child = internal_pool_[root_].children[0];
                free_internal(root_);
                root_ = only_child;
                --height_;
            }
        }

        return erased ? 1 : 0;
    }

    // std::map-style erase by position. Returns an iterator to the element that
    // followed `pos`. We capture the successor's KEY first because the erase can
    // rebalance leaves and invalidate any held iterator, then re-seek it.
    iterator erase(const_iterator pos)
    {
        DYNMAP_VERIFY(pos.owner_ == this);  // foreign iterator == stale-handle bug
        DYNMAP_VERIFY(pos != cend());       // ++ below would walk leaf_pool_[NIL]

        const_iterator nxt = pos;
        ++nxt;

        bool has_next = (nxt != end());
        Key  next_key = has_next ? nxt.key() : Key{};

        erase(pos.key());

        return has_next ? find(next_key) : end();
    }

    // Range erase: [first, last). Captures last's key up front (every erase
    // invalidates iterators), then walks by successive erase(pos) re-seeks.
    iterator erase(const_iterator first, const_iterator last)
    {
        DYNMAP_VERIFY(first.owner_ == this && (last == cend() || last.owner_ == this));

        const bool to_end   = (last == cend());
        const Key  stop_key = to_end ? Key{} : last.key();

        iterator it = (first == cend()) ? end() : unconst(first);
        while (it != end() && (to_end || it.key() < stop_key))
        {
            it = erase(it);
        }
        return it;
    }

    // Member swap (std-canonical). Move-based: three steal()s, no element moves.
    void swap(dynamic_map& other) noexcept
    {
        if (this == &other)
        {
            return;
        }
        dynamic_map tmp(std::move(other));
        other = std::move(*this);
        *this = std::move(tmp);
    }

    // Drop every element and return to a single empty leaf. Pools are retained
    // (capacity is unchanged); only the free lists and root are reset.
    void clear()
    {
        // Release live values so a cleared map does not pin Value resources.
        // (Skipped entirely for trivially-destructible payloads.)
        if constexpr (!std::is_trivially_destructible<Value>::value)
        {
            for (handle_t h = (size_ ? leftmost_leaf() : NIL); h != NIL;
                 h = leaf_pool_[h].next)
            {
                Leaf& leaf = leaf_pool_[h];
                for (int i = 0; i < leaf.count; ++i)
                {
                    release_value(leaf.values[i]);
                }
            }
        }

        // Re-thread both pools into fresh free lists.
        for (std::uint32_t i = 0; i < leaf_capacity_; ++i)
        {
            leaf_pool_[i].free_link = (i + 1 < leaf_capacity_) ? (i + 1) : NIL;
        }
        leaf_free_ = (leaf_capacity_ > 0) ? 0 : NIL;

        for (std::uint32_t i = 0; i < internal_capacity_; ++i)
        {
            internal_pool_[i].free_link =
                (i + 1 < internal_capacity_) ? (i + 1) : NIL;
        }
        internal_free_ = (internal_capacity_ > 0) ? 0 : NIL;

        size_ = 0;
        root_ = alloc_leaf();
        height_ = 1;
    }

    // -------------------------------------------------------------------------
    //  compact() -- densifying bulk rebuild into a minimal-height B+ tree.
    //
    //  Random insert/erase leaves nodes ~69% full and scatters the leaf chain
    //  across the pool, so the tree is taller than necessary (more misses per
    //  lookup) and ordered iteration is a random memory walk (one cold miss per
    //  leaf, no prefetch slack through a singly-linked list). compact() streams
    //  every entry out in key order and rebuilds the tree bottom-up into fresh
    //  pools:
    //    * leaves packed to MAX_KEYS (last one balanced to >= MIN_KEYS), laid out
    //      in pool slots 0..L-1 so `next == here + 1` -- iteration is then a
    //      linear sweep the streaming prefetcher handles;
    //    * internal levels rebuilt with maximum fanout, so the height is the
    //      minimum for this element count.
    //
    //  Net effect: ~30% fewer live nodes (so a smaller resident working set),
    //  one fewer level on the lookup path, and front-to-back leaf storage. The
    //  pre-allocated pool *capacity* is unchanged (the no-grow guarantee) -- only
    //  the number of *live* nodes drops.
    //
    //  O(N), single streaming pass; transiently holds the old and new pools at
    //  once. Explicit maintenance call (e.g. after a bulk build or a churn-heavy
    //  phase, before a read-heavy phase); never on the find/insert/erase path.
    //  Packing leaves full maximizes density: a subsequent insert into a full
    //  leaf splits as usual, so call this when writes are mostly done.
    // -------------------------------------------------------------------------
    void compact()
    {
        if (size_ == 0)
        {
            return; // root already a single empty leaf; nothing to densify
        }

        const std::uint32_t N = static_cast<std::uint32_t>(size_);

        Leaf*     nl = new Leaf[leaf_capacity_];
        Internal* ni = new Internal[internal_capacity_];

        // The level currently being parented: (child handle, child subtree min
        // key) pairs. The leaf level is the widest, so leaf_capacity_ bounds it.
        // Parents are written back into the front of these same buffers as we go
        // (a parent consumes >= 2 children, so its index never overruns the
        // children it reads).
        handle_t* lvl_child = new handle_t[leaf_capacity_];
        Key*      lvl_key   = new Key[leaf_capacity_];

        // ---- stream source entries in key order from the old leaf chain ----
        handle_t sh = leftmost_leaf();
        int      si = 0;
        auto next_entry = [&](Key& k, Value& v)
        {
            while (sh != NIL && si >= leaf_pool_[sh].count)
            {
                sh = leaf_pool_[sh].next;
                si = 0;
            }
            DYNMAP_VERIFY(sh != NIL); // size_ / leaf-chain mismatch would walk off the end
            Leaf& s = leaf_pool_[sh];
            k = s.keys[si];
            v = std::move(s.values[si]);
            ++si;
        };

        // ---- step 1: pack dense leaves into slots 0..L-1 ----
        const std::uint32_t L    = (N + MAX_KEYS - 1) / MAX_KEYS;   // ceil
        const std::uint32_t last = N - (L - 1) * MAX_KEYS;          // last leaf fill
        const bool fixup = (L > 1 && last < static_cast<std::uint32_t>(MIN_KEYS));

        auto leaf_cnt = [&](std::uint32_t j) -> std::uint32_t
        {
            if (j + 1 < L)
            {
                if (fixup && j == L - 2)
                {
                    return MAX_KEYS - (MIN_KEYS - last); // donate to last leaf
                }
                return MAX_KEYS;
            }
            return fixup ? static_cast<std::uint32_t>(MIN_KEYS) : last;
        };

        for (std::uint32_t j = 0; j < L; ++j)
        {
            Leaf& d = nl[j];
            fill_sentinel(d.keys);

            const std::uint32_t cnt = leaf_cnt(j);
            for (std::uint32_t i = 0; i < cnt; ++i)
            {
                next_entry(d.keys[i], d.values[i]);
            }
            d.count = static_cast<std::uint16_t>(cnt);
            d.prev  = (j == 0)     ? NIL : (j - 1);
            d.next  = (j + 1 < L)  ? (j + 1) : NIL;

            lvl_child[j] = j;
            lvl_key[j]   = d.keys[0];
        }

        // free list over the leaf slots the dense tree does not use
        for (std::uint32_t j = L; j < leaf_capacity_; ++j)
        {
            nl[j].free_link = (j + 1 < leaf_capacity_) ? (j + 1) : NIL;
        }
        leaf_free_ = (L < leaf_capacity_) ? L : NIL;

        // ---- step 2: build internal levels bottom-up at maximum fanout ----
        const std::uint32_t FAN   = MAX_KEYS + 1;   // children per internal node
        const std::uint32_t MINCH = MIN_KEYS + 1;   // min children (== MIN_KEYS sep)

        std::uint32_t M       = L;   // nodes in the level being parented
        std::uint32_t ni_used = 0;
        int           levels  = 0;

        while (M > 1)
        {
            const std::uint32_t P     = (M + FAN - 1) / FAN;       // parent count
            const std::uint32_t lastc = M - (P - 1) * FAN;         // last parent fanout
            const bool pfix = (P > 1 && lastc < MINCH);

            auto par_children = [&](std::uint32_t p) -> std::uint32_t
            {
                if (p + 1 < P)
                {
                    if (pfix && p == P - 2)
                    {
                        return FAN - (MINCH - lastc);
                    }
                    return FAN;
                }
                return pfix ? MINCH : lastc;
            };

            std::uint32_t cstart = 0;
            for (std::uint32_t p = 0; p < P; ++p)
            {
                const std::uint32_t cc = par_children(p);
                const handle_t nh = ni_used++;

                Internal& nd = ni[nh];
                fill_sentinel(nd.keys);
                nd.count = static_cast<std::uint16_t>(cc - 1);

                for (std::uint32_t c = 0; c < cc; ++c)
                {
                    nd.children[c] = lvl_child[cstart + c];
                }
                for (std::uint32_t c = 1; c < cc; ++c)
                {
                    nd.keys[c - 1] = lvl_key[cstart + c]; // sep = min key of child c
                }

                const Key node_min = lvl_key[cstart];
                lvl_child[p] = nh;          // fold parent back into the front
                lvl_key[p]   = node_min;
                cstart += cc;
            }

            M = P;
            ++levels;
        }

        // free list over the internal slots the dense tree does not use
        for (std::uint32_t k = ni_used; k < internal_capacity_; ++k)
        {
            ni[k].free_link = (k + 1 < internal_capacity_) ? (k + 1) : NIL;
        }
        internal_free_ = (ni_used < internal_capacity_) ? ni_used : NIL;

        // ---- commit: swap in the rebuilt pools ----
        delete[] leaf_pool_;
        delete[] internal_pool_;
        leaf_pool_     = nl;
        internal_pool_ = ni;

        root_   = lvl_child[0];          // lone leaf (L==1) or the new root
        height_ = levels + 1;

        delete[] lvl_child;
        delete[] lvl_key;
    }

private:

    struct split_result
    {
        bool     happened = false;
        Key      sep_key{};
        handle_t new_node = NIL;
    };

    // Where the inserted / found key ended up. insert_into_leaf fills this so
    // emplace_impl can build the return iterator DIRECTLY -- the descent that
    // places the element is the only descent (the old code re-found from the
    // root to build the iterator, and operator[] paid a third walk on top).
    struct insert_outcome
    {
        bool     inserted = false;  // a new element was placed
        bool     rejected = false;  // at-capacity rejection of a NEW key (nothing mutated)
        handle_t leaf     = NIL;    // landing leaf (valid unless rejected)
        unsigned pos      = 0;      // landing slot within that leaf
    };

    std::pair<iterator, bool> emplace_impl(const Key& key, Value value,
                                           bool overwrite)
    {
        DYNMAP_VERIFY(leaf_pool_ != nullptr);  // moved-from map (see steal())
        DYNMAP_VERIFY(key_is_finite(key));     // inf/NaN break the sentinel ordering

        insert_outcome out;
        split_result   split;
        insert_rec(root_, height_ - 1, key, std::move(value), overwrite, out, split);

        if (out.rejected)
        {
            return { end(), false };  // graceful degrade: full() and key is new
        }

        if (split.happened)
        {
            handle_t new_root = alloc_internal();
            Internal& r = internal_pool_[new_root];
            r.count = 1;
            r.keys[0] = split.sep_key;
            r.children[0] = root_;
            r.children[1] = split.new_node;
            root_ = new_root;
            ++height_;
        }

        if (out.inserted)
        {
            ++size_;
        }

        return { iterator(this, out.leaf, static_cast<int>(out.pos)), out.inserted };
    }

    void insert_rec(handle_t h, int level, const Key& key, Value&& value,
                    bool overwrite, insert_outcome& out, split_result& split)
    {
        if (level == 0)
        {
            insert_into_leaf(h, key, std::move(value), overwrite, out, split);
            return;
        }

        Internal& node = internal_pool_[h];
        unsigned ci = child_index(node, key);

        split_result child_split;
        insert_rec(node.children[ci], level - 1, key, std::move(value), overwrite,
                   out, child_split);

        if (!child_split.happened)
        {
            return;
        }

        insert_into_internal(h, ci, child_split.sep_key, child_split.new_node,
                             split);
    }

    void insert_into_leaf(handle_t h, const Key& key, Value&& value,
                          bool overwrite, insert_outcome& out, split_result& split)
    {
        Leaf& leaf = leaf_pool_[h];
        unsigned pos = leaf_lower(leaf, key);

        if (pos < leaf.count && keys_equal(leaf.keys[pos], key))
        {
            if (overwrite)
            {
                leaf.values[pos] = std::move(value);
            }
            out.inserted = false;
            out.leaf = h;
            out.pos = pos;
            return;
        }

        // New key: enforce the declared capacity bound BEFORE any mutation.
        if (size_ >= capacity_)
        {
#if defined(DEGRADED_PATH_ALERT)
            DEGRADED_PATH_ALERT("dynamic_map: insert of a new key rejected -- map at declared capacity");
#endif
            out.rejected = true;
            return;
        }

        out.inserted = true;

        if (leaf.count < MAX_KEYS)
        {
            for (int i = leaf.count; i > static_cast<int>(pos); --i)
            {
                leaf.keys[i] = leaf.keys[i - 1];
                leaf.values[i] = std::move(leaf.values[i - 1]);
            }
            leaf.keys[pos] = key;
            leaf.values[pos] = std::move(value);
            ++leaf.count;
            out.leaf = h;
            out.pos = pos;
            return;
        }

        // ---- full leaf: split IN PLACE ----
        // The (B+1)-entry combined order is left[0..pos) + new + left[pos..MAX).
        // The first left_count of it stay in this leaf; the rest move to a new
        // right sibling. Both cases below write each surviving element exactly
        // once (the old implementation round-tripped all B+1 entries through a
        // stack temporary -- 2x the moves and B+1 dead Value constructions).
        const int left_count  = (MAX_KEYS + 1) / 2;
        const int right_count = (MAX_KEYS + 1) - left_count;

        handle_t rh = alloc_leaf();
        Leaf& right = leaf_pool_[rh];
        Leaf& left  = leaf_pool_[h];

        if (static_cast<int>(pos) >= left_count)
        {
            // New element lands in RIGHT: right = left[left_count..pos) + new
            // + left[pos..MAX). Left's keep-set [0, left_count) is untouched.
            const unsigned rpos = pos - static_cast<unsigned>(left_count);

            unsigned j = 0;
            for (unsigned i = static_cast<unsigned>(left_count); i < pos; ++i, ++j)
            {
                right.keys[j]   = left.keys[i];
                right.values[j] = std::move(left.values[i]);
            }

            right.keys[rpos]   = key;
            right.values[rpos] = std::move(value);

            j = rpos + 1;
            for (unsigned i = pos; i < MAX_KEYS; ++i, ++j)
            {
                right.keys[j]   = left.keys[i];
                right.values[j] = std::move(left.values[i]);
            }

            out.leaf = rh;
            out.pos = rpos;
        }
        else
        {
            // New element lands in LEFT: right takes left[left_count-1..MAX)
            // FIRST (before the shift below overwrites left[left_count-1]),
            // then left[pos..left_count-1) shifts up one to make room.
            for (int i = 0; i < right_count; ++i)
            {
                right.keys[i]   = left.keys[left_count - 1 + i];
                right.values[i] = std::move(left.values[left_count - 1 + i]);
            }

            for (int i = left_count - 1; i > static_cast<int>(pos); --i)
            {
                left.keys[i]   = left.keys[i - 1];
                left.values[i] = std::move(left.values[i - 1]);
            }
            left.keys[pos]   = key;
            left.values[pos] = std::move(value);

            out.leaf = h;
            out.pos = pos;
        }

        // Sentinel-fill the vacated left tail and release its moved-from values
        // (release is a no-op for trivially-destructible payloads).
        for (int i = left_count; i < MAX_KEYS; ++i)
        {
            left.keys[i] = sentinel<Key>::value();
            release_value(left.values[i]);
        }

        left.count  = static_cast<std::uint16_t>(left_count);
        right.count = static_cast<std::uint16_t>(right_count);

        right.next = left.next;
        right.prev = h;
        if (left.next != NIL)
        {
            leaf_pool_[left.next].prev = rh;
        }
        left.next = rh;

        split.happened = true;
        split.sep_key = right.keys[0];
        split.new_node = rh;
    }

    void insert_into_internal(handle_t h, unsigned ci, const Key& sep_key,
                              handle_t new_child, split_result& split)
    {
        Internal& node = internal_pool_[h];

        if (node.count < MAX_KEYS)
        {
            for (int i = node.count; i > static_cast<int>(ci); --i)
            {
                node.keys[i] = node.keys[i - 1];
                node.children[i + 1] = node.children[i];
            }
            node.keys[ci] = sep_key;
            node.children[ci + 1] = new_child;
            ++node.count;
            return;
        }

        // Full internal node: temp of (B+1) keys / (B+2) children, promote middle.
        Key      tmp_keys[MAX_KEYS + 1];
        handle_t tmp_children[MAX_KEYS + 2];

        for (unsigned i = 0; i < ci; ++i)
        {
            tmp_keys[i] = node.keys[i];
        }
        tmp_keys[ci] = sep_key;
        for (unsigned i = ci; i < MAX_KEYS; ++i)
        {
            tmp_keys[i + 1] = node.keys[i];
        }

        for (unsigned i = 0; i <= ci; ++i)
        {
            tmp_children[i] = node.children[i];
        }
        tmp_children[ci + 1] = new_child;
        for (unsigned i = ci + 1; i <= MAX_KEYS; ++i)
        {
            tmp_children[i + 1] = node.children[i];
        }

        const int mid = MAX_KEYS / 2;
        const int left_keys = mid;
        const int right_keys = MAX_KEYS - mid;

        handle_t rh = alloc_internal();
        Internal& right = internal_pool_[rh];
        Internal& left  = internal_pool_[h];

        fill_sentinel(left.keys);
        for (int i = 0; i < left_keys; ++i)
        {
            left.keys[i] = tmp_keys[i];
        }
        for (int i = 0; i <= left_keys; ++i)
        {
            left.children[i] = tmp_children[i];
        }
        left.count = left_keys;

        for (int i = 0; i < right_keys; ++i)
        {
            right.keys[i] = tmp_keys[mid + 1 + i];
        }
        for (int i = 0; i <= right_keys; ++i)
        {
            right.children[i] = tmp_children[mid + 1 + i];
        }
        right.count = right_keys;

        split.happened = true;
        split.sep_key = tmp_keys[mid];
        split.new_node = rh;
    }

    // ---- erase ----
    bool erase_rec(handle_t h, int level, const Key& key, bool& erased)
    {
        if (level == 0)
        {
            return erase_from_leaf(h, key, erased);
        }

        Internal& node = internal_pool_[h];
        unsigned ci = child_index(node, key);
        bool child_under = erase_rec(node.children[ci], level - 1, key, erased);

        if (!erased || !child_under)
        {
            return node.count < MIN_KEYS;
        }

        rebalance_child(h, ci, level - 1);
        return node.count < MIN_KEYS;
    }

    bool erase_from_leaf(handle_t h, const Key& key, bool& erased)
    {
        Leaf& leaf = leaf_pool_[h];
        unsigned pos = leaf_lower(leaf, key);

        if (pos >= leaf.count || !keys_equal(leaf.keys[pos], key))
        {
            erased = false;
            return false;
        }

        erased = true;
        for (int i = pos; i + 1 < leaf.count; ++i)
        {
            leaf.keys[i] = leaf.keys[i + 1];
            leaf.values[i] = std::move(leaf.values[i + 1]);
        }
        --leaf.count;
        leaf.keys[leaf.count] = sentinel<Key>::value();
        release_value(leaf.values[leaf.count]);

        return leaf.count < MIN_KEYS;
    }

    void rebalance_child(handle_t h, unsigned ci, int child_level)
    {
        if (child_level == 0)
        {
            rebalance_leaf_child(h, ci);
        }
        else
        {
            rebalance_internal_child(h, ci);
        }
    }

    void rebalance_leaf_child(handle_t h, unsigned ci)
    {
        Internal& parent = internal_pool_[h];
        handle_t child_h = parent.children[ci];
        Leaf& child = leaf_pool_[child_h];

        if (ci > 0)
        {
            Leaf& left = leaf_pool_[parent.children[ci - 1]];
            if (left.count > MIN_KEYS)
            {
                for (int i = child.count; i > 0; --i)
                {
                    child.keys[i] = child.keys[i - 1];
                    child.values[i] = std::move(child.values[i - 1]);
                }
                child.keys[0] = left.keys[left.count - 1];
                child.values[0] = std::move(left.values[left.count - 1]);
                ++child.count;
                --left.count;
                left.keys[left.count] = sentinel<Key>::value();

                parent.keys[ci - 1] = child.keys[0];
                return;
            }
        }

        if (ci + 1 <= parent.count)
        {
            Leaf& right = leaf_pool_[parent.children[ci + 1]];
            if (right.count > MIN_KEYS)
            {
                child.keys[child.count] = right.keys[0];
                child.values[child.count] = std::move(right.values[0]);
                ++child.count;

                for (int i = 0; i + 1 < right.count; ++i)
                {
                    right.keys[i] = right.keys[i + 1];
                    right.values[i] = std::move(right.values[i + 1]);
                }
                --right.count;
                right.keys[right.count] = sentinel<Key>::value();

                parent.keys[ci] = right.keys[0];
                return;
            }
        }

        if (ci > 0)
        {
            merge_leaves(h, ci - 1);
        }
        else
        {
            merge_leaves(h, ci);
        }
    }

    void merge_leaves(handle_t h, unsigned sep)
    {
        Internal& parent = internal_pool_[h];
        handle_t lh = parent.children[sep];
        handle_t rh = parent.children[sep + 1];
        Leaf& left = leaf_pool_[lh];
        Leaf& right = leaf_pool_[rh];

        for (int i = 0; i < right.count; ++i)
        {
            left.keys[left.count + i] = right.keys[i];
            left.values[left.count + i] = std::move(right.values[i]);
        }
        left.count += right.count;

        left.next = right.next;
        if (right.next != NIL)
        {
            leaf_pool_[right.next].prev = lh;
        }

        free_leaf(rh);

        for (int i = sep; i + 1 < parent.count; ++i)
        {
            parent.keys[i] = parent.keys[i + 1];
            parent.children[i + 1] = parent.children[i + 2];
        }
        --parent.count;
        parent.keys[parent.count] = sentinel<Key>::value();
    }

    void rebalance_internal_child(handle_t h, unsigned ci)
    {
        Internal& parent = internal_pool_[h];
        handle_t child_h = parent.children[ci];
        Internal& child = internal_pool_[child_h];

        if (ci > 0)
        {
            Internal& left = internal_pool_[parent.children[ci - 1]];
            if (left.count > MIN_KEYS)
            {
                for (int i = child.count; i > 0; --i)
                {
                    child.keys[i] = child.keys[i - 1];
                }
                for (int i = child.count + 1; i > 0; --i)
                {
                    child.children[i] = child.children[i - 1];
                }
                child.keys[0] = parent.keys[ci - 1];
                child.children[0] = left.children[left.count];
                ++child.count;

                parent.keys[ci - 1] = left.keys[left.count - 1];
                --left.count;
                left.keys[left.count] = sentinel<Key>::value();
                return;
            }
        }

        if (ci + 1 <= parent.count)
        {
            Internal& right = internal_pool_[parent.children[ci + 1]];
            if (right.count > MIN_KEYS)
            {
                child.keys[child.count] = parent.keys[ci];
                child.children[child.count + 1] = right.children[0];
                ++child.count;

                parent.keys[ci] = right.keys[0];
                for (int i = 0; i + 1 < right.count; ++i)
                {
                    right.keys[i] = right.keys[i + 1];
                }
                for (int i = 0; i < right.count; ++i)
                {
                    right.children[i] = right.children[i + 1];
                }
                --right.count;
                right.keys[right.count] = sentinel<Key>::value();
                return;
            }
        }

        if (ci > 0)
        {
            merge_internals(h, ci - 1);
        }
        else
        {
            merge_internals(h, ci);
        }
    }

    void merge_internals(handle_t h, unsigned sep)
    {
        Internal& parent = internal_pool_[h];
        handle_t lh = parent.children[sep];
        handle_t rh = parent.children[sep + 1];
        Internal& left = internal_pool_[lh];
        Internal& right = internal_pool_[rh];

        left.keys[left.count] = parent.keys[sep];
        int base = left.count + 1;
        for (int i = 0; i < right.count; ++i)
        {
            left.keys[base + i] = right.keys[i];
        }
        for (int i = 0; i <= right.count; ++i)
        {
            left.children[base + i] = right.children[i];
        }
        left.count = base + right.count;

        free_internal(rh);

        for (int i = sep; i + 1 < parent.count; ++i)
        {
            parent.keys[i] = parent.keys[i + 1];
            parent.children[i + 1] = parent.children[i + 2];
        }
        --parent.count;
        parent.keys[parent.count] = sentinel<Key>::value();
    }

    // ---- iteration helpers ----
    handle_t leftmost_leaf() const
    {
        handle_t h = root_;
        for (int level = height_ - 1; level > 0; --level)
        {
            h = internal_pool_[h].children[0];
        }
        return h;
    }

    handle_t rightmost_leaf() const
    {
        handle_t h = root_;
        for (int level = height_ - 1; level > 0; --level)
        {
            const Internal& node = internal_pool_[h];
            h = node.children[node.count];
        }
        return h;
    }
};

} // namespace dyn
} // namespace stree

#endif // DYNAMIC_MAP_HPP
