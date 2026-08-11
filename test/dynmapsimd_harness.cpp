// dynmapsimd_harness.cpp — SIMD-vs-scalar parity gate for the vectorized kernels ripwire vendors.
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
//   C  sparseCsr<T> kernels (src/infra/sparseCsr.h) — blockReduceDot / scaleVec / spmvRow / applyInto
//      vs independent scalar oracles. Two float regimes per kernel: an EXACT arm (values drawn from
//      {1,2,4}, every partial sum an integer < 2^24 — any lane/tail bug shows as a bit-exact mismatch,
//      no tolerance to hide behind) and a RANDOM arm (double-accumulated oracle, relative tolerance
//      band — the house float-test style, since SIMD reassociation legitimately changes rounding).
//      Plus dominantEigenvector on a known eigenpair, and same-input-same-bits determinism.
//
// NON-VACUITY: the banner names the compiled kernels ("rank kernel: NEON|SSE|scalar", "fixedstr eq: ...",
// "csr kernels: ..."). On arm64/x86_64 the gate script REQUIRES the vector kernels to have engaged — a
// scalar-only build there would compare the contract to itself and pass vacuously, which is exactly the
// green-but-blind shape the gate exists to prevent.
//
// Exit 0 = all pass; nonzero = failure (per-arm PASS/FAIL lines on stdout, first mismatch detailed).

#include "infra/dynamic_map.hpp"
#include "infra/sparseCsr.h"

#include "../src/infra/fixedStr.h"
#include "harnesscommon.h"      // checkf / g_fail / DeterministicRng / drawKey — shared with radixsimd_harness.cpp

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <string>
#include <string_view>
#include <type_traits>
#include <vector>

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
// Arm C — sparseCsr kernel parity (blockReduceDot / scaleVec / spmvRow / applyInto)
// ============================================================================

// Sequential double-accumulated dot — the independent oracle for every float sum below.
static double refDot( const float* a, const float* b, std::size_t n )
{
    double acc = 0.0;
    for( std::size_t i = 0; i < n; ++i )
    {
        acc += double( a[ i ] ) * double( b[ i ] );
    }
    return acc;
}

// EXACT regime: values from {1,2,4} — products <= 16, partial sums integers < 2^24, so every
// association order yields the identical float. A lane or tail bug cannot hide in rounding.
static float drawExact( DeterministicRng& gen )
{
    const float pool[ 3 ] = { 1.0f, 2.0f, 4.0f };
    return pool[ gen.next() % 3u ];
}

// RANDOM regime: floats in roughly [-1,1) — reassociation changes rounding, so parity is a
// relative tolerance band against the double oracle (house float-test style).
static float drawUnit( DeterministicRng& gen )
{
    return float( double( std::int64_t( gen.next() ) ) / 9.3e18 );
}

static bool withinRel( double got, double want, double relTol )
{
    const double mag = ( want < 0.0 ? -want : want );
    const double err = ( got - want < 0.0 ? want - got : got - want );
    return err <= relTol * ( mag > 1.0 ? mag : 1.0 );
}

static void csrReduceParity()
{
    const std::size_t sizes[] = { 0, 1, 3, 4, 5, 7, 8, 31, 1023, 1024, 1025, 2051 };   // straddle the 1024 block seam + every tail shape

    DeterministicRng gen{ 0xC5EED5ull };
    bool exactClean = true, randomClean = true, selfClean = true, deterministic = true, scaleClean = true;

    for( std::size_t n : sizes )
    {
        std::vector< float > a( n ), b( n );

        for( std::size_t i = 0; i < n; ++i ) { a[ i ] = drawExact( gen ); b[ i ] = drawExact( gen ); }
        const float gotExact = csrdetail::blockReduceDot( a.data(), b.data(), n );
        exactClean = exactClean && ( double( gotExact ) == refDot( a.data(), b.data(), n ) );

        for( std::size_t i = 0; i < n; ++i ) { a[ i ] = drawUnit( gen ); b[ i ] = drawUnit( gen ); }
        const float gotRandom = csrdetail::blockReduceDot( a.data(), b.data(), n );
        randomClean   = randomClean && withinRel( double( gotRandom ), refDot( a.data(), b.data(), n ), 1e-4 );
        selfClean     = selfClean && withinRel( double( csrdetail::blockReduceDot( a.data(), a.data(), n ) ), refDot( a.data(), a.data(), n ), 1e-4 );
        deterministic = deterministic && ( gotRandom == csrdetail::blockReduceDot( a.data(), b.data(), n ) );

        // scaleVec: one float multiply per element in both the vector and scalar paths — bit-exact parity required.
        for( float s : { 0.37f, -2.5f } )
        {
            std::vector< float > x = a;
            csrdetail::scaleVec( x.data(), s, n );
            for( std::size_t i = 0; i < n; ++i ) { scaleClean = scaleClean && ( x[ i ] == a[ i ] * s ); }
        }
    }

    checkf( exactClean,   "csr blockReduceDot: bit-exact on integer-exact values across the 1024 block seam" );
    checkf( randomClean,  "csr blockReduceDot: within 1e-4 rel of double oracle on random values" );
    checkf( selfClean,    "csr blockReduceDot: a==b (norm) aliasing arm within band" );
    checkf( deterministic,"csr blockReduceDot: same input, same bits" );
    checkf( scaleClean,   "csr scaleVec: bit-exact vs scalar multiply (all tail shapes)" );
}

static void csrSpmvParity()
{
    constexpr std::size_t kCols = 97;
    const std::size_t rowLens[] = { 0, 1, 3, 4, 5, 8, 9, 16, 23, 40 };   // straddle the 4-wide (spmvRow) and 8-wide (applyInto) unroll seams
    constexpr std::size_t kRows = sizeof( rowLens ) / sizeof( rowLens[ 0 ] );

    DeterministicRng gen{ 0x5EAF00Dull };

    for( int regime = 0; regime < 2; ++regime )   // 0 = exact, 1 = random
    {
        std::size_t nnz = 0;
        for( std::size_t r = 0; r < kRows; ++r ) { nnz += rowLens[ r ]; }

        sparseCsr< float > A( kRows, kCols, nnz );
        std::vector< float > x( kCols );
        for( std::size_t c = 0; c < kCols; ++c ) { x[ c ] = regime == 0 ? drawExact( gen ) : drawUnit( gen ); }

        std::size_t k = 0;
        for( std::size_t r = 0; r < kRows; ++r )
        {
            A.rowOffsets()[ r ] = std::uint32_t( k );
            for( std::size_t j = 0; j < rowLens[ r ]; ++j, ++k )
            {
                A.colIndices()[ k ] = std::uint32_t( gen.next() % kCols );
                A.values()[ k ]     = regime == 0 ? drawExact( gen ) : drawUnit( gen );
            }
        }
        A.rowOffsets()[ kRows ] = std::uint32_t( nnz );

        // spmvRow, called directly per row (the applyInto float path bypasses it by design)
        bool rowClean = true;
        for( std::size_t r = 0; r < kRows; ++r )
        {
            const std::uint32_t b0 = A.rowOffsets()[ r ], e0 = A.rowOffsets()[ r + 1 ];
            const float got = csrdetail::spmvRow( A.values() + b0, A.colIndices() + b0, x.data(), std::size_t( e0 - b0 ) );
            double want = 0.0;
            for( std::uint32_t j = b0; j < e0; ++j ) { want += double( A.values()[ j ] ) * double( x[ A.colIndices()[ j ] ] ); }
            rowClean = rowClean && ( regime == 0 ? double( got ) == want : withinRel( double( got ), want, 1e-4 ) );
        }
        checkf( rowClean, "csr spmvRow: %s parity across unroll seams", regime == 0 ? "bit-exact" : "tolerance" );

        // applyInto (the shipped SpMV — 8-accumulator float path incl. the prefetch bounds guard)
        std::vector< float > y( kRows, -1.0f );
        A.applyInto( x.data(), y.data() );
        bool applyClean = true;
        for( std::size_t r = 0; r < kRows; ++r )
        {
            double want = 0.0;
            for( std::uint32_t j = A.rowOffsets()[ r ]; j < A.rowOffsets()[ r + 1 ]; ++j ) { want += double( A.values()[ j ] ) * double( x[ A.colIndices()[ j ] ] ); }
            applyClean = applyClean && ( regime == 0 ? double( y[ r ] ) == want : withinRel( double( y[ r ] ), want, 1e-4 ) );
        }
        checkf( applyClean, "csr applyInto<float>: %s parity (0..40-long rows)", regime == 0 ? "bit-exact" : "tolerance" );
    }

    // the non-float template path (spmvRow scalar branch) — double, tolerance vs double oracle
    {
        sparseCsr< double > A( 2, 2, 4 );
        const std::uint32_t off[ 3 ] = { 0, 2, 4 };
        const std::uint32_t col[ 4 ] = { 0, 1, 0, 1 };
        const double        val[ 4 ] = { 2.0, 1.0, 1.0, 2.0 };
        std::memcpy( A.rowOffsets(), off, sizeof( off ) );
        std::memcpy( A.colIndices(), col, sizeof( col ) );
        std::memcpy( A.values(),     val, sizeof( val ) );
        const double x[ 2 ] = { 0.25, -3.0 };
        double y[ 2 ] = { 0.0, 0.0 };
        A.applyInto( x, y );
        checkf( y[ 0 ] == 2.0 * 0.25 + 1.0 * -3.0 && y[ 1 ] == 1.0 * 0.25 + 2.0 * -3.0, "csr applyInto<double>: scalar template path exact on a 2x2" );
    }
}

static void csrEigenParity()
{
    // [[2,1],[1,2]] — dominant eigenpair lambda=3, v=(1,1)/sqrt(2). Exercises the full
    // blockReduceDot + scaleVec + applyInto composition the PageRank kernel leans on.
    sparseCsr< float > A( 2, 2, 4 );
    const std::uint32_t off[ 3 ] = { 0, 2, 4 };
    const std::uint32_t col[ 4 ] = { 0, 1, 0, 1 };
    const float         val[ 4 ] = { 2.0f, 1.0f, 1.0f, 2.0f };
    std::memcpy( A.rowOffsets(), off, sizeof( off ) );
    std::memcpy( A.colIndices(), col, sizeof( col ) );
    std::memcpy( A.values(),     val, sizeof( val ) );

    float x[ 2 ] = { 1.0f, 0.0f };
    const float lambda = dominantEigenvector( A, x, 1e-6f, 1000 );

    const double invSqrt2 = 0.70710678118654752;
    checkf( withinRel( double( lambda ), 3.0, 1e-4 ), "csr dominantEigenvector: lambda within band of 3 (got %.8f)", double( lambda ) );
    checkf( withinRel( double( x[ 0 ] ), invSqrt2, 1e-3 ) && withinRel( double( x[ 1 ] ), invSqrt2, 1e-3 ),
            "csr dominantEigenvector: eigenvector within band of (1,1)/sqrt(2)" );
}

// ============================================================================
// main — banner (non-vacuity evidence for the gate script) + all arms
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
#if defined( SPARSECSR_NEON ) && SPARSECSR_NEON
    const char* csrKernel = "NEON";
#elif defined( SPARSECSR_SSE2 ) && SPARSECSR_SSE2
    const char* csrKernel = "SSE";
#else
    const char* csrKernel = "scalar";
#endif
    std::printf( "dynmapsimd: rank kernel: %s   fixedstr eq: %s   csr kernels: %s\n", rankKernel, fixedStrKernel, csrKernel );

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

    csrReduceParity();
    csrSpmvParity();
    csrEigenParity();

    return g_fail;
}
