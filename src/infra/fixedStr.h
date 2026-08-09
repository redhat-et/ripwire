#pragma once

// fixedStr.h — a 32-byte fixed-capacity string for hot SHORT-string workloads (symbol tables, dictionary
// keys, join keys). The trick: length is stored inline and the tail is ZERO-PADDED at construction, so the
// whole object is a fixed 32-byte block whose unused bytes are deterministically zero. Equality and hashing
// then run as BRANCHLESS fixed-width operations over all 32 bytes — no length check, no variable-length loop,
// no heap pointer to chase. Strings longer than 31 bytes truncate (a `truncated()` probe is provided) —
// intended for identifiers (e.g. final-segment symbol names, ~all < 31 chars), NOT arbitrary text or paths.
//
// Layout: { len:1, data:31 } = exactly 32 bytes, alignas(16) → two 16-byte SIMD loads (NEON or SSE2)
// cover it. Vendorable: depends only on the standard library + (optionally) <arm_neon.h>/<emmintrin.h>.

#include "hashutil.h"   // sanitizer-clean modulo-2^64 FNV multiplication

#include <cstdint>
#include <cstring>
#include <string_view>
#if defined( __ARM_NEON )
    #include <arm_neon.h>
#elif defined( __SSE2__ ) || defined( _M_X64 )
    #include <emmintrin.h>
#endif

namespace rw
{

struct alignas( 16 ) FixedStr
{
    static constexpr int CAP = 31;
    std::uint8_t len = 0;            // bytes used (≤ CAP)
    char         data[ CAP ] = {};   // zero-padded tail — load-bearing for the branchless compare/hash

    FixedStr() noexcept = default;

    explicit FixedStr( std::string_view s ) noexcept
    {
        len = std::uint8_t( s.size() < std::size_t( CAP ) ? s.size() : CAP );   // truncate over-long
        std::memcpy( data, s.data(), len );
        std::memset( data + len, 0, std::size_t( CAP ) - len );                 // zero pad → fixed-width ops
    }

    std::string_view view() const noexcept { return { data, len }; }
    static bool       fits( std::string_view s ) noexcept { return s.size() <= std::size_t( CAP ); }

    bool operator==( const FixedStr& o ) const noexcept
    {
#if defined( __ARM_NEON )
        const auto* pa = reinterpret_cast<const std::uint8_t*>( this );
        const auto* pb = reinterpret_cast<const std::uint8_t*>( &o );
        const uint8x16_t eq = vandq_u8( vceqq_u8( vld1q_u8( pa ), vld1q_u8( pb ) ),
                                        vceqq_u8( vld1q_u8( pa + 16 ), vld1q_u8( pb + 16 ) ) );
        return vminvq_u8( eq ) == 0xFF;                 // all 32 bytes equal (len byte included)
#elif defined( __SSE2__ ) || defined( _M_X64 )
        const auto* pa = reinterpret_cast<const __m128i*>( this );
        const auto* pb = reinterpret_cast<const __m128i*>( &o );
        const __m128i eq = _mm_and_si128( _mm_cmpeq_epi8( _mm_load_si128( pa ),     _mm_load_si128( pb ) ),
                                          _mm_cmpeq_epi8( _mm_load_si128( pa + 1 ), _mm_load_si128( pb + 1 ) ) );
        return _mm_movemask_epi8( eq ) == 0xFFFF;       // all 32 bytes equal (len byte included)
#else
        std::uint64_t w[ 4 ], v[ 4 ];
        std::memcpy( w, this, 32 );  std::memcpy( v, &o, 32 );
        return ( ( w[0] ^ v[0] ) | ( w[1] ^ v[1] ) | ( w[2] ^ v[2] ) | ( w[3] ^ v[3] ) ) == 0;
#endif
    }
    bool operator!=( const FixedStr& o ) const noexcept { return !( *this == o ); }

    // FNV-1a over the fixed 32-byte block (len + padded data) — no length branch, inline (no pointer chase).
    std::uint64_t hash() const noexcept
    {
        std::uint64_t w[ 4 ];
        std::memcpy( w, this, 32 );
        std::uint64_t h = 1469598103934665603ULL;
        for( int i = 0; i < 4; ++i ) { h ^= w[i]; h = hashutil::fnv1aMultiply( h ); }
        return h;
    }
};
static_assert( sizeof( FixedStr ) == 32, "FixedStr must be exactly 32 bytes (2 per cache line)" );

struct FixedStrHash { std::uint64_t operator()( const FixedStr& s ) const noexcept { return s.hash(); } };

// ---------------------------------------------------------------------------
// findByte — the same branchless SIMD compare as FixedStr::operator==, aimed at an ARBITRARY byte span
// instead of a fixed 32-byte block. It is a FREE FUNCTION, not a FixedStr member, precisely because the
// span is arbitrary: nothing about it is 32-byte-shaped. Returns the first position in [first,last) whose
// byte equals `needle`, or `last` if there is none — i.e. memchr's contract, restated over a pointer pair.
//
// EXACT, therefore determinism-neutral. This kernel computes the same answer as a byte-at-a-time loop for
// every input, with no tolerance, no approximation, and no data-dependent ordering: the vector body only
// ever runs where a full 16-byte load lies wholly inside the span, and the head/tail bytes go through the
// scalar path. Substituting it for a scalar scan cannot move any downstream output, so a caller's
// determinism contract is untouched by construction, not merely by measurement. bench/bench_newline_ab.cpp
// asserts that equivalence over the whole repo corpus plus the edge cases (empty span, needle at position
// 0, no trailing needle, CRLF bytes) before it reports a single timing number.
//
// Alignment: both vld1q_u8 and _mm_loadu_si128 are defined for unaligned addresses, and the loop never
// issues a load that reaches past `last`, so there is no page-crossing read and no alignment prologue to
// get wrong. The bytes before the first full vector and after the last one are handled scalar-side.
inline const char* findByte( const char* first, const char* last, char needle ) noexcept
{
#if defined( __ARM_NEON )
    const uint8x16_t want = vdupq_n_u8( std::uint8_t( needle ) );
    while( last - first >= 16 )
    {
        const uint8x16_t eq = vceqq_u8( vld1q_u8( reinterpret_cast<const std::uint8_t*>( first ) ), want );
        // shrn-by-4 folds the 16-byte 0x00/0xFF compare result into a 64-bit word carrying 4 mask bits per
        // input byte — arm64 has no movemask, and this is the cheapest exact substitute for one.
        const std::uint64_t mask = vget_lane_u64( vreinterpret_u64_u8( vshrn_n_u16( vreinterpretq_u16_u8( eq ), 4 ) ), 0 );
        if( mask != 0 )
        {
            return first + ( __builtin_ctzll( mask ) >> 2 );
        }
        first += 16;
    }
#elif defined( __SSE2__ ) || defined( _M_X64 )
    const __m128i want = _mm_set1_epi8( needle );
    while( last - first >= 16 )
    {
        const __m128i eq   = _mm_cmpeq_epi8( _mm_loadu_si128( reinterpret_cast<const __m128i*>( first ) ), want );
        const int     mask = _mm_movemask_epi8( eq );
        if( mask != 0 )
        {
            return first + __builtin_ctz( static_cast<unsigned>( mask ) );
        }
        first += 16;
    }
#endif
    while( first < last )
    {
        if( *first == needle )
        {
            return first;
        }
        ++first;
    }
    return last;
}

}   // namespace rw
