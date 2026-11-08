// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  agenttrap_os.h
//
//  The OS half of AGENT-VISIBLE-TRAP (agenttrap.h): the rw::os calls the failure path makes, as the plain function
//  table agenttrap::arm takes. Kept out of diagnostics.cpp because that file is linked ALONE into every standalone test
//  harness and reaches no OS layer; main.cpp, which links all of rw::os, hands this table over. Debug builds only.
//
//  Each entry runs after a failed check, so none allocates: descriptors and write(2)/send(2), never a FILE*.
//
#pragma once

#if !defined( NDEBUG )

  #include "agenttrap.h"
  #include "os.h"

  #include <cstddef>

namespace Diagnostics::agenttrap
{

inline OsCalls osCalls() noexcept
{
    OsCalls calls;
    calls.write = []( int fd, const char* bytes, std::size_t count ) noexcept -> long long
    { return static_cast<long long>( rw::os::write( fd, bytes, count ) ); };
    calls.send = []( int socket, const char* bytes, std::size_t count ) noexcept -> long long
    { return static_cast<long long>( rw::os::send( socket, bytes, count, MSG_NOSIGNAL ) ); };
    calls.createTruncate = []( const char* path ) noexcept -> int { return rw::os::open( path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600 ); };
    calls.close          = []( int fd ) noexcept { rw::os::close( fd ); };
    calls.rename         = []( const char* from, const char* to ) noexcept -> int { return rw::os::rename( from, to ); };
    calls.remove         = []( const char* path ) noexcept -> int { return rw::os::unlink( path ); };
    calls.readPrefix     = []( const char* path, char* into, std::size_t capacity ) noexcept -> std::size_t
    {
        const int fd = rw::os::open( path, O_RDONLY | O_CLOEXEC );
        if( fd < 0 )
        {
            return 0;
        }
        std::size_t got = 0;
        while( got < capacity )
        {
            const auto n = rw::os::read( fd, into + got, capacity - got );
            if( n <= 0 )
            {
                break;
            }
            got += static_cast<std::size_t>( n );
        }
        rw::os::close( fd );
        return got;
    };
    calls.processId = []() noexcept -> long long { return static_cast<long long>( rw::os::getpid() ); };
    return calls;
}

} // namespace Diagnostics::agenttrap

#endif
