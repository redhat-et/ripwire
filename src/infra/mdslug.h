#pragma once

// mdslug.h — the ONE GitHub-style anchor slug of a markdown heading name.
//
// Two stages need it and neither can include the other: ingest_docs.h resolves an in-file [text](#slug) at
// extraction, and graph.h resolves a cross-file [text](other.md#slug) once every heading in the repo is a
// symbol. A leaf header keeps them on one definition (a second copy is the clone --quality-delta flags).

#include <algorithm>
#include <string>
#include <string_view>

namespace rw
{

// A reST link as RawRef::memberPath carries it (ingest_rest.h writes it, graph.h bindMarkdownLinks reads it). A markdown
// destination stops at its first tab, so a leading tab cannot be a markdown link as written.
inline constexpr std::string_view kRestLabelMark   = "\tref:";   // + the lowered label a :ref: names
inline constexpr std::string_view kRestDocRootMark = "\tdoc:";   // + a :doc:`/path` relative to the Sphinx root, own extension added

// alnum lowered, spaces→'-', '-'/'_' kept, everything else dropped. First match wins on collision
// (GitHub's -1/-2 suffixes, percent-encoded slugs and headings with inline markup are not modelled; such a link falls
// back to the target file's own edge — disclosed here rather than guessed, and never marked anchor="missing": see
// mdSlugOutsideModel, mdHeadingOutsideModel and graph.h mdSlugProvablyAbsent).
inline std::string mdSlugOf( std::string_view name )
{
    std::string slug;
    slug.reserve( name.size() );
    for( const char c : name )
    {
        if( ( c >= 'a' && c <= 'z' ) || ( c >= '0' && c <= '9' ) || c == '_' || c == '-' ) { slug += c; }
        else if( c >= 'A' && c <= 'Z' ) { slug += char( c - 'A' + 'a' ); }
        else if( c == ' ' || c == '\t' ) { slug += '-'; }
    }
    return slug;
}

// A link slug this function cannot decide about: a byte >= 0x80 (it drops non-ASCII letters, GitHub keeps them) or a '%'
// (an encoded slug; it does not decode). A miss on such a slug proves nothing about the heading.
inline bool mdSlugOutsideModel( std::string_view slug ) noexcept
{
    return std::any_of( slug.begin(), slug.end(), []( char c ) { return c == '%' || static_cast<unsigned char>( c ) >= 0x80; } );
}

// A heading name whose slug mdSlugOf cannot give as GitHub does: GitHub slugs the RENDERED text, mdSlugOf the raw source.
// `[`/`<`/`&` open a link, a tag or an entity (`## See [docs](x.md)` renders "See docs", `see-docs`; the raw slug reads
// see-docsxmd), `*` and a `_` that is not inside a word open emphasis (`## _Setup_` renders "Setup", `setup`; the raw slug
// keeps the underscores). A snake_case word is no emphasis. A file with such a heading proves nothing by a slug miss.
inline bool mdHeadingOutsideModel( std::string_view name ) noexcept
{
    const auto word = []( char c ) { return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ); };
    for( std::size_t i = 0; i < name.size(); ++i )
    {
        const char c = name[ i ];
        if( c == '[' || c == '<' || c == '&' || c == '*' )
        {
            return true;
        }
        if( c == '_' && !( i > 0 && i + 1 < name.size() && word( name[ i - 1 ] ) && word( name[ i + 1 ] ) ) )
        {
            return true;
        }
    }
    return false;
}

}   // namespace rw
