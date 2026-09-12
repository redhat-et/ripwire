#pragma once

// emit.h — THE formatted-output emitter, and the ONE place the std::print-versus-std::format choice is made.
//
// WHY A CHOICE AT ALL. The house rule (CONTRIBUTING.md §3 "Output") is std::print; the tree is printf-family
// by history and converting it is byte-parity-fenced by test/printffmtparitycheck.sh. <print> arrives in
// libstdc++ 14 and, on libc++, only at a macOS 14+ deployment target — and libc++ defines __cpp_lib_print
// only when the target admits it (measured 2026-09-08 with Apple clang 21: defined at -mmacosx-version-min
// 14.0, absent at 13.0), so testing the FEATURE MACRO rather than the header's presence is what keeps a
// lower target compiling instead of failing on an unavailable symbol. Every toolchain therefore builds:
// std::print where the library has it, std::format rendered and written with std::fputs where it does not.
//
// WHY THE CHOICE IS DISCLOSED. A silent fallback would let a CI leg on gcc 13 read as "the std::print floor
// holds". kEmitterName names the path that compiled in; --version prints it as emit= (gated by
// test/versioncheck.sh #6) and each CI leg asserts the value it is supposed to have (.github/workflows).
//
// CONTRACT PARITY. std::fputs reports a failed write by return value, which every emitting site here has
// always ignored; std::print reports it by THROWING std::system_error. The std::print arm catches that one
// exception so the two arms keep one contract — a write failure is silent on both, exactly as before the
// conversion, and never a std::terminate the fputs arm could not produce. (A closed pipe is SIGPIPE on
// both arms and reaches neither.) fmt is NOT vendored: the standard library has the feature, so a vendored
// copy would be a G3 regression.

#include <cstddef>
#include <type_traits>
#include <cstring>
#include <cstdio>
#include <format>
#include <string_view>
#include <system_error>
#include <utility>
#include <version>
#if __has_include( <print> )
#include <print>
#endif

namespace rw
{

// EMIT_FORCE_FALLBACK selects the std::format+fputs arm on a toolchain that would otherwise
// take the <print> one, so both arms can be diffed locally instead of only in one CI job.
#if defined( __cpp_lib_print ) && __cpp_lib_print >= 202207L && !defined( EMIT_FORCE_FALLBACK )

inline constexpr const char* kEmitterName = "std::print";

template<class... A> inline void emitTo( std::FILE* stream, std::format_string<A...> f, A&&... a )
{
    // A fixed char[] must arrive as rw::cstr( buf ). printf's %s always meant "bytes to the first NUL";
    // `{}` on a char[N] is a different question that library versions answer differently, and an
    // implementation that formats the ARRAY emits the trailing NUL and the uninitialised bytes after it.
    // A regex sweep missed sites twice, so the compiler enforces it instead of a reviewer.
    // Only a MUTABLE char[N] is rejected. A string literal is const char[N]; every implementation formats
    // that as a string, and the hazard here is the reusable buffer that was written short.
    static_assert( ( ... && !( std::is_array_v<std::remove_reference_t<A>>
                               && !std::is_const_v<std::remove_extent_t<std::remove_reference_t<A>>> ) ),
                   "pass rw::cstr( buf ) for a fixed char buffer: {} on a char[N] is not printf's %s" );
    try
    {
        std::print( stream, f, std::forward<A>( a )... );
    }
    catch( const std::system_error& )
    {
        // fputs's contract, kept: a failed write is silent (see the header comment).
    }
}

#else

inline constexpr const char* kEmitterName = "std::format+fputs";

template<class... A> inline void emitTo( std::FILE* stream, std::format_string<A...> f, A&&... a )
{
    // A fixed char[] must arrive as rw::cstr( buf ). printf's %s always meant "bytes to the first NUL";
    // `{}` on a char[N] is a different question that library versions answer differently, and an
    // implementation that formats the ARRAY emits the trailing NUL and the uninitialised bytes after it.
    // A regex sweep missed sites twice, so the compiler enforces it instead of a reviewer.
    // Only a MUTABLE char[N] is rejected. A string literal is const char[N]; every implementation formats
    // that as a string, and the hazard here is the reusable buffer that was written short.
    static_assert( ( ... && !( std::is_array_v<std::remove_reference_t<A>>
                               && !std::is_const_v<std::remove_extent_t<std::remove_reference_t<A>>> ) ),
                   "pass rw::cstr( buf ) for a fixed char buffer: {} on a char[N] is not printf's %s" );
    std::fputs( std::format( f, std::forward<A>( a )... ).c_str(), stream );
}

#endif


// ── emitRaw — literal text, which is not a format string at all ──────────────────────────────────────
// 353 of this tree's printf-family calls pass a string and NO arguments: help pages, legends, usage
// banners, XML preambles. Routing those through emitTo would be worse than pointless — std::format_string
// is CONSTEVAL, so each would pay compile-time parsing for formatting that never happens, and the --help
// table at 114,985 characters exceeds the constant-evaluation budget outright and does not compile.
//
// THE TRAP WHEN CONVERTING INTO THIS: a printf format spells a literal percent %%, and text passed to
// fputs is no longer a format, so %% here would print TWO characters and must become a single %. Braces
// are the mirror image: emitTo needs {{ and }} where this needs a bare { and }.
template<class S> inline void emitRaw( std::FILE* stream, const S& text )
{
    std::fputs( text, stream );
}

// ── cstr — a fixed char[] holds a C STRING, and `{}` must be told so ─────────────────────────────────
// printf's %s on a `char buf[N]` always meant ONE thing: the bytes up to the first NUL. The array itself
// is a different object, and what `{}` means for a char[N] argument has not been uniform across library
// versions — an implementation that formats the ARRAY emits the trailing NUL and whatever uninitialised
// bytes follow it, which in this tool lands inside an XML attribute and produces a document that does not
// parse. The buffers here are routinely written short and reused, so that difference is not theoretical.
//
// Decaying explicitly removes the question on every implementation, and says at the call site which of the
// two readings was meant. Pass a fixed buffer as rw::cstr( buf ), never bare.
inline const char* cstr( const char* p ) noexcept { return p; }

// ── formatTo — snprintf's SHAPE, kept ────────────────────────────────────────────────────────────────
// std::snprintf's other half of this tree renders into a CALLER-OWNED char buffer rather than a stream,
// so emitTo is the wrong tool for it: routing those sites through std::format and a std::string would
// put an allocation on serialize.h's per-symbol path, which is a G2 regression, not a modernisation.
// std::format_to_n keeps the stack buffer and adds nothing.
//
// The contract is snprintf's, exactly, so the call sites need no reasoning about the difference:
//   - writes at most cap-1 characters and ALWAYS NUL-terminates when cap > 0;
//   - returns the length the output WOULD have had, untruncated — snprintf's return, which is what the
//     truncation-detecting call sites read;
//   - cap == 0 writes nothing and still reports that length.
//
// Only ONE arm, unlike emitTo: std::format_to_n is <format> (C++20), present on every toolchain that
// builds this tree, so there is nothing to feature-test and nothing to disclose.
//
// WHY THIS IS A SAFETY FIX AND NOT ONLY A STYLE ONE: snprintf returns the would-have-written length, so
// the append idiom `p += snprintf( p, e - p, ... )` walks p PAST e on truncation and the next
// size_t( e - p ) underflows into an unbounded write. Three lambdas in serialize.h carry a hand-written
// clamp against exactly that (see their A4-F8 comments). format_to_n returns the ACTUAL end of the
// written region, already bounded by the n it was given, so the clamp becomes structural and the bug
// class stops existing rather than being defended against site by site.
template<class... A> inline std::size_t formatTo( char* buf, std::size_t cap, std::format_string<A...> f, A&&... a )
{
    // A fixed char[] must arrive as rw::cstr( buf ). printf's %s always meant "bytes to the first NUL";
    // `{}` on a char[N] is a different question that library versions answer differently, and an
    // implementation that formats the ARRAY emits the trailing NUL and the uninitialised bytes after it.
    // A regex sweep missed sites twice, so the compiler enforces it instead of a reviewer.
    // Only a MUTABLE char[N] is rejected. A string literal is const char[N]; every implementation formats
    // that as a string, and the hazard here is the reusable buffer that was written short.
    static_assert( ( ... && !( std::is_array_v<std::remove_reference_t<A>>
                               && !std::is_const_v<std::remove_extent_t<std::remove_reference_t<A>>> ) ),
                   "pass rw::cstr( buf ) for a fixed char buffer: {} on a char[N] is not printf's %s" );
    if( cap == 0 )
    {
        return std::formatted_size( f, std::forward<A>( a )... );
    }
    const auto r = std::format_to_n( buf, static_cast<std::ptrdiff_t>( cap - 1 ), f, std::forward<A>( a )... );
    *r.out = '\0';
    return static_cast<std::size_t>( r.size );
}

}   // namespace rw
