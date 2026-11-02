#pragma once
// epmanifest.h — MANIFEST ENTRY POINTS on a --for answer (lane ep-manifest; CONTRIBUTING family 10, slice 10a, first readers).
//
// WHY. A Python plugin is registered in a manifest, not in code: setup.cfg `[options.entry_points] flake8.report = pylint =
// flake8.formatting.default:Pylint`, and the host loads the group by its string literal (`ep.group == "flake8.report"`). Neither
// file names the other, so a registration question ("how is a formatter registered?") reached the class and never the
// manifest nor the loader: no edge joins a config key to a code literal. Measured before this code (reports/ep-manifest.md
// Stage 0): flake8-02's answer ranked all four flake8.report targets and printed 0 hits for setup.cfg and the loader.
//
// WHAT. <ep p= l= group= [used_at= used_in= used_total=]><e n= target= [def=|external=1|unresolved=1]/>…</ep>, after the file
// tail and before the caller hop and the bodies: one element per manifest group that holds a SHOWN ranked row, every entry of
// that group (n= the entry name, target= the module:attr as written), def= the in-tree definition the target names
// (file:line), external="1" when no indexed file is that module, unresolved="1" when the module is in the tree but the
// attribute is not exactly one definition there. used_at= / used_in= are the code consumers of the group's string literal —
// a comparison with a `.group`, `entry_points(group=…)`, `.select(group=…)`, `iter_entry_points(…)`, `entry_points()[…]` —
// by literal text (not resolved), file:line and the enclosing definition, at most kForEpUsedAtRows with used_capped="1" used_total= past it.
// No consumer: no used_at= (never a guess). The manifest group l= is the group's own line (setup.cfg key, pyproject header).
//
// READERS (one per manifest format, language data separate from the shared row): setup.cfg `[options.entry_points]` (INI keys
// and continuation lines), pyproject.toml `[project.entry-points.G]`, `[project.scripts]` (console_scripts), `[project.gui-scripts]`
// (gui_scripts), `[tool.poetry.plugins.G]`, `[tool.poetry.scripts]` (string values only); Cargo.toml `[[bin]]` (name, path,
// Cargo's default `src/main.rs` / `src/bin/<name>.rs` when a target omits it, the package's own bin when a crate declares none);
// package.json `"bin"` / `"main"` (file-path targets). One table (kEpManifestFormats) names each format's file, reader, target
// form and the shown-row file extensions that look for it: a manifest is read where such a shown row sits in a directory or an
// ancestor that holds one — a package's manifest always sits above its modules.
// FLOORS (stated in the legend's absence of them, and in the lane report): setup.py `entry_points={…}` (a call, not a table),
// package.json `"exports"` maps, pyproject inline tables, a group literal built at run time, a multi-root run. The DEFAULT regime
// and the XML dialect only, as the caller hop: --json, --token-budget=N,
// --signatures-only and --detail=N carry none. RIPWIRE_NO_EP_MANIFEST (any value) turns it off — the A/B handle.

#include "docparse.h"     // readRegularFile — a fixed-name file in the tree, refused when it is not a regular file
#include "darkflags.h"    // forEachLine — the one line splitter over raw file text (CR stripped)
#include "flipimpact.h"   // SymbolLineIndex / innermostAtLine — the innermost def covering a line (the consumer's enclosing def)
#include "infra/namesplit.h"   // isIdentChar
#include "model.h"        // IngestResult, rootRelPath, diskPath, symbolsByFile
#include "pydottedpath.h" // epModuleFile, epAttrNames: the one dotted-path resolver (shared with fordottedstring.h)
#include "resolve.h"      // trimWs
#include "serialize.h"    // escapeXml

#include <algorithm>
#include <array>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <format>
#include <iterator>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// Runaway guards, not size targets (knob census ADDENDUM): every group or entry past them is dropped WITH a disclosure
// (groups_capped="1" groups_total= on the first element, entries_capped="1" entries_total= on the group, used_capped="1" used_total=) — a manifest rarely has more than a handful of either.
inline constexpr std::size_t kForEpGroupRows   = 4;    // groups per answer
inline constexpr std::size_t kForEpEntryRows  = 12;   // entries shown per group
inline constexpr std::size_t kForEpUsedAtRows   = 3;    // consumer sites shown per group (used_total= counts all)

inline bool forEpManifestOn()
{
    return std::getenv( "RIPWIRE_NO_EP_MANIFEST" ) == nullptr;
}

// One manifest entry: the group it sits in, the group's line (setup.cfg key / pyproject header), the entry name and its
// target exactly as written (extras and trailing text cut), and the entry's own line.
struct EpEntry
{
    std::string   group;
    std::uint32_t groupLine = 0;
    std::string   name;
    std::string   target;
    std::uint32_t line = 0;
    bool          implicit = false;   // no manifest line names it: Cargo's package bin inferred with no [[bin]] (a quiet satellite, renderForEpManifest)
};

namespace epdetail
{


inline bool isDottedNameChar( char c ) noexcept
{
    return namesplit::isIdentChar( c ) || c == '.';
}

// `module[:attr]` from an entry value: the leading run up to whitespace or an extras bracket. "" when it is not a dotted module
// name with an optional dotted attribute (a path, a quoted table, garbage) — that entry is not recorded.
inline std::string entryTarget( std::string_view v )
{
    v = trimWs( v );
    std::string joined;   // `mod : attr` (the importlib grammar allows blanks around the colon) reads as `mod:attr`
    if( const std::size_t c = v.find( ':' ); c != std::string_view::npos && c > 0 )
    {
        joined = std::string( trimWs( v.substr( 0, c ) ) ) + ":" + std::string( trimWs( v.substr( c + 1 ) ) );
        v      = joined;
    }
    std::size_t end = 0;
    while( end < v.size() && v[end] != ' ' && v[end] != '\t' && v[end] != '[' )
    {
        ++end;
    }
    const std::string_view t     = v.substr( 0, end );
    const std::size_t      colon = t.find( ':' );
    const std::string_view mod   = t.substr( 0, colon );
    const std::string_view attr  = colon == std::string_view::npos ? std::string_view() : t.substr( colon + 1 );
    const auto             dotted = []( std::string_view s ) { return !s.empty() && s.front() != '.' && s.back() != '.' && std::ranges::all_of( s, isDottedNameChar ); };
    if( !dotted( mod ) || ( colon != std::string_view::npos && !dotted( attr ) ) )
    {
        return {};
    }
    return std::string( t );
}

// `name = module:attr` (one setup.cfg entry line or the inline part of a group line).
inline void addCfgEntry( std::string_view v, std::string_view group, std::uint32_t groupLine, std::uint32_t line, std::vector<EpEntry>& out )
{
    const std::size_t eq = v.find( '=' );
    if( eq == std::string_view::npos )
    {
        return;
    }
    const std::string_view name   = trimWs( v.substr( 0, eq ) );
    const std::string      target = entryTarget( v.substr( eq + 1 ) );
    if( name.empty() || target.empty() )
    {
        return;
    }
    out.push_back( EpEntry{ std::string( group ), groupLine, std::string( name ), target, line } );
}

// A TOML key or header path split on its dots, quoted parts kept whole ("a.b" is one part). Empty on a malformed path.
inline std::vector<std::string> tomlKeyParts( std::string_view s )
{
    std::vector<std::string> parts;
    std::string              cur;
    bool                     any = false;
    for( std::size_t i = 0; i < s.size(); ++i )
    {
        const char c = s[i];
        if( c == '"' || c == '\'' )
        {
            const std::size_t close = s.find( c, i + 1 );
            if( close == std::string_view::npos )
            {
                return {};
            }
            cur.append( s.substr( i + 1, close - i - 1 ) );
            any = true;
            i   = close;
        }
        else if( c == '.' )
        {
            if( !any )
            {
                return {};
            }
            parts.push_back( std::string( trimWs( cur ) ) );
            cur.clear();
            any = false;
        }
        else if( c != ' ' && c != '\t' )
        {
            cur += c;
            any = true;
        }
    }
    if( !any )
    {
        return {};
    }
    parts.push_back( std::move( cur ) );
    return parts;
}

// The entry-point group a pyproject table header names, or "" when the table is no entry-point table.
inline std::string pyprojectGroupOf( const std::vector<std::string>& k )
{
    if( k.size() == 3 && k[0] == "project" && k[1] == "entry-points" && !k[2].empty() )
    {
        return k[2];
    }
    if( k.size() == 2 && k[0] == "project" && k[1] == "scripts" )
    {
        return "console_scripts";
    }
    if( k.size() == 2 && k[0] == "project" && k[1] == "gui-scripts" )
    {
        return "gui_scripts";
    }
    if( k.size() == 4 && k[0] == "tool" && k[1] == "poetry" && k[2] == "plugins" && !k[3].empty() )
    {
        return k[3];
    }
    if( k.size() == 3 && k[0] == "tool" && k[1] == "poetry" && k[2] == "scripts" )
    {
        return "console_scripts";
    }
    return {};
}

// A TOML basic or literal string value (`"x"` / `'x'`), or nullopt for any other value (a table, an array, a number).
inline std::optional<std::string_view> tomlStringValue( std::string_view v ) noexcept
{
    v = trimWs( v );
    if( v.size() < 2 || ( v.front() != '"' && v.front() != '\'' ) )
    {
        return std::nullopt;
    }
    const std::size_t close = v.find( v.front(), 1 );
    if( close == std::string_view::npos )
    {
        return std::nullopt;
    }
    return v.substr( 1, close - 1 );
}

// The index of the ']' that closes the TOML table header `t` (t[0] == '['; quoted parts skipped), npos when it is unclosed.
inline std::size_t tomlHeaderClose( std::string_view t ) noexcept
{
    for( std::size_t i = 1, q = 0; i < t.size(); ++i )
    {
        if( q != 0 )
        {
            q = std::size_t( t[i] ) == q ? 0 : q;
        }
        else if( t[i] == '"' || t[i] == '\'' )
        {
            q = std::size_t( t[i] );
        }
        else if( t[i] == ']' )
        {
            return i;
        }
    }
    return std::string_view::npos;
}

// The '=' that ends the key of a TOML `key = value` line: the first one outside quotes, npos when there is none.
inline std::size_t tomlKeyEnd( std::string_view t ) noexcept
{
    char q = 0;
    for( std::size_t i = 0; i < t.size(); ++i )
    {
        if( q != 0 )
        {
            q = t[i] == q ? char( 0 ) : q;
        }
        else if( t[i] == '"' || t[i] == '\'' )
        {
            q = t[i];
        }
        else if( t[i] == '=' )
        {
            return i;
        }
    }
    return std::string_view::npos;
}

// The header path of a TOML table line `[a.b]` (`array` false) or array-of-tables line `[[a.b]]` (`array` true); empty when
// `t` is no well-formed header.
inline std::vector<std::string> tomlHeaderParts( std::string_view t, bool& array )
{
    array = t.starts_with( "[[" );
    const std::string_view inner = array ? t.substr( 1 ) : t;
    const std::size_t      close = tomlHeaderClose( inner );
    if( close == std::string_view::npos || close <= 1 || ( array && inner.substr( close ).size() < 2 ) || ( array && inner[ close + 1 ] != ']' ) )
    {
        return {};
    }
    return tomlKeyParts( inner.substr( 1, close - 1 ) );
}

// The delimiter (""" or ''') of a multi-line string the value `rhs` opens and does not close on its own line, else "".
inline std::string_view tomlMultilineOpen( std::string_view rhs ) noexcept
{
    for( const std::string_view d : { std::string_view( "\"\"\"" ), std::string_view( "\'\'\'" ) } )
    {
        if( rhs.starts_with( d ) && rhs.find( d, 3 ) == std::string_view::npos )
        {
            return d;
        }
    }
    return {};
}


}   // namespace epdetail

// setup.cfg: the `[options.entry_points]` section. A group is an unindented `key = value` (or `key: value`) line; its entries are
// the inline value and every indented continuation line `name = module:attr`. Comment lines (# ;) are skipped.
inline void parseSetupCfgEntryPoints( std::string_view text, std::vector<EpEntry>& out )
{
    bool          inSection = false;
    std::string   group;
    std::uint32_t groupLine = 0;
    darkflags::forEachLine( text, [ & ]( std::string_view line, std::uint32_t lineNo )
    {
        const std::string_view t = trimWs( line );
        if( t.empty() || t.front() == '#' || t.front() == ';' )
        {
            return;
        }
        if( t.front() == '[' )
        {
            inSection = t == "[options.entry_points]";
            group.clear();
            return;
        }
        if( !inSection )
        {
            return;
        }
        if( line.front() == ' ' || line.front() == '\t' )
        {
            if( !group.empty() )
            {
                epdetail::addCfgEntry( t, group, groupLine, lineNo, out );
            }
            return;
        }
        const std::size_t sep = t.find_first_of( "=:" );
        if( sep == std::string_view::npos )
        {
            group.clear();
            return;
        }
        group     = std::string( trimWs( t.substr( 0, sep ) ) );
        groupLine = lineNo;
        if( group.empty() )
        {
            return;   // `= x = m:a` names no group: nothing to search for, nothing to print
        }
        if( const std::string_view inl = trimWs( t.substr( sep + 1 ) ); !inl.empty() )
        {
            epdetail::addCfgEntry( inl, group, groupLine, lineNo, out );
        }
    } );
}

// pyproject.toml: `[project.entry-points.G]` / `[project.scripts]` / `[project.gui-scripts]` / `[tool.poetry.plugins.G]` /
// `[tool.poetry.scripts]` tables, each `name = "module:attr"` line whose value is a string.
inline void parsePyprojectEntryPoints( std::string_view text, std::vector<EpEntry>& out )
{
    std::string      group;
    std::uint32_t    groupLine = 0;
    std::string_view multiline;   // the delimiter of an open multi-line string: its lines are a value, never a table or a key
    darkflags::forEachLine( text, [ & ]( std::string_view line, std::uint32_t lineNo )
    {
        const std::string_view t = trimWs( line );
        if( !multiline.empty() )
        {
            multiline = t.contains( multiline ) ? std::string_view() : multiline;
            return;
        }
        if( t.empty() || t.front() == '#' )
        {
            return;
        }
        if( t.front() == '[' )
        {
            const std::size_t close = epdetail::tomlHeaderClose( t );
            group = ( t.starts_with( "[[" ) || close == std::string_view::npos ) ? std::string()
                  : epdetail::pyprojectGroupOf( epdetail::tomlKeyParts( t.substr( 1, close - 1 ) ) );
            groupLine = lineNo;
            return;
        }
        const std::size_t eq = epdetail::tomlKeyEnd( t );   // the key ends at the first '=' outside quotes
        if( eq == std::string_view::npos )
        {
            return;
        }
        multiline = epdetail::tomlMultilineOpen( trimWs( t.substr( eq + 1 ) ) );   // in any table: [project] description = """
        if( group.empty() )
        {
            return;
        }
        const std::vector<std::string>        key = epdetail::tomlKeyParts( t.substr( 0, eq ) );
        const std::optional<std::string_view> val = epdetail::tomlStringValue( t.substr( eq + 1 ) );
        const std::string                     target = val ? epdetail::entryTarget( *val ) : std::string();
        if( key.size() != 1 || key[0].empty() || target.empty() )
        {
            return;
        }
        out.push_back( EpEntry{ group, groupLine, key[0], target, lineNo } );
    } );
}

// Cargo.toml: each `[[bin]]` table (name, path; Cargo's default `src/main.rs` for the package's own name, `src/bin/<name>.rs`
// otherwise, when `path` is omitted — filled after the scan, so a `[[bin]]` written before `[package]` is named as Cargo
// names it), else — no `[[bin]]` at all and no `autobins = false` — the package's own bin at `src/main.rs`, marked implicit.
// Group "bin", the target a file path. Lines inside a multi-line string are values, never keys or tables. Not read (floors):
// src/bin/<name>/main.rs as a default path, and the src/bin/*.rs binaries Cargo auto-discovers.
inline void parseCargoBins( std::string_view text, std::vector<EpEntry>& out )
{
    bool             inBin     = false;
    bool             inPackage = false;
    bool             sawBin    = false;
    bool             autobins  = true;
    const std::size_t first    = out.size();   // this manifest's entries start here
    std::string      pkgName;
    std::uint32_t    pkgLine = 0;
    std::string      curName;
    std::string      curPath;
    std::uint32_t    binLine = 0;
    std::string_view multiline;   // the delimiter of an open multi-line string
    const auto       flushBin = [ & ]()
    {
        if( inBin && !curName.empty() )
        {
            out.push_back( EpEntry{ "bin", binLine, curName, curPath, binLine } );   // an empty path: Cargo's default, after the scan
            sawBin = true;
        }
        curName.clear();
        curPath.clear();
    };
    darkflags::forEachLine( text, [ & ]( std::string_view line, std::uint32_t lineNo )
    {
        const std::string_view t = trimWs( line );
        if( !multiline.empty() )
        {
            multiline = t.contains( multiline ) ? std::string_view() : multiline;
            return;
        }
        if( t.empty() || t.front() == '#' )
        {
            return;
        }
        if( t.front() == '[' )
        {
            flushBin();
            bool                           array = false;
            const std::vector<std::string> table = epdetail::tomlHeaderParts( t, array );
            const bool                     one   = table.size() == 1;
            inBin     = array && one && table[0] == "bin";
            inPackage = !array && one && table[0] == "package";
            binLine   = inBin ? lineNo : 0;
            pkgLine   = inPackage ? lineNo : pkgLine;
            return;
        }
        const std::size_t eq = epdetail::tomlKeyEnd( t );
        if( eq == std::string_view::npos )
        {
            return;
        }
        multiline                                   = epdetail::tomlMultilineOpen( trimWs( t.substr( eq + 1 ) ) );
        const std::vector<std::string>        key   = epdetail::tomlKeyParts( t.substr( 0, eq ) );
        const std::optional<std::string_view> val   = epdetail::tomlStringValue( t.substr( eq + 1 ) );
        if( inPackage && key.size() == 1 && key[0] == "autobins" )
        {
            const std::string_view rhs = trimWs( t.substr( eq + 1 ) );   // a TOML bool, then blanks or a comment
            autobins = !( rhs.starts_with( "false" ) && ( rhs.size() == 5 || rhs[5] == ' ' || rhs[5] == '\t' || rhs[5] == '#' ) );
        }
        if( key.size() != 1 || !val || val->empty() )
        {
            return;
        }
        if( inBin && key[0] == "name" )
        {
            curName = *val;
        }
        else if( inBin && key[0] == "path" )
        {
            curPath = *val;
        }
        else if( inPackage && key[0] == "name" )
        {
            pkgName = *val;
        }
    } );
    flushBin();
    for( std::size_t i = first; i < out.size(); ++i )
    {
        // (src/bin/<name>/main.rs is not tried: a floor, the entry then reads unresolved or external)
        out[i].target = !out[i].target.empty() ? out[i].target : out[i].name == pkgName ? std::string( "src/main.rs" ) : "src/bin/" + out[i].name + ".rs";
    }
    if( !sawBin && autobins && !pkgName.empty() )
    {
        out.push_back( EpEntry{ "bin", pkgLine, pkgName, "src/main.rs", pkgLine, /*implicit=*/true } );
    }
}

// package.json: `"bin"` (a string or an object of name → path) and `"main"`, each target a file path as written (not module:attr).
// The line of the TOP-LEVEL key `key` of the JSON object `text` (object depth 1, outside strings), 0 when it is absent: a
// same-named key nested deeper ("publishConfig": {"bin": …}) or a value that spells it ("files": ["bin"]) is not that key.
inline std::uint32_t jsonKeyLine( std::string_view text, std::string_view key )
{
    std::uint32_t line  = 1;
    int           depth = 0;
    for( std::size_t i = 0; i < text.size(); ++i )
    {
        const char c = text[i];
        line += c == '\n' ? 1 : 0;
        depth += ( c == '{' || c == '[' ) ? 1 : ( c == '}' || c == ']' ) ? -1 : 0;
        if( c != '"' )
        {
            continue;
        }
        std::size_t end = i + 1;   // the closing quote; a backslash escapes the next byte
        while( end < text.size() && text[end] != '"' )
        {
            end += text[end] == '\\' ? 2 : 1;
        }
        if( end >= text.size() )
        {
            return 0;   // an unclosed string: no key can follow
        }
        const std::size_t after = text.find_first_not_of( " \t\r\n", end + 1 );
        if( depth == 1 && text.substr( i + 1, end - i - 1 ) == key && after != std::string_view::npos && text[after] == ':' )
        {
            return line;
        }
        i = end;
    }
    return 0;
}

inline void parsePackageJsonEntries( std::string_view text, std::vector<EpEntry>& out )
{
    tsimport::JsonNode root;
    if( !tsimport::parseJsonObject( std::string( text ), root ) )
    {
        return;
    }
    std::string pkgName;   // a string `bin` and `main` are named by the package; with no "name", `main` by its key (never invented)
    if( const tsimport::JsonNode* nm = root.get( "name" ); nm != nullptr && nm->kind == tsimport::JsonNode::Kind::Str && !nm->str.empty() )
    {
        pkgName = nm->str;
    }
    const auto add = [ & ]( std::string_view group, std::uint32_t groupLine, std::string_view name, std::string_view target, std::uint32_t line )
    {
        if( !name.empty() && !target.empty() )
        {
            out.push_back( EpEntry{ std::string( group ), groupLine, std::string( name ), std::string( target ), line } );
        }
    };
    if( const tsimport::JsonNode* bin = root.get( "bin" ) )
    {
        const std::uint32_t binLine = jsonKeyLine( text, "bin" );
        // npm installs a bin under its name's last segment ("@acme/tool" → tool), and drops a string `bin` of a nameless package
        const auto command = []( std::string_view n ) { return n.substr( n.rfind( '/' ) == std::string_view::npos ? 0 : n.rfind( '/' ) + 1 ); };
        if( bin->kind == tsimport::JsonNode::Kind::Str && !bin->str.empty() && !pkgName.empty() )
        {
            add( "bin", binLine, command( pkgName ), bin->str, binLine );
        }
        else if( bin->kind == tsimport::JsonNode::Kind::Obj )
        {
            for( std::size_t i = 0; i < bin->keys.size(); ++i )
            {
                const tsimport::JsonNode& v = bin->vals[i];
                if( v.kind == tsimport::JsonNode::Kind::Str && !v.str.empty() && !bin->keys[i].empty() )
                {
                    add( "bin", binLine, command( bin->keys[i] ), v.str, binLine );
                }
            }
        }
    }
    if( const tsimport::JsonNode* main = root.get( "main" ) )
    {
        const std::uint32_t mainLine = jsonKeyLine( text, "main" );
        if( main->kind == tsimport::JsonNode::Kind::Str && !main->str.empty() )
        {
            add( "main", mainLine, pkgName.empty() ? std::string_view( "main" ) : std::string_view( pkgName ), main->str, mainLine );
        }
    }
}

// ── the consumer shapes: a quoted occurrence of the group literal whose line reads it as an entry-point group ──────────────
namespace epdetail
{

// The trailing dotted name of `s` (after trimming), e.g. "loaded.plugin.entry_point.group" → its last segment "group".
// The last segment of the dotted name `s` ENDS with (after trimming), and of the one it STARTS with (model.h scopeLastSegment).
inline std::string_view lastSegmentOfTrailingName( std::string_view s ) noexcept
{
    s = trimWs( s );
    const auto from = std::find_if_not( s.rbegin(), s.rend(), isDottedNameChar );
    return scopeLastSegment( s.substr( std::size_t( s.rend() - from ) ) );
}
inline std::string_view leadingName( std::string_view s ) noexcept
{
    s = trimWs( s );
    return scopeLastSegment( s.substr( 0, std::size_t( std::ranges::find_if_not( s, isDottedNameChar ) - s.begin() ) ) );
}

// Is a '#' outside a string literal before the end of `before`? (then the occurrence sits in a comment)
inline bool inLineComment( std::string_view before ) noexcept
{
    char q = 0;
    for( const char c : before )
    {
        if( q != 0 )
        {
            q = c == q ? char( 0 ) : q;
        }
        else if( c == '"' || c == '\'' )
        {
            q = c;
        }
        else if( c == '#' )
        {
            return true;
        }
    }
    return false;
}

// The loaders whose argument (or group= keyword) names an entry-point group: importlib.metadata entry_points / select,
// pkg_resources iter_entry_points / get_entry_map, the importlib_metadata backport's same names.
inline constexpr std::string_view kEpGroupLoaders[] = { "entry_points", "select", "iter_entry_points", "get_group_all", "get_group_named", "get_entry_map" };

// `b` ends with `group=`: cut it back to the call's open paren — `f( group=` → `f(`, and `f( x, y, group=` past the arguments
// before it to the last unclosed '(' — so the caller reads the callee. False (b untouched) when the keyword is not `group`
// or no paren is open.
inline bool groupKeywordCall( std::string_view& b ) noexcept
{
    std::string_view k = trimWs( b.substr( 0, b.size() - 1 ) );
    if( !k.ends_with( "group" ) || ( k.size() > 5 && isDottedNameChar( k[k.size() - 6] ) ) )
    {
        return false;
    }
    k = trimWs( k.substr( 0, k.size() - 5 ) );
    int         depth = 0;
    std::size_t i     = k.ends_with( "," ) ? k.size() : 0;   // after a comma: walk back to the unclosed '('
    while( i > 0 && depth >= 0 )
    {
        --i;
        depth += k[i] == ')' ? 1 : ( k[i] == '(' ? -1 : 0 );
    }
    if( k.ends_with( "," ) && depth >= 0 )
    {
        return false;
    }
    b = k.ends_with( "," ) ? k.substr( 0, i + 1 ) : k;
    return true;
}

// `before` = the line up to the literal's opening quote, `after` = from its closing quote on.
inline bool consumerShape( std::string_view before, std::string_view after ) noexcept
{
    if( inLineComment( before ) )
    {
        return false;
    }
    std::string_view b = trimWs( before );
    std::string_view a = trimWs( after );
    // X.group == "g" / X.group != "g"
    if( b.ends_with( "==" ) || b.ends_with( "!=" ) )
    {
        return lastSegmentOfTrailingName( b.substr( 0, b.size() - 2 ) ) == "group";
    }
    // "g" == X.group
    if( a.starts_with( "==" ) || a.starts_with( "!=" ) )
    {
        return leadingName( a.substr( 2 ) ) == "group";
    }
    // entry_points()["g"] / entry_points().get("g")
    if( b.ends_with( "entry_points()[" ) || b.ends_with( "entry_points().get(" ) )
    {
        return true;
    }
    // loader( "g" ) / loader( group="g" ) — the literal is the first argument or the group= keyword
    if( b.ends_with( "=" ) && !groupKeywordCall( b ) )
    {
        return false;
    }
    if( !b.ends_with( "(" ) )
    {
        return false;
    }
    return std::ranges::find( kEpGroupLoaders, lastSegmentOfTrailingName( b.substr( 0, b.size() - 1 ) ) ) != std::end( kEpGroupLoaders );
}

}   // namespace epdetail

// One code consumer of a group literal: the file and line, as a site.
struct EpConsumer
{
    std::uint32_t fileId = 0;
    std::uint32_t line   = 0;
};

// Every consumer site of each literal in `groups`, over the indexed .py files, in file order then line. One read per file that
// holds any of the literals (a substring pre-filter on the whole text first); an unreadable file is skipped (it can only make
// the list shorter, and the legend says the sites are a floor).
inline std::vector<std::vector<EpConsumer>> findGroupConsumers( const IngestResult& ing, std::span<const std::string> groups )
{
    std::vector<std::vector<EpConsumer>> out( groups.size() );
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( !rootRelPath( ing, f ).ends_with( ".py" ) )
        {
            continue;
        }
        const std::optional<std::string> text = docparse::detail::readWholeFile( diskPath( ing, f ) );
        if( !text )
        {
            continue;
        }
        for( std::size_t gi = 0; gi < groups.size(); ++gi )
        {
            const std::string& g = groups[gi];
            std::uint32_t      lastLine = 0;
            std::size_t        countedTo = 0;   // the newlines before countedTo are in countedLines (one forward pass per literal)
            std::uint32_t      countedLines = 0;
            for( std::size_t at = text->find( g ); at != std::string::npos; at = text->find( g, at + 1 ) )
            {
                const std::size_t close = at + g.size();
                if( at == 0 || close >= text->size() || ( ( *text )[at - 1] != '"' && ( *text )[at - 1] != '\'' ) || ( *text )[close] != ( *text )[at - 1] )
                {
                    continue;
                }
                const std::size_t ls  = text->rfind( '\n', at - 1 );
                const std::size_t lb  = ls == std::string::npos ? 0 : ls + 1;
                const std::size_t le  = std::min( text->find( '\n', close ), text->size() );
                const std::string_view tv( *text );
                if( !epdetail::consumerShape( tv.substr( lb, at - 1 - lb ), tv.substr( close + 1, le - close - 1 ) ) )
                {
                    continue;
                }
                countedLines += std::uint32_t( std::count( text->begin() + std::ptrdiff_t( countedTo ), text->begin() + std::ptrdiff_t( lb ), '\n' ) );
                countedTo = lb;
                const std::uint32_t line = 1 + countedLines;
                if( line != lastLine )
                {
                    out[gi].push_back( EpConsumer{ f, line } );
                    lastLine = line;
                }
            }
        }
    }
    return out;
}

// The in-tree definition an entry's target names, or why there is none.
enum class EpTargetState : std::uint8_t { Def, External, Unresolved };
struct EpTarget
{
    EpTargetState state = EpTargetState::External;
    NodeId        def   = kNoNode;
};

struct EpRender
{
    std::string xml;   // the <ep> elements; empty when no manifest group holds a shown row
};

// How a manifest's entry target names code: `module:attr` (Python), a file whose `fn main` runs (Cargo), a file whose exported
// function or module body runs (package.json).
enum class EpTargetForm : std::uint8_t { ModuleAttr, BinMain, FileExport };

// THE FORMAT TABLE: one row per manifest file name — its reader, its target form, and the extensions of the shown rows that
// look for it (a Python row never reads Cargo.toml, a Rust row never reads setup.cfg). Bit i of a format mask is row i.
struct EpManifestFormat
{
    std::string_view name;
    void ( *read )( std::string_view, std::vector<EpEntry>& );
    EpTargetForm     form;
    std::string_view exts[2];
};
inline constexpr EpManifestFormat kEpManifestFormats[] = {
    { "setup.cfg", parseSetupCfgEntryPoints, EpTargetForm::ModuleAttr, { ".py", {} } },
    { "pyproject.toml", parsePyprojectEntryPoints, EpTargetForm::ModuleAttr, { ".py", {} } },
    { "Cargo.toml", parseCargoBins, EpTargetForm::BinMain, { ".rs", {} } },
    { "package.json", parsePackageJsonEntries, EpTargetForm::FileExport, { ".js", ".ts" } },
};
static_assert( std::size( kEpManifestFormats ) <= 8, "a format mask is one byte" );

// The formats a shown row in file `rel` looks for (bit mask over kEpManifestFormats).
inline std::uint8_t epFormatsForFile( std::string_view rel ) noexcept
{
    std::uint8_t mask = 0;
    for( std::size_t fi = 0; fi < std::size( kEpManifestFormats ); ++fi )
    {
        for( const std::string_view ext : kEpManifestFormats[fi].exts )
        {
            mask |= !ext.empty() && rel.ends_with( ext ) ? std::uint8_t( 1U << fi ) : std::uint8_t( 0 );
        }
    }
    return mask;
}

// The formats whose target is written in `form`.
inline std::uint8_t epFormatsOfForm( EpTargetForm form ) noexcept
{
    std::uint8_t mask = 0;
    for( std::size_t fi = 0; fi < std::size( kEpManifestFormats ); ++fi )
    {
        mask |= kEpManifestFormats[fi].form == form ? std::uint8_t( 1U << fi ) : std::uint8_t( 0 );
    }
    return mask;
}

// THE ONE PATH RESOLVER for file-path targets (Cargo `path`, package.json `bin`/`main`): `path` as written, a Windows `\`
// read as `/`, joined to the manifest's directory `mdir` and normalized lexically (lexicalNormalize: "./" and "." elided, ".."
// collapsed, so "../shared/gen.rs" from up/ is shared/gen.rs); the indexed file at exactly that root-relative path. `inTree`
// says whether one exists. A path that escapes above the root, an absolute path or a directory matches no indexed file: External.
inline std::uint32_t epPathFile( const IngestResult& ing, std::string_view mdir, std::string_view path, bool& inTree )
{
    std::string joined = mdir.empty() ? std::string( path ) : std::string( mdir ) + "/" + std::string( path );
    std::replace( joined.begin(), joined.end(), '\\', '/' );   // a TOML basic string's undecoded "\\" leaves an empty segment: elided
    const std::string rel = path.starts_with( '/' ) || path.starts_with( '\\' ) ? std::string() : lexicalNormalize( joined );
    std::uint32_t     hit = kNoFile;
    for( std::uint32_t f = 0; f < ing.files.size() && hit == kNoFile && !rel.empty(); ++f )
    {
        hit = rootRelPath( ing, f ) == rel ? f : kNoFile;
    }
    inTree = hit != kNoFile;
    return hit;
}

namespace epdetail
{

inline bool epIsMainFn( const Symbol& s ) noexcept
{
    return s.name == "main" && s.kind == SymKind::Function;
}

// A package.json target file's entry definition: its first top-level function inside an ES export, else the file's module
// scope (the body that runs when the file is loaded). `exports` are that file's JsExport bindings.
inline NodeId epFileEntryDef( const IngestResult& ing, const FileSymbols& fs, std::span<const Binding* const> exports )
{
    NodeId        modScope   = kNoNode;
    NodeId        exportFn   = kNoNode;
    std::uint32_t exportLine = UINT32_MAX;
    for( const NodeId id : fs )
    {
        const Symbol& s = ing.symbols[id];
        if( s.kind == SymKind::ModuleScope )
        {
            modScope = id;
        }
        if( s.kind != SymKind::Function || ( !s.scope.empty() && s.scope != s.name ) || s.line >= exportLine )
        {
            continue;
        }
        const bool exported = std::ranges::any_of( exports, [ & ]( const Binding* b )
        {
            const std::string_view local = b->importedName.empty() ? std::string_view( b->var ) : std::string_view( b->importedName );
            return local == s.name && s.sigStartByte >= b->spanStart && s.endByte <= b->spanEnd;
        } );
        if( exported )
        {
            exportLine = s.line;
            exportFn   = id;
        }
    }
    return exportFn != kNoNode ? exportFn : modScope;
}

struct Manifest
{
    std::string             rel;   // root-relative path of the manifest file
    std::string             dir;   // its root-relative directory ("" = the root)
    std::vector<EpEntry>    entries;
    const EpManifestFormat* fmt = nullptr;   // its row of kEpManifestFormats
};

// A manifest inside a node_modules tree belongs to a dependency, not to the shown row's package.
inline bool epInDependencyTree( std::string_view rel, std::string_view diskPath )
{
    const std::string                   relFromRoot = "/" + std::string( rel );   // a leading segment is a segment too
    const std::array<std::string_view, 2> paths     = { relFromRoot, diskPath };
    return std::ranges::any_of( paths, []( std::string_view p ) { return p.contains( "/node_modules/" ); } );
}

// Read one manifest of format `fmt` in directory `dir` (root-relative; `disk` is the same directory on disk); kept only when
// it holds entries.
inline void epTryReadManifest( const std::filesystem::path& disk, std::string_view dir, const EpManifestFormat& fmt, std::vector<Manifest>& out )
{
    const std::string manRel  = dir.empty() ? std::string( fmt.name ) : std::string( dir ) + "/" + std::string( fmt.name );
    const std::string manDisk = ( disk / std::string( fmt.name ) ).generic_string();
    if( epInDependencyTree( manRel, manDisk ) )
    {
        return;
    }
    const std::optional<std::string> text = docparse::detail::readRegularFile( std::string( fmt.name ), manDisk );
    if( !text )
    {
        return;
    }
    Manifest m{ manRel, std::string( dir ), {}, &fmt };
    fmt.read( *text, m.entries );
    if( !m.entries.empty() )
    {
        out.push_back( std::move( m ) );
    }
}

// The manifests above one file: its own directory and each ancestor up to the root, each format of `formats` (a mask over
// kEpManifestFormats) in each, read once per directory and format (`seen`). Only manifests that hold entries are kept.
inline void collectManifestsAbove( const IngestResult& ing, std::uint32_t fileId, std::uint8_t formats, std::vector<std::string>& seen,
                                   std::vector<Manifest>& out )
{
    const std::string_view rel  = rootRelPath( ing, fileId );
    std::filesystem::path  disk = std::filesystem::path( diskPath( ing, fileId ) ).parent_path();
    std::string_view       dir  = rel.substr( 0, rel.rfind( '/' ) == std::string_view::npos ? 0 : rel.rfind( '/' ) );
    while( true )
    {
        for( std::size_t fi = 0; fi < std::size( kEpManifestFormats ); ++fi )
        {
            std::string key = std::string( 1, char( 'a' + fi ) ) + std::string( dir );
            if( ( formats & ( 1U << fi ) ) != 0 && std::ranges::find( seen, key ) == seen.end() )
            {
                seen.push_back( std::move( key ) );
                epTryReadManifest( disk, dir, kEpManifestFormats[fi], out );
            }
        }
        if( dir.empty() )
        {
            break;
        }
        const std::size_t up = dir.rfind( '/' );
        dir  = up == std::string_view::npos ? std::string_view() : dir.substr( 0, up );
        disk = disk.parent_path();
    }
}

inline void appendAttr( std::string& x, std::string_view key, std::string_view val, std::vector<char>& esc )
{
    x += std::format( " {}=\"{}\"", key, escapeXml( val, esc ) );
}

// The indexed file an entry's target names: its module (epModuleFile) for module:attr, its path (epPathFile) otherwise.
inline std::uint32_t epEntryFile( const IngestResult& ing, const Manifest& man, const EpEntry& e, bool& inTree )
{
    if( man.fmt->form == EpTargetForm::ModuleAttr )
    {
        return epModuleFile( ing, man.dir, std::string_view( e.target ).substr( 0, e.target.find( ':' ) ), inTree );
    }
    return epPathFile( ing, man.dir, e.target, inTree );
}

// The definition in the target's file `fs`, by the format's target form; `out` stays Unresolved when there is not exactly one.
inline void epApplyTargetDef( const IngestResult& ing, const Manifest& man, const EpEntry& e, const FileSymbols& fs,
                              std::span<const Binding* const> exports, EpTarget& out )
{
    const auto one = [ & ]( auto&& hit )
    {
        if( std::ranges::count_if( fs, hit ) == 1 )
        {
            out = EpTarget{ EpTargetState::Def, *std::ranges::find_if( fs, hit ) };
        }
    };
    switch( man.fmt->form )
    {
    case EpTargetForm::ModuleAttr:
        if( const std::size_t colon = e.target.find( ':' ); colon != std::string::npos )
        {
            const std::string_view attr = std::string_view( e.target ).substr( colon + 1 );
            one( [ & ]( NodeId id ) { return epAttrNames( ing.symbols[id], attr ); } );
        }
        return;
    case EpTargetForm::BinMain:
        one( [ & ]( NodeId id ) { return epIsMainFn( ing.symbols[id] ); } );
        return;
    case EpTargetForm::FileExport:
        if( const NodeId def = epFileEntryDef( ing, fs, exports ); def != kNoNode )
        {
            out = EpTarget{ EpTargetState::Def, def };
        }
        return;
    }
}

// Each entry's target, resolved: its indexed file (epEntryFile), then ONE pass over the symbols of those files (and, when a
// package.json target is among them, ONE pass over the bindings for their exports): exactly one definition → Def; none or
// several in a file of the tree → Unresolved; no file at all → External.
inline std::vector<std::vector<EpTarget>> resolveEpTargets( const IngestResult& ing, const std::vector<Manifest>& manifests )
{
    std::vector<std::vector<EpTarget>>      targets( manifests.size() );
    std::vector<std::vector<std::uint32_t>> targetFile( manifests.size() );
    std::vector<char>                       wantFile( ing.files.size(), 0 );
    bool                                    wantExports = false;
    for( std::size_t m = 0; m < manifests.size(); ++m )
    {
        for( const EpEntry& e : manifests[m].entries )
        {
            bool                inTree = false;
            const std::uint32_t f      = epEntryFile( ing, manifests[m], e, inTree );
            targetFile[m].push_back( f );
            targets[m].push_back( EpTarget{ inTree ? EpTargetState::Unresolved : EpTargetState::External, kNoNode } );
            if( f != kNoFile )
            {
                wantFile[f] = 1;
                wantExports = wantExports || manifests[m].fmt->form == EpTargetForm::FileExport;
            }
        }
    }
    const SymbolsByFile byFile = symbolsByFile( ing, [ & ]( const Symbol& s ) { return wantFile[ s.fileId ] != 0; },
                                                []( NodeId a, NodeId b ) { return a < b; } );
    std::vector<const Binding*> exports;   // the JsExport bindings of the wanted files, by file id (stable)
    for( const Binding& b : ing.bindings )
    {
        if( wantExports && b.kind == LocalBindKind::JsExport && b.fileId < wantFile.size() && wantFile[ b.fileId ] != 0 )
        {
            exports.push_back( &b );
        }
    }
    std::ranges::stable_sort( exports, {}, &Binding::fileId );
    for( std::size_t m = 0; m < manifests.size(); ++m )
    {
        for( std::size_t k = 0; k < manifests[m].entries.size(); ++k )
        {
            const std::uint32_t f = targetFile[m][k];
            if( f == kNoFile )
            {
                continue;
            }
            const auto fileExports = std::ranges::equal_range( exports, f, {}, &Binding::fileId );
            epApplyTargetDef( ing, manifests[m], manifests[m].entries[k], byFile[f], std::span<const Binding* const>( fileExports.begin(), fileExports.end() ),
                              targets[m][k] );
        }
    }
    return targets;
}

// An implicit-only group (Cargo's inferred package bin: no [[bin]] line names it) adds only the package name to a src/main.rs
// row the answer already shows, so it rides only when the task asks about running a binary: a cue word (run, bin, binary, cli,
// command, executable, launch, main, entry, entrypoint and their plurals and -ing forms), case-folded, as a whole word — words
// split on every byte that is not alphanumeric, '_', '.' or ':', so `next.run` and `axum::serve` are identifiers, not cues — or
// the name of one of the group's entries (`-` and `_` alike, as Cargo's crate names) bounded by bytes that are not a name byte.
inline bool epTaskCuesBinary( std::string_view task, std::span<const std::string* const> names )
{
    static constexpr std::string_view kCues[] = { "run", "runs", "running", "bin", "bins", "binary", "binaries", "cli", "command",
                                                   "commands", "executable", "executables", "launch", "launches", "launching", "main",
                                                   "entry", "entrypoint", "entrypoints" };
    std::string lower;    // the task case-folded: the cue words
    std::string folded;   // and with '-' read as '_': the entry names
    for( const char c : task )
    {
        lower += char( std::tolower( static_cast<unsigned char>( c ) ) );
        folded += c == '-' ? '_' : lower.back();
    }
    const auto fold     = []( char c ) { return c == '-' ? '_' : char( std::tolower( static_cast<unsigned char>( c ) ) ); };
    const auto wordByte = []( char c ) { return std::isalnum( static_cast<unsigned char>( c ) ) || c == '_' || c == '.' || c == ':'; };
    for( std::size_t i = 0; i < lower.size(); )
    {
        std::size_t j = i;
        while( j < lower.size() && wordByte( lower[j] ) )
        {
            ++j;
        }
        std::string_view w = std::string_view( lower ).substr( i, j - i );
        while( !w.empty() && ( w.back() == '.' || w.back() == ':' ) )
        {
            w.remove_suffix( 1 );   // a sentence's full stop or colon ends the word, it does not join it
        }
        if( std::ranges::find( kCues, w ) != std::end( kCues ) )
        {
            return true;
        }
        i = j + 1;
    }
    const auto nameByte = []( char c ) { return std::isalnum( static_cast<unsigned char>( c ) ) || c == '_'; };
    for( const std::string* n : names )
    {
        std::string want;
        for( const char c : *n )
        {
            want += fold( c );
        }
        for( std::size_t at = want.empty() ? std::string::npos : folded.find( want ); at != std::string::npos; at = folded.find( want, at + 1 ) )
        {
            const std::size_t end = at + want.size();
            if( ( at == 0 || !nameByte( folded[at - 1] ) ) && ( end == folded.size() || !nameByte( folded[end] ) ) )
            {
                return true;
            }
        }
    }
    return false;
}

// A (manifest, group) the answer prints.
struct EpPick
{
    std::size_t m;
    std::string group;
};

// The groups that hold a shown row, in the rank order of their first shown target; `total` counts them before the cap.
inline std::vector<EpPick> pickEpGroups( const std::vector<Manifest>& manifests, const std::vector<std::vector<EpTarget>>& targets,
                                         std::span<const NodeId> shown, std::string_view task, std::size_t& total )
{
    // a group whose every entry is implicit rides only on a binary cue in the task (epTaskCuesBinary)
    const auto quiet = [ & ]( std::size_t m, const std::string& g )
    {
        std::vector<const std::string*> names;
        for( const EpEntry& e : manifests[m].entries )
        {
            if( e.group == g && !e.implicit )
            {
                return false;
            }
            if( e.group == g )
            {
                names.push_back( &e.name );
            }
        }
        return !epTaskCuesBinary( task, names );
    };
    std::vector<EpPick> picks;
    for( const NodeId id : shown )
    {
        for( std::size_t m = 0; m < manifests.size(); ++m )
        {
            for( std::size_t k = 0; k < manifests[m].entries.size(); ++k )
            {
                const std::string& g    = manifests[m].entries[k].group;
                const auto         same = [ & ]( const EpPick& p ) { return p.m == m && p.group == g; };
                if( targets[m][k].def == id && !std::ranges::any_of( picks, same ) && !quiet( m, g ) )
                {
                    picks.push_back( EpPick{ m, g } );
                }
            }
        }
    }
    total = picks.size();
    picks.resize( std::min( picks.size(), kForEpGroupRows ) );
    return picks;
}

// used_at= / used_in= / used_capped= used_total= of one group's consumers ("" when none: no attribute, never a guess).
inline void appendEpConsumers( std::string& x, const IngestResult& ing, const flipimpact::SymbolLineIndex& lineIx,
                               std::span<const EpConsumer> cs, std::vector<char>& esc )
{
    if( cs.empty() )
    {
        return;
    }
    std::string at;
    std::string in;
    for( std::size_t i = 0; i < cs.size() && i < kForEpUsedAtRows; ++i )
    {
        at += std::format( "{}{}:{}", i ? " " : "", rootRelPath( ing, cs[i].fileId ), cs[i].line );
        const NodeId host = flipimpact::innermostAtLine( ing, lineIx, cs[i].fileId, cs[i].line );
        const Symbol* h   = host == kNoNode ? nullptr : &ing.symbols[host];
        in += i ? " " : "";
        in += h == nullptr ? std::string( "-" ) : ( h->scope.empty() || h->scope == h->name ) ? h->name : h->scope + "." + h->name;
    }
    appendAttr( x, "used_at", at, esc );
    appendAttr( x, "used_in", in, esc );
    if( cs.size() > kForEpUsedAtRows )
    {
        x += std::format( " used_capped=\"1\" used_total=\"{}\"", cs.size() );
    }
}

// One <e>: the entry as written and what its target resolved to.
inline void appendEpEntry( std::string& x, const IngestResult& ing, const EpEntry& e, const EpTarget& t, std::vector<char>& esc )
{
    x += "<e";
    appendAttr( x, "n", e.name, esc );
    appendAttr( x, "target", e.target, esc );
    if( t.state == EpTargetState::Def )
    {
        const Symbol& s = ing.symbols[ t.def ];
        appendAttr( x, "def", std::format( "{}:{}", rootRelPath( ing, s.fileId ), s.line ), esc );
    }
    else
    {
        x += t.state == EpTargetState::External ? " external=\"1\"" : " unresolved=\"1\"";
    }
    x += "/>";
}

// The innermost definitions around the shown consumer sites: a line index over only the files that hold one.
inline flipimpact::SymbolLineIndex consumerLineIndex( const IngestResult& ing, const std::vector<std::vector<EpConsumer>>& consumers )
{
    std::vector<char> siteFile( ing.files.size(), 0 );
    for( const std::vector<EpConsumer>& cs : consumers )
    {
        for( std::size_t i = 0; i < cs.size() && i < kForEpUsedAtRows; ++i )
        {
            siteFile[ cs[i].fileId ] = 1;
        }
    }
    flipimpact::SymbolLineIndex ix;
    ix.byFile = symbolsByFile( ing, [ & ]( const Symbol& s ) { return siteFile[ s.fileId ] != 0 && s.kind != SymKind::ModuleScope; },
                               [ & ]( NodeId a, NodeId b ) { return ing.symbols[a].line != ing.symbols[b].line ? ing.symbols[a].line < ing.symbols[b].line : a < b; } );
    return ix;
}

// One <ep> element: the group's manifest row, the cap disclosures (the groups cap rides the first element), its consumers, its entries.
inline void appendEpGroup( std::string& x, const IngestResult& ing, const flipimpact::SymbolLineIndex& lineIx, const Manifest& man,
                           const std::vector<EpTarget>& targets, const std::string& group, const std::vector<EpConsumer>& consumers,
                           const std::string& groupsCap, std::vector<char>& esc )
{
    std::vector<std::size_t> ks;   // the group's entries, manifest order
    for( std::size_t k = 0; k < man.entries.size(); ++k )
    {
        if( man.entries[k].group == group )
        {
            ks.push_back( k );
        }
    }
    x += "<ep";
    appendAttr( x, "p", man.rel, esc );
    x += std::format( " l=\"{}\"", man.entries[ ks.front() ].groupLine );
    appendAttr( x, "group", group, esc );
    x += groupsCap;
    x += ks.size() > kForEpEntryRows ? std::format( " entries_capped=\"1\" entries_total=\"{}\"", ks.size() ) : std::string();
    appendEpConsumers( x, ing, lineIx, consumers, esc );
    x += '>';
    for( std::size_t i = 0; i < ks.size() && i < kForEpEntryRows; ++i )
    {
        appendEpEntry( x, ing, man.entries[ ks[i] ], targets[ ks[i] ], esc );
    }
    x += "</ep>";
}

}   // namespace epdetail


inline void collectEpManifestsForShown( const IngestResult& ing, std::span<const NodeId> shown, std::vector<std::string>& seen,
                                        std::vector<epdetail::Manifest>& manifests )
{
    for( const NodeId id : shown )   // the manifests above every shown row whose file kind has a format (kEpManifestFormats)
    {
        if( id >= ing.symbols.size() )
        {
            continue;
        }
        if( const std::uint8_t formats = epFormatsForFile( rootRelPath( ing, ing.symbols[id].fileId ) ); formats != 0 )
        {
            epdetail::collectManifestsAbove( ing, ing.symbols[id].fileId, formats, seen, manifests );
        }
    }
}

// The element(s). `shown` is the answer's ranked head (the rows <sigs> serves, rank order); `task` the --for text (an implicit-only
// Cargo group rides on a binary cue in it, pickEpGroups). Single-root runs only.
inline EpRender renderForEpManifest( const IngestResult& ing, std::span<const NodeId> shown, std::string_view task )
{
    EpRender out;
    if( ing.crawlRoot.empty() || shown.empty() )
    {
        return out;   // a multi-root run has no one root to place a manifest under
    }
    std::vector<std::string>        seenDirs;
    std::vector<epdetail::Manifest> manifests;
    collectEpManifestsForShown( ing, shown, seenDirs, manifests );
    if( manifests.empty() )
    {
        return out;   // no manifest above a shown row: resolveEpTargets and consumerLineIndex would each walk every symbol for nothing
    }
    const std::vector<std::vector<EpTarget>> targets     = epdetail::resolveEpTargets( ing, manifests );
    std::size_t                              groupsTotal = 0;
    const std::vector<epdetail::EpPick>      picks       = epdetail::pickEpGroups( manifests, targets, shown, task, groupsTotal );
    if( picks.empty() )
    {
        return out;   // no group holds a shown row: nothing to scan for consumers, no element to print
    }
    // one consumer scan per distinct group literal of a module:attr format; a Cargo or package.json group ("bin", "main") is a
    // manifest key, no literal code loads it by: not scanned, so its element carries no used_at= (legend: "not scanned")
    const auto                               scanned = [ & ]( const epdetail::EpPick& p ) { return manifests[ p.m ].fmt->form == EpTargetForm::ModuleAttr; };
    std::vector<std::string>                 literals;
    for( const epdetail::EpPick& p : picks )
    {
        if( scanned( p ) && std::ranges::find( literals, p.group ) == literals.end() )
        {
            literals.push_back( p.group );
        }
    }
    const std::vector<std::vector<EpConsumer>> consumers = literals.empty() ? std::vector<std::vector<EpConsumer>>() : findGroupConsumers( ing, literals );
    const flipimpact::SymbolLineIndex          lineIx    = literals.empty() ? flipimpact::SymbolLineIndex() : epdetail::consumerLineIndex( ing, consumers );
    std::vector<char>                          esc;
    const std::vector<EpConsumer>              noConsumers;
    for( std::size_t pi = 0; pi < picks.size(); ++pi )
    {
        const std::string groupsCap = ( pi == 0 && groupsTotal > picks.size() ) ? std::format( " groups_capped=\"1\" groups_total=\"{}\"", groupsTotal ) : std::string();
        epdetail::appendEpGroup( out.xml, ing, lineIx, manifests[ picks[pi].m ], targets[ picks[pi].m ], picks[pi].group,
                                 scanned( picks[pi] ) ? consumers[ std::size_t( std::ranges::find( literals, picks[pi].group ) - literals.begin() ) ] : noConsumers,
                                 groupsCap, esc );
    }
    return out;
}

// The element's legend clauses, present-only beside it: the full and the compact dialect. No "--": they ride inside an XML comment.
inline constexpr std::string_view kForEpManifestLegend =
    "; ep p= l= group=: a manifest entry-point group (setup.cfg [options.entry_points], pyproject [project.entry-points.*], "
    "[project.scripts], [project.gui-scripts], [tool.poetry.plugins.*]/[tool.poetry.scripts], Cargo.toml [[bin]], package.json bin/main) "
    "that registers a shown row, l= the group's line; e n= target=: each entry as written, def=file:line the in-tree definition it names, "
    "external=1 no indexed file is its module or path, unresolved=1 the module, path or name is not exactly one file or definition in the tree; "
    "used_at=file:line used_in=: code that "
    "compares or loads that group's string literal (by literal text, not resolved, so a docstring or a parameter default that quotes it is listed too; a floor); "
    "no used_at= means no such code was found (a Cargo.toml or package.json group is a manifest key, not scanned); used_capped=1 used_total=, entries_capped=1 entries_total=, groups_capped=1 "
    "groups_total=: that list was cut, the total it was cut from";
inline constexpr std::string_view kForCompactEpManifestLegend =
    "; ep p= l= group=: a manifest entry-point group registering a shown row; e n= target= as written, def=file:line in tree, "
    "external=1 module or path not in tree, unresolved=1 not one def; used_at=file:line used_in=: code reading that group literal "
    "(by text, a floor; Cargo.toml/package.json groups not scanned); used_capped=1/entries_capped=1/groups_capped=1 with used_total=/entries_total=/groups_total= if cut";

}   // namespace rw
