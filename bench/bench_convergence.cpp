// bench_convergence.cpp — the library-scale convergence showpiece. After a parallel parse, the symbols
// must converge into ONE structure (the byName multimap) and references resolve against it — the classic
// "many writers / one structure" problem (semiconductor DV elaboration; ripwire's serial merge).
//
//   A serial            : one byName map + resolve, single-threaded — ripwire today.
//   B partition-by-hash : shard the keyspace by hash(name); each shard built + read independently →
//                         DISJOINT writes → lock-free, parallel. The DV lesson: beat many-writers by NOT
//                         sharing — partition until writes don't collide, then it scales with cores.
//   C  = B + rw::svector shard values (inline ≤2 ids → no per-name malloc, AND branch-free size()).
//
// VERIFIED FINDINGS (component medians over 5–7 runs — on a contended box where n=1 IS noise, so repeat):
//   • partition-by-hash ≈ 7.5x over serial — the DV many-writers win (the headline).
//   • rw::svector shard_build ~2x faster than std::vector (alloc elimination, ~200k fewer mallocs).
//   • rw::svector resolve ≈ std::vector resolve: size() is `return sz_`, branch-free (the design point).
//   ⇒ C beats BOTH here — std::vector (per-name malloc on build) and martinus/svector (whose SVO-packed
//     size() branches on the 4M-read hot loop, ~6ms). The full 3-way std::vector / martinus / rw::svector
//     comparison + the isolation proving the gap is size() lives in bench/bench_svector3.cpp.
//
// Keys are FixedStr (32-byte branchless SIMD short string). Profiled with the real PROFILE_SCOPE
// (src/infra/profileScope.h — CNTVCT, or PMC hardware cycle counts when run with sudo).
// Build: cc -O3 -march=native -std=c++23 bench/bench_convergence.cpp src/infra/diagnostics.cpp \
//        -Isrc -Isrc/infra -Ithird_party -lc++

#define PROFILE_AUTO_REPORT 0          // we call prof::report() explicitly, in order
#include "fixedStr.h"
#include "svector.h"                    // rw::svector (src/, -Isrc first) — the branch-free-size() hot-read variant
#include "profileScope.h"               // prof::* (src/infra/)
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
{
    std::uint64_t h = s.hash();
    h ^= h >> 33;  h *= 0xff51afd7ed558ccdULL;  h ^= h >> 33;
    return std::uint32_t( h ) & ( SHARDS - 1 );
}

template <class Fn> static double timedMs( Fn&& fn )
{
    const auto t0 = std::chrono::steady_clock::now();
    fn();
    return std::chrono::duration<double, std::milli>( std::chrono::steady_clock::now() - t0 ).count();
}

int main()
{
    const std::size_t N = 1'000'000, D = 200'000, R = 4'000'000;

    std::mt19937_64 rng( 0xC0FFEEULL );
    std::vector<FixedStr> pool;  pool.reserve( D );
    for( std::size_t i = 0; i < D; ++i )
    { char b[ 24 ]; int n = std::snprintf( b, sizeof( b ), "sym_%llu", (unsigned long long)( rng() % 99999983ULL ) ); pool.emplace_back( std::string_view( b, std::size_t( n ) ) ); }
    std::vector<FixedStr> symN( N ), refN( R );
    for( std::size_t i = 0; i < N; ++i ) symN[i] = pool[ rng() % D ];
    for( std::size_t i = 0; i < R; ++i ) refN[i] = pool[ rng() % D ];

    unsigned T = std::thread::hardware_concurrency();  if( T == 0 ) T = 1;
    std::printf( "synthetic: %zu symbols, %zu refs, %zu distinct names | %d shards, %u threads, FixedStr keys\n", N, R, D, SHARDS, T );

    // ---- A: serial ----
    std::uint64_t resolvedA = 0;
    Map<std::vector<std::uint32_t>> byName;
    const double aBuild = timedMs( [ & ] { PROFILE_SCOPE_DESCRIBE( "A.serial.byName_build" );
        byName.reserve( D );  for( std::uint32_t i = 0; i < N; ++i ) byName[ symN[i] ].push_back( i ); } );
    const double aResolve = timedMs( [ & ] { PROFILE_SCOPE_DESCRIBE( "A.serial.resolve" );
        for( std::size_t i = 0; i < R; ++i ) { const auto it = byName.find( refN[i] ); if( it != byName.end() ) resolvedA += it->second.size(); } } );

    // ---- shared bucketing (phase 1 of B/C) ----
    std::vector<std::vector<std::vector<std::uint32_t>>> tBuckets( T, std::vector<std::vector<std::uint32_t>>( SHARDS ) );
    const double tBucket = timedMs( [ & ] { PROFILE_SCOPE_DESCRIBE( "P.bucket(shared)" );
        std::vector<std::thread> pool;  std::atomic<std::size_t> next{ 0 };
        for( unsigned t = 0; t < T; ++t ) pool.emplace_back( [ &, t ] { auto& tb = tBuckets[t];
            for( ;; ) { const std::size_t lo = next.fetch_add( 65536 ); if( lo >= N ) break; const std::size_t hi = std::min( N, lo + 65536 );
                for( std::size_t i = lo; i < hi; ++i ) tb[ shardOf( symN[i] ) ].push_back( std::uint32_t( i ) ); } } );
        for( auto& th : pool ) th.join(); } );

    const auto buildShards = [ & ]( auto& shards )
    {
        std::vector<std::thread> pool;  std::atomic<int> nextShard{ 0 };
        for( unsigned t = 0; t < T; ++t ) pool.emplace_back( [ & ] {
            for( ;; ) { const int s = nextShard.fetch_add( 1 ); if( s >= SHARDS ) break;
                std::size_t cnt = 0; for( unsigned tt = 0; tt < T; ++tt ) cnt += tBuckets[tt][s].size();
                auto& m = shards[s];  m.reserve( cnt / 2 + 1 );
                for( unsigned tt = 0; tt < T; ++tt ) for( std::uint32_t id : tBuckets[tt][s] ) m[ symN[id] ].push_back( id ); } } );
        for( auto& th : pool ) th.join();
    };
    const auto resolveShards = [ & ]( auto& shards ) -> std::uint64_t
    {
        std::vector<std::thread> pool;  std::atomic<std::size_t> next{ 0 };  std::vector<std::uint64_t> tR( T, 0 );
        for( unsigned t = 0; t < T; ++t ) pool.emplace_back( [ &, t ] { std::uint64_t r = 0;
            for( ;; ) { const std::size_t lo = next.fetch_add( 65536 ); if( lo >= R ) break; const std::size_t hi = std::min( R, lo + 65536 );
                for( std::size_t i = lo; i < hi; ++i ) { const auto& m = shards[ shardOf( refN[i] ) ]; const auto it = m.find( refN[i] ); if( it != m.end() ) r += it->second.size(); } }
            tR[t] = r; } );
        for( auto& th : pool ) th.join();
        std::uint64_t tot = 0; for( auto v : tR ) tot += v; return tot;
    };

    // ---- B (std::vector shards) ----
    std::uint64_t resolvedB = 0;
    std::vector<Map<std::vector<std::uint32_t>>> shardV( SHARDS );
    const double bBuild   = timedMs( [ & ] { PROFILE_SCOPE_DESCRIBE( "B.shard_build.vector" ); buildShards( shardV ); } );
    const double bResolve = timedMs( [ & ] { PROFILE_SCOPE_DESCRIBE( "B.resolve" ); resolvedB = resolveShards( shardV ); } );

    // ---- C (rw::svector shards — alloc-free build + branch-free size()) ----
    std::uint64_t resolvedC = 0;
    std::vector<Map<rw::svector<std::uint32_t, 2>>> shardS( SHARDS );
    const double cBuild   = timedMs( [ & ] { PROFILE_SCOPE_DESCRIBE( "C.shard_build.svector" ); buildShards( shardS ); } );
    const double cResolve = timedMs( [ & ] { PROFILE_SCOPE_DESCRIBE( "C.resolve" ); resolvedC = resolveShards( shardS ); } );

    // ---- verify + report ----
    const bool match = ( resolvedA == resolvedB && resolvedB == resolvedC );
    std::printf( "resolved: A=%llu  B=%llu  C=%llu  %s\n", (unsigned long long)resolvedA, (unsigned long long)resolvedB, (unsigned long long)resolvedC, match ? "(all match ✓)" : "(MISMATCH!)" );

    prof::report();   // the real profiler: per-site time (+ PMC cycles when run with sudo)

    const double aMs = aBuild + aResolve;
    const double bMs = tBucket + bBuild + bResolve;
    const double cMs = tBucket + cBuild + cResolve;
    std::printf( "\nconvergence totals (%u threads, chrono):\n", T );
    std::printf( "  serial (A)                   %6.1f ms\n", aMs );
    std::printf( "  partition + std::vector (B)  %6.1f ms   (%.2fx vs serial)\n", bMs, aMs / bMs );
    std::printf( "  partition + rw::svector (C) %6.1f ms   (%.2fx vs serial)\n", cMs, aMs / cMs );
    std::printf( "  └─ shard_build: std::vector %.1f ms → rw::svector %.1f ms  (%.2fx, ~%zu fewer mallocs)\n", bBuild, cBuild, cBuild > 0 ? bBuild / cBuild : 0.0, D );
    return 0;
}
