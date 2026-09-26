#pragma once

// shquote.h — a string as ONE POSIX shell word: single-quoted, with each embedded `'` spelled `'\''` (close the
// literal, a backslash-escaped quote, reopen). Inside POSIX single quotes nothing expands — no `$`, no backtick, no
// `$(...)` — so the result is safe to splice into a command line or to print as a line the user pastes.
//
// Standard library only, on purpose: every header in this layer (os.h among them) can include it without a cycle,
// and a consumer that copies one of those headers gets the quoter with it instead of a link-time dependency on a
// heavier sibling. The one definition lives here; jsonesc.h includes this file rather than keeping its own copy.
//
// POSIX only. PowerShell's single-quoted literal is a different grammar (a doubled `''`, and typographic quotes
// close it too), so os_win32_logic.h carries its own quoter rather than a parameterised form of this one.

#include <string>

namespace rw
{

inline std::string shSingleQuote( const std::string& s )
{
    std::string out = "'";
    for( const char c : s )
    {
        if( c == '\'' ) { out += "'\\''"; }
        else
        {
            out += c;
        }
    }
    out += "'";
    return out;
}

}   // namespace rw
