#pragma once

// fixedStr.h — a 32-byte fixed-capacity string for hot SHORT-string workloads (symbol tables, dictionary
// keys, join keys). The trick: length is stored inline and the tail is ZERO-PADDED at construction, so the
// whole object is a fixed 32-byte block whose unused bytes are deterministically zero. Equality and hashing
// then run as BRANCHLESS fixed-width operations over all 32 bytes — no length check, no variable-length loop,
// no heap pointer to chase. Strings longer than 31 bytes truncate (a `truncated()` probe is provided) —
// intended for identifiers (e.g. final-segment symbol names, ~all < 31 chars), NOT arbitrary text or paths.
//
// Layout: { len:1, data:31 } = exactly 32 bytes, alignas(16) → two NEON 16-byte loads cover it. Vendorable:
// depends only on the standard library + (optionally) <arm_neon.h>.

#include "hashutil.h"   // sanitizer-clean modulo-2^64 FNV multiplication

#include <cstdint>
#include <cstring>
#include <string_view>
#if defined( __ARM_NEON )
    #include <arm_neon.h>
#endif

namespace ctx
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

}   // namespace ctx
