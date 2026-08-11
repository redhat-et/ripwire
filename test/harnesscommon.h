// harnesscommon.h — the tiny support kit shared by the standalone SIMD parity harnesses
// (dynmapsimd_harness.cpp, radixsimd_harness.cpp): the PASS/FAIL line printer, the
// sanitizer-clean deterministic generator, and the per-key-type draw. Header-only so each
// gate still compiles standalone (one TU + diagnostics.cpp); lives in test/, not src/,
// because nothing shipped includes it.
#pragma once

#include "../src/infra/hashutil.h"

#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <type_traits>

inline int g_fail = 0;

inline void checkf( bool cond, const char* fmt, ... )
{
    std::va_list args;
    va_start( args, fmt );
    char msg[ 256 ];
    std::vsnprintf( msg, sizeof( msg ), fmt, args );
    va_end( args );
    std::printf( "  %s  %s\n", cond ? "PASS" : "FAIL", msg );
    if( !cond )
    {
        g_fail = 1;
    }
}

// Deterministic generator built on the house sanitizer-clean multiply (hashutil::multiplyModulo64) —
// libc++'s mt19937 trips G1's unsigned-shift-base check inside its own header, so it cannot run under
// these gates' -fno-sanitize-recover=all. XOR (never wraps) replaces the usual LCG add; murmur-style
// right-shift mixing is UB-free by construction. Fixed seed ⇒ failure reports reproduce anywhere.
struct DeterministicRng
{
    std::uint64_t state;

    std::uint64_t next() noexcept
    {
        state = rw::hashutil::multiplyModulo64( state, 6364136223846793005ull ) ^ 1442695040888963407ull;
        std::uint64_t mixed = state;
        mixed ^= mixed >> 33;
        mixed = rw::hashutil::multiplyModulo64( mixed, 0xFF51AFD7ED558CCDull );
        mixed ^= mixed >> 33;
        return mixed;
    }
};

// One deterministic key drawn from the generator.
template< typename Key >
inline Key drawKey( DeterministicRng& gen )
{
    if constexpr( std::is_floating_point_v< Key > )
    {
        return Key( double( std::int64_t( gen.next() ) ) / 1e12 );
    }
    else
    {
        return Key( gen.next() );   // C++20+ two's-complement wrap: well-defined for signed targets
    }
}
