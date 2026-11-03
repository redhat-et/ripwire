#pragma once

// memguard.h — #350 layer 3: a memory guard on every root, zero-config, silent on every normal run.
//
// WHY. ripwire held no bound on its own memory. An MCP server started in a home directory crawled it for seven hours
// and reached a 67 GB footprint (issue #350); nothing in the process measured memory at all. Layer 1 (rootguard.h)
// refuses the roots nobody chose; this guard is what protects the roots somebody did choose.
//
// THE LIMIT. The hard limit is 65% of the machine's memory — physical RAM, or the cgroup's memory.max when that is
// lower — so the default derives from the machine and nobody configures it. `--max-memory=<N>[K|M|G]` (or the
// RIPWIRE_MAX_MEMORY environment variable; the flag wins) replaces it; below kFloorBytes a value is refused as a typo,
// never obeyed. When the machine cannot say how much RAM it has the footprint cap is off and only the pressure signal
// remains.
//
// THE LINES, measured on the process footprint (measuredFootprint: os::mem_footprint, or the cgroup leaf's unreclaimable
// charge when the leaf has a memory.max and that is larger):
//   crawl  stops when the footprint has GROWN by limit/8 since this ingest began, or reaches half the limit. The
//          crawl's own cost is ~1-3 KB per file (#350's measurements), so a crawl that alone reaches an eighth of the
//          limit is a tree whose parse could never fit; stopping there is what leaves room to answer.
//   parse  stops at half the limit. The other half is what the model build, the graph and the answer need: measured
//          2026-09-28 on a 160,000-file synthetic C tree, the ingest's own tail (dedup, symbols, attribution) grows the
//          footprint ~1.5x past the moment the parse stops, and with a 4/5 line every stop the 5 s cadence caught
//          became a hard stop after the ingest instead of a partial answer.
//   hard   at the limit itself, checked between phases (main.cpp; --quality-delta=A..B, which dispatches before main()'s
//          ingest, between its own: verbs_quality.h refPairOverHardLimit) and before each MCP tool call: no partial answer.
//          The range form alone answers PART of the question instead (qd-memory-degrade): a stop in either commit's full
//          tree — or a projection that says the target phase will not fit (projectTargetPhase) — releases the full trees
//          and re-asks from both commits' CHANGED FILES the kinds those files decide, naming every kind it skipped
//          (exit 2 when a row gates, else 6); exit 5 is then left for "even the changed files did not fit".
//   pressure: the OS signal (os::mem_pressure) at "critical" stops the crawl or the parse too — but only once this
//          process holds at least max( 256 MiB, limit/8 ), so a small run is never cut because something ELSE is
//          using the machine. It never causes a hard stop.
//
// THE COST. Nothing is measured until five seconds after an ingest starts (owner decision, #350: the runaway adds
// ~15 MB per 5 s), and then at most once per five seconds: the crawl looks every 1,024 entries, the parse on each file
// completion, and only the thread that wins the time slot pays the syscall. A CLI run shorter than five seconds reads
// the footprint three times — at ingest start, after the ingest and after the graph build (the hard line) — and an MCP
// tool call once more. The `--quality-delta=A..B` range form reads it up to 2 + 6 times: two outside its commit
// ingests and the six hard-line readings around them, plus one projection after the base commit (two footprint readings
// and one PEAK reading, os::mem_footprint_peak) and one peak reading after the answer. None of it changes a byte of
// output unless a line is crossed (test/memguardcheck.sh (C), test/qddegradecheck.sh (L)). No thread, no timer, no
// signal handler.
//
// THE STOP. A soft stop sets an atomic flag the crawl loop and the parse workers read before the next unit of work,
// records WHY through DISCLOSE on IngestResult::memoryStop, and lets ingest() finish with what it has: the crawl keeps
// the entries it saw (then sorts them, as always); the parse keeps every file it claimed — a prefix of its parse order
// (a worker checks the flag BEFORE claiming a file, so every claimed file completes). Nothing derived from a partial ingest is ever persisted — not the ingest
// cache, not a quality snapshot, not a baseline. Whether the partial ingest may answer is the caller's decision — main.cpp answers the
// default map with memory_stop= in its header and refuses every other verb (exit 5) except --quality-delta=A..B, which
// releases the cut tree unscored and answers from both commits' changed files (see "hard" above); the MCP server
// answers with `_memory_stop` in the envelope.
//
// THE TEST SEAM. RIPWIRE_TEST_MEMGUARD=crawl:N | pressure:N | parse:N | request:N | hard:N ADDS a trip — at the Nth crawl entry
// (over the line, or under critical pressure), after exactly N files of the parse order are parsed, or at the Nth and
// later MCP tool calls, or at the Nth and later hard-line readings (hard:N); eager:1 instead drops the five-second time gate, so every guarded unit takes a REAL reading — so test/memguardcheck.sh can drive every stop path deterministically. It never replaces a real
// reading: every real line, the time gate and the hard line still apply, so it can only make a run stricter. crawl:N and
// parse:N count per INGEST (each ingest's own Watch). Three more for the range form (test/qddegradecheck.sh): project:N —
// the Nth target-phase projection reads "does not fit"; ingest:N — the Nth ingest of the process stops its crawl at its
// first entry (a stop in ONE chosen ingest, e.g. the target's after the base fit); peak:N — the Nth post-answer peak
// reading reads as over the limit.
//
// REPEATABILITY. A crawl stop keeps what the walk had seen, then sorts it. A parse stop keeps the first K slots of the
// parse ORDER (cache misses, then cache hits, then grammarless files, each largest first, then fileId — or plain fileId
// order when no grammar-bearing file needed a fresh parse, every one an ingest-cache hit: the query prewarm then has
// nothing to compile, ingest_prewarm.h), every one of which completed (a slot may reuse cached facts or fail to read),
// so a partial answer is a function of the tree, the cache and memory_parsed=K: two runs cut at the same K print the
// same bytes.

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iterator>
#include <string>
#include <string_view>

#include "infra/Diagnostics.h"   // VALIDATE — the environment is external input
#include "infra/os.h"            // rw::os::mem_footprint / mem_physical / mem_cgroup_max / mem_cgroup_unreclaimable / mem_pressure
#include "model.h"               // MemoryStop — the disclosure sink

namespace rw::memguard
{

inline constexpr std::uint64_t kMiB             = 1024ull * 1024ull;
inline constexpr std::uint64_t kFloorBytes      = 64ull * kMiB;              // --max-memory below this is a typo, refused
inline constexpr std::uint64_t kPressureMinimum = 256ull * kMiB;             // pressure never cuts a run smaller than this
inline constexpr std::int64_t  kCheckIntervalNs = 5'000'000'000;             // owner, #350: five seconds between readings
inline constexpr std::uint32_t kCrawlStride     = 1024;                      // crawl entries between time-gate looks
static_assert( ( kCrawlStride & ( kCrawlStride - 1 ) ) == 0, "the crawl stride is a mask" );

enum class Source : std::uint8_t
{
    Default,   // 65% of the machine's memory
    Flag,      // --max-memory
    Env,       // RIPWIRE_MAX_MEMORY
};

// The process-wide limit. Written once by main() before any worker thread exists (install), read everywhere after.
struct Limits
{
    std::uint64_t hardBytes = 0;   // 0 = the machine's memory is unknown: no footprint cap, pressure only
    Source        source    = Source::Default;
};
inline Limits& limitsSlot() noexcept
{
    static Limits slot;
    return slot;
}
inline const Limits& limits() noexcept { return limitsSlot(); }

// the machine's own ceiling: physical RAM, or the cgroup's memory.max when that is lower; 0 when unknown. Also what a
// degraded --quality-delta=A..B compares its replay's need with (a need above it is recoverable only on a larger machine).
inline std::uint64_t machineMemoryBytes()
{
    std::uint64_t machine = os::mem_physical();
    const std::uint64_t cgroup = os::mem_cgroup_max();
    if( cgroup != 0 && ( machine == 0 || cgroup < machine ) )
    {
        machine = cgroup;
    }
    return machine;
}
// 65% of min( physical RAM, cgroup memory.max ), or 0 when the machine cannot say how much RAM it has.
inline std::uint64_t defaultLimitBytes()
{
    return machineMemoryBytes() / 100 * 65;
}

// the footprint every line is measured on: this process's own (os::mem_footprint), or, when it is larger, the
// unreclaimable charge of the cgroup v2 leaf this process runs in, read only when that leaf has a finite memory.max (#387).
// There the OOM killer acts on the leaf's charge, which counts every process in the leaf and anonymous memory statm
// does not show; the leaf's reclaimable page cache (the extracted commit trees --quality-delta=A..B writes) is left out,
// because the kernel drops it before it kills. An unlimited or unreadable leaf reads 0, so the process footprint decides.
inline std::uint64_t measuredFootprint()
{
    return std::max( os::mem_footprint(), os::mem_cgroup_unreclaimable() );
}
// true when the cgroup leaf's charge, not this process's own footprint, is the larger figure: a message about the hard line
// then names the leaf, because freeing this process's memory may not bring the leaf back under it
inline bool leafChargeDecides()
{
    return os::mem_cgroup_unreclaimable() > os::mem_footprint();
}

// the limit as a --max-memory value ("10854M"): what the reader would type to raise it — so always in whole MiB,
// rounded up, the spelling every disclosure and message uses
inline std::string limitSpelling( std::uint64_t bytes )
{
    return std::to_string( ( bytes + kMiB - 1 ) / kMiB ) + "M";
}

// ── the test seam ──────────────────────────────────────────────────────────────────────────────────────────
enum class TripAt : std::uint8_t
{
    Nowhere,
    Crawl,      // crawl:N    — the Nth crawl entry reads as over the crawl line
    Pressure,   // pressure:N — the Nth crawl entry reads as critical OS memory pressure
    Parse,      // parse:N    — exactly the first N files of the parse order are parsed: memory_parsed=N
    Request,    // request:N  — the Nth MCP tool call reads as over the hard limit
    Hard,       // hard:N     — the Nth hard-line reading (overHardLimit: between CLI phases, per workspace root, between --quality-delta=A..B's phases) reads as over
    Eager,      // eager:1    — no five-second time gate: every guarded unit takes a REAL footprint reading (only stricter)
    Project,    // project:N  — the Nth target-phase projection (projectTargetPhase) reads as "does not fit"
    Ingest,     // ingest:N   — the Nth ingest of the process stops its crawl at its first entry (a crawl stop)
    Peak,       // peak:N     — the Nth post-answer peak reading (peakOverLimit) reads as over the limit
};
struct TestTrip
{
    TripAt        at    = TripAt::Nowhere;
    std::uint64_t index = 0;   // 1-based: the Nth guarded unit trips
};
// the seam's phase spellings (an unknown one is no seam at all)
inline TripAt tripAtFor( std::string_view phase ) noexcept
{
    constexpr struct
    {
        std::string_view name;
        TripAt           at;
    } kPhases[] = {
        { "crawl", TripAt::Crawl }, { "pressure", TripAt::Pressure }, { "parse", TripAt::Parse },
        { "request", TripAt::Request }, { "hard", TripAt::Hard }, { "eager", TripAt::Eager },
        { "project", TripAt::Project }, { "ingest", TripAt::Ingest }, { "peak", TripAt::Peak },
    };
    for( const auto& p : kPhases )
    {
        if( p.name == phase )
        {
            return p.at;
        }
    }
    return TripAt::Nowhere;
}
// RIPWIRE_TEST_MEMGUARD, read once. A malformed value is no seam at all (the variable is for gates only).
inline const TestTrip& testTrip() noexcept
{
    static const TestTrip trip = []() noexcept
    {
        TestTrip          t;
        const char* const env = std::getenv( "RIPWIRE_TEST_MEMGUARD" );
        if( env == nullptr )
        {
            return t;
        }
        const std::string_view v( env );
        const std::size_t      colon = v.find( ':' );
        if( !VALIDATE( colon != std::string_view::npos && colon + 1 < v.size(), "the test seam is <phase>:<n>" ) )
        {
            return t;
        }
        std::uint64_t n = 0;
        for( const char c : v.substr( colon + 1 ) )
        {
            if( c < '0' || c > '9' || n > ( 1ull << 40 ) )
            {
                return t;
            }
            n = n * 10 + std::uint64_t( c - '0' );
        }
        const std::string_view phase = v.substr( 0, colon );
        t.at    = tripAtFor( phase );
        t.index = n;
        return t;
    }();
    return trip;
}

// the time gate runs on the steady clock's own ticks: no conversion on the hot path, only one at compile time
using GateClock = std::chrono::steady_clock;
inline constexpr GateClock::rep kCheckIntervalTicks = std::chrono::duration_cast<GateClock::duration>( std::chrono::nanoseconds( kCheckIntervalNs ) ).count();

// The seams' process-wide call counters, one struct (stopCounts' shape): every ingest() (the ingest:N ordinal, counted
// at its Watch), the MCP tool calls (request:N), the range form's projections (project:N) and its post-answer peak
// readings (peak:N). Relaxed: each is read by the call that bumps it.
struct SeamCounters
{
    std::atomic<std::uint64_t> ingests{ 0 };
    std::atomic<std::uint64_t> requests{ 0 };
    std::atomic<std::uint64_t> projections{ 0 };
    std::atomic<std::uint64_t> peaks{ 0 };
};
inline SeamCounters& seamCounters() noexcept
{
    static SeamCounters counters;
    return counters;
}
// one call of a call-counted seam: true for the Nth call (`laterToo` false) or the Nth and every later one
inline bool seamCallTrips( TripAt at, std::atomic<std::uint64_t>& seen, bool laterToo ) noexcept
{
    if( testTrip().at != at )
    {
        return false;
    }
    const std::uint64_t n = seen.fetch_add( 1, std::memory_order_relaxed ) + 1;
    return laterToo ? n >= testTrip().index : n == testTrip().index;
}

// install: main() calls this once, before any thread, with the resolved limit. A zero `bytes` means "the default".
inline void install( std::uint64_t bytes, Source source )
{
    Limits& slot  = limitsSlot();
    slot.hardBytes = bytes != 0 ? bytes : defaultLimitBytes();
    slot.source    = bytes != 0 ? source : Source::Default;
}

// ── the per-ingest watch ───────────────────────────────────────────────────────────────────────────────────
// One per ingest() call: the crawl and the parse pool share it, the parse workers from several threads. The test seam is
// ADDITIVE: it adds a trip at a fixed unit of work and never removes a real reading, the time gate or the hard line, so
// the variable can only make a run stricter (the RIPWIRE_TEST_PR_MAXITERS convention: it can only LOWER).
class Watch
{
public:
    Watch() noexcept
        : trip_( testTrip() )
        , hardBytes_( limits().hardBytes )
        , ingestOrdinal_( seamCounters().ingests.fetch_add( 1, std::memory_order_relaxed ) + 1 )
    {
        baseFootprint_ = measuredFootprint();
        nextCheckTick_.store( GateClock::now().time_since_epoch().count() + kCheckIntervalTicks, std::memory_order_relaxed );
    }
    Watch( const Watch& )            = delete;
    Watch& operator=( const Watch& ) = delete;

    // the crawl: called once per directory entry with the running entry count; true = stop walking now
    [[nodiscard]] bool crawlShouldStop( std::uint64_t entryCount ) noexcept
    {
        if( stopped_.load( std::memory_order_relaxed ) )
        {
            return true;
        }
        if( entryCount + 1 == trip_.index && ( trip_.at == TripAt::Crawl || trip_.at == TripAt::Pressure ) )
        {
            return tripSoft( trip_.at == TripAt::Pressure );
        }
        if( trip_.at == TripAt::Ingest && ingestOrdinal_ == trip_.index )
        {
            return tripSoft( false );   // ingest:N — this whole ingest is the one the seam cuts, at its first entry
        }
        if( ( entryCount & ( kCrawlStride - 1 ) ) != 0 || !claimTimeSlot() )
        {
            return false;
        }
        const std::uint64_t footprint = measuredFootprint();
        const bool overLine = hardBytes_ != 0 && footprint != 0
                           && ( footprint >= softLine() || ( footprint > baseFootprint_ && footprint - baseFootprint_ >= hardBytes_ / 8 ) );
        return ( overLine && tripSoft( false ) ) || ( underPressure( footprint ) && tripSoft( true ) );
    }

    // the parse: a worker asks BEFORE claiming its next file (a relaxed load, nothing else)
    [[nodiscard]] bool isStopped() const noexcept { return stopped_.load( std::memory_order_relaxed ); }

    // the parse seam (parse:N): the work-order slot at which claims are abandoned, or SIZE_MAX when no parse seam is set
    [[nodiscard]] std::size_t seamParseCutoff() const noexcept
    {
        return trip_.at == TripAt::Parse ? std::size_t( trip_.index ) : SIZE_MAX;
    }
    void tripParseSeam() noexcept { (void)tripSoft( false ); }

    // the parse: a worker reports each finished file; may trip the stop for every worker (time-gated real reading)
    void parseFileDone() noexcept
    {
        if( stopped_.load( std::memory_order_relaxed ) || !claimTimeSlot() )
        {
            return;
        }
        const std::uint64_t footprint = measuredFootprint();
        if( hardBytes_ != 0 && footprint != 0 && footprint >= softLine() )
        {
            (void)tripSoft( false );
        }
        else if( underPressure( footprint ) )
        {
            (void)tripSoft( true );
        }
    }

    // ingest() calls this between the crawl and the parse: a crawl stop is already recorded, and the parse has its own
    // (higher) line, so the flag is re-armed rather than handed on — a stopped crawl's files are still parsed, guarded.
    void rearmForParse() noexcept
    {
        stopped_.store( false, std::memory_order_relaxed );
        trippedOnce_.store( false, std::memory_order_relaxed );
        byPressure_ = false;
    }

    [[nodiscard]] bool tripped() const noexcept { return stopped_.load( std::memory_order_acquire ); }
    [[nodiscard]] bool trippedByPressure() const noexcept { return byPressure_; }   // read after tripped() / the pool join
    [[nodiscard]] std::uint64_t hardBytes() const noexcept { return hardBytes_; }

private:
    [[nodiscard]] std::uint64_t softLine() const noexcept { return hardBytes_ / 2; }

    [[nodiscard]] bool underPressure( std::uint64_t footprint ) const noexcept
    {
        const std::uint64_t minimum = std::max( kPressureMinimum, hardBytes_ / 8 );
        return footprint >= minimum && os::mem_pressure() >= 3;
    }

    // true for exactly one caller per five-second slot: the one that moves the deadline forward
    [[nodiscard]] bool claimTimeSlot() noexcept
    {
        if( trip_.at == TripAt::Eager )
        {
            return true;   // the eager seam: a real reading every time — the gate's way to reach a REAL stop in well under 5 s
        }
        const GateClock::rep now      = GateClock::now().time_since_epoch().count();
        GateClock::rep       deadline = nextCheckTick_.load( std::memory_order_relaxed );
        return now >= deadline && nextCheckTick_.compare_exchange_strong( deadline, now + kCheckIntervalTicks, std::memory_order_relaxed );
    }

    // the first caller to trip records the cause; everyone sees stopped_ afterwards. Always returns true.
    bool tripSoft( bool byPressure ) noexcept
    {
        bool expected = false;
        if( trippedOnce_.compare_exchange_strong( expected, true, std::memory_order_acq_rel ) )
        {
            byPressure_ = byPressure;
            stopped_.store( true, std::memory_order_release );
        }
        return true;
    }

    const TestTrip&             trip_;
    const std::uint64_t         hardBytes_;
    const std::uint64_t         ingestOrdinal_;
    std::uint64_t               baseFootprint_ = 0;
    std::atomic<GateClock::rep> nextCheckTick_{ 0 };
    std::atomic<bool>           stopped_{ false };
    std::atomic<bool>           trippedOnce_{ false };
    bool                        byPressure_    = false;
};

// ── the hard line: between phases (CLI) and before each MCP tool call ──────────────────────────────────────
// true when the footprint is at or over the hard limit. Unlike the soft lines this reads the footprint every time it
// is called — its callers run it once per phase or once per request, never per unit of work.
inline bool overHardLimit()
{
    const Limits& l = limits();
    if( l.hardBytes == 0 )
    {
        return false;
    }
    if( testTrip().at == TripAt::Hard )   // the seam: additive, so a real reading below still applies before the Nth
    {
        static std::atomic<std::uint64_t> readingsSeen{ 0 };
        if( readingsSeen.fetch_add( 1, std::memory_order_relaxed ) + 1 >= testTrip().index )
        {
            return true;
        }
    }
    const std::uint64_t footprint = measuredFootprint();
    return footprint != 0 && footprint >= l.hardBytes;
}

// the MCP request seam: true for the Nth and later tool calls under request:N (counts one call per invocation). The
// pre-check is `requestSeamTrips() || overHardLimit()` — additive, like every seam.
inline bool requestSeamTrips()
{
    return seamCallTrips( TripAt::Request, seamCounters().requests, /*laterToo=*/true );
}

// ── the range form's projection and peak (qd-memory-degrade) ───────────────────────────────────────────────
// --quality-delta=A..B scores the base commit and releases it before the target is materialized (#387). The target
// phase then holds the base snapshot, the full target tree and computeDelta's passes; on the measured repositories its
// growth over the starting footprint was 0.9-1.4x the base phase's. What the base released is reused, not added: the
// footprint once it is released (`after`) is anywhere from the start plus the snapshot (the allocator returned the
// pages) to the base phase's peak (it kept them), and the target phase grows into that. So after the base phase:
//     need       = max( after, before + k * ( basePeak - before ) )   against the hard limit, and
//     ingestNeed = max( after, ingestPeak )                          against the parse line (half the limit),
// where `before` is this process's own footprint before the base phase and `basePeak` / `ingestPeak` its PEAK at the end
// of the base phase / of the base ingest (os::mem_footprint_peak — the readings between phases miss the clone passes'
// transient peak). k is kProjectionScalePct / 100, calibrated in the qd-memory-degrade report as the max over the measured
// corpora of ( full peak - before ) / ( base-phase peak - before ), rounded up. A run whose true need lies within that
// margin below the limit may be answered degraded; the projection never lets a run past the limit by its own choice (an
// under-projection is caught by the guard's stops, which degrade). An unknown peak (0) projects nothing: the full attempt
// runs, and a stop in it still degrades.
inline constexpr std::uint64_t kProjectionScalePct = 175;   // max measured 1.48 over 11 cold runs on 5 corpora (qd-memory-degrade report), + ~18%
struct TargetProjection
{
    bool          measured        = false;   // false: no peak reading — nothing was projected
    bool          fits            = true;
    std::uint64_t needBytes       = 0;       // the projected need (0 when not measured)
    std::uint64_t ingestNeedBytes = 0;       // max( after, ingestPeak ), judged against half the limit (0 when not measured)
};
inline TargetProjection projectTargetPhase( std::uint64_t before, std::uint64_t ingestPeak, std::uint64_t basePeak, std::uint64_t after )
{
    TargetProjection    p;
    const std::uint64_t limit = limits().hardBytes;
    p.measured = basePeak != 0 && ingestPeak != 0 && after != 0 && basePeak >= before;
    if( p.measured )
    {
        const std::uint64_t growth     = basePeak - before;
        const std::uint64_t scaled     = growth / 100 * kProjectionScalePct + growth % 100 * kProjectionScalePct / 100;   // no overflow below 2^57 B
        p.needBytes                    = std::max( after, before + scaled );
        const std::uint64_t ingestNeed = std::max( after, ingestPeak );
        p.ingestNeedBytes              = ingestNeed;
        p.fits = limit == 0 || ( p.needBytes < limit && ingestNeed < limit / 2 );
    }
    if( seamCallTrips( TripAt::Project, seamCounters().projections, /*laterToo=*/false ) )
    {
        p.fits = false;   // the seam: additive — it can only make a run degrade, never let one run full past a real projection
    }
    return p;
}
// --max-memory for a replay of what a degraded run skipped: strictly above BOTH lines the projection judged — the projected
// need (against the limit) and twice the ingest need (against the parse line, half the limit) — and never below the limit
// this run used, in whole MiB, at least the parser's floor, and at most what a size_t can hold (item 27: the value the
// continuation names is one the parser accepts). After a stop no need was measured, so the replay names twice the limit:
// a guess, and said to be one.
inline std::uint64_t replayLimitBytes( std::uint64_t needBytes, std::uint64_t ingestNeedBytes, bool needMeasured )
{
    const std::uint64_t limit      = limits().hardBytes;
    const std::uint64_t ingestLine = ingestNeedBytes > ( UINT64_MAX / 2 ) ? UINT64_MAX : ingestNeedBytes * 2;
    const std::uint64_t need       = std::max( { needBytes, ingestLine, limit } );
    std::uint64_t       want       = needMeasured ? ( need >= UINT64_MAX - kMiB ? UINT64_MAX : ( ( need + kMiB - 1 ) / kMiB + 1 ) * kMiB )   // one MiB above, as spelled
                                                  : ( limit > ( UINT64_MAX / 2 ) ? UINT64_MAX : limit * 2 );
    want = std::max( want, kFloorBytes );
    const std::uint64_t ceiling = std::uint64_t( SIZE_MAX ) / kMiB * kMiB;
    return std::min( want, ceiling );
}
// The peak after the answer was computed, when it went over the limit (or the peak:N seam says so), else 0. computeDelta
// runs after the last hard-line reading, so a full answer can finish over --max-memory (rv-pr391 N1: 1.09-1.11x); this
// is the reading that SAYS so instead of answering silently over it. It never changes the exit code.
inline std::uint64_t peakOverLimit()
{
    const std::uint64_t limit = limits().hardBytes;
    if( limit == 0 )
    {
        return 0;
    }
    std::uint64_t peak = os::mem_footprint_peak();
    if( seamCallTrips( TripAt::Peak, seamCounters().peaks, /*laterToo=*/false ) )
    {
        peak = std::max( peak, limit + kMiB );   // the seam: the reading says over, whatever the real peak was
    }
    return peak > limit ? peak : 0;
}
// ── the backstop: a stop nobody answered for ────────────────────────────────────────────────────────────
// ingest() counts every stop it discloses; the caller that decides what the partial ingest may answer (main.cpp's
// memoryStopExit) marks every stop so far as answered for. A CLI run that ends with a stop nobody answered for — an
// ingest INSIDE a verb (a --quality-delta HEAD snapshot, --index-out, --dmm) whose verb does not read memoryStop —
// exits 5 with one line, so a partial secondary ingest can never pass as a whole one. The counters are process-wide
// and relaxed: every reader runs after the ingests it counts have returned.
struct StopCounts
{
    std::atomic<std::uint32_t> recorded{ 0 };
    std::atomic<std::uint32_t> answered{ 0 };
};
inline StopCounts& stopCounts() noexcept
{
    static StopCounts counts;
    return counts;
}
inline void recordStop() noexcept { stopCounts().recorded.fetch_add( 1, std::memory_order_relaxed ); }
inline void answerStops() noexcept { stopCounts().answered.store( stopCounts().recorded.load( std::memory_order_relaxed ), std::memory_order_relaxed ); }
[[nodiscard]] inline bool hasUnansweredStop() noexcept
{
    return stopCounts().recorded.load( std::memory_order_relaxed ) > stopCounts().answered.load( std::memory_order_relaxed );
}

// ── the sentences ──────────────────────────────────────────────────────────────────────────────────────────
// indexed by MemoryStop::Phase; None never reaches a sentence that names a phase
inline constexpr std::string_view kPhaseNames[] = { "ingest", "crawl", "parse" };
static_assert( std::size( kPhaseNames ) == std::size_t( MemoryStop::Phase::Parse ) + 1, "one name per MemoryStop::Phase" );
inline std::string_view phaseName( MemoryStop::Phase phase ) noexcept
{
    return kPhaseNames[ std::size_t( phase ) ];
}

// every message ends with the override
inline constexpr std::string_view kOverride = "raise it with --max-memory=<N>[K|M|G] or RIPWIRE_MAX_MEMORY, or pass a smaller root";

// where the limit came from, as the clause every message spells it with
inline std::string_view limitSourceClause() noexcept
{
    const Limits& l = limits();
    return l.source == Source::Flag ? "from --max-memory" : l.source == Source::Env ? "from RIPWIRE_MAX_MEMORY" : "65% of this machine's memory";
}

// the hard stop's one line: nothing was built that could answer. `also` is said between the limit and the verdict — the
// range form's "the changed files were not tried" / "were cut too" — and is empty everywhere else (the line keeps its bytes).
inline std::string hardStopLine( std::string_view where, std::string_view also = {} )
{
    std::string line = "memory limit reached during the ";
    line.append( where ).append( " (limit " ).append( limitSpelling( limits().hardBytes ) ).append( ", " ).append( limitSourceClause() ).append( "); " );
    return line.append( also ).append( "stopped cleanly without an answer — " ).append( kOverride );
}

// which line a soft stop crossed, spelled against the limit that sets it (a soft stop is never the limit itself)
inline std::string stopCause( const MemoryStop& stop )
{
    if( stop.byPressure )
    {
        return "under critical system memory pressure";
    }
    return stop.phase == MemoryStop::Phase::Crawl
         ? "at the crawl line (footprint growth of an eighth of the " + limitSpelling( stop.limitBytes ) + " limit)"
         : "at the parse line (half of the " + limitSpelling( stop.limitBytes ) + " limit)";
}

// a soft stop that left nothing to answer from — named by its cause, never as the limit it did not reach
inline std::string nothingBuiltLine( const MemoryStop& stop )
{
    return "the memory guard stopped the " + std::string( phaseName( stop.phase ) ) + " " + stopCause( stop )
         + " before anything was built; stopped cleanly without an answer — " + std::string( kOverride );
}

// a verb that cannot carry the disclosure, facing a partial ingest
inline std::string verbRefusalLine( const MemoryStop& stop, std::string_view verb )
{
    return "the memory guard stopped the " + std::string( phaseName( stop.phase ) ) + " " + stopCause( stop ) + "; " + std::string( verb )
         + " cannot answer from a partial index — " + std::string( kOverride );
}

// the soft stop's one line (stderr on the CLI, the MCP envelope's _memory_stop)
inline std::string softStopLine( const IngestResult& ing )
{
    const MemoryStop& m = ing.memoryStop;
    std::string line = "the memory guard stopped the " + std::string( phaseName( m.phase ) ) + " " + stopCause( m )
                     + ": this answer covers " + std::to_string( ing.files.size() ) + " files";
    if( m.parseCut )
    {
        line += ", " + std::to_string( m.parsedFiles ) + " of them parsed";
    }
    return line + ", a floor of the tree — " + std::string( kOverride );
}

// An ABSENCE or an error served from a partial index (notfound-on-cut): "symbol not found", "0 callers" and a refusal
// built after the index was read all describe the CUT corpus, not the tree. softStopLine already says what the answer
// covered (the file count, the parsed count) and how to get the whole tree; this prefixes the one thing a not-found
// reader needs, that the absence is unproven. It rides on EVERY error from a cut index, usage errors included: the clause
// is true of the index whatever the error was, and a cut index is the state an agent most needs to hear about. The CLI never reaches it (a verb other than the map refuses with exit 5).
inline std::string partialAbsenceLine( const IngestResult& ing )
{
    return "the index this server holds is partial, so a not-found or empty answer from it is not proof of absence — " + softStopLine( ing );
}

}   // namespace rw::memguard
