#pragma once
// notfoundtext.h — BX2 FIX 9: a found="0" answer still carries the selector's plain-text occurrences (test/notfoundtextcheck.sh).
//
// WHY. fastify keys a reply property with `kReplyHijacked: Symbol( … )` — an object-literal data property, not a definition — so
// --callers, --uses and --impact each answered found="0" and nothing else (lane BS1, fastify-02), while the two files that read
// and write `reply[kReplyHijacked]` were one --grep away. A zero there is honest about the GRAPH, and silent about the text a
// reader needs next. The not-found answer of the three "who uses it" verbs now adds the whole-word lines of the selector's last
// name, one row per file, labelled PLAIN TEXT (selectorrefuse.h writeNotFoundAnswer words it): found= stays 0, the exit status
// stays 1, and nothing here is counted as a call, a use or an edge.
//
// HOW. The literal scan --grep runs (grepCollect: every indexed file, tier-then-path order), then a whole-word test on each hit
// (darkflags::wholeWordAt, the boundary the degraded-parse refusal scan uses), reading each hit file once. Cold path only (the
// command is already failing) and bounded: kNotFoundTextFiles hit files and kNotFoundTextBytes bytes are read at most; a stop,
// an unreadable file or the grep's own collection budget makes both counts floors (counts_floor=1), never a silent short count.
// A selector whose last name is not an identifier (a path, an @FILE:LINE seed, a line range) seeks nothing.
#include "darkflags.h"        // readWhole / wholeWordAt — the shared lexical helpers
#include "graph.h"            // splitQualifiedSpec — the selector grammar the verbs resolve with
#include "model.h"
#include "search.h"           // grepCollect — the literal scan --grep runs
#include "selectorrefuse.h"   // NotFoundText / NotFoundAnswer — the answer this fills
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace rw
{
inline constexpr std::size_t kNotFoundTextRows  = 20;          // <text> rows printed (text_files= counts every file)
inline constexpr std::size_t kNotFoundTextFiles = 512;         // hit files read for the whole-word test
inline constexpr std::size_t kNotFoundTextBytes = 64u << 20;   // bytes read for it

// The name a selector's text evidence is sought for: its last segment (after `file:`, `::`, `.`, `#`), when that is an
// identifier of 2..256 bytes (letters, digits, `_`, `$`, not starting with a digit); "" otherwise.
inline std::string_view notFoundTextTerm( std::string_view spec ) noexcept
{
    if( spec.empty() || spec.front() == '@' )
    {
        return {};
    }
    std::string_view file, name;
    splitQualifiedSpec( spec, file, name );
    for( const std::string_view sep : { std::string_view( "::" ), std::string_view( "." ), std::string_view( "#" ) } )
    {
        if( const std::size_t at = name.rfind( sep ); at != std::string_view::npos )
        {
            name.remove_prefix( at + sep.size() );
        }
    }
    if( name.size() < 2 || name.size() > 256 || ( name.front() >= '0' && name.front() <= '9' ) )
    {
        return {};
    }
    for( const char c : name )
    {
        if( !( ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_' || c == '$' ) )
        {
            return {};
        }
    }
    return name;
}

inline NotFoundText notFoundTextEvidence( const IngestResult& ing, std::string_view spec )
{
    NotFoundText out;
    const std::string_view term = notFoundTextTerm( spec );
    if( term.empty() )
    {
        return out;
    }
    out.term = std::string( term );
    const GrepCollection found = grepCollect( ing, out.term );
    out.floor = found.isBudgetReached || found.unreadableFiles > 0 || found.degraded;
    std::size_t readFiles = 0, readBytes = 0;
    for( std::size_t h = 0; h < found.raw.size(); )
    {
        const std::uint32_t f   = found.raw[h].fileId;
        std::size_t         end = h;
        while( end < found.raw.size() && found.raw[end].fileId == f )
        {
            ++end;   // one file's hits are contiguous (the collection's tier-then-path order)
        }
        std::optional<std::string> bytes;
        if( ++readFiles <= kNotFoundTextFiles )
        {
            bytes = darkflags::readWhole( diskPath( ing, f ) );
        }
        if( !bytes || ( readBytes += bytes->size() ) > kNotFoundTextBytes )
        {
            out.floor = true;   // past a budget, or unreadable: its lines are not counted, so the counts are floors
            h = end;
            continue;
        }
        NotFoundText::Row row;
        std::uint32_t     lastLine = 0;
        for( std::size_t k = h; k < end; ++k )
        {
            const GrepRawHit& hit = found.raw[k];
            if( hit.byteOffset < bytes->size() && darkflags::wholeWordAt( *bytes, hit.byteOffset, term.size() ) && hit.line != lastLine )
            {
                lastLine = hit.line;
                row.line = row.lines == 0 ? hit.line : row.line;
                ++row.lines;
            }
        }
        if( row.lines > 0 )
        {
            out.hits += row.lines;
            ++out.files;
            if( out.rows.size() < kNotFoundTextRows )
            {
                row.path = std::string( rootRelPath( ing, f ) );
                out.rows.push_back( std::move( row ) );
            }
        }
        h = end;
    }
    return out;
}

// The text evidence a not-found answer of --callers / --uses / --impact (and their MCP twins) carries; every other answer — a
// refusal over several definitions, a path miss, --callees / --defs / --path — is left as it was.
inline void attachNotFoundText( const IngestResult& ing, NotFoundAnswer& a )
{
    if( ( a.tag != "callers" && a.tag != "uses" && a.tag != "impact" ) || a.refused != 0 || a.nearMatches != 0 || !a.missing.empty() || a.echo.empty() )
    {
        return;
    }
    a.text = notFoundTextEvidence( ing, a.echo.front().second );
}
}   // namespace rw
