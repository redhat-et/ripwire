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
//   (ii) the task is prose: no backtick, `::`, `()`, snake_case, camelCase or dotted-call token (forDocBodyProseTask).
// A code task, or a prose task whose answer leads with code files, prints nothing: the answer is byte-identical.
//
// WHAT. The first kForDocBodyFiles doc files the answer shows (its signature rows first, then its <t> rows in rank order).
// Each file's sections are the ones --recall would pick for the same task (recallLensScores + buildSectionGranularBody), served in
// rank order while they fit the block's OWN allowance (kForDocBodyBytes, shared by the files with recall's water-filling): no code
// row, body or tail row pays for it, and est_tokens does not count it. A section is a lexical match, not a verified answer: a section
// that shares the task's words and answers another question can rank first, and the legend says so.
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
};

struct ForDocBody
{
    std::vector<ForDocPassage> passages; // file by file in pick order, each file's sections best first
    std::vector<std::uint32_t> unread; // picked files that served no text (unreadable, or no allowance left)
    std::size_t textBytes = 0;
    std::size_t dropped = 0; // picked sections the allowance left out
    bool isCapped = false;
};

namespace fordocbody_detail
{
// a whole-doc head (no heading section matched, or extracted text), cut to `allowance` when it is larger
inline ForDocPassage wholeDocPassage( const IngestResult& ing, std::uint32_t fileId, std::string body, std::size_t allowance )
{
    ForDocPassage p;
    p.fileId = fileId;
    p.isExtracted = ing.docText.find( fileId ) != ing.docText.end();
    if( body.size() > allowance )
    {
        const std::size_t keep = allowance > kRecallTruncNoteBytes ? allowance - kRecallTruncNoteBytes : kRecallMinBodyBytes;
        const std::size_t kept = truncateRecallBody( body, keep ).sourceKeptBytes;
        p.isCut = true;
        const std::string_view served( body.data(), std::min( kept, body.size() ) );
        p.lineHi = std::uint32_t( 1 + std::count( served.begin(), served.end() - ( served.empty() ? 0 : 1 ), '\n' ) );
    }
    else
    {
        p.lineHi = std::uint32_t( 1 + std::count( body.begin(), body.end() - ( body.empty() ? 0 : 1 ), '\n' ) );
    }
    p.lineLo = p.isExtracted ? 0 : 1;
    p.lineHi = p.isExtracted ? 0 : p.lineHi;
    p.text = std::move( body );
    return p;
}

// one file's sections in rank order while they fit `allowance`; the top one is cut to fit when even it does not
inline void sectionPassages( const IngestResult& ing, std::uint32_t fileId, RecallSectionBody& sec, std::size_t allowance, ForDocBody& out )
{
    const RecallUnitAdmission admitted = admitRecallUnits( sec, allowance );
    const std::uint32_t of = std::uint32_t( sec.units.size() );
    if( admitted.admittedCount == 0 )
    {
        const RecallSectionUnit& top = sec.units[sec.rankOrder[0]];
        std::string text( sec.body, top.bodyOffset, top.bodyLength );
        const std::size_t keep = allowance > kRecallTruncNoteBytes ? allowance - kRecallTruncNoteBytes : kRecallMinBodyBytes;
        const std::size_t kept = truncateRecallBody( text, keep ).sourceKeptBytes;
        const std::string_view served( text.data(), std::min( kept, text.size() ) );
        const std::uint32_t hi = top.lineLo + std::uint32_t( std::count( served.begin(), served.end() - ( served.empty() ? 0 : 1 ), '\n' ) );
        out.passages.push_back( ForDocPassage { fileId, top.lineLo, std::min( hi, top.lineHi ), ing.symbols[top.symIndex].name, std::move( text ), 1, of,
                                                /*isSection=*/true, /*isExtracted=*/false, /*isCut=*/true } );
        out.dropped += sec.units.size() - 1;
        out.isCapped = true;
        return;
    }
    std::uint32_t rank = 0;
    for( const std::uint32_t u : sec.rankOrder )
    {
        ++rank;
        if( !admitted.isAdmitted[u] )
        {
            continue;
        }
        const RecallSectionUnit& unit = sec.units[u];
        out.passages.push_back( ForDocPassage { fileId, unit.lineLo, unit.lineHi, ing.symbols[unit.symIndex].name,
                                                sec.body.substr( unit.bodyOffset, unit.bodyLength ), rank, of, /*isSection=*/true } );
    }
    out.dropped += sec.units.size() - admitted.admittedCount;
    out.isCapped = out.isCapped || admitted.admittedCount < sec.units.size();
}
} // namespace fordocbody_detail

// The passages of a fired pick: --recall's section choice per file, the allowance shared by recall's water-filling.
inline ForDocBody buildForDocBody( const IngestResult& ing, const std::vector<std::uint32_t>& outOff, const std::vector<NodeId>& outTargets,
                                   std::string_view task, const ForDocBodyPick& pick, RedactCounts* redact, std::string_view rootArg )
{
    ForDocBody out;
    if( !pick.fires || pick.fileIds.empty() )
    {
        return out;
    }
    const std::vector<float> scores = recallLensScores( ing, outOff, outTargets, task, rootArg );
    std::vector<std::string> queryToks;
    subtokens( task, queryToks );

    struct Loaded
    {
        std::uint32_t fileId = 0;
        std::optional<RecallSectionBody> sections;
        std::string whole;
    };
    std::vector<Loaded> loaded;
    std::vector<std::size_t> overhead, demand;
    for( const std::uint32_t f : pick.fileIds )
    {
        Loaded l { f, buildSectionGranularBody( ing, scores, f, redact, queryToks ), {} };
        std::size_t need = 0;
        if( l.sections )
        {
            for( const RecallSectionUnit& u : l.sections->units )
            {
                need += recallUnitCostBytes( u );
            }
        }
        else if( std::optional<std::string> body = loadRecallBody( ing, f, redact ) )
        {
            l.whole = std::move( *body );
            need = l.whole.size();
        }
        else
        {
            out.unread.push_back( f ); // unreadable on disk: named, never a stub
            continue;
        }
        overhead.push_back( 0 ); // the markup is the block's own, outside the text allowance
        demand.push_back( need );
        loaded.push_back( std::move( l ) );
    }
    const RecallShares shares = allocateRecallShares( overhead, demand, kForDocBodyBytes );
    for( std::size_t i = 0; i < loaded.size(); ++i )
    {
        Loaded& l = loaded[i];
        if( i >= shares.servedCount )
        {
            out.unread.push_back( l.fileId ); // the allowance served the files before it
            out.isCapped = true;
            continue;
        }
        if( l.sections )
        {
            fordocbody_detail::sectionPassages( ing, l.fileId, *l.sections, shares.alloc[i], out );
        }
        else
        {
            out.passages.push_back( fordocbody_detail::wholeDocPassage( ing, l.fileId, std::move( l.whole ), shares.alloc[i] ) );
            out.isCapped = out.isCapped || out.passages.back().isCut;
        }
    }
    for( const ForDocPassage& p : out.passages )
    {
        out.textBytes += p.text.size();
    }
    return out;
}

// ── spellings ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
// No double dash inside the comments: XML forbids it there.
inline constexpr std::string_view kForDocBodyLegend =
    "<!-- ripwire for doc_body: the task reads as prose and 2 or more of the first 10 t files in rank order are doc files, so the "
    "sections of the first 3 doc files this answer shows (its sig rows, then its t files in rank order) follow. Each b t=\"section\" is a section of p= that ranks "
    "highest for the task's words in that file (the recall verb's pick): n= its heading, l= e= its source lines, rank= its place "
    "among the of= sections picked in that file (1 = top). It is a lexical match, not a verified answer: a section that shares the "
    "task's words and answers another question can rank first. b t=\"doc\": the head of a doc with no matching heading section; "
    "src=\"extracted\": text extracted from HTML or a notebook, which has no source lines; cut=\"1\": cut to fit. allowance= the "
    "section text the files share, bytes= the text printed; dropped= picked sections the allowance left out, and next= is the recall "
    "call that serves more doc text; f p= a doc file that served none (why=). The answer above is unchanged, and these bytes are "
    "not in est_tokens -->";

inline std::string forDocBodyNext( std::string_view task ) { return nextAttrXml( nextFlag( "--recall=", task ) ); }

// A token budget is a request the block must obey: the sections are not printed, the files are named, next= is the call without it.
inline std::string forDocBodyHeldXml( const IngestResult& ing, const ForDocBodyPick& pick, std::string_view task, std::string_view rootArg )
{
    std::vector<char> esc;
    const std::string prefix = sarif::rootPrefixOf( rootArg );
    std::string out =
        "<!-- ripwire for doc_body held=\"budget\": a token budget is set, so the doc sections are not printed (they sit outside "
        "est_tokens); f p= the doc files they come from; next= repeats this call without the budget. The answer above is unchanged -->"
        "<doc_body held=\"budget\" files=\"" +
        std::to_string( pick.fileIds.size() ) + "\"" + nextAttrXml( nextFlag( "--for=", task ) ) + ">";
    for( const std::uint32_t f : pick.fileIds )
    {
        const std::string_view p = rootArg.empty() ? std::string_view( ing.files[f] ) : sarif::rootRelativeUri( ing.files[f], prefix );
        out += "<f p=\"" + std::string( escapeXml( p, esc ) ) + "\"/>";
    }
    return out + "</doc_body>";
}

inline std::string forDocBodyXml( const IngestResult& ing, const ForDocBody& body, const ForDocBodyPick& pick, std::string_view task, std::string_view rootArg )
{
    std::vector<char> esc;
    const std::string prefix = sarif::rootPrefixOf( rootArg );
    const auto display = [&]( std::uint32_t f ) -> std::string
    {
        const std::string_view p = rootArg.empty() ? std::string_view( ing.files[f] ) : sarif::rootRelativeUri( ing.files[f], prefix );
        return std::string( escapeXml( p, esc ) );
    };
    std::string out( kForDocBodyLegend );
    out += "<doc_body files=\"" + std::to_string( pick.fileIds.size() ) + "\" allowance=\"" + std::to_string( kForDocBodyBytes ) + "\" bytes=\"" + std::to_string( body.textBytes ) + "\"";
    if( body.dropped > 0 )
    {
        out += " dropped=\"" + std::to_string( body.dropped ) + "\"";
    }
    if( body.isCapped )
    {
        out += " capped=\"1\"" + forDocBodyNext( task );
    }
    out += ">";
    for( const ForDocPassage& p : body.passages )
    {
        out += p.isSection ? "<b t=\"section\" p=\"" : "<b t=\"doc\" p=\"";
        out += display( p.fileId ) + "\"";
        if( p.lineLo > 0 )
        {
            out += " l=\"" + std::to_string( p.lineLo ) + "\" e=\"" + std::to_string( p.lineHi ) + "\"";
        }
        if( p.isSection )
        {
            out += " n=\"" + std::string( escapeXml( p.heading, esc ) ) + "\" rank=\"" + std::to_string( p.rank ) + "\" of=\"" + std::to_string( p.of ) + "\"";
        }
        out += p.isExtracted ? " src=\"extracted\"" : "";
        out += p.isCut ? " cut=\"1\"" : "";
        out += "><![CDATA[";
        appendCdataSafe( p.text, out );
        out += "]]></b>";
    }
    for( const std::uint32_t f : body.unread )
    {
        const bool served = std::ranges::any_of( body.passages, [&]( const ForDocPassage& p )
                                                 { return p.fileId == f; } );
        out += served ? "" : "<f p=\"" + display( f ) + "\" why=\"" + ( body.isCapped ? "allowance" : "unread" ) + "\"/>";
    }
    return out + "</doc_body>";
}

// The --json twin: one key, appended after "sigs" (outside est_tokens, as the XML block).
inline std::string forDocBodyJson( const IngestResult& ing, const ForDocBody& body, const ForDocBodyPick& pick, std::string_view task,
                                   std::string_view rootArg, bool held )
{
    const std::string prefix = sarif::rootPrefixOf( rootArg );
    const auto display = [&]( std::uint32_t f ) -> std::string_view
    { return rootArg.empty() ? std::string_view( ing.files[f] ) : sarif::rootRelativeUri( ing.files[f], prefix ); };
    std::string out = ",\"doc_body\":{\"in_est_tokens\":false,\"files\":[";
    for( std::size_t i = 0; i < pick.fileIds.size(); ++i )
    {
        out += ( i ? ",\"" : "\"" ) + jsonStr( display( pick.fileIds[i] ) ) + "\"";
    }
    out += "]";
    if( held )
    {
        return out + ",\"held\":\"budget\",\"next\":\"" + jsonStr( nextFlag( "--for=", task ) ) + "\"}";
    }
    out += ",\"pick\":\"the recall verb's top-ranked sections of these files for the task's words: a lexical match, not a verified answer\"";
    out += ",\"allowance\":" + std::to_string( kForDocBodyBytes ) + ",\"bytes\":" + std::to_string( body.textBytes );
    if( body.isCapped )
    {
        out += ",\"capped\":true,\"dropped\":" + std::to_string( body.dropped ) + ",\"next\":\"" + jsonStr( nextFlag( "--recall=", task ) ) + "\"";
    }
    out += ",\"passages\":[";
    for( std::size_t i = 0; i < body.passages.size(); ++i )
    {
        const ForDocPassage& p = body.passages[i];
        out += std::string( i ? ",{" : "{" ) + "\"t\":\"" + ( p.isSection ? "section" : "doc" ) + "\",\"p\":\"" + jsonStr( display( p.fileId ) ) + "\"";
        if( p.lineLo > 0 )
        {
            out += ",\"l\":" + std::to_string( p.lineLo ) + ",\"e\":" + std::to_string( p.lineHi );
        }
        if( p.isSection )
        {
            out += ",\"n\":\"" + jsonStr( p.heading ) + "\",\"rank\":" + std::to_string( p.rank ) + ",\"of\":" + std::to_string( p.of );
        }
        out += p.isExtracted ? ",\"src\":\"extracted\"" : "";
        out += p.isCut ? ",\"cut\":true" : "";
        out += ",\"text\":\"" + jsonStr( p.text ) + "\"}";
    }
    out += "]";
    if( !body.unread.empty() )
    {
        out += ",\"unserved\":[";
        for( std::size_t i = 0; i < body.unread.size(); ++i )
        {
            out += ( i ? ",\"" : "\"" ) + jsonStr( display( body.unread[i] ) ) + "\"";
        }
        out += "]";
    }
    return out + "}";
}

// The XML block of a fired pick ("" otherwise): held under a token budget, else the passages.
inline std::string renderForDocBodyXml( const IngestResult& ing, const std::vector<std::uint32_t>& outOff, const std::vector<NodeId>& outTargets,
                                        std::string_view task, const ForDocBodyPick& pick, RedactCounts* redact, std::string_view rootArg, bool held )
{
    if( !pick.fires || pick.fileIds.empty() )
    {
        return {};
    }
    if( held )
    {
        return forDocBodyHeldXml( ing, pick, task, rootArg );
    }
    return forDocBodyXml( ing, buildForDocBody( ing, outOff, outTargets, task, pick, redact, rootArg ), pick, task, rootArg );
}
} // namespace rw
