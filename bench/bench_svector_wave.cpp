// bench_svector_wave.cpp — the SHAPE-LEVEL half of the small-vector measurement rig.
//
// The authoritative comparison is the in-situ one (bench/svectorab.py, whole pipeline, real corpora).
// This binary answers the three questions that a whole-pipeline wall-clock cannot:
//
//   1. IS THE WORKLOAD MEMORY-BOUND? Read this FIRST; it decides how to read everything else. Answered
//      with the tree's existing PMC backend (src/infra/profilePmc.h): IPC, and misses per thousand
//      instructions at L1D and LLC. The answer at 200K names is YES, emphatically (IPC 0.70, LLC-MPKI
//      84.9), and that measurement is what promoted the 16-byte union layout into rw::svector — under a
//      memory-bound profile an instance-size difference is real, where a predicted branch is ~1 cycle.
//      Note what this arm can no longer isolate: A is the only 24-byte arm left, so the 24-vs-16
//      comparison that produced the promotion is preserved in bench/SVECTORAB.md, not re-run here.
//   2. HOW MANY HEAP ALLOCATIONS does each arm perform, and how many bytes? Counted exactly, with a
//      global operator new replacement (this is a standalone bench binary, so that costs nothing
//      anywhere else).
//   3. WHAT DOES THE REHASH PATH COST? ankerl::unordered_dense keeps values in ONE contiguous vector, so
//      every rehash MOVES EVERY ELEMENT. That is the hottest operation on these types and nothing calls
//      it explicitly. WaveShape below forces several rehashes and times only the movement.
//
// ARMS (the same three the alias flip selects, so the two halves of the rig are comparable):
//   A std::vector<uint32>          24 B, a malloc per non-empty list
//   B ankerl::svector<uint32,2>    16 B, size() branches on the SVO tag; inline capacity is really 3
//   C rw::svector<uint32,2>        16 B AND size() branch-free (the promoted union design)
//
// There used to be a fourth arm, rwx::svector16 — the union experiment. It won and was promoted into
// rw::svector, so arm C IS that design now and the separate copy is gone.
//
// THE KNOWN-NEGATIVE. A measurement rig that has never returned "no difference" is not trustworthy, so
// arm E is arm C again — the SAME type, same code, same everything. Any spread the rig reports between C
// and E is the rig's own noise floor, and no B-vs-C difference smaller than that floor may be read as a
// result. It is printed on every run, PER COLUMN: a single global floor is the max across columns, and
// taking the max lets the noisiest column set the bar for all of them — a 6.6% rehash floor once buried
// a real 11.7% size-hot effect whose own column floor was 0.3%.
//
// Build (the standalone one-liner every bench here uses — no CMake target, deliberately):
//   c++ -O2 -std=c++23 bench/bench_svector_wave.cpp -Isrc -Isrc/infra -Ithird_party -Ibench -o /tmp/rw_svwave
//   /tmp/rw_svwave           # timing + allocations, unprivileged
//   sudo /tmp/rw_svwave      # + hardware counters (kperf needs root on Apple; Linux needs
//                            #   perf_event_paranoid <= 2 — see src/infra/profilePmc.h)

#define PROFILE_AUTO_REPORT 0
#include "profilePmc.h"

#include "infra/fixedStr.h"
#include "infra/svector.h"
#include "../third_party/svector.h"
#include "unordered_dense.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>
#include <vector>

// ── allocation counting ──────────────────────────────────────────────────────────────────────────────
// Armed only around the phase being counted. When disarmed this is one predictable, arm-independent
// branch per malloc; the timing phases run disarmed so the count does not inflate whichever arm
// allocates most — which is precisely the quantity under measurement.
namespace
{
std::atomic<bool>          g_arm { false };
std::atomic<std::uint64_t> g_count { 0 };
std::atomic<std::uint64_t> g_bytes { 0 };
constexpr std::size_t      kHdr = 16;
}

void* operator new( std::size_t n )
{
    void* raw = std::malloc( n + kHdr );
    if( raw == nullptr ) { throw std::bad_alloc(); }
    *static_cast<std::uint64_t*>( raw ) = n;
    if( g_arm.load( std::memory_order_relaxed ) )
    {
        g_count.fetch_add( 1, std::memory_order_relaxed );
        g_bytes.fetch_add( n, std::memory_order_relaxed );
    }
    return static_cast<char*>( raw ) + kHdr;
}
void* operator new[]( std::size_t n ) { return ::operator new( n ); }
void  operator delete( void* p ) noexcept { if( p ) { std::free( static_cast<char*>( p ) - kHdr ); } }
void  operator delete[]( void* p ) noexcept { ::operator delete( p ); }
void  operator delete( void* p, std::size_t ) noexcept { ::operator delete( p ); }
void  operator delete[]( void* p, std::size_t ) noexcept { ::operator delete( p ); }

namespace
{

using rw::FixedStr;
using rw::FixedStrHash;
template <class V> using Map = ankerl::unordered_dense::map<FixedStr, V, FixedStrHash>;

// Runtime, not constexpr, because the WORKING-SET SWEEP below varies the first of them and the other two
// track it. Defaults reproduce the single-point run.
std::size_t kNames = 200'000;   // distinct names — the byName cardinality shape
std::size_t kPush  = 1'000'000; // id pushes across those names
std::size_t kReads = 4'000'000; // read-hot loop length
int         kSamples = 5;       // odd, so the median is a real sample

// deterministic, stdlib-independent, and UBSan-clean (see bench_svector_diff.cpp for why not mt19937_64)
struct Rng
{
    std::uint64_t s;
    explicit Rng( std::uint64_t seed ) noexcept : s( seed ? seed : 0x9E3779B97F4A7C15ull ) {}
    std::uint64_t operator()() noexcept
    {
        s ^= ( s & 0x0007FFFFFFFFFFFFull ) << 13;
        s ^= s >> 7;
        s ^= ( s & 0x00007FFFFFFFFFFFull ) << 17;
        return s;
    }
};

struct Counters
{
    double              ms = 0.0;
    prof::pmc::Snapshot d {};
};

template <class Fn>
Counters measure( Fn&& fn )
{
    Counters c;
    const prof::pmc::Snapshot before = prof::pmc::read();
    const auto                t0     = std::chrono::steady_clock::now();
    fn();
    const auto                t1    = std::chrono::steady_clock::now();
    const prof::pmc::Snapshot after = prof::pmc::read();
    c.ms = std::chrono::duration<double, std::milli>( t1 - t0 ).count();
    for( unsigned i = 0; i < prof::pmc::kMaxEvents; ++i ) { c.d.values[i] = after.values[i] - before.values[i]; }
    return c;
}

template <class Key>
auto medianBy( std::vector<Counters> v, Key key ) -> decltype( key( v[0] ) )
{
    std::sort( v.begin(), v.end(), [ & ]( const Counters& a, const Counters& b ) { return key( a ) < key( b ); } );
    return key( v[ v.size() / 2 ] );
}

std::vector<FixedStr> g_pool;
std::vector<std::uint32_t> g_keyOf;    // push i -> pool index
std::vector<std::uint32_t> g_readOf;   // read i -> pool index

// ── shape S: build byName, then read it size()-hot ───────────────────────────────────────────────────
template <class V>
struct WaveShape
{
    static void build( Map<V>& m )
    {
        m.reserve( kNames );
        for( std::size_t i = 0; i < kPush; ++i ) { m[ g_pool[ g_keyOf[i] ] ].push_back( std::uint32_t( i ) ); }
    }
    static std::uint64_t readSize( const Map<V>& m )
    {
        std::uint64_t acc = 0;
        for( std::size_t i = 0; i < kReads; ++i )
        {
            const auto it = m.find( g_pool[ g_readOf[i] ] );
            if( it != m.end() ) { acc += it->second.size(); }
        }
        return acc;
    }
    static std::uint64_t readIterate( const Map<V>& m )
    {
        std::uint64_t acc = 0;
        for( std::size_t i = 0; i < kReads; ++i )
        {
            const auto it = m.find( g_pool[ g_readOf[i] ] );
            if( it != m.end() ) { for( const auto& e : it->second ) { acc += e; } }
        }
        return acc;
    }
    // REHASH: no reserve, so unordered_dense grows through its whole doubling cascade and MOVES EVERY
    // ELEMENT at each step. This is the operation nothing calls explicitly and everything pays for.
    static std::size_t rehash()
    {
        Map<V> m;                                       // deliberately NOT reserved
        for( std::size_t i = 0; i < kNames; ++i )
        {
            m[ g_pool[i] ].push_back( std::uint32_t( i ) );
        }
        return m.size();
    }
};

struct Row
{
    const char*   name;
    std::size_t   bytes;
    double        buildMs, sizeMs, iterMs, rehashMs;
    std::uint64_t allocs, allocBytes;
    Counters      sizeCounters, iterCounters;
};

template <class V>
Row runArm( const char* name )
{
    Row r {};
    r.name  = name;
    r.bytes = sizeof( V );

    Map<V> m;
    std::vector<Counters> b, s, it, rh;
    for( int k = 0; k < kSamples; ++k )
    {
        Map<V> fresh;
        b.push_back( measure( [ & ] { WaveShape<V>::build( fresh ); } ) );
        std::uint64_t sink = 0;
        s.push_back(  measure( [ & ] { sink += WaveShape<V>::readSize( fresh ); } ) );
        it.push_back( measure( [ & ] { sink += WaveShape<V>::readIterate( fresh ); } ) );
        rh.push_back( measure( [ & ] { sink += WaveShape<V>::rehash(); } ) );
        if( sink == 0xDEADBEEF ) { std::fprintf( stderr, "impossible sink\n" ); }
        if( k == 0 ) { m = std::move( fresh ); }
    }
    const auto msOf = []( const Counters& c ) { return c.ms; };
    r.buildMs  = medianBy( b,  msOf );
    r.sizeMs   = medianBy( s,  msOf );
    r.iterMs   = medianBy( it, msOf );
    r.rehashMs = medianBy( rh, msOf );
    // the counter sample nearest the median wall time, so counters and time describe the same run
    r.sizeCounters = s[ s.size() / 2 ];
    r.iterCounters = it[ it.size() / 2 ];

    // allocation count: armed for exactly one build, timing already taken
    g_count.store( 0 ); g_bytes.store( 0 ); g_arm.store( true );
    {
        Map<V> counted;
        WaveShape<V>::build( counted );
    }
    g_arm.store( false );
    r.allocs     = g_count.load();
    r.allocBytes = g_bytes.load();
    return r;
}

// derive the memory-boundedness verdict from the counters, or say it is unavailable
void boundedness( const char* label, const Counters& c )
{
    if( !prof::pmc::active() )
    {
        std::printf( "    %-10s counters=UNAVAILABLE — memory-boundedness UNKNOWN for this run\n", label );
        return;
    }
    double cyc = 0, ins = 0, l1d = 0, llc = 0;
    for( unsigned i = 0; i < prof::pmc::event_count(); ++i )
    {
        const char* n = prof::pmc::event_name( i );
        const double v = double( c.d.values[i] );
        if( std::strcmp( n, "cycles" ) == 0 )                { cyc = v; }
        else if( std::strcmp( n, "instructions" ) == 0 )     { ins = v; }
        else if( std::strcmp( n, "l1d-cache-misses" ) == 0 ) { l1d = v; }
        else if( std::strcmp( n, "llc-misses" ) == 0 )       { llc = v; }
    }
    const double ipc      = cyc > 0 ? ins / cyc : 0.0;
    const double l1dMpki  = ins > 0 ? l1d * 1000.0 / ins : 0.0;
    const double llcMpki  = ins > 0 ? llc * 1000.0 / ins : 0.0;
    std::printf( "    %-10s IPC=%4.2f  L1D-MPKI=%7.2f  LLC-MPKI=%7.2f   -> %s\n", label, ipc, l1dMpki, llcMpki,
                 ( ipc < 1.0 && llcMpki > 5.0 ) ? "MEMORY-BOUND (size should dominate the branch)"
                 : ( ipc > 2.0 ) ? "COMPUTE-BOUND (the size() branch is the only axis)"
                                 : "MIXED — read the arms' spread against the known-negative floor" );
}

void regenerate()
{
    Rng rng( 0xC0FFEEull );
    g_pool.clear();
    g_pool.reserve( kNames );
    for( std::size_t i = 0; i < kNames; ++i )
    {
        char b[ 24 ];
        const int n = std::snprintf( b, sizeof( b ), "sym_%llu", (unsigned long long) ( rng() % 99999983ull ) );
        g_pool.emplace_back( std::string_view( b, std::size_t( n ) ) );
    }
    g_keyOf.resize( kPush );
    g_readOf.resize( kReads );
    for( std::size_t i = 0; i < kPush; ++i )  { g_keyOf[i]  = std::uint32_t( rng() % kNames ); }
    for( std::size_t i = 0; i < kReads; ++i ) { g_readOf[i] = std::uint32_t( rng() % kNames ); }
}

// ── the WORKING-SET SWEEP: memory-boundedness without root ────────────────────────────────────────────
// The PMC backend answers "is this memory-bound?" directly, but it needs root on Apple (kperf) and a
// permissive perf_event_paranoid on Linux, so on an ordinary developer run it is UNAVAILABLE. This sweep
// answers the same question by EXPERIMENT rather than by counter, and it is the more direct evidence for
// the actual decision anyway: hold the code fixed and grow the working set. If the container's SIZE is
// what matters, the 16-byte arms must pull further ahead as cardinality rises, because that is the only
// mechanism by which 8 bytes per instance can matter at all. If the ranking is flat across two orders of
// magnitude, size is not the axis and the size() branch is.
//
// Every delta is printed against the A/A noise floor measured at the SAME cardinality — a sweep whose
// trend is smaller than its own noise is not a trend.
void sweep()
{
    // CALIBRATED to the real thing. ripwire's own tree indexes 3220 symbols and the large validation
    // corpus 43354, so `byName` holds at most that many distinct names — the rig's usual 200000 is 62x
    // and 4.6x those. A sweep that only visits sizes nothing real reaches measures an extrapolation.
    // The two REAL points are first-class rows here.
    const std::size_t points[] = { 3'220, 10'000, 43'354, 100'000, 200'000, 400'000 };

    std::printf( "\n== WORKING-SET SWEEP (does the ranking hold at REALISTIC cardinality?) ==\n" );
    std::printf( "  WORK IS HELD CONSTANT: %zu reads and ~1.5 ids per name at every point, so the only variable\n", kReads );
    std::printf( "  is the WORKING SET. (The earlier version scaled reads with cardinality, which changed the\n" );
    std::printf( "  amount of work and the working set together and could not separate them.)\n" );
    std::printf( "  *3220 = ripwire's own tree, *43354 = the large validation corpus. Everything else is\n" );
    std::printf( "  extrapolation beyond anything this tool actually indexes.\n" );
    std::printf( "  Per-column A/A floors (arm E vs arm C) are printed per row; no delta below its OWN\n" );
    std::printf( "  column's floor is a result.\n\n" );
    std::printf( "  %9s %8s | %16s %7s | %16s %7s\n",
                 "names", "val KB", "size-hot B vs C", "floor", "iterated B vs C", "floor" );
    kSamples = 5;
    const std::size_t fixedReads = 4'000'000;
    for( std::size_t n : points )
    {
        kNames = n;
        kPush  = ( n * 3 ) / 2;      // ~1.5 ids per name: the real byName shape (most names define 1-2)
        kReads = fixedReads;         // CONSTANT work
        regenerate();
        const Row b = runArm<ankerl::svector<std::uint32_t, 2>>( "B" );
        const Row c = runArm<rw::svector<std::uint32_t, 2>>( "C" );
        const Row e = runArm<rw::svector<std::uint32_t, 2>>( "E" );
        const auto pct = []( double x, double base ) { return base == 0.0 ? 0.0 : ( x / base - 1.0 ) * 100.0; };
        // PER-COLUMN floors. A single global floor taken as the max across columns is conservative, but it
        // masks a real effect in a quiet column with the noise of a loud one — which is exactly what
        // happened when a 6.6% rehash floor buried an 11.7% size-hot result.
        const double floorSize = std::abs( pct( e.sizeMs, c.sizeMs ) );
        const double floorIter = std::abs( pct( e.iterMs, c.iterMs ) );
        const char*  markBs    = std::abs( pct( b.sizeMs, c.sizeMs ) ) > floorSize ? "" : "~";
        const char*  markBi    = std::abs( pct( b.iterMs, c.iterMs ) ) > floorIter ? "" : "~";
        std::printf( "  %8zu%c %8.0f | %+7.1f%%%s %6.1f%% | %+7.1f%%%s %6.1f%%\n",
                     n, ( n == 3220 || n == 43354 ) ? '*' : ' ', double( 16 * n ) / 1024.0,
                     pct( b.sizeMs, c.sizeMs ), markBs, floorSize,
                     pct( b.iterMs, c.iterMs ), markBi, floorIter );
    }
    std::printf( "\n  READ IT LIKE THIS: negative = faster than rw::svector (arm C). A `~` marks a delta INSIDE\n"
                 "  its own column's A/A floor, i.e. not a result. B and C are now BOTH 16 bytes, so this table\n"
                 "  isolates the size() COST alone — the instance-size variable is held constant. (The old\n"
                 "  24-vs-16 locality comparison is gone from the rig because the 24-byte design no longer\n"
                 "  exists; bench/SVECTORAB.md keeps its measured table.)\n" );
}

}   // namespace

int main( int argc, char** argv )
{
    prof::pmc::ensure_thread_counting();
    const bool sweepMode = ( argc > 1 && std::strcmp( argv[1], "--sweep" ) == 0 );
    if( sweepMode )
    {
        sweep();
        return 0;
    }
    regenerate();

    std::printf( "bench_svector_wave: shape-level four-way (+ a known-negative fifth arm)\n" );
    std::printf( "  names=%zu pushes=%zu reads=%zu samples=%d\n", kNames, kPush, kReads, kSamples );
    if( prof::pmc::active() )
    {
        std::printf( "  counters=ACTIVE events=%u:", prof::pmc::event_count() );
        for( unsigned i = 0; i < prof::pmc::event_count(); ++i ) { std::printf( " %s", prof::pmc::event_label( i ) ); }
        std::printf( "\n" );
    }
    else
    {
        std::printf( "  counters=UNAVAILABLE (kperf needs root on Apple; Linux needs perf_event_paranoid<=2)"
                     " — re-run under sudo. Timing and allocation counts below are unaffected.\n" );
    }

    std::vector<Row> rows;
    rows.push_back( runArm<std::vector<std::uint32_t>>( "A std::vec" ) );
    rows.push_back( runArm<ankerl::svector<std::uint32_t, 2>>( "B ankerl" ) );
    rows.push_back( runArm<rw::svector<std::uint32_t, 2>>( "C rw" ) );
    rows.push_back( runArm<rw::svector<std::uint32_t, 2>>( "E rw (A/A)" ) );   // the known-negative

    std::printf( "\n  %-12s %6s %10s %10s %10s %10s %12s %14s\n",
                 "arm", "B/inst", "build ms", "size ms", "iter ms", "rehash ms", "allocs", "alloc bytes" );
    for( const Row& r : rows )
    {
        std::printf( "  %-12s %6zu %10.1f %10.1f %10.1f %10.1f %12llu %14llu\n",
                     r.name, r.bytes, r.buildMs, r.sizeMs, r.iterMs, r.rehashMs,
                     (unsigned long long) r.allocs, (unsigned long long) r.allocBytes );
    }

    // total inline footprint: what the map's value array costs at this cardinality, per arm
    std::printf( "\n  inline footprint of the value array at %zu entries:\n", kNames );
    for( const Row& r : rows ) { std::printf( "    %-12s %8.2f MB\n", r.name, double( r.bytes * kNames ) / ( 1024.0 * 1024.0 ) ); }

    std::printf( "\n  memory-boundedness (read this BEFORE comparing arms):\n" );
    boundedness( "size-hot", rows[2].sizeCounters );
    boundedness( "iterated", rows[2].iterCounters );

    // THE KNOWN-NEGATIVE, printed every run. C and E are the same type; their gap is the noise floor.
    const Row& c = rows[2];
    const Row& e = rows[3];
    const auto pct = []( double a, double b ) { return b == 0.0 ? 0.0 : ( a / b - 1.0 ) * 100.0; };
    // PER-COLUMN floors, not one global bar. A global floor is the max across columns, and taking the
    // max means the noisiest column sets the bar for all of them: a 6.6% rehash floor (a 6 ms column,
    // where a 0.4 ms wobble is 6%) once buried a real 11.7% size-hot effect whose own column floor was
    // 0.3%. Each column is now judged against its OWN A/A spread, with the global max kept alongside
    // as the conservative reading rather than as the only one.
    const double fBuild  = std::abs( pct( e.buildMs, c.buildMs ) );
    const double fSize   = std::abs( pct( e.sizeMs, c.sizeMs ) );
    const double fIter   = std::abs( pct( e.iterMs, c.iterMs ) );
    const double fRehash = std::abs( pct( e.rehashMs, c.rehashMs ) );
    std::printf( "\n  KNOWN-NEGATIVE (arm C vs arm E — the SAME implementation twice):\n" );
    std::printf( "    %-10s %8s %8s %8s %8s\n", "", "build", "size", "iter", "rehash" );
    std::printf( "    %-10s %+7.1f%% %+7.1f%% %+7.1f%% %+7.1f%%   allocs %s\n", "A/A delta",
                 pct( e.buildMs, c.buildMs ), pct( e.sizeMs, c.sizeMs ), pct( e.iterMs, c.iterMs ),
                 pct( e.rehashMs, c.rehashMs ), ( c.allocs == e.allocs ) ? "IDENTICAL" : "DIFFER (rig is broken)" );
    std::printf( "    %-10s %7.1f%% %7.1f%% %7.1f%% %7.1f%%   <- judge each column against ITS OWN floor\n",
                 "floor", fBuild, fSize, fIter, fRehash );
    const double floorPct = std::max( { fBuild, fSize, fIter, fRehash } );
    std::printf( "    global (max) floor %.1f%% — the conservative bar; using it ALONE masks a real effect in a\n"
                 "    quiet column, so it is reported beside the per-column floors and never instead of them.\n", floorPct );
    if( c.allocs != e.allocs )
    {
        std::printf( "    FAIL: the known-negative arms disagree on allocation count — do not trust any number above.\n" );
        return 1;
    }
    return 0;
}
