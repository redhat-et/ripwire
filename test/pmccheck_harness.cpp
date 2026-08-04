// pmccheck_harness.cpp — honesty gate for the PROFILE_SCOPE hardware-counter (PMC) backend
// (src/infra/profilePmc.h): whatever platform this compiles on, the backend must land in one of exactly
// two truthful states, and this harness asserts the WHOLE contract of whichever one it observes:
//
//   ACTIVE    (privileged macOS/arm64, or a Linux box whose PMU is exposed and perf_event_paranoid
//             admits self-profiling): event_count() >= 1, every configured slot has a non-empty
//             name/label, and a 4M-iteration serially-dependent multiply loop advances some counter by
//             at least 1M — a counter that "works" but reads garbage/zero deltas is a lie the timing
//             columns would inherit.
//   INACTIVE (unprivileged macOS, VMs without a vPMU, paranoid>=3, Rosetta): active()==false,
//             event_count()==0, read() returns all-zero Snapshots, and NOTHING is printed to stderr —
//             the quiet-degrade contract (an unprivileged run must not spam).
//
// Either state passes; an inconsistent mixture (active with zero events, inactive with nonzero reads,
// stderr noise) fails. The gate script captures stderr separately to enforce the quiet-degrade arm.
// Compiled with -DPROFILE_ENABLED=1 -DPROFILE_AUTO_REPORT=0; prof::report() is invoked explicitly so the
// report path (which drops counter columns when inactive) is exercised in both states.
//
// Exit 0 = the observed state is internally honest; nonzero = a contract violation (PASS/FAIL lines on stdout).

#include "profileScope.h"

#include "../src/hashutil.h"

#include <cstdint>
#include <cstdio>

#if defined( __linux__ )
  #include <linux/perf_event.h>
  #include <sys/syscall.h>
  #include <unistd.h>
#endif

static int g_fail = 0;

#if defined( __linux__ )
// Does the kernel offer ANY self-profiling counter to this process? Mirrors the backend's exact attr
// posture (exclude_kernel/hv, pid=0, cpu=-1). PERF_COUNT_SW_TASK_CLOCK is the canonical always-there
// software event: it needs no PMU and no privilege at perf_event_paranoid<=2, so it opens on
// vPMU-less VMs/containers where every PERF_TYPE_HARDWARE open fails with ENOENT. If this opens while
// the backend sits INACTIVE, the backend left an offered counter unused — the graceful-skip contract
// ("bail to active()==false only if NOTHING opens") is being violated, not honestly degraded.
static bool kernelOffersSoftwareCounter()
{
    perf_event_attr attr {};
    attr.size           = sizeof( attr );
    attr.type           = PERF_TYPE_SOFTWARE;
    attr.config         = PERF_COUNT_SW_TASK_CLOCK;
    attr.exclude_kernel = 1;
    attr.exclude_hv     = 1;

    const long fd = ::syscall( __NR_perf_event_open, &attr, 0, -1, -1, 0 );
    if( fd < 0 )
    {
        return false;
    }

    ::close( int( fd ) );
    return true;
}
#endif

static void check( bool cond, const char* msg )
{
    std::printf( "  %s  %s\n", cond ? "PASS" : "FAIL", msg );
    if( !cond )
    {
        g_fail = 1;
    }
}

// Serially-dependent integer work: several instructions per iteration that no compiler can fuse away
// (the result feeds a volatile sink). 4M iterations ⇒ >> 1M retired instructions, safely past the bar.
// Deliberately NOT the house FNV loop shape — that would clone the reused byteHash/cloneSketchMatches
// helpers; this is a xorshift-multiply mix that exists only to burn a known floor of instructions.
static std::uint64_t busyWork( std::uint64_t iterationCount )
{
    std::uint64_t acc = 0x9E3779B97F4A7C15ull;
    for( std::uint64_t i = 0; i < iterationCount; ++i )
    {
        acc  = rw::hashutil::multiplyModulo64( acc ^ ( acc >> 29 ), 0x2545F4914F6CDD1Dull );
        acc ^= rw::hashutil::multiplyModulo64( i + 1, 0x9E3779B97F4A7C15ull );
    }
    return acc;
}

int main()
{
    // a nested pair of scopes so the report has rows in both states (and the PMC bracket runs when active)
    {
        PROFILE_SCOPE_DESCRIBE( "pmccheck: outer" );
        volatile std::uint64_t sink = 0;
        {
            PROFILE_SCOPE_DESCRIBE( "pmccheck: inner busy loop" );
            sink += busyWork( 1'000'000 );
        }
    }

    prof::pmc::ensure_thread_counting();
    const bool     isActive   = prof::pmc::active();
    const unsigned eventCount = prof::pmc::event_count();
    std::printf( "pmc state: %s  events=%u\n", isActive ? "ACTIVE" : "INACTIVE", eventCount );

    if( isActive )
    {
        check( eventCount >= 1, "active: at least one event armed" );

        bool namesPresent = true;
        for( unsigned slot = 0; slot < eventCount; ++slot )
        {
            namesPresent = namesPresent && prof::pmc::event_name( slot )[ 0 ] != '\0' && prof::pmc::event_label( slot )[ 0 ] != '\0';
        }
        check( namesPresent, "active: every armed slot carries a name and a label (the report banner depends on it)" );

        // bracket the busy loop the same way ScopedTimer does and demand a plausible delta
        const prof::pmc::Snapshot before = prof::pmc::read();
        volatile std::uint64_t sink = busyWork( 4'000'000 );
        (void) sink;
        const prof::pmc::Snapshot after = prof::pmc::read();

        bool anyPlausible  = false;
        bool anyBackwards  = false;
        for( unsigned slot = 0; slot < eventCount; ++slot )
        {
            const std::uint64_t delta = after.values[ slot ] - before.values[ slot ];
            anyPlausible = anyPlausible || ( delta > 1'000'000ull );
            anyBackwards = anyBackwards || ( delta > ( 1ull << 62 ) );   // an underflowed (non-monotonic) counter shows as a huge delta
        }
        check( anyPlausible, "active: some counter advanced >1M across a 4M-iteration dependent loop" );
        check( !anyBackwards, "active: no counter ran backwards across the bracket (monotonic per-thread contract)" );
    }
    else
    {
        // NOTE the deliberate scope of this arm: event_count() reports events CONFIGURED, which on Apple
        // can be nonzero even when arming failed (unprivileged) — every reporter-facing consumer gates
        // through active() (profileScope.h effectiveEventCount: `active() ? event_count() : 0`), so the
        // inactive contract is "reads are zero and nothing downstream prints columns", not "count is 0".
        const prof::pmc::Snapshot snapshot = prof::pmc::read();
        bool allZero = true;
        for( unsigned slot = 0; slot < prof::pmc::kMaxEvents; ++slot )
        {
            allZero = allZero && snapshot.values[ slot ] == 0;
        }
        check( allZero, "inactive: read() returns all-zero Snapshots (the timing path stays untouched)" );

#if defined( __linux__ )
        // INACTIVE is only honest when the kernel truly offers nothing. Software events (task-clock,
        // page-faults) exist on every Linux, PMU or not — a backend that goes dark while one of those
        // opens has dropped counters it could have armed, which the per-event graceful-skip contract
        // forbids ("bail to active()==false only if NOTHING opens").
        check( !kernelOffersSoftwareCounter(),
               "inactive: the kernel offers no counter at all (software fallback armed when available)" );
#endif
    }

    // the report must render in both states (counter columns present iff active); stderr silence is
    // asserted by the gate script, which captures the streams separately.
    prof::report();

    return g_fail;
}
