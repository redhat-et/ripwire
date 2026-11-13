#pragma once

#include <cstddef>
#include <cstdint>

#include "platform.h" // infra::platform::multiplyLow64 — the sanitizer-clean wrapping multiply
#include "unordered_dense.h" // ankerl::unordered_dense::detail::wyhash::hash — hashMix's body

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

// Mix a u64 key (a packPair, an id) into a well-spread hash, for a hash container keyed by a composite integer. This IS the
// flat containers' own u64 hash (wyhash's 128-bit multiply-fold, the one ankerl applies to an integer key), so a custom
// hasher built on it spreads exactly as HashMap/HashSet do on a bare u64. Picked by microbench over the splitmix64
// finalizer (M2, 2026-11-11, -O2, median of 3): a dependent chain 1.7 vs 4.8 ns, throughput 0.39 vs 0.78 ns, and a
// 4 M-key set insert + lookup 23.8 vs 39.0 ns/op. One 64x64->128 multiply, no wrapping 64-bit multiply for the sanitizer.
inline std::uint64_t hashMix( std::uint64_t key ) noexcept
{
    return ankerl::unordered_dense::detail::wyhash::hash( key );
}

// Hash a byte range: the flat containers' own string hash (wyhash over 8-byte words, the one ankerl applies to a
// std::string key). For a bucket key whose value never reaches output; FNV-1a above absorbs ONE byte per multiply,
// which on a declined call's candidate list (graph.h internDeclinedList) was 1.2-3 % of a warm --deps main thread.
inline std::uint64_t hashBytes( const void* data, std::size_t size ) noexcept
{
    return ankerl::unordered_dense::detail::wyhash::hash( data, size );
}

} // namespace rw::hashutil
