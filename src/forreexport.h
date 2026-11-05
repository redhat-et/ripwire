#pragma once
// forreexport.h — RE-EXPORT HOP ROWS on a --for answer (lane alias-import; readout-40 family ALIAS-IMPORT, mf1 shape MF-a:
// "the answer reaches the definition and then stops").
//
// WHY. "Where is ShellError, used in ls.rs, defined — through which re-export hops?" The ranked answer prints the definition
// and stops: the `pub use` / `export { … } from` statements a reader must walk from the use site to it are never rows, because
// they define nothing and call nothing. An agent then greps each prelude and barrel by hand.
//
// WHEN. The task asks where something comes from — a cue word (`defined`, `import`, `export`, `re-export`, `hop(s)`) or the import
// spelling `NAME from <module>` (`verify from hono/jwt`) — or the chain reaches a file the task names (`ls.rs`, a `remove-emphasis`
// directory), or (BARREL-SHORT-KEY) the subject's SHAPE asks it: the task IS one name (a bare subject), or it writes a TS/JS name
// QUALIFIED (`Completions.getCompletionsAtPosition`, `ts.server.Session`), in which case only the chains that prove the qualifier
// print (forreexport.h qualifierProofAt: a namespace hop, a `a.b.ts` file stem or the path's tail; a consumer's `import * as Q` or a
// stray directory only hedges, and a cued task with no proof keeps its chains, q_unmatched="1"). Without one, a definition's re-exports are not what was asked: the fire table showed 25 fires across S1/MF1/LD/LD2
// before this gate, 20 of them on path/orientation questions that gained no asked-for name (angular barrels alone 9 rows, 10 KB).
// WHAT. For each task word that names an in-tree definition (a code-shaped word, or `NAME from <module>`), the re-export statements
// that make THAT definition reachable under another module path, walked outward from the definition (nearest first):
//   Rust  `pub use path::Item;`, `pub use path::{A, B};` (an item), `pub use path::module;` (a module that holds it) and
//         `pub use path::*` (a glob: hedged, glob="1" — the module may not supply the name). The path is resolved the way rustc
//         reads it (`crate` / `self` / `super` / a child module of the file / a crate of the tree by its Cargo name), so two
//         same-named items in two modules keep their module identity; a crate name that two manifests spell is cands="N".
//   TS/JS `export { a } from './m'`, `export { a as b } from './m'` (the row says as=), `export * from './m'` (hedged, glob="1"),
//         NAMESPACE hops (ns=): `export * as X from './m'`, and `import * as X from './m'` with a local `export { X [as Y] }` in the
//         same file (both records already indexed: ModuleAlias "*" + the JsExport clause); a Web spelling then carries its
//         namespace path (Spelling::mods), and a later hop takes its head segment. The module resolved by the import pin's own
//         resolver (resolveJsNamedImportFile, unique-or-nothing).
// A file the task names (`ls.rs`) that imports the definition through one of those spellings adds its own `use`/`import` row
// (u, the start of the chain). Rows only: no row is a call edge, nothing here feeds reaches=, and a type-only re-export is a
// row like any other (it moves a name, not a call).
//
// NOT ON. A definition nothing re-exports (no block); a definition inside a function, impl or inline `mod { }` (its module
// path is not the file's: a disclosed floor; a `pub use` STATEMENT inside an inline `mod { }` is read, with the inline module in
// its path); `src/main.rs` beside a lib.rs and `src/bin/**` (their own binary crates, never the lib's modules); a Rust `pub use a as b` RENAME (counted as_skipped=, not followed: help-wanted
// #445 owns renames); an external target (the walk starts at an in-tree definition, so an outside crate is never a row);
// a namespace import that the file does not export. Cycles terminate (each public spelling is visited once, and a namespace hop
// is never taken twice on one path).
// RIPWIRE_NO_REEXPORT_HOPS (any value) turns it off.

#include "defslookup.h"          // aliasTargetRow — an alias row (model.h AliasTarget) is another name, not the definition a sentence asks for
#include "depdialect.h"          // dependencyDialect — the Web dialect is the unit the ReExport records are written per
#include "docparse.h"            // detail::readWholeFile — the `pub` check and the row's line read the statement's file
#include "fordottedstring.h"     // dotteddetail::displayName — a <shortkey> definition row names the symbol as <dotted> rows do
#include "forliteral.h"          // lit_detail::isConstShaped; hopbody.h renderBodyElement — a CONST-shaped key is <lit>'s; search.h grepCollect/grepEnrich, redact, nextverb
#include "graph.h"               // tomlSectionNames, resolveJsNamedImportFile, lexicalNormalize
#include "infra/namesplit.h"     // isIdentChar
#include "model.h"
#include "serialize.h"           // escapeXml

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <iterator>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <system_error>
#include <tuple>
#include <utility>
#include <vector>

namespace rw
{

inline constexpr std::size_t kReexportNameCap = 3;   // task words served
inline constexpr std::size_t kReexportDefCap  = 2;   // definitions per word that carry a chain
inline constexpr std::size_t kReexportRowCap  = 8;   // hop rows per definition (BFS order); the rest counted in total=
static_assert( kReexportRowCap == 8, "kReexportLegend states the cap (8 shown): move the sentence with the constant" );
inline constexpr std::size_t kReexportUseCap  = 2;   // use-site rows per definition, from task-named files
inline constexpr std::size_t kReexportSpellingCap = 256;   // spellings one walk visits; past it total= is a floor (capped="1")

inline bool forReexportOn()
{
    return std::getenv( "RIPWIRE_NO_REEXPORT_HOPS" ) == nullptr;
}

inline constexpr std::string_view kReexportLegend =
    "<!-- reexports: the statements that re-export a definition the task names, nearest the definition first. def p= l= the "
    "definition, at= its path, total= its rx rows (8 shown; capped=1: the walk stopped at 256 spellings, total= is a floor), same=1 the same rows as a def above; "
    "rx p= l= one `pub use`/`export … from` statement, use= its written path (or from= the module), "
    "at= the path it makes public (vis=restricted: pub(crate)/pub(super)/pub(in …), visible only inside its crate), as= the new name; glob=1 a glob/star hop (hedged: the module may not supply the name); "
    "cands=N the path names N same-named crates (hedged); ns= a namespace hop (`import * as X` then `export { X }`, or `export * as X from`): "
    "the whole module published as X; def q= the qualifier the task wrote the name under (`Q.name`), proven at a hop or the definition's "
    "own file and printed first (when one chain proves every segment, a same-named definition that cannot is not listed); q_by=alias "
    "only a consumer's own `import * as Q` reaches it, q_by=path its file path names Q but an `import * as Q` binds Q to another module, "
    "q_by=dir only directories on its path name Q (all hedged); q_unmatched=1 no "
    "chain proves Q (listed because the task asks where it comes from); u p= l= a task-named file's own import of it (the chain's start); "
    "as_skipped=N renamed re-exports not followed; rows, not call edges -->";

namespace reexport_detail
{

// A public spelling of the definition: Rust = (crate, module path, name); Web = (file, exported name).
struct Spelling
{
    std::uint32_t            crate = kNoFile;   // Rust crate index, or the Web file
    std::vector<std::string> mods;
    std::string              name;
};

struct Row
{
    const Binding* b     = nullptr;
    bool           glob  = false;
    bool           use   = false;   // a task-named file's own import (no new spelling)
    bool           restricted = false;   // Rust `pub(crate)` / `pub(super)` / `pub(in …)`: visible only inside its crate, not a public path
    bool           ns    = false;   // Web NAMESPACE hop: `export * as X from` (b), or `import * as X from` (b) + `export { X }` (exp)
    const Binding* exp   = nullptr; // the `export { X [as Y] }` clause of a paired namespace hop
    std::size_t    cands = 1;
    int            parent = -1;     // the row whose new spelling this row consumed (-1: the definition's own spelling)
    Spelling       at;
};

struct Sources
{
    const IngestResult&                                ing;
    HashMap<std::uint32_t, std::optional<std::string>> text;

    const std::string* of( std::uint32_t f )
    {
        auto [ it, fresh ] = text.try_emplace( f );
        if( fresh )
        {
            it->second = docparse::detail::readWholeFile( diskPath( ing, f ) );
        }
        return it->second ? &*it->second : nullptr;
    }
    std::uint32_t lineOf( std::uint32_t f, std::uint32_t byte )
    {
        const std::string* t = of( f );
        if( t == nullptr || byte > t->size() )
        {
            return 0;
        }
        return std::uint32_t( std::count( t->begin(), t->begin() + byte, '\n' ) ) + 1;
    }
    // The visibility the statement at `byte` is written with: 0 none (or unreadable / not a statement start: reads as private),
    // 1 `pub`, 2 `pub(crate)` / `pub(super)` / `pub(in path)` (visible only inside part of its crate: not a public path).
    int visOf( std::uint32_t f, std::uint32_t byte )
    {
        const std::string* t = of( f );
        if( t == nullptr || byte >= t->size() || !std::string_view( *t ).substr( byte ).starts_with( "pub" ) || byte + 3 >= t->size() )
        {
            return 0;
        }
        std::size_t at = byte + 3;
        if( namesplit::isIdentChar( ( *t )[ at ] ) )
        {
            return 0;
        }
        while( at < t->size() && ( ( *t )[ at ] == ' ' || ( *t )[ at ] == '\t' ) )
        {
            ++at;
        }
        return at < t->size() && ( *t )[ at ] == '(' ? 2 : 1;
    }
    // Does file `f` bind `name` with `extern crate x as name;`? (no use record is written for it: a path through `name` is the
    // crate x, never a same-named crate of the tree)
    bool externCrateAs( std::uint32_t f, std::string_view name )
    {
        const std::string* t = of( f );
        for( std::size_t at = t == nullptr ? std::string::npos : t->find( "extern crate" ); at != std::string::npos; at = t->find( "extern crate", at + 1 ) )
        {
            const std::string_view stmt = std::string_view( *t ).substr( at, std::min( t->find( ';', at ), t->size() ) - at );
            const std::size_t      as   = stmt.rfind( " as " );
            if( as != std::string_view::npos && stmt.substr( as + 4 ) == name )
            {
                return true;
            }
        }
        return false;
    }
};

inline std::string joinPath( const std::vector<std::string>& mods, std::string_view name, std::string_view sep )
{
    std::string out;
    for( const std::string& m : mods )
    {
        out.append( m ).append( sep );
    }
    return out.append( name );
}

inline std::vector<std::string> splitColons( std::string_view path )
{
    const std::vector<std::string_view> segs = rustPathSegments( path );   // resolve.h
    return { segs.begin(), segs.end() };
}

// ── Rust: crates, module paths, `use` paths ─────────────────────────────────────────────────────────────────────────────────
// An inline `mod name { … }` of a file: its body spans [start, end).
struct InlineMod
{
    std::uint32_t start = 0;
    std::uint32_t end   = 0;
    std::string   name;
};

struct RustCrates
{
    std::vector<std::string>                          names;      // crate index -> its (first) Cargo name, `_` for `-`
    std::vector<std::uint32_t>                        crateOf;    // file -> crate index (kNoFile: outside every crate's source root)
    std::vector<std::vector<std::string>>             modOf;      // file -> module path below its crate root (the FILE's own path)
    std::vector<std::vector<InlineMod>>               inlineOf;   // file -> its inline `mod { }` bodies, outermost first (by start)
    HashMap<std::string, std::vector<std::uint32_t>> byName;      // Cargo name -> crate indices (two manifests may spell one)
    HashMap<std::string, char>                        modules;    // "<crate>#a::b" -> the module exists (a file, or an inline body)
    HashMap<std::string, std::vector<const Binding*>> imported;   // "<file>#name" -> the file's `use` records that bind `name` (no globs)

    [[nodiscard]] bool hasModule( std::uint32_t crate, const std::vector<std::string>& mods ) const
    {
        return modules.contains( std::to_string( crate ) + "#" + joinPath( mods, "", "::" ) );
    }
    // The module path in force at `byte` of file `f`: the file's module path, then each inline mod whose body holds the byte.
    // A `pub use` inside `pub mod private { }` publishes `<file path>::private::Name`, never `<file path>::Name`.
    [[nodiscard]] std::vector<std::string> modsAt( std::uint32_t f, std::uint32_t byte ) const
    {
        std::vector<std::string> mods = modOf[ f ];
        for( const InlineMod& m : inlineOf[ f ] )
        {
            if( m.start < byte && byte < m.end )
            {
                mods.push_back( m.name );
            }
        }
        return mods;
    }
    [[nodiscard]] static std::string importKey( std::uint32_t f, std::string_view name )
    {
        return std::to_string( f ).append( "#" ).append( name );
    }
};

// The module path of `rel` below the crate root file `root` (`src/lib.rs`): `src/a/b.rs` and `src/a/b/mod.rs` -> [a, b], the
// root itself -> []. nullopt for a file outside the root's directory (tests/, examples/, build.rs: their own crate roots) and for
// the package's OTHER crate roots: `src/main.rs` beside a lib.rs and every `src/bin/**` file are binary crates, not modules of
// the lib (a private `struct Widget` in main.rs is not the lib's `Widget`).
inline std::optional<std::vector<std::string>> rustModulePath( std::string_view rel, std::string_view root )
{
    const std::size_t      slash = root.rfind( '/' );
    const std::string_view dir   = slash == std::string_view::npos ? std::string_view() : root.substr( 0, slash + 1 );
    if( rel == root )
    {
        return std::vector<std::string>{};
    }
    if( !rel.starts_with( dir ) || !rel.ends_with( ".rs" ) )
    {
        return std::nullopt;
    }
    std::string_view below = rel.substr( dir.size(), rel.size() - dir.size() - 3 );
    if( below == "main" || below.starts_with( "bin/" ) )
    {
        return std::nullopt;
    }
    std::vector<std::string> mods;
    for( std::size_t at = 0; at <= below.size(); )
    {
        const std::size_t end = std::min( below.find( '/', at ), below.size() );
        mods.emplace_back( below.substr( at, end - at ) );
        at = end + 1;
    }
    if( !mods.empty() && mods.back() == "mod" )
    {
        mods.pop_back();
    }
    return mods;
}

// The inline `mod name { … }` bodies (queries/rust/tags.scm `@definition.module`: a module is the one Rust SymKind::Other) and the
// `use` records that bind a name, per file. An inline body is a module of its crate like a file (a 2018 path may start at it).
inline void indexRustInlineMods( const IngestResult& ing, RustCrates& rc )
{
    for( const Symbol& s : ing.symbols )
    {
        if( s.kind == SymKind::Other && dependencyDialect( s.lang ) == DepDialect::Rust && s.fileId < rc.crateOf.size() && rc.crateOf[ s.fileId ] != kNoFile
            && s.endByte > s.sigStartByte )
        {
            rc.inlineOf[ s.fileId ].push_back( InlineMod{ s.sigStartByte, s.endByte, s.name } );
        }
    }
    for( std::uint32_t f = 0; f < rc.inlineOf.size(); ++f )
    {
        std::vector<InlineMod>& inl = rc.inlineOf[ f ];
        std::ranges::sort( inl, []( const InlineMod& a, const InlineMod& b ) { return a.start != b.start ? a.start < b.start : a.end > b.end; } );
        for( const InlineMod& m : inl )
        {
            std::vector<std::string> path = rc.modsAt( f, m.start );
            path.push_back( m.name );
            rc.modules.try_emplace( std::to_string( rc.crateOf[ f ] ) + "#" + joinPath( path, "", "::" ), '\0' );
        }
    }
    // a `use` inside a function body binds only inside that body (train 42b T-2): never an import of the file or of a module
    std::vector<std::vector<std::pair<std::uint32_t, std::uint32_t>>> fnBodies( rc.crateOf.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && dependencyDialect( s.lang ) == DepDialect::Rust && s.fileId < rc.crateOf.size()
            && rc.crateOf[ s.fileId ] != kNoFile && s.endByte > s.sigEndByte )
        {
            fnBodies[ s.fileId ].emplace_back( s.sigEndByte, s.endByte );
        }
    }
    const auto inFnBody = [ & ]( const Binding& b )
    {
        return std::ranges::any_of( fnBodies[ b.fileId ], [ & ]( const auto& r ) { return r.first <= b.startByte && b.startByte < r.second; } );
    };
    for( const Binding& b : ing.bindings )
    {
        if( b.kind == LocalBindKind::TypeImport && b.var != "*" && b.fileId < rc.crateOf.size() && rc.crateOf[ b.fileId ] != kNoFile && !inFnBody( b ) )
        {
            rc.imported[ RustCrates::importKey( b.fileId, b.var ) ].push_back( &b );
        }
    }
}

inline RustCrates buildRustCrates( const IngestResult& ing, const HashMap<std::string, std::uint32_t>& files )
{
    RustCrates                          rc;
    HashMap<std::string, std::uint32_t> crateAtDir;   // manifest directory ("" or "a/b/") -> crate index
    std::vector<std::string>            roots;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view rel = rootRelPath( ing, f );
        if( rel != "Cargo.toml" && !rel.ends_with( "/Cargo.toml" ) )
        {
            continue;
        }
        const std::string_view            dir  = rel.substr( 0, rel.size() - 10 );
        const std::optional<std::string>  text = docparse::detail::readWholeFile( diskPath( ing, f ) );
        std::vector<std::string>          names, libPath;
        if( text )
        {
            tomlSectionNames( *text, { "[package]", "[lib]" }, names );
            tomlSectionNames( *text, { "[lib]" }, libPath, "path" );
        }
        std::string root = std::string( dir ) + ( libPath.empty() ? "src/lib.rs" : lexicalNormalize( libPath.front() ) );
        if( !files.contains( root ) && libPath.empty() )
        {
            root = std::string( dir ) + "src/main.rs";
        }
        const std::uint32_t k = std::uint32_t( roots.size() );
        roots.push_back( std::move( root ) );
        rc.names.emplace_back();
        for( std::string& n : names )
        {
            std::replace( n.begin(), n.end(), '-', '_' );
            if( rc.names.back().empty() )
            {
                rc.names.back() = n;
            }
            std::vector<std::uint32_t>& owners = rc.byName[ n ];
            if( std::ranges::find( owners, k ) == owners.end() )
            {
                owners.push_back( k );
            }
        }
        crateAtDir.try_emplace( std::string( dir ), k );
    }
    rc.crateOf.assign( ing.files.size(), kNoFile );
    rc.modOf.resize( ing.files.size() );
    rc.inlineOf.resize( ing.files.size() );
    for( std::uint32_t f = 0; f < ing.files.size() && !roots.empty(); ++f )
    {
        const std::string_view rel = rootRelPath( ing, f );
        if( !rel.ends_with( ".rs" ) )
        {
            continue;
        }
        for( std::size_t slash = rel.rfind( '/' );; slash = rel.rfind( '/', slash - 1 ) )   // the nearest manifest above the file
        {
            const std::string_view dir = slash == std::string_view::npos ? std::string_view() : rel.substr( 0, slash + 1 );
            if( const auto hit = crateAtDir.find( std::string( dir ) ); hit != crateAtDir.end() )
            {
                if( std::optional<std::vector<std::string>> mods = rustModulePath( rel, roots[ hit->second ] ) )
                {
                    rc.crateOf[ f ] = hit->second;
                    rc.modOf[ f ]   = std::move( *mods );
                }
                break;
            }
            if( slash == std::string_view::npos || slash == 0 )
            {
                break;
            }
        }
        if( rc.crateOf[ f ] == kNoFile )
        {
            continue;
        }
        std::vector<std::string> prefix;
        rc.modules.try_emplace( std::to_string( rc.crateOf[ f ] ) + "#", '\0' );
        for( const std::string& m : rc.modOf[ f ] )
        {
            prefix.push_back( m );
            rc.modules.try_emplace( std::to_string( rc.crateOf[ f ] ) + "#" + joinPath( prefix, "", "::" ), '\0' );
        }
    }
    indexRustInlineMods( ing, rc );
    return rc;
}

// Where a `use` path written at `byte` of file `f` points: the crates it may name (empty = outside the tree, refused, or
// unreadable) and the whole segment path below that crate's root. `crate`/`self`/`super` stay in the file's crate (relative to
// the module in force at `byte`, inline `mod { }` bodies included); a first segment the file itself binds (a `use` record of the
// file, in scope here) is read through that import; a first segment that is a child module of the current module is local (2018
// paths); otherwise it is a crate of the tree by its Cargo name. `boundHere` = the first segment is bound by a statement this
// function cannot read (`extern crate x as y`): refused, never a same-named crate.
struct RustTarget
{
    std::vector<std::uint32_t> crates;
    std::vector<std::string>   segs;
};

inline RustTarget resolveRustPath( const RustCrates& rc, std::uint32_t f, std::uint32_t byte, std::string_view path, bool boundHere = false, int depth = 0 )
{
    RustTarget                     t;
    const std::vector<std::string> segs = splitColons( path );
    if( segs.empty() || segs.front().empty() || f >= rc.crateOf.size() || depth > 4 )
    {
        return t;
    }
    const std::uint32_t      own  = rc.crateOf[ f ];
    std::vector<std::string> base = own == kNoFile ? std::vector<std::string>{} : rc.modsAt( f, byte );
    std::vector<std::string> child = base;
    child.push_back( segs.front() );
    const bool crateHead = segs.front() == "crate" || segs.front() == "self" || segs.front() == "super";
    if( !crateHead && !path.starts_with( "::" ) )
    {
        if( boundHere )
        {
            return t;   // `extern crate x as segs.front();` — the crate x, which this walk does not follow
        }
        if( const auto hit = rc.imported.find( RustCrates::importKey( f, segs.front() ) ); hit != rc.imported.end() )
        {
            const Binding* only    = nullptr;
            std::size_t    visible = 0;
            for( const Binding* b : hit->second )   // the imports in scope at `byte`: those of the SAME module (a child `mod` inherits none)
            {
                if( rc.modsAt( f, b->startByte ) == base && splitColons( b->importedName ).front() != segs.front() )   // train 42b T-2: exact module
                {
                    ++visible;
                    only = b;
                }
            }
            if( visible > 1 || ( visible == 1 && only->var != only->typeName ) )
            {
                return t;   // two imports bind the name, or it is a rename (#445): not followed, never a same-named crate
            }
            if( visible == 1 )
            {
                std::string through = only->importedName;
                for( std::size_t i = 1; i < segs.size(); ++i )
                {
                    through.append( "::" ).append( segs[ i ] );
                }
                return resolveRustPath( rc, f, only->startByte, through, false, depth + 1 );
            }
        }
    }
    if( !crateHead && ( own == kNoFile || path.starts_with( "::" ) || !rc.hasModule( own, child ) ) )
    {
        const auto hit = rc.byName.find( segs.front() );   // a crate of the tree by its Cargo name (else outside the tree)
        if( hit != rc.byName.end() )
        {
            t.crates = hit->second;
            t.segs.assign( segs.begin() + 1, segs.end() );
        }
        return t;
    }
    if( own == kNoFile )
    {
        return t;
    }
    std::size_t next = crateHead ? 1 : 0;
    if( segs.front() == "crate" )
    {
        base.clear();
    }
    else if( segs.front() == "super" )
    {
        for( next = 0; next < segs.size() && segs[ next ] == "super"; ++next )
        {
            if( base.empty() )
            {
                return t;
            }
            base.pop_back();
        }
    }
    t.crates = { own };
    t.segs   = std::move( base );
    t.segs.insert( t.segs.end(), segs.begin() + std::ptrdiff_t( next ), segs.end() );
    return t;
}

// ── the walk ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
struct Walk
{
    const IngestResult&                         ing;
    Sources&                                    src;
    const RustCrates&                           rc;
    const HashMap<std::string, std::uint32_t>&  files;
    HashMap<std::string, std::vector<const Binding*>> rustByVar;     // Rust TypeImport records by bound name ("*" = globs)
    HashMap<std::string, std::vector<const Binding*>> webByTaken;    // Web ReExport records by the name they take ("*" = stars, namespaces)
    // Web paired NAMESPACE hops by the module FILE they import: `import * as X from './m'` (first) + `export { X [as Y] }` (second)
    HashMap<std::uint32_t, std::vector<std::pair<const Binding*, const Binding*>>> webNsByTarget;
    HashMap<std::string, std::vector<const Binding*>> webAliasByVar;  // Web `import * as X from` records by X (a consumer alias proves Q=X)
    HashMap<const Binding*, RustTarget>               rustTargets;   // memo
    HashMap<const Binding*, std::uint32_t>            webTargets;    // memo: the module's file, kNoFile when not unique
    std::vector<char>                                 taskFile;      // file -> the task names it (use-site rows)

    const RustTarget& rustTarget( const Binding* b )
    {
        auto [ it, fresh ] = rustTargets.try_emplace( b );
        if( fresh )
        {
            const std::string_view head = std::string_view( b->importedName ).substr( 0, b->importedName.find( "::" ) );
            it->second = resolveRustPath( rc, b->fileId, b->startByte, b->importedName, src.externCrateAs( b->fileId, head ) );
        }
        return it->second;
    }
    std::uint32_t webTarget( const Binding* b )
    {
        auto [ it, fresh ] = webTargets.try_emplace( b, kNoFile );
        if( fresh )
        {
            const auto [ file, ambiguous ] = resolveJsNamedImportFile( lexicalNormalize( rootRelPath( ing, b->fileId ) ), b->typeName, files, nullptr, b->fileId );
            it->second = ambiguous ? kNoFile : file;
        }
        return it->second;
    }

    // Rust: does record `b` re-export spelling `s`, and under what new spelling? `asSkipped` counts a matching rename.
    std::optional<Row> rustMatch( const Binding* b, const Spelling& s, std::size_t& asSkipped )
    {
        const RustTarget& t = rustTarget( b );
        if( std::ranges::find( t.crates, s.crate ) == t.crates.end() )
        {
            return std::nullopt;
        }
        const std::uint32_t g = b->fileId;
        Row                 row{ .b = b, .cands = t.crates.size() };
        row.at.crate = rc.crateOf[ g ];
        row.at.name  = s.name;
        row.at.mods  = rc.modsAt( g, b->startByte );   // the FILE's path plus any inline `mod { }` the statement sits in
        const bool renamed = b->var != "*" && b->var != b->typeName;
        if( b->var == "*" )
        {
            if( t.segs != s.mods )
            {
                return std::nullopt;
            }
            row.glob = true;
            return row;
        }
        std::vector<std::string> item = s.mods;
        item.push_back( s.name );
        if( t.segs == item && b->typeName == s.name )
        {
            if( renamed )
            {
                ++asSkipped;
                return std::nullopt;
            }
            return row;
        }
        if( t.segs.empty() || t.segs.size() > s.mods.size() || !std::equal( t.segs.begin(), t.segs.end(), s.mods.begin() ) || b->typeName != t.segs.back() )
        {
            return std::nullopt;
        }
        if( renamed )
        {
            ++asSkipped;
            return std::nullopt;
        }
        row.at.mods.push_back( b->var );   // a module re-export: the rest of the path rides below the new module name
        row.at.mods.insert( row.at.mods.end(), s.mods.begin() + std::ptrdiff_t( t.segs.size() ), s.mods.end() );
        return row;
    }
};

// Web: does record `b` re-export spelling `s` (file + namespace path + exported name)? A Web spelling's mods are the namespace
// path it is reached under (`Completions.getCompletionsAtPosition`: mods [Completions]); the statement takes its head segment.
inline std::optional<Row> webMatch( Walk& w, const Binding* b, const Spelling& s )
{
    if( w.webTarget( b ) != s.crate )
    {
        return std::nullopt;
    }
    Row row{ .b = b };
    row.at.crate = b->fileId;
    row.at.mods  = s.mods;
    row.at.name  = s.name;
    if( b->importedName == "*" )
    {
        row.glob = b->var == "*";   // `export * from`: the same spelling, hedged; `export * as X from`: a namespace hop
        row.ns   = !row.glob;
        if( row.ns )
        {
            row.at.mods.insert( row.at.mods.begin(), b->var );
        }
        return row;
    }
    std::string& head = row.at.mods.empty() ? row.at.name : row.at.mods.front();
    if( b->importedName != head )   // `export { a [as b] } from`: takes the head segment by name, publishes it as b
    {
        return std::nullopt;
    }
    head = b->var;
    return row;
}
// Web: the paired namespace hops of the module file `s.crate` (`import * as X from` it, then `export { X [as Y] }`): each
// publishes `Y.<s>` from the importing file.
inline void webNsRows( const Walk& w, const Spelling& s, std::vector<Row>& out )
{
    const auto hit = w.webNsByTarget.find( s.crate );
    for( const auto& [ alias, exp ] : hit == w.webNsByTarget.end() ? std::vector<std::pair<const Binding*, const Binding*>>{} : hit->second )
    {
        Row row{ .b = alias, .ns = true, .exp = exp };
        row.at.crate = alias->fileId;
        row.at.mods  = s.mods;
        row.at.mods.insert( row.at.mods.begin(), exp->var );
        row.at.name = s.name;
        out.push_back( std::move( row ) );
    }
}

inline std::string spellingKey( const Spelling& s )
{
    return std::to_string( s.crate ) + "#" + joinPath( s.mods, s.name, "::" );
}

// How strongly a written qualifier Q (`Q.leaf`) is proven at a spelling; a higher level wins. Dir and Alias are HEDGED: they may keep
// a candidate, never make one exact, and never hide an unproven one.
enum class QProof : std::uint8_t
{
    None,
    Dir,      // each Q segment is SOME directory (or the stem) of the path, not its own tail: a coincidence (src/utils/legacy/old.ts)
    Path,     // a Strong PATH proof (stem, tail, package file) of Q's leading segments while an in-tree `import * as Q0` binds Q's
              // first segment to a module that does not reach the definition: the tree's own binding contradicts the file name
    Alias,    // only a consumer's own `import * as Q from M` reaches it (M resolves to the spelling's file; nothing exports Q)
    Strong,   // the stem or the path's own tail, a package file's directory, every owner-scope segment, or a namespace hop spells Q
};

struct Chain
{
    const Symbol*    def = nullptr;
    bool             rust = false;
    Spelling         start;
    std::vector<Row> rows;   // BFS order
    std::vector<Row> uses;
    std::size_t      asSkipped = 0;
    bool             capped    = false;   // the walk stopped at kReexportSpellingCap spellings: total= is a floor
    std::vector<std::string> q;           // the qualifier the task wrote the name under (Web only; empty: none)
    int              qRow      = -2;      // where q is proven best: -1 the definition's own file, K the row whose spelling it is, -2 not proven
    QProof           qLevel    = QProof::None;
};

// The file stem of `rel` (`src/a/ts.Completions.ts` -> `ts.Completions`; `x.d.ts` -> `x`) and its directory segments.
inline std::string_view reexportStem( std::string_view rel )
{
    const std::size_t slash = rel.rfind( '/' );
    std::string_view  base  = rel.substr( slash == std::string_view::npos ? 0 : slash + 1 );
    for( const std::string_view ext : { std::string_view( ".d.ts" ), std::string_view( ".d.mts" ), std::string_view( ".d.cts" ) } )
    {
        if( base.ends_with( ext ) )
        {
            return base.substr( 0, base.size() - ext.size() );
        }
    }
    const std::size_t dot = base.rfind( '.' );
    return dot == std::string_view::npos || dot == 0 ? base : base.substr( 0, dot );
}

// THE QUALIFIER RULE (one rule for the re-export rows and the SHORT-KEY leaf rung). A name written `Q.leaf` is reached under Q at a
// spelling (file F, namespace or owner path P) when Q ends with P and EVERY segment before that is accounted for by F itself:
//   Strong  the segments, joined by `.`, are F's stem or a dot-suffix of it (`ts.server` for `ts.server.ts`; `Completions` for
//           `ts.Completions.ts`); or they are the path's own tail, stem last (`pkg.mod` for `pkg/mod.py`); or F is a package file
//           (`index`, `__init__`, `mod`, any Go file) and they are its directories' tail (`utils` for `src/utils/index.ts`).
//   Dir     each segment is the stem or SOME directory of F, out of order or with others between (`utils` for
//           `src/utils/legacy/old.ts`): something closer (`legacy`, `old`) is unexplained, so it is a lead, hedged.
//   None    otherwise (a same-named definition elsewhere is never picked by its leaf alone). Case-sensitive.
// `boundElsewhere`: an in-tree `import * as Q0` binds Q's first segment and none of its modules reaches the definition, so a Strong
// proof that rests on the path for any segment (rest > 0) is only Path (hedged); a namespace path that spells all of Q (rest = 0) is
// itself a binding and stays Strong.
inline QProof qualifierProofAt( std::string_view rel, const std::vector<std::string>& mods, const std::vector<std::string>& q, bool boundElsewhere = false )
{
    if( q.empty() || q.size() < mods.size() || !std::equal( mods.begin(), mods.end(), q.end() - std::ptrdiff_t( mods.size() ) ) )
    {
        return QProof::None;
    }
    const std::size_t rest = q.size() - mods.size();
    if( rest == 0 )
    {
        return QProof::Strong;
    }
    const std::string_view stem = reexportStem( rel );
    std::string            joined;
    for( std::size_t i = 0; i < rest; ++i )
    {
        joined.append( i ? "." : "" ).append( q[ i ] );
    }
    const QProof path = boundElsewhere ? QProof::Path : QProof::Strong;
    if( stem == joined || ( stem.size() > joined.size() && stem.ends_with( joined ) && stem[ stem.size() - joined.size() - 1 ] == '.' ) )
    {
        return path;
    }
    std::vector<std::string_view> segs;   // the directories, then the stem
    for( std::size_t at = 0, slash = rel.find( '/' ); slash != std::string_view::npos; at = slash + 1, slash = rel.find( '/', at ) )
    {
        segs.push_back( rel.substr( at, slash - at ) );
    }
    segs.push_back( stem );
    const auto tailIs = [ & ]( std::size_t drop )   // Q's rest is the path's last `rest` segments before the last `drop`
    { return segs.size() >= rest + drop && std::equal( q.begin(), q.begin() + std::ptrdiff_t( rest ), segs.end() - std::ptrdiff_t( drop + rest ) ); };
    const bool package = stem == "index" || stem == "__init__" || stem == "mod" || rel.ends_with( ".go" );
    if( tailIs( 0 ) || ( package && tailIs( 1 ) ) )
    {
        return path;
    }
    const bool everyDir = std::all_of( q.begin(), q.begin() + std::ptrdiff_t( rest ), [ & ]( const std::string& seg ) { return std::ranges::find( segs, seg ) != segs.end(); } );
    return everyDir ? QProof::Dir : QProof::None;
}

// A consumer's own alias: some Web file does `import * as Q0 from M`, M resolves to `file`, and the rest of Q is the spelling's
// namespace path (`utils.formatDate` for `import * as utils from '../helpers'`). Hedged: the alias is local to that consumer.
inline QProof aliasProofAt( Walk& w, std::uint32_t file, const std::vector<std::string>& mods, const std::vector<std::string>& q )
{
    const auto hit = q.size() == mods.size() + 1 && std::equal( mods.begin(), mods.end(), q.begin() + 1 ) ? w.webAliasByVar.find( q.front() ) : w.webAliasByVar.end();
    if( hit == w.webAliasByVar.end() )
    {
        return QProof::None;
    }
    return std::ranges::any_of( hit->second, [ & ]( const Binding* b ) { return w.webTarget( b ) == file; } ) ? QProof::Alias : QProof::None;
}

// Whether the tree binds Q's first segment elsewhere: some Web file does `import * as Q0 from M` and no such M resolves to a file in
// `reached` (the definition's own file and every file that re-exports it). An unresolved M (a package outside the tree) binds Q0
// elsewhere too. False when nothing aliases Q0.
inline bool qualifierBoundElsewhere( Walk& w, const std::vector<std::string>& q, const std::vector<std::uint32_t>& reached )
{
    const auto hit = q.empty() ? w.webAliasByVar.end() : w.webAliasByVar.find( q.front() );
    return hit != w.webAliasByVar.end() && std::ranges::none_of( hit->second, [ & ]( const Binding* b ) { return std::ranges::find( reached, w.webTarget( b ) ) != reached.end(); } );
}

// The files a chain's spellings sit in: the definition's own, then every row's (a Web spelling's crate is its file).
inline std::vector<std::uint32_t> chainFiles( const Chain& c )
{
    std::vector<std::uint32_t> files{ c.def->fileId };
    for( const Row& r : c.rows )
    {
        files.push_back( r.at.crate );
    }
    return files;
}

// The statements that may re-export spelling `s`: by its name, every glob, and (Rust) by each module segment of its path.
inline std::vector<const Binding*> reexportCandidates( const Walk& w, bool rust, const Spelling& s )
{
    std::vector<const Binding*> cand;
    const HashMap<std::string, std::vector<const Binding*>>& by = rust ? w.rustByVar : w.webByTaken;
    const auto take = [ & ]( const std::string& key )
    {
        if( const auto hit = by.find( key ); hit != by.end() )
        {
            cand.insert( cand.end(), hit->second.begin(), hit->second.end() );
        }
    };
    take( !rust && !s.mods.empty() ? s.mods.front() : s.name );   // Web: a namespace-path spelling is taken by its head segment
    take( "*" );
    for( const std::string& m : rust ? s.mods : std::vector<std::string>{} )
    {
        take( m );
    }
    std::ranges::sort( cand );
    cand.erase( std::unique( cand.begin(), cand.end() ), cand.end() );
    return cand;
}

// A matching statement that publishes nothing (not `pub`, or outside every crate root) is a use-site row when the task names its file.
inline void noteReexportUse( const Walk& w, Chain& c, Row row )
{
    const Binding* b = row.b;
    if( b->fileId < w.taskFile.size() && w.taskFile[ b->fileId ] && c.uses.size() < kReexportUseCap
        && std::ranges::none_of( c.uses, [ & ]( const Row& r ) { return r.b == b; } ) )
    {
        row.use = true;
        c.uses.push_back( std::move( row ) );
    }
}

// Web use sites: a task-named file's named import of any spelling the walk reached.
inline void webReexportUses( Walk& w, Chain& c, const HashMap<std::string, char>& reached )
{
    for( const Binding& b : w.ing.bindings )
    {
        if( c.uses.size() >= kReexportUseCap || b.kind != LocalBindKind::JsImport || b.fileId >= w.taskFile.size() || !w.taskFile[ b.fileId ] || b.importedName.empty() )
        {
            continue;
        }
        const std::uint32_t file = w.webTarget( &b );
        if( file != kNoFile && reached.contains( spellingKey( Spelling{ .crate = file, .name = b.importedName } ) ) )
        {
            c.uses.push_back( Row{ .b = &b, .use = true } );
        }
    }
}

// Breadth-first from the definition: each statement that re-exports a reached spelling is a row and publishes a new spelling
// (visited once: cycles terminate); a statement already printed for another spelling is not printed twice.
// The rows that publish spelling `s` one hop further (a use site that does not publish is noted on the chain instead), and for Web
// the namespace hops of `s`'s module file.
inline std::vector<Row> publishingHops( Walk& w, Chain& c, const Spelling& s )
{
    std::vector<Row> found;
    for( const Binding* b : reexportCandidates( w, c.rust, s ) )
    {
        std::optional<Row> row = c.rust ? w.rustMatch( b, s, c.asSkipped ) : webMatch( w, b, s );
        const int  vis       = row && c.rust ? w.src.visOf( b->fileId, b->startByte ) : 1;
        const bool publishes = row && vis > 0 && ( !c.rust || w.rc.crateOf[ b->fileId ] != kNoFile );
        if( publishes )
        {
            row->restricted = vis == 2;
            found.push_back( std::move( *row ) );
        }
        else if( row )
        {
            noteReexportUse( w, c, std::move( *row ) );
        }
    }
    if( !c.rust )
    {
        webNsRows( w, s, found );
    }
    return found;
}

// A use site imports a spelling's HEAD segment (a namespace, or the name itself): the keys webReexportUses matches against.
inline HashMap<std::string, char> spellingHeads( const std::vector<Spelling>& frontier )
{
    HashMap<std::string, char> heads;
    for( const Spelling& s : frontier )
    {
        heads.try_emplace( spellingKey( Spelling{ .crate = s.crate, .name = s.mods.empty() ? s.name : s.mods.front() } ), '\0' );
    }
    return heads;
}

// Is namespace hop `row` already on the path that published the spelling it consumes (`path`: that spelling's row)? Taking it again
// only grows the namespace path (`A.B.A.B…` for `a.ts: export * as B from './b'` + `b.ts: export * as A from './a'`): a cycle.
inline bool namespaceHopOnPath( const Chain& c, int path, const Row& row )
{
    for( int i = path; i >= 0; i = c.rows[ std::size_t( i ) ].parent )
    {
        if( c.rows[ std::size_t( i ) ].b == row.b && c.rows[ std::size_t( i ) ].exp == row.exp )
        {
            return true;
        }
    }
    return false;
}

inline void walkChain( Walk& w, Chain& c )
{
    HashMap<std::string, char> seen;
    seen.try_emplace( spellingKey( c.start ), '\0' );
    std::vector<Spelling> frontier{ c.start };
    std::vector<int>      frontierRow{ -1 };   // the row that published frontier[i] (-1: the definition's own spelling)
    std::size_t at = 0;
    for( ; at < frontier.size() && frontier.size() < kReexportSpellingCap; ++at )
    {
        for( Row& row : publishingHops( w, c, Spelling( frontier[ at ] ) ) )
        {
            if( ( row.ns && namespaceHopOnPath( c, frontierRow[ at ], row ) ) || !seen.try_emplace( spellingKey( row.at ), '\0' ).second )
            {
                continue;
            }
            row.parent = frontierRow[ at ];
            frontier.push_back( row.at );
            const auto same = std::ranges::find_if( c.rows, [ & ]( const Row& r ) { return r.b == row.b && r.exp == row.exp; } );
            frontierRow.push_back( same == c.rows.end() ? int( c.rows.size() ) : int( same - c.rows.begin() ) );
            if( same == c.rows.end() )
            {
                c.rows.push_back( std::move( row ) );
            }
        }
    }
    c.capped = at < frontier.size();   // the loop ended on the cap with spellings still unvisited
    if( !c.rust )
    {
        webReexportUses( w, c, spellingHeads( frontier ) );
    }
}

// The task split at blanks, quotes, brackets (one break set for both loops: a break the skip did not eat would never advance),
// trailing `,.?:` trimmed: `ls.rs`, `hono/jwt`, `remove-emphasis`, `from`.
inline std::vector<std::string_view> reexportTaskTokens( std::string_view task )
{
    static constexpr std::string_view kBreak = " \t\n`'\"()[]<>";
    std::vector<std::string_view>     tokens;
    for( std::size_t at = 0; at < task.size(); )
    {
        at                   = std::min( task.find_first_not_of( kBreak, at ), task.size() );
        const std::size_t end = std::min( task.find_first_of( kBreak, at ), task.size() );
        std::string_view  tok = task.substr( at, end - at );
        while( !tok.empty() && ( tok.back() == ',' || tok.back() == '.' || tok.back() == '?' || tok.back() == ':' ) )
        {
            tok.remove_suffix( 1 );
        }
        if( !tok.empty() )
        {
            tokens.push_back( tok );
        }
        at = end;
    }
    return tokens;
}

// A token spelled as a module (`hono/jwt`, `@angular/core`, `./x`), not a word or a qualified symbol (`Editor::backspace`).
inline bool reexportModuleLike( std::string_view m )
{
    const char first = m.empty() ? '\0' : m.front();
    return first == '@' || first == '.' || m.contains( '/' );
}

// `NAME from M` with M spelled as a module: the import spelling, not `path from A to B`.
inline bool reexportFromModule( const std::vector<std::string_view>& tokens, std::size_t i )
{
    return i + 2 < tokens.size() && tokens[ i + 1 ] == "from" && reexportModuleLike( tokens[ i + 2 ] );
}

// Does the task ask where something comes from (a definition's location, an import or re-export, its hops)?
inline bool reexportTaskCued( const std::vector<std::string_view>& tokens )
{
    static constexpr std::string_view kCue[] = { "defined", "re-export", "re-exports", "re-exported", "reexport", "export", "exports", "exported",
                                                 "import", "imports", "imported", "hop", "hops" };
    for( std::size_t i = 0; i < tokens.size(); ++i )
    {
        if( std::ranges::find( kCue, tokens[ i ] ) != std::end( kCue ) || reexportFromModule( tokens, i ) )
        {
            return true;
        }
    }
    return false;
}

// A token spelled as a QUALIFIED name: identifier segments joined by `.` or `::` (`Completions.getCompletionsAtPosition`,
// `ts.server.Session`, `a::b::Item`), at least two, none empty. A `this.`/`self.` chain is a member access, not a qualifier, and a
// segment that is not an identifier (`ls.rs` passes the shape but its leaf is no code word, so it names nothing). Empty when not.
inline std::vector<std::string_view> reexportQualifiedSegments( std::string_view tok )
{
    std::vector<std::string_view> segs;
    for( std::size_t at = 0; at <= tok.size(); )
    {
        std::size_t end = at;
        while( end < tok.size() && ( namesplit::isIdentChar( tok[ end ] ) || tok[ end ] == '$' ) )
        {
            ++end;
        }
        if( end == at )
        {
            return {};
        }
        segs.push_back( tok.substr( at, end - at ) );
        if( end == tok.size() )
        {
            break;
        }
        const std::size_t sep = tok.substr( end ).starts_with( "::" ) ? 2 : tok[ end ] == '.' ? 1 : 0;
        if( sep == 0 )
        {
            return {};
        }
        at = end + sep;
    }
    if( segs.size() < 2 || segs.front() == "this" || segs.front() == "self" )
    {
        return {};
    }
    return segs;
}

// A task word that may name a definition, with the qualifier it was written under (`Completions` for
// `Completions.getCompletionsAtPosition`; empty when bare).
struct ReexportTaskName
{
    std::string              name;
    std::vector<std::string> q;
};

// The task's words that may name a definition: code-shaped (an upper-case letter, `_` or `$` inside, or a capital first
// letter) or written `NAME from M` with M a module spelling. The LAST word of a qualified token keeps its qualifier.
// A word written as code: an upper-case first letter, or an upper-case letter, `_` or `$` past it (`Widget`, `getX`, `max_len`).
inline bool reexportCodeShapedWord( std::string_view w )
{
    const auto upper = []( char ch ) { return ch >= 'A' && ch <= 'Z'; };
    return ( !w.empty() && upper( w.front() ) ) ||
           std::ranges::any_of( w.substr( std::min<std::size_t>( 1, w.size() ) ), [ & ]( char ch ) { return upper( ch ) || ch == '_' || ch == '$'; } );
}

inline std::vector<ReexportTaskName> reexportTaskNames( std::string_view task )
{
    const std::vector<std::string_view> tokens = reexportTaskTokens( task );
    std::vector<ReexportTaskName>       out;
    const auto add = [ & ]( std::string_view w, std::vector<std::string> q )
    {
        if( out.size() < kReexportNameCap && w.size() >= 3 && std::ranges::none_of( out, [ & ]( const ReexportTaskName& n ) { return n.name == w; } ) )
        {
            out.push_back( ReexportTaskName{ std::string( w ), std::move( q ) } );
        }
    };
    for( std::size_t i = 0; i < tokens.size(); ++i )
    {
        const std::string_view              tok  = tokens[ i ];
        const std::vector<std::string_view> segs = reexportQualifiedSegments( tok );
        for( std::size_t at = 0; at < tok.size(); )   // the identifier words inside one token (`Owner::name`, `a/b`)
        {
            std::size_t end = at;
            while( end < tok.size() && ( namesplit::isIdentChar( tok[ end ] ) || tok[ end ] == '$' ) )
            {
                ++end;
            }
            const std::string_view w = tok.substr( at, end - at );
            const bool code = reexportCodeShapedWord( w );
            // the LEAF of a qualified spelling is a name whatever its case (`Utils.formatDate`, `api.v1.handler`): the qualified form
            // is itself the code shape. A file or host suffix (`main.go`, `pkg.json`) is not a leaf.
            const bool leaf = !segs.empty() && end == tok.size() && !lit_detail::isFileOrHostSuffix( w );
            if( code || leaf || ( end == tok.size() && at == 0 && reexportFromModule( tokens, i ) ) )
            {
                add( w, leaf ? std::vector<std::string>( segs.begin(), segs.end() - 1 ) : std::vector<std::string>{} );
            }
            at = end + 1;
        }
    }
    return out;
}

// Files the task names: a token with an extension by basename (`ls.rs`), a `-`/`_` token by a directory segment (`remove-emphasis`).
inline std::vector<char> reexportTaskFiles( const IngestResult& ing, const std::vector<std::string_view>& tokens )
{
    std::vector<std::string_view> bases, dirs;
    for( const std::string_view tok : tokens )
    {
        if( tok.size() >= 4 && tok.find( '.' ) != std::string_view::npos && tok.find( '/' ) == std::string_view::npos )
        {
            bases.push_back( tok );
        }
        else if( tok.size() >= 4 && tok.find_first_of( "-_" ) != std::string_view::npos && tok.find_first_of( "./" ) == std::string_view::npos )
        {
            dirs.push_back( tok );
        }
    }
    std::vector<char> out( ing.files.size(), 0 );
    for( std::uint32_t f = 0; f < ing.files.size() && !( bases.empty() && dirs.empty() ); ++f )
    {
        const std::string_view rel   = rootRelPath( ing, f );
        const std::size_t      slash = rel.rfind( '/' );
        const std::string_view base  = rel.substr( slash == std::string_view::npos ? 0 : slash + 1 );
        bool                   hit   = std::ranges::find( bases, base ) != bases.end();
        for( std::size_t at = 0; !hit && slash != std::string_view::npos && at < slash; )
        {
            const std::size_t end = std::min( rel.find( '/', at ), slash );
            hit                   = std::ranges::find( dirs, rel.substr( at, end - at ) ) != dirs.end();
            at                    = end + 1;
        }
        out[ f ] = char( hit );
    }
    return out;
}

inline bool reexportDefKind( const Symbol& s )
{
    switch( s.kind )
    {
        case SymKind::Function:
        case SymKind::Class:
        case SymKind::Struct:
        case SymKind::Interface:
        case SymKind::Var:
        case SymKind::NamedType:
        case SymKind::Alias:
        case SymKind::FuncType: return s.scope.empty();
        default: return false;
    }
}

// The rows printed, at most kReexportRowCap: walk order, except that a QUALIFIED chain prints the hops that reach the qualifier
// first (nearest the definition first), so the cap never cuts the path the task's spelling names.
inline std::vector<std::size_t> reexportRowOrder( const Chain& c )
{
    std::vector<std::size_t> order;
    for( int i = c.qRow; i >= 0; i = c.rows[ std::size_t( i ) ].parent )
    {
        order.insert( order.begin(), std::size_t( i ) );
    }
    for( std::size_t i = 0; i < c.rows.size(); ++i )
    {
        if( std::ranges::find( order, i ) == order.end() )
        {
            order.push_back( i );
        }
    }
    order.resize( std::min( order.size(), kReexportRowCap ) );
    return order;
}

// A row's name attribute: ns= the namespace a hop publishes the module under, as= a Web rename ("" when neither).
inline std::pair<std::string_view, std::string_view> reexportRowName( const Chain& c, const Row& r )
{
    if( r.ns )
    {
        return { "ns", r.exp != nullptr ? r.exp->var : r.b->var };
    }
    const bool renamed = !c.rust && !r.use && !r.glob && r.b->var != r.b->importedName;
    return renamed ? std::pair<std::string_view, std::string_view>{ "as", r.b->var } : std::pair<std::string_view, std::string_view>{};
}

// The def row's qualifier: q= as the task wrote it, then the hedge when no spelling proves every segment (q_by=alias|path|dir, or
// q_unmatched="1" when nothing proves it). "" for an unqualified name.
inline std::string reexportQualifierAttrs( const Chain& c, std::vector<char>& esc )
{
    if( c.q.empty() )
    {
        return {};
    }
    std::string out = std::string( " q=\"" ).append( escapeXml( joinPath( std::vector<std::string>( c.q.begin(), c.q.end() - 1 ), c.q.back(), "." ), esc ) ).append( "\"" );
    return out.append( c.qLevel == QProof::Strong ? ""
                       : c.qLevel == QProof::None ? " q_unmatched=\"1\""
                       : c.qLevel == QProof::Alias ? " q_by=\"alias\""
                       : c.qLevel == QProof::Path  ? " q_by=\"path\""
                                                   : " q_by=\"dir\"" );
}

// The statements a chain prints (its rows, then its use rows): two definitions reached through the same ones print them once.
inline std::vector<const Binding*> chainStatements( const Chain& c )
{
    std::vector<const Binding*> sig;
    for( const std::vector<Row>* part : { &c.rows, &c.uses } )
    {
        std::ranges::transform( *part, std::back_inserter( sig ), []( const Row& r ) { return r.b; } );
    }
    return sig;
}

// The XML writer: one <def> row per printed chain, its rx rows and its u rows (a chain that repeats an earlier one's statements
// prints its def row alone, same="1").
struct ReexportXml
{
    const IngestResult&                      ing;
    const RustCrates&                        rc;
    Sources&                                 src;
    std::string                              out;
    std::vector<char>                        esc;
    std::vector<std::vector<const Binding*>> printed;   // the row statements of every chain already printed

    void attr( std::string_view k, std::string_view v )
    {
        out.append( " " ).append( k ).append( "=\"" ).append( escapeXml( v, esc ) ).append( "\"" );
    }
    void num( std::string_view k, std::size_t v )
    {
        out.append( " " ).append( k ).append( "=\"" ).append( std::to_string( v ) ).append( "\"" );
    }
    std::string spelled( const Spelling& s ) const
    {
        return rc.names[ s.crate ] + "::" + joinPath( s.mods, s.name, "::" );
    }
    void row( const Chain& c, const Row& r, std::string_view tag )
    {
        out.append( "<" ).append( tag );
        attr( "p", rootRelPath( ing, r.b->fileId ) );
        num( "l", src.lineOf( r.b->fileId, r.b->startByte ) );
        if( c.rust )
        {
            attr( "use", r.b->var == "*" ? r.b->importedName + "::*" : r.b->importedName );
        }
        else
        {
            attr( "from", r.b->typeName );
        }
        if( c.rust && !r.use )
        {
            attr( "at", spelled( r.at ) );
            out.append( r.restricted ? " vis=\"restricted\"" : "" );
        }
        if( const auto [ k, v ] = reexportRowName( c, r ); !k.empty() )
        {
            attr( k, v );
        }
        out.append( r.glob ? " glob=\"1\"" : "" );
        if( r.cands > 1 )
        {
            num( "cands", r.cands );
        }
        out.append( "/>" );
    }
    // false when the chain's statements were already printed (its def row then says same="1")
    bool defRow( const Chain& c )
    {
        out.append( out.empty() ? std::string( "<reexports>" ).append( kReexportLegend ) : std::string() ).append( "<def" );
        attr( "n", c.def->name );
        attr( "p", rootRelPath( ing, c.def->fileId ) );
        num( "l", c.def->line );
        if( c.rust )
        {
            attr( "at", spelled( c.start ) );
        }
        out.append( reexportQualifierAttrs( c, esc ) );
        num( "total", c.rows.size() );
        out.append( c.capped ? " capped=\"1\"" : "" );
        if( c.asSkipped > 0 )
        {
            num( "as_skipped", c.asSkipped );
        }
        std::vector<const Binding*> sig = chainStatements( c );   // a same-named definition reached through the very same statements prints them once
        const bool same = std::ranges::find( printed, sig ) != printed.end();
        out.append( same ? " same=\"1\"/>" : "/>" );
        if( !same )
        {
            printed.push_back( std::move( sig ) );
        }
        return !same;
    }
    void chain( const Chain& c )
    {
        if( !defRow( c ) )
        {
            return;
        }
        for( const std::size_t i : reexportRowOrder( c ) )
        {
            row( c, c.rows[ i ], "rx" );
        }
        for( const Row& u : c.uses )
        {
            row( c, u, "u" );
        }
    }
};

// The package a `from <module>` names (`@angular/core` -> core, `hono/jwt` -> jwt; "" when the task names none): a definition
// the task asks about then lives under a directory of that name, so a same-named item of another package is not it.
inline std::string_view reexportFromPackage( const std::vector<std::string_view>& tokens )
{
    for( std::size_t i = 0; i + 1 < tokens.size(); ++i )
    {
        if( tokens[ i ] == "from" && reexportModuleLike( tokens[ i + 1 ] ) )
        {
            const std::string_view m = tokens[ i + 1 ];
            return m.substr( m.rfind( '/' ) == std::string_view::npos ? 0 : m.rfind( '/' ) + 1 );
        }
    }
    return {};
}

// The file map the Web module resolver reads: root-relative normalized path -> file.
inline HashMap<std::string, std::uint32_t> webFileMap( const IngestResult& ing )
{
    HashMap<std::string, std::uint32_t> files;
    files.reserve( ing.files.size() );
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        files.emplace( lexicalNormalize( rootRelPath( ing, f ) ), f );
    }
    return files;
}

// The definitions a task word names, in a language whose re-exports this file reads (Rust; the Web dialect), inside the
// package the task names (`from @angular/core`: a path with a `core/` directory) when it names one.
inline std::vector<const Symbol*> reexportDefs( const IngestResult& ing, const std::vector<ReexportTaskName>& names, std::string_view package )
{
    std::vector<const Symbol*> defs;
    const std::string          dir = std::string( "/" ).append( package ).append( "/" );
    for( const Symbol& s : ing.symbols )
    {
        const DepDialect d    = dependencyDialect( s.lang );
        const bool       lang = d == DepDialect::Rust || d == DepDialect::Web;
        const bool inPkg = package.empty() || std::string( "/" ).append( rootRelPath( ing, s.fileId ) ).find( dir ) != std::string::npos;
        if( lang && inPkg && reexportDefKind( s ) && std::ranges::any_of( names, [ & ]( const ReexportTaskName& n ) { return n.name == s.name; } ) )
        {
            defs.push_back( &s );
        }
    }
    return defs;
}

// Is the statement at `byte` of file `f` a LOCAL export clause, `export { … }` with no `from` (the clause form of a JsExport record; a
// re-export clause names another module's binding, never this file's namespace import)? Unreadable reads as no.
inline bool localExportClause( Sources& src, std::uint32_t f, std::uint32_t byte )
{
    const std::string* t = src.of( f );
    if( t == nullptr || byte >= t->size() || !std::string_view( *t ).substr( byte ).starts_with( "export" ) )
    {
        return false;
    }
    const std::size_t open  = t->find_first_not_of( " \t\r\n", byte + 6 );
    const std::size_t close = open == std::string::npos || ( *t )[ open ] != '{' ? std::string::npos : t->find( '}', open );
    if( close == std::string::npos )
    {
        return false;
    }
    const std::size_t next = t->find_first_not_of( " \t\r\n", close + 1 );
    return next == std::string::npos || !std::string_view( *t ).substr( next ).starts_with( "from" )
        || ( next + 4 < t->size() && namesplit::isIdentChar( ( *t )[ next + 4 ] ) );
}

// The paired NAMESPACE hops: a file that does `import * as X from './m'` and exports X with a local `export { X [as Y] }` publishes
// m's whole namespace as Y. Both records are already indexed (ModuleAlias "*" and the JsExport clause); the module must resolve to
// ONE file. Only this proven shape is a hop: an import with no local export, or an export of a name no namespace import binds, is not.
inline void indexWebNamespaceHops( const IngestResult& ing, Walk& w )
{
    HashMap<std::string, const Binding*>   byKey;
    for( const Binding& b : ing.bindings )
    {
        if( b.kind == LocalBindKind::ModuleAlias && b.importedName == "*" && !b.isFromAssignment && dependencyDialect( langOfPath( rootRelPath( ing, b.fileId ) ) ) == DepDialect::Web )
        {
            byKey.try_emplace( std::to_string( b.fileId ) + "#" + b.var, &b );
            w.webAliasByVar[ b.var ].push_back( &b );
        }
    }
    for( const Binding& b : ing.bindings )
    {
        if( b.kind != LocalBindKind::JsExport || b.importedName.empty() || byKey.empty() )
        {
            continue;
        }
        const auto alias = byKey.find( std::to_string( b.fileId ) + "#" + b.importedName );
        if( alias == byKey.end() || !localExportClause( w.src, b.fileId, b.startByte ) )
        {
            continue;
        }
        const std::uint32_t target = w.webTarget( alias->second );
        if( target != kNoFile )
        {
            w.webNsByTarget[ target ].emplace_back( alias->second, &b );
        }
    }
}

// The candidate statements by the name they bind or take: Rust `use` records (a rename also under the name it takes, to be
// counted as_skipped=), Web ReExport records by the name they take ("*" = globs / stars).
inline void indexReexportRecords( const IngestResult& ing, bool rust, bool web, Walk& w )
{
    for( const Binding& b : ing.bindings )
    {
        if( rust && b.kind == LocalBindKind::TypeImport && b.fileId < ing.files.size() && rootRelPath( ing, b.fileId ).ends_with( ".rs" ) )
        {
            w.rustByVar[ b.var ].push_back( &b );
            if( b.var != "*" && b.var != b.typeName )
            {
                w.rustByVar[ b.typeName ].push_back( &b );
            }
        }
        else if( web && b.kind == LocalBindKind::ReExport )
        {
            w.webByTaken[ b.importedName ].push_back( &b );
        }
    }
    if( web )
    {
        indexWebNamespaceHops( ing, w );
    }
}

// A Web chain walked for a QUALIFIED task name: the strongest proof of the qualifier over its spellings (Chain::qLevel) and the first
// spelling that gives it (Chain::qRow): the definition's own file, then the rows in walk order.
inline void proveChainQualifier( Walk& w, Chain& c )
{
    const bool bound = qualifierBoundElsewhere( w, c.q, chainFiles( c ) );
    const auto at    = [ & ]( std::uint32_t file, const std::vector<std::string>& mods )
    { return std::max( qualifierProofAt( rootRelPath( w.ing, file ), mods, c.q, bound ), aliasProofAt( w, file, mods, c.q ) ); };
    c.qLevel = at( c.def->fileId, {} );
    c.qRow   = c.qLevel == QProof::None ? -2 : -1;
    for( std::size_t i = 0; i < c.rows.size() && c.qLevel != QProof::Strong; ++i )
    {
        if( const QProof l = at( c.rows[ i ].at.crate, c.rows[ i ].at.mods ); l > c.qLevel )
        {
            c.qLevel = l;
            c.qRow   = int( i );
        }
    }
}

// Every chain of the definitions named `n.name` that has a hop: the stronger qualifier proof first, then one reaching a task-named
// file, then the longer. A Web name the task QUALIFIED keeps only the Strong chains when one exists (a same-named definition elsewhere
// is a decoy); otherwise every chain, the hedged ones first (renderForReexports prints an unproven one only when a cue WORD asks
// where the name comes from, `where is utils.formatDate defined`: a qualifier nothing proves never drops the only definition).
// The chain of definition `d` walked from its own spelling; a Web chain under a written qualifier `q` is proven against it (qRow).
inline Chain walkedChain( Walk& w, const Symbol* d, bool rust, const std::vector<std::string>& q )
{
    Chain c{ .def = d, .rust = rust };
    c.start = rust ? Spelling{ w.rc.crateOf[ d->fileId ], w.rc.modOf[ d->fileId ], d->name } : Spelling{ .crate = d->fileId, .name = d->name };
    walkChain( w, c );
    if( !rust && !q.empty() )
    {
        c.q = q;
        proveChainQualifier( w, c );
    }
    return c;
}

// Chains with the stronger qualifier proof first, then use rows, then the longer walk.
inline bool chainBefore( const Chain& a, const Chain& b )
{
    if( a.qLevel != b.qLevel )
    {
        return a.qLevel > b.qLevel;
    }
    return a.uses.size() != b.uses.size() ? a.uses.size() > b.uses.size() : a.rows.size() > b.rows.size();
}

inline std::vector<Chain> reexportChains( Walk& w, const std::vector<const Symbol*>& defs, const ReexportTaskName& n )
{
    std::vector<Chain> chains;
    for( const Symbol* d : defs )
    {
        const bool rust = dependencyDialect( d->lang ) == DepDialect::Rust;
        if( d->name != n.name || ( rust && w.rc.crateOf[ d->fileId ] == kNoFile ) )
        {
            continue;
        }
        Chain c = walkedChain( w, d, rust, n.q );
        if( !c.rows.empty() )
        {
            chains.push_back( std::move( c ) );
        }
    }
    const bool strong = std::ranges::any_of( chains, []( const Chain& c ) { return c.qLevel == QProof::Strong; } );
    std::erase_if( chains, [ & ]( const Chain& c ) { return !c.q.empty() && strong && c.qLevel != QProof::Strong; } );
    std::ranges::stable_sort( chains, chainBefore );
    return chains;
}

// Print the first kReexportDefCap chains of one task word that may print: a chain prints when the task is cued, the name was
// qualified, or it carries a use row; an UNPROVEN qualified chain only under a cue word (a bare `Q.leaf` prints proven chains only).
// Returns the def rows printed.
inline std::size_t printReexportChains( ReexportXml& xml, const std::vector<Chain>& chains, bool cued, bool wordCued )
{
    std::size_t printed = 0;
    for( std::size_t k = 0; k < chains.size() && k < kReexportDefCap; ++k )
    {
        const Chain& c        = chains[ k ];
        const bool   unproven = !c.q.empty() && c.qLevel == QProof::None;
        if( ( unproven && !wordCued ) || !( cued || !c.q.empty() || !c.uses.empty() ) )
        {
            continue;
        }
        xml.chain( c );
        ++printed;
    }
    return printed;
}

}   // namespace reexport_detail

// CR pre-pass 42b: a token budget is a request the block must obey, so under one the rows are NOT printed (they sit outside
// est_tokens). A one-line marker names how many definitions carry a chain; the legend sentence holds no double dash.
inline std::string reexportHeldMarker( std::size_t defs )
{
    return "<!-- reexports held=\"budget\": a token budget is set, so the re-export rows are not printed (they sit outside est_tokens); "
           "defs= definitions carry a chain: ask again without the token budget for the rows -->"
           "<reexports held=\"budget\" defs=\"" + std::to_string( defs ) + "\"/>";
}

// The <reexports> block for `task` ("" when no task word names a definition that something re-exports; `held`: a token budget is
// set, so a marker stands in for the rows).
inline std::string renderForReexports( const IngestResult& ing, std::string_view task, bool held = false )
{
    using namespace reexport_detail;
    const std::vector<ReexportTaskName> names  = reexportTaskNames( task );
    const std::vector<std::string_view> tokens = reexportTaskTokens( task );
    const std::vector<const Symbol*>    defs   = names.empty() ? std::vector<const Symbol*>{} : reexportDefs( ing, names, reexportFromPackage( tokens ) );
    if( defs.empty() )
    {
        return {};
    }
    // CR nitpick (review 5712563408, forreexport.h:1025): no cue word and no task-named file means no chain can print (a chain prints
    // when cued, or when it carries a use row, and a use row is only noted from a task-named file): return before the file map and
    // the Cargo.toml reads
    // BARREL-SHORT-KEY: the SUBJECT'S SHAPE cues it too, not only a word: a task that IS one name (a bare subject: where it comes from
    // is part of what it asks) and a QUALIFIED name (`Completions.getCompletionsAtPosition`: the qualifier is a namespace path a
    // reader must walk, and only the chain that proves it prints)
    const bool        bare      = tokens.size() == 1;
    const bool        wordCued  = reexportTaskCued( tokens );
    const bool        cued      = wordCued || bare;   // otherwise only a chain that reaches a task-named file prints
    const bool        qualified = std::ranges::any_of( names, []( const ReexportTaskName& n ) { return !n.q.empty(); } );
    std::vector<char> taskFiles = reexportTaskFiles( ing, tokens );
    if( !cued && !qualified && std::ranges::none_of( taskFiles, []( char c ) { return c != 0; } ) )
    {
        return {};
    }
    const auto dialectOf = []( DepDialect want ) { return [ want ]( const Symbol* d ) { return dependencyDialect( d->lang ) == want; }; };
    const bool rust      = std::ranges::any_of( defs, dialectOf( DepDialect::Rust ) );
    const bool web       = std::ranges::any_of( defs, dialectOf( DepDialect::Web ) );
    const HashMap<std::string, std::uint32_t> files = webFileMap( ing );
    const RustCrates rc = rust ? buildRustCrates( ing, files ) : RustCrates{ .crateOf = std::vector<std::uint32_t>( ing.files.size(), kNoFile ) };
    Sources          src{ ing, {} };
    Walk             w{ ing, src, rc, files, {}, {}, {}, {}, {}, {}, std::move( taskFiles ) };
    indexReexportRecords( ing, rust, web, w );
    ReexportXml xml{ ing, rc, src, {}, {}, {} };
    std::size_t printedDefs = 0;   // the def rows printed (the held marker's count)
    for( const ReexportTaskName& name : names )
    {
        printedDefs += printReexportChains( xml, reexportChains( w, defs, name ), cued, wordCued );
    }
    if( xml.out.empty() )
    {
        return xml.out;
    }
    return held ? reexportHeldMarker( printedDefs ) : xml.out.append( "</reexports>" );
}

// ── SHORT-KEY-FOR (lane barrel-short-key): the fallback ladder of a name-exact route that resolved no definition ─────────────────
// WHY. `--for=ColumnPtr` / `--for=Completions.getCompletionsAtPosition` routes name-exact and then finds no definition: the answer was
// reason="no_candidates", an empty <sigs> and no next= (1.2 KB that says nothing), the worst outcome for an agent, although a dotted
// leaf, a longer definition name or a declaration line the index did not store (`using ColumnPtr = …`, `use … as ExprType`) is
// one call away. WHAT. <shortkey of=X found="0" rungs= next=> just before </ctx>, outside est_tokens (its own allowance: no
// auto-served body pays for it), each rung named:
//   leaf      X written `Q.leaf` / `Q::leaf`: the definitions named leaf that PROVE every segment of Q (qualifierProofAt, ownerProof:
//             the owner path, the file stem or path tail, or a TS/JS re-export hop; a consumer's `import * as Q` or a stray directory
//             is a hedged proof). One fully proven = exact="1" and the ladder stops; several = exact="0" cands=; only hedged ones =
//             exact="0" with q_by=alias|dir; none = q_unmatched="1" with the same-leaf definitions listed, hedged.
//   substring definition names containing the key (at least kShortKeyMinSubstring bytes), never exact.
//   literal   DECLARATION-SHAPED source lines of the key (an allowlist: `using X =`, `typedef … X;`, `type X`, `#define X`, `as X` on an
//             import/use line, `const|let|var|static X`, `X =`/`X: T =` at column 0), never called a definition; a CONST-shaped key is
//             the <lit> block's (held="lit"). Other lines holding the word are not rows (next= --grep).
// Every shortkey carries a next=. RIPWIRE_NO_SHORT_KEY (any value) turns it off; a token budget prints a held marker.
inline constexpr std::size_t kShortKeyRows          = 6;   // rows per rung (a runaway guard; total= counts all)
static_assert( kShortKeyRows == 6, "kShortKeyLegend states the cap (6 shown): move the sentence with the constant" );
inline constexpr std::size_t kShortKeyMinSubstring  = 4;   // a shorter key matches too many names to be a lead
inline constexpr std::size_t kShortKeyLineBytes     = 200; // a literal row's line is cut here (an ellipsis marks it)
inline constexpr std::size_t kShortKeyBodyBytes     = 8192;   // the exact leaf's body is cut at a line end past this (a runaway guard, disclosed)
static_assert( kShortKeyBodyBytes == 8192, "kShortKeyLegend states the body cut (8192 bytes): move the sentence with the constant" );

inline bool forShortKeyOn()
{
    return std::getenv( "RIPWIRE_NO_SHORT_KEY" ) == nullptr;
}

inline constexpr std::string_view kShortKeyLegend =
    "<!-- shortkey: the task names X, the route read it as a name (name-exact) and no definition resolved (from=sentence: the route read "
    "the task as words, X is its one code-shaped name and no definition of X resolved); the ladder below says what "
    "the index holds, each rung named, none of it a definition of X unless exact=1. rungs= the rungs run, in order. "
    "rung n=leaf: X written Q.leaf; kept= the definitions named leaf that prove every segment of Q (q_by=scope: its owner path; file: "
    "its file stem or path tail, never for a member; ns: a TS/JS re-export hop publishes it under Q; alias: only a consumer's own "
    "`import * as Q`; path: its file path names Q but an `import * as Q` binds Q to another module; dir: only directories on its path; "
    "alias, path and dir are hedged and kept only when nothing proves Q fully), of= all named leaf; exact=1 one "
    "fully proven (the ladder stops), cands=N several (hedged), q_unmatched=1 none proves Q (the rows are same-leaf definitions, NOT "
    "the one asked). "
    "rung n=substring: definitions whose name contains key (exact=0 always). rung n=literal: declaration-shaped source lines of key "
    "(shape=using|typedef|type|define|import-as|const|assign; in= the enclosing definition), not indexed as definitions; "
    "held=lit: the lit block lists this key. total= all matches, 6 shown; floor=1: the scan stopped early, counts are floors. "
    "d n= t= p= l=: a definition row; ld p= l= shape=: a line row; b: the exact leaf's body (the expand shape; cut past 8192 bytes "
    "with truncated=1 lines= next=). next= the call that continues. The block is not in est_tokens -->";

namespace shortkey_detail
{

using reexport_detail::QProof;

// The name inside `name-exact(X)` at the head of the route note ("" when the route is not name-exact).
inline std::string_view routeName( std::string_view routeNote )
{
    static constexpr std::string_view kHead = "name-exact(";
    if( !routeNote.starts_with( kHead ) )
    {
        return {};
    }
    const std::size_t close = routeNote.find( ')', kHead.size() );
    return close == std::string_view::npos ? std::string_view{} : routeNote.substr( kHead.size(), close - kHead.size() );
}

// A definition row, the shared order: source before test/doc, then path, then line.
inline bool rowBefore( const IngestResult& ing, const Symbol* a, const Symbol* b )
{
    const auto key = [ & ]( const Symbol* s ) { return std::tuple( int( pathTierOf( rootRelPath( ing, s->fileId ) ) ), rootRelPath( ing, s->fileId ), s->line ); };
    return key( a ) < key( b );
}

struct Proven
{
    const Symbol*    s = nullptr;
    std::string_view by;   // scope | file | ns (Strong) | alias | dir (hedged)
    QProof           level = QProof::None;
};

// A stored owner scope as path segments (`a::b::Cls`, `pkg.Cls` -> a b Cls; a scope that is not a plain dotted name stays whole).
inline std::vector<std::string> scopeSegments( std::string_view scope )
{
    const std::vector<std::string_view> segs = reexport_detail::reexportQualifiedSegments( scope );
    return segs.empty() ? std::vector<std::string>{ std::string( scope ) } : std::vector<std::string>( segs.begin(), segs.end() );
}

// Q against a definition's OWNER path (its stored scope, or the type whose line span holds it): Q names the owner's tail (`Cls` or
// `b::Cls` for a::b::Cls), or Q ends with the whole owner and the segments before it are proven by the file (qualifierProofAt). The
// last segment alone never proves a longer Q (`Wrong.Fmt3.leaf` is not `Fmt3.leaf`).
inline QProof ownerProof( const IngestResult& ing, const std::vector<std::string>& owner, std::uint32_t file, const std::vector<std::string>& q, bool boundElsewhere )
{
    if( !owner.empty() && owner.size() >= q.size() && std::equal( q.begin(), q.end(), owner.end() - std::ptrdiff_t( q.size() ) ) )
    {
        return QProof::Strong;
    }
    return owner.empty() ? QProof::None : reexport_detail::qualifierProofAt( rootRelPath( ing, file ), owner, q, boundElsewhere );
}

// The Web walk the leaf rung needs (built once, only when a Web definition is left to prove through its chain).
struct LeafWalk
{
    const IngestResult&                                ing;
    std::optional<HashMap<std::string, std::uint32_t>> files;
    std::optional<reexport_detail::RustCrates>         rc;
    std::optional<reexport_detail::Sources>            src;
    std::optional<reexport_detail::Walk>               w;

    reexport_detail::Walk& get()
    {
        if( !w )
        {
            files.emplace( reexport_detail::webFileMap( ing ) );
            rc.emplace( reexport_detail::RustCrates{ .crateOf = std::vector<std::uint32_t>( ing.files.size(), kNoFile ) } );
            src.emplace( reexport_detail::Sources{ ing, {} } );
            w.emplace( reexport_detail::Walk{ ing, *src, *rc, *files, {}, {}, {}, {}, {}, {}, std::vector<char>( ing.files.size(), 0 ) } );
            reexport_detail::indexReexportRecords( ing, /*rust=*/false, /*web=*/true, *w );
        }
        return *w;
    }
};

// The strongest proof of Q for definition `s` (named leaf): its owner path, its file, and for a Web definition its re-export chain
// (namespace hops, a consumer's alias), or for a member the chain of its owner type under the rest of Q. A MEMBER (`member`: inside a
// type's or function's line span, stored with no owner scope) gets only its owner-path proofs, never the bare file proof (`utils.f`
// cannot name a method of a class in utils.ts). `qAliased`: some Web file does `import * as Q0` for Q's first segment; a path proof
// is then only Path (hedged) unless one of those modules reaches this definition (qualifierBoundElsewhere).
inline Proven leafProof( const IngestResult& ing, const Symbol& s, const std::vector<const Symbol*>& owners, const std::vector<std::string>& q, LeafWalk& lw, bool member, bool qAliased )
{
    using namespace reexport_detail;
    Proven     best{ &s, {}, QProof::None };
    const auto consider = [ & ]( QProof l, std::string_view by )
    {
        if( l > best.level )
        {
            best = Proven{ &s, by, l };
        }
    };
    const bool web = dependencyDialect( s.lang ) == DepDialect::Web;
    std::vector<const Symbol*> mine;   // the owners whose line span holds s (a member the index stores with no owner scope)
    for( const Symbol* o : s.scope.empty() && s.kind != SymKind::Class ? owners : std::vector<const Symbol*>{} )
    {
        if( o->fileId == s.fileId && s.line > o->line && s.line < o->line + o->loc )
        {
            mine.push_back( o );
        }
    }
    const bool           ownChain = s.scope.empty() && !member && web && reexportDefKind( s );
    std::optional<Chain> chain;   // s's own chain, walked once (its qualifier proof applies the same bound rule)
    bool                 bound = false;
    if( qAliased )
    {
        std::vector<std::uint32_t> reached{ s.fileId };
        if( ownChain )
        {
            chain.emplace( walkedChain( lw.get(), &s, /*rust=*/false, q ) );
            reached = chainFiles( *chain );
        }
        for( const Symbol* o : q.size() > 1 && web ? mine : std::vector<const Symbol*>{} )
        {
            if( reexportDefKind( *o ) )
            {
                const std::vector<std::uint32_t> more = chainFiles( walkedChain( lw.get(), o, /*rust=*/false, std::vector<std::string>( q.begin(), q.end() - 1 ) ) );
                reached.insert( reached.end(), more.begin(), more.end() );
            }
        }
        bound = qualifierBoundElsewhere( lw.get(), q, reached );
    }
    if( !s.scope.empty() )
    {
        consider( ownerProof( ing, scopeSegments( s.scope ), s.fileId, q, bound ), "scope" );
    }
    for( const Symbol* o : mine )
    {
        std::vector<std::string> path = scopeSegments( o->scope );
        path.push_back( o->name );
        consider( ownerProof( ing, path, s.fileId, q, bound ), "scope" );
        if( q.size() > 1 && web && reexportDefKind( *o ) )   // `Utils.Fmt3.leaf`: the owner type published under the rest of Q
        {
            consider( walkedChain( lw.get(), o, /*rust=*/false, std::vector<std::string>( q.begin(), q.end() - 1 ) ).qLevel, "ns" );
        }
    }
    if( s.scope.empty() && !member )
    {
        consider( qualifierProofAt( rootRelPath( ing, s.fileId ), {}, q, bound ), "file" );
    }
    if( ownChain && best.level != QProof::Strong )
    {
        if( !chain )
        {
            chain.emplace( walkedChain( lw.get(), &s, /*rust=*/false, q ) );
        }
        consider( chain->qLevel, chain->qRow == -1 ? "file" : "ns" );
    }
    best.by = best.level == QProof::Dir ? "dir" : best.level == QProof::Alias ? "alias" : best.level == QProof::Path ? "path" : best.by;
    return best;
}

// Whether `s` (stored with no owner scope) sits strictly inside another definition's line span in its file: a class/struct/
// interface member or a function nested in a function or method. `spans` holds those definitions, sorted by file.
inline bool leafIsMember( const Symbol& s, const std::vector<const Symbol*>& spans )
{
    const auto lo = std::ranges::lower_bound( spans, s.fileId, {}, []( const Symbol* t ) { return t->fileId; } );
    return s.scope.empty() && std::any_of( lo, spans.end(), [ & ]( const Symbol* t ) { return t->fileId == s.fileId && t != &s && s.line > t->line && s.line < t->line + t->loc; } );
}

// The leaf rung: the definitions named `leaf` that prove qualifier `q`. When one is Strong, only the Strong ones (exact when one);
// otherwise every hedged one (alias, path, dir), never exact. `sameLeaf` gets every definition named leaf.
inline std::vector<Proven> provenLeafDefs( const IngestResult& ing, std::string_view leaf, const std::vector<std::string>& q, std::vector<const Symbol*>& sameLeaf )
{
    // the type definitions named like the qualifier's last segment: a member the index stores with no owner scope (TS/JS methods) is
    // still inside one when its line sits strictly within that type's line span in the same file
    std::vector<const Symbol*> owners;
    for( const Symbol& s : ing.symbols )
    {
        if( s.name == q.back() && s.loc > 1 && ( s.kind == SymKind::Class || s.kind == SymKind::Struct || s.kind == SymKind::Interface ) )
        {
            owners.push_back( &s );
        }
        if( s.name == leaf )
        {
            sameLeaf.push_back( &s );
        }
    }
    // the definitions whose span may hold a leaf definition (only in the leaf definitions' files), sorted by file
    std::vector<std::uint32_t> leafFiles;
    for( const Symbol* s : sameLeaf )
    {
        leafFiles.push_back( s->fileId );
    }
    std::ranges::sort( leafFiles );
    std::vector<const Symbol*> spans;
    for( const Symbol& t : ing.symbols )
    {
        const bool holder = t.kind == SymKind::Class || t.kind == SymKind::Struct || t.kind == SymKind::Interface || t.kind == SymKind::Function || t.kind == SymKind::Method;
        if( holder && t.loc > 1 && std::ranges::binary_search( leafFiles, t.fileId ) )
        {
            spans.push_back( &t );
        }
    }
    std::ranges::stable_sort( spans, {}, []( const Symbol* t ) { return t->fileId; } );
    // Q's first segment bound by a Web `import * as Q0` somewhere (the walk that resolves its modules is built only then)
    const bool qAliased = std::ranges::any_of( ing.bindings, [ & ]( const Binding& b )
                                               { return b.kind == LocalBindKind::ModuleAlias && b.importedName == "*" && !b.isFromAssignment && b.var == q.front(); } );
    LeafWalk            lw{ ing, {}, {}, {}, {} };
    std::vector<Proven> all;
    for( const Symbol* s : sameLeaf )
    {
        all.push_back( leafProof( ing, *s, owners, q, lw, leafIsMember( *s, spans ), qAliased ) );
    }
    const bool strong = std::ranges::any_of( all, []( const Proven& p ) { return p.level == QProof::Strong; } );
    std::vector<Proven> kept;
    std::ranges::copy_if( all, std::back_inserter( kept ), [ & ]( const Proven& p ) { return strong ? p.level == QProof::Strong : p.level != QProof::None; } );
    std::ranges::sort( kept, [ & ]( const Proven& a, const Proven& b ) { return a.level != b.level ? a.level > b.level : rowBefore( ing, a.s, b.s ); } );
    std::ranges::sort( sameLeaf, [ & ]( const Symbol* a, const Symbol* b ) { return rowBefore( ing, a, b ); } );
    return kept;
}

// SHORT-KEY-SENTENCE: the ONE code-shaped name of a task the route read as words ("" when it holds none or several). Code-shaped:
// a QUALIFIED spelling (reexportQualifiedSegments, every segment starting like an identifier, a leaf of 2+ bytes that is no file or
// host suffix: `index.ts`, `e.g.`, `3.15`, `Node.js` are not) or a word namesplit::hasIdentifierShape accepts (a lower-to-upper step
// or an interior `_`: `ChunkPtr`, `max_len`; a plain capitalised word, `Python`, `Utils`, `Column`, is English as often as code, the
// same reading the name-exact route makes). A bare word that is a segment of the qualified spelling beside it (`getX … Owner.getX`)
// is that name. Spans break on every byte that is not an identifier byte, `$`, `.` or `:` (`--defs=ColumnPtr` holds `ColumnPtr`).
// A span whose last segment is a file or host suffix names a file or host, so none of its words is a name (`CMakeLists.txt`).
inline std::string_view sentenceName( std::string_view task )
{
    const auto spanByte = []( char c ) { return namesplit::isIdentChar( c ) || c == '$' || c == '.' || c == ':'; };
    const auto edge     = []( char c ) { return c == '.' || c == ':'; };
    std::vector<std::string_view> quals, words;
    const auto addOnce = []( std::vector<std::string_view>& v, std::string_view w ) { if( std::ranges::find( v, w ) == v.end() ) { v.push_back( w ); } };
    for( std::size_t at = 0; at < task.size(); )
    {
        std::size_t end = at;
        while( end < task.size() && spanByte( task[ end ] ) )
        {
            ++end;
        }
        std::string_view tok = task.substr( at, end - at );
        at                   = end == at ? at + 1 : end;
        while( !tok.empty() && edge( tok.front() ) )   // sentence punctuation around a span (`X.`, `::X`)
        {
            tok.remove_prefix( 1 );
        }
        while( !tok.empty() && edge( tok.back() ) )
        {
            tok.remove_suffix( 1 );
        }
        const std::vector<std::string_view> segs = reexport_detail::reexportQualifiedSegments( tok );
        if( !segs.empty() && segs.back().size() >= 2 && !lit_detail::isFileOrHostSuffix( segs.back() ) &&
            std::ranges::all_of( segs, []( std::string_view g ) { return namesplit::isIdentStart( g.front() ) || g.front() == '$'; } ) )
        {
            addOnce( quals, tok );
            continue;
        }
        if( !segs.empty() && lit_detail::isFileOrHostSuffix( segs.back() ) )   // a file or host name (`CMakeLists.txt`, `HttpClient.cpp`): no word of it is a name
        {
            continue;
        }
        for( std::size_t w = 0; w < tok.size(); )   // the words of a span that is no qualified name
        {
            std::size_t e = w;
            while( e < tok.size() && !edge( tok[ e ] ) )
            {
                ++e;
            }
            if( namesplit::hasIdentifierShape( tok.substr( w, e - w ) ) )
            {
                addOnce( words, tok.substr( w, e - w ) );
            }
            w = e + 1;
        }
    }
    for( const std::string_view q : quals )
    {
        const std::vector<std::string_view> segs = reexport_detail::reexportQualifiedSegments( q );
        std::erase_if( words, [ & ]( std::string_view w ) { return std::ranges::find( segs, w ) != segs.end(); } );
    }
    if( quals.size() + words.size() != 1 )
    {
        return {};
    }
    return quals.empty() ? words.front() : quals.front();
}

// A qualified spelling that names a FILE of the tree, not a definition: a file's basename (`build.ninja`), a module path whose
// segments are the file's directories and stem (`http.server` for Lib/http/server.py, `pkg.sub` for pkg/sub/__init__.py or
// pkg/sub/index.ts), or one down to a dotted stem (`app.module` for src/app/app.module.ts, `feature.user.service` for
// lib/feature/user.service.ts). A dotted X that exists at the root (`go.mod`, `meson.build`: files the index does not hold) is a
// file too: one stat, `root` "" skips it.
inline bool sentenceNameIsFile( const IngestResult& ing, std::string_view x, const std::vector<std::string_view>& segs, std::string_view root )
{
    std::string mod, dotted;
    for( const std::string_view g : segs )
    {
        mod.append( mod.empty() ? "" : "/" ).append( g );
        dotted.append( dotted.empty() ? "" : "." ).append( g );
    }
    const auto atSegment = []( std::string_view path, std::string_view tail ) { return path.ends_with( tail ) && ( path.size() == tail.size() || path[ path.size() - tail.size() - 1 ] == '/' ); };
    // `tail` (segments joined by `.`) ends `path` at a `/` or `.` boundary, a `/` of the path matching a `.` of the tail
    const auto atDottedSegment = []( std::string_view path, std::string_view tail )
    {
        if( path.size() < tail.size() )
        {
            return false;
        }
        const std::size_t off = path.size() - tail.size();
        for( std::size_t i = 0; i < tail.size(); ++i )
        {
            if( path[ off + i ] != tail[ i ] && !( path[ off + i ] == '/' && tail[ i ] == '.' ) )
            {
                return false;
            }
        }
        return off == 0 || path[ off - 1 ] == '/' || path[ off - 1 ] == '.';
    };
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view rel     = rootRelPath( ing, f );
        const std::size_t      slash   = rel.rfind( '/' );
        const std::string_view base    = rel.substr( slash == std::string_view::npos ? 0 : slash + 1 );
        const std::size_t      dot     = base.find( '.' );
        const std::size_t      lastDot = base.rfind( '.' );
        const std::string_view stem    = rel.substr( 0, rel.size() - base.size() + ( dot == std::string_view::npos ? base.size() : dot ) );
        const std::string_view stemAll = rel.substr( 0, rel.size() - base.size() + ( lastDot == std::string_view::npos ? base.size() : lastDot ) );
        const bool             pkg     = base.starts_with( "__init__." ) || base.starts_with( "index." ) || base.starts_with( "mod." );
        if( base == x || atSegment( stem, mod ) || ( lastDot != dot && atDottedSegment( stemAll, dotted ) ) ||
            ( pkg && slash != std::string_view::npos && atSegment( rel.substr( 0, slash ), mod ) ) )
        {
            return true;
        }
    }
    std::error_code ec;
    return !root.empty() && x.find( ':' ) == std::string_view::npos && std::filesystem::is_regular_file( std::filesystem::path( root ) / x, ec );
}

// The sentence's name resolved to no definition: a bare X names no symbol in the index other than alias rows (one that exists is the
// route's to rank, not the ladder's; INDEX-ALIAS-CONST: a C++ `using X = Y;` / `namespace X = y;` row, defslookup.h aliasTargetRow, is
// another name the words route does not anchor on, so a name with only alias rows keeps the ladder and its literal rung prints the
// `using` lines; a name-exact route lands on the alias rows themselves); a qualified X has no definition the answer printed that
// proves its qualifier fully (provenLeafDefs, the leaf rung's own rule: a served same-leaf decoy does not resolve it). A qualified X
// that names a file (sentenceNameIsFile) is no definition to resolve: the ladder would list same-leaf strangers.
inline bool sentenceNameUnresolved( const IngestResult& ing, std::string_view x, const std::vector<NodeId>& served, std::string_view root )
{
    const std::vector<std::string_view> segs = reexport_detail::reexportQualifiedSegments( x );
    if( segs.empty() )
    {
        return std::ranges::none_of( ing.symbols, [ & ]( const Symbol& s ) { return s.name == x && !aliasTargetRow( ing, s ); } );
    }
    if( sentenceNameIsFile( ing, x, segs, root ) )
    {
        return false;
    }
    std::vector<const Symbol*> sameLeaf;
    const std::vector<Proven>  kept = provenLeafDefs( ing, segs.back(), std::vector<std::string>( segs.begin(), segs.end() - 1 ), sameLeaf );
    return std::ranges::none_of( kept, [ & ]( const Proven& p )
                                 { return p.level == QProof::Strong && std::ranges::find( served, NodeId( p.s - ing.symbols.data() ) ) != served.end(); } );
}

// The literal rung's allowlist: the declaration shape of `line` for key `k` ("" = not a declaration line).
inline std::string_view declShape( std::string_view line, std::string_view k )
{
    const auto wordAt = [ & ]( std::size_t at, std::size_t n )
    {
        return ( at == 0 || !namesplit::isIdentChar( line[ at - 1 ] ) ) && ( at + n >= line.size() || !namesplit::isIdentChar( line[ at + n ] ) );
    };
    const auto skipBlank = [ & ]( std::size_t at ) { return std::min( line.find_first_not_of( " \t", at ), line.size() ); };
    const std::size_t lead = skipBlank( 0 );
    // a comment line is never a declaration: `//`, `/*`, a block-comment continuation `*`, `--` (SQL/Lua/Haskell) and `#` other than a
    // preprocessor `#define` (a Python/shell/Ruby comment)
    if( const std::string_view body = line.substr( lead );
        body.starts_with( "//" ) || body.starts_with( "/*" ) || body.starts_with( "*" ) || body.starts_with( "--" ) ||
        ( body.starts_with( "#" ) && !body.substr( skipBlank( lead + 1 ) - lead ).starts_with( "define" ) ) )
    {
        return {};
    }
    // `X =` / `X: T =` at column 0 (a module constant)
    if( line.starts_with( k ) && wordAt( 0, k.size() ) )
    {
        const std::size_t after = skipBlank( k.size() );
        if( after < line.size() && ( ( line[ after ] == '=' && line.substr( after, 2 ) != "==" ) || line[ after ] == ':' ) )
        {
            return line[ after ] == ':' && line.find( '=', after ) == std::string_view::npos ? std::string_view{} : std::string_view( "assign" );
        }
    }
    for( std::size_t at = line.find( k ); at != std::string_view::npos; at = line.find( k, at + 1 ) )
    {
        if( !wordAt( at, k.size() ) )
        {
            continue;
        }
        std::size_t prev = at;
        while( prev > 0 && ( line[ prev - 1 ] == ' ' || line[ prev - 1 ] == '\t' ) )
        {
            --prev;
        }
        std::size_t start = prev;
        while( start > 0 && namesplit::isIdentChar( line[ start - 1 ] ) )
        {
            --start;
        }
        const std::string_view before = line.substr( start, prev - start );   // the word right before the key
        const std::size_t      after  = skipBlank( at + k.size() );
        const char             next   = after < line.size() ? line[ after ] : '\0';
        if( before == "using" && next == '=' )
        {
            return "using";
        }
        if( before == "type" && prev < at )
        {
            return "type";
        }
        if( before == "define" && line.substr( lead ).starts_with( "#" ) )
        {
            return "define";
        }
        if( before == "as" )
        {
            const std::string_view body = line.substr( lead );
            if( body.starts_with( "import " ) || body.starts_with( "use " ) || body.starts_with( "pub use " ) || body.starts_with( "pub(" ) || body.starts_with( "from " )
                || body.starts_with( "export " ) || line.find( "import" ) != std::string_view::npos )
            {
                return "import-as";
            }
        }
        if( ( before == "const" || before == "let" || before == "var" || before == "static" ) && ( next == '=' || next == ':' || next == ';' ) )
        {
            return "const";
        }
        if( line.substr( lead ).starts_with( "typedef" ) && ( next == ';' || next == '[' || next == ')' ) )
        {
            return "typedef";
        }
    }
    return {};
}

// The literal rung's rows: every declaration-shaped line of the key, those with an in= owner after those without (stable).
// in=: the enclosing definition, never the key's own alias row (INDEX-ALIAS-CONST: a `using X = Y;` line encloses itself):
// then the next definition out, spelt as grep's breadcrumb (`struct Holder { using X = Y; };` keeps main's in="Holder::Holder"),
// or none at namespace scope.
struct ShortKeyDeclLine
{
    const GrepHit*   h;
    std::string_view shape;
    std::string      in;
    const Symbol*    self  = nullptr;   // the key's own alias row the line sits in
    const Symbol*    outer = nullptr;   // the innermost definition around that alias row
};
// One pass over the symbols finds the owner of every line that sits in the key's own alias row (the file-scope owner is no
// definition to name; modscope rows are appended out of file order, so the pass is linear, not a file range).
inline void shortKeyAliasRowOwners( const IngestResult& ing, std::vector<ShortKeyDeclLine>& decl )
{
    std::vector<ShortKeyDeclLine*> selfs;   // the few lines inside the key's own alias rows
    for( ShortKeyDeclLine& d : decl )
    {
        if( d.self != nullptr )
        {
            selfs.push_back( &d );
        }
    }
    for( const Symbol& o : selfs.empty() ? std::span<const Symbol>() : std::span<const Symbol>( ing.symbols ) )
    {
        const auto around = [ & ]( const ShortKeyDeclLine& d )
        {
            const Symbol& a = *d.self;
            return &o != &a && o.kind != SymKind::ModuleScope && o.fileId == a.fileId && o.sigStartByte <= a.sigStartByte && a.endByte <= o.endByte &&
                   ( d.outer == nullptr || o.sigStartByte > d.outer->sigStartByte );
        };
        for( ShortKeyDeclLine* d : selfs )
        {
            d->outer = around( *d ) ? &o : d->outer;
        }
    }
    for( ShortKeyDeclLine* d : selfs )
    {
        d->in = d->outer == nullptr ? std::string() : d->outer->scope.empty() ? d->outer->name : d->outer->scope + "::" + d->outer->name;
    }
}
inline std::vector<ShortKeyDeclLine> shortKeyDeclLines( const IngestResult& ing, std::string_view key, const std::vector<GrepHit>& lines )
{
    std::vector<ShortKeyDeclLine> decl;
    for( const GrepHit& h : lines )
    {
        if( const std::string_view shape = declShape( h.text, key ); !shape.empty() )
        {
            const Symbol* e    = h.enclosingId < ing.symbols.size() ? &ing.symbols[ h.enclosingId ] : nullptr;
            const bool    self = e != nullptr && e->name == key && aliasTargetRow( ing, *e );
            decl.push_back( ShortKeyDeclLine{ &h, shape, self ? std::string() : h.enclosing, self ? e : nullptr } );
        }
    }
    shortKeyAliasRowOwners( ing, decl );
    std::ranges::stable_sort( decl, []( const ShortKeyDeclLine& l, const ShortKeyDeclLine& r ) { return l.in.empty() && !r.in.empty(); } );
    return decl;
}

}   // namespace shortkey_detail

struct ShortKeyArgs
{
    std::string_view routeNote;           // the route note: `name-exact(X); anchors: …`
    bool             noDefinitionServed;  // the answer printed no signature row (the no_candidates shape)
    bool             held = false;        // a token budget is set: the marker, not the rows
    RedactCounts*    redact = nullptr;
    std::string_view rootArg;             // the single root (p= relative to it), "" otherwise
    std::string_view task;                // the --for text (SHORT-KEY-SENTENCE: its one code-shaped name when the route read it as words)
    const std::vector<NodeId>* served = nullptr;   // the signature rows the answer printed; null when they streamed unrecorded (no sentence ladder)
};

// The <shortkey> block ("" unless the route is name-exact and no definition was served, or the route read the task as words and
// its one code-shaped name resolved to no definition: from="sentence").
inline std::string renderShortKeyFallback( const IngestResult& ing, const ShortKeyArgs& a )
{
    using namespace shortkey_detail;
    std::string_view x = routeName( a.routeNote );
    // SHORT-KEY-SENTENCE: a route that read the task as words reaches the same ladder when the task holds exactly one code-shaped
    // name and no definition of it resolved (sentenceName, sentenceNameUnresolved); every rung and proof below is unchanged
    bool fromSentence = false;
    if( x.empty() && a.served != nullptr && forShortKeyOn() )
    {
        x            = sentenceName( a.task );
        fromSentence = !x.empty() && sentenceNameUnresolved( ing, x, *a.served, a.rootArg );
        if( !fromSentence )   // a sentence name that resolved, or names a file, is no route name: the bare-name branch must not take it
        {
            x = {};
        }
    }
    // `this.X` / `self.X` is a member access, not a qualified name: no ladder keyed on text no definition can carry
    if( x.empty() || !( a.noDefinitionServed || fromSentence ) || !forShortKeyOn() || x.starts_with( "this." ) || x.starts_with( "self." ) )
    {
        return {};
    }
    const std::vector<std::string_view> segs = reexport_detail::reexportQualifiedSegments( x );
    const std::string_view              key  = segs.empty() ? x : segs.back();
    std::string                         out;
    std::vector<char>                   esc;
    const auto attr = [ & ]( std::string_view k, std::string_view v ) { out.append( " " ).append( k ).append( "=\"" ).append( escapeXml( v, esc ) ).append( "\"" ); };
    const auto num  = [ & ]( std::string_view k, std::size_t v ) { out.append( " " ).append( k ).append( "=\"" ).append( std::to_string( v ) ).append( "\"" ); };
    const auto defRow = [ & ]( const Symbol& s, std::string_view by )
    {
        out.append( "<d" );
        attr( "n", dotteddetail::displayName( s ) );
        attr( "t", symTag( s.kind ) );
        attr( "p", rootRelPath( ing, s.fileId ) );
        num( "l", s.line );
        if( !by.empty() )
        {
            attr( "q_by", by );
        }
        out.append( "/>" );
    };
    if( a.held )
    {
        out = fromSentence ? "<!-- shortkey held=\"budget\": a token budget is set, so the fallback ladder is not run (not in est_tokens); next= runs it without the budget; "
                             "from=sentence: the route read the task as words and X is its one code-shaped name, unresolved --><shortkey held=\"budget\""
                           : "<!-- shortkey held=\"budget\": a token budget is set, so the fallback ladder is not run (not in est_tokens); next= runs it without the budget --><shortkey held=\"budget\"";
        attr( "of", x );
        out.append( fromSentence ? " from=\"sentence\"" : "" );
        return out.append( nextAttrXml( nextFlag( "--for=", x ) ) ).append( "/>" );
    }
    std::string rungs, body, next;
    // rung 1: the leaf, proven by its qualifier
    bool exact = false;
    if( !segs.empty() )
    {
        rungs = "leaf";
        const std::vector<std::string> q( segs.begin(), segs.end() - 1 );
        std::vector<const Symbol*>     sameLeaf;
        const std::vector<Proven>      kept = provenLeafDefs( ing, key, q, sameLeaf );
        exact                                = kept.size() == 1 && kept.front().level == QProof::Strong;   // a hedged proof is never exact
        out.append( "<rung n=\"leaf\"" );
        attr( "key", key );
        attr( "q", std::string_view( x ).substr( 0, x.size() - key.size() - ( x.ends_with( "::" + std::string( key ) ) ? 2 : 1 ) ) );
        num( "kept", kept.size() );
        num( "of", sameLeaf.size() );
        out.append( exact ? " exact=\"1\"" : " exact=\"0\"" );
        if( kept.size() > 1 )
        {
            num( "cands", kept.size() );
        }
        out.append( kept.empty() && !sameLeaf.empty() ? " q_unmatched=\"1\">" : ">" );
        for( std::size_t i = 0; i < kept.size() && i < kShortKeyRows; ++i )
        {
            defRow( *kept[ i ].s, kept[ i ].by );
        }
        for( std::size_t i = 0; kept.empty() && i < sameLeaf.size() && i < kShortKeyRows; ++i )
        {
            defRow( *sameLeaf[ i ], {} );
        }
        out.append( "</rung>" );
        if( exact )   // the one proven definition IS the answer the route missed: its body, like --expand prints it
        {
            const Symbol& s = *kept.front().s;
            if( std::optional<std::string> b = renderBodyElement( ing, NodeId( &s - ing.symbols.data() ), kShortKeyBodyBytes, /*compress=*/false, a.redact, a.rootArg, nullptr ) )
            {
                out.append( *b );
            }
            next = nextFlag( "--expand=", std::string( rootRelPath( ing, s.fileId ) ) + ":" + std::to_string( s.line ) + ":" + s.name );
        }
        else if( !sameLeaf.empty() )
        {
            next = nextFlag( "--defs=", key );
        }
    }
    // rung 2: definition names containing the key
    if( !exact && key.size() >= kShortKeyMinSubstring )
    {
        rungs.append( rungs.empty() ? "" : "," ).append( "substring" );
        std::vector<const Symbol*> hits;
        for( const Symbol& s : ing.symbols )
        {
            if( s.name != key && s.name.find( key ) != std::string::npos )
            {
                hits.push_back( &s );
            }
        }
        std::ranges::sort( hits, [ & ]( const Symbol* l, const Symbol* r ) { return l->name.size() != r->name.size() ? l->name.size() < r->name.size() : rowBefore( ing, l, r ); } );
        out.append( "<rung n=\"substring\"" );
        attr( "key", key );
        num( "total", hits.size() );
        num( "shown", std::min( hits.size(), kShortKeyRows ) );
        out.append( " exact=\"0\">" );
        for( std::size_t i = 0; i < hits.size() && i < kShortKeyRows; ++i )
        {
            defRow( *hits[ i ], {} );
        }
        out.append( "</rung>" );
    }
    // rung 3: declaration-shaped source lines
    if( !exact )
    {
        rungs.append( rungs.empty() ? "" : "," ).append( "literal" );
        out.append( "<rung n=\"literal\"" );
        attr( "key", key );
        const bool identKey = std::ranges::all_of( key, []( char ch ) { return namesplit::isIdentChar( ch ); } );
        if( lit_detail::isConstShaped( key ) || !identKey )
        {
            out.append( identKey ? " held=\"lit\"" : " skipped=\"1\"" ).append( " exact=\"0\"/>" );
        }
        else
        {
            const GrepCollection          got = grepCollect( ing, std::string( key ), /*regex=*/false, /*noPrefilter=*/false );
            std::vector<GrepRawHit>       src;
            std::copy_if( got.raw.begin(), got.raw.end(), std::back_inserter( src ), [ & ]( const GrepRawHit& h ) { return pathTierOf( rootRelPath( ing, h.fileId ) ) == PathTier::Source; } );
            const std::vector<GrepHit>    lines = grepEnrich( ing, src );
            const std::vector<ShortKeyDeclLine> decl = shortKeyDeclLines( ing, key, lines );
            num( "total", decl.size() );
            num( "shown", std::min( decl.size(), kShortKeyRows ) );
            out.append( " exact=\"0\"" ).append( got.cleanScan() ? "" : " floor=\"1\"" ).append( ">" );
            for( std::size_t i = 0; i < decl.size() && i < kShortKeyRows; ++i )
            {
                const GrepHit& h = *decl[ i ].h;
                out.append( "<ld" );
                attr( "p", rootRelPath( ing, h.fileId ) );
                num( "l", h.line );
                attr( "shape", decl[ i ].shape );
                if( !decl[ i ].in.empty() )
                {
                    attr( "in", decl[ i ].in );
                }
                std::string text( h.text.substr( std::min( h.text.find_first_not_of( " \t" ), h.text.size() ) ) );
                redactInPlace( text, a.redact );
                truncateUtf8WithEllipsis( text, kShortKeyLineBytes );
                out.append( "><![CDATA[" );
                appendCdataSafe( text, out );
                out.append( "]]></ld>" );
            }
            out.append( "</rung>" );
        }
        if( next.empty() )
        {
            next = nextFlag( "--grep=", key );
        }
    }
    std::string head = std::string( kShortKeyLegend ).append( "<shortkey" );
    std::swap( out, head );
    attr( "of", x );
    out.append( fromSentence ? " from=\"sentence\" found=\"0\"" : " found=\"0\"" );
    attr( "rungs", rungs );
    out.append( nextAttrXml( next ) ).append( ">" ).append( head ).append( "</shortkey>" );
    return out;
}

}   // namespace rw
