#pragma once
// RIPWIRE_STATS's memory readings (card M0 MEM-STATS, reports mem-audit-fable-1111): the process footprint and its lifetime
// peak at the phase boundaries that set a run's headline peak — the parse pool's join, the cache write, the model at rest,
// buildGraph's side tables built, its resolve loop done and its end. Before these lines, every per-phase figure needed lldb
// breakpoints; with them a memory card is one paired run, and the plateau ("graph-tables" minus "model") is a number a gate
// can bound (test/memstatscheck.sh).
//
// Env-gated stderr only: unset, the readers below cost one getenv each and print nothing, so stdout, stderr and rc of every
// ordinary run are unchanged. The footprint is os::mem_footprint (macOS phys_footprint, Linux VmRSS). Its readers return 0
// when they cannot read (os.h: "0 = unknown"); a reading of 0 prints `unavailable`, never `0.0`, so a consumer (a person, or
// test/memstatscheck.sh's plateau arm) cannot read an unknown as "nothing held" (CodeRabbit 4543019678).
#include "infra/emit.h"   // rw::emitTo
#include "infra/os.h"     // rw::os::mem_footprint / mem_footprint_peak

#include <cstdint>
#include <cstdlib>  // std::getenv
#include <format>   // std::format: a reading's MiB text
#include <string>
#include <string_view>

namespace rw::memstats
{
// read at each of the handful of call sites (no cache: a run asks it fewer than a dozen times)
inline bool enabled() noexcept
{
    return std::getenv( "RIPWIRE_STATS" ) != nullptr;
}

inline double mib( std::uint64_t bytes ) noexcept
{
    return double( bytes ) / ( 1024.0 * 1024.0 );
}

// One footprint reading as the [mem] lines print it: MiB to one decimal, or `unavailable` for the readers' 0 (unknown). THE TEST
// SEAM: RIPWIRE_TEST_MEMSTATS_UNREAD (any non-empty value) makes every reading unknown, the shape of a platform with no reader
// (os.h's #else branch), which a macOS or Linux gate run cannot otherwise reach (test/memstatscheck.sh arm U).
inline std::string reading( std::uint64_t bytes )
{
    const char* const unread = std::getenv( "RIPWIRE_TEST_MEMSTATS_UNREAD" );
    if( bytes == 0 || ( unread != nullptr && *unread != '\0' ) )
    {
        return "unavailable";
    }
    return std::format( "{:.1f}", mib( bytes ) );
}

// one `[mem] phase=<phase> cur_mib=<now> peak_mib=<lifetime peak>` line when RIPWIRE_STATS is set (either reading may be
// `unavailable`)
inline void mark( std::string_view phase )
{
    if( !enabled() )
    {
        return;
    }
    rw::emitTo( stderr, "[mem] phase={} cur_mib={} peak_mib={}\n", phase, reading( os::mem_footprint() ), reading( os::mem_footprint_peak() ) );
}
}   // namespace rw::memstats
