// bench_chase_ab.cpp — the VALIDATION HALF of Phase B (src/fieldaffinity.h's chase-pointer colocation
// refinement, PLAN.md "2026-08-06 (evening, cont.)"): the SAME A/B-and-alternate methodology
// bench_field_ab.cpp already uses for the general split-line hypothesis, applied to the ONE shape Phase B
// singles out — a chase-pointer field (`next`) colocated with the hot payload field a traversal ALSO
// reads on every step.
//
// Build (the same standalone one-liner every bench in this directory uses — no CMake target, deliberately):
//   c++ -O2 -std=c++23 bench/bench_chase_ab.cpp -Isrc -Isrc/infra -Ithird_party -o /tmp/ripwire_chase_ab
//   /tmp/ripwire_chase_ab            # timing only, unprivileged
//   sudo /tmp/ripwire_chase_ab       # + hardware counters (kperf on Apple needs root; Linux needs
//                                    #   perf_event_paranoid <= 2, see src/infra/profilePmc.h)
//
// ── WHY THIS IS A DIFFERENT MEASUREMENT FROM bench_field_ab.cpp, NOT A DUPLICATE ────────────────────────
// bench_field_ab's array walk advances by a STRIDE FORMULA — the address of element N+1 is known before
// element N is even read, so a hardware prefetcher can hide the split arm's second cache-line fetch, and
// §5.3 of docs/FIELDAFFINITY.md records the hypothesis INVERTING at stride 1 because of exactly that. A
// pointer-chase traversal has no such escape: the address of the NEXT node is the VALUE just read out of
// THIS node's `next` field, so the fetch that resolves `next` and the fetch that would resolve `payload`
// are either the SAME cache-line fetch (packed) or two SERIALIZED, dependent ones (split) that no
// prefetcher can hide — the next address literally does not exist until the current line lands. That
// latency-bound dependency chain is Phase B's whole premise, and this harness isolates it: same node
// count, same total bytes, same VISIT ORDER (a single Fisher-Yates shuffle, fixed seed, applied to build
// BOTH arms' `next` chains identically) — the only variable is whether `next` and `payload` share a line.
//
// ── THE SHAPE UNDER TEST ─────────────────────────────────────────────────────────────────────────────
// ChaseSplit puts `payload` at offset 0 and `next` at offset 192 — the EXACT distance
// bench_field_ab.cpp's split arm uses, so the two documents' numbers are comparable. ChasePacked puts
// `next` at offset 8, immediately after `payload`, on the SAME 64 B line. Both arms are 256 B; only the
// byte distance between the two fields a traversal touches on every step moves.
//
// ── WHAT AN HONEST RESULT LOOKS LIKE ─────────────────────────────────────────────────────────────────
// Same two failure modes bench_field_ab.cpp discloses, never hidden: counters UNAVAILABLE without root
// still reports timing; a null result (the two arms measure the same) is printed as a null result, not
// suppressed. THE NUMBER THIS PRODUCES IS NOT WIRED INTO src/fieldaffinity.h's sepCost ARITHMETIC — see
// kChaseSepCostBoostMeasured / kChaseSepCostBoostApplied in that file and docs/FIELDAFFINITY.md §8 for why
// a REAL measured number here still does not clear PLAN.md's required real-corpus, blind-reviewed
// precision floor before Phase B may consume anything ranking-affecting.

#include "profilePmc.h"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <vector>

namespace
{

constexpr std::size_t kNodes   = 1u << 18;   // 256 Ki nodes x 256 B = 64 MB per arm — matches bench_field_ab.cpp's scale
constexpr int         kSamples = 7;          // odd, so the median is a real sample
constexpr std::uint32_t kShuffleSeed = 0x5AFEu;   // fixed — BOTH arms' next-chains use the SAME visit order

// ── the two arms ─────────────────────────────────────────────────────────────────────────────────────
struct ChaseSplit
{
    std::uint64_t payload;      // off 0..7      (64 B line 0)
    std::uint64_t cold[23];     // off 8..191
    ChaseSplit*   next;         // off 192..199  (64 B line 3) — the EXACT bench_field_ab.cpp split distance
    std::uint64_t tail[7];      // off 200..255
};
static_assert( sizeof( ChaseSplit ) == 256, "ChaseSplit must be exactly four 64 B lines" );
static_assert( offsetof( ChaseSplit, next ) - offsetof( ChaseSplit, payload ) == 192,
               "the chase-split hypothesis IS this distance — must match bench_field_ab.cpp's split arm" );

struct ChasePacked
{
    std::uint64_t payload;      // off 0..7    (64 B line 0)
    ChasePacked*  next;         // off 8..15   (64 B line 0 — the whole point: next lands the SAME fetch as payload)
    std::uint64_t cold[22];     // off 16..191
    std::uint64_t tail[8];      // off 192..255
};
static_assert( sizeof( ChasePacked ) == 256, "ChasePacked must match ChaseSplit byte for byte in SIZE" );
static_assert( offsetof( ChasePacked, next ) - offsetof( ChasePacked, payload ) == 8,
               "the packed arm must co-locate payload and next on ONE line" );

// One Fisher-Yates permutation of [0,kNodes), used to link BOTH arms' `next` chains identically — the
// visit ORDER is the same dependent-load pattern in both arms; only the intra-node byte distance differs.
std::vector<std::uint32_t> shufflePermutation()
{
    std::vector<std::uint32_t> perm( kNodes );
    for( std::uint32_t i = 0; i < kNodes; ++i )
    {
        perm[i] = i;
    }
    std::mt19937 rng( kShuffleSeed );
    std::shuffle( perm.begin(), perm.end(), rng );
    return perm;
}

template<class T>
T* linkChain( std::vector<T>& nodes, const std::vector<std::uint32_t>& perm )
{
    for( std::size_t i = 0; i < nodes.size(); ++i )
    {
        nodes[i].payload = std::uint64_t( i & 1023u );
        std::memset( nodes[i].cold, 0, sizeof( nodes[i].cold ) );
        std::memset( nodes[i].tail, 0, sizeof( nodes[i].tail ) );
    }
    for( std::size_t i = 0; i + 1 < perm.size(); ++i )
    {
        nodes[ perm[i] ].next = &nodes[ perm[ i + 1 ] ];
    }
    nodes[ perm.back() ].next = nullptr;
    return &nodes[ perm.front() ];
}

// The workload: a genuine pointer-chase — the address of the next fetch does not exist until THIS one
// resolves, exactly the latency-bound dependency chain Phase B's premise is about.
template<class T>
std::uint64_t chase( T* head )
{
    std::uint64_t sink = 0;
    for( T* p = head; p != nullptr; p = p->next )
    {
        sink += p->payload;
    }
    return sink;
}

struct Sample
{
    double                 ms = 0.0;
    prof::pmc::Snapshot    delta;
};

template<class T>
Sample runOnce( T* head )
{
    Sample s;
    const prof::pmc::Snapshot before = prof::pmc::read();
    const auto                t0     = std::chrono::steady_clock::now();
    const std::uint64_t       sink   = chase( head );
    const auto                t1     = std::chrono::steady_clock::now();
    const prof::pmc::Snapshot after  = prof::pmc::read();
    s.ms = std::chrono::duration<double, std::milli>( t1 - t0 ).count();
    for( unsigned i = 0; i < prof::pmc::kMaxEvents; ++i )
    {
        s.delta.values[i] = after.values[i] - before.values[i];
    }
    if( sink == 0xFFFFFFFFFFFFFFFFull )   // keep the sink observable so no compiler can delete the loop
    {
        std::fprintf( stderr, "impossible sink\n" );
    }
    return s;
}

template<class Key>
auto medianBy( std::vector<Sample> v, Key key ) -> decltype( key( v[0] ) )
{
    std::sort( v.begin(), v.end(), [ & ]( const Sample& a, const Sample& b ) { return key( a ) < key( b ); } );
    return key( v[ v.size() / 2 ] );
}

}   // namespace

int main()
{
    prof::pmc::ensure_thread_counting();

    std::printf( "bench_chase_ab: the --field-affinity chase-pointer colocation hypothesis, on hardware\n" );
    std::printf( "  nodes=%zu  bytes/arm=%zu MB  samples=%d (alternating)  block=64 B  shuffle_seed=0x%x\n",
                 kNodes, ( kNodes * sizeof( ChaseSplit ) ) >> 20, kSamples, kShuffleSeed );
    std::printf( "  arm A (split)  dist(payload,next)=%zu  wt=0.00      <- what Phase B would flag\n",
                 std::size_t( offsetof( ChaseSplit, next ) - offsetof( ChaseSplit, payload ) ) );
    std::printf( "  arm B (packed) dist(payload,next)=%zu  wt=0.88\n",
                 std::size_t( offsetof( ChasePacked, next ) - offsetof( ChasePacked, payload ) ) );

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
        std::printf( "  counters=UNAVAILABLE (kperf needs root on Apple; Linux needs perf_event_paranoid<=2)"
                     " — re-run under sudo for the counter columns. Timing below is unaffected.\n" );
    }

    const std::vector<std::uint32_t> perm = shufflePermutation();
    std::vector<ChaseSplit>  a( kNodes );
    std::vector<ChasePacked> b( kNodes );
    ChaseSplit*  headA = linkChain( a, perm );
    ChasePacked* headB = linkChain( b, perm );

    std::vector<Sample> sa, sb;
    sa.reserve( kSamples );
    sb.reserve( kSamples );
    for( int i = 0; i < kSamples; ++i )
    {
        if( i % 2 == 0 )
        {
            sa.push_back( runOnce( headA ) );
            sb.push_back( runOnce( headB ) );
        }
        else
        {
            sb.push_back( runOnce( headB ) );
            sa.push_back( runOnce( headA ) );
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

    const double delta = ( msA - msB ) / msB;
    if( delta < 0.02 && delta > -0.02 )
    {
        std::printf( "\n  VERDICT: NULL — the two layouts are within 2%%. A latency-bound chase over a shuffled\n"
                     "  64 MB arena did NOT separate the two layouts at this working-set size.\n" );
    }
    else if( delta > 0.0 )
    {
        std::printf( "\n  VERDICT: CONFIRMED — the split layout is %.1f%% slower per traversal.\n", delta * 100.0 );
    }
    else
    {
        std::printf( "\n  VERDICT: REFUTED — the split layout is %.1f%% FASTER. Same caution as bench_field_ab.cpp\n"
                     "  §5.3: a static separation cost is a hypothesis, not a defect.\n", -delta * 100.0 );
    }
    std::printf( "\n  NOT WIRED IN: this number is NOT applied to src/fieldaffinity.h's sepCost arithmetic\n"
                 "  (kChaseSepCostBoostApplied is locked at 1.0) until PLAN.md's real-corpus, blind-reviewed\n"
                 "  precision floor clears. See docs/FIELDAFFINITY.md sec 8.\n" );
    return 0;
}
