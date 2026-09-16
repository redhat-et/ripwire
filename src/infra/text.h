#pragma once

#include <string>

namespace rw
{

// Presentation-only newline normalization. Callers that keep source offsets or content hashes must apply this
// after selecting their raw span; CRLF and LF are equivalent source newlines, but removing CR before that
// selection would invalidate byte offsets and change the identity of the file being hashed. A span can end
// immediately before its source LF (line renderers intentionally omit trailing newlines), so a terminal CR
// is removed as well: it is the visible half of that omitted CRLF, not a standalone source byte.
inline void normalizeCrlfInPlace( std::string& text ) noexcept
{
    std::size_t write = 0;
    for( std::size_t read = 0; read < text.size(); ++read )
    {
        if( static_cast<unsigned char>( text[ read ] ) == 13 &&
            ( ( read + 1 < text.size() && text[ read + 1 ] == '\n' ) || read + 1 == text.size() ) )
        {
            continue;
        }
        text[ write++ ] = text[ read ];
    }
    text.resize( write );
}

} // namespace rw
