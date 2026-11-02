#pragma once

// fileGraphStop.h: why the file graph's fold or adjacency gave up, and the exception that carries it.
// A stopped fold, or an adjacency past its edge limit, is a FAILED BUILD: memguard::guardedFileClosure and
// FileAdjacency::fromEdges throw FileGraphStopped instead of returning a partial store, so no reader can answer from one
// and none has to remember to check. There is no process-wide "a stop happened" slot, so a stop cannot outlive the build it
// stopped (an MCP server that released the index serves the next call). The catch sites are few and each one refuses
// in its own surface: main.cpp's dispatchMain (exit 5, one line), mcp.h's request envelope (an MCP error naming the stop)
// and the places that own a half-built state (mcpindex.h getIndex, quality.h loadRefTree). A background worker catches and
// writes nothing.

#include <cstdint>
#include <exception>

namespace rw
{

enum class FileGraphStop : std::uint8_t
{
    None,
    MemoryLimit,    // the fold read the footprint at or over the memory guard's hard limit
    Capacity,       // a 32-bit offset would have wrapped: payload words or adjacency edges past 2^32 - 1
    AllocFailure,   // std::bad_alloc inside the fold
};

class FileGraphStopped final : public std::exception
{
public:
    explicit FileGraphStopped( FileGraphStop why ) noexcept : why_( why ) {}
    FileGraphStop why() const noexcept { return why_; }
    const char*   what() const noexcept override { return "the file graph stopped: no answer from a partial store"; }

private:
    FileGraphStop why_;
};

} // namespace rw
