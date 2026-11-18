#pragma once

// memceiling.h — PROTOTYPE (lane M2, 2026-11-18), default OFF: a memory CEILING read at the allocator, so a run that grows past
// it inside a single loop the phase-boundary guard cannot see is refused instead of taking the machine down.
//
// WHY A SECOND LINE. memguard.h already holds a hard limit (65% of RAM), but it reads the footprint only at phase boundaries,
// in the crawl/parse workers and in the file graph's fold. On 2026-11-18 a run over llvm-project grew ~5 GB/s inside
// buildGraph's resolve loop (resolve.h derivesFromName: a breadth-first frontier with no visited set) and reached 149.7 GB
// before macOS killed it: nothing between "graph-tables" and "graph-end" reads memory, and one call can grow without bound.
// This line sits where every growth passes — operator new — so it sees inside any loop without a call site in it.
//
// THE READING. Every allocation of kLargeBytes or more reads the footprint (os::mem_footprint — macOS phys_footprint, Linux
// statm resident pages) BEFORE the block is taken, so the overshoot past the ceiling is at most the block that would cross it.
// Smaller allocations add to a per-thread byte count and read once per kSmallStrideBytes of allocation. Disarmed, the cost is
// one relaxed atomic load per operator new. Armed, the footprint reader is a task_info / procfs read into a stack buffer:
// it never allocates, so it is safe to call from inside operator new.
//
// THE REFUSAL. One stderr line, written with os::write from a stack buffer (no allocation, no stdio lock), then std::_Exit(5)
// — 5 is ripwire's memory-refusal exit everywhere (memguard.h's hard line). No destructor runs: nothing partial is persisted
// (the ingest cache is written by rename, so it is the old blob or none), and stdio buffers are NOT flushed, so a map still
// being assembled prints nothing. A verb that had already flushed part of its answer is said to be cut by the line itself.
// The first thread to cross writes the line; any other thread that crosses at the same time parks until the process ends.
//
// SERVERS. --mcp and --lsp do not arm it: its refusal ends the process, and a server must survive a refused request (the
// per-request hard line in memguard.h still applies there). MEMGUARD_DESIGN.md (lane M2) holds the server plan.
//
// DETERMINISM. It reads; it never changes what is computed. A run under the ceiling prints the same bytes armed or disarmed.
//
// THE KNOB. RIPWIRE_MEM_BUDGET_MB=<MiB>, a whole number of at least kFloorMiB. Unset or empty = off. Any other value refuses the
// run at startup (exit 1), as RIPWIRE_MAX_MEMORY does: a typo is never silently obeyed or silently ignored.
// Only translation units that replace operator new call onAllocate (largealloc.cpp, macOS); elsewhere it stays disarmed and
// the startup line says so.

#include <atomic>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <cstdlib>   // std::getenv, std::_Exit
#include <ctime>
#include <string_view>

#include "infra/envnumber.h"   // readEnvNumber: RIPWIRE_MEM_BUDGET_MB
#include "infra/os.h"   // rw::os::mem_footprint, rw::os::write, rw::os::nanosleep

namespace rw::memceiling
{

inline constexpr std::uint64_t kMiB              = 1024ull * 1024ull;
inline constexpr std::uint64_t kFloorMiB         = 64;                // memguard's own floor: below it a value is a typo
inline constexpr std::size_t   kLargeBytes       = 256 * 1024;        // largealloc's kMinBytes: these read on every call
inline constexpr std::uint64_t kSmallStrideBytes = 64ull * kMiB;      // per thread, small allocations between two readings
inline constexpr int           kRefusalExit      = 5;                 // the memory-refusal exit (memguard.h)

struct State
{
    std::atomic<std::uint64_t> budgetBytes{ 0 };          // 0 = disarmed
    std::atomic<std::uint64_t> budgetMiB{ 0 };            // as typed, for the refusal line
    std::atomic<bool>          refusing{ false };         // the first crossing thread owns the line
    std::atomic<const char*>   phase{ "ingest" };         // the last phase boundary passed (memstats::mark), a literal
};
inline constinit State g_state;

// the phase the refusal names: memstats::mark calls this at every boundary it marks (each call passes a string literal)
inline void notePhase( const char* literal ) noexcept
{
    g_state.phase.store( literal, std::memory_order_relaxed );
}

enum class Parse : std::uint8_t
{
    Unset,     // no variable, or an empty one: off
    Armed,     // a whole number of MiB at or over the floor
    Invalid,   // anything else: the caller refuses the run
};
struct Setting
{
    Parse         parse = Parse::Unset;
    std::uint64_t mib   = 0;
};
// RIPWIRE_MEM_BUDGET_MB, read once by main() before any thread exists
inline Setting readSetting() noexcept
{
    Setting         s;
    const EnvNumber n = readEnvNumber( "RIPWIRE_MEM_BUDGET_MB" );
    if( !n.set || n.text.empty() )
    {
        return s;
    }
    const std::uint64_t mib = n.value;
    if( !n.parsed || mib < kFloorMiB || mib > ( 1ull << 40 ) )
    {
        s.parse = Parse::Invalid;
        return s;
    }
    s.parse = Parse::Armed;
    s.mib   = mib;
    return s;
}

inline void arm( std::uint64_t mib ) noexcept
{
    g_state.budgetMiB.store( mib, std::memory_order_relaxed );
    g_state.budgetBytes.store( mib * kMiB, std::memory_order_release );
}

// ── the refusal: no allocation from here on ────────────────────────────────────────────────────────────────
struct LineBuffer
{
    char        text[ 640 ];
    std::size_t used = 0;
    void put( std::string_view s ) noexcept
    {
        for( const char c : s )
        {
            if( used < sizeof( text ) )
            {
                text[ used++ ] = c;
            }
        }
    }
    void putNumber( std::uint64_t n ) noexcept
    {
        char digits[ 24 ];
        const auto [ end, ec ] = std::to_chars( digits, digits + sizeof( digits ), n );
        put( std::string_view( digits, ec == std::errc() ? std::size_t( end - digits ) : 0 ) );
    }
};

[[noreturn]] inline void refuse( std::uint64_t footprint, std::size_t request ) noexcept
{
    if( g_state.refusing.exchange( true, std::memory_order_acq_rel ) )
    {
        for( ;; )   // another thread is writing the line and ending the process: wait for it, allocate nothing
        {
            const ::timespec park{ 1, 0 };
            (void)os::nanosleep( &park, nullptr );
        }
    }
    LineBuffer line;
    line.put( "ripwire: refused by the memory ceiling (RIPWIRE_MEM_BUDGET_MB=" );
    line.putNumber( g_state.budgetMiB.load( std::memory_order_relaxed ) );
    line.put( "): the footprint was " );
    line.putNumber( footprint / kMiB );
    line.put( " MiB and the next allocation (" );
    line.putNumber( ( std::uint64_t( request ) + kMiB - 1 ) / kMiB );
    line.put( " MiB) would pass it, after phase " );
    line.put( g_state.phase.load( std::memory_order_relaxed ) );
    line.put( " — the run stopped there and answers nothing (any output already printed above is cut, not complete); exit 5. "
              "Raise RIPWIRE_MEM_BUDGET_MB, or unset it to run without the ceiling\n" );
    std::size_t done = 0;
    while( done < line.used )
    {
        const auto n = os::write( 2, line.text + done, line.used - done );
        if( n <= 0 )
        {
            break;
        }
        done += std::size_t( n );
    }
    std::_Exit( kRefusalExit );
}

// operator new's hook: called with every request size before the block is taken
inline void onAllocate( std::size_t request ) noexcept
{
    const std::uint64_t budget = g_state.budgetBytes.load( std::memory_order_relaxed );
    if( budget == 0 )
    {
        return;
    }
    if( request < kLargeBytes )
    {
        thread_local constinit std::uint64_t sinceReading = 0;
        sinceReading += request;
        if( sinceReading < kSmallStrideBytes )
        {
            return;
        }
        sinceReading = 0;
    }
    const std::uint64_t footprint = os::mem_footprint();
    if( footprint != 0 && footprint + request > budget )
    {
        refuse( footprint, request );
    }
}

} // namespace rw::memceiling
