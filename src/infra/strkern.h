#pragma once

// strkern.h — THE byte-parallel string kernels. One header, three mirrored paths, no other home.
//
// House rule (owner, 2026-09-10): every SIMD string kernel the host project owns lives HERE, as inline functions
// with the NEON, the AVX2 and the scalar/SWAR reference written side by side in one place, so a reader
// can diff the three by eye and a reviewer can see immediately when one path drifted. No SIMD intrinsic
// for string work exists outside this header. (The pre-existing vector code in fixedStr.h, radixSort.h,
// sparseCsr.h and dynamic_map.hpp is NOT string work and stays where it is.)
//
// Every kernel takes ( const char*, std::size_t ) — never a NUL terminator, never a std::string — so a
// future SIMD-backed string type can adopt them unchanged, and so a kernel can run over the interior of a
// mapped file. Every kernel has a `_scalar` twin that is ALWAYS compiled and always callable (find3 and findNeedle reach theirs,
// findByEndBytes_scalar, through a KernelPath::Scalar argument rather than a second spelling): it is the
// oracle test/strkerncheck.sh compares the vector path against, and it is the code that actually runs on
// a target with neither NEON nor AVX2. The scalar twins are portable C++ — no intrinsic, no UB, no
// unaligned type-punned load (every wide read goes through std::memcpy).
//
// ── ATTRIBUTION ──────────────────────────────────────────────────────────────────────────────────────
//   * Daniel Lemire, 2023-07-13 ("Fast Unicode/ASCII character classification", sse_type.c / upper_type.c):
//     the two-stage nibble-table classification this file's classMasks is built on — the low nibble indexes
//     a 16-byte column bitmap, the high nibble selects a row bit, AND them, a nonzero result is a member
//     and its bit says WHICH class. Also the SWAR case-fold identity used by the fused subtoken hash.
//   * Tempesta Technologies (`match_symbols_mask32_c`, and the strcasecmp kernel): the branchless A-Z fold
//     as `(unsigned)( c - 'A' ) < 26` — one wrapping subtract and one unsigned compare — and its SSE
//     0x80-bias spelling for a signed-only compare instruction.
//   * StringZilla (`find/neon.h`, `find/serial.h`, Ash Vardanian): the NEON movemask via
//     `vshrn_n_u16( ..., 4 )` + `vget_lane_u64` (four bits per byte, one shift-and-narrow instead of the
//     bitmask-and-horizontal-add x86 gets for free from `pmovmskb`); `sz_find_byteset`'s 256-bit set test
//     as two table lookups over the (byte>>3, byte&7) decomposition; the SWAR has-zero-byte probe.
//   * Wojciech Muła: the `pshufb` byte-classification family these two-stage lookups descend from, and
//     the "check an anomalous first and last byte, then verify" shape find3 uses.
//
// ── THE F3 LESSON (memory `optremarks-f3-strcmp`, PR #107) ───────────────────────────────────────────
// A compare that DECIDES at byte 0 or 1 is call overhead, not string work: vectorizing it loses, and F3's
// measured win came from deleting the call, not from widening it. SIMD pays only where a loop must touch
// EVERY byte of a text. That is why classMasks (which reads every byte of every doc/body field) is wired
// into the tokenizer, while lowerFoldedEquals below — the acronym-seam fallback, reached only after a
// length-and-head filter has already rejected almost everything, on tokens averaging ~7 bytes — ships as
// a kernel with a parity arm but is deliberately NOT wired into lexical.h's scan loop. Measure before
// widening a short compare.
//
// ── PORTABILITY ──────────────────────────────────────────────────────────────────────────────────────
// arm64 has NEON in the baseline (`__ARM_NEON` is defined by every arm64 toolchain). x86-64 builds carry
// `-march=x86-64-v3` unconditionally (CMakeLists.txt; owner decision 2026-09-10 — AVX2 + BMI1/2 + FMA +
// LZCNT + MOVBE, the RHEL 10 floor), so `__AVX2__` is defined on every shipped x86-64 binary, the macOS one
// cross-built on arm64 included (the floor keys on the TARGET arch). Anything else — a target that is neither,
// a hand-configured toolchain that overrides the arch flags — compiles the scalar twins: same contracts, no ISA.
//
// The scalar twins are ALWAYS compiled, so nothing in them may be a GCC/Clang extension: the trailing-zero
// count is `std::countr_zero` (<bit>, C++20) and not `__builtin_ctzll`, which MSVC — a supported compiler,
// and the one the pending Windows port builds with — does not provide. It is the same instruction on every
// toolchain that has one, and it is DEFINED at zero (width) where the builtin is undefined, so the change
// can only remove a footgun. The vector paths use the same spelling for the same reason: MSVC compiles them
// too under /arch:AVX2.
//
// Determinism (docs/ARCHITECTURE.md §3): every kernel here is INTEGER and EXACT. Its result is a bit
// pattern, not a rounded sum, so no path can reassociate its way to a different answer; the NEON, AVX2
// and scalar paths return identical values for identical input, which is precisely what
// test/strkerncheck.sh asserts on 100k random buffers and on every byte of src/ and docs/.

#include <algorithm>      // std::min — countByte's 255-block lane bound
#include <bit>            // std::countr_zero — the portable spelling of ctz; the scalar twins must compile on MSVC too
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>       // std::numeric_limits — the mask-width static_assert: an index shifted into a mask must fit it
#include <string_view>
#include <type_traits>     // std::is_array_v / is_convertible_v — find's literal vs runtime-needle overloads

#if defined( __ARM_NEON )
    #include <arm_neon.h>
#elif defined( __AVX2__ )
    #include <immintrin.h>
#endif

namespace rw::strkern
{

// ── the compiled path, named so a harness banner can prove it is not vacuously testing scalar-vs-scalar ──
#if defined( __ARM_NEON )
inline constexpr const char* kPathName   = "NEON";
inline constexpr std::size_t kBlockBytes = 16;      // one uint8x16_t
#elif defined( __AVX2__ )
inline constexpr const char* kPathName   = "AVX2";
inline constexpr std::size_t kBlockBytes = 32;      // one __m256i
#else
inline constexpr const char* kPathName   = "scalar";
inline constexpr std::size_t kBlockBytes = 16;      // the scalar twins accept any n <= 32; 16 keeps the
                                                    // block loop's shape identical on every path
#endif

// The largest block any path uses. A caller that wants ONE stack buffer big enough for every path
// (the harness does) sizes it by this, not by kBlockBytes.
inline constexpr std::size_t kMaxBlockBytes = 32;

// ═══════════════════════════════════════════════════════════════════════════════════════════════════
//  1. classMasks — per-byte character-class bitmasks over one block
// ═══════════════════════════════════════════════════════════════════════════════════════════════════
//
// One BIT per byte, bit k = byte k of the block (LSB first). Bits at or above `n` are always 0, so a
// short tail needs no separate mask from the caller. `alnum` is exactly `upper | lower | digit`; a
// SEPARATOR is a byte with no class, i.e. a clear bit in `alnum` below n — the tokenizer never needs a
// separate separator mask, it needs `~alnum & validBits`, which only the caller knows the width of.
struct Masks
{
    std::uint32_t alnum = 0;      // [A-Za-z0-9]
    std::uint32_t upper = 0;      // [A-Z]
    std::uint32_t lower = 0;      // [a-z]
    std::uint32_t digit = 0;      // [0-9]
};
// bit k is byte k of a block of at most kMaxBlockBytes, set by `1 << k`: the block must not outgrow the mask
static_assert( kMaxBlockBytes <= std::numeric_limits<decltype( Masks::alnum )>::digits,
               "strkern: a block longer than the class masks are wide would shift past them — widen Masks first" );

// ── the two-stage nibble table (Lemire 2023/07/13) ──────────────────────────────────────────────────
// A class is a set of bytes, and pshufb/vqtbl1q can only look up 16 entries — so a byte's membership is
// decomposed into "what its LOW nibble allows" AND "what its HIGH nibble allows", one bit per (class,
// high-nibble) pair. Five bits are enough because the three classes span five (high-nibble, low-range)
// rectangles:
//
//     bit 0  0x01   upper-A   high nibble 4, low nibble 1..F      'A'(0x41) .. 'O'(0x4F)
//     bit 1  0x02   upper-B   high nibble 5, low nibble 0..A      'P'(0x50) .. 'Z'(0x5A)
//     bit 2  0x04   lower-A   high nibble 6, low nibble 1..F      'a'(0x61) .. 'o'(0x6F)
//     bit 3  0x08   lower-B   high nibble 7, low nibble 0..A      'p'(0x70) .. 'z'(0x7A)
//     bit 4  0x10   digit     high nibble 3, low nibble 0..9      '0'(0x30) .. '9'(0x39)
//
// The high-nibble table has AT MOST ONE bit per entry, so `lowTable[lo] & highTable[hi]` has at most one
// bit set and never confuses two classes. A byte >= 0x80 has a high nibble of 8..F, every one of which
// maps to 0 — so the whole non-ASCII half is a separator by construction, with no extra compare. A zero
// byte maps to 0 as well, which is what makes zero-padding a short tail safe.
inline constexpr std::uint8_t kClsUpper = 0x03;   // upper-A | upper-B
inline constexpr std::uint8_t kClsLower = 0x0C;   // lower-A | lower-B
inline constexpr std::uint8_t kClsDigit = 0x10;

// STRKERN_MUTATE is the gate's can-go-red arm: it flips ONE bit of the SIMD-only nibble table, which the
// scalar oracle does not consult. A build with it defined must make test/strkerncheck.sh fail; if it does
// not, the parity assertion is vacuous and the gate is worthless. Never define it in a real build.
inline constexpr std::uint8_t kLowNibbleTable[ 16 ] = {
    /* 0 */ 0x1A,   // lo 0: upper-B | lower-B | digit
    /* 1 */ 0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F,   // lo 1..9: every rectangle
    /* A */ 0x0F,   // lo A: upper-A | upper-B | lower-A | lower-B (no digit — ':' is not one)
    /* B */ 0x05, 0x05, 0x05, 0x05, 0x05                            // lo B..F: only the ..A rectangles
};
inline constexpr std::uint8_t kHighNibbleTable[ 16 ] = {
    0x00, 0x00, 0x00,
    /* 3 */ 0x10,                       // '0'..'?'
#if defined( STRKERN_MUTATE )
    /* 4 */ 0x03,                       // MUTATION: upper-A's row bit widened — 'P'..'Z' now also
                                        // report upper-A, so '@'(0x40) misclassifies. SIMD only.
#else
    /* 4 */ 0x01,                       // '@'..'O'
#endif
    /* 5 */ 0x02,                       // 'P'..'_'
    /* 6 */ 0x04,                       // '`'..'o'
    /* 7 */ 0x08,                       // 'p'..DEL
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

// ── the scalar oracle: the class definitions, restated with no table and no intrinsic ────────────────
// Deliberately written as the three range tests a reader would write by hand, NOT as a lookup — an oracle
// that shared the tables would move with them and prove nothing. Accepts any n <= kMaxBlockBytes, so it
// can validate a 32-byte AVX2 block and a 16-byte NEON block from the same harness arm.
inline void classMasks_scalar( const char* p, std::size_t n, Masks& out ) noexcept
{
    out = Masks{};
    if( n > kMaxBlockBytes )
    {
        n = kMaxBlockBytes;
    }
    for( std::size_t k = 0; k < n; ++k )
    {
        const unsigned char  c   = static_cast<unsigned char>( p[ k ] );
        const std::uint32_t  bit = std::uint32_t( 1 ) << k;
        if( c >= 'A' && c <= 'Z' )
        {
            out.upper |= bit;
        }
        else if( c >= 'a' && c <= 'z' )
        {
            out.lower |= bit;
        }
        else if( c >= '0' && c <= '9' )
        {
            out.digit |= bit;
        }
    }
    out.alnum = out.upper | out.lower | out.digit;
}

#if defined( __ARM_NEON )
// StringZilla's NEON movemask: `vshrn_n_u16( x, 4 )` narrows sixteen u16 lanes to eight u8 lanes taking
// four bits from each, so a byte-wide all-ones/all-zeros compare result becomes a u64 with a NIBBLE per
// input byte. One shift-and-narrow plus one lane read; `countr_zero( m ) >> 2` is the first match's byte
// index. Used by the find kernels, which only ever want that index.
inline std::uint64_t neonNibbleMask( uint8x16_t cmp ) noexcept
{
    return vget_lane_u64( vreinterpret_u64_u8( vshrn_n_u16( vreinterpretq_u16_u8( cmp ), 4 ) ), 0 );
}

// One BIT per byte (16 bits), which is what the tokenizer's mask ALGEBRA needs — there a shift by one
// must mean "one byte over", and the nibble form's shift by four would work but would make every mask
// expression carry a scale factor that differs between NEON and AVX2. Four instructions: AND with the
// per-lane bit weights, then two horizontal byte sums.
inline std::uint32_t neonByteMask( uint8x16_t cmp ) noexcept
{
    static constexpr std::uint8_t kBitWeights[ 16 ] = { 1, 2, 4, 8, 16, 32, 64, 128, 1, 2, 4, 8, 16, 32, 64, 128 };
    const uint8x16_t m = vandq_u8( cmp, vld1q_u8( kBitWeights ) );
    return std::uint32_t( vaddv_u8( vget_low_u8( m ) ) ) | ( std::uint32_t( vaddv_u8( vget_high_u8( m ) ) ) << 8 );
}
#endif

// Per-byte class masks for ONE block. `n` must be <= kBlockBytes; bits at or above n are 0. Never reads
// past p + n: a short block is copied into a zero-filled stack buffer first (a zero byte classifies as a
// separator, so the padding cannot invent a class bit).
inline void classMasks( const char* p, std::size_t n, Masks& out ) noexcept
{
#if defined( __ARM_NEON ) || defined( __AVX2__ )
    alignas( 32 ) std::uint8_t padded[ kBlockBytes ] = {};
    if( n < kBlockBytes )
    {
        std::memcpy( padded, p, n );
        p = reinterpret_cast<const char*>( padded );
    }
#endif

#if defined( __ARM_NEON )
    const uint8x16_t v     = vld1q_u8( reinterpret_cast<const std::uint8_t*>( p ) );
    const uint8x16_t lo    = vandq_u8( v, vdupq_n_u8( 0x0F ) );
    const uint8x16_t hi    = vshrq_n_u8( v, 4 );                       // u8 shift is logical: 0..15 always
    const uint8x16_t rowLo = vqtbl1q_u8( vld1q_u8( kLowNibbleTable ), lo );
    const uint8x16_t rowHi = vqtbl1q_u8( vld1q_u8( kHighNibbleTable ), hi );
    const uint8x16_t cls   = vandq_u8( rowLo, rowHi );
    out.upper = neonByteMask( vtstq_u8( cls, vdupq_n_u8( kClsUpper ) ) );
    out.lower = neonByteMask( vtstq_u8( cls, vdupq_n_u8( kClsLower ) ) );
    out.digit = neonByteMask( vtstq_u8( cls, vdupq_n_u8( kClsDigit ) ) );
    out.alnum = out.upper | out.lower | out.digit;
#elif defined( __AVX2__ )
    // `_mm256_shuffle_epi8` shuffles WITHIN each 128-bit lane, so both nibble tables are broadcast to
    // both lanes — that is the whole difference from the NEON spelling. It also differs from vqtbl1q in
    // out-of-range behaviour: vqtbl1q returns 0 for an index >= 16 while pshufb takes index & 15 unless
    // bit 7 is set, so both indices are masked to 0..15 BEFORE the lookup rather than relying on either.
    const __m256i v     = _mm256_loadu_si256( reinterpret_cast<const __m256i*>( p ) );
    const __m256i loTab = _mm256_broadcastsi128_si256( _mm_loadu_si128( reinterpret_cast<const __m128i*>( kLowNibbleTable ) ) );
    const __m256i hiTab = _mm256_broadcastsi128_si256( _mm_loadu_si128( reinterpret_cast<const __m128i*>( kHighNibbleTable ) ) );
    const __m256i nibbleMask = _mm256_set1_epi8( 0x0F );
    const __m256i lo    = _mm256_and_si256( v, nibbleMask );
    const __m256i hi    = _mm256_and_si256( _mm256_srli_epi16( v, 4 ), nibbleMask );   // no epi8 shift exists
    const __m256i cls   = _mm256_and_si256( _mm256_shuffle_epi8( loTab, lo ), _mm256_shuffle_epi8( hiTab, hi ) );
    const __m256i zero  = _mm256_setzero_si256();
    const auto    nonzeroMask = [ & ]( std::uint8_t bits ) noexcept
    {
        // cmpeq-with-zero marks the bytes that are NOT members; invert to get the membership mask. Every
        // one of the 32 bits is meaningful (padding bytes are zero, hence non-members), so a plain
        // bitwise NOT is correct with no width bookkeeping.
        const __m256i isZero = _mm256_cmpeq_epi8( _mm256_and_si256( cls, _mm256_set1_epi8( char( bits ) ) ), zero );
        return ~std::uint32_t( _mm256_movemask_epi8( isZero ) );
    };
    out.upper = nonzeroMask( kClsUpper );
    out.lower = nonzeroMask( kClsLower );
    out.digit = nonzeroMask( kClsDigit );
    out.alnum = out.upper | out.lower | out.digit;
#else
    classMasks_scalar( p, n, out );
#endif
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════
//  2. lowerFoldAscii / lowerFoldedEquals — the A-Z-only fold
// ═══════════════════════════════════════════════════════════════════════════════════════════════════
//
// A-Z ONLY, on purpose: this is the fold the host's lexical layer means by "lowercase" (lexindex.h
// lexLowerByte), and it is the only one that is locale-free, byte-exact and reversible enough to hash
// with. Bytes >= 0x80 are left alone — a UTF-8 continuation byte is not a letter to fold.
//
// The identity (Tempesta): `(unsigned char)( c - 'A' ) < 26` is true exactly for 'A'..'Z', because the
// subtraction wraps, so every byte below 'A' lands at 230..255 and every byte above 'Z' at 26..229. NEON
// has an unsigned compare (`vcltq_u8`) and spells it directly. AVX2's byte compare is SIGNED only, so the
// same test is biased by 0x80: subtracting `'A' + 0x80` produces `( c - 'A' ) ^ 0x80`, and the unsigned
// `< 26` becomes the signed `> -103` with the constant on the left. Same predicate, one instruction each.

// SWAR fold of eight bytes at once (Lemire's formulation, high-bit arithmetic only, no per-byte branch).
// `heptets` clears bit 7 so a byte >= 0x80 cannot borrow into its neighbour's compare; the final `& ~x`
// then excludes those bytes from the fold, since their true value was never in 'A'..'Z'.
inline std::uint64_t swarLowerFold8( std::uint64_t x ) noexcept
{
    constexpr std::uint64_t kOnes  = 0x0101010101010101ull;
    constexpr std::uint64_t kHighs = 0x8080808080808080ull;
    const std::uint64_t heptets  = x & ( 0x7Full * kOnes );
    const std::uint64_t geA      = ( heptets + ( 0x80ull - 'A' ) * kOnes ) & kHighs;   // byte >= 'A'
    const std::uint64_t gtZ      = ( heptets + ( 0x7Full - 'Z' ) * kOnes ) & kHighs;   // byte >  'Z'
    const std::uint64_t isUpper  = geA & ~gtZ & ~x;                                    // and ASCII
    return x | ( isUpper >> 2 );                                                       // 0x80 >> 2 == 0x20
}

inline void lowerFoldAscii_scalar( char* p, std::size_t n ) noexcept
{
    std::size_t k = 0;
    for( ; k + 8 <= n; k += 8 )
    {
        std::uint64_t x = 0;
        std::memcpy( &x, p + k, 8 );
        x = swarLowerFold8( x );
        std::memcpy( p + k, &x, 8 );
    }
    for( ; k < n; ++k )
    {
        const unsigned char c = static_cast<unsigned char>( p[ k ] );
        if( c >= 'A' && c <= 'Z' )
        {
            p[ k ] = char( c + 0x20 );
        }
    }
}

inline void lowerFoldAscii( char* p, std::size_t n ) noexcept
{
    std::size_t k = 0;
#if defined( __ARM_NEON )
  #if defined( STRKERN_MUTATE )
    const uint8x16_t kSpan = vdupq_n_u8( 25 );   // MUTATION: 'Z' stops folding. SIMD only.
  #else
    const uint8x16_t kSpan = vdupq_n_u8( 26 );
  #endif
    for( ; k + 16 <= n; k += 16 )
    {
        auto*            q     = reinterpret_cast<std::uint8_t*>( p + k );
        const uint8x16_t v     = vld1q_u8( q );
        const uint8x16_t isUp  = vcltq_u8( vsubq_u8( v, vdupq_n_u8( 'A' ) ), kSpan );
        vst1q_u8( q, vorrq_u8( v, vandq_u8( isUp, vdupq_n_u8( 0x20 ) ) ) );
    }
#elif defined( __AVX2__ )
  #if defined( STRKERN_MUTATE )
    const __m256i kBound = _mm256_set1_epi8( char( 0x99 ) );   // MUTATION: 'Z' stops folding. SIMD only.
  #else
    const __m256i kBound = _mm256_set1_epi8( char( 0x9A ) );   // 26 ^ 0x80, i.e. -102 signed
  #endif
    for( ; k + 32 <= n; k += 32 )
    {
        auto*         q     = reinterpret_cast<__m256i*>( p + k );
        const __m256i v     = _mm256_loadu_si256( q );
        const __m256i biased = _mm256_sub_epi8( v, _mm256_set1_epi8( char( 'A' + 0x80 ) ) );
        const __m256i isUp  = _mm256_cmpgt_epi8( kBound, biased );
        _mm256_storeu_si256( q, _mm256_or_si256( v, _mm256_and_si256( isUp, _mm256_set1_epi8( 0x20 ) ) ) );
    }
#endif
    lowerFoldAscii_scalar( p + k, n - k );
}

// Does `a[0..n)` equal `bLowered[0..n)` once a is A-Z-folded? `bLowered` must ALREADY be all-lowercase —
// the caller's query token is, by construction. See the F3 note at the top of this header before wiring
// this into a hot path: it is a late-deciding compare over short spans and the scalar form usually wins.
inline bool lowerFoldedEquals_scalar( const char* a, const char* bLowered, std::size_t n ) noexcept
{
    std::size_t k = 0;
    for( ; k + 8 <= n; k += 8 )
    {
        std::uint64_t x = 0, y = 0;
        std::memcpy( &x, a + k, 8 );
        std::memcpy( &y, bLowered + k, 8 );
        if( swarLowerFold8( x ) != y )
        {
            return false;
        }
    }
    for( ; k < n; ++k )
    {
        const unsigned char c = static_cast<unsigned char>( a[ k ] );
        const unsigned char f = ( c >= 'A' && c <= 'Z' ) ? static_cast<unsigned char>( c + 0x20 ) : c;
        if( f != static_cast<unsigned char>( bLowered[ k ] ) )
        {
            return false;
        }
    }
    return true;
}

inline bool lowerFoldedEquals( const char* a, const char* bLowered, std::size_t n ) noexcept
{
    std::size_t k = 0;
#if defined( __ARM_NEON )
    for( ; k + 16 <= n; k += 16 )
    {
        const uint8x16_t v     = vld1q_u8( reinterpret_cast<const std::uint8_t*>( a + k ) );
        const uint8x16_t isUp  = vcltq_u8( vsubq_u8( v, vdupq_n_u8( 'A' ) ), vdupq_n_u8( 26 ) );
        const uint8x16_t fold  = vorrq_u8( v, vandq_u8( isUp, vdupq_n_u8( 0x20 ) ) );
        const uint8x16_t other = vld1q_u8( reinterpret_cast<const std::uint8_t*>( bLowered + k ) );
        if( vminvq_u8( vceqq_u8( fold, other ) ) != 0xFF )
        {
            return false;
        }
    }
#elif defined( __AVX2__ )
    for( ; k + 32 <= n; k += 32 )
    {
        const __m256i v      = _mm256_loadu_si256( reinterpret_cast<const __m256i*>( a + k ) );
        const __m256i biased = _mm256_sub_epi8( v, _mm256_set1_epi8( char( 'A' + 0x80 ) ) );
        const __m256i isUp   = _mm256_cmpgt_epi8( _mm256_set1_epi8( char( 0x9A ) ), biased );
        const __m256i fold   = _mm256_or_si256( v, _mm256_and_si256( isUp, _mm256_set1_epi8( 0x20 ) ) );
        const __m256i other  = _mm256_loadu_si256( reinterpret_cast<const __m256i*>( bLowered + k ) );
        if( std::uint32_t( _mm256_movemask_epi8( _mm256_cmpeq_epi8( fold, other ) ) ) != 0xFFFFFFFFu )
        {
            return false;
        }
    }
#endif
    return lowerFoldedEquals_scalar( a + k, bLowered + k, n - k );
}

// The string_view call-site form: `s` equals the all-lowercase `lowered` once s is A-Z-folded. An adapter that
// adds the length test and forwards, not a kernel. `lowered` must already be lowercase: an upper-case byte in it
// never matches.
inline bool lowerFoldedEquals( std::string_view s, std::string_view lowered ) noexcept
{
    return s.size() == lowered.size() && lowerFoldedEquals( s.data(), lowered.data(), s.size() );
}

// The same adapter for a prefix: `s` begins with the all-lowercase `loweredPrefix` once A-Z-folded. An upper-case
// byte in `loweredPrefix` never matches. substr( 0, n ) clamps, so an `s` shorter than the prefix fails the length test.
inline bool lowerFoldedStartsWith( std::string_view s, std::string_view loweredPrefix ) noexcept
{
    return lowerFoldedEquals( s.substr( 0, loweredPrefix.size() ), loweredPrefix );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════
//  3. findByte / find3 / findByteset — first-occurrence scans
// ═══════════════════════════════════════════════════════════════════════════════════════════════════
//
// All three return the index of the first match, or `n` when there is none — never a sentinel that a
// caller could confuse with a valid index, and never std::string_view::npos (these kernels do not know
// what a string_view is).

// SWAR has-zero-byte (StringZilla serial; the exact variant, not the borrow one). Sets 0x80 in EVERY zero
// byte of x and in no other byte — the result is exact, so a caller can act on ctz( m ) >> 3 without a
// verify pass.
//
// TWO REASONS THIS IS NOT THE FAMILIAR `( x - 0x0101… ) & ~x & 0x8080…`. First, that form is only
// approximate: a borrow running out of a zero byte can set the high bit of the NEXT byte too (0x0001
// reports both bytes), so every candidate needs re-checking. Second, and decisive here, its subtraction
// WRAPS, and G1 compiles with `-fsanitize=integer -fno-sanitize-recover=all`: an unsigned wrap is an
// immediate abort, which is exactly how this landed red the first time. The form below never wraps at all
// — per byte, `( v & 0x7F ) + 0x7F <= 0xFE`, so no carry crosses a byte boundary or leaves bit 63.
//
// Why it is exact: `( v & 0x7F ) + 0x7F` has its high bit set iff the low seven bits of v are nonzero, and
// OR-ing v back in adds the case "v's own high bit is set". So the high bit of `t | v` is CLEAR exactly
// when v == 0; invert and mask.
inline constexpr std::uint64_t swarZeroByteMask( std::uint64_t x ) noexcept
{
    constexpr std::uint64_t kLows  = 0x7F7F7F7F7F7F7F7Full;
    constexpr std::uint64_t kHighs = 0x8080808080808080ull;
    return ~( ( ( x & kLows ) + kLows ) | x ) & kHighs;
}

inline std::size_t findByte_scalar( const char* p, std::size_t n, char needle ) noexcept
{
    constexpr std::uint64_t kOnes = 0x0101010101010101ull;
    const std::uint64_t     splat = kOnes * static_cast<unsigned char>( needle );
    std::size_t             k     = 0;
    for( ; k + 8 <= n; k += 8 )
    {
        std::uint64_t x = 0;
        std::memcpy( &x, p + k, 8 );
        const std::uint64_t m = swarZeroByteMask( x ^ splat );
        if( m != 0 )
        {
            return k + ( std::size_t( std::countr_zero( m ) ) >> 3 );   // the mask is EXACT: no verify pass
        }
    }
    for( ; k < n; ++k )
    {
        if( p[ k ] == needle )
        {
            return k;
        }
    }
    return n;
}

inline std::size_t findByte( const char* p, std::size_t n, char needle ) noexcept
{
    std::size_t k = 0;
#if defined( __ARM_NEON )
    const uint8x16_t splat = vdupq_n_u8( static_cast<std::uint8_t>( needle ) );
    for( ; k + 16 <= n; k += 16 )
    {
        const uint8x16_t  v = vld1q_u8( reinterpret_cast<const std::uint8_t*>( p + k ) );
        const std::uint64_t m = neonNibbleMask( vceqq_u8( v, splat ) );
        if( m != 0 )
        {
            return k + ( std::size_t( std::countr_zero( m ) ) >> 2 );   // four mask bits per input byte
        }
    }
#elif defined( __AVX2__ )
    const __m256i splat = _mm256_set1_epi8( needle );
    for( ; k + 32 <= n; k += 32 )
    {
        const __m256i v = _mm256_loadu_si256( reinterpret_cast<const __m256i*>( p + k ) );
        const std::uint32_t m = std::uint32_t( _mm256_movemask_epi8( _mm256_cmpeq_epi8( v, splat ) ) );
        if( m != 0 )
        {
            return k + std::size_t( std::countr_zero( m ) );
        }
    }
#endif
    const std::size_t tail = findByte_scalar( p + k, n - k, needle );
    return tail == n - k ? n : k + tail;
}

// Muła's "check an anomalous first and last byte, then verify": a needle's FIRST byte and its LAST (at `span - 1`) are compared in
// parallel across a block of start positions, and only a start where both agree pays `verify( at )`, which tests the bytes between.
// The first such start (the smallest), or n when there is none or span > n. One loop for every needle length, so find3 and
// findNeedle below cannot drift apart; `verify` is how they differ (one middle byte, or a memcmp of the whole needle).
// How the end-byte filter sees a haystack byte: as is (find, find3), or A-Z-folded (ciFindLiteral). One loop serves both, so the
// case-insensitive find cannot drift from the exact one; the policy is applied to each loaded block, word and tail byte before the
// compare, and the needle's ends arrive already in the folded form. The fold is section 2's Tempesta identity, `(unsigned char)( c - 'A' )
// < 26`: NEON spells it with its unsigned compare, AVX2 with the 0x80 bias, SWAR with swarLowerFold8. Bytes >= 0x80 never fold.
struct ExactBytes
{
    static char          one( char c ) noexcept { return c; }
    static std::uint64_t swar8( std::uint64_t x ) noexcept { return x; }
#if defined( __ARM_NEON )
    static uint8x16_t vec( uint8x16_t v ) noexcept { return v; }
#elif defined( __AVX2__ )
    static __m256i vec( __m256i v ) noexcept { return v; }
#endif
};
struct AsciiLowerBytes
{
    static char one( char c ) noexcept
    {
        return static_cast<unsigned char>( c - 'A' ) < 26 ? char( c + 0x20 ) : c;
    }
    static std::uint64_t swar8( std::uint64_t x ) noexcept { return swarLowerFold8( x ); }
#if defined( __ARM_NEON )
    static uint8x16_t vec( uint8x16_t v ) noexcept
    {
  #if defined( STRKERN_MUTATE )
        const uint8x16_t kSpan = vdupq_n_u8( 25 );   // MUTATION: 'Z' stops folding in ciFindLiteral's filter. SIMD only.
  #else
        const uint8x16_t kSpan = vdupq_n_u8( 26 );
  #endif
        const uint8x16_t isUp = vcltq_u8( vsubq_u8( v, vdupq_n_u8( 'A' ) ), kSpan );
        return vorrq_u8( v, vandq_u8( isUp, vdupq_n_u8( 0x20 ) ) );
    }
#elif defined( __AVX2__ )
    static __m256i vec( __m256i v ) noexcept
    {
        const __m256i biased = _mm256_sub_epi8( v, _mm256_set1_epi8( char( 'A' + 0x80 ) ) );
  #if defined( STRKERN_MUTATE )
        const __m256i kBound = _mm256_set1_epi8( char( 0x99 ) );   // MUTATION: 'Z' stops folding in ciFindLiteral's filter. SIMD only.
  #else
        const __m256i kBound = _mm256_set1_epi8( char( 0x9A ) );   // 26 ^ 0x80: the signed spelling of < 26
  #endif
        const __m256i isUp   = _mm256_cmpgt_epi8( kBound, biased );
        return _mm256_or_si256( v, _mm256_and_si256( isUp, _mm256_set1_epi8( 0x20 ) ) );
    }
#endif
};

struct NeedleEnds
{
    char        first = 0;
    char        last  = 0;
    std::size_t span  = 0;   // the needle's length: `last` sits at start + span - 1
};
template<class Fold = ExactBytes, class Verify>
inline std::size_t findByEndBytes_scalar( const char* p, std::size_t n, NeedleEnds ends, Verify&& verify ) noexcept
{
    const auto [ first, last, span ] = ends;
    if( span == 0 || span > n )
    {
        return n;
    }
    constexpr std::uint64_t kOnes = 0x0101010101010101ull;
    const std::uint64_t     n0    = kOnes * static_cast<unsigned char>( first );
    const std::uint64_t     nl    = kOnes * static_cast<unsigned char>( last );
    std::size_t             k     = 0;
    while( k + span + 7 <= n )                 // eight starts k..k+7, each with the whole needle in range
    {
        std::uint64_t a = 0, b = 0;
        std::memcpy( &a, p + k, 8 );
        std::memcpy( &b, p + k + span - 1, 8 );
        a = Fold::swar8( a );
        b = Fold::swar8( b );
        // both masks are exact, so their AND marks exactly the starts where the first and last bytes agree
        std::uint64_t mask = swarZeroByteMask( a ^ n0 ) & swarZeroByteMask( b ^ nl );
        while( mask != 0 )
        {
            const std::size_t at = k + ( std::size_t( std::countr_zero( mask ) ) >> 3 );
            if( verify( at ) )
            {
                return at;
            }
            mask &= mask - 1;
        }
        k += 8;
    }
    const std::size_t starts = n - span + 1;
    if( k < starts && starts >= 8 )            // the last 1..7 starts: one more word ending at the last start, its already-tested
    {                                          // starts (below k) masked off — no byte loop once there are eight starts. The mask
                                               // clears the LOW bits ( ~( 2^s - 1 ) ), never shifts set bits out: G1's integer
                                               // sanitizer rejects an unsigned shift that loses bits
        const std::size_t at0 = starts - 8;
        std::uint64_t     a = 0, b = 0;
        std::memcpy( &a, p + at0, 8 );
        std::memcpy( &b, p + at0 + span - 1, 8 );
        std::uint64_t mask = swarZeroByteMask( Fold::swar8( a ) ^ n0 ) & swarZeroByteMask( Fold::swar8( b ) ^ nl ) & ~( ( 1ull << ( 8 * ( k - at0 ) ) ) - 1 );
        while( mask != 0 )
        {
            const std::size_t at = at0 + ( std::size_t( std::countr_zero( mask ) ) >> 3 );
            if( verify( at ) )
            {
                return at;
            }
            mask &= mask - 1;
        }
        return n;
    }
    for( ; k + span <= n; ++k )
    {
        if( Fold::one( p[ k ] ) == first && Fold::one( p[ k + span - 1 ] ) == last && verify( k ) )
        {
            return k;
        }
    }
    return n;
}

template<class Fold = ExactBytes, class Verify>
inline std::size_t findByEndBytes( const char* p, std::size_t n, NeedleEnds ends, Verify&& verify ) noexcept
{
    const auto [ first, last, span ] = ends;
    if( span == 0 || span > n )
    {
        return n;
    }
    std::size_t k = 0;
#if defined( __ARM_NEON )
    const uint8x16_t s0 = vdupq_n_u8( static_cast<std::uint8_t>( first ) );
    const uint8x16_t sl = vdupq_n_u8( static_cast<std::uint8_t>( last ) );
    const auto block = [ & ]( std::size_t at0 ) noexcept   // the candidates of the sixteen starts at0..at0+15
    {
        const uint8x16_t v0 = Fold::vec( vld1q_u8( reinterpret_cast<const std::uint8_t*>( p + at0 ) ) );
        const uint8x16_t vl = Fold::vec( vld1q_u8( reinterpret_cast<const std::uint8_t*>( p + at0 + span - 1 ) ) );
        return vandq_u8( vceqq_u8( v0, s0 ), vceqq_u8( vl, sl ) );
    };
    const auto verifyEach = [ & ]( std::size_t at0, std::uint64_t mask ) noexcept
    {
        while( mask != 0 )
        {
            // one NIBBLE per input byte, so the lowest set bit sits at 4 * byteIndex and clearing the
            // candidate means clearing its whole nibble — `mask &= mask - 1` (the bit-per-byte idiom) would
            // spin on the other three bits of the same byte.
            const int         lowBit = std::countr_zero( mask );
            const std::size_t at     = at0 + ( std::size_t( lowBit ) >> 2 );
            if( verify( at ) )
            {
                return at;
            }
            mask &= ~( 0xFull << ( lowBit & ~3 ) );
        }
        return n;
    };
    // Four blocks per test: sixty-four starts, one OR-reduced mask, so a stretch with no candidate costs one branch per 64 B (the
    // one-block loop below measured 0.6x libc's memchr-led std find on a rare first byte; this one is its equal or better).
    while( k + span + 63 <= n )
    {
        const uint8x16_t c0 = block( k ), c1 = block( k + 16 ), c2 = block( k + 32 ), c3 = block( k + 48 );
        if( neonNibbleMask( vorrq_u8( vorrq_u8( c0, c1 ), vorrq_u8( c2, c3 ) ) ) != 0 )
        {
            const uint8x16_t cs[ 4 ] = { c0, c1, c2, c3 };
            for( std::size_t b = 0; b < 4; ++b )
            {
                const std::size_t at = verifyEach( k + 16 * b, neonNibbleMask( cs[ b ] ) );
                if( at != n )
                {
                    return at;
                }
            }
        }
        k += 64;
    }
    while( k + span + 15 <= n )                // sixteen starts, each with the whole needle in range
    {
        const std::size_t at = verifyEach( k, neonNibbleMask( block( k ) ) );
        if( at != n )
        {
            return at;
        }
        k += 16;
    }
    const std::size_t starts = n - span + 1;
    if( starts >= 16 )                         // the last 0..15 starts: one block ending at the last start, the starts below k (tested
    {                                          // already) masked off, so a haystack of sixteen starts or more never reaches the scalar tail
        if( k == starts )
        {
            return n;
        }
        const std::size_t at0 = starts - 16;
        return verifyEach( at0, neonNibbleMask( block( at0 ) ) & ~( ( 1ull << ( 4 * ( k - at0 ) ) ) - 1 ) );
    }
#elif defined( __AVX2__ )
    const __m256i s0    = _mm256_set1_epi8( first );
    const __m256i sl    = _mm256_set1_epi8( last );
    const auto    block = [ & ]( std::size_t at0 ) noexcept   // the candidates of the thirty-two starts at0..at0+31
    {
        const __m256i v0 = Fold::vec( _mm256_loadu_si256( reinterpret_cast<const __m256i*>( p + at0 ) ) );
        const __m256i vl = Fold::vec( _mm256_loadu_si256( reinterpret_cast<const __m256i*>( p + at0 + span - 1 ) ) );
        return _mm256_and_si256( _mm256_cmpeq_epi8( v0, s0 ), _mm256_cmpeq_epi8( vl, sl ) );
    };
    const auto verifyEach = [ & ]( std::size_t at0, std::uint32_t mask ) noexcept
    {
        while( mask != 0 )
        {
            const std::size_t at = at0 + std::size_t( std::countr_zero( mask ) );
            if( verify( at ) )
            {
                return at;
            }
            mask &= mask - 1;
        }
        return n;
    };
    // Two blocks per test (sixty-four starts), the NEON loop's shape: one OR-reduced test per 64 B.
    while( k + span + 63 <= n )
    {
        const __m256i c0 = block( k ), c1 = block( k + 32 );
        if( !_mm256_testz_si256( _mm256_or_si256( c0, c1 ), _mm256_or_si256( c0, c1 ) ) )
        {
            std::size_t at = verifyEach( k, std::uint32_t( _mm256_movemask_epi8( c0 ) ) );
            if( at == n )
            {
                at = verifyEach( k + 32, std::uint32_t( _mm256_movemask_epi8( c1 ) ) );
            }
            if( at != n )
            {
                return at;
            }
        }
        k += 64;
    }
    while( k + span + 31 <= n )                // thirty-two starts, each with the whole needle in range
    {
        const std::size_t at = verifyEach( k, std::uint32_t( _mm256_movemask_epi8( block( k ) ) ) );
        if( at != n )
        {
            return at;
        }
        k += 32;
    }
    const std::size_t starts = n - span + 1;
    if( starts >= 32 )                         // the last 0..31 starts: one block ending at the last start, as on NEON
    {
        if( k == starts )
        {
            return n;
        }
        const std::size_t at0 = starts - 32;
        return verifyEach( at0, std::uint32_t( _mm256_movemask_epi8( block( at0 ) ) ) & ~( ( 1u << ( k - at0 ) ) - 1 ) );
    }
#endif
    const std::size_t tail = findByEndBytes_scalar<Fold>( p + k, n - k, ends, [ &verify, k ]( std::size_t at ) { return verify( k + at ); } );
    return tail == n - k ? n : k + tail;
}

// Which path a dispatching kernel runs: the compiled vector path (NEON or AVX2; the scalar loop on a target with neither), or the scalar
// twin every target compiles, the oracle test/strkerncheck.sh compares the vector path against. One entry per kernel, so a caller and
// the gate name the same function and the path is an argument, not a second spelling.
enum class KernelPath : std::uint8_t
{
    Vector,
    Scalar,
};

// The verifies: find3's one byte between its ends, and findNeedle's whole needle.
struct MiddleByteMatches
{
    const char* p;
    const char* needle;
    bool        operator()( std::size_t at ) const noexcept { return p[ at + 1 ] == needle[ 1 ]; }
};
struct LowerFoldedNeedleMatches   // ciFindLiteral's verify: the whole span, A-Z-folded, against the lowered needle
{
    const char* p;
    const char* needleLowered;
    std::size_t m;
    bool        operator()( std::size_t at ) const noexcept { return lowerFoldedEquals( p + at, needleLowered, m ); }
};
struct WholeNeedleMatches
{
    const char* p;
    const char* needle;
    std::size_t m;
    bool        operator()( std::size_t at ) const noexcept { return std::memcmp( p + at, needle, m ) == 0; }
};

// The first start the end-byte filter and `verify` both accept, on the path asked for.
template<class Fold = ExactBytes, class Verify>
inline std::size_t findByEndBytesOn( KernelPath path, const char* p, std::size_t n, NeedleEnds ends, const Verify& verify ) noexcept
{
    return path == KernelPath::Scalar ? findByEndBytes_scalar<Fold>( p, n, ends, verify ) : findByEndBytes<Fold>( p, n, ends, verify );
}

// Three-byte needle — the trigram probe shape: the first and THIRD bytes filter, byte 1 is the verify. Returns n when the needle
// does not occur, and when n < 3.
inline std::size_t find3( const char* p, std::size_t n, const char* needle, KernelPath path = KernelPath::Vector ) noexcept
{
    return findByEndBytesOn( path, p, n, { needle[ 0 ], needle[ 2 ], 3 }, MiddleByteMatches{ p, needle } );
}

// A needle of any length: its first and last bytes filter, a memcmp of the whole needle verifies. The first occurrence (the smallest
// start), so a caller looping from `hit + 1` sees every occurrence, overlapping ones included, in order: exactly std::string_view::find.
// Returns n when the needle does not occur, and when m > n; an empty needle occurs at 0. Measured over this repository's 131 MB
// (search.h grepScanText, 2026-11-26, arm64, warm, one thread): std::string::find 36-85 ms for a needle whose first byte is a common
// letter, this kernel 6-10 ms; a needle whose first byte is rare stays where it was (5-9 ms).
inline std::size_t findNeedle( const char* p, std::size_t n, const char* needle, std::size_t m, KernelPath path = KernelPath::Vector ) noexcept
{
    return m == 0 ? 0 : findByEndBytesOn( path, p, n, { needle[ 0 ], needle[ m - 1 ], m }, WholeNeedleMatches{ p, needle, m } );
}

// find's dispatch, from bench/bench_strkern_find.cpp (arm64 M2, cache-hot cuts of src/ + docs/, best of 9 rounds of thread CPU
// time, ns per find call; the tables and how to re-run them are in bench/STRKERN_FIND.md). Which find is fastest depends on
// three things, so find asks all three, cheapest first:
//   * the LENGTHS: a needle longer than what is left is npos with no byte read — std's answer, inlined here, never a call.
//   * the needle's FIRST BYTE: std's search is memchr for the first byte, then a compare. When that byte is rare, memchr strides
//     through the text faster than the two-byte block filter (one compare per byte, not two), so a needle whose first byte is not in
//     kCommonLeadBytes goes to std — "]]>" over 1 KB: std 34 ns, the block kernel 46 ns. When it is common, memchr stops at every
//     occurrence and the block kernel wins at every size: 0.4x std at 16 B, 0.2x at 32-64 B, 0.1-0.2x from 256 B up.
//   * a ONE-byte needle is memchr from kFindMemchrCutoff bytes up (the kernel's equal there); below it the kernel (0.76-0.97x).
// A LITERAL needle (the Literal overload) has a constant length, which lets the compiler specialize std's search for it; below a
// block of start positions that inlined std is the faster (2-5 ns against the kernel's 6-7), so a literal goes to the kernel only from
// kFindBlockStarts start positions up, and only with a common first byte.
inline constexpr std::size_t kFindMemchrCutoff = 16;
inline constexpr std::size_t kFindBlockStarts  = kBlockBytes;   // one vector block of start positions (16 NEON, 32 AVX2)

// The bytes that are COMMON at the start of a needle: every byte at >= 0.5 % of the text in each of three corpora (this repo's
// src/ + docs/, VS Code's src/, Envoy's source/; 2026-11-26, 20 MB each). A byte outside it is rare enough that std's memchr-led
// search is the faster find (see the dispatch note above). A wrong guess costs speed near the break-even, never an answer.
struct LeadByteTable
{
    bool common[ 256 ] = {};
};
consteval LeadByteTable leadByteTableOf( std::string_view bytes )
{
    LeadByteTable t;
    for( const char c : bytes ) { t.common[ static_cast<unsigned char>( c ) ] = true; }
    return t;
}
inline constexpr LeadByteTable kCommonLeadBytes = leadByteTableOf( "\n (),.:=abcdefghilmnoprstuvy" );

// find's dispatch is INLINED into every caller: its early outs (from past the end, empty needle, needle longer than the rest) are
// then a compare or two where std's are, instead of a call. The measured cost of a call was 1.5 ns on a 1.3 ns std answer.
#if defined( _MSC_VER ) && !defined( __clang__ )
    #define RW_STRKERN_ALWAYS_INLINE __forceinline
#else
    #define RW_STRKERN_ALWAYS_INLINE [[gnu::always_inline]] inline
#endif

// THE string-find utility (CONTRIBUTING.md §3 "String search"): the first occurrence of `needle` in `hay` at or after `from`, or
// std::string_view::npos. Contract: byte-identical to `hay.find( needle, from )` for EVERY input — npos when `from > hay.size()`
// or there is no occurrence, `from` for an empty needle — so a call site swaps one for the other with no other change, and walking from
// `hit + 1` yields every occurrence, overlapping ones included, in order. The proof is D2 in test/verify_strkern.cpp, a property
// test against std::string_view::find over every `from` of chosen and random inputs, on every path and either side of each cutoff,
// in exact-size heap buffers under ASan + UBSan (test/strkerncheck.sh). The scalar/NEON/AVX2 choice is made inside; `path`
// exists for that test alone (KernelPath::Scalar runs the scalar twin with no dispatch). It is the fastest find at every measured
// size — never slower than std in any cell of bench/bench_strkern_find.cpp, which fails red if it ever is — so it is the one to
// use everywhere (see the dispatch note above).
[[nodiscard]] RW_STRKERN_ALWAYS_INLINE std::size_t findIn( std::string_view hay, std::string_view needle, std::size_t from, KernelPath path ) noexcept
{
    if( from > hay.size() ) { return std::string_view::npos; }
    const std::size_t left = hay.size() - from, m = needle.size();
    if( m == 0 ) { return from; }
    if( m > left ) { return std::string_view::npos; }
    if( path == KernelPath::Vector )
    {
        if( m == 1 && left >= kFindMemchrCutoff ) { return hay.find( needle[ 0 ], from ); }
        if( m > 1 && !kCommonLeadBytes.common[ static_cast<unsigned char>( needle[ 0 ] ) ] ) { return hay.find( needle, from ); }
    }
    const std::size_t at = findNeedle( hay.data() + from, left, needle.data(), m, path );
    return at == left ? std::string_view::npos : from + at;
}

// A string LITERAL needle, checked at compile time: the constructor is consteval, so only a constant array binds (a runtime
// `char buf[ 64 ]` is a compile error, never a 63-byte needle), it must end in its NUL, and it may hold no other NUL (std's
// `hay.find( "a\0b" )` stops at the first one; refusing it keeps the two spellings from meaning different needles). Its length is
// a constant where find inlines, so the one-byte and long-needle branches fold away.
struct Literal
{
    const char* text       = nullptr;
    std::size_t size       = 0;
    bool        commonLead = false;   // kCommonLeadBytes holds text[ 0 ]: decided at compile time
    template<std::size_t N>
    consteval Literal( const char ( &s )[ N ] )   // NOLINT(google-explicit-constructor): the implicit conversion IS the feature
        : text( s ), size( N - 1 ), commonLead( N > 1 && kCommonLeadBytes.common[ static_cast<unsigned char>( s[ 0 ] ) ] )
    {
        if( s[ N - 1 ] != '\0' ) { throw "strkern::Literal: the array does not end in its NUL"; }   // a throw in consteval = compile error
        for( std::size_t i = 0; i + 1 < N; ++i )
        {
            if( s[ i ] == '\0' ) { throw "strkern::Literal: an embedded NUL would end std's needle early"; }
        }
    }
};

// find( hay, "literal", from ): the literal overload (a string literal reaches only this one).
[[nodiscard]] RW_STRKERN_ALWAYS_INLINE std::size_t find( std::string_view hay, Literal needle, std::size_t from = 0 ) noexcept
{
    const std::string_view n( needle.text, needle.size );
    if( !needle.commonLead || from > hay.size() || hay.size() - from < needle.size + kFindBlockStarts - 1 ) { return hay.find( n, from ); }
    return findIn( hay, n, from, KernelPath::Vector );
}

// find( hay, needle, from ): any runtime needle that converts to std::string_view — a std::string, a string_view, a const char*.
// An ARRAY needle is left to the Literal overload above, so a literal takes the checked, constant-length path and a runtime char
// array does not compile (spell it std::string_view( buf ) to search its strlen bytes, as std does).
template<class Needle>
    requires( std::is_convertible_v<const Needle&, std::string_view> && !std::is_array_v<Needle> )
[[nodiscard]] RW_STRKERN_ALWAYS_INLINE std::size_t find( std::string_view hay, const Needle& needle, std::size_t from = 0, KernelPath path = KernelPath::Vector ) noexcept
{
    return findIn( hay, std::string_view( needle ), from, path );
}

// The ASCII case-insensitive twin of find: the first start at or after `from` where `hay`, A-Z-folded, equals `needleLowered`, or
// std::string_view::npos. `needleLowered` is lowered once by the caller (an upper-case byte in it never matches, as for
// lowerFoldedEquals). Contract: byte-identical to folding every A-Z byte of `hay` to lower case and calling std::string_view::find,
// for EVERY input; bytes >= 0x80 never fold (no locale, no UTF-8 case mapping). D3 in test/verify_strkern.cpp is the property test.
[[nodiscard]] inline std::size_t ciFindLiteral( std::string_view hay, std::string_view needleLowered, std::size_t from = 0,
                                                KernelPath path = KernelPath::Vector ) noexcept
{
    if( from > hay.size() ) { return std::string_view::npos; }
    const std::size_t m = needleLowered.size();
    if( m == 0 ) { return from; }
    const std::size_t left = hay.size() - from;
    if( m > left ) { return std::string_view::npos; }   // from the lengths alone, as find answers it
    const char* const p = hay.data() + from;
    const std::size_t at   = findByEndBytesOn<AsciiLowerBytes>( path, p, left, { needleLowered[ 0 ], needleLowered[ m - 1 ], m },
                                                                LowerFoldedNeedleMatches{ p, needleLowered.data(), m } );
    return at == left ? std::string_view::npos : from + at;
}

// A 256-bit byte set that carries BOTH of the representations its users need, DERIVED ONCE at
// construction — usually at compile time, since every set this repo ships is `constexpr`:
//
//   bits[ 32 ]   bit ( b & 7 ) of byte ( b >> 3 ). What the SIMD paths want (`sz_find_byteset`'s layout):
//                that decomposition makes the membership test two table lookups — the (b >> 3) lookup
//                fetches the set's row byte, the (b & 7) lookup fetches the bit to test it with.
//   words[ 4 ]   bit ( b & 63 ) of word ( b >> 6 ). What a SCALAR loop wants: one indexed load, one
//                variable shift, one AND per byte — and, decisively, NO per-call preamble.
//
// WHY THE SET CARRIES ITS OWN WORDS RATHER THAN A SCAN DERIVING THEM. The tail of a block scan is short
// by construction (< kBlockBytes), and the hot callers of a byte-set scan are ALL tail: an escaper over a
// 6..40-byte symbol name or path never enters a 16- or 32-byte block loop at all. A tail that re-derives
// its set representation on entry therefore does O( 256 ) work before it looks at one byte of input.
//
// That is measured, not feared. Until 2026-09-10 `findByteset` ended every call in an oracle that
// re-derived these four words from `bits` on entry; routing rw::escapeXml through it took escapeXml from
// 4.62% to 22.46% of a warm `--top-k=100000` map, made the whole map 6-18% slower, and left the scan
// 3.5x-7x SLOWER than the per-byte switch it replaced on 6..40-byte inputs (lane M's report, the row that
// refused it). Deriving in `add` instead costs one extra OR per inserted byte, at construction.
//
// The oracle is still here, still a different derivation — it just is not the shipped tail any more. See
// findByteset_oracle below.
struct Byteset256
{
    std::uint8_t  bits[ 32 ] = {};    // ( b >> 3, b & 7 )  — the SIMD tables' layout
    std::uint64_t words[ 4 ] = {};    // ( b >> 6, b & 63 ) — the scalar tail's O( 1 ) test

    constexpr void add( unsigned char b ) noexcept
    {
        bits[ b >> 3 ] |= std::uint8_t( 1u << ( b & 7u ) );
#if defined( STRKERN_MUTATE )
        // MUTATION (gate's can-go-red arm): the high half of the set never reaches `words`, so the scalar
        // tail and the oracle disagree above 0x7F. This is the ONE mutation that is not SIMD-only, and it
        // exists because the defect it models is not SIMD-only either: a second stored derivation of the
        // same set can go stale silently, and E0/D1-E1 are the arms that must see it. Never define this.
        if( b < 0x80u )
        {
            words[ b >> 6 ] |= std::uint64_t( 1 ) << ( b & 63u );
        }
#else
        words[ b >> 6 ] |= std::uint64_t( 1 ) << ( b & 63u );
#endif
    }
    constexpr void addRange( unsigned char lo, unsigned char hi ) noexcept
    {
        for( unsigned b = lo; b <= unsigned( hi ); ++b )
        {
            add( static_cast<unsigned char>( b ) );
        }
    }
    constexpr bool contains( unsigned char b ) const noexcept { return ( bits[ b >> 3 ] >> ( b & 7u ) ) & 1u; }
    // The same question asked of the OTHER member. A caller never needs this — `contains` is the answer —
    // but the gate does: the two representations are built by the same `add`, so an arm that reads both
    // back is what proves they cannot drift (test/verify_strkern.cpp, "Byteset256 carries two agreeing
    // representations").
    constexpr bool containsWord( unsigned char b ) const noexcept { return ( words[ b >> 6 ] >> ( b & 63u ) ) & 1u; }
};

// THE SHIPPED SCALAR TWIN, and the tail every vector path below falls into. One O( 1 ) bit test per byte
// against the set's own precomputed words; no preamble, nothing derived per call. This is the function a
// target with neither NEON nor AVX2 runs, and it is also the function a 6-byte input runs on every target.
// kOutside = true asks the complement question — the first byte NOT in the set (find_first_not_of, skipWhile) — on the same
// tables, so a caller never builds a second, inverted set.
template<bool kOutside = false>
inline std::size_t findByteset_scalar( const char* p, std::size_t n, const Byteset256& set ) noexcept
{
    for( std::size_t k = 0; k < n; ++k )
    {
        const unsigned char c = static_cast<unsigned char>( p[ k ] );
        if( ( ( ( set.words[ c >> 6 ] >> ( c & 63u ) ) & 1u ) != 0 ) != kOutside )
        {
            return k;
        }
    }
    return n;
}

// THE ORACLE — for the gate, and for nothing else. It answers the same question by re-deriving the four
// words from `bits` through `contains`, i.e. through the (b >> 3, b & 7) packing, so a bug in EITHER
// representation cannot hide behind a reference that shares it. That derivation is a 256-iteration loop
// per call: it is why this must never be reachable from a shipped path, and the header comment above is
// the record of what happened when it was. Not called from anywhere in src/.
inline std::size_t findByteset_oracle( const char* p, std::size_t n, const Byteset256& set ) noexcept
{
    std::uint64_t words[ 4 ] = { 0, 0, 0, 0 };
    for( unsigned b = 0; b < 256u; ++b )
    {
        if( set.contains( static_cast<unsigned char>( b ) ) )
        {
            words[ b >> 6 ] |= std::uint64_t( 1 ) << ( b & 63u );
        }
    }
    for( std::size_t k = 0; k < n; ++k )
    {
        const unsigned char c = static_cast<unsigned char>( p[ k ] );
        if( ( words[ c >> 6 ] >> ( c & 63u ) ) & 1u )
        {
            return k;
        }
    }
    return n;
}

template<bool kOutside = false>
inline std::size_t findByteset( const char* p, std::size_t n, const Byteset256& set ) noexcept
{
    std::size_t k = 0;
#if defined( __ARM_NEON )
    static constexpr std::uint8_t kBitOfIndex[ 16 ] = { 1, 2, 4, 8, 16, 32, 64, 128, 1, 2, 4, 8, 16, 32, 64, 128 };
    const uint8x16_t rowsLo  = vld1q_u8( set.bits );          // rows 0..15  → bytes 0x00..0x7F
    const uint8x16_t rowsHi  = vld1q_u8( set.bits + 16 );     // rows 16..31 → bytes 0x80..0xFF
    const uint8x16_t bitTab  = vld1q_u8( kBitOfIndex );
    for( ; k + 16 <= n; k += 16 )
    {
        const uint8x16_t v   = vld1q_u8( reinterpret_cast<const std::uint8_t*>( p + k ) );
        const uint8x16_t idx = vshrq_n_u8( v, 3 );                                   // 0..31
        // vqtbl1q_u8 returns 0 for an index >= 16, which is exactly the lane selection we want: the low
        // table answers for idx 0..15 and zeroes the rest, the high table answers for idx 16..31 after
        // the (wrapping) subtract pushes 0..15 far out of range. OR them and there is no blend to do.
#if defined( STRKERN_MUTATE )
        const uint8x16_t row = vqtbl1q_u8( rowsLo, idx );                            // MUTATION: high half dropped
#else
        const uint8x16_t row = vorrq_u8( vqtbl1q_u8( rowsLo, idx ),
                                         vqtbl1q_u8( rowsHi, vsubq_u8( idx, vdupq_n_u8( 16 ) ) ) );
#endif
        const uint8x16_t bit = vqtbl1q_u8( bitTab, vandq_u8( v, vdupq_n_u8( 7 ) ) );
        const uint8x16_t    in = vtstq_u8( row, bit );
        const std::uint64_t m  = neonNibbleMask( kOutside ? vmvnq_u8( in ) : in );
        if( m != 0 )
        {
            return k + ( std::size_t( std::countr_zero( m ) ) >> 2 );
        }
    }
#elif defined( __AVX2__ )
    static constexpr std::uint8_t kBitOfIndex[ 16 ] = { 1, 2, 4, 8, 16, 32, 64, 128, 1, 2, 4, 8, 16, 32, 64, 128 };
    const __m256i rowsLo = _mm256_broadcastsi128_si256( _mm_loadu_si128( reinterpret_cast<const __m128i*>( set.bits ) ) );
    const __m256i rowsHi = _mm256_broadcastsi128_si256( _mm_loadu_si128( reinterpret_cast<const __m128i*>( set.bits + 16 ) ) );
    const __m256i bitTab = _mm256_broadcastsi128_si256( _mm_loadu_si128( reinterpret_cast<const __m128i*>( kBitOfIndex ) ) );
    for( ; k + 32 <= n; k += 32 )
    {
        const __m256i v   = _mm256_loadu_si256( reinterpret_cast<const __m256i*>( p + k ) );
        const __m256i idx = _mm256_and_si256( _mm256_srli_epi16( v, 3 ), _mm256_set1_epi8( 0x1F ) );
        // pshufb takes index & 15 (it only zeroes when bit 7 is set), so unlike NEON the two halves must
        // be BLENDED rather than OR-ed — and the selector is v itself: its high bit is set exactly for
        // the bytes 0x80..0xFF whose row lives in the high table.
#if defined( STRKERN_MUTATE )
        const __m256i row = _mm256_shuffle_epi8( rowsLo, idx );                       // MUTATION: high half dropped
#else
        const __m256i row = _mm256_blendv_epi8( _mm256_shuffle_epi8( rowsLo, idx ),
                                                _mm256_shuffle_epi8( rowsHi, idx ), v );
#endif
        const __m256i bit = _mm256_shuffle_epi8( bitTab, _mm256_and_si256( v, _mm256_set1_epi8( 7 ) ) );
        const __m256i hit = _mm256_cmpeq_epi8( _mm256_and_si256( row, bit ), bit );
        const std::uint32_t in = std::uint32_t( _mm256_movemask_epi8( hit ) );
        const std::uint32_t m  = kOutside ? ~in : in;
        if( m != 0 )
        {
            return k + std::size_t( std::countr_zero( m ) );
        }
    }
#endif
    // The tail is the scalar twin above — one bit test per byte against the set's OWN words. It is NOT
    // the oracle: see the Byteset256 note for the 4.62% -> 22.46% that rule is written from.
    const std::size_t tail = findByteset_scalar<kOutside>( p + k, n - k, set );
    return tail == n - k ? n : k + tail;
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════
//  4. appendCleanRun — the run-copy step the emit escapers are built out of
// ═══════════════════════════════════════════════════════════════════════════════════════════════════
//
// Lane M's shape, folded into this header on 2026-09-10 the moment the tail above stopped being the
// oracle. It lived in a sibling `src/infra/strkern_find.h` for exactly as long as that defect did, and
// that header's own closing note named this as the fold-back: "if strkern.h grows a shipped tail beside
// its oracle, this file collapses into a call to it and the SIMD path comes along for free". It has, so
// it did. (Owner, 2026-09-10: ALL SIMD string kernels live in ONE header.)
//
// Appends the bytes from d[i] up to (not including) the next byte that is IN `set` — the run the caller's
// per-byte switch has no opinion about — and returns the index of that byte, or n when the rest is clean.
// A zero-length run appends nothing, so the caller needs no emptiness test.
//
// Written to sit in a `for`'s INIT and INCREMENT slots:
//     for( std::size_t i = appendCleanRun( d, 0, n, set, out ); i < n; i = appendCleanRun( d, i, n, set, out ) )
// which is why it takes the index rather than a pointer and returns the next one. That placement is not
// cosmetic: the increment expression also runs on `continue`, so an escaper whose switch arms end in
// `continue` (jsonesc::escapeInto) keeps every one of them, and the loop keeps the SINGLE branch it had
// before the rewrite — the run-copy costs the escapers no measured complexity, which is the difference
// between a gated --quality-delta row and none.
//
// It scans with `findByteset`, i.e. with the block loop, not with the scalar twin — measured, on the REAL
// inputs a warm `--top-k=100000` map hands rw::escapeXml (44k-341k calls per corpus, captured with a
// scratch trace build, replayed end to end through escapeXml, best of 9, four independent process runs,
// box load 24-33). Milliseconds for the whole trace, lower is better:
//
//   corpus     per-byte switch   run-copy + scalar scan   run-copy + findByteset
//   host tree    1.60-2.00              0.81-1.01               0.71-0.96   −15% vs scalar
//   go           6.85-7.62              4.57-4.85               4.74-5.08    +1% (median len 8: 82% of
//                                                                                calls never reach a block)
//   django       8.00-9.12              3.80-4.30               2.97-3.11   −23% vs scalar
//
// Two corpora win, one ties, none loses outside the noise band — so the block loop ships and no caller
// has to choose. The verb-level number is deliberately NOT claimed: escapeXml is ~1% of a warm map here
// (0.82-1.18% by `sample`), so a 15-23% cut in it is ~0.2% of the run and an interleaved whole-verb A/B
// at this box load resolves nothing (it did not: 12 runs a side, medians identical to 0.01 s).
//
// ONE template, not two overloads — a second body differing only in how it spells "append k bytes" is a
// 48-token clone of the first, and --quality-delta says so out loud. The spelling is picked by
// `if constexpr`: std::string (jsonesc's sink) has the (pointer, count) append and it is measurably the
// faster of the two, std::vector<char> (serialize's sink) has only the iterator-pair insert. Both take a
// contiguous-range memcpy underneath; the difference is the length arithmetic libc++ has to redo when it
// is handed iterators instead of a count, and on strings this short that arithmetic is not free.
template< typename Sink >
inline std::size_t appendCleanRun( const char* d, std::size_t i, std::size_t n, const Byteset256& set, Sink& out )
{
    const std::size_t clean = findByteset( d + i, n - i, set );
    if constexpr( requires { out.append( d + i, clean ); } )
    {
        out.append( d + i, clean );
    }
    else
    {
        out.insert( out.end(), d + i, d + i + clean );
    }
    return i + clean;
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════
//  5. one byte's positions and count — lineStarts, countByte
// ═══════════════════════════════════════════════════════════════════════════════════════════════════
//
// About nine hand loops built a line-start table (`if( text[ i ] == '\n' ) starts.push_back( i + 1 )`) and about thirty counted
// newlines one byte at a time (`std::count`, or a loop with `++line`). Both are one question — where, or how many, of ONE byte — so
// both are one block compare: sixteen (NEON) or thirty-two (AVX2) bytes against a splat, then the mask's set bits (positions) or
// their number (count). The scalar twins are the SWAR form of the same compare (swarZeroByteMask: one exact high bit per match).

// fn( k ) for every k < n with p[ k ] == b, in ascending order.
template<class Fn>
inline void forEachByte_scalar( const char* p, std::size_t n, char b, Fn&& fn )
{
    constexpr std::uint64_t kOnes = 0x0101010101010101ull;
    const std::uint64_t     splat = kOnes * static_cast<unsigned char>( b );
    std::size_t             k     = 0;
    for( ; k + 8 <= n; k += 8 )
    {
        std::uint64_t x = 0;
        std::memcpy( &x, p + k, 8 );
        for( std::uint64_t m = swarZeroByteMask( x ^ splat ); m != 0; m &= m - 1 )   // one exact bit per match: the bit idiom is right here
        {
            fn( k + ( std::size_t( std::countr_zero( m ) ) >> 3 ) );
        }
    }
    for( ; k < n; ++k )
    {
        if( p[ k ] == b )
        {
            fn( k );
        }
    }
}

template<class Fn>
inline void forEachByte( const char* p, std::size_t n, char b, Fn&& fn )
{
    std::size_t k = 0;
#if defined( __ARM_NEON )
    const uint8x16_t splat = vdupq_n_u8( static_cast<std::uint8_t>( b ) );
    for( ; k + 16 <= n; k += 16 )
    {
        // keep one bit of each match's nibble, so the bit-per-match idiom walks it
#if defined( STRKERN_MUTATE )
        constexpr std::uint64_t kOneBitPerByte = 0x0888888888888888ull;   // MUTATION: a match in lane 15 is never reported
#else
        constexpr std::uint64_t kOneBitPerByte = 0x8888888888888888ull;
#endif
        std::uint64_t m = neonNibbleMask( vceqq_u8( vld1q_u8( reinterpret_cast<const std::uint8_t*>( p + k ) ), splat ) ) & kOneBitPerByte;
        for( ; m != 0; m &= m - 1 )
        {
            fn( k + ( std::size_t( std::countr_zero( m ) ) >> 2 ) );
        }
    }
#elif defined( __AVX2__ )
    const __m256i splat = _mm256_set1_epi8( b );
    for( ; k + 32 <= n; k += 32 )
    {
        const __m256i v = _mm256_loadu_si256( reinterpret_cast<const __m256i*>( p + k ) );
#if defined( STRKERN_MUTATE )
        constexpr std::uint32_t kLanes = 0x7FFFFFFFu;   // MUTATION: a match in lane 31 is never reported
#else
        constexpr std::uint32_t kLanes = 0xFFFFFFFFu;
#endif
        for( std::uint32_t m = std::uint32_t( _mm256_movemask_epi8( _mm256_cmpeq_epi8( v, splat ) ) ) & kLanes; m != 0; m &= m - 1 )
        {
            fn( k + std::size_t( std::countr_zero( m ) ) );
        }
    }
#endif
    forEachByte_scalar( p + k, n - k, b, [ &fn, k ]( std::size_t at ) { fn( k + at ); } );
}

template<class Fn>
inline void forEachByteOn( KernelPath path, const char* p, std::size_t n, char b, Fn&& fn )
{
    path == KernelPath::Scalar ? forEachByte_scalar( p, n, b, fn ) : forEachByte( p, n, b, fn );
}

// How many bytes of `text` equal `b`. Contract: == std::count( text.begin(), text.end(), b ), for every input. A line count is
// countByte( text, '\n' ) (plus one, or not, as the caller's own convention says); the line holding offset `at` is
// 1 + countByte( text.substr( 0, at ), '\n' ). D5 in test/verify_strkern.cpp is the property test.
[[nodiscard]] inline std::size_t countByte( std::string_view text, char b, KernelPath path = KernelPath::Vector ) noexcept
{
    const char* const p = text.data();
    const std::size_t n = text.size();
    std::size_t       k = 0, count = 0;
    if( path == KernelPath::Vector )
    {
#if defined( __ARM_NEON )
        const uint8x16_t splat = vdupq_n_u8( static_cast<std::uint8_t>( b ) );
        while( k + 16 <= n )
        {
            // a match compares to 0xFF, i.e. -1: subtracting it adds one to that lane. 255 blocks at most, so no lane wraps
            uint8x16_t        lanes = vdupq_n_u8( 0 );
            const std::size_t stop  = k + 16 * std::min<std::size_t>( 255, ( n - k ) / 16 );
            for( ; k < stop; k += 16 )
            {
                lanes = vsubq_u8( lanes, vceqq_u8( vld1q_u8( reinterpret_cast<const std::uint8_t*>( p + k ) ), splat ) );
            }
#if defined( STRKERN_MUTATE )
            lanes = vsetq_lane_u8( 0, lanes, 15 );   // MUTATION: lane 15's matches are never counted
#endif
            count += vaddlvq_u8( lanes );
        }
#elif defined( __AVX2__ )
        const __m256i splat = _mm256_set1_epi8( b );
        for( ; k + 32 <= n; k += 32 )
        {
            const __m256i v = _mm256_loadu_si256( reinterpret_cast<const __m256i*>( p + k ) );
#if defined( STRKERN_MUTATE )
            constexpr std::uint32_t kLanes = 0x7FFFFFFFu;   // MUTATION: lane 31's matches are never counted
#else
            constexpr std::uint32_t kLanes = 0xFFFFFFFFu;
#endif
            count += std::size_t( std::popcount( std::uint32_t( _mm256_movemask_epi8( _mm256_cmpeq_epi8( v, splat ) ) ) & kLanes ) );
        }
#endif
    }
    constexpr std::uint64_t kOnes = 0x0101010101010101ull;
    const std::uint64_t     splat = kOnes * static_cast<unsigned char>( b );
    for( ; k + 8 <= n; k += 8 )
    {
        std::uint64_t x = 0;
        std::memcpy( &x, p + k, 8 );
        count += std::size_t( std::popcount( swarZeroByteMask( x ^ splat ) ) );   // exact: one high bit per matching byte
    }
    for( ; k < n; ++k )
    {
        count += p[ k ] == b ? 1u : 0u;
    }
    return count;
}

// Whether the table ends with a start AT text.size() when the text ends in '\n' — the start of an empty last line. Both house
// conventions exist: most tables keep it (graph, lsp, situ, search); FileTextCache and the file page drop it.
enum class FinalLineStart : std::uint8_t
{
    Keep,
    DropAtEnd,
};

// THE line-start table: appends 0, then k + 1 for every '\n' at k, to `out` (any container with push_back / pop_back and an
// integral value_type; the value is cast to it). A "\r\n" line ends at its '\n' like every other, so CRLF text gets the same starts
// the hand loops gave it; a text with no final newline gets no extra start; an empty text gets { 0 }. With
// FinalLineStart::DropAtEnd, the start a final '\n' would add at text.size() is left out. D4 in test/verify_strkern.cpp checks it
// against the hand loop it replaced, both conventions, on both paths.
template<class Vec>
inline void lineStarts( std::string_view text, Vec& out, FinalLineStart final = FinalLineStart::Keep, KernelPath path = KernelPath::Vector )
{
    using T = typename Vec::value_type;
    out.push_back( T( 0 ) );
    forEachByteOn( path, text.data(), text.size(), '\n', [ &out ]( std::size_t k ) { out.push_back( T( k + 1 ) ); } );
    if( final == FinalLineStart::DropAtEnd && !text.empty() && text.back() == '\n' )
    {
        out.pop_back();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════
//  6. findAnyOf / findNotAnyOf / skipWhile — the std byte-set searches, on findByteset
// ═══════════════════════════════════════════════════════════════════════════════════════════════════
//
// std::string_view::find_first_of( chars ) tests each text byte against each set byte (libc++ calls memchr over the set per text
// byte); a Byteset256 built once (constexpr: bytesetOf below) answers in two table lookups per byte, sixteen or thirty-two bytes at
// a time (findByteset, section 3). A set of one or two bytes stays `find( c )` / memchr.

// The set of the bytes in `chars`. constexpr, so a call site's set is built at compile time:
//     static constexpr auto kQuoteOrEscape = strkern::bytesetOf( "\"'\\\\" );
[[nodiscard]] constexpr Byteset256 bytesetOf( std::string_view chars ) noexcept
{
    Byteset256 set;
    for( const char c : chars )
    {
        set.add( static_cast<unsigned char>( c ) );
    }
    return set;
}

// The ASCII classes the "C" locale's <cctype> predicates name — the only locale ripwire runs in — so a scan loop needs no libc
// call per byte. A byte >= 0x80 is in none of them, as in the "C" locale.
inline constexpr Byteset256 kAsciiSpace = bytesetOf( " \t\n\v\f\r" );   // std::isspace
inline constexpr Byteset256 kAsciiDigit = bytesetOf( "0123456789" );    // std::isdigit
inline constexpr Byteset256 kAsciiAlnum = bytesetOf( "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" );   // std::isalnum
inline constexpr Byteset256 kAsciiIdent = bytesetOf( "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_" );  // isalnum || '_'

// The first position at or after `from` whose byte is in `set`, or npos. Contract: == hay.find_first_of( chars, from ) for the
// `chars` the set was built from, for every input (npos when from >= hay.size()). D6 in test/verify_strkern.cpp.
[[nodiscard]] inline std::size_t findAnyOf( std::string_view hay, const Byteset256& set, std::size_t from = 0,
                                            KernelPath path = KernelPath::Vector ) noexcept
{
    if( from >= hay.size() ) { return std::string_view::npos; }
    const std::size_t left = hay.size() - from;
    const std::size_t at   = path == KernelPath::Scalar ? findByteset_scalar( hay.data() + from, left, set ) : findByteset( hay.data() + from, left, set );
    return at == left ? std::string_view::npos : from + at;
}

// The first position at or after `from` whose byte is NOT in `set`, or npos. Contract: == hay.find_first_not_of( chars, from ).
[[nodiscard]] inline std::size_t findNotAnyOf( std::string_view hay, const Byteset256& set, std::size_t from = 0,
                                               KernelPath path = KernelPath::Vector ) noexcept
{
    if( from >= hay.size() ) { return std::string_view::npos; }
    const std::size_t left = hay.size() - from;
    const std::size_t at   = path == KernelPath::Scalar ? findByteset_scalar<true>( hay.data() + from, left, set )
                                                        : findByteset<true>( hay.data() + from, left, set );
    return at == left ? std::string_view::npos : from + at;
}

// The run loop `while( i < hay.size() && in( hay[ i ] ) ) ++i;` as one call: the first position at or after `from` whose byte is not
// in `set`, hay.size() when the run reaches the end, and `from` itself when from >= hay.size() (the loop's body never ran).
[[nodiscard]] inline std::size_t skipWhile( std::string_view hay, const Byteset256& set, std::size_t from = 0,
                                            KernelPath path = KernelPath::Vector ) noexcept
{
    if( from >= hay.size() ) { return from; }
    const std::size_t at = findNotAnyOf( hay, set, from, path );
    return at == std::string_view::npos ? hay.size() : at;
}

}   // namespace rw::strkern
