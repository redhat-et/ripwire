#pragma once

// pipefields.h — the NUL-framed read of a popen'd stream that can keep a deadline.
//
// `git log -z` terminates every --format field and --name-only path with NUL instead of '\n', and an EMPTY field is the record
// boundary, so a field is what gets read. This reads the pipe's descriptor itself, in blocks, because a read through stdio cannot
// keep a deadline against a git that stopped writing. Between blocks, and at least every 100 ms while none arrives, it checks
// `abandon` (the walkers' stop-at-the-next-unit contract, gitmine.h) and `deadline`. Either one drops a partial field and reads as
// end of stream, so a caller that must tell them apart consults the flag and `timedOut`. An end of stream inside a field returns
// that field: a final unterminated field counts. The owner closes the pipe, which is what ends the child.

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "os.h"   // rw::os::pipeReadSome

namespace rw
{

class PipeFieldReader
{
public:
    bool timedOut = false;

    PipeFieldReader( std::FILE* pipe, const std::atomic<bool>* abandon, std::chrono::steady_clock::time_point deadline )
        : pipe_( pipe ), abandon_( abandon ), deadline_( deadline ), block_( 64u * 1024u ) {}

    bool next( std::string& field )
    {
        field.clear();
        bool readAny = false;
        for( ;; )
        {
            if( pos_ == len_ && !refill() )
            {
                return readAny && !stopping();
            }
            readAny = true;
            const char* start = block_.data() + pos_;
            const char* nul   = static_cast<const char*>( std::memchr( start, '\0', len_ - pos_ ) );
            if( nul != nullptr )
            {
                field.append( start, nul );
                pos_ += static_cast<std::size_t>( nul - start ) + 1;
                return true;
            }
            field.append( start, len_ - pos_ );
            pos_ = len_;
        }
    }

private:
    bool stopping() const noexcept { return timedOut || ( abandon_ != nullptr && abandon_->load( std::memory_order_relaxed ) ); }

    bool refill()
    {
        constexpr std::int64_t kPollMs = 100;
        pos_ = len_ = 0;
        while( !stopping() )
        {
            const auto now = std::chrono::steady_clock::now();
            if( now >= deadline_ )
            {
                timedOut = true;
                return false;
            }
            const std::int64_t leftMs = std::chrono::duration_cast<std::chrono::milliseconds>( std::min( deadline_ - now, std::chrono::steady_clock::duration( std::chrono::milliseconds( kPollMs ) ) ) ).count() + 1;
            const long got = os::pipeReadSome( pipe_, block_.data(), block_.size(), static_cast<int>( leftMs ) );
            if( got == os::kPipeNothingYet )
            {
                continue;
            }
            if( got <= 0 )
            {
                return false;
            }
            len_ = static_cast<std::size_t>( got );
            return true;
        }
        return false;
    }

    std::FILE*                            pipe_;
    const std::atomic<bool>*              abandon_;
    std::chrono::steady_clock::time_point deadline_;
    std::vector<char>                     block_;
    std::size_t                           pos_ = 0;
    std::size_t                           len_ = 0;
};

} // namespace rw
