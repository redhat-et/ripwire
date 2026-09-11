#pragma once

#include "Diagnostics.h"
#include "platform_compat.h"

#include <cerrno>
#include <cstdio>
#include <fcntl.h>
#include <string>
#include <sys/file.h>
#include <unistd.h>

namespace rw::infra
{

// A stable lockfile whose inode survives cache publishes. The kernel releases the lock when the owning
// process exits, so a crashed ripwire cannot leave a stale lock that blocks future runs.
class ProcessLock
{
public:
    explicit ProcessLock( const std::string& lockPath )
    {
        fd_ = ::open( lockPath.c_str(), O_RDWR | O_CREAT | O_CLOEXEC, 0600 );
        if( fd_ < 0 )
        {
            DEGRADED_PATH_ALERT( "ripwire: process lockfile open failed; continuing without cross-process serialization" );
            std::fprintf( stderr, "ripwire: process lock unavailable; continuing without cross-process serialization\n" );
            return;
        }

        for( ;; )
        {
            if( ::flock( fd_, LOCK_EX ) == 0 )
            {
                locked_ = true;
                return;
            }
            if( errno != EINTR )
            {
                DEGRADED_PATH_ALERT( "ripwire: process lock acquire failed; continuing without cross-process serialization" );
                std::fprintf( stderr, "ripwire: process lock acquire failed; continuing without cross-process serialization\n" );
                return;
            }
        }
    }

    ~ProcessLock()
    {
        if( fd_ >= 0 )
        {
            if( locked_ )
            {
                ::flock( fd_, LOCK_UN );
            }
            ::close( fd_ );
        }
    }

    ProcessLock( const ProcessLock& )            = delete;
    ProcessLock& operator=( const ProcessLock& ) = delete;

private:
    int  fd_     = -1;
    bool locked_ = false;
};

}   // namespace rw::infra
