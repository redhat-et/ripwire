// alloccount.cpp — the heap-allocation instrument for the small-vector A/B. Compiled into the binary ONLY
// under `-DRIPWIRE_ALLOC_COUNT=ON`, which no shipped or gated build sets, so the normal binary does not
// contain a byte of this file.
//
// WHY A GLOBAL REPLACEMENT AND NOT A PER-CONTAINER ALLOCATOR. The question is "how many heap allocations
// did the conversion wave avoid", and the containers under test are map VALUES inside
// ankerl::unordered_dense — plumbing a counting allocator through that reaches into the vendored map and
// changes the thing being measured. Replacing the global operator new/delete pair measures the process
// instead: total allocations, total bytes, and peak live bytes.
//
// WHAT THE NUMBER MEANS, STATED HONESTLY. The absolute count is NOT attributable to the small-vector —
// it includes tree-sitter, every std::string in the symbol table, and the map's own bucket arrays. Only
// the DELTA BETWEEN ARMS is attributable, because every other allocation in the run is identical across
// arms by construction (same corpus, same code, same flags, one type alias different). bench/svectorab.py
// only ever reports the delta, and this comment is the reason.
//
// DETERMINISM. Counters are relaxed atomics: ripwire parses on several threads, and a non-atomic counter
// would both race (a G1 TSan finding) and undercount. Relaxed ordering is right — nothing reads a counter
// until the report at exit, which happens after every worker has joined.
//
// The report goes to STDERR. stdout carries the XML map, and a trailing report there would break every
// `>file` / `| xmllint` workflow and G4's well-formedness contract — the same rule test/pmccheck.sh
// enforces for the profile report.

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <new>

namespace
{

std::atomic<std::uint64_t> g_allocCount { 0 };
std::atomic<std::uint64_t> g_allocBytes { 0 };
std::atomic<std::uint64_t> g_freeCount { 0 };
std::atomic<std::uint64_t> g_liveBytes { 0 };
std::atomic<std::uint64_t> g_peakBytes { 0 };

// Every allocation is over-allocated by one 16-byte header holding its size, so operator delete can
// subtract the right number of bytes from the live total. 16 rather than 8 keeps the returned pointer
// 16-byte aligned, which is the platform's default new alignment on both targets.
constexpr std::size_t kHeader = 16;

void* countedAlloc( std::size_t bytes ) noexcept
{
    void* raw = std::malloc( bytes + kHeader );
    if( raw == nullptr )
    {
        return nullptr;
    }
    *static_cast<std::uint64_t*>( raw ) = std::uint64_t( bytes );
    g_allocCount.fetch_add( 1, std::memory_order_relaxed );
    g_allocBytes.fetch_add( bytes, std::memory_order_relaxed );
    const std::uint64_t live = g_liveBytes.fetch_add( bytes, std::memory_order_relaxed ) + bytes;
    // A relaxed CAS loop, not a plain store: two threads growing the peak at once must not lose the
    // larger value. This is the only place the counters interact.
    std::uint64_t seen = g_peakBytes.load( std::memory_order_relaxed );
    while( live > seen && !g_peakBytes.compare_exchange_weak( seen, live, std::memory_order_relaxed ) )
    {
    }
    return static_cast<char*>( raw ) + kHeader;
}

void countedFree( void* p ) noexcept
{
    if( p == nullptr )
    {
        return;
    }
    char* const         raw   = static_cast<char*>( p ) - kHeader;
    const std::uint64_t bytes = *reinterpret_cast<std::uint64_t*>( raw );
    g_freeCount.fetch_add( 1, std::memory_order_relaxed );
    g_liveBytes.fetch_sub( bytes, std::memory_order_relaxed );
    std::free( raw );
}

// Reported at static destruction, after every worker thread has joined.
struct Reporter
{
    ~Reporter()
    {
        std::fprintf( stderr,
                      "ALLOC_REPORT allocs=%llu bytes=%llu frees=%llu peak_live_bytes=%llu\n",
                      (unsigned long long) g_allocCount.load( std::memory_order_relaxed ),
                      (unsigned long long) g_allocBytes.load( std::memory_order_relaxed ),
                      (unsigned long long) g_freeCount.load( std::memory_order_relaxed ),
                      (unsigned long long) g_peakBytes.load( std::memory_order_relaxed ) );
    }
};
Reporter g_reporter;

}   // namespace

// ── the replacements. All of them, or the program mixes allocators and crashes on the first mismatched
//    delete: the sized and aligned forms are what a C++17/23 standard library actually calls. ──────────
void* operator new( std::size_t n )
{
    void* p = countedAlloc( n );
    if( p == nullptr ) { throw std::bad_alloc(); }      // the ONE throw seam CONTRIBUTING.md §3 permits
    return p;
}
void* operator new[]( std::size_t n )                                            { return ::operator new( n ); }
void* operator new( std::size_t n, const std::nothrow_t& ) noexcept              { return countedAlloc( n ); }
void* operator new[]( std::size_t n, const std::nothrow_t& ) noexcept            { return countedAlloc( n ); }

void operator delete( void* p ) noexcept                                         { countedFree( p ); }
void operator delete[]( void* p ) noexcept                                       { countedFree( p ); }
void operator delete( void* p, std::size_t ) noexcept                            { countedFree( p ); }
void operator delete[]( void* p, std::size_t ) noexcept                          { countedFree( p ); }
void operator delete( void* p, const std::nothrow_t& ) noexcept                  { countedFree( p ); }
void operator delete[]( void* p, const std::nothrow_t& ) noexcept                { countedFree( p ); }

// Over-aligned forms. std::malloc guarantees only __STDCPP_DEFAULT_NEW_ALIGNMENT__, so these route to
// aligned_alloc with the header folded into the alignment rather than into a fixed 16 bytes.
void* operator new( std::size_t n, std::align_val_t a )
{
    const std::size_t align = std::size_t( a ) < kHeader ? kHeader : std::size_t( a );
    const std::size_t total = ( ( n + align + align - 1 ) / align ) * align;
    void*             raw   = std::aligned_alloc( align, total );
    if( raw == nullptr ) { throw std::bad_alloc(); }
    *static_cast<std::uint64_t*>( raw ) = std::uint64_t( n );
    g_allocCount.fetch_add( 1, std::memory_order_relaxed );
    g_allocBytes.fetch_add( n, std::memory_order_relaxed );
    g_liveBytes.fetch_add( n, std::memory_order_relaxed );
    return static_cast<char*>( raw ) + align;
}
void* operator new[]( std::size_t n, std::align_val_t a )                        { return ::operator new( n, a ); }

void operator delete( void* p, std::align_val_t a ) noexcept
{
    if( p == nullptr ) { return; }
    const std::size_t align = std::size_t( a ) < kHeader ? kHeader : std::size_t( a );
    char* const       raw   = static_cast<char*>( p ) - align;
    g_freeCount.fetch_add( 1, std::memory_order_relaxed );
    g_liveBytes.fetch_sub( *reinterpret_cast<std::uint64_t*>( raw ), std::memory_order_relaxed );
    std::free( raw );
}
void operator delete[]( void* p, std::align_val_t a ) noexcept                   { ::operator delete( p, a ); }
void operator delete( void* p, std::size_t, std::align_val_t a ) noexcept        { ::operator delete( p, a ); }
void operator delete[]( void* p, std::size_t, std::align_val_t a ) noexcept      { ::operator delete( p, a ); }
