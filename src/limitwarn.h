#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings

// limitwarn.h — the USER-FACING warning when a work budget cuts an answer (LARGE-PARTIAL-1, owner 2026-11-14:
// "print a warning to the user whenever the limit is found").
//
// The answer already discloses every cut for the AGENT, in attributes (refs_omitted=, <unparsed>, …). A person running the
// CLI does not read those, so a cut also prints ONE stderr line naming what was cut, the limit, and the flag or option that
// raises it. stderr only: the answer's bytes on stdout are unchanged. At most kLimitWarnLines lines per process, then one
// line saying further warnings were collapsed (an MCP server is one process: the cap spans its session).

#include <atomic>
#include <cstdio>
#include <string_view>

namespace rw
{

constexpr unsigned kLimitWarnLines = 5;

inline std::atomic<unsigned> gLimitWarnLines{ 0 };   // the lines warnLimitReached spent this process (one MCP session included)

// `what`: what was cut, with its count ("--stray-content read the newest 512 of 602 local branches; 90 not read").
// `raise`: the flag or option that lifts it ("pass --detail=1 to read every branch").
inline void warnLimitReached( std::string_view what, std::string_view raise )
{
    const unsigned n = gLimitWarnLines.fetch_add( 1, std::memory_order_relaxed );
    if( n < kLimitWarnLines )
    {
        rw::emitTo( stderr, "ripwire: warning: {}; {}\n", what, raise );
    }
    else if( n == kLimitWarnLines )
    {
        rw::emitTo( stderr, "ripwire: warning: more limits were reached; further warnings this run are collapsed\n" );
    }
}

} // namespace rw
