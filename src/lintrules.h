#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings


// lintrules.h — user-extensible lint rules, ast-grep style (Wave 4 #2). Load a directory of YAML
// rule files; each rule is a tree-sitter s-expression run through the EXISTING astQuery engine over
// files of one language, and every @-capture hit becomes a finding tagged with the rule's id /
// severity / message. This is a LOADER + a POST-FILTER only — it emits nothing itself; main.cpp owns
// the <lint> XML, so user findings share the built-ins' shape, sort, and escaping.
//
// Zero new dependencies: the YAML we accept is a tiny, fixed SUBSET, not a general YAML document —
//   - a top-level sequence of list items, each introduced by "- " at column 0
//   - within an item, "key: value" scalar fields (id | language | severity | message)
//   - one multi-line "query: |" block whose body is the indented lines that follow
// Anything outside this shape is a malformed rule → alert (file+line) + SKIP that file, keep going.
// We parse exactly this shape by hand; we do NOT try to be a YAML engine.
//
// Style: Allman braces; spaces inside parens; graceful degrade (never throw — the whole pipeline must
// survive a malformed rules dir); index-vs-count naming; declarative tables over switch chains.

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

#include "model.h"              // Lang enum
#include "ingest.h"             // AstQuerySpec, AstMatch, astQuery, IngestResult
#include "docparse.h"           // detail::readWholeFile — THE canonical whole-file byte read; never re-rolled
#include "infra/Diagnostics.h"  // DEGRADED_PATH_ALERT (no-op in release; the fprintf below is the visible line)

namespace rw
{

// ── the parsed shape ────────────────────────────────────────────────────────────────────────────
// One user rule = one finding source. `tag` is a synthetic unique key ("<file>#<index>") threaded
// through astQuery's per-spec tag so results route back to THIS rule; id/severity/message are what
// the user wrote and what we emit. `lang` is the file-language this rule's query applies to.
struct LintRule
{
    std::string id;          // rule id — the emitted rule=" " and the human handle
    std::string severity;    // info | warn | error (validated; defaults to "warn")
    std::string message;     // the finding message (may be empty)
    std::string query;       // the tree-sitter s-expression (as written, newlines preserved)
    std::string tag;         // synthetic unique routing key (never emitted)
    Lang        lang = Lang::Cpp;   // which file-language the query runs over
    std::size_t queryKeyIndent = 0; // indent of the current block-scalar key (scratch: body must indent deeper)

    // ── phase-2 combinators (Wave 4 #2 phase 2) — pure span-algebra constraints over the SAME astQuery
    // engine, zero dataflow. Each entry is a tree-sitter query; repeated keys accumulate → AND-ed. A
    // candidate span (the main query's collapsed @hit) is filtered against each constraint's span set:
    //   inside:      KEEP the candidate iff it is fully contained in ≥1 span of EVERY inside query
    //   not-inside:  DROP the candidate iff it is fully contained in ≥1 span of ANY not-inside query
    //   not-matches: DROP the candidate iff a span of ANY not-matches query EQUALS or fully covers it
    std::vector<std::string> inside;      // AND: candidate must sit inside one match of each
    std::vector<std::string> notInside;   // OR:  candidate dropped if inside any match of any
    std::vector<std::string> notMatches;  // OR:  candidate dropped if any match equals/covers it
};

// severity → its emitted sev=" " string, validated against this closed set (declarative, not a switch).
inline constexpr std::array<std::string_view, 3> kLintSeverities = { "info", "warn", "error" };
inline bool isValidSeverity( std::string_view s ) noexcept
{
    for( std::string_view v : kLintSeverities )
    {
        if( v == s )
        {
            return true;
        }
    }
    return false;
}

// language token (as written in `language:`) → Lang enum. Declarative table, not an if-chain. Only the
// grammar-bearing languages are accepted (Markdown has no tree-sitter grammar → no AST rules).
/// Parse a supported language token; assign out only on success and otherwise return false.
inline bool langFromToken( std::string_view tok, Lang& out ) noexcept
{
    struct Row { std::string_view name; Lang lang; };
    static constexpr std::array<Row, 18> kMap = { {
        { "cpp",        Lang::Cpp        },
        { "python",     Lang::Python     },
        { "typescript", Lang::TypeScript },
        { "go",         Lang::Go         },
        { "rust",       Lang::Rust       },
        { "swift",      Lang::Swift      },
        { "objc",       Lang::ObjC       },
        { "javascript", Lang::JavaScript },
        { "bash",       Lang::Bash       },
        { "java",       Lang::Java       },
        { "ruby",       Lang::Ruby       },
        { "csharp",     Lang::CSharp     },
        { "c",          Lang::C          },
        { "php",        Lang::Php        },
        { "lua",        Lang::Lua        },
        { "elixir",     Lang::Elixir     },
        { "dart",       Lang::Dart       },
        { "kotlin",     Lang::Kotlin     },
    } };
    for( const Row& r : kMap )
    {
        if( r.name == tok )
        {
            out = r.lang;
            return true;
        }
    }
    return false;
}

// file extension → Lang, mirroring ingest.cpp's kLangTable so we can bucket a finding's file by
// language WITHOUT reaching into ingest internals (lookupLang is not exported). Kept in sync by hand;
// a header (.h) is treated as Cpp here (the same conservative choice ingest.cpp's kLangTable makes —
// `.h` ownership is inherently ambiguous, see model.h's Lang-enum comment) — documented degrade: an
// ObjC .h rule may not match, prefer .m/.mm fixtures for ObjC. `.c` (L3) is its OWN language, NOT Cpp.
/// Classify a path by its supported extension, returning Unknown when no extension matches.
inline Lang langOfPath( std::string_view path ) noexcept
{
    const std::size_t dot = path.rfind( '.' );
    if( dot == std::string_view::npos )
    {
        return Lang::Unknown;
    }
    std::string ext( path.substr( dot ) );
    for( char& c : ext )
    {
        c = static_cast<char>( std::tolower( static_cast<unsigned char>( c ) ) );
    }

    struct Row { std::string_view ext; Lang lang; };
    static const std::array<Row, 34> kExt = { {
        { ".cpp", Lang::Cpp }, { ".cc", Lang::Cpp }, { ".cxx", Lang::Cpp },
        { ".h", Lang::Cpp }, { ".hpp", Lang::Cpp }, { ".hh", Lang::Cpp }, { ".hxx", Lang::Cpp }, { ".c", Lang::C },
        { ".py", Lang::Python },
        { ".go", Lang::Go },
        { ".rs", Lang::Rust },
        { ".ts", Lang::TypeScript }, { ".tsx", Lang::TypeScript }, { ".mts", Lang::TypeScript }, { ".cts", Lang::TypeScript },
        { ".swift", Lang::Swift },
        { ".m", Lang::ObjC }, { ".mm", Lang::ObjC },
        { ".js", Lang::JavaScript }, { ".jsx", Lang::JavaScript }, { ".mjs", Lang::JavaScript }, { ".cjs", Lang::JavaScript },
        { ".sh", Lang::Bash }, { ".bash", Lang::Bash }, { ".zsh", Lang::Bash },
        { ".java", Lang::Java },
        { ".rb", Lang::Ruby },
        { ".cs", Lang::CSharp },
        { ".php", Lang::Php },
        { ".lua", Lang::Lua },
        { ".ex", Lang::Elixir }, { ".exs", Lang::Elixir },
        { ".dart", Lang::Dart },
        { ".kt", Lang::Kotlin },
    } };
    for( const Row& r : kExt )
    {
        if( r.ext == ext )
        {
            return r.lang;
        }
    }
    return Lang::Unknown;
}

// §P9.4: which languages can appear as a NODE in the #include/import dependency graph at all — a file
// whose language has no include/import syntax (or no grammar) can never be a source or a meaningful
// target of a physical dependency edge, so counting it in `--deps <health>`'s N or `--arch`'s
// propagation_cost N dilutes both toward 0 for no structural reason (measured on this repo: 385 of 760
// files are .sh/.md, nccd=0.27 "horizontal" over all files vs ~1.1-1.25 "vertical" over the 233 C-family
// files alone — the denominator was making the verdict, not the arithmetic). Derived empirically from
// ingest.cpp's captureIncludes(): every language below has a node-type branch there (Cpp/C/ObjC's
// preproc_include/#import, Python/TS/JS's import_statement(_from), Rust's use_declaration/mod_item,
// Go/Swift/Java's import_declaration — Java shares that node-type SPELLING with Go/Swift so it is
// captured too, even though only best-effort resolved — and C#'s using_directive; PHP's
// namespace_use_declaration joined them in the PHP/Lua port round).
//
// kParserVer 81 (the four-language import round) ADDED Bash/Ruby/Lua/Elixir. Each now has its own
// branch in directiveTargetOf and its own Step-A in resolve.h, so each is a real node in this graph:
//   Bash    `source FILE` / `. FILE`   — a LITERAL path (no name→path convention to model at all)
//   Lua     `require "a.b"`            — package.path's dotted convention (`a.b` → `a/b.lua`)
//   Ruby    `require_relative` / `require` — path-relative, and a bounded load-path probe; parser version 82
//           adds the CONSTANT spellings a Rails codebase actually depends through — `class X < Base`,
//           include/extend/prepend, `autoload :Name` — resolved through the corpus's own class/module
//           index (resolve.h::RubyConstantIndex), never by a name→path convention; parser version 83 adds
//           the constant RECEIVER (`User.find`), one directive per (file, nesting, spelling)
//   Elixir  `alias`/`import`/`require`/`use` — resolved through the corpus's OWN defmodule index
// The paragraph this replaced said the opposite ("`require "mod"` LOOKS like an import and is not one")
// and was TRUE of the extractor, never of the language: a Lua `require` is dispatched through
// package.loaders onto a FILE, and reading it as an ordinary global call is what made a 695-file Lua or
// Ruby tree report `<deps files="0">` — the same shape, and the same wrong conclusion, as webpack's
// CommonJS `require` before kParserVer 71. THIS COMMENT IS THE DENOMINATOR'S DOCUMENTATION: every number
// derived from it (ccd/acd/nccd, propagation_cost, dep_files=) MOVES on a corpus holding these four
// languages, in the direction of counting files that were always structurally able to carry an edge.
//
// MARKDOWN stays FALSE, and its exclusion is now explicit rather than a side effect of having no
// extractor. Markdown DOES mint doc→doc edges (`[B](b.md)` is captured, and shows up as a `<c>` in the
// map), so "no import syntax" is simply not the reason. The reason is that `--deps`/`--arch` measure
// PROPAGATION COST — "how far does a change to this file travel" — and a README that links twelve design
// docs is not twelve files' worth of change amplification: docs are read, not compiled, and a doc link
// obliges no rebuild, no re-test and no re-review of the target. Counting them would put a hub with
// ~O(all docs) fan-out into the same N² closure as a header, which is exactly the denominator distortion
// the §P9.4 restriction exists to prevent. The doc→doc edges remain in the MAP (where they answer "what
// does this document reference"); they are excluded from the DEPENDENCY verbs on purpose.
// JSON/TOML/YAML stay FALSE for the original reason, unchanged: TOML LOOKS like a counterexample because
// a Cargo.toml [dependencies] table names real dependencies. They are PACKAGE deps, not the physical
// file-include edges this graph is built from, and inventing a node for one would put a name with no
// in-repo file behind it into a denominator that propagation_cost divides by.
/// Return whether this language has syntax-backed dependency extraction for dependency rules.
inline bool dependencyCapable( Lang lang ) noexcept
{
    switch( lang )
    {
        case Lang::Cpp: case Lang::C: case Lang::ObjC:
        case Lang::Python: case Lang::TypeScript: case Lang::JavaScript:
        case Lang::Rust: case Lang::Go: case Lang::Swift:
        case Lang::Java: case Lang::CSharp: case Lang::Php:
        case Lang::Bash: case Lang::Ruby: case Lang::Lua: case Lang::Elixir:
        case Lang::Kotlin:
            return true;
        case Lang::Json: case Lang::Toml: case Lang::Yaml: case Lang::Markdown: case Lang::Unknown:
        default:
            return false;
    }
}

// The DEPENDENCY DIALECT a language's imports resolve in — the answer to "could an include edge from a
// file of language A to a file of language B exist AT ALL". Per-file capability is not enough to answer
// that: a Bash gate and the C++ translation unit it exercises are BOTH dependency-capable as of
// kParserVer 81, and no `source` can ever name a .cpp. Anything that asks "is the ABSENCE of a static
// dependency between these two informative?" (gitmine.h's `surprising=`) needs the pair form, or it
// re-manufactures exactly the §A9.3 false positive — measured here, on this repo, before the change
// landed: of 153 `dep_capable="0"` co-change rows in the top 400, a per-file-only flip would have turned
// 88 capable, and 75 of those 88 are cross-dialect (.h↔.sh, .cpp↔.sh, .py↔.sh, .js↔.sh) and would have
// rendered as "hidden architectural debt" that no include edge could ever have explained.
//
// One group per resolvable dialect; C-family is one group because a .c/.h/.cpp/.mm genuinely include one
// another, and TS+JS is one group because their specifiers resolve against one shared extension ladder
// (resolve.h::resolveTsImport). Every other language resolves only onto its own files (resolve.h's
// Step-A candidate lists are extension-closed), so each is its own group. Java/Go/Swift/C#/PHP keep a
// group despite being DEFERRED in the resolver: capability is about the language, not about how far this
// tool currently resolves it, and a deferred pair is honestly "could carry one, we found none". Kotlin
// joins Java's group rather than minting its own, for the SAME reason C-family is one group: a Kotlin
// file genuinely imports a Java class and vice versa in a mixed Android/JVM module (graph.h's
// langCompatible bridges the two for the same reason on the call-graph side) — a separate Kotlin dialect
// would report a real cross-language import pair as "not defined" instead of "found none".
enum class DepDialect : std::uint8_t { None = 0, CFamily, Web, Python, Rust, Go, Swift, Java, CSharp, Php, Bash, Ruby, Lua, Elixir };

/// Return the dependency dialect of a language, or DepDialect::None when it carries no file dependency.
inline DepDialect dependencyDialect( Lang lang ) noexcept
{
    switch( lang )
    {
        case Lang::Cpp: case Lang::C: case Lang::ObjC:  return DepDialect::CFamily;
        case Lang::TypeScript: case Lang::JavaScript:   return DepDialect::Web;
        case Lang::Python:                              return DepDialect::Python;
        case Lang::Rust:                                return DepDialect::Rust;
        case Lang::Go:                                  return DepDialect::Go;
        case Lang::Swift:                               return DepDialect::Swift;
        case Lang::Java: case Lang::Kotlin:              return DepDialect::Java;
        case Lang::CSharp:                              return DepDialect::CSharp;
        case Lang::Php:                                 return DepDialect::Php;
        case Lang::Bash:                                return DepDialect::Bash;
        case Lang::Ruby:                                return DepDialect::Ruby;
        case Lang::Lua:                                 return DepDialect::Lua;
        case Lang::Elixir:                              return DepDialect::Elixir;
        case Lang::Json: case Lang::Toml: case Lang::Yaml: case Lang::Markdown: case Lang::Unknown:
        default:                                        return DepDialect::None;
    }
}

// Could a physical dependency edge exist between a file of language `a` and one of language `b`, in
// EITHER direction? Both sides must be dependency-capable AND share a dialect. Bash is the one language
// whose resolver probes a written path with no extension ladder (`source ./config`), so it CAN in
// principle land on a file this predicate calls a different dialect; that direction under-claims (the
// pair reads "not defined" instead of "not surprising"), which is the safe way to be wrong here — the
// alternative over-claims hidden coupling, which is the finding §A9.3 removed.
inline bool dependencyPairCapable( Lang a, Lang b ) noexcept
{
    const DepDialect da = dependencyDialect( a );
    return da != DepDialect::None && da == dependencyDialect( b );
}

// The capable SET, as the terse output labels, comma-joined in Lang-enum order — derived from
// dependencyCapable() and langTag() so it can never drift from the predicate it documents. `--deps
// <health dep_langs=>` publishes it: a `dep_files=` denominator that changed between two releases is
// otherwise an unexplained number, and this makes the set that produced it readable off the same line.
inline std::string dependencyCapableLangTags()
{
    std::string out;
    for( std::size_t i = 0; i < kLangCount; ++i )
    {
        const Lang l = Lang( i );
        if( l == Lang::Unknown || !dependencyCapable( l ) )
        {
            continue;
        }
        if( !out.empty() ) { out.push_back( ',' ); }
        out.append( langTag( l ) );
    }
    return out;
}

// One mask, built once, shared by --deps <health> (graph.h::dependencyHealth) and --arch's
// propagation_cost (arch.h::dsmPropagationCost) so the two verbs' N is provably the SAME denominator —
// the plan's explicit requirement, not just a coincidence of two independent counts.
inline std::vector<char> dependencyCapableMask( const IngestResult& ing )
{
    std::vector<char> mask( ing.files.size(), 0 );
    for( std::size_t f = 0; f < ing.files.size(); ++f )
    {
        mask[f] = dependencyCapable( langOfPath( ing.files[f] ) ) ? 1 : 0;
    }
    return mask;
}

// ── the tiny YAML-subset parser ──────────────────────────────────────────────────────────────────
namespace lintdetail
{

inline std::string_view rtrim( std::string_view s ) noexcept
{
    while( !s.empty() && ( s.back() == ' ' || s.back() == '\t' || s.back() == '\r' || s.back() == '\n' ) )
    {
        s.remove_suffix( 1 );
    }
    return s;
}
inline std::string_view ltrim( std::string_view s ) noexcept
{
    while( !s.empty() && ( s.front() == ' ' || s.front() == '\t' ) )
    {
        s.remove_prefix( 1 );
    }
    return s;
}
inline std::string_view trim( std::string_view s ) noexcept { return rtrim( ltrim( s ) ); }

// leading-space count (indentation) of a raw line (tabs count as one column each — good enough for the
// block-scalar boundary test; we never mix tabs and spaces in the fixtures).
inline std::size_t indentOf( std::string_view line ) noexcept
{
    std::size_t n = 0;
    while( n < line.size() && ( line[n] == ' ' || line[n] == '\t' ) )
    {
        ++n;
    }
    return n;
}

// strip surrounding matched quotes from a scalar value (either '...' or "..."). No escape processing —
// the values we accept (ids, messages, severities) don't need it.
inline std::string_view unquote( std::string_view v ) noexcept
{
    if( v.size() >= 2 && ( ( v.front() == '"' && v.back() == '"' ) || ( v.front() == '\'' && v.back() == '\'' ) ) )
    {
        return v.substr( 1, v.size() - 2 );
    }
    return v;
}

}   // namespace lintdetail

// Parse ONE rules file into `rules` (appending). Returns false and leaves a stderr diagnostic (file +
// 1-based line) on the first shape violation — the caller then skips the whole file. `tagPrefix` makes
// each rule's synthetic tag unique across files (the file's basename); `ruleBase` is the running rule
// count so tags stay unique even within a file.
//
// Accepted shape (exactly):
//   - id: NAME                 <- a "- " at column 0 opens a new rule; the rest is its first field
//     language: cpp
//     severity: warn
//     message: some text
//     query: |
//       (s-expression ...)
//       (... multi line ...)
inline bool parseLintRuleFile( const std::string& path, std::string_view src, std::vector<LintRule>& rules )
{
    using namespace lintdetail;

    // Split into raw lines (keep line numbers 1-based for diagnostics).
    std::vector<std::string_view> lines;
    {
        std::size_t start = 0;
        for( std::size_t i = 0; i <= src.size(); ++i )
        {
            if( i == src.size() || src[i] == '\n' ) { lines.emplace_back( src.data() + start, i - start ); start = i + 1; }
        }
    }

    const auto badLine = [ & ]( std::size_t lineNo, const char* why ) -> bool
    {
        rw::emitTo( stderr, "ripwire: lint-rules: {}:{}: {} — file skipped\n", path.c_str(), lineNo + 1, why );
        DEGRADED_PATH_ALERT( "lint-rules: malformed rule file skipped" );
        return false;
    };

    std::vector<LintRule> parsed;   // stage locally; only commit to `rules` if the whole file is clean
    LintRule*             cur = nullptr;
    bool                  inQuery = false;      // inside a `<key>: |` block (query / inside / not-inside / not-matches)
    std::size_t           queryIndent = 0;      // the block's minimum body indent (first body line sets it)
    bool                  sawQueryLine = false;
    std::string           queryBuf;
    std::string*          queryDest = nullptr;  // where the flushed block body lands (a field, or a pushed-back vector slot)

    const auto flushQuery = [ & ]()
    {
        if( cur && inQuery && queryDest )
        {
            *queryDest = rtrim( queryBuf ); // trailing newline trimmed; interior preserved
        }
        inQuery = false;
        sawQueryLine = false;
        queryIndent = 0;
        queryBuf.clear();
        queryDest = nullptr;
    };

    for( std::size_t li = 0; li < lines.size(); ++li )
    {
        const std::string_view raw = lines[li];

        // Inside a block scalar: a line is body if it is blank OR indented deeper than the "query:" key.
        if( inQuery )
        {
            const std::string_view noNl = rtrim( raw );
            const bool             blank = trim( noNl ).empty();
            const std::size_t      ind   = indentOf( raw );
            const bool             isBody = blank || ind > cur->queryKeyIndent;
            if( isBody )
            {
                if( !sawQueryLine ) { queryIndent = blank ? 0 : ind; sawQueryLine = true; }
                // strip exactly the block's base indent from each body line; keep deeper indent (nested s-exprs)
                std::string_view body = raw;
                for( std::size_t k = 0; k < queryIndent && !body.empty() && ( body.front() == ' ' || body.front() == '\t' ); ++k )
                {
                    body.remove_prefix( 1 );
                }
                queryBuf.append( body );
                queryBuf.push_back( '\n' );
                continue;
            }
            flushQuery();   // dedent → block ended; fall through to normal handling of this line
        }

        const std::string_view content = trim( raw );
        if( content.empty() )
        {
            continue; // blank line between items — ignore
        }
        if( content.front() == '#' )
        {
            continue; // full-line comment — ignore
        }

        // A new rule opens with "- " at column 0 (no leading indent).
        const std::size_t ind = indentOf( raw );
        std::string_view  keyPart;
        if( ind == 0 && content.size() >= 2 && content[0] == '-' && ( content[1] == ' ' || content[1] == '\t' ) )
        {
            flushQuery();
            parsed.emplace_back();
            cur     = &parsed.back();
            keyPart = trim( content.substr( 1 ) );      // the field after "- "
        }
        else if( ind == 0 && content == "-" )
        {
            flushQuery();
            parsed.emplace_back();
            cur = &parsed.back();
            continue;                                    // "- " alone: the field is on following lines
        }
        else
        {
            if( cur == nullptr )
            {
                return badLine( li, "content before any '- ' list item" );
            }
            keyPart = content;                           // an item field line ("key: value")
        }

        // keyPart is "key: value" (value may be empty, or "|" to open a block scalar).
        const std::size_t colon = keyPart.find( ':' );
        if( colon == std::string_view::npos )
        {
            return badLine( li, "expected 'key: value'" );
        }
        const std::string_view key = trim( keyPart.substr( 0, colon ) );
        const std::string_view val = trim( keyPart.substr( colon + 1 ) );

        // A block-scalar or inline query lands in `dest`. Opening a "| block" arms the block-scalar state
        // pointed at `dest`; an inline value writes it directly. `dest` MUST stay valid until flushQuery —
        // for the combinator vectors we push_back first, then hand the stable back() slot's address here.
        const auto takeQuery = [ & ]( std::string* dest, const char* whatNeedsValue ) -> bool
        {
            if( val == "|" || val == "|-" || val == "|+" )
            {
                inQuery = true;  sawQueryLine = false;  queryIndent = 0;  queryBuf.clear();
                queryDest = dest;  cur->queryKeyIndent = ind;
            }
            else if( !val.empty() )
            {
                *dest = std::string( val ); // single-line inline query
            }
            else
            {
                return badLine( li, whatNeedsValue );
            }
            return true;
        };

        if( key == "id" )
        {
            cur->id = std::string( unquote( val ) );
        }
        else if( key == "severity" )
        {
            cur->severity = std::string( unquote( val ) );
        }
        else if( key == "message" )
        {
            cur->message = std::string( unquote( val ) );
        }
        else if( key == "language" )
        {
            if( !langFromToken( unquote( val ), cur->lang ) )
            {
                return badLine( li, "unknown 'language' (want cpp|python|typescript|go|rust|swift|objc)" );
            }
        }
        else if( key == "query" )
        {
            if( !takeQuery( &cur->query, "'query:' needs a value or a '|' block" ) )
            {
                return false;
            }
        }
        else if( key == "inside" )
        {
            cur->inside.emplace_back();                                  // repeated key → AND (new slot each time)
            if( !takeQuery( &cur->inside.back(), "'inside:' needs a value or a '|' block" ) )
            {
                return false;
            }
        }
        else if( key == "not-inside" )
        {
            cur->notInside.emplace_back();                              // repeated key → OR (new slot each time)
            if( !takeQuery( &cur->notInside.back(), "'not-inside:' needs a value or a '|' block" ) )
            {
                return false;
            }
        }
        else if( key == "not-matches" )
        {
            cur->notMatches.emplace_back();                            // repeated key → OR (new slot each time)
            if( !takeQuery( &cur->notMatches.back(), "'not-matches:' needs a value or a '|' block" ) )
            {
                return false;
            }
        }
        else
        {
            return badLine( li, "unknown key (want id|language|severity|message|query|inside|not-inside|not-matches)" );
        }
    }
    flushQuery();

    // Validate + finalise each staged rule. Any invalid rule dooms the file (skip it whole).
    for( std::size_t ri = 0; ri < parsed.size(); ++ri )
    {
        LintRule& r = parsed[ri];
        if( r.id.empty() )
        {
            return badLine( 0, "a rule is missing 'id'" );
        }
        if( r.query.empty() )
        {
            return badLine( 0, "rule has no 'query'" );
        }
        if( r.severity.empty() )
        {
            r.severity = "warn";
        }
        if( !isValidSeverity( r.severity ) )
        {
            return badLine( 0, "invalid 'severity' (want info|warn|error)" );
        }
        // A combinator block that opened with '|' but got no body is malformed — empty constraint queries would
        // silently no-op (inside → drop everything, not-inside/not-matches → filter nothing); refuse the file.
        for( const std::string& q : r.inside )
        {
            if( q.empty() )
            {
                return badLine( 0, "empty 'inside' query" );
            }
        }
        for( const std::string& q : r.notInside )
        {
            if( q.empty() )
            {
                return badLine( 0, "empty 'not-inside' query" );
            }
        }
        for( const std::string& q : r.notMatches )
        {
            if( q.empty() )
            {
                return badLine( 0, "empty 'not-matches' query" );
            }
        }
    }

    // Commit — assign globally-unique synthetic routing tags now that the file is known clean.
    for( std::size_t ri = 0; ri < parsed.size(); ++ri )
    {
        parsed[ri].tag = path + "#" + std::to_string( rules.size() );
        rules.push_back( std::move( parsed[ri] ) );
    }
    return true;
}

// ── the public loader ────────────────────────────────────────────────────────────────────────────
// Load every *.yml / *.yaml file in `dir` (SORTED, for determinism) into a flat rule list. Malformed
// files are alerted + skipped (never abort). Returns the rules; the caller decides exit-1-on-empty.
inline std::vector<LintRule> loadLintRules( const std::string& dir )
{
    namespace fs = std::filesystem;
    std::vector<LintRule> rules;

    std::error_code ec;
    if( !fs::is_directory( dir, ec ) )
    {
        // No DEGRADED_PATH_ALERT (M7/F20): the caller REFUSES on an empty rule list, so the alert stamped a
        // "this run continued in a reduced mode" notice on stderr in front of a refusal that continued
        // nothing. The user-facing sentence is the whole message.
        rw::emitTo( stderr, "ripwire: --lint-rules: not a directory: {}\n", dir.c_str() );
        return rules;
    }

    // Collect + sort the rule-file paths for a deterministic load order.
    std::vector<std::string> files;
    for( fs::directory_iterator it( dir, ec ), end; !ec && it != end; it.increment( ec ) )
    {
        if( ec )
        {
            break;
        }
        if( !it->is_regular_file( ec ) || ec )
        {
            continue;
        }
        std::string ext = it->path().extension().string();
        for( char& c : ext )
        {
            c = static_cast<char>( std::tolower( static_cast<unsigned char>( c ) ) );
        }
        if( ext == ".yml" || ext == ".yaml" )
        {
            files.push_back( it->path().string() );
        }
    }
    std::sort( files.begin(), files.end() );

    for( const std::string& path : files )
    {
        // read the file
        std::FILE* fp = std::fopen( path.c_str(), "rb" );
        if( fp == nullptr ) { rw::emitTo( stderr, "ripwire: --lint-rules: cannot read {} — skipped\n", path.c_str() ); DEGRADED_PATH_ALERT( "lint-rules: unreadable file" ); continue; }
        std::string buf;
        {
            std::fseek( fp, 0, SEEK_END );
            const long sz = std::ftell( fp );
            std::fseek( fp, 0, SEEK_SET );
            if( sz > 0 )
            {
                buf.resize( std::size_t( sz ) );
                if( std::fread( buf.data(), 1, std::size_t( sz ), fp ) != std::size_t( sz ) )
                {
                    buf.clear();
                }
            }
            std::fclose( fp );
        }

        const std::size_t before = rules.size();
        if( !parseLintRuleFile( path, buf, rules ) )
        {
            rules.resize( before );   // roll back any rules this file half-committed (parse commits atomically, but be safe)
        }
    }
    return rules;
}

// ── run the loaded rules → findings, tagged back to id/severity/message ──────────────────────────
// A user finding, shaped like the built-in AstMatch so main.cpp emits it identically. We keep the
// per-rule id/severity/message alongside so the <f> element can carry rule=" " sev=" ".
struct LintFinding
{
    std::uint32_t fileId    = 0;
    std::uint32_t startByte = 0;
    std::uint32_t line      = 0;
    std::string   id;         // rule id  → rule="
    std::string   severity;   // sev="
    std::string   message;    // element text
};

// ── span-algebra helpers (phase-2 combinators) ────────────────────────────────────────────────────
namespace lintdetail
{

// A candidate/constraint span, tagged with which rule + constraint-slot produced it. `group` bundles the
// rule index with the constraint kind+slot so collapse and lookup never cross rules or combinator blocks.
struct Span
{
    std::uint32_t fileId    = 0;
    std::uint32_t startByte = 0;
    std::uint32_t endByte   = 0;
    std::uint32_t line      = 0;
    std::size_t   group     = 0;   // opaque routing key (rule index for candidates; encoded rule+kind+slot for constraints)
};

// Collapse enclosed captures per (group, file): drop any span fully contained in ANOTHER kept span of the
// SAME group+file, so a multi-capture pattern yields one span per match (`@hit`/`@scope` outer survives,
// inner `@fn`/`@t` captures fold away). Equal spans (same start AND end) keep the FIRST after the stable
// sort and drop the duplicate — a zero-set difference. Same O(n log n) sort + linear sweep as phase 1.
inline void collapseEnclosed( std::vector<Span>& spans )
{
    std::sort( spans.begin(), spans.end(), []( const Span& a, const Span& b )
               {
                   if( a.group != b.group )
                   {
                       return a.group < b.group;
                   }
                   if( a.fileId != b.fileId )
                   {
                       return a.fileId < b.fileId;
                   }
                   if( a.startByte != b.startByte )
                   {
                       return a.startByte < b.startByte; // outer (smaller start) first
                   }
                   return a.endByte > b.endByte;                                        // ...and widest span first
               } );
    std::vector<char> keep( spans.size(), 1 );
    for( std::size_t i = 0; i < spans.size(); ++i )
    {
        if( !keep[i] )
        {
            continue;
        }
        for( std::size_t j = i + 1; j < spans.size(); ++j )
        {
            if( spans[j].group != spans[i].group || spans[j].fileId != spans[i].fileId )
            {
                break;
            }
            if( spans[j].startByte >= spans[i].endByte )
            {
                break; // past the enclosing span
            }
            if( spans[j].endByte <= spans[i].endByte )
            {
                keep[j] = 0; // fully contained (or equal) → inner/dup
            }
        }
    }
    std::size_t w = 0;
    for( std::size_t i = 0; i < spans.size(); ++i )
    {
        if( keep[i] )
        {
            spans[w++] = spans[i];
        }
    }
    spans.resize( w );
}

// Span predicates (half-open [start,end) byte ranges; same file assumed by the caller).
inline bool contains( const Span& outer, const Span& inner ) noexcept   // inner fully inside outer (equal spans count as inside)
{
    return inner.startByte >= outer.startByte && inner.endByte <= outer.endByte;
}
inline bool coversOrEquals( const Span& cover, const Span& c ) noexcept  // cover spans the whole of c (equal or wider)
{
    return cover.startByte <= c.startByte && cover.endByte >= c.endByte;
}

}   // namespace lintdetail

// Run every rule through the shared astQuery engine, then keep only findings whose FILE-language matches
// the rule's language, collapse each match's captures to its widest span (the `@hit` node encloses inner
// predicate captures like `@fn`), and APPLY the phase-2 combinators (inside / not-inside / not-matches) as
// pure span algebra over the candidate + constraint span sets. Deterministically sorted like the built-ins.
//
// Span-algebra contract (documented edge cases):
//   • CANDIDATE span   = the main query's widest per-match span (the collapse above).
//   • CONSTRAINT spans = each combinator query's widest per-match spans (collapsed the SAME way), so
//     `(function_definition) @scope` / `(comment) @x` give the outer region. For not-matches, CAPTURE THE
//     NODE YOU WANT COMPARED (an outer `@`): the constraint span is what you captured, and a candidate is
//     dropped iff some constraint span EQUALS or COVERS it — an inner-only capture (e.g. a lone `@t` deep in
//     the pattern) is smaller than the candidate and will NOT cover it, so it would not drop.
//   • inside      : AND across blocks — kept iff, for EVERY inside query, the candidate is contained in ≥1
//                   of that query's spans in the same file. (A rule with an inside query but zero constraint
//                   spans in a file → nothing kept there.)
//   • not-inside  : OR across blocks — dropped iff contained in ≥1 span of ANY not-inside query (same file).
//   • not-matches : OR across blocks — dropped iff some span of ANY not-matches query equals/covers it.
//   • equal spans : "contained" and "covers" are inclusive, so a constraint span exactly equal to the
//                   candidate satisfies inside and triggers not-inside / not-matches.
//   • zero-width  : astQuery already drops zero/negative-width captures (a >= b), so no zero-width spans reach here.
//   • cross-file  : constraints are matched ONLY within the candidate's own file (span bytes are per-file).
//
// §P0.2: every spec below spends its OWN astQuery budget (kUserRuleMaxPerRule), so a user rule matching
// every number literal can no longer starve the rule next to it out of the pool. A rule whose raw candidate
// stream lands ON that budget has a count= that is a FLOOR; its id comes back in `saturatedRuleIds` so the
// caller can disclose it rather than print a truncated tally as a total.
struct LintRulesRun
{
    std::vector<LintFinding> findings;
    std::vector<std::string> saturatedRuleIds;   // rule ids whose candidate stream spent its whole budget
    // §L10: rule ids whose MAIN query compiled for NO linked grammar (a malformed/misspelled tree-sitter
    // pattern) — astQuery already alerts on stderr and silently contributes zero matches for these, which
    // made a broken query byte-identical, on stdout, to a well-formed query that legitimately found
    // nothing. The caller marks these rows compiled="0" instead of a bare count="0" (see printLintRuleTallyRow).
    std::vector<std::string> uncompiledRuleIds;
};

// The per-rule astQuery budget shared by the built-in checks (--lint) and the user rules (--lint-rules).
// ONE constant so the two tallies are capped on the same scale and `capped="1"` means the same thing in both.
inline constexpr std::size_t kLintMaxPerRule = 5000;

inline LintRulesRun runLintRules( const IngestResult& ing, const std::vector<LintRule>& rules )
{
    using namespace lintdetail;
    std::vector<LintFinding> out;
    std::vector<std::string> saturatedRuleIds;
    if( rules.empty() || ing.files.empty() )
    {
        return { std::move( out ), std::move( saturatedRuleIds ) };
    }

    // Constraint-group encoding: pack (ruleIdx, kind, slot) into one std::size_t `group` distinct from any
    // candidate group (a bare ruleIdx). kind ∈ {1:inside, 2:not-inside, 3:not-matches}; slot = block index.
    const auto constraintGroup = []( std::size_t ruleIdx, std::size_t kind, std::size_t slot ) noexcept -> std::size_t
    {
        // reserve the low bit-band for candidates (kind 0); shift so candidate ruleIdx (kind 0) never collides.
        return ( ruleIdx << 8 ) | ( kind << 4 ) | ( slot & 0xF );   // ≤16 blocks/kind, ≤2^56 rules — ample
    };
    const std::size_t kindInside = 1, kindNotInside = 2, kindNotMatches = 3;

    // Build astQuery specs: the main query per rule PLUS one spec per combinator query. Each combinator spec
    // gets a UNIQUE tag ("<rule tag>\x1c<kind><slot>", \x1c never appears in a path) so its spans route back
    // to the right (rule, kind, slot). Invalid ts queries alert+drop inside astQuery — a bad combinator query
    // simply contributes no constraint spans (inside → the rule matches nothing; not-* → nothing filtered).
    std::vector<AstQuerySpec>                     specs;
    HashMap<std::string, std::size_t>             tagToGroup;   // combinator tag → encoded constraint group
    HashMap<std::string, std::size_t>             tagToRule;    // main-query tag → rule index (candidates)
    specs.reserve( rules.size() * 2 );  tagToGroup.reserve( rules.size() * 2 );  tagToRule.reserve( rules.size() );

    const auto addCombinator = [ & ]( std::size_t ruleIdx, std::size_t kind, const std::vector<std::string>& qs )
    {
        for( std::size_t slot = 0; slot < qs.size(); ++slot )
        {
            std::string tag = rules[ruleIdx].tag + "\x1c" + char( '0' + kind ) + std::to_string( slot );
            specs.push_back( { qs[slot], tag } );
            tagToGroup.emplace( std::move( tag ), constraintGroup( ruleIdx, kind, slot ) );
        }
    };
    for( std::size_t i = 0; i < rules.size(); ++i )
    {
        specs.push_back( { rules[i].query, rules[i].tag } );
        tagToRule.emplace( rules[i].tag, i );
        addCombinator( i, kindInside,     rules[i].inside );
        addCombinator( i, kindNotInside,  rules[i].notInside );
        addCombinator( i, kindNotMatches, rules[i].notMatches );
    }

    std::vector<std::string>    uncompiledQueries;   // §L10: query TEXT of every spec that compiled for no grammar
    const std::vector<AstMatch> ms = astQuery( ing, specs, kLintMaxPerRule, &uncompiledQueries );

    for( const LintRule& r : rules )    // saturation is measured on the RAW candidate stream, before the combinators thin it
    {
        std::size_t rawForRule = 0;
        for( const AstMatch& m : ms )
        {
            if( m.tag == r.tag )
            {
                ++rawForRule;
            }
        }
        if( rawForRule >= kLintMaxPerRule )
        {
            saturatedRuleIds.push_back( r.id );
        }
    }

    // §L10: a rule whose MAIN query (not a combinator — those degrade silently by design, see addCombinator's
    // comment above) is in uncompiledQueries never contributed a single AstMatch, so it is indistinguishable
    // from a well-formed query that legitimately matched nothing. Matched by query TEXT (astQuery's own
    // uncompiledOut contract carries no tag) — two rules sharing byte-identical broken query text both get
    // marked, which is the conservative, honest direction (never hides a real compile failure).
    std::vector<std::string> uncompiledRuleIds;
    if( !uncompiledQueries.empty() )
    {
        for( const LintRule& r : rules )
        {
            if( std::find( uncompiledQueries.begin(), uncompiledQueries.end(), r.query ) != uncompiledQueries.end() )
            {
                uncompiledRuleIds.push_back( r.id );
            }
        }
    }

    // Split matches into candidate spans (main query, keyed by rule index) and constraint spans (combinator
    // queries, keyed by the encoded group). Language-gate BOTH by the owning rule's language so a constraint
    // never fires on a foreign-language file (a candidate can only exist on a rule-language file anyway).
    std::vector<Span> candidates;   candidates.reserve( ms.size() );
    std::vector<Span> constraints;  constraints.reserve( ms.size() );
    for( const AstMatch& m : ms )
    {
        if( const auto it = tagToRule.find( m.tag ); it != tagToRule.end() )
        {
            const LintRule& r = rules[ it->second ];
            if( langOfPath( ing.files[m.fileId] ) != r.lang )
            {
                continue;
            }
            candidates.push_back( { m.fileId, m.startByte, m.endByte, m.line, it->second } );
        }
        else if( const auto jt = tagToGroup.find( m.tag ); jt != tagToGroup.end() )
        {
            const std::size_t ruleIdx = jt->second >> 8;
            if( langOfPath( ing.files[m.fileId] ) != rules[ruleIdx].lang )
            {
                continue;
            }
            constraints.push_back( { m.fileId, m.startByte, m.endByte, m.line, jt->second } );
        }
    }

    // Collapse both sets to widest-per-match spans (candidate `@hit`, constraint `@scope`/`@x`/…).
    collapseEnclosed( candidates );
    collapseEnclosed( constraints );

    // Index constraint spans by (group, file) → contiguous ranges for O(1)-ish lookup during filtering.
    // constraints is already sorted by (group, file, start) from collapseEnclosed; record range starts.
    struct Range { std::size_t begin, end; };
    HashMap<std::uint64_t, Range> constraintIndex;   // key = group<<32 | fileId  → [begin,end) in constraints
    constraintIndex.reserve( constraints.size() );
    for( std::size_t i = 0; i < constraints.size(); )
    {
        std::size_t j = i + 1;
        while( j < constraints.size() && constraints[j].group == constraints[i].group && constraints[j].fileId == constraints[i].fileId )
        {
            ++j;
        }
        const std::uint64_t key = ( std::uint64_t( constraints[i].group ) << 32 ) | constraints[i].fileId;
        constraintIndex.emplace( key, Range{ i, j } );
        i = j;
    }
    const auto lookup = [ & ]( std::size_t group, std::uint32_t fileId ) -> Range
    {
        const std::uint64_t key = ( std::uint64_t( group ) << 32 ) | fileId;
        const auto it = constraintIndex.find( key );
        return it == constraintIndex.end() ? Range{ 0, 0 } : it->second;
    };

    // Filter each candidate through its rule's combinators, then emit the survivors.
    for( const Span& cand : candidates )
    {
        const std::size_t ruleIdx = cand.group;
        const LintRule&   r       = rules[ruleIdx];

        // inside: AND across every inside block — the candidate must be contained in ≥1 span of EACH.
        bool keptByInside = true;
        for( std::size_t slot = 0; slot < r.inside.size() && keptByInside; ++slot )
        {
            const Range rg = lookup( constraintGroup( ruleIdx, kindInside, slot ), cand.fileId );
            bool anyContains = false;
            for( std::size_t k = rg.begin; k < rg.end && !anyContains; ++k )
            {
                if( contains( constraints[k], cand ) )
                {
                    anyContains = true;
                }
            }
            keptByInside = anyContains;                                 // this block unsatisfied ⇒ candidate dropped
        }
        if( !keptByInside )
        {
            continue;
        }

        // not-inside: OR across blocks — dropped if contained in ≥1 span of ANY not-inside query.
        bool droppedByNotInside = false;
        for( std::size_t slot = 0; slot < r.notInside.size() && !droppedByNotInside; ++slot )
        {
            const Range rg = lookup( constraintGroup( ruleIdx, kindNotInside, slot ), cand.fileId );
            for( std::size_t k = rg.begin; k < rg.end; ++k )
            {
                if( contains( constraints[k], cand ) ) { droppedByNotInside = true; break; }
            }
        }
        if( droppedByNotInside )
        {
            continue;
        }

        // not-matches: OR across blocks — dropped if some constraint span equals/covers the candidate.
        bool droppedByNotMatches = false;
        for( std::size_t slot = 0; slot < r.notMatches.size() && !droppedByNotMatches; ++slot )
        {
            const Range rg = lookup( constraintGroup( ruleIdx, kindNotMatches, slot ), cand.fileId );
            for( std::size_t k = rg.begin; k < rg.end; ++k )
            {
                if( coversOrEquals( constraints[k], cand ) ) { droppedByNotMatches = true; break; }
            }
        }
        if( droppedByNotMatches )
        {
            continue;
        }

        out.push_back( { cand.fileId, cand.startByte, cand.line, r.id, r.severity, r.message } );
    }

    // Deterministic final order: by (file path, startByte, id) — identical discipline to the built-ins.
    std::sort( out.begin(), out.end(), [ & ]( const LintFinding& a, const LintFinding& b )
               {
        if( ing.files[a.fileId] != ing.files[b.fileId] ) { return ing.files[a.fileId] < ing.files[b.fileId];
}
        if( a.startByte != b.startByte ) { return a.startByte < b.startByte;
}
        return a.id < b.id; } );
    return { std::move( out ), std::move( saturatedRuleIds ), std::move( uncompiledRuleIds ) };
}

// ── built-in ERROR-MASKING rule table (GitClear 2026: +47% error-masking constructs in AI-authored code,
//    2023→2026) ──────────────────────────────────────────────────────────────────────────────────────────
//
// A DECLARATIVE constexpr table (house rule: tables over scattered ifs) of the deterministic error-masking
// shapes ripwire's --quality-delta flags as a NEW regression. Each row is one tree-sitter query that captures
// the SUPPRESSING BLOCK (`@m`) — the catch body, the except handler body, or the swallowing arrow body — plus
// an `emptyOnly` bit: when set, a hit counts ONLY if the captured block is EMPTY (its collapsed source is just
// `{}`), so a catch that actually logs/rethrows is not a false positive. Python's `pass`/`...` handler bodies
// are matched structurally (the query already narrows to a pass/ellipsis-only block) so `emptyOnly` is off.
//
// A query that names a node-type absent from a given grammar simply fails to compile for that grammar and is
// dropped silently by astQuery (verified in ingest.cpp) — so a cross-language table is safe: each row only
// fires on the grammars where its node-types exist. Zero new dependencies; runs the SAME astQuery engine.
struct ErrorMaskRule
{
    std::string_view query;      // tree-sitter s-expression capturing the suppressing block as @m
    std::string_view id;         // stable rule id (also the --lint-style handle if ever surfaced)
    bool             emptyOnly;  // true → count only when the @m block's collapsed source is exactly "{}"
};

// The table. C-family (C/C++/ObjC), Java, TS/JS empty catches; Python bare/pass/ellipsis except handlers;
// swallowed promise rejections (`.catch(()=>{})` / `.then(...,()=>{})` empty handler). Go's ignored-error
// `_ =` discard is deliberately OMITTED: distinguishing an error-typed discard from a benign `_ =` needs type
// info ripwire does not have, so a deterministic, low-false-positive rule is not available (documented skip).
inline constexpr std::array<ErrorMaskRule, 7> kErrorMaskRules = { {
    { "(catch_clause body: (compound_statement) @m)",                                    "empty-catch-cfamily", true  },  // C/C++/ObjC
    { "(catch_clause body: (block) @m)",                                                 "empty-catch-java",    true  },  // Java
    { "(catch_clause body: (statement_block) @m)",                                       "empty-catch-tsjs",    true  },  // TS/JS
    { "(except_clause (block (pass_statement)) @m)",                                      "swallow-except-pass", false },  // Python: except ...: pass
    { "(except_clause (block (expression_statement (ellipsis))) @m)",                    "swallow-except-dots", false },  // Python: except ...: ...
    { "(call_expression function: (member_expression property: (property_identifier) @p (#eq? @p \"catch\")) arguments: (arguments (arrow_function body: (statement_block) @m)))", "swallow-catch-arrow", true  },  // .catch(()=>{})
    { "(call_expression function: (member_expression property: (property_identifier) @p (#eq? @p \"then\"))  arguments: (arguments (_) (arrow_function body: (statement_block) @m)))", "swallow-then-arrow",  true  },  // .then(_, ()=>{})
} } ;

// Does the captured block SWALLOW — is there nothing in it that could handle the error? astQuery returns the
// @m span text with \n/\r/\t already flattened to spaces and truncated to 120 chars; an empty `{}` (even
// `{  }` / `{ }`) is far under 120, so the collapsed check is exact for the shapes we target. Deterministic.
//
// Q-DIAL-6 (2026-09-10) — A COMMENT IS NOT A HANDLER. This asked one question, "is the collapsed text exactly
// {}", and audit lane Q1's synthetic S2b — `catch( const std::exception& ) { /* ignore */ }` — walked straight
// past it, as does every `// intentionally ignored`. The comment is where the intent is WRITTEN DOWN; it is
// the most likely spelling of a deliberate swallow, and it was the one spelling the kind could not see. A
// block whose only content is a comment counts. Measured on 40 replayed commits of this repo: +0 rows — the
// widening finds nothing in this history and turns S2b from a silent miss into a reported row.
//
// TWO FLOORS, stated. (1) astQuery truncates the span at 120 characters, so a comment-only block longer than
// that does not end in '}' here and is not recognized — a miss, never a false hit. (2) The scan is over
// flattened text, so a ';' or a '{' anywhere inside means "a statement survives" and the block is not a
// swallow, which is what keeps `catch { log( x ); }` out; a semicolon inside the comment PROSE therefore also
// keeps the block out. Both directions of the imprecision lose recall rather than manufacturing a finding.
// The @p capture filter in findErrorMasking depends on a bare identifier ("catch"/"then") answering false
// here, and it still does: no braces, no match.
// The comment-only half, factored out so neither this test nor its caller crosses a complexity bar: is
// `collapsed` a brace pair whose entire interior is one comment? Called only after the exact-`{}` test has
// already failed.
inline bool errorMaskBlockIsCommentOnly( std::string_view collapsed ) noexcept
{
    std::string_view t = collapsed;
    while( !t.empty() && ( t.front() == ' ' || t.front() == '\t' ) ) { t.remove_prefix( 1 ); }
    while( !t.empty() && ( t.back()  == ' ' || t.back()  == '\t' ) ) { t.remove_suffix( 1 ); }
    if( t.size() < 2 || t.front() != '{' || t.back() != '}' )
    {
        return false;
    }
    const std::string_view mid = t.substr( 1, t.size() - 2 );
    if( mid.find( ';' ) != std::string_view::npos || mid.find( '{' ) != std::string_view::npos )
    {
        return false;   // a statement survives inside it — not a swallow
    }
    std::size_t first = std::string_view::npos;
    for( std::string_view opener : { std::string_view( "//" ), std::string_view( "/*" ), std::string_view( "#" ) } )
    {
        const std::size_t at = mid.find( opener );
        if( at != std::string_view::npos && ( first == std::string_view::npos || at < first ) ) { first = at; }
    }
    if( first == std::string_view::npos )
    {
        return false;   // content that is not a comment at all
    }
    return mid.substr( 0, first ).find_first_not_of( " \t" ) == std::string_view::npos;
}

// ── the EXACT answer, over the block's UNFLATTENED bytes (CodeRabbit #127 / 3985249701) ─────────────
// The test above is a PREFILTER and nothing more: it proves a comment OPENS the interior, never that the
// comment CLOSES it. `catch( e ) { /* ignore */ recover() }` is valid JavaScript, holds no ';' and no inner
// '{', and opens with a comment — so the prefilter said "comment-only" about a block that handles the
// error, and the kind manufactured a finding. That is the one direction §Q-DIAL-6's own floors forbid.
//
// It cannot be fixed on the flattened text. astQuery scrubs '\n' to ' ' (makeAstMatch, the ONE cut), and a
// `//` comment ends at a newline that is no longer there: `{ // ignore <NL> recover() }` and
// `{ // ignore recover() }` are the same 23 bytes after the scrub, and the first is a handler while the
// second is a swallow. So the confirm reads the block's RAW bytes and asks the only question that decides
// it — does comment text consume the WHOLE interior?
//
//   /* … */   spans to its closer; an unterminated one is NOT comment-only (it cannot be, the block closed)
//   //  #     run to the end of THEIR line — the fact the scrub destroyed
//   between   only spaces, tabs, CR and LF
//
// `raw` is the block's bytes cut to exactly the length astQuery cut its text to, so the 120-byte floor
// §Q-DIAL-6 states is preserved character for character: this confirm can only REMOVE rows, never add one.
inline bool errorMaskCommentConsumesBlock( std::string_view raw ) noexcept
{
    const auto isSpace = []( char c ) noexcept { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; };

    std::string_view t = raw;
    while( !t.empty() && isSpace( t.front() ) ) { t.remove_prefix( 1 ); }
    while( !t.empty() && isSpace( t.back()  ) ) { t.remove_suffix( 1 ); }
    if( t.size() < 2 || t.front() != '{' || t.back() != '}' )
    {
        return false;
    }

    const std::string_view mid = t.substr( 1, t.size() - 2 );
    std::size_t            at  = 0;
    while( at < mid.size() )
    {
        if( isSpace( mid[ at ] ) )
        {
            ++at;
            continue;
        }
        if( mid.compare( at, 2, "/*" ) == 0 )
        {
            const std::size_t close = mid.find( "*/", at + 2 );
            if( close == std::string_view::npos )
            {
                return false;      // the block closed but the comment did not — not decidable as a swallow
            }
            at = close + 2;
            continue;
        }
        if( mid.compare( at, 2, "//" ) == 0 || mid[ at ] == '#' )
        {
            const std::size_t nl = mid.find( '\n', at );
            if( nl == std::string_view::npos )
            {
                return true;       // the line comment runs to the end of the interior
            }
            at = nl + 1;
            continue;
        }
        return false;              // code survives inside the block — a handler, not a swallow
    }
    return true;
}

// A brace pair with nothing at all between them. Split out from errorMaskBlockIsEmpty so the caller can
// tell WHICH half answered: this one needs no confirm (there is no comment to mis-read), the comment half
// does.
inline bool errorMaskBlockIsBareBraces( std::string_view collapsed ) noexcept
{
    std::string stripped;
    for( char c : collapsed )
    {
        if( c != ' ' && c != '\t' && c != '\n' && c != '\r' )
        {
            stripped.push_back( c );
        }
    }
    return stripped == "{}";
}

// THE PREFILTER, over astQuery's flattened span text. Cheap and deliberately over-accepting on its comment
// half — findErrorMasking confirms every row this admits through a comment against the block's RAW bytes
// (errorMaskCommentConsumesBlock). Never call this alone to decide a finding.
inline bool errorMaskBlockIsEmpty( std::string_view collapsed ) noexcept
{
    return errorMaskBlockIsBareBraces( collapsed ) || errorMaskBlockIsCommentOnly( collapsed );
}

// THE CONFIRM (CodeRabbit #127 / 3985249701), as its own step so findErrorMasking stays under the bars.
// The flattened prefilter cannot see where a `//` comment ends, because astQuery scrubbed the newline
// that ended it — so a block admitted through its COMMENT half is re-asked of the file's own bytes. A
// bare `{}` never reaches here: there is no comment there to mis-read, and skipping it keeps the cost at
// "one read per file that has a comment-shaped candidate", a handful of files rather than the corpus.
//
// `m.text.size()` IS the cut length makeAstMatch used (the scrub is byte-for-byte), so the raw slice is
// the same span — the 120-byte floor §Q-DIAL-6 discloses is preserved exactly. `memoFileId`/`memoBytes`
// are the caller's ONE-ENTRY memo: astQuery already sorts (file, startByte, tag), so one slot holds a
// whole file's candidates. An UNREADABLE or MOVED file answers false — a finding that cannot be
// substantiated is not reported. Never throws.
inline bool errorMaskConfirmOnDisk( const IngestResult& ing, const AstMatch& m,
                                    std::uint32_t& memoFileId, std::string& memoBytes )
{
    if( m.fileId != memoFileId )
    {
        memoFileId = m.fileId;
        std::optional<std::string> bytes = docparse::detail::readWholeFile( diskPath( ing, m.fileId ) );
        if( !bytes )
        {
            DEGRADED_PATH_ALERT( "lintrules: error-mask confirm cannot re-read the block's file" );
        }
        memoBytes = std::move( bytes ).value_or( std::string() );
    }
    if( std::size_t( m.startByte ) + m.text.size() > memoBytes.size() )
    {
        return false;
    }
    return errorMaskCommentConsumesBlock( std::string_view( memoBytes ).substr( m.startByte, m.text.size() ) );
}

// One error-masking hit: the suppressing block's file + start byte (so a caller can attribute it to the
// enclosing symbol by span containment), the 1-based line, and the rule id. Shaped for span attribution,
// not for direct emission — quality.h owns the delta accounting.
struct ErrorMaskHit
{
    std::uint32_t fileId    = 0;
    std::uint32_t startByte = 0;
    std::uint32_t line      = 0;
    std::string   id;
};

// Run the built-in error-masking table over the tree and return the surviving hits (empty-block filter
// applied). Deterministic: astQuery sorts (file, startByte, tag); we keep that order and only drop
// non-empty blocks for `emptyOnly` rules. Never throws (astQuery degrades per-file internally).
inline std::vector<ErrorMaskHit> findErrorMasking( const IngestResult& ing )
{
    std::vector<ErrorMaskHit> out;
    if( ing.files.empty() )
    {
        return out;
    }

    // Build one astQuery spec per rule, tagging with the rule index so the empty-block gate routes back.
    std::vector<AstQuerySpec> specs;
    specs.reserve( kErrorMaskRules.size() );
    for( std::size_t r = 0; r < kErrorMaskRules.size(); ++r )
    {
        specs.push_back( { std::string( kErrorMaskRules[r].query ), std::to_string( r ) } );
    }

    // The @m block capture is the WIDEST node in each match (it encloses the inner @p property id), so it is
    // the span astQuery reports for that match's block. But a match with a #eq? predicate also captures @p;
    // filter to the block capture by picking, per (file,startByte) match, the row's node — astQuery emits one
    // AstMatch per CAPTURE, so a swallow rule yields both a @p hit and a @m hit. We keep only the @m block by
    // its emptiness signature: @p (a bare identifier "catch"/"then") is never "{}", and for non-emptyOnly
    // Python rules @p does not exist, so every emitted capture is the block. Route by tag → rule.
    // one-entry raw-bytes memo for the confirm below: astQuery already sorts (file, startByte, tag), so the
    // candidates of one file arrive together and a single slot is the whole cache.
    std::uint32_t rawFileId = ~std::uint32_t( 0 );
    std::string   rawBytes;

    for( const AstMatch& m : astQuery( ing, specs ) )
    {
        std::size_t r = 0;
        {
            std::uint64_t v = 0;
            for( char c : m.tag )
            {
                if( c >= '0' && c <= '9' )
                {
                    v = v * 10 + std::uint64_t( c - '0' );
                }
            }
            r = std::size_t( v );
        }
        if( r >= kErrorMaskRules.size() )
        {
            continue;
        }
        const ErrorMaskRule& rule = kErrorMaskRules[r];
        if( rule.emptyOnly && !errorMaskBlockIsEmpty( m.text ) )
        {
            continue; // the @p identifier capture is dropped here too (never "{}")
        }
        if( rule.emptyOnly && !errorMaskBlockIsBareBraces( m.text )
            && !errorMaskConfirmOnDisk( ing, m, rawFileId, rawBytes ) )
        {
            continue;       // a comment OPENS the block but code follows it — that is a handler
        }
        out.push_back( { m.fileId, m.startByte, m.line, std::string( rule.id ) } );
    }

    // Deterministic order: (file path, startByte, id). astQuery already sorts (file, startByte, tag); re-sort
    // on the final key so the id tiebreak is the rule id, not its numeric tag.
    std::sort( out.begin(), out.end(), [ & ]( const ErrorMaskHit& a, const ErrorMaskHit& b )
               {
        if( ing.files[a.fileId] != ing.files[b.fileId] ) { return ing.files[a.fileId] < ing.files[b.fileId];
}
        if( a.startByte != b.startByte ) { return a.startByte < b.startByte;
}
        return a.id < b.id; } );
    return out;
}

}   // namespace rw
