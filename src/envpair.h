#pragma once

// envpair.h — the ONE "<a>,<b>" experiment-env parser (r4 siblift + r5 nameboost, and any later
// pre-registered candidate that gates on an env pair). Hoisted for the same reason namesplit.h exists:
// the two per-experiment copies were exactly the clone class --quality-delta flags, and their parsing
// contract is load-bearing enough to state once:
//   * anything malformed (no comma, empty half, a non-digit byte) => (0,0) = OFF;
//   * each half accumulates digits but STOPS once the value exceeds 99 (so "100"/"1000" both read as
//     100 and fail the range check below — oversized values mean OFF, never a clamp-and-guess);
//   * a value outside its caller-supplied inclusive [lo, hi] range => (0,0) = OFF.
// test/sibliftcheck.sh and test/nameboostcheck.sh both pin the malformed-value behavior.

#include <cstdlib>
#include <string_view>
#include <utility>

namespace rw
{

inline std::pair<std::size_t, std::size_t> parseEnvSizePair( const char* envName,
                                                             std::size_t loA, std::size_t hiA,
                                                             std::size_t loB, std::size_t hiB )
{
    const char* env = std::getenv( envName );
    if( !env )
    {
        return { 0, 0 };
    }
    const std::string_view s( env );
    const std::size_t comma = s.find( ',' );
    if( comma == std::string_view::npos || comma == 0 || comma + 1 >= s.size() )
    {
        return { 0, 0 };
    }
    std::size_t a = 0, b = 0;
    for( const char c : s.substr( 0, comma ) )
    {
        if( c < '0' || c > '9' ) { return { 0, 0 }; }
        a = a * 10 + std::size_t( c - '0' );
        if( a > 99 ) { break; }
    }
    for( const char c : s.substr( comma + 1 ) )
    {
        if( c < '0' || c > '9' ) { return { 0, 0 }; }
        b = b * 10 + std::size_t( c - '0' );
        if( b > 99 ) { break; }
    }
    if( a < loA || a > hiA || b < loB || b > hiB )
    {
        return { 0, 0 };
    }
    return { a, b };
}

} // namespace rw
