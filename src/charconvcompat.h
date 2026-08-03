// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

#pragma once

// charconvcompat.h — the ONE floating-point `std::from_chars` this tree is allowed to call.
//
// WHY THIS EXISTS. C++17's FLOATING-POINT `std::from_chars` overloads are still not universally
// shipped. libc++ DECLARES them `= delete` until it implements them, so a call that compiles on a
// current toolchain is a hard error — "call to deleted function 'from_chars'" — on an older libc++.
// That is exactly what the first public CI run hit on macos-14 (both the release and the asan leg)
// against a tree that had only ever been built on one Mac. The INTEGER overloads are present
// everywhere and are NOT routed through here; only the float/double ones need a fallback.
//
// DETECTION IS A `requires`, NOT A FEATURE-TEST MACRO — measured, not assumed. `__cpp_lib_to_chars`
// is the obvious candidate and it is WRONG here: it covers `to_chars` AND `from_chars` together, so
// libc++ leaves it undefined while shipping a perfectly good FP `from_chars`. On this repo's own dev
// machine (Apple Clang 21 / libc++ 21) the macro is UNDEFINED and `std::from_chars( …, double& )`
// compiles and runs — keying off the macro would have pushed the dev machine onto the fallback and
// changed the very platform the fix must not disturb. A requires-expression asks the only question
// that matters (does this exact call compile?) and answers it correctly for BOTH shapes of absence:
// an overload that is `= delete` (libc++) and one that was never declared at all.
//
// THE FALLBACK IS ALWAYS COMPILED, on every platform, even where the std path is chosen. A shim that
// only type-checks on the toolchain that cannot be built locally is a shim that rots silently; this
// way the dev machine's build proves the fallback still compiles, and the macos-14 CI leg proves it
// still behaves (the lint magic-number gates run straight through it there).
//
// SEMANTICS: `parseFloating` reproduces `std::from_chars( first, last, value )` with the default
// `chars_format::general`, which is strtod's grammar MINUS three things. All three are handled below
// rather than inherited, because the caller distinguishes "parsed the whole token" from "stopped
// early" and every one of them would silently shift that boundary:
//   • leading whitespace  — strtod skips it, from_chars rejects it
//   • a leading '+'       — strtod accepts it, from_chars rejects it
//   • a hexadecimal float — strtod consumes "0x1p3", from_chars(general) stops at the 'x'
// Everything else (decimal significand, exponent, `inf`/`infinity`, `nan`/`nan(chars)`) is strtod's
// contract already and is passed through unchanged. Two out-of-range details are NOT, and both were
// found by running the two implementations side by side over a 64-vector list on the dev machine:
//   • strtod raises ERANGE for a SUBNORMAL result too ("4.9e-324"), which from_chars accepts as
//     perfectly representable. Only a real overflow (±inf) or a flush-to-zero underflow is mapped to
//     `result_out_of_range`; a nonzero subnormal is a success, matching from_chars.
//   • on `result_out_of_range` this leaves `value` UNMODIFIED, which is what the standard specifies.
//     libc++'s own FP from_chars additionally stores ±inf / 0 there. `ec` is identical either way, so
//     no correct caller can see the difference — reading `value` after a non-zero `ec` is a bug.
//
// `ptr` and `ec` were verified IDENTICAL to `std::from_chars` on all 64 vectors, covering signs,
// exponents, `inf`/`nan` spellings, hex, leading '+'/whitespace, empty and trailing-garbage input,
// and the representable/overflow/underflow boundaries.

#include <cerrno>
#include <charconv>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <string>
#include <system_error>
#include <type_traits>

namespace rw
{

namespace charconvdetail
{

// Does the standard library provide a USABLE FP from_chars for T? False both when the overload is
// `= delete` (older libc++) and when it does not exist (the integer template is constrained to
// integral types, so it is not viable either way).
template<class T>
concept HasStdFloatingFromChars = requires( const char* p, T& v ) { std::from_chars( p, p, v ); };

// strtod / strtof behind one name, so the fallback below is written once for both widths.
inline double callStrtox( const char* text, char** parseEnd, double* ) noexcept { return std::strtod( text, parseEnd ); }
inline float  callStrtox( const char* text, char** parseEnd, float*  ) noexcept { return std::strtof( text, parseEnd ); }

// Is this an IEEE-754 infinity? NOT `std::isinf`: the portable build flags include -ffast-math, whose
// -ffinite-math-only lets the optimiser fold every isinf/isfinite call to constant false. Reading the
// exponent field through an opaque asm barrier is the same defence platform.h's isFiniteFast uses.
// The sentinel is bit_cast from numeric_limits rather than a hand-typed hex constant, so the float and
// double widths are one function and neither pattern can be mistyped.
template<class T> requires std::is_floating_point_v<T>
[[nodiscard]] inline bool isInfiniteBits( T x ) noexcept
{
    using Bits = std::conditional_t<sizeof( T ) == sizeof( std::uint32_t ), std::uint32_t, std::uint64_t>;
    static_assert( sizeof( Bits ) == sizeof( T ), "no same-width unsigned type for this floating format" );
    constexpr Bits kInfinityBits = __builtin_bit_cast( Bits, std::numeric_limits<T>::infinity() );
    constexpr Bits kExceptSignBit = static_cast<Bits>( ~Bits( 0 ) >> 1 );

    Bits bits = __builtin_bit_cast( Bits, x );
    asm volatile( "" : "+r"( bits ) );
    return ( bits & kExceptSignBit ) == kInfinityBits;
}

// The always-compiled strtod/strtof implementation of from_chars( …, chars_format::general ). Kept
// out of `parseFloating` so it is a real function on every platform (see the header note) and can be
// exercised directly side by side with the std path.
template<class T> requires std::is_floating_point_v<T>
inline std::from_chars_result parseFloatingViaStrtox( const char* first, const char* last, T& value ) noexcept
{
    if( first >= last )
    {
        return { first, std::errc::invalid_argument };
    }

    // The two leading characters strtod would swallow and from_chars refuses. Rejecting them here
    // keeps `ptr` on the first unconsumed character in exactly the cases the std path would.
    if( std::isspace( static_cast<unsigned char>( *first ) ) || *first == '+' )
    {
        return { first, std::errc::invalid_argument };
    }

    // A hex float is strtod-only: from_chars(general) matches just the leading "[-]0" and reports the
    // 'x' as the stop. Trim the range so strtod sees the same characters instead of the whole literal.
    const char* afterSign = first + ( *first == '-' ? 1 : 0 );
    const char* scanLast  = last;
    if( last - afterSign >= 2 && afterSign[ 0 ] == '0' && ( afterSign[ 1 ] == 'x' || afterSign[ 1 ] == 'X' ) )
    {
        scanLast = afterSign + 1;
    }

    // strtod needs a NUL terminator and [first,last) is a view into a larger buffer; one small copy.
    const std::string nullTerminated( first, scanLast );
    char*             parseEnd = nullptr;
    errno = 0;
    const T parsed = static_cast<T>( callStrtox( nullTerminated.c_str(), &parseEnd, static_cast<T*>( nullptr ) ) );

    const std::size_t consumedCount = static_cast<std::size_t>( parseEnd - nullTerminated.c_str() );
    if( consumedCount == 0 )
    {
        return { first, std::errc::invalid_argument }; // no pattern matched at all
    }

    // ERANGE alone does NOT mean out-of-range: strtod raises it for a gradual underflow to a SUBNORMAL,
    // which from_chars reports as a plain success. Only ±inf (overflow) and a flushed 0 (total
    // underflow) are genuinely unrepresentable — and there `value` stays untouched, per the standard.
    const bool isUnrepresentable = ( errno == ERANGE ) && ( parsed == T( 0 ) || isInfiniteBits( parsed ) );
    if( isUnrepresentable )
    {
        return { first + consumedCount, std::errc::result_out_of_range };
    }

    value = parsed;
    return { first + consumedCount, std::errc{} };
}

} // namespace charconvdetail

// Parse a float/double out of [first,last) exactly as `std::from_chars( first, last, value )` does,
// on every toolchain this tree supports. Same return shape, same `ptr`/`ec` contract — so a call site
// keeps its "did it consume the WHOLE token?" test written as `ptr == last`.
template<class T> requires std::is_floating_point_v<T>
[[nodiscard]] inline std::from_chars_result parseFloating( const char* first, const char* last, T& value ) noexcept
{
    if constexpr( charconvdetail::HasStdFloatingFromChars<T> )
    {
        return std::from_chars( first, last, value );
    }
    else
    {
        return charconvdetail::parseFloatingViaStrtox( first, last, value );
    }
}

} // namespace rw
