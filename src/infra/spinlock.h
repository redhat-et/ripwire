#pragma once
// spinlock.h — a test-and-test-and-set lock with capped doubling backoff, for the SHORT critical
// sections a std::mutex is the wrong shape for. Owner's design, 2026-11-15 (after Fedor Pikus, The Art
// of Writing Efficient Programs, ch. 6), with the backoff doubling added.
//
// THE PLAIN LOAD IS THE OPTIMIZATION, and it is worth saying exactly why, because the line it saves is
// invisible in a profile that only counts instructions. Taking the lock with an exchange on every
// attempt WRITES the flag's cache line. A write needs the line EXCLUSIVE, so every waiter's attempt
// invalidates it in every other core's cache — including the holder's, which then pays a miss to
// release it, and including the other waiters', who are only going to fail anyway. N waiters make
// O(N) coherence traffic per attempt and the holder gets slower the more company it has. The relaxed
// load does not need the line exclusive: while the lock is held, every waiter reads a SHARED copy out
// of its own cache and generates no traffic at all. Only a load that observes 0 goes on to the one
// write that can win. That is the whole trick, and `test/spinlockcheck.sh` arm (C) reads it out of the
// disassembly rather than trusting this comment.
//
// WHERE IT BELONGS, and where it does not. Spinning is right when the hold is a few hundred cycles and
// the waiter would otherwise pay a futex round trip to sleep and wake. It is WRONG when the hold is
// long: a spinner burns a core the holder may need, and on a loaded box it can keep the holder off the
// CPU it is waiting for. So this is for the short ones — `infra/internedtext.h`'s per-shard hash probe
// is the first consumer — and emphatically NOT for `quality.h`'s headSnapshotIngestMutex, which is held
// across a whole re-ingest, nor for any lock paired with a condition variable (there is nothing here to
// wait on). A spinlock is also not recursive and offers no timed acquire.
//
// WHY IT ALSO SHRINKS ITS CONSUMER. A std::mutex is 40 B on libstdc++ and 64 on libc++; this is 4. An
// InternedText shard is `alignas( destructive-interference )` so no two shards' locks share a line, and
// at 40 B + vector + size the shard needed TWO 64 B lines on x86 (the #608 note in that header). At 4 B
// it needs one. That is a deterministic claim, asserted by arm (D) rather than measured.
//
// WHAT A HOLD MAY CALL, because a spinlock makes this question sharper than a mutex does: a cycle with
// mutexes blocks, a cycle with spinlocks burns every waiting core until the machine is useless. Two
// rules, and the first consumer was audited against both before it was converted.
//
//   (1) NON-RECURSIVE. Re-entering lock() on a lock this thread already holds is a self-deadlock with
//       no diagnostic, so in a dev build this records the owning thread and DASSERTs on re-entry. That
//       turns the worst failure mode into an abort with a message at the moment it happens.
//   (2) NO LOCK MAY BE TAKEN UNDER ONE, except where the order is strict and one-directional.
//       Audited for infra/internedtext.h, the first consumer: a hold calls locate() (arithmetic),
//       text() (an atomic load plus a string compare — lock-free), next_.fetch_add (atomic), and two
//       that allocate — growShard()'s vector and makeSlot()'s ::operator new. The allocator takes its
//       own lock, so the order is shard -> allocator; nothing in an allocation path calls back into
//       interning, so the reverse order does not exist and there is no cycle. Crucially, each call
//       locks exactly ONE shard, chosen by hash, and no path holds two — so this component has no
//       internal order to check at all.
//
// A lock-ORDER checker across different locks is a separate piece of work and this is not it. What is
// here is the re-entrancy half, which is the half a non-recursive lock must have.
//
// NO PERFORMANCE CLAIM IS MADE HERE. The structural facts above are asserted; a throughput number for
// the interning path needs its own measurement on an llvm-sized corpus and is not in this header.

#include "os.h"   // rw::os::nanosleep — the one spelling of the sleep, per the POSIX-seam rule

#if defined( __aarch64__ ) || defined( __arm64__ )
  #include <arm_acle.h>   // __builtin_arm_yield / __builtin_arm_isb — the CPU hints, a few cycles each
#elif defined( __x86_64__ ) || defined( _M_X64 )
  #include <immintrin.h>  // _mm_pause
#endif

#include "Diagnostics.h"   // DASSERT — the re-entrancy tripwire, dev builds only

#include <atomic>
#include <cstdint>
#include <ctime>
#ifndef NDEBUG
  #include <functional>   // std::hash<std::thread::id> — the owner record is a u64, see below
  #include <thread>
#endif

namespace rw
{

// THE CHEAPEST RUNG, and the one both drafts of this lock were missing. A relaxed-load spin still
// issues a load every iteration; a CPU hint tells the core that this is a spin-wait, so it can stop
// speculating down the loop and (on ARM) let the other hardware thread have the pipeline. It costs a
// few cycles against the 2,667 ns a nanosleep costs — measured below — which is why the ladder must
// pass through here and through a yield before it ever reaches a syscall.
[[gnu::always_inline]] inline void spinPause() noexcept
{
#if defined( __aarch64__ ) || defined( __arm64__ )
    __builtin_arm_yield();
#elif defined( __x86_64__ ) || defined( _M_X64 )
    _mm_pause();
#endif
}

// The backoff ladder, as a PURE FUNCTION so a gate can assert its shape without a stopwatch.
//
// THE CONSTANTS ARE MEASURED, NOT CHOSEN, and the measurement overturned two guesses — the published
// example's 1 ns first sleep and a 64 ns cap, and this header's own first attempt at 64 ns to 65 us.
// Measured on this box (Apple Silicon, macOS 25.5, 200 nanosleep calls per rung, median):
//
//     requested ns:     1      2      4     64    256   1024   2048   4096   16384   65536
//     actual ns:     4000   5375   3083   2667   2667   2667   4291   6666   23916   85875
//
// `nanosleep` has a FLOOR of about 2,667 ns here, so every request from 1 ns to 1024 ns sleeps the
// same ~2.7 us. A ladder that doubles 1, 2, 4 ... 64 is therefore seven identical sleeps: the doubling
// is real in the source and absent in the machine. The ladder only begins to climb above ~2 us and
// tracks the request from ~16 us up.
//
// The second measurement says how much a sleep costs in the currency of spinning: a relaxed load is
// 0.26 ns and an exchange on a line already owned is 2.77 ns, so ONE sleep at the floor buys about
// 10,000 relaxed loads. That is what sets kSpinHotRounds: sleeping after 8 attempts pays 2.7 us to
// avoid 2 ns of spinning. A shard hold here is a hash probe — tens to a couple of hundred ns — so the
// hot phase is sized to cover a whole typical hold and still cost a tenth of one sleep.
//
// AND NO sched_yield RUNG, which the owner called before the measurement confirmed it. A yield does not
// BLOCK: it hands the core back and is immediately runnable again, so with more waiters than cores it
// burns CPU handing off to threads that also cannot enter, while a short nanosleep actually takes the
// waiter off the runqueue and lets the holder finish. Measured here, 20,000 lock/unlock per thread over
// a ~200 ns hold, same hint-spin in all three:
//
//     threads      pause only      + sched_yield      + nanosleep
//         4           20.5 ms           19.3 ms          17.1 ms
//         8           45.6 ms           43.6 ms          35.5 ms
//        24          189.1 ms          145.5 ms         128.3 ms
//
// The sleep wins at every width, by 11-19%, and the gap widens where it matters — 24 threads on 18
// cores, which is this tool's own parse pool oversubscribed. So the ladder goes hint-spin -> sleep, and
// rw::os::sched_yield was removed again rather than left as an unused seam.
//
// Linux is UNMEASURED. Its floor depends on the timer configuration and is often coarser, which would
// make the low rungs even more inert, never less. If these constants are ever tuned for Linux, measure
// there; do not reason from this table.
inline constexpr long     kSpinBackoffFirstNs = 2048;    // the first rung that is not below the floor
inline constexpr long     kSpinBackoffMaxNs   = 65536;   // ~86 us actual: the cap. Doubling without one
                                                         // reaches a second in 19 more steps.
inline constexpr unsigned kSpinHotRounds      = 1024;    // ~266 ns of relaxed loads before the first
                                                         // sleep: covers a probe-length hold, and is
                                                         // 10x cheaper than the syscall it defers

inline constexpr long spinBackoffNs( unsigned step ) noexcept
{
    long ns = kSpinBackoffFirstNs;
    for( unsigned k = 0; k < step; ++k )
    {
        if( ns >= kSpinBackoffMaxNs / 2 )
        {
            return kSpinBackoffMaxNs;
        }
        ns *= 2;
    }
    return ns;
}

static_assert( spinBackoffNs( 0 ) == kSpinBackoffFirstNs );
static_assert( spinBackoffNs( 1 ) == 2 * kSpinBackoffFirstNs );
static_assert( spinBackoffNs( 64 ) == kSpinBackoffMaxNs, "the ladder must saturate, not overflow" );

// A Lockable: lock() / unlock() / try_lock(), so std::lock_guard and std::scoped_lock take it unchanged
// and a converted call site keeps the RAII holder it already had (the house rule on RAII over paired
// calls applies here more than anywhere — a spinlock leaked by an early return hangs the next thread).
class Spinlock
{
  public:
    Spinlock() noexcept = default;
    Spinlock( const Spinlock& )            = delete;
    Spinlock& operator=( const Spinlock& ) = delete;

    void lock() noexcept
    {
        if( tryTake() )
        {
            return;   // the uncontended case: one load, one exchange, no hint, no syscall
        }
        // TWO RUNGS: a hint-spin, then the sleep ladder. There is deliberately NO sched_yield rung
        // between them, and that is a measured decision rather than a style one — see the table below.
        for( unsigned spin = 0; spin < kSpinHotRounds; ++spin )
        {
            if( tryTake() )
            {
                return;
            }
            spinPause();
        }
        for( unsigned sleeps = 0;; )
        {
            if( tryTake() )
            {
                return;
            }
            const long       ns = spinBackoffNs( sleeps );
            const ::timespec ts{ 0, ns };
            os::nanosleep( &ts, nullptr );
            if( ns < kSpinBackoffMaxNs )
            {
                ++sleeps;   // stop counting at the cap: an unbounded counter is a shape, not a limit
            }
        }
    }

    bool try_lock() noexcept { return tryTake(); }

    void unlock() noexcept
    {
#ifndef NDEBUG
        owner_.store( 0, std::memory_order_relaxed );
#endif
        flag_.store( 0, std::memory_order_release );   // pairs with the acquire on the exchange below
    }

  private:
    // The load/exchange pair this whole header exists for. The relaxed load is allowed to be stale: a
    // false negative only costs one more turn of the loop, and a false POSITIVE is impossible because
    // the exchange is what actually takes the lock.
    bool tryTake() noexcept
    {
#ifndef NDEBUG
        // Rule (1): re-entering a non-recursive lock is a hang with no message. Check BEFORE the
        // exchange, so the assert fires on the attempt rather than after the thread is stuck.
        DASSERT( owner_.load( std::memory_order_relaxed ) != selfTag(),
                 "spinlock re-entered by the thread that already holds it: a self-deadlock" );
#endif
        if( flag_.load( std::memory_order_relaxed ) != 0 || flag_.exchange( 1, std::memory_order_acquire ) != 0 )
        {
            return false;
        }
#ifndef NDEBUG
        owner_.store( selfTag(), std::memory_order_relaxed );
#endif
        return true;
    }

#ifndef NDEBUG
    static std::uint64_t selfTag() noexcept
    {
        const std::uint64_t h = std::uint64_t( std::hash<std::thread::id>{}( std::this_thread::get_id() ) );
        return h == 0 ? 1 : h;   // 0 means UNHELD, so no thread may tag itself 0
    }
#endif

    std::atomic<std::uint32_t> flag_{ 0 };
#ifndef NDEBUG
    // A u64 and not a std::thread::id: std::atomic<std::thread::id> has no constexpr constructor, so a
    // Spinlock member made every constant-initialized object holding one (src/refnames.h:43) fail to
    // compile with "variable does not have a constant initializer". The hash is only ever compared for
    // equality with itself, so a collision costs a spurious assert in a dev build and nothing else.
    std::atomic<std::uint64_t> owner_{ 0 };   // dev builds only: whose hold is this? (rule (1) above)
#endif
};

#ifdef NDEBUG
static_assert( sizeof( Spinlock ) == 4, "the size claim arm (D) and internedtext.h's shard layout both read this" );
#else
static_assert( sizeof( Spinlock ) <= 16, "a dev build carries the owning-thread record for the re-entrancy tripwire; release is 4" );
#endif
static_assert( std::atomic<std::uint32_t>::is_always_lock_free, "a spinlock whose flag is itself locked is a deadlock waiting to be found" );

}   // namespace rw
