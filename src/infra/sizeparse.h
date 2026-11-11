#pragma once

#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstdlib>

namespace rw
{
// parse a NUL-terminated "...=<u64>" value tail with the same reject rules as parsePosInt: empty /
// non-numeric / signed / zero / overflow (so `--pack-budget-bytes=-1` no longer wraps to 2^64-1 and
// `=abc` no longer silently becomes 0). First char must be a digit — strtoull would accept "-1" by wrapping.
inline bool parsePosU64( const char* s, std::size_t& out ) noexcept
{
    if( s[0] < '0' || s[0] > '9' )
    {
        return false;
    }
    char* end = nullptr;
    errno     = 0;
    const unsigned long long v = std::strtoull( s, &end, 10 );
    if( end == s || *end != '\0' || v < 1 || errno == ERANGE || v > SIZE_MAX )
    {
        return false;
    }
    out = std::size_t( v );
    return true;
}

// parse a "...=<u64>[K|M|G]" BYTE-SIZE value: an optional single-char suffix (case-insensitive, powers of
// 1024, a trailing "B" tolerated so "10MB" works) scales the number; a bare number is bytes. Same reject
// rules as parsePosU64 (empty / signed / zero / bad-suffix / overflow). Used by --max-file-size.
inline bool parseByteSize( const char* s, std::size_t& out ) noexcept
{
    if( s[0] < '0' || s[0] > '9' )
    {
        return false;
    }
    char* end = nullptr;
    errno     = 0;
    const unsigned long long v = std::strtoull( s, &end, 10 );
    if( end == s || v < 1 || errno == ERANGE )
    {
        return false;
    }

    std::size_t mult = 1;
    if( *end != '\0' )                                        // an optional K/M/G scale suffix
    {
        switch( *end )
        {
            case 'k': case 'K': mult = 1024ull;                    break;
            case 'm': case 'M': mult = 1024ull * 1024;             break;
            case 'g': case 'G': mult = 1024ull * 1024 * 1024;      break;
            default:            return false;
        }
        ++end;
        if( *end == 'b' || *end == 'B' )
        {
            ++end; // tolerate the "B" of KB/MB/GB
        }
        if( *end != '\0' )
        {
            return false;
        }
    }
    if( v > static_cast<unsigned long long>( SIZE_MAX / mult ) )
    {
        return false; // overflow guard
    }
    out = std::size_t( v ) * mult;
    return true;
}
}   // namespace rw
