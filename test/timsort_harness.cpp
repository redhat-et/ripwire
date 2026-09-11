// timsort_harness.cpp — the differential + allocation harness behind test/timsortcheck.sh.
//
// The vendored timsort is a TOOL WITH NO CALL SITE (see src/infra/fastSort.h's header comment for the
// measured reason). Nothing in a normal build exercises it, so nothing in a normal build can notice when
// it stops working — or, far more quietly, when it stops being ALLOCATION-FREE. This harness is the only
// thing that runs it, and the allocation modes are the reason it exists.
//
// WHY GLOBAL operator new AND NOT A COUNTING ALLOCATOR. The property under test is "the caller-owned
// workspace keeps the whole sort out of the allocator". A counting allocator threaded through the value
// type would measure the value type; a counting allocator threaded through the workspace's vectors would
// change the very code path being measured. Replacing the global pair measures the PROCESS, which is the
// claim. The counters are gated on a flag that is off until the measured region begins, so the setup —
// the input vectors, the reserve, stdio's first-use buffer — is outside the window by construction.
//
// Single-threaded on purpose: plain counters, no atomics, and therefore no memory-ordering question to
// get wrong. src/alloccount.cpp is the multi-threaded instrument for the whole binary; this is not that.
//
// Modes (argv[1]):
//   correct <seed>   differential vs std::stable_sort over 8 shapes x 15 sizes, records tagged with their
//                    original index so STABILITY is checked and not just ordering. Both facade entry
//                    points (owning and workspace) must agree with the oracle and with each other.
//   alloc            the property: reserve_for() once, then 200 sorts through the WORKSPACE entry point.
//                    Prints the allocation count inside the measured window. Must be 0.
//   allocnaive       the same 200 sorts through the OWNING entry point. Must be > 0 — this is what makes
//                    the counter in `alloc` falsifiable rather than a counter that is simply dead.
//
// Output is one machine-readable RESULT line per mode; the gate parses it and never eyeballs prose.

#include "harnesscommon.h"
#include "infra/fastSort.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>
#include <vector>

namespace
{

// ── the instrument ───────────────────────────────────────────────────────────────────────────────────
bool        g_counting = false;
std::size_t g_allocs   = 0;
std::size_t g_bytes    = 0;

void countAlloc( std::size_t bytes ) noexcept
{
    if( g_counting )
    {
        ++g_allocs;
        g_bytes += bytes;
    }
}

}   // namespace

void* operator new( std::size_t bytes )
{
    countAlloc( bytes );
    void* p = std::malloc( bytes != 0 ? bytes : 1 );
    if( p == nullptr )
    {
        throw std::bad_alloc();
    }
    return p;
}

void* operator new[]( std::size_t bytes )
{
    return ::operator new( bytes );
}

void operator delete( void* p ) noexcept { std::free( p ); }
void operator delete[]( void* p ) noexcept { std::free( p ); }
void operator delete( void* p, std::size_t ) noexcept { std::free( p ); }
void operator delete[]( void* p, std::size_t ) noexcept { std::free( p ); }

namespace
{

// A record wide enough that the merge path moves a payload rather than a bare word, and tagged with its
// arrival index so a stability violation is VISIBLE: two records with equal keys must come out in
// arrival order, and comparing whole records against the oracle is what checks that.
struct Rec
{
    std::uint32_t key;
    std::uint32_t tag;
    std::uint32_t pad[ 2 ];

    bool operator==( const Rec& other ) const { return key == other.key && tag == other.tag; }
};

struct ByKey
{
    bool operator()( const Rec& lhs, const Rec& rhs ) const { return lhs.key < rhs.key; }
};

// The generator is test/harnesscommon.h's DeterministicRng, shared with the SIMD parity harnesses, and
// not a private one: libc++'s mt19937 trips G1's unsigned-shift-base check inside its own header, so a
// harness that rolls its own engine tends to roll that bug too. Fixed seed ⇒ reports reproduce anywhere.

enum Shape : int { kRandom, kSorted, kReverse, kSawtooth, kFewUnique, kAllEqual, kNearlySorted, kOrganPipe, kShapeCount };

// A table rather than a switch: the names index the enum directly, so a new shape cannot be added without
// a name, and there is no second copy of the enum's order to drift.
const char* const kShapeNames[ kShapeCount ] =
    { "random", "sorted", "reverse", "sawtooth", "fewunique", "allequal", "nearlysorted", "organpipe" };

const char* shapeName( int shape )
{
    return ( shape >= 0 && shape < kShapeCount ) ? kShapeNames[ shape ] : "?";
}

// The shapes span the covariate the measurement says decides everything — adjacent descents per element —
// from 0 (sorted, allequal) to ~1 (reverse), with the run-detecting middle (sawtooth, nearlysorted) where
// timsort's run stack actually does work and therefore actually merges.
std::vector<Rec> makeInput( int shape, std::size_t count, DeterministicRng& gen )
{
    std::vector<Rec> out( count );
    for( std::size_t i = 0; i < count; ++i )
    {
        std::uint32_t key = 0;
        switch( shape )
        {
            case kRandom:       key = std::uint32_t( gen.next() ); break;
            case kSorted:       key = std::uint32_t( i * 3 ); break;
            case kReverse:      key = std::uint32_t( ( count - i ) * 3 ); break;
            case kSawtooth:     key = std::uint32_t( i % 64 ); break;
            case kFewUnique:    key = std::uint32_t( gen.next() % 8 ); break;
            case kAllEqual:     key = 7; break;
            case kNearlySorted: key = std::uint32_t( i * 3 ); break;
            case kOrganPipe:    key = std::uint32_t( i < count / 2 ? i : count - i ); break;
            default:            key = 0; break;
        }
        out[ i ] = Rec { key, std::uint32_t( i ), { 0, 0 } };
    }
    if( shape == kNearlySorted && count > 8 )
    {
        // 1% displaced — the shape a real "append in id order, then patch a few" site produces.
        const std::size_t swaps = count / 100 + 1;
        for( std::size_t s = 0; s < swaps; ++s )
        {
            const std::size_t a = std::size_t( gen.next() % count );
            const std::size_t b = std::size_t( gen.next() % count );
            std::swap( out[ a ].key, out[ b ].key );
        }
    }
    return out;
}

const std::size_t kSizes[]  = { 0, 1, 2, 3, 7, 31, 32, 33, 63, 64, 65, 127, 1000, 4096, 10000 };
const std::size_t kSizeCount = sizeof( kSizes ) / sizeof( kSizes[ 0 ] );

// ── mode: correct ────────────────────────────────────────────────────────────────────────────────────
int runCorrect( std::uint64_t seed )
{
    DeterministicRng gen { seed };
    std::size_t      cases       = 0;
    std::size_t      mismatches  = 0;
    std::size_t      unstableHit = 0;

    for( int shape = 0; shape < kShapeCount; ++shape )
    {
        for( std::size_t s = 0; s < kSizeCount; ++s )
        {
            const std::vector<Rec> input = makeInput( shape, kSizes[ s ], gen );

            std::vector<Rec> oracle = input;
            std::stable_sort( oracle.begin(), oracle.end(), ByKey {} );

            std::vector<Rec> owning = input;
            infra::sort::stable( owning.begin(), owning.end(), ByKey {} );

            std::vector<Rec>                                         workspaced = input;
            infra::sort::stableWorkspace<std::vector<Rec>::iterator> ws;
            ws.reserve_for( input.size() );
            infra::sort::stable( workspaced.begin(), workspaced.end(), ws, ByKey {} );

            // Determinism: the same workspace, reused, must produce the same answer as its first use.
            std::vector<Rec> reused = input;
            infra::sort::stable( reused.begin(), reused.end(), ws, ByKey {} );

            ++cases;
            if( owning != oracle || workspaced != oracle || reused != oracle )
            {
                ++mismatches;
                std::printf( "  MISMATCH shape=%s n=%zu owning=%d workspaced=%d reused=%d\n",
                             shapeName( shape ), kSizes[ s ],
                             int( owning == oracle ), int( workspaced == oracle ), int( reused == oracle ) );
                // A key-only comparison that PASSES while the record comparison fails is a stability
                // failure specifically, and worth naming rather than lumping into "wrong".
                const bool keysOk = std::equal( owning.begin(), owning.end(), oracle.begin(), oracle.end(),
                                                []( const Rec& a, const Rec& b ) { return a.key == b.key; } );
                if( keysOk )
                {
                    ++unstableHit;
                }
            }
        }
    }

    std::printf( "RESULT mode=correct seed=%llu cases=%zu mismatches=%zu stability_only=%zu\n",
                 static_cast<unsigned long long>( seed ), cases, mismatches, unstableHit );
    return mismatches == 0 ? 0 : 1;
}

// ── modes: alloc / allocnaive ────────────────────────────────────────────────────────────────────────
//
// Both modes do exactly the same work on exactly the same data and differ in ONE thing: which facade
// overload they call. That is the contrast — without `allocnaive` the zero in `alloc` could equally mean
// "the workspace works" or "the counter is dead", and the gate could not tell those apart.
int runAlloc( bool useWorkspace )
{
    const std::size_t kCount = 4096;
    const int         kSorts = 200;

    // Scattered input, so the run stack is exercised and the merge path actually copies into tmp_. On a
    // fully ascending input timsort never merges and never allocates, and a zero measured THERE would be
    // a property of the data, not of the workspace.
    DeterministicRng       gen { 12345 };
    const std::vector<Rec> input = makeInput( kRandom, kCount, gen );

    std::vector<Rec>                                        scratch( kCount );
    infra::sort::stableWorkspace<std::vector<Rec>::iterator> ws;
    ws.reserve_for( kCount );

    // stdio allocates its buffer on first use; do that before the window opens.
    std::printf( "  priming stdio (workspace=%d, tmp cap=%zu, pending cap=%zu)\n",
                 int( useWorkspace ), ws.temp_capacity(), ws.pending_capacity() );
    std::fflush( stdout );

    g_allocs   = 0;
    g_bytes    = 0;
    g_counting = true;
    for( int i = 0; i < kSorts; ++i )
    {
        std::memcpy( scratch.data(), input.data(), kCount * sizeof( Rec ) );
        if( useWorkspace )
        {
            infra::sort::stable( scratch.begin(), scratch.end(), ws, ByKey {} );
        }
        else
        {
            infra::sort::stable( scratch.begin(), scratch.end(), ByKey {} );
        }
    }
    g_counting = false;

    const std::size_t allocs = g_allocs;
    const std::size_t bytes  = g_bytes;

    // Guard against a sort that did nothing: an unsorted result would make any allocation count
    // meaningless, and a compiler that elided the whole loop would report a perfect zero.
    const bool sorted = std::is_sorted( scratch.begin(), scratch.end(), ByKey {} );

    std::printf( "RESULT mode=%s sorts=%d n=%zu allocs=%zu bytes=%zu sorted=%d\n",
                 useWorkspace ? "alloc" : "allocnaive", kSorts, kCount, allocs, bytes, int( sorted ) );
    return sorted ? 0 : 1;
}

}   // namespace

int main( int argc, char** argv )
{
    if( argc < 2 )
    {
        std::fprintf( stderr, "usage: timsort_harness correct <seed> | alloc | allocnaive\n" );
        return 2;
    }
    if( std::strcmp( argv[ 1 ], "correct" ) == 0 )
    {
        return runCorrect( argc > 2 ? std::strtoull( argv[ 2 ], nullptr, 10 ) : 1 );
    }
    if( std::strcmp( argv[ 1 ], "alloc" ) == 0 )
    {
        return runAlloc( true );
    }
    if( std::strcmp( argv[ 1 ], "allocnaive" ) == 0 )
    {
        return runAlloc( false );
    }
    std::fprintf( stderr, "unknown mode: %s\n", argv[ 1 ] );
    return 2;
}
