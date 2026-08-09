// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  profilePmc.h
//
//  Hardware performance-counter (PMC) backends for the scope profiler
//  (profileScope.h), behind one tiny "read a snapshot of all counters" surface;
//  profileScope.h brackets each PROFILE_SCOPE with two reads and accumulates the
//  deltas, so the report can show cycles / instructions / branch-misses /
//  cache-misses PER SCOPE alongside the wall-clock time. Two real backends:
//    * Apple Silicon — dlopen()s the private kperf / kperfdata frameworks.
//    * Linux         — perf_event_open, one atomically-scheduled event group per
//      thread (leader + PERF_FORMAT_GROUP, so every column covers the same
//      instruction window and the whole group reads in ONE syscall).
//  Everything else gets inert stubs; the timing path never notices.
//
//  WHY A SEPARATE BACKEND
//    * Privilege + availability. kpc_* needs root or the com.apple.private.kperf
//      entitlement. When that is missing (the usual case for a plain dev build)
//      everything degrades to active()==false: read() returns zeros, the report
//      drops the counter columns and falls back to pure timing. No warnings, no
//      crash. The messy framework loading lives behind a clean boundary the hot
//      path can ignore with one bool check (active()).
//    * It is the ONE place that touches Apple's undocumented kperf ABI. Keeping
//      it isolated keeps profileScope.h readable and lets that file stay the
//      portable, privilege-free timing core.
//
//  HOT-PATH COST
//    When active, read() is a thin wrapper over kpc_get_thread_counters — far
//    heavier than the single `mrs cntvct_el0` the timing path pays. That is why
//    PROFILE_PMC (profileScope.h) gates it, and why only the OUTERMOST frame of a
//    recursive site samples counters.
//
//  CREDIT: the kperf / kperfdata symbol shapes follow the well-known lib_kperf
//  reverse-engineering work; adapted here to this code base's style and folded
//  behind a snapshot interface.
//

#pragma once

#include "platform.h"        // ALWAYS_INLINE

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>

// ============================================================================
// Common, platform-independent surface (referenced by profileScope.h's Record /
// Row regardless of platform, so it must exist on every build).
// ============================================================================
namespace prof
{
namespace pmc
{

// Max hardware events we configure and carry per scope. Apple's fixed +
// configurable PMC budget on current cores sits well under this; 8 leaves slack.
inline constexpr unsigned kMaxEvents = 8;

// One read of all configured counters for the calling thread. Trivial POD (64 B).
struct Snapshot
{
    uint64_t values[ kMaxEvents ] {};
};

}   // namespace pmc
}   // namespace prof

// ----- diagnostics, shared by every real backend (off by default: a missing
//       entitlement / vPMU / paranoid setting is the common, quiet case — we do
//       not want every unprivileged run spamming stderr). Build with
//       -DPROFILE_PMC_VERBOSE=1 to trace exactly which init step fails. -
#ifndef PROFILE_PMC_VERBOSE
  #define PROFILE_PMC_VERBOSE 0
#endif

#if PROFILE_PMC_VERBOSE
  #define PMC_DIAG( ... ) std::fprintf( stderr, "prof::pmc: " __VA_ARGS__ )
#else
  #define PMC_DIAG( ... ) ( (void) 0 )
#endif


#if defined( __APPLE__ ) && ( defined( __arm64__ ) || defined( __aarch64__ ) )

#include <dlfcn.h>
#include <mutex>
#include <unistd.h>          // geteuid (verbose diagnostics)

namespace prof
{
namespace pmc
{

// kpc configuration words are plain u64s.
using kpc_config_t = uint64_t;

// Opaque kperfdata handles — we only ever pass pointers to these around.
struct kpep_db;
struct kpep_config;
struct kpep_event;

// ============================================================================
// KpcApi — Apple's private kperf / kperfdata ABI, resolved at runtime by dlsym.
// ============================================================================
struct KpcApi
{
    void* kperf     = nullptr;
    void* kperfdata = nullptr;

    // kperf.framework — the counter engine
    int      (*kpc_force_all_ctrs_get)( int* )                          = nullptr;
    int      (*kpc_force_all_ctrs_set)( int )                           = nullptr;
    uint32_t (*kpc_get_counter_count)( uint32_t )                       = nullptr;
    uint32_t (*kpc_get_config_count)( uint32_t )                        = nullptr;
    int      (*kpc_set_config)( uint32_t, kpc_config_t* )               = nullptr;
    int      (*kpc_get_thread_counters)( uint32_t, uint32_t, uint64_t* )= nullptr;
    int      (*kpc_set_counting)( uint32_t )                            = nullptr;
    int      (*kpc_set_thread_counting)( uint32_t )                     = nullptr;

    // kperfdata.framework — the event database that turns names into config words
    int      (*kpep_db_create)( const char*, kpep_db** )                = nullptr;
    void     (*kpep_db_free)( kpep_db* )                                = nullptr;
    int      (*kpep_db_event)( kpep_db*, const char*, kpep_event** )    = nullptr;
    int      (*kpep_config_create)( kpep_db*, kpep_config** )           = nullptr;
    void     (*kpep_config_free)( kpep_config* )                        = nullptr;
    int      (*kpep_config_add_event)( kpep_config*, kpep_event**, uint32_t, uint32_t* ) = nullptr;
    int      (*kpep_config_force_counters)( kpep_config* )              = nullptr;
    int      (*kpep_config_kpc_classes)( kpep_config*, uint32_t* )      = nullptr;
    int      (*kpep_config_kpc_count)( kpep_config*, size_t* )          = nullptr;
    int      (*kpep_config_kpc_map)( kpep_config*, size_t*, size_t )    = nullptr;
    int      (*kpep_config_kpc)( kpep_config*, kpc_config_t*, size_t )  = nullptr;
};

inline KpcApi g_api;

template< class Fn >
inline bool load_sym( void* handle, Fn& fn, const char* name ) noexcept
{
    fn = reinterpret_cast<Fn>( dlsym( handle, name ) );
    return fn != nullptr;
}

inline bool load_api() noexcept
{
    g_api.kperf     = dlopen( "/System/Library/PrivateFrameworks/kperf.framework/kperf",         RTLD_LAZY );
    g_api.kperfdata = dlopen( "/System/Library/PrivateFrameworks/kperfdata.framework/kperfdata", RTLD_LAZY );

    if( !g_api.kperf || !g_api.kperfdata )
    {
        return false;
    }

    bool ok = true;

    ok &= load_sym( g_api.kperf, g_api.kpc_force_all_ctrs_get,  "kpc_force_all_ctrs_get"  );
    ok &= load_sym( g_api.kperf, g_api.kpc_force_all_ctrs_set,  "kpc_force_all_ctrs_set"  );
    ok &= load_sym( g_api.kperf, g_api.kpc_get_counter_count,   "kpc_get_counter_count"   );
    ok &= load_sym( g_api.kperf, g_api.kpc_get_config_count,    "kpc_get_config_count"    );
    ok &= load_sym( g_api.kperf, g_api.kpc_set_config,          "kpc_set_config"          );
    ok &= load_sym( g_api.kperf, g_api.kpc_get_thread_counters, "kpc_get_thread_counters" );
    ok &= load_sym( g_api.kperf, g_api.kpc_set_counting,        "kpc_set_counting"        );
    ok &= load_sym( g_api.kperf, g_api.kpc_set_thread_counting, "kpc_set_thread_counting" );

    ok &= load_sym( g_api.kperfdata, g_api.kpep_db_create,            "kpep_db_create"            );
    ok &= load_sym( g_api.kperfdata, g_api.kpep_db_free,              "kpep_db_free"              );
    ok &= load_sym( g_api.kperfdata, g_api.kpep_db_event,             "kpep_db_event"             );
    ok &= load_sym( g_api.kperfdata, g_api.kpep_config_create,        "kpep_config_create"        );
    ok &= load_sym( g_api.kperfdata, g_api.kpep_config_free,          "kpep_config_free"          );
    ok &= load_sym( g_api.kperfdata, g_api.kpep_config_add_event,     "kpep_config_add_event"     );
    ok &= load_sym( g_api.kperfdata, g_api.kpep_config_force_counters,"kpep_config_force_counters");
    ok &= load_sym( g_api.kperfdata, g_api.kpep_config_kpc_classes,   "kpep_config_kpc_classes"   );
    ok &= load_sym( g_api.kperfdata, g_api.kpep_config_kpc_count,     "kpep_config_kpc_count"     );
    ok &= load_sym( g_api.kperfdata, g_api.kpep_config_kpc_map,       "kpep_config_kpc_map"       );
    ok &= load_sym( g_api.kperfdata, g_api.kpep_config_kpc,           "kpep_config_kpc"           );

    return ok;
}

// ============================================================================
// Event table — declarative. One row per logical event: the name we request and
// report, a short label for the table header, and the hardware event names to
// probe in order (Apple-core name first, Intel/x86 second, generic last). The DB
// is per-microarchitecture, so probing lets one table cover several CPUs.
// ============================================================================
struct EventDesc
{
    const char* alias;        // logical name (requested + printed in the banner)
    const char* label;        // short header label for the report table
    const char* probes[ 5 ];  // hardware names to try, in order; nullptr terminates
};

inline constexpr EventDesc kEvents[] =
{
    { "cycles",           "cyc",     { "FIXED_CYCLES",          "CPU_CLK_UNHALTED.THREAD",         "cycles",                  nullptr } },
    { "instructions",     "inst",    { "FIXED_INSTRUCTIONS",    "INST_RETIRED.ANY",                "instructions",            nullptr } },
    { "branches",         "br",      { "INST_BRANCH",           "BR_INST_RETIRED.ALL_BRANCHES",    "branches",                nullptr } },
    { "branch-misses",    "br-ms",   { "BRANCH_MISPRED_NONSPEC","BRANCH_MISPREDICT",               "BR_MISP_RETIRED.ALL_BRANCHES", "branch-misses", nullptr } },
    { "l1d-cache-misses", "l1d-ms",  { "L1D_CACHE_MISS_LD",     "L1D_CACHE_MISS_LD_NONSPEC",       "MEM_LOAD_RETIRED.L1_MISS","l1d-cache-misses", nullptr } },
    { "l1i-cache-misses", "l1i-ms",  { "L1I_CACHE_MISS_DEMAND", "ICACHE.MISSES",                   "l1i-cache-misses",        nullptr } },
    { "llc-misses",       "llc-ms",  { "LLC_MISS_LD",           "PL2_CACHE_MISS_LD",               "LONGEST_LAT_CACHE.MISS",  "llc-misses", nullptr } },
    { "l1d-tlb-misses",   "dtlb-ms", { "L1D_TLB_MISS",          "DTLB_MISS",                       "DTLB_LOAD_MISSES.WALK_COMPLETED", "l1d-tlb-misses", nullptr } },
    { "map-stalls",       "mapstl",  { "MAP_STALL",             "map-stalls",                      nullptr,                   nullptr } },
    { "dispatch-stalls",  "dispstl", { "DISPATCH_STALL",        "dispatch-stalls",                 nullptr,                   nullptr } },
};

// Which events to actually configure (must fit the core's PMC budget — current
// Apple cores expose 2 fixed + ~6 configurable, so 6 is the safe ceiling). Add a
// row above and an entry here to capture more; trim here if add_event fails.
inline constexpr const char* kDefaultSelection[] =
{
    "cycles",
    "instructions",
    "branch-misses",
    "l1d-cache-misses",
    "l1i-cache-misses",
    "llc-misses",
};

inline const char* label_for( const char* alias ) noexcept
{
    for( const EventDesc& d : kEvents )
    {
        if( std::strcmp( d.alias, alias ) == 0 )
        {
            return d.label;
        }
    }
    return alias;
}

inline bool resolve_event( kpep_db* db, const char* alias, kpep_event** out ) noexcept
{
    // try the alias verbatim first (some DBs expose the friendly name directly)
    if( g_api.kpep_db_event( db, alias, out ) == 0 && *out )
    {
        PMC_DIAG( "resolved '%s' -> '%s' (verbatim)\n", alias, alias );
        return true;
    }

    // otherwise walk this alias's hardware probes in order
    for( const EventDesc& d : kEvents )
    {
        if( std::strcmp( d.alias, alias ) != 0 )
        {
            continue;
        }

        for( const char* probe : d.probes )
        {
            if( !probe )
            {
                break;
            }
            if( g_api.kpep_db_event( db, probe, out ) == 0 && *out )
            {
                PMC_DIAG( "resolved '%s' -> '%s'\n", alias, probe );
                return true;
            }
        }
    }
    return false;
}

// ============================================================================
// PerfState — everything resolved once at init; read-only on the hot path.
// ============================================================================
struct PerfState
{
    bool         ok            = false;
    kpep_db*     db            = nullptr;
    kpep_config* cfg           = nullptr;
    uint32_t     classes       = 0;
    uint32_t     counter_count = 0;     // raw counters per thread read
    unsigned     event_count   = 0;     // logical events we configured

    const char* names [ kMaxEvents ] {}; // logical alias per slot (for the banner)
    const char* labels[ kMaxEvents ] {}; // short header label per slot
    size_t      kpc_map[ kMaxEvents ] {};// slot -> index into the raw counter array
};

inline PerfState     g_perf;
inline std::once_flag g_once;

// global, one-time: load the ABI, build the config, arm the counters
inline void ensure_global_init() noexcept
{
    std::call_once( g_once, []() noexcept
    {
        PMC_DIAG( "init: euid=%u (root needed unless entitled)\n", unsigned( geteuid() ) );

        if( !load_api() )
        {
            PMC_DIAG( "FAIL load_api: kperf/kperfdata dlopen or a symbol is missing\n" );
            return;
        }

        if( g_api.kpep_db_create( nullptr, &g_perf.db ) != 0 || !g_perf.db )
        {
            PMC_DIAG( "FAIL kpep_db_create (no event DB for this CPU?)\n" );
            return;
        }

        if( g_api.kpep_config_create( g_perf.db, &g_perf.cfg ) != 0 || !g_perf.cfg )
        {
            PMC_DIAG( "FAIL kpep_config_create\n" );
            return;
        }

        // MUST precede add_event: adding a fixed event (FIXED_CYCLES/INSTRUCTIONS)
        // before the counters are forced returns KPEP_ERR_COUNTERS_NOT_FORCED (13).
        g_api.kpep_config_force_counters( g_perf.cfg );

        // Per-event graceful skip: event names + the PMC budget vary by core, so a
        // requested event that won't resolve / add just drops a column rather than
        // killing the whole report. We only bail if NOTHING resolves.
        const unsigned want = unsigned( sizeof( kDefaultSelection ) / sizeof( kDefaultSelection[ 0 ] ) );
        unsigned       slot = 0;

        for( unsigned i = 0; i < want && slot < kMaxEvents; ++i )
        {
            kpep_event* ev = nullptr;
            if( !resolve_event( g_perf.db, kDefaultSelection[ i ], &ev ) )
            {
                PMC_DIAG( "skip '%s' (not in this core's DB)\n", kDefaultSelection[ i ] );
                continue;
            }

            uint32_t err = 0;
            const int rc = g_api.kpep_config_add_event( g_perf.cfg, &ev, 0, &err );
            if( rc != 0 )
            {
                PMC_DIAG( "skip '%s' (add rc=%d err=%u; PMC budget?)\n", kDefaultSelection[ i ], rc, err );
                continue;
            }

            g_perf.names [ slot ] = kDefaultSelection[ i ];
            g_perf.labels[ slot ] = label_for( kDefaultSelection[ i ] );
            ++slot;
        }

        g_perf.event_count = slot;
        if( slot == 0 )
        {
            PMC_DIAG( "FAIL: no requested events resolved on this core\n" );
            return;
        }

        if( g_api.kpep_config_kpc_classes( g_perf.cfg, &g_perf.classes ) != 0 )
        {
            PMC_DIAG( "FAIL kpep_config_kpc_classes\n" );
            return;
        }

        size_t kpc_count = 0;
        if( g_api.kpep_config_kpc_count( g_perf.cfg, &kpc_count ) != 0 )
        {
            PMC_DIAG( "FAIL kpep_config_kpc_count\n" );
            return;
        }
        g_perf.counter_count = uint32_t( kpc_count );

        // config words (count-sized) ... and the slot->raw-index map (BYTE-sized:
        // Apple's two kpep_config_kpc* calls disagree on units — preserve both)
        kpc_config_t regs[ 64 ] {};
        if( g_api.kpep_config_kpc( g_perf.cfg, regs, sizeof( regs ) / sizeof( regs[ 0 ] ) ) != 0 )
        {
            PMC_DIAG( "FAIL kpep_config_kpc\n" );
            return;
        }

        if( g_api.kpep_config_kpc_map( g_perf.cfg, g_perf.kpc_map, sizeof( g_perf.kpc_map ) ) != 0 )
        {
            PMC_DIAG( "FAIL kpep_config_kpc_map\n" );
            return;
        }

        // arm: take ownership of all counters, push the config, start counting.
        // The force/set calls are the privileged ones — they fail without root or
        // the entitlement, or if another tool (Instruments) holds the counters.
        int prev = 0;
        g_api.kpc_force_all_ctrs_get( &prev );
        if( g_api.kpc_force_all_ctrs_set( 1 ) != 0 )
        {
            PMC_DIAG( "FAIL kpc_force_all_ctrs_set (privilege? counters busy?)\n" );
            return;
        }

        if( g_api.kpc_set_config( g_perf.classes, regs ) != 0 )
        {
            PMC_DIAG( "FAIL kpc_set_config\n" );
            return;
        }

        if( g_api.kpc_set_counting( g_perf.classes ) != 0 )
        {
            PMC_DIAG( "FAIL kpc_set_counting\n" );
            return;
        }

        g_perf.ok = true;
        PMC_DIAG( "OK: %u events armed, %u raw counters\n", g_perf.event_count, g_perf.counter_count );
    } );
}

// per-thread: enable counting for the calling thread (each profiled thread does
// this once, from profileScope.h's per-thread registration)
inline void ensure_thread_counting() noexcept
{
    ensure_global_init();
    if( g_perf.ok )
    {
        g_api.kpc_set_thread_counting( g_perf.classes );
    }
}

// ---- hot path: read all configured counters for the calling thread ----------
// The first arg is 0 == "current thread". Passing a real pthread/system tid (as
// the original snippet did) is NOT understood by this call and silently yields
// all-zero counters. KPC_MAX_COUNTERS (the buffer capacity) is the documented
// count argument, not the configured-event count.
ALWAYS_INLINE Snapshot read() noexcept
{
    Snapshot s {};
    if( !g_perf.ok )
    {
        return s;
    }

    uint64_t  raw[ 64 ] {};
    const int rc = g_api.kpc_get_thread_counters( 0, sizeof( raw ) / sizeof( raw[ 0 ] ), raw );

#if PROFILE_PMC_VERBOSE
    static thread_local bool logged = false;
    if( !logged )
    {
        logged = true;
        PMC_DIAG( "first read: rc=%d cc=%u raw[0..2]=%llu,%llu,%llu\n", rc, g_perf.counter_count,
                  (unsigned long long) raw[ 0 ], (unsigned long long) raw[ 1 ], (unsigned long long) raw[ 2 ] );
    }
#endif

    if( rc != 0 )
    {
        return s;
    }

    for( unsigned i = 0; i < g_perf.event_count; ++i )
    {
        s.values[ i ] = raw[ g_perf.kpc_map[ i ] ];
    }

    return s;
}

}   // namespace pmc
}   // namespace prof

#define PROF_PMC_REAL_BACKEND 1

#elif defined( __linux__ )   // ===== Linux: perf_event_open backend (x86 and ARM alike) =====

//  DESIGN (mirrors the kperf side's posture, different kernel surface):
//    * One event GROUP per thread — the first surviving event is the leader, every other event joins
//      via group_fd, and the leader's read_format is PERF_FORMAT_GROUP | ID | TOTAL_TIME_ENABLED/RUNNING.
//      The kernel schedules a group atomically (every column covers the same instruction window) and the
//      hot-path read is ONE syscall for all events. The grouped-read shape follows Filament's
//      utils::Profiler (google/filament, libs/utils — Apache-2.0), adapted to this file's snapshot
//      surface and per-thread arming; the id→slot map is this backend's analogue of kpc_map.
//    * The leader is PINNED: the group is either truly on the PMU or in error state — the kernel is
//      never allowed to multiplex it, so a reported delta is always a raw truth, never a silent scale.
//      An over-budget group is detected at arm time (a pinned group in error reads back 0 bytes) and
//      handled by dropping the last PMU-consuming event and re-arming — a column disappears, honestly,
//      per the same graceful-skip rule the kperf side applies per event. That skip applies to the
//      LEADER too: leadership just falls to the first event that opens, so a box whose kernel refuses
//      `cycles` (vPMU-less VMs refuse every hardware event) still arms whatever it does offer — the
//      trailing PERF_TYPE_SOFTWARE rows (task-clock, page-faults) in the worst case, which exist on
//      every Linux and keep per-scope counts flowing where the old shape went silently dark.
//    * exclude_kernel + exclude_hv, so the default perf_event_paranoid=2 admits us: no root, no
//      CAP_PERFMON. EACCES / ENOENT (no PMU — most VMs) degrade to active()==false, silently.
//    * The FIRST thread to arm (main, per profileScope.h's registration order) decides the surviving
//      event selection and publishes it in g_perf; every later thread opens exactly that selection so
//      the report's columns mean the same thing on every row. A later thread whose open fails reads
//      zeros — same shape as a failed kpc_get_thread_counters read on the Apple side.

#include <cerrno>
#include <linux/perf_event.h>
#include <mutex>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace prof
{
namespace pmc
{

// ============================================================================
// Event table — declarative, same logical aliases and labels as the kperf side
// so a report reads identically across platforms. type/config are the kernel's
// generic event encodings; unsupported rows drop out per-event at arm time.
// ============================================================================
struct EventDesc
{
    const char*   alias;      // logical name (printed in the banner)
    const char*   label;      // short header label for the report table
    std::uint32_t type;       // PERF_TYPE_*
    std::uint64_t config;     // PERF_COUNT_* (or the HW_CACHE triple encoding)
};

inline constexpr std::uint64_t hw_cache_config( std::uint64_t cache, std::uint64_t op, std::uint64_t result ) noexcept
{
    return cache | ( op << 8 ) | ( result << 16 );
}

// The two trailing rows are PERF_TYPE_SOFTWARE — kernel-maintained counts that exist on every Linux,
// PMU or not, and never occupy a hardware counter slot. On bare metal they ride along for free inside
// the hardware group; on the vPMU-less VMs most cloud/CI boxes are (every PERF_TYPE_HARDWARE open
// fails with ENOENT there) they are what keeps the backend ACTIVE, so a profile still carries honest
// per-scope task-clock (on-CPU ns — its gap against the wall column is off-CPU time) and page-fault
// counts instead of dropping every counter column. Distinctly named columns, never a silent stand-in.
inline constexpr EventDesc kEvents[] =
{
    { "cycles",           "cyc",      PERF_TYPE_HARDWARE, PERF_COUNT_HW_CPU_CYCLES },
    { "instructions",     "inst",     PERF_TYPE_HARDWARE, PERF_COUNT_HW_INSTRUCTIONS },
    { "branch-misses",    "br-ms",    PERF_TYPE_HARDWARE, PERF_COUNT_HW_BRANCH_MISSES },
    { "l1d-cache-misses", "l1d-ms",   PERF_TYPE_HW_CACHE, hw_cache_config( PERF_COUNT_HW_CACHE_L1D, PERF_COUNT_HW_CACHE_OP_READ, PERF_COUNT_HW_CACHE_RESULT_MISS ) },
    { "l1i-cache-misses", "l1i-ms",   PERF_TYPE_HW_CACHE, hw_cache_config( PERF_COUNT_HW_CACHE_L1I, PERF_COUNT_HW_CACHE_OP_READ, PERF_COUNT_HW_CACHE_RESULT_MISS ) },
    { "llc-misses",       "llc-ms",   PERF_TYPE_HARDWARE, PERF_COUNT_HW_CACHE_MISSES },
    { "task-clock",       "task-clk", PERF_TYPE_SOFTWARE, PERF_COUNT_SW_TASK_CLOCK },
    { "page-faults",      "pgflt",    PERF_TYPE_SOFTWARE, PERF_COUNT_SW_PAGE_FAULTS },
};

inline constexpr unsigned kEventTableCount = unsigned( sizeof( kEvents ) / sizeof( kEvents[ 0 ] ) );
static_assert( kEventTableCount <= kMaxEvents, "event table must fit the shared Snapshot" );

// ============================================================================
// PerfState — the first thread's surviving selection; read-only afterwards.
// ============================================================================
struct PerfState
{
    bool        ok          = false;
    unsigned    event_count = 0;               // events that survived the fit loop
    unsigned    table_index[ kMaxEvents ] {};  // slot -> row in kEvents
    const char* names [ kMaxEvents ] {};
    const char* labels[ kMaxEvents ] {};
};

inline PerfState      g_perf;
inline std::once_flag g_once;

// the group-read layout for PERF_FORMAT_GROUP | ID | TOTAL_TIME_ENABLED | TOTAL_TIME_RUNNING
struct GroupRead
{
    std::uint64_t nr;
    std::uint64_t time_enabled;
    std::uint64_t time_running;
    struct
    {
        std::uint64_t value;
        std::uint64_t id;
    } cnt[ kMaxEvents ];
};

// per-thread arming: the group's fds plus the id-derived slot -> cnt[] index map
struct ThreadCounters
{
    bool     tried    = false;
    bool     ok       = false;
    unsigned fd_count = 0;
    int      fds[ kMaxEvents ] {};
    unsigned value_index[ kMaxEvents ] {};

    void close_all() noexcept
    {
        for( unsigned i = 0; i < fd_count; ++i )
        {
            ::close( fds[ i ] );
        }
        fd_count = 0;
        ok       = false;
    }

    ~ThreadCounters() { close_all(); }
};

inline thread_local ThreadCounters t_counters;

inline long sys_perf_event_open( perf_event_attr* attr, pid_t pid, int cpu, int group_fd, unsigned long flags ) noexcept
{
    return ::syscall( __NR_perf_event_open, attr, pid, cpu, group_fd, flags );
}

// open one selection (rows tableIndices[0..selectedCount)) as a pinned group for the calling thread.
// Per-event graceful skip — for EVERY event, the would-be leader included: an event the kernel refuses
// outright just drops its column, and leadership falls to the first event that actually opens (on a
// vPMU-less VM that is the first software row, after every hardware open fails with ENOENT). Returns
// false only when NOTHING opens (no PMU and no software events = paranoid/seccomp lockdown) — budget
// overflows surface later, at the arm-time self check, because a pinned group only goes to error state
// when it first fails to schedule.
inline bool open_group( ThreadCounters& tc, const unsigned* tableIndices, unsigned selectedCount, unsigned* openedRows, unsigned* openedCount ) noexcept
{
    tc.close_all();
    *openedCount = 0;

    for( unsigned i = 0; i < selectedCount; ++i )
    {
        const EventDesc& desc     = kEvents[ tableIndices[ i ] ];
        const bool       isLeader = tc.fd_count == 0;

        perf_event_attr attr {};
        attr.size           = sizeof( attr );
        attr.type           = desc.type;
        attr.config         = desc.config;
        attr.disabled       = isLeader ? 1 : 0;    // the whole group arms via one ioctl on the leader
        attr.pinned         = isLeader ? 1 : 0;    // on the PMU for real, or in error state — never multiplexed
        attr.exclude_kernel = 1;                   // paranoid=2 (the common default) then admits us
        attr.exclude_hv     = 1;
        attr.inherit        = 0;                   // per-thread truth; children arm their own groups
        attr.read_format    = PERF_FORMAT_GROUP | PERF_FORMAT_ID | PERF_FORMAT_TOTAL_TIME_ENABLED | PERF_FORMAT_TOTAL_TIME_RUNNING;

        const int groupFd = isLeader ? -1 : tc.fds[ 0 ];
        const long fd     = sys_perf_event_open( &attr, 0, -1, groupFd, 0 );
        if( fd < 0 )
        {
            PMC_DIAG( "open '%s' failed (errno=%d) — column dropped%s\n", desc.alias, errno, isLeader ? ", leadership passes to the next event that opens" : "" );
            continue;                              // graceful per-event skip, leader included — same rule as the kperf side
        }

        tc.fds[ tc.fd_count ]        = int( fd );
        openedRows[ *openedCount ]   = tableIndices[ i ];
        ++tc.fd_count;
        ++*openedCount;
    }

    return tc.fd_count > 0;
}

// arm the group and prove it is genuinely counting: enable, burn a short dependent loop, read back.
// A pinned group that did not fit reads 0 bytes (error state) — the caller then shrinks and retries.
inline bool arm_and_verify( ThreadCounters& tc, GroupRead* out ) noexcept
{
    if( ::ioctl( tc.fds[ 0 ], PERF_EVENT_IOC_RESET,  PERF_IOC_FLAG_GROUP ) != 0 ||
        ::ioctl( tc.fds[ 0 ], PERF_EVENT_IOC_ENABLE, PERF_IOC_FLAG_GROUP ) != 0 )
    {
        PMC_DIAG( "group reset/enable ioctl failed (errno=%d)\n", errno );
        return false;
    }

    volatile std::uint64_t spin = 0;
    for( unsigned i = 0; i < 50'000; ++i )
    {
        spin += i;
    }

    const ssize_t got = ::read( tc.fds[ 0 ], out, sizeof( *out ) );
    if( got < ssize_t( 3 * sizeof( std::uint64_t ) ) || out->nr != tc.fd_count )
    {
        PMC_DIAG( "group verify read got=%zd nr=%llu (want %u fds) — over PMU budget?\n",
                  got, ( unsigned long long ) ( got > 0 ? out->nr : 0 ), tc.fd_count );
        return false;
    }
    if( out->time_running == 0 )
    {
        PMC_DIAG( "group verify: time_running==0 — pinned group never scheduled\n" );
        return false;
    }
    return true;
}

// map slot -> index in the group read via PERF_FORMAT_ID (creation order is the kernel's business, not ours)
inline bool map_value_indices( ThreadCounters& tc, const GroupRead& probe ) noexcept
{
    for( unsigned slot = 0; slot < tc.fd_count; ++slot )
    {
        std::uint64_t id = 0;
        if( ::ioctl( tc.fds[ slot ], PERF_EVENT_IOC_ID, &id ) != 0 )
        {
            PMC_DIAG( "PERF_EVENT_IOC_ID failed for slot %u (errno=%d)\n", slot, errno );
            return false;
        }

        bool found = false;
        for( unsigned i = 0; i < probe.nr && i < kMaxEvents; ++i )
        {
            if( probe.cnt[ i ].id == id )
            {
                tc.value_index[ slot ] = i;
                found                  = true;
                break;
            }
        }
        if( !found )
        {
            PMC_DIAG( "id %llu for slot %u missing from group read\n", ( unsigned long long ) id, slot );
            return false;
        }
    }
    return true;
}

// first thread only: shrink-until-it-fits, then publish the surviving selection for every later thread
inline void select_and_arm_first_thread( ThreadCounters& tc ) noexcept
{
    unsigned candidates[ kMaxEvents ];
    unsigned candidateCount = kEventTableCount;
    for( unsigned i = 0; i < kEventTableCount; ++i )
    {
        candidates[ i ] = i;
    }

    while( candidateCount > 0 )
    {
        unsigned  openedRows[ kMaxEvents ];
        unsigned  openedCount = 0;
        GroupRead probe {};

        if( !open_group( tc, candidates, candidateCount, openedRows, &openedCount ) )
        {
            tc.close_all();
            return;                                // leader refused: no PMU / no permission — stay inactive
        }
        if( arm_and_verify( tc, &probe ) && map_value_indices( tc, probe ) )
        {
            for( unsigned slot = 0; slot < openedCount; ++slot )
            {
                g_perf.table_index[ slot ] = openedRows[ slot ];
                g_perf.names [ slot ]      = kEvents[ openedRows[ slot ] ].alias;
                g_perf.labels[ slot ]      = kEvents[ openedRows[ slot ] ].label;
            }
            g_perf.event_count = openedCount;
            g_perf.ok          = true;
            tc.ok              = true;
            PMC_DIAG( "OK: %u events armed (pinned group)\n", openedCount );
            return;
        }

        // over budget: drop the LAST PMU-consuming event and retry — a disclosed missing column, never
        // a scaled one. Software rows are skipped over when picking the victim: they occupy no hardware
        // counter slot, so dropping one can never make a pinned group fit (it would just burn a retry
        // and lose a free column).
        unsigned dropIndex = openedCount;                  // index into openedRows[] to remove
        for( unsigned i = openedCount; i-- > 0; )
        {
            if( kEvents[ openedRows[ i ] ].type != PERF_TYPE_SOFTWARE )
            {
                dropIndex = i;
                break;
            }
        }
        if( dropIndex == openedCount )                     // defensive: nothing PMU-consuming left to shed
        {
            dropIndex = openedCount - 1;
        }

        candidateCount = 0;
        for( unsigned i = 0; i < openedCount; ++i )
        {
            if( i != dropIndex )
            {
                candidates[ candidateCount++ ] = openedRows[ i ];
            }
        }
        PMC_DIAG( "dropped '%s', retrying with %u events\n", kEvents[ openedRows[ dropIndex ] ].alias, candidateCount );
    }

    tc.close_all();
}

// later threads: open exactly the published selection (columns must mean the same thing on every row)
inline bool open_published_selection( ThreadCounters& tc ) noexcept
{
    unsigned  openedRows[ kMaxEvents ];
    unsigned  openedCount = 0;
    GroupRead probe {};

    if( !open_group( tc, g_perf.table_index, g_perf.event_count, openedRows, &openedCount ) ||
        openedCount != g_perf.event_count ||
        !arm_and_verify( tc, &probe ) || !map_value_indices( tc, probe ) )
    {
        tc.close_all();
        return false;                              // this thread reads zeros; the selection stays intact
    }
    return true;
}

// ---- the public surface (mirrors the kperf side exactly) --------------------
inline void ensure_thread_counting() noexcept
{
    ThreadCounters& tc = t_counters;
    if( tc.tried )
    {
        return;
    }
    tc.tried = true;

    std::call_once( g_once, [ &tc ]() noexcept { select_and_arm_first_thread( tc ); } );

    if( g_perf.ok && !tc.ok )
    {
        tc.ok = open_published_selection( tc );
    }
}

// hot path: one grouped read() syscall returns every counter for the calling thread
ALWAYS_INLINE Snapshot read() noexcept
{
    Snapshot s;
    const ThreadCounters& tc = t_counters;
    if( !tc.ok )
    {
        return s;
    }

    GroupRead buf;
    if( ::read( tc.fds[ 0 ], &buf, sizeof( buf ) ) < ssize_t( 3 * sizeof( std::uint64_t ) ) )
    {
        return s;                                  // group died post-arm (PMU stolen): zeros, not lies
    }
    for( unsigned slot = 0; slot < tc.fd_count && slot < kMaxEvents; ++slot )
    {
        s.values[ slot ] = buf.cnt[ tc.value_index[ slot ] ].value;
    }
    return s;
}

}   // namespace pmc
}   // namespace prof

#define PROF_PMC_REAL_BACKEND 1

#else   // ===== other platforms: inert stubs, timing path stays intact =====

namespace prof
{
namespace pmc
{

inline void        ensure_thread_counting() noexcept {}
ALWAYS_INLINE Snapshot read() noexcept { return {}; }
inline bool        active()      noexcept { return false; }
inline unsigned    event_count() noexcept { return 0; }
inline const char* event_name ( unsigned ) noexcept { return ""; }
inline const char* event_label( unsigned ) noexcept { return ""; }

}   // namespace pmc
}   // namespace prof

#endif

#if defined( PROF_PMC_REAL_BACKEND )

// ---- reporter-facing accessors, shared by every real backend ----------------
// Both backends publish the same four PerfState fields (ok / event_count / names / labels); defining the
// accessors once here keeps the two arms from drifting apart. NOTE event_count() reports events
// CONFIGURED — on Apple it can be nonzero when arming failed (unprivileged); every reporter-facing
// consumer gates through active() (see profileScope.h's effectiveEventCount), so a zero from active()
// silences the columns regardless.
namespace prof
{
namespace pmc
{

inline bool        active()      noexcept { return g_perf.ok; }
inline unsigned    event_count() noexcept { return g_perf.event_count; }
inline const char* event_name ( unsigned i ) noexcept { return i < g_perf.event_count ? g_perf.names [ i ] : ""; }
inline const char* event_label( unsigned i ) noexcept { return i < g_perf.event_count ? g_perf.labels[ i ] : ""; }

}   // namespace pmc
}   // namespace prof

#undef PROF_PMC_REAL_BACKEND

#endif
