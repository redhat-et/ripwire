#pragma once

#include <cstdint>

#include "platform.h" // infra::platform::multiplyLow64 — the sanitizer-clean wrapping multiply

namespace rw::hashutil
{

inline constexpr std::uint64_t kFnv1aPrime64 = 1099511628211ull;

// The low 64 bits of lhs * rhs, through the seam in infra/platform.h.
//
// This briefly read `return lhs * rhs;` on the argument that unsigned arithmetic is already modulo 2^64, so the
// old `unsigned __int128` product and its mask "bought nothing". The VALUES were identical — 59,120,289 pairs
// checked against the original, zero disagreements — and the conclusion was still wrong, because value
// equivalence was not the property the wide type was there for. It was there to be SANITIZER-clean: G1's
// `integer` group flags a wrapping uint64 multiply, -fno-sanitize-recover=all makes that fatal, and the narrow
// body aborted every asan-flavour crawl on the first byte of the first hash (rc=134). Three comments in this
// tree already said so — clones.h:546, test/harnesscommon.h:31, and gitblob.h:13, which names this very
// function as the posture it copies and records that the asan tree found it "on the first receipt".
//
// What the seam adds over simply restoring the old body: MSVC has no `__int128` at all on x64 (C4235), and also
// none of that sanitizer group, so it wants the plain multiply — a per-compiler answer, which is exactly what
// infra/platform.h is for and what osswitchcheck arm H exists to force. The GNU/Clang arm is byte-for-byte the
// arithmetic this function has always done, proven at the object level rather than by reading: the .s at -O2,
// and under the asan flavour's own flags, is identical to the one this file produced before the detour.
inline constexpr std::uint64_t multiplyModulo64( std::uint64_t lhs, std::uint64_t rhs ) noexcept
{
    return infra::platform::multiplyLow64( lhs, rhs );
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

// Pack a (high, low) pair of 32-bit ids into one u64 that sorts by `high`, then `low` — the ONE such key (contextratio.h's fact
// streams sort these; aliashop.h keys its per-(file, byte) scope chains on them).
inline constexpr std::uint64_t packPair( std::uint32_t high, std::uint32_t low ) noexcept
{
    return ( std::uint64_t( high ) << 32 ) | std::uint64_t( low );
}

} // namespace rw::hashutil
