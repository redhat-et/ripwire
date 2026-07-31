#pragma once

// docparse.h — P1-B document ingest (PLAN_absorb2026 §P1-B). Turns non-code documents that live IN a repo
// (Jupyter notebooks, HTML, CSV — and, via a bridge, PDF/DOCX/PPTX/XLSX) into plain text so `--recall` /
// `--for` can see them. The architecture PDF and design notebook beside the code are context an agent wants;
// `--recall` previously saw only markdown + code. Zero new dependency: the .ipynb/.html/.csv parsers are
// hand-rolled (the project's moat is a single self-contained binary — no simdjson, no libxml). Binary
// formats degrade to a `markitdown` shell-out IF it is on PATH, else "" (graceful).
//
// Integration (see ingest.cpp): a doc file is collected like markdown, contributes ONE whole-file Section
// node, and its EXTRACTED text is recorded in IngestResult::docText[fileId]. lexical.h / recall.h read that
// override instead of the raw bytes, so a notebook is indexed + recalled by its prose, not its JSON.
// Determinism: every parser is a pure function of the file bytes; the post-pass runs each cold OR warm.
//
// Style: Allman braces; spaces inside parens; VERIFY/DEGRADED_PATH_ALERT; ~160–200 col wrap.

#include "Diagnostics.h"
#include "jsonesc.h"   // A4-F27 residual: ctx::shSingleQuote — canonical shell single-quote, forwarded
                        // to below instead of carrying a local copy; STL-only, no coupling cost here.

#include <array>
#include <cctype>
#include <cstdio>
#include <string>
#include <string_view>

namespace ctx
{
namespace docparse
{

// ── doc-extension classification ───────────────────────────────────────────────────────────────────

enum class DocKind : std::uint8_t { None, Ipynb, Html, Csv, Markitdown };

// Lowercase extension (incl. leading dot) → which extractor handles it. Single source of truth for "is
// this a doc file" — collectSources() and the ingest post-pass both consult isDocExtension().
inline DocKind docKindOf( std::string_view extLower ) noexcept
{
    if( extLower == ".ipynb" )                                                   return DocKind::Ipynb;
    if( extLower == ".html" || extLower == ".htm" )                             return DocKind::Html;
    if( extLower == ".csv" )                                                     return DocKind::Csv;
    // binary formats — handled by the markitdown bridge (NOTE: not collected in v1; the crawl's binary
    // sniff excludes them. The bridge is reachable once binary-doc collection lands — see §P1-B.)
    if( extLower == ".pdf" || extLower == ".docx" || extLower == ".pptx" || extLower == ".xlsx" )
        return DocKind::Markitdown;
    return DocKind::None;
}

// A path's extension, lower-cased, INCLUDING the dot (".md"); empty when the path has none. Every
// classifier in this header takes an already-lowered extension, so this is the step that produces one —
// and it lives here rather than in each caller because it had already been copied twice (docdrift.h's
// own copy and gitoracle.h's markdown test) before this header was made its home.
inline std::string lowerExtOf( std::string_view path )
{
    const std::size_t dot = path.find_last_of( '.' );
    if( dot == std::string_view::npos ) return {};
    std::string ext;
    ext.reserve( path.size() - dot );
    for( std::size_t i = dot; i < path.size(); ++i ) ext.push_back( char( std::tolower( (unsigned char)path[i] ) ) );
    return ext;
}

inline bool isDocExtension( std::string_view extLower ) noexcept
{
    return docKindOf( extLower ) != DocKind::None;
}

// ── .ipynb (Jupyter) — pull every "source" cell's text out of the JSON ──────────────────────────────

namespace detail
{

inline bool readWholeFile( const std::string& path, std::string& out )
{
    std::FILE* fp = std::fopen( path.c_str(), "rb" );
    if( fp == nullptr )
        return false;

    if( std::fseek( fp, 0, SEEK_END ) != 0 )
    {
        std::fclose( fp );
        return false;
    }
    const long len = std::ftell( fp );
    if( len < 0 )
    {
        std::fclose( fp );
        return false;
    }
    if( std::fseek( fp, 0, SEEK_SET ) != 0 )
    {
        std::fclose( fp );
        return false;
    }

    out.resize( std::size_t( len ) );
    const std::size_t want = out.size();
    const std::size_t got  = want == 0 ? 0 : std::fread( out.data(), 1, want, fp );
    const bool ok = ( got == want ) && ( std::fclose( fp ) == 0 );
    if( !ok ) out.clear();
    return ok;
}

// Decode the JSON string starting at s[i]=='"' into `out`, advancing i past the closing quote. Handles the
// common escapes; \uXXXX collapses to a space (we only need ASCII tokens for BM25, not faithful glyphs).
inline void appendJsonString( std::string_view s, std::size_t& i, std::string& out )
{
    ++i;   // past the opening quote
    while( i < s.size() && s[i] != '"' )
    {
        const char c = s[i];
        if( c == '\\' && i + 1 < s.size() )
        {
            const char n = s[ i + 1 ];
            switch( n )
            {
                case 'n': case 'r': case 't': out.push_back( '\n' ); break;   // whitespace escapes → newline (token sep)
                case '"':                     out.push_back( '"' );  break;
                case '\\':                    out.push_back( '\\' ); break;
                case '/':                     out.push_back( '/' );  break;
                case 'u':                     out.push_back( ' ' ); i += 4; break;   // skip the 4 hex; +2 below
                default:                      out.push_back( n );   break;
            }
            i += 2;
        }
        else
        {
            out.push_back( c );
            ++i;
        }
    }
    if( i < s.size() ) ++i;   // past the closing quote
}

}   // namespace detail

// Concatenate the text of every cell's "source" (a JSON string or array-of-strings). Tolerant scanner — not
// a full JSON parser; it finds each "source" key and decodes the value that follows. Good enough for
// retrieval (we want the prose + code tokens, not byte-exact JSON).
inline std::string extractIpynb( std::string_view json )
{
    std::string                  out;
    std::size_t                  i   = 0;
    constexpr std::string_view   key = "\"source\"";
    const auto skipWs = [ & ]() { while( i < json.size() && ( json[i] == ' ' || json[i] == '\t' || json[i] == '\n' || json[i] == '\r' ) ) ++i; };

    while( ( i = json.find( key, i ) ) != std::string_view::npos )
    {
        i += key.size();
        skipWs();
        if( i >= json.size() || json[i] != ':' ) continue;          // not a "source": key
        ++i;
        skipWs();
        if( i >= json.size() ) break;

        if( json[i] == '"' )                                         // "source": "one string"
        {
            detail::appendJsonString( json, i, out );
            out.push_back( '\n' );
        }
        else if( json[i] == '[' )                                    // "source": ["line\n", "line\n", ...]
        {
            ++i;
            while( i < json.size() && json[i] != ']' )
            {
                if( json[i] == '"' ) detail::appendJsonString( json, i, out );
                else                 ++i;
            }
            if( i < json.size() ) ++i;                               // past ']'
            out.push_back( '\n' );
        }
    }
    return out;
}

// ── .html — strip script/style + tags, decode a few entities ────────────────────────────────────────

namespace detail
{

// Case-insensitive: does s, at offset p, begin with the lowercase `lit` (e.g. "<script")?
inline bool ciStartsWith( std::string_view s, std::size_t p, std::string_view lit ) noexcept
{
    if( p + lit.size() > s.size() ) return false;
    for( std::size_t k = 0; k < lit.size(); ++k )
        if( char( std::tolower( static_cast<unsigned char>( s[ p + k ] ) ) ) != lit[k] ) return false;
    return true;
}

}   // namespace detail

inline std::string extractHtml( std::string_view html )
{
    std::string out;
    out.reserve( html.size() );

    for( std::size_t i = 0; i < html.size(); )
    {
        if( html[i] == '<' )
        {
            // drop <script>…</script> and <style>…</style> wholesale (content is not prose)
            if( detail::ciStartsWith( html, i, "<script" ) || detail::ciStartsWith( html, i, "<style" ) )
            {
                const std::string_view close = detail::ciStartsWith( html, i, "<script" ) ? "</script" : "</style";
                std::size_t            e     = i + 1;
                while( e < html.size() && !detail::ciStartsWith( html, e, close ) ) ++e;
                while( e < html.size() && html[e] != '>' ) ++e;     // to end of the closing tag
                i = ( e < html.size() ) ? e + 1 : html.size();
                out.push_back( ' ' );
                continue;
            }
            // ordinary tag — skip to '>'
            while( i < html.size() && html[i] != '>' ) ++i;
            if( i < html.size() ) ++i;
            out.push_back( ' ' );
            continue;
        }

        // text node — decode the handful of entities that matter for tokens
        if( html[i] == '&' )
        {
            const std::size_t semi = html.find( ';', i );
            if( semi != std::string_view::npos && semi - i <= 8 )
            {
                const std::string_view ent = html.substr( i, semi - i + 1 );
                if( ent == "&amp;" )        out.push_back( '&' );
                else if( ent == "&lt;" )    out.push_back( '<' );
                else if( ent == "&gt;" )    out.push_back( '>' );
                else if( ent == "&quot;" )  out.push_back( '"' );
                else if( ent == "&#39;" || ent == "&apos;" ) out.push_back( '\'' );
                else                        out.push_back( ' ' );   // &nbsp; and friends → space
                i = semi + 1;
                continue;
            }
        }

        out.push_back( html[i] );
        ++i;
    }

    // collapse whitespace runs (tag-stripping leaves long blank gaps): a run containing a newline → one '\n'
    // (keep block structure), a run of spaces/tabs → one ' '. Trim ends. Purely cosmetic for the recall body;
    // BM25 tokenization is whitespace-insensitive anyway.
    std::string collapsed;
    collapsed.reserve( out.size() );
    for( std::size_t k = 0; k < out.size(); )
    {
        if( std::isspace( static_cast<unsigned char>( out[k] ) ) )
        {
            bool hasNewline = false;
            while( k < out.size() && std::isspace( static_cast<unsigned char>( out[k] ) ) )
            {
                if( out[k] == '\n' ) hasNewline = true;
                ++k;
            }
            if( !collapsed.empty() ) collapsed.push_back( hasNewline ? '\n' : ' ' );
        }
        else
        {
            collapsed.push_back( out[k] );
            ++k;
        }
    }
    while( !collapsed.empty() && std::isspace( static_cast<unsigned char>( collapsed.back() ) ) )
        collapsed.pop_back();
    return collapsed;
}

// ── .csv — header names + a few sample rows (the column names are the searchable tokens) ─────────────

inline std::string extractCsv( std::string_view csv )
{
    // first line = header; the rest are data rows. We summarise rather than dump (a 100k-row CSV is noise).
    std::size_t nl = csv.find( '\n' );
    std::string_view header = ( nl == std::string_view::npos ) ? csv : csv.substr( 0, nl );
    if( !header.empty() && header.back() == '\r' ) header.remove_suffix( 1 );

    // count data rows
    std::size_t rows = 0;
    bool hasData = false;
    for( std::size_t p = ( nl == std::string_view::npos ? csv.size() : nl + 1 ); p < csv.size(); ++p )
    {
        const char c = csv[p];
        if( c == '\n' )
        {
            if( hasData ) ++rows;
            hasData = false;
        }
        else if( c != '\r' )
            hasData = true;
    }
    if( hasData ) ++rows;

    std::string out = "CSV columns: ";
    for( char c : header ) out.push_back( c == ',' ? ' ' : c );   // commas → spaces so column names tokenize
    out += "\nrows: ";
    out += std::to_string( rows );
    out.push_back( '\n' );

    // include up to 3 sample data rows so values are searchable too
    std::size_t emitted = 0, p = ( nl == std::string_view::npos ? csv.size() : nl + 1 );
    while( p < csv.size() && emitted < 3 )
    {
        const std::size_t e = csv.find( '\n', p );
        std::string_view line = csv.substr( p, ( e == std::string_view::npos ? csv.size() : e ) - p );
        if( !line.empty() && line.back() == '\r' ) line.remove_suffix( 1 );
        if( !line.empty() )
        {
            for( char c : line ) out.push_back( c == ',' ? ' ' : c );
            out.push_back( '\n' );
            ++emitted;
        }
        if( e == std::string_view::npos ) break;
        p = e + 1;
    }
    return out;
}

// ── markitdown bridge (binary formats) — shell out IF present, else "" ──────────────────────────────

namespace detail
{

// Single-quote a path for safe inclusion in a /bin/sh command (paths come from the crawl, not user input,
// but quote anyway — defence in depth, and paths can contain spaces).
// NOTE (F13, resolved): was byte-identical to ctx::shSingleQuote in gitmine.h — a local copy was kept
// deliberately at the time because merging would have forced docparse.h (Diagnostics.h + STL only,
// pulled by ingest.cpp) to include gitmine.h and thus the whole graph.h dependency chain. That's now
// moot: the canonical implementation moved to jsonesc.h (STL-only, zero project includes), which both
// docparse.h and gitmine.h can pull in for free. This is a thin forwarder so the local `shellQuote`
// name/call sites below don't need to change.
inline std::string shellQuote( const std::string& s )
{
    return ctx::shSingleQuote( s );
}

}   // namespace detail

// Run `markitdown <path>` and return its stdout (Markdown), or "" if markitdown is not on PATH / it failed.
// NOTE: this performs a subprocess call — used only for binary doc formats, only when they are ingested.
inline std::string runMarkitdown( const std::string& path )
{
    const std::string cmd = "markitdown " + detail::shellQuote( path ) + " 2>/dev/null";
    std::FILE* pipe = ::popen( cmd.c_str(), "r" );
    if( pipe == nullptr )
    {
        DEGRADED_PATH_ALERT( "docparse: popen failed for markitdown bridge" );
        return {};
    }
    std::string         out;
    std::array<char, 65536> buf;
    std::size_t         n = 0;
    while( ( n = std::fread( buf.data(), 1, buf.size(), pipe ) ) > 0 )
        out.append( buf.data(), n );
    const int rc = ::pclose( pipe );
    if( rc != 0 )                                   // markitdown absent or errored → degrade to no-doc
        return {};
    return out;
}

// ── top-level entry: path → extracted text (or "" = not a doc / extraction empty) ───────────────────

inline std::string parseDocFile( const std::string& path, std::string_view extLower )
{
    switch( docKindOf( extLower ) )
    {
        case DocKind::Markitdown:
            return runMarkitdown( path );

        case DocKind::Ipynb:
        case DocKind::Html:
        case DocKind::Csv:
        {
            std::string bytes;
            if( !detail::readWholeFile( path, bytes ) )
            {
                DEGRADED_PATH_ALERT( "docparse: cannot read document file" );
                return {};
            }
            switch( docKindOf( extLower ) )
            {
                case DocKind::Ipynb: return extractIpynb( bytes );
                case DocKind::Html:  return extractHtml( bytes );
                case DocKind::Csv:   return extractCsv( bytes );
                default:             return {};
            }
        }

        default:
            return {};
    }
}

// ── generated-document signals (PLAN_outputAudit_2026-07-28 §P2b) ───────────────────────────────────
//
// A GENERATED document — a command capture, an API dump, a doxygen/openapi export — QUOTES the whole
// system it documents, so BM25 hands it every query's terms and it out-scores the design document that
// EXPLAINS them. Measured on this repo before the captures were relocated: a 246 KB capture scored
// 11.548 against SPEC.md's 2.355 for "quality delta gating exit codes" (4.9x) — on a question the capture
// does not answer. Any repo with large generated documentation hits this; the tool had no notion that a
// generated artifact is not a design document. These functions are that notion, and they read the file's
// own BYTES — never its name (a name blacklist is a guess dressed as evidence).
//
// Two independent arms, deliberately conservative, each DISCLOSED by --recall on the doc it demotes:
//
//   • Marker       — the document SAYS it is generated, within its first kGeneratedMarkerHeadLines lines.
//                    PHRASE-level, never the bare word "generated": measured here, "Generated: 2026-06-29"
//                    is a human's date stamp (reviews/MEASUREMENTS.md) and "regenerated capture" is prose
//                    (the capture's own subtitle) — a substring test flags both, the phrase list neither.
//   • Size+fences  — the document is BOTH extreme for THIS corpus (>= kGeneratedSizeRatio x the median
//                    doc's bytes, and at least kGeneratedMinBytes absolute) AND mostly QUOTED OUTPUT
//                    (>= kGeneratedFencedFraction of its lines inside ``` fences). Neither half alone
//                    demotes: a design doc is allowed to be long, a tutorial is allowed to be fence-dense.
//
// Calibration (148 markdown docs of this repo, median 9,340 B — the numbers the thresholds were picked
// from, so a future round can re-measure rather than re-guess):
//
//     doc                                    xmedian   fenced-lines
//     docs/captures/…_2026-07-28.md            26.3        0.41      <- generated (raw + fenced output)
//     docs/captures/…_2026-07-27.md            18.2        0.78      <- generated
//     PLAN_planLanes_2026-07-27.md              6.5        0.23      hand-written, densest big doc
//     README.md                                 6.5        0.13      hand-written
//     PLAN_systemAudit2026.md                   6.1        0.02      hand-written
//     reviews/PERF.md                           2.2        0.26      hand-written, densest at >=2x median
//
// So 5x/0.35 separates the two populations with margin on both sides (0.26 -> 0.35 -> 0.41), and seven
// hand-written docs sit above the size line untouched because none is fence-dense. HONEST LIMIT: a
// capture that dumps raw XML/JSON with no fences at all scores low here and is NOT demoted unless it
// carries a marker — this under-claims by design; a wrongly demoted design doc is the worse error.
inline constexpr std::size_t kGeneratedMarkerHeadLines = 10;      // a marker introduces a file; it is not buried
inline constexpr double      kGeneratedSizeRatio       = 5.0;     // x the corpus median doc bytes
inline constexpr double      kGeneratedFencedFraction  = 0.35;    // of the document's lines inside ``` fences
inline constexpr std::size_t kGeneratedMinBytes        = 4096;    // absolute floor — 5x a tiny median is not "huge"
inline constexpr std::size_t kGeneratedMinDocCount     = 3;       // below this a median has no middle to speak of

enum class GeneratedDocReason : std::uint8_t { None = 0, Marker = 1, SizeAndFences = 2 };

// The reason's stable machine tag — what --recall prints beside the demoted doc. A table indexed by the
// enum, not a switch (house style, and it cannot drift out of order: the static_assert below pins it).
// "" for None, so a caller can print the tag unconditionally.
inline constexpr const char* kGeneratedReasonTag[] = { "", "marker", "size+fences" };
static_assert( sizeof( kGeneratedReasonTag ) / sizeof( kGeneratedReasonTag[0] ) == 3,
               "kGeneratedReasonTag must carry one tag per GeneratedDocReason value" );

inline const char* generatedReasonTag( GeneratedDocReason reason ) noexcept
{
    const std::size_t index = std::size_t( reason );
    return ( index < sizeof( kGeneratedReasonTag ) / sizeof( kGeneratedReasonTag[0] ) ) ? kGeneratedReasonTag[ index ] : "";
}

// One pass over a markdown body's LINES with the fence state machine: how many lines there are, how many
// of them are inside (or are) a ``` fence, and whether the text ends with a fence still open. The single
// fence scanner in the tool — recall.h's truncation repair reads `endsInsideFence`, the generated-doc
// signal reads `fencedLineCount` — so the two can never disagree about what "inside a fence" means.
//
// Fence rule, reduced to what markdown prose needs: a line whose first non-space characters are three-or-
// more backticks TOGGLES the state, and counts as fenced itself. No tilde fences, no info-string
// validation, no indented-code-block exemption. Pure text in, pure counts out — no map order, no clock.
struct MarkdownFenceScan
{
    std::size_t lineCount       = 0;
    std::size_t fencedLineCount = 0;
    bool        endsInsideFence = false;
};

inline MarkdownFenceScan scanMarkdownFences( std::string_view text ) noexcept
{
    MarkdownFenceScan scan;
    bool              isInsideFence = false;
    for( std::size_t lineStart = 0; lineStart < text.size(); )
    {
        std::size_t lineEnd = text.find( '\n', lineStart );
        if( lineEnd == std::string_view::npos ) lineEnd = text.size();

        std::size_t cursor = lineStart;
        while( cursor < lineEnd && ( text[ cursor ] == ' ' || text[ cursor ] == '\t' ) ) ++cursor;
        std::size_t tickCount = 0;
        while( cursor + tickCount < lineEnd && text[ cursor + tickCount ] == '`' ) ++tickCount;

        ++scan.lineCount;
        if( tickCount >= 3 )        { isInsideFence = !isInsideFence; ++scan.fencedLineCount; }
        else if( isInsideFence )    { ++scan.fencedLineCount; }

        lineStart = lineEnd + 1;   // past text.size() when lineEnd was the tail — the loop condition ends it
    }
    scan.endsInsideFence = isInsideFence;
    return scan;
}

// fencedLineCount / lineCount, 0 for an empty text — the "how much of this document is quoted output"
// number the size+fences arm thresholds against.
inline double fencedLineFraction( const MarkdownFenceScan& scan ) noexcept
{
    return scan.lineCount ? double( scan.fencedLineCount ) / double( scan.lineCount ) : 0.0;
}

namespace detail
{

// Case-insensitive substring search over an ASCII haystack for an already-lower-cased needle.
inline bool ciContains( std::string_view haystack, std::string_view needle ) noexcept
{
    if( needle.empty() || needle.size() > haystack.size() ) return false;
    for( std::size_t at = 0; at + needle.size() <= haystack.size(); ++at )
        if( ciStartsWith( haystack, at, needle ) ) return true;
    return false;
}

}   // namespace detail

// Does this document DECLARE itself generated in its opening lines? The phrases are the conventions real
// generators emit (`@generated`, "Code generated by protoc", "DO NOT EDIT", doxygen/swagger banners); each
// is a whole phrase precisely so a hand-written doc that merely uses the word "generated" is not caught.
inline bool hasGeneratedMarker( std::string_view text ) noexcept
{
    static constexpr std::string_view kMarkerPhrases[] = {
        "@generated", "auto-generated", "autogenerated", "auto generated",
        "automatically generated", "generated by", "generated file", "generated automatically",
        "do not edit", "don't edit", "do not modify" };

    // the head: the first kGeneratedMarkerHeadLines lines, whatever they cost in bytes
    std::size_t headEnd = 0;
    for( std::size_t lineIndex = 0; lineIndex < kGeneratedMarkerHeadLines && headEnd < text.size(); ++lineIndex )
    {
        const std::size_t nextNewline = text.find( '\n', headEnd );
        if( nextNewline == std::string_view::npos ) { headEnd = text.size(); break; }
        headEnd = nextNewline + 1;
    }

    const std::string_view head = text.substr( 0, headEnd );
    for( std::string_view phrase : kMarkerPhrases )
        if( detail::ciContains( head, phrase ) ) return true;
    return false;
}

// The verdict for ONE document, from evidence only. `medianDocBytes` and `docCount` are the corpus this
// document is extreme (or ordinary) relative to; a corpus too small for a median disables the size arm
// entirely — the marker arm, which needs no corpus, still applies.
inline GeneratedDocReason classifyGeneratedDoc( std::string_view text, std::size_t bytes,
                                                std::size_t medianDocBytes, std::size_t docCount ) noexcept
{
    if( hasGeneratedMarker( text ) ) return GeneratedDocReason::Marker;

    const bool isCorpusMeasurable = docCount >= kGeneratedMinDocCount && medianDocBytes > 0;
    if( !isCorpusMeasurable )                                          return GeneratedDocReason::None;
    if( bytes < kGeneratedMinBytes )                                   return GeneratedDocReason::None;
    if( double( bytes ) < kGeneratedSizeRatio * double( medianDocBytes ) ) return GeneratedDocReason::None;
    if( fencedLineFraction( scanMarkdownFences( text ) ) < kGeneratedFencedFraction ) return GeneratedDocReason::None;
    return GeneratedDocReason::SizeAndFences;
}

}   // namespace docparse
}   // namespace ctx
