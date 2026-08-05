// radixsimd_harness.cpp — SIMD-vs-scalar parity gate for the radix byte-histogram fast paths.
//
//   radix::detail::buildHistogramsContiguousKeys<Key,kPasses> (src/infra/radixSort.inl) — "hist[pass][bin]
//   = how many keys' sortable-word byte `pass` equals bin" over contiguous uint32/uint64/float keys.
//   NEON on arm64, SSE2 on x86_64, the scalar loop elsewhere. The oracle here restates that contract
//   bytewise from an independently-restated sortable-word map (the IEEE monotone flip for float uses a
//   DIFFERENT formulation — ~raw / raw+bias instead of the implementation's xor-mask — so a shared flip
//   bug cannot cancel out), and the oracle itself is validated against the ordering contract it encodes
//   (strict monotonicity over sorted finite floats, ±0.0 collapse) before it is trusted as a reference.
//
//   Sweeps the seams where a vector histogram goes wrong: remainder tails for both the 4-lane (u32/f32)
//   and 2-lane (u64) strides, unaligned base pointers (a wrongly-aligned vector load faults or reads the
//   wrong lanes), byte-boundary values in every lane position, all-equal fills, sign boundaries, ±0.0,
//   denormals, and a fixed-seed random sweep. Ends with full sortKeyLarge runs checked against
//   std::stable_sort — the histogram feeding a scatter that still sorts correctly and STABLY.
//
// NON-VACUITY: the banner names the compiled kernel ("radix histogram kernel: NEON|SSE|scalar"). On
// arm64/x86_64 the gate script REQUIRES the vector kernel to have engaged — a scalar-only build there
// compares the scalar loop to itself and passes vacuously, which is exactly the green-but-blind shape
// the gate exists to prevent.
//
// Exit 0 = all pass; nonzero = failure (per-arm PASS/FAIL lines on stdout, first mismatch detailed).

#include "radixSort.h"

#include "harnesscommon.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <numeric>
#include <type_traits>
#include <vector>

// ============================================================================
// The independent oracle
// ============================================================================

// Independent restatement of the documented order-preserving float→u32 map (radixSort.inl sortWordOf):
// collapse ±0.0, then negatives reverse (bitwise NOT) and positives shift above them (add the sign bias).
// Deliberately NOT the implementation's sign?0xFFFFFFFF:0x80000000 xor-mask formulation.
static std::uint32_t refFloatWord( float value )
{
    std::uint32_t raw;
    std::memcpy( &raw, &value, sizeof( raw ) );
    if( ( raw & 0x7FFFFFFFu ) == 0u )
    {
        raw = 0u;                                   // +0.0 and -0.0 sort identically
    }
    if( ( raw >> 31 ) != 0u )
    {
        return ~raw;
    }
    return raw + 0x80000000u;                       // raw < 2^31 here, so this never wraps
}

// The contract, restated bytewise: hist[pass][bin] counts keys whose sortable-word byte `pass` is bin.
template< typename Key, int kPasses >
static void refHistograms( const Key* keys, std::size_t count, radix::detail::Count ( &hist )[ kPasses ][ 256 ] )
{
    for( int pass = 0; pass < kPasses; ++pass )
    {
        for( int bin = 0; bin < 256; ++bin )
        {
            hist[ pass ][ bin ] = 0;
        }
    }
    for( std::size_t i = 0; i < count; ++i )
    {
        std::uint64_t word;
        if constexpr( std::is_same_v< Key, float > )
        {
            word = refFloatWord( keys[ i ] );
        }
        else
        {
            word = std::uint64_t( keys[ i ] );
        }
        for( int pass = 0; pass < kPasses; ++pass )
        {
            ++hist[ pass ][ ( word >> ( pass * 8 ) ) & 0xFFu ];
        }
    }
}

// ============================================================================
// Seam values per key type
// ============================================================================

template< typename Key >
static std::vector< Key > seamValues()
{
    if constexpr( std::is_same_v< Key, float > )
    {
        // finite only — the contract requires finite keys (VERIFY'd in sortWordOf)
        return { 0.0f, -0.0f, 1e-45f, -1e-45f,                                  // zeros collapse; denormals
                 std::numeric_limits< float >::min(), -std::numeric_limits< float >::min(),
                 1.5f, -1.5f, 255.0f, 256.0f, 3.25e8f, -3.25e8f,
                 std::numeric_limits< float >::max(), std::numeric_limits< float >::lowest() };
    }
    else if constexpr( std::is_same_v< Key, std::uint32_t > )
    {
        return { 0u, 1u, 0x7Fu, 0x80u, 0xFFu, 0x100u, 0xFF00u, 0x010203u,
                 0x7FFFFFFFu, 0x80000000u, 0x80000001u, 0xFFFFFF00u, 0xFFFFFFFFu };
    }
    else
    {
        static_assert( std::is_same_v< Key, std::uint64_t > );
        return { 0ull, 1ull, 0xFFull, 0x100ull, 0x0102030405060708ull,
                 0x7FFFFFFFFFFFFFFFull, 0x8000000000000000ull, 0xFF00FF00FF00FF00ull,
                 0xFFFFFFFF00000000ull, 0x00000000FFFFFFFFull, 0xFFFFFFFFFFFFFFFFull };
    }
}

// ============================================================================
// Arm A — histogram parity
// ============================================================================

// Locate and print the first differing (pass, bin) cell of a failed case.
template< int kPasses >
static void printFirstMismatch( const char* keyName, std::size_t patternIndex, std::size_t offset, std::size_t count,
                                const radix::detail::Count ( &got )[ kPasses ][ 256 ],
                                const radix::detail::Count ( &want )[ kPasses ][ 256 ] )
{
    for( int pass = 0; pass < kPasses; ++pass )
    {
        for( int bin = 0; bin < 256; ++bin )
        {
            if( got[ pass ][ bin ] != want[ pass ][ bin ] )
            {
                std::printf( "        first mismatch: %s pattern=%zu offset=%zu count=%zu pass=%d bin=%d got=%u want=%u\n",
                             keyName, patternIndex, offset, count, pass, bin, got[ pass ][ bin ], want[ pass ][ bin ] );
                return;
            }
        }
    }
}

template< typename Key >
static void histogramParity( const char* keyName )
{
    constexpr int kPasses = radix::detail::Passes< Key >;
    const std::vector< Key > seeds = seamValues< Key >();

    // remainder tails for both the 4-lane (u32/f32) and 2-lane (u64) strides, plus larger blocks
    const std::size_t counts[] = { 0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 33, 64, 127, 257, 1000, 1023 };
    const std::size_t maxCount = 1023;

    // patterns: each fills maxCount keys; every (count, offset) prefix of each is a test case
    std::vector< std::vector< Key > > patterns;

    // 1) cycled seam values — every byte-boundary value visits every lane position
    {
        std::vector< Key > p( maxCount + 1 );
        for( std::size_t i = 0; i < p.size(); ++i )
        {
            p[ i ] = seeds[ i % seeds.size() ];
        }
        patterns.push_back( p );
    }

    // 2) all-equal fills (three representative values — one histogram bin takes the whole count)
    for( std::size_t s = 0; s < seeds.size(); s += seeds.size() / 3 + 1 )
    {
        patterns.push_back( std::vector< Key >( maxCount + 1, seeds[ s ] ) );
    }

    // 3) fixed-seed random sweep
    {
        DeterministicRng gen{ 0xC0FFEEull };
        std::vector< Key > p( maxCount + 1 );
        for( std::size_t i = 0; i < p.size(); ++i )
        {
            p[ i ] = drawKey< Key >( gen );
        }
        patterns.push_back( p );
    }

    unsigned caseCount     = 0;
    unsigned mismatchCount = 0;

    for( std::size_t patternIndex = 0; patternIndex < patterns.size(); ++patternIndex )
    {
        // offset 1 shifts the base pointer off 16-byte alignment: an aligned-load kernel faults or
        // silently reads the wrong lanes here, so both alignments must agree with the oracle
        for( std::size_t offset = 0; offset <= 1; ++offset )
        {
            const Key* base = patterns[ patternIndex ].data() + offset;
            for( const std::size_t count : counts )
            {
                alignas( 64 ) radix::detail::Count got[ kPasses ][ 256 ];
                alignas( 64 ) radix::detail::Count want[ kPasses ][ 256 ];
                radix::detail::clearHistograms( got );
                radix::detail::buildHistogramsContiguousKeys( base, count, got );
                refHistograms( base, count, want );
                ++caseCount;

                if( std::memcmp( got, want, sizeof( got ) ) != 0 )
                {
                    if( mismatchCount == 0 )
                    {
                        printFirstMismatch( keyName, patternIndex, offset, count, got, want );
                    }
                    ++mismatchCount;
                }
            }
        }
    }

    checkf( mismatchCount == 0, "histogram parity <%s> (%u cases, %u mismatches)", keyName, caseCount, mismatchCount );
}

// ============================================================================
// Arm B — the float oracle is itself checked against the ordering contract
// ============================================================================

static void oracleMonotonicity()
{
    std::vector< float > values = seamValues< float >();
    DeterministicRng gen{ 0xBEEFull };
    for( int i = 0; i < 256; ++i )
    {
        values.push_back( drawKey< float >( gen ) );
    }
    std::sort( values.begin(), values.end() );

    bool ordered = true;
    for( std::size_t i = 1; i < values.size(); ++i )
    {
        const std::uint32_t prev = refFloatWord( values[ i - 1 ] );
        const std::uint32_t cur  = refFloatWord( values[ i ] );
        if( values[ i - 1 ] < values[ i ] )
        {
            ordered = ordered && ( prev < cur );
        }
        else
        {
            ordered = ordered && ( prev == cur );   // ties (incl. -0.0 vs +0.0) map to equal words
        }
    }
    checkf( ordered, "float oracle: word map is strictly monotone over %zu sorted finite values", values.size() );
    checkf( refFloatWord( 0.0f ) == refFloatWord( -0.0f ), "float oracle: +0.0 and -0.0 collapse to one word" );
}

// ============================================================================
// Arm C — end-to-end: the histogram feeds a scatter that still sorts, stably
// ============================================================================

template< typename Key >
static void sortEndToEnd( const char* keyName )
{
    const std::vector< Key > seeds = seamValues< Key >();
    DeterministicRng gen{ 0xD00Dull };

    std::vector< Key > keys( 1000 );
    for( std::size_t i = 0; i < keys.size(); ++i )
    {
        // seams sprinkled among random draws so equal keys exist → stability is actually exercised
        keys[ i ] = ( i % 5 == 0 ) ? seeds[ i % seeds.size() ] : drawKey< Key >( gen );
    }

    std::vector< std::uint32_t > indices( keys.size() );
    std::vector< std::uint32_t > scratch( keys.size() );
    radix::sortKeyLarge( keys.data(), indices.data(), scratch.data(), keys.size() );

    std::vector< std::uint32_t > expected( keys.size() );
    std::iota( expected.begin(), expected.end(), 0u );
    std::stable_sort( expected.begin(), expected.end(),
                      [ & ]( std::uint32_t a, std::uint32_t b ) { return keys[ a ] < keys[ b ]; } );

    checkf( indices == expected, "sortKeyLarge <%s> matches std::stable_sort order+stability (%zu keys)", keyName, keys.size() );
}

// ============================================================================
// main — banner (non-vacuity evidence for the gate script) + all arms
// ============================================================================

int main()
{
#if defined( RADIXSORT_SSE2 ) && RADIXSORT_SSE2
    const char* histKernel = "SSE";
#elif defined( RADIXSORT_NEON ) && RADIXSORT_NEON
    const char* histKernel = "NEON";
#else
    const char* histKernel = "scalar";
#endif
    std::printf( "radixsimd: radix histogram kernel: %s\n", histKernel );

    oracleMonotonicity();

    histogramParity< std::uint32_t >( "u32" );
    histogramParity< std::uint64_t >( "u64" );
    histogramParity< float >( "f32" );

    sortEndToEnd< std::uint32_t >( "u32" );
    sortEndToEnd< std::uint64_t >( "u64" );
    sortEndToEnd< float >( "f32" );

    return g_fail;
}
