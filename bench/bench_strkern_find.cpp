// The crossover race behind rw::strkern::find's dispatch (src/infra/strkern.h kFindMemchrCutoff and the four-block loop), and its
// standing check: strkern::find must not be slower than std::string_view::find in ANY measured cell. Tables: bench/STRKERN_FIND.md.
//
// Build: c++ -O2 -std=c++23 bench/bench_strkern_find.cpp -Isrc -Isrc/infra -o /tmp/ripwire_find_ab
//        (x86-64: add -march=x86-64-v3, the shipped floor; on arm64 macOS the same slice runs under Rosetta 2 with
//        `-arch x86_64 -march=x86-64-v3`, which times the AVX2 path but not native x86 hardware)
// Run:   /tmp/ripwire_find_ab [repoRoot]        (default "."; reads every .h/.cpp/.md under src/ and docs/)
//
// CELLS: haystack 4..4096 bytes in powers of two, plus "file" (whole files), x needle length 1/2/3/4/8/16. A cell's haystacks
// are cuts at deterministic offsets from a 1 MiB pool of real text (2 MiB of input per cell, so the cuts are cache-hot as a short
// string a caller probes is). RUNTIME needles are cuts of the whole corpus (64 per length), so first bytes are as common as they
// are in code and docs, and some needles occur; LITERAL needles are one fixed literal per length, the shapes call sites search for
// (several start with a byte that is rare in code, where std's memchr-led search is at its best). The operation is the find-all walk
// a scan does: find, then find again from hit + 1, until npos.
//
// ARMS, run ALTERNATING (the first arm rotates each round), ns per find call:
//   std     std::string_view::find( needle, from )
//   kernel  strkern::findNeedle — the first/last-byte block kernel alone, at every size (runtime needles only)
//   find    strkern::find — the shipped dispatch (the Literal overload in the literal table)
// All arms must return the same hits (summed positions) in every cell before any time is printed; a mismatch exits 2.
//
// TIMING: thread CPU time (CLOCK_THREAD_CPUTIME_ID), so a round the scheduler preempted does not count the time it sat out; the
// cell's number is the BEST of 9 rounds per arm, the least-disturbed run of each (the M2 this was tuned on runs other lanes' builds).
// THE CHECK: a cell where find / std > kSlowerThanStd prints SLOWER and the run exits 1 — but only after the cell was re-raced
// kAttempts times and was over the bar EVERY time, so one disturbed race does not fail a cell and a real regression still does.
// On x86-64 (native, or translated by Rosetta 2) the run prints its SLOWER cells but exits 0 until the AVX2 dispatch is tuned.

#include "infra/strkern.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>
#if defined( __APPLE__ )
    #include <sys/sysctl.h>
#endif

namespace sk = rw::strkern;

namespace
{

constexpr double kSlowerThanStd = 1.10;
constexpr int    kRounds        = 9;
constexpr int    kAttempts      = 3;

std::vector<std::string> readCorpus( const std::filesystem::path& root )
{
    std::vector<std::string> files;
    for( const char* sub : { "src", "docs" } )
    {
        std::error_code ec;
        for( auto it = std::filesystem::recursive_directory_iterator( root / sub, ec ); !ec && it != std::filesystem::recursive_directory_iterator(); it.increment( ec ) )
        {
            const std::string ext = it->path().extension().string();
            if( !it->is_regular_file() || ( ext != ".h" && ext != ".cpp" && ext != ".md" ) ) { continue; }
            std::ifstream in( it->path(), std::ios::binary );
            std::stringstream ss;
            ss << in.rdbuf();
            files.push_back( ss.str() );
        }
    }
    std::sort( files.begin(), files.end() );   // directory order is not deterministic; the cells must be
    return files;
}

struct Lcg
{
    std::uint64_t s;
    std::uint64_t next() { s = s * 6364136223846793005ull + 1442695040888963407ull; return s >> 17; }
};

// Under Rosetta 2 the thread CPU clock does not tick in nanoseconds (it reads 0.04 ns for a find), so a translated run times with
// the monotonic wall clock instead and says so in its header line.
bool underRosetta()
{
#if defined( __APPLE__ ) && defined( __x86_64__ )
    int translated = 0;
    std::size_t size = sizeof translated;
    return sysctlbyname( "sysctl.proc_translated", &translated, &size, nullptr, 0 ) == 0 && translated == 1;
#else
    return false;
#endif
}
const bool kWallClock = underRosetta();

double threadNs()
{
    timespec ts{};
    clock_gettime( kWallClock ? CLOCK_MONOTONIC : CLOCK_THREAD_CPUTIME_ID, &ts );
    return double( ts.tv_sec ) * 1e9 + double( ts.tv_nsec );
}

// a find-all walk with `f` over every haystack; `needleOf( i )` is haystack i's needle. Returns the sum of ( hit + 1 ) so the arms
// can be compared, and counts the calls.
template<class F, class NeedleOf>
std::uint64_t walk( const std::vector<std::string_view>& hays, NeedleOf&& needleOf, F&& f, std::uint64_t& calls )
{
    std::uint64_t sum = 0;
    for( std::size_t i = 0; i < hays.size(); ++i )
    {
        const std::string_view h = hays[ i ];
        const auto             n = needleOf( i );
        for( std::size_t at = f( h, n, 0 ); ; at = f( h, n, at + 1 ) )
        {
            ++calls;
            if( at == std::string_view::npos ) { break; }
            sum += at + 1;
        }
    }
    return sum;
}

struct CellResult
{
    std::array<double, 3> ns{};      // best-of-kRounds ns per call, per arm (arm 0 = std)
    int                   attempts = 0;
    bool                  slower   = false;
    bool                  mismatch = false;
};

// Race K arms (`run( arm, calls )` walks the cell with arm `arm` and returns its hit sum), the find arm being `findArm`.
template<std::size_t K, class Run>
CellResult race( Run&& run, std::size_t findArm )
{
    CellResult r;
    for( int attempt = 1; attempt <= kAttempts; ++attempt )
    {
        std::array<double, K>        best;
        std::array<std::uint64_t, K> sums{};
        best.fill( 1e300 );
        for( int round = 0; round < kRounds; ++round )
        {
            for( std::size_t k = 0; k < K; ++k )
            {
                const std::size_t arm   = ( k + std::size_t( round ) ) % K;
                std::uint64_t     calls = 0;
                const double      t0    = threadNs();
                sums[ arm ]             = run( arm, calls );
                best[ arm ]             = std::min( best[ arm ], ( threadNs() - t0 ) / double( calls ) );
            }
        }
        r.attempts = attempt;
        for( std::size_t a = 1; a < K; ++a ) { r.mismatch = r.mismatch || sums[ a ] != sums[ 0 ]; }
        for( std::size_t a = 0; a < K; ++a ) { r.ns[ a ] = best[ a ]; }
        r.slower = best[ findArm ] / best[ 0 ] > kSlowerThanStd;
        if( !r.slower || r.mismatch ) { break; }
    }
    return r;
}

const char* hayName( std::size_t hay, char ( &buf )[ 24 ] )
{
    if( hay == 0 ) { return "file"; }
    std::snprintf( buf, sizeof buf, "%zu", hay );
    return buf;
}

// a cell's haystacks: whole files (hay == 0), or cuts of `hay` bytes from the first files holding 1 MiB, read twice over per
// round — a short string a caller probes is cache-hot, and a cut that missed to DRAM would time the miss, not the find
std::vector<std::string_view> haysFor( const std::vector<std::string>& corpus, std::size_t pool, std::size_t hay, Lcg& rng )
{
    std::vector<std::string_view> hays;
    if( hay == 0 )
    {
        for( const auto& f : corpus ) { hays.emplace_back( f ); }
        return hays;
    }
    const std::size_t want = std::max<std::size_t>( 4000, ( 2u << 20 ) / hay );
    while( hays.size() < want )
    {
        const std::string& f = corpus[ rng.next() % pool ];
        if( f.size() >= hay ) { hays.emplace_back( f.data() + rng.next() % ( f.size() - hay + 1 ), hay ); }
    }
    return hays;
}

// One literal cell: std's h.find( LIT ) against strkern::find( h, LIT ) — the Literal overload, a compile-time length. The macro
// keeps LIT a literal at both call sites (a function parameter would be an array reference, which the Literal overload refuses).
#define RIPWIRE_LITERAL_CELL( HAYS, LIT )                                                                                                       \
    race<2>(                                                                                                                                    \
        [ & ]( std::size_t arm, std::uint64_t& calls )                                                                                          \
        {                                                                                                                                       \
            const auto one = []( std::size_t ) { return 0; };                                                                                   \
            return arm == 0 ? walk( HAYS, one, []( std::string_view h, int, std::size_t from ) { return h.find( LIT, from ); }, calls )        \
                            : walk( HAYS, one, []( std::string_view h, int, std::size_t from ) { return sk::find( h, LIT, from ); }, calls ); \
        },                                                                                                                                      \
        1 )

}   // namespace

int main( int argc, char** argv )
{
    const std::vector<std::string> corpus = readCorpus( argc > 1 ? argv[ 1 ] : "." );
    std::size_t bytes = 0;
    for( const auto& f : corpus ) { bytes += f.size(); }
    if( corpus.empty() || bytes < ( 1u << 20 ) ) { std::fprintf( stderr, "corpus too small (%zu files, %zu bytes)\n", corpus.size(), bytes ); return 2; }
    std::printf( "corpus: %zu files, %zu bytes; strkern path %s; best of %d rounds, %s ns per call; check: find/std <= %.2f in every cell"
                 " (a cell over it is re-raced, up to %d races)\n",
                 corpus.size(), bytes, sk::kPathName, kRounds, kWallClock ? "wall-clock (Rosetta 2)" : "thread CPU", kSlowerThanStd, kAttempts );

    std::size_t pool = 0;   // the first files of the sorted corpus that hold 1 MiB
    for( std::size_t poolBytes = 0; pool < corpus.size() && poolBytes < ( 1u << 20 ); ++pool ) { poolBytes += corpus[ pool ].size(); }

    const auto stdFind    = []( std::string_view h, std::string_view n, std::size_t from ) { return h.find( n, from ); };
    const auto kernelFind = []( std::string_view h, std::string_view n, std::size_t from ) -> std::size_t
    {
        if( from > h.size() ) { return std::string_view::npos; }
        const std::size_t left = h.size() - from, at = sk::findNeedle( h.data() + from, left, n.data(), n.size() );
        return at == left ? std::string_view::npos : from + at;
    };
    const auto shippedFind = []( std::string_view h, std::string_view n, std::size_t from ) { return sk::find( h, n, from ); };

    int  slower = 0;
    char buf[ 24 ];
    std::printf( "RUNTIME needles\n%-6s %3s %9s %9s %9s %8s %8s %3s\n", "hay", "m", "std ns", "kernel ns", "find ns", "kern/std", "find/std", "try" );
    for( const std::size_t hay : { 4ul, 8ul, 16ul, 32ul, 64ul, 128ul, 256ul, 512ul, 1024ul, 2048ul, 4096ul, 0ul } )
    {
        Lcg rng{ 0x5EED0000ull + hay };
        const std::vector<std::string_view> hays = haysFor( corpus, pool, hay, rng );
        for( const std::size_t m : { 1ul, 2ul, 3ul, 4ul, 8ul, 16ul } )
        {
            std::vector<std::string_view> needles;
            while( needles.size() < 64 )
            {
                const std::string& f = corpus[ rng.next() % corpus.size() ];
                if( f.size() > m ) { needles.emplace_back( f.data() + rng.next() % ( f.size() - m ), m ); }
            }
            const auto       needleOf = [ & ]( std::size_t i ) { return needles[ i % needles.size() ]; };
            const CellResult r        = race<3>(
                [ & ]( std::size_t arm, std::uint64_t& calls )
                {
                    return arm == 0 ? walk( hays, needleOf, stdFind, calls ) : arm == 1 ? walk( hays, needleOf, kernelFind, calls ) : walk( hays, needleOf, shippedFind, calls );
                },
                2 );
            if( r.mismatch ) { std::fprintf( stderr, "MISMATCH hay=%zu m=%zu\n", hay, m ); return 2; }
            slower += r.slower ? 1 : 0;
            std::printf( "%-6s %3zu %9.2f %9.2f %9.2f %8.2f %8.2f %3d%s\n", hayName( hay, buf ), m, r.ns[ 0 ], r.ns[ 1 ], r.ns[ 2 ], r.ns[ 1 ] / r.ns[ 0 ],
                         r.ns[ 2 ] / r.ns[ 0 ], r.attempts, r.slower ? "  SLOWER" : "" );
        }
    }

    std::printf( "LITERAL needles: std h.find( \"lit\" ) vs strkern::find( h, \"lit\" )\n%-6s %3s %-18s %9s %9s %8s %3s\n", "hay", "m", "literal", "std ns",
                 "find ns", "find/std", "try" );
    for( const std::size_t hay : { 4ul, 8ul, 16ul, 32ul, 64ul, 128ul, 256ul, 512ul, 1024ul, 4096ul, 0ul } )
    {
        Lcg rng{ 0x11700000ull + hay };
        const std::vector<std::string_view> hays = haysFor( corpus, pool, hay, rng );
        const auto                          row  = [ & ]( const char* lit, std::size_t m, const CellResult& r )
        {
            if( r.mismatch ) { std::fprintf( stderr, "MISMATCH literal hay=%zu %s\n", hay, lit ); std::exit( 2 ); }
            slower += r.slower ? 1 : 0;
            std::printf( "%-6s %3zu %-18s %9.2f %9.2f %8.2f %3d%s\n", hayName( hay, buf ), m, lit, r.ns[ 0 ], r.ns[ 1 ], r.ns[ 1 ] / r.ns[ 0 ], r.attempts,
                         r.slower ? "  SLOWER" : "" );
        };
        row( "(", 1, RIPWIRE_LITERAL_CELL( hays, "(" ) );
        row( "::", 2, RIPWIRE_LITERAL_CELL( hays, "::" ) );
        row( "]]>", 3, RIPWIRE_LITERAL_CELL( hays, "]]>" ) );
        row( "<!--", 4, RIPWIRE_LITERAL_CELL( hays, "<!--" ) );
        row( "#include", 8, RIPWIRE_LITERAL_CELL( hays, "#include" ) );
        row( "std::string_view", 16, RIPWIRE_LITERAL_CELL( hays, "std::string_view" ) );
    }
    std::printf( "%s: %d cell(s) where strkern::find is slower than std::string_view::find by more than %.0f %% in all %d races\n", slower ? "FAIL" : "PASS",
                 slower, ( kSlowerThanStd - 1 ) * 100, kAttempts );
    // x86-64 REPORTS and does not gate yet: its dispatch is NEON's carried over block for block, not tuned from native x86 numbers
    // (the follow-up STRKERN-X86-TUNE does that from CI's table, then turns this into a gate). A Rosetta 2 run is x86 too, and is
    // not x86 hardware at all: it times Rosetta's emulation of the 256-bit compares and pmovmskb.
#if defined( __x86_64__ ) || defined( _M_X64 )
    if( slower )
    {
        std::printf( "x86-64%s: report-only until the AVX2 dispatch is tuned from native numbers; this exit is 0\n", kWallClock ? " (Rosetta 2)" : "" );
        return 0;
    }
#endif
    return slower ? 1 : 0;
}
