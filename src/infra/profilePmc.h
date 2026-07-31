// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  profilePmc.h
//
//  Apple Silicon hardware performance-counter (PMC) backend for the scope
//  profiler (profileScope.h). It dlopen()s the private kperf / kperfdata
//  frameworks and exposes a tiny "read a snapshot of all counters" interface;
//  profileScope.h brackets each PROFILE_SCOPE with two reads and accumulates the
//  deltas, so the report can show cycles / instructions / branch-misses /
//  cache-misses PER SCOPE alongside the CNTVCT wall-clock time.
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

#include "fastmath.h"        // ALWAYS_INLINE, fastmath::min

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


#if defined( __APPLE__ ) && ( defined( __arm64__ ) || defined( __aarch64__ ) )

#include <dlfcn.h>
#include <mutex>
#include <unistd.h>          // geteuid (verbose diagnostics)

// ----- diagnostics (off by default: a missing entitlement is the common, quiet
//       case — we do not want every unprivileged run spamming stderr). Build with
//       -DPROFILE_PMC_VERBOSE=1 to trace exactly which init step fails + the euid. -
#ifndef PROFILE_PMC_VERBOSE
  #define PROFILE_PMC_VERBOSE 0
#endif

#if PROFILE_PMC_VERBOSE
  #define PMC_DIAG( ... ) std::fprintf( stderr, "prof::pmc: " __VA_ARGS__ )
#else
  #define PMC_DIAG( ... ) ( (void) 0 )
#endif

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
        return false;

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
    { "llc-misses",       "llc-ms",  { "LLC_MISS_LD",           "LONGEST_LAT_CACHE.MISS",          "llc-misses",              nullptr } },
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
        if( std::strcmp( d.alias, alias ) == 0 )
            return d.label;
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
            continue;

        for( const char* probe : d.probes )
        {
            if( !probe )
                break;
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
        g_api.kpc_set_thread_counting( g_perf.classes );
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
        return s;

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
        return s;

    for( unsigned i = 0; i < g_perf.event_count; ++i )
        s.values[ i ] = raw[ g_perf.kpc_map[ i ] ];

    return s;
}

// ---- reporter-facing accessors ----------------------------------------------
inline bool        active()      noexcept { return g_perf.ok; }
inline unsigned    event_count() noexcept { return g_perf.event_count; }
inline const char* event_name ( unsigned i ) noexcept { return i < g_perf.event_count ? g_perf.names [ i ] : ""; }
inline const char* event_label( unsigned i ) noexcept { return i < g_perf.event_count ? g_perf.labels[ i ] : ""; }

}   // namespace pmc
}   // namespace prof

#else   // ===== non-Apple / non-ARM64: inert stubs, timing path stays intact =====

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
