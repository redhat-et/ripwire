// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster
//
//  stackthreads.h
//
//  Run one piece of work on N threads whose STACK SIZE is chosen, not inherited. std::thread cannot ask for a
//  stack, and the default differs by a factor of sixteen across the platforms this tree ships on (512 KiB on a
//  macOS secondary thread, 8 MiB under glibc), so work whose depth is data-dependent — libstdc++'s regex matcher
//  recurses once per state it visits — gets a stack it can state and bound instead of whatever the platform gave.
//
//  POSIX, inline (behind rw::os): pthread_attr_setstacksize + pthread_create + pthread_join, nothing wrapped
//  beyond os::'s own always_inline passthrough. A stack of S bytes
//  is an address-space reservation; pages are committed only as deep as the work actually recurses, and returned
//  when the thread exits.
//
//  The work pulls its own share from shared state (an atomic cursor), so a thread that fails to start costs
//  parallelism, not coverage: the threads that did start finish the work. A thread the system refuses the full
//  stack is retried with half, down to 8 MiB. ONE size is then SETTLED — the smallest any started thread got — and
//  every thread is told that size, and no thread runs any work until it is settled (the threads wait on a gate
//  the creator holds). So a piece of work never sees a size that depends on which thread picked it up: work that
//  derives a limit from its stack derives the same limit on every thread (determinism, CLAUDE.md non-negotiable
//  #2). When NONE starts, the work runs once on the calling thread and is told kCallerStackBytesFloor — the
//  caller's stack is not this header's to measure, so the work plans for the smallest one this tree runs on. The
//  settled size is RETURNED, so a caller whose answer depends on it can disclose it.
//
#pragma once

#include "Diagnostics.h"   // DISCLOSE
#include "os.h"            // rw::os::pthread_* — attr init/setstacksize/destroy, create, join

#include <algorithm>
#include <cstddef>
#include <mutex>
#include <vector>

namespace rw
{

// The stack a caller that never sized its own thread plans for, where work bounds itself by it (src/regexguard.h
// maxEngineSubjectBytes). The number only ever reaches a bound under libstdc++, whose matcher recurses once per visit;
// libc++'s bound is SIZE_MAX on any stack. So it is chosen per library. libc++ is macOS here, where a secondary thread
// gets 512 KiB. libstdc++ is glibc here, where the main thread and every std::thread get RLIMIT_STACK's soft limit, 8 MiB
// unless an operator lowers it. 512 KiB under libstdc++ left NO visits once regexguard.h holds back half the stack and its
// frame reserve (CI on #283): every #match?, skill-scan line and --arch path subject was Skipped on every Linux leg, a
// failure a macOS run cannot see. regexguard.h static_asserts the libstdc++ number's budget on every platform. This is
// still a planning number, not a measurement: running these callers on runOnStackThreads with the SETTLED size (and
// reading the real thread stack, which glibc does not size at 8 MiB when RLIMIT_STACK is unlimited) is a follow-up.
inline constexpr std::size_t kCallerStackBytesFloorLibcxx    = std::size_t{ 512 } * 1024;
inline constexpr std::size_t kCallerStackBytesFloorLibstdcxx = std::size_t{ 8 } * 1024 * 1024;
#if defined( _LIBCPP_VERSION )
inline constexpr std::size_t kCallerStackBytesFloor = kCallerStackBytesFloorLibcxx;
#else
inline constexpr std::size_t kCallerStackBytesFloor = kCallerStackBytesFloorLibstdcxx;
#endif

// The attribute object, released on every path.
class StackThreadAttr
{
public:
    explicit StackThreadAttr( std::size_t stackBytes ) noexcept
        : isInitialized( os::pthread_attr_init( &attr ) == 0 )
        , isSized( isInitialized && os::pthread_attr_setstacksize( &attr, stackBytes ) == 0 )
    {
    }
    ~StackThreadAttr() { if( isInitialized ) { os::pthread_attr_destroy( &attr ); } }
    StackThreadAttr( const StackThreadAttr& )            = delete;
    StackThreadAttr& operator=( const StackThreadAttr& ) = delete;

    os::pthread_attr_t attr {};
    const bool          isInitialized;
    const bool          isSized;
};

inline constexpr std::size_t kStackThreadBytesFloor = std::size_t{ 8 } * 1024 * 1024;   // the smallest stack a refused thread is retried with

// work( settledBytes ) on `threadCount` threads; returns the settled stack size after every thread has been joined. Each
// thread asks for `stackBytes` and, when the system refuses that much (a strict overcommit policy, an address-space
// ulimit), for half as much, down to kStackThreadBytesFloor. `work` must not throw: an exception escaping a thread's
// entry is std::terminate. `isRefused( threadIndex, tryBytes, askedBytes )` lets a caller's test hook refuse a size the
// system would have granted, so the degrade is reachable on demand; the default refuses nothing.
inline bool isStackNeverRefused( std::size_t, std::size_t, std::size_t ) noexcept { return false; }

// The size a refused try retries with: half, but never past the floor — the floor itself is always tried, so a request
// that is not a power-of-two multiple of it (12 MiB -> 8 MiB, where plain halving went 12 -> 6 and stopped) still gets
// a floor-sized thread before the work falls back to the caller's stack. 0 once the floor has been tried. A request
// below the floor is its own floor and is tried once.
inline constexpr std::size_t nextStackTryBytes( std::size_t tryBytes, std::size_t askedBytes ) noexcept
{
    const std::size_t floorBytes = askedBytes < kStackThreadBytesFloor ? askedBytes : kStackThreadBytesFloor;
    if( tryBytes <= floorBytes )
    {
        return 0;
    }
    return ( tryBytes / 2 < floorBytes ) ? floorBytes : tryBytes / 2;
}
static_assert( nextStackTryBytes( std::size_t{ 12 } * 1024 * 1024, std::size_t{ 12 } * 1024 * 1024 ) == kStackThreadBytesFloor, "a 12 MiB request retries at the 8 MiB floor" );
static_assert( nextStackTryBytes( kStackThreadBytesFloor, std::size_t{ 12 } * 1024 * 1024 ) == 0, "the floor is the last try" );
static_assert( nextStackTryBytes( std::size_t{ 256 } * 1024 * 1024, std::size_t{ 256 } * 1024 * 1024 ) == std::size_t{ 128 } * 1024 * 1024, "a power-of-two request still halves" );
static_assert( nextStackTryBytes( std::size_t{ 4 } * 1024 * 1024, std::size_t{ 4 } * 1024 * 1024 ) == 0, "a request below the floor is tried once" );

template<typename Work, typename RefusePolicy = decltype( &isStackNeverRefused )>
std::size_t runOnStackThreads( std::size_t threadCount, std::size_t stackBytes, Work& work, RefusePolicy isRefused = &isStackNeverRefused ) noexcept
{
    struct Shared
    {
        explicit Shared( Work* w ) noexcept : work( w ) {}
        Work*       work;
        std::size_t settledBytes = 0;   // written under `gate` before it opens; read under it by every thread
        std::mutex  gate;
    };
    struct Launch
    {
        Shared*        shared;
        os::pthread_t  thread;
    };
    const auto entry = []( void* arg ) -> void*
    {
        Shared&     shared       = *static_cast<Launch*>( arg )->shared;
        std::size_t settledBytes = 0;
        {
            const std::lock_guard<std::mutex> wait( shared.gate );   // blocks until the creator has settled one size
            settledBytes = shared.settledBytes;
        }
        ( *shared.work )( settledBytes );
        return nullptr;
    };
    Shared              shared( &work );
    std::vector<Launch> launches( threadCount, Launch{ &shared, os::pthread_t{} } );
    std::size_t         startedCount = 0;
    {
        const std::lock_guard<std::mutex> hold( shared.gate );
        std::size_t                       smallestBytes = stackBytes;
        for( std::size_t t = 0; t < threadCount; ++t )
        {
            Launch& launch    = launches[ startedCount ];
            bool    isStarted = false;
            for( std::size_t tryBytes = stackBytes; !isStarted && tryBytes > 0; tryBytes = nextStackTryBytes( tryBytes, stackBytes ) )
            {
                const StackThreadAttr attr( tryBytes );
                isStarted     = attr.isSized && !isRefused( t, tryBytes, stackBytes ) && os::pthread_create( &launch.thread, &attr.attr, entry, &launch ) == 0;
                smallestBytes = isStarted ? std::min( smallestBytes, tryBytes ) : smallestBytes;
            }
            startedCount += isStarted ? 1 : 0;
        }
        shared.settledBytes = startedCount == 0 ? kCallerStackBytesFloor : smallestBytes;
    }
    for( std::size_t t = 0; t < startedCount; ++t )
    {
        os::pthread_join( launches[ t ].thread, nullptr );
    }
    if( startedCount == 0 )
    {
        DISCLOSE( "stackthreads: no thread could be created with any stack of at least 8 MiB — the work runs on the caller's thread" );
        work( kCallerStackBytesFloor );
    }
    return shared.settledBytes;
}

}   // namespace rw
