// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  Diagnostics.h
//
//  Platform-portable assertion / panic system.
//  Implementations live in fastmath.cpp — this header is declarations only.
//
//  Debug:   VERIFY fires handleAssert → stderr + location → __builtin_trap
//  Release: VERIFY → __builtin_assume (zero cost, optimizer hint)
//  PANIC:   always active, always crashes (std::abort after logging)
//  DEGRADED_PATH_ALERT: debug-only one-shot notice for graceful-degrade paths
//

#pragma once

#include <cstdint>
#if !defined(NDEBUG)
  #include <atomic>   // VERIFY_SAME_THREAD's per-call-site owner latch (debug only)
#endif

// --------------------------------------------------------------------------
// 1. __FILE_NAME__ — short filename without directory path
// --------------------------------------------------------------------------
#if defined(__clang__) || (defined(__GNUC__) && __GNUC__ >= 12)
  #define _SHORTERFILE_ __FILE_NAME__
#else
  #define _SHORTERFILE_ __FILE__
#endif

// --------------------------------------------------------------------------
// 2. Handler declarations — implemented in Diagnostics.cpp
// --------------------------------------------------------------------------
namespace Diagnostics {

class ConsoleLog {
public:
    [[gnu::cold, gnu::noinline]]
    static void handleAssert( const char* expr,
                               const char* file, int line,
                               const char* function,
                               const char* description = "" ) noexcept;

    [[gnu::cold, gnu::noinline, noreturn]]
    static void handlePanic( const char* file, int line,
                              const char* function,
                              const char* description ) noexcept;

    // VERIFY_SAME_THREAD violation reporter. Fires when a call site that already
    // ran on one thread is later hit by a different thread.
    [[gnu::cold, gnu::noinline]]
    static void handleThreadViolation( uint64_t expected, uint64_t got,
                                        const char* file, int line,
                                        const char* function,
                                        const char* description = "" ) noexcept;

    // DEGRADED_PATH_ALERT reporter — one-line notice, never traps, debug only.
    [[gnu::cold, gnu::noinline]]
    static void handleDegraded( const char* file, int line,
                                 const char* function,
                                 const char* description ) noexcept;
};

// Opaque, stable, NON-ZERO id for the calling thread (lives for the thread's
// lifetime). Implemented with a thread_local counter so no <thread> include is
// forced on every TU that pulls in Diagnostics.h. Used by VERIFY_SAME_THREAD.
uint64_t currentThreadId() noexcept;

} // namespace Diagnostics

// --------------------------------------------------------------------------
// 3. Core macros
// --------------------------------------------------------------------------
#if !defined(NDEBUG)

#define VERIFY_TEXT(expr, msg)                                                  \
    do {                                                                        \
        if (!(expr)) [[unlikely]] {                                             \
            ::Diagnostics::ConsoleLog::handleAssert(                            \
                #expr, _SHORTERFILE_, __LINE__, __PRETTY_FUNCTION__, msg);      \
        }                                                                       \
    } while (0)

#define VERIFY_NOT_REACHED_TEXT(msg)                                            \
    ::Diagnostics::ConsoleLog::handleAssert(                                    \
        "Unreachable code path hit!",                                           \
        _SHORTERFILE_, __LINE__, __PRETTY_FUNCTION__, msg)

// VERIFY_SAME_THREAD — assert this call site is only ever reached from ONE
// thread. The first thread to hit it claims the site (a static per-site atomic
// latch); any later hit from a different thread fires handleThreadViolation.
// Compiles to nothing in release. Use it to guard data structures that are NOT
// internally synchronised and rely on single-thread access (e.g. the audio
// btree library: read on the game thread, so a stray background-thread mutation
// would be a data race — this catches it loudly in debug).
#define VERIFY_SAME_THREAD_TEXT(msg)                                            \
    do {                                                                        \
        static ::std::atomic<::std::uint64_t> _vstOwner{ 0 };                   \
        const ::std::uint64_t _vstCur = ::Diagnostics::currentThreadId();       \
        ::std::uint64_t _vstExpected = 0;                                       \
        if( !_vstOwner.compare_exchange_strong(                                 \
                _vstExpected, _vstCur, ::std::memory_order_relaxed )            \
            && _vstExpected != _vstCur ) [[unlikely]] {                         \
            ::Diagnostics::ConsoleLog::handleThreadViolation(                   \
                _vstExpected, _vstCur,                                          \
                _SHORTERFILE_, __LINE__, __PRETTY_FUNCTION__, msg );            \
        }                                                                       \
    } while (0)

#else   // NDEBUG — release build

// __builtin_assume is Clang-only; GCC expresses the same optimizer hint via
// if(!expr) __builtin_unreachable(). Both compile to zero code, just a hint.
#if defined(__clang__)
  // Some predicates (e.g. fastmath::isFiniteFast) carry a load-bearing inline-asm
  // barrier to survive -ffast-math. Clang treats ANY inline asm in an assumed
  // expression as a side effect, DISCARDS the assumption, and warns -Wassume.
  // The hint is a no-op in release anyway (finiteness is already globally assumed
  // under -ffast-math), so suppress the cosmetic warning at the one expansion site.
  #define VERIFY_TEXT(expr, msg)                                                 \
    do {                                                                         \
        _Pragma("clang diagnostic push")                                         \
        _Pragma("clang diagnostic ignored \"-Wassume\"")                         \
        __builtin_assume(static_cast<bool>(expr));                               \
        _Pragma("clang diagnostic pop")                                          \
    } while (0)
#else
  #define VERIFY_TEXT(expr, msg)        do { if(!(expr)) __builtin_unreachable(); } while (0)
#endif
#define VERIFY_NOT_REACHED_TEXT(msg)    __builtin_unreachable()
#define VERIFY_SAME_THREAD_TEXT(msg)    do { } while (0)

#endif

// --------------------------------------------------------------------------
// 4. PANIC — always active, never compiled out
// --------------------------------------------------------------------------
#define PANIC(msg)                                                              \
    ::Diagnostics::ConsoleLog::handlePanic(                                     \
        _SHORTERFILE_, __LINE__, __PRETTY_FUNCTION__, msg)

// --------------------------------------------------------------------------
// 4b. DEGRADED_PATH_ALERT — non-fatal debug notice for graceful-degrade paths
//
// For rung-2 sites of the error ladder (recoverable runtime condition): the
// code clamps / falls back and CONTINUES. This makes the degradation visible
// in debug runs without killing them — logs ONCE per call site, never traps,
// compiles to nothing in release.
//
// NOT a VERIFY. Never write VERIFY_TEXT(false, …) on a degrade path: in
// release that is __builtin_assume(false), which deletes the fallback code
// and makes reaching the function undefined behavior (this exact bug shipped
// in safeDivisorNoInLine / safeDeterminantNoInline).
// --------------------------------------------------------------------------
#if !defined(NDEBUG)
#define DEGRADED_PATH_ALERT(msg)                                                \
    do {                                                                        \
        static ::std::atomic<bool> _dpaSeen{ false };                           \
        if( !_dpaSeen.exchange( true, ::std::memory_order_relaxed ) )           \
            ::Diagnostics::ConsoleLog::handleDegraded(                          \
                _SHORTERFILE_, __LINE__, __PRETTY_FUNCTION__, msg );            \
    } while (0)
#else
#define DEGRADED_PATH_ALERT(msg)        do { } while (0)
#endif

// --------------------------------------------------------------------------
// 5. Convenience shorthands
// --------------------------------------------------------------------------
#define VERIFY(expr)              VERIFY_TEXT(expr, "")
#define VERIFY_NOT_REACHED()      VERIFY_NOT_REACHED_TEXT("")
#define VERIFY_SAME_THREAD()      VERIFY_SAME_THREAD_TEXT("")
#define TODO_IMPLEMENT()          VERIFY_NOT_REACHED_TEXT("Feature not yet implemented.")

// --------------------------------------------------------------------------
// 6. VERIFY_NO_ALIAS — catch accidental self-aliasing in debug builds
//
// Use in functions that WRITE through one reference while READING another of
// the same type, where passing the same object twice would silently produce a
// wrong result (e.g. out-parameters of decompose/extract functions, or a
// destination that is read mid-computation).
//
// Takes two objects (not pointers); compares their addresses. Fires VERIFY if
// they are the same object. Compiles to nothing in release builds.
//
// This is a CORRECTNESS guard, not an optimisation. It documents and enforces
// the no-alias contract that __restrict would assert — without the UB risk of
// __restrict (which would make self-aliasing undefined rather than caught).
//
//   void decompose(const T& src, U& outA, U& outB) {
//       VERIFY_NO_ALIAS(outA, outB);   // the two outputs must be distinct
//       ...
//   }
// --------------------------------------------------------------------------
#define VERIFY_NO_ALIAS(a, b)                                                   \
    VERIFY_TEXT( static_cast<const void*>(&(a)) != static_cast<const void*>(&(b)), \
                 "aliasing violation: '" #a "' and '" #b "' are the same object" )

// Three-way variant for functions with three outputs (e.g. decomposeToTRS).
#define VERIFY_NO_ALIAS3(a, b, c)                                               \
    do { VERIFY_NO_ALIAS(a, b); VERIFY_NO_ALIAS(a, c); VERIFY_NO_ALIAS(b, c); } while (0)

// --------------------------------------------------------------------------
// 7. Benchmark micro-helpers — DoNotOptimize / ClobberMemory
//
// The two canonical Google-Benchmark primitives, reimplemented here so micro-
// benchmarks in this tree don't need the full benchmark library. Both are pure
// COMPILER barriers (empty inline asm) — they emit no instructions.
//
//   DoNotOptimize(x) : forces `x` to be materialised, so the compiler cannot
//                      delete the computation that produced it (defeats dead-
//                      code elimination of a benchmarked result).
//
//   ClobberMemory()  : a full compiler read/write memory barrier. Forces all
//                      pending stores to be committed to memory and stops the
//                      compiler from caching or reordering memory accesses
//                      across this point. Use it after a step that writes
//                      through a buffer (e.g. a deferred newY->heights copy)
//                      so the writes can't be hoisted into registers or elided.
//
// IMPORTANT: ClobberMemory is a *compiler* barrier only. It does NOT flush CPU
// caches, evict working sets, or simulate memory pressure from other systems.
// To model a cold-cache cost you must actually touch a large foreign buffer
// between iterations — these helpers won't do that for you.
// --------------------------------------------------------------------------
namespace Diagnostics {

#if defined(__GNUC__) || defined(__clang__)

template <typename T>
[[gnu::always_inline]] inline void DoNotOptimize( const T& value ) noexcept
{
    asm volatile( "" : : "r,m"(value) : "memory" );
}

template <typename T>
[[gnu::always_inline]] inline void DoNotOptimize( T& value ) noexcept
{
#if defined(__clang__)
    asm volatile( "" : "+r,m"(value) : : "memory" );
#else
    asm volatile( "" : "+m,r"(value) : : "memory" );
#endif
}

[[gnu::always_inline]] inline void ClobberMemory() noexcept
{
    asm volatile( "" : : : "memory" );
}

#else   // portable fallback (no inline asm): a volatile sink + atomic fence

template <typename T>
inline void DoNotOptimize( const T& value ) noexcept
{
    volatile const T* p = &value;
    (void)p;
}
template <typename T>
inline void DoNotOptimize( T& value ) noexcept
{
    volatile T* p = &value;
    (void)*p;
}
inline void ClobberMemory() noexcept
{
    // No inline-asm barrier available; best effort. (Unused on Clang/GCC.)
    static volatile int barrier = 0;
    barrier = barrier;
}

#endif

} // namespace Diagnostics
