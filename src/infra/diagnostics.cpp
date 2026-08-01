// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  diagnostics.cpp
//
//  The one out-of-line translation unit behind Diagnostics.h: the four ConsoleLog
//  report handlers (assert / panic / thread-affinity violation / degraded path) and
//  the thread-id counter. Everything else in the diagnostics system is macros, so
//  every target and every standalone test harness in test/ links exactly this file
//  to satisfy VERIFY, PANIC and DEGRADED_PATH_ALERT.
//
#include "Diagnostics.h"
#include <iostream>
#include <cstdlib>
#include <atomic>

namespace Diagnostics {

[[gnu::cold, gnu::noinline]]
void ConsoleLog::handleAssert( const char* expr, const char* file, int line,
                                const char* function, const char* description ) noexcept
{
    std::cerr
        << "\n======================================\n"
        << "!!! DEBUG ASSERT FAILED !!!\n"
        << "======================================\n"
        << "  Expr:     " << expr     << "\n"
        << "  Location: " << file << ":" << line << "\n"
        << "  Function: " << function << "\n";
    if( description && description[0] != '\0' )
        std::cerr << "  Notes:    " << description << "\n";
    std::cerr << "======================================\n" << std::flush;
    __builtin_trap();
}

[[gnu::cold, gnu::noinline, noreturn]]
void ConsoleLog::handlePanic( const char* file, int line,
                               const char* function, const char* description ) noexcept
{
    std::cerr
        << "\n======================================\n"
        << "!!! CRITICAL SYSTEM PANIC !!!\n"
        << "======================================\n"
        << "  Location: " << file << ":" << line << "\n"
        << "  Function: " << function             << "\n"
        << "  Reason:   " << description          << "\n"
        << "======================================\n" << std::flush;
    std::abort();
}

[[gnu::cold, gnu::noinline]]
void ConsoleLog::handleThreadViolation( uint64_t expected, uint64_t got,
                                         const char* file, int line,
                                         const char* function, const char* description ) noexcept
{
    std::cerr
        << "\n======================================\n"
        << "!!! THREAD-AFFINITY VIOLATION !!!\n"
        << "======================================\n"
        << "  This call site is single-thread only but was reached from a 2nd thread.\n"
        << "  Owner thread: " << expected << "   Offending thread: " << got << "\n"
        << "  Location: " << file << ":" << line << "\n"
        << "  Function: " << function << "\n";
    if( description && description[0] != '\0' )
        std::cerr << "  Notes:    " << description << "\n";
    std::cerr << "======================================\n" << std::flush;
    __builtin_trap();
}

[[gnu::cold, gnu::noinline]]
void ConsoleLog::handleDegraded( const char* file, int line,
                                  const char* function, const char* description ) noexcept
{
    // One-line notice, no trap — the caller clamps/falls back and continues.
    std::cerr << "[math degraded] " << description
              << "  (" << file << ":" << line << ", " << function
              << " — logged once per site)\n" << std::flush;
}

// Unique, stable, non-zero per-thread id. thread_local counter avoids pulling
// <thread> into the widely-included Diagnostics.h; first thread to ask gets 1,
// next 2, etc. Non-zero so 0 stays a valid "unclaimed" sentinel for the latch.
uint64_t currentThreadId() noexcept
{
    static std::atomic<uint64_t> counter{ 0 };
    thread_local const uint64_t id = ++counter;
    return id;
}

} // namespace Diagnostics
