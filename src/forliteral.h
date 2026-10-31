#pragma once
// forliteral.h — MF1-LIT: THE LITERAL ANCHOR of a --for answer whose task names a literal (an error string, an env var, a
// config key, an error code).
//
// WHY. A --for task such as `FZF_DEFAULT_COMMAND` or `"dependency cycle" error` names a STRING, not a symbol. The ranked answer
// reads it as words: name-exact finds no definition (`reason="no_candidates"`, empty <sigs>) or stops at the one variable spelled
// like it, and the place the literal is read, compared, built or raised is never printed. Measured before this code (ORCH
// reports/mf1-lit.md Stage 0): on the three MF1-DEV rows whose 12 missing items readout-40 files under LITERAL (fastify-02,
// fzf-05, textual-03) the default answer held none of the code that handles the literal, while a byte-exact scan finds it in
// one call (`--grep`).
//
// WHAT. <lit s= shape= hits= src= …> just before </ctx>, after every byte of the ordinary answer (RIPWIRE_NO_LITERAL_ANCHOR=1
// is the rest of it byte for byte): the grep verb's own byte-exact literal scan (search.h grepCollect + grepEnrich) over the
// index, then
//   * <ls> rows: the sites in SOURCE files (filter.h pathTierOf = Source, not a doc/shell/config file), each labelled by the
//     parse (ingest.h spanTierAt): k="string" inside a string literal, k="code" outside one (an identifier or key use),
//     k="?" a file past the classification budget or with no grammar (never dropped, never called code). One row per source
//     line; sites inside a function or method first, then string before code before unclassified, the scan's own path order
//     within each; in= the innermost definition holding the site and ink= its kind; a string site outside any function (an
//     error-code table entry) carries the kForLiteralContextLines lines after it (lines=), at most kForLiteralContextRows rows;
//   * counts beside them for what is NOT a handler: comment= (comment sites in source files, and a Python docstring: a triple-quoted
//     string that is the first statement of a module, class or def body; a string opening a call-argument line is a site),
//     test= (test or bench paths), doc= (docs, shell scripts, config files) — counted, never listed as rows here (the grep verb
//     lists them: next=);
//   * <b> the whole body of the function or method holding a shown site when it is kForLiteralWholeBodyLines lines or fewer
//     (at most kForLiteralBodies owners in row order), or <x> an excerpt of a longer one: its signature line plus one window
//     [site-1, site+5] per shown site (windows merged only where they touch; l= lists the ranges, an ellipsis line sits between
//     them; of= is the body's lines; next= names the whole body); a body this answer already printed is not repeated
//     (body="above" on its rows); an owner past the cap prints no body and its rows say body="held".
// Several sites are always listed with counts: the block never picks one. floor="1" when the scan stopped early (budget,
// unreadable files) or a source site was left unclassified (k="?": comment= cannot see it): every count is then a floor. No source site, nothing printed (a literal met only in tests, docs or comments
// anchors nothing; never a "the literal is unused" claim).
//
// WHEN. The default regime of the XML dialect, a single root: an explicit --token-budget, --json, --columnar and --candidates
// carry none. The literal is read from the task: the first "double-quoted" span of at least 6 bytes holding a letter and a space
// (a message fragment; a backticked span is code the ranked answer already reads as names, and measured as noise on S1), else the first CONST_SHAPED word (upper-case letters and digits joined by at least one underscore, 5 bytes or more,
// or 10 or more upper-case letters and digits). A task with neither carries no block. The block is not in est_tokens (the
// FOR-ROUTE-DECLINED precedent: the bytes are counted on the element instead, bytes=). MCP `for` is not changed.
//
// LITERAL-ANCHOR V1. Failing both, the same block for two more shapes read from the --for text itself (an agent's or a stored subject
// is bare: `files.autoSave afterDelay setting flow`, `Invalid user settings file notification`, no backticks survive into it):
//   * shape="dotted": a dotted key of 3+ segments, or 2 with a whole word setting/option/key/command/flag beside it. Identity is an
//     allowlist (forliteral.h dottedKeyOf): identifier segments only; never a file name or host, a `self.`/`this.` chain or a call; a
//     capitalised first segment (Class.method) only with a cue. Rows are the WHOLE key: a site inside a longer name or a child key is
//     counted in longer=, never a row, and sites the quotes delimit rank above mentions, so a registration survives the row cap.
//   * shape="message": 3+ words with a whole word error/notification/message: a backticked or single-quoted span (cue outside it),
//     else the whole task minus a leading or trailing cue. Bytes are tried longest first, at most kForLiteralMessageTries scans, then
//     end-anchored fragments of the longest placeholder-free word run, down to 3 words (frag="1": s= is only part of the task's
//     words). Only a string site anchors a message: no such site, no block, next try.

#include "filter.h"          // pathTierOf — source / test / doc, the reader's tier
#include "layout.h"          // layout::lineOf — a byte offset's line
#include "hopbody.h"         // renderBodyElement — the --expand body element, no callee rows; pythonDocstringQuote
#include "langfacts.h"       // langFacts(...).leadingDocstring — which languages have a docstring convention
#include "lintrules.h"       // langOfPath
#include "model.h"
#include "nextverb.h"        // nextFlag / nextAttrXml
#include "receiverevidence.h"   // ReceiverEvidence::callableKind
#include "redact.h"          // redactInPlace — raw source text is redacted before it is emitted
#include "sarif.h"           // rootPrefixOf / rootRelativeUri
#include "search.h"          // grepCollect / grepEnrich / isBareWordCodePath
#include "serialize.h"       // escapeXml / appendCdataSafe / truncateUtf8WithEllipsis

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <initializer_list>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
inline constexpr std::size_t kForLiteralSiteRows      = 8;      // <ls> rows shown (a runaway guard: shown=/src= count, next= lists all)
inline constexpr std::size_t kForLiteralRankedRows    = 256;    // source sites ordered for the rows (past it: counted in src=, not ranked)
inline constexpr std::size_t kForLiteralContextRows   = 2;      // string sites outside any function served with the lines after them
inline constexpr std::uint32_t kForLiteralContextLines = 2;     // ...this many lines after the site
inline constexpr std::size_t kForLiteralBodies        = 3;      // owner bodies served, in row order
inline constexpr std::size_t kForLiteralBodyCapBytes  = 3000;   // a short body over this many bytes is still served as an excerpt <x>
inline constexpr std::uint32_t kForLiteralWholeBodyLines = 10;  // a body of at most this many lines is served whole; a longer one as an excerpt
inline constexpr std::uint32_t kForLiteralExcerptBefore = 1;    // lines before a site in its excerpt window
inline constexpr std::uint32_t kForLiteralExcerptAfter  = 5;    // lines after it: what the code does with a literal follows the read (+2/+3 drops fzf R2)
inline constexpr std::size_t kForLiteralTierFiles     = 64;     // source hit files classified (k=); past it k="?"
inline constexpr std::size_t kForLiteralLineBytes     = 200;    // the matched line's text, cut on a UTF-8 boundary
inline constexpr std::size_t kForLiteralMinQuoted     = 6;
inline constexpr std::size_t kForLiteralMinConst      = 5;
inline constexpr std::size_t kForLiteralMinBareCaps   = 10;
inline constexpr std::size_t kForLiteralMinKeyBytes   = 6;      // a dotted key shorter than this is not a key (`a.b.c`)
inline constexpr std::size_t kForLiteralMessageWords  = 3;      // a message or a fragment of one has at least this many words
inline constexpr std::size_t kForLiteralMessageTries  = 8;      // whole-repo scans a message may cost (a runaway guard on a task's word count)

// the element's legend comment (X3: no double hyphen inside). The compact form is the default --legend=compact posture; the long
// text rides --legend=full. Both name every attribute the element prints.
inline constexpr std::string_view kForLiteralLegend =
    "<!-- ripwire for lit: a byte-exact index scan for the literal the task names (s=; shape= quoted span or CONST word), after "
    "the unchanged answer, not in est_tokens (bytes= is its size). ls = one source line holding it, in-function sites first: "
    "k=string in a string literal, code outside one, ? unclassified; in=/ink= the enclosing definition and kind; CDATA its line "
    "(lines=a-b: with the lines after it). hits= all matches, src= source lines (shown=, capped=1), comment= comments and "
    "docstrings, test= test paths, doc= docs, shell, config: counted, never rows. b = a shown site's whole function (10 lines or "
    "fewer), x = an excerpt of a longer one (l= its line ranges: the signature line and a window around each site, an ellipsis "
    "line between them; of= the body's lines; cut=1: a line over 200 bytes was cut; next= the whole body); body=above: printed "
    "above, held: its owner body is past the 3-body cap, not printed. floor=1: scan stopped early or a site "
    "was not classified (k=?), counts are floors; next= on lit lists every site. -->";
inline constexpr std::string_view kForCompactLiteralLegend =
    "<!-- ripwire for lit: byte-exact scan for the task's literal (s=, shape=), not in est_tokens (bytes=). ls: a source line with it "
    "(k=string|code|?; in=/ink= its def; lines=a-b adds the lines after). hits=/src= all/source lines (shown=; capped=1: more); "
    "comment= test= doc= counted, not rows; floor=1: floors. b whole fn, x excerpt (l= ranges, \xE2\x80\xA6 between; of= body lines; "
    "cut=1: lines cut; next= whole); body=above|held: printed above|past the 3-body cap. -->";
static_assert( kForLiteralLegend.find( "--", 4 ) == kForLiteralLegend.size() - 3 && kForCompactLiteralLegend.find( "--", 4 ) == kForCompactLiteralLegend.size() - 3,
               "the only double hyphen in a legend comment is its closing: one inside is not well-formed XML" );

// present only with shape=dotted|message, so the bytes of a quoted or const fire do not move; the name of the shape is the row's whole
// reading, the base legend above still defines every other attribute
inline constexpr std::string_view kForLiteralKeyLegend =
    "<!-- ripwire for lit: shape=dotted a dotted key in the task (3 or more segments, or 2 with a setting, option, key, command or flag "
    "word): rows hold the whole key, quoted sites first; longer= source sites inside a longer name or child key, counted, never rows. "
    "shape=message the task's words as a message (3 or more, with an error, notification or message word): string sites only; frag=1: "
    "the whole text has no site, s= is the part that does. -->";
static_assert( kForLiteralKeyLegend.find( "--", 4 ) == kForLiteralKeyLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );

inline bool forLiteralOn()
{
    return std::getenv( "RIPWIRE_NO_LITERAL_ANCHOR" ) == nullptr;
}

struct ForLiteral
{
    std::string text;
    std::string_view shape;   // "quoted" | "const" | "dotted" | "message"
    bool             frag = false;   // shape=message: `text` is a fragment of the task's words, the whole text has no site
};

namespace lit_detail
{

// CONST_SHAPED: upper-case letters and digits, starting with a letter, joined by underscores (at least one, none doubled or at an
// end) and at least kForLiteralMinConst bytes; or no underscore and at least kForLiteralMinBareCaps bytes (PYTHONASYNCIODEBUG)
inline bool isConstShaped( std::string_view w ) noexcept
{
    if( w.empty() || !( w[0] >= 'A' && w[0] <= 'Z' ) || w.back() == '_' )
    {
        return false;
    }
    std::size_t underscores = 0;
    for( std::size_t i = 0; i < w.size(); ++i )
    {
        if( w[i] == '_' )
        {
            if( w[i - 1] == '_' )
            {
                return false;
            }
            ++underscores;
        }
        else if( !std::isupper( static_cast<unsigned char>( w[i] ) ) && !std::isdigit( static_cast<unsigned char>( w[i] ) ) )
        {
            return false;
        }
    }
    return underscores > 0 ? w.size() >= kForLiteralMinConst : w.size() >= kForLiteralMinBareCaps;
}

inline std::optional<std::string> quotedSpan( std::string_view task, char q )
{
    for( std::size_t open = task.find( q ); open != std::string_view::npos; open = task.find( q, open + 1 ) )
    {
        const std::size_t close = task.find( q, open + 1 );
        if( close == std::string_view::npos )
        {
            return std::nullopt;
        }
        const std::string_view inner = task.substr( open + 1, close - open - 1 );
        bool letter = false;
        for( const char c : inner )
        {
            letter = letter || std::isalpha( static_cast<unsigned char>( c ) ) != 0;
        }
        // a MESSAGE fragment: two words or more (a single quoted word is a value or a name, read as words by the ranked answer)
        if( inner.size() >= kForLiteralMinQuoted && letter && inner.find_first_not_of( " \t" ) == 0 && inner.back() != ' '
            && inner.find( ' ' ) != std::string_view::npos )
        {
            return std::string( inner );
        }
        open = close;
    }
    return std::nullopt;
}

// the task's whitespace-separated words, in order
inline std::vector<std::string_view> taskWords( std::string_view task )
{
    std::vector<std::string_view> out;
    for( std::size_t i = 0; i < task.size(); )
    {
        const std::size_t a = task.find_first_not_of( " \t", i );
        if( a == std::string_view::npos )
        {
            break;
        }
        const std::size_t b = std::min( task.find_first_of( " \t", a ), task.size() );
        out.push_back( task.substr( a, b - a ) );
        i = b;
    }
    return out;
}

// a word without the quotes and sentence punctuation around it (never parentheses: `f.g.h()` stays a call, dottedKeyOf refuses it)
inline std::string_view stripWordPunct( std::string_view w ) noexcept
{
    constexpr std::string_view kPunct = "\"'`,;:.!?<>[]{}";
    while( !w.empty() && kPunct.find( w.front() ) != std::string_view::npos )
    {
        w.remove_prefix( 1 );
    }
    while( !w.empty() && kPunct.find( w.back() ) != std::string_view::npos )
    {
        w.remove_suffix( 1 );
    }
    return w;
}

inline bool wordIsOneOf( std::string_view word, std::initializer_list<std::string_view> set )
{
    std::string low( stripWordPunct( word ) );
    std::transform( low.begin(), low.end(), low.begin(), []( unsigned char c ) { return static_cast<char>( std::tolower( c ) ); } );
    return std::find( set.begin(), set.end(), std::string_view( low ) ) != set.end();
}

inline bool isSettingCue( std::string_view w )
{
    return wordIsOneOf( w, { "setting", "settings", "option", "options", "key", "keys", "command", "commands", "flag", "flags" } );
}

inline bool isMessageCue( std::string_view w )
{
    return wordIsOneOf( w, { "error", "errors", "notification", "notifications", "message", "messages" } );
}

// a key's last segment that says the dotted word is a file or a host: every extension the linter table knows (langOfPath), the data and
// doc files it does not, and the common host suffixes
inline bool isFileOrHostSuffix( std::string_view lastSegment )
{
    if( langOfPath( "x." + std::string( lastSegment ) ) != Lang::Unknown )
    {
        return true;
    }
    return wordIsOneOf( lastSegment, { "json", "jsonc", "toml", "yaml", "yml", "md", "txt", "html", "css", "xml", "ini", "cfg", "conf", "lock", "log", "csv", "com", "org", "net", "io" } );
}

// ALLOWLIST (SAFETY (d)1): segments of letters, digits, `_` and `-` that open with a letter or `_`, no `-` at a segment's end. Returns the
// segment count, 0 when the word is not of that shape
inline std::size_t keySegments( std::string_view w ) noexcept
{
    std::size_t segments = 0;
    for( std::size_t at = 0; at <= w.size(); ++segments )
    {
        const std::size_t end = std::min( w.find( '.', at ), w.size() );
        const std::string_view seg = w.substr( at, end - at );
        if( seg.empty() || !( std::isalpha( static_cast<unsigned char>( seg[0] ) ) != 0 || seg[0] == '_' ) || seg.back() == '-' )
        {
            return 0;
        }
        for( const char c : seg )
        {
            if( std::isalnum( static_cast<unsigned char>( c ) ) == 0 && c != '_' && c != '-' )
            {
                return 0;
            }
        }
        at = end + 1;
    }
    return segments;
}

// the first dotted key of the task's words, or none
inline std::optional<std::string> dottedKeyOf( const std::vector<std::string_view>& words )
{
    const bool cue = std::any_of( words.begin(), words.end(), []( std::string_view w ) { return isSettingCue( w ); } );
    for( const std::string_view raw : words )
    {
        const std::string_view w = stripWordPunct( raw );
        const std::size_t      n = keySegments( w );
        if( n < 2 || w.size() < kForLiteralMinKeyBytes || isFileOrHostSuffix( w.substr( w.rfind( '.' ) + 1 ) )
            || w.starts_with( "self." ) || w.starts_with( "this." ) )
        {
            continue;
        }
        const bool classShaped = std::isupper( static_cast<unsigned char>( w[0] ) ) != 0;
        if( cue || ( n >= 3 && !classShaped ) )
        {
            return std::string( w );
        }
    }
    return std::nullopt;
}

// the first ` or ' delimited span of 3+ words with a message cue outside it. A ' only opens after a space or the start and only closes
// before one or the end (`wasn't` is no quote)
inline std::optional<std::string> quotedMessageOf( std::string_view task )
{
    const auto spanOf = [ & ]( char q ) -> std::optional<std::string_view>
    {
        for( std::size_t a = task.find( q ); a != std::string_view::npos; a = task.find( q, a + 1 ) )
        {
            if( q == '\'' && a > 0 && task[a - 1] != ' ' )
            {
                continue;
            }
            std::size_t b = task.find( q, a + 1 );
            while( q == '\'' && b != std::string_view::npos && b + 1 < task.size() && task[b + 1] != ' ' && std::isalnum( static_cast<unsigned char>( task[b + 1] ) ) != 0 )
            {
                b = task.find( q, b + 1 );
            }
            if( b == std::string_view::npos )
            {
                return std::nullopt;
            }
            return task.substr( a, b - a + 1 );
        }
        return std::nullopt;
    };
    for( const char q : { '`', '\'' } )
    {
        const std::optional<std::string_view> span = spanOf( q );
        if( !span )
        {
            continue;
        }
        const std::string_view inner = span->substr( 1, span->size() - 2 );
        if( taskWords( inner ).size() < kForLiteralMessageWords )
        {
            continue;
        }
        const std::size_t at = std::size_t( span->data() - task.data() );
        const std::string outside = std::string( task.substr( 0, at ) ) + " " + std::string( task.substr( at + span->size() ) );
        for( const std::string_view w : taskWords( outside ) )
        {
            if( isMessageCue( w ) )
            {
                return std::string( inner );
            }
        }
    }
    return std::nullopt;
}

// the whole task minus its leading or trailing cue words, when that is 3+ plain words: a stored subject is `<message> <cue>`. Refused:
// a task that opens with a question or a verb's own lead word, or holds code punctuation
inline std::optional<std::string> bareMessageOf( std::vector<std::string_view> words )
{
    bool cue = false;
    while( !words.empty() && isMessageCue( words.back() ) )
    {
        words.pop_back();
        cue = true;
    }
    while( !words.empty() && isMessageCue( words.front() ) )
    {
        words.erase( words.begin() );
        cue = true;
    }
    if( !cue || words.size() < kForLiteralMessageWords
        || wordIsOneOf( words.front(), { "where", "which", "what", "who", "why", "when", "how", "does", "do", "is", "path", "callers", "common", "lowest", "call", "trace", "thread" } ) )
    {
        return std::nullopt;
    }
    std::string out;
    for( const std::string_view w : words )
    {
        if( w.find_first_of( "(){}=;`" ) != std::string_view::npos )
        {
            return std::nullopt;
        }
        out += out.empty() ? "" : " ";
        out += w;
    }
    return out;
}
}   // namespace lit_detail

// The tries of a message, in order, at most kForLiteralMessageTries: the whole text, then the longest word run free of placeholders and
// dotted or path words (`asyncio.run`, `{}`, `%s`), that run and its end-anchored fragments, longest first, down to 3 words. A source
// message is usually split by a placeholder the task does not spell, so the fragment may be anchored at either end.
inline std::vector<std::string> forMessageTries( std::string_view message )
{
    const std::vector<std::string_view> words = lit_detail::taskWords( message );
    std::vector<std::string>            out{ std::string( message ) };
    std::size_t bestAt = 0, bestLen = 0;
    for( std::size_t i = 0; i < words.size(); )
    {
        std::size_t j = i;
        const auto  plain = [ & ]( std::string_view w ) { return lit_detail::stripWordPunct( w ).find_first_of( ".:/\\%{}$" ) == std::string_view::npos; };
        while( j < words.size() && plain( words[j] ) )
        {
            ++j;
        }
        if( j - i > bestLen )
        {
            bestAt  = i;
            bestLen = j - i;
        }
        i = j == i ? i + 1 : j;
    }
    const auto joined = [ & ]( std::size_t at, std::size_t n )
    {
        const char* const b = words[at].data();
        const char* const e = words[at + n - 1].data() + words[at + n - 1].size();
        return std::string( lit_detail::stripWordPunct( std::string_view( b, std::size_t( e - b ) ) ) );
    };
    const auto addTry = [ & ]( std::string t )
    {
        if( out.size() < kForLiteralMessageTries && std::find( out.begin(), out.end(), t ) == out.end() )
        {
            out.push_back( std::move( t ) );
        }
    };
    for( std::size_t n = bestLen; n >= kForLiteralMessageWords; --n )
    {
        addTry( joined( bestAt, n ) );
        addTry( joined( bestAt + bestLen - n, n ) );
    }
    return out;
}

// The literal the task names, or none. Quoted spans first (the task's own quoting is the strongest evidence), then the first
// CONST_SHAPED word (trailing/leading punctuation stripped), then a dotted key, then a message.
inline std::optional<ForLiteral> forLiteralOf( std::string_view task )
{
    if( std::optional<std::string> s = lit_detail::quotedSpan( task, '"' ) )
    {
        return ForLiteral{ std::move( *s ), "quoted" };
    }
    std::size_t i = 0;
    while( i < task.size() )
    {
        while( i < task.size() && ( task[i] == ' ' || task[i] == '\t' ) )
        {
            ++i;
        }
        std::size_t j = i;
        while( j < task.size() && task[j] != ' ' && task[j] != '\t' )
        {
            ++j;
        }
        std::string_view w = task.substr( i, j - i );
        while( !w.empty() && std::string_view( "$(['{<,;:.!?)]}>'`" ).find( w.front() ) != std::string_view::npos )
        {
            w.remove_prefix( 1 );
        }
        while( !w.empty() && std::string_view( "(['{<,;:.!?)]}>'`" ).find( w.back() ) != std::string_view::npos )
        {
            w.remove_suffix( 1 );
        }
        if( lit_detail::isConstShaped( w ) )
        {
            return ForLiteral{ std::string( w ), "const" };
        }
        i = j;
    }
    const std::vector<std::string_view> words = lit_detail::taskWords( task );
    if( std::optional<std::string> key = lit_detail::dottedKeyOf( words ) )
    {
        return ForLiteral{ std::move( *key ), "dotted" };
    }
    if( std::optional<std::string> m = lit_detail::quotedMessageOf( task ) )
    {
        return ForLiteral{ std::move( *m ), "message" };
    }
    if( std::optional<std::string> m = lit_detail::bareMessageOf( words ) )
    {
        return ForLiteral{ std::move( *m ), "message" };
    }
    return std::nullopt;
}

struct ForLiteralRender
{
    std::string xml;          // "" = nothing rides
    std::size_t sites = 0;    // src= (source code + string + unclassified sites)
    std::size_t bodies = 0;   // <b>/<x> elements served
};

namespace lit_detail
{
struct Site
{
    GrepRawHit raw;
    char       k = '?';   // 's' string, 'c' code, '?' unclassified
    bool       quotedKey = false;   // shape=dotted: quotes delimit the key on both sides (`'files.autoSave'`), not a mention inside a sentence
};

// shape=dotted: where a hit of a key of `n` bytes at `at` of `text` stands. longer: inside a longer name or a child key (an identifier byte
// on either side, or `.` plus an identifier byte after it); `config.a.b` keeps a.b whole, a prefix is how a context key spells it.
struct KeyHit
{
    bool longer = false;
    bool quoted = false;
};
inline KeyHit keyHitAt( std::string_view text, std::size_t at, std::size_t n ) noexcept
{
    const auto ident = []( char c ) { return std::isalnum( static_cast<unsigned char>( c ) ) != 0 || c == '_' || c == '-'; };
    const auto quote = []( char c ) { return c == '"' || c == '\'' || c == '`'; };
    const char before = at > 0 ? text[at - 1] : ' ';
    const char after  = at + n < text.size() ? text[at + n] : ' ';
    const char after2 = at + n + 1 < text.size() ? text[at + n + 1] : ' ';
    return KeyHit{ ident( before ) || ident( after ) || ( after == '.' && ident( after2 ) ), quote( before ) && quote( after ) };
}

// text-line helpers for the docstring position test: the previous line of the one starting at `ls` (its start moves back to that
// line's start), trimmed of '\r'; false at the top of the file
inline bool prevLine( const std::string& text, std::size_t& ls, std::string_view& line ) noexcept
{
    if( ls == 0 )
    {
        return false;
    }
    const std::size_t nl = ls - 1;   // text[nl] == '\n'
    const std::size_t r  = nl == 0 ? std::string::npos : text.rfind( '\n', nl - 1 );
    const std::size_t pb = r == std::string::npos ? 0 : r + 1;
    line                 = std::string_view( text ).substr( pb, nl - pb );
    if( !line.empty() && line.back() == '\r' )
    {
        line.remove_suffix( 1 );
    }
    ls = pb;
    return true;
}

// the previous line that holds code (not blank, not a whole-line # comment)
inline bool prevCodeLine( const std::string& text, std::size_t& ls, std::string_view& line ) noexcept
{
    while( prevLine( text, ls, line ) )
    {
        const std::string_view t = lintdetail::ltrim( line );
        if( !t.empty() && t.front() != '#' )
        {
            return true;
        }
    }
    return false;
}

// step back through code lines until one is indented LESS than `limit` (at most 200 lines); false when the top of the file comes first
inline bool climbBelow( const std::string& text, std::size_t& pos, std::string_view& line, std::size_t limit ) noexcept
{
    for( std::size_t steps = 0; lintdetail::indentOf( line ) >= limit; ++steps )
    {
        if( steps >= 200 || !prevCodeLine( text, pos, line ) )
        {
            return false;
        }
    }
    return true;
}

// `start` opens a (r/b/u-prefixed) triple-quoted string that is the first thing on its line: ls = that line's start, ind = its indent
inline bool opensTripleQuoteLine( const std::string& text, std::size_t start, std::size_t& ls, std::size_t& ind ) noexcept
{
    if( start >= text.size() )
    {
        return false;
    }
    for( ls = start; ls > 0 && text[ls - 1] != '\n'; --ls )
    {
    }
    const std::size_t fs = ls + lintdetail::indentOf( std::string_view( text ).substr( ls, start - ls ) );
    ind                  = fs - ls;
    return start - fs <= 2 && pythonDocstringQuote( std::string_view( text ).substr( fs, 8 ) ).size() == 3;
}

// a code line that ends a statement header: a trailing ':' (a trailing # comment aside)
inline bool endsWithColon( std::string_view line ) noexcept
{
    // the whole-line form keeps `def f(x="#"):` a header (its '#' is inside a string); only a def/class header line takes it, so a
    // trailing comment that ends in a colon (`x = x + 1  # note:`) is no header (train 42b, rv-mf1-lit-delta N2)
    const std::string_view lead = line.substr( std::min( line.find_first_not_of( " \t" ), line.size() ) );
    const bool header = lead.starts_with( "def " ) || lead.starts_with( "async def " ) || lead.starts_with( "class " );
    return lintdetail::rtrim( line.substr( 0, line.rfind( '#' ) ) ).ends_with( ':' ) || ( header && lintdetail::rtrim( line ).ends_with( ':' ) );
}

// A Python DOCSTRING: a triple-quoted string statement that is the FIRST statement of a module, class or def body — the line
// before it (comments and blank lines aside) closes a `def` / `async def` / `class` header with a ':' (a signature may span lines),
// or there is none (the top of the module). The same string opening a call-argument line (`raise E(\n """msg""")`), sitting in an
// `if` body or following other statements is a string SITE: the parse says String, this decides whether it is documentation. The
// caller applies it to Python only (langFacts leadingDocstring); another language's triple quote is a raw string, its comments
// are the parse's own Comment tier.
inline bool isPythonDocstringAt( const std::string& text, std::size_t start ) noexcept
{
    std::size_t ls = 0, ind = 0;
    if( !opensTripleQuoteLine( text, start, ls, ind ) )
    {
        return false;   // not the first thing on its line, or not a triple-quoted string
    }
    std::size_t      pos = ls;
    std::string_view line;
    if( !prevCodeLine( text, pos, line ) )
    {
        return true;   // nothing but comments before it: the module docstring
    }
    // the header's first line: the nearest code line indented LESS than the string (a multi-line signature closes with `) -> T:` at
    // the def's own indent; its parameters sit deeper or at the string's indent)
    if( !endsWithColon( line ) || !climbBelow( text, pos, line, ind ) )
    {
        return false;
    }
    std::string_view t = lintdetail::ltrim( line );
    if( !t.empty() && std::string_view( ")]}" ).find( t[0] ) != std::string_view::npos )   // `) -> None:` — on to the line that opened it
    {
        const std::size_t closeIndent = lintdetail::indentOf( line );
        if( !prevCodeLine( text, pos, line ) || !climbBelow( text, pos, line, closeIndent + 1 ) )
        {
            return false;
        }
        t = lintdetail::ltrim( line );
    }
    return t.starts_with( "def " ) || t.starts_with( "async def " ) || t.starts_with( "class " );
}

using LineRange = std::pair<std::uint32_t, std::uint32_t>;   // inclusive, 1-based

// the excerpt of a body: its signature line `first` plus a window [site-before, site+after] per site line, clipped to
// [first, last], overlapping or touching windows merged; ascending and disjoint
inline std::vector<LineRange> excerptRanges( const std::vector<std::uint32_t>& siteLines, std::uint32_t first, std::uint32_t last )
{
    std::vector<LineRange> w{ LineRange{ first, first } };
    for( const std::uint32_t l : siteLines )
    {
        const std::uint32_t a = std::max( first, l > kForLiteralExcerptBefore ? l - kForLiteralExcerptBefore : 1u );
        const std::uint32_t b = std::min( last, l + kForLiteralExcerptAfter );
        if( a <= b )
        {
            w.push_back( LineRange{ a, b } );
        }
    }
    std::sort( w.begin(), w.end() );
    std::vector<LineRange> merged;
    for( const LineRange& r : w )
    {
        if( !merged.empty() && r.first <= merged.back().second + 1 )
        {
            merged.back().second = std::max( merged.back().second, r.second );
        }
        else
        {
            merged.push_back( r );
        }
    }
    return merged;
}

// the lines of every range of `text`, each range newline-joined (the grep verb's own slicing core, search.h grepLineRangeText),
// the ranges joined by a line holding one ellipsis
inline std::string linesOfRanges( const std::string& text, const std::vector<LineRange>& ranges )
{
    std::vector<std::size_t> starts{ 0 };
    for( std::size_t i = 0; i < text.size(); ++i )
    {
        if( text[i] == '\n' )
        {
            starts.push_back( i + 1 );
        }
    }
    const std::uint32_t count = grepRealLineCount( text, starts );
    std::string         out;
    for( const LineRange& r : ranges )
    {
        const std::uint32_t b = std::min( r.second, count );
        if( r.first < 1 || r.first > b )
        {
            continue;
        }
        out += out.empty() ? std::string_view() : std::string_view( "\n\xE2\x80\xA6\n" );
        out += grepLineRangeText( text, starts, count, r.first, b );
    }
    return out;
}

// cut every line of `lines` longer than `cap` bytes on a UTF-8 boundary (an ellipsis marks the cut); true when one was cut
inline bool capLineBytes( std::string& lines, std::size_t cap )
{
    if( lines.size() <= cap )
    {
        return false;
    }
    std::string out;
    bool        cut = false;
    for( std::size_t at = 0; at <= lines.size(); )
    {
        const std::size_t end  = std::min( lines.find( '\n', at ), lines.size() );
        std::string       line = lines.substr( at, end - at );
        cut                    = cut || line.size() > cap;
        truncateUtf8WithEllipsis( line, cap );
        out += line;
        out += end < lines.size() ? "\n" : "";
        at = end + 1;
    }
    if( cut )
    {
        lines = std::move( out );
    }
    return cut;
}

inline std::string rangesAttr( const std::vector<LineRange>& ranges )
{
    std::string out;
    for( const LineRange& r : ranges )
    {
        out += out.empty() ? "" : ",";
        out += std::to_string( r.first );
        if( r.second > r.first )
        {
            out += "-" + std::to_string( r.second );
        }
    }
    return out;
}
// <x> for the body [first, last] of `s` in `text`: the signature line and one window per site line (l= lists the ranges, of= the body,
// next= the whole body)
inline std::string excerptElement( const std::string& text, const std::string& path, const Symbol& s, std::uint32_t first, std::uint32_t last,
                                   const std::vector<std::uint32_t>& siteLines, RedactCounts* redact )
{
    std::vector<char>      esc;
    const std::vector<LineRange> ranges = excerptRanges( siteLines, first, last );
    std::string x = "<x p=\"";
    x += escapeXml( path, esc );
    x += "\" n=\"";
    x += escapeXml( s.name, esc );
    x += "\" l=\"" + rangesAttr( ranges ) + "\" of=\"" + std::to_string( first ) + "-" + std::to_string( last ) + "\"";
    // train 42b T-3: each window line is cut at kForLiteralLineBytes like an <ls> row (a minified one-line body printed 48.9 KB
    // whole); cut="1" says a line was cut, next= prints the whole body
    std::string lines = linesOfRanges( text, ranges );
    redactInPlace( lines, redact );   // CR 4423843223: a window of raw source is a body-emission seam; redact BEFORE the cut so a key is never half-cut
    const bool  cut   = capLineBytes( lines, kForLiteralLineBytes );
    x += cut ? " cut=\"1\"" : "";
    x += nextAttrXml( nextFlag( "--expand=", path + ":" + std::to_string( s.line ) + ":" + s.name ) );
    x += "><![CDATA[";
    appendCdataSafe( lines, x );
    x += "]]></x>";
    return x;
}
}   // namespace lit_detail

// THE BLOCK. `served` = the answer's own bytes after <sigs> (bodies, fold, slot, hops): a body whose <b … l= p= n=> head is in it
// is not printed again. `useMemo` = the span-tier memo (false under --no-cache). `compactLegend` = the default --legend=compact dialect.
inline ForLiteralRender renderForLiteral( const IngestResult& ing, const ForLiteral& lit, std::string_view rootArg, std::string_view served,
                                          RedactCounts* redact, bool useMemo, bool compactLegend )
{
    ForLiteralRender out;
    if( lit.text.empty() || ing.files.empty() )
    {
        return out;
    }
    const GrepCollection collected = grepCollect( ing, lit.text, /*regex=*/false, /*noPrefilter=*/false );
    if( collected.raw.empty() )
    {
        return out;   // nothing found: no claim (a partial index cannot prove the literal unused)
    }
    const std::string rootPrefix = rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( rootArg );
    const auto relPath = [ & ]( std::uint32_t f ) -> std::string
    {
        return rootArg.empty() ? std::string( ing.files[f] ) : std::string( rw::sarif::rootRelativeUri( ing.files[f], rootPrefix ) );
    };
    // ── path tiers, then the span tier of every source hit file (bounded, in the scan's order: classified files first) ─────────
    const bool  dotted  = lit.shape == "dotted";
    const bool  message = lit.shape == "message";
    std::uint32_t loadedFile = UINT32_MAX;
    std::string   loadedText;
    const auto loadFile = [ & ]( std::uint32_t fileId )
    {
        if( loadedFile != fileId )
        {
            loadedFile = fileId;
            loadedText = docparse::detail::readWholeFile( diskPath( ing, fileId ) ).value_or( std::string() );
        }
    };
    std::size_t testHits = 0, docHits = 0, commentHits = 0, longerHits = 0;
    std::vector<lit_detail::Site> src;
    std::vector<std::uint32_t>    srcFiles;
    for( const GrepRawHit& r : collected.raw )
    {
        const std::string_view p = rootRelPath( ing, r.fileId );
        const PathTier         t = pathTierOf( p );
        if( t == PathTier::TestOrBench )
        {
            ++testHits;
        }
        else if( t == PathTier::Doc || isBareWordCodePath( p ) )
        {
            ++docHits;
        }
        else
        {
            lit_detail::KeyHit keyHit;
            if( dotted )
            {
                loadFile( r.fileId );
                keyHit = lit_detail::keyHitAt( loadedText, r.byteOffset, lit.text.size() );
                if( keyHit.longer )
                {
                    ++longerHits;
                    continue;
                }
            }
            if( srcFiles.empty() || srcFiles.back() != r.fileId )
            {
                srcFiles.push_back( r.fileId );
            }
            src.push_back( lit_detail::Site{ r, '?', keyHit.quoted } );
        }
    }
    std::vector<std::string> tierPaths;
    for( std::size_t i = 0; i < srcFiles.size() && i < kForLiteralTierFiles; ++i )
    {
        tierPaths.push_back( diskPath( ing, srcFiles[i] ) );
    }
    const SpanTierBatch batch = spanTiersOfFiles( std::span<const std::string>( tierPaths ), useMemo );
    std::vector<lit_detail::Site> rows;
    bool anyUnclassified = false;   // CR (train 42b harvest): a source site the span tier never saw is invisible to comment=, which is then a floor
    for( lit_detail::Site& s : src )
    {
        std::size_t idx = SIZE_MAX;
        for( std::size_t i = 0; i < tierPaths.size(); ++i )
        {
            if( srcFiles[i] == s.raw.fileId )
            {
                idx = i;
                break;
            }
        }
        if( idx != SIZE_MAX && idx < batch.perFile.size() && batch.perFile[idx].isParsed )
        {
            const SpanTierMap& m = batch.perFile[idx];
            const SpanTier     t = spanTierAt( m, s.raw.byteOffset );
            if( t == SpanTier::Comment )
            {
                ++commentHits;
                continue;
            }
            if( t == SpanTier::String && langFacts( langOfPath( ing.files[s.raw.fileId] ) ).leadingDocstring )
            {
                // a Python docstring (the first statement of a module / class / def body): documentation, counted with the comments
                const auto        it    = std::upper_bound( m.startByte.begin(), m.startByte.end(), s.raw.byteOffset );
                const std::size_t start = it == m.startByte.begin() ? 0 : m.startByte[std::size_t( it - m.startByte.begin() ) - 1];
                loadFile( s.raw.fileId );
                if( lit_detail::isPythonDocstringAt( loadedText, start ) )
                {
                    ++commentHits;
                    continue;
                }
            }
            s.k = t == SpanTier::String ? 's' : 'c';
        }
        else
        {
            anyUnclassified = true;   // past kForLiteralTierFiles, or a file the span tier did not parse: k="?"
        }
        rows.push_back( s );
    }
    // one row per source LINE (a line holding the literal twice is one site), enriched for its owner, then ordered: sites inside a
    // function or method first, string before code before unclassified, the scan's own order within each class
    std::vector<GrepRawHit> all;
    {
        std::vector<lit_detail::Site> lines;
        for( const lit_detail::Site& r : rows )
        {
            if( lines.empty() || lines.back().raw.fileId != r.raw.fileId || lines.back().raw.line != r.raw.line )
            {
                lines.push_back( r );
            }
            else if( r.k == 's' )
            {
                lines.back().k = 's';
            }
            if( lines.back().raw.fileId == r.raw.fileId && lines.back().raw.line == r.raw.line )
            {
                lines.back().quotedKey = lines.back().quotedKey || r.quotedKey;
            }
        }
        rows = std::move( lines );
    }
    out.sites = rows.size();
    if( rows.empty() )
    {
        return out;   // no source site: nothing to anchor on (test/doc/comment counts alone answer nothing; measured as noise, ld2-django-09)
    }
    if( message && std::none_of( rows.begin(), rows.end(), []( const lit_detail::Site& r ) { return r.k != 'c'; } ) )
    {
        out.sites = 0;
        return out;   // a task's words met only outside a string are no message
    }
    const std::size_t ranked = std::min( rows.size(), kForLiteralRankedRows );
    for( std::size_t i = 0; i < ranked; ++i )
    {
        all.push_back( rows[i].raw );
    }
    std::vector<GrepHit> enriched = grepEnrich( ing, std::span<const GrepRawHit>( all ) );
    ASSUME( enriched.size() == all.size(), "grepEnrich returns one row per windowed hit" );
    std::vector<std::size_t> order( enriched.size() );
    for( std::size_t i = 0; i < order.size(); ++i )
    {
        order[i] = i;
    }
    const auto rankOf = [ & ]( std::size_t i )
    {
        const bool callable = enriched[i].enclosingId != kNoNode && ReceiverEvidence::callableKind( ing.symbols[enriched[i].enclosingId].kind );
        return ( dotted && !rows[i].quotedKey ? 6 : 0 ) + ( callable ? 0 : 3 ) + ( rows[i].k == 's' ? 0 : ( rows[i].k == 'c' ? 1 : 2 ) );
    };
    std::stable_sort( order.begin(), order.end(), [ & ]( std::size_t a, std::size_t b ) { return rankOf( a ) < rankOf( b ); } );
    const std::size_t shown = std::min( order.size(), kForLiteralSiteRows );
    std::vector<GrepHit>          hits;
    std::vector<lit_detail::Site> shownRows;
    for( std::size_t i = 0; i < shown; ++i )
    {
        hits.push_back( std::move( enriched[order[i]] ) );
        shownRows.push_back( rows[order[i]] );
    }
    rows = std::move( shownRows );

    // ── the owner bodies: distinct callable owners of the shown rows, in row order ───────────────────────────────────────────
    std::vector<char>   esc;
    std::vector<NodeId> owners;
    std::vector<char>   ownerAbove;   // parallel: 1 = already printed by the answer, 2 = body held by the kForLiteralBodies cap, 0 = otherwise
    std::string         bodiesXml;
    for( const GrepHit& h : hits )
    {
        if( h.enclosingId == kNoNode || !ReceiverEvidence::callableKind( ing.symbols[h.enclosingId].kind )
            || std::find( owners.begin(), owners.end(), h.enclosingId ) != owners.end() )
        {
            continue;
        }
        const Symbol&     s    = ing.symbols[h.enclosingId];
        const std::string path = relPath( s.fileId );
        std::string head = " l=\"" + std::to_string( s.line ) + "\" p=\"";
        head += escapeXml( path, esc );
        head += "\" n=\"";
        head += escapeXml( s.name, esc );
        head += "\"";
        const bool above = served.find( head ) != std::string_view::npos;
        owners.push_back( h.enclosingId );
        ownerAbove.push_back( above ? 1 : ( out.bodies >= kForLiteralBodies ? 2 : 0 ) );
        if( above || out.bodies >= kForLiteralBodies )
        {
            continue;
        }
        const std::string text = docparse::detail::readWholeFile( diskPath( ing, s.fileId ) ).value_or( std::string() );
        if( text.empty() )
        {
            continue;
        }
        const std::uint32_t first = layout::lineOf( text, s.sigStartByte );
        const std::uint32_t last  = layout::lineOf( text, s.endByte > 0 ? s.endByte - 1 : 0 );
        if( last >= first && last - first < kForLiteralWholeBodyLines )   // a short body is served whole (nothing to leave out)
        {
            std::optional<std::string> body = renderBodyElement( ing, h.enclosingId, /*capBytes=*/0, /*compress=*/false, redact, rootArg, nullptr );
            if( body && body->size() <= kForLiteralBodyCapBytes )
            {
                bodiesXml += *body;
                ++out.bodies;
                continue;
            }
        }
        // an excerpt of a longer body: its signature line and one window per shown site this owner holds (never the span between)
        std::vector<std::uint32_t> siteLines;
        for( const GrepHit& o : hits )
        {
            if( o.enclosingId == h.enclosingId )
            {
                siteLines.push_back( o.line );
            }
        }
        bodiesXml += lit_detail::excerptElement( text, path, s, first, last, siteLines, redact );
        ++out.bodies;
    }

    // ── the rows ──────────────────────────────────────────────────────────────────────────────────────────────────────────
    std::string rowsXml;
    std::size_t contextRows = 0;
    for( std::size_t i = 0; i < hits.size(); ++i )
    {
        const GrepHit& h = hits[i];
        rowsXml += "<ls p=\"";
        rowsXml += escapeXml( relPath( h.fileId ), esc );
        rowsXml += "\" l=\"" + std::to_string( h.line ) + "\" k=\"";
        rowsXml += rows[i].k == 's' ? "string" : ( rows[i].k == 'c' ? "code" : "?" );
        rowsXml += "\"";
        if( h.enclosingId != kNoNode )
        {
            rowsXml += " in=\"";
            rowsXml += escapeXml( h.enclosing, esc );
            rowsXml += "\" ink=\"";
            rowsXml += symTag( ing.symbols[h.enclosingId].kind );
            rowsXml += "\"";
            const auto it = std::find( owners.begin(), owners.end(), h.enclosingId );
            if( it != owners.end() && ownerAbove[std::size_t( it - owners.begin() )] != 0 )
            {
                rowsXml += ownerAbove[std::size_t( it - owners.begin() )] == 1 ? " body=\"above\"" : " body=\"held\"";
            }
        }
        std::string line = h.text;
        const std::size_t lead = line.find_first_not_of( " \t" );
        line = lead == std::string::npos ? std::string() : line.substr( lead );
        redactInPlace( line, redact );   // CR 4423843223: the matched line is raw source text; redact before the cut
        truncateUtf8WithEllipsis( line, kForLiteralLineBytes );
        const bool callableOwner = h.enclosingId != kNoNode && ReceiverEvidence::callableKind( ing.symbols[h.enclosingId].kind );
        if( rows[i].k == 's' && !callableOwner && contextRows < kForLiteralContextRows )
        {
            // a string site outside any function (a table entry, an error-code map): the lines after it hold what it builds
            const std::string text = docparse::detail::readWholeFile( diskPath( ing, h.fileId ) ).value_or( std::string() );
            const std::uint32_t lastLine = text.empty() ? h.line : layout::lineOf( text, text.size() - 1 );
            const std::uint32_t b = std::min( h.line + kForLiteralContextLines, lastLine );
            if( !text.empty() && b > h.line )
            {
                line = lit_detail::linesOfRanges( text, { lit_detail::LineRange{ h.line, b } } );
                redactInPlace( line, redact );   // CR 4423843223: the lines after a table entry are raw source text too
                truncateUtf8WithEllipsis( line, kForLiteralLineBytes * ( kForLiteralContextLines + 1 ) );
                rowsXml += " lines=\"" + std::to_string( h.line ) + "-" + std::to_string( b ) + "\"";
                ++contextRows;
            }
        }
        rowsXml += "><![CDATA[";
        appendCdataSafe( line, rowsXml );
        rowsXml += "]]></ls>";
    }

    std::string& x = out.xml;
    x = compactLegend ? std::string( kForCompactLiteralLegend ) : std::string( kForLiteralLegend );
    x += dotted || message ? kForLiteralKeyLegend : std::string_view();
    x += "<lit s=\"";
    x += escapeXml( lit.text, esc );
    x += "\" shape=\"";
    x += lit.shape;
    x += "\" hits=\"" + std::to_string( collected.raw.size() ) + "\" src=\"" + std::to_string( out.sites ) + "\" shown=\""
         + std::to_string( shown ) + "\"";
    if( shown < out.sites )
    {
        x += " capped=\"1\"";
    }
    x += longerHits > 0 ? " longer=\"" + std::to_string( longerHits ) + "\"" : std::string();
    x += lit.frag ? " frag=\"1\"" : "";
    x += " comment=\"" + std::to_string( commentHits ) + "\" test=\"" + std::to_string( testHits ) + "\" doc=\"" + std::to_string( docHits ) + "\"";
    if( !collected.cleanScan() || anyUnclassified )
    {
        x += " floor=\"1\"";
    }
    x += nextAttrXml( nextFlag( "--grep=", lit.text ) );
    const std::string inner = rowsXml + bodiesXml + "</lit>";
    // bytes= is the element's own size from its open tag on (the legend comment excluded): a fixed point over its own digits
    const std::size_t openAt = x.find( "<lit " );
    const std::size_t fixed  = ( x.size() - openAt ) + std::string_view( " bytes=\"\">" ).size() + inner.size();
    std::size_t       bytes  = fixed;
    while( fixed + std::to_string( bytes ).size() != bytes )   // the digits count themselves: converges in <= 2 steps
    {
        bytes = fixed + std::to_string( bytes ).size();
    }
    x += " bytes=\"" + std::to_string( bytes ) + "\">";
    x += inner;
    ENSURES( x.size() - openAt == bytes, "bytes= is the element's own size" );
    return out;
}

// the block of the task's literal: a message walks its tries (forMessageTries) until one has a string site in source, every other shape
// has the one try
inline ForLiteralRender renderForLiteralOfTask( const IngestResult& ing, std::string_view task, std::string_view rootArg, std::string_view served,
                                                RedactCounts* redact, bool useMemo, bool compactLegend )
{
    const std::optional<ForLiteral> lit = forLiteralOf( task );
    if( !lit )
    {
        return {};
    }
    if( lit->shape != "message" )
    {
        return renderForLiteral( ing, *lit, rootArg, served, redact, useMemo, compactLegend );
    }
    for( const std::string& t : forMessageTries( lit->text ) )
    {
        ForLiteralRender r = renderForLiteral( ing, ForLiteral{ t, lit->shape, t != lit->text }, rootArg, served, redact, useMemo, compactLegend );
        if( !r.xml.empty() )
        {
            return r;
        }
    }
    return {};
}
}   // namespace rw
