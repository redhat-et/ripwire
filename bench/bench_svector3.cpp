// bench_svector3.cpp — the evidence for why src/infra/svector.h (rw::svector) earns a place ALONGSIDE the
// vendored martinus/svector. A controlled 3-way: same partition-by-hash machinery, same FixedStr keys,
// 64 shards — ONLY the Map<FixedStr, V> value type V differs. So any timing delta is the value type.
//
//   B  std::vector<uint32>          24 B — per-name malloc on build; branch-free size() (ptr subtraction)
//   C  ankerl::svector<uint32,2>    16 B — alloc-free build; size() branches on SVO is_direct()
//   D  rw::svector<uint32,2>       24 B — alloc-free build; size() is `return sz_` (branch-free)
//
// Measured (5 runs, contended box — repeat, n=1 is noise): for this WRITE-ONCE / READ-HOT map value,
//   build:   C≈D ~7ms  ≪  B ~22ms      (both svectors kill the per-name malloc)
//   resolve: B≈D ~11ms  <  C ~18ms      (B & D branch-free size(); C's SVO size() branch costs ~6ms/4M)
//   total:   D ~18ms  <  C ~24ms  <  B ~33ms   → rw::svector ~25% over martinus, ~45% over std::vector.
// D wins by spending 8 bytes (24 vs 16) on an explicit size field.
//
// ── THAT 25% DOES NOT SURVIVE CONTACT WITH THE PIPELINE. Read this before quoting it. ────────────────
// The numbers above are correct FOR THIS MICROBENCHMARK and they do not transfer. Measured in situ
// (bench/svectorab.py, four-way alias flip, --no-cache both sides, fresh build per arm, 11 interleaved
// reps against a 0.3% A/A noise floor) on a 2376-file C++/ObjC++ corpus:
//
//   affected phase (buildGraph):  std::vector +6.0%   ankerl +1.9%   rw 0.0%   rwx-union +0.2%
//   end-to-end:                   all four arms indistinguishable
//
// ankerl is 1.9% behind on the real workload, not 25%. Two reasons the microbenchmark inflates it, and
// note that the FIRST one is the opposite of what an earlier revision of this comment claimed:
//   * ITS CARDINALITY IS UNREAL. It builds 200 000 distinct names. ripwire's own tree indexes 3 220
//     symbols and the largest corpus it has been pointed at 43 354, so this runs at 62x and 4.6x
//     anything real. At 200 000 names the profile is memory-bound (counters: IPC 0.70, LLC-MPKI 84.9)
//     and a 16-byte value beats a 24-byte one by ~11.7%; at 3 220 and 43 354 that same comparison is
//     0.2-0.5%, at the noise floor. The microbenchmark therefore OVERSTATES the cost of instance SIZE.
//     What does transfer is the size() cost (~6-7% inline, 42-55% once lists spill past ankerl's
//     inline 3, because its spilled size() is a dependent load into the heap block).
//   * buildGraph is 2.7% of a full run, so even a real 25% on this shape is ~0.7% end-to-end.
//     Report against post-parse pipeline time (31.4 ms), not the ~900 ms total — see bench/SVECTORAB.md.
// Keep this file: it is a good ISOLATION of the size() branch and the correctness harness's methodology
// ancestor. Do not cite its ratio as the reason to choose a container. bench/SVECTORAB.md is that answer.
//
// Build: cc -O3 -march=native -std=c++23 bench/bench_svector3.cpp src/infra/diagnostics.cpp \
//        -Isrc -Isrc/infra -Ithird_party -lc++

#define PROFILE_AUTO_REPORT 0
#include "infra/fixedStr.h"
#include "infra/svector.h"           // rw::svector — src/infra/, named by its layer prefix
#include "../third_party/svector.h"  // martinus/svector → ankerl::svector — explicit path (dodges the basename clash)
#include "infra/profileScope.h"
#include "unordered_dense.h"
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <random>
#include <thread>
#include <vector>

using rw::FixedStr;
using rw::FixedStrHash;
template <class V> using Map = ankerl::unordered_dense::map<FixedStr, V, FixedStrHash>;
constexpr int SHARDS = 64;

static inline std::uint32_t shardOf( const FixedStr& s ) noexcept
{ std::uint64_t h = s.hash(); h ^= h >> 33; h *= 0xff51afd7ed558ccdULL; h ^= h >> 33; return std::uint32_t( h ) & ( SHARDS - 1 ); }

template <class Fn> static double timedMs( Fn&& fn )
{ const auto t0 = std::chrono::steady_clock::now(); fn(); return std::chrono::duration<double, std::milli>( std::chrono::steady_clock::now() - t0 ).count(); }

int main()
{
    const std::size_t N = 1'000'000, D = 200'000, R = 4'000'000;
    std::mt19937_64 rng( 0xC0FFEEULL );
    std::vector<FixedStr> pool;  pool.reserve( D );
    for( std::size_t i = 0; i < D; ++i ) { char b[ 24 ]; int n = std::snprintf( b, sizeof( b ), "sym_%llu", (unsigned long long)( rng() % 99999983ULL ) ); pool.emplace_back( std::string_view( b, std::size_t( n ) ) ); }
    std::vector<FixedStr> symN( N ), refN( R );
    for( std::size_t i = 0; i < N; ++i ) symN[i] = pool[ rng() % D ];
    for( std::size_t i = 0; i < R; ++i ) refN[i] = pool[ rng() % D ];
    unsigned T = std::thread::hardware_concurrency();  if( T == 0 ) T = 1;

    std::printf( "sizeof: std::vector=%zu  martinus/svector=%zu  rw::svector=%zu\n",
                 sizeof( std::vector<std::uint32_t> ), sizeof( ankerl::svector<std::uint32_t, 2> ), sizeof( rw::svector<std::uint32_t, 2> ) );

    std::vector<std::vector<std::vector<std::uint32_t>>> tBuckets( T, std::vector<std::vector<std::uint32_t>>( SHARDS ) );
    timedMs( [ & ] { std::vector<std::thread> pool; std::atomic<std::size_t> next{ 0 };
        for( unsigned t = 0; t < T; ++t ) pool.emplace_back( [ &, t ] { auto& tb = tBuckets[t];
            for( ;; ) { const std::size_t lo = next.fetch_add( 65536 ); if( lo >= N ) break; const std::size_t hi = std::min( N, lo + 65536 );
                for( std::size_t i = lo; i < hi; ++i ) tb[ shardOf( symN[i] ) ].push_back( std::uint32_t( i ) ); } } );
        for( auto& th : pool ) th.join(); } );

    const auto build = [ & ]( auto& shards ) { std::vector<std::thread> pool; std::atomic<int> ns{ 0 };
        for( unsigned t = 0; t < T; ++t ) pool.emplace_back( [ & ] { for( ;; ) { const int s = ns.fetch_add( 1 ); if( s >= SHARDS ) break;
            std::size_t cnt = 0; for( unsigned tt = 0; tt < T; ++tt ) cnt += tBuckets[tt][s].size(); auto& m = shards[s]; m.reserve( cnt / 2 + 1 );
            for( unsigned tt = 0; tt < T; ++tt ) for( std::uint32_t id : tBuckets[tt][s] ) m[ symN[id] ].push_back( id ); } } ); for( auto& th : pool ) th.join(); };
    const auto resolve = [ & ]( auto& shards ) -> std::uint64_t { std::vector<std::thread> pool; std::atomic<std::size_t> next{ 0 }; std::vector<std::uint64_t> tR( T, 0 );
        for( unsigned t = 0; t < T; ++t ) pool.emplace_back( [ &, t ] { std::uint64_t r = 0;
            for( ;; ) { const std::size_t lo = next.fetch_add( 65536 ); if( lo >= R ) break; const std::size_t hi = std::min( R, lo + 65536 );
                for( std::size_t i = lo; i < hi; ++i ) { const auto& m = shards[ shardOf( refN[i] ) ]; const auto it = m.find( refN[i] ); if( it != m.end() ) r += it->second.size(); } } tR[t] = r; } );
        for( auto& th : pool ) th.join(); std::uint64_t tot = 0; for( auto v : tR ) tot += v; return tot; };

    std::vector<Map<std::vector<std::uint32_t>>>        sB( SHARDS );
    std::vector<Map<ankerl::svector<std::uint32_t, 2>>> sC( SHARDS );
    std::vector<Map<rw::svector<std::uint32_t, 2>>>    sD( SHARDS );
    std::uint64_t rB, rC, rD;
    const double bB = timedMs( [ & ] { PROFILE_SCOPE_DESCRIBE( "B.build.std_vector" ); build( sB ); } );
    const double rrB = timedMs( [ & ] { PROFILE_SCOPE_DESCRIBE( "B.resolve" );          rB = resolve( sB ); } );
    const double bC = timedMs( [ & ] { PROFILE_SCOPE_DESCRIBE( "C.build.martinus" );    build( sC ); } );
    const double rrC = timedMs( [ & ] { PROFILE_SCOPE_DESCRIBE( "C.resolve" );          rC = resolve( sC ); } );
    const double bD = timedMs( [ & ] { PROFILE_SCOPE_DESCRIBE( "D.build.ctx" );         build( sD ); } );
    const double rrD = timedMs( [ & ] { PROFILE_SCOPE_DESCRIBE( "D.resolve" );          rD = resolve( sD ); } );

    std::printf( "verify: B=%llu C=%llu D=%llu %s\n", (unsigned long long)rB, (unsigned long long)rC, (unsigned long long)rD, ( rB == rC && rC == rD ) ? "(match)" : "(MISMATCH)" );
    std::printf( "  %-28s build=%5.1f  resolve=%5.1f  total=%5.1f\n", "B std::vector (24B)",          bB, rrB, bB + rrB );
    std::printf( "  %-28s build=%5.1f  resolve=%5.1f  total=%5.1f\n", "C martinus/svector (16B)",     bC, rrC, bC + rrC );
    std::printf( "  %-28s build=%5.1f  resolve=%5.1f  total=%5.1f\n", "D rw::svector (24B)",         bD, rrD, bD + rrD );
    return 0;
}
