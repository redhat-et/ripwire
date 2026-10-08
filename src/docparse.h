#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings
#include "infra/os.h"   // rw::os::popen / pclose — the markitdown bridge; open / fdopen / close / fstat — readRegularFile asks a FIFO for an answer instead of waiting on it, and asks the DESCRIPTOR what it opened


// docparse.h — P1-B document ingest. Turns non-code documents that live IN a repo
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
// Style: Allman braces; spaces inside parens; ASSUME/DISCLOSE; ~160–200 col wrap.

#include "infra/Diagnostics.h"
#include "infra/jsonesc.h"   // A4-F27 residual: rw::shSingleQuote — canonical shell single-quote, forwarded
                        // to below instead of carrying a local copy; STL-only, no coupling cost here.

#include "infra/sortutil.h"  // svLess — the memcmp-then-length string_view order the sorted tables below use
#include "infra/ownedfile.h" // rw::OwnedFile — the whole-file readers own their stream, so every return closes it
#include "pathguard.h"        // rw::pathguard::NoFollowRead — the owned line stream a fixed-name file is read through

#include <algorithm>   // std::binary_search — the membership test, instead of a hand-rolled scan loop
#include <iterator>
#include <array>
#include <cctype>
#include <cstdio>
#include <mutex>       // openRegularFileStream discloses a refused path once per process
#include <optional>
#include <string>
#include <string_view>
#include <vector>      // openRegularFileStream: the paths already disclosed

namespace rw
{
namespace docparse
{

// ── doc-extension classification ───────────────────────────────────────────────────────────────────

enum class DocKind : std::uint8_t { None, Ipynb, Html, Csv, Markitdown };

// Lowercase extension (incl. leading dot) → which extractor handles it. Single source of truth for "is
// this a doc file" — collectSources() and the ingest post-pass both consult isDocExtension().
inline DocKind docKindOf( std::string_view extLower ) noexcept
{
    if( extLower == ".ipynb" )
    {
        return DocKind::Ipynb;
    }
    if( extLower == ".html" || extLower == ".htm" )
    {
        return DocKind::Html;
    }
    if( extLower == ".csv" )
    {
        return DocKind::Csv;
    }
    // Binary formats — the markitdown bridge. MEASURED 2026-09-09, correcting the note that stood here: a
    // .pdf IS collected (recordPreSizeDrop admits any isDocExtension, and the NUL sniff only ever runs on a
    // file the PARSE POOL reads, which a doc file never enters), so the bridge runs on every invocation.
    // What it produces without markitdown on PATH is "" — and an empty extraction contributes no Section
    // node, so the file is counted in files= and is a SILENT ZERO in every doc lens. Closing that is the
    // extractor-provenance design in LANE_C_REPORT.md §2 (prov="markitdown:<ver>" + a named unindexed
    // reason), and it is deliberately not turned on here: the owner's 2026-09-08 scope ruling is
    // text/markdown, not bloated document formats.
    if( extLower == ".pdf" || extLower == ".docx" || extLower == ".pptx" || extLower == ".xlsx" )
    {
        return DocKind::Markitdown;
    }
    return DocKind::None;
}

// A path's extension, lower-cased, INCLUDING the dot (".md"); empty when the path has none. Every
// classifier in this header takes an already-lowered extension, so this is the step that produces one —
// and it lives here rather than in each caller because it had already been copied twice (docdrift.h's
// own copy and gitoracle.h's markdown test) before this header was made its home.
inline std::string lowerExtOf( std::string_view path )
{
    const std::size_t dot = path.find_last_of( '.' );
    if( dot == std::string_view::npos )
    {
        return {};
    }
    std::string ext;
    ext.reserve( path.size() - dot );
    for( std::size_t i = dot; i < path.size(); ++i )
    {
        ext.push_back( char( std::tolower( (unsigned char)path[i] ) ) );
    }
    return ext;
}

inline bool isDocExtension( std::string_view extLower ) noexcept
{
    return docKindOf( extLower ) != DocKind::None;
}

// ── the prose vocabulary — ONE place, two questions ─────────────────────────────────────────────────
//
// Every extension test in this tree asks one of exactly two things, and conflating them is what let the
// defect below ship. THE INDEX'S question is "does this build carry the file as a DOCUMENT?"
// (isIndexedDocExtension). THE READER'S question is "is this file prose?" (isProseExtension) — an
// ordering key, a comment-syntax verdict, how much a name deleted here proves. The second is a strict
// SUPERSET of the first, and both live here so a format added to one is visible to the other.
//
// THREE TIERS, separated by WHICH MACHINERY reads the file — not by how a reader thinks about it:
//
//   • MARKDOWN-GRAMMAR tier (kMarkdownGrammarExts). ingest_crawl.h's kLangTable maps these to
//     Lang::Markdown and the vendored markdown BLOCK grammar, so they reach the section tier, --recall's
//     section-granular serving and doc→code mentions with no extractor and no extracted-text copy at
//     all. Deliberately NOT a DocKind: docKindOf answers "which EXTRACTOR", and these need none. A
//     compile-time guard in ingest_crawl.h asserts every name here really has a grammar row.
//   • EXTRACTOR tier (docKindOf). A notebook / exported HTML / CSV is turned into plain text by a parser
//     below, or by the markitdown bridge, and contributes one whole-file section.
//   • PROSE THIS BUILD DOES NOT INDEX (kUnindexedProseExts). Prose to a reader, absent from the index —
//     so every reader-facing lens must still answer "prose", and `unindexed=` must still disclose it.
//
// WHY THE THREE LIVE IN ONE HEADER (METHODOLOGY §3, sibling completeness). Five headers spelled their own
// prose list — filter.h's PathTier, darkflags.h's lineSyntaxFor, gitoracle.h's isProsePath,
// flipimpact.h's kProseExtTable, docdrift.h's isIndexedDocPath — and no two agreed. `.rst` and `.txt`
// counted as prose for ORDERING while the crawl indexed neither; `.adoc` counted for one lens and not the
// next; `.org` for none. Measured 2026-09-09: eight files holding the same ADR text and differing only in
// extension produced `unindexed="adoc:1,log:1,mdx:1,org:1,rst:1,txt:1"`, so a repository whose decision
// history lives in `docs/adr/*.rst` got "0 relevant of 0 document files" out of --recall.
//
// WHY `.txt` IS PROSE BUT NOT INDEXED — a census, not a taste. `.txt` is the universal "arbitrary bytes"
// extension. In this repository 69 of 69 crawled `.txt` files are build manifests, gate fixtures or
// captured output (571,706 B; the largest is 69,729 B = 7.5x the corpus median document) and NONE is prose;
// across three checkouts on the development machine the commonest `.txt` basenames are requirements.txt
// (111), meson_options.txt (67) and CMakeLists.txt (50) against README.txt (71) and index.txt (32).
// Admitting it would hand BM25 half a megabyte of gate dumps that the generated-document demotion does
// NOT catch — those carry no marker and no ``` fences, the limit classifyGeneratedDoc states itself. So
// `.txt` stays a reader's prose and an unindexed extension, DISCLOSED in `unindexed=` rather than silently
// absent. `.tsv` is the same shape one tier further out: a table a reader reads, no extractor for it here.
// Gate: test/textdocscheck.sh pins both halves — the four admitted formats and the four refused ones.
// SORT ORDER IS LOAD-BEARING on both tables — they are binary-searched, and an out-of-order entry does not
// fail to compile on its own, it silently stops matching. The static_asserts are the guard, exactly as
// ingest.h's kNonTextExts carries one. Two earlier spellings were tried and rejected by measurement rather
// than taste: a hand-rolled `for( x : table ) if( x == v )` loop is the five-instance clone shape
// isNonTextExtension's note already records (ripwire's own --quality-delta called the first draft six more
// instances of it), and a std::find one-liner then cloned abicheck.h's KindCounts::total. The sorted-table
// + binary_search + is_sorted trio is the shape externalnames.h::isShellBuiltinName settled on for the
// identical collision, and it is the one this file now carries too.
inline constexpr std::string_view kMarkdownGrammarExts[] = { ".adoc", ".markdown", ".md", ".mdx", ".org", ".rst" };

static_assert( std::is_sorted( std::begin( kMarkdownGrammarExts ), std::end( kMarkdownGrammarExts ), rw::sortutil::svLess ),
               "kMarkdownGrammarExts must stay byte-sorted — isMarkdownGrammarExtension binary-searches it" );

inline constexpr std::string_view kUnindexedProseExts[] = { ".tsv", ".txt" };

static_assert( std::is_sorted( std::begin( kUnindexedProseExts ), std::end( kUnindexedProseExts ), rw::sortutil::svLess ),
               "kUnindexedProseExts must stay byte-sorted — isProseExtension binary-searches it" );

inline bool isMarkdownGrammarExtension( std::string_view extLower ) noexcept
{
    return std::binary_search( std::begin( kMarkdownGrammarExts ), std::end( kMarkdownGrammarExts ), extLower, rw::sortutil::svLess );
}

// THE INDEX'S question: this build carries the file as a document — a markdown-grammar file or an
// extracted one. Everything that must not treat an indexed document as CODE asks this.
inline bool isIndexedDocExtension( std::string_view extLower ) noexcept
{
    return isMarkdownGrammarExtension( extLower ) || isDocExtension( extLower );
}

// THE READER'S question: prose, whether or not this build indexes it. Ordering keys, comment-syntax
// verdicts and evidence weight ask this — they are about the file, not about the index.
inline bool isProseExtension( std::string_view extLower ) noexcept
{
    return isIndexedDocExtension( extLower )
        || std::binary_search( std::begin( kUnindexedProseExts ), std::end( kUnindexedProseExts ), extLower, rw::sortutil::svLess );
}

// ── .ipynb (Jupyter) — pull every "source" cell's text out of the JSON ──────────────────────────────

namespace detail
{

// The rest of an open stream from its start, or nullopt when it cannot be sized or read in full. The ONE body both
// whole-file readers below share; the stream stays owned by the caller, who closes it on every path.
inline std::optional<std::string> readAllOfStream( std::FILE* fp )
{
    if( std::fseek( fp, 0, SEEK_END ) != 0 )
    {
        return std::nullopt;
    }
    const long len = std::ftell( fp );
    if( len < 0 || std::fseek( fp, 0, SEEK_SET ) != 0 )
    {
        return std::nullopt;
    }
    std::string       out( std::size_t( len ), '\0' );
    const std::size_t want = out.size();
    const std::size_t got  = want == 0 ? 0 : std::fread( out.data(), 1, want, fp );
    if( got != want )
    {
        return std::nullopt;
    }
    return out;
}

// The whole file, or nullopt when it cannot be opened, sized or read in full. An EMPTY file is an engaged empty
// string, not a failure — a caller for which empty and unreadable mean the same thing says so with value_or.
inline std::optional<std::string> readWholeFile( const std::string& path )
{
    // Owned, so the close runs on every return: `( got == want ) && ( std::fclose( fp ) == 0 )` short-circuited
    // past it and leaked the FILE on every short read (clang-analyzer-unix.Stream).
    OwnedFile fp = openOwnedFile( path.c_str(), "rb" );
    if( !fp )
    {
        return std::nullopt;
    }
    std::optional<std::string> out      = readAllOfStream( fp.file );
    const bool                 closedOk = fp.close();
    if( !closedOk )
    {
        return std::nullopt;
    }
    return out;
}

// A fixed-name file in the tree (.ripwire_config, the quality-acks ledger) whose CONTENT is the repository's to decide
// but whose SHAPE is not, opened as a line stream only when it is a regular file. Anything else at that name — a
// FIFO, a directory, a device, or a symlink to one — is refused before a byte is read, and `what` names it on
// stderr, because each of those shapes used to hold or take down the process:
//   - a FIFO blocked the open until a writer appeared, so every --quality-delta hung before any output;
//   - a symlink to /dev/zero or /dev/urandom never reaches end of file;
//   - a directory opens on Linux, and where its seek reports LLONG_MAX (overlayfs) a whole-file read sizes a string
//     to that — the shape ingest_crawl.h's PathShape note measured for --cache=<dir>.
// The open carries O_NONBLOCK so a FIFO answers instead of waiting, and the shape is asked of the DESCRIPTOR (fstat),
// so nothing can swap the name between the question and the read. A symlink to a regular file is still followed:
// that is the ordinary way a user-authored file is shared, and refusing it is a different policy with its own owner.
//
// The stream comes back inside pathguard's NoFollowRead, the house line reader over a descriptor-checked stream: it
// owns the FILE from fdopen on, so every return closes it, and readLine streams one line at a time — a large ledger
// is never held whole. No stream (file == nullptr) means absent, unreadable or refused.
inline rw::pathguard::NoFollowRead openRegularFileStream( std::string_view what, const std::string& path )
{
    rw::pathguard::NoFollowRead stream;
    const int                   fd = os::open( path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC );
    if( fd < 0 )
    {
        return stream;   // absent or unreadable: the caller's own "no such file" reading
    }
    stream.file = os::fdopen( fd, "rb" );   // owned from here: NoFollowRead's destructor fcloses it on every return
    if( stream.file == nullptr )
    {
        os::close( fd );   // fdopen did not take the descriptor, so it is still ours to close
        return stream;
    }
    stream.opened = true;
    os::stat_t st{};
    if( os::fstat( os::fileno( stream.file ), &st ) != 0 || !S_ISREG( st.st_mode ) )
    {
        // Once per path per process: .ripwire_config is read several times in one --quality-delta, and the same sentence
        // three times says nothing the first did not.
        static std::mutex               disclosedMutex;
        static std::vector<std::string> disclosed;
        bool                            firstTime = false;
        {
            const std::lock_guard<std::mutex> lock( disclosedMutex );
            if( std::find( disclosed.begin(), disclosed.end(), path ) == disclosed.end() )
            {
                disclosed.push_back( path );
                firstTime = true;
            }
        }
        if( firstTime )
        {
            rw::emitTo( stderr, "ripwire: ignoring {} at '{}': it is not a regular file (a FIFO, a directory or a device), "
                                "so it was not read and counts as absent\n", what, path );
        }
        DISCLOSE( "docparse: a fixed-name file in the tree is not a regular file — refused before reading" );
        return rw::pathguard::NoFollowRead{};   // `stream` closes as it leaves scope; the caller gets no stream
    }
    return stream;
}

// The whole of such a file, for a caller that parses it as one text (.ripwire_config, and --quality-ack's
// byte-for-byte comparison of a ledger it is about to rewrite). nullopt when openRegularFileStream gave no stream.
inline std::optional<std::string> readRegularFile( std::string_view what, const std::string& path )
{
    const rw::pathguard::NoFollowRead stream = openRegularFileStream( what, path );
    if( stream.file == nullptr )
    {
        return std::nullopt;
    }
    return readAllOfStream( stream.file );
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
    if( i < s.size() )
    {
        ++i; // past the closing quote
    }
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
    const auto skipWs = [ & ]() { while( i < json.size() && ( json[i] == ' ' || json[i] == '\t' || json[i] == '\n' || json[i] == '\r' ) ) { ++i; } };

    while( ( i = json.find( key, i ) ) != std::string_view::npos )
    {
        i += key.size();
        skipWs();
        if( i >= json.size() || json[i] != ':' )
        {
            continue; // not a "source": key
        }
        ++i;
        skipWs();
        if( i >= json.size() )
        {
            break;
        }

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
                if( json[i] == '"' )
                {
                    detail::appendJsonString( json, i, out );
                }
                else
                {
                    ++i;
                }
            }
            if( i < json.size() )
            {
                ++i; // past ']'
            }
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
    if( p + lit.size() > s.size() )
    {
        return false;
    }
    for( std::size_t k = 0; k < lit.size(); ++k )
    {
        if( char( std::tolower( static_cast<unsigned char>( s[p + k] ) ) ) != lit[k] )
        {
            return false;
        }
    }
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
                while( e < html.size() && !detail::ciStartsWith( html, e, close ) )
                {
                    ++e;
                }
                while( e < html.size() && html[e] != '>' )
                {
                    ++e; // to end of the closing tag
                }
                i = ( e < html.size() ) ? e + 1 : html.size();
                out.push_back( ' ' );
                continue;
            }
            // ordinary tag — skip to '>'
            while( i < html.size() && html[i] != '>' )
            {
                ++i;
            }
            if( i < html.size() )
            {
                ++i;
            }
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
                if( ent == "&amp;" )
                {
                    out.push_back( '&' );
                }
                else if( ent == "&lt;" )
                {
                    out.push_back( '<' );
                }
                else if( ent == "&gt;" )
                {
                    out.push_back( '>' );
                }
                else if( ent == "&quot;" )
                {
                    out.push_back( '"' );
                }
                else if( ent == "&#39;" || ent == "&apos;" )
                {
                    out.push_back( '\'' );
                }
                else
                {
                    out.push_back( ' ' ); // &nbsp; and friends → space
                }
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
                if( out[k] == '\n' )
                {
                    hasNewline = true;
                }
                ++k;
            }
            if( !collapsed.empty() )
            {
                collapsed.push_back( hasNewline ? '\n' : ' ' );
            }
        }
        else
        {
            collapsed.push_back( out[k] );
            ++k;
        }
    }
    while( !collapsed.empty() && std::isspace( static_cast<unsigned char>( collapsed.back() ) ) )
    {
        collapsed.pop_back();
    }
    return collapsed;
}

// ── .csv — header names + a few sample rows (the column names are the searchable tokens) ─────────────

inline std::string extractCsv( std::string_view csv )
{
    // first line = header; the rest are data rows. We summarise rather than dump (a 100k-row CSV is noise).
    std::size_t nl = csv.find( '\n' );
    std::string_view header = ( nl == std::string_view::npos ) ? csv : csv.substr( 0, nl );
    if( !header.empty() && header.back() == '\r' )
    {
        header.remove_suffix( 1 );
    }

    // count data rows
    std::size_t rows = 0;
    bool hasData = false;
    for( std::size_t p = ( nl == std::string_view::npos ? csv.size() : nl + 1 ); p < csv.size(); ++p )
    {
        const char c = csv[p];
        if( c == '\n' )
        {
            if( hasData )
            {
                ++rows;
            }
            hasData = false;
        }
        else if( c != '\r' )
        {
            hasData = true;
        }
    }
    if( hasData )
    {
        ++rows;
    }

    std::string out = "CSV columns: ";
    for( char c : header )
    {
        out.push_back( c == ',' ? ' ' : c ); // commas → spaces so column names tokenize
    }
    out += "\nrows: ";
    out += std::to_string( rows );
    out.push_back( '\n' );

    // include up to 3 sample data rows so values are searchable too
    std::size_t emitted = 0, p = ( nl == std::string_view::npos ? csv.size() : nl + 1 );
    while( p < csv.size() && emitted < 3 )
    {
        const std::size_t e = csv.find( '\n', p );
        std::string_view line = csv.substr( p, ( e == std::string_view::npos ? csv.size() : e ) - p );
        if( !line.empty() && line.back() == '\r' )
        {
            line.remove_suffix( 1 );
        }
        if( !line.empty() )
        {
            for( char c : line )
            {
                out.push_back( c == ',' ? ' ' : c );
            }
            out.push_back( '\n' );
            ++emitted;
        }
        if( e == std::string_view::npos )
        {
            break;
        }
        p = e + 1;
    }
    return out;
}

// ── markitdown bridge (binary formats) — shell out IF present, else "" ──────────────────────────────

namespace detail
{

// Single-quote a path for safe inclusion in a /bin/sh command (paths come from the crawl, not user input,
// but quote anyway — defence in depth, and paths can contain spaces).
// NOTE (F13, resolved): was byte-identical to rw::shSingleQuote in gitmine.h — a local copy was kept
// deliberately at the time because merging would have forced docparse.h (Diagnostics.h + STL only,
// pulled by ingest.cpp) to include gitmine.h and thus the whole graph.h dependency chain. That's now
// moot: the canonical implementation moved to jsonesc.h (STL-only, zero project includes), which both
// docparse.h and gitmine.h can pull in for free. This is a thin forwarder so the local `shellQuote`
// name/call sites below don't need to change.
inline std::string shellQuote( const std::string& s )
{
    return rw::shSingleQuote( s );
}

}   // namespace detail

// Could `markitdown <path>` start at all? The bridge runs through the shell, and a shell that finds no command answers
// rc 127, which runMarkitdown reads as "" — so a machine WITHOUT markitdown paid one /bin/sh start per binary doc on
// every warm run, for an answer known before the fork (cli-floor 2026-10-08: ~25 ms of a warm call on this repository,
// two present/ decks). This asks the same question the shell would, with no process: os::which walks PATH exactly as
// sh does (an empty entry is the current directory; a directory or a non-executable file named markitdown is not a
// program). It is asked once per doc post-pass, never memoized across ingests, so installing markitdown under a
// running MCP server is seen on its next ingest. It answers TRUE whenever it cannot rule the shell out — PATH unset
// (sh then searches its own default path), an executable `./markitdown` (a Windows shell searches the current
// directory first), or an exported shell function of that name — because a false "absent" would drop a Section the
// shell would have produced, while a false "present" only costs the popen it always cost. Gated by
// test/docmdcachecheck.sh arms 6-9.
inline bool markitdownMayRun()
{
    if( std::getenv( "PATH" ) == nullptr || std::getenv( "BASH_FUNC_markitdown%%" ) != nullptr || std::getenv( "BASH_FUNC_markitdown()" ) != nullptr )
    {
        return true;
    }
    return !os::which( "markitdown" ).empty() || !os::which( "./markitdown" ).empty();
}

// Run `markitdown <path>` and return its stdout (Markdown), or "" if markitdown is not on PATH / it failed.
// NOTE: this performs a subprocess call — used only for binary doc formats, only when they are ingested.
inline std::string runMarkitdown( const std::string& path )
{
    const std::string cmd = "markitdown " + detail::shellQuote( path ) + " 2>/dev/null";
    std::FILE* pipe = os::popen( cmd.c_str(), "r" );
    if( pipe == nullptr )
    {
        DISCLOSE( "docparse: popen failed for markitdown bridge" );
        return {};
    }
    std::string         out;
    std::array<char, 65536> buf;
    std::size_t         n = 0;
    while( ( n = std::fread( buf.data(), 1, buf.size(), pipe ) ) > 0 )
    {
        out.append( buf.data(), n );
    }
    const int rc = os::pclose( pipe );
    if( rc != 0 )
    { // markitdown absent or errored → degrade to no-doc
        return {};
    }
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
            const std::optional<std::string> bytes = detail::readWholeFile( path );
            if( !bytes )
            {
                DISCLOSE( "docparse: cannot read document file" );
                rw::emitTo( stderr, "ripwire: doc {}: cannot read — omitted from the index (the skipped verb counts it as unmeasured)\n", path.c_str() );   // 2026-09-06
                return {};
            }
            switch( docKindOf( extLower ) )
            {
                case DocKind::Ipynb: return extractIpynb( *bytes );
                case DocKind::Html:  return extractHtml( *bytes );
                case DocKind::Csv:   return extractCsv( *bytes );
                case DocKind::Markitdown:                       // routed by the outer switch, never read here
                case DocKind::None:  return {};
            }
            return {};
        }

        case DocKind::None:
            return {};
    }
    return {};
}

// ── generated-document signals ───────────────────────────────────────────────────────────────────────
//
// A GENERATED document — a command capture, an API dump, a doxygen/openapi export — QUOTES the whole
// system it documents, so BM25 hands it every query's terms and it out-scores the design document that
// EXPLAINS them. Measured on this repo before the captures were relocated: a 246 KB capture scored
// 11.548 against a hand-written design document's 2.355 for "quality delta gating exit codes" (4.9x) — on a question the capture
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
//     (hand-written planning doc)                6.5        0.23      hand-written, densest big doc
//     README.md                                 6.5        0.13      hand-written
//     (hand-written planning doc)               6.1        0.02      hand-written
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
        if( lineEnd == std::string_view::npos )
        {
            lineEnd = text.size();
        }

        std::size_t cursor = lineStart;
        while( cursor < lineEnd && ( text[cursor] == ' ' || text[cursor] == '\t' ) )
        {
            ++cursor;
        }
        std::size_t tickCount = 0;
        while( cursor + tickCount < lineEnd && text[cursor + tickCount] == '`' )
        {
            ++tickCount;
        }

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
    if( needle.empty() || needle.size() > haystack.size() )
    {
        return false;
    }
    for( std::size_t at = 0; at + needle.size() <= haystack.size(); ++at )
    {
        if( ciStartsWith( haystack, at, needle ) )
        {
            return true;
        }
    }
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
    {
        if( detail::ciContains( head, phrase ) )
        {
            return true;
        }
    }
    return false;
}

// The verdict for ONE document, from evidence only. `medianDocBytes` and `docCount` are the corpus this
// document is extreme (or ordinary) relative to; a corpus too small for a median disables the size arm
// entirely — the marker arm, which needs no corpus, still applies.
inline GeneratedDocReason classifyGeneratedDoc( std::string_view text, std::size_t bytes,
                                                std::size_t medianDocBytes, std::size_t docCount ) noexcept
{
    if( hasGeneratedMarker( text ) )
    {
        return GeneratedDocReason::Marker;
    }

    const bool isCorpusMeasurable = docCount >= kGeneratedMinDocCount && medianDocBytes > 0;
    if( !isCorpusMeasurable )
    {
        return GeneratedDocReason::None;
    }
    if( bytes < kGeneratedMinBytes )
    {
        return GeneratedDocReason::None;
    }
    if( double( bytes ) < kGeneratedSizeRatio * double( medianDocBytes ) )
    {
        return GeneratedDocReason::None;
    }
    if( fencedLineFraction( scanMarkdownFences( text ) ) < kGeneratedFencedFraction )
    {
        return GeneratedDocReason::None;
    }
    return GeneratedDocReason::SizeAndFences;
}

}   // namespace docparse
}   // namespace rw
