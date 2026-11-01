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
//     allowlist (forliteral.h dottedKeysOf): identifier segments only; never a file name or host (a leading dot, a file or host suffix,
//     the name of an indexed file), a `self.`/`this.` chain or a call; a capitalised first segment (Class.method) only with a cue.
//     Rows hold the key: a site inside a longer name or a child key is counted in longer=, never a row (a dotted prefix before it is
//     kept: `config.a.b`). Sites the quotes delimit rank above mentions, and kForLiteralRegistrationRows slots are kept for a quoted
//     site outside any function (a registration), whatever the reader count. A row cut at 200 bytes opens near the key.
//   * shape="message": 3+ words with a whole word error/notification/message: a backticked or single-quoted span (cue outside it),
//     else the task minus a leading or trailing cue, else the words before a cue inside the sentence. Tries: the whole text, then
//     fragments of the longest placeholder-free word run, down to 3 words (frag="1": s= is only part of the task's words); a
//     FRAGMENT with fewer than kForLiteralMessageContent words that are not function words is dropped, the whole text needs one and
//     must end in it (`must not be empty` passes, `the value of the` does not); the rest are ordered by that count.
//     Hits stand on word edges (a hit inside a longer word is counted in longer=; the letter of an escape, `\n`, or of a printf
//     verb, `%s`, right before the hit is no word byte). A code row (k=code) is never printed; a k=? row stays.
// Literals are tried in order (forLiteralCandidates: quoted span, CONST words, dotted keys, message), kForLiteralCandidates scans, until
// one has a source site; try="N" says it was the task's Nth. Literals past the cap are not scanned: when none of the scanned ones
// anchors, <lit_capped scanned= skipped= next=> says so (a task of five keys no longer reads as five misses).
//
// TABLE-CONST V2. Last of all, only when no earlier literal has a site, shape="table": the sites of the identifiers a task about a table
// or a registration names, the question a ranked answer cannot print because the table holds no edge (a Go map entry, a Rust macro row, a C
// X-macro line). Trigger (forTableCueOf), whole words: a registration, table or compile-time word; "add a new", the exemplar form, whose
// anchor is the named sibling; or default/handler, which print only when a table row exists. Anchors (forTableAnchorsOf): backticked
// spans first, then identifier-shaped words (snake_case, camelCase, Pascal with an inner capital, a::b, a.b), then a plain word after
// like/alongside/following; a backticked span stands as it is, any other word must be a symbol of the index (forTableAnchorKeeps), at
// most kForTableAnchors. Each anchor with a site prints one <lit>, its own row limit (kForTableRows) and all of them under one byte cap
// (kForTableByteCap, cut on a row boundary, capped=1 and next=; an anchor the cap left out is counted by <lit_capped>). A row whose line
// reads as a table row (lit_detail::tableRowOf) ranks first and carries tbl= (the line that opens the table, "item" at top level) and the
// lines after it: the members beside it. Hits stand on word edges.

#include "infra/namesplit.h" // isIdentChar
#include "filter.h"          // pathTierOf — source / test / doc, the reader's tier
#include "layout.h"          // layout::lineOf — a byte offset's line
#include "hopbody.h"         // renderBodyElement — the --expand body element, no callee rows; pythonDocstringQuote
#include "langfacts.h"       // langFacts(...).leadingDocstring — which languages have a docstring convention
#include "lintrules.h"       // kLintExtRows — the extensions of every indexed language
#include "model.h"
#include "nextverb.h"        // nextFlag / nextAttrXml
#include "receiverevidence.h"   // ReceiverEvidence::callableKind
#include "resolve.h"       // tsimport::isAssetSpecifier — an asset extension is no key segment
#include "redact.h"          // redactInPlace — raw source text is redacted before it is emitted
#include "sarif.h"           // rootPrefixOf / rootRelativeUri
#include "search.h"          // grepCollect / grepEnrich / isBareWordCodePath
#include "serialize.h"       // escapeXml / appendCdataSafe / truncateUtf8WithEllipsis

#include <algorithm>
#include <array>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <optional>
#include <span>
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
inline constexpr std::size_t kForLiteralMessageContent = 2;      // a message FRAGMENT holds at least this many words that are not function words
inline constexpr std::size_t kForLiteralWholeContent   = 1;      // the WHOLE text holds at least this many, and ends in one (`must not be empty`)
inline constexpr std::size_t kForLiteralCandidates    = 4;      // literals (quoted span, CONST words, dotted keys) a task may have scanned, in order, until one has a source site
inline constexpr std::size_t kForLiteralRegistrationRows = 2;   // shape=dotted: row slots kept for quoted sites outside any function (a registration) whatever the reader count
inline constexpr std::size_t kForLiteralFileMaxSegments = 4;    // a dotted word of this many segments or more is a key even when its last one is an extension (`envoy.filters.http.lua`)
inline constexpr std::size_t kForLiteralKeyLead       = 40;     // a cut row starts this many bytes before the key
inline constexpr std::size_t kForTableAnchors         = 3;      // shape=table: identifiers of a task scanned, in order, each with a site printing a <lit>
inline constexpr std::size_t kForTableRows            = 32;     // shape=table: <ls> rows per anchor (next= lists all)
inline constexpr std::size_t kForTableByteCap         = 40000;  // shape=table: all its <lit> elements together, cut on a row boundary (runaway guard: a 16 KB cap loses ld-nushell-07)
inline constexpr std::size_t kForTableElementBytes    = 800;    // shape=table: what an element's open tag and legend may add to its rows and bodies; an anchor is not tried with less than this left
inline constexpr std::size_t kForTableRankedRows      = 4096;   // shape=table: source sites read for a table row and ordered (a registry past the readers in path order must still rank first)
inline constexpr std::size_t kForTableContextRows     = 4;      // shape=table: table rows served with the lines after them
inline constexpr std::size_t kForTableSiblingLines    = 24;     // a sibling row of a table row is looked for this many lines away (an entry may span lines)
inline constexpr std::size_t kForTableOpenerLines     = 2000;   // the line that opens a table is looked for this many lines above a row
inline constexpr std::size_t kForTableOpenerBytes     = 80;     // tbl= text
inline constexpr std::size_t kForTableMinAnchor       = 3;      // a shorter word is no anchor
inline constexpr std::size_t kForTableMaxAnchor       = 60;     // a longer backticked span is no anchor

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
    "word): rows hold the key (a dotted prefix may stand before it), quoted sites first, up to two row slots kept for a quoted string "
    "site outside any function (a registration or table the parse classified as a string; a C #define is not one); longer= source "
    "sites inside a longer name, child key or word, counted, never rows. shape=message the task's words as a "
    "message (3 or more, with an error, notification or message word): never a code row; frag=1: the whole text has no site, s= is "
    "the part that does. try=N: the task's Nth literal anchored; the ones before it had no source site or were not scanned. -->";
static_assert( kForLiteralKeyLegend.find( "--", 4 ) == kForLiteralKeyLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );
// the walk's cap, printed alone (no <lit>) when the task names more literals than kForLiteralCandidates scans and none of those anchored
inline constexpr std::string_view kForLiteralCapLegend =
    "<!-- ripwire for lit: lit_capped = the task names more literals than one answer scans; scanned= whole-repo scans made, none found a source site; "
    "skipped= literals not scanned; next= scans the first of them; this note is not in est_tokens. -->";
static_assert( kForLiteralCapLegend.find( "--", 4 ) == kForLiteralCapLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );

// present only with shape=table (the first of its elements), so the bytes of every other fire do not move
inline constexpr std::string_view kForLiteralTableLegend =
    "<!-- ripwire for lit: shape=table a task about a table, registration or new sibling: the identifier it names, one lit per identifier, "
    "after the other shapes found no site. Table rows first: tbl= the line that opens the table (item: a top level macro or call row), lines=a-b "
    "with the lines after it. longer= source sites inside a longer word, counted, never rows. A cut on a row boundary says capped=1. -->";
static_assert( kForLiteralTableLegend.find( "--", 4 ) == kForLiteralTableLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );

inline bool forLiteralOn()
{
    return std::getenv( "RIPWIRE_NO_LITERAL_ANCHOR" ) == nullptr;
}

struct ForLiteral
{
    std::string text;
    std::string_view shape;   // "quoted" | "const" | "dotted" | "message"
    bool             frag = false;   // shape=message: `text` is a fragment of the task's words, the whole text has no site
    std::size_t      tryNo = 1;      // the task's Nth literal (earlier ones were scanned and have no source site): try="N" when > 1
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

inline constexpr std::array<std::string_view, 10> kForLiteralSettingCues{ "setting", "settings", "option", "options", "key", "keys", "command", "commands", "flag", "flags" };
inline constexpr std::array<std::string_view, 6>  kForLiteralMessageCues{ "error", "errors", "notification", "notifications", "message", "messages" };
// the data, doc, build and host words no language table or asset table holds (isFileOrHostSuffix reads those: kLintExtRows, isAssetSpecifier).
// A REFUSAL list (SAFETY (d)1): a word not here and in neither table is a segment of a key.
inline constexpr auto kForLiteralFileSuffixes = std::to_array<std::string_view>(
    { "jsonc", "json5", "mdx", "rst", "htm", "ini", "cfg", "conf", "properties", "env", "lock", "log", "tsv", "sql", "proto", "gradle", "cmake",
      "bazel", "bzl", "hcl", "tf", "tfvars", "tfstate", "plist", "pdf", "zip", "tar", "gz", "jar", "so", "vue", "scala",
      "com", "org", "net", "io", "dev", "ai", "co", "app" } );
// function words: a message or fragment of nothing but these (`the value of the`) says nothing about the code
inline constexpr auto kForLiteralStopWords = std::to_array<std::string_view>(
    { "the", "a", "an", "of", "is", "are", "was", "were", "be", "been", "to", "in", "on", "at", "for", "and", "or", "not", "no", "by", "with",
      "from", "this", "that", "it", "its", "could", "can", "cannot", "would", "should", "will", "may", "must", "do", "does", "did", "has",
      "have", "had", "as", "if", "but", "so", "then", "than", "there" } );
inline constexpr std::array<std::string_view, 17> kForLiteralLeadWords{ "where", "which", "what", "who", "why", "when", "how", "does", "do", "is", "path", "callers", "common", "lowest", "call", "trace", "thread" };

inline bool wordIsOneOf( std::string_view word, std::span<const std::string_view> set )
{
    std::string low( stripWordPunct( word ) );
    std::transform( low.begin(), low.end(), low.begin(), []( unsigned char c ) { return static_cast<char>( std::tolower( c ) ); } );
    return std::find( set.begin(), set.end(), std::string_view( low ) ) != set.end();
}

inline bool isSettingCue( std::string_view w )
{
    return wordIsOneOf( w, kForLiteralSettingCues );
}

inline bool isMessageCue( std::string_view w )
{
    return wordIsOneOf( w, kForLiteralMessageCues );
}

// a key's last segment that says the dotted word is a file or a host: an extension of kLintExtRows (every indexed language), of
// isAssetSpecifier's assets, or a word of the table above (data, doc and build files, the common host suffixes). A file the index holds is
// refused by its name in renderForLiteralOfTask, whatever its extension. dottedKeysOf applies it below kForLiteralFileMaxSegments segments only.
inline bool isFileOrHostSuffix( std::string_view lastSegment )
{
    if( wordIsOneOf( lastSegment, kForLiteralFileSuffixes ) )
    {
        return true;
    }
    std::string dotted( "." );   // `.rake`, `.astro`: an extension of lintrules.h kLintExtRows (the crawl's own table, 10 rows the first table missed)
    for( const char c : lastSegment )
    {
        dotted += static_cast<char>( std::tolower( static_cast<unsigned char>( c ) ) );
    }
    return std::any_of( std::begin( kLintExtRows ), std::end( kLintExtRows ), [ & ]( const LintExtRow& r ) { return r.ext == dotted; } )
           || tsimport::isAssetSpecifier( "x" + dotted );
}

// `.env.local`, `".terraform.lock.hcl"`: a word that opens with a dot (behind quotes or brackets) is a dotfile, never a key
inline bool opensWithDot( std::string_view raw ) noexcept
{
    const std::size_t at = raw.find_first_not_of( "\"'`(<[{" );
    return at != std::string_view::npos && raw[at] == '.';
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

// the dotted keys of the task's words, in order, those beside a setting cue word first (`workbench.action.files.save files.autoSave
// setting`: the key the cue names leads); none when there is no key
inline std::vector<std::string> dottedKeysOf( const std::vector<std::string_view>& words )
{
    const bool cue = std::any_of( words.begin(), words.end(), []( std::string_view w ) { return isSettingCue( w ); } );
    std::vector<std::string> beside, rest;
    for( std::size_t i = 0; i < words.size(); ++i )
    {
        const std::string_view w = stripWordPunct( words[i] );
        const std::size_t      n = keySegments( w );
        if( n < 2 || w.size() < kForLiteralMinKeyBytes || opensWithDot( words[i] )
            || ( n < kForLiteralFileMaxSegments && isFileOrHostSuffix( w.substr( w.rfind( '.' ) + 1 ) ) )
            || w.starts_with( "self." ) || w.starts_with( "this." ) )
        {
            continue;
        }
        const bool classShaped = std::isupper( static_cast<unsigned char>( w[0] ) ) != 0;
        const std::string key( w );
        if( !( cue || ( n >= 3 && !classShaped ) ) || std::find( beside.begin(), beside.end(), key ) != beside.end()
            || std::find( rest.begin(), rest.end(), key ) != rest.end() )
        {
            continue;
        }
        const bool near = ( i > 0 && isSettingCue( words[i - 1] ) ) || ( i + 1 < words.size() && isSettingCue( words[i + 1] ) );
        ( near ? beside : rest ).push_back( key );
    }
    beside.insert( beside.end(), rest.begin(), rest.end() );
    return beside;
}

// the first span `q` delimits, its delimiters included. A ' only opens after a space or the start and never closes before a letter or
// digit (`wasn't` is no quote)
inline std::optional<std::string_view> delimitedSpan( std::string_view task, char q )
{
    for( std::size_t a = task.find( q ); a != std::string_view::npos; a = task.find( q, a + 1 ) )
    {
        if( q == '\'' && a > 0 && task[a - 1] != ' ' )
        {
            continue;
        }
        std::size_t b = task.find( q, a + 1 );
        while( q == '\'' && b != std::string_view::npos && b + 1 < task.size() && std::isalnum( static_cast<unsigned char>( task[b + 1] ) ) != 0 )
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
}

// the first ` or ' delimited span of 3+ words with a message cue outside it
inline std::optional<std::string> quotedMessageOf( std::string_view task )
{
    for( const char q : { '`', '\'' } )
    {
        const std::optional<std::string_view> span = delimitedSpan( task, q );
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

// the whole task minus its leading or trailing cue words, else the words before a cue inside it, when that is 3+ plain words: a stored
// subject is `<message> <cue>`. Refused:
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
    if( !cue )
    {
        // a cue inside the sentence (`Command not found error for an unknown word`): the words before the first cue
        const auto at = std::find_if( words.begin(), words.end(), []( std::string_view w ) { return isMessageCue( w ); } );
        if( at != words.end() )
        {
            words.erase( at, words.end() );
            cue = true;
        }
    }
    if( !cue || words.size() < kForLiteralMessageWords
        || wordIsOneOf( words.front(), kForLiteralLeadWords ) )
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

// the words of `text` that are not function words (kForLiteralStopWords)
inline std::size_t contentWords( std::string_view text )
{
    std::size_t n = 0;
    for( const std::string_view w : lit_detail::taskWords( text ) )
    {
        n += lit_detail::wordIsOneOf( w, lit_detail::kForLiteralStopWords ) ? 0 : 1;
    }
    return n;
}

// The tries of a message, in order, at most kForLiteralMessageTries: the whole text, then the longest word run free of placeholders and
// dotted or path words (`asyncio.run`, `{}`, `%s`), that run and its end-anchored fragments, down to 3 words. A source message is
// usually split by a placeholder the task does not spell, so the fragment may be anchored at either end. A try with fewer than
// kForLiteralMessageContent words that are not function words is dropped (`the transaction is`; the whole text needs one and must end in
// it), and the rest are ordered by that count,
// the longest first among equals: a start-anchored stop-word fragment never wins over the fragment that holds the content.
inline std::vector<std::string> forMessageTries( std::string_view message )
{
    const std::vector<std::string_view> words = lit_detail::taskWords( message );
    std::vector<std::string>            all{ std::string( message ) };
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
        if( std::find( all.begin(), all.end(), t ) == all.end() )
        {
            all.push_back( std::move( t ) );
        }
    };
    for( std::size_t n = bestLen; n >= kForLiteralMessageWords; --n )
    {
        addTry( joined( bestAt, n ) );
        addTry( joined( bestAt + bestLen - n, n ) );
    }
    std::vector<std::string> out;
    for( std::size_t i = 0; i < all.size(); ++i )
    {
        // a fragment needs kForLiteralMessageContent content words; the whole text, the task's own words, needs kForLiteralWholeContent
        // and must end in a content word (`must not be empty` yes, `the value of the` no)
        const std::size_t content = contentWords( all[i] );
        const std::vector<std::string_view> tw = lit_detail::taskWords( all[i] );
        const bool        wholeOk = i == 0 && content >= kForLiteralWholeContent && !tw.empty()
                                    && !lit_detail::wordIsOneOf( tw.back(), lit_detail::kForLiteralStopWords );
        if( content >= kForLiteralMessageContent || wholeOk )
        {
            out.push_back( std::move( all[i] ) );
        }
    }
    std::stable_sort( out.begin(), out.end(), []( const std::string& a, const std::string& b ) { return contentWords( a ) > contentWords( b ); } );
    if( out.size() > kForLiteralMessageTries )
    {
        out.resize( kForLiteralMessageTries );
    }
    return out;
}

// the CONST_SHAPED words of the task, in order (trailing/leading punctuation stripped), each once
inline std::vector<std::string> constWordsOf( std::string_view task )
{
    std::vector<std::string> out;
    for( std::string_view w : lit_detail::taskWords( task ) )
    {
        while( !w.empty() && std::string_view( "$(['{<,;:.!?)]}>'`" ).find( w.front() ) != std::string_view::npos )
        {
            w.remove_prefix( 1 );
        }
        while( !w.empty() && std::string_view( "(['{<,;:.!?)]}>'`" ).find( w.back() ) != std::string_view::npos )
        {
            w.remove_suffix( 1 );
        }
        if( lit_detail::isConstShaped( w ) && std::find( out.begin(), out.end(), w ) == out.end() )   // a name repeated in the task is one scan, one slot
        {
            out.emplace_back( w );
        }
    }
    return out;
}

// The literals the task names, in the order they are tried: a quoted span (the task's own quoting is the strongest evidence), the
// CONST_SHAPED words, the dotted keys (the one beside a setting cue first), then a message. The caller scans them in order until one
// has a source site (kForLiteralCandidates scans, a message's own tries besides): the first literal with no site no longer hides the next.
inline std::vector<ForLiteral> forLiteralCandidates( std::string_view task )
{
    std::vector<ForLiteral> out;
    if( std::optional<std::string> s = lit_detail::quotedSpan( task, '"' ) )
    {
        out.push_back( ForLiteral{ std::move( *s ), "quoted" } );
    }
    for( std::string& c : constWordsOf( task ) )
    {
        out.push_back( ForLiteral{ std::move( c ), "const" } );
    }
    const std::vector<std::string_view> words = lit_detail::taskWords( task );
    for( std::string& k : lit_detail::dottedKeysOf( words ) )
    {
        out.push_back( ForLiteral{ std::move( k ), "dotted" } );
    }
    std::optional<std::string> m = lit_detail::quotedMessageOf( task );
    if( !m )
    {
        m = lit_detail::bareMessageOf( words );
    }
    if( m )
    {
        out.push_back( ForLiteral{ std::move( *m ), "message" } );
    }
    for( std::size_t i = 0; i < out.size(); ++i )
    {
        out[i].tryNo = i + 1;
    }
    return out;
}

// shape=table: which trigger a task pulled. None: no block. AnySite: a registration, table or compile-time word, or "add a new". TableRowOnly:
// default/handler, words of many tasks, so the block prints only when a site reads as a table row.
enum class TableCue : std::uint8_t
{
    None,
    AnySite,
    TableRowOnly
};

namespace lit_detail
{
inline constexpr auto kForTableRegistrationCues = std::to_array<std::string_view>(
    { "register", "registers", "registered", "registering", "registration", "registrations", "registry", "registries", "registrar", "registrars", "table", "tables",
      "compile-time" } );
inline constexpr std::array<std::string_view, 4> kForTableValueCues{ "default", "defaults", "handler", "handlers" };
inline constexpr std::array<std::string_view, 3> kForTableExemplarLeads{ "like", "alongside", "following" };

// the task with every backticked span blanked (a cue inside code quotes is code, not the task's word)
inline std::string withoutBackticks( std::string_view task )
{
    std::string out( task );
    bool inside = false;
    for( char& c : out )
    {
        const bool tick = c == '`';
        inside = tick ? !inside : inside;
        c = tick || inside ? ' ' : c;
    }
    return out;
}

// snake_case, camelCase, Pascal with an inner capital, a::b, a.b: a word nobody writes in prose. Allowlist: only these shapes anchor.
inline bool isIdentifierShaped( std::string_view w ) noexcept
{
    if( w.size() < kForTableMinAnchor || std::isalpha( static_cast<unsigned char>( w[0] ) ) == 0 )
    {
        return false;
    }
    bool underscore = false, innerCap = false, lower = false, sep = false;
    for( std::size_t i = 0; i < w.size(); ++i )
    {
        const char c = w[i];
        if( c == '.' || c == ':' )
        {
            if( i == 0 || i + 1 == w.size() || std::isalpha( static_cast<unsigned char>( w[i + 1] ) ) == 0 )
            {
                if( c == ':' && i + 1 < w.size() && w[i + 1] == ':' )
                {
                    continue;
                }
                return false;
            }
            sep = true;
            continue;
        }
        if( !namesplit::isIdentChar( c ) )
        {
            return false;
        }
        underscore = underscore || ( c == '_' && i + 1 < w.size() );
        innerCap   = innerCap || ( i > 0 && std::isupper( static_cast<unsigned char>( c ) ) != 0 && lower );
        lower      = lower || std::islower( static_cast<unsigned char>( c ) ) != 0;
    }
    return lower && ( underscore || innerCap || sep );
}

// a backticked span that can be scanned for: identifier bytes and a few separators, never a flag, a path or a file name
inline bool isTableAnchorSpan( std::string_view w ) noexcept
{
    if( w.size() < kForTableMinAnchor || w.size() > kForTableMaxAnchor || w.front() == '-' )
    {
        return false;
    }
    const bool bytesOk = std::all_of( w.begin(), w.end(), []( char c ) { return namesplit::isIdentChar( c ) || c == '.' || c == ':' || c == '#' || c == '$'; } );
    const std::size_t dot = w.rfind( '.' );
    return bytesOk && ( dot == std::string_view::npos || !isFileOrHostSuffix( w.substr( dot + 1 ) ) );
}

}   // namespace lit_detail

// the trigger of shape=table, read from the task's own words outside code quotes
inline TableCue forTableCueOf( std::string_view task )
{
    const std::string prose = lit_detail::withoutBackticks( task );
    const std::vector<std::string_view> words = lit_detail::taskWords( prose );
    TableCue cue = TableCue::None;
    std::size_t addAt = SIZE_MAX;
    for( std::size_t i = 0; i < words.size(); ++i )
    {
        const std::string_view w = lit_detail::stripWordPunct( words[i] );
        if( lit_detail::wordIsOneOf( w, std::span<const std::string_view>( lit_detail::kForTableRegistrationCues ) ) )
        {
            return TableCue::AnySite;
        }
        if( i + 1 < words.size() && lit_detail::wordIsOneOf( w, std::array<std::string_view, 1>{ "compile" } )
            && lit_detail::wordIsOneOf( lit_detail::stripWordPunct( words[i + 1] ), std::array<std::string_view, 1>{ "time" } ) )
        {
            return TableCue::AnySite;
        }
        if( lit_detail::wordIsOneOf( w, std::array<std::string_view, 4>{ "add", "adding", "implement", "implementing" } ) )
        {
            addAt = i;
        }
        if( addAt != SIZE_MAX && i <= addAt + 2 && i > addAt && lit_detail::wordIsOneOf( w, std::array<std::string_view, 2>{ "new", "another" } ) )
        {
            return TableCue::AnySite;
        }
        if( lit_detail::wordIsOneOf( w, std::span<const std::string_view>( lit_detail::kForTableValueCues ) ) )
        {
            cue = TableCue::TableRowOnly;
        }
    }
    return cue;
}

// the anchors of shape=table, in order, before the index filter: {text, quoted}
inline std::vector<std::pair<std::string, bool>> forTableAnchorsOf( std::string_view task )
{
    std::vector<std::pair<std::string, bool>> out;
    const auto add = [ & ]( std::string_view w, bool quoted )
    {
        if( std::none_of( out.begin(), out.end(), [ & ]( const auto& a ) { return a.first == w; } ) )
        {
            out.emplace_back( std::string( w ), quoted );
        }
    };
    for( std::size_t at = task.find( '`' ); at != std::string_view::npos; )
    {
        const std::size_t end = task.find( '`', at + 1 );
        if( end == std::string_view::npos )
        {
            break;
        }
        std::string_view span = task.substr( at + 1, end - at - 1 );
        span = span.ends_with( "()" ) ? span.substr( 0, span.size() - 2 ) : span;
        const std::size_t call = span.rfind( "()." );   // `a.load().b()`: the last link of a call chain is the name
        span = call == std::string_view::npos ? span : span.substr( call + 3 );
        if( lit_detail::isTableAnchorSpan( span ) )
        {
            add( span, true );
        }
        at = task.find( '`', end + 1 );
    }
    const std::string prose = lit_detail::withoutBackticks( task );
    const std::vector<std::string_view> words = lit_detail::taskWords( prose );
    for( std::size_t i = 0; i < words.size(); ++i )
    {
        const std::string_view w = lit_detail::stripWordPunct( words[i] );
        const bool afterLead = i > 0 && lit_detail::wordIsOneOf( lit_detail::stripWordPunct( words[i - 1] ), std::span<const std::string_view>( lit_detail::kForTableExemplarLeads ) );
        if( lit_detail::isIdentifierShaped( w ) || ( afterLead && w.size() >= kForTableMinAnchor && !lit_detail::wordIsOneOf( w, std::span<const std::string_view>( lit_detail::kForLiteralStopWords ) )
                                                     && std::all_of( w.begin(), w.end(), namesplit::isIdentChar ) ) )
        {
            add( w, false );
        }
    }
    return out;
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
    std::string tbl;                // shape=table: the line that opens the table this site is a row of ("item" at top level); "" = not a table row
};

// shape=dotted: where a hit of a key of `n` bytes at `at` of `text` stands. longer: inside a longer name or a child key (an identifier byte
// on either side, or `.` plus an identifier byte after it); `config.a.b` keeps a.b whole, a prefix is how a context key spells it.
struct KeyHit
{
    bool longer = false;
    bool quoted = false;
};
// the byte before `at` is the LETTER OF AN ESCAPE or of a printf conversion, not a letter of the text: `\n`, `\t`, `\0` (an odd run of
// backslashes before it: `\\n` is a backslash and a real n) or `%s`, `%d`, `%5.2f`, `%ld` (an odd run of `%` before the flags, width and
// length modifiers). The message or key begins right after it: `"\nFailed to get document"`.
inline bool afterEscapeOrVerb( std::string_view text, std::size_t at ) noexcept
{
    if( at < 2 || at > text.size() )
    {
        return false;
    }
    std::size_t slashes = 0;
    for( std::size_t i = at - 1; i > 0 && text[i - 1] == '\\'; --i )
    {
        ++slashes;
    }
    if( slashes % 2 == 1 )
    {
        return true;
    }
    constexpr std::string_view kVerbs = "diouxXeEfFgGaAcspnvTtqb", kMods = "0123456789.+-# *lhzjtLq";
    if( kVerbs.find( text[at - 1] ) == std::string_view::npos )
    {
        return false;
    }
    std::size_t i = at - 1;
    for( std::size_t steps = 0; i > 0 && steps < 8 && kMods.find( text[i - 1] ) != std::string_view::npos; --i, ++steps )
    {
    }
    std::size_t percents = 0;
    for( ; i > 0 && text[i - 1] == '%'; --i )
    {
        ++percents;
    }
    return percents % 2 == 1;
}

inline KeyHit keyHitAt( std::string_view text, std::size_t at, std::size_t n ) noexcept
{
    const auto ident = []( char c ) { return std::isalnum( static_cast<unsigned char>( c ) ) != 0 || c == '_' || c == '-'; };
    const auto quote = []( char c ) { return c == '"' || c == '\'' || c == '`'; };
    const char before = at > 0 && at <= text.size() ? text[at - 1] : ' ';   // a file that shrank since the scan: unknown, not out of range
    const char after  = at + n < text.size() ? text[at + n] : ' ';
    const char after2 = at + n + 1 < text.size() ? text[at + n + 1] : ' ';
    // an identifier byte before the key joins it to a longer name, except the letter of an escape (`"\nsvc.x.y"`) and a leading `--` (a
    // flag spelled with the key): a `-` joins only behind an identifier byte (`a-svc.x.y`)
    const bool joinsBefore = ident( before ) && !afterEscapeOrVerb( text, at )
                             && !( before == '-' && !( at >= 2 && ident( text[at - 2] ) && text[at - 2] != '-' ) );
    return KeyHit{ joinsBefore || ident( after ) || ( after == '.' && ident( after2 ) ), quote( before ) && quote( after ) };
}

// shape=message: the hit stands on word edges (`this field is` inside `this field isn't` does not). An edge byte that is not a letter,
// digit or `_` (a message that ends in a punctuation mark) needs no check; the letter of an escape or a printf verb before the hit is
// no word byte (afterEscapeOrVerb).
inline bool wordBounded( std::string_view text, std::size_t at, std::size_t n ) noexcept
{
    const auto word = []( char c ) { return std::isalnum( static_cast<unsigned char>( c ) ) != 0 || c == '_'; };
    if( n == 0 || at + n > text.size() )
    {
        return true;   // a file that changed since the scan: unknown, kept
    }
    return !( word( text[at] ) && at > 0 && word( text[at - 1] ) && !afterEscapeOrVerb( text, at ) )
           && !( word( text[at + n - 1] ) && at + n < text.size() && word( text[at + n] ) );
}

// a row's line cut to `cap` bytes; when the literal sits past the cap the row opens `kForLiteralKeyLead` bytes before it (an ellipsis
// marks the cut), so the row shows what it matched
inline void cutAround( std::string& line, std::string_view needle, std::size_t cap )
{
    const std::size_t at = needle.empty() ? 0 : line.find( needle );
    if( at != std::string::npos && at + needle.size() > cap )
    {
        std::size_t from = at > kForLiteralKeyLead ? at - kForLiteralKeyLead : 0;
        while( from < line.size() && ( static_cast<unsigned char>( line[from] ) & 0xC0 ) == 0x80 )
        {
            ++from;
        }
        line = "\xE2\x80\xA6" + line.substr( from );
    }
    truncateUtf8WithEllipsis( line, cap );
}

// the rows to show, as positions in the rank order: the first `cap`, except that rows `reg` marks (2 = a registration: a quoted key outside
// any function that is itself a property key, 1 = another quoted site outside any function) from past the cap replace the lowest-ranked
// rows of a lower mark until `reserve` rows of that mark or higher are shown, property keys first; ascending, so the rank order is kept
inline std::vector<std::size_t> pickRows( const std::vector<char>& reg, std::size_t cap, std::size_t reserve )
{
    std::vector<std::size_t> pick;
    for( std::size_t i = 0; i < reg.size() && i < cap; ++i )
    {
        pick.push_back( i );
    }
    for( char level = 2; level >= 1; --level )
    {
        std::size_t have = std::size_t( std::count_if( pick.begin(), pick.end(), [ & ]( std::size_t i ) { return reg[i] >= level; } ) );
        for( std::size_t p = cap; p < reg.size() && have < reserve; ++p )
        {
            if( reg[p] != level )
            {
                continue;
            }
            std::size_t q = pick.size();
            while( q > 0 && reg[pick[q - 1]] >= level )
            {
                --q;
            }
            if( q == 0 )
            {
                break;   // every shown row is as much a registration already
            }
            pick.erase( pick.begin() + std::ptrdiff_t( q - 1 ) );
            pick.push_back( p );
            ++have;
        }
    }
    std::sort( pick.begin(), pick.end() );
    return pick;
}

// How a shape of <lit> reads its sites: one row of this table per shape, so a new shape is a new row, never a new bool through renderForLiteral.
enum class LitBoundary : std::uint8_t
{
    None,   // shape=quoted|const: every byte-exact hit is a site
    Key,    // shape=dotted: keyHitAt, a hit inside a longer name or a child key is `longer`, quotes around the key rank it
    Word    // shape=message: wordBounded, a hit inside a longer word is `longer`
};
struct LitPolicy
{
    LitBoundary      boundary = LitBoundary::None;
    bool             dropCode = false;   // a code row is never printed (the task's words met outside a string are no message)
    std::size_t      rows     = kForLiteralSiteRows;
    std::size_t      reserve  = 0;       // row slots kept for a registration (pickRows)
    std::string_view legend;             // the clause this shape adds to the base legend; "" = none
    bool             tableRows    = false;   // sites are read for a table row (tableRowOf), which rank first and carry tbl=
    std::size_t      contextRows  = kForLiteralContextRows;
    std::size_t      rankedRows   = kForLiteralRankedRows;
};
inline LitPolicy litPolicyOf( std::string_view shape ) noexcept
{
    if( shape == "dotted" )
    {
        return LitPolicy{ LitBoundary::Key, false, kForLiteralSiteRows, kForLiteralRegistrationRows, kForLiteralKeyLegend };
    }
    if( shape == "message" )
    {
        return LitPolicy{ LitBoundary::Word, true, kForLiteralSiteRows, 0, kForLiteralKeyLegend };
    }
    if( shape == "table" )
    {
        return LitPolicy{ LitBoundary::Word, false, kForTableRows, 0, kForLiteralTableLegend, true, kForTableContextRows, kForTableRankedRows };
    }
    return LitPolicy{};
}

// where a hit of the literal at `at` of `text` stands, by the shape's boundary rule
inline KeyHit literalHitAt( LitBoundary boundary, std::string_view text, std::size_t at, std::size_t n ) noexcept
{
    if( boundary == LitBoundary::Key )
    {
        return keyHitAt( text, at, n );
    }
    KeyHit h;
    h.longer = boundary == LitBoundary::Word && !wordBounded( text, at, n );
    return h;
}

// shape=table: what a source line looks like as a row of a table. Allowlist: a line of none of these shapes is never a table row.
enum class RowKind : std::uint8_t
{
    None,
    Call,    // `DECLARE(MaxThreads, max_threads, ...`, `impl_stream_node_body!(HashJoin(HashJoinNode) => ...);`, `Register("k", f);`
    Key,     // `"abspath": funcs.AbsPathFunc,`, `InPlacePodVerticalScaling: {`, `"k" => v,`
    Member,  // `Each,`  `Each, Filter,`  `"a",`
    Brace    // `{ barrier_interval_ms, u32, ...`
};
struct RowShape
{
    RowKind          kind = RowKind::None;
    std::string_view head;   // RowKind::Call: the callee, so two calls of one callee are siblings and two different ones are not
};
inline constexpr auto kForTableNotCallee = std::to_array<std::string_view>(
    { "if", "for", "while", "switch", "catch", "return", "sizeof", "assert", "elif", "match", "def", "func", "fn", "function", "class", "struct", "print", "println" } );

inline std::size_t identEnd( std::string_view t ) noexcept
{
    return std::size_t( std::find_if_not( t.begin(), t.end(), namesplit::isIdentChar ) - t.begin() );
}

inline RowShape rowShapeOf( std::string_view line )
{
    std::string_view t = trimWs( line );
    if( t.empty() )
    {
        return {};
    }
    if( t.front() == '{' )
    {
        const std::string_view in = trimWs( t.substr( 1 ) );
        return !in.empty() && ( namesplit::isIdentChar( in.front() ) || in.front() == '"' ) ? RowShape{ RowKind::Brace, {} } : RowShape{};
    }
    std::size_t keyEnd = 0;
    if( t.front() == '"' || t.front() == '\'' )
    {
        const std::size_t close = t.find( t.front(), 1 );
        if( close == std::string_view::npos )
        {
            return {};
        }
        keyEnd = close + 1;
    }
    else
    {
        keyEnd = identEnd( t );
        if( keyEnd == 0 )
        {
            return {};
        }
        const std::size_t bang = keyEnd < t.size() && t[keyEnd] == '!' ? keyEnd + 1 : keyEnd;
        if( bang < t.size() && t[bang] == '(' )
        {
            const std::string_view callee = t.substr( 0, keyEnd );
            return wordIsOneOf( callee, kForTableNotCallee ) ? RowShape{} : RowShape{ RowKind::Call, t.substr( 0, bang ) };
        }
    }
    const std::string_view rest = trimWs( t.substr( keyEnd ) );
    if( rest.empty() || rest.front() == ',' )
    {
        // a member: nothing but bare words and commas on the line, and it ends in a comma or stands alone in a list
        const bool plain = std::all_of( t.begin(), t.end(), []( char c ) { return namesplit::isIdentChar( c ) || c == ',' || c == ' ' || c == '"' || c == '\''; } );
        return plain && t.back() == ',' ? RowShape{ RowKind::Member, {} } : RowShape{};
    }
    if( ( rest.front() == ':' && !rest.starts_with( "::" ) && !rest.starts_with( ":=" ) ) || rest.starts_with( "=>" ) )
    {
        return RowShape{ RowKind::Key, {} };
    }
    return {};
}

inline std::size_t indentOf( std::string_view line ) noexcept
{
    return std::min( line.find_first_not_of( " \t" ), line.size() );
}

// the line at `start` of `text`, and the start of the next one
inline std::string_view lineAt( std::string_view text, std::size_t start ) noexcept
{
    const std::size_t end = text.find( '\n', start );
    return text.substr( start, end == std::string_view::npos ? std::string_view::npos : end - start );
}

// the nearest line at this indent, walking one way, that is not a closer; `down` next line, else the previous one. A line less indented ends the walk unless `crossLess`.
inline std::optional<std::string_view> siblingLine( std::string_view text, std::size_t rowStart, std::size_t indent, bool down, bool crossLess ) noexcept
{
    std::size_t pos = rowStart;
    for( std::size_t step = 0; step < kForTableSiblingLines; ++step )
    {
        if( down )
        {
            const std::size_t nl = text.find( '\n', pos );
            if( nl == std::string_view::npos || nl + 1 >= text.size() )
            {
                return std::nullopt;
            }
            pos = nl + 1;
        }
        else
        {
            if( pos == 0 )
            {
                return std::nullopt;
            }
            const std::size_t nl = pos >= 2 ? text.rfind( '\n', pos - 2 ) : std::string_view::npos;
            pos = nl == std::string_view::npos ? 0 : nl + 1;
        }
        const std::string_view l = lineAt( text, pos );
        const std::string_view t = trimWs( l );
        if( t.empty() )
        {
            continue;
        }
        const std::size_t in = indentOf( l );
        if( in < indent && !crossLess )
        {
            return std::nullopt;
        }
        if( in == indent && t.front() != '}' && t.front() != ')' && t.front() != ']' )
        {
            return l;
        }
    }
    return std::nullopt;
}

// a line that can open a table: it ends in an open bracket, or is a #define (a continuation line of raw text above a row opens nothing)
inline bool linesOpensBlock( std::string_view line ) noexcept
{
    std::string_view t = trimWs( line );
    t = t.ends_with( '\\' ) ? trimWs( t.substr( 0, t.size() - 1 ) ) : t;
    return !t.empty() && ( t.back() == '{' || t.back() == '[' || t.back() == '(' || t.starts_with( "#define" ) );
}

// the line that opens the table a row at `rowStart` stands in: the nearest less indented line above it that can open one
inline std::string_view openerOf( std::string_view text, std::size_t rowStart, std::size_t indent ) noexcept
{
    std::size_t pos = rowStart;
    for( std::size_t step = 0; indent > 0 && pos > 0 && step < kForTableOpenerLines; ++step )
    {
        const std::size_t nl = pos >= 2 ? text.rfind( '\n', pos - 2 ) : std::string_view::npos;
        pos = nl == std::string_view::npos ? 0 : nl + 1;
        const std::string_view l = lineAt( text, pos );
        if( !trimWs( l ).empty() && indentOf( l ) < indent && linesOpensBlock( l ) )
        {
            return trimWs( l );
        }
    }
    return {};
}

// shape=table, rank only: a site under documentation, examples or an integration app comes after the product's own (a row is never dropped by this)
inline bool isSecondaryPath( std::string_view p ) noexcept
{
    static constexpr std::array<std::string_view, 8> kSegments{ "docs", "doc", "examples", "example", "samples", "snippets", "website", "integration" };
    while( !p.empty() )
    {
        const std::size_t slash = p.find( '/' );
        if( slash == std::string_view::npos )
        {
            return false;   // the last segment is the file's own name
        }
        if( std::find( kSegments.begin(), kSegments.end(), p.substr( 0, slash ) ) != kSegments.end() )
        {
            return true;
        }
        p.remove_prefix( slash + 1 );
    }
    return false;
}

// an import list reads like a member list: `use a::{` / `import {` / `from x import (` open no table
inline bool opensImport( std::string_view opener ) noexcept
{
    const std::size_t n = identEnd( opener );
    const std::string_view first = opener.substr( 0, n );
    return first == "use" || first == "import" || first == "from" || first == "export" || first == "package" || first == "extern" || first == "pub";
}

// The table this source line is a row of, or "": a row of an allowed shape with a sibling of the same shape at its indent, or a macro row at
// top level (a Rust `name!(`, an ALLCAPS callee, outside any function), which is a registration with no sibling needed.
inline std::string tableRowOf( std::string_view text, std::size_t byteOffset, bool callableOwner )
{
    if( byteOffset >= text.size() )
    {
        return {};   // a file that changed since the scan: unknown, no claim
    }
    const std::size_t nl    = byteOffset == 0 ? std::string_view::npos : text.rfind( '\n', byteOffset - 1 );
    const std::size_t start = nl == std::string_view::npos ? 0 : nl + 1;
    const std::string_view line = lineAt( text, start );
    const RowShape shape = rowShapeOf( line );
    if( shape.kind == RowKind::None )
    {
        return {};
    }
    const std::size_t indent = indentOf( line );
    const std::string_view opener = openerOf( text, start, indent );
    if( opensImport( opener ) )
    {
        return {};
    }
    const auto same = [ & ]( std::optional<std::string_view> l )
    {
        if( !l )
        {
            return false;
        }
        const RowShape o = rowShapeOf( *l );
        return o.kind == shape.kind && o.head == shape.head;
    };
    const bool macroRow = shape.kind == RowKind::Call && !callableOwner
                          && ( shape.head.ends_with( '!' ) || std::none_of( shape.head.begin(), shape.head.end(), []( char c ) { return std::islower( static_cast<unsigned char>( c ) ) != 0; } ) );
    const bool crossLess = shape.kind == RowKind::Call;   // a call row's text may span raw lines at any indent (`DECLARE(.., R"(` over a description)
    if( !macroRow && !same( siblingLine( text, start, indent, true, crossLess ) ) && !same( siblingLine( text, start, indent, false, crossLess ) ) )
    {
        return {};
    }
    return opener.empty() ? std::string( "item" ) : std::string( opener );
}

// shape=table: read each ranked site for a table row; true when one is
template<typename LoadFile>
inline bool markTableRows( const IngestResult& ing, std::vector<Site>& rows, const std::vector<GrepHit>& enriched, LoadFile&& loadFile, const std::string& loadedText )
{
    bool any = false;
    for( std::size_t i = 0; i < enriched.size(); ++i )
    {
        loadFile( rows[i].raw.fileId );
        const bool callableOwner = enriched[i].enclosingId != kNoNode && ReceiverEvidence::callableKind( ing.symbols[enriched[i].enclosingId].kind );
        rows[i].tbl = tableRowOf( loadedText, rows[i].raw.byteOffset, callableOwner );
        any         = any || !rows[i].tbl.empty();
    }
    return any;
}

// the tbl= attribute of a row, "" on a row that is no table row; the opener is raw source text
inline std::string tblAttr( std::string opener, RedactCounts* redact )
{
    if( opener.empty() )
    {
        return {};
    }
    std::vector<char> esc;
    redactInPlace( opener, redact );
    truncateUtf8WithEllipsis( opener, kForTableOpenerBytes );
    return " tbl=\"" + std::string( escapeXml( opener, esc ) ) + "\"";
}

// `'files.autoSave': {`: the quoted key is followed by a colon on its line (a property key, the way a schema registers a setting)
inline bool keyIsProperty( std::string_view line, std::string_view key ) noexcept
{
    const std::size_t at = line.find( key );
    if( at == std::string_view::npos )
    {
        return false;
    }
    const std::size_t colon = line.find_first_not_of( " \t", at + key.size() + 1 );
    return colon != std::string_view::npos && line[colon] == ':';
}

// shape=dotted: how much of a registration a site is, 0 none: 1 a quoted string site outside any function or method, 2 one whose key is a
// property key (`'files.autoSave': {`)
inline char registrationMark( const IngestResult& ing, const Site& s, NodeId owner, std::string_view line, std::string_view key )
{
    if( !s.quotedKey || s.k != 's' || ( owner != kNoNode && ReceiverEvidence::callableKind( ing.symbols[owner].kind ) ) )
    {
        return 0;
    }
    return keyIsProperty( line, key ) ? 2 : 1;
}

// shape=message: the rows that are not code (a task's words met outside a string are no message)
inline void dropCodeRows( std::vector<Site>& rows )
{
    rows.erase( std::remove_if( rows.begin(), rows.end(), []( const Site& r ) { return r.k == 'c'; } ), rows.end() );
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

// shape=table: what a later <lit> of one task inherits from the earlier ones
struct ForLiteralLimits
{
    std::size_t byteCap    = SIZE_MAX;   // element bytes left for rows and bodies
    bool        withLegend = true;       // only the first element of a task carries the legend comments
    bool        tableOnly  = false;      // TableCue::TableRowOnly: no table row, no block
};

// THE BLOCK. `served` = the answer's own bytes after <sigs> (bodies, fold, slot, hops): a body whose <b … l= p= n=> head is in it
// is not printed again. `useMemo` = the span-tier memo (false under --no-cache). `compactLegend` = the default --legend=compact dialect.
inline ForLiteralRender renderForLiteral( const IngestResult& ing, const ForLiteral& lit, std::string_view rootArg, std::string_view served,
                                          RedactCounts* redact, bool useMemo, bool compactLegend, const ForLiteralLimits& limits = {} )
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
    const lit_detail::LitPolicy policy = lit_detail::litPolicyOf( lit.shape );
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
            if( policy.boundary != lit_detail::LitBoundary::None )
            {
                loadFile( r.fileId );
                keyHit = lit_detail::literalHitAt( policy.boundary, loadedText, r.byteOffset, lit.text.size() );
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
    if( policy.dropCode )
    {
        lit_detail::dropCodeRows( rows );   // a code row is never printed (all code: no block)
    }
    out.sites = rows.size();
    if( rows.empty() )
    {
        return out;   // no source site: nothing to anchor on (test/doc/comment counts alone answer nothing; measured as noise, ld2-django-09)
    }
    const std::size_t ranked = std::min( rows.size(), policy.rankedRows );
    for( std::size_t i = 0; i < ranked; ++i )
    {
        all.push_back( rows[i].raw );
    }
    std::vector<GrepHit> enriched = grepEnrich( ing, std::span<const GrepRawHit>( all ) );
    ASSUME( enriched.size() == all.size(), "grepEnrich returns one row per windowed hit" );
    if( policy.tableRows && !lit_detail::markTableRows( ing, rows, enriched, loadFile, loadedText ) && limits.tableOnly )
    {
        return ForLiteralRender{};
    }
    std::vector<std::size_t> order( enriched.size() );
    for( std::size_t i = 0; i < order.size(); ++i )
    {
        order[i] = i;
    }
    const auto rankOf = [ & ]( std::size_t i )
    {
        const bool callable = enriched[i].enclosingId != kNoNode && ReceiverEvidence::callableKind( ing.symbols[enriched[i].enclosingId].kind );
        return ( policy.tableRows && lit_detail::isSecondaryPath( rootRelPath( ing, rows[i].raw.fileId ) ) ? 12 : 0 ) + ( policy.tableRows && rows[i].tbl.empty() ? 6 : 0 ) + ( policy.boundary == lit_detail::LitBoundary::Key && !rows[i].quotedKey ? 6 : 0 ) + ( callable != policy.tableRows ? 0 : 3 ) + ( rows[i].k == 's' ? 0 : ( rows[i].k == 'c' ? 1 : 2 ) );
    };
    std::stable_sort( order.begin(), order.end(), [ & ]( std::size_t a, std::size_t b ) { return rankOf( a ) < rankOf( b ); } );
    std::vector<char> registration( order.size(), 0 );   // by rank position: a quoted key outside any function (shape=dotted)
    for( std::size_t i = 0; policy.reserve > 0 && i < order.size(); ++i )
    {
        registration[i] = lit_detail::registrationMark( ing, rows[order[i]], enriched[order[i]].enclosingId, enriched[order[i]].text, lit.text );
    }
    const std::vector<std::size_t> pick = lit_detail::pickRows( registration, policy.rows, policy.reserve );
    std::vector<GrepHit>          hits;
    std::vector<lit_detail::Site> shownRows;
    for( const std::size_t p : pick )
    {
        hits.push_back( std::move( enriched[order[p]] ) );
        shownRows.push_back( rows[order[p]] );
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
            if( body && body->size() <= kForLiteralBodyCapBytes && bodiesXml.size() + body->size() <= limits.byteCap )
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
        std::string excerpt = lit_detail::excerptElement( text, path, s, first, last, siteLines, redact );
        if( bodiesXml.size() + excerpt.size() > limits.byteCap )
        {
            ownerAbove.back() = 2;   // past the byte cap, as past the body cap: the row says body="held"
            continue;
        }
        bodiesXml += excerpt;
        ++out.bodies;
    }

    // ── the rows ──────────────────────────────────────────────────────────────────────────────────────────────────────────
    const std::string_view needle = policy.boundary != lit_detail::LitBoundary::None ? std::string_view( lit.text ) : std::string_view();   // a cut row opens near it
    std::string rowsXml;
    std::size_t contextRows = 0;
    std::size_t shownRowCount = 0;
    bool        byteCut       = false;
    for( std::size_t i = 0; i < hits.size(); ++i )
    {
        const GrepHit& h = hits[i];
        const std::size_t rowStartAt = rowsXml.size();
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
        lit_detail::cutAround( line, needle, kForLiteralLineBytes );
        const bool callableOwner = h.enclosingId != kNoNode && ReceiverEvidence::callableKind( ing.symbols[h.enclosingId].kind );
        rowsXml += lit_detail::tblAttr( rows[i].tbl, redact );
        if( ( policy.tableRows ? !rows[i].tbl.empty() : rows[i].k == 's' && !callableOwner ) && contextRows < policy.contextRows )
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
        if( rowsXml.size() + bodiesXml.size() > limits.byteCap )
        {
            rowsXml.resize( rowStartAt );   // a cut stands on a row boundary, never inside a line
            byteCut = true;
            break;
        }
        ++shownRowCount;
    }
    if( byteCut && shownRowCount == 0 )
    {
        return ForLiteralRender{};   // not one row fits what the cap left: the caller counts this anchor as skipped
    }

    std::string& x = out.xml;
    if( limits.withLegend )
    {
        x = compactLegend ? std::string( kForCompactLiteralLegend ) : std::string( kForLiteralLegend );
        x += !policy.legend.empty() ? policy.legend : ( lit.tryNo > 1 ? kForLiteralKeyLegend : std::string_view() );
    }
    x += "<lit s=\"";
    x += escapeXml( lit.text, esc );
    x += "\" shape=\"";
    x += lit.shape;
    x += "\" hits=\"" + std::to_string( collected.raw.size() ) + "\" src=\"" + std::to_string( out.sites ) + "\" shown=\""
         + std::to_string( shownRowCount ) + "\"";
    if( shownRowCount < out.sites )
    {
        x += " capped=\"1\"";
    }
    x += longerHits > 0 ? " longer=\"" + std::to_string( longerHits ) + "\"" : std::string();
    x += lit.frag ? " frag=\"1\"" : "";
    x += lit.tryNo > 1 ? " try=\"" + std::to_string( lit.tryNo ) + "\"" : std::string();
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

// a file of the index named `name` (a dotted word that is a file's name is no key, whatever its extension)
inline bool namesIndexedFile( const IngestResult& ing, std::string_view name )
{
    return std::any_of( ing.files.begin(), ing.files.end(),
                        [ & ]( const auto& f ) { const std::string_view p( f ); return p.ends_with( name ) && ( p.size() == name.size() || p[p.size() - name.size() - 1] == '/' ); } );
}

// the first try of a message (forMessageTries) that has a string site, or nothing
inline ForLiteralRender renderMessageTries( const IngestResult& ing, const ForLiteral& lit, std::string_view rootArg, std::string_view served,
                                            RedactCounts* redact, bool useMemo, bool compactLegend )
{
    for( const std::string& t : forMessageTries( lit.text ) )
    {
        ForLiteral tried = lit;
        tried.text       = t;
        tried.frag       = t != lit.text;
        ForLiteralRender r = renderForLiteral( ing, tried, rootArg, served, redact, useMemo, compactLegend );
        if( !r.xml.empty() )
        {
            return r;
        }
    }
    return {};
}

// a word of the task is an anchor of shape=table when the index holds a symbol of that name (a backticked span stands on its own quoting)
inline bool forTableAnchorKeeps( const IngestResult& ing, std::string_view word, bool quoted )
{
    if( quoted )
    {
        return true;
    }
    if( word.starts_with( "self." ) || word.starts_with( "this." ) )
    {
        return false;   // a member chain, never a table's key (dottedKeysOf's rule)
    }
    const std::string_view tail = word.substr( word.find_last_of( ".:#" ) + 1 );   // the name an index symbol carries; npos + 1 is the whole word
    return tail.size() >= kForTableMinAnchor && std::any_of( ing.symbols.begin(), ing.symbols.end(), [ & ]( const Symbol& s ) { return s.name == tail; } );
}

// shape=table, the last try: every kept anchor with a site prints its own <lit>, all under one byte cap. `capped` = what the earlier shapes
// left unscanned, which stays said. An anchor the cap left out is counted the way a literal past the scan cap is.
inline ForLiteralRender renderForTableOfTask( const IngestResult& ing, std::string_view task, std::string_view rootArg, std::string_view served,
                                              RedactCounts* redact, bool useMemo, bool compactLegend )
{
    ForLiteralRender out;
    const TableCue cue = forTableCueOf( task );
    if( cue == TableCue::None )
    {
        return out;
    }
    std::size_t kept = 0, scanned = 0, skipped = 0, used = 0;
    std::string firstSkipped;
    for( const auto& [word, quoted] : forTableAnchorsOf( task ) )
    {
        if( kept >= kForTableAnchors || namesIndexedFile( ing, word ) || !forTableAnchorKeeps( ing, word, quoted ) )
        {
            continue;
        }
        ++kept;
        if( used + kForTableElementBytes >= kForTableByteCap )
        {
            ++skipped;
            firstSkipped = firstSkipped.empty() ? word : firstSkipped;
            continue;
        }
        ++scanned;
        ForLiteralLimits limits{ kForTableByteCap - used - kForTableElementBytes, out.xml.empty(), cue == TableCue::TableRowOnly };
        ForLiteral lit{ word, "table" };
        ForLiteralRender r = renderForLiteral( ing, lit, rootArg, served, redact, useMemo, compactLegend, limits );
        if( r.xml.empty() )
        {
            continue;
        }
        used += r.xml.size() - r.xml.find( "<lit " );   // element bytes: the legend comments before the first are not
        out.xml += r.xml;
        out.sites += r.sites;
        out.bodies += r.bodies;
    }
    if( skipped > 0 )
    {
        out.xml += std::string( kForLiteralCapLegend ) + "<lit_capped scanned=\"" + std::to_string( scanned ) + "\" skipped=\"" + std::to_string( skipped )
                   + "\"" + nextAttrXml( nextFlag( "--grep=", firstSkipped ) ) + "/>";
    }
    return out;
}

// the block of the task's literals: each in order (forLiteralCandidates) until one has a source site, at most kForLiteralCandidates scans
// besides a message, which walks its tries
inline ForLiteralRender renderForLiteralOfTask( const IngestResult& ing, std::string_view task, std::string_view rootArg, std::string_view served,
                                                RedactCounts* redact, bool useMemo, bool compactLegend )
{
    std::size_t scans = 0, skipped = 0;
    std::string firstSkipped;
    for( const ForLiteral& lit : forLiteralCandidates( task ) )
    {
        const bool message = lit.shape == "message";
        if( !message && lit.shape == "dotted" && namesIndexedFile( ing, lit.text ) )
        {
            continue;
        }
        if( !message && scans >= kForLiteralCandidates )
        {
            skipped += 1;
            firstSkipped = firstSkipped.empty() ? lit.text : firstSkipped;
            continue;
        }
        scans += message ? 0 : 1;
        ForLiteralRender r = message ? renderMessageTries( ing, lit, rootArg, served, redact, useMemo, compactLegend )
                                     : renderForLiteral( ing, lit, rootArg, served, redact, useMemo, compactLegend );
        if( !r.xml.empty() )
        {
            return r;
        }
    }
    // no earlier shape anchored: the last try, shape=table (it never prints beside them)
    ForLiteralRender table = renderForTableOfTask( ing, task, rootArg, served, redact, useMemo, compactLegend );
    if( skipped > 0 )
    {
        // the cap was hit and nothing scanned anchored: say so (no <lit>: no site was found, so the block's attributes would claim one)
        table.xml = std::string( kForLiteralCapLegend ) + "<lit_capped scanned=\"" + std::to_string( scans ) + "\" skipped=\"" + std::to_string( skipped )
                    + "\"" + nextAttrXml( nextFlag( "--grep=", firstSkipped ) ) + "/>" + table.xml;
    }
    return table;
}
}   // namespace rw
