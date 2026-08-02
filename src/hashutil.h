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

// FNV-1a is defined over OCTETS, but every string we hash is a range of `char` — and `char` is a distinct,
// IMPLEMENTATION-SIGNED type. Feeding it to the octet step as `for( unsigned char c : s )` performs an
// IMPLICIT char → unsigned char conversion, which for any byte ≥ 0x80 changes the value (-12 → 244) and so
// trips G1's `implicit-integer-sign-change` — a member of Clang's `integer` group, and under
// -fno-sanitize-recover=all a HARD STOP, not a warning. Whether it fires is a property of the toolchain,
// not of the code, which is why six copies of that loop sat green for the whole life of the project:
//
//   Linux aarch64  (gcc/clang) : `char` is UNSIGNED     → the conversion never changes a value  → green
//   macOS arm64    (AppleClang): `char` is signed, but AppleClang does not even SUPPORT the check → green
//   Linux x86-64   (clang 18)  : `char` is signed AND the check exists and fires                 → ABORT
//
// GitHub's ubuntu-24.04 runners are this project's first true x86-64 target, so that last row is new
// ground rather than a regression. `toByte` makes the conversion EXPLICIT (identical bits, identical hash,
// on every platform) and `fnv1aAbsorb` is the one seam that owns the whole octet step, so a future FNV
// site cannot reintroduce the implicit form by copying a neighbour. Do not open-code `h ^= c` again.
inline constexpr unsigned char toByte( char c ) noexcept
{
    return static_cast<unsigned char>( c );
}

inline constexpr std::uint64_t fnv1aAbsorb( std::uint64_t hash, char c ) noexcept
{
    return fnv1aMultiply( hash ^ toByte( c ) );
}

} // namespace rw::hashutil
