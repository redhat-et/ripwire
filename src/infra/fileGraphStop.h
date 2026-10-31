#pragma once

// fileGraphStop.h: why the file graph's fold or adjacency stopped, kept process-wide so every hard-line reading sees it.
// The stores in fileSetStore.h record a stop here and return a PARTIAL store; memguard::overHardLimit() reads this slot, so
// the CLI's hard line, the MCP per-request check and the verbs that fold a second time all refuse instead of answering from it.
// First stop wins. Tests clear it.

#include <atomic>
#include <cstdint>

namespace rw
{

enum class FileGraphStop : std::uint8_t
{
    None,
    MemoryLimit,    // the fold read the footprint at or over the memory guard's hard limit
    Capacity,       // a 32-bit offset would have wrapped: payload words or adjacency edges past 2^32 - 1
    AllocFailure,   // std::bad_alloc inside the fold
};

inline std::atomic<std::uint8_t>& fileGraphStopSlot() noexcept
{
    static std::atomic<std::uint8_t> slot{ 0 };
    return slot;
}
inline void fileGraphStopRecord( FileGraphStop why ) noexcept
{
    std::uint8_t none = 0;
    fileGraphStopSlot().compare_exchange_strong( none, static_cast<std::uint8_t>( why ), std::memory_order_relaxed );
}
inline FileGraphStop fileGraphStopped() noexcept { return static_cast<FileGraphStop>( fileGraphStopSlot().load( std::memory_order_relaxed ) ); }
inline void          fileGraphStopClear() noexcept { fileGraphStopSlot().store( 0, std::memory_order_relaxed ); }

} // namespace rw
