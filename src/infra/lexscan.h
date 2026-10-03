#pragma once
// lexscan.h — the shared lexical primitives for raw source text: an identifier byte, a whole word at an offset, the
// identifier starting at an offset, and the first whole-word occurrence. One definition for every module that scans
// file text without a parser (darkflags.h's harvest, docdrift.h's claims, taskroute.h's cues, orientmap.h's export
// markers) — before this header each carried its own copy of the same loop.
//
// The identifier alphabet is [A-Za-z0-9_]. A language whose identifiers take more bytes (JS's `$`) sees a boundary there;
// a caller that reads a `$name` therefore matches less, never more (orientmap.h jsExports: a missed export marker names
// the module scope, a true statement).
#include <cctype>
#include <cstddef>
#include <string_view>

namespace rw::lexscan
{

inline bool identByte( unsigned char c ) noexcept
{
    return std::isalnum( c ) || c == '_';
}

// `hay[at, at+len)` is a WHOLE word: not flanked by identifier bytes, so `Foo` never matches `FooBar` / `myFoo`
inline bool wholeWordAt( std::string_view hay, std::size_t at, std::size_t len ) noexcept
{
    if( at > 0 && identByte( (unsigned char)hay[at - 1] ) )
    {
        return false;
    }
    if( at + len < hay.size() && identByte( (unsigned char)hay[at + len] ) )
    {
        return false;
    }
    return true;
}

// The identifier starting at `i` (empty if src[i] does not open one), advancing `i` past it.
inline std::string_view takeIdent( std::string_view src, std::size_t& i )
{
    const std::size_t s = i;
    while( i < src.size() && identByte( (unsigned char)src[i] ) )
    {
        ++i;
    }
    return src.substr( s, i - s );
}

// the first whole-word occurrence of `word` in `hay` at or after `from`, or npos
inline std::size_t findWholeWord( std::string_view hay, std::string_view word, std::size_t from = 0 ) noexcept
{
    for( std::size_t at = hay.find( word, from ); at != std::string_view::npos; at = hay.find( word, at + 1 ) )
    {
        if( wholeWordAt( hay, at, word.size() ) )
        {
            return at;
        }
    }
    return std::string_view::npos;
}

}   // namespace rw::lexscan
