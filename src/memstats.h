#pragma once
// RIPWIRE_STATS's memory readings (card M0 MEM-STATS, reports mem-audit-fable-1111): the process footprint and its lifetime
// peak at the phase boundaries that set a run's headline peak — the parse pool's join, the cache write, the model at rest,
// buildGraph's side tables built, its resolve loop done and its end. Before these lines, every per-phase figure needed lldb
// breakpoints; with them a memory card is one paired run, and the plateau ("graph-tables" minus "model") is a number a gate
// can bound (test/memstatscheck.sh).
//
// Env-gated stderr only: unset, the readers below cost one getenv each and print nothing, so stdout, stderr and rc of every
// ordinary run are unchanged. The footprint is os::mem_footprint (macOS phys_footprint, Linux VmRSS); a platform that cannot
// read it prints 0, which is a reading of "unknown", never of "nothing held".
#include "infra/emit.h"   // rw::emitTo
#include "infra/os.h"     // rw::os::mem_footprint / mem_footprint_peak

#include <cstdint>
#include <cstdlib>  // std::getenv
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

// one `[mem] phase=<phase> cur_mib=<now> peak_mib=<lifetime peak>` line when RIPWIRE_STATS is set
inline void mark( std::string_view phase )
{
    if( !enabled() )
    {
        return;
    }
    rw::emitTo( stderr, "[mem] phase={} cur_mib={:.1f} peak_mib={:.1f}\n", phase, mib( os::mem_footprint() ), mib( os::mem_footprint_peak() ) );
}
}   // namespace rw::memstats
