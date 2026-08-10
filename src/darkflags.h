#pragma once

// darkflags.h — `--flags`, the DARK-CONTENT DASHBOARD.
// Evidence: twice in one day an owner asked "why don't I see X?" and the answer both times was that X ships
// COMPILED OUT — a `#ifndef F / #define F 0` header gate, a CMake `option()`, or a `getenv()` read that
// nothing sets. That question has no verb: `--grep` finds the gate's spelling but not its DEFAULT, not how
// much code hangs off it, and not the second place that overrides it. One call should answer "what is built
// but dark in this repo".
//
// Three gate patterns, one report:
//   compile — `#ifndef NAME` immediately followed by `#define NAME VALUE` (the build-dark-then-flip idiom:
//             the guard is what lets `-DNAME=1` win from the command line without editing the header).
//   cmake   — `option( NAME "doc" ON|OFF )` in CMakeLists.txt / *.cmake.
//   env     — `getenv("NAME")` / `std::getenv` / Python `os.environ.get` / `os.getenv`. Default: unset.
//
// ── the override rule (the actual bug this verb catches) ─────────────────────────────────────────────────
// A name is routinely BOTH a header gate defaulting to 0 AND a CMake option defaulting to ON — the header
// says dark, the build says lit, and the header is what a reader greps. The CMake option WINS here, because
// it is what the build actually passes on the command line, and the loser is still reported as an <also/>
// row so the contradiction is visible rather than resolved silently.
//
// ── guarded size ─────────────────────────────────────────────────────────────────────────────────────────
// A gate's weight is how much code it turns off: every `#if`-family region whose condition MENTIONS the gate
// is counted, along with the lines inside it, tracking nesting so an inner `#if` cannot close an outer one.
// This is a lexical region count, not a preprocessor evaluation — see the LIMITS note in the help text.
//
// Determinism: files come from the caller's already-sorted ingest file list plus a sorted CMake walk; gates
// iterate in name order; every site list is sorted by (path, line). No wall clock, no hashing of addresses.

#include "model.h"
#include "ingest.h"             // kCrawlSkipDirs / isSkippedCrawlDir — the SHARED crawl denylist
#include "arch.h"               // relForHash
#include "serialize.h"          // escapeXml
#include "docparse.h"           // lowerExtOf / isDocExtension — which files are PROSE, not code
#include "infra/Diagnostics.h"  // DEGRADED_PATH_ALERT

#include "btree.hpp"      // gtl::btree_map — sorted iteration (house rule: never std::map)

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <filesystem>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
namespace darkflags
{

constexpr std::size_t kMaxFlagFileBytes = 4u << 20;   // 4 MB — past this a "source" file is generated data
constexpr std::size_t kMaxSitesShown    = 8;          // per gate, per list; the rest are counted in a <more/>
constexpr std::size_t kMaxEnvNameLen    = 128;        // longest plausible environment-variable name

enum class GateKind : std::uint8_t { Compile = 0, CMake, Env };

inline const char* gateKindTag( GateKind k ) noexcept
{
    static const char* kTag[] = { "compile", "cmake", "env" };
    return kTag[ std::size_t( k ) ];
}

struct Site
{
    std::string   path;
    std::uint32_t line = 0;
};

inline bool siteLess( const Site& a, const Site& b )
{
    return a.path != b.path ? a.path < b.path : a.line < b.line;
}

// One `#if`-family region whose condition mentions a gate, kept as a SPAN rather than folded straight into
// the counters. `--flags` only ever prints the counts, but `--flip` (flipimpact.h) needs the span itself to
// ask "which indexed SYMBOLS sit inside the code this gate turns on" — a question the count cannot answer.
// Additive: nothing in the `--flags` output reads this.
struct Region
{
    Site          site;             // the `#if` line that opens the region
    std::uint32_t lines = 0;        // lines strictly INSIDE it (the same number folded into guardedLines)
};

inline std::uint32_t regionEndLine( const Region& r ) noexcept { return r.site.line + r.lines + 1; }   // the `#endif`

struct Gate
{
    std::string       name;
    GateKind          kind = GateKind::Compile;   // the WINNING kind (cmake beats compile — see the header note)
    std::string       def;                        // the winning default, as written ("0" / "ON" / "unset")
    Site              defSite;
    bool              hasAlso = false;            // the same name also declared by the losing pattern
    GateKind          alsoKind = GateKind::Compile;
    std::string       alsoDef;
    Site              alsoSite;
    std::uint32_t     regions = 0;                // `#if`-family regions whose condition mentions this gate
    std::uint32_t     guardedLines = 0;           // lines inside them
    std::vector<Site> reads;                      // every site that TESTS the gate (#if / getenv / cmake use)
    std::vector<Region> regionSpans;              // the SAME regions as spans (sorted by path,line) — `--flip` only

    // Alias chain: `#define CANYON_RRF_WALLS CANYON_RRF_ALL` makes WALLS an alias OF ALL. A master switch
    // spelled that way guards nothing directly, so without the roll-up below it reports regions=0/loc=0 —
    // technically true and completely misleading, since flipping it is what lights every child's code.
    std::string       aliasOf;                    // this gate's default IS another gate's name (the ROOT of the chain)
    std::string       aliasParent;                // the IMMEDIATE `#define CHILD PARENT` link — equals aliasOf on a
                                                  // 2-level chain, differs on A->B->C (aliasOf=C, aliasParent=B).
                                                  // `--flip` walks THIS to build the family a flip actually lights:
                                                  // flipping B must light A, which the root-only link cannot express.
    std::uint32_t     aliasCount = 0;             // (on the PARENT) how many gates alias to it
    std::uint32_t     aliasRegions = 0;           // (on the PARENT) regions its aliases guard
    std::uint32_t     aliasLines = 0;             // (on the PARENT) lines those regions hold
};

// A gate is DARK when its effective default keeps the guarded code out of the build: 0/OFF/FALSE/NO/unset.
// Anything else (1, ON, a version number, a path) is live. Case-insensitive: CMake accepts ON/on/On.
inline bool isDarkDefault( std::string_view v )
{
    std::string low;
    low.reserve( v.size() );
    for( char c : v )
    {
        low.push_back( char( std::tolower( (unsigned char)c ) ) );
    }
    return low.empty() || low == "0" || low == "off" || low == "false" || low == "no" || low == "unset";
}

// ── lexical helpers ──────────────────────────────────────────────────────────────────────────────────────

inline bool identByte( unsigned char c ) noexcept { return std::isalnum( c ) || c == '_'; }

// `hay[at, at+len)` is a WHOLE word (not flanked by identifier bytes) — so `Foo` never matches `FooBar` /
// `myFoo`. Lives HERE, beside identByte, because three modules need the same test on raw file text:
// layout.h's declaration scanner, flipimpact.h's value lane, and the harvest below.
inline bool wholeWordAt( std::string_view hay, std::size_t at, std::size_t len ) noexcept
{
    if( at > 0 && identByte( (unsigned char)hay[at - 1] ) )
    {
        return false;
    }
    if( at + len < hay.size() && identByte( (unsigned char)hay[at + len] ) )
    {
        return false;
    }
    return true;
}

// An IDENTIFIER-shaped run: a letter or underscore, then identifier bytes only, with a length in
// [minLen, maxLen]. Lives beside identByte because more than one lane needs the identical test —
// docdrift's doc-name filter (identOk) and this file's env-name filter, where it is the whole reason
// `,`, `, `, `" sym="` and `CANYON_*` cannot be gates: nothing else can name an environment variable.
inline bool isIdentShaped( std::string_view s, std::size_t minLen, std::size_t maxLen ) noexcept
{
    if( s.size() < minLen || s.size() > maxLen )
    {
        return false;
    }
    if( !( std::isalpha( (unsigned char)s[0] ) || s[0] == '_' ) )
    {
        return false;
    }
    for( char c : s )
    {
        if( !identByte( (unsigned char)c ) )
        {
            return false;
        }
    }
    return true;
}

inline bool endsWithView( std::string_view s, std::string_view suffix ) noexcept
{
    return s.size() >= suffix.size() && s.compare( s.size() - suffix.size(), suffix.size(), suffix ) == 0;
}

// Offset of the first WHOLE-WORD occurrence of `word` in `hay`, or npos. containsWord is the yes/no form;
// a caller that must read what sits to the LEFT of the hit (flipimpact's binding declarator) needs WHERE.
inline std::size_t firstWordAt( std::string_view hay, std::string_view word ) noexcept
{
    if( word.empty() )
    {
        return std::string_view::npos;
    }
    for( std::size_t at = hay.find( word ); at != std::string_view::npos; at = hay.find( word, at + 1 ) )
    {
        if( wholeWordAt( hay, at, word.size() ) )
        {
            return at;
        }
    }
    return std::string_view::npos;
}

inline bool containsWord( std::string_view hay, std::string_view word ) noexcept
{
    return firstWordAt( hay, word ) != std::string_view::npos;
}

// Split `bytes` into 1-based lines (CR stripped) and hand each to `perLine`; returns the line COUNT. The ONE
// line splitter over raw file text — docdrift's anchor scan and flipimpact's value lane both sit on it, so a
// CRLF file is handled identically by both instead of by whichever one remembered.
//
// The bound is `i < bytes.size()`, NOT `<=`: a file's terminating `\n` ENDS its last line, it does not OPEN
// an empty one. With the `<=` bound every newline-terminated file reported one line more than it has (and an
// empty file reported 1), which `--doc-drift` printed verbatim — `got="849 lines"` for a file `wc -l` calls
// 848 — and, worse, let an anchor citing exactly line lineCount+1 pass the past-eof bounds test.
// `lineIndex` (the 1-based number handed to `perLine`) and `lineCount` (what this returns) are the same
// number only because the last visited index IS the count; they are named apart on purpose.
template<class PerLine>
inline std::uint32_t forEachLine( std::string_view bytes, PerLine&& perLine )
{
    std::uint32_t lineCount = 0;
    for( std::size_t i = 0; i < bytes.size(); )
    {
        std::size_t e = bytes.find( '\n', i );
        if( e == std::string_view::npos )
        {
            e = bytes.size();
        }
        std::string_view line = bytes.substr( i, e - i );
        if( !line.empty() && line.back() == '\r' )
        {
            line.remove_suffix( 1 );
        }
        ++lineCount;
        perLine( line, lineCount );
        if( e == bytes.size() )
        {
            break;
        }
        i = e + 1;
    }
    return lineCount;
}

inline std::string_view trimView( std::string_view s )
{
    std::size_t a = 0, b = s.size();
    while( a < b && std::isspace( (unsigned char)s[a] ) )
    {
        ++a;
    }
    while( b > a && std::isspace( (unsigned char)s[b - 1] ) )
    {
        --b;
    }
    return s.substr( a, b - a );
}

// The identifier starting at `i` (empty if src[i] does not open one), advancing `i` past it.
inline std::string_view takeIdent( std::string_view src, std::size_t& i )
{
    const std::size_t s = i;
    while( i < src.size() && identByte( (unsigned char)src[i] ) )
    {
        ++i;
    }
    return src.substr( s, i - s );
}

// Every identifier mentioned in `expr` (a preprocessor condition), skipping the `defined` keyword itself.
inline std::vector<std::string_view> identsIn( std::string_view expr )
{
    std::vector<std::string_view> out;
    for( std::size_t i = 0; i < expr.size(); )
    {
        if( !identByte( (unsigned char)expr[i] ) ) { ++i; continue; }
        const std::string_view id = takeIdent( expr, i );
        if( !id.empty() && id != "defined" && !std::isdigit( (unsigned char)id[0] ) )
        {
            out.push_back( id );
        }
    }
    return out;
}

// ── per-file harvest ─────────────────────────────────────────────────────────────────────────────────────

// What one file contributes, before gate identity is resolved across the whole tree.
struct FileHarvest
{
    struct Def  { std::string name; std::string value; std::uint32_t line; GateKind kind; };
    struct Cond { std::vector<std::string> idents; std::uint32_t line; std::uint32_t lines; };
    struct Read { std::string name; std::uint32_t line; };

    std::vector<Def>  defs;
    std::vector<Cond> conds;
    std::vector<Read> reads;
};

// One open `#if` region while scanning — its start line and the identifiers its condition mentioned.
struct OpenCond
{
    std::vector<std::string> idents;
    std::uint32_t            line = 0;
    bool                     declared = false;   // a `#define NAME …` for this guard's own name fired inside it
};

// Handle one preprocessor directive line. `pending` carries the `#ifndef NAME` seen on the previous
// directive so the `#define NAME VALUE` that follows it can be recognised as the guarded-default idiom.
inline void harvestDirective( std::string_view d, std::uint32_t lineNo, FileHarvest& fh,
                              std::vector<OpenCond>& stack, std::string& pendingIfndef )
{
    std::size_t            i = 0;
    const std::string_view kw = takeIdent( d, i );
    const std::string_view rest = trimView( d.substr( i ) );

    if( kw == "define" )
    {
        std::size_t j = 0;
        const std::string_view name = takeIdent( rest, j );
        // The trailing comment is NOT part of the value: `#define F 1   // shipped ON` must report "1",
        // not the whole rest of the line (which then lands verbatim in an XML attribute).
        std::string_view raw = rest.substr( j );
        if( const std::size_t c = raw.find( "//" ); c != std::string_view::npos )
        {
            raw = raw.substr( 0, c );
        }
        if( const std::size_t c = raw.find( "/*" ); c != std::string_view::npos )
        {
            raw = raw.substr( 0, c );
        }
        const std::string value( trimView( raw ) );

        // A VALUE is required. `#ifndef X / #define X` with nothing after it is an INCLUDE GUARD, which
        // wears the identical shape — and every header in the tree has one, so admitting them would bury
        // the real gates under one row per file. A feature gate always states its default (`0` / `1`);
        // that is the whole point of the idiom (see the LIMITS note in the help text).
        // `#define CHILD MASTER` is a READ of MASTER — and often its ONLY one, when a master switch exists
        // purely to drive sub-gates (its own `#if` count is zero by construction). Without this the master
        // fails the has-a-reader filter below and disappears from the report entirely, which is precisely
        // backwards: it is the switch the owner actually flips.
        if( !value.empty() && ( std::isalpha( (unsigned char)value[0] ) || value[0] == '_' ) )
        {
            std::size_t k = 0;
            const std::string_view target = takeIdent( std::string_view( value ), k );
            if( k == value.size() )
            {
                fh.reads.push_back( FileHarvest::Read { std::string( target ), lineNo } );
            }
        }

        if( name == pendingIfndef && !name.empty() && !value.empty() )
        {
            fh.defs.push_back( FileHarvest::Def{ std::string( name ), value, lineNo, GateKind::Compile } );
            // The enclosing `#ifndef NAME` is this gate's DECLARATION, not a use of it — mark it so the
            // region is not later counted as guarded code or as a read site of the gate it declares.
            if( !stack.empty() && stack.back().idents.size() == 1 && stack.back().idents[0] == name )
            {
                stack.back().declared = true;
            }
        }
        pendingIfndef.clear();
        return;
    }

    if( kw == "ifndef" )
    {
        std::size_t j = 0;
        const std::string_view name = takeIdent( rest, j );
        pendingIfndef.assign( name );
        stack.push_back( OpenCond{ { std::string( name ) }, lineNo } );
        return;
    }
    pendingIfndef.clear();

    if( kw == "if" || kw == "ifdef" || kw == "elif" )
    {
        // `#if !defined(NAME)` is the same guard idiom spelled the other way; treat it like `#ifndef NAME`
        // so the `#define` beneath it is still recognised as that gate's default.
        std::vector<std::string> ids;
        for( std::string_view s : identsIn( rest ) )
        {
            ids.emplace_back( s );
        }
        if( kw == "if" && rest.find( '!' ) != std::string_view::npos && rest.find( "defined" ) != std::string_view::npos && ids.size() == 1 )
        {
            pendingIfndef = ids[0];
        }
        if( kw == "elif" && !stack.empty() )
        {
            stack.back().idents.insert( stack.back().idents.end(), ids.begin(), ids.end() );
        }
        else
        {
            stack.push_back( OpenCond { std::move( ids ), lineNo } );
        }
        return;
    }

    if( kw == "endif" )
    {
        if( stack.empty() )
        {
            return; // unbalanced (a file fragment) — degrade, never crash
        }
        OpenCond top = std::move( stack.back() );
        stack.pop_back();
        if( top.declared )
        {
            return; // the gate's own declaration guard — not a use of it
        }
        fh.conds.push_back( FileHarvest::Cond{ std::move( top.idents ), top.line,
                                               ( lineNo > top.line ) ? ( lineNo - top.line - 1 ) : 0u } );
    }
}

// ── what counts as CODE on a line (the anti-cry-wolf filter for the env lane) ────────────────────────────
// A gate harvested out of a doc comment or out of a string literal is not a gate, it is a mention of one.
// Measured on this repo before the filter existed: 7 of 45 reported gates (~16%) came from exactly there —
// `NAME` from THIS header's own `getenv("NAME")` doc comment, `,` and `, ` from the commas BETWEEN the probe
// spellings in the table below, `" sym="` from a single-quoted shell fragment, and `CANYON_*` / `env` from
// markdown prose. Every one of them then accrued read sites and sorted alongside real switches.

// Where a line stops being code, per language family. `#` is a COMMENT opener in Python/shell/Ruby and the
// preprocessor's DIRECTIVE opener in C — the two must never share a rule, which is why this is a per-file
// property rather than one global guess.
struct LineSyntax
{
    bool hasSlashComments = true;    // `//` to end of line and `/* … */` across lines — C family + brace langs
    bool hasHashComments  = false;   // `#` to end of line — Python / shell / Ruby / Perl / YAML / CMake
    bool hasHeredocs      = false;   // `<<WORD` opens a multi-line string — SHELL ONLY, because `a << B` is a
                                     //   shift in Python and Ruby and mistaking one for a heredoc would blind
                                     //   the rest of the file
    bool isProse          = false;   // markdown or an extracted-doc format: the env lane skips it entirely
};

inline constexpr std::string_view kShellExtTable[] = { ".sh", ".bash", ".zsh" };

inline constexpr std::string_view kHashCommentExtTable[] = {
    ".py", ".pyi", ".sh", ".bash", ".zsh", ".rb", ".pl", ".cmake", ".yml", ".yaml", ".toml", ".r", ".jl"
};

inline LineSyntax lineSyntaxFor( std::string_view path )
{
    const std::string ext = docparse::lowerExtOf( path );
    LineSyntax        syn;
    for( std::string_view hashExt : kHashCommentExtTable )
    {
        if( ext == hashExt )
        {
            syn.hasHashComments = true;
            syn.hasSlashComments = false;
            for( std::string_view shellExt : kShellExtTable )
            {
                if( ext == shellExt )
                {
                    syn.hasHeredocs = true;
                }
            }
            return syn;
        }
    }
    if( ext == ".md" || ext == ".markdown" || ext == ".rst" || ext == ".txt" || docparse::isDocExtension( ext ) )
    {
        syn.isProse = true;
    }
    return syn;
}

// Visit every byte of `line` that is CODE — outside every comment and outside every string literal — handing
// its index to `onCode`. `isInBlockComment` carries `/* … */` across lines, so it is the caller's per-file
// state, not a per-line local. Classification and probing are fused so no per-line buffer is allocated.
template<class OnCode>
inline void forEachCodeByte( std::string_view line, const LineSyntax& syn, bool& isInBlockComment, OnCode&& onCode )
{
    char quote = 0;
    for( std::size_t i = 0; i < line.size(); ++i )
    {
        const char c = line[i];
        if( isInBlockComment )
        {
            if( c == '*' && i + 1 < line.size() && line[ i + 1 ] == '/' ) { isInBlockComment = false; ++i; }
            continue;
        }
        if( quote != 0 )
        {
            if( c == '\\' ) { ++i; continue; }                      // an escaped byte closes nothing
            if( c == quote )
            {
                quote = 0;
            }
            continue;
        }
        if( c == '"' || c == '\'' ) { quote = c; continue; }
        if( syn.hasSlashComments && c == '/' && i + 1 < line.size() )
        {
            if( line[i + 1] == '/' )
            {
                return; // line comment: nothing after it is code
            }
            if( line[ i + 1 ] == '*' ) { isInBlockComment = true; ++i; continue; }
        }
        if( syn.hasHashComments && c == '#' )
        {
            return;
        }
        onCode( i );
    }
}

// Every `getenv`-family read on one line (the env lane). Python's `os.environ.get(...)` and `os.getenv(...)`
// share the literal-argument shape, so one probe covers C/C++/ObjC and Python alike.
//
// Three filters, all narrower than the old "find the probe anywhere, then take the next quoted run":
//   1. the probe must sit in CODE (forEachCodeByte), and must open its own identifier (`my_getenv` is not it);
//   2. it must wear the CALL shape `probe ( "…" )` — the loose reader turned the commas separating the probe
//      SPELLINGS in kEnvProbeTable below into gates named `,` and `, `, because it happily read across a `"`
//      that closed one literal and into the one that opened the next;
//   3. the harvested name must be identifier-shaped.
// `isInBlockComment` is threaded through from the file scan. Deliberately still permissive about WHICH call
// it is: `std::getenv( "RIPWIRE_NO_MENTION" )`, `os.getenv("X")` and `os.environ["X"]` all match.
inline constexpr std::string_view kEnvProbeTable[] = { "getenv", "environ.get", "environ[" };

// The environment-variable name a `probe` occurrence at `at` reads, or "" when this occurrence is not a call
// of the shape `probe ( "NAME" )`. Filters 2 and 3 live here: the walk from the probe to the literal never
// leaves the ONE call (the old reader crossed a `"` that closed one literal and entered the next, which is
// how the commas separating kEnvProbeTable's own spellings became gates named `,` and `, `), and the name it
// finds must be identifier-shaped.
inline std::string_view envNameAt( std::string_view line, std::size_t at, std::string_view probe )
{
    if( line.compare( at, probe.size(), probe ) != 0 )
    {
        return {};
    }

    std::size_t i = at + probe.size();
    if( probe.back() != '[' )                                            // `environ[` already opened its own
    {
        while( i < line.size() && std::isspace( (unsigned char)line[i] ) )
        {
            ++i;
        }
        if( i >= line.size() || line[i] != '(' )
        {
            return {};
        }
        ++i;
    }
    while( i < line.size() && std::isspace( (unsigned char)line[i] ) )
    {
        ++i;
    }
    if( i >= line.size() || line[i] != '"' )
    {
        return {}; // computed name — cannot be named
    }

    const std::size_t close = line.find( '"', i + 1 );
    if( close == std::string_view::npos )
    {
        return {};
    }

    const std::string_view name = line.substr( i + 1, close - i - 1 );
    return isIdentShaped( name, 1, kMaxEnvNameLen ) ? name : std::string_view{};
}

inline void harvestEnvReads( std::string_view line, std::uint32_t lineNo, FileHarvest& fh,
                             const LineSyntax& syn, bool& isInBlockComment )
{
    forEachCodeByte( line, syn, isInBlockComment, [ & ]( std::size_t at )
                     {
        if( at > 0 && identByte( (unsigned char)line[ at - 1 ] ) ) { return;   // mid-identifier — not a call of ours
}
        for( std::string_view probe : kEnvProbeTable )
        {
            const std::string_view name = envNameAt( line, at, probe );
            if( name.empty() ) { continue;
}
            fh.reads.push_back( FileHarvest::Read{ std::string( name ), lineNo } );
            fh.defs.push_back( FileHarvest::Def{ std::string( name ), "unset", lineNo, GateKind::Env } );
            return;
        } } );
}

// `option( NAME "doc" ON )` — CMake's own declaration of a build switch, with its default as the LAST token.
// A missing default means OFF (CMake's documented behavior), which is exactly the dark case.
inline void harvestCMakeOption( std::string_view line, std::uint32_t lineNo, FileHarvest& fh )
{
    const std::size_t at = line.find( "option" );
    if( at == std::string_view::npos )
    {
        return;
    }
    if( at > 0 && identByte( (unsigned char)line[at - 1] ) )
    {
        return; // e.g. `add_option(`
    }
    std::size_t i = at + 6;
    while( i < line.size() && std::isspace( (unsigned char)line[i] ) )
    {
        ++i;
    }
    if( i >= line.size() || line[i] != '(' )
    {
        return;
    }
    ++i;
    while( i < line.size() && std::isspace( (unsigned char)line[i] ) )
    {
        ++i;
    }
    const std::string_view name = takeIdent( line, i );
    if( name.empty() )
    {
        return;
    }

    const std::size_t close = line.rfind( ')' );
    std::string       def( "OFF" );
    if( close != std::string_view::npos && close > i )
    {
        std::string_view tail = trimView( line.substr( i, close - i ) );
        const std::size_t sp  = tail.find_last_of( " \t\"" );
        const std::string_view last = ( sp == std::string_view::npos ) ? tail : trimView( tail.substr( sp + 1 ) );
        if( !last.empty() && last.find( '"' ) == std::string_view::npos )
        {
            def.assign( last );
        }
    }
    fh.defs.push_back( FileHarvest::Def{ std::string( name ), def, lineNo, GateKind::CMake } );
}

// The delimiter word a shell HEREDOC opener on this line introduces, or "" if there is none. A heredoc body
// is a multi-line STRING LITERAL — text a script writes to a file — so nothing inside it declares a gate of
// THIS repo. Measured: gate scripts write C fixtures with `cat >x.h <<'EOF' … #ifndef SYNFIX_FEATURE …`, and
// without this the fixture's gates land in the report as if the shell script itself declared them.
// `<<<` (a here-STRING) and `1 << 2` (a shift) both fall out: neither is followed by a bare word.
inline std::string_view heredocDelimiterOn( std::string_view line )
{
    for( std::size_t at = line.find( "<<" ); at != std::string_view::npos; at = line.find( "<<", at + 1 ) )
    {
        std::size_t i = at + 2;
        if( i < line.size() && line[i] == '<' )
        {
            continue; // <<< is a here-string, not a heredoc
        }
        if( i < line.size() && line[i] == '-' )
        {
            ++i; // <<- strips leading tabs
        }
        if( i < line.size() && ( line[i] == '\'' || line[i] == '"' ) )
        {
            ++i;
        }
        const std::string_view word = takeIdent( line, i );
        if( !word.empty() )
        {
            return word;
        }
    }
    return {};
}

// Scan one file's bytes into a FileHarvest. `isCMake` selects the CMake lane; everything else runs the
// preprocessor + getenv lanes (a getenv read is just as real in Python or shell as in C++), with `path`
// choosing the comment syntax those lanes must respect.
//
// A PROSE file returns empty. A design doc writing `getenv("CANYON_*")` or `#ifndef F / #define F 0` in a
// fenced example is DOCUMENTING a gate — often someone else's — and admitting it declares switches this repo
// does not have. Markdown is also where `--flags`' own help text lives, so the verb was reading itself.
inline FileHarvest harvestFile( std::string_view bytes, std::string_view path, bool isCMake )
{
    FileHarvest           fh;
    const LineSyntax      syn = isCMake ? LineSyntax{ /*slash=*/false, /*hash=*/true, /*heredoc=*/false, /*prose=*/false }
                                      : lineSyntaxFor( path );
    if( syn.isProse )
    {
        return fh;
    }

    std::vector<OpenCond> stack;
    std::string           pendingIfndef;
    std::string           heredocDelimiter;              // non-empty ⇒ this line is heredoc BODY, i.e. data
    bool                  isInBlockComment = false;

    forEachLine( bytes, [ & ]( std::string_view line, std::uint32_t lineIndex )
    {
        if( isCMake )
        {
            harvestCMakeOption( line, lineIndex, fh );
            // A CMake mention of an already-declared option (`${NAME}`, a generator expression, a
            // target_compile_definitions row) is a READ site — it is where the switch reaches the build.
            for( std::string_view id : identsIn( line ) )
            {
                if( id.size() > 2 )
                {
                    fh.reads.push_back( FileHarvest::Read { std::string( id ), lineIndex } );
                }
            }
            return;
        }

        // Heredoc bodies, in the shell family only: skipped whole, until their own delimiter line closes them.
        if( !heredocDelimiter.empty() )
        {
            if( trimView( line ) == heredocDelimiter )
            {
                heredocDelimiter.clear();
            }
            return;
        }

        // The block-comment state must be read BEFORE the env lane advances it, so a `#define` on the first
        // line of a `/* … */` block is judged by the state the line OPENED in.
        const bool wasInBlockComment = isInBlockComment;
        harvestEnvReads( line, lineIndex, fh, syn, isInBlockComment );

        // The opener line itself IS code (it can carry a real call); only what follows it is data. A `#`
        // comment mentioning a heredoc must not open one, or the rest of the file goes dark.
        if( syn.hasHeredocs && !trimView( line ).empty() && trimView( line )[0] != '#' )
        {
            heredocDelimiter.assign( heredocDelimiterOn( line ) );
        }

        // The preprocessor lane is C-family only. In a hash-comment language every `#` line is a comment, and
        // feeding those to harvestDirective made `# if the cache is warm` open an unbalanced `#if` region.
        if( wasInBlockComment || syn.hasHashComments )
        {
            return;
        }
        const std::string_view t = trimView( line );
        if( t.empty() || t[0] != '#' )
        {
            return;
        }
        harvestDirective( trimView( t.substr( 1 ) ), lineIndex, fh, stack, pendingIfndef );
    } );
    return fh;
}

// ── tree walk + resolution ───────────────────────────────────────────────────────────────────────────────

inline bool readWhole( const std::string& path, std::string& out )
{
    std::FILE* fp = std::fopen( path.c_str(), "rb" );
    if( !fp )
    {
        return false;
    }
    out.clear();
    char        buf[ 65536 ];
    std::size_t n = 0;
    while( ( n = std::fread( buf, 1, sizeof( buf ), fp ) ) > 0 )
    {
        out.append( buf, n );
        if( out.size() > kMaxFlagFileBytes ) { out.clear(); std::fclose( fp ); return false; }
    }
    std::fclose( fp );
    return true;
}

// The CMake files under `root`, sorted. ingest() never collects these (CMake is not one of the indexed
// grammars), so this is the ONE crawl this module owns; every other file it reads comes from the caller's
// already-crawled, already-excluded ingest file list.
inline std::vector<std::string> collectCMakeFiles( const std::string& root, const std::vector<std::string>& excludes )
{
    namespace fs = std::filesystem;
    std::vector<std::string> out;
    std::error_code          ec;
    fs::recursive_directory_iterator it( root, fs::directory_options::skip_permission_denied, ec );
    if( ec ) { DEGRADED_PATH_ALERT( "flags: cannot walk root for CMake files — cmake gates omitted" ); return out; }

    const fs::recursive_directory_iterator end;
    for( ; it != end; it.increment( ec ) )
    {
        if( ec ) { ec.clear(); continue; }
        const std::string base = it->path().filename().string();

        // Prune with ingest's OWN denylist (ingest.h kCrawlSkipDirs), plus a CMakeCache.txt sentinel for
        // build-output trees. Without this the walk finds every nested agent worktree's and build dir's copy
        // of CMakeLists.txt, and a stale copy declaring `option(X … OFF)` shadows the real `ON` — measured on
        // the motivating repo, where a worktree copy inverted CANYON_SPHERE_FIRE's reported default.
        if( it->is_directory( ec ) )
        {
            std::error_code sec;
            if( isSkippedCrawlDir( base ) || std::filesystem::exists( it->path() / "CMakeCache.txt", sec ) )
            { it.disable_recursion_pending(); continue; }
            continue;
        }

        const std::string p = it->path().string();
        bool skip = false;
        for( const std::string& x : excludes )
        {
            if( !x.empty() && p.find( x ) != std::string::npos ) { skip = true; break; }
        }
        if( skip )
        {
            continue;
        }
        if( base == "CMakeLists.txt" || ( base.size() > 6 && base.compare( base.size() - 6, 6, ".cmake" ) == 0 ) )
        {
            out.push_back( p );
        }
    }
    std::sort( out.begin(), out.end() );
    return out;
}

struct FlagsResult
{
    std::vector<Gate> gates;          // sorted: dark first, then by guarded size desc, then name
    std::uint32_t     dark = 0;
    std::uint32_t     compileCount = 0, cmakeCount = 0, envCount = 0;
    std::size_t       filesScanned = 0;
};

// Fold one harvested definition into the gate table, applying the cmake-beats-compile override rule.
inline void mergeDef( gtl::btree_map<std::string, Gate>& gates, const FileHarvest::Def& d, const std::string& rel )
{
    Gate& g = gates[ d.name ];
    if( g.name.empty() )
    {
        g.name = d.name;  g.kind = d.kind;  g.def = d.value;  g.defSite = Site{ rel, d.line };
        return;
    }
    if( g.kind == d.kind )
    {
        return; // first site of a kind wins (sorted walk ⇒ stable)
    }

    // Different kinds for one name: CMake is what the build actually passes, so it wins the headline and the
    // other becomes the <also/> row. Env never displaces a real build switch (it is a runtime read, not a
    // declaration), so it only fills the loser slot.
    const bool cmakeIncoming = d.kind == GateKind::CMake;
    if( cmakeIncoming && g.kind != GateKind::CMake )
    {
        g.hasAlso = true;  g.alsoKind = g.kind;  g.alsoDef = g.def;  g.alsoSite = g.defSite;
        g.kind = d.kind;   g.def = d.value;      g.defSite = Site{ rel, d.line };
    }
    else if( !g.hasAlso )
    {
        g.hasAlso = true;  g.alsoKind = d.kind;  g.alsoDef = d.value;  g.alsoSite = Site{ rel, d.line };
    }
}

// Alias resolution. A gate whose DEFAULT is literally another gate's name (`#define F_WALLS F_ALL`)
// inherits that gate's effective default — so a child of an OFF master reads dark, as it truly is — and
// rolls its guarded size up to the master, which otherwise reports a misleading loc="0" despite being the
// switch that actually turns the code on. Bounded walk: a cycle (`#define A B` / `#define B A`) stops at
// the depth cap rather than spinning; a malformed header must never hang the report.
inline void resolveAliases( gtl::btree_map<std::string, Gate>& gates )
{
    constexpr std::uint32_t kMaxAliasDepth = 8;
    for( auto& [ name, g ] : gates )
    {
        std::string cursor = g.def;
        std::string master;
        for( std::uint32_t depth = 0; depth < kMaxAliasDepth; ++depth )
        {
            const auto p = gates.find( cursor );
            if( p == gates.end() || p->first == name )
            {
                break;
            }
            if( depth == 0 )
            {
                g.aliasParent = cursor; // the immediate link, before the walk climbs past it
            }
            master = cursor;
            cursor = p->second.def;
        }
        if( master.empty() )
        {
            continue;
        }
        const auto m = gates.find( master );
        if( m == gates.end() )
        {
            continue;
        }
        g.aliasOf = master;
        g.def     = m->second.def;                                       // inherit the master's effective default
    }

    // Roll up through a plain vector rather than while iterating the map: the parent being CREDITED is a
    // different key than the child being read, and gtl::btree_map promises no reference stability across a
    // lookup that could insert.
    struct RollUp { std::string parent; std::uint32_t regions, lines; };
    std::vector<RollUp> rolls;
    for( const auto& [ name, g ] : gates )
    {
        if( !g.aliasOf.empty() )
        {
            rolls.push_back( RollUp { g.aliasOf, g.regions, g.guardedLines } );
        }
    }
    for( const RollUp& r : rolls )
    {
        const auto p = gates.find( r.parent );
        if( p == gates.end() )
        {
            continue;
        }
        ++p->second.aliasCount;
        p->second.aliasRegions += r.regions;
        p->second.aliasLines   += r.lines;
    }
}

// Harvest every file, then resolve: gate identities first (so a read site can be attributed only to a name
// that is actually a declared gate), then regions and reads, then alias chains.
// `keepUnreadGates` (default false = the `--flags` contract, byte-identical): normally a DECLARED name with
// no reader is dropped as a dead name. `--flip` needs them kept — an alias CHILD (`#define F_WALLS F_ALL`)
// whose code is consumed as a VALUE has zero preprocessor readers by construction, so the dead-name filter
// deletes exactly the gates a master's flip lights. The flag only widens the table; it changes no gate's fields.
inline FlagsResult computeFlags( const IngestResult& ing, const std::string& root,
                                 const std::vector<std::string>& excludes, std::string_view filter,
                                 bool keepUnreadGates = false )
{
    struct Harvested { std::string rel; FileHarvest fh; };
    std::vector<Harvested> harvest;

    const auto scan = [ & ]( const std::string& full, bool isCMake )
    {
        std::string bytes;
        if( !readWhole( full, bytes ) )
        {
            return;
        }
        std::string rel( relForHash( full, root ) );
        FileHarvest fh = harvestFile( bytes, full, isCMake );
        harvest.push_back( Harvested{ std::move( rel ), std::move( fh ) } );
    };

    for( const std::string& f : ing.files )
    {
        scan( f, false );
    }
    for( const std::string& f : collectCMakeFiles( root, excludes ) )
    {
        scan( f, true );
    }

    // Pass 1 — gate identities (declarations only).
    gtl::btree_map<std::string, Gate> gates;
    for( const Harvested& h : harvest )
    {
        for( const FileHarvest::Def& d : h.fh.defs )
        {
            mergeDef( gates, d, h.rel );
        }
    }

    // Pass 2 — regions and read sites, attributed only to declared gates.
    for( const Harvested& h : harvest )
    {
        for( const FileHarvest::Cond& c : h.fh.conds )
        {
            for( const std::string& id : c.idents )
            {
                const auto it = gates.find( id );
                if( it == gates.end() )
                {
                    continue;
                }
                ++it->second.regions;
                it->second.guardedLines += c.lines;
                it->second.reads.push_back( Site{ h.rel, c.line } );
                it->second.regionSpans.push_back( Region{ Site{ h.rel, c.line }, c.lines } );
            }
        }
        for( const FileHarvest::Read& r : h.fh.reads )
        {
            const auto it = gates.find( r.name );
            if( it == gates.end() )
            {
                continue;
            }
            it->second.reads.push_back( Site{ h.rel, r.line } );
        }
    }

    resolveAliases( gates );

    FlagsResult res;
    res.filesScanned = harvest.size();
    for( auto& [ name, g ] : gates )
    {
        if( !filter.empty() && name.find( filter ) == std::string::npos )
        {
            continue;
        }
        // A declaration with no reader is a dead name, not a gate — the getenv lane especially would
        // otherwise report every one-off environment probe as a repo-wide switch.
        if( g.reads.empty() && !keepUnreadGates )
        {
            continue;
        }

        // `#endif` order is not start-line order once regions nest (the inner one closes first) — sort so the
        // span list is deterministic and reads top-down like the file does.
        std::sort( g.regionSpans.begin(), g.regionSpans.end(),
                   []( const Region& a, const Region& b ) { return siteLess( a.site, b.site ); } );
        std::sort( g.reads.begin(), g.reads.end(), siteLess );
        g.reads.erase( std::unique( g.reads.begin(), g.reads.end(),
                                    []( const Site& a, const Site& b ) { return a.path == b.path && a.line == b.line; } ), g.reads.end() );
        if( isDarkDefault( g.def ) )
        {
            ++res.dark;
        }
        if( g.kind == GateKind::CMake )
        {
            ++res.cmakeCount;
        }
        else if( g.kind == GateKind::Env )
        {
            ++res.envCount;
        }
        else
        {
            ++res.compileCount;
        }
        res.gates.push_back( std::move( g ) );
    }

    // Dark gates first (that IS the question), then by how much code they turn off INCLUDING what their
    // aliases guard (a master switch's weight is its children's), then by name.
    const auto weight = []( const Gate& g ) { return std::uint64_t( g.guardedLines ) + g.aliasLines; };
    std::sort( res.gates.begin(), res.gates.end(), [ & ]( const Gate& a, const Gate& b )
    {
        const bool ad = isDarkDefault( a.def ), bd = isDarkDefault( b.def );
        if( ad != bd )
        {
            return ad;
        }
        if( weight( a ) != weight( b ) )
        {
            return weight( a ) > weight( b );
        }
        return a.name < b.name;
    } );
    return res;
}

// ── XML emission (G4: minified, xmllint-clean; no `--` inside a comment, no `\n` outside CDATA) ──────────

using XmlEscaper = std::function<std::string( std::string_view )>;

inline void writeGate( std::FILE* out, const Gate& g, const XmlEscaper& ex, std::size_t maxSites )
{
    std::fprintf( out, "<gate name=\"%s\" kind=\"%s\" default=\"%s\" dark=\"%d\" regions=\"%u\" loc=\"%u\" reads=\"%zu\" p=\"%s\" l=\"%u\">",
                  ex( g.name ).c_str(), gateKindTag( g.kind ), ex( g.def ).c_str(), isDarkDefault( g.def ) ? 1 : 0,
                  g.regions, g.guardedLines, g.reads.size(), ex( g.defSite.path ).c_str(), g.defSite.line );
    if( !g.aliasOf.empty() )
    {
        std::fprintf( out, "<alias-of name=\"%s\"/>", ex( g.aliasOf ).c_str() );
    }
    if( g.aliasCount )
    {
        std::fprintf( out, "<aliases n=\"%u\" regions=\"%u\" loc=\"%u\"/>", g.aliasCount, g.aliasRegions, g.aliasLines );
    }
    if( g.hasAlso )
    {
        std::fprintf( out, "<also kind=\"%s\" default=\"%s\" p=\"%s\" l=\"%u\"/>",
                      gateKindTag( g.alsoKind ), ex( g.alsoDef ).c_str(), ex( g.alsoSite.path ).c_str(), g.alsoSite.line );
    }
    // "Nothing is dropped without a number": shownCount is what the loop will PRINT, so the <more/> remainder
    // is exactly what it will not. The `shown++ >= cap` form got this wrong twice over — it left the counter
    // at cap+1, so <more/> under-reported the drop by one, and at exactly cap+1 reads the element vanished
    // entirely and one row disappeared unmarked. abicheck.h::writeAbiRef is the shape this follows.
    const std::size_t shownCount = std::min( g.reads.size(), maxSites );
    for( std::size_t readIndex = 0; readIndex < shownCount; ++readIndex )
    {
        std::fprintf( out, "<read p=\"%s\" l=\"%u\"/>", ex( g.reads[ readIndex ].path ).c_str(), g.reads[ readIndex ].line );
    }
    if( g.reads.size() > shownCount )
    {
        std::fprintf( out, "<more reads=\"%zu\"/>", g.reads.size() - shownCount );
    }
    std::fprintf( out, "</gate>" );
}

inline void writeFlags( std::FILE* out, const FlagsResult& res, std::size_t maxSites )
{
    std::vector<char> esc;
    const XmlEscaper  ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };

    std::fprintf( out, "<!-- ripwire flags: what is BUILT but DARK here. Three gate patterns in one report: ifndef/define "
                       "header gates (kind=\"compile\"), CMake option() switches (kind=\"cmake\"), and getenv reads "
                       "(kind=\"env\", default unset). dark=\"1\" means the default keeps the guarded code out of the build; "
                       "regions/loc size what it turns off. When one name is BOTH a header gate and a CMake option the CMake "
                       "default wins (that is what the build passes) and the header shows as an also row. Lexical, not "
                       "preprocessed: this reports the in-repo default, never the value your build used. dark_gates on this root "
                       "is the COUNT of dark gates; it was spelled dark until that collided with the child bool. files= is THIS "
                       "verb's own harvest scan (source + CMakeLists files it read looking for gates) — a wider crawl than the "
                       "map's indexed corpus, so it will not equal the map's files= -->" );
    // §P8 collision: `dark=` was a COUNT here and a BOOL on the <gate/> children beneath — indistinguishable
    // to a parser. The count is renamed (index-vs-count rule) and reads correctly beside its
    // gates=/compile=/cmake=/env= siblings; it had ZERO parsers, so the bool half keeps its name.
    std::fprintf( out, "<flags gates=\"%zu\" dark_gates=\"%u\" compile=\"%u\" cmake=\"%u\" env=\"%u\" files=\"%zu\">",
                  res.gates.size(), res.dark, res.compileCount, res.cmakeCount, res.envCount, res.filesScanned );
    for( const Gate& g : res.gates )
    {
        writeGate( out, g, ex, maxSites );
    }
    std::fprintf( out, "</flags>" );
}

}}   // namespace rw::darkflags
