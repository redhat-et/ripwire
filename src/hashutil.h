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

} // namespace rw::hashutil
