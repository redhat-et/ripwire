#pragma once
// forqsites.h — θ11 (PLAN_071 §1.8, tmp/orch-1124/theta11/RESULT.md step 3): the QUESTION'S OWN SITES, on page 1.
//
// WHAT IT IS. A `--for` question usually spells the names the agent will grep for next: a `--flag`, a `snake_name`, a
// `Type::member`, an ALL-CAPS macro. After the answer it was given, the agent runs that grep (the follow-on calls are about 25 % of
// session cost, tmp/orch-1124/followon/RESULT.md). θ11 runs it first: one <qs> element per question token, every file:line where the token
// occurs, in a block with its OWN 1,000 B budget at the end of page 1, inside the root (before </ctx>), outside est_tokens.
//
// STATUS: ON by default since lane THETA11-FLIP (owner 11-24, after the sealed NL4 and NL5-large runs both passed); RIPWIRE_THETA11=0
// turns it off, and the answer is then byte-identical to the one served before the block existed (switch: forqsitesswitch.h, which
// --version's qsites= reads too). The offline proxy (grep coverage of the 56 M5 sessions' recorded follow-on calls) is about −2.9 %
// of session cost, most of it in multi-file sessions.
//
// THE RULE (pre-registered in cands.py `question_tokens` / `theta11`; this header is its product form):
//   1. TOKENS, in this order: inside backticks every `--opt` / `-opt` and identifier (`a`, `a::b`, `a.b`, `a->b`); then over the
//      whole question every `--long-opt` and identifier (`a::b`, `a.b`; one followed by `(` counts as code). A qualified name also
//      adds its last part. Kept: 3+ bytes, no dotted part under 3; IDENTIFIER-SHAPED (an option, from backticks or a call, `_`,
//      `::`, `.`, `->`, a lower→Upper seam, letters mixed with digits, ALL-CAPS 3+, CamelCase) — or a PLAIN lowercase word of 4+
//      bytes. Never a stopword.
//   2. SITES: the index's own literal scan (search.h grepCollectEach, every indexed file in ONE read, the whole-word test on the
//      bytes that read holds) plus ONE pass over the crawl's unindexed text files: the unsupported-extension rows and the
//      extensionless ones (CrawlSkips::extensionless: NEWS, Gemfile, Dockerfile, Makefile, ...). Whole-word for a plain identifier,
//      substring for an option or a qualified name. One site per line. Inside a --for render the indexed scan is served by the
//      answer's own FOR-SCAN-ONCE batch (search.h GrepScanBatch), so a question whose literal block reads the corpus reads it once.
//   3. KEPT: a token with 1..150 sites; a PLAIN word with 1..20 (kRareWordSites), or 1..150 when the index itself uses it as a
//      NAME (a definition's name or a reference's callee: `snprintf`). Repo rarity and code vocabulary stand in for the English word
//      list the emulation used: a word the repository rarely spells, or calls, is a lead; a common prose word is not. Portable: no
//      /usr/share/dict.
//   4. ORDER: identifier-shaped first, then fewest sites, then question order. Files in the scan's order (source, then test, then
//      docs; path within a tier; then the unindexed files by path), lines ascending.
//   5. EMIT: `<qs t="TOK" n="N">path:l,l path2:l</qs>`, one element per token; an element goes in whole or not at all, and on overflow the
//      next token is tried; 1,000 B of lines in all. One comment line before them says what they are. No token kept: no block.
//   6. FLOORS: n="N+" when a file the token may occur in went unread — the crawl kept fewer skip rows than it counted (500 per
//      class), the index scan stopped at its budget or skipped an unreadable file, or an unindexed text file could not be read or is
//      over the crawl's byte ceiling (a binary one is not text and floors nothing). Rule 3's caps read N, so a floor is listed as a
//      lower bound, never as a total (TokenSites is the DISCLOSE sink; the legend says what `+` means).
#include "model.h"       // IngestResult
#include "search.h"      // grepCollectEach / grepCollectAux — the index's literal scan
#include "docparse.h"    // docparse::detail::readWholeFile — the unindexed files' one read
#include "ingest.h"      // looksBinary / kDefaultMaxFileBytes — the aux pass skips what grepCollectAux skips
#include "sarif.h"       // rootRelativeUri — p= in the rows' own path dialect
#include "serialize.h"   // escapeXml
#include "darkflags.h"   // identByte / containsWord / forEachLine — the shared whole-word test and line splitter on raw file text
#include "lexical.h"     // routeLower
#include "forbudgetfit.h" // ForAnswerLedger::questionSites — the render hands its block to the page
#include "forliteral.h"  // lit_detail::trimAllWs — a backtick span is trimmed as Python str.strip does
#include "infra/ownedfile.h" // openOwnedFile — an oversized file's head, read to tell text from binary
#include "infra/Diagnostics.h" // DISCLOSE — a floored count
#include "forqsitesswitch.h" // thetaElevenOn — the switch (default ON; RIPWIRE_THETA11=0 off)

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <vector>

namespace rw::qsites
{

inline constexpr std::size_t kBlockBytes      = 1000;   // RESULT.md step 3: the knee (0.5→1 KB still saves, 1→2 KB barely)
inline constexpr std::size_t kMaxSitesPerTok  = 150;    // a token with more lines than this is not a lead
inline constexpr std::size_t kRareWordSites   = 20;     // a plain word with more lines than this is prose (rule 3; the 41-task proxy's knee)


struct Token
{
    std::string text;
    bool        wholeWord = true;    // false: substring (an option, a qualified name)
    bool        shaped    = false;   // identifier-shaped: sorts ahead of a plain word
};

namespace detail
{
[[nodiscard]] inline bool isWordByte( unsigned char c ) noexcept { return darkflags::identByte( c ); }
[[nodiscard]] inline bool isIdentStart( unsigned char c ) noexcept
{
    return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || c == '_';
}
[[nodiscard]] inline bool isAlpha( unsigned char c ) noexcept { return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ); }
[[nodiscard]] inline bool isDigit( unsigned char c ) noexcept { return c >= '0' && c <= '9'; }
[[nodiscard]] inline bool isUpper( unsigned char c ) noexcept { return c >= 'A' && c <= 'Z'; }
[[nodiscard]] inline bool isLower( unsigned char c ) noexcept { return c >= 'a' && c <= 'z'; }

// The length of the qualifier separator at s[i] ("::", ".", or "->" when `arrow`), 0 when none.
[[nodiscard]] inline std::size_t sepAt( std::string_view s, std::size_t i, bool arrow ) noexcept
{
    if( s.substr( i, 2 ) == "::" || ( arrow && s.substr( i, 2 ) == "->" ) )
    {
        return 2;
    }
    return i < s.size() && s[i] == '.' ? 1 : 0;
}

// `[A-Za-z_]\w*((::|\.|->)[A-Za-z_]\w*)*` at i (`arrow` admits `->`): the end, or i when no match.
[[nodiscard]] inline std::size_t identEnd( std::string_view s, std::size_t i, bool arrow ) noexcept
{
    if( i >= s.size() || !isIdentStart( (unsigned char)s[i] ) )
    {
        return i;
    }
    std::size_t j = i + 1;
    for( ;; )
    {
        while( j < s.size() && isWordByte( (unsigned char)s[j] ) )
        {
            ++j;
        }
        const std::size_t sep = sepAt( s, j, arrow );
        if( sep == 0 || j + sep >= s.size() || !isIdentStart( (unsigned char)s[j + sep] ) )
        {
            return j;
        }
        j += sep + 1;
    }
}

// `--?[A-Za-z][\w-]*(=\w+)?` (minDashes 1, minTail 0) or `--[A-Za-z][\w-]+(=\w+)?` (2, 1) at i: the end, or i when no match.
[[nodiscard]] inline std::size_t optionEnd( std::string_view s, std::size_t i, std::size_t minDashes, std::size_t minTail ) noexcept
{
    std::size_t j = i;
    std::size_t dashes = 0;
    while( j < s.size() && s[j] == '-' && dashes < 2 )
    {
        ++j;
        ++dashes;
    }
    if( dashes < minDashes || j >= s.size() || !isAlpha( (unsigned char)s[j] ) )
    {
        return i;
    }
    ++j;
    const std::size_t tailStart = j;
    while( j < s.size() && ( isWordByte( (unsigned char)s[j] ) || s[j] == '-' ) )
    {
        ++j;
    }
    if( j - tailStart < minTail )
    {
        return i;
    }
    if( j + 1 < s.size() && s[j] == '=' && isWordByte( (unsigned char)s[j + 1] ) )
    {
        ++j;
        while( j < s.size() && isWordByte( (unsigned char)s[j] ) )
        {
            ++j;
        }
    }
    return j;
}

[[nodiscard]] inline bool hasSep( std::string_view x, bool arrow ) noexcept
{
    return x.find( "::" ) != std::string_view::npos || x.find( '.' ) != std::string_view::npos
           || ( arrow && x.find( "->" ) != std::string_view::npos );
}

// The parts of a qualified name, split at `::`, `.` and `->`.
[[nodiscard]] inline std::vector<std::string_view> qualParts( std::string_view x )
{
    std::vector<std::string_view> parts;
    std::size_t start = 0;
    for( std::size_t i = 0; i < x.size(); )
    {
        const std::size_t sep = sepAt( x, i, true );
        if( sep != 0 )
        {
            parts.push_back( x.substr( start, i - start ) );
            i += sep;
            start = i;
        }
        else
        {
            ++i;
        }
    }
    parts.push_back( x.substr( start ) );
    return parts;
}

[[nodiscard]] inline bool isStopword( std::string_view lower ) noexcept
{
    static constexpr std::array kStop = std::to_array<std::string_view>( { "self", "this", "that", "with", "from", "when", "into", "then", "than", "only",
                                                  "also", "were", "which", "there", "problem", "solution", "fix", "fixes", "fixed",
                                                  "add", "adds", "added", "remove", "removes", "support", "should", "would", "could",
                                                  "because", "instead", "every", "each", "some", "none", "true", "false", "null" } );
    return std::ranges::any_of( kStop, [ lower ]( std::string_view w ) { return w == lower; } );
}


// Identifier-shaped (rule 1), `fromCode`: from backticks or followed by `(`.
[[nodiscard]] inline bool isShaped( std::string_view x, bool fromCode ) noexcept
{
    if( fromCode || x.starts_with( '-' ) || x.find( '_' ) != std::string_view::npos || hasSep( x, true ) )
    {
        return true;
    }
    for( std::size_t i = 0; i + 1 < x.size(); ++i )
    {
        const auto a = (unsigned char)x[i];
        const auto b = (unsigned char)x[i + 1];
        if( ( isLower( a ) && isUpper( b ) ) || ( isAlpha( a ) && isDigit( b ) ) || ( isDigit( a ) && isAlpha( b ) ) )
        {
            return true;
        }
    }
    const bool allCaps = x.size() >= 3 && isUpper( (unsigned char)x[0] )
                         && std::all_of( x.begin() + 1, x.end(), []( char c ) { return isUpper( static_cast<unsigned char>( c ) ) || isDigit( static_cast<unsigned char>( c ) ); } );
    return allCaps;   // CamelCase (`[A-Z][a-z]+[A-Z]\w*`) always carries a lower→Upper seam, caught above
}

}   // namespace detail

namespace detail
{
// A token as the question spells it: `fromCode` when it came from backticks or is followed by `(`.
struct RawToken
{
    std::string text;
    bool        fromCode = false;
};

inline void addRaw( std::vector<RawToken>& raw, std::string_view t, bool fromCode )
{
    if( std::ranges::none_of( raw, [ t ]( const RawToken& r ) { return r.text == t; } ) )
    {
        raw.push_back( { std::string( t ), fromCode } );   // first spelling wins (OrderedDict.setdefault)
    }
}

// Every `--opt` / `-opt` / identifier inside one backtick span.
inline void scanCodeSpan( std::string_view span, std::vector<RawToken>& raw )
{
    for( std::size_t j = 0; j < span.size(); )
    {
        std::size_t e = optionEnd( span, j, 1, 0 );
        e = e == j ? identEnd( span, j, true ) : e;
        if( e == j )
        {
            ++j;
            continue;
        }
        addRaw( raw, span.substr( j, e - j ), true );
        j = e;
    }
}

// Every `--long-opt` and identifier over the whole question; one followed by `(` is code.
inline void scanProse( std::string_view q, std::vector<RawToken>& raw )
{
    for( std::size_t j = 0; j < q.size(); )
    {
        std::size_t e    = optionEnd( q, j, 2, 1 );
        bool        call = false;
        if( e == j )
        {
            e    = identEnd( q, j, false );
            call = e != j && e < q.size() && q[e] == '(';
        }
        if( e == j )
        {
            ++j;
            continue;
        }
        addRaw( raw, q.substr( j, e - j ), call );
        j = e + ( call ? 1 : 0 );
    }
}

// The question's tokens in rule 1's order: backtick spans first, then the whole question.
[[nodiscard]] inline std::vector<RawToken> rawTokens( std::string_view q )
{
    std::vector<RawToken> raw;
    std::size_t           open = q.find( '`' );
    while( open != std::string_view::npos )
    {
        const std::size_t close = q.find( '`', open + 1 );
        if( close == std::string_view::npos )
        {
            break;
        }
        scanCodeSpan( lit_detail::trimAllWs( q.substr( open + 1, close - open - 1 ) ), raw );
        open = q.find( '`', close + 1 );
    }
    scanProse( q, raw );
    return raw;
}

// A dotted token with a part under 3 bytes is not kept (`a.b`, `os.path` is: `os` is short).
[[nodiscard]] inline bool hasShortDottedPart( std::string_view x )
{
    if( x.find( '.' ) == std::string_view::npos )
    {
        return false;
    }
    const std::size_t lead = x.find_first_not_of( '-' );
    const std::vector<std::string_view> ps = qualParts( lead == std::string_view::npos ? std::string_view() : x.substr( lead ) );
    return std::ranges::any_of( ps, []( std::string_view p ) { return p.size() < 3; } );
}

[[nodiscard]] inline bool isLowerWord( std::string_view x ) noexcept
{
    return std::ranges::any_of( x, []( char ch ) { return isLower( (unsigned char)ch ); } )
           && std::ranges::none_of( x, []( char ch ) { return isUpper( (unsigned char)ch ); } );
}

// Rule 1's keep tests, in cands.py's order: `seen` is marked before the stopword and plain-word tests.
[[nodiscard]] inline std::vector<Token> candidates( const std::vector<RawToken>& raw )
{
    std::vector<Token>       out;
    std::vector<std::string> seen;
    for( const RawToken& r : raw )
    {
        std::vector<std::string_view> parts{ r.text };
        if( hasSep( r.text, true ) && !r.text.starts_with( '-' ) )
        {
            parts.push_back( qualParts( r.text ).back() );
        }
        for( const std::string_view x : parts )
        {
            if( x.size() < 3 || std::ranges::find( seen, x ) != seen.end() || hasShortDottedPart( x ) )
            {
                continue;
            }
            seen.emplace_back( x );
            const bool shaped = isShaped( x, r.fromCode );
            if( isStopword( routeLower( x ) ) || ( !shaped && ( x.size() < 4 || !isLowerWord( x ) ) ) )
            {
                continue;
            }
            out.push_back( { std::string( x ), !( x.starts_with( '-' ) || hasSep( x, true ) ), shaped } );
        }
    }
    return out;
}
}   // namespace detail

// Rule 1: the question's tokens (a plain word's rarity, rule 3, is judged on its sites).
[[nodiscard]] inline std::vector<Token> questionTokens( std::string_view q )
{
    return detail::candidates( detail::rawTokens( q ) );
}

// One token's sites: (path, line) in the scan's order, one per line.
struct TokenSites
{
    std::size_t                                        order = 0;   // question order
    const Token*                                       tok   = nullptr;
    std::vector<std::pair<std::string, std::uint32_t>> sites;
    bool                                               codeName = false;   // a plain word the index uses as a name (rule 3)
    bool                                               floor    = false;   // a file it may occur in went unread: n= is a floor (rule 6)

    enum class DisclosureWhy : std::uint8_t
    {
        SkipRowsCapped,        // the crawl counted more skipped files than it kept rows for
        IndexScanIncomplete,   // the index scan stopped at its budget or skipped an unreadable file
        FileUnread,            // an unindexed text file could not be read, or is over the byte ceiling
        OversizeUnread,        // the crawl dropped a file over its size ceiling (IngestResult::skippedOversize); this scan does not read it
    };
    void disclose( DisclosureWhy ) noexcept   // the DISCLOSE sink: formatLine prints n="N+"
    {
        floor = true;
    }
};

// Rule 3's code vocabulary: the index defines a symbol named `w`, or a reference calls or names it (an exact id compare: a name no
// reference carries was never interned, so ifInterned answers that without a pass).
[[nodiscard]] inline bool indexNamesWord( const IngestResult& ing, std::string_view w )
{
    if( std::ranges::any_of( ing.symbols, [ w ]( const Symbol& s ) { return s.name == w; } ) )
    {
        return true;
    }
    const std::optional<InternedText> id = InternedText::ifInterned( w );
    return id && std::ranges::any_of( ing.references, [ &id ]( const Reference& r ) { return r.calleeName == *id; } );
}

// A token's site cap (rule 3).
[[nodiscard]] inline std::size_t siteCap( const TokenSites& t ) noexcept
{
    return t.tok->shaped || t.codeName ? kMaxSitesPerTok : kRareWordSites;
}

namespace detail
{
// The indexed files' sites of one token (the scan already kept only whole-word ones for a word-bounded token), one per line; stops
// one past the cap (the token is then skipped).
inline void indexedSites( const IngestResult& ing, const GrepCollection& found, std::string_view rootPrefix, TokenSites& ts )
{
    if( !found.cleanScan() )
    {
        DISCLOSE( ts, TokenSites::DisclosureWhy::IndexScanIncomplete, "qsites: the index scan stopped at its budget or skipped an unreadable file; n= is a floor" );
    }
    std::uint32_t lastFile = UINT32_MAX, lastLine = 0;
    for( const GrepRawHit& h : found.raw )
    {
        if( ts.sites.size() > kMaxSitesPerTok )
        {
            return;
        }
        if( h.fileId == lastFile && h.line == lastLine )
        {
            continue;
        }
        lastFile = h.fileId;
        lastLine = h.line;
        ts.sites.emplace_back( rootPrefix.empty() ? ing.files[h.fileId] : std::string( sarif::rootRelativeUri( ing.files[h.fileId], rootPrefix ) ), h.line );
    }
}

// Where a skip row's file is on disk: its own path on a single root; in a workspace the row carries the labelled `<label>/<rel>`
// (workspace.h relabel), so the longest label it starts with names the root whose path the rest is under.
[[nodiscard]] inline std::string skipRowDiskPath( const IngestResult& ing, const std::string& rowPath )
{
    std::size_t best = SIZE_MAX, bestLen = 0;
    for( std::size_t r = 0; r < ing.rootLabels.size() && r < ing.rootPaths.size(); ++r )
    {
        const std::string& label = ing.rootLabels[r];
        if( label.size() >= bestLen && rowPath.size() > label.size() && rowPath.starts_with( label ) && rowPath[label.size()] == '/' )
        {
            best    = r;
            bestLen = label.size();
        }
    }
    return best == SIZE_MAX ? rowPath : ing.rootPaths[best] + rowPath.substr( bestLen );
}

// An oversized file's first bytes: binary there means no text line was skipped.
[[nodiscard]] inline bool headLooksBinary( const std::string& diskPath )
{
    OwnedFile   fp = openOwnedFile( diskPath.c_str(), "rb" );
    std::string head( kBinarySniffCap, '\0' );
    head.resize( fp ? std::fread( head.data(), 1, head.size(), fp.file ) : 0 );
    return fp && looksBinary( head );
}

// Rule 6 for a file every token may occur in: each count becomes a floor.
inline void floorEvery( std::span<TokenSites> out ) noexcept
{
    for( TokenSites& ts : out )
    {
        DISCLOSE( ts, TokenSites::DisclosureWhy::FileUnread, "qsites: an unindexed text file was unreadable or over the byte ceiling; n= is a floor" );
    }
}

// One file outside the index, read ONCE: every token still under its cap gets the lines it occurs on.
inline void auxFileSites( const IngestResult& ing, const SkippedFile& row, std::span<TokenSites> out, std::string_view rootPrefix )
{
    const std::string disk = skipRowDiskPath( ing, row.path );
    if( row.sizeBytes > kDefaultMaxFileBytes )
    {
        if( !headLooksBinary( disk ) )
        {
            floorEvery( out );   // the crawl ceiling: a text file this big is left unread (a lead is not in a 4 MB file), and said so
        }
        return;
    }
    const std::optional<std::string> bytes = docparse::detail::readWholeFile( disk );
    if( !bytes )
    {
        floorEvery( out );
        return;
    }
    if( looksBinary( *bytes ) )
    {
        return;
    }
    const std::string path = rootPrefix.empty() ? row.path : std::string( sarif::rootRelativeUri( row.path, rootPrefix ) );
    for( TokenSites& ts : out )
    {
        const Token& tok = *ts.tok;
        if( ts.sites.size() > kMaxSitesPerTok || bytes->find( tok.text ) == std::string::npos )
        {
            continue;
        }
        (void)darkflags::forEachLine( *bytes, [ & ]( std::string_view line, std::uint32_t lineNo )
        {
            if( ts.sites.size() <= kMaxSitesPerTok && ( tok.wholeWord ? darkflags::containsWord( line, tok.text ) : line.find( tok.text ) != std::string_view::npos ) )
            {
                ts.sites.emplace_back( path, lineNo );
            }
        } );
    }
}
}   // namespace detail

// The literal scans rule 2 asks of the index: one per token, word-bounded for a whole-word one.
struct ScanPlan
{
    std::vector<std::string> patterns;
    std::vector<char>        wordBounded;   // parallel
};
[[nodiscard]] inline ScanPlan scanPlan( std::span<const Token> toks )
{
    ScanPlan plan;
    for( const Token& t : toks )
    {
        plan.patterns.push_back( t.text );
        plan.wordBounded.push_back( char( t.wholeWord ) );
    }
    return plan;
}
// The same plan split as GrepScanBatch expects it: substring patterns, then word-bounded ones.
[[nodiscard]] inline std::pair<std::vector<std::string>, std::vector<std::string>> batchExpectations( std::string_view task )
{
    std::pair<std::vector<std::string>, std::vector<std::string>> out;
    for( const Token& t : questionTokens( task ) )
    {
        ( t.wholeWord ? out.second : out.first ).push_back( t.text );
    }
    return out;
}

// The index's collections for the plan: from the open FOR-SCAN-ONCE batch on this index when there is one (its read is shared),
// else one grepCollectEach read for every token.
[[nodiscard]] inline std::vector<GrepCollection> indexedCollections( const IngestResult& ing, const ScanPlan& plan )
{
    if( plan.patterns.empty() )
    {
        return {};
    }
    if( GrepScanBatch* const batch = GrepScanBatch::openFor( ing ) )
    {
        std::vector<GrepCollection> out;
        for( std::size_t k = 0; k < plan.patterns.size(); ++k )
        {
            out.push_back( batch->collect( plan.patterns[k], kGrepScanStackBytes, plan.wordBounded[k] != 0 ) );
        }
        return out;
    }
    return grepCollectEach( ing, plan.patterns, /*regex=*/false, /*noPrefilter=*/false, kGrepScanStackBytes, plan.wordBounded );
}

// Rule 2: every token's sites — the index's scan, then one pass over the unindexed text files.
[[nodiscard]] inline std::vector<TokenSites> collectSites( const IngestResult& ing, std::span<const Token> toks, std::string_view rootPrefix )
{
    std::vector<TokenSites>           out( toks.size() );
    const std::vector<GrepCollection> found = indexedCollections( ing, scanPlan( toks ) );
    for( std::size_t k = 0; k < toks.size(); ++k )
    {
        out[k].order = k;
        out[k].tok   = &toks[k];
        detail::indexedSites( ing, found[k], rootPrefix, out[k] );
    }
    const CrawlSkips& cs = ing.crawlSkips;
    if( cs.unsupported.size() < cs.unsupportedFiles || cs.extensionless.size() < cs.extensionlessFiles )
    {
        for( TokenSites& ts : out )
        {
            DISCLOSE( ts, TokenSites::DisclosureWhy::SkipRowsCapped, "qsites: the crawl kept fewer skip rows than it counted, so files past the cap were not read; n= is a floor" );
        }
    }
    if( !ing.skippedOversize.empty() )   // CR #746: a dropped oversize file may hold a site, so no count here is a total
    {
        for( TokenSites& ts : out )
        {
            DISCLOSE( ts, TokenSites::DisclosureWhy::OversizeUnread, "qsites: the crawl dropped a file over its size ceiling and this scan does not read it; n= is a floor" );
        }
    }
    for( const std::vector<SkippedFile>* rows : { &cs.unsupported, &cs.extensionless } )
    {
        for( const SkippedFile& row : *rows )
        {
            detail::auxFileSites( ing, row, out, rootPrefix );
        }
    }
    for( TokenSites& t : out )   // rule 3: only a plain word past the rarity cap and within the name cap asks the index
    {
        t.codeName = !t.tok->shaped && t.sites.size() > kRareWordSites && t.sites.size() <= kMaxSitesPerTok && indexNamesWord( ing, t.tok->text );
    }
    return out;
}

// Rule 5's line for one token: `<qs t="TOK" n="N">path:l,l path2:l</qs>`, its files in first-site order.
[[nodiscard]] inline std::string formatLine( const TokenSites& t, std::vector<char>& esc )
{
    std::string line = "<qs t=\"" + std::string( escapeXml( t.tok->text, esc ) ) + "\" n=\"" + std::to_string( t.sites.size() ) + ( t.floor ? "+" : "" ) + "\">";
    std::vector<std::string_view> files;
    for( const auto& [ p, l ] : t.sites )
    {
        if( std::find( files.begin(), files.end(), std::string_view( p ) ) == files.end() )
        {
            files.emplace_back( p );
        }
    }
    for( std::size_t f = 0; f < files.size(); ++f )
    {
        line += f ? " " : "";
        line += escapeXml( files[f], esc );
        char sep = ':';
        for( const auto& [ p, l ] : t.sites )
        {
            if( p == files[f] )
            {
                line += sep;
                line += std::to_string( l );
                sep = ',';
            }
        }
    }
    return line + "</qs>";
}

// Rules 3 to 5: the block's <qs> elements, back to back, or "" when no token fits. No newline: the page is minified XML with no newline
// outside CDATA (G4; test/actlinecheck.sh (H)). The 1,000 B still counts one separator byte per element, so the elements chosen are the
// ones the sealed NL4 / NL5-large runs measured (they printed one per line).
[[nodiscard]] inline std::string formatLines( std::vector<TokenSites> sites, std::size_t budget = kBlockBytes )
{
    std::erase_if( sites, []( const TokenSites& t ) { return t.sites.empty() || t.sites.size() > siteCap( t ); } );
    std::stable_sort( sites.begin(), sites.end(), []( const TokenSites& a, const TokenSites& b )
                      { return std::tuple( !a.tok->shaped, a.sites.size(), a.order ) < std::tuple( !b.tok->shaped, b.sites.size(), b.order ); } );
    std::string       out;
    std::size_t       used = 0;
    std::vector<char> esc;
    for( const TokenSites& t : sites )
    {
        const std::string line = formatLine( t, esc );
        if( used + line.size() + 1 > budget )
        {
            continue;
        }
        out += line;
        used += line.size() + 1;   // + 1: the separator the measured block printed (see above)
    }
    return out;
}

inline constexpr std::string_view kLegend =
    "<!-- qs: where this question's own words occur, as a grep would list them (indexed, unindexed and extensionless text files): "
    "t= the word, n= its lines (N+ a floor: a file it may be in went unread), then path:line,line per file; whole-word for a name, substring for an option or a qualified name; "
    "a word only on 150 lines or fewer, a plain word on 20 lines or fewer unless the code names it; these entries are their own 1,000 B, "
    "outside est_tokens and any budget -->";
static_assert( kBlockBytes == 1000 && kLegend.find( "their own 1,000 B" ) != std::string_view::npos, "the qs legend states the block's budget" );
static_assert( kMaxSitesPerTok == 150 && kLegend.find( "150 lines or fewer" ) != std::string_view::npos, "the qs legend states the word cap" );
static_assert( kRareWordSites == 20 && kLegend.find( "20 lines or fewer" ) != std::string_view::npos, "the qs legend states the plain-word cap" );

// The whole θ11 block for `task` ("" when the knob is off or no token fits): the legend comment, then the <qs> elements, no newline (G4).
[[nodiscard]] inline std::string questionSitesBlock( const IngestResult& ing, std::string_view task, std::string_view root )
{
    if( !thetaElevenOn() )
    {
        return {};
    }
    const std::vector<Token> toks  = questionTokens( task );
    const std::string        lines = formatLines( collectSites( ing, toks, root.empty() ? std::string() : sarif::rootPrefixOf( root ) ) );
    return lines.empty() ? std::string() : std::string( kLegend ) + lines;
}

// Inside the root: the block goes in after the answer's last element, ahead of the comments that close the root (the document legend
// and the ROWLINES clauses, which stay last before </ctx>: forrowlines.h; test/rowlinescheck.sh (L2)); a trailing newline after </ctx>
// stays after it. false: no block, or the page does not end in </ctx> (a JSON or columnar answer) — nothing is inserted.
inline bool insertBlock( std::string& page, std::string_view block )
{
    static constexpr std::string_view kClose = "</ctx>";
    std::size_t end = page.size();
    while( end > 0 && page[end - 1] == '\n' )
    {
        --end;
    }
    if( block.empty() || end < kClose.size() || std::string_view( page ).substr( end - kClose.size(), kClose.size() ) != kClose )
    {
        return false;
    }
    std::size_t at = end - kClose.size();
    while( std::string_view( page ).substr( 0, at ).ends_with( "-->" ) )   // step back over the closing comment run
    {
        const std::size_t open = page.rfind( "<!--", at - 3 );
        if( open == std::string::npos )
        {
            break;
        }
        at = open;
    }
    page.insert( at, block );
    return true;
}

// The CLI seam: page 1 of a --for answer gains the block the render left in its ledger.
inline void appendQuestionSites( std::string& page, const ForAnswerLedger& ledger, std::size_t pageNo )
{
    if( pageNo == 1 )
    {
        (void)insertBlock( page, ledger.questionSites );
    }
}

}   // namespace rw::qsites
