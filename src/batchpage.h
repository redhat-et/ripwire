#pragma once
// batchpage.h — CL1 (outputceiling.h) for the CLI --batch: a batch over the output ceiling pages by WHOLE <q> sub-answers.
//
// WHY. Each sub-verb bounds its own answer; sixteen of them together did not. The research audit of 2026-11-26 (item 2)
// measured a 61,579-character MCP batch spilled to a file, and #774 pages the MCP twin by the same unit. The CLI read the
// same batchText and printed it whole at any size, so `ripwire . --batch=F` past ~30,000 characters reached Claude Code's
// Bash tool as a file path and a 2,000-character preview, which is the answer never arriving.
//
// THE RULE (the MCP twin's, spelled in the CLI's own continuation form):
//   * a batch whose delivered answer fits, at no --offset, is batchText byte for byte;
//   * past the ceiling, the page serves the sub-answers from --offset=K that fit, whole, and its root says offset= shown=
//     has_more= and, when more follow, next_offset= and next="--batch=FILE --offset=E …" (the call that serves the rest);
//   * a sub-answer is never split. One larger than a page by itself is served alone and whole, over_ceiling="1" on the root
//     and one stderr line naming its size, as --for --page-bytes=0 does for a whole answer;
//   * --page-bytes=0 is the whole batch by request (cli.h batchWholeConflict), with the same stderr line when it is over.
// Every page runs the whole batch, since dedup needs every payload, so a <dup-of q=> may name a <q> an earlier page carried.
//
// WHY THE ROWS ARE READ BACK OUT OF batchText. batchText (mcpverbs.h) is the one writer of the <q> row format, and the MCP
// lane owns that file; #774 splits it into batchRows + batchPage there. Until that lands, this header reads the rows back out
// of batchText's finished document, so the row format still has one writer and a page's rows are its exact substrings.
// A document that does not have the shape batchText writes is never paged: splitBatchRows returns nullopt and the caller
// prints it whole and says so. FOLLOW-UP (after #774): take batchRows directly and let batchPage share fitWholeUnits.
#include "nextverb.h"        // nextAttrXml — the root's pasteable next=
#include "outputceiling.h"   // kOutputCeilingChars, fitWholeUnits
#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// batchText's document in three parts, each a view into it.
struct BatchRowSplit
{
    std::string_view              rootOpen;   // `<batch n=… requested=… cap=…[ capped="1"]`: the open tag without its '>'
    std::string_view              legend;     // the legend comment up to, not including, its closing " -->"
    std::vector<std::string_view> rows;       // one per <q>, whole, in order
};

// One past the <q> element that starts at `at`, or npos when the bytes there are not one. The shapes are batchText's three:
// `<q …/>` (ok=0: its attribute values are XML-escaped, so the tag's first '>' ends it), `<q …><dup-of q="i"/></q>`, and
// `<q …>` + one or more CDATA sections + `</q>` (batchCdata splits a payload's "]]>" across two sections).
[[nodiscard]] inline std::size_t batchRowEnd( std::string_view doc, std::size_t at ) noexcept
{
    constexpr std::size_t      npos  = std::string_view::npos;
    constexpr std::string_view kOpen = "<![CDATA[";
    const std::size_t          gt    = doc.substr( at ).starts_with( "<q " ) ? doc.find( '>', at ) : npos;
    if( gt == npos || doc[ gt - 1 ] == '/' )
    {
        return gt == npos ? npos : gt + 1;
    }
    std::size_t p = gt + 1;
    if( doc.substr( p ).starts_with( "<dup-of " ) )
    {
        const std::size_t close = doc.find( "/>", p );
        p                       = close == npos ? doc.size() : close + 2;
    }
    while( doc.substr( p ).starts_with( kOpen ) )
    {
        const std::size_t close = doc.find( "]]>", p + kOpen.size() );
        p                       = close == npos ? doc.size() : close + 3;
    }
    return doc.substr( p ).starts_with( "</q>" ) ? p + 4 : npos;
}

// batchText's finished document split into its root, its legend and its rows; nullopt when it does not have that shape.
[[nodiscard]] inline std::optional<BatchRowSplit> splitBatchRows( std::string_view whole )
{
    constexpr std::string_view kClose = "</batch>";
    const std::size_t          tagEnd = whole.starts_with( "<batch " ) ? whole.find( '>' ) : std::string_view::npos;
    if( tagEnd == std::string_view::npos || !whole.substr( tagEnd + 1 ).starts_with( "<!--" ) )
    {
        return std::nullopt;
    }
    const std::size_t legendEnd = whole.find( " -->", tagEnd );
    if( legendEnd == std::string_view::npos )
    {
        return std::nullopt;
    }
    BatchRowSplit split{ whole.substr( 0, tagEnd ), whole.substr( tagEnd + 1, legendEnd - tagEnd - 1 ), {} };
    std::size_t   p = legendEnd + 4;
    while( !whole.substr( p ).starts_with( kClose ) )
    {
        const std::size_t end = batchRowEnd( whole, p );
        if( end == std::string_view::npos )
        {
            return std::nullopt;
        }
        split.rows.push_back( whole.substr( p, end - p ) );
        p = end;
    }
    if( p + kClose.size() != whole.size() )
    {
        return std::nullopt;
    }
    return split;
}

// One page of a CLI batch, or the refusal of an --offset past its last sub-answer.
struct CliBatchPage
{
    std::string text;               // the page document (no trailing newline); empty with a refusal
    std::string refusal;            // the stderr sentence when --offset is past the last sub-answer
    std::size_t overBytes = 0;      // > 0: the one <q> served alone is over the ceiling, and this is the page's size before any legend rewrite
};

// The page clause the legend gains on a page (the compact posture restates the window from its own paging terms instead).
inline constexpr std::string_view kCliBatchPageLegend =
    " Paged under the output ceiling: offset= is the first <q> on this page, shown= how many it carries, has_more=1 with "
    "next_offset= and next= the call that serves the rest (the same batch file); a <dup-of q=> may name a <q> an earlier page "
    "carried; over_ceiling=1: one <q> larger than a page, served whole on its own.";

// The page of `split` from `offset`. `batchFlag` is the --batch=FILE spelling the next= replays and `replayFlags` (each with its
// leading space) the flags that shaped the sub-answers, so the next page is a page of the SAME batch.
[[nodiscard]] inline CliBatchPage cliBatchPage( const BatchRowSplit& split, std::size_t offset, std::string_view batchFlag,
                                                std::string_view replayFlags, std::size_t ceiling = kOutputCeilingChars )
{
    const std::size_t n = split.rows.size();
    if( offset >= n )
    {
        return { {}, "--offset=" + std::to_string( offset ) + " is past the last of this batch's " + std::to_string( n )
                         + " sub-answers — --offset is the next_offset= a paged batch's root names, with the same batch file",
                 0 };
    }
    const auto nextFrom = [ & ]( std::size_t end )
    { return nextAttrXml( std::string( batchFlag ) + " --offset=" + std::to_string( end ) + std::string( replayFlags ) ); };
    // the window attributes at their widest (every count at n's digits), so the fit below can only over-reserve
    const std::size_t windowBytes = 64 + 4 * std::to_string( n ).size() + nextFrom( n ).size();
    const std::size_t fixedBytes  = split.rootOpen.size() + windowBytes + split.legend.size() + kCliBatchPageLegend.size() + 13;   // "> -->…</batch>"
    const auto [ end, used ]      = fitWholeUnits( split.rows, offset, fixedBytes, ceiling );
    const bool more               = end < n;

    std::string out( split.rootOpen );
    out += " offset=\"" + std::to_string( offset ) + "\" shown=\"" + std::to_string( end - offset ) + "\" has_more=\"" + ( more ? "1" : "0" ) + "\"";
    out += more ? " next_offset=\"" + std::to_string( end ) + "\"" + nextFrom( end ) : std::string();
    out += used > ceiling ? " over_ceiling=\"1\">" : ">";
    out += split.legend;
    out += kCliBatchPageLegend;
    out += " -->";
    for( std::size_t i = offset; i < end; ++i )
    {
        out += split.rows[ i ];
    }
    out += "</batch>";
    const std::size_t overBytes = used > ceiling ? out.size() : 0;
    return { std::move( out ), {}, overBytes };
}

}   // namespace rw
