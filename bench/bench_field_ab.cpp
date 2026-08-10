// bench_field_ab.cpp — the VALIDATION HALF of `--field-affinity`: take one static hypothesis the lens
// emits, build the two layouts it compares, and settle the question on real hardware.
//
// Build (the same standalone one-liner every bench in this directory uses — no CMake target, deliberately):
//   c++ -O2 -std=c++23 bench/bench_field_ab.cpp -Isrc -Isrc/infra -Ithird_party -o /tmp/ripwire_field_ab
//   /tmp/ripwire_field_ab            # timing only, unprivileged
//   sudo /tmp/ripwire_field_ab       # + hardware counters (kperf on Apple needs root; Linux needs
//                                    #   perf_event_paranoid <= 2, see src/infra/profilePmc.h)
//
// ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────────────
// The lens is a STATIC hypothesis generator, and its own header says the two things it cannot know: a
// static access count is not a dynamic frequency, and a modelled offset is not the ABI. A hypothesis a
// tool cannot be wrong about is not a hypothesis. So this harness closes the loop the way Chilimbi
// closed it in 1999 (UltraSPARC counters) and Hundt closed it in 2006 (Itanium PMU sampling attributed
// back to individual fields): run the SAME workload over the SAME data in the two layouts, alternating
// to cancel thermal drift, and read `prof::pmc` — ripwire's existing counter backend — around each.
//
// ── THE SHAPE UNDER TEST ─────────────────────────────────────────────────────────────────────────────
// SplitLayout is the exact geometry `--field-affinity` fires split-line on: two field groups that one
// function co-accesses, declared 64 bytes apart, so no field order as declared can put them on one
// line. PackedLayout is the same fields with the co-accessed ones adjacent. Nothing else differs — same
// element count, same arithmetic, same total bytes touched per element. Only the byte distance moves.
//
// ── WHAT AN HONEST RESULT LOOKS LIKE ─────────────────────────────────────────────────────────────────
// Two failure modes are reported, never hidden:
//   * counters unavailable (no root / no vPMU) prints counters=UNAVAILABLE and the timing still stands.
//     A measure that could not be evaluated is UNAVAILABLE, never "did not fire".
//   * a null result — the two layouts measure the same — is printed as a null result. The lens ranks by
//     a STATIC separation cost, so a top-ranked struct that is touched a handful of times per process
//     SHOULD show nothing here, and saying so is the point of running it.

#include "infra/profilePmc.h"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string_view>
#include <vector>

namespace
{

constexpr std::size_t kElems   = 1u << 18;   // 256 Ki elements x 256 B = 64 MB per arm: well past any LLC, and both arms fit in RAM
constexpr int         kSamples = 7;          // odd, so the median is a real sample

// ── the two arms ─────────────────────────────────────────────────────────────────────────────────────
// Both are 256 B. Both put the position quad and the velocity quad on IDENTICALLY ALIGNED 16-byte slots,
// so the compiler emits the same vector shape for each and the only variable left is the DISTANCE
// between them. (The first draft did not control for that: it put the packed arm's velocity at offset 12,
// which is 16-byte-misaligned, and the measurement was dominated by codegen instead of by cache traffic.
// Found by measuring, not by inspection.)
//
// Element size matters and is a named choice: an Apple-silicon L2 line is 128 B even though L1 is 64 B,
// so a 128 B element is ONE L2 line whatever the field order and the two arms become indistinguishable
// below L1. 256 B puts the split pair four 64 B lines — two 128 B L2 lines — apart, which is the regime
// the lens's block="64" assumption is actually about.
struct SplitLayout
{
    float         x, y, z, pad0;    // off 0..15    (64 B line 0)
    std::uint64_t cold[22];         // off 16..191
    float         vx, vy, vz, pad1; // off 192..207 (64 B line 3)
    std::uint64_t tail[6];          // off 208..255
};
static_assert( sizeof( SplitLayout ) == 256, "SplitLayout must be exactly four 64 B lines" );
static_assert( offsetof( SplitLayout, vx ) - offsetof( SplitLayout, x ) == 192, "the split-line hypothesis IS this distance" );

// The same fields with the co-accessed quads adjacent: dist(x, vx) = 16, wt = (64-16)/64 = 0.75.
struct PackedLayout
{
    float         x, y, z, pad0;    // off 0..15    (64 B line 0)
    float         vx, vy, vz, pad1; // off 16..31   (64 B line 0 — the whole point)
    std::uint64_t cold[22];         // off 32..207
    std::uint64_t tail[6];          // off 208..255
};
static_assert( sizeof( PackedLayout ) == 256, "PackedLayout must match SplitLayout byte for byte in SIZE" );
static_assert( offsetof( PackedLayout, vx ) - offsetof( PackedLayout, x ) == 16, "the packed arm must co-locate the pair" );

// The traversal stride, in ELEMENTS. Must be odd (kElems is a power of two, so any odd stride is coprime
// with it and the walk visits every element exactly once). It is a command-line argument because the
// answer DEPENDS ON IT and hiding that would be picking the flattering number: at a small stride the walk
// is the near-sequential AoS sweep a real hot loop performs and the line-count difference shows; at a
// stride large enough that every access is its own TLB/DRAM-page miss, that cost dwarfs the line count
// and the difference disappears. Both regimes are recorded in docs/FIELDAFFINITY.md.
std::size_t g_stride = 9;

// The workload: exactly the co-access the lens observed — one function touching x,y,z,vx,vy,vz.
template<class T>
double integrate( std::vector<T>& elems, float dt )
{
    double            sink   = 0.0;
    const std::size_t kStride = g_stride;
    std::size_t at = 0;
    for( std::size_t n = 0; n < elems.size(); ++n )
    {
        T& e = elems[ at ];
        e.x += e.vx * dt;
        e.y += e.vy * dt;
        e.z += e.vz * dt;
        sink += double( e.x ) + double( e.y ) + double( e.z );
        // MASK, never `%`: elems.size() is a runtime value, so a modulo compiles to a hardware divide
        // (~20 cycles) and the benchmark would be measuring integer division rather than cache traffic.
        // Found by measuring, not by inspection — the first draft's numbers were dominated by the divide.
        at = ( at + kStride ) & ( kElems - 1 );
    }
    return sink;
}

struct Sample
{
    double                 ms = 0.0;
    prof::pmc::Snapshot    delta;
};

template<class T>
Sample runOnce( std::vector<T>& elems )
{
    Sample s;
    const prof::pmc::Snapshot before = prof::pmc::read();
    const auto                t0     = std::chrono::steady_clock::now();
    const double              sink   = integrate( elems, 0.001f );
    const auto                t1     = std::chrono::steady_clock::now();
    const prof::pmc::Snapshot after  = prof::pmc::read();
    s.ms = std::chrono::duration<double, std::milli>( t1 - t0 ).count();
    for( unsigned i = 0; i < prof::pmc::kMaxEvents; ++i )
    {
        s.delta.values[i] = after.values[i] - before.values[i];
    }
    // Keep the sink observable so no compiler can delete the loop; the value itself is not interesting.
    if( sink == 1234.5678 )
    {
        std::fprintf( stderr, "impossible sink\n" );
    }
    return s;
}

// One median, over whichever field of a Sample the caller names. Takes the vector BY VALUE so a caller
// can take the median of several keys off the same samples without the sort order of one call leaking
// into the next.
template<class Key>
auto medianBy( std::vector<Sample> v, Key key ) -> decltype( key( v[0] ) )
{
    std::sort( v.begin(), v.end(), [ & ]( const Sample& a, const Sample& b ) { return key( a ) < key( b ); } );
    return key( v[ v.size() / 2 ] );
}

template<class T>
void fill( std::vector<T>& v )
{
    for( std::size_t i = 0; i < v.size(); ++i )
    {
        std::memset( &v[i], 0, sizeof( T ) );
        v[i].x  = float( i & 1023u );
        v[i].vx = 1.0f;
        v[i].vy = 2.0f;
        v[i].vz = 3.0f;
    }
}

}   // namespace

int main( int argc, char** argv )
{
    if( argc > 1 )
    {
        const long want = std::strtol( argv[1], nullptr, 10 );
        if( want <= 0 || ( want % 2 ) == 0 )
        {
            std::fprintf( stderr, "usage: %s [ODD_STRIDE_IN_ELEMENTS]  (odd, so it is coprime with the power-of-two count)\n", argv[0] );
            return 2;
        }
        g_stride = std::size_t( want );
    }

    prof::pmc::ensure_thread_counting();

    std::printf( "bench_field_ab: the --field-affinity split-line hypothesis, on hardware\n" );
    std::printf( "  elems=%zu  bytes/arm=%zu MB  samples=%d (alternating)  block=64 B  stride=%zu elems\n",
                 kElems, ( kElems * sizeof( SplitLayout ) ) >> 20, kSamples, g_stride );
    std::printf( "  layout A (split)  dist(x,vx)=%zu  wt=0.00      <- what the lens flags\n",
                 std::size_t( offsetof( SplitLayout, vx ) - offsetof( SplitLayout, x ) ) );
    std::printf( "  layout B (packed) dist(x,vx)=%zu  wt=0.75\n",
                 std::size_t( offsetof( PackedLayout, vx ) - offsetof( PackedLayout, x ) ) );

    const bool counters = prof::pmc::active();
    if( counters )
    {
        std::printf( "  counters=ACTIVE events=%u:", prof::pmc::event_count() );
        for( unsigned i = 0; i < prof::pmc::event_count(); ++i )
        {
            std::printf( " %s", prof::pmc::event_label( i ) );
        }
        std::printf( "\n" );
    }
    else
    {
        // House rule: a measure that could not be evaluated is UNAVAILABLE, never "did not fire".
        std::printf( "  counters=UNAVAILABLE (kperf needs root on Apple; Linux needs perf_event_paranoid<=2)"
                     " — re-run under sudo for the counter columns. Timing below is unaffected.\n" );
    }

    std::vector<SplitLayout>  a( kElems );
    std::vector<PackedLayout> b( kElems );
    fill( a );
    fill( b );

    std::vector<Sample> sa, sb;
    sa.reserve( kSamples );
    sb.reserve( kSamples );
    for( int i = 0; i < kSamples; ++i )
    {
        if( i % 2 == 0 )
        {
            sa.push_back( runOnce( a ) );
            sb.push_back( runOnce( b ) );
        }
        else
        {
            sb.push_back( runOnce( b ) );
            sa.push_back( runOnce( a ) );
        }
    }

    const double msA = medianBy( sa, []( const Sample& s ) { return s.ms; } );
    const double msB = medianBy( sb, []( const Sample& s ) { return s.ms; } );
    std::printf( "\n  split=%9.3f ms   packed=%9.3f ms   ratio=%5.2fx\n", msA, msB, msA / msB );

    if( counters )
    {
        for( unsigned i = 0; i < prof::pmc::event_count(); ++i )
        {
            const std::uint64_t ca = medianBy( sa, [ i ]( const Sample& s ) { return s.delta.values[ i ]; } );
            const std::uint64_t cb = medianBy( sb, [ i ]( const Sample& s ) { return s.delta.values[ i ]; } );
            const double        r  = ( cb == 0 ) ? 0.0 : double( ca ) / double( cb );
            std::printf( "  %-18s split=%14llu  packed=%14llu  ratio=%5.2fx\n",
                         prof::pmc::event_name( i ),
                         static_cast<unsigned long long>( ca ), static_cast<unsigned long long>( cb ), r );
        }
    }
    else
    {
        std::printf( "  l1d-cache-misses   UNAVAILABLE  (the mechanism claim is unverified in this run)\n" );
    }

    // A null result is a result. Reported, not swallowed.
    const double delta = ( msA - msB ) / msB;
    if( delta < 0.02 && delta > -0.02 )
    {
        std::printf( "\n  VERDICT: NULL — the two layouts are within 2%%. The static separation cost did NOT\n"
                     "  translate into a measured cost at this working-set size. That is exactly limit (1) in\n"
                     "  src/fieldaffinity.h: a static access count is not a dynamic frequency.\n" );
    }
    else if( delta > 0.0 )
    {
        std::printf( "\n  VERDICT: CONFIRMED at stride=%zu — the flagged (split) layout is %.1f%% slower.\n",
                     g_stride, delta * 100.0 );
    }
    else
    {
        std::printf( "\n  VERDICT: REFUTED at stride=%zu — the flagged (split) layout is %.1f%% FASTER. Co-locating the\n"
                     "  pair moved LESS data and still cost MORE time: the packed arm touches one 64 B line per 256 B\n"
                     "  element, which is a sparser stream than the split arm's two, and the hardware prefetcher\n"
                     "  reacts to density. That is a measured instance of the non-monotonicity src/fieldaffinity.h\n"
                     "  warns about, independent of the false-sharing argument.\n", g_stride, -delta * 100.0 );
    }
    // ONE stride is not an answer. The sign of this measurement flips with the access pattern on this
    // machine (see docs/FIELDAFFINITY.md for the recorded sweep), so a run that reports only one regime is
    // reporting half a result. Say so every time rather than trusting the reader to remember.
    std::printf( "\n  ONE STRIDE IS NOT AN ANSWER: re-run at several (e.g. 1, 9, 129, 4097). The sign of this\n"
                 "  difference is access-pattern dependent, which is the whole reason the lens ADVISES and does\n"
                 "  not transform.\n" );
    return 0;
}
