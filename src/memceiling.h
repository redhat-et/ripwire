#pragma once

// memceiling.h — the memory guard's ALLOCATOR LINE (lane M2, 2026-11-18; ON by default, owner 2026-11-18 "On by default"):
// the guard's hard limit, read at operator new, so a run that grows past it inside a single loop the phase-boundary readings
// cannot see is refused instead of taking the machine down.
//
// WHY A SECOND READING SITE. memguard.h holds the hard limit (65% of RAM, or --max-memory / RIPWIRE_MAX_MEMORY), but it reads
// the footprint only at phase boundaries, in the crawl/parse workers and in the file graph's fold. On 2026-11-18 a run over
// llvm-project grew ~5 GB/s inside buildGraph's resolve loop (resolve.h derivesFromName: a breadth-first frontier with no
// visited set) and reached 149.7 GB before macOS killed it: nothing between "graph-tables" and "graph-end" reads memory, and
// one call can grow without bound. This line sits where every growth passes — operator new — so it sees inside any loop
// without a call site in it.
//
// ONE KNOB, ONE EXIT CODE. The ceiling IS the guard's hard limit unless RIPWIRE_MEM_BUDGET_MB says otherwise:
//   neither set                      ceiling = 65% of min( RAM, cgroup memory.max )  (memguard's default)
//   --max-memory / RIPWIRE_MAX_MEMORY ceiling = that limit (the flag wins over the variable, as it always has)
//   RIPWIRE_MEM_BUDGET_MB=<MiB>      ceiling = that many MiB, for this line alone; memguard's own lines keep their limit
//   RIPWIRE_MEM_BUDGET_MB=0          this line is off; memguard's own lines are unchanged
//   machine memory unknown           off, as memguard's footprint cap is
// A refusal exits 5, the memory refusal everywhere in ripwire (memguard's hard line, a stopped fold).
//
// ONE LIMIT, BUT NOT THE SAME QUANTITY — say this rather than "folded into the guard's limit" (owner ruling 102,
// 2026-11-20). The LIMIT and the KNOBS are shared, as above. The quantity measured against them is not:
//   this line            os::mem_footprint()      — THIS PROCESS's footprint, and nothing else
//   memguard's own lines  measuredFootprint()     — max( that, the cgroup v2 leaf's unreclaimable charge ), memguard.h
// So on a Linux leaf with a finite memory.max, shared with other processes, this line can admit an allocation
// after the leaf's charge has already passed the limit; the leaf case is caught at memguard's phase boundaries
// only. That is a deliberate narrowing of the claim, not an oversight, and the reasoning is: what this line
// exists to catch is THIS process growing without bound inside one loop (buildGraph's resolve frontier, ~5 GB/s
// on 2026-11-18), and the quantity that grows there is exactly the process footprint it reads. The leaf term
// would have to be read from inside operator new, where os::mem_cgroup_unreclaimable() cannot go as written —
// it allocates two std::strings and does three procfs reads per call — and it is not exercisable on macOS
// (0 there) nor on a stock CI runner (memguardcheck's (B24) arm already SKIPs for want of such a leaf). It
// lands only behind a gate that can actually run it.
//
// THE OVERSHOOT. memguard used to disclose a run whose transient peak passed the limit and fell back before the next reading
// (owner 2026-11-01: disclosed, not enforced). An operator-new allocation can no longer do that: the line reads BEFORE the
// block is taken. What remains is memory this line cannot see — malloc called directly (tree-sitter), mmap, and up to
// kSmallStrideBytes per thread of small allocations between readings — and memguard's memory_peak= disclosure still covers it.
//
// THE READING. Every allocation of kLargeBytes or more reads the footprint (os::mem_footprint — macOS phys_footprint, Linux
// statm resident pages, Windows commit charge) BEFORE the block is taken. Smaller allocations add to a per-thread byte count
// and read once per kSmallStrideBytes of allocation. Disarmed, the cost is one relaxed atomic load per operator new. The
// readers never allocate (a Mach call, a procfs read into a stack buffer, GetProcessMemoryInfo), so they are safe inside
// operator new. RIPWIRE_STATS prints how many readings a run took (`[mem] ceiling`, memstats.h).
//
// A READING THE OS CANNOT GIVE is a degrade path, not a pass: every reader answers 0 when it fails (a failed task_info,
// an unreadable /proc/self/statm), and that allocation is then admitted UNCHECKED. It is disclosed on stderr the first
// time it happens and counted in `[mem] ceiling unreadable=`, so it is never a silent zero (noteUnreadable).
//
// THE REFUSAL. One stderr line, written with os::write from a stack buffer (no allocation, no stdio lock), then std::_Exit(5).
// No destructor runs: nothing partial is persisted (the ingest cache is written by rename, so it is the old blob or none), and
// stdio buffers are NOT flushed, so a map still being assembled prints nothing. A verb that had already flushed part of its
// answer is said to be cut by the line itself. The first thread to cross writes the line; any other thread that crosses at
// the same time parks until the process ends.
//
// ONE REGION WHERE IT DOES NOT REFUSE. An edit verb commits the file with atomicWrite and THEN rebuilds the index
// for its post-check. A refusal there would end the process with the edit already on disk and no receipt, and a
// caller that retries can insert twice — so the line is suspended for exactly that region, a crossing inside it
// is recorded instead of fatal, and the receipt discloses it (`memory_ceiling`). Suspension, below, holds the
// mechanism, the three properties it guarantees and the cost (owner ruling 101, 2026-11-20).
//
// SERVERS. --mcp and --lsp do not arm it: its refusal ends the process, and a server must survive a refused request (the
// per-request hard line in memguard.h still applies there). The follow-up — the index built in a child process under this
// line — is in lane M2's MEMGUARD_DESIGN.md.
//
// DETERMINISM. It reads; it never changes what is computed. A run under the ceiling prints the same bytes armed or off
// (test/memceilingcheck.sh D).
//
// The hook lives in the one translation unit that replaces operator new: largealloc.cpp (macOS) or memceiling_new.cpp
// (elsewhere); a build that links neither (RIPWIRE_ALLOC_COUNT) leaves the line disarmed, and an explicit
// RIPWIRE_MEM_BUDGET_MB says so on stderr.

#include <atomic>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <cstdlib>   // std::_Exit
#include <ctime>
#include <string_view>

#include "infra/envnumber.h"   // readEnvNumber: RIPWIRE_MEM_BUDGET_MB
#include "infra/os.h"          // rw::os::mem_footprint, rw::os::write, rw::os::nanosleep

namespace rw::memceiling
{

inline constexpr std::uint64_t kMiB              = 1024ull * 1024ull;
inline constexpr std::uint64_t kFloorMiB         = 64;                // memguard's own floor: below it a value is a typo
inline constexpr std::size_t   kLargeBytes       = 256 * 1024;        // largealloc's kMinBytes: these read on every call
inline constexpr std::uint64_t kSmallStrideBytes = 64ull * kMiB;      // per thread, small allocations between two readings
inline constexpr int           kRefusalExit      = 5;                 // the memory-refusal exit (memguard.h)
inline constexpr std::size_t   kLabelBytes       = 96;

struct State
{
    std::atomic<std::uint64_t> budgetBytes{ 0 };          // 0 = disarmed
    std::atomic<bool>          refusing{ false };         // the first crossing thread owns the line
    std::atomic<const char*>   phase{ "ingest" };         // the last phase boundary passed (memstats::mark), a literal
    std::atomic<std::uint64_t> readings{ 0 };             // footprint readings taken (RIPWIRE_STATS)
    std::atomic<std::uint64_t> largeReadings{ 0 };        // of which on a large allocation
    std::atomic<std::uint64_t> unreadable{ 0 };           // of which the OS could not answer: admitted UNCHECKED (noteUnreadable)
    std::atomic<bool>          saidUnreadable{ false };   // the one-per-run disclosure of that degrade path
    std::atomic<std::uint32_t> suspendDepth{ 0 };         // >0 = inside a post-write region: a crossing is RECORDED, never fatal (Suspension)
    std::atomic<std::uint64_t> admitted{ 0 };             // crossings admitted because the line was suspended (0 = the line never bent)
    std::atomic<std::uint64_t> admittedPeak{ 0 };         // the largest footprint admitted that way, bytes
    char                       label[ kLabelBytes ]{};    // the limit as the refusal names it, written once by arm()
    std::size_t                labelSize = 0;
};
inline constinit State g_state;

// the phase the refusal names: memstats::mark calls this at every boundary it marks (each call passes a string literal)
inline void notePhase( const char* literal ) noexcept
{
    g_state.phase.store( literal, std::memory_order_relaxed );
}

enum class Parse : std::uint8_t
{
    Unset,     // no variable, or an empty one: the ceiling is memguard's hard limit
    Off,       // RIPWIRE_MEM_BUDGET_MB=0: this line is off
    Armed,     // a whole number of MiB at or over the floor: the ceiling for this line alone
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
    if( n.parsed && mib == 0 )
    {
        s.parse = Parse::Off;
        return s;
    }
    if( !n.parsed || mib < kFloorMiB || mib > ( 1ull << 40 ) )
    {
        s.parse = Parse::Invalid;
        return s;
    }
    s.parse = Parse::Armed;
    s.mib   = mib;
    return s;
}

// main(), once, before any thread: the ceiling in bytes (0 = off) and how the refusal names it ("RIPWIRE_MEM_BUDGET_MB=4000",
// "--max-memory=8192M", "the default 65% of RAM, 31949M")
inline void arm( std::uint64_t bytes, std::string_view label ) noexcept
{
    const std::size_t n = label.size() < kLabelBytes ? label.size() : kLabelBytes;
    for( std::size_t i = 0; i < n; ++i )
    {
        g_state.label[ i ] = label[ i ];
    }
    g_state.labelSize = n;
    g_state.budgetBytes.store( bytes, std::memory_order_release );
}
inline std::uint64_t budgetBytes() noexcept { return g_state.budgetBytes.load( std::memory_order_relaxed ); }

// ── the refusal: no allocation from here on ────────────────────────────────────────────────────────────────
struct LineBuffer
{
    char        text[ 768 ];
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

// the one write both lines below use: os::write to fd 2 until the buffer is out, no stdio lock, no allocation
inline void writeLine( const LineBuffer& line ) noexcept
{
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
}

// THE SILENT ZERO. os::mem_footprint() answers 0 when the OS cannot say (a failed task_info on macOS, an unreadable
// /proc/self/statm on Linux). The allocation is then admitted UNCHECKED — refusing every run on a host whose reader is
// unavailable would be far worse than not checking — and that is a degrade path, so it is DISCLOSED rather than silent:
// one stderr line the first time, and a count for RIPWIRE_STATS (`[mem] ceiling unreadable=`) so a run that admitted
// unchecked allocations says how many. The line is written with the same stack buffer and os::write the refusal uses,
// because DISCLOSE's handler formats and can allocate, and nothing inside operator new may do that.
inline void noteUnreadable() noexcept
{
    g_state.unreadable.fetch_add( 1, std::memory_order_relaxed );
    if( g_state.saidUnreadable.exchange( true, std::memory_order_acq_rel ) )
    {
        return;   // said once per run: the hot path must not write a line per allocation
    }
    LineBuffer line;
    line.put( "ripwire: the memory ceiling (" );
    line.put( std::string_view( g_state.label, g_state.labelSize ) );
    line.put( ") cannot read this process's footprint — the OS reading is unavailable, so this allocation is admitted "
              "UNCHECKED and the ceiling refuses nothing while that lasts (the memory guard's own phase-boundary lines "
              "still apply). RIPWIRE_STATS counts them as `[mem] ceiling unreadable=`\n" );
    writeLine( line );
}

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
    line.put( "ripwire: refused by the memory ceiling (" );
    line.put( std::string_view( g_state.label, g_state.labelSize ) );
    line.put( "): the footprint was " );
    line.putNumber( footprint / kMiB );
    line.put( " MiB and the next allocation (" );
    line.putNumber( ( std::uint64_t( request ) + kMiB - 1 ) / kMiB );
    line.put( " MiB) would pass it, after phase " );
    line.put( g_state.phase.load( std::memory_order_relaxed ) );
    line.put( " — the run stopped there and answers nothing (any output already printed above is cut, not complete); exit 5. "
              "Raise the limit (--max-memory, RIPWIRE_MAX_MEMORY, or RIPWIRE_MEM_BUDGET_MB for this line alone), "
              "or set RIPWIRE_MEM_BUDGET_MB=0 to run without the ceiling\n" );
    writeLine( line );
    std::_Exit( kRefusalExit );
}

// ── THE POST-WRITE SUSPENSION (owner ruling 101, 2026-11-20) ───────────────────────────────────────────────
// A refusal ends the process with std::_Exit(5). That is the right answer for a run that has answered nothing
// — and the WRONG answer once an edit verb has already committed a file to disk: the edit is applied, no
// receipt is reported, and a caller that retries may apply the same insertion twice. mcpedit.h says it in as
// many words about the memory guard's own stop: "an agent that believes it inserts twice".
//
// So the allocator line is SUSPENDED for the post-write region, and only there. While suspended a crossing is
// RECORDED instead of being fatal, so the receipt can disclose it. The accepted cost, stated plainly: growth
// inside one loop is unbounded again in that region. It is bounded work (one index rebuild plus the contract
// check), the memory guard's own phase-boundary line is still armed inside it and still has a receipt-bearing
// stop (FileGraphStopped -> post_check "not run: …", exit 0), and the alternative is the double-insert above.
//
// THREE PROPERTIES THIS TYPE EXISTS TO GUARANTEE:
//   * UNREACHABLE FROM OUTSIDE. There is no flag, no environment variable and no setter — the only way to
//     suspend the line is to construct this object, and the only construction is inside mcpedit.h's
//     postCheckJson, which runs after a committed write by its own contract. Nothing a caller can type
//     switches the ceiling off.
//   * EVERY PRE-WRITE CHECK STAYS ARMED. The scope opens after atomicWrite has succeeded, so resolution, the
//     freshness re-check, the splice and the write itself are refused exactly as before.
//   * WHAT HAPPENED IS REPORTABLE. crossings() counts the admissions inside THIS scope (a sampled delta, so
//     each op of an --edit-plan --apply reports its own), and peakMib() the largest footprint admitted.
// It nests (depth, not a bool) and it costs the admit path NOTHING: the depth is read only on a crossing,
// which otherwise ends the process anyway.
class Suspension
{
public:
    Suspension() noexcept : admittedBefore_( g_state.admitted.load( std::memory_order_relaxed ) )
    {
        g_state.suspendDepth.fetch_add( 1, std::memory_order_acq_rel );
    }
    ~Suspension() noexcept { g_state.suspendDepth.fetch_sub( 1, std::memory_order_acq_rel ); }
    Suspension( const Suspension& )            = delete;
    Suspension& operator=( const Suspension& ) = delete;
    Suspension( Suspension&& )                 = delete;
    Suspension& operator=( Suspension&& )      = delete;

    [[nodiscard]] bool          armed() const noexcept { return g_state.budgetBytes.load( std::memory_order_relaxed ) != 0; }
    [[nodiscard]] std::uint64_t limitMib() const noexcept { return g_state.budgetBytes.load( std::memory_order_relaxed ) / kMiB; }
    [[nodiscard]] std::uint64_t crossings() const noexcept
    {
        return g_state.admitted.load( std::memory_order_relaxed ) - admittedBefore_;
    }
    [[nodiscard]] std::uint64_t peakMib() const noexcept { return g_state.admittedPeak.load( std::memory_order_relaxed ) / kMiB; }

private:
    std::uint64_t admittedBefore_;
};

// a crossing inside a suspended region: recorded, never fatal. No allocation and no output from here — the
// receipt does the disclosing, because this runs inside operator new and the caller is mid-edit.
inline void noteAdmitted( std::uint64_t footprint ) noexcept
{
    g_state.admitted.fetch_add( 1, std::memory_order_relaxed );
    std::uint64_t seen = g_state.admittedPeak.load( std::memory_order_relaxed );
    while( footprint > seen && !g_state.admittedPeak.compare_exchange_weak( seen, footprint, std::memory_order_relaxed ) )
    {
    }
}

// operator new's hook: called with every request size before the block is taken
inline void onAllocate( std::size_t request ) noexcept
{
    const std::uint64_t budget = g_state.budgetBytes.load( std::memory_order_relaxed );
    if( budget == 0 )
    {
        return;
    }
    const bool large = request >= kLargeBytes;
    if( !large )
    {
        thread_local constinit std::uint64_t sinceReading = 0;
        sinceReading += request;
        if( sinceReading < kSmallStrideBytes )
        {
            return;
        }
        sinceReading = 0;
    }
    g_state.readings.fetch_add( 1, std::memory_order_relaxed );
    if( large )
    {
        g_state.largeReadings.fetch_add( 1, std::memory_order_relaxed );
    }
    const std::uint64_t footprint = os::mem_footprint();
    if( footprint == 0 )
    {
        noteUnreadable();   // the OS cannot say: admitted unchecked, disclosed once, counted — never a silent zero
        return;
    }
    if( footprint + request > budget )
    {
        // The depth is read ONLY here, on a crossing that would otherwise end the process, so the admit path
        // pays nothing for the suspension (ruling 101; Suspension above holds the reasoning).
        if( g_state.suspendDepth.load( std::memory_order_acquire ) != 0 )
        {
            noteAdmitted( footprint );   // a file is already written: record it for the receipt, never _Exit here
            return;
        }
        refuse( footprint, request );
    }
}

} // namespace rw::memceiling
