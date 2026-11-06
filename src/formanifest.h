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
#include "darkflags.h" // forEachLine
#include "docparse.h" // detail::readRegularFile
#include "epmanifest.h" // epdetail TOML helpers: tomlHeaderParts, tomlKeyEnd, tomlKeyParts, tomlStringValue, tomlMultilineOpen
#include "exemplarfamily.h" // exemplar_detail::taskWords / singular; exemplarTouchList / touchListXml (the E3a co-mention scan)
#include "filter.h" // hasDirSegment
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
inline constexpr std::array<std::string_view, 15> kManifestKindTags { "package", "module", "dep", "dev-dep", "peer-dep", "opt-dep", "script",
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
// Every key of a JSON object text: its depth (1 = top level), the top-level key it sits under (depth 2 only), its string value
// ("" for any other value) and its line.
template<class OnKey>
inline void forEachJsonKey( std::string_view text, OnKey&& onKey )
{
    std::uint32_t line = 1;
    int depth = 0;
    std::string_view top;
    for( std::size_t i = 0; i < text.size(); ++i )
    {
        const char c = text[i];
        line += c == '\n' ? 1 : 0;
        depth += ( c == '{' || c == '[' ) ? 1 : ( c == '}' || c == ']' ) ? -1
                                                                         : 0;
        if( c != '"' )
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
        const std::string_view key = text.substr( i + 1, end - i - 1 );
        top = depth == 1 ? key : top;
        const std::size_t v = text.find_first_not_of( " \t\r", colon + 1 );
        const std::size_t ve = v != std::string_view::npos && text[v] == '"' ? jsonStringEnd( text, v ) : std::string_view::npos;
        onKey( depth, depth == 2 ? top : std::string_view(), key, ve != std::string_view::npos ? text.substr( v + 1, ve - v - 1 ) : std::string_view(), line );
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
    if( !h.empty() && !array && std::ranges::contains( kCargoDepTables, h.back() ) ) // [dependencies], [target.'cfg(..)'.dependencies], [workspace.dependencies]
    {
        return { R::Keys, ( h.back() == kCargoDepTables[1] ? ManifestKind::DevDep : ManifestKind::Dep ) };
    }
    if( h.size() >= 2 && !array && std::ranges::contains( kCargoDepTables, h[h.size() - 2] ) )
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

// How many more `[` than `]` a TOML value text opens, outside quoted strings and past a `#` comment: > 0 when its array continues on
// the next lines.
inline int tomlBracketDelta( std::string_view v ) noexcept
{
    int delta = 0;
    char quote = '\0';
    for( std::size_t i = 0; i < v.size(); ++i )
    {
        const char c = v[i];
        if( quote != '\0' )
        {
            i += c == '\\' && quote == '"' ? 1 : 0;
            quote = c == quote ? '\0' : quote;
            continue;
        }
        if( c == '#' )
        {
            break;
        }
        quote = c == '"' || c == '\'' ? c : '\0';
        delta += c == '[' ? 1 : c == ']' ? -1
                                          : 0;
    }
    return delta;
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
            bool array = false;
            table = tableOf( epdetail::tomlHeaderParts( t, array ), array, lineNo, out );
            return;
        }
        const std::size_t eq = epdetail::tomlKeyEnd( t );
        if( eq == std::string_view::npos )
        {
            return; // an array element line (`"form",`), never a key
        }
        multiline = epdetail::tomlMultilineOpen( trimWs( t.substr( eq + 1 ) ) );
        arrayDepth = multiline.empty() ? std::max( 0, tomlBracketDelta( t.substr( eq + 1 ) ) ) : 0;
        const std::vector<std::string> key = epdetail::tomlKeyParts( t.substr( 0, eq ) );
        if( key.empty() || key[0].empty() )
        {
            return;
        }
        const std::optional<std::string_view> val = epdetail::tomlStringValue( t.substr( eq + 1 ) );
        if( table.read == TomlTable::Read::Keys && key[0] != table.skipKey )
        {
            out.push_back( ManifestEntry { key[0], lineNo, table.kind } );
        }
        else if( table.read == TomlTable::Read::NameOf && key.size() == 1 && key[0] == "name" && val && !val->empty() )
        {
            out.push_back( ManifestEntry { std::string( *val ), lineNo, table.kind } );
        } } );
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

// One CMake call being read: its kind, the line its first argument is on and the argument text so far (a call may span lines).
struct CMakeCall
{
    ManifestKind kind = ManifestKind::Package;
    std::uint32_t line = 0;
    std::string args;
};
inline constexpr std::size_t kCMakeCallLines = 16; // a call longer than this is not read (its `)` is missing or far away)

// The closer of a bracket comment `#[[` / `#[==[` that starts the trimmed line `t` and is still open at its end, else "".
inline std::string cmakeBracketCommentOpen( std::string_view t )
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
    const std::string closer = "]" + std::string( levels - 2, '=' ) + "]";
    return t.find( closer, levels + 1 ) == std::string_view::npos ? closer : std::string();
}

// A finished call as an entry: its first argument names it. `IMPORTED` / `ALIAS` targets are not defined by this project and a
// `${VAR}` name is not a name.
inline void addCMakeCall( const CMakeCall& call, std::vector<ManifestEntry>& out )
{
    const std::size_t end = call.args.find( ')' );
    std::vector<std::string_view> words;
    for( std::size_t at = 0; at < std::min( end, call.args.size() ); )
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

// CMakeLists.txt: add_executable( NAME / add_library( NAME / project( NAME (any case), the call on one line or several; a `${VAR}`
// name, an IMPORTED or ALIAS target, a `#` line comment and a `#[[ .. ]]` bracket comment are not read.
inline void readCMakeLists( std::string_view text, std::vector<ManifestEntry>& out )
{
    static constexpr std::array<std::pair<std::string_view, ManifestKind>, 3> kCommands { {
        { "add_executable", ManifestKind::Executable },
        { "add_library", ManifestKind::Library },
        { "project", ManifestKind::Package },
    } };
    std::string closer; // the open bracket comment's end
    std::optional<CMakeCall> call;
    std::size_t callLines = 0;
    darkflags::forEachLine( text, [&]( std::string_view line, std::uint32_t lineNo )
                            {
        std::string_view t = trimWs( line );
        if( !closer.empty() )
        {
            closer = t.contains( closer ) ? std::string() : closer;
            return;
        }
        closer = cmakeBracketCommentOpen( t );
        t = trimWs( t.substr( 0, t.find( '#' ) ) );
        if( t.empty() )
        {
            return;
        }
        if( !call )
        {
            for( const auto& [cmd, kind] : kCommands )
            {
                if( t.size() > cmd.size() && std::ranges::equal( t.substr( 0, cmd.size() ), cmd, []( char a, char b )
                                                                 { return lexLowerByte( static_cast<unsigned char>( a ) ) == b; } ) &&
                    trimWs( t.substr( cmd.size() ) ).starts_with( '(' ) )
                {
                    call = CMakeCall { kind, 0, {} };
                    callLines = 0;
                    t = trimWs( trimWs( t.substr( cmd.size() ) ).substr( 1 ) );
                    break;
                }
            }
        }
        if( !call )
        {
            return;
        }
        call->line = call->line == 0 && !t.empty() ? lineNo : call->line; // the name's line, so the printed row shows the name
        call->args += std::string( t ) + " ";
        if( call->args.contains( ')' ) || ++callLines >= kCMakeCallLines )
        {
            if( call->args.contains( ')' ) )
            {
                addCMakeCall( *call, out );
            }
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

// Read one manifest and keep it when it defines any name.
inline void addManifest( std::string rel, std::uint32_t fileId, const std::string& disk, const ManifestFormat& fmt, std::vector<ManifestDoc>& out )
{
    std::optional<std::string> text = docparse::detail::readRegularFile( fmt.name, disk );
    if( !text || text->size() > kDefaultMaxFileBytes )
    {
        return;
    }
    ManifestDoc doc { std::move( rel ), fileId, std::move( *text ), {} };
    fmt.read( doc.text, doc.entries );
    if( !doc.entries.empty() )
    {
        out.push_back( std::move( doc ) );
    }
}

// Every manifest of the tree: the indexed ones from the file list; the others from each directory holding an indexed file, and its
// ancestors, by name (one stat per directory and name). HOISTING: the directories are collected once, sorted and deduplicated.
inline std::vector<ManifestDoc> readManifests( const IngestResult& ing )
{
    std::vector<ManifestDoc> docs;
    std::vector<std::string_view> dirs;
    std::string rootPrefix; // the disk spelling of the root, joined onto a root-relative path
    const auto skipped = []( std::string_view rel )
    {
        for( const std::string_view seg : kManifestSkipDirs )
        {
            if( hasDirSegment( rel, seg ) )
            {
                return true;
            }
        }
        return false;
    };
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view rel = rootRelPath( ing, f ), disk = diskPath( ing, f );
        if( f == 0 && disk.ends_with( rel ) )
        {
            rootPrefix = std::string( disk.substr( 0, disk.size() - rel.size() ) );
        }
        for( std::string_view d = includerDir( rel );; d = includerDir( d ) )
        {
            dirs.push_back( d );
            if( d.empty() )
            {
                break;
            }
        }
        const auto fmt = std::ranges::find( kManifestFormats, baseName( rel ), &ManifestFormat::name );
        if( fmt != kManifestFormats.end() && fmt->indexed && !skipped( rel ) )
        {
            addManifest( std::string( rel ), f, std::string( disk ), *fmt, docs );
        }
    }
    std::ranges::sort( dirs, sortutil::svLess );
    dirs.erase( std::unique( dirs.begin(), dirs.end() ), dirs.end() );
    for( const std::string_view d : dirs )
    {
        for( const ManifestFormat& fmt : kManifestFormats )
        {
            const std::string rel = d.empty() ? std::string( fmt.name ) : std::string( d ) + "/" + std::string( fmt.name );
            std::error_code ec;
            if( !fmt.indexed && !skipped( rel ) && std::filesystem::is_regular_file( rootPrefix + rel, ec ) )
            {
                addManifest( rel, UINT32_MAX, rootPrefix + rel, fmt, docs );
            }
        }
    }
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
inline constexpr std::array<ManifestCue, 15> kManifestCues { {
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

// How one entry matches one task word: 2 when the word names it exactly, 1 when it is one part of it, else 0.
inline std::uint8_t entryStrength( std::string_view folded, const std::vector<std::string>& parts, std::string_view word )
{
    return folded == word ? 2 : std::ranges::contains( parts, word ) ? 1
                                                                     : 0;
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
    for( std::size_t at = 0; at <= group.size(); )
    {
        const std::size_t dot = std::min( group.find( '.', at ), group.size() );
        forms.push_back( foldedName( group.substr( at, dot - at ) ) );
        at = dot + 1;
    }
    return forms;
}

// How an entry point's group matches one task word: 2 when the word names the group or one of its dot segments, else 0.
inline std::uint8_t groupStrength( const std::vector<std::string>& forms, std::string_view word )
{
    return std::ranges::contains( forms, word ) ? 2 : 0;
}

// One manifest against the task (see WHEN and RANK). HOISTING: an entry's folded name, parts and group spellings are built once, not per task word.
inline ManifestMatch matchManifest( const ManifestDoc& doc, std::size_t di, const ManifestTask& t )
{
    ManifestMatch m { .doc = di };
    std::vector<std::uint8_t> best( t.words.size(), 0 );
    for( std::uint32_t e = 0; e < doc.entries.size(); ++e )
    {
        const ManifestEntry& en = doc.entries[e];
        const std::size_t k = std::size_t( en.kind );
        const std::string folded = foldedName( en.name );
        if( ( en.kind == ManifestKind::Script || en.kind == ManifestKind::Main || en.kind == ManifestKind::EntryPoint ) && !t.cue[k] )
        {
            continue; // a script, the main entry or a plugin entry point the task does not ask for
        }
        const bool own = folded == t.repoName; // the repo's own name: the package so named adds score, never fires the block (a kind word does not change that)
        const bool dep = en.kind == ManifestKind::Dep || en.kind == ManifestKind::DevDep || en.kind == ManifestKind::PeerDep || en.kind == ManifestKind::OptDep;
        if( own && dep )
        {
            continue; // a dependency on the repo's own crate or package says nothing about the task
        }
        const std::vector<std::string> parts = nameParts( en.name ), group = groupForms( en.group );
        ManifestHit hit { .entry = e };
        for( std::size_t w = 0; w < t.words.size(); ++w )
        {
            const std::uint8_t s = std::max( entryStrength( folded, parts, t.words[w] ), groupStrength( group, t.words[w] ) );
            hit.strength = std::max( hit.strength, s );
            best[w] = std::max( best[w], s );
        }
        hit.anchor = hit.strength == 2 && !own && ( t.cue[k] || t.addNew ) && ( !std::ranges::contains( kManifestGenericNames, folded ) || en.kind == ManifestKind::EntryPoint );
        m.anchors += hit.anchor ? 1 : 0;
        m.defines = m.defines || ( hit.anchor && !dep );
        if( hit.strength > 0 )
        {
            m.hits.push_back( hit );
        }
    }
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
// anchor of the match is one of them and the manifest is an indexed file (the touch list skips the members' own file by id).
inline std::optional<ExemplarFamily> featureFamily( const ManifestDoc& doc, const ManifestMatch& m )
{
    const auto isFeature = []( ManifestKind k )
    { return k == ManifestKind::Feature || k == ManifestKind::Extra; };
    const bool anchored = std::ranges::any_of( m.hits, [&]( const ManifestHit& h )
                                               { return h.anchor && isFeature( doc.entries[h.entry].kind ); } );
    if( !anchored || doc.fileId == UINT32_MAX )
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
    return t.starts_with( "#[cfg" ) || t.starts_with( "#![cfg" ) || t.contains( "cfg!(" );
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

// A touch row whose line is a `#[cfg(feature = ..)]` use gets the first line of its file that names an anchored feature and is no cfg use,
// the table row or doc line that defines it (axum's `//! `multipart` | ..` feature table, not a `#[cfg(feature = "form")]` beside a module).
// A line that names the feature in backticks or quotes beats a bare mention. Only the printed rows are read; no other line is touched.
inline void retargetCfgTouchLines( const IngestResult& ing, const std::vector<std::string_view>& features, std::vector<ExemplarTouch>& touch )
{
    std::vector<std::array<std::string, 3>> forms; // HOISTING: per feature, its bare, backticked and quoted spellings, built once
    for( const std::string_view f : features )
    {
        forms.push_back( { std::string( f ), "`" + std::string( f ) + "`", "\"" + std::string( f ) + "\"" } );
    }
    for( std::size_t i = 0; i < touch.size() && i < kExemplarTouchRows; ++i )
    {
        if( !cfgUseLine( touch[i].text ) )
        {
            continue;
        }
        const std::optional<std::string> txt = docparse::detail::readWholeFile( diskPath( ing, touch[i].fileId ) );
        if( !txt )
        {
            continue;
        }
        int bestRank = 2;
        darkflags::forEachLine( *txt, [&]( std::string_view line, std::uint32_t n )
                                {
            for( const auto& [bare, ticked, quoted] : forms )
            {
                const int rank = line.contains( ticked ) || line.contains( quoted ) ? 0 : holdsWord( line, bare ) ? 1
                                                                                                                 : 2;
                if( rank < bestRank && !cfgUseLine( line ) )
                {
                    bestRank = rank;
                    touch[i].line = n;
                    touch[i].text = std::string( trimWs( line ) );
                }
            } } );
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
    "task word exactly, shown= and capped=\"1\" when fewer are printed, best first (2 per task word named exactly, 1 per word that is one "
    "part of a name; when the first only depends on a thing the task names, the best manifest that defines one moves first). <mf> p= the manifest, matched= the task words its names hold, rows= its matching lines, shown= and capped=\"1\" when "
    "fewer are printed. <r> l= the line, kind= what it defines (package, module, dep, dev-dep, peer-dep, opt-dep, script, bin, main, lib, "
    "feature, extra, executable, library, entry-point; a console or gui script is a bin), group= the entry point's group, its text that line, cut=\"1\" when cut to 120 bytes. <feature_touch> (under a manifest whose "
    "match is a feature or extra) n= its features (default and _-private ones left out); <touch_list> the files outside the manifest that "
    "mention at least half of them, where a new feature is listed or gated: total= such files, shown= and capped=\"1\" when fewer rows are "
    "printed; <touch> p=file:line the line to copy, share=named/of the distinct feature names it mentions, cut=\"1\" when cut to 120 bytes; "
    "test, docs, vendored, generated, frozen and baseline files are not read. The answer above is unchanged, and these bytes are not in "
    "est_tokens -->";
// The --legend=compact posture (the CLI default); the long text rides --legend=full and the MCP tool. Both define every attribute printed.
inline constexpr std::string_view kForManifestRowsCompactLegend =
    "<!-- ripwire for manifest_rows: manifest lines defining a package, dependency, script, binary, target, feature or plugin entry point the task names "
    "exactly (package.json, Cargo.toml, pyproject.toml, setup.cfg, go.mod, CMakeLists.txt; the repo's own name (an entry point's group may be it), generic names, "
    "un-asked scripts or plugin entry points and entries the task neither names by their kind nor adds as a new X never fire it); leads, not a guarantee; not in est_tokens. files= manifests naming a task word; <mf> p= manifest, "
    "matched= task words its names hold, rows= matching lines; <r> l= line, kind= what it defines, group= an entry point's group, cut=\"1\": text cut to 120 bytes; "
    "shown=/capped=\"1\": rows cut. <feature_touch> n= the manifest's features; <touch_list> total= files naming at least half of "
    "them (tests, docs, vendored, generated unread); <touch> p= the line, share=named/of distinct feature names, cut=\"1\": cut. -->";
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
        std::vector<ExemplarTouch> touch = exemplarTouchList( ing, *fam );
        std::vector<std::string_view> anchored; // the features the task names: the lines that define or document them
        for( const ManifestHit& h : m.hits )
        {
            const ManifestEntry& en = doc.entries[h.entry];
            if( h.anchor && ( en.kind == ManifestKind::Feature || en.kind == ManifestKind::Extra ) )
            {
                anchored.push_back( en.name );
            }
        }
        retargetCfgTouchLines( ing, anchored, touch );
        out += "<feature_touch n=\"" + std::to_string( fam->members.size() ) + "\">" + touchListXml( ing, *fam, touch ) + "</feature_touch>";
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
    const std::vector<ManifestDoc> docs = readManifests( ing );
    const std::vector<ManifestMatch> ranked = rankManifests( docs, t );
    if( ranked.empty() )
    {
        return {};
    }
    if( held )
    {
        return "<!-- ripwire for manifest_rows: held=\"budget\": a token budget is set, so the manifest lines the task names are not printed; "
               "files= the manifests that name a task word exactly; the same call without the token budget prints them; the answer above is unchanged -->"
               "<manifest_rows files=\"" +
               std::to_string( ranked.size() ) + "\" held=\"budget\"/>";
    }
    std::string out( compactLegend ? kForManifestRowsCompactLegend : kForManifestRowsLegend );
    out += "<manifest_rows files=\"" + std::to_string( ranked.size() ) + "\"";
    out += ranked.size() > kManifestFileRows ? " shown=\"" + std::to_string( kManifestFileRows ) + "\" capped=\"1\">" : std::string( ">" ); // CAP-DISCLOSE
    for( std::size_t i = 0; i < ranked.size() && i < kManifestFileRows; ++i )
    {
        out += manifestFileXml( ing, docs[ranked[i].doc], ranked[i] );
    }
    return out + "</manifest_rows>";
}
} // namespace rw
