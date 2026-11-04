#pragma once
// largealloc.h — the route behind src/largealloc.cpp: a block of kMinBytes or more gets its own mmap region and
// goes back to the OS at once on delete. Only the mechanism lives here (no replaced operator), so
// test/largeallocfix/largealloc_test.cpp can drive it with a tiny table. Why it exists: largealloc.cpp.
#include <atomic>
#include <cstddef>
#include <cstdint>
#include "infra/os.h" // os::vm_map / vm_unmap

namespace rw::largealloc
{
constexpr std::size_t kMinBytes = 256 * 1024; // below this the zone's small and medium paths keep working as they do
constexpr std::size_t kHeader = 16; // holds the region size; 16 keeps the user pointer at the default new alignment
constexpr std::size_t kRoundTo = 16384; // the largest page size of a target (arm64 macOS); on 4 KiB pages it only rounds up
constexpr std::size_t kPageFilter = 4095; // regions start on a page of at least 4 KiB, whatever the architecture
constexpr std::size_t kMaxRouted = std::size_t( -1 ) / 2; // keeps the rounding below from wrapping; malloc then refuses the size

// Which user pointers are routed: lock-free open addressing over the address alone. 0 = never used, 1 = free again.
// A slot never returns to 0, so a probe that stops at 0 cannot have skipped a live pointer. Only the block's owner
// forgets it, and the address cannot be mapped again until after the forget, so a pointer is in the table at most once.
// Full, or ProbeLimit slots busy from its home: remember() says no and the block comes from malloc, as a smaller one
// would; nothing is lost but that block's early return to the OS.
template<std::size_t Slots, std::size_t ProbeLimit>
class BlockTable
{
    static_assert( ( Slots & ( Slots - 1 ) ) == 0 );
    std::atomic<std::uint64_t> m_slots[Slots] {};

    static constexpr std::size_t home( std::uint64_t p ) noexcept
    {
        return static_cast<std::size_t>( ( ( p >> 12 ) * 0x9E3779B97F4A7C15ull ) >> 32 ) & ( Slots - 1 );
    }

public:
    bool remember( std::uint64_t p ) noexcept
    {
        std::size_t h = home( p );
        for( std::size_t n = 0; n < ProbeLimit; ++n, h = ( h + 1 ) & ( Slots - 1 ) )
        {
            std::uint64_t e = m_slots[h].load( std::memory_order_relaxed );
            if( ( e == 0 || e == 1 ) && m_slots[h].compare_exchange_strong( e, p ) )
            {
                return true;
            }
        }
        return false;
    }
    bool forget( std::uint64_t p ) noexcept
    {
        std::size_t h = home( p );
        for( std::size_t n = 0; n < ProbeLimit; ++n, h = ( h + 1 ) & ( Slots - 1 ) )
        {
            const std::uint64_t e = m_slots[h].load( std::memory_order_relaxed );
            if( e == 0 )
            {
                return false;
            }
            if( e == p )
            {
                m_slots[h].store( 1 );
                return true;
            }
        }
        return false;
    }
};

// nullptr = not routed (too small, too large, mmap refused, table busy): the caller falls back to malloc.
template<class Table>
inline void* allocate( Table& table, std::size_t n ) noexcept
{
    if( n < kMinBytes || n > kMaxRouted )
    {
        return nullptr;
    }
    const std::size_t total = ( n + kHeader + kRoundTo - 1 ) & ~( kRoundTo - 1 );
    void* b = os::vm_map( total );
    if( b == nullptr )
    {
        return nullptr;
    }
    *static_cast<std::size_t*>( b ) = total;
    char* p = static_cast<char*>( b ) + kHeader;
    if( table.remember( reinterpret_cast<std::uint64_t>( p ) ) )
    {
        return p;
    }
    os::vm_unmap( b, total );
    return nullptr;
}

// true = p was routed and is unmapped. Any other block returns false without the table being read in most cases: a
// routed pointer sits exactly kHeader into a page, so only 1 in 256 of the 16-byte-aligned ordinary pointers probes.
template<class Table>
inline bool release( Table& table, void* p ) noexcept
{
    if( ( reinterpret_cast<std::uintptr_t>( p ) & kPageFilter ) != kHeader || !table.forget( reinterpret_cast<std::uint64_t>( p ) ) )
    {
        return false;
    }
    void* b = static_cast<char*>( p ) - kHeader;
    os::vm_unmap( b, *static_cast<std::size_t*>( b ) );
    return true;
}
} // namespace rw::largealloc
