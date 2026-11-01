#pragma once
// largealloc.h — EXPERIMENT (mem-reserve): on macOS, give every operator new of 256 KiB or more its own mmap
// region and munmap it on delete, so a freed large block returns its pages at once. The default zone keeps
// freed large blocks resident ("MALLOC_LARGE (empty)"), and ripwire's growth ladders and short-lived big
// arrays leave about half the peak footprint there (reports/mem-reserve.md). Included from main.cpp ONLY:
// replacement allocation functions may be defined in exactly one translation unit.
#if defined( __APPLE__ ) && !defined( __SANITIZE_ADDRESS__ ) && !defined( __SANITIZE_THREAD__ )
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <new>
#include <sys/mman.h>

namespace rw::largealloc
{
constexpr std::size_t kMinBytes = 256 * 1024;   // below this the zone's own small/medium paths are fine
constexpr std::size_t kHeader   = 16;           // region size, keeps the user pointer 16-byte aligned
constexpr std::size_t kPage     = 16384;
constexpr std::size_t kSlots    = std::size_t( 1 ) << 16;   // live large blocks at once: dozens in practice

// Which user pointers are ours: lock-free open addressing, 0 = never used, 1 = tombstone. A pointer whose
// low 14 bits are not kHeader cannot be ours (regions are page aligned), so delete of an ordinary block
// never reads the table.
inline std::atomic<std::uint64_t>* slots()
{
    static auto* t = static_cast<std::atomic<std::uint64_t>*>( ::mmap( nullptr, sizeof( std::uint64_t ) * kSlots, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0 ) );
    return t == MAP_FAILED ? nullptr : t;
}
inline std::size_t home( std::uint64_t p ) { return static_cast<std::size_t>( ( ( p >> 14 ) * 0x9E3779B97F4A7C15ull ) >> 40 ) & ( kSlots - 1 ); }
inline bool remember( std::uint64_t p )
{
    auto* t = slots();
    for( std::size_t h = t == nullptr ? kSlots : home( p ), n = 0; n < 4096; h = ( h + 1 ) & ( kSlots - 1 ), ++n )
    {
        std::uint64_t e = t[ h ].load( std::memory_order_relaxed );
        if( ( e == 0 || e == 1 ) && t[ h ].compare_exchange_strong( e, p ) )
        {
            return true;
        }
    }
    return false;
}
inline bool forget( std::uint64_t p )
{
    auto* t = slots();
    for( std::size_t h = t == nullptr ? kSlots : home( p ), n = 0; n < 4096; h = ( h + 1 ) & ( kSlots - 1 ), ++n )
    {
        std::uint64_t e = t[ h ].load( std::memory_order_relaxed );
        if( e == 0 )
        {
            return false;
        }
        if( e == p )
        {
            return t[ h ].compare_exchange_strong( e, 1 );
        }
    }
    return false;
}
}   // namespace rw::largealloc

void* operator new( std::size_t n )
{
    static const bool on = [] { const char* v = std::getenv( "RW_A" ); return v == nullptr || v[ 0 ] != '0'; }();
    if( n >= rw::largealloc::kMinBytes && on )
    {
        const std::size_t total = ( n + rw::largealloc::kHeader + rw::largealloc::kPage - 1 ) & ~( rw::largealloc::kPage - 1 );
        void*             b     = ::mmap( nullptr, total, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0 );
        if( b != MAP_FAILED )
        {
            *static_cast<std::size_t*>( b ) = total;
            void* p = static_cast<char*>( b ) + rw::largealloc::kHeader;
            if( rw::largealloc::remember( reinterpret_cast<std::uint64_t>( p ) ) )
            {
                return p;
            }
            ::munmap( b, total );   // table full: fall through to malloc
        }
    }
    if( void* p = std::malloc( n != 0 ? n : 1 ) )
    {
        return p;
    }
    throw std::bad_alloc();
}
void operator delete( void* p ) noexcept
{
    if( p == nullptr )
    {
        return;
    }
    if( ( reinterpret_cast<std::uintptr_t>( p ) & ( rw::largealloc::kPage - 1 ) ) == rw::largealloc::kHeader
        && rw::largealloc::forget( reinterpret_cast<std::uint64_t>( p ) ) )
    {
        void* b = static_cast<char*>( p ) - rw::largealloc::kHeader;
        ::munmap( b, *static_cast<std::size_t*>( b ) );
        return;
    }
    std::free( p );
}
void operator delete( void* p, std::size_t ) noexcept { operator delete( p ); }
#endif
