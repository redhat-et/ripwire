#pragma once
// fordocbody.h — FOR-DOC-BODY: a prose --for task whose answer leads with doc files gets the top-ranked SECTIONS of the first
// doc files it shows, in <doc_body> just before </ctx>. (CLI src/verbs_for.h, MCP `for` src/mcpverbs.h forTaskText, --json
// emitForLensJsonPass — one picker, one builder, two spellings.)
//
// WHY. --for names a doc page and prints no doc text: on the DOCS-DEV set it named the right page and printed no body on every
// row, while --recall serves the section that answers on a third of them. The agent's next step was a --recall or a Read.
//
// WHEN (present-only; trigger v1, written down before the dev questions were read, reports/for-doc-body-s0.md section 3):
//   (i)  at least kForDocBodyTriggerDocs of the first kForDocBodyTriggerRows file-tail <t> rows IN RANK ORDER are doc files
//        (forDocBodyExt): the order the tail printed when the rule was written; a code question's tail now prints its code rows
//        first (forpage.h tailOrdersCodeFirst), and read in that order the rule fired on 6 of the 48 DOCS-DEV rows (17 in rank order, 11-05), and
//   (ii) the task is prose: it holds none of the code cues trigger v1 listed (forDocBodyProseTask): a backtick, `::`, `()`, a lowercase
//        snake_case word that ends in a letter or underscore, a camelCase or CapsLowCaps word, a dotted call `a.b(`. A cue LIST, not a
//        parse: handle_upload_3, MAX_RETRIES, __init__, HTTPServer and getX read as prose, and the legend says so.
// A code task, or a prose task whose answer leads with code files, prints nothing: the answer is byte-identical.
//
// WHAT. The first kForDocBodyFiles doc files the answer shows (its signature rows first, then its <t> rows in rank order).
// Each file's sections are the ones --recall would pick for the same task (recallLensScores + buildSectionGranularBody), served in
// rank order while they fit the block's OWN allowance (kForDocBodyBytes, shared by the files with recall's water-filling): no code
// row, body or tail row pays for it, and the answer's est_tokens does not count it (the block prices itself, est_tokens= on its root). A section
// that does not fit is skipped and the next tried; the first that still does not fit the unspent rest is an excerpt around the best window of
// the task's words (cut="1" range=). A section is a lexical match, not a verified answer: a section that shares the task's words and answers
// another question can rank first, and the legend and match="lexical" on the root say so.
//
// BUDGETS. The answer is served first. Under --token-budget, --max-tokens with --detail or MCP budget_tokens the block is served into the
// tokens left after the answer's est_tokens (the allowance shrinks until the priced block fits) and holds only the part that does not fit:
// held="budget" held_bytes= on the root, f p= why="budget" held=N per file, next= the call without the budget. When not even
// kForDocMinAllowance bytes fit it is held whole (the files named).
#include "forpage.h" // FileTail — the answer's <t> rows
#include "nextverb.h" // nextFlag / nextAttrXml
#include "recall.h" // recallLensScores, buildSectionGranularBody, loadRecallBody, allocateRecallShares, admitRecallUnits
#include "sarif.h" // rootPrefixOf / rootRelativeUri — the display path the tail rows print
#include "serialize.h" // escapeXml, appendCdataSafe, jsonStr

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
inline constexpr std::size_t kForDocBodyTriggerRows = 10; // file-tail <t> files the trigger reads (the first ones in rank order)
inline constexpr std::size_t kForDocBodyTriggerDocs = 2; // doc files among them that fire it
inline constexpr std::size_t kForDocBodyFiles = 3; // doc files whose sections are served (first shown first)
inline constexpr std::size_t kForDocBodyBytes = 7500; // section text the block may print, shared by its files (own allowance, outside est_tokens)

inline bool forDocBodyOn()
{
    return std::getenv( "RIPWIRE_NO_FOR_DOC_BODY" ) == nullptr;
}

// A doc file for this block: the extension set the trigger was written with (.md .markdown .mdx .rst .txt .html .htm),
// case-insensitive. An extension test on the printed path, so the trigger reads exactly what the reader sees.
inline bool forDocBodyExt( std::string_view path ) noexcept
{
    static constexpr std::string_view kExts[] = { ".htm", ".html", ".markdown", ".md", ".mdx", ".rst", ".txt" };
    const std::size_t dot = path.rfind( '.' );
    const std::size_t slash = path.rfind( '/' );
    if( dot == std::string_view::npos || ( slash != std::string_view::npos && dot < slash ) || path.size() - dot > 9 )
    {
        return false;
    }
    char buf[10] = {};
    std::size_t n = 0;
    for( std::size_t i = dot; i < path.size(); ++i )
    {
        const char c = path[i];
        buf[n++] = ( c >= 'A' && c <= 'Z' ) ? char( c - 'A' + 'a' ) : c;
    }
    const std::string_view ext( buf, n );
    return std::ranges::find( kExts, ext ) != std::end( kExts );
}

namespace fordocbody_detail
{
// Python's \w over a UTF-8 string, close enough for a task line: ASCII letters, digits and '_'; a multi-byte letter is a word
// byte, except the General Punctuation block (U+2000..U+206F: curly quotes, dashes), which is punctuation.
inline bool isWordAt( std::string_view s, std::size_t i ) noexcept
{
    const unsigned char c = static_cast<unsigned char>( s[i] );
    if( c < 0x80 )
    {
        return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_';
    }
    std::size_t lead = i; // the sequence's lead byte
    while( lead > 0 && ( static_cast<unsigned char>( s[lead] ) & 0xC0 ) == 0x80 )
    {
        --lead;
    }
    const unsigned char l0 = static_cast<unsigned char>( s[lead] );
    const unsigned char l1 = lead + 1 < s.size() ? static_cast<unsigned char>( s[lead + 1] ) : 0;
    return !( l0 == 0xE2 && ( l1 == 0x80 || l1 == 0x81 ) ); // E2 80 80 .. E2 81 AF = U+2000..U+206F
}
inline bool isLower( char c ) noexcept { return c >= 'a' && c <= 'z'; }
inline bool isUpper( char c ) noexcept { return c >= 'A' && c <= 'Z'; }
inline bool isAlpha( char c ) noexcept { return isLower( c ) || isUpper( c ); }
// \b after position j (exclusive end of a match): the end of the string or a non-word byte
inline bool boundaryAt( std::string_view s, std::size_t j ) noexcept { return j >= s.size() || !isWordAt( s, j ); }
// the end of the run of `pred` bytes that starts at i (i itself when s[i] is not one)
inline std::size_t runOf( std::string_view s, std::size_t i, bool ( *pred )( char ) ) noexcept
{
    return i >= s.size() ? s.size() : std::size_t( std::find_if_not( s.begin() + std::ptrdiff_t( i ), s.end(), pred ) - s.begin() );
}
inline bool isLowerOrUnderscore( char c ) noexcept { return isLower( c ) || c == '_'; }

// The three word shapes, each anchored at a word start i: `[a-z]+_[a-z_]+\b`, `[a-z]+[A-Z][A-Za-z]+\b`, `[A-Z][a-z]+[A-Z][A-Za-z]*\b`.
// Each quantified run is maximal: a shorter one would end before a letter, which is a word byte, so no \b could follow it.
inline bool codeWordAt( std::string_view s, std::size_t i ) noexcept
{
    if( isLower( s[i] ) )
    {
        const std::size_t low = runOf( s, i, isLower );
        if( low < s.size() && s[low] == '_' )
        {
            const std::size_t tail = runOf( s, low + 1, isLowerOrUnderscore );
            if( tail > low + 1 && boundaryAt( s, tail ) )
            {
                return true; // snake_case
            }
        }
        if( low < s.size() && isUpper( s[low] ) )
        {
            const std::size_t tail = runOf( s, low + 1, isAlpha );
            return tail > low + 1 && boundaryAt( s, tail ); // camelCase
        }
        return false;
    }
    if( isUpper( s[i] ) )
    {
        const std::size_t low = runOf( s, i + 1, isLower );
        if( low > i + 1 && low < s.size() && isUpper( s[low] ) )
        {
            return boundaryAt( s, runOf( s, low + 1, isAlpha ) ); // InnerCaps (PascalCase with a second capital)
        }
    }
    return false;
}
} // namespace fordocbody_detail

// The task reads as prose: none of the code cues trigger v1 named (a backtick, `::`, `()`, a snake_case, camelCase or InnerCaps
// word, a dotted call `a.b(`). A code-shaped task asks about code, and the block stays silent on it.
inline bool forDocBodyProseTask( std::string_view task ) noexcept
{
    using namespace fordocbody_detail;
    if( task.find( '`' ) != std::string_view::npos || task.find( "::" ) != std::string_view::npos || task.find( "()" ) != std::string_view::npos )
    {
        return false;
    }
    for( std::size_t i = 0; i < task.size(); ++i )
    {
        if( ( i == 0 || !isWordAt( task, i - 1 ) ) && codeWordAt( task, i ) )
        {
            return false;
        }
        // a dotted call: a word byte, '.', one or more word bytes, '('
        if( task[i] == '.' && i > 0 && isWordAt( task, i - 1 ) && i + 1 < task.size() && isWordAt( task, i + 1 ) )
        {
            std::size_t j = i + 1;
            while( j < task.size() && isWordAt( task, j ) )
            {
                ++j;
            }
            if( j < task.size() && task[j] == '(' )
            {
                return false;
            }
        }
    }
    return true;
}

// The trigger's verdict and the files it serves.
struct ForDocBodyPick
{
    std::vector<std::uint32_t> fileIds; // the first kForDocBodyFiles doc files the answer shows (sig rows, then t rows by rank)
    bool fires = false;
};

// `shownSigIds`: the signature rows the answer printed, in order; `rankTail()`: the answer's <t> rows in RANK order (computeFileTail
// with rankOrder: the order trigger v1 was written on, before a code question's tail printed its code rows first), display form
// relative to `rootArg`. Called only for a prose task. Present-only: every other task returns fires=false and reads nothing.
template<class RankTail>
inline ForDocBodyPick pickForDocBody( const IngestResult& ing, std::string_view task, std::span<const NodeId> shownSigIds, RankTail&& rankTail,
                                      std::string_view rootArg )
{
    ForDocBodyPick pick;
    if( !forDocBodyOn() || !forDocBodyProseTask( task ) )
    {
        return pick;
    }
    const FileTail rankRows = rankTail();
    const std::vector<std::string>& tailPaths = rankRows.paths;
    const std::size_t head = std::min( tailPaths.size(), kForDocBodyTriggerRows );
    const auto topDocs = std::count_if( tailPaths.begin(), tailPaths.begin() + std::ptrdiff_t( head ),
                                        []( const std::string& p )
                                        { return forDocBodyExt( p ); } );
    if( std::size_t( topDocs ) < kForDocBodyTriggerDocs )
    {
        return pick;
    }
    pick.fires = true;
    const auto add = [&]( std::uint32_t fileId )
    {
        if( pick.fileIds.size() < kForDocBodyFiles && std::ranges::find( pick.fileIds, fileId ) == pick.fileIds.end() )
        {
            pick.fileIds.push_back( fileId );
        }
    };
    for( const NodeId id : shownSigIds )
    {
        ASSUME( id < ing.symbols.size(), "pickForDocBody: a shown signature row names a symbol outside the index" );
        const std::uint32_t fileId = ing.symbols[id].fileId;
        if( forDocBodyExt( ing.files[fileId] ) )
        {
            add( fileId );
        }
    }
    // the <t> rows print display paths: map the doc ones back to file ids, in row order (one pass over the files)
    std::vector<std::string_view> wanted;
    for( const std::string& p : tailPaths )
    {
        if( wanted.size() + pick.fileIds.size() >= kForDocBodyFiles * 2 )
        {
            break; // enough candidates: a duplicate of a sig-row file is the only way one is skipped
        }
        if( forDocBodyExt( p ) )
        {
            wanted.push_back( p );
        }
    }
    std::vector<std::uint32_t> idOf( wanted.size(), UINT32_MAX );
    const std::string prefix = sarif::rootPrefixOf( rootArg );
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( !forDocBodyExt( ing.files[f] ) )
        {
            continue;
        }
        const std::string_view shown = rootArg.empty() ? std::string_view( ing.files[f] ) : sarif::rootRelativeUri( ing.files[f], prefix );
        for( std::size_t w = 0; w < wanted.size(); ++w )
        {
            if( idOf[w] == UINT32_MAX && wanted[w] == shown )
            {
                idOf[w] = f;
            }
        }
    }
    for( const std::uint32_t f : idOf )
    {
        if( f != UINT32_MAX )
        {
            add( f );
        }
    }
    return pick;
}

// One served passage.
struct ForDocPassage
{
    std::uint32_t fileId = 0;
    std::uint32_t lineLo = 0, lineHi = 0; // source lines (0 = none: extracted text has no source lines)
    std::string heading; // the section's heading ("" for a whole-doc head)
    std::string text;
    std::uint32_t rank = 0, of = 0; // rank among the file's picked sections (1 = top), of= how many were picked
    bool isSection = false;
    bool isExtracted = false;
    bool isCut = false;
    std::uint32_t rangeLo = 0, rangeHi = 0, rangeOf = 0; // isCut: the excerpt is bytes [rangeLo, rangeHi) of the rangeOf-byte section text
};

// Why a picked doc file (or part of one) was not served. Unreadable: the file could not be read; Allowance: the block's own
// 7500 bytes were spent; Budget: a token budget left less room than the allowance and the default allowance would have served it.
enum class ForDocWhy : std::uint8_t
{
    Unreadable,
    Allowance,
    Budget
};
inline std::string_view forDocWhyName( ForDocWhy why ) noexcept
{
    return why == ForDocWhy::Unreadable ? "unreadable" : why == ForDocWhy::Allowance ? "allowance"
                                                                                     : "budget";
}

struct ForDocUnserved
{
    std::uint32_t fileId = 0;
    ForDocWhy why = ForDocWhy::Allowance;
    std::uint32_t held = 0; // Budget only: the sections of this file the budget kept out (0 = the whole file)
};

struct ForDocBody
{
    std::vector<ForDocPassage> passages; // file by file in pick order, each file's sections best first
    std::vector<ForDocUnserved> unserved; // picked files with nothing served, or with sections a budget kept out
    std::size_t textBytes = 0;
    std::size_t dropped = 0; // picked sections the allowance left out
    std::size_t allowance = kForDocBodyBytes; // the section text this block could print (less than the default under a token budget)
    std::size_t heldBytes = 0; // text the default allowance would have printed and the token budget kept out
    bool isCapped = false;
    bool isHeldByBudget = false;
};

// The token budget a block is served under: tokens 0 = none. The answer is served first; the block gets what is left.
struct ForDocBodyBudget
{
    std::size_t tokens = 0; // the budget asked for (--token-budget, --max-tokens with --detail, MCP budget_tokens)
    std::size_t answerTokens = 0; // the answer's est_tokens
    bool active() const noexcept { return tokens > 0; }
    std::size_t leftTokens() const noexcept { return tokens > answerTokens ? tokens - answerTokens : 0; }
};

inline constexpr std::size_t kForDocTopShareTenths = 6; // a file's top-ranked section that does not fit is an excerpt of up to this many tenths of the file's share
inline constexpr std::size_t kForDocExcerptMinBytes = 400; // an excerpt is cut only when at least this much allowance is left
inline constexpr std::size_t kForDocMinAllowance = 600; // under a token budget a block with less text room than this is held whole

namespace fordocbody_detail
{
inline constexpr std::string_view kEllipsis = "\xE2\x80\xA6"; // "…"

struct DocExcerpt
{
    std::string text; // the window, with an ellipsis on each cut side
    std::size_t from = 0, to = 0; // its byte range in the source text
};

// The one window of at most `maxBytes` that holds the most of the task's words: each task term weighs 1 / its count in the text, so a
// term that occurs once pulls harder than one that occurs everywhere. The window starts at a hit (backed to its line start when
// that is close) and ends at a line or word end. No hit anywhere: the head of the text. A text that fits is returned whole.
inline DocExcerpt excerptAroundTerms( std::string_view text, const std::vector<std::string>& terms, std::size_t maxBytes )
{
    DocExcerpt ex;
    if( text.size() <= maxBytes )
    {
        ex.text = std::string( text );
        ex.to = text.size();
        return ex;
    }
    const std::size_t room = maxBytes > 2 * kEllipsis.size() ? maxBytes - 2 * kEllipsis.size() : 0;
    std::vector<std::uint32_t> counts( terms.size(), 0 );
    std::vector<std::pair<std::size_t, std::uint32_t>> hits; // (byte position, term index)
    forEachLexSubtoken( text,
                        [&]( std::size_t tokStartByte, std::size_t tokEndByte )
                        {
                            if( tokEndByte - tokStartByte < 2 )
                            {
                                return;
                            }
                            const std::size_t t = recallMatchedTermIndex( text, tokStartByte, tokEndByte - tokStartByte, terms );
                            if( t < terms.size() )
                            {
                                hits.emplace_back( tokStartByte, std::uint32_t( t ) );
                                ++counts[t];
                            }
                        } );
    std::vector<double> prefix( hits.size() + 1, 0.0 ); // prefix[i] = weight of hits[0, i)
    for( std::size_t i = 0; i < hits.size(); ++i )
    {
        prefix[i + 1] = prefix[i] + 1.0 / double( counts[hits[i].second] );
    }
    const auto posLess = []( const std::pair<std::size_t, std::uint32_t>& h, std::size_t pos )
    { return h.first < pos; };
    std::size_t from = 0;
    double best = -1.0;
    for( std::size_t i = 0; i < hits.size(); ++i )
    {
        std::size_t start = hits[i].first;
        const std::size_t lineStart = text.rfind( '\n', start == 0 ? 0 : start - 1 );
        if( lineStart != std::string_view::npos && start - ( lineStart + 1 ) <= 160 )
        {
            start = lineStart + 1;
        }
        const auto lo = std::lower_bound( hits.begin(), hits.end(), start, posLess ) - hits.begin();
        const auto hi = std::lower_bound( hits.begin(), hits.end(), start + room, posLess ) - hits.begin();
        const double weight = prefix[std::size_t( hi )] - prefix[std::size_t( lo )];
        if( weight > best + 1e-9 )
        {
            best = weight;
            from = start;
        }
    }
    if( best > 0.0 )
    {
        // centre the window on the weighted centroid of the hits it holds, so the words sit in the middle, not at its end
        const auto lo = std::lower_bound( hits.begin(), hits.end(), from, posLess ) - hits.begin();
        const auto hi = std::lower_bound( hits.begin(), hits.end(), from + room, posLess ) - hits.begin();
        double centroid = 0.0;
        for( auto i = lo; i < hi; ++i )
        {
            centroid += double( hits[std::size_t( i )].first ) / double( counts[hits[std::size_t( i )].second] );
        }
        const std::size_t mid = std::size_t( centroid / best );
        from = mid > room / 2 ? mid - room / 2 : 0;
        from = std::min( from, text.size() - room ); // text.size() > maxBytes >= room: a window at the end is full
        const std::size_t lineStart = from == 0 ? std::string_view::npos : text.rfind( '\n', from - 1 );
        if( lineStart != std::string_view::npos && from - ( lineStart + 1 ) <= 160 )
        {
            from = lineStart + 1;
        }
    }
    while( from < text.size() && ( static_cast<unsigned char>( text[from] ) & 0xC0 ) == 0x80 )
    {
        ++from;
    }
    std::size_t to = std::min( text.size(), from + room );
    if( to < text.size() )
    {
        const std::size_t floorAt = from + room * 6 / 10;
        const std::size_t nl = text.rfind( '\n', to - 1 );
        const std::size_t sp = text.rfind( ' ', to - 1 );
        if( nl != std::string_view::npos && nl >= floorAt )
        {
            to = nl + 1;
        }
        else if( sp != std::string_view::npos && sp >= floorAt )
        {
            to = sp + 1;
        }
        while( to > from && ( static_cast<unsigned char>( text[to] ) & 0xC0 ) == 0x80 )
        {
            --to;
        }
    }
    ex.from = from;
    ex.to = to;
    ex.text = std::string( from > 0 ? kEllipsis : std::string_view() ) + std::string( text.substr( from, to - from ) ) +
              std::string( to < text.size() ? kEllipsis : std::string_view() );
    return ex;
}

inline std::uint32_t newlinesIn( std::string_view s ) noexcept
{
    return std::uint32_t( std::count( s.begin(), s.end(), '\n' ) );
}

// one passage from a unit's text: whole when `maxBytes` holds it, else the best-window excerpt (cut="1" with its byte range)
inline ForDocPassage unitPassage( std::uint32_t fileId, std::string_view text, std::uint32_t lineLo, std::uint32_t lineHi, std::string heading,
                                  std::uint32_t rank, std::uint32_t of, bool isSection, bool isExtracted, const std::vector<std::string>& terms,
                                  std::size_t maxBytes )
{
    ForDocPassage p;
    p.fileId = fileId;
    p.heading = std::move( heading );
    p.rank = rank;
    p.of = of;
    p.isSection = isSection;
    p.isExtracted = isExtracted;
    const DocExcerpt ex = excerptAroundTerms( text, terms, maxBytes );
    p.text = ex.text;
    p.isCut = ex.to - ex.from < text.size();
    if( p.isCut )
    {
        p.rangeLo = std::uint32_t( ex.from );
        p.rangeHi = std::uint32_t( ex.to );
        p.rangeOf = std::uint32_t( text.size() );
    }
    if( lineLo > 0 )
    {
        // a line the excerpt only opens (its last byte is the newline that ends the previous one) is not a line it served
        const std::string_view served = text.substr( ex.from, ex.to - ex.from );
        p.lineLo = lineLo + newlinesIn( text.substr( 0, ex.from ) );
        p.lineHi = std::min( lineHi, p.lineLo + newlinesIn( served.substr( 0, served.empty() ? 0 : served.size() - 1 ) ) );
    }
    return p;
}

// a whole-doc head (a doc with no heading section, or extracted text): the whole text, or the best window of it
inline ForDocPassage wholeDocPassage( const IngestResult& ing, std::uint32_t fileId, std::string_view text, const std::vector<std::string>& terms,
                                      std::size_t maxBytes )
{
    const bool isExtracted = ing.docText.find( fileId ) != ing.docText.end();
    const std::uint32_t lineHi = 1 + newlinesIn( text.substr( 0, text.empty() ? 0 : text.size() - 1 ) );
    return unitPassage( fileId, text, isExtracted ? 0 : 1, isExtracted ? 0 : lineHi, {}, 0, 0, false, isExtracted, terms, maxBytes );
}

// What one loaded file keeps from the first admission pass.
struct FileServe
{
    std::vector<ForDocPassage> passages;
    std::vector<std::pair<std::uint32_t, std::uint32_t>> missed; // (rank 1-based, unit index) the file's share did not admit, best first
    std::size_t spent = 0;
    std::size_t units = 0;
    bool isServed = false;
};
} // namespace fordocbody_detail

// The doc files a fired pick loads: --recall's section choice per file, read once and served at any allowance.
struct ForDocPrep
{
    struct Loaded
    {
        std::uint32_t fileId = 0;
        std::optional<RecallSectionBody> sections;
        std::string whole; // a doc with no heading sections: its whole text
        std::size_t demand = 0;
    };
    std::vector<Loaded> loaded;
    std::vector<std::uint32_t> unreadable;
    std::vector<std::string> queryToks;
};

inline ForDocPrep prepareForDocBody( const IngestResult& ing, const std::vector<std::uint32_t>& outOff, const std::vector<NodeId>& outTargets,
                                     std::string_view task, const ForDocBodyPick& pick, RedactCounts* redact, std::string_view rootArg )
{
    ForDocPrep prep;
    if( !pick.fires || pick.fileIds.empty() )
    {
        return prep;
    }
    const std::vector<float> scores = recallLensScores( ing, outOff, outTargets, task, rootArg );
    subtokens( task, prep.queryToks );
    for( const std::uint32_t f : pick.fileIds )
    {
        ForDocPrep::Loaded l { f, buildSectionGranularBody( ing, scores, f, redact, prep.queryToks ), {}, 0 };
        if( l.sections )
        {
            for( const RecallSectionUnit& u : l.sections->units )
            {
                l.demand += recallUnitCostBytes( u );
            }
        }
        else if( std::optional<std::string> body = loadRecallBody( ing, f, redact ) )
        {
            l.whole = std::move( *body );
            l.demand = l.whole.size();
        }
        else
        {
            prep.unreadable.push_back( f ); // unreadable on disk: named (why="unreadable"), never a stub
            continue;
        }
        prep.loaded.push_back( std::move( l ) );
    }
    return prep;
}

namespace fordocbody_detail
{
// one unit of a loaded file as a passage, whole or cut to the best window within `maxBytes`
inline ForDocPassage loadedUnitPassage( const IngestResult& ing, const ForDocPrep& prep, const ForDocPrep::Loaded& l, std::uint32_t u, std::uint32_t rank,
                                        std::size_t maxBytes )
{
    if( !l.sections )
    {
        return wholeDocPassage( ing, l.fileId, l.whole, prep.queryToks, maxBytes );
    }
    const RecallSectionUnit& unit = l.sections->units[u];
    return unitPassage( l.fileId, std::string_view( l.sections->body ).substr( unit.bodyOffset, unit.bodyLength ), unit.lineLo, unit.lineHi,
                        ing.symbols[unit.symIndex].name, rank, std::uint32_t( l.sections->units.size() ), true, false, prep.queryToks, maxBytes );
}

// pass 1 for one file: its sections in rank order, each admitted whole when it fits what is left of the file's share and SKIPPED
// when it does not (the next one is tried: a misfit no longer ends the file). The file's top-ranked section is never skipped: when it
// does not fit it is an excerpt around the task's words, up to kForDocTopShareTenths of the share (all of it for a file with one unit),
// and the sections below it share the rest.
inline FileServe admitFileSections( const IngestResult& ing, const ForDocPrep& prep, const ForDocPrep::Loaded& l, std::size_t share )
{
    FileServe fs;
    fs.isServed = true;
    const std::size_t unitCount = l.sections ? l.sections->units.size() : 1;
    fs.units = unitCount;
    const auto topExcerpt = [&]( std::uint32_t u )
    {
        const std::size_t cap = unitCount == 1 ? share : share * kForDocTopShareTenths / 10;
        if( cap < kForDocExcerptMinBytes )
        {
            return false;
        }
        fs.passages.push_back( loadedUnitPassage( ing, prep, l, u, 1, cap ) );
        fs.spent += fs.passages.back().text.size();
        return true;
    };
    if( !l.sections )
    {
        if( l.whole.size() <= share )
        {
            fs.passages.push_back( wholeDocPassage( ing, l.fileId, l.whole, {}, share ) );
            fs.spent = l.whole.size();
        }
        else if( !topExcerpt( 0 ) )
        {
            fs.missed.emplace_back( 1, 0 );
        }
        return fs;
    }
    const RecallSectionBody& sec = *l.sections;
    std::uint32_t rank = 0;
    for( const std::uint32_t u : sec.rankOrder )
    {
        ++rank;
        const RecallSectionUnit& unit = sec.units[u];
        const std::size_t cost = recallUnitCostBytes( unit );
        if( fs.spent + cost > share )
        {
            if( rank == 1 && topExcerpt( u ) )
            {
                continue;
            }
            fs.missed.emplace_back( rank, u );
            continue;
        }
        fs.spent += cost;
        fs.passages.push_back( ForDocPassage { l.fileId, unit.lineLo, unit.lineHi, ing.symbols[unit.symIndex].name,
                                               sec.body.substr( unit.bodyOffset, unit.bodyLength ), rank, std::uint32_t( sec.units.size() ), /*isSection=*/true } );
    }
    return fs;
}

// pass 2: the allowance the files left unspent goes to the sections their shares did not admit, the pool split equally among the files that
// still have one (a file that needs less hands the rest on); per file best first: a section that fits is admitted whole, the first that
// does not is cut to fit around the best window of the task's words
inline void admitFromPool( const IngestResult& ing, const ForDocPrep& prep, std::vector<FileServe>& served, std::size_t pool )
{
    std::size_t waiting = std::ranges::count_if( served, []( const FileServe& fs )
                                                 { return !fs.missed.empty(); } );
    for( std::size_t i = 0; i < served.size(); ++i )
    {
        FileServe& fs = served[i];
        if( fs.missed.empty() )
        {
            continue;
        }
        std::size_t room = std::min( pool, pool / waiting );
        --waiting;
        const ForDocPrep::Loaded& l = prep.loaded[i];
        std::vector<std::pair<std::uint32_t, std::uint32_t>> stillMissed;
        bool isExcerpted = false;
        for( const auto& [rank, u] : fs.missed )
        {
            const std::size_t cost = l.sections ? recallUnitCostBytes( l.sections->units[u] ) : l.whole.size();
            if( isExcerpted || room < kForDocExcerptMinBytes )
            {
                stillMissed.emplace_back( rank, u );
                continue;
            }
            fs.passages.push_back( loadedUnitPassage( ing, prep, l, u, rank, room ) );
            const bool isFit = cost <= room;
            const std::size_t used = std::min( room, isFit ? cost : fs.passages.back().text.size() );
            room -= used;
            pool -= std::min( pool, used );
            isExcerpted = !isFit;
        }
        fs.missed = std::move( stillMissed );
    }
}
} // namespace fordocbody_detail

// The block served at one allowance: the files share it by recall's water-filling, each file admits its sections best first (a
// misfit is skipped, not a stop), and what the files left unspent is given to the sections their shares missed (the first
// that still does not fit is an excerpt around the best window of the task's words, cut="1" with its byte range).
inline ForDocBody serveForDocBody( const IngestResult& ing, const ForDocPrep& prep, std::size_t allowance )
{
    ForDocBody out;
    out.allowance = allowance;
    for( const std::uint32_t f : prep.unreadable )
    {
        out.unserved.push_back( { f, ForDocWhy::Unreadable, 0 } );
    }
    std::vector<std::size_t> overhead( prep.loaded.size(), 0 ), demand; // the markup is the block's own, outside the text allowance
    for( const ForDocPrep::Loaded& l : prep.loaded )
    {
        demand.push_back( l.demand );
    }
    const RecallShares shares = allocateRecallShares( overhead, demand, allowance );
    std::vector<fordocbody_detail::FileServe> served;
    std::size_t spent = 0;
    for( std::size_t i = 0; i < shares.servedCount; ++i )
    {
        served.push_back( fordocbody_detail::admitFileSections( ing, prep, prep.loaded[i], shares.alloc[i] ) );
        spent += served.back().spent;
    }
    fordocbody_detail::admitFromPool( ing, prep, served, allowance > spent ? allowance - spent : 0 );
    for( std::size_t i = 0; i < prep.loaded.size(); ++i )
    {
        if( i >= shares.servedCount )
        {
            out.unserved.push_back( { prep.loaded[i].fileId, ForDocWhy::Allowance, 0 } ); // the allowance served the files before it
            out.isCapped = true;
            continue;
        }
        fordocbody_detail::FileServe& fs = served[i];
        std::ranges::stable_sort( fs.passages, []( const ForDocPassage& a, const ForDocPassage& b )
                                  { return a.rank < b.rank; } );
        out.dropped += fs.units - fs.passages.size();
        out.isCapped = out.isCapped || fs.passages.size() < fs.units || std::ranges::any_of( fs.passages, []( const ForDocPassage& p )
                                                                                             { return p.isCut; } );
        for( ForDocPassage& p : fs.passages )
        {
            out.passages.push_back( std::move( p ) );
        }
    }
    for( const ForDocPassage& p : out.passages )
    {
        out.textBytes += p.text.size();
    }
    return out;
}

// The block served under a token budget: the same block at a smaller allowance, with what the budget alone kept out named (held=).
// The block the default allowance would have served is served beside it: the difference is the held part.
inline ForDocBody serveForDocBodyHeld( const IngestResult& ing, const ForDocPrep& prep, std::size_t allowance )
{
    ForDocBody out = serveForDocBody( ing, prep, allowance );
    if( allowance >= kForDocBodyBytes )
    {
        return out;
    }
    const ForDocBody full = serveForDocBody( ing, prep, kForDocBodyBytes );
    const auto countOf = []( const ForDocBody& b, std::uint32_t f ) -> std::uint32_t
    { return std::uint32_t( std::ranges::count_if( b.passages, [&]( const ForDocPassage& p )
                                                   { return p.fileId == f; } ) ); };
    for( ForDocUnserved& u : out.unserved )
    {
        if( u.why == ForDocWhy::Allowance && countOf( full, u.fileId ) > 0 )
        {
            u.why = ForDocWhy::Budget;
            u.held = countOf( full, u.fileId );
        }
    }
    for( const ForDocPrep::Loaded& l : prep.loaded )
    {
        const std::uint32_t cut = countOf( out, l.fileId ), uncut = countOf( full, l.fileId );
        if( cut > 0 && uncut > cut )
        {
            out.unserved.push_back( { l.fileId, ForDocWhy::Budget, uncut - cut } );
        }
    }
    out.heldBytes = full.textBytes > out.textBytes ? full.textBytes - out.textBytes : 0;
    out.isHeldByBudget = out.heldBytes > 0;
    return out;
}

// ── spellings ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
// No double dash inside the comments: XML forbids it there.
inline constexpr std::string_view kForDocBodyLegend =
    "<!-- ripwire for doc_body: the task reads as prose (a cue list, not a parse: it holds no backtick, ::, (), lowercase snake_case word "
    "ending in a letter, camelCase or CapsLowCaps word, or dotted call a.b(, so handle_upload_3, MAX_RETRIES, __init__, HTTPServer and getX "
    "read as prose) and 2 or more of the first 10 t files in rank order are doc files, so sections of the first 3 doc files this answer shows "
    "follow. b t=\"section\" p= ranks highest in that file for the task's words (the recall verb's pick): n= heading, l= e= source lines, "
    "rank= its place among the of= sections picked there (1 = top). It is a lexical match, not a verified answer: a section "
    "that shares the task's words and answers another question can rank first (match=\"lexical\" on the root says so). b t=\"doc\": the head of a doc with no matching heading "
    "section; src=\"extracted\": text from HTML or a notebook, no source lines; cut=\"1\" range=S-E/N: an excerpt, bytes S to E of the "
    "section's N, around the task's words. allowance= section text the files share, bytes= printed; est_tokens= prices this block alone (the "
    "answer's est_tokens leaves it out); dropped= picked sections left out, capped=\"1\", next= the call that serves more; f p= a doc file with "
    "sections left out, why= unreadable, allowance or budget; held=\"budget\" held_bytes=: a token budget kept that much text out, next= "
    "repeats the call without it. The answer above is unchanged -->";

inline std::string forDocBodyNext( std::string_view task ) { return nextAttrXml( nextFlag( "--recall=", task ) ); }

// A block no budget room is left for: the sections are not printed, the files are named, next= is the call without the budget.
inline std::string forDocBodyHeldXml( const IngestResult& ing, const ForDocBodyPick& pick, std::string_view task, std::string_view rootArg )
{
    std::vector<char> esc;
    const std::string prefix = sarif::rootPrefixOf( rootArg );
    std::string out =
        "<!-- ripwire for doc_body held=\"budget\": the token budget leaves no room after the answer for the doc sections, so they are not "
        "printed; match=\"lexical\" is the kind of section they would be; f p= the doc files they come from; next= repeats this call without "
        "the budget. The answer above is unchanged -->"
        "<doc_body match=\"lexical\" held=\"budget\" files=\"" +
        std::to_string( pick.fileIds.size() ) + "\"" + nextAttrXml( nextFlag( "--for=", task ) ) + ">";
    for( const std::uint32_t f : pick.fileIds )
    {
        const std::string_view p = rootArg.empty() ? std::string_view( ing.files[f] ) : sarif::rootRelativeUri( ing.files[f], prefix );
        out += "<f p=\"" + std::string( escapeXml( p, esc ) ) + "\"/>";
    }
    return out + "</doc_body>";
}

// the block's own price: its markup at the markup rate, its section text at the body rate (the root's est_tokens= is part of what it prices)
inline std::string forDocBodyPriceAttr( std::size_t blockBytesWithoutPrice, const ForDocBody& body, std::size_t* tokens )
{
    ASSUME( blockBytesWithoutPrice >= body.textBytes, "forDocBodyPriceAttr: the block is smaller than its own text" );
    return pricedRootAttr( blockBytesWithoutPrice - body.textBytes, kBytesPerTokenDefault, body.textBytes, tokens );
}

// The XML block of a served body, with its price. Returns {block, est_tokens}.
inline std::pair<std::string, std::size_t> forDocBodyXml( const IngestResult& ing, const ForDocBody& body, const ForDocBodyPick& pick, std::string_view task,
                                                          std::string_view rootArg )
{
    std::vector<char> esc;
    const std::string prefix = sarif::rootPrefixOf( rootArg );
    const auto display = [&]( std::uint32_t f ) -> std::string
    {
        const std::string_view p = rootArg.empty() ? std::string_view( ing.files[f] ) : sarif::rootRelativeUri( ing.files[f], prefix );
        return std::string( escapeXml( p, esc ) );
    };
    std::string rows;
    for( const ForDocPassage& p : body.passages )
    {
        rows += p.isSection ? "<b t=\"section\" p=\"" : "<b t=\"doc\" p=\"";
        rows += display( p.fileId ) + "\"";
        if( p.lineLo > 0 )
        {
            rows += " l=\"" + std::to_string( p.lineLo ) + "\" e=\"" + std::to_string( p.lineHi ) + "\"";
        }
        if( p.isSection )
        {
            rows += " n=\"" + std::string( escapeXml( p.heading, esc ) ) + "\" rank=\"" + std::to_string( p.rank ) + "\" of=\"" + std::to_string( p.of ) + "\"";
        }
        rows += p.isExtracted ? " src=\"extracted\"" : "";
        if( p.isCut )
        {
            rows += " cut=\"1\" range=\"" + std::to_string( p.rangeLo ) + "-" + std::to_string( p.rangeHi ) + "/" + std::to_string( p.rangeOf ) + "\"";
        }
        rows += "><![CDATA[";
        appendCdataSafe( p.text, rows );
        rows += "]]></b>";
    }
    for( const ForDocUnserved& u : body.unserved )
    {
        rows += "<f p=\"" + display( u.fileId ) + "\" why=\"" + std::string( forDocWhyName( u.why ) ) + "\"" +
                ( u.held > 0 ? " held=\"" + std::to_string( u.held ) + "\"" : std::string() ) + "/>";
    }
    std::string attrs = " files=\"" + std::to_string( pick.fileIds.size() ) + "\" allowance=\"" + std::to_string( body.allowance ) + "\" bytes=\"" +
                        std::to_string( body.textBytes ) + "\"";
    if( body.isHeldByBudget )
    {
        attrs += " held=\"budget\" held_bytes=\"" + std::to_string( body.heldBytes ) + "\"";
    }
    if( body.dropped > 0 )
    {
        attrs += " dropped=\"" + std::to_string( body.dropped ) + "\"";
    }
    if( body.isHeldByBudget )
    {
        attrs += nextAttrXml( nextFlag( "--for=", task ) );
    }
    else if( body.isCapped )
    {
        attrs += forDocBodyNext( task );
    }
    if( body.isCapped )
    {
        attrs += " capped=\"1\"";
    }
    const std::string open = "<doc_body match=\"lexical\"";
    const std::string close = "</doc_body>";
    std::size_t tokens = 0;
    const std::string priceAttr =
        forDocBodyPriceAttr( kForDocBodyLegend.size() + open.size() + attrs.size() + 1 + rows.size() + close.size(), body, &tokens );
    return { std::string( kForDocBodyLegend ) + open + priceAttr + attrs + ">" + rows + close, tokens };
}

// The --json twin: one key, appended after "sigs" (outside the answer's est_tokens, as the XML block). Returns {text, est_tokens}.
inline std::pair<std::string, std::size_t> forDocBodyJsonServed( const IngestResult& ing, const ForDocBody& body, const ForDocBodyPick& pick,
                                                                 std::string_view task, std::string_view rootArg )
{
    const std::string prefix = sarif::rootPrefixOf( rootArg );
    const auto display = [&]( std::uint32_t f ) -> std::string_view
    { return rootArg.empty() ? std::string_view( ing.files[f] ) : sarif::rootRelativeUri( ing.files[f], prefix ); };
    std::string head = ",\"doc_body\":{\"in_est_tokens\":false,\"match\":\"lexical\",\"files\":[";
    for( std::size_t i = 0; i < pick.fileIds.size(); ++i )
    {
        head += ( i ? ",\"" : "\"" ) + jsonStr( display( pick.fileIds[i] ) ) + "\"";
    }
    head += "],\"pick\":\"the recall verb's top-ranked sections of these files for the task's words: a lexical match, not a verified answer\"";
    head += ",\"allowance\":" + std::to_string( body.allowance ) + ",\"bytes\":" + std::to_string( body.textBytes );
    std::string tail;
    if( body.isHeldByBudget )
    {
        tail += ",\"held\":\"budget\",\"held_bytes\":" + std::to_string( body.heldBytes );
    }
    if( body.isCapped )
    {
        tail += ",\"capped\":true,\"dropped\":" + std::to_string( body.dropped );
    }
    if( body.isHeldByBudget || body.isCapped )
    {
        tail += ",\"next\":\"" + jsonStr( nextFlag( body.isHeldByBudget ? "--for=" : "--recall=", task ) ) + "\"";
    }
    tail += ",\"passages\":[";
    for( std::size_t i = 0; i < body.passages.size(); ++i )
    {
        const ForDocPassage& p = body.passages[i];
        tail += std::string( i ? ",{" : "{" ) + "\"t\":\"" + ( p.isSection ? "section" : "doc" ) + "\",\"p\":\"" + jsonStr( display( p.fileId ) ) + "\"";
        if( p.lineLo > 0 )
        {
            tail += ",\"l\":" + std::to_string( p.lineLo ) + ",\"e\":" + std::to_string( p.lineHi );
        }
        if( p.isSection )
        {
            tail += ",\"n\":\"" + jsonStr( p.heading ) + "\",\"rank\":" + std::to_string( p.rank ) + ",\"of\":" + std::to_string( p.of );
        }
        tail += p.isExtracted ? ",\"src\":\"extracted\"" : "";
        if( p.isCut )
        {
            tail += ",\"cut\":true,\"range\":[" + std::to_string( p.rangeLo ) + "," + std::to_string( p.rangeHi ) + "],\"section_bytes\":" + std::to_string( p.rangeOf );
        }
        tail += ",\"text\":\"" + jsonStr( p.text ) + "\"}";
    }
    tail += "]";
    if( !body.unserved.empty() )
    {
        tail += ",\"unserved\":[";
        for( std::size_t i = 0; i < body.unserved.size(); ++i )
        {
            const ForDocUnserved& u = body.unserved[i];
            tail += std::string( i ? ",{" : "{" ) + "\"p\":\"" + jsonStr( display( u.fileId ) ) + "\",\"why\":\"" + std::string( forDocWhyName( u.why ) ) + "\"" +
                    ( u.held > 0 ? ",\"held\":" + std::to_string( u.held ) : std::string() ) + "}";
        }
        tail += "]";
    }
    tail += "}";
    // the price: the JSON text escapes a little more than the XML text; the estimate prices the bytes as written
    std::size_t tokens = 0;
    forDocBodyPriceAttr( head.size() + tail.size() + sizeof( ",\"est_tokens\":" ) - 1, body, &tokens );
    return { head + ",\"est_tokens\":" + std::to_string( tokens ) + tail, tokens };
}

// The held-whole twin of forDocBodyHeldXml.
inline std::string forDocBodyJsonHeld( const IngestResult& ing, const ForDocBodyPick& pick, std::string_view task, std::string_view rootArg )
{
    const std::string prefix = sarif::rootPrefixOf( rootArg );
    std::string out = ",\"doc_body\":{\"in_est_tokens\":false,\"match\":\"lexical\",\"files\":[";
    for( std::size_t i = 0; i < pick.fileIds.size(); ++i )
    {
        const std::uint32_t f = pick.fileIds[i];
        out += ( i ? ",\"" : "\"" ) + jsonStr( rootArg.empty() ? std::string_view( ing.files[f] ) : sarif::rootRelativeUri( ing.files[f], prefix ) ) + "\"";
    }
    return out + "],\"held\":\"budget\",\"next\":\"" + jsonStr( nextFlag( "--for=", task ) ) + "\"}";
}

// Serve a fired pick for one dialect: the XML or JSON text of the block ("" when it does not fire). With no budget the default
// allowance; under a budget the allowance the budget leaves after the answer (shrunk until the priced block fits), or the held-whole
// block when not even kForDocMinAllowance fits. `render` maps a served body to {text, est_tokens}, `heldWhole` to the held text.
template<class Render, class HeldWhole>
inline std::string fitForDocBody( const IngestResult& ing, const ForDocPrep& prep, const ForDocBodyBudget& budget, Render&& render, HeldWhole&& heldWhole )
{
    if( !budget.active() )
    {
        return render( serveForDocBody( ing, prep, kForDocBodyBytes ) ).first;
    }
    const std::size_t left = budget.leftTokens();
    std::size_t allowance = kForDocBodyBytes;
    for( int attempt = 0; attempt < 8 && left > 0; ++attempt )
    {
        const auto [text, tokens] = render( serveForDocBodyHeld( ing, prep, allowance ) );
        if( tokens <= left )
        {
            return text;
        }
        if( allowance <= kForDocMinAllowance )
        {
            break; // even the smallest block is over what the answer left
        }
        // the over-shoot in tokens, as text bytes at the body rate (a little more: the block is not linear in its allowance)
        const std::size_t shrink = std::size_t( double( tokens - left ) * kBytesPerTokenBody * 1.15 ) + 16;
        allowance = allowance > kForDocMinAllowance + shrink ? allowance - shrink : kForDocMinAllowance;
    }
    return heldWhole();
}

// The XML block of a fired pick ("" otherwise).
inline std::string renderForDocBodyXml( const IngestResult& ing, const std::vector<std::uint32_t>& outOff, const std::vector<NodeId>& outTargets,
                                        std::string_view task, const ForDocBodyPick& pick, RedactCounts* redact, std::string_view rootArg,
                                        const ForDocBodyBudget& budget )
{
    if( !pick.fires || pick.fileIds.empty() )
    {
        return {};
    }
    const auto heldWhole = [&]
    { return forDocBodyHeldXml( ing, pick, task, rootArg ); };
    if( budget.active() && budget.leftTokens() == 0 )
    {
        return heldWhole(); // the answer alone spent the budget: nothing is read for the block
    }
    const ForDocPrep prep = prepareForDocBody( ing, outOff, outTargets, task, pick, redact, rootArg );
    return fitForDocBody( ing, prep, budget, [&]( const ForDocBody& b )
                          { return forDocBodyXml( ing, b, pick, task, rootArg ); }, heldWhole );
}

// The JSON block of a fired pick (",\"doc_body\":{...}" or "").
inline std::string renderForDocBodyJson( const IngestResult& ing, const std::vector<std::uint32_t>& outOff, const std::vector<NodeId>& outTargets,
                                         std::string_view task, const ForDocBodyPick& pick, RedactCounts* redact, std::string_view rootArg,
                                         const ForDocBodyBudget& budget )
{
    if( !pick.fires || pick.fileIds.empty() )
    {
        return {};
    }
    const auto heldWhole = [&]
    { return forDocBodyJsonHeld( ing, pick, task, rootArg ); };
    if( budget.active() && budget.leftTokens() == 0 )
    {
        return heldWhole();
    }
    const ForDocPrep prep = prepareForDocBody( ing, outOff, outTargets, task, pick, redact, rootArg );
    return fitForDocBody( ing, prep, budget, [&]( const ForDocBody& b )
                          { return forDocBodyJsonServed( ing, b, pick, task, rootArg ); }, heldWhole );
}
} // namespace rw
