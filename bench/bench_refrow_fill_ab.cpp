// bench_refrow_fill_ab.cpp — is filling 5.9M rw::Reference rows bound by the TYPE or by the MACHINE?
//
// Build (the same standalone one-liner every bench in this directory uses — no CMake target, deliberately):
//   c++ -O2 -std=c++23 bench/bench_refrow_fill_ab.cpp -Isrc -Isrc/infra -Ithird_party -o /tmp/rw_refrow_fill
//   /tmp/rw_refrow_fill
//
// The ALLOCATOR REGIME is load-bearing here and the plain build above does not reproduce production.
// On macOS the real binary links src/largealloc.cpp, which routes every operator new >= 256 KiB through its
// own mmap and munmaps it on delete (CMakeLists.txt: RIPWIRE_LARGE_ALLOC, ON by default). Without it, macOS
// libmalloc KEEPS a freed 380 MB block resident -- which is the very thing largealloc.cpp exists to stop --
// so arm A gets handed warm pages back after rep 1 and stops being a cold-page arm at all. To measure the
// production regime, and to A/B it against the libmalloc one in the SAME binary:
//   c++ -O2 -std=c++23 bench/bench_refrow_fill_ab.cpp src/largealloc.cpp src/infra/diagnostics.cpp \
//       -Isrc -Isrc/infra -Ithird_party -o /tmp/rw_refrow_fill_la
//   /tmp/rw_refrow_fill_la                               # production route: fresh mmap per rep
//   RIPWIRE_TEST_LARGEALLOC=off /tmp/rw_refrow_fill_la   # route off, same binary, the only difference
// Add NO other allocator TU: alloccount.cpp and memceiling_new.cpp each replace the same functions and would
// make a THIRD regime. And note largealloc.cpp is never linked beside a sanitizer (ASan owns operator new),
// so this effect is INVISIBLE under asan/ripwire -- a false negative with a plausible-looking provenance.
//
// Read A - B FIRST (cold vs resident, within one run and one regime, needing no cross-run comparison), and
// arm A's absolute value second.
//
#include "model.h"
#include <chrono>
#include <cstdio>
#include <cstring>
#include <memory>
#include <thread>
#include <vector>

using Clock = std::chrono::steady_clock;
static double ms( Clock::duration d ) { return std::chrono::duration<double, std::milli>( d ).count(); }
#define FENCE( p ) __asm__ volatile( "" : : "r"( p ) : "memory" )

int main()
{
    const std::size_t n       = 5935104;
    const std::size_t bytes   = n * sizeof( rw::Reference );
    const unsigned    threads = std::max( 2u, std::thread::hardware_concurrency() );
    std::printf( "n=%zu sizeof(Reference)=%zu bytes=%zu (%.1f MB) threads=%u\n", n, sizeof( rw::Reference ), bytes, double( bytes ) / 1e6, threads );

    double best[ 6 ] = { 1e9, 1e9, 1e9, 1e9, 1e9, 1e9 };
    const char* label[ 6 ] = { "A cold pages, Reference ctor, 1 thread",
                               "B resident pages, Reference ctor, 1 thread",
                               "C cold pages, memset (bulk-store ceiling)",
                               "D resident pages, memset (bulk-store ceiling)",
                               "E cold pages, construct_at, N threads",
                               "F cold pages, memset NON-ZERO (true ceiling)" };

    for( int rep = 0; rep < 5; ++rep )
    {
        {
            const auto t0 = Clock::now();
            std::vector<rw::Reference> v( n );
            FENCE( v.data() );
            const auto t1 = Clock::now();
            best[ 0 ] = std::min( best[ 0 ], ms( t1 - t0 ) );

            v.clear();
            FENCE( v.data() );
            const auto t2 = Clock::now();
            v.resize( n );
            FENCE( v.data() );
            const auto t3 = Clock::now();
            best[ 1 ] = std::min( best[ 1 ], ms( t3 - t2 ) );
        }
        {
            auto* raw = static_cast<unsigned char*>( ::malloc( bytes ) );
            FENCE( raw );
            const auto t0 = Clock::now();
            std::memset( raw, 0, bytes );
            FENCE( raw );
            const auto t1 = Clock::now();
            best[ 2 ] = std::min( best[ 2 ], ms( t1 - t0 ) );

            const auto t2 = Clock::now();
            std::memset( raw, 1, bytes );
            FENCE( raw );
            const auto t3 = Clock::now();
            best[ 3 ] = std::min( best[ 3 ], ms( t3 - t2 ) );
            ::free( raw );
        }
        {
            auto* raw = static_cast<unsigned char*>( ::malloc( bytes ) );
            FENCE( raw );
            const auto t0 = Clock::now();
            std::memset( raw, 0xA5, bytes );
            FENCE( raw );
            const auto t1 = Clock::now();
            best[ 5 ] = std::min( best[ 5 ], ms( t1 - t0 ) );
            ::free( raw );
        }
        {
            auto* raw = static_cast<rw::Reference*>( ::malloc( bytes ) );
            FENCE( raw );
            const auto t0 = Clock::now();
            {
                std::vector<std::thread> pool;
                pool.reserve( threads );
                const std::size_t share = ( n + threads - 1 ) / threads;
                for( unsigned t = 0; t < threads; ++t )
                {
                    pool.emplace_back( [ & , t ]
                    {
                        const std::size_t from = t * share, to = std::min( n, from + share );
                        for( std::size_t i = from; i < to; ++i ) { std::construct_at( raw + i ); }
                    } );
                }
                for( std::thread& th : pool ) { th.join(); }
            }
            FENCE( raw );
            const auto t1 = Clock::now();
            best[ 4 ] = std::min( best[ 4 ], ms( t1 - t0 ) );
            std::destroy_n( raw, n );
            ::free( raw );
        }
    }
    for( int i = 0; i < 6; ++i ) { std::printf( "%-46s %7.2f ms  %7.1f GB/s\n", label[ i ], best[ i ], double( bytes ) / best[ i ] / 1e6 ); }
    std::printf( "A-F = %.2f ms  <- the prize against the ceiling for a NON-ZERO default pattern\n", best[ 0 ] - best[ 5 ] );
    std::printf( "E-F = %.2f ms  <- what a triviality change could add ON TOP of parallel construction\n", best[ 4 ] - best[ 5 ] );
    std::printf( "A-C = %.2f ms  <- the ENTIRE prize a triviality change could win on the production shape\n", best[ 0 ] - best[ 2 ] );
    std::printf( "A-E = %.2f ms  <- the prize for constructing the rows on the threads that fill them\n", best[ 0 ] - best[ 4 ] );
    return 0;
}
