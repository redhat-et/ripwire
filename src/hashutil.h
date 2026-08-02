#pragma once

#include <cstdint>
#include <limits>

namespace rw::hashutil
{

inline constexpr std::uint64_t kFnv1aPrime64 = 1099511628211ull;

inline constexpr std::uint64_t multiplyModulo64( std::uint64_t lhs, std::uint64_t rhs ) noexcept
{
    using Wide = unsigned __int128;
    constexpr Wide kMask64 = Wide( std::numeric_limits<std::uint64_t>::max() );
    return static_cast<std::uint64_t>( ( Wide( lhs ) * Wide( rhs ) ) & kMask64 );
}

inline constexpr std::uint64_t fnv1aMultiply( std::uint64_t value ) noexcept
{
    return multiplyModulo64( value, kFnv1aPrime64 );
}

// FNV-1a absorbs OCTETS, but the strings we hash are ranges of `char` — an implementation-SIGNED type. The
// implicit `for( unsigned char c : s )` form changes the value of any byte >= 0x80 and so trips G1's
// implicit-integer-sign-change, which -fno-sanitize-recover=all makes a hard abort on x86-64 clang (aarch64
// has unsigned `char` and AppleClang lacks the check, which is why six copies sat green for years — see the
// commit that added this). Absorb through here; never open-code `h ^= c` again.
inline constexpr unsigned char toByte( char c ) noexcept
{
    return static_cast<unsigned char>( c );
}

inline constexpr std::uint64_t fnv1aAbsorb( std::uint64_t hash, char c ) noexcept
{
    return fnv1aMultiply( hash ^ toByte( c ) );
}

} // namespace rw::hashutil
