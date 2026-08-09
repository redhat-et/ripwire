// dynmapsimd_harness.cpp — SIMD-vs-scalar parity gate for the two vectorized kernels ripwire vendors.
//
//   A  stree::dyn::node_rank<Key,B>::lt/le (src/infra/dynamic_map.hpp) — "count of slots with key < x
//      (resp. <= x) over all B slots, sentinel-padded". The scalar loops in THIS file restate that
//      documented contract independently; the shipped kernel (NEON on arm64, SSE on x86_64, the scalar
//      template elsewhere) must match them on every (pattern, query) pair: sorted/unsorted, all-equal,
//      all-sentinel, sentinel-padded prefixes, sign-boundary values (the unsigned-bias trick's failure
//      site), and a fixed-seed random sweep (mt19937_64 raw output — standardized, so a failure report
//      reproduces bit-identically on any platform).
//   B  rw::FixedStr (src/infra/fixedStr.h) — 32-byte branchless equality vs a bytewise len+data reference,
//      the zero-pad construction invariant, len-byte participation, truncation semantics at CAP, and
//      a==b => hash(a)==hash(b) over the full case-set cross product.
//
// NON-VACUITY: the banner names the compiled kernels ("rank kernel: NEON|SSE|scalar", "fixedstr eq: ...").
// On arm64/x86_64 the gate script REQUIRES the vector kernel to have engaged — a scalar-only build there
// would compare the contract to itself and pass vacuously, which is exactly the green-but-blind shape the
// gate exists to prevent.
//
// Exit 0 = all pass; nonzero = failure (per-arm PASS/FAIL lines on stdout, first mismatch detailed).

#include "dynamic_map.hpp"

#include "../src/infra/fixedStr.h"

#include <algorithm>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <string>
#include <string_view>
#include <type_traits>
#include <vector>

static int g_fail = 0;

static void checkf( bool cond, const char* fmt, ... )
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

// ============================================================================
// Arm A — node_rank parity
// ============================================================================

// The documented contract, restated independently of dynamic_map.hpp's scalar template (so a future edit
// to that template cannot silently drag this oracle along with it).
template< typename Key >
static unsigned refLt( const Key* keys, int slotCount, Key x )
{
    unsigned count = 0;
    for( int i = 0; i < slotCount; ++i )
    {
        count += ( keys[ i ] < x ) ? 1u : 0u;
    }
    return count;
}

template< typename Key >
static unsigned refLe( const Key* keys, int slotCount, Key x )
{
    unsigned count = 0;
    for( int i = 0; i < slotCount; ++i )
    {
        count += ( keys[ i ] <= x ) ? 1u : 0u;
    }
    return count;
}

// Values chosen to sit on the seams where a vector kernel goes wrong: zero, sign boundaries (where the
// XOR-bias trick for unsigned SSE compares breaks if mis-applied), type min/max, and the sentinel itself.
template< typename Key >
static std::vector< Key > interestingValues()
{
    std::vector< Key > v;
    if constexpr( std::is_floating_point_v< Key > )
    {
        v = { Key( -1e30 ), Key( -2.5 ), Key( -0.0 ), Key( 0.0 ), Key( 0.5 ), Key( 3.0 ), Key( 1e30 ),
              std::numeric_limits< Key >::lowest(), std::numeric_limits< Key >::max() };
    }
    else if constexpr( std::is_signed_v< Key > )
    {
        v = { Key( 0 ), Key( 1 ), Key( -1 ), Key( 2 ), Key( -2 ), Key( 100 ),
              std::numeric_limits< Key >::min(), Key( std::numeric_limits< Key >::min() + 1 ),
              Key( std::numeric_limits< Key >::max() - 1 ), std::numeric_limits< Key >::max() };
    }
    else
    {
        const Key signBit = Key( Key( 1 ) << ( sizeof( Key ) * 8 - 1 ) );
        v = { Key( 0 ), Key( 1 ), Key( 2 ), Key( 100 ),
              Key( signBit - 1 ), signBit, Key( signBit + 1 ),
              Key( std::numeric_limits< Key >::max() - 1 ), std::numeric_limits< Key >::max() };
    }
    return v;
}

// Deterministic generator built on the house sanitizer-clean multiply (hashutil::multiplyModulo64) —
// libc++'s mt19937 trips G1's unsigned-shift-base check inside its own header, so it cannot run under
// this gate's -fno-sanitize-recover=all. XOR (never wraps) replaces the usual LCG add; murmur-style
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
static Key drawKey( DeterministicRng& gen )
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

template< typename Key, int B >
static void rankParity( const char* keyName )
{
    using rank = stree::dyn::node_rank< Key, B >;
    const Key sentinelValue = stree::dyn::sentinel< Key >::value();
    const std::vector< Key > seeds = interestingValues< Key >();

    // patterns: each is a full B-slot fill
    std::vector< std::vector< Key > > patterns;

    // 1) sorted spread of the seam values, cycled to fill B
    {
        std::vector< Key > p( B );
        for( int i = 0; i < B; ++i )
        {
            p[ std::size_t( i ) ] = seeds[ std::size_t( i ) % seeds.size() ];
        }
        std::sort( p.begin(), p.end() );
        patterns.push_back( p );
    }

    // 2) all-equal nodes (three representative fills)
    for( std::size_t s = 0; s < seeds.size(); s += seeds.size() / 3 + 1 )
    {
        patterns.push_back( std::vector< Key >( B, seeds[ s ] ) );
    }

    // 3) all-sentinel (an empty node)
    patterns.push_back( std::vector< Key >( B, sentinelValue ) );

    // 4) the realistic shape: sorted prefix of h live keys, sentinel-padded tail
    DeterministicRng gen{ 0xC0FFEEull };
    for( int liveCount : { 0, 1, B / 2, B - 1, B } )
    {
        std::vector< Key > p( B, sentinelValue );
        for( int i = 0; i < liveCount; ++i )
        {
            p[ std::size_t( i ) ] = drawKey< Key >( gen );
        }
        std::sort( p.begin(), p.begin() + liveCount );
        patterns.push_back( p );
    }

    // 5) fully random, sorted and unsorted (the contract is a count — order must not matter)
    {
        std::vector< Key > p( B );
        for( int i = 0; i < B; ++i )
        {
            p[ std::size_t( i ) ] = drawKey< Key >( gen );
        }
        patterns.push_back( p );
        std::sort( p.begin(), p.end() );
        patterns.push_back( p );
    }

    // queries: every seam value, the sentinel, and every key present in the pattern under test
    alignas( 16 ) Key keys[ B ];
    unsigned caseCount    = 0;
    unsigned mismatchCount = 0;

    for( std::size_t patternIndex = 0; patternIndex < patterns.size(); ++patternIndex )
    {
        std::memcpy( keys, patterns[ patternIndex ].data(), sizeof( keys ) );

        std::vector< Key > queries = seeds;
        queries.push_back( sentinelValue );
        queries.insert( queries.end(), patterns[ patternIndex ].begin(), patterns[ patternIndex ].end() );

        for( std::size_t queryIndex = 0; queryIndex < queries.size(); ++queryIndex )
        {
            const Key x = queries[ queryIndex ];
            const unsigned gotLt  = rank::lt( keys, x );
            const unsigned gotLe  = rank::le( keys, x );
            const unsigned wantLt = refLt( keys, B, x );
            const unsigned wantLe = refLe( keys, B, x );
            caseCount += 2;

            if( gotLt != wantLt || gotLe != wantLe )
            {
                if( mismatchCount == 0 )
                {
                    std::printf( "        first mismatch: %s B=%d pattern=%zu query=%zu x=%.17g lt got=%u want=%u le got=%u want=%u\n",
                                 keyName, B, patternIndex, queryIndex, double( x ), gotLt, wantLt, gotLe, wantLe );
                }
                ++mismatchCount;
            }
        }
    }

    checkf( mismatchCount == 0, "node_rank<%s,B=%d> lt/le parity (%u cases, %u mismatches)", keyName, B, caseCount, mismatchCount );
}

// ============================================================================
// Arm B — FixedStr equality / hash / construction invariants
// ============================================================================

// Bytewise reference: length plus every data byte, no fold tricks shared with the implementation.
static bool refEq( const rw::FixedStr& a, const rw::FixedStr& b )
{
    return a.len == b.len && std::memcmp( a.data, b.data, std::size_t( rw::FixedStr::CAP ) ) == 0;
}

static void fixedStrParity()
{
    std::vector< std::string > sources;

    // empty, short, exactly-CAP, and over-CAP (truncating) inputs
    sources.push_back( "" );
    sources.push_back( "a" );
    sources.push_back( "abc" );
    sources.push_back( std::string( "abc" ) + '\0' );                       // len 4, same visible prefix — only the len byte + one pad slot move
    const std::string base31 = "abcdefghijklmnopqrstuvwxyz01234";           // exactly CAP chars
    sources.push_back( base31 );

    // every single-byte difference position across the full 31-byte payload
    for( std::size_t bytePosition = 0; bytePosition < base31.size(); ++bytePosition )
    {
        std::string mutated = base31;
        mutated[ bytePosition ] = char( mutated[ bytePosition ] ^ 0x40 );
        sources.push_back( mutated );
    }

    // truncation seam: differ only at [31] → equal after truncation; differ at [30] → unequal
    sources.push_back( base31 + "X" );
    sources.push_back( base31 + "Y" );
    {
        std::string differAt30 = base31 + "X";
        differAt30[ 30 ] = '!';
        sources.push_back( differAt30 );
    }

    // construction invariants: zero-padded tail, truncating length clamp, fits() honesty
    bool padClean   = true;
    bool lenClean   = true;
    for( const std::string& s : sources )
    {
        const rw::FixedStr f{ std::string_view( s ) };
        const std::size_t expectLen = s.size() < std::size_t( rw::FixedStr::CAP ) ? s.size() : std::size_t( rw::FixedStr::CAP );
        lenClean = lenClean && ( std::size_t( f.len ) == expectLen );
        for( std::size_t padIndex = std::size_t( f.len ); padIndex < std::size_t( rw::FixedStr::CAP ); ++padIndex )
        {
            padClean = padClean && ( f.data[ padIndex ] == 0 );
        }
    }
    checkf( lenClean, "FixedStr: len equals min(size, CAP) for all %zu sources", sources.size() );
    checkf( padClean, "FixedStr: tail bytes past len are zero for all sources (load-bearing for the fixed-width ops)" );
    checkf( rw::FixedStr::fits( base31 ) && !rw::FixedStr::fits( base31 + "X" ), "FixedStr: fits() flips exactly past CAP" );

    // equality parity + hash consistency over the full cross product
    unsigned pairCount    = 0;
    unsigned eqMismatches = 0;
    unsigned hashBreaks   = 0;
    for( const std::string& sa : sources )
    {
        for( const std::string& sb : sources )
        {
            const rw::FixedStr a{ std::string_view( sa ) };
            const rw::FixedStr b{ std::string_view( sb ) };
            const bool want = refEq( a, b );
            const bool got  = ( a == b );
            ++pairCount;
            if( got != want )
            {
                if( eqMismatches == 0 )
                {
                    std::printf( "        first eq mismatch: \"%.40s\" vs \"%.40s\" got=%d want=%d\n", sa.c_str(), sb.c_str(), got, want );
                }
                ++eqMismatches;
            }
            if( want && a.hash() != b.hash() )
            {
                ++hashBreaks;
            }
            if( got == ( a != b ) )
            {
                ++eqMismatches;   // operator!= must be the exact complement
            }
        }
    }
    checkf( eqMismatches == 0, "FixedStr: operator== matches bytewise reference (%u pairs, %u mismatches)", pairCount, eqMismatches );
    checkf( hashBreaks == 0, "FixedStr: a==b implies hash(a)==hash(b) (%u equal pairs broken)", hashBreaks );

    // the truncation seam, asserted explicitly so the semantics stay documented-by-test
    const rw::FixedStr truncX{ std::string_view( base31 + "X" ) };
    const rw::FixedStr truncY{ std::string_view( base31 + "Y" ) };
    checkf( truncX == truncY, "FixedStr: inputs differing only past CAP truncate to equal values" );
    checkf( rw::FixedStr{} == rw::FixedStr{ std::string_view( "" ) }, "FixedStr: default-constructed equals empty-string-constructed" );
}

// ============================================================================
// main — banner (non-vacuity evidence for the gate script) + both arms
// ============================================================================

int main()
{
#if defined( DYNMAP_HAS_SSE2 ) && DYNMAP_HAS_SSE2
    const char* rankKernel = "SSE";
#elif DYNMAP_HAS_NEON
    const char* rankKernel = "NEON";
#else
    const char* rankKernel = "scalar";
#endif
#if defined( __ARM_NEON )
    const char* fixedStrKernel = "NEON";
#elif defined( __SSE2__ )
    const char* fixedStrKernel = "SSE";
#else
    const char* fixedStrKernel = "scalar";
#endif
    std::printf( "dynmapsimd: rank kernel: %s   fixedstr eq: %s\n", rankKernel, fixedStrKernel );

    // 32-bit lanes (4 per 128-bit vector): B must be a multiple of 4
    rankParity< std::int32_t,  4  >( "i32" );
    rankParity< std::int32_t,  8  >( "i32" );
    rankParity< std::int32_t,  32 >( "i32" );
    rankParity< std::uint32_t, 4  >( "u32" );
    rankParity< std::uint32_t, 8  >( "u32" );
    rankParity< std::uint32_t, 32 >( "u32" );
    rankParity< float,         4  >( "f32" );
    rankParity< float,         8  >( "f32" );
    rankParity< float,         32 >( "f32" );

    // 64-bit lanes (2 per vector): B must be even — 6 catches a non-power-of-two stride
    rankParity< std::int64_t,  4  >( "i64" );
    rankParity< std::int64_t,  6  >( "i64" );
    rankParity< std::int64_t,  32 >( "i64" );
    rankParity< std::uint64_t, 4  >( "u64" );
    rankParity< std::uint64_t, 6  >( "u64" );
    rankParity< std::uint64_t, 32 >( "u64" );   // the production instantiation's shape (quality.h ScratchMap)
    rankParity< double,        4  >( "f64" );
    rankParity< double,        6  >( "f64" );
    rankParity< double,        32 >( "f64" );

    fixedStrParity();

    return g_fail;
}
