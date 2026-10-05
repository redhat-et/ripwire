#pragma once
// enumcount.h — prove at COMPILE time that an enum's count constant is exactly its enumerator count.
//
// WHY THIS EXISTS. A byte read back from an on-disk cache is external input, and a reader range-checks it
// against a count constant declared beside its enum. Spelled the house way — for an enum
// `Shape { Circle, Square }`, `std::size_t( Shape::Square ) + 1` — that constant goes stale the day someone
// appends an enumerator AFTER `Square`, and it goes stale quietly: every cached record carrying the new value
// is refused as corrupt and reparsed, so the cache stops working for that value and nothing says so. A static_assert on
// `count == last + 1` only restates the definition and cannot see the append. This can, because it asks the
// compiler a different question — does this VALUE spell a declared enumerator? — so `count - 1` must be a
// name and `count` must not be.
//
// HOW. __PRETTY_FUNCTION__ of a function templated on an enum VALUE spells a declared enumerator as
// `Shape::Square` and any other value as `(Shape)2` (the technique magic_enum rests on). Only the
// character after "V = " is inspected. The self-test below asserts both polarities on a local enum, so a
// compiler that spells it differently is a COMPILE ERROR here — never a probe that quietly answers "fine".
//
// CLANG ONLY, stated rather than implied: the spelling was verified on Apple clang 21. GCC is expected to
// print the same form but was not verified, so under GCC the probe is not evaluated (kEnumCountProbed is
// false) and every enumCountIsExact assertion passes trivially there. The macOS and Linux clang CI legs
// evaluate it on every change, which is where an append is caught.
//
// CONTIGUITY is the caller's contract: an enum checked here is declared from 0 with no explicit gaps, which is
// what makes "count - 1 is the last name" and "every value below count is a name" the same statement.

#include <cstddef>
#include <cstdint>
#include <string_view>
#include <type_traits>

namespace rw
{

#if defined( __clang__ )

inline constexpr bool kEnumCountProbed = true;

// Does V spell a declared enumerator of its enum?  "[V = Shape::Square]" yes, "[V = (Shape)2]" no.
template<auto V>
    requires std::is_enum_v<decltype( V )>
constexpr bool namesEnumerator() noexcept
{
    const std::string_view signature = __PRETTY_FUNCTION__;
    const std::size_t      at        = signature.rfind( "V = " );
    return at != std::string_view::npos && at + 4 < signature.size() && signature[ at + 4 ] != '(';
}

// `Count` is exact: the value Count-1 is a declared enumerator of E and the value Count is not.
template<class E, std::size_t Count>
    requires std::is_enum_v<E>
constexpr bool enumCountIsExact() noexcept
{
    return Count > 0 && namesEnumerator<static_cast<E>( Count - 1 )>() && !namesEnumerator<static_cast<E>( Count )>();
}

// The probe proves itself on both polarities before anything relies on it.
namespace enumcount_selftest
{
enum class Probe : std::uint8_t { First, Last };
}
static_assert( namesEnumerator<enumcount_selftest::Probe::Last>() && !namesEnumerator<static_cast<enumcount_selftest::Probe>( 2 )>(),
               "enumcount.h: this compiler spells an enum value in __PRETTY_FUNCTION__ differently — fix the probe, do not delete it" );
static_assert( enumCountIsExact<enumcount_selftest::Probe, 2>() && !enumCountIsExact<enumcount_selftest::Probe, 1>()
                   && !enumCountIsExact<enumcount_selftest::Probe, 3>(),
               "enumcount.h: enumCountIsExact must accept the exact count and refuse one short and one over" );

#else

inline constexpr bool kEnumCountProbed = false;

template<class E, std::size_t Count>
    requires std::is_enum_v<E>
constexpr bool enumCountIsExact() noexcept
{
    return true;   // not evaluated off clang — see the header note
}

#endif

// The one bounded lookup of an enum-indexed table: `table[e]` when e indexes it, `fallback` for a byte past the
// table (a corrupt cache byte, a value past the enum). refRoleTag, valueRefFamily and cacheRejectName all read
// their tables through it rather than re-spelling the bound check.
template<class E, class Table, class T>
    requires std::is_enum_v<E>
constexpr T enumTableAt( const Table& table, E e, T fallback ) noexcept
{
    const auto i = static_cast<std::size_t>( e );
    return i < std::size( table ) ? T( table[ i ] ) : fallback;
}

}   // namespace rw
