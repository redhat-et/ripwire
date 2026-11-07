#pragma once
// formanifest.h — MANIFEST-ROW: when a --for task names a package, dependency, script, binary, build target or cargo feature that a
// manifest defines, the answer ends with the manifest's DEFINING LINES, before </ctx>. (CLI src/verbs_for.h appendForTaskRowBlocks,
// MCP `for` src/mcpverbs.h forTaskText — one renderer, renderForManifestRows.)
//
// WHY. Stage 0 (reports/d2d1-s0.md card 1a, reports/manifest-row.md): on "add a new built-in microservice transport like NATS or MQTT"
// the package that declares the broker libraries (packages/microservices/package.json, its optional peer dependencies) sat in the
// answer's path tail under about twelve code files, with no line; on "add a new optional extractor behind its own cargo feature like
// multipart" no answer row named the crate's feature table or the crate docs that list every feature. A manifest is not code, so the
// ranking never puts its lines first: this block reads them on their own allowance.
//
// WHEN (present-only). A task word (lowercased, singular, split on `-` `.` `/` `@`; a hyphenated word also as one folded word) EXACTLY
// names an entry a manifest defines (its last `/` segment, letters and digits only): an ANCHOR. Not an anchor: a name equal to the repo's
// own directory name, even beside a kind word (every task about a crate names the crate; such a row adds score and prints only
// beside a real anchor); a generic name (core, common, test, ..: kManifestGenericNames); a script unless the task says script,
// npm, yarn or pnpm (`test`, `build`, `lint` are in every package.json); a plugin entry point unless the task says plugin, entry
// point or extension. An entry point's group matches by any dot segment, even the repo's own name (`[project.entry-points.pydantic]`
// is pydantic's plugin hook). An entry also anchors only when the task says what KIND of thing it means (the cue words of its kind:
// dependency for a dependency, feature for a feature, package for a package, ..) or reads as adding one more X (exemplarTasksOf,
// EXEMPLAR's own trigger): a common word in a task is not a request for the third-party dependency or the Rust feature of that name
// (the review's 18 of 35 misleading fires). A manifest prints only when it holds an anchor; a partial
// match (a task word that is one part of a name: `nats` in `@nats-io/transport-node`) adds rows and score, never fires alone.
//
// READERS (line-based, the way the tools write these files): package.json name, main, bin, scripts, dependencies, devDependencies,
// peerDependencies, optionalDependencies (a key per line); Cargo.toml [package] / [lib] / [[bin]] name, [features] keys,
// [dependencies] / [dev-dependencies] / [build-dependencies] (also under [target.*] and [workspace]) keys and [dependencies.X]
// headers; pyproject.toml [project] / [tool.poetry] name, [project.optional-dependencies] / [tool.poetry.extras] keys,
// [tool.poetry.dependencies] / [tool.poetry.group.<g>.dependencies] / dev-dependencies keys (not `python`), and its entry points; setup.cfg [metadata] name, [options.extras_require] keys and
// [options.entry_points] (the entry points through epmanifest.h's own readers: a console / gui script is kind bin, every other group's
// entry kind entry-point with group=); go.mod module and require lines
// (`// indirect` ones skipped); CMakeLists.txt add_executable / add_library / project names (a call may span lines; IMPORTED and ALIAS
// targets, `#` and `#[[ ]]` comments are not read). package.json, Cargo.toml and
// pyproject.toml are indexed files; setup.cfg, go.mod and CMakeLists.txt are not, so they are looked for in every directory that
// holds an indexed file and in its ancestors. FLOORS: pyproject `dependencies = [..]` arrays, setup.py, Makefile, meson.build and
// Bazel files are not read; vendored, node_modules, fixtures and testdata manifests are skipped.
//
// RANK. A manifest scores 2 per task word it names exactly and 1 per word it names in part (the best per word); the highest score
// first, then more anchors, then the shallower path, then the path. kManifestFileRows manifests, kManifestRowsPerFile lines each
// (exact before part, then line order), every cut disclosed. When the leader only DEPENDS on what the task names, the best manifest that
// DEFINES a named thing (an anchor that is not a dependency: a package, bin, feature, ..) moves to the front.
//
// FEATURE TOUCH. When a printed manifest's anchor is a cargo feature or a Python extra, the files that mention at least half of that
// manifest's features (default and `_`-private ones left out) are listed with EXEMPLAR's touch list (exemplarfamily.h
// exemplarTouchList, one helper): where a new feature must also be documented or gated (axum's crate-doc feature table in lib.rs).
#include "arch.h" // splitSegments
#include "darkflags.h" // forEachLine
#include "eval.h" // minedjson::unescape: a JSON string's escapes decoded (`pub\u006cish` is publish)
#include "docparse.h" // detail::readRegularFile
#include "epmanifest.h" // epdetail TOML helpers: tomlHeaderParts, tomlKeyEnd, tomlKeyParts, tomlStringValue, tomlMultilineOpen
#include "exemplarfamily.h" // exemplar_detail::taskWords / singular; exemplarTouchList / touchListXml (the E3a co-mention scan)
#include "filter.h" // hasDirSegment
#include "infra/Diagnostics.h" // DISCLOSE: a manifest that could not be read is counted on the answer (unread=)
#include "ingest.h" // canonicalCrawlRoot / crawlPathStaysInRoot: a probed manifest that is a link must resolve inside the root
#include "infra/enumcount.h" // enumCountIsExact: kManifestKindTags / kManifestCues are indexed by ManifestKind
#include "infra/jsonesc.h" // jsonStringEnd: the one escape-aware JSON string walk
#include "infra/sortutil.h" // svLess
#include "lexical.h" // lexLowerByte
#include "model.h"
#include "resolve.h" // trimWs
#include "serialize.h" // escapeXml

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
inline constexpr std::size_t kManifestFileRows = 3; // manifests printed (files= counts every manifest holding an anchor)
inline constexpr std::size_t kManifestRowsPerFile = 3; // defining lines printed per manifest (rows= counts its matching lines)
inline constexpr std::size_t kManifestLineMax = 120; // bytes of a defining line printed (cut="1" when longer)

enum class ManifestKind : std::uint8_t
{
    Package,
    Module,
    Dep,
    DevDep,
    PeerDep,
    OptDep,
    Script,
    Bin,
    Main,
    Lib,
    Feature,
    Extra,
    Executable,
    Library,
    EntryPoint
};
inline constexpr std::size_t kManifestKindCount = static_cast<std::size_t>( ManifestKind::EntryPoint ) + 1;
static_assert( enumCountIsExact<ManifestKind, kManifestKindCount>(), "kManifestKindCount must name the LAST ManifestKind — move it with the append" );
inline constexpr std::array<std::string_view, kManifestKindCount> kManifestKindTags { "package", "module", "dep", "dev-dep", "peer-dep", "opt-dep", "script",
                                                                      "bin", "main", "lib", "feature", "extra", "executable", "library", "entry-point" };

// One name a manifest defines: the name as written, its line, what it is.
struct ManifestEntry
{
    std::string name;
    std::uint32_t line = 0;
    ManifestKind kind = ManifestKind::Package;
    std::string group; // an entry point's group (`pydantic`, `flake8.extension`); "" for every other kind
};

// One manifest read: its root-relative path, the indexed file id (UINT32_MAX: not an indexed file), its text and its entries.
struct ManifestDoc
{
    std::string rel;
    std::uint32_t fileId = UINT32_MAX;
    std::string text;
    std::vector<ManifestEntry> entries;
};

namespace manifest_detail
{
using exemplar_detail::singular;

// ── readers ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
// The depth change a byte makes: `{` and `[` open one, `}` and `]` close one.
inline int jsonDepthStep( char c ) noexcept
{
    return ( c == '{' || c == '[' ) ? 1 : ( c == '}' || c == ']' ) ? -1
                                                                   : 0;
}

// The string value that follows the colon at text[colon] ("" for any other value).
inline std::string_view jsonStringValueAfter( std::string_view text, std::size_t colon ) noexcept
{
    const std::size_t v = text.find_first_not_of( " \t\r", colon + 1 );
    const std::size_t ve = v != std::string_view::npos && text[v] == '"' ? jsonStringEnd( text, v ) : std::string_view::npos;
    return ve != std::string_view::npos ? text.substr( v + 1, ve - v - 1 ) : std::string_view();
}

// A JSON string's text (between its quotes) with its escapes decoded; the raw text itself when it holds none. `buf` keeps a decoded copy.
inline std::string_view jsonDecoded( std::string_view raw, std::string& buf )
{
    if( !raw.contains( '\\' ) )
    {
        return raw;
    }
    const std::string quoted = "\"" + std::string( raw ) + "\"";
    buf = minedjson::unescape( quoted, 0, quoted.size() );
    return buf;
}

// Every key of a JSON object text: its depth (1 = top level), the top-level key it sits under (depth 2 only), its string value
// ("" for any other value) and its line. Keys and values are passed decoded (`"pub\u006cish"` is publish); the line is the text's own.
template<class OnKey>
inline void forEachJsonKey( std::string_view text, OnKey&& onKey )
{
    std::uint32_t line = 1;
    int depth = 0;
    std::string top, keyBuf, valBuf;
    for( std::size_t i = 0; i < text.size(); ++i )
    {
        line += text[i] == '\n' ? 1 : 0;
        depth += jsonDepthStep( text[i] );
        if( text[i] != '"' )
        {
            continue;
        }
        const std::size_t end = jsonStringEnd( text, i );
        if( end == std::string_view::npos )
        {
            return;
        }
        const std::size_t colon = text.find_first_not_of( " \t\r", end + 1 );
        if( colon == std::string_view::npos || text[colon] != ':' )
        {
            i = end; // a value or an array element, not a key
            continue;
        }
        const std::string_view key = jsonDecoded( text.substr( i + 1, end - i - 1 ), keyBuf );
        if( depth == 1 )
        {
            top.assign( key );
        }
        onKey( depth, depth == 2 ? std::string_view( top ) : std::string_view(), key, jsonDecoded( jsonStringValueAfter( text, colon ), valBuf ), line );
        i = end;
    }
}

// The kind of an entry under a package.json top-level object key, or nullopt for an object read no further.
inline std::optional<ManifestKind> packageJsonMemberKind( std::string_view top ) noexcept
{
    static constexpr std::array<std::pair<std::string_view, ManifestKind>, 6> kMembers { {
        { "scripts", ManifestKind::Script },
        { "bin", ManifestKind::Bin },
        { "dependencies", ManifestKind::Dep },
        { "devDependencies", ManifestKind::DevDep },
        { "peerDependencies", ManifestKind::PeerDep },
        { "optionalDependencies", ManifestKind::OptDep },
    } };
    const auto it = std::ranges::find( kMembers, top, &std::pair<std::string_view, ManifestKind>::first );
    return it != kMembers.end() ? std::optional( it->second ) : std::nullopt;
}

// The last `/` segment of a name: npm installs bin `@acme/tool` as `tool`; `@nestjs/microservices` is the microservices package.
inline std::string_view lastSegment( std::string_view n ) noexcept
{
    const std::string_view dir = includerDir( n ); // resolve.h: everything before the last '/'
    return n.substr( dir.size() + ( dir.size() < n.size() && n[dir.size()] == '/' ? 1 : 0 ) );
}

inline void readPackageJson( std::string_view text, std::vector<ManifestEntry>& out )
{
    std::string pkg;
    std::uint32_t mainLine = 0, binLine = 0;
    forEachJsonKey( text, [&]( int depth, std::string_view top, std::string_view key, std::string_view val, std::uint32_t line )
                    {
        if( depth == 1 && key == "name" && !val.empty() )
        {
            pkg = val;
            out.push_back( ManifestEntry { pkg, line, ManifestKind::Package } );
        }
        mainLine = depth == 1 && key == "main" && !val.empty() ? line : mainLine;
        binLine = depth == 1 && key == "bin" && !val.empty() ? line : binLine; // a string bin, named by the package
        const std::optional<ManifestKind> k = depth == 2 ? packageJsonMemberKind( top ) : std::nullopt;
        if( k )
        {
            out.push_back( ManifestEntry { std::string( *k == ManifestKind::Bin ? lastSegment( key ) : key ), line, *k } );
        } } );
    if( !pkg.empty() && mainLine != 0 )
    {
        out.push_back( ManifestEntry { pkg, mainLine, ManifestKind::Main } );
    }
    if( !pkg.empty() && binLine != 0 )
    {
        out.push_back( ManifestEntry { std::string( lastSegment( pkg ) ), binLine, ManifestKind::Bin } );
    }
}

// A TOML table: which keys of it are entries. NameOf: its `name = ".."` key names one entry; Keys: every key is one.
struct TomlTable
{
    enum class Read : std::uint8_t
    {
        None,
        NameOf,
        Keys
    } read = Read::None;
    ManifestKind kind = ManifestKind::Package;
    std::string_view skipKey; // a key of a Keys table that is not an entry (poetry's `python = ".."` constrains the interpreter)
};

// The Cargo dependency tables; the second one's keys are dev-dependencies.
inline constexpr std::array<std::string_view, 3> kCargoDepTables { "dependencies", "dev-dependencies", "build-dependencies" };

// Is h[at] a Cargo dependency table in a scope Cargo reads: top level (`[dependencies]`), `[workspace.dependencies]` or
// `[target.<cfg>.dependencies]`? `[package.metadata.dependencies]` is tool metadata Cargo ignores, not a dependency table.
inline bool cargoDepTableAt( const std::vector<std::string>& h, std::size_t at )
{
    const bool scoped = at == 0 || ( at == 1 && h[0] == "workspace" ) || ( at == 2 && h[0] == "target" );
    return at < h.size() && scoped && std::ranges::contains( kCargoDepTables, h[at] );
}

// A Cargo.toml table header: what its keys are. `[dependencies.serde]` names one dependency on the header line itself (pushed here).
inline TomlTable cargoTable( const std::vector<std::string>& h, bool array, std::uint32_t lineNo, std::vector<ManifestEntry>& out )
{
    using R = TomlTable::Read;
    const bool one = h.size() == 1;
    if( one && !array && ( h[0] == "package" || h[0] == "lib" ) )
    {
        return { R::NameOf, h[0] == "lib" ? ManifestKind::Lib : ManifestKind::Package };
    }
    if( one && array && h[0] == "bin" )
    {
        return { R::NameOf, ManifestKind::Bin };
    }
    if( one && !array && h[0] == "features" )
    {
        return { R::Keys, ManifestKind::Feature };
    }
    if( !h.empty() && !array && cargoDepTableAt( h, h.size() - 1 ) ) // [dependencies], [target.'cfg(..)'.dependencies], [workspace.dependencies]
    {
        return { R::Keys, ( h.back() == kCargoDepTables[1] ? ManifestKind::DevDep : ManifestKind::Dep ) };
    }
    if( h.size() >= 2 && !array && cargoDepTableAt( h, h.size() - 2 ) ) // [dependencies.serde], [workspace.dependencies.serde], ..
    {
        out.push_back( ManifestEntry { h.back(), lineNo, ( h[h.size() - 2] == kCargoDepTables[1] ? ManifestKind::DevDep : ManifestKind::Dep ) } );
    }
    return {};
}

// A pyproject.toml table header: [project] / [tool.poetry] name, optional-dependencies / extras keys, poetry dependency keys.
inline TomlTable pyprojectTable( const std::vector<std::string>& h, bool array, std::uint32_t, std::vector<ManifestEntry>& )
{
    using R = TomlTable::Read;
    const bool poetry = h.size() >= 2 && h[0] == "tool" && h[1] == "poetry";
    if( array )
    {
        return {};
    }
    if( ( h.size() == 1 && h[0] == "project" ) || ( poetry && h.size() == 2 ) )
    {
        return { R::NameOf, ManifestKind::Package };
    }
    if( ( h.size() == 2 && h[0] == "project" && h[1] == "optional-dependencies" ) || ( poetry && h.size() == 3 && h[2] == "extras" ) )
    {
        return { R::Keys, ManifestKind::Extra };
    }
    const bool deps = poetry && ( ( h.size() == 3 && h[2] == "dependencies" ) || ( h.size() == 5 && h[2] == "group" && h[4] == "dependencies" ) ); // groups: Poetry 1.2+
    if( deps )
    {
        return { R::Keys, ManifestKind::Dep, "python" };
    }
    return poetry && h.size() == 3 && h[2] == "dev-dependencies" ? TomlTable { R::Keys, ManifestKind::DevDep, "python" } : TomlTable {};
}

// The index of the quote that closes the string opened at v[open] (`"` takes backslash escapes, `'` does not); v.size() when it never closes.
inline std::size_t tomlQuotedEnd( std::string_view v, std::size_t open ) noexcept
{
    const char quote = v[open];
    std::size_t i = open + 1;
    for( ; i < v.size() && v[i] != quote; ++i )
    {
        i += v[i] == '\\' && quote == '"' ? 1 : 0;
    }
    return std::min( i, v.size() );
}

// How many more `[` than `]` a TOML value text opens, outside quoted strings and past a `#` comment: > 0 when its array continues on
// the next lines.
inline int tomlBracketDelta( std::string_view v ) noexcept
{
    int delta = 0;
    for( std::size_t i = 0; i < v.size() && v[i] != '#'; ++i )
    {
        if( v[i] == '"' || v[i] == '\'' )
        {
            i = tomlQuotedEnd( v, i );
            continue;
        }
        delta += v[i] == '[' ? 1 : v[i] == ']' ? -1
                                               : 0;
    }
    return delta;
}

// The entry a `key = value` line makes in the table being read: a Keys table reads every key (bar its skipKey), a NameOf table its `name`.
inline void addTomlEntry( const TomlTable& table, std::string_view keyText, std::string_view value, std::uint32_t lineNo, std::vector<ManifestEntry>& out )
{
    const std::vector<std::string> key = epdetail::tomlKeyParts( keyText );
    if( key.empty() || key[0].empty() )
    {
        return;
    }
    const std::optional<std::string_view> val = epdetail::tomlStringValue( value );
    if( table.read == TomlTable::Read::Keys && key[0] != table.skipKey )
    {
        out.push_back( ManifestEntry { key[0], lineNo, table.kind } );
    }
    else if( table.read == TomlTable::Read::NameOf && key.size() == 1 && key[0] == "name" && val && !val->empty() )
    {
        out.push_back( ManifestEntry { std::string( *val ), lineNo, table.kind } );
    }
}

// A TOML manifest, line by line: table headers through `tableOf`, then the keys the current table reads. Lines inside a multi-line
// string or a multi-line array are a value, never a key or a table (a poetry constraint list `numpy = [ {version = "^1", python = ".."},
// ..]` holds `version =` lines); a dotted key (`serde.workspace = true`) is an entry by its first part.
template<class TableOf>
inline void readToml( std::string_view text, TableOf&& tableOf, std::vector<ManifestEntry>& out )
{
    TomlTable table;
    std::string_view multiline;
    int arrayDepth = 0; // open `[` of a multi-line array value
    darkflags::forEachLine( text, [&]( std::string_view line, std::uint32_t lineNo )
                            {
        const std::string_view t = trimWs( line );
        if( !multiline.empty() )
        {
            multiline = t.contains( multiline ) ? std::string_view() : multiline;
            return;
        }
        if( arrayDepth > 0 )
        {
            arrayDepth = std::max( 0, arrayDepth + tomlBracketDelta( t ) );
            return;
        }
        if( t.empty() || t.front() == '#' )
        {
            return;
        }
        if( t.front() == '[' )
        {
            bool array = false; // set by tomlHeaderParts: read it only after that call (an argument beside it may be evaluated first: GCC did)
            const std::vector<std::string> header = epdetail::tomlHeaderParts( t, array );
            table = tableOf( header, array, lineNo, out );
            return;
        }
        const std::size_t eq = epdetail::tomlKeyEnd( t );
        if( eq == std::string_view::npos )
        {
            return; // an array element line (`"form",`), never a key
        }
        multiline = epdetail::tomlMultilineOpen( trimWs( t.substr( eq + 1 ) ) );
        arrayDepth = multiline.empty() ? std::max( 0, tomlBracketDelta( t.substr( eq + 1 ) ) ) : 0;
        addTomlEntry( table, t.substr( 0, eq ), t.substr( eq + 1 ), lineNo, out ); } );
}

// setup.cfg: [metadata] name, [options.extras_require] keys (unindented `key = value` lines), [options.entry_points] (epmanifest.h).
inline void readSetupCfgNames( std::string_view text, std::vector<ManifestEntry>& out )
{
    std::string_view section;
    darkflags::forEachLine( text, [&]( std::string_view line, std::uint32_t lineNo )
                            {
        const std::string_view t = trimWs( line );
        if( t.empty() || t.front() == '#' || t.front() == ';' )
        {
            return;
        }
        if( t.front() == '[' )
        {
            section = t;
            return;
        }
        const std::size_t sep = t.find_first_of( "=:" );
        if( line.front() == ' ' || line.front() == '\t' || sep == std::string_view::npos )
        {
            return; // a continuation line holds a value, not a key
        }
        const std::string_view key = trimWs( t.substr( 0, sep ) ), val = trimWs( t.substr( sep + 1 ) );
        if( section == "[metadata]" && key == "name" && !val.empty() )
        {
            out.push_back( ManifestEntry { std::string( val ), lineNo, ManifestKind::Package } );
        }
        else if( section == "[options.extras_require]" && !key.empty() )
        {
            out.push_back( ManifestEntry { std::string( key ), lineNo, ManifestKind::Extra } );
        } } );
}

// A Go module path's name: its last segment, a major-version suffix dropped (`github.com/nats-io/nats.go/v2` → nats.go).
inline std::string_view goModuleName( std::string_view path ) noexcept
{
    std::string_view seg = lastSegment( path );
    if( seg.size() >= 2 && seg[0] == 'v' && std::ranges::all_of( seg.substr( 1 ), []( char c )
                                                                 { return c >= '0' && c <= '9'; } ) )
    {
        path = path.substr( 0, path.rfind( '/' ) == std::string_view::npos ? 0 : path.rfind( '/' ) );
        seg = lastSegment( path );
    }
    return seg;
}

// go.mod: `module P`, `require P v` and every line of a `require ( .. )` block; `// indirect` requirements are not the module's own.
inline void readGoMod( std::string_view text, std::vector<ManifestEntry>& out )
{
    bool inRequire = false;
    darkflags::forEachLine( text, [&]( std::string_view line, std::uint32_t lineNo )
                            {
        std::string_view t = trimWs( line );
        const bool indirect = t.contains( "// indirect" );
        t = trimWs( t.substr( 0, t.find( "//" ) ) );
        if( inRequire && t.starts_with( ')' ) )
        {
            inRequire = false;
            return;
        }
        const bool req = t.starts_with( "require " ), mod = t.starts_with( "module " );
        std::string_view rest = req ? trimWs( t.substr( 8 ) ) : mod ? trimWs( t.substr( 7 ) ) : inRequire ? t : std::string_view();
        if( req && rest == "(" )
        {
            inRequire = true;
            return;
        }
        rest = rest.substr( 0, rest.find_first_of( " \t" ) );
        if( !rest.empty() && !indirect )
        {
            out.push_back( ManifestEntry { std::string( goModuleName( rest ) ), lineNo, mod ? ManifestKind::Module : ManifestKind::Dep } );
        } } );
}

// One CMake call being read: its kind, the line its first argument is on, the argument text so far and the lines it has taken (a call
// may span lines).
struct CMakeCall
{
    ManifestKind kind = ManifestKind::Package;
    std::uint32_t line = 0;
    std::string args;
    std::size_t lines = 0;
};
inline constexpr std::size_t kCMakeMaxCallLines = 16; // CMake call lines read for one call; a longer call still names its target (its first argument), but an IMPORTED / ALIAS past this is not seen

inline constexpr std::array<std::pair<std::string_view, ManifestKind>, 3> kCMakeCommands { {
    { "add_executable", ManifestKind::Executable },
    { "add_library", ManifestKind::Library },
    { "project", ManifestKind::Package },
} };

// The closer of the bracket comment `#[[` / `#[==[` that `t` starts with (`]]` / `]==]`), else "" (a `#` line comment, or no `#`).
// The opener is one byte longer than its closer.
inline std::string cmakeBracketCloser( std::string_view t )
{
    if( !t.starts_with( "#[" ) )
    {
        return {};
    }
    const std::size_t levels = t.find_first_not_of( '=', 2 ); // `#[==[`: the `=` run between the brackets
    if( levels == std::string_view::npos || t[levels] != '[' )
    {
        return {};
    }
    return "]" + std::string( levels - 2, '=' ) + "]";
}

// The first `#` of `t` outside a quoted argument (`"a#b"` holds no comment), or npos.
inline std::size_t cmakeCommentStart( std::string_view t ) noexcept
{
    bool quoted = false;
    for( std::size_t i = 0; i < t.size(); ++i )
    {
        quoted = t[i] == '"' ? !quoted : quoted;
        i += quoted && t[i] == '\\' ? 1 : 0;
        if( !quoted && t[i] == '#' )
        {
            return i;
        }
    }
    return std::string_view::npos;
}

// The code of one CMakeLists.txt line, comments cut: a `#` line comment ends it; a bracket comment, inline or spanning lines (`closer`
// holds the end of one still open), is skipped and the text after its closer is read on (`add_library( #[[note]] core )`).
inline std::string cmakeCodeOf( std::string_view t, std::string& closer )
{
    std::string code;
    while( !t.empty() )
    {
        if( !closer.empty() )
        {
            const std::size_t end = t.find( closer );
            if( end == std::string_view::npos )
            {
                return code; // the comment goes on past this line
            }
            t = t.substr( end + closer.size() );
            closer.clear();
            code += ' '; // a bracket comment separates arguments
            continue;
        }
        const std::size_t hash = cmakeCommentStart( t );
        code += t.substr( 0, hash );
        closer = hash == std::string_view::npos ? std::string() : cmakeBracketCloser( t.substr( hash ) );
        if( closer.empty() )
        {
            return code; // no comment, or a line comment
        }
        t = t.substr( hash + closer.size() + 1 );
    }
    return code;
}

// A finished call as an entry: its first argument names it. `IMPORTED` / `ALIAS` targets are not defined by this project and a `${VAR}`
// name is not a name. A call that ran past kCMakeMaxCallLines before its `)` is read up to there: its name is its first argument.
inline void addCMakeCall( const CMakeCall& call, std::vector<ManifestEntry>& out )
{
    const std::size_t end = std::min( call.args.find( ')' ), call.args.size() );
    std::vector<std::string_view> words;
    for( std::size_t at = 0; at < end; )
    {
        const std::size_t b = call.args.find_first_not_of( " \t\r", at );
        const std::size_t e = std::min( { call.args.find_first_of( " \t\r)", b ), call.args.size() } );
        if( b == std::string::npos || b >= e )
        {
            break;
        }
        words.push_back( std::string_view( call.args ).substr( b, e - b ) );
        at = e;
    }
    const bool foreign = std::ranges::contains( words, std::string_view( "IMPORTED" ) ) || std::ranges::contains( words, std::string_view( "ALIAS" ) );
    if( !words.empty() && !foreign && !words[0].contains( '$' ) )
    {
        out.push_back( ManifestEntry { std::string( words[0] ), call.line, call.kind } );
    }
}

// The call a trimmed line starts (the command in any case, then `(`) with the text after the `(`, or nullopt.
inline std::optional<std::pair<CMakeCall, std::string_view>> cmakeCallStart( std::string_view t )
{
    for( const auto& [cmd, kind] : kCMakeCommands )
    {
        const bool named = t.size() > cmd.size() && std::ranges::equal( t.substr( 0, cmd.size() ), cmd, []( char a, char b )
                                                                       { return lexLowerByte( static_cast<unsigned char>( a ) ) == b; } );
        const std::string_view paren = named ? trimWs( t.substr( cmd.size() ) ) : std::string_view();
        if( paren.starts_with( '(' ) )
        {
            return std::pair { CMakeCall { .kind = kind }, trimWs( paren.substr( 1 ) ) };
        }
    }
    return std::nullopt;
}

// One more line of a call (its arguments, comment stripped); true when the call ends here: its `)` came, or it ran too long.
inline bool takeCMakeLine( CMakeCall& call, std::uint32_t lineNo, std::string_view t )
{
    call.line = call.line == 0 && !t.empty() ? lineNo : call.line; // the name's line, so the printed row shows the name
    call.args += std::string( t ) + " ";
    return call.args.contains( ')' ) || ++call.lines >= kCMakeMaxCallLines;
}

// CMakeLists.txt: add_executable( NAME / add_library( NAME / project( NAME (any case), the call on one line or several; a `${VAR}`
// name, an IMPORTED or ALIAS target, a `#` line comment and a `#[[ .. ]]` bracket comment are not read.
inline void readCMakeLists( std::string_view text, std::vector<ManifestEntry>& out )
{
    std::string closer; // the open bracket comment's end
    std::optional<CMakeCall> call;
    darkflags::forEachLine( text, [&]( std::string_view line, std::uint32_t lineNo )
                            {
        const std::string code = cmakeCodeOf( line, closer );
        std::string_view t = trimWs( code );
        if( t.empty() )
        {
            return;
        }
        if( !call )
        {
            const auto start = cmakeCallStart( t );
            call = start ? std::optional( start->first ) : std::nullopt;
            t = start ? start->second : t;
        }
        if( call && takeCMakeLine( *call, lineNo, t ) )
        {
            addCMakeCall( *call, out );
            call.reset();
        } } );
}

// ── discovery ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
// A manifest under one of these directories belongs to someone else's package or to a test's sample tree.
inline constexpr std::array<std::string_view, 6> kManifestSkipDirs { "node_modules/", "vendor/", "third_party/", "fixtures/", "testdata/", "benchmarks/" };

using ManifestReader = void ( * )( std::string_view, std::vector<ManifestEntry>& );

inline void readCargoToml( std::string_view text, std::vector<ManifestEntry>& out )
{
    readToml( text, cargoTable, out );
}
// The entry points of a Python manifest, read by epmanifest.h's own parser: a console or gui script is an installed command (kind
// bin, named by its key); every other group's entry is kind entry-point, with its group.
inline void addEntryPoints( const std::vector<EpEntry>& eps, std::vector<ManifestEntry>& out )
{
    for( const EpEntry& ep : eps )
    {
        const bool script = ep.group == "console_scripts" || ep.group == "gui_scripts";
        out.push_back( ManifestEntry { ep.name, ep.line, script ? ManifestKind::Bin : ManifestKind::EntryPoint, script ? std::string() : ep.group } );
    }
}

inline void readPyproject( std::string_view text, std::vector<ManifestEntry>& out )
{
    readToml( text, pyprojectTable, out );
    std::vector<EpEntry> eps;
    parsePyprojectEntryPoints( text, eps );
    addEntryPoints( eps, out );
}

inline void readSetupCfg( std::string_view text, std::vector<ManifestEntry>& out )
{
    readSetupCfgNames( text, out );
    std::vector<EpEntry> eps;
    parseSetupCfgEntryPoints( text, eps );
    addEntryPoints( eps, out );
}

// The reader of a manifest file name, or nullptr. `indexed`: the crawl indexes that name (else it is looked for on disk).
struct ManifestFormat
{
    std::string_view name;
    ManifestReader read;
    bool indexed;
};
inline constexpr std::array<ManifestFormat, 6> kManifestFormats { {
    { "package.json", readPackageJson, true },
    { "Cargo.toml", readCargoToml, true },
    { "pyproject.toml", readPyproject, true },
    { "setup.cfg", readSetupCfg, false },
    { "go.mod", readGoMod, false },
    { "CMakeLists.txt", readCMakeLists, false },
} };

inline std::string_view baseName( std::string_view rel ) noexcept
{
    return lastSegment( rel );
}

// The manifests of a tree and how many it found but did not read: unreadable, over kDefaultMaxFileBytes, or a link resolving outside
// the root. `unread` > 0 makes files= a floor (a manifest naming the task may be among them); the DISCLOSE sink counts them.
struct ManifestSet
{
    std::vector<ManifestDoc> docs;
    std::uint32_t unread = 0;
    enum class DisclosureWhy : std::uint8_t
    {
        Unread
    };
    void disclose( DisclosureWhy ) noexcept
    {
        ++unread;
    }
};

// Read one manifest and keep it when it defines any name. Its size is checked on disk before anything is allocated for it.
inline void addManifest( std::string rel, std::uint32_t fileId, const std::string& disk, const ManifestFormat& fmt, ManifestSet& out )
{
    if( std::ranges::any_of( kManifestSkipDirs, [&]( std::string_view seg )
                             { return hasDirSegment( rel, seg ); } ) )
    {
        return; // someone else's package or a test's sample tree
    }
    std::error_code ec;
    const std::uintmax_t bytes = std::filesystem::file_size( disk, ec );
    std::optional<std::string> text = !ec && bytes <= kDefaultMaxFileBytes ? docparse::detail::readRegularFile( fmt.name, disk ) : std::nullopt;
    if( !text || text->size() > kDefaultMaxFileBytes ) // the size again: the file may have grown since the stat
    {
        DISCLOSE( out, ManifestSet::DisclosureWhy::Unread, "manifest_rows: a manifest could not be read or is over the size ceiling: files= is a floor" );
        return;
    }
    ManifestDoc doc { std::move( rel ), fileId, std::move( *text ), {} };
    fmt.read( doc.text, doc.entries );
    if( !doc.entries.empty() )
    {
        out.docs.push_back( std::move( doc ) );
    }
}

// `rel` and every directory above it, nearest first, the root ("") last.
inline void pushAncestorDirs( std::string_view rel, std::vector<std::string_view>& dirs )
{
    for( std::string_view d = includerDir( rel );; d = includerDir( d ) )
    {
        dirs.push_back( d );
        if( d.empty() )
        {
            break;
        }
    }
}

// The manifests no crawl indexes (setup.cfg, go.mod, CMakeLists.txt), by name in each directory: one stat per directory and name. A
// name that is a link is read only when it resolves inside the root (the root's real path is resolved once, at the first link).
inline void readUnindexedManifests( const std::string& rootPrefix, const std::vector<std::string_view>& dirs, ManifestSet& set )
{
    std::optional<std::string> rootReal;
    for( const std::string_view d : dirs )
    {
        for( const ManifestFormat& fmt : kManifestFormats )
        {
            if( fmt.indexed )
            {
                continue;
            }
            const std::string rel = d.empty() ? std::string( fmt.name ) : std::string( d ) + "/" + std::string( fmt.name ), disk = rootPrefix + rel;
            std::error_code ec;
            const std::filesystem::file_status st = std::filesystem::symlink_status( disk, ec );
            const bool link = std::filesystem::is_symlink( st );
            if( link && !rootReal )
            {
                rootReal = canonicalCrawlRoot( rootPrefix );
            }
            if( link && !crawlPathStaysInRoot( disk, *rootReal ) )
            {
                DISCLOSE( set, ManifestSet::DisclosureWhy::Unread, "manifest_rows: a probed manifest is a link out of the root: not read" );
            }
            else if( link ? std::filesystem::is_regular_file( disk, ec ) : std::filesystem::is_regular_file( st ) )
            {
                addManifest( rel, UINT32_MAX, disk, fmt, set );
            }
        }
    }
}

// Every manifest of the tree: the indexed ones from the file list; the others from each directory holding an indexed file, and its
// ancestors, by name (one stat per directory and name). HOISTING: the directories are collected once, sorted and deduplicated.
inline ManifestSet readManifests( const IngestResult& ing )
{
    ManifestSet docs;
    std::vector<std::string_view> dirs;
    std::string rootPrefix; // the disk spelling of the root, joined onto a root-relative path
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view rel = rootRelPath( ing, f ), disk = diskPath( ing, f );
        if( f == 0 && disk.ends_with( rel ) )
        {
            rootPrefix = std::string( disk.substr( 0, disk.size() - rel.size() ) );
        }
        pushAncestorDirs( rel, dirs );
        const auto fmt = std::ranges::find( kManifestFormats, baseName( rel ), &ManifestFormat::name );
        if( fmt != kManifestFormats.end() && fmt->indexed )
        {
            addManifest( std::string( rel ), f, std::string( disk ), *fmt, docs );
        }
    }
    std::ranges::sort( dirs, sortutil::svLess );
    dirs.erase( std::unique( dirs.begin(), dirs.end() ), dirs.end() );
    readUnindexedManifests( rootPrefix, dirs, docs );
    return docs;
}

// ── matching ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
// Task words that name no manifest entry by themselves.
inline constexpr auto kManifestStopWords = std::to_array<std::string_view>( { "the", "and", "for", "with", "new", "add", "create", "write", "register", "implement", "introduce", "define", "like", "that",
                                                                              "this", "which", "into", "from", "its", "own", "how", "what", "where", "why", "when", "doe", "must", "should", "can", "use",
                                                                              "using", "used", "need", "want", "file", "code", "change", "both", "side", "next", "each", "every", "all", "any", "one", "are",
                                                                              "was", "not", "only", "also", "then", "than", "make", "get", "set", "via", "per", "our", "your", "existing", "way", "same",
                                                                              "behind", "there" } );
// A name too generic to anchor (it may still add score as a part).
inline constexpr auto kManifestGenericNames = std::to_array<std::string_view>( { "test", "testing", "example", "demo", "doc", "lib", "src", "main", "index", "app", "util", "common", "core", "type", "build",
                                                                                 "dev", "default", "internal", "api", "cli", "server", "client", "shared", "tool", "script", "config", "base", "helper", "web", "node" } );

// The words of one task token: each run of letters and digits, and the token folded whole when it is hyphenated or dotted.
template<class Add>
inline void splitTaskToken( std::string_view tok, Add&& add )
{
    std::string part, folded;
    for( const char c : tok )
    {
        const bool alnum = ( c >= 'a' && c <= 'z' ) || ( c >= '0' && c <= '9' );
        folded += alnum ? std::string( 1, c ) : std::string();
        part += alnum ? std::string( 1, c ) : std::string();
        if( !alnum && !part.empty() )
        {
            add( std::exchange( part, std::string() ) );
        }
    }
    if( folded != part && !folded.empty() )
    {
        add( folded );
    }
    if( !part.empty() )
    {
        add( part );
    }
}

// The task words a manifest name is compared with: lowercase, singular, split on every non-identifier byte (`built-in` → built, in;
// `@nestjs/common` → nestjs, common) and, for a hyphenated or dotted word, also folded whole (`matched-path` → matchedpath).
// `spelled`: each word as the task spells it (lowercase, not singular), for matched=.
inline std::vector<std::string> manifestTaskWords( std::string_view task, std::vector<std::string>& spelled )
{
    std::vector<std::string> out;
    const auto add = [&]( std::string w )
    {
        std::string one = singular( w );
        if( one.size() >= 3 && !std::ranges::contains( kManifestStopWords, one ) && !std::ranges::contains( out, one ) )
        {
            out.push_back( std::move( one ) );
            spelled.push_back( std::move( w ) );
        }
    };
    for( const std::string& tok : exemplar_detail::taskWords( task ) )
    {
        splitTaskToken( tok, add );
    }
    return out;
}

// A name folded for an exact compare: its last `/` segment, lowercase, every byte but a letter or digit dropped, singular
// (`matched-path` → matchedpath, `nats.go` → natsgo: the task's hyphenated or dotted word folds the same way).
inline std::string foldedName( std::string_view name )
{
    std::string f;
    for( const char c : lastSegment( name ) )
    {
        const char l = char( lexLowerByte( static_cast<unsigned char>( c ) ) );
        if( ( l >= 'a' && l <= 'z' ) || ( l >= '0' && l <= '9' ) )
        {
            f.push_back( l );
        }
    }
    return singular( std::move( f ) );
}

// The parts of a name: its alphanumeric runs, lowercase and singular (`@nats-io/transport-node` → nat, io, transport, node).
inline std::vector<std::string> nameParts( std::string_view name )
{
    std::vector<std::string> parts;
    std::string cur;
    for( std::size_t i = 0; i <= name.size(); ++i )
    {
        const char c = i < name.size() ? char( lexLowerByte( static_cast<unsigned char>( name[i] ) ) ) : ' ';
        if( ( c >= 'a' && c <= 'z' ) || ( c >= '0' && c <= '9' ) )
        {
            cur.push_back( c );
            continue;
        }
        if( cur.size() >= 3 )
        {
            parts.push_back( singular( cur ) );
        }
        cur.clear();
    }
    return parts;
}

// Words that say what kind of manifest entry the task means; a name equal to the repo's is an anchor only beside one of these.
struct ManifestCue
{
    ManifestKind kind;
    std::array<std::string_view, 4> words;
};
inline constexpr std::array<ManifestCue, kManifestKindCount> kManifestCues { {
    { ManifestKind::Package, { "package", "crate", "library", "module" } },
    { ManifestKind::Module, { "module", "package", "", "" } },
    { ManifestKind::Dep, { "dependency", "depend", "dep", "crate" } },
    { ManifestKind::DevDep, { "dependency", "depend", "dep", "dev" } },
    { ManifestKind::PeerDep, { "dependency", "depend", "peer", "dep" } },
    { ManifestKind::OptDep, { "dependency", "depend", "optional", "dep" } },
    { ManifestKind::Script, { "script", "npm", "yarn", "pnpm" } },
    { ManifestKind::Bin, { "binary", "bin", "executable", "command" } },
    { ManifestKind::Main, { "main", "entry", "", "" } },
    { ManifestKind::Lib, { "library", "lib", "crate", "" } },
    { ManifestKind::Feature, { "feature", "flag", "", "" } },
    { ManifestKind::Extra, { "extra", "optional", "feature", "" } },
    { ManifestKind::Executable, { "executable", "binary", "target", "program" } },
    { ManifestKind::Library, { "library", "lib", "target", "" } },
    { ManifestKind::EntryPoint, { "plugin", "entry", "entrypoint", "extension" } },
} };

static_assert( std::ranges::all_of( std::array { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 }, []( int k )
                                    { return kManifestCues[std::size_t( k )].kind == ManifestKind( k ); } ),
               "kManifestCues is indexed by ManifestKind" );

inline bool hasCue( const std::vector<std::string>& words, ManifestKind kind )
{
    const ManifestCue& cue = kManifestCues[std::size_t( kind )];
    return std::ranges::any_of( cue.words, [&]( std::string_view w )
                                { return !w.empty() && std::ranges::contains( words, w ); } );
}

// One matching line of a manifest: the entry, how well it matches (2 exact, 1 part), and whether it alone fires the block.
struct ManifestHit
{
    std::uint32_t entry = 0;
    std::uint8_t strength = 0;
    bool anchor = false;
};

// A manifest's match against the task: its score, anchors, rows and the task words it names.
struct ManifestMatch
{
    std::size_t doc = 0;
    std::size_t score = 0;
    std::size_t anchors = 0;
    bool defines = false; // an anchor is not a dependency: this manifest DEFINES a thing the task names (a package, bin, feature, ..)
    std::vector<ManifestHit> hits; // one per matching entry, best first (see RANK)
    std::vector<std::string> matched;
};

// The task as the matcher reads it: its words, the repo's own name (folded) and which kinds the task names (cues).
struct ManifestTask
{
    std::vector<std::string> words;
    std::vector<std::string> spelled; // the same words as the task spells them
    std::string repoName;
    std::array<bool, kManifestKindTags.size()> cue {};
    bool addNew = false; // the task reads as adding one more X (EXEMPLAR's exemplarTasksOf): it may mean any kind of entry
};

inline ManifestTask manifestTaskOf( const IngestResult& ing, std::string_view task )
{
    ManifestTask t;
    t.words = manifestTaskWords( task, t.spelled );
    std::filesystem::path root = std::filesystem::path( ing.crawlRoot ).lexically_normal();
    std::error_code ec;
    root = root.has_filename() && root.filename() != "." ? root : std::filesystem::absolute( root, ec ).lexically_normal();
    root = root.has_filename() ? root : root.parent_path(); // "/abs/repo/" → "/abs/repo"
    t.repoName = foldedName( root.filename().string() );
    for( std::size_t k = 0; k < t.cue.size(); ++k )
    {
        t.cue[k] = hasCue( t.words, ManifestKind( k ) );
    }
    t.addNew = !exemplarTasksOf( task ).empty();
    return t;
}

// The spellings an entry point's group is compared in: the group folded whole and each of its dot segments (`flake8.extension` →
// flake8extension, flake8, extension), the host the plugin hooks into. A group named after the repo is still an anchor: it is the
// repo's plugin hook, and the entry point fires only beside a plugin / entry-point word anyway. Empty for an entry with no group.
inline std::vector<std::string> groupForms( std::string_view group )
{
    std::vector<std::string> forms;
    if( group.empty() )
    {
        return forms;
    }
    forms.push_back( foldedName( group ) );
    for( const std::string_view segment : splitSegments( group, '.' ) )
    {
        forms.push_back( foldedName( segment ) );
    }
    return forms;
}

// How one entry matches one task word: 2 when the word names it exactly (its folded name, or an entry point's group or one dot segment
// of it), 1 when it is one part of the name, else 0.
inline std::uint8_t entryStrength( std::string_view folded, const std::vector<std::string>& parts, const std::vector<std::string>& group, std::string_view word )
{
    if( folded == word || std::ranges::contains( group, word ) )
    {
        return 2;
    }
    return std::ranges::contains( parts, word ) ? 1 : 0;
}

inline bool isDependencyKind( ManifestKind k ) noexcept
{
    static_assert( ManifestKind::Dep < ManifestKind::DevDep && ManifestKind::DevDep < ManifestKind::PeerDep && ManifestKind::PeerDep < ManifestKind::OptDep && std::to_underlying( ManifestKind::OptDep ) - std::to_underlying( ManifestKind::Dep ) == 3,
                   "the four dependency kinds are consecutive" );
    return k >= ManifestKind::Dep && k <= ManifestKind::OptDep;
}

// An entry the task cannot mean: a script, the main entry or a plugin entry point it does not ask for, or a dependency on the
// repo's own crate or package (it says nothing about the task).
inline bool entryIgnored( const ManifestEntry& en, bool own, const ManifestTask& t ) noexcept
{
    const bool unasked = ( en.kind == ManifestKind::Script || en.kind == ManifestKind::Main || en.kind == ManifestKind::EntryPoint ) && !t.cue[std::size_t( en.kind )];
    return unasked || ( own && isDependencyKind( en.kind ) );
}

// Does a name that matches a task word exactly fire the block? Not the repo's own name, not a generic one (an entry point is named
// freely), and only for a kind the task names or beside an add-a-new task.
inline bool entryAnchors( const ManifestEntry& en, std::string_view folded, bool own, const ManifestTask& t )
{
    return !own && ( t.cue[std::size_t( en.kind )] || t.addNew ) && ( !std::ranges::contains( kManifestGenericNames, folded ) || en.kind == ManifestKind::EntryPoint );
}

// A manifest's score (the best strength per task word, summed), the task words it names, and its hits in print order: anchors
// first, then the stronger match, then line order.
inline void settleMatch( const ManifestDoc& doc, const ManifestTask& t, const std::vector<std::uint8_t>& best, ManifestMatch& m )
{
    for( std::size_t w = 0; w < t.words.size(); ++w )
    {
        m.score += best[w];
        if( best[w] > 0 )
        {
            m.matched.push_back( t.spelled[w] );
        }
    }
    std::ranges::sort( m.hits, [&]( const ManifestHit& a, const ManifestHit& b )
                       {
        if( a.anchor != b.anchor )
        {
            return a.anchor;
        }
        return a.strength != b.strength ? a.strength > b.strength : doc.entries[a.entry].line < doc.entries[b.entry].line; } );
}

// One manifest against the task (see WHEN and RANK). HOISTING: an entry's folded name, parts and group spellings are built once, not per task word.
inline ManifestMatch matchManifest( const ManifestDoc& doc, std::size_t di, const ManifestTask& t )
{
    ManifestMatch m { .doc = di };
    std::vector<std::uint8_t> best( t.words.size(), 0 );
    for( std::uint32_t e = 0; e < doc.entries.size(); ++e )
    {
        const ManifestEntry& en = doc.entries[e];
        const std::string folded = foldedName( en.name );
        const bool own = folded == t.repoName; // the repo's own name: the package so named adds score, never fires the block (a kind word does not change that)
        if( entryIgnored( en, own, t ) )
        {
            continue;
        }
        const std::vector<std::string> parts = nameParts( en.name ), group = groupForms( en.group );
        ManifestHit hit { .entry = e };
        for( std::size_t w = 0; w < t.words.size(); ++w )
        {
            const std::uint8_t s = entryStrength( folded, parts, group, t.words[w] );
            hit.strength = std::max( hit.strength, s );
            best[w] = std::max( best[w], s );
        }
        hit.anchor = hit.strength == 2 && entryAnchors( en, folded, own, t );
        m.anchors += hit.anchor ? 1 : 0;
        m.defines = m.defines || ( hit.anchor && !isDependencyKind( en.kind ) );
        if( hit.strength > 0 )
        {
            m.hits.push_back( hit );
        }
    }
    settleMatch( doc, t, best, m );
    return m;
}

// The manifests that hold an anchor, best first (see RANK).
inline std::vector<ManifestMatch> rankManifests( const std::vector<ManifestDoc>& docs, const ManifestTask& t )
{
    std::vector<ManifestMatch> out;
    for( std::size_t d = 0; d < docs.size(); ++d )
    {
        ManifestMatch m = matchManifest( docs[d], d, t );
        if( m.anchors > 0 )
        {
            out.push_back( std::move( m ) );
        }
    }
    const auto depth = [&]( const ManifestMatch& m )
    { return std::ranges::count( docs[m.doc].rel, '/' ); };
    std::ranges::sort( out, [&]( const ManifestMatch& a, const ManifestMatch& b )
                       {
        if( a.score != b.score )
        {
            return a.score > b.score;
        }
        if( a.anchors != b.anchors )
        {
            return a.anchors > b.anchors;
        }
        return depth( a ) != depth( b ) ? depth( a ) < depth( b ) : sortutil::svLess( docs[a.doc].rel, docs[b.doc].rel ); } );
    // A manifest that only depends on what the task names must not lead when one defines it: the best definer comes first, the rest keep their order.
    const auto definer = std::ranges::find_if( out, []( const ManifestMatch& m )
                                               { return m.defines; } );
    if( definer != out.end() )
    {
        std::rotate( out.begin(), definer, definer + 1 );
    }
    return out;
}

// The text of line `line` (1-based) of `text`, trimmed.
inline std::string_view lineOf( std::string_view text, std::uint32_t line ) noexcept
{
    std::string_view found;
    darkflags::forEachLine( text, [&]( std::string_view l, std::uint32_t n ) // the same line numbering every reader above used
                            { found = n == line ? trimWs( l ) : found; } );
    return found;
}

// The family a manifest's feature table is (its cargo features or Python extras, `default` and `_`-private ones left out), when an
// anchor of the match is one of them. An unindexed manifest (setup.cfg) has the UINT32_MAX file id: a registry family's touch scan only
// compares member file ids with the indexed files it scans, so no file is skipped for it and none is dereferenced.
inline std::optional<ExemplarFamily> featureFamily( const ManifestDoc& doc, const ManifestMatch& m )
{
    const auto isFeature = []( ManifestKind k )
    { return k == ManifestKind::Feature || k == ManifestKind::Extra; };
    const bool anchored = std::ranges::any_of( m.hits, [&]( const ManifestHit& h )
                                               { return h.anchor && isFeature( doc.entries[h.entry].kind ); } );
    if( !anchored )
    {
        return std::nullopt;
    }
    ExemplarFamily fam { .rule = ExemplarRule::Registry, .key = "features" };
    for( const ManifestEntry& en : doc.entries )
    {
        if( isFeature( en.kind ) && en.name != "default" && !en.name.starts_with( '_' ) )
        {
            fam.members.push_back( ExemplarMember { en.name, doc.fileId, en.line, 0, {} } );
        }
    }
    return fam.members.size() >= kExemplarFamilyMin ? std::optional( std::move( fam ) ) : std::nullopt;
}

// A `#[cfg(feature = "x")]` line USES a feature (it gates an item); it is not where the feature is defined or documented.
inline bool cfgUseLine( std::string_view line ) noexcept
{
    const std::string_view t = trimWs( line );
    return ( t.starts_with( '#' ) && t.find( "cfg" ) < 4 ) || t.contains( "cfg!(" ); // `#[cfg(`, `#![cfg(`, `#[cfg_attr(`, `cfg!(`
}

// Does `line` hold `name` as a whole word (no letter, digit, `_` or `-` beside it)?
inline bool holdsWord( std::string_view line, std::string_view name ) noexcept
{
    const auto wordByte = []( char c )
    { return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_' || c == '-'; };
    for( std::size_t at = line.find( name ); at != std::string_view::npos; at = line.find( name, at + 1 ) )
    {
        const bool before = at > 0 && wordByte( line[at - 1] ), after = at + name.size() < line.size() && wordByte( line[at + name.size()] );
        if( !before && !after )
        {
            return true;
        }
    }
    return false;
}

// A feature's spellings in a doc line: bare, backticked and quoted.
using FeatureForms = std::array<std::string, 3>;

// The first line of `txt` that names one of the features and is no cfg use: a line naming it in backticks or quotes beats a bare mention.
// {0, ""} when no line does.
inline std::pair<std::uint32_t, std::string> definingLine( std::string_view txt, const std::vector<FeatureForms>& forms )
{
    std::pair<std::uint32_t, std::string> best { 0, {} };
    int bestRank = 2;
    darkflags::forEachLine( txt, [&]( std::string_view line, std::uint32_t n )
                            {
        for( const auto& [bare, ticked, quoted] : forms )
        {
            const int rank = line.contains( ticked ) || line.contains( quoted ) ? 0 : holdsWord( line, bare ) ? 1
                                                                                                             : 2;
            if( rank < bestRank && !cfgUseLine( line ) )
            {
                bestRank = rank;
                best = { n, std::string( trimWs( line ) ) };
            }
        } } );
    return best;
}

// A touch row whose line is a `#[cfg(feature = ..)]` use gets the first line of its file that names an anchored feature and is no cfg use,
// the table row or doc line that defines it (axum's `//! `multipart` | ..` feature table, not a `#[cfg(feature = "form")]` beside a module).
// Only the printed rows are read; no other line is touched.
inline void retargetCfgTouchLines( const IngestResult& ing, const std::vector<std::string_view>& features, std::vector<ExemplarTouch>& touch )
{
    std::vector<FeatureForms> forms; // HOISTING: per feature, its spellings, built once
    for( const std::string_view f : features )
    {
        forms.push_back( { std::string( f ), "`" + std::string( f ) + "`", "\"" + std::string( f ) + "\"" } );
    }
    for( std::size_t i = 0; i < touch.size() && i < kExemplarTouchRows; ++i )
    {
        const std::optional<std::string> txt = cfgUseLine( touch[i].text ) ? docparse::detail::readWholeFile( diskPath( ing, touch[i].fileId ) ) : std::nullopt;
        const auto [line, text] = txt ? definingLine( *txt, forms ) : std::pair<std::uint32_t, std::string>();
        touch[i].line = line != 0 ? line : touch[i].line;
        touch[i].text = line != 0 ? text : touch[i].text;
    }
}
} // namespace manifest_detail

inline constexpr std::string_view kForManifestRowsLegend =
    "<!-- ripwire for manifest_rows: the task names a package, dependency, script, binary, build target or cargo feature that a manifest "
    "defines (an exact name: its last / segment, letters and digits only, compared lowercase and singular); these are the manifests' DEFINING LINES, read off the manifest text, a "
    "lead to verify, not a guarantee that each must change. Read: package.json (name, main, bin, scripts, dependencies, devDependencies, "
    "peerDependencies, optionalDependencies), Cargo.toml ([package] / [lib] / [[bin]] name, [features], dependency tables), pyproject.toml "
    "([project] / [tool.poetry] name, optional-dependencies, extras, poetry dependencies and groups without the python key, entry points and scripts), setup.cfg ([metadata] name, "
    "extras_require, entry_points), "
    "go.mod (module, require; indirect ones skipped), CMakeLists.txt (add_executable, add_library, project; a call may span lines; IMPORTED and ALIAS targets and comments skipped); not read: pyproject dependency "
    "arrays, setup.py, Makefile, meson and Bazel files, vendored, node_modules, fixtures and testdata trees. A name equal to the repo's, a "
    "generic name (core, common, test, ..), a script the task does not call a script, or a plugin entry point the task does not call a "
    "plugin, entry point or extension does not fire it; nor does a dependency, feature or other entry the task neither calls by its kind (dependency, feature, package, binary, ..) nor adds as a new X; an entry point's group (pydantic, flake8.extension) matches by any dot segment, and may be the repo's own name. files= the manifests that name a "
    "task word exactly, shown= and capped=\"1\" when fewer are printed, floor=\"1\" unread=K when K manifests found could not be read, are over 4 MiB or are a link out of the repo (files= then counts only the others), best first (2 per task word named exactly, 1 per word that is one "
    "part of a name; when the first only depends on a thing the task names, the best manifest that defines one moves first). <mf> p= the manifest, matched= the task words its names hold, rows= its matching lines, shown= and capped=\"1\" when "
    "fewer are printed. <r> l= the line, kind= what it defines (package, module, dep, dev-dep, peer-dep, opt-dep, script, bin, main, lib, "
    "feature, extra, executable, library, entry-point; a console or gui script is a bin), group= the entry point's group, its text that line, cut=\"1\" when cut to 120 bytes. <feature_touch> (under a manifest whose "
    "match is a feature or extra) n= its features (default and _-private ones left out); <touch_list> the files outside the manifest that "
    "mention at least half of them, where a new feature is listed or gated: total= such files, shown= and capped=\"1\" when fewer rows are "
    "printed; floor=\"1\" unread=K when K listing files could not be read or are over 4 MiB (total= then counts only the others); "
    "<touch> p=file:line the line to copy, share=named/of the distinct feature names it mentions, cut=\"1\" when cut to 120 bytes; "
    "test, docs, vendored, generated, frozen and baseline files are not read. The answer above is unchanged, and these bytes are not in "
    "est_tokens -->";
// The --legend=compact posture (the CLI default); the long text rides --legend=full and the MCP tool. Both define every attribute printed.
inline constexpr std::string_view kForManifestRowsCompactLegend =
    "<!-- ripwire for manifest_rows: manifest lines defining a package, dependency, script, binary, target, feature or plugin entry point the task names "
    "exactly (package.json, Cargo.toml, pyproject.toml, setup.cfg, go.mod, CMakeLists.txt; the repo's own name (an entry point's group may be it), generic names, "
    "un-asked scripts or plugin entry points and entries the task neither names by their kind nor adds as a new X never fire it); leads, not a guarantee; not in est_tokens. files= manifests naming a task word (floor=\"1\" unread=K: K manifests unreadable, over 4 MiB or links out of the repo, files= is a floor); <mf> p= manifest, "
    "matched= task words its names hold, rows= matching lines; <r> l= line, kind= what it defines, group= an entry point's group, cut=\"1\": text cut to 120 bytes; "
    "shown=/capped=\"1\": rows cut. <feature_touch> n= the manifest's features; <touch_list> total= files naming at least half of "
    "them (tests, docs, vendored, generated unread); floor=\"1\" unread=K: K files unreadable or over 4 MiB, total= is a floor; <touch> p= the line, share=named/of distinct feature names, cut=\"1\": cut. -->";
static_assert( kForManifestRowsLegend.find( "--", 4 ) == kForManifestRowsLegend.size() - 3 && kForManifestRowsCompactLegend.find( "--", 4 ) == kForManifestRowsCompactLegend.size() - 3,
               "the only double hyphen in a legend comment is its closing: one inside is not well-formed XML" );

namespace manifest_detail
{
// One <r> row: the line, the kind it defines, its text (cut at kManifestLineMax bytes, never inside a UTF-8 sequence).
inline std::string manifestRowXml( const ManifestDoc& doc, const ManifestEntry& en, std::vector<char>& esc )
{
    const std::string_view text = lineOf( doc.text, en.line );
    std::size_t keep = std::min( text.size(), kManifestLineMax );
    while( keep > 0 && keep < text.size() && ( static_cast<unsigned char>( text[keep] ) & 0xC0 ) == 0x80 )
    {
        --keep;
    }
    std::string out = "<r l=\"" + std::to_string( en.line ) + "\" kind=\"" + std::string( kManifestKindTags[std::size_t( en.kind )] ) + "\"";
    out += en.group.empty() ? std::string() : " group=\"" + std::string( escapeXml( en.group, esc ) ) + "\"";
    out += keep < text.size() ? " cut=\"1\">" : ">";
    return out + std::string( escapeXml( text.substr( 0, keep ), esc ) ) + "</r>";
}

// One <mf> element: the manifest, the task words it names, its best rows and, for a feature match, the feature touch list.
inline std::string manifestFileXml( const IngestResult& ing, const ManifestDoc& doc, const ManifestMatch& m )
{
    std::vector<char> esc;
    std::string words;
    for( const std::string& w : m.matched )
    {
        words += ( words.empty() ? "" : " " ) + w;
    }
    std::string out = "<mf p=\"" + std::string( escapeXml( doc.rel, esc ) ) + "\" matched=\"" + std::string( escapeXml( words, esc ) ) + "\" rows=\"" + std::to_string( m.hits.size() ) + "\"";
    out += m.hits.size() > kManifestRowsPerFile ? " shown=\"" + std::to_string( kManifestRowsPerFile ) + "\" capped=\"1\">" : std::string( ">" ); // CAP-DISCLOSE
    for( std::size_t i = 0; i < m.hits.size() && i < kManifestRowsPerFile; ++i )
    {
        out += manifestRowXml( doc, doc.entries[m.hits[i].entry], esc );
    }
    if( const std::optional<ExemplarFamily> fam = featureFamily( doc, m ) )
    {
        ExemplarTouchList touch = exemplarTouchList( ing, *fam ); // rows + unread (a floor when a listing file could not be read)
        std::vector<std::string_view> anchored; // the features the task names: the lines that define or document them
        for( const ManifestHit& h : m.hits )
        {
            const ManifestEntry& en = doc.entries[h.entry];
            if( h.anchor && ( en.kind == ManifestKind::Feature || en.kind == ManifestKind::Extra ) )
            {
                anchored.push_back( en.name );
            }
        }
        retargetCfgTouchLines( ing, anchored, touch.rows );
        out += "<feature_touch n=\"" + std::to_string( fam->members.size() ) + "\">" + touchListXml( ing, touch ) + "</feature_touch>";
    }
    return out + "</mf>";
}
} // namespace manifest_detail

// The <manifest_rows> block of this task, or "" (see WHEN above). `held`: a token budget is set; the block is named, not printed.
// `compactLegend`: the --legend=compact posture (the CLI default) prints the short legend; the MCP tool and --legend=full the long one.
inline std::string renderForManifestRows( const IngestResult& ing, std::string_view task, bool held = false, bool compactLegend = false )
{
    using namespace manifest_detail;
    if( !ing.realPaths.empty() || task.empty() )
    {
        return {}; // a multi-root run: one repo's name and root are not the run's
    }
    const ManifestTask t = manifestTaskOf( ing, task );
    if( t.words.empty() )
    {
        return {};
    }
    const ManifestSet set = readManifests( ing );
    const std::vector<ManifestDoc>& docs = set.docs;
    const std::vector<ManifestMatch> ranked = rankManifests( docs, t );
    if( ranked.empty() )
    {
        return {};
    }
    const std::string floor = set.unread > 0 ? " floor=\"1\" unread=\"" + std::to_string( set.unread ) + "\"" : std::string(); // DISCLOSE: files= is a floor
    if( held )
    {
        return "<!-- ripwire for manifest_rows: held=\"budget\": a token budget is set, so the manifest lines the task names are not printed; "
               "files= the manifests that name a task word exactly" +
               std::string( floor.empty() ? "" : " (floor=\"1\" unread=K: K manifests could not be read, files= counts only the others)" ) +
               "; the same call without the token budget prints them; the answer above is unchanged -->"
               "<manifest_rows files=\"" +
               std::to_string( ranked.size() ) + "\"" + floor + " held=\"budget\"/>";
    }
    std::string out( compactLegend ? kForManifestRowsCompactLegend : kForManifestRowsLegend );
    out += "<manifest_rows files=\"" + std::to_string( ranked.size() ) + "\"" + floor;
    out += ranked.size() > kManifestFileRows ? " shown=\"" + std::to_string( kManifestFileRows ) + "\" capped=\"1\">" : std::string( ">" ); // CAP-DISCLOSE
    for( std::size_t i = 0; i < ranked.size() && i < kManifestFileRows; ++i )
    {
        out += manifestFileXml( ing, docs[ranked[i].doc], ranked[i] );
    }
    return out + "</manifest_rows>";
}
} // namespace rw
