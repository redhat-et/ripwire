#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings
#include <string_view>       // %.*s (precision, pointer) collapses to one view


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
//   env     — `getenv("NAME")` / `std::getenv` / Python `os.environ.get` / `os.getenv` / JS/TS `process.env.NAME`. Default: unset.
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
#include "pageview.h"           // §P8: pageWindow / effectiveRowCap / secondaryCutAttrs — the ONE paging contract
#include "nextverb.h"           // P3: nextAttrXml — the ONE pasteable follow-up a cut root carries
#include "infra/Diagnostics.h"  // DISCLOSE
#include "infra/sortutil.h"     // svLess — the portable string_view order (portablebuildcheck #6b)
#include "infra/tablelookup.h"  // findByField — the shell keyword table

#include "btree.hpp"      // gtl::btree_map — sorted iteration (house rule: never std::map)

#include <algorithm>
#include <cctype>
#include <climits>
#include <cstdio>
#include <filesystem>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <tuple>
#include <vector>

namespace rw
{
namespace darkflags
{

constexpr std::size_t kMaxFlagFileBytes = 4u << 20;   // 4 MB — past this a "source" file is generated data
constexpr std::size_t kMaxSitesShown    = 8;          // <read> sites per gate; a DEFAULT, raisable by --limit=N (effectiveRowCap), lifted by --detail
constexpr std::size_t kMaxEnvNameLen    = 128;        // longest plausible environment-variable name

enum class GateKind : std::uint8_t { Compile = 0, CMake, Env };
inline constexpr std::size_t kGateKindCount = static_cast<std::size_t>( GateKind::Env ) + 1;
static_assert( enumCountIsExact<GateKind, kGateKindCount>(), "kGateKindCount must name the LAST GateKind — move it with the append" );

inline constexpr const char* kGateKindTag[] = { "compile", "cmake", "env" };
static_assert( std::size( kGateKindTag ) == kGateKindCount, "kGateKindTag is indexed by GateKind — one tag per enumerator" );

inline const char* gateKindTag( GateKind k ) noexcept { return kGateKindTag[ std::size_t( k ) ]; }

// ── the Bash read FORM (the shell env lane, harvestShellLine below) ────────────────────────────────────────
// A getenv call has one shape; a Bash parameter expansion has eight, and they say different things about the
// caller's obligation: `${X:?}` dies when X is missing, `${X:-d}` supplies its own default, `${X:+w}` and
// `[[ -n "$X" ]]` only ASK whether it is set. A contract check that joins a script's reads against what its
// caller supplies needs that distinction per site, so every Bash read carries it; every other lane's read
// carries ShellForm::None and emits exactly the bytes it always did.
enum class ShellForm : std::uint8_t { None = 0, Plain, Required, Default, UnsetDefault, SetTest, Assign };
inline constexpr std::size_t kShellFormCount = static_cast<std::size_t>( ShellForm::Assign ) + 1;
static_assert( enumCountIsExact<ShellForm, kShellFormCount>(), "kShellFormCount must name the LAST ShellForm — move it with the append" );

// `${X:?}`/`${X?}` required · `${X:-d}` default · `${X-d}` unset-default · `${X:+w}`/`${X+w}`/`-n`/`-z` settest ·
// `${X:=d}`/`${X=d}` assign (a default that is also written back) · `$X`/`${X}` plain
inline constexpr const char* kShellFormTag[] = { "", "plain", "required", "default", "unset-default", "settest", "assign" };
static_assert( std::size( kShellFormTag ) == kShellFormCount, "kShellFormTag is indexed by ShellForm — one tag per enumerator" );

struct ShellRead
{
    ShellForm   form = ShellForm::None;
    bool        hasOperator = false;   // the expansion carried an operator (`:-`, `?`, `+`, …): colon= is meaningful
    bool        isColon = false;       // the `:` spelling — an EMPTY value counts as unset
    bool        hasDefault = false;    // `-` / `:-` / `=` / `:=`: def holds the literal word, possibly ""
    char        test = 0;              // 'n' / 'z': the expansion is the operand of a `-n` / `-z` test
    std::string def;
};

struct Site
{
    std::string   path;
    std::uint32_t line = 0;
    ShellRead     sh;                  // Bash read sites only; form None everywhere else
};

// (path, line) first — the order every reader of a site list relies on — then the Bash form, so two different
// expansions of one name on one line keep a total, deterministic order instead of whatever std::sort left.
inline auto siteKey( const Site& s )
{
    return std::tie( s.path, s.line, s.sh.form, s.sh.hasOperator, s.sh.isColon, s.sh.test, s.sh.hasDefault, s.sh.def );
}
inline bool siteLess( const Site& a, const Site& b ) { return siteKey( a ) < siteKey( b ); }
inline bool siteSame( const Site& a, const Site& b ) { return siteKey( a ) == siteKey( b ); }

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

    // The shell env lane: every Bash site that ASSIGNS this name (`X=`, `export X=`, `local X`, `read X`, …),
    // repo-wide. A Bash read that FOLLOWS a write in its own file is the script's own state and is not a read
    // at all; the writes are still listed so a consumer joining a script against the files it sources can see
    // that a library set the name, which one file's lexical order cannot.
    std::vector<Site> writes;
    bool              isShellOnly = true;         // every declaration came from the shell lane (no getenv, #define, option())
    bool              isAmbient = false;          // kind env, a Bash read, and a name Bash or the login sets (kAmbientEnvNames)
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
    struct Def  { std::string name; std::string value; std::uint32_t line; GateKind kind; bool isShell = false; };
    struct Cond { std::vector<std::string> idents; std::uint32_t line; std::uint32_t lines; };
    // col (shell lane only): a read's `$`, or the column where a write takes effect; stmtCol: where that write's
    // statement starts, so a read between the two is the write's own right-hand side.
    struct Read { std::string name; std::uint32_t line; ShellRead sh = {}; std::uint32_t col = 0; std::uint32_t stmtCol = 0; };

    std::vector<Def>  defs;
    std::vector<Cond> conds;
    std::vector<Read> reads;
    std::vector<Read> writes;          // the shell env lane's assignments (sh unused)
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
    bool hasTemplates     = false;   // 0.6.6 D5: a backtick template literal — JavaScript / TypeScript ONLY (a shell `…` is
                                     //   a command substitution, a Go `…` a raw string: neither changes here)
};

inline constexpr std::string_view kTemplateLiteralExtTable[] = { ".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts" };

// 0.6.6 D5 (review B1): the per-file state of the JS/TS template literals that are open at a line boundary. Each entry
// is one open construct, innermost last: kTemplateText = inside a template's TEXT (a string), n >= 0 = inside a `${…}`
// substitution (CODE) with n unclosed `{` of its own. Empty = plain code. A template spans lines, so the caller keeps
// this per file, like the block-comment flag.
using TemplateStack = std::vector<std::int32_t>;
inline constexpr std::int32_t kTemplateText = -1;

inline constexpr std::string_view kShellExtTable[] = { ".sh", ".bash", ".zsh" };

inline constexpr std::string_view kHashCommentExtTable[] = {
    ".py", ".pyi", ".sh", ".bash", ".zsh", ".rb", ".rake", ".jbuilder", ".pl", ".cmake", ".yml", ".yaml", ".toml", ".r", ".jl"
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
    if( docparse::isProseExtension( ext ) )   // the shared prose vocabulary, not a fifth private list
    {
        syn.isProse = true;
    }
    syn.hasTemplates = std::find( std::begin( kTemplateLiteralExtTable ), std::end( kTemplateLiteralExtTable ), ext ) != std::end( kTemplateLiteralExtTable );
    return syn;
}

// 0.6.6 D5 (review B1): one byte of a JS/TS template construct. Returns true when the byte was consumed as template
// TEXT or template punctuation (never code), false when it is code the caller classifies as usual. `i` may advance
// past an escaped byte or the `{` of `${`.
inline bool stepTemplate( std::string_view line, std::size_t& i, TemplateStack& templates )
{
    const char c = line[i];
    if( !templates.empty() && templates.back() == kTemplateText )
    {
        if( c == '\\' ) { ++i; }                                            // an escaped byte closes nothing
        else if( c == '`' ) { templates.pop_back(); }                        // the template ends
        else if( c == '$' && i + 1 < line.size() && line[ i + 1 ] == '{' ) { templates.push_back( 0 ); ++i; }   // `${` opens code
        return true;
    }
    if( c == '`' )
    {
        templates.push_back( kTemplateText );
        return true;
    }
    if( !templates.empty() && c == '{' )
    {
        ++templates.back();
    }
    else if( !templates.empty() && c == '}' )
    {
        if( templates.back() == 0 )
        {
            templates.pop_back();                                            // `}` closes the `${`: back to the text
            return true;
        }
        --templates.back();
    }
    return false;
}

// Visit every byte of `line` that is CODE — outside every comment and outside every string literal — handing
// its index to `onCode`. `isInBlockComment` carries `/* … */` across lines, so it is the caller's per-file
// state, not a per-line local. Classification and probing are fused so no per-line buffer is allocated.
// `templates` (JS/TS only, syn.hasTemplates) carries open template literals the same way — see TemplateStack.
template<class OnCode>
inline void forEachCodeByte( std::string_view line, const LineSyntax& syn, bool& isInBlockComment, TemplateStack& templates, OnCode&& onCode )
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
        if( syn.hasTemplates && quote == 0 && stepTemplate( line, i, templates ) )
        {
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
// The identifier-shaped name inside ONE quoted literal that opens at `i` (after optional whitespace), with an opening
// quote from `quotes`, closed by the same quote; "" otherwise (a computed name, an unclosed literal, a non-name).
// Shared by the getenv-family call shape and Node's `process.env[...]` subscript.
inline std::string_view quotedEnvNameAt( std::string_view line, std::size_t i, std::string_view quotes )
{
    while( i < line.size() && std::isspace( (unsigned char)line[i] ) )
    {
        ++i;
    }
    if( i >= line.size() || quotes.find( line[i] ) == std::string_view::npos )
    {
        return {}; // computed name — cannot be named
    }
    const std::size_t close = line.find( line[i], i + 1 );
    if( close == std::string_view::npos )
    {
        return {};
    }
    const std::string_view name = line.substr( i + 1, close - i - 1 );
    return isIdentShaped( name, 1, kMaxEnvNameLen ) ? name : std::string_view{};
}

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
    return quotedEnvNameAt( line, i, "\"" );
}

// 0.6.6 D5: Node's environment read — `process.env.NAME`, `process.env["NAME"]`, `process.env['NAME']` — is the getenv of
// JavaScript and TypeScript, and a TS repo whose switches are all `process.env.X === "1"` answered gates="0" env="0".
// The name after the dot (or the one quoted literal in the brackets) must be identifier-shaped; `process.env` alone
// (`const env = process.env`, a spread) names nothing and is not a read. Same CODE-only filter as the probes above.
inline std::string_view processEnvNameAt( std::string_view line, std::size_t at )
{
    constexpr std::string_view probe = "process.env";
    if( line.compare( at, probe.size(), probe ) != 0 )
    {
        return {};
    }
    std::size_t i = at + probe.size();
    if( i < line.size() && line[i] == '.' )
    {
        std::size_t end = i + 1;
        while( end < line.size() && identByte( (unsigned char)line[end] ) )
        {
            ++end;
        }
        const std::string_view name = line.substr( i + 1, end - i - 1 );
        return isIdentShaped( name, 1, kMaxEnvNameLen ) ? name : std::string_view{};
    }
    return ( i < line.size() && line[i] == '[' ) ? quotedEnvNameAt( line, i + 1, "\"'`" ) : std::string_view{};
}

inline void harvestEnvReads( std::string_view line, std::uint32_t lineNo, FileHarvest& fh,
                             const LineSyntax& syn, bool& isInBlockComment, TemplateStack& templates )
{
    forEachCodeByte( line, syn, isInBlockComment, templates, [ & ]( std::size_t at )
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
        }
        if( const std::string_view nodeName = processEnvNameAt( line, at ); !nodeName.empty() )   // 0.6.6 D5
        {
            fh.reads.push_back( FileHarvest::Read{ std::string( nodeName ), lineNo } );
            fh.defs.push_back( FileHarvest::Def{ std::string( nodeName ), "unset", lineNo, GateKind::Env } );
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

// The shell env lane's own heredoc reader, for a `<<` the Bash scanner met in CODE (never inside a string, which is
// where the whole-line probe above can be fooled: `"operator<< missing"`). It needs more than the delimiter: an
// UNQUOTED one (`<<EOF`) still expands `$X` in the body, while `<<'EOF'`, `<<"EOF"` and `<<\EOF` expand nothing.
// Bash allows blanks before the word (`cat << EOF`). `at` is the first `<`; returns the word ("" when none) and the
// index of its last byte in `end`.
struct HeredocOpener
{
    std::string_view word;
    bool             isQuoted = false;
};

inline HeredocOpener heredocOpenerAt( std::string_view line, std::size_t at, std::size_t& end )
{
    std::size_t i = at + 2;
    end = at + 1;
    if( i < line.size() && line[i] == '<' )
    {
        end = i;
        return {}; // <<< is a here-string
    }
    if( i < line.size() && line[i] == '-' ) { ++i; }
    while( i < line.size() && ( line[i] == ' ' || line[i] == '\t' ) ) { ++i; }
    bool isQuoted = false;
    if( i < line.size() && ( line[i] == '\'' || line[i] == '"' || line[i] == '\\' ) )
    {
        isQuoted = true;
        ++i;
    }
    if( i >= line.size() || !( std::isalpha( (unsigned char)line[i] ) || line[i] == '_' ) )
    {
        return {};
    }
    const std::string_view word = takeIdent( line, i );
    if( isQuoted && i < line.size() && ( line[i] == '\'' || line[i] == '"' ) ) { ++i; }
    end = i - 1;
    return HeredocOpener{ word, isQuoted };
}

// ── the shell env lane: Bash parameter-expansion READS and the assignments that make them internal ───────
// A shell script has no getenv: every `$X` is an environment read unless the script itself set X first. So the
// lane records two things per file — each expansion with its form (ShellRead), and each assignment — and
// harvestFile drops a read that a write on an EARLIER line of the same file shadows. That is lexical order in
// one file, the same file-local precision every other lane here has; there is no flow, call or `source`
// analysis. The writes are kept as rows so a consumer that does model `source` can join them itself.
//
// What is CODE follows Bash, not forEachCodeByte's C-ish rule: `'…'` expands nothing (and spans lines), `"…"`
// expands `$X` but not `'`, `$( … )` opens a fresh command context even inside `"…"`, `#` is a comment only at
// the start of a word (`${#X}` and `$#` are not), and a backslash escapes the next byte. A heredoc body is
// literal text whose `$X` still expands unless its delimiter was quoted (harvestFile routes those lines to
// shellLiteralReads).

// Names Bash sets for every script, plus the two the login always supplies (HOME, PATH). A read of one is not a
// requirement on the caller, so the gate is tagged ambient="1" rather than dropped: the read is real, it is just
// never unsupplied. Sorted: binary-searched (finishGate).
inline constexpr std::string_view kAmbientEnvNames[] = {
    "BASH", "BASHOPTS", "BASHPID", "BASH_ALIASES", "BASH_ARGC", "BASH_ARGV", "BASH_ARGV0", "BASH_CMDS", "BASH_COMMAND",
    "BASH_EXECUTION_STRING", "BASH_LINENO", "BASH_REMATCH", "BASH_SOURCE", "BASH_SUBSHELL", "BASH_VERSINFO", "BASH_VERSION",
    "COLUMNS", "DIRSTACK", "EPOCHREALTIME", "EPOCHSECONDS", "EUID", "FUNCNAME", "GROUPS", "HISTCMD", "HOME", "HOSTNAME",
    "HOSTTYPE", "IFS", "LINENO", "LINES", "MACHTYPE", "OLDPWD", "OPTARG", "OPTERR", "OPTIND", "OSTYPE", "PATH", "PIPESTATUS",
    "PPID", "PS4", "PWD", "RANDOM", "REPLY", "SECONDS", "SHELLOPTS", "SHLVL", "SRANDOM", "UID",
};

// `GENERATED … DO NOT EDIT` in a `#` comment within the first docparse::kGeneratedMarkerHeadLines lines: a bundle a
// build step writes from a hand-edited source (fullsend-ai's `scripts/*.sh`, inlined from `*.src.sh` and its
// libraries). Its reads are the source's reads, counted twice and pinned to lines nobody edits, so the shell
// lane skips the whole file and the root discloses how many (generated_skipped=). Upper case on purpose: the
// prose "generated by `tool new`" in an ordinary header must not trip it.
inline bool hasGeneratedShellBanner( std::string_view bytes )
{
    bool          isGenerated = false;
    std::uint32_t seen = 0;
    forEachLine( bytes, [ & ]( std::string_view line, std::uint32_t )
    {
        if( isGenerated || ++seen > docparse::kGeneratedMarkerHeadLines )
        {
            return;
        }
        const std::string_view t = trimView( line );
        if( !t.empty() && t[0] == '#' && t.find( "GENERATED" ) != std::string_view::npos && t.find( "DO NOT EDIT" ) != std::string_view::npos )
        {
            isGenerated = true;
        }
    } );
    return isGenerated;
}

// `-n` / `-z` immediately before the expansion that opens at `dollarAt` (an optional `"` between): the operand
// of a set test. Returns 'n', 'z' or 0.
inline char shellSetTestBefore( std::string_view line, std::size_t dollarAt ) noexcept
{
    std::size_t k = dollarAt;
    if( k > 0 && line[ k - 1 ] == '"' ) { --k; }
    const std::size_t blanksEnd = k;
    while( k > 0 && ( line[ k - 1 ] == ' ' || line[ k - 1 ] == '\t' ) ) { --k; }
    if( k == blanksEnd || k < 2 || line[ k - 2 ] != '-' || ( line[ k - 1 ] != 'n' && line[ k - 1 ] != 'z' ) )
    {
        return 0;
    }
    if( k > 2 && !std::isspace( (unsigned char)line[ k - 3 ] ) && line[ k - 3 ] != '[' )
    {
        return 0;
    }
    return line[ k - 1 ];
}

// The index of the `}` closing the `${` whose body starts at `from` (nested `${` counted), or npos when the line
// ends first.
inline std::size_t shellBraceClose( std::string_view line, std::size_t from ) noexcept
{
    std::uint32_t depth = 1;
    for( std::size_t i = from; i < line.size(); ++i )
    {
        if( line[i] == '$' && i + 1 < line.size() && line[ i + 1 ] == '{' ) { ++depth; ++i; continue; }
        if( line[i] == '}' && --depth == 0 )
        {
            return i;
        }
    }
    return std::string_view::npos;
}

inline void shellLiteralReads( std::string_view line, std::size_t from, std::uint32_t lineNo, FileHarvest& fh );

// One `$…` expansion at `at` (line[at] == '$'): records the read, returns the index of its LAST byte (so the
// caller resumes after it), or `at` when nothing nameable starts here (`$1`, `$@`, `$(`, `${!X}`, a lone `$`).
// A braced expansion's WORD (`${X:-$Y}`) is scanned for its own reads here, as literal text, so a quote inside
// it can never unbalance the caller's quote state.
inline std::size_t shellExpansionAt( std::string_view line, std::size_t at, std::uint32_t lineNo, FileHarvest& fh )
{
    if( at + 1 >= line.size() )
    {
        return at;
    }
    ShellRead sh;
    sh.test = shellSetTestBefore( line, at );
    if( line[ at + 1 ] != '{' )
    {
        std::size_t i = at + 1;
        if( !( std::isalpha( (unsigned char)line[i] ) || line[i] == '_' ) )
        {
            return at;
        }
        const std::string_view name = takeIdent( line, i );
        if( name == "_" || name.size() > kMaxEnvNameLen )
        {
            return i - 1;   // `$_` is the last argument, not a variable
        }
        sh.form = sh.test ? ShellForm::SetTest : ShellForm::Plain;
        fh.reads.push_back( FileHarvest::Read{ std::string( name ), lineNo, std::move( sh ), std::uint32_t( at ) } );
        return i - 1;
    }

    std::size_t i = at + 2;
    if( i < line.size() && line[i] == '#' && i + 1 < line.size() && ( std::isalpha( (unsigned char)line[ i + 1 ] ) || line[ i + 1 ] == '_' ) )
    {
        ++i; // ${#X}: the length of X — still a read of X
    }
    const std::size_t close = shellBraceClose( line, at + 2 );
    const std::size_t end   = close == std::string_view::npos ? line.size() : close;
    if( i >= line.size() || !( std::isalpha( (unsigned char)line[i] ) || line[i] == '_' ) )
    {
        // ${!X} (indirection), ${1}, ${@}: nothing nameable — but its word may still hold reads
        shellLiteralReads( line.substr( 0, end ), std::min( i, end ), lineNo, fh );
        return end == line.size() ? end - 1 : end;
    }
    const std::string_view name = takeIdent( line, i );
    if( i < end && line[i] == '[' )
    {
        const std::size_t rb = line.find( ']', i );
        i = ( rb == std::string_view::npos || rb > end ) ? end : rb + 1;   // ${X[@]} / ${X[0]}: a read of the array X
    }
    std::size_t wordFrom = end;
    if( i < end )
    {
        const bool        isColon = line[i] == ':';
        const std::size_t opAt    = isColon ? i + 1 : i;
        const char        op      = opAt < end ? line[ opAt ] : '\0';
        if( op == '-' || op == '=' || op == '?' || op == '+' )
        {
            sh.hasOperator = true;
            sh.isColon     = isColon;
            sh.form        = op == '-' ? ( isColon ? ShellForm::Default : ShellForm::UnsetDefault )
                           : op == '=' ? ShellForm::Assign
                           : op == '?' ? ShellForm::Required
                                       : ShellForm::SetTest;
            wordFrom = opAt + 1;
            if( op == '-' || op == '=' )
            {
                sh.hasDefault = true;
                sh.def.assign( line.substr( wordFrom, end - wordFrom ) );
            }
        }
        else
        {
            wordFrom = i;   // ${X:0:3}, ${X%pat}, ${X/a/b}, ${X^^}: a plain read; the rest may hold reads
        }
    }
    if( sh.form == ShellForm::None )
    {
        sh.form = sh.test ? ShellForm::SetTest : ShellForm::Plain;
    }
    if( name != "_" && name.size() <= kMaxEnvNameLen )
    {
        if( sh.form == ShellForm::Assign )
        {
            fh.writes.push_back( FileHarvest::Read{ std::string( name ), lineNo, {}, std::uint32_t( end ), std::uint32_t( at ) } );   // ${X:=d} sets X past its `}`
        }
        fh.reads.push_back( FileHarvest::Read{ std::string( name ), lineNo, std::move( sh ), std::uint32_t( at ) } );
    }
    if( wordFrom < end )
    {
        shellLiteralReads( line.substr( 0, end ), wordFrom, lineNo, fh );
    }
    return end == line.size() ? end - 1 : end;
}

// Every expansion in LITERAL text — a heredoc body, a braced expansion's word — where quotes are ordinary bytes and
// only a backslash protects a `$`. `line[from, size)` is the text; indices stay line-absolute so a read's col is too.
inline void shellLiteralReads( std::string_view text, std::size_t from, std::uint32_t lineNo, FileHarvest& fh )
{
    for( std::size_t i = from; i < text.size(); ++i )
    {
        if( text[i] == '\\' ) { ++i; continue; }
        if( text[i] == '$' )
        {
            i = shellExpansionAt( text, i, lineNo, fh );
        }
    }
}

// The scanner's state across lines: quoting and command context nest (`"$( cmd "$X" )"`), and both `'…'` and `"…"`
// may span lines, so this is per FILE, like forEachCodeByte's block-comment flag.
struct ShellScan
{
    // What the words after a command keyword mean, until the command ends.
    enum class Kw : std::uint8_t { None, Decl, Export, Read, MapFile, ForName, GetOpts, PrintfV };

    struct Frame
    {
        bool          isDq = false;        // inside "…" (no words, no comments: one string)
        std::int32_t  parens = 0;          // a `$( … )` frame: open parens; 0 = the file's top level
        bool          atWordStart = true;
        bool          isCmdPos = true;     // the next word is a command name (or a prefix assignment)
        Kw            kw = Kw::None;
        char          optArg = 0;          // the option letter whose argument the next word is (read -p, mapfile -d, …)
        std::uint8_t  wordsLeft = 0;       // getopts: optstring to skip before the name
    };

    std::vector<Frame> frames{ Frame{} };
    bool               isInSingle = false;
    bool               isAnsiC = false;      // the open single quote is `$'…'`: backslash escapes inside it
    bool               isContinued = false;  // the previous line ended in `\`: the same command goes on
    std::string        heredocWord;          // non-empty: the lines until this delimiter are a heredoc BODY
    bool               isHeredocQuoted = false;
};

inline constexpr std::string_view kShellCmdSeparators = ";&|";   // the bytes that end a simple command

// The shape of one WORD at `at`: its leading identifier (if any), whether that identifier IS the word (a bare
// NAME), and whether it is an assignment (`NAME=`, `NAME+=`, `NAME[i]=`).
struct ShellWord
{
    std::string_view name;
    std::string_view word;
    bool             isBare   = false;
    bool             isAssign = false;
};

inline ShellWord shellWordShape( std::string_view line, std::size_t at )
{
    ShellWord   w;
    std::size_t k = at;
    if( std::isalpha( (unsigned char)line[at] ) || line[at] == '_' )
    {
        w.name = takeIdent( line, k );
    }
    std::size_t wordEnd = at;
    while( wordEnd < line.size() && !std::isspace( (unsigned char)line[ wordEnd ] ) && kShellCmdSeparators.find( line[ wordEnd ] ) == std::string_view::npos )
    {
        ++wordEnd;
    }
    w.word = line.substr( at, wordEnd - at );
    if( w.name.empty() )
    {
        return w;
    }
    w.isBare = k == wordEnd;
    if( k < line.size() && line[k] == '[' )
    {
        const std::size_t rb = line.find( ']', k );
        k = rb == std::string_view::npos ? line.size() : rb + 1;   // X[i]=v: an element write of X
    }
    if( k < line.size() && line[k] == '+' ) { ++k; }
    w.isAssign = k < line.size() && line[k] == '=';
    return w;
}

// Where a write that starts at `at` takes effect: the end of its STATEMENT — the next unquoted `;` `&` `|` — so
// `X="${X:-d}"` still reads the caller's X while `for X in a; do echo "$X"` and `X=1; echo "$X"` read the script's own.
inline std::uint32_t shellWriteEffectCol( std::string_view line, std::size_t at ) noexcept
{
    char        quote  = 0;
    std::size_t effect = at;
    for( ; effect < line.size(); ++effect )
    {
        const char c = line[ effect ];
        if( quote != 0 ) { if( c == '\\' && quote == '"' ) { ++effect; } else if( c == quote ) { quote = 0; } continue; }
        if( c == '\\' ) { ++effect; continue; }
        if( c == '\'' || c == '"' ) { quote = c; continue; }
        if( kShellCmdSeparators.find( c ) != std::string_view::npos ) { break; }
    }
    return std::uint32_t( std::min( effect, line.size() ) );
}

// A word inside a keyword's argument list (f.kw != None, or a pending option argument): does it WRITE its name?
// Advances the keyword state. Only called while a keyword is open.
inline bool shellKeywordArgWrites( ShellScan::Frame& f, const ShellWord& w )
{
    using Kw = ShellScan::Kw;
    const bool isOption = w.word.size() > 1 && w.word[0] == '-';
    if( f.optArg != 0 )
    {
        const bool isArrayName = f.optArg == 'a' && w.isBare;   // read -a NAME, printf -v NAME
        f.optArg = 0;
        return isArrayName;
    }
    switch( f.kw )
    {
        case Kw::Decl:      return !isOption && ( w.isBare || w.isAssign );   // local / declare / typeset / readonly
        case Kw::Export:    return w.isAssign;   // a bare `export X` publishes the inherited value — no write
        case Kw::Read:
        case Kw::MapFile:
        {
            const std::string_view takesArg = f.kw == Kw::Read ? std::string_view( "adinNptu" ) : std::string_view( "dnOsuCc" );
            if( isOption && takesArg.find( w.word.back() ) != std::string_view::npos )
            {
                f.optArg = w.word.back();
            }
            return !isOption && w.isBare;
        }
        case Kw::GetOpts:   // getopts OPTSTRING NAME
            if( f.wordsLeft > 0 ) { --f.wordsLeft; return false; }
            f.kw = Kw::None;
            return w.isBare;
        case Kw::ForName:   // for NAME in … / select NAME in …
            f.kw = Kw::None;
            return w.isBare;
        case Kw::PrintfV:   // printf -v NAME …: the next bare word is written, exactly like read -a
            f.optArg = w.word == "-v" ? 'a' : 0;
            f.kw     = Kw::None;
            return false;
        case Kw::None:
            return false;
    }
    return false;
}

// The command words that open a keyword argument list, and the reserved words after which a command still follows.
struct ShellKeyword { std::string_view word; ShellScan::Kw kw; std::uint8_t wordsLeft; };
inline constexpr ShellKeyword kShellKeywords[] = {
    { "local", ShellScan::Kw::Decl, 0 },     { "declare", ShellScan::Kw::Decl, 0 },   { "typeset", ShellScan::Kw::Decl, 0 },
    { "readonly", ShellScan::Kw::Decl, 0 },  { "export", ShellScan::Kw::Export, 0 },  { "read", ShellScan::Kw::Read, 0 },
    { "mapfile", ShellScan::Kw::MapFile, 0 }, { "readarray", ShellScan::Kw::MapFile, 0 }, { "for", ShellScan::Kw::ForName, 0 },
    { "select", ShellScan::Kw::ForName, 0 }, { "getopts", ShellScan::Kw::GetOpts, 1 }, { "printf", ShellScan::Kw::PrintfV, 0 },
};
inline constexpr std::string_view kShellReservedWords[] = {
    "if", "then", "else", "elif", "do", "while", "until", "!", "time", "{", "}", "function",
};

// One WORD that starts at `at` in a command context: an assignment, a declaration keyword, or the name a
// keyword's argument list writes. Writes go to fh.writes; the frame's command state advances.
inline void shellWordAt( std::string_view line, std::size_t at, std::uint32_t lineNo, ShellScan::Frame& f, FileHarvest& fh )
{
    const ShellWord w        = shellWordShape( line, at );
    const bool      isKwOpen = f.kw != ShellScan::Kw::None || f.optArg != 0;
    // Outside a keyword list only command position can assign: `X=v`, or a prefix `X=v cmd` (position continues).
    const bool      isWrite  = isKwOpen ? shellKeywordArgWrites( f, w ) : ( f.isCmdPos && w.isAssign );
    if( isWrite )
    {
        fh.writes.push_back( FileHarvest::Read{ std::string( w.name ), lineNo, {}, shellWriteEffectCol( line, at ), std::uint32_t( at ) } );
    }
    if( isKwOpen || !f.isCmdPos || w.isAssign )
    {
        return;
    }
    f.isCmdPos = std::find( std::begin( kShellReservedWords ), std::end( kShellReservedWords ), w.word ) != std::end( kShellReservedWords );
    const ShellKeyword* kw = findByField( kShellKeywords, &ShellKeyword::word, w.word );
    if( kw != nullptr )
    {
        f.kw        = kw->kw;
        f.wordsLeft = kw->wordsLeft;
    }
}

// One CODE line of a shell file (not a heredoc body): every expansion read and every assignment on it.
inline void harvestShellLine( std::string_view line, std::uint32_t lineNo, FileHarvest& fh, ShellScan& st )
{
    if( !st.isContinued && !st.frames.back().isDq )
    {
        ShellScan::Frame& f = st.frames.back();   // a new line is a new command
        f.atWordStart = true;  f.isCmdPos = true;  f.kw = ShellScan::Kw::None;  f.optArg = 0;
    }
    st.isContinued = false;
    for( std::size_t i = 0; i < line.size(); ++i )
    {
        const char c = line[i];
        if( st.isInSingle )
        {
            if( st.isAnsiC && c == '\\' ) { ++i; continue; }
            if( c == '\'' ) { st.isInSingle = false; }
            continue;
        }
        ShellScan::Frame& f = st.frames.back();
        if( c == '$' && i + 1 < line.size() && line[ i + 1 ] == '(' )
        {
            f.atWordStart = false;
            st.frames.push_back( ShellScan::Frame{ false, 1 } );   // $( … ) and $(( … )): a fresh command context
            ++i;
            continue;
        }
        if( f.isDq )
        {
            if( c == '\\' ) { ++i; continue; }
            if( c == '"' ) { st.frames.pop_back(); continue; }
            if( c == '$' ) { i = shellExpansionAt( line, i, lineNo, fh ); }
            continue;
        }
        if( c == ' ' || c == '\t' ) { f.atWordStart = true; continue; }
        if( kShellCmdSeparators.find( c ) != std::string_view::npos || c == '(' || c == ')' )
        {
            if( c == '(' && f.parens > 0 ) { ++f.parens; }
            if( c == ')' && f.parens > 0 && --f.parens == 0 && st.frames.size() > 1 )
            {
                st.frames.pop_back();
                continue;
            }
            f.atWordStart = true;  f.isCmdPos = true;  f.kw = ShellScan::Kw::None;  f.optArg = 0;
            continue;
        }
        if( c == '#' && f.atWordStart )
        {
            return;   // a comment: the rest of the line is prose
        }
        if( f.atWordStart )
        {
            f.atWordStart = false;
            shellWordAt( line, i, lineNo, f, fh );
        }
        if( c == '\\' )
        {
            if( i + 1 == line.size() ) { st.isContinued = true; }
            ++i;
            continue;
        }
        if( c == '\'' ) { st.isInSingle = true; st.isAnsiC = false; continue; }
        if( c == '"' ) { st.frames.push_back( ShellScan::Frame{ true } ); continue; }
        if( c == '$' && i + 1 < line.size() && line[ i + 1 ] == '\'' )
        {
            st.isInSingle = true;  st.isAnsiC = true;  ++i;
            continue;
        }
        if( c == '<' && i + 1 < line.size() && line[ i + 1 ] == '<' )
        {
            std::size_t         end    = i;
            const HeredocOpener opener = heredocOpenerAt( line, i, end );
            if( !opener.word.empty() && st.heredocWord.empty() )
            {
                st.heredocWord.assign( opener.word );   // the body starts on the NEXT line
                st.isHeredocQuoted = opener.isQuoted;
            }
            i = end;
            continue;
        }
        if( c == '$' ) { i = shellExpansionAt( line, i, lineNo, fh ); }
    }
}

// One line of a shell file for the env lane: a heredoc body line (literal text, expanded unless quoted) or code.
inline void harvestShellFileLine( std::string_view line, std::uint32_t lineNo, FileHarvest& fh, ShellScan& st )
{
    if( st.heredocWord.empty() )
    {
        harvestShellLine( line, lineNo, fh, st );
        return;
    }
    if( trimView( line ) == st.heredocWord )
    {
        st.heredocWord.clear();
    }
    else if( !st.isHeredocQuoted )
    {
        shellLiteralReads( line, 0, lineNo, fh );
    }
}

// The Bash env lane over one shell file, as its own pass: its quote, command and heredoc state is its own (a `<<` it
// meets in CODE, never one inside a string), so the lanes harvestFile runs line by line keep exactly the
// whole-line heredoc rule they always had.
//
// Then: drop each read a write EARLIER in the same file shadows (the script set it before reading it), and sort the
// writes into the (name, line, col) order the resolver expects. "Earlier" is (line, col) with a write's col at the
// end of its statement, so `X="${X:-d}"` — which reads X before it assigns it — keeps its read: that read IS a
// requirement-or-default on the caller. That same write is also PASS-THROUGH: its value is the caller's X (or a
// default standing in for it), so it shadows nothing. `X="${X:-}"` (the set -u normaliser) followed, a hundred lines
// on, by `${X:-post-script-error}` still has a caller-facing default there. Measured on fullsend-ai agents: without
// this, every `${POST_FAILURE_CATEGORY:-…}` after the library's normaliser vanished. A pass-through write is still
// listed as a write.
inline void harvestShellEnv( std::string_view bytes, FileHarvest& fh )
{
    ShellScan shell;
    forEachLine( bytes, [ & ]( std::string_view line, std::uint32_t lineIndex ) { harvestShellFileLine( line, lineIndex, fh, shell ); } );

    const auto byPosition = []( const FileHarvest::Read& a, const FileHarvest::Read& b )
    {
        if( a.name != b.name ) { return a.name < b.name; }
        return a.line != b.line ? a.line < b.line : a.col < b.col;
    };
    std::sort( fh.writes.begin(), fh.writes.end(), byPosition );
    const auto readsItself = [ & ]( const FileHarvest::Read& w )
    {
        return std::any_of( fh.reads.begin(), fh.reads.end(), [ & ]( const FileHarvest::Read& r )
        {
            return r.sh.form != ShellForm::None && r.line == w.line && r.name == w.name && r.col >= w.stmtCol && r.col < w.col;
        } );
    };
    std::vector<FileHarvest::Read> shadowing;   // the writes that set the script's OWN value, in byPosition order
    std::copy_if( fh.writes.begin(), fh.writes.end(), std::back_inserter( shadowing ), [ & ]( const FileHarvest::Read& w ) { return !readsItself( w ); } );
    std::erase_if( fh.reads, [ & ]( const FileHarvest::Read& r )
    {
        if( r.sh.form == ShellForm::None )
        {
            return false;
        }
        const auto it = std::lower_bound( shadowing.begin(), shadowing.end(), r.name,
                                          []( const FileHarvest::Read& w, const std::string& n ) { return w.name < n; } );
        return it != shadowing.end() && it->name == r.name && ( it->line < r.line || ( it->line == r.line && it->col < r.col ) );
    } );
    // Every surviving read declares an env gate, exactly as a getenv("X") does: default unset.
    for( const FileHarvest::Read& r : fh.reads )
    {
        if( r.sh.form != ShellForm::None )
        {
            fh.defs.push_back( FileHarvest::Def{ r.name, "unset", r.line, GateKind::Env, /*isShell=*/true } );
        }
    }
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
    TemplateStack         templates;                     // 0.6.6 D5: open JS/TS template literals across lines

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
        harvestEnvReads( line, lineIndex, fh, syn, isInBlockComment, templates );

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
    if( syn.hasHeredocs )   // ⇔ a shell file: the Bash env lane is its own pass (harvestShellEnv)
    {
        harvestShellEnv( bytes, fh );
    }
    return fh;
}

// ── tree walk + resolution ───────────────────────────────────────────────────────────────────────────────

// The whole file, or nullopt when it cannot be opened or grows past kMaxFlagFileBytes. A read error part-way
// through keeps what was read, and an empty file is an engaged empty string.
inline std::optional<std::string> readWhole( const std::string& path )
{
    std::FILE* fp = std::fopen( path.c_str(), "rb" );
    if( !fp )
    {
        return std::nullopt;
    }
    std::string out;
    char        buf[ 65536 ];
    std::size_t n = 0;
    while( ( n = std::fread( buf, 1, sizeof( buf ), fp ) ) > 0 )
    {
        out.append( buf, n );
        if( out.size() > kMaxFlagFileBytes ) { std::fclose( fp ); return std::nullopt; }
    }
    std::fclose( fp );
    return out;
}

// §SEC1 — what the CMake walk found, and what it refused. Two fields rather than an out-param because the
// refusal is not an error the caller can ignore: it has to reach the report.
struct CMakeScan
{
    std::vector<std::string> files;        // sorted
    std::uint64_t            escaped = 0;  // links whose target left the root — EXACT count
    // The root itself could not be walked (permission denied, missing, …). `files` and `escaped` then read
    // exactly like a healthy repo with zero CMake presence — that is the lie this flag exists to prevent:
    // the caller must disclose that cmake= and escaped_root= are floors, not totals, for this run.
    bool                      rootWalkFailed = false;

    // rv-s2 review LOW-4: CMakeScan IS the field the caller already reads for this answer, so it models
    // Diagnostics::DisclosureSink directly rather than the flag being set beside a sink-less DISCLOSE — the
    // flag-setting becomes the disclosure itself, and disclose() is the ONE place rootWalkFailed and escaped are written.
    enum class DisclosureWhy : std::uint8_t
    {
        RootWalkFailed,
        SymlinkEscapesRoot,
    };
    void disclose( DisclosureWhy why ) noexcept   // the DISCLOSE sink: the fields the emitter reads
    {
        rootWalkFailed = rootWalkFailed || why == DisclosureWhy::RootWalkFailed;
        escaped += why == DisclosureWhy::SymlinkEscapesRoot ? 1u : 0u;
    }
};

// Can the root itself be LISTED? libc++ AND libstdc++ swallow EACCES on the root under skip_permission_denied (the flag is
// meant for entries met mid-walk, not the walk's own starting point), so a recursive walk of an unlistable root reads as
// an EMPTY SUCCESSFUL walk with its error_code clear (measured: `ec=0 atEnd=1` with the flag, `ec=13` without it, on both
// libraries). A walker that must not mistake that for an empty tree probes here first, without the flag.
inline bool crawlRootIsListable( const std::string& root )
{
    std::error_code                             ec;
    const std::filesystem::directory_iterator  probe( root, ec );
    return !ec;
}

// THE prune-aware file walk the two non-ingest walkers share (collectCMakeFiles below, docdrift.h collectRepoPaths):
// every entry under `root` in readdir order, a directory pruned when `isPrunedDir( base )` holds or it holds a
// CMakeCache.txt (a build-output tree), a path containing any non-empty `excludes` substring skipped, and each remaining
// non-directory handed to `onFile( entry, fullPath, base )`. A per-entry error is skipped, as the walk always did. Returns
// false — having visited nothing — when the root itself cannot be walked (crawlRootIsListable, or the iterator's own
// error): the caller discloses that through its own sink, because an empty walk and a failed one must not read alike.
template<class PruneDir, class OnFile>
inline bool walkCrawlFiles( const std::string& root, const std::vector<std::string>& excludes, PruneDir&& isPrunedDir, OnFile&& onFile )
{
    namespace fs = std::filesystem;
    std::error_code ec;
    const bool      isListable = crawlRootIsListable( root );   // checked together with `ec` below: one verdict, no TOCTOU gap
    fs::recursive_directory_iterator it( root, fs::directory_options::skip_permission_denied, ec );
    if( !isListable || ec )
    {
        return false;
    }
    const fs::recursive_directory_iterator end;
    for( ; it != end; it.increment( ec ) )
    {
        if( ec ) { ec.clear(); continue; }
        const std::string base = it->path().filename().string();
        if( it->is_directory( ec ) )
        {
            std::error_code sec;
            if( isPrunedDir( base ) || fs::exists( it->path() / "CMakeCache.txt", sec ) )
            {
                it.disable_recursion_pending();
            }
            continue;
        }
        const std::string full = it->path().string();
        const bool isExcluded = std::any_of( excludes.begin(), excludes.end(),
                                             [ & ]( const std::string& x ) { return !x.empty() && full.find( x ) != std::string::npos; } );
        if( !isExcluded )
        {
            onFile( *it, full, base );
        }
    }
    return true;
}

// The CMake files under `root`, sorted. ingest() never collects these (CMake is not one of the indexed
// grammars), so this is the ONE crawl this module owns; every other file it reads comes from the caller's
// already-crawled, already-excluded ingest file list — which is exactly why this walk needs the crawl
// boundary applied HERE and not inherited: the reporter who found the ingest-side symlink escape found this
// second copy of it in the same pass, and a linked CMakeLists.txt outside the root had its option() names and
// defaults parsed and reported. ingest.h owns the rule (crawlPathStaysInRoot); this is the second caller, for
// the same reason kCrawlSkipDirs is shared — a boundary two walkers disagreed about is not a boundary.
inline CMakeScan collectCMakeFiles( const std::string& root, const std::vector<std::string>& excludes )
{
    CMakeScan       out;
    // libc++ AND libstdc++ swallow EACCES on the ROOT itself under skip_permission_denied below (the flag is
    // meant for subdirectories encountered mid-walk, not the root the walk starts from): an unreadable root
    // then reads as an EMPTY successful walk with `ec` clear — exactly the false zero rootWalkFailed exists
    // to disclose (measured: `ec=0 atEnd=1` with the flag, `ec=13 Permission denied` without it, both libc++
    // and libstdc++). Probe the root without the flag first, mirroring main.cpp's rootIsReadable shape, which
    // this walk cannot rely on: `--flags` reaches this walk on a warm index even after the root's mode
    // changed out from under it, a path rootIsReadable's own one-shot CLI check never revisits. One combined
    // check (walkCrawlFiles, not two DISCLOSE sites) so a TOCTOU between the two constructions is still caught.
    const std::string rootReal = canonicalCrawlRoot( root );
    // Prune with ingest's OWN denylist (ingest.h kCrawlSkipDirs), plus walkCrawlFiles' CMakeCache.txt sentinel for
    // build-output trees. Without this the walk finds every nested agent worktree's and build dir's copy
    // of CMakeLists.txt, and a stale copy declaring `option(X … OFF)` shadows the real `ON` — measured on
    // the motivating repo, where a worktree copy inverted CANYON_SPHERE_FIRE's reported default.
    const bool isWalked = walkCrawlFiles( root, excludes, []( const std::string& base ) { return isSkippedCrawlDir( base ); },
                                          [ & ]( const std::filesystem::directory_entry& entry, const std::string& p, const std::string& base )
    {
        if( base == "CMakeLists.txt" || ( base.size() > 6 && base.compare( base.size() - 6, 6, ".cmake" ) == 0 ) )
        {
            // §SEC1 — the crawl boundary, tested only once the file is one this walk would actually OPEN, so
            // escaped= counts refusals and nothing else. is_symlink() reads the cached readdir type; only a
            // symlink pays the realpath.
            std::error_code lec;
            const bool      isLink = entry.is_symlink( lec );
            if( isLink && !rw::crawlPathStaysInRoot( p, rootReal ) )
            {
                DISCLOSE( out, CMakeScan::DisclosureWhy::SymlinkEscapesRoot, "flags: a CMake file's symlink target leaves the root — file refused" );
                return;
            }
            out.files.push_back( p );
        }
    } );
    if( !isWalked )
    {
        DISCLOSE( out, CMakeScan::DisclosureWhy::RootWalkFailed, "flags: cannot walk root for CMake files — cmake gates omitted" );
        return out;
    }
    std::sort( out.files.begin(), out.files.end() );
    return out;
}

struct FlagsResult
{
    std::vector<Gate> gates;          // sorted: dark first, then by guarded size desc, then name
    std::uint32_t     dark = 0;
    std::uint32_t     compileCount = 0, cmakeCount = 0, envCount = 0;
    std::size_t       filesScanned = 0;
    // §SEC1 — CMake files this verb's own walk REFUSED to open because a symlink took them out of the root.
    // Reported (absent when zero, the house rule) rather than dropped in silence: --flags answers "what is
    // built but dark here", and a switch that vanished because its file was refused is the same shape of lie
    // as one that was never declared. There is no ROW class here the way --skipped has one — this walk has no
    // drop taxonomy at all (its --exclude and denylist prunes are silent too) — so the count is the disclosure.
    std::uint64_t     escapedRoot  = 0;
    // The CMake sub-walk (§SEC1) never reached the root at all — cmake=/escaped_root= above are a floor for
    // this run, not a total; see CMakeScan::rootWalkFailed. Absent from the XML when false, same house rule.
    bool              cmakeScanFailed = false;
    std::string       filter;          // H14/M6: the --flags=SUBSTR this harvest was narrowed by ("" = none)
    // H7 (capture-audit 2026-09-04): true when --flags=SUBSTR names no DECLARED gate at all. `gates="0"`
    // beside `files="1550"` reads exactly like the true and interesting fact "this repo has no dark gates",
    // so a filter that owns nothing has to refuse instead — the ruling --dead-code / --doc-drift / --scope
    // already apply to their own filters. Set on the DECLARED name set, before the dead-name drop: a filter
    // that names a real gate which then failed the has-a-reader test HAS selected something, and its zero is
    // a measurement.
    bool              filterMatchedNothing = false;
    // Shell files the env lane skipped whole because a `GENERATED … DO NOT EDIT` banner opens them
    // (hasGeneratedShellBanner). They are still in files= (they were read); absent from the XML when zero.
    std::uint64_t     generatedSkipped = 0;
};

// Fold one harvested definition into the gate table, applying the cmake-beats-compile override rule.
inline void mergeDef( gtl::btree_map<std::string, Gate>& gates, const FileHarvest::Def& d, const std::string& rel )
{
    Gate& g = gates[ d.name ];
    g.isShellOnly = g.isShellOnly && d.isShell;
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

// One harvested file, as the resolver below consumes it.
struct HarvestedFile
{
    std::string rel;
    FileHarvest fh;
    bool        isCMake = false;
};

// Pass 2a: every `#if`-family region of `h` whose condition names a declared gate.
inline void attachRegions( gtl::btree_map<std::string, Gate>& gates, const HarvestedFile& h )
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
}

// Pass 2b: the read sites of declared gates, and the Bash writes of declared env gates.
inline void attachReadsAndWrites( gtl::btree_map<std::string, Gate>& gates, const HarvestedFile& h )
{
    for( const FileHarvest::Read& r : h.fh.reads )
    {
        const auto it = gates.find( r.name );
        // A CMake file's every identifier is a candidate read of a DECLARED switch. A name only a shell script
        // declared (`$WRONG`, `$C`) is not a switch CMake can mention, so the word is just a word there.
        if( it != gates.end() && !( h.isCMake && it->second.isShellOnly ) )
        {
            it->second.reads.push_back( Site{ h.rel, r.line, r.sh } );
        }
    }
    for( const FileHarvest::Read& w : h.fh.writes )
    {
        const auto it = gates.find( w.name );
        if( it != gates.end() && it->second.kind == GateKind::Env )   // a write only matters beside an env read
        {
            it->second.writes.push_back( Site{ h.rel, w.line } );
        }
    }
}

// A kept gate's site lists in their canonical order, duplicates folded, and the ambient verdict.
inline void finishGate( Gate& g )
{
    // `#endif` order is not start-line order once regions nest (the inner one closes first) — sort so the
    // span list is deterministic and reads top-down like the file does.
    std::sort( g.regionSpans.begin(), g.regionSpans.end(),
               []( const Region& a, const Region& b ) { return siteLess( a.site, b.site ); } );
    for( std::vector<Site>* sites : { &g.reads, &g.writes } )
    {
        std::sort( sites->begin(), sites->end(), siteLess );
        sites->erase( std::unique( sites->begin(), sites->end(), siteSame ), sites->end() );
    }
    // Ambient is a Bash lane verdict: a getenv("HOME") gate in C keeps the exact bytes it always had.
    g.isAmbient = g.kind == GateKind::Env && std::ranges::binary_search( kAmbientEnvNames, std::string_view( g.name ), sortutil::svLess )
               && std::any_of( g.reads.begin(), g.reads.end(), []( const Site& r ) { return r.sh.form != ShellForm::None; } );
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
    std::vector<HarvestedFile> harvest;
    std::uint64_t          generatedSkipped = 0;

    const auto scan = [ & ]( const std::string& full, bool isCMake )
    {
        const std::optional<std::string> bytes = readWhole( full );
        if( !bytes )
        {
            return;
        }
        std::string rel( relForHash( full, root ) );
        // A generated shell bundle repeats its sources' reads at lines nobody edits: read, counted, not harvested.
        if( !isCMake && lineSyntaxFor( full ).hasHeredocs && hasGeneratedShellBanner( *bytes ) )
        {
            ++generatedSkipped;
            harvest.push_back( HarvestedFile{ std::move( rel ), FileHarvest{} } );
            return;
        }
        FileHarvest fh = harvestFile( *bytes, full, isCMake );
        harvest.push_back( HarvestedFile{ std::move( rel ), std::move( fh ), isCMake } );
    };

    for( const std::string& f : ing.files )
    {
        scan( f, false );
    }
    const CMakeScan cmakeScan = collectCMakeFiles( root, excludes );   // §SEC1: .files plus what the boundary refused
    for( const std::string& f : cmakeScan.files )
    {
        scan( f, true );
    }

    // Pass 1 — gate identities (declarations only).
    gtl::btree_map<std::string, Gate> gates;
    for( const HarvestedFile& h : harvest )
    {
        for( const FileHarvest::Def& d : h.fh.defs )
        {
            mergeDef( gates, d, h.rel );
        }
    }

    // Pass 2 — regions and read sites, attributed only to declared gates.
    for( const HarvestedFile& h : harvest )
    {
        attachRegions( gates, h );
        attachReadsAndWrites( gates, h );
    }

    resolveAliases( gates );

    FlagsResult res;
    res.filesScanned = harvest.size();
    res.escapedRoot  = cmakeScan.escaped;   // §SEC1 — a refusal this verb made is this verb's to disclose
    res.cmakeScanFailed = cmakeScan.rootWalkFailed;
    res.generatedSkipped = generatedSkipped;
    std::size_t filterNameHits = 0;
    for( auto& [ name, g ] : gates )
    {
        if( !filter.empty() && name.find( filter ) == std::string::npos )
        {
            continue;
        }
        ++filterNameHits;
        // A declaration with no reader is a dead name, not a gate — the getenv lane especially would
        // otherwise report every one-off environment probe as a repo-wide switch.
        if( g.reads.empty() && !keepUnreadGates )
        {
            continue;
        }

        finishGate( g );
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
    res.filterMatchedNothing = !filter.empty() && filterNameHits == 0;
    // H14/M6: the filter is what makes gates= a count for a NAME SET rather than for the repo, so it is
    // carried on the result and echoed on the root.
    res.filter = std::string( filter );
    return res;
}

// ── XML emission (G4: minified, xmllint-clean; no `--` inside a comment, no `\n` outside CDATA) ──────────

using XmlEscaper = std::function<std::string( std::string_view )>;

// C1 F-07 (2026-09-10): the <read> site list was cut at 8 and this file emitted no shown=/total=/capped=
// token anywhere — a reporting verb dropping rows in silence, with only the <more reads=> remainder to say
// so and no flag that could lift it. The GATE rows are the answer here ("what is built but dark") and are
// never windowed; the SITES under one gate are context, so they are what pages. reads= on the same element
// is already this listing's rule-2 total, so the disclosure is rule 1's pair alone (pageview.h).
// A gate's Bash WRITE sites page the same way, through the same window. Shared with flipimpact.h's listings.
inline PageWindow siteCapWindow( std::size_t total, std::size_t maxSites, int pageOffset ) noexcept
{
    // maxSites == SIZE_MAX is --detail ("every row"), which pageWindow spells as limit <= 0.
    return pageWindow( total, maxSites >= std::size_t( INT_MAX ) ? 0 : int( maxSites ), pageOffset );
}

// A Bash read's form attributes (empty for every other lane, so those rows keep their exact bytes):
// form= always, colon= only when the expansion had an operator, default= (possibly "") only when it supplies one,
// test= only as the operand of `-n` / `-z`.
inline std::string shellReadAttrsXml( const ShellRead& sh, const XmlEscaper& ex )
{
    if( sh.form == ShellForm::None )
    {
        return {};
    }
    std::string a = " form=\"" + std::string( kShellFormTag[ std::size_t( sh.form ) ] ) + "\"";
    if( sh.hasOperator )
    {
        a += sh.isColon ? " colon=\"1\"" : " colon=\"0\"";
    }
    if( sh.hasDefault )
    {
        a += " default=\"" + ex( sh.def ) + "\"";
    }
    if( sh.test != 0 )
    {
        a += std::string( " test=\"" ) + sh.test + "\"";
    }
    return a;
}

inline void writeGate( std::FILE* out, const Gate& g, const XmlEscaper& ex, std::size_t maxSites, int pageOffset = 0 )
{
    const PageWindow  readPage    = siteCapWindow( g.reads.size(), maxSites, pageOffset );
    const std::size_t shownCount  = readPage.end - readPage.begin;
    const PageWindow  writePage   = siteCapWindow( g.writes.size(), maxSites, pageOffset );
    const std::size_t shownWrites = writePage.end - writePage.begin;
    // Present-only, so a gate with no Bash writes and a non-ambient name keeps its exact bytes.
    const std::string writesAttr = g.writes.empty() ? std::string()
                                                    : " writes=\"" + std::to_string( g.writes.size() ) + "\"" + secondaryCutAttrs( "writes", shownWrites, g.writes.size() );
    rw::emitTo( out, "<gate name=\"{}\" kind=\"{}\" default=\"{}\" dark=\"{}\" regions=\"{}\" loc=\"{}\" reads=\"{}\" p=\"{}\" l=\"{}\"{}{}{}>",
                  ex( g.name ).c_str(), gateKindTag( g.kind ), ex( g.def ).c_str(), isDarkDefault( g.def ) ? 1 : 0,
                  g.regions, g.guardedLines, g.reads.size(), ex( g.defSite.path ).c_str(), g.defSite.line,
                  secondaryCutAttrs( "reads", shownCount, g.reads.size() ).c_str(), g.isAmbient ? " ambient=\"1\"" : "", writesAttr.c_str() );
    if( !g.aliasOf.empty() )
    {
        rw::emitTo( out, "<alias-of name=\"{}\"/>", ex( g.aliasOf ).c_str() );
    }
    if( g.aliasCount )
    {
        rw::emitTo( out, "<aliases n=\"{}\" regions=\"{}\" loc=\"{}\"/>", g.aliasCount, g.aliasRegions, g.aliasLines );
    }
    if( g.hasAlso )
    {
        rw::emitTo( out, "<also kind=\"{}\" default=\"{}\" p=\"{}\" l=\"{}\"/>",
                      gateKindTag( g.alsoKind ), ex( g.alsoDef ).c_str(), ex( g.alsoSite.path ).c_str(), g.alsoSite.line );
    }
    // "Nothing is dropped without a number": shownCount is what the loop will PRINT, so the <more/> remainder
    // is exactly what it will not. The `shown++ >= cap` form got this wrong twice over — it left the counter
    // at cap+1, so <more/> under-reported the drop by one, and at exactly cap+1 reads the element vanished
    // entirely and one row disappeared unmarked. abicheck.h::writeAbiRef is the shape this follows.
    for( std::size_t readIndex = readPage.begin; readIndex < readPage.end; ++readIndex )
    {
        const Site& r = g.reads[ readIndex ];
        rw::emitTo( out, "<read p=\"{}\" l=\"{}\"{}/>", ex( r.path ).c_str(), r.line, shellReadAttrsXml( r.sh, ex ).c_str() );
    }
    if( g.reads.size() > shownCount )
    {
        rw::emitTo( out, "<more reads=\"{}\"/>", g.reads.size() - shownCount );
    }
    for( std::size_t writeIndex = writePage.begin; writeIndex < writePage.end; ++writeIndex )
    {
        rw::emitTo( out, "<write p=\"{}\" l=\"{}\"/>", ex( g.writes[ writeIndex ].path ).c_str(), g.writes[ writeIndex ].line );
    }
    if( g.writes.size() > shownWrites )
    {
        rw::emitTo( out, "<more writes=\"{}\"/>", g.writes.size() - shownWrites );
    }
    rw::emitRaw( out, "</gate>" );
}

// The shell env lane's vocabulary, defined where the reader meets it — and only then: an answer that carries no
// Bash row and no generated_skipped= keeps the exact bytes it had before the lane existed (G4).
inline void writeShellLegend( std::FILE* out, const FlagsResult& res )
{
    const bool hasShellRows = res.generatedSkipped != 0 || std::any_of( res.gates.begin(), res.gates.end(), []( const Gate& g )
    {
        return g.isAmbient || !g.writes.empty()
            || std::any_of( g.reads.begin(), g.reads.end(), []( const Site& r ) { return r.sh.form != ShellForm::None; } );
    } );
    if( !hasShellRows )
    {
        return;
    }
    rw::emitRaw( out, "<!-- BASH: a parameter expansion in a .sh/.bash/.zsh file is an env read (kind=\"env\") unless the same file "
                       "assigned that name on an EARLIER line (lexical order in one file: no flow, no source following). Each "
                       "Bash read row carries form= (required for :? and ?, default for :-, unset-default for -, settest for "
                       "+ and :+ and a -n/-z test, assign for := and =, plain for $X and ${X}); colon=\"1\" when the colon "
                       "spelling makes an EMPTY value count as unset (colon=\"0\" when not, absent when the expansion has no "
                       "operator); default= the literal default word, possibly empty; test=\"n\" or \"z\" when the read is "
                       "the operand of that test. writes= on a gate counts, and write rows list, every Bash assignment of the "
                       "name anywhere in the repo (X=, export X=, local, declare, readonly, read, for, mapfile, printf -v, := "
                       "expansions), paged like the reads (shown_writes= writes_capped= and more writes= as for "
                       "reads). ambient=\"1\": a name Bash or the login always sets (BASH_*, PWD, HOME, PATH, RANDOM "
                       "and the like), never unsupplied. generated_skipped=N on the root: shell files this "
                       "verb read but did not harvest because a GENERATED and DO NOT EDIT banner opens them. -->" );
}

// P3 (nextverb.h): the ONE pasteable follow-up, and it is EXACT — the smallest --limit that cuts no gate's read
// or write list. Empty when nothing was cut, so an uncut root is byte-identical to what it was. Both dialects.
inline std::string flagsNextInvocation( const FlagsResult& res, std::size_t maxSites, int pageOffset, std::string_view extra = {} )
{
    std::size_t widestCut = 0;
    for( const Gate& g : res.gates )
    {
        for( const std::vector<Site>* sites : { &g.reads, &g.writes } )
        {
            const PageWindow probe = siteCapWindow( sites->size(), maxSites, pageOffset );
            if( probe.end - probe.begin < sites->size() )
            {
                widestCut = std::max( widestCut, sites->size() );
            }
        }
    }
    return widestCut == 0 ? std::string() : "--flags" + std::string( extra ) + " --limit=" + std::to_string( widestCut );
}

inline void writeFlags( std::FILE* out, const FlagsResult& res, std::size_t maxSites, int pageOffset = 0 )
{
    std::vector<char> esc;
    const XmlEscaper  ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };

    rw::emitRaw( out, "<!-- ripwire flags: what is BUILT but DARK here. Three gate patterns in one report: ifndef/define "
                       "header gates (kind=\"compile\"), CMake option() switches (kind=\"cmake\"), and getenv reads "
                       "(kind=\"env\", default unset; os.environ in Python, process.env in JavaScript/TypeScript). dark=\"1\" means the default keeps the guarded code out of the build; "
                       "regions/loc size what it turns off, and are measured only for #if/#ifdef regions: an env gate (getenv, "
                       "os.environ, process.env) guards a runtime branch this verb does not size, so it reads regions=0 loc=0. When one name is BOTH a header gate and a CMake option the CMake "
                       "default wins (that is what the build passes) and the header shows as an also row. Lexical, not "
                       "preprocessed: this reports the in-repo default, never the value your build used. dark_gates on this root "
                       "is the COUNT of dark gates; it was spelled dark until that collided with the child bool. files= is THIS "
                       "verb's own harvest scan (source + CMakeLists files it read looking for gates) — a wider crawl than the "
                       "map's indexed corpus, so it will not equal the map's files= -->" );
    writeShellLegend( out, res );
    // C1 F-07: the site listing's own vocabulary, DEFINED where the reader meets it (legendcoveragecheck's
    // rule). Emitted unconditionally because it describes a listing every run carries, unlike the attributes
    // themselves, which appear only on a gate that was actually cut.
    rw::emitRaw( out, "<!-- ROWS AND WHAT IS NEVER CUT: the gate rows ARE the answer this verb was asked for "
                       "and are never windowed, capped or paged, and gates/dark_gates/compile/cmake/env/files "
                       "on the root plus regions/loc/reads/dark on every gate are counted over the FULL set "
                       "before any cap exists. What pages is the read SITES under one gate, at 8 a gate by "
                       "default: a gate whose sites were cut says shown_reads= (the rows this run printed) "
                       "with reads_capped=\"1\", against the reads= total already on the same element, and the "
                       "more reads= child keeps naming the remainder. The pair is emitted ONLY on a gate that "
                       "was cut, never as a capped=\"0\" on the gates that fit. limit=N raises the per gate "
                       "cap (offset=M skips that many sites in every gate), detail lifts it entirely, and "
                       "next= on the root is the exact pasteable invocation that shows every site this run "
                       "dropped. -->" );
    // §P8 collision: `dark=` was a COUNT here and a BOOL on the <gate/> children beneath — indistinguishable
    // to a parser. The count is renamed (index-vs-count rule) and reads correctly beside its
    // gates=/compile=/cmake=/env= siblings; it had ZERO parsers, so the bool half keeps its name.
    // H14/M6: gates="41" under a name filter is not gates="69" for the repo, and only the echoed filter
    // separates the two. --doc-drift already carried filter=; this is the same attribute on its sibling.
    std::vector<char> fgEsc;
    const std::string fgFilterAttr = res.filter.empty() ? std::string()
                                                        : ( " filter=\"" + std::string( rw::escapeXml( res.filter, fgEsc ) ) + "\"" );
    // P3 (nextverb.h): the ONE pasteable follow-up, and it is EXACT — the smallest --limit that cuts no
    // gate's site list. Empty when nothing was cut, so an uncut root is byte-identical to what it was.
    const std::string flagsNext = nextAttrXml( flagsNextInvocation( res, maxSites, pageOffset ) );
    // §SEC1 — absent when zero, so every repository without a hostile symlink keeps a byte-identical report.
    const std::string fgEscapedAttr = res.escapedRoot == 0 ? std::string()
                                                           : " escaped_root=\"" + std::to_string( res.escapedRoot ) + "\"";
    // Absent when false: a repo whose CMake sub-walk always succeeds keeps a byte-identical report.
    const std::string fgCmakeFailedAttr = res.cmakeScanFailed ? " cmake_scan_failed=\"1\"" : std::string();
    const std::string fgGeneratedAttr = res.generatedSkipped == 0 ? std::string()
                                                                  : " generated_skipped=\"" + std::to_string( res.generatedSkipped ) + "\"";
    rw::emitTo( out, "<flags gates=\"{}\" dark_gates=\"{}\" compile=\"{}\" cmake=\"{}\" env=\"{}\" files=\"{}\"{}{}{}{}{}>",
                  res.gates.size(), res.dark, res.compileCount, res.cmakeCount, res.envCount, res.filesScanned,
                  fgGeneratedAttr.c_str(), fgEscapedAttr.c_str(), fgCmakeFailedAttr.c_str(), fgFilterAttr.c_str(), flagsNext.c_str() );
    for( const Gate& g : res.gates )
    {
        writeGate( out, g, ex, maxSites, pageOffset );
    }
    rw::emitRaw( out, "</flags>" );
}

// One JSON site list ("read" / "write") over the window: {"p","l"} plus a Bash read's form keys, present-only.
inline void appendSitesJson( std::string& doc, std::string_view key, const std::vector<Site>& sites, const PageWindow& page )
{
    doc += ",\"" + std::string( key ) + "\":[";
    for( std::size_t siteIndex = page.begin; siteIndex < page.end; ++siteIndex )
    {
        const Site& r = sites[ siteIndex ];
        doc += std::string( siteIndex > page.begin ? ",{" : "{" ) + "\"p\":\"" + jsonStr( r.path ) + "\",\"l\":" + std::to_string( r.line );
        if( r.sh.form != ShellForm::None )
        {
            doc += ",\"form\":\"" + std::string( kShellFormTag[ std::size_t( r.sh.form ) ] ) + "\"";
            doc += r.sh.hasOperator ? std::string( ",\"colon\":" ) + ( r.sh.isColon ? "true" : "false" ) : std::string();
            doc += r.sh.hasDefault ? ",\"default\":\"" + jsonStr( r.sh.def ) + "\"" : std::string();
            doc += r.sh.test != 0 ? std::string( ",\"test\":\"" ) + r.sh.test + "\"" : std::string();
        }
        doc += "}";
    }
    doc += "]";
}

// One gate as a JSON object: writeGate's attributes and children, key for key.
inline void appendGateJson( std::string& doc, const Gate& g, std::size_t maxSites, int pageOffset )
{
    const auto q = []( std::string_view v ) { return "\"" + jsonStr( v ) + "\""; };
    const PageWindow  readPage    = siteCapWindow( g.reads.size(), maxSites, pageOffset );
    const PageWindow  writePage   = siteCapWindow( g.writes.size(), maxSites, pageOffset );
    const std::size_t shownReads  = readPage.end - readPage.begin;
    const std::size_t shownWrites = writePage.end - writePage.begin;
    doc += "{\"name\":" + q( g.name ) + ",\"kind\":\"" + gateKindTag( g.kind ) + "\",\"default\":" + q( g.def )
         + ",\"dark\":" + ( isDarkDefault( g.def ) ? "true" : "false" ) + ",\"regions\":" + std::to_string( g.regions )
         + ",\"loc\":" + std::to_string( g.guardedLines ) + ",\"reads\":" + std::to_string( g.reads.size() )
         + ",\"p\":" + q( g.defSite.path ) + ",\"l\":" + std::to_string( g.defSite.line );
    if( shownReads < g.reads.size() ) { doc += ",\"shown_reads\":" + std::to_string( shownReads ) + ",\"reads_capped\":true"; }
    if( g.isAmbient )                 { doc += ",\"ambient\":true"; }
    if( !g.writes.empty() )
    {
        doc += ",\"writes\":" + std::to_string( g.writes.size() );
        if( shownWrites < g.writes.size() ) { doc += ",\"shown_writes\":" + std::to_string( shownWrites ) + ",\"writes_capped\":true"; }
    }
    if( !g.aliasOf.empty() ) { doc += ",\"alias_of\":" + q( g.aliasOf ); }
    if( g.aliasCount )
    {
        doc += ",\"aliases\":{\"n\":" + std::to_string( g.aliasCount ) + ",\"regions\":" + std::to_string( g.aliasRegions )
             + ",\"loc\":" + std::to_string( g.aliasLines ) + "}";
    }
    if( g.hasAlso )
    {
        doc += ",\"also\":{\"kind\":\"" + std::string( gateKindTag( g.alsoKind ) ) + "\",\"default\":" + q( g.alsoDef )
             + ",\"p\":" + q( g.alsoSite.path ) + ",\"l\":" + std::to_string( g.alsoSite.line ) + "}";
    }
    appendSitesJson( doc, "read", g.reads, readPage );
    if( g.reads.size() > shownReads ) { doc += ",\"more_reads\":" + std::to_string( g.reads.size() - shownReads ); }
    if( !g.writes.empty() )
    {
        appendSitesJson( doc, "write", g.writes, writePage );
        if( g.writes.size() > shownWrites ) { doc += ",\"more_writes\":" + std::to_string( g.writes.size() - shownWrites ); }
    }
    doc += "}";
}

// `--flags --json`: the SAME content as writeFlags, keys mirroring the XML attribute names one to one — the root's
// counts, then "gate":[…] with each gate's attributes, "read":[…] / "write":[…] site rows (the same window) and the
// child elements as keys ("alias_of", "aliases", "also", "more_reads", "more_writes"). Present-only attributes stay
// present-only; the XML's 0/1 flags are JSON booleans. A machine consumer (a CI contract check joining Bash reads
// against what a caller supplies) wants exactly the rows, so this twin carries no legend.
inline void writeFlagsJson( std::FILE* out, const FlagsResult& res, std::size_t maxSites, int pageOffset = 0 )
{
    const auto q = []( std::string_view v ) { return "\"" + jsonStr( v ) + "\""; };
    std::string doc = "{\"schema\":\"ripwire.flags/v1\",\"gates\":" + std::to_string( res.gates.size() )
                    + ",\"dark_gates\":" + std::to_string( res.dark ) + ",\"compile\":" + std::to_string( res.compileCount )
                    + ",\"cmake\":" + std::to_string( res.cmakeCount ) + ",\"env\":" + std::to_string( res.envCount )
                    + ",\"files\":" + std::to_string( res.filesScanned );
    if( res.generatedSkipped != 0 ) { doc += ",\"generated_skipped\":" + std::to_string( res.generatedSkipped ); }
    if( res.escapedRoot != 0 )      { doc += ",\"escaped_root\":" + std::to_string( res.escapedRoot ); }
    if( res.cmakeScanFailed )       { doc += ",\"cmake_scan_failed\":true"; }
    if( !res.filter.empty() )       { doc += ",\"filter\":" + q( res.filter ); }
    doc += nextFieldJson( flagsNextInvocation( res, maxSites, pageOffset, " --json" ) );
    doc += ",\"gate\":[";
    for( std::size_t gateIndex = 0; gateIndex < res.gates.size(); ++gateIndex )
    {
        doc += gateIndex ? "," : "";
        appendGateJson( doc, res.gates[ gateIndex ], maxSites, pageOffset );
    }
    doc += "]}\n";
    rw::emitRaw( out, doc.c_str() );
}

}}   // namespace rw::darkflags
