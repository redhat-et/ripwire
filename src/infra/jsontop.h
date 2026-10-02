#pragma once
// jsontop.h — the package.json top-level walk: read one JSON string, find a depth-1 key's value. Moved verbatim out of
// jsrunner.h (fix #8) so orientmap.h can read the manifest's bin/exports/main without pulling the tree-sitter half of
// jsrunner.h into serialize.h (and so into every harness that compiles serialize.h alone). Same namespace, same bytes.
#include "jsonesc.h"     // jsonStringEnd
#include <cstddef>
#include <string>
#include <string_view>

namespace rw::jsrunner::detail
{

// Read the JSON string starting at `p` (the opening quote) and advance `p` past its closing quote.
// Minimal unescaping (the same "keep the byte after a backslash" rule resolve.h::parseTsconfigPaths uses) —
// package.json keys and the evidence values this file compares are all plain ASCII in every real corpus.
inline std::string readQuoted( std::string_view s, std::size_t& p )
{
    std::string out;
    if( p >= s.size() || s[p] != '"' )
    {
        return out;
    }
    ++p;
    while( p < s.size() && s[p] != '"' )
    {
        if( s[p] == '\\' && p + 1 < s.size() )
        {
            out.push_back( s[p + 1] );
            p += 2;
            continue;
        }
        out.push_back( s[p] );
        ++p;
    }
    if( p < s.size() )
    {
        ++p;
    }
    return out;
}

// The offset of the first byte of the FIRST top-level `"key"`'s VALUE in `json` (whitespace after the colon
// skipped), or npos when no depth-1 key of that name exists — the one scan `topLevelObjectBody` (an object
// value) and `topLevelStringValue` (a string value) both start from, so the two never disagree about which
// key is top-level.
inline std::size_t topLevelValueStart( std::string_view json, std::string_view key )
{
    std::size_t p     = 0;
    int         depth = 0;
    while( p < json.size() )
    {
        const char c = json[p];
        if( c == '"' )
        {
            const std::string k = readQuoted( json, p );
            if( depth == 1 && k == key )
            {
                std::size_t v = json.find( ':', p );
                if( v == std::string_view::npos )
                {
                    return std::string_view::npos;
                }
                ++v;
                while( v < json.size() && ( json[v] == ' ' || json[v] == '\t' || json[v] == '\n' || json[v] == '\r' ) )
                {
                    ++v;
                }
                return v < json.size() ? v : std::string_view::npos;
            }
            continue;   // p already advanced past this string by readQuoted
        }
        if( c == '{' || c == '[' )
        {
            ++depth;
        }
        else if( c == '}' || c == ']' )
        {
            --depth;
        }
        ++p;
    }
    return std::string_view::npos;
}


// The byte range (begin,end) of the FIRST top-level `"key": { ... }` object VALUE in `json` — package.json's
// own top level ("scripts", "dependencies", "devDependencies" are SIBLINGS, never nested in one another), so
// only a depth-1 key is a match; a same-named key inside some other object (e.g. a "scripts" key nested
// inside an unrelated config blob) is not evidence. A non-object value (or an absent key) yields npos/npos.
struct ObjSpan
{
    std::size_t begin = std::string_view::npos;
    std::size_t end   = std::string_view::npos;
};


inline ObjSpan topLevelObjectBody( std::string_view json, std::string_view key )
{
    std::size_t v = topLevelValueStart( json, key );
    if( v == std::string_view::npos || json[v] != '{' )
    {
        return {};   // scripts/dependencies must be an object; anything else is not this shape
    }
    const std::size_t objStart = v + 1;
    int                d       = 0;
    for( ; v < json.size(); ++v )
    {
        if( json[v] == '"' )
        {
            const std::size_t close = rw::jsonStringEnd( json, v );
            v = ( close == std::string_view::npos ) ? json.size() : close + 1;
            --v;   // the for-loop's ++v re-lands exactly past the string
            continue;
        }
        if( json[v] == '{' )
        {
            ++d;
        }
        else if( json[v] == '}' )
        {
            --d;
            if( d == 0 )
            {
                return { objStart, v };
            }
        }
    }
    return {};   // unterminated object: malformed input, no evidence
}

// train20-cr C8: the string value of package.json's top-level `key` (`"type"`), or "" when absent or not a
// string — the same "no evidence" reading `stringValue` gives an absent field.
inline std::string topLevelStringValue( std::string_view json, std::string_view key )
{
    std::size_t v = topLevelValueStart( json, key );
    if( v == std::string_view::npos || json[v] != '"' )
    {
        return {};
    }
    return readQuoted( json, v );
}
}   // namespace rw::jsrunner::detail
