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
// mapped file. Every kernel has a `_scalar` twin that is ALWAYS compiled and always callable: it is the
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

#include <bit>            // std::countr_zero — the portable spelling of ctz; the scalar twins must compile on MSVC too
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string_view>

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

// Three-byte needle — the trigram probe shape. Muła's "check an anomalous first and last byte, then
// verify": the first and THIRD bytes are compared in parallel across a whole block, and only the handful
// of positions where both agree pay a three-byte verify. Returns n when the needle does not occur, and
// when n < 3.
inline std::size_t find3_scalar( const char* p, std::size_t n, const char* needle ) noexcept
{
    if( n < 3 )
    {
        return n;
    }
    constexpr std::uint64_t kOnes = 0x0101010101010101ull;
    const std::uint64_t     n0    = kOnes * static_cast<unsigned char>( needle[ 0 ] );
    const std::uint64_t     n2    = kOnes * static_cast<unsigned char>( needle[ 2 ] );
    std::size_t             k     = 0;
    while( k + 10 <= n )                       // needs 8 bytes at k AND 8 bytes at k + 2
    {
        std::uint64_t a = 0, b = 0;
        std::memcpy( &a, p + k, 8 );
        std::memcpy( &b, p + k + 2, 8 );
        // both masks are exact, so their AND marks exactly the positions where bytes 0 and 2 of the
        // needle agree; only byte 1 is left to verify (Mula's first/last-byte filter, serial spelling).
        std::uint64_t m = swarZeroByteMask( a ^ n0 ) & swarZeroByteMask( b ^ n2 );
        while( m != 0 )
        {
            const std::size_t at = k + ( std::size_t( std::countr_zero( m ) ) >> 3 );
            if( p[ at + 1 ] == needle[ 1 ] )
            {
                return at;
            }
            m &= m - 1;
        }
        k += 8;
    }
    for( ; k + 3 <= n; ++k )
    {
        if( std::memcmp( p + k, needle, 3 ) == 0 )
        {
            return k;
        }
    }
    return n;
}

inline std::size_t find3( const char* p, std::size_t n, const char* needle ) noexcept
{
    if( n < 3 )
    {
        return n;
    }
    std::size_t k = 0;
#if defined( __ARM_NEON )
    const uint8x16_t s0 = vdupq_n_u8( static_cast<std::uint8_t>( needle[ 0 ] ) );
    const uint8x16_t s2 = vdupq_n_u8( static_cast<std::uint8_t>( needle[ 2 ] ) );
    while( k + 18 <= n )                       // 16 bytes at k AND 16 bytes at k + 2
    {
        const uint8x16_t v0 = vld1q_u8( reinterpret_cast<const std::uint8_t*>( p + k ) );
        const uint8x16_t v2 = vld1q_u8( reinterpret_cast<const std::uint8_t*>( p + k + 2 ) );
        std::uint64_t    m  = neonNibbleMask( vandq_u8( vceqq_u8( v0, s0 ), vceqq_u8( v2, s2 ) ) );
        while( m != 0 )
        {
            // one NIBBLE per input byte, so the lowest set bit sits at 4 * byteIndex and clearing the
            // candidate means clearing its whole nibble — `m &= m - 1` (the bit-per-byte idiom) would
            // spin on the other three bits of the same byte.
            const int lowBit = std::countr_zero( m );
            const std::size_t at = k + ( std::size_t( lowBit ) >> 2 );
            if( p[ at + 1 ] == needle[ 1 ] )
            {
                return at;
            }
            m &= ~( 0xFull << ( lowBit & ~3 ) );
        }
        k += 16;
    }
#elif defined( __AVX2__ )
    const __m256i s0 = _mm256_set1_epi8( needle[ 0 ] );
    const __m256i s2 = _mm256_set1_epi8( needle[ 2 ] );
    while( k + 34 <= n )                       // 32 bytes at k AND 32 bytes at k + 2
    {
        const __m256i v0 = _mm256_loadu_si256( reinterpret_cast<const __m256i*>( p + k ) );
        const __m256i v2 = _mm256_loadu_si256( reinterpret_cast<const __m256i*>( p + k + 2 ) );
        std::uint32_t m  = std::uint32_t( _mm256_movemask_epi8(
                               _mm256_and_si256( _mm256_cmpeq_epi8( v0, s0 ), _mm256_cmpeq_epi8( v2, s2 ) ) ) );
        while( m != 0 )
        {
            const std::size_t at = k + std::size_t( std::countr_zero( m ) );
            if( p[ at + 1 ] == needle[ 1 ] )
            {
                return at;
            }
            m &= m - 1;
        }
        k += 32;
    }
#endif
    const std::size_t tail = find3_scalar( p + k, n - k, needle );
    return tail == n - k ? n : k + tail;
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
inline std::size_t findByteset_scalar( const char* p, std::size_t n, const Byteset256& set ) noexcept
{
    for( std::size_t k = 0; k < n; ++k )
    {
        const unsigned char c = static_cast<unsigned char>( p[ k ] );
        if( ( set.words[ c >> 6 ] >> ( c & 63u ) ) & 1u )
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
        const std::uint64_t m = neonNibbleMask( vtstq_u8( row, bit ) );
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
        const std::uint32_t m = std::uint32_t( _mm256_movemask_epi8( hit ) );
        if( m != 0 )
        {
            return k + std::size_t( std::countr_zero( m ) );
        }
    }
#endif
    // The tail is the scalar twin above — one bit test per byte against the set's OWN words. It is NOT
    // the oracle: see the Byteset256 note for the 4.62% -> 22.46% that rule is written from.
    const std::size_t tail = findByteset_scalar( p + k, n - k, set );
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

}   // namespace rw::strkern
