// parallelforcheck_harness.cpp — arms A and B of test/parallelforcheck.sh.
//
// WHAT IS BEING PINNED. warmsnap::parallelFor picks its worker count from the ITEM COUNT:
// workers = min( hardware_concurrency, ceil( n / itemsPerWorker ) ), serial at one worker. The
// default itemsPerWorker of 2048 is right for a caller whose item is cheap and wrong for one whose
// item is coarse: readRefRows passes the CHUNK count, each chunk is 4096 rows costing ~163 us, and
// at llvm-project scale ceil( 1449 / 2048 ) == 1, so ~5.94 M reference rows decoded on one core of
// eighteen. The fix is an opt-in third argument, and these arms pin both halves of it: that a caller
// CAN ask for coarse-item parallelism, and that a caller which does not ask sees exactly what it saw
// before.
//
// WHY THREAD IDS AND NOT TIMINGS. The house rule is no perf-budget gates, and a timing gate on a
// shared CI runner is a flake. A COUNT of distinct thread ids is contention-proof: it says whether
// the work was handed to more than one worker, which is the contract, and says nothing about speed.
//
// Arms:
//   A1  itemsPerWorker = 1 and n >= 2  =>  more than one distinct thread id (skipped, with a reason,
//       on a single-core box, where no arrangement of this code could show it).
//   A2  the DEFAULT and n = 287 (envoy's real chunk count)  =>  exactly one thread id. This is the
//       preserved-behaviour half: it is what every untouched call site still gets, including
//       verbfs_qmetrics.h, whose digest is folded in block order and must not be reordered.
//   B   identity across worker counts: a battery of n, each run serially and at itemsPerWorker = 1,
//       must produce identical output.
//   Bp  B's POISON: an order-dependent lambda must make B's comparison FAIL. Without this, a
//       comparison that could never fail would pass arm B in silence.
//
// Exit: 0 all arms held, 1 an arm failed, 2 could not run.

#include "warmsnap.h"

#include <algorithm>
#include <cstdio>
#include <chrono>
#include <mutex>
#include <set>
#include <thread>
#include <vector>

namespace
{
int failures = 0;

void ok( const char* what ) { std::printf( "  ok    %s\n", what ); }
void bad( const char* what ) { std::printf( "  FAIL  %s\n", what ); ++failures; }

// Distinct thread ids observed while running fn( i ) for n items at the given granularity.
//
// WHY A BARRIER AND NOT A BARE COUNT. The first version just inserted each thread id into a set, and
// it reported ONE thread even where parallelism was demonstrably happening (arm Bp saw it). The items
// were a mutex insert — a couple of microseconds for all 64 — while spawning a thread costs tens of
// microseconds, so the main thread (parallelFor runs `body()` on it too) drained the whole queue
// before any spawned worker arrived. That is a RACE in the gate, not a defect in the code, and an arm
// whose answer depends on which thread wins a start-up race is a timing arm wearing a count's clothes.
//
// Each item now registers its thread and then waits until a SECOND thread has registered, bounded by a
// deadline. With more than one worker the first arrival blocks, so the main thread cannot drain the
// queue and a second worker necessarily arrives: the positive is reliable. With one worker the single
// thread waits out the deadline and the answer is 1: the negative is reliable too, and costs the
// deadline only when the arm is going to fail anyway.
std::size_t threadsUsed( std::size_t n, std::size_t itemsPerWorker, bool useDefault )
{
    std::mutex                      lock;
    std::set<std::thread::id>       seen;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds( 5 );
    const auto note = [ & ]( std::size_t )
    {
        {
            const std::lock_guard<std::mutex> held( lock );
            seen.insert( std::this_thread::get_id() );
        }
        for( ;; )
        {
            {
                const std::lock_guard<std::mutex> held( lock );
                if( seen.size() >= 2 ) { return; }
            }
            if( std::chrono::steady_clock::now() >= deadline ) { return; }
            std::this_thread::yield();
        }
    };
    if( useDefault )
    {
        rw::warmsnap::parallelFor( n, note );
    }
    else
    {
        rw::warmsnap::parallelFor( n, note, itemsPerWorker );
    }
    return seen.size();
}

// the battery arm B and its poison both run over
const std::size_t kSizes[] = { 0, 1, 2, 7, 255, 256, 257, 2047, 2048, 2049, 5000 };

std::vector<std::size_t> byIndex( std::size_t n, bool parallel )
{
    std::vector<std::size_t> out( n, 0 );
    const auto fill = [ & ]( std::size_t i ) { out[ i ] = i * 3 + 1; };
    if( parallel )
    {
        rw::warmsnap::parallelFor( n, fill, 1 );
    }
    else
    {
        for( std::size_t i = 0; i < n; ++i ) { fill( i ); }
    }
    return out;
}

// DELIBERATELY order-dependent: appends in completion order, so a parallel run and a serial run
// disagree. Arm Bp requires that disagreement to be SEEN.
//
// --quality-delta reports this as 119 tokens duplicated from byIndex, and that is accurate but must
// NOT be refactored away: the near-identity is the experiment. byIndex writes slot i and byAppend
// pushes in completion order, and arm B's whole claim rests on the first being order-free while arm
// Bp's rests on the second not being. Merge them behind a flag and the poison stops poisoning.
std::vector<std::size_t> byAppend( std::size_t n, bool parallel )
{
    std::mutex               lock;
    std::vector<std::size_t> out;
    out.reserve( n );
    const auto push = [ & ]( std::size_t i )
    {
        const std::lock_guard<std::mutex> held( lock );
        out.push_back( i );
    };
    if( parallel )
    {
        rw::warmsnap::parallelFor( n, push, 1 );
    }
    else
    {
        for( std::size_t i = 0; i < n; ++i ) { push( i ); }
    }
    return out;
}
}   // namespace

int main()
{
    const unsigned hw = std::max( std::thread::hardware_concurrency(), 1u );
    std::printf( "parallelforcheck_harness: hardware_concurrency=%u\n", hw );

    // ── A1: a coarse-item caller can ask for parallelism ────────────────────────────────────────
    if( hw < 2 )
    {
        std::printf( "  SKIP  arm A1 (coarse-item caller gets more than one worker): this box reports "
                     "hardware_concurrency=%u, so no arrangement of this code could show it. A2 and B are asserted.\n", hw );
    }
    else
    {
        const std::size_t used = threadsUsed( 64, 1, false );
        if( used > 1 )
        {
            std::printf( "  ok    arm A1: itemsPerWorker=1 over 64 items used %zu distinct threads\n", used );
        }
        else
        {
            std::printf( "  FAIL  arm A1: itemsPerWorker=1 over 64 items used %zu thread — a coarse-item caller "
                         "cannot obtain parallelism, which is the whole defect this gate exists for\n", used );
            ++failures;
        }
    }

    // ── A2: a caller that does not ask sees exactly what it saw before ──────────────────────────
    // 287 is envoy's measured reference-chunk count: ceil( 287 / 2048 ) == 1, so the DEFAULT must
    // still serialise it. If this ever reads > 1, the default moved and every untouched call site
    // changed scheduling with it.
    {
        const std::size_t used = threadsUsed( 287, 0, true );
        if( used == 1 )
        {
            ok( "arm A2: the default over 287 items still uses exactly 1 thread (untouched callers unchanged)" );
        }
        else
        {
            std::printf( "  FAIL  arm A2: the default over 287 items used %zu threads — the default moved, so "
                         "call sites that never asked for parallelism have had their scheduling changed\n", used );
            ++failures;
        }
    }

    // ── B: identity across worker counts ────────────────────────────────────────────────────────
    {
        bool allSame = true;
        for( const std::size_t n : kSizes )
        {
            if( byIndex( n, false ) != byIndex( n, true ) )
            {
                std::printf( "  FAIL  arm B: n=%zu differs between a serial run and itemsPerWorker=1\n", n );
                allSame = false;
                ++failures;
            }
        }
        if( allSame )
        {
            ok( "arm B: index-writing output identical serial vs itemsPerWorker=1 over 11 sizes" );
        }
    }

    // ── Bp: arm B's poison. The comparison must be able to fail. ────────────────────────────────
    if( hw < 2 )
    {
        std::printf( "  SKIP  arm Bp (B's poison): needs more than one worker to produce a disagreement.\n" );
    }
    else
    {
        bool sawDifference = false;
        for( const std::size_t n : kSizes )
        {
            if( n >= 2 && byAppend( n, false ) != byAppend( n, true ) ) { sawDifference = true; }
        }
        if( sawDifference )
        {
            ok( "arm Bp: an order-dependent lambda IS seen to differ, so arm B's comparison can fail" );
        }
        else
        {
            bad( "arm Bp: an order-dependent lambda compared EQUAL at every size — arm B's comparison cannot "
                 "fail and therefore proved nothing" );
        }
    }

    std::printf( failures == 0 ? "parallelforcheck_harness: PASS\n" : "parallelforcheck_harness: FAIL\n" );
    return failures == 0 ? 0 : 1;
}
