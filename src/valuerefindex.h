#pragma once
// valuerefindex.h — the resolution core of the reference-as-value rows (src/valuerefs.h says what a row means):
// ValueRefIndex, the rows every surface serves, the --uses filter and the --path count. No rendering and no
// serialize.h, so quality.h (the --quality-delta dead kind) can include it without an include cycle.

#include "graph.h"             // jsImportKey — the "fileId#name" key, reused for containers
#include "mention.h"           // pathStem — a module path's file stem
#include "resolve.h"           // includerDir, resolvePreciseInclude — a module path's file
#include "infra/Diagnostics.h"   // EXPECTS/ENSURES — the window and index invariants
#include "infra/sortutil.h"      // svLess: the method-name list slot_join::memberCalls binary-searches
#include "model.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <iterator>
#include <optional>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

namespace rw
{

using VrLangFamily = ValueRefFamily;   // model.h: the armed-language table the capture indexes too

// A Through key matches a Value key: "*" (a computed subscript) reaches every keyed or indexed slot, "" (a bare
// call through the variable) only the variable itself, anything else only its own key.
inline bool vrKeyMatches( std::string_view throughKey, std::string_view valueKey ) noexcept
{
    if( throughKey == "*" )
    {
        return !valueKey.empty() && ( valueKey.front() == '.' || valueKey.front() == '[' );
    }
    return throughKey == valueKey;
}

// A decorator row (`into=@NAME`) whose decorator only wraps the function and binds it back to its own name: the
// builtin descriptors, abc/typing markers, property accessors and functools.wraps. Keyed on the last dotted segment,
// so `@abc.abstractmethod`, `@functools.cached_property` and `@x.setter` all match.
inline bool vrIsWrapperDecorator( std::string_view into ) noexcept
{
    if( !into.starts_with( '@' ) )
    {
        return false;
    }
    std::string_view last = into.substr( 1 );
    if( const std::size_t dot = last.rfind( '.' ); dot != std::string_view::npos )
    {
        last = last.substr( dot + 1 );
    }
    static constexpr std::string_view kWrappers[] = {
        "classmethod", "staticmethod", "property", "cached_property", "abstractmethod", "abstractproperty",
        "abstractclassmethod", "abstractstaticmethod", "setter", "getter", "deleter", "overload", "override", "wraps",
    };
    return std::ranges::find( kWrappers, last ) != std::end( kWrappers );
}

// Two references in served order: by path, then by position in the file.
inline bool vrBindLess( const IngestResult& ing, const Reference& a, const Reference& b )
{
    if( a.fileId != b.fileId )
    {
        return ing.files[a.fileId] < ing.files[b.fileId];
    }
    return a.startByte < b.startByte;
}

// ── IX1-V2: the per-language pieces of the slot join (model.h kVrSlotLangs) ──────────────────────────────────────
namespace slot_join
{
// fix1 F-2: a PackageDir (Go) slot type's key — the package DIRECTORY the type is declared in (a Go package is a directory:
// x/types.Cmd and y/types.Cmd are two types though both packages are named `types`), as the first file of that directory, and the
// type name: jsImportKey( dirFile, name ). keyOfSymbol is the ONE spelling the store side (SlotIndex) and --for's struct rows
// (forslots.h, through SlotIndex::typeKeyOf) both key by. A store's type (Reference::memberCtor, keyOf): `T` → the writing
// file's directory; `pkg.T` → the directory of the file's import bound to `pkg`, when exactly one in-tree Go directory is that
// import path's tail, else "" (unknown: the name tier — an out-of-tree package, an unmatched or ambiguous path). fix1 F-5: an
// in-tree type that is no STRUCT (`type Table map[Op]func()`, an alias) keys kNoSlot: its keyed literal names map keys, not fields.
inline constexpr std::string_view kNoSlot = "\x01";   // == SlotIndex's kConflict: an end that joins nothing
class GoTypeKeys
{
public:
    void build( const IngestResult& ing )
    {
        for( const Binding& b : ing.bindings )
        {
            if( b.kind == LocalBindKind::ModuleAlias && !b.var.empty() && !b.typeName.empty() )
            {
                std::string& have = m_imports[ jsImportKey( b.fileId, b.var ) ];
                have = have.empty() || have == b.typeName ? b.typeName : std::string( kNoSlot );
            }
        }
        HashMap<std::string, std::uint32_t> first;    // a directory as the files spell it → its first file
        HashMap<std::uint32_t, char>        goDir;    // CR 4396503857: first files of the directories already in m_dirs (the first file may be no .go file)
        m_dirOfFile.resize( ing.files.size() );
        for( std::uint32_t f = 0; f < ing.files.size(); ++f )
        {
            const auto it = first.try_emplace( std::string( includerDir( ing.files[f] ) ), f ).first;
            m_dirOfFile[f] = it->second;
            if( ing.files[f].ends_with( ".go" ) && goDir.try_emplace( it->second, char( 1 ) ).second )
            {
                m_dirs.emplace_back( std::string( includerDir( rootRelPath( ing, f ) ) ), it->second );
            }
        }
        for( const Symbol& sym : ing.symbols )
        {
            if( sym.kind == SymKind::Struct && slotTypeKeyOf( sym.lang ) == VrSlotTypeKey::PackageDir )
            {
                m_structs.try_emplace( keyOfSymbol( sym ), char( 1 ) );
            }
        }
    }
    std::string keyOfSymbol( const Symbol& s ) const { return jsImportKey( m_dirOfFile[ s.fileId ], s.name ); }
    std::string keyOf( const Reference& r )
    {
        const std::string_view t   = r.memberCtor;
        const std::size_t      dot = t.find( '.' );
        std::uint32_t          dir = t.empty() ? kNoFile : m_dirOfFile[ r.fileId ];
        if( dot != std::string_view::npos )
        {
            const auto imp = m_imports.find( jsImportKey( r.fileId, t.substr( 0, dot ) ) );
            dir = imp == m_imports.end() || imp->second == kNoSlot ? kNoFile : dirOfImport( imp->second );
        }
        if( dir == kNoFile )
        {
            return {};
        }
        std::string key = jsImportKey( dir, dot == std::string_view::npos ? t : t.substr( dot + 1 ) );
        return m_structs.contains( key ) ? key : std::string( kNoSlot );
    }

private:
    // the ONE in-tree Go directory whose root-relative path is the tail of import path `path`, kNoFile when none or several
    std::uint32_t dirOfImport( const std::string& path )
    {
        if( const auto it = m_dirOf.find( path ); it != m_dirOf.end() )
        {
            return it->second;
        }
        std::uint32_t hit = kNoFile;
        int           n   = 0;
        for( const auto& [ rel, dir ] : m_dirs )
        {
            if( !rel.empty() && path.ends_with( rel ) && ( path.size() == rel.size() || path[ path.size() - rel.size() - 1 ] == '/' ) )
            {
                hit = dir;
                ++n;
            }
        }
        return m_dirOf[ path ] = n == 1 ? hit : kNoFile;
    }
    HashMap<std::string, std::string>                  m_imports;     // "fileId#alias" → import path (kNoSlot: two paths)
    std::vector<std::uint32_t>                         m_dirOfFile;   // file → the first file of its directory
    std::vector<std::pair<std::string, std::uint32_t>> m_dirs;        // (root-relative dir, its first file), one per Go dir
    HashMap<std::string, char>                         m_structs;     // every in-tree Go struct's key
    HashMap<std::string, std::uint32_t>                m_dirOf;       // import path → its directory's first file (kNoFile none)
};
// FN-SLOT part 2: each file's Rust crate as its path spells it — the root-relative path before the first `src/` directory (a crate's
// sources live under its own src/), else the file's directory; "" for a file of no path-call language (never compared).
inline std::vector<std::string_view> cratesOf( const IngestResult& ing )
{
    std::vector<std::string_view> out( ing.files.size() );
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view rel = rootRelPath( ing, f );
        if( !rel.ends_with( ".rs" ) || rel.starts_with( "src/" ) )
        {
            continue;
        }
        const std::size_t at = rel.find( "/src/" );
        out[f] = at == std::string_view::npos ? includerDir( rel ) : rel.substr( 0, at );
    }
    return out;
}
// FN-SLOT-2 fix 1 (review rv-fn-slot-2 F-1/F-2): where a Rust path AS WRITTEN can reach — the module path ingest_rustslots.h
// keeps (a value's memberVia, a path callee's recvVar, a struct type's memberCtor), read against the file's `use` records (the
// L3 Rust import records: ing.includes, the specifiers resolve.h resolveRustImport resolves for the call graph) and the in-tree
// crates (cratesOf). Never a guess: a path whose target is out of the tree, renamed, or not decidable reaches nothing.
//   * std / core / alloc, an out-of-tree crate (`tokio::spawn`, `use extcrate::Hook`), a `use … as` rename, an unknown first
//     segment (an inline module: a floor): None.
//   * `crate::a::x`, `self::…`, `super::…`, `mod a; a::x`, a `use` that spells one: the ONE file resolveRustImport resolves the
//     path to (this crate's root), never the writing file's own namesake (F-2); `crate::x` the crate root's.
//   * a path led by an in-tree crate's name (`zed::x`, `use zed::{x}`): that crate's one, outside the writing file.
//   * a bare name no `use` names: this file's, else its crate's, else the repo's only one — that last tier only when the file
//     `use`s the defining crate (F-1 iv); none of the last two while the file has an OUT-OF-TREE glob (`use extcrate::*`: the
//     bare name may come from it; a namesake in this file still shadows it). A bare name a `use` names while this file defines a
//     namesake too: None (the `use` sits in an inner scope; which one this reference sees is not read).
class RustPaths
{
public:
    enum class Reach : std::uint8_t { Near, File, Crate, InCrate, CrateRoot, None };
    struct At
    {
        Reach            kind    = Reach::Near;
        bool             viaUse  = false;     // Near only: decided through a `use` (a namesake in this file: None)
        std::uint32_t    file    = kNoFile;   // File: the one file
        std::string_view crate;               // Crate / InCrate / CrateRoot: the crate
    };
    void build( const IngestResult& ing )
    {
        m_ing    = &ing;
        m_crates = cratesOf( ing );
        m_uses.assign( ing.files.size(), {} );
        for( const Include& inc : ing.includes )
        {
            if( inc.fileId < ing.files.size() && !inc.isSymbolic && rootRelPath( ing, inc.fileId ).ends_with( ".rs" ) )
            {
                m_uses[ inc.fileId ].push_back( inc.target );
            }
        }
        for( const std::string_view c : m_crates )
        {
            if( c.empty() )
            {
                continue;
            }
            const auto [ it, fresh ] = m_crateByName.try_emplace( crateName( c ), c );
            if( !fresh && it->second != c )
            {
                it->second = std::string_view();   // two crates of one name: which one a path means is unknown
            }
        }
        m_extGlob.assign( ing.files.size(), 0 );
        for( std::uint32_t f = 0; f < m_uses.size(); ++f )
        {
            m_extGlob[f] = hasOutOfTreeGlob( f ) ? 1 : 0;
        }
    }
    std::string_view crateOf( std::uint32_t f ) const { return m_crates[f]; }
    // Where `name`, written after module path `module` ("" bare) by reference `r`, can reach.
    At reach( const Reference& r, std::string_view module, std::string_view name ) const
    {
        if( !module.empty() )
        {
            return moduleReach( r, module, name, 0 );
        }
        std::string via;
        switch( useOf( r.fileId, name, via ) )
        {
            case Use::None:    return At{};
            case Use::Opaque:  return At{ Reach::None };
            case Use::Path:    break;
        }
        At at = moduleReach( r, via, name, 0 );
        at.viaUse = true;
        return at;
    }
    // The one candidate of `cands` (symbols) `at` reaches from file `fileId`: Near — its own file's, else its crate's, else the
    // repo's only one (use-gated); kNoNode when the tier that has any holds two (which one is unknown: never a guess).
    NodeId nearestOf( std::span<const NodeId> cands, std::uint32_t fileId, const At& at ) const
    {
        const IngestResult& ing = *m_ing;
        NodeId pick[3] = { kNoNode, kNoNode, kNoNode };
        int    n[3]    = { 0, 0, 0 };
        for( const NodeId id : cands )
        {
            const std::uint32_t f    = ing.symbols[id].fileId;
            const int           tier = tierOf( f, fileId, at );
            if( f == fileId && at.viaUse && !( at.kind == Reach::File && at.file == fileId ) )
            {
                return kNoNode;   // a `use` names it AND this file defines it: the use is in an inner scope (which one is unread)
            }
            for( int t = tier; t >= 0 && t < 3; ++t )
            {
                pick[t] = id;
                ++n[t];
            }
        }
        for( int t = 0; t < 3; ++t )
        {
            if( n[t] > 0 )
            {
                return n[t] == 1 ? pick[t] : kNoNode;
            }
        }
        return kNoNode;
    }

private:
    enum class Use : std::uint8_t { None, Path, Opaque };
    static bool upperLead( std::string_view s ) noexcept { return !s.empty() && s[0] >= 'A' && s[0] <= 'Z'; }
    // resolve.h trimWs, newlines included (a `use` brace group spans lines)
    static std::string_view trimmed( std::string_view s ) noexcept
    {
        for( std::size_t was = s.size() + 1; was != s.size(); )
        {
            was = s.size();
            s   = trimWs( s );
            s   = s.starts_with( '\n' ) ? s.substr( 1 ) : s;
            s   = s.ends_with( '\n' ) ? s.substr( 0, s.size() - 1 ) : s;
        }
        return s;
    }
    static std::string_view firstSegment( std::string_view p ) noexcept { return p.substr( 0, std::min( p.find( "::" ), p.size() ) ); }
    // A crate's name as a path spells it: its directory's last component, `-` as `_` (`crates/nu-engine` → nu_engine).
    static std::string crateName( std::string_view crate )
    {
        std::string n( crate.substr( crate.rfind( '/' ) == std::string_view::npos ? 0 : crate.rfind( '/' ) + 1 ) );
        std::ranges::replace( n, '-', '_' );
        return n;
    }
    // Each name one `use` specifier binds: cb( name, module path, renamed ). `a::{b, c::d as e, self}`, `a::b as c`; a glob reports
    // the name "*" (it binds none; no identifier equals it) with the module path it opens.
    template<class Cb>
    static void forEachUse( std::string_view t, const std::string& prefix, int depth, const Cb& cb )
    {
        t = trimmed( t );
        if( t.starts_with( "::" ) )
        {
            t.remove_prefix( 2 );
        }
        if( const std::size_t br = t.find( '{' ); br != std::string_view::npos )
        {
            const std::size_t close = t.rfind( '}' );
            std::string_view  head  = trimmed( t.substr( 0, br ) );
            if( close == std::string_view::npos || close < br || depth > 4 )
            {
                return;
            }
            if( head.ends_with( "::" ) )
            {
                head.remove_suffix( 2 );
            }
            const std::string      p    = head.empty() ? prefix : CallResultTypes::joinModule( prefix, head );
            const std::string_view body = t.substr( br + 1, close - br - 1 );
            int                    lvl  = 0;
            std::size_t            from = 0;
            for( std::size_t i = 0; i <= body.size(); ++i )
            {
                const char c = i < body.size() ? body[i] : ',';
                lvl += c == '{' ? 1 : c == '}' ? -1 : 0;
                if( c == ',' && lvl == 0 )
                {
                    forEachUse( body.substr( from, i - from ), p, depth + 1, cb );
                    from = i + 1;
                }
            }
            return;
        }
        std::string_view alias;
        if( const std::size_t as = t.find( " as " ); as != std::string_view::npos )
        {
            alias = trimmed( t.substr( as + 4 ) );
            t     = trimmed( t.substr( 0, as ) );
        }
        const std::size_t c      = t.rfind( "::" );
        std::string_view  leaf   = c == std::string_view::npos ? t : t.substr( c + 2 );
        std::string       module = c == std::string_view::npos ? prefix : CallResultTypes::joinModule( prefix, t.substr( 0, c ) );
        std::string       own;   // the `self` module's name, copied BEFORE `module` is reassigned (a view into it would dangle)
        if( leaf == "self" )
        {
            const std::size_t up = module.rfind( "::" );   // `a::b::{self}` binds module b
            own                  = module.substr( up == std::string::npos ? 0 : up + 2 );
            module               = up == std::string::npos ? std::string() : module.substr( 0, up );
            if( alias.empty() )
            {
                cb( std::string_view( own ), module, false );
                return;
            }
            leaf = own;
        }
        if( leaf.empty() )
        {
            return;
        }
        if( leaf == "*" )
        {
            cb( leaf, module, false );   // a glob binds no name; its module path is what hasOutOfTreeGlob reads
            return;
        }
        cb( alias.empty() ? leaf : alias, module, !alias.empty() && alias != leaf );
    }
    // The module path the file's `use` binds `name` from (`use tokio::spawn` → "tokio"); Opaque: a rename, or two that differ.
    Use useOf( std::uint32_t fileId, std::string_view name, std::string& via ) const
    {
        Use got = Use::None;
        for( const std::string_view t : m_uses[ fileId ] )
        {
            if( t.starts_with( "mod:" ) || got == Use::Opaque )
            {
                continue;
            }
            forEachUse( t, std::string(), 0, [ & ]( std::string_view bound, const std::string& module, bool renamed )
            {
                if( bound != name )
                {
                    return;
                }
                if( renamed || module.empty() || ( got == Use::Path && via != module ) )
                {
                    got = Use::Opaque;
                    return;
                }
                got = Use::Path;
                via = module;
            } );
        }
        return got;
    }
    bool declaresMod( std::uint32_t fileId, std::string_view seg ) const
    {
        return std::ranges::any_of( m_uses[ fileId ], [ & ]( std::string_view t ) { return t.starts_with( "mod:" ) && t.substr( 4 ) == seg; } );
    }
    // The file `use`s a glob of something outside the tree (`use extcrate::*`, `use std::io::prelude::*`): a bare name no `use`
    // names may be that glob's, so an in-tree namesake of another file is one guess among two. A glob led by `crate` / `self` /
    // `super`, an in-tree crate or a `mod` this file declares is in the tree (its names are in-tree ones); the crate-less `use *` none.
    bool hasOutOfTreeGlob( std::uint32_t fileId ) const
    {
        bool out = false;
        for( const std::string_view t : m_uses[ fileId ] )
        {
            if( t.starts_with( "mod:" ) || out )
            {
                continue;
            }
            forEachUse( t, std::string(), 0, [ & ]( std::string_view bound, const std::string& module, bool )
            {
                const std::string_view seg = trimmed( firstSegment( module ) );
                out = out || ( bound == "*" && !seg.empty() && seg != "crate" && seg != "self" && seg != "super"
                               && !m_crateByName.contains( std::string( seg ) ) && !declaresMod( fileId, seg ) );
            } );
        }
        return out;
    }
    bool usesCrate( std::uint32_t fileId, std::string_view crate ) const
    {
        const std::string want = crateName( crate );
        return std::ranges::any_of( m_uses[ fileId ], [ & ]( std::string_view t )
        {
            t = trimmed( t.starts_with( "::" ) ? t.substr( 2 ) : t );
            return trimmed( t.substr( 0, std::min( { t.find( "::" ), t.find( '{' ), t.size() } ) ) ) == want;
        } );
    }
    // The candidate's tier for `at` (-1: out of reach). Near: 0 own file, 1 own crate, 2 another crate the file `use`s — tiers 1 and 2
    // only while the file has no out-of-tree glob (fix 2 L-2: that glob may be where the bare name comes from; a local item shadows it).
    int tierOf( std::uint32_t f, std::uint32_t fileId, const At& at ) const
    {
        switch( at.kind )
        {
            case Reach::Near:
                return f == fileId ? 0 : m_extGlob[fileId] ? -1 : m_crates[f] == m_crates[fileId] ? 1 : usesCrate( fileId, m_crates[f] ) ? 2 : -1;
            case Reach::File:      return f == at.file ? 0 : -1;
            case Reach::Crate:     return f != fileId && m_crates[f] == at.crate ? 0 : -1;
            case Reach::InCrate:   return m_crates[f] == at.crate ? 0 : -1;
            case Reach::CrateRoot:
            {
                const std::string_view p = rootRelPath( *m_ing, f );
                return m_crates[f] == at.crate && ( p.ends_with( "/lib.rs" ) || p.ends_with( "/main.rs" ) ) && includerDir( p ) == crateRootDir( f ) ? 0 : -1;
            }
            case Reach::None:      return -1;
        }
        return -1;
    }
    // The directory a file's crate's `crate::` anchors in: `<crate>/src`, a root crate's `src`, else the crate's own directory.
    std::string_view crateRootDir( std::uint32_t f ) const
    {
        const std::string_view rel = rootRelPath( *m_ing, f );
        if( rel.starts_with( "src/" ) )
        {
            return rel.substr( 0, 3 );
        }
        const std::size_t at = rel.find( "/src/" );
        return at == std::string_view::npos ? includerDir( rel ) : rel.substr( 0, at + 4 );
    }
    At fileAt( std::uint32_t fileId, const std::string& target, std::uint32_t rootOf ) const
    {
        if( m_fileIndex.empty() )
        {
            m_fileIndex.reserve( m_ing->files.size() );
            for( std::uint32_t f = 0; f < m_ing->files.size(); ++f )
            {
                m_fileIndex.emplace( lexicalNormalize( rootRelPath( *m_ing, f ) ), f );
            }
        }
        const std::uint32_t f = resolveRustImport( rootRelPath( *m_ing, fileId ), target, m_fileIndex, crateRootDir( rootOf ), true );
        return f == kNoFile ? At{ Reach::None } : At{ Reach::File, false, f };
    }
    // `module::name` led by an anchor, an in-tree crate's name, a `mod` this file declares or a module a `use` binds.
    At moduleReach( const Reference& r, std::string_view module, std::string_view name, int depth ) const
    {
        const std::string_view seg  = trimmed( firstSegment( module ) );
        const std::string_view rest = module.size() > seg.size() + 2 ? module.substr( seg.size() + 2 ) : std::string_view();
        if( seg == "std" || seg == "core" || seg == "alloc" )
        {
            return At{ Reach::None };
        }
        if( seg == "crate" || seg == "self" || seg == "super" )
        {
            return anchored( r, seg, rest, name );
        }
        if( const auto it = m_crateByName.find( std::string( seg ) ); it != m_crateByName.end() )
        {
            if( it->second.empty() )
            {
                return At{ Reach::None };
            }
            if( rest.empty() )
            {
                return At{ Reach::Crate, false, kNoFile, it->second };
            }
            for( std::uint32_t f = 0; f < m_crates.size(); ++f )
            {
                if( m_crates[f] == it->second )
                {
                    return fileAt( r.fileId, "crate::" + CallResultTypes::joinModule( rest, name ), f );   // that crate's root anchors it
                }
            }
            return At{ Reach::None };
        }
        if( depth == 0 && declaresMod( r.fileId, seg ) )
        {
            return anchored( r, "self", module, name );
        }
        std::string via;
        if( depth == 0 && useOf( r.fileId, seg, via ) == Use::Path )
        {
            return moduleReach( r, CallResultTypes::joinModule( via, module ), name, 1 );
        }
        return At{ Reach::None };
    }
    // `crate::…`, `self::…`, `super::…`: resolveRustImport's module-file rule from this file (`rest` the modules after the anchor).
    At anchored( const Reference& r, std::string_view anchor, std::string_view rest, std::string_view name ) const
    {
        const IngestResult&    ing  = *m_ing;
        const std::string_view path = rootRelPath( ing, r.fileId );
        const std::string_view dir  = includerDir( path );
        std::string_view       stem = path.substr( dir.empty() ? 0 : dir.size() + 1 );
        stem                        = stem.substr( 0, stem.rfind( '.' ) );
        const bool modFile = stem == "mod" || stem == "lib" || stem == "main";
        if( anchor == "crate" )
        {
            return rest.empty() ? At{ Reach::CrateRoot, false, kNoFile, m_crates[ r.fileId ] } : fileAt( r.fileId, "crate::" + CallResultTypes::joinModule( rest, name ), r.fileId );
        }
        if( r.fromSymbol < ing.symbols.size() )
        {
            const Symbol& from = ing.symbols[ r.fromSymbol ];
            if( from.kind == SymKind::Method && !from.scope.empty() && !upperLead( from.scope ) )
            {
                return At{ Reach::None };   // inside an inline `mod m { … }`: `self` / `super` are not this file's module
            }
        }
        if( anchor == "self" )
        {
            if( rest.empty() )
            {
                return At{ Reach::File, false, r.fileId };
            }
            return fileAt( r.fileId, modFile ? "self::" + CallResultTypes::joinModule( rest, name ) : "self::" + CallResultTypes::joinModule( CallResultTypes::joinModule( stem, rest ), name ), r.fileId );
        }
        if( modFile )   // super of a mod.rs: its directory's parent module (a crate root has none)
        {
            return stem != "mod" || rest.empty() ? At{ Reach::None } : fileAt( r.fileId, "super::" + CallResultTypes::joinModule( rest, name ), r.fileId );
        }
        if( rest.empty() )   // `super::x` in d/s.rs: x in module d (d.rs or d/mod.rs)
        {
            const std::string_view up = dir.substr( dir.rfind( '/' ) == std::string_view::npos ? 0 : dir.rfind( '/' ) + 1 );
            return up.empty() ? At{ Reach::None } : fileAt( r.fileId, "super::" + CallResultTypes::joinModule( up, name ), r.fileId );
        }
        return fileAt( r.fileId, "self::" + CallResultTypes::joinModule( rest, name ), r.fileId );   // super::a::x in d/s.rs: d/a…
    }

    const IngestResult*                          m_ing = nullptr;
    std::vector<std::string_view>                m_crates;       // cratesOf
    std::vector<std::vector<std::string_view>>   m_uses;         // per file: its Rust `use` specifiers and `mod:x` records
    HashMap<std::string, std::string_view>       m_crateByName;  // a crate's path name → the crate ("" two crates share it)
    std::vector<std::uint8_t>                    m_extGlob;      // per file: 1 when it `use`s an out-of-tree glob (hasOutOfTreeGlob)
    mutable HashMap<std::string, std::uint32_t>  m_fileIndex;    // root-relative normalised path → fileId, built on first anchored path
};
// FN-SLOT part 2: a ModuleType (Rust) slot type's key — the in-tree STRUCT symbol the written path reaches (RustPaths: a bare
// name its own file's, else its crate's, else the repo's only one; a module path the file it resolves to), as jsImportKey( symbolId, name ); "" when no struct or several of one tier carry the
// name (an out-of-tree type, or which one is unknown: the name tier); kNoSlot when the name is a path through a TYPE (`E::V`, a
// variant: no field slot of a struct).
class RustTypeKeys
{
public:
    void build( const IngestResult& ing )
    {
        for( NodeId id = 0; id < ing.symbols.size(); ++id )
        {
            const Symbol& sym = ing.symbols[id];
            if( ( sym.kind == SymKind::Struct || sym.kind == SymKind::Class ) && slotTypeKeyOf( sym.lang ) == VrSlotTypeKey::ModuleType )   // a Rust struct is a class row
            {
                m_structs[ sym.name ].push_back( id );
            }
        }
        if( !m_structs.empty() )
        {
            m_paths.build( ing );
        }
    }
    static std::string keyOfSymbol( const Symbol& s, NodeId id ) { return jsImportKey( id, s.name ); }
    std::string keyOf( const IngestResult& ing, const Reference& r ) const
    {
        const std::string_view t = r.memberCtor;
        if( t.empty() || m_structs.empty() )
        {
            return {};
        }
        const std::size_t      at     = t.rfind( "::" );
        const std::string_view name   = at == std::string_view::npos ? t : t.substr( at + 2 );
        const std::string_view module = at == std::string_view::npos ? std::string_view() : t.substr( 0, at );
        const std::size_t      up     = module.rfind( "::" );
        const std::string_view last   = up == std::string_view::npos ? module : module.substr( up + 2 );
        if( !last.empty() && last[0] >= 'A' && last[0] <= 'Z' )
        {
            return std::string( kNoSlot );   // `E::V`: a variant, no struct's field
        }
        const RustPaths::At reach = m_paths.reach( r, module, name );
        if( reach.kind == RustPaths::Reach::None )
        {
            return std::string( kNoSlot );   // an out-of-tree or undecidable type (`extcrate::Hook`, `std::…`): no in-tree slot
        }
        const auto it = m_structs.find( std::string( name ) );
        if( it == m_structs.end() )
        {
            return {};
        }
        const NodeId id = m_paths.nearestOf( it->second, r.fileId, reach );
        return id == kNoNode ? std::string() : keyOfSymbol( ing.symbols[id], id );
    }

private:
    HashMap<std::string, std::vector<NodeId>> m_structs;   // struct name → the in-tree Rust structs of that name
    RustPaths                                 m_paths;     // built when any Rust struct exists
};
// The type key of every language that keys its own types (model.h slotKeysOwnTypes), by its row's VrSlotTypeKey.
class TypeKeys
{
public:
    void build( const IngestResult& ing )
    {
        m_ing = &ing;
        m_go.build( ing );
        m_rust.build( ing );
    }
    // A switch with no default (rv-fn-slot-2 F-8): a new VrSlotTypeKey fails -Wswitch here instead of keying as a Go directory.
    // TypedefFacts keys nothing here (its slots key through SlotIndex's typedef facts; endOf and forslots never ask).
    std::string keyOf( const Reference& r )
    {
        switch( slotTypeKeyOf( r.lang ) )
        {
            case VrSlotTypeKey::PackageDir:   return m_go.keyOf( r );
            case VrSlotTypeKey::ModuleType:   return m_rust.keyOf( *m_ing, r );
            case VrSlotTypeKey::TypedefFacts: return {};
        }
        return {};
    }
    std::string keyOfSymbol( NodeId id ) const
    {
        const Symbol& s = m_ing->symbols[id];
        switch( slotTypeKeyOf( s.lang ) )
        {
            case VrSlotTypeKey::PackageDir:   return m_go.keyOfSymbol( s );
            case VrSlotTypeKey::ModuleType:   return RustTypeKeys::keyOfSymbol( s, id );
            case VrSlotTypeKey::TypedefFacts: return {};
        }
        return {};
    }

private:
    const IngestResult* m_ing = nullptr;
    GoTypeKeys          m_go;
    RustTypeKeys        m_rust;
};
// The member calls `x.F( … )` of a MemberCallByName language whose field F holds a stored function somewhere (`holds`), as calls
// through that slot, in reference order. Not when that language defines a METHOD named F anywhere in the tree: the call may
// then be that method, and the receiver's type is not read here (a named floor, never a guess).
template<class Holds>
std::vector<std::uint32_t> memberCalls( const IngestResult& ing, const Holds& holds )
{
    std::vector<std::uint32_t> out;
    if( holds.empty() )
    {
        return out;
    }
    std::vector<std::string_view> methods;
    for( const Symbol& s : ing.symbols )
    {
        if( s.kind == SymKind::Method && slotJoinsByFieldName( s.lang ) && holds.contains( s.name ) )
        {
            methods.push_back( s.name );
        }
    }
    std::ranges::sort( methods, rw::sortutil::svLess );
    for( std::uint32_t i = 0; i < ing.references.size(); ++i )
    {
        const Reference& r = ing.references[i];
        if( r.role == RefRole::Call && r.memberCall && slotJoinsByFieldName( r.lang ) && holds.contains( r.calleeName )
            && !std::ranges::binary_search( methods, std::string_view( r.calleeName ), rw::sortutil::svLess ) )
        {
            out.push_back( i );
        }
    }
    return out;
}
// The registrars' parameters stored into field slots (model.h kValueRefSlotParamScope facts): an ARGUMENT row of a bare call
// `Reg( … )` (scope 'a', key "#k") lands in the slot parameter k of Reg is stored into. fix1 F-1: a fact is keyed by the
// registrar's DEFINITION (the symbol it is recorded in), and the argument row by the definitions its bare callee resolves to
// (ValueRefIndex::resolveName, the same rule the parameter join uses) — so a same-named function of another package that stores
// nothing, or a METHOD (a bare call never calls one), never feeds the slot. Every resolved definition must record the one same
// slot; one storing the parameter in two fields decides nothing.
class ParamSlots
{
public:
    void take( std::uint32_t refIdx ) { m_refs.push_back( refIdx ); }
    void build( const IngestResult& ing, TypeKeys& keys )
    {
        for( const std::uint32_t q : m_refs )
        {
            const Reference& r = ing.references[q];
            const bool       pathCalls = !slotPathSep( r.lang ).empty();   // a path call `T::f( … )` reaches an associated function
            if( r.fromSymbol >= ing.symbols.size() || ing.symbols[ r.fromSymbol ].name != r.recvVar
                || !( ing.symbols[ r.fromSymbol ].kind == SymKind::Function || ( pathCalls && ing.symbols[ r.fromSymbol ].kind == SymKind::Method ) ) )
            {
                continue;   // a method registrar no call of its language reaches by name, or a fact outside its own function's definition
            }
            const std::string to   = keys.keyOf( r ) + "#" + r.memberPath;
            std::string&      have = m_slot[ jsImportKey( r.fromSymbol, std::to_string( r.argCount ) ) ];
            have = have.empty() || have == to ? to : std::string( kConflict );
        }
    }
    // (type, field) of argument row `v`'s slot, or nothing; `ownersOf( v )` = the registrar definitions its bare callee resolves to.
    template<class OwnersOf>
    std::optional<std::pair<std::string, std::string>> slotOf( const Reference& v, const OwnersOf& ownersOf ) const
    {
        if( m_slot.empty() || !v.argCountKnown || v.recvVar.empty() || v.qualifier.empty() || v.qualifier[0] != 'a' )
        {
            return std::nullopt;
        }
        std::optional<std::string_view> to;
        for( const NodeId o : ownersOf( v ) )
        {
            const auto it = m_slot.find( jsImportKey( o, std::to_string( v.argCount ) ) );
            if( it == m_slot.end() || it->second == kConflict || ( to.has_value() && *to != it->second ) )
            {
                return std::nullopt;   // a resolved definition that stores nothing there, or two that disagree
            }
            to = it->second;
        }
        if( !to.has_value() )
        {
            return std::nullopt;
        }
        const std::size_t hash = to->rfind( '#' );
        return std::pair{ std::string( to->substr( 0, hash ) ), std::string( to->substr( hash + 1 ) ) };
    }

private:
    static constexpr std::string_view kConflict = "\x01";
    std::vector<std::uint32_t>        m_refs;   // the facts, keyed in build() (the type key by its file, TypeKeys)
    HashMap<std::string, std::string> m_slot;   // "registrarId#k" → "TypeKey#field" (kConflict: two different slots)
};
// `extra` (ascending) merged into the slot calls and their per-function lists, all kept in reference order (join() and callsIn()
// binary-search them).
inline void addCalls( const IngestResult& ing, const std::vector<std::uint32_t>& extra, std::vector<std::uint32_t>& calls,
                      HashMap<NodeId, std::vector<std::uint32_t>>& bySym )
{
    const bool resort = !calls.empty() && !extra.empty();
    for( const std::uint32_t c : extra )
    {
        calls.push_back( c );
        bySym[ ing.references[c].fromSymbol ].push_back( c );
    }
    if( resort )
    {
        std::ranges::sort( calls );
        for( auto& [ sym, list ] : bySym )
        {
            std::ranges::sort( list );
        }
    }
}
}   // namespace slot_join

// ── IX-1 slot-type join ──────────────────────────────────────────────────────────────────────────────────
// A function stored in struct field T.f (a Value row with a slot, ingest_valuerefs.h valueSlot) MAY be called by every call
// through a field f (`x->f( … )`, a slot Through, scope 's'): via="slot" when both sides' declared struct types resolve to the
// same T, via="slot-name" when one side's type is unknown; two KNOWN, different types never join (two different slots —
// `item->cb` never calls what `.cb` of another struct holds; the typedef aliases the facts record are resolved first). Never
// a proven call and never an edge: no count= / reaches= reads it. Built by ValueRefIndex (take, then build).
class SlotIndex
{
public:
    struct Hit
    {
        std::uint32_t ref   = 0;       // the other side's reference index
        bool          typed = false;   // same declared type (via="slot"), else field name only (via="slot-name")
    };

    // Takes reference `i` when it belongs here (a slot fact, scope 't'; a slot call, scope 's'), so the value index skips it.
    bool take( std::uint32_t i, const Reference& r )
    {
        const char sc = r.qualifier.empty() ? 'x' : r.qualifier[0];
        if( r.role == RefRole::Value && sc == kValueRefSlotFactScope )
        {
            addFact( r );
            return true;
        }
        if( r.role == RefRole::Through && sc == kValueRefSlotCallScope )
        {
            m_calls.push_back( i );
            m_callsBySym[ r.fromSymbol ].push_back( i );
            return true;
        }
        if( r.role == RefRole::Value && sc == kValueRefSlotParamScope )
        {
            m_params.take( i );   // IX1-V2: a registrar's parameter stored into a field slot
            return true;
        }
        if( r.role == RefRole::Value && sc == kValueRefRegParamScope )
        {
            return true;   // REGISTRAR: a container-store fact, read by src/regindex.h only — never a value row here
        }
        return false;
    }
    // fix1 F-1: how an argument row's bare callee resolves to its definitions (the registrars, ParamSlots) — before build().
    void resolveCalleesBy( std::function<std::vector<NodeId>( const Reference& )> ownersOf ) { m_ownersOf = std::move( ownersOf ); }
    // FN-SLOT S2 fix 1: the scope path (enclosing named namespaces and classes, "::"-joined, "" = global) a class named `name` is
    // defined in; nullopt when no body fact names it, or two files define it in different scopes.
    std::optional<std::string_view> bodyScope( std::string_view name ) const
    {
        const auto it = m_bodyScope.find( std::string( name ) );
        if( it == m_bodyScope.end() || it->second == kConflict )
        {
            return std::nullopt;
        }
        return std::string_view( it->second ).substr( 1 );
    }
    // After every take: keys the slot values (`values`, ascending, with their resolved `targets`) and the calls by field.
    void build( const IngestResult& ing, std::span<const std::uint32_t> values, std::span<const std::vector<NodeId>> targets )
    {
        m_keys.build( ing );
        m_params.build( ing, m_keys );
        for( std::size_t k = 0; k < values.size(); ++k )
        {
            if( targets[k].empty() )
            {
                continue;
            }
            const Reference& v = ing.references[ values[k] ];
            if( !v.memberPath.empty() )
            {
                m_values.push_back( endOf( ing, values[k] ) );
            }
            else if( const auto ps = m_ownersOf ? m_params.slotOf( v, m_ownersOf ) : std::nullopt )
            {
                m_values.push_back( { values[k], ps->first, ps->second, valueRefFamily( v.lang ) } );   // IX1-V2: `Reg( Put )`, Reg storing that parameter in a field
            }
            else
            {
                continue;
            }
            m_valuesByField[ m_values.back().field ].push_back( static_cast<std::uint32_t>( m_values.size() - 1 ) );
        }
        slot_join::addCalls( ing, slot_join::memberCalls( ing, m_valuesByField ), m_calls, m_callsBySym );   // IX1-V2: a MemberCallByName slot's calls
        if( m_calls.empty() )
        {
            return;   // no call through a struct field anywhere: no value needs a slot key
        }
        m_callEnds.reserve( m_calls.size() );
        for( const std::uint32_t c : m_calls )
        {
            m_callEnds.push_back( endOf( ing, c ) );
            m_callsByField[ m_callEnds.back().field ].push_back( static_cast<std::uint32_t>( m_callEnds.size() - 1 ) );
        }
    }

    // The slot calls that may call through the slot value reference `valueIdx` lands in (empty: not a struct-field slot).
    std::vector<Hit> callsFor( std::uint32_t valueIdx ) const { return join( m_values, valueIdx, m_callsByField, m_callEnds ); }
    // The slot value references (with a resolved function) the slot call `callIdx` may call through.
    std::vector<Hit> valuesFor( std::uint32_t callIdx ) const { return join( m_callEnds, callIdx, m_valuesByField, m_values ); }
    // fix1 F-2: the slot type key of a struct symbol of a language that keys its own types (model.h slotKeysOwnTypes), as
    // valuesOfType reads it (the store side keys the same way)
    std::string typeKeyOf( NodeId id ) const { return m_keys.keyOfSymbol( id ); }
    // IX1-V2: the slot value references stored into a field of struct type `type` (the resolved type name), with the field,
    // in reference order — what --for's slot_fields= lists on a struct row.
    std::vector<std::pair<std::uint32_t, std::string_view>> valuesOfType( std::string_view type ) const
    {
        std::vector<std::pair<std::uint32_t, std::string_view>> out;
        for( const End& e : m_values )
        {
            if( e.type == type )
            {
                out.emplace_back( e.ref, e.field );
            }
        }
        return out;
    }
    // The slot calls made inside function `f`, ascending.
    std::span<const std::uint32_t> callsIn( NodeId f ) const
    {
        const auto it = m_callsBySym.find( f );
        return it == m_callsBySym.end() ? std::span<const std::uint32_t>() : std::span<const std::uint32_t>( it->second );
    }
    // The resolved "Type.field" of slot call `callIdx` (".field" when the type is unknown; an anonymous struct is "@LINE").
    std::string nameOf( std::uint32_t callIdx ) const
    {
        const End* e = find( m_callEnds, callIdx );
        if( e == nullptr )
        {
            return {};
        }
        if( e->type == kConflict )
        {
            return "." + e->field;
        }
        // an anonymous struct's "@LINE#file" prints "@LINE"; an own-keyed type's "id#Name" (TypeKeys) prints its name
        const std::size_t      hash = e->type.find( '#' );
        const std::string_view t    = e->type.starts_with( '@' ) ? std::string_view( e->type ).substr( 0, hash )
                                    : hash == std::string::npos ? std::string_view( e->type ) : std::string_view( e->type ).substr( hash + 1 );
        return std::string( t ) + "." + e->field;
    }

private:
    struct End
    {
        std::uint32_t ref = 0;
        std::string   type;    // the resolved declared struct type, "" unknown
        std::string   field;
        VrLangFamily  fam = VrLangFamily::None;   // fix1 F-3: the value-ref family; a slot never joins across two
    };
    // An anonymous struct's "@LINE" key is unique in its own file only: the file joins the key.
    static std::string canonType( std::string_view t, std::uint32_t fileId )
    {
        if( t.starts_with( kValueRefSlotTagMark ) )
        {
            return kValueRefSlotTagMark + canonType( t.substr( 1 ), fileId );
        }
        return t.starts_with( '@' ) ? std::string( t ) + "#" + std::to_string( fileId ) : std::string( t );
    }
    // A type no end resolves to: an alias or field type the facts spell two different ways. It joins NOTHING (not even the
    // name tier): which struct is meant is unknown, and a guess may be the wrong one.
    static constexpr std::string_view kConflict = "\x01";
    // Records name → to; a second, different spelling of the same name marks it a conflict (unlike an unknown "", which
    // still joins by name).
    static void noteFact( HashMap<std::string, std::string>& m, const std::string& name, const std::string& to )
    {
        std::string& have = m[ name ];
        have = have.empty() || have == to ? to : std::string( kConflict );
    }
    void addFact( const Reference& r )
    {
        const std::string to = canonType( r.memberCtor, r.fileId );
        if( !r.composeRel.empty() && r.composeRel[0] == kValueRefSlotBodyRel )
        {
            // a struct body (`to` is its digest): the same tag or name with a DIFFERENT body in another file is no one type
            noteFact( m_body, r.recvVar, to );
            noteFact( m_bodyScope, r.recvVar, "." + r.composeRel.substr( 1 ) );   // FN-SLOT S2 fix 1: where it is defined ("." = the global scope)
            return;
        }
        if( r.composeRel.empty() )
        {
            // `typedef struct tag NAME;`: the file's own spelling, and the repo's (agreed by every file, or a conflict)
            noteFact( m_aliasInFile, jsImportKey( r.fileId, r.recvVar ), to );
            noteFact( m_alias, r.recvVar, to );
        }
        else
        {
            noteFact( m_fieldType, canonType( r.recvVar, r.fileId ) + "#" + r.composeRel, to );
        }
    }
    // A type through the aliases as file `fileId` sees them: its own typedef first, else the repo's one agreed spelling (a
    // header's); kConflict when the name is spelled two ways and the file does not decide it.
    std::string unalias( std::string t, std::uint32_t fileId ) const
    {
        for( int hop = 0; hop < 4 && t != kConflict && !t.starts_with( kValueRefSlotTagMark ); ++hop )   // `typedef struct a b; typedef b c;`: a short chain, cut (never a cycle)
        {
            auto it = m_aliasInFile.find( jsImportKey( fileId, t ) );
            if( it == m_aliasInFile.end() )
            {
                it = m_alias.find( t );
                if( it == m_alias.end() )
                {
                    break;
                }
            }
            if( it->second == t )
            {
                break;
            }
            t = it->second;
        }
        if( t.starts_with( kValueRefSlotTagMark ) )
        {
            t.erase( 0, 1 );   // spelled `struct X`: the tag, which no typedef name renames
        }
        const auto body = m_body.find( t );
        return body != m_body.end() && body->second == kConflict ? std::string( kConflict ) : t;
    }
    // The slot of a slot reference: the root's type through the typedef aliases, then each field of the chain through the
    // field-type facts; a hop the facts do not know leaves the type unknown (the name tier).
    End endOf( const IngestResult& ing, std::uint32_t refIdx )
    {
        const Reference& r = ing.references[refIdx];
        End              e;
        e.ref = refIdx;
        e.fam = valueRefFamily( r.lang );
        if( r.role == RefRole::Call || slotKeysOwnTypes( r.lang ) )
        {
            // IX1-V2: a member call `x.F( … )` (slot_join::memberCalls, its receiver's type unread: the name tier), or a store of a
            // language that keys its own types (Go: package-qualified; no typedef aliases or field-type facts on this side)
            e.type  = r.role == RefRole::Call ? std::string() : m_keys.keyOf( r );
            e.field = r.role == RefRole::Call ? r.calleeName : r.memberPath;
            return e;
        }
        std::string_view chain = r.memberPath;
        std::string      t     = r.memberCtor.empty() ? std::string() : unalias( canonType( r.memberCtor, r.fileId ), r.fileId );
        if( t.starts_with( kVrSlotMacroCastMark ) )
        {
            t.clear();   // FN-SLOT S2 (c): a macro / function call root no cast fact resolves: the name tier
        }
        for( std::size_t dot = chain.find( '.' ); dot != std::string_view::npos; dot = chain.find( '.' ) )
        {
            if( !t.empty() && t != kConflict )
            {
                const auto it = m_fieldType.find( t + "#" + std::string( chain.substr( 0, dot ) ) );
                t = it == m_fieldType.end() ? std::string() : unalias( it->second, r.fileId );
            }
            chain.remove_prefix( dot + 1 );
        }
        e.type  = std::move( t );
        e.field = std::string( chain );
        return e;
    }
    static const End* find( const std::vector<End>& ends, std::uint32_t ref ) noexcept
    {
        const auto it = std::ranges::lower_bound( ends, ref, {}, &End::ref );
        return it != ends.end() && it->ref == ref ? &*it : nullptr;
    }
    // One side's end `ref` against every end of the other side with the same field: same type → typed; a side's type
    // unknown → the name tier; two known, different types → no hit.
    static std::vector<Hit> join( const std::vector<End>& side, std::uint32_t ref, const HashMap<std::string, std::vector<std::uint32_t>>& byField,
                                  const std::vector<End>& other )
    {
        std::vector<Hit> out;
        const End*       e = find( side, ref );
        const auto       it = e == nullptr || e->type == kConflict ? byField.end() : byField.find( e->field );
        if( it == byField.end() )
        {
            return out;
        }
        for( const std::uint32_t k : it->second )
        {
            const End& o = other[k];
            if( o.type == kConflict || o.fam != e->fam )
            {
                continue;   // fix1 F-3: a Go member call never runs what a C function-pointer field holds, nor the reverse
            }
            if( e->type.empty() || o.type.empty() || e->type == o.type )
            {
                out.push_back( { o.ref, !e->type.empty() && e->type == o.type } );
            }
        }
        return out;
    }

    HashMap<std::string, std::string>                m_fieldType;      // "Type#field" → that field's struct type
    HashMap<std::string, std::string>                m_alias;          // typedef name → struct type (kConflict: files disagree)
    HashMap<std::string, std::string>                m_aliasInFile;    // "fileId#name" → struct type, the file's own typedef
    HashMap<std::string, std::string>                m_body;           // struct type → its body's digest (kConflict: files differ)
    HashMap<std::string, std::string>                m_bodyScope;      // class name → "." + its scope path (kConflict: files differ)
    slot_join::ParamSlots                            m_params;         // IX1-V2: registrars' parameters stored into field slots
    slot_join::TypeKeys                              m_keys;           // fix1 F-2 / part 2: Go and Rust type keys
    std::function<std::vector<NodeId>( const Reference& )> m_ownersOf;  // fix1 F-1: a bare callee's definitions
    std::vector<std::uint32_t>                       m_calls;          // slot Through references, ascending
    HashMap<NodeId, std::vector<std::uint32_t>>      m_callsBySym;     // calling function → its slot Through references
    std::vector<End>                                 m_values;         // slot Value rows with a resolved function, by ref
    std::vector<End>                                 m_callEnds;       // parallel to m_calls
    HashMap<std::string, std::vector<std::uint32_t>> m_valuesByField;  // field → positions in m_values
    HashMap<std::string, std::vector<std::uint32_t>> m_callsByField;   // field → positions in m_callEnds
};

// class name → the base names it is written to extend (the inherit references, derived → base), name-keyed; one copy for the
// value index's member-pointer candidates (`struct D : B` and `class D : B`).
inline HashMap<std::string, std::vector<std::string>> inheritEdges( const IngestResult& ing )
{
    HashMap<std::string, std::vector<std::string>> out;
    for( const Reference& r : ing.references )
    {
        if( !( r.isInherit || r.role == RefRole::Extends ) || r.fromSymbol >= ing.symbols.size() )
        {
            continue;
        }
        const Symbol& from = ing.symbols[ r.fromSymbol ];
        if( ( from.kind != SymKind::Class && from.kind != SymKind::Struct ) || r.baseBind == kBaseBindTemplateParam )   // a template parameter, no class
        {
            continue;
        }
        std::vector<std::string>& b = out[ from.name ];
        if( std::ranges::find( b, r.calleeName ) == b.end() )
        {
            b.push_back( r.calleeName );
        }
    }
    return out;
}

// The index every verb queries. Built from one IngestResult in O(refs + symbols); no graph needed.
class ValueRefIndex
{
public:
    explicit ValueRefIndex( const IngestResult& ing ) : m_ing( ing ) { index( nullptr ); }
    // fix1 (RSS): a NARROW index — what --for's slot splice (forslots.h spliceSlotJoinRows) reads, and nothing else: the Value
    // references naming one of `names` (sorted by svLess: the shown functions), every slot STORE (a struct-field value, an argument
    // of a registrar that stores its parameter in a field: the cands=, K and @C counts need the whole slot), every slot fact and
    // slot call, and the Throughs those kept values join (their container, the parameter calls of their callee). Every query the
    // splice makes answers the same as on the full index, by construction; the by-name table holds only the names they resolve.
    static ValueRefIndex narrowFor( const IngestResult& ing, std::span<const std::string_view> names ) { return ValueRefIndex( Narrowed{ ing, keepSets( ing, names ) } ); }

    const SlotIndex& slots() const noexcept { return m_slots; }   // IX-1: the struct-field slot join

    // The files that the JS/TS/Python imports of file `fileId` binding `name` resolve to, in import order (none: no such import, or
    // a package outside the tree). The import's module is resolved by the call graph's own Step-A (resolve.h resolvePreciseInclude:
    // a relative JS/TS specifier against the importer, a Python module relative-to-file then root, then the whole-component suffix
    // for an absolute Python spec). A bare package specifier resolves to no file: no row — a stem match across directories bound
    // `import { test } from "./a"` to every a.js. resolveName and the class-base check of handlerrule.h read this one rule.
    std::vector<std::uint32_t> importedFilesBinding( std::uint32_t fileId, std::string_view name ) const
    {
        std::vector<std::uint32_t> out;
        const auto                 imp = m_importsByFile.find( fileId );
        if( imp == m_importsByFile.end() )
        {
            return out;
        }
        for( const Binding* b : imp->second )
        {
            const bool named = b->kind == LocalBindKind::JsImport ? ( b->var == name && b->importedName == name )
                                                                 : ( b->var == name && b->importedName.empty() );
            if( const std::uint32_t moduleFile = named ? importedModuleFile( *b ) : kNoFile; moduleFile != kNoFile )
            {
                out.push_back( moduleFile );
            }
        }
        return out;
    }

    // Value references (indices into ing.references) whose resolved target is any of `defs`, in served order.
    std::vector<std::uint32_t> valueRefsTo( std::span<const NodeId> defs ) const
    {
        std::vector<std::uint32_t> out;
        for( const NodeId d : defs )
        {
            if( const auto it = m_valuesByTarget.find( d ); it != m_valuesByTarget.end() )
            {
                for( const std::uint32_t k : it->second )
                {
                    out.push_back( m_values[k] );
                }
            }
        }
        std::ranges::sort( out );
        out.erase( std::ranges::unique( out ).begin(), out.end() );
        return out;
    }

    // True when at least one value reference resolves to `def` and can make it reachable: the dead-set question
    // (--dead-code, --quality-delta). A Python descriptor/typing WRAPPER decorator row does not count. `@classmethod`,
    // `@property` or `@functools.wraps` hands the function back to the same name, so it is still reached only by a
    // call. A registering decorator (`@app.route`, `@register`) is the value use this exclusion exists for. The row
    // itself is still served (ruling 5); the wrapper FLOOR for rows is a follow-up.
    // A reference made INSIDE `def` itself (`static void tick( void ) { timer_set( tick ); }`) does not count either: it
    // can only run once something else reaches `def`, exactly as the call graph drops a recursive self-call (the CSR has
    // no self-loops). The row is still served and is still a use site (--safe-delete's uses=).
    bool isValueReferenced( NodeId def ) const
    {
        const auto it = m_valuesByTarget.find( def );
        if( it == m_valuesByTarget.end() )
        {
            return false;
        }
        return std::ranges::any_of( it->second, [ & ]( std::uint32_t k )
        {
            const Reference& r = m_ing.references[ m_values[k] ];
            return r.fromSymbol != def && !vrIsWrapperDecorator( r.fieldName );
        } );
    }

    // The value walk's depth cut (ingest_valuerefs.h kVrMaxDepth) as it bears on an answer about `defs`: how many files
    // of the defs' language families stopped their walk at the cap (a value reference below it was never captured, so a
    // value_refs= count is a FLOOR there), and the first such record by path then line (the clue, value_refs_depth_at=).
    // `everyFamily` asks about every armed family (--dead-code's whole-tree answer). Only functions and methods have
    // value references, so a def of another kind brings no family in, and no def brings none.
    struct DepthCuts
    {
        std::uint32_t files = 0;
        std::uint32_t first = UINT32_MAX;   // a reference index, UINT32_MAX when files == 0
    };
    DepthCuts depthCutsFor( std::span<const NodeId> defs, bool everyFamily = false ) const
    {
        DepthCuts out;
        for( const std::uint32_t i : m_depthCuts )
        {
            const Reference&   c   = m_ing.references[i];
            const VrLangFamily fam = valueRefFamily( c.lang );
            const bool relevant = everyFamily || std::ranges::any_of( defs, [ & ]( NodeId d )
            {
                const Symbol& s = m_ing.symbols[d];
                return ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && valueRefFamily( s.lang ) == fam;
            } );
            if( !relevant )
            {
                continue;
            }
            ++out.files;
            if( out.first == UINT32_MAX || vrBindLess( m_ing, c, m_ing.references[ out.first ] ) )
            {
                out.first = i;
            }
        }
        return out;
    }

    // The resolved targets of value reference `refIdx` (an index into ing.references).
    std::vector<NodeId> targetsOf( std::uint32_t refIdx ) const
    {
        const auto it = std::lower_bound( m_values.begin(), m_values.end(), refIdx );
        if( it == m_values.end() || *it != refIdx )
        {
            return {};
        }
        return m_targets[ static_cast<std::size_t>( it - m_values.begin() ) ];
    }

    // called_by=: the functions that may call through the slot value reference `refIdx` lands in, sorted by name.
    std::vector<NodeId> calledBy( std::uint32_t refIdx ) const
    {
        std::vector<NodeId> out;
        for( const std::uint32_t t : throughsFor( refIdx ) )
        {
            const NodeId f = m_ing.references[t].fromSymbol;
            if( f != kNoNode )
            {
                out.push_back( f );
            }
        }
        std::sort( out.begin(), out.end(), [ & ]( NodeId a, NodeId b )
        {
            const Symbol& sa = m_ing.symbols[a];
            const Symbol& sb = m_ing.symbols[b];
            return sa.name != sb.name ? sa.name < sb.name : a < b;
        } );
        out.erase( std::unique( out.begin(), out.end() ), out.end() );
        return out;
    }

    // The Through references matching value reference `refIdx` (indices into ing.references).
    std::vector<std::uint32_t> throughsFor( std::uint32_t refIdx ) const
    {
        const Reference&           v = m_ing.references[refIdx];
        std::vector<std::uint32_t> out;
        const char                 sc = scopeOf( v );
        if( sc == 'f' || sc == 'l' )
        {
            if( const auto it = m_throughByContainer.find( jsImportKey( v.fileId, v.recvVar ) ); it != m_throughByContainer.end() )
            {
                for( const std::uint32_t t : it->second )
                {
                    const Reference& tr = m_ing.references[t];
                    if( scopeOf( tr ) == sc && ( sc == 'f' || tr.fromSymbol == v.fromSymbol ) && vrKeyMatches( tr.composeRel, v.composeRel ) )
                    {
                        out.push_back( t );
                    }
                }
            }
        }
        else if( sc == 'a' || sc == 'p' )
        {
            // an argument of a bare callee: the callee's definitions that CALL that parameter; a parameter default: the
            // function the default belongs to.
            std::vector<NodeId> owners = sc == 'a' ? resolveName( v, v.recvVar ) : std::vector<NodeId>{ v.fromSymbol };
            for( const NodeId o : owners )
            {
                const auto it = m_throughParamBySym.find( o );
                if( o == kNoNode || it == m_throughParamBySym.end() )
                {
                    continue;
                }
                for( const std::uint32_t t : it->second )
                {
                    const Reference& tr = m_ing.references[t];
                    if( paramMatches( v.composeRel, tr ) )
                    {
                        out.push_back( t );
                    }
                }
            }
        }
        std::ranges::sort( out );
        out.erase( std::ranges::unique( out ).begin(), out.end() );
        return out;
    }

    // The value references a Through reference reaches (the callees side of the same join).
    std::vector<std::uint32_t> valuesThrough( std::uint32_t throughIdx ) const
    {
        const Reference&           t = m_ing.references[throughIdx];
        std::vector<std::uint32_t> out;
        const char                 sc = scopeOf( t );
        if( sc == 'f' || sc == 'l' )
        {
            if( const auto it = m_valueByContainer.find( jsImportKey( t.fileId, t.calleeName ) ); it != m_valueByContainer.end() )
            {
                for( const std::uint32_t v : it->second )
                {
                    const Reference& vr = m_ing.references[v];
                    if( scopeOf( vr ) == sc && ( sc == 'f' || vr.fromSymbol == t.fromSymbol ) && vrKeyMatches( t.composeRel, vr.composeRel ) )
                    {
                        out.push_back( v );
                    }
                }
            }
        }
        else if( sc == 'p' && t.fromSymbol != kNoNode )
        {
            // every argument of a bare call that resolves to this function, at this parameter; and its own default
            const Symbol& owner = m_ing.symbols[ t.fromSymbol ];
            for( const std::uint32_t v : m_values )
            {
                const Reference& vr  = m_ing.references[v];
                const char       vsc = scopeOf( vr );
                if( vsc == 'p' && vr.fromSymbol == t.fromSymbol && paramMatches( vr.composeRel, t ) )
                {
                    out.push_back( v );
                }
                else if( vsc == 'a' && vr.recvVar == owner.name && paramMatches( vr.composeRel, t ) )
                {
                    const std::vector<NodeId> owners = resolveName( vr, vr.recvVar );
                    if( std::find( owners.begin(), owners.end(), t.fromSymbol ) != owners.end() )
                    {
                        out.push_back( v );
                    }
                }
            }
        }
        std::ranges::sort( out );
        out.erase( std::ranges::unique( out ).begin(), out.end() );
        return out;
    }

    // Through references (role Through) or Value references (role Value) made inside any of `fns`.
    std::vector<std::uint32_t> madeIn( std::span<const NodeId> fns, RefRole role ) const
    {
        std::vector<std::uint32_t> out;
        const auto inFns = [ & ]( std::uint32_t i ) { return std::ranges::find( fns, m_ing.references[i].fromSymbol ) != fns.end(); };
        if( role == RefRole::Value )
        {
            std::ranges::copy_if( m_values, std::back_inserter( out ), inFns );
            return out;
        }
        for( const auto& [ key, list ] : m_throughByContainer )
        {
            std::ranges::copy_if( list, std::back_inserter( out ), inFns );
        }
        for( const auto& [ sym, list ] : m_throughParamBySym )
        {
            if( std::ranges::find( fns, sym ) != fns.end() )
            {
                out.insert( out.end(), list.begin(), list.end() );
            }
        }
        std::ranges::sort( out );
        return out;
    }

    static char scopeOf( const Reference& r ) noexcept
    {
        return r.qualifier.empty() ? 'x' : r.qualifier[0];
    }

    // A class member, in every armed language: a Method, or a Python def directly in its class (public: PatternIndex reads it).
    bool isClassMember( const Symbol& s ) const noexcept
    {
        if( s.kind == SymKind::Method )
        {
            return true;
        }
        return s.lang == Lang::Python && s.id < m_pyMember.size() && m_pyMember[ s.id ] != 0;
    }

private:
    struct KeepSets;
    struct Narrowed;
    explicit ValueRefIndex( const Narrowed& n );
    // The tables (`keep` non-null: a narrow index, narrowFor).
    void index( const KeepSets* keep )
    {
        const IngestResult& ing = m_ing;
        for( NodeId id = 0; id < ing.symbols.size(); ++id )
        {
            const Symbol& s = ing.symbols[id];
            if( ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && valueRefFamily( s.lang ) != VrLangFamily::None
                && ( keep == nullptr || keep->names.contains( s.name ) ) )
            {
                m_fnByName[ s.name ].push_back( id );
            }
        }
        indexOwners( keep );
        markPythonMembers();
        for( std::uint32_t i = 0; i < ing.references.size(); ++i )
        {
            indexReference( i, keep );
        }
        for( const Binding& b : ing.bindings )
        {
            if( b.kind == LocalBindKind::JsImport || b.kind == LocalBindKind::Import )
            {
                m_importsByFile[ b.fileId ].push_back( &b );
            }
        }
        ENSURES( std::is_sorted( m_values.begin(), m_values.end() ), "m_values is built in reference order — targetsOf binary-searches it" );
        m_targets.resize( m_values.size() );
        for( std::size_t k = 0; k < m_values.size(); ++k )
        {
            m_targets[k] = resolveName( ing.references[ m_values[k] ], ing.references[ m_values[k] ].calleeName );
            for( const NodeId t : m_targets[k] )
            {
                m_valuesByTarget[ t ].push_back( static_cast<std::uint32_t>( k ) );
            }
        }
        m_slots.resolveCalleesBy( [ this ]( const Reference& v ) { return resolveCallee( v ); } );
        m_slots.build( ing, m_values, m_targets );
        m_slots.resolveCalleesBy( nullptr );   // it captured `this`: never outlives the build
    }
    // part 2: a path language's functions by owner type (`Editor::backspace`, ownedBy's "family#Owner::name"), and every file's
    // crate (slot_join::cratesOf) when such a language is indexed.
    void indexOwners( const KeepSets* keep )
    {
        bool pathLang = false;
        for( NodeId id = 0; id < m_ing.symbols.size(); ++id )
        {
            const Symbol& s = m_ing.symbols[id];
            if( slotPathSep( s.lang ).empty() )
            {
                continue;
            }
            pathLang = true;
            if( ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && !s.scope.empty() && ( keep == nullptr || keep->names.contains( s.name ) ) )
            {
                m_fnByOwner[ jsImportKey( static_cast<std::uint32_t>( valueRefFamily( s.lang ) ), s.scope + "::" + s.name ) ].push_back( id );
            }
        }
        if( pathLang )
        {
            m_paths.build( m_ing );
        }
    }
    // Reference `i` into its table (`keep` non-null: a narrow index, which skips what the splice never reads).
    void indexReference( std::uint32_t i, const KeepSets* keep )
    {
        const Reference& r = m_ing.references[i];
        if( m_slots.take( i, r ) )
        {
            return;   // IX-1: a slot fact or a call through a struct field (SlotIndex)
        }
        if( r.role == RefRole::Value && scopeOf( r ) == kValueRefDepthCutScope )
        {
            m_depthCuts.push_back( i );   // the file's depth-cut record: no row, a disclosure (depthCutsFor)
        }
        else if( r.role == RefRole::Value && ( keep == nullptr || keep->values.contains( i ) ) )
        {
            m_values.push_back( i );
            if( !r.recvVar.empty() )
            {
                m_valueByContainer[ jsImportKey( r.fileId, r.recvVar ) ].push_back( i );
            }
        }
        else if( r.role == RefRole::Through && ( keep == nullptr || keep->keepsThrough( m_ing, r ) ) )
        {
            if( scopeOf( r ) == 'p' )
            {
                m_throughParamBySym[ r.fromSymbol ].push_back( i );
            }
            else
            {
                m_throughByContainer[ jsImportKey( r.fileId, r.calleeName ) ].push_back( i );
            }
        }
    }
    // fix1 (RSS): what a narrow index keeps (narrowFor).
    struct KeepSets
    {
        HashMap<std::uint32_t, char> values;       // kept Value reference indices
        HashMap<std::string, char>   names;        // the names resolveName looks up: kept values' callees and their bare callees
        HashMap<std::string, char>   containers;   // "fileId#container" of the kept values
        HashMap<NodeId, char>        paramOwners;  // a kept parameter default's function
        bool keepsThrough( const IngestResult& ing, const Reference& t ) const
        {
            if( scopeOf( t ) == 'p' )
            {
                return paramOwners.contains( t.fromSymbol ) || ( t.fromSymbol < ing.symbols.size() && names.contains( ing.symbols[ t.fromSymbol ].name ) );
            }
            return containers.contains( jsImportKey( t.fileId, t.calleeName ) );
        }
    };
    struct Narrowed
    {
        const IngestResult& ing;
        KeepSets            keep;
    };
    static KeepSets keepSets( const IngestResult& ing, std::span<const std::string_view> names )
    {
        KeepSets                   k;
        HashMap<std::string, char> registrars;   // functions storing a parameter in a field slot (kValueRefSlotParamScope facts)
        for( const Reference& r : ing.references )
        {
            if( r.role == RefRole::Value && scopeOf( r ) == kValueRefSlotParamScope )
            {
                registrars.try_emplace( r.recvVar, char( 1 ) );
            }
        }
        for( std::uint32_t i = 0; i < ing.references.size(); ++i )
        {
            const Reference& r  = ing.references[i];
            const char       sc = scopeOf( r );
            if( r.role != RefRole::Value || isSlotJoinRecord( r ) || sc == kValueRefDepthCutScope )
            {
                continue;
            }
            const bool             named = std::ranges::binary_search( names, std::string_view( r.calleeName ), rw::sortutil::svLess );
            const std::string_view sep   = slotPathSep( r.lang );
            const std::size_t      at    = sep.empty() ? std::string::npos : r.recvVar.rfind( sep );
            const std::string      leaf  = at == std::string::npos ? r.recvVar : r.recvVar.substr( at + sep.size() );   // resolveCallee's name
            if( !named && r.memberPath.empty() && !( sc == 'a' && registrars.contains( leaf ) ) )
            {
                continue;
            }
            k.values.try_emplace( i, char( 1 ) );
            k.names.try_emplace( r.calleeName, char( 1 ) );
            if( sc == 'a' )
            {
                k.names.try_emplace( leaf, char( 1 ) );
            }
            else if( sc == 'p' )
            {
                k.paramOwners.try_emplace( r.fromSymbol, char( 1 ) );
            }
            if( !r.recvVar.empty() )
            {
                k.containers.try_emplace( jsImportKey( r.fileId, r.recvVar ), char( 1 ) );
            }
        }
        return k;
    }

    // A value key "#N" (an argument position) or "#name" (a keyword / a parameter default) against a parameter Through.
    static bool paramMatches( std::string_view valueKey, const Reference& through ) noexcept
    {
        if( valueKey.size() < 2 || valueKey.front() != '#' )
        {
            return false;
        }
        const std::string_view tail = valueKey.substr( 1 );
        if( tail.front() >= '0' && tail.front() <= '9' )
        {
            return through.argCountKnown && std::to_string( through.argCount ) == tail;
        }
        return through.calleeName == tail;
    }

    std::uint32_t importedModuleFile( const Binding& b ) const
    {
        if( b.typeName.empty() || b.fileId >= m_ing.files.size() )
        {
            return kNoFile;
        }
        if( m_fileIndex.empty() )
        {
            m_fileIndex.reserve( m_ing.files.size() );
            for( std::uint32_t f = 0; f < m_ing.files.size(); ++f )
            {
                m_fileIndex.emplace( lexicalNormalize( rootRelPath( m_ing, f ) ), f );
            }
        }
        const std::uint32_t precise = resolvePreciseInclude( rootRelPath( m_ing, b.fileId ), b.typeName, /*isAngle=*/false, m_fileIndex );
        if( precise != kNoFile || b.kind != LocalBindKind::Import )
        {
            return precise;
        }
        return resolvePythonModuleSuffix( b.typeName, m_fileIndex, m_ing.fileRoot.empty() ? nullptr : &m_ing.fileRoot, b.fileId );
    }

    // Python's tags.scm has no @definition.method: every `def` is a Function, and its `scope` is the nearest
    // enclosing class at ANY depth (a helper nested inside a method carries the class too). A Function is a class
    // MEMBER only when its innermost enclosing definition is that class itself, which this sweep decides from the
    // def spans: per file, defs sorted by start (widest first), a stack of the open ones.
    void markPythonMembers()
    {
        std::vector<NodeId> py;
        for( NodeId id = 0; id < m_ing.symbols.size(); ++id )
        {
            const Symbol& s = m_ing.symbols[id];
            if( s.lang == Lang::Python
                && ( s.kind == SymKind::Function || s.kind == SymKind::Method || s.kind == SymKind::Class ) )
            {
                py.push_back( id );
            }
        }
        if( py.empty() )
        {
            return;
        }
        m_pyMember.assign( m_ing.symbols.size(), 0 );
        std::ranges::sort( py, [ & ]( NodeId a, NodeId b )
        {
            const Symbol& x = m_ing.symbols[a];
            const Symbol& y = m_ing.symbols[b];
            if( x.fileId != y.fileId )
            {
                return x.fileId < y.fileId;
            }
            if( x.sigStartByte != y.sigStartByte )
            {
                return x.sigStartByte < y.sigStartByte;
            }
            return x.endByte != y.endByte ? x.endByte > y.endByte : a < b;
        } );
        std::vector<NodeId> open;
        for( const NodeId id : py )
        {
            const Symbol& s = m_ing.symbols[id];
            while( !open.empty() )
            {
                const Symbol& o = m_ing.symbols[ open.back() ];
                if( o.fileId == s.fileId && o.sigStartByte <= s.sigStartByte && s.endByte <= o.endByte )
                {
                    break;
                }
                open.pop_back();
            }
            if( s.kind != SymKind::Class && !s.scope.empty() && !open.empty() )
            {
                const Symbol& owner = m_ing.symbols[ open.back() ];
                m_pyMember[id] = owner.kind == SymKind::Class && owner.name == s.scope ? 1 : 0;
            }
            open.push_back( id );
        }
    }

    // Is the class member `m` in bare-name scope at reference `r`? The call graph's own visibility, per language:
    //   * a decorator row names the definition it decorates — the decorated def itself, in this file;
    //   * Python: only the class BODY sees its members bare (`__str__ = render`, `property( _get )`); a method body
    //     does not (`sorted( xs, key=sibling )` is a NameError), nor does any other code (`isinstance( x, (list,
    //     tuple) )` never means a method named `list`);
    //   * C++: the class body, and any member function of the same class (in-class or `T::f` out of class);
    //   * JS/TS: never — a method is reached through `this`/an instance, a bare name is a binding or a global
    //     (the JS call graph binds a bare `render()` to a method by name; this resolver deliberately does not);
    //   * Go: never — a method value is always `recv.M`.
    bool memberVisibleFrom( const Reference& r, const Symbol& m, VrLangFamily fam ) const
    {
        if( r.role == RefRole::Value && r.fieldName.starts_with( '@' ) )
        {
            return m.fileId == r.fileId;
        }
        if( ( fam != VrLangFamily::Py && fam != VrLangFamily::C ) || r.fromSymbol == kNoNode || r.fromSymbol >= m_ing.symbols.size()
            || m.scope.empty() )
        {
            return false;
        }
        const Symbol& f      = m_ing.symbols[ r.fromSymbol ];
        const bool    fIsFn  = f.kind == SymKind::Function || f.kind == SymKind::Method;
        const bool    fClass = ( f.kind == SymKind::Class || isStructOrNamedType( f.kind ) ) && f.name == m.scope;
        // a statement of the class body (owned by the class, or by an annotated attribute of it); a Python NESTED class's
        // body does not see the outer class's names, a C++ one does
        const bool    inBody = !fIsFn && f.fileId == m.fileId
                            && ( fClass || ( f.scope == m.scope && ( fam == VrLangFamily::C || f.kind != SymKind::Class ) ) );
        if( inBody )
        {
            return true;   // the class body itself
        }
        return fam == VrLangFamily::C && fIsFn && f.scope == m.scope;   // a C++ member function of the same class
    }

    // The method-value owner rule (rv-fn-slot part-2 piece 3): `fns` (one name's functions) owned by type `owner`, as reference
    // `r`'s language means it. Go (a method value `b.opPlan` of the enclosing method's receiver, ingest_valuerefs.h methodValueAt):
    // that type's METHOD in r's own package directory. Rust (`Editor::backspace`, `Self::f` with Self resolved, `module` the path
    // written before the type): the owner type's function of that name in the crate the type's path reaches (slot_join::RustPaths;
    // a bare type: nearest r — its own file, else its crate, else the repo's only one), else nothing.
    std::vector<NodeId> ownedBy( const Reference& r, std::string_view owner, std::span<const NodeId> fns, std::string_view module = {} ) const
    {
        const VrLangFamily fam = valueRefFamily( r.lang );
        if( !slotPathSep( r.lang ).empty() )
        {
            const auto it = fns.empty() ? m_fnByOwner.end() : m_fnByOwner.find( jsImportKey( static_cast<std::uint32_t>( fam ), std::string( owner ) + "::" + m_ing.symbols[ fns.front() ].name ) );
            if( it == m_fnByOwner.end() )
            {
                return {};
            }
            using Reach              = slot_join::RustPaths::Reach;
            slot_join::RustPaths::At at = m_paths.reach( r, module, owner );
            if( at.kind == Reach::File || at.kind == Reach::Crate || at.kind == Reach::CrateRoot )
            {
                // the type's own crate (an impl lives in its type's crate, not always its file)
                at = { Reach::InCrate, false, kNoFile, at.kind == Reach::File ? m_paths.crateOf( at.file ) : at.crate };
            }
            const NodeId one = m_paths.nearestOf( it->second, r.fileId, at );
            return one == kNoNode ? std::vector<NodeId>{} : std::vector<NodeId>{ one };
        }
        if( fam == VrLangFamily::C )
        {
            return memberOf( owner, fns, module );
        }
        std::vector<NodeId> out;
        for( const NodeId id : fns )
        {
            const Symbol& s = m_ing.symbols[id];
            if( s.kind == SymKind::Method && valueRefFamily( s.lang ) == fam && s.scope == owner
                && includerDir( m_ing.files[ s.fileId ] ) == includerDir( m_ing.files[ r.fileId ] ) )
            {
                out.push_back( id );
            }
        }
        return out;
    }
    // FN-SLOT S2 (C++ `&Cls::m`): the methods a pointer to `owner`'s member `m` (`fns` = the functions named m) MAY run, as a
    // candidate SET: the definitions with a body of the declaring class (owner itself, else — F-3 — the nearest base that
    // defines m) and of every class derived from owner (F-1: a virtual m dispatches on the dynamic type; a non-virtual one an
    // override merely hides is a hedge, never a pin); else the declaring class's bodyless declarations, but a class with an
    // override never pins its own bodyless (possibly pure virtual) declaration. A symbol's scope is the innermost class name
    // only (no namespace), so when the repo defines TWO classes of that name, or `via` (where the pointer was written, model.h
    // VrMemberScope) says the class is not the in-tree one (F-2: `&grpc::Server::start` beside an in-tree `mine::Server`), the
    // owner is not proven: no target (a floor, never a guess).
    std::vector<NodeId> memberOf( std::string_view owner, std::span<const NodeId> fns, std::string_view via ) const
    {
        if( classDefsNamed( owner ) > 1 || !ownerInScope( owner, vrMemberScopeOf( via ) ) )
        {
            return {};
        }
        const auto methodsOf = [ & ]( const std::vector<std::string>& classes ) -> std::vector<NodeId>
        {
            std::vector<NodeId> out;
            for( const NodeId id : fns )
            {
                const Symbol& s = m_ing.symbols[id];
                if( s.kind == SymKind::Method && valueRefFamily( s.lang ) == VrLangFamily::C && std::ranges::find( classes, s.scope ) != classes.end() )
                {
                    out.push_back( id );
                }
            }
            return out;
        };
        const std::string declaring = declaringClass( std::string( owner ), methodsOf );
        if( declaring.empty() )
        {
            return {};
        }
        std::vector<std::string> classes = derivedFrom( std::string( owner ) );
        classes.push_back( declaring );
        std::vector<NodeId> bodies, declOwn, declOver;
        for( const NodeId id : methodsOf( classes ) )
        {
            const Symbol& s = m_ing.symbols[id];
            ( s.sigEndByte < s.endByte ? bodies : ( s.scope == declaring ? declOwn : declOver ) ).push_back( id );
        }
        return !bodies.empty() ? bodies : ( declOver.empty() ? declOwn : declOver );
    }
    // The class whose member `m` a pointer to `owner`'s m names: owner when it declares one, else the one nearest base that
    // does ("" when none, an ambiguous base level, or a base name two classes share). `methodsOf( {class} )` is that class's m.
    template <class MethodsOf>
    std::string declaringClass( const std::string& owner, const MethodsOf& methodsOf ) const
    {
        buildHierarchy();
        std::vector<std::string> level { owner };
        for( int depth = 0; depth < 8 && !level.empty(); ++depth )
        {
            std::vector<std::string> holders, next;
            for( const std::string& c : level )
            {
                if( !methodsOf( std::vector<std::string>{ c } ).empty() )
                {
                    holders.push_back( c );
                }
                if( const auto it = m_basesOf.find( c ); it != m_basesOf.end() )
                {
                    for( const std::string& b : it->second )
                    {
                        if( std::ranges::find( next, b ) == next.end() )
                        {
                            next.push_back( b );
                        }
                    }
                }
            }
            if( holders.size() == 1 )
            {
                return classDefsNamed( holders[0] ) > 1 ? std::string() : holders[0];
            }
            if( !holders.empty() )
            {
                return {};   // two bases at one level declare m: which one `&Cls::m` names is not proven
            }
            level = std::move( next );
        }
        return {};
    }
    // Every class transitively derived from `owner` (by the written base names), excluding it; capped (a runaway guard).
    std::vector<std::string> derivedFrom( const std::string& owner ) const
    {
        buildHierarchy();
        std::vector<std::string> out;
        std::vector<std::string> todo { owner };
        while( !todo.empty() && out.size() < 4096 )
        {
            const std::string c = std::move( todo.back() );
            todo.pop_back();
            if( const auto it = m_derivedOf.find( c ); it != m_derivedOf.end() )
            {
                for( const std::string& d : it->second )
                {
                    if( d != owner && std::ranges::find( out, d ) == out.end() )
                    {
                        out.push_back( d );
                        todo.push_back( d );
                    }
                }
            }
        }
        return out;
    }
    // class name → its written bases, and base → its derived classes (name-keyed, built on first use like m_classDefs: the first
    // use is always inside the constructor, which resolves every member-pointer row before any query).
    void buildHierarchy() const
    {
        if( m_hierarchyBuilt )
        {
            return;
        }
        m_hierarchyBuilt = true;
        m_basesOf        = inheritEdges( m_ing );
        for( const auto& [ derived, bases ] : m_basesOf )
        {
            for( const std::string& b : bases )
            {
                m_derivedOf[ b ].push_back( derived );
            }
        }
    }
    // F-2: is the in-tree class `owner` the one a `&[qualifier::]owner::m` written at `at` names? The scope path the class is
    // defined in is read against the written qualifier (a suffix of it, or exactly it after a leading `::`); a bare owner is the
    // class when it is global, defined around the pointer, or reached by a `using namespace` / `using` of the file.
    bool ownerInScope( std::string_view owner, const VrMemberScope& at ) const
    {
        if( classDefsNamed( owner ) == 0 )
        {
            return at.qualifier.empty();   // no body names the class (its header is not indexed): the scope is unproven, only a bare spelling stays
        }
        const std::string_view path = m_slots.bodyScope( owner ).value_or( std::string_view() );   // a body without a fact: read as global
        if( !at.qualifier.empty() )
        {
            const bool anchored = at.qualifier.starts_with( "::" );
            const std::string_view q = anchored ? at.qualifier.substr( 2 ) : at.qualifier;
            return anchored ? path == q : scopePathEndsWith( path, q );
        }
        return path.empty() || scopePathStartsWith( at.site, path )
            || std::ranges::any_of( std::views::split( at.directives, ',' ), [ & ]( auto d ) { return scopePathEndsWith( path, std::string_view( d.begin(), d.end() ) ); } );
    }
    // `path` is `tail` or ends with it on a "::" boundary / `head` is `path` or leads it on one.
    static bool scopePathEndsWith( std::string_view path, std::string_view tail ) noexcept
    {
        if( tail.empty() || !path.ends_with( tail ) )
        {
            return false;
        }
        return path.size() == tail.size() || path[ path.size() - tail.size() - 1 ] == ':';
    }
    static bool scopePathStartsWith( std::string_view path, std::string_view head ) noexcept
    {
        if( head.empty() )
        {
            return true;
        }
        return path.starts_with( head ) && ( path.size() == head.size() || path[ head.size() ] == ':' );
    }
    // How many C-family class / struct definitions (a body) the repo has named `name` (counted once, on first use).
    std::size_t classDefsNamed( std::string_view name ) const
    {
        if( !m_classDefsBuilt )
        {
            m_classDefsBuilt = true;
            for( const Symbol& s : m_ing.symbols )
            {
                if( ( s.kind == SymKind::Class || s.kind == SymKind::Struct ) && valueRefFamily( s.lang ) == VrLangFamily::C && s.sigEndByte < s.endByte )
                {
                    ++m_classDefs[ s.name ];
                }
            }
        }
        const auto it = m_classDefs.find( std::string( name ) );
        return it == m_classDefs.end() ? 0 : it->second;
    }
    // fix1 F-1 / part-2 piece 4: the definitions an argument row's callee (recvVar) resolves to — a bare callee by resolveName;
    // a path callee `Owner::name` (a language whose slot row has a pathSep) by ownedBy, never by its bare last segment.
    std::vector<NodeId> resolveCallee( const Reference& v ) const
    {
        const std::string_view sep = slotPathSep( v.lang );
        const std::size_t      at  = sep.empty() ? std::string::npos : v.recvVar.rfind( sep );
        if( at == std::string::npos )
        {
            return valueRefFamily( v.lang ) == VrLangFamily::Rust ? resolveIn( v, v.recvVar, {} ) : resolveName( v, v.recvVar );
        }
        const std::string_view path  = std::string_view( v.recvVar ).substr( 0, at );   // `crate::other` / `a::Owner` / `Owner`
        const std::size_t      up    = path.rfind( sep );
        const std::string_view owner = up == std::string_view::npos ? path : path.substr( up + sep.size() );
        if( owner.empty() || !( owner[0] >= 'A' && owner[0] <= 'Z' ) )
        {
            return resolveIn( v, std::string_view( v.recvVar ).substr( at + sep.size() ), path );   // a module path: no owner type
        }
        const auto it = m_fnByName.find( v.recvVar.substr( at + sep.size() ) );
        return it == m_fnByName.end() ? std::vector<NodeId>{} : ownedBy( v, owner, it->second, up == std::string_view::npos ? std::string_view() : path.substr( 0, up ) );
    }

    // FN-SLOT-2 fix 1: Rust function `name` written after module path `module` ("" bare) by reference `r` — the one
    // slot_join::RustPaths reaches (a bare name with no `use`: every one in r's own file, else its crate's one, else the repo's
    // only one in a crate the file `use`s); a class member (an impl's or an inline module's function) is never in bare scope.
    std::vector<NodeId> resolveIn( const Reference& r, std::string_view name, std::string_view module ) const
    {
        const auto it = m_fnByName.find( std::string( name ) );
        if( it == m_fnByName.end() )
        {
            return {};
        }
        std::vector<NodeId> cands, sameFile;
        for( const NodeId id : it->second )
        {
            const Symbol& s = m_ing.symbols[id];
            if( valueRefFamily( s.lang ) != VrLangFamily::Rust || ( isClassMember( s ) && !memberVisibleFrom( r, s, VrLangFamily::Rust ) ) )
            {
                continue;
            }
            cands.push_back( id );
            if( s.fileId == r.fileId )
            {
                sameFile.push_back( id );
            }
        }
        const slot_join::RustPaths::At at = m_paths.reach( r, module, name );
        if( at.kind == slot_join::RustPaths::Reach::Near && !sameFile.empty() )
        {
            return sameFile;   // the file's own (`#[cfg]` twins all of them, as every family's same-file rule)
        }
        const NodeId one = m_paths.nearestOf( cands, r.fileId, at );
        return one == kNoNode ? std::vector<NodeId>{} : std::vector<NodeId>{ one };
    }
    // `name` as seen from reference `r`'s file, under the visibility rules in the header comment.
    std::vector<NodeId> resolveName( const Reference& r, std::string_view name ) const
    {
        const auto it = m_fnByName.find( std::string( name ) );
        if( it == m_fnByName.end() )
        {
            return {};
        }
        const VrLangFamily  fam = valueRefFamily( r.lang );
        if( r.role == RefRole::Value && !r.memberRoot.empty() )
        {
            return ownedBy( r, r.memberRoot, it->second, r.memberVia );
        }
        if( valueRefFamily( r.lang ) == VrLangFamily::Rust )
        {
            return resolveIn( r, name, r.role == RefRole::Value ? std::string_view( r.memberVia ) : std::string_view() );
        }
        // A C/C++ PROTOTYPE (a bodyless declaration) names the function its definition lives in: it is the target only
        // when no definition with a body is visible — a prototype in this file never hides the extern definition.
        std::vector<NodeId> sameFile, other, declsHere;
        for( const NodeId id : it->second )
        {
            const Symbol& s = m_ing.symbols[id];
            if( valueRefFamily( s.lang ) != fam )
            {
                continue;
            }
            if( isClassMember( s ) && !memberVisibleFrom( r, s, fam ) )
            {
                continue;   // a class member is never in BARE-name scope outside its class (R1 of the final review)
            }
            const bool prototype = fam == VrLangFamily::C && s.sigEndByte >= s.endByte;
            if( prototype )
            {
                if( s.fileId == r.fileId )
                {
                    declsHere.push_back( id );
                }
                continue;
            }
            ( s.fileId == r.fileId ? sameFile : other ).push_back( id );
        }
        if( !sameFile.empty() )
        {
            return sameFile;
        }
        const bool fileShadow = r.qualifier.size() >= 2 && r.qualifier[1] == '1';
        if( fileShadow || other.empty() )
        {
            return fileShadow ? std::vector<NodeId>{} : declsHere;
        }
        const std::string_view refPath = m_ing.files[ r.fileId ];
        std::vector<NodeId>    out;
        switch( fam )
        {
            case VrLangFamily::C:
            {
                for( const NodeId id : other )
                {
                    if( m_ing.symbols[id].internalLinkage == 0 )
                    {
                        out.push_back( id );
                    }
                }
                break;
            }
            case VrLangFamily::Go:
            {
                for( const NodeId id : other )
                {
                    if( includerDir( m_ing.files[ m_ing.symbols[id].fileId ] ) == includerDir( refPath ) )
                    {
                        out.push_back( id );
                    }
                }
                break;
            }
            case VrLangFamily::Rust: break;   // resolveIn above
            case VrLangFamily::Js:
            case VrLangFamily::Py:
            {
                for( const std::uint32_t moduleFile : importedFilesBinding( r.fileId, name ) )
                {
                    for( const NodeId id : other )
                    {
                        if( m_ing.symbols[id].fileId == moduleFile )
                        {
                            out.push_back( id );
                        }
                    }
                }
                break;
            }
            case VrLangFamily::None: break;
        }
        std::sort( out.begin(), out.end() );
        out.erase( std::unique( out.begin(), out.end() ), out.end() );
        return out.empty() ? declsHere : out;
    }

    const IngestResult&                                  m_ing;
    HashMap<std::string, std::vector<NodeId>>            m_fnByName;
    mutable HashMap<std::string, std::size_t>            m_classDefs;   // FN-SLOT S2: C-family class / struct name → definitions (classDefsNamed)
    mutable HashMap<std::string, std::vector<std::string>> m_basesOf;     // FN-SLOT S2 fix 1: class → written bases (buildHierarchy)
    mutable HashMap<std::string, std::vector<std::string>> m_derivedOf;    //   base → derived classes
    mutable bool                                         m_hierarchyBuilt = false;
    mutable bool                                         m_classDefsBuilt = false;
    HashMap<std::string, std::vector<NodeId>>            m_fnByOwner;   // part 2: "family#Owner::name" → a path language's owned functions
    slot_join::RustPaths                                 m_paths;       // part 2 fix 1: where a Rust path reaches, when a path language is indexed
    std::vector<std::uint8_t>                            m_pyMember;   // per symbol: 1 = a Python def directly in its class (empty: no Python)
    std::vector<std::uint32_t>                           m_values;            // Value reference indices, ascending
    std::vector<std::uint32_t>                           m_depthCuts;         // the files' depth-cut records (no row), ascending
    std::vector<std::vector<NodeId>>                     m_targets;           // parallel to m_values
    HashMap<NodeId, std::vector<std::uint32_t>>          m_valuesByTarget;    // target def → positions in m_values
    HashMap<std::string, std::vector<std::uint32_t>>     m_valueByContainer;  // "file#container" → Value refs
    HashMap<std::string, std::vector<std::uint32_t>>     m_throughByContainer;
    HashMap<NodeId, std::vector<std::uint32_t>>          m_throughParamBySym;
    HashMap<std::uint32_t, std::vector<const Binding*>>  m_importsByFile;
    SlotIndex                                            m_slots;     // IX-1: struct-field slots and the calls through them
    mutable HashMap<std::string, std::uint32_t>          m_fileIndex;   // root-relative normalised path → fileId, built on first import
};

// The class DEFINITIONS of the armed languages and what relates them: a definition's enclosing class (the innermost Class symbol
// of its file whose span holds it: a symbol identity, so a class of the same name in another file is another class, and a JS/TS
// method, whose Symbol::scope is empty, is owned too), and the family of a class (itself, its ancestors, its subclasses). A base
// written by name binds to the class of that name in the derived class's own file, else to every class of it (a base imported from
// another module); name-keyed beyond that, as the census. Built on first use; one place for PatternIndex (IX-3) and any later reader.
class ClassFamilies
{
public:
    explicit ClassFamilies( const IngestResult& ing ) : m_ing( ing ) {}

    // The class definition that owns definition `d` (never `d` itself); kNoNode when none. Memoised: a walk asks once per symbol.
    NodeId ownerOf( NodeId d ) const
    {
        buildSpans();
        if( m_ownerDone[d] == 0 )
        {
            m_ownerDone[d]   = 1;
            const Symbol& s  = m_ing.symbols[d];
            auto          it = std::ranges::upper_bound( m_spans, std::pair( s.fileId, s.sigStartByte ), std::less<>(),
                                                         []( const ClassSpan& c ) { return std::pair( c.fileId, c.begin ); } );
            for( ; it != m_spans.begin(); )
            {
                --it;
                if( it->fileId != s.fileId )
                {
                    break;
                }
                if( it->id != d && it->begin <= s.sigStartByte && s.endByte <= it->end )
                {
                    m_owner[d] = it->id;
                    break;
                }
            }
        }
        return m_owner[d];
    }
    // Is class `member` in the family of class `site`: `site` itself, an ancestor of it, or a subclass of it?
    bool sameFamily( NodeId site, NodeId member ) const
    {
        if( site == member )
        {
            return true;
        }
        return isAncestor( member, site ) || isAncestor( site, member );
    }
    // Calls `visit( base )` for each class definition the written base names of class `c` bind to, in reference order.
    template <class Visit>
    void eachBase( NodeId c, Visit&& visit ) const
    {
        buildBases();
        if( const auto it = m_basesOf.find( c ); it != m_basesOf.end() )
        {
            std::ranges::for_each( it->second, visit );
        }
    }

private:
    struct ClassSpan
    {
        std::uint32_t fileId = 0;
        std::uint32_t begin  = 0;
        std::uint32_t end    = 0;
        NodeId        id     = kNoNode;
    };
    // Is `to` an ancestor of `from` (through the bound bases, 4096 classes at most)?
    bool isAncestor( NodeId from, NodeId to ) const
    {
        buildBases();
        std::vector<NodeId> todo { from };
        std::vector<NodeId> seen;
        while( !todo.empty() && seen.size() < 4096 )
        {
            const NodeId c = todo.back();
            todo.pop_back();
            if( std::ranges::find( seen, c ) != seen.end() )
            {
                continue;
            }
            seen.push_back( c );
            if( const auto it = m_basesOf.find( c ); it != m_basesOf.end() )
            {
                if( std::ranges::find( it->second, to ) != it->second.end() )
                {
                    return true;
                }
                todo.insert( todo.end(), it->second.begin(), it->second.end() );
            }
        }
        return false;
    }
    // The class spans of the armed languages, sorted (file, begin, end descending): an inner class sorts after its outer one.
    void buildSpans() const
    {
        if( m_spansBuilt )
        {
            return;
        }
        m_spansBuilt = true;
        m_owner.assign( m_ing.symbols.size(), kNoNode );
        m_ownerDone.assign( m_ing.symbols.size(), 0 );
        for( const Symbol& c : m_ing.symbols )
        {
            if( c.kind == SymKind::Class && valueRefFamily( c.lang ) != VrLangFamily::None )
            {
                m_spans.push_back( ClassSpan{ c.fileId, c.sigStartByte, c.endByte, c.id } );
            }
        }
        std::ranges::sort( m_spans, []( const ClassSpan& a, const ClassSpan& b )
        {
            return std::tie( a.fileId, a.begin, b.end, a.id ) < std::tie( b.fileId, b.begin, a.end, b.id );
        } );
    }
    // Bind one inherit reference's written base name to class definitions: the one of that name in the derived class's file, else all.
    void bindBase( const Reference& r, const HashMap<std::string_view, std::vector<NodeId>>& byName ) const
    {
        if( r.baseBind == kBaseBindTemplateParam )   // a template parameter (`template <class B> class M : B`): a dependent base names no in-tree class, even one called B
        {
            return;
        }
        const auto named = byName.find( std::string_view( r.calleeName ) );
        if( named == byName.end() )
        {
            return;
        }
        const std::uint32_t file = m_ing.symbols[ r.fromSymbol ].fileId;
        std::vector<NodeId> bound;
        std::ranges::copy_if( named->second, std::back_inserter( bound ), [ & ]( NodeId b ) { return m_ing.symbols[b].fileId == file; } );
        std::vector<NodeId>& out = m_basesOf[ r.fromSymbol ];
        for( const NodeId b : bound.empty() ? named->second : bound )
        {
            if( b != r.fromSymbol && std::ranges::find( out, b ) == out.end() )
            {
                out.push_back( b );
            }
        }
    }
    void buildBases() const
    {
        if( m_basesBuilt )
        {
            return;
        }
        m_basesBuilt = true;
        buildSpans();
        HashMap<std::string_view, std::vector<NodeId>> byName;
        for( const ClassSpan& c : m_spans )
        {
            byName[ m_ing.symbols[ c.id ].name ].push_back( c.id );
        }
        for( const Reference& r : m_ing.references )
        {
            if( ( r.isInherit || r.role == RefRole::Extends ) && r.fromSymbol < m_ing.symbols.size() && m_ing.symbols[ r.fromSymbol ].kind == SymKind::Class )
            {
                bindBase( r, byName );
            }
        }
    }

    const IngestResult&                          m_ing;
    mutable std::vector<ClassSpan>               m_spans;
    mutable std::vector<NodeId>                  m_owner;       // per symbol: its enclosing class definition (ownerOf)
    mutable std::vector<char>                    m_ownerDone;   // per symbol: m_owner is decided
    mutable bool                                 m_spansBuilt = false;
    mutable HashMap<NodeId, std::vector<NodeId>> m_basesOf;     // class definition -> the class definitions its base names bind to
    mutable bool                                 m_basesBuilt = false;
};

// fix1 (RSS): the narrow index (ValueRefIndex::narrowFor), defined here where Narrowed is complete.
inline ValueRefIndex::ValueRefIndex( const Narrowed& n ) : m_ing( n.ing )
{
    index( &n.keep );
}

// ── IX-3 name-template dispatch ───────────────────────────────────────────────────────────────────────────────
// The Pattern references (model.h RefRole::Pattern) and what they may name. Its own index beside ValueRefIndex, built
// from the same IngestResult: a template site (indices into ing.references, in reference order) can name a class member
// of the site's value-ref family whose name holds the literal prefix and suffix around a non-empty hole. A `self` /
// `this` / `cls` receiver narrows the members to the site's class FAMILY: the class DEFINITION that encloses the site's
// function (the innermost class whose span holds it, in that file: a symbol identity, so a class of the same name in another
// file is another class, and a JS/TS method, whose Symbol::scope is empty, is owned the same way), its ancestors and its
// subclasses (a base written by name binds to the same-file class of that name, else to every class of it); any other
// receiver is unnarrowed. A site with no enclosing class (a module function) is unnarrowed. A MAY-dispatch clue matched
// by name: never a call. Class membership is ValueRefIndex::isClassMember, read once per symbol at construction (only
// when a Pattern reference exists), so no reference to `vri` is kept.
class PatternIndex
{
public:
    PatternIndex( const IngestResult& ing, const ValueRefIndex& vri ) : m_ing( ing ), m_classes( ing )
    {
        for( std::uint32_t i = 0; i < ing.references.size(); ++i )
        {
            if( ing.references[i].role == RefRole::Pattern )
            {
                ( ValueRefIndex::scopeOf( ing.references[i] ) == 'w' ? m_patternsWide : m_patterns ).push_back( i );   // 'w' = too wide, a count, never a row
            }
        }
        m_member.assign( ing.symbols.size(), 0 );
        if( !m_patterns.empty() || !m_patternsWide.empty() )
        {
            for( NodeId id = 0; id < ing.symbols.size(); ++id )
            {
                m_member[id] = vri.isClassMember( ing.symbols[id] ) ? 1 : 0;
            }
        }
    }

    // The usable Pattern sites whose template can name one of `defs`, in reference order, once each.
    std::vector<std::uint32_t> sitesTo( std::span<const NodeId> defs ) const
    {
        return sitesNaming( m_patterns, defs );
    }
    // The class members Pattern site `refIdx` can name, in symbol order (the dispatcher's --callees side).
    std::vector<NodeId> targets( std::uint32_t refIdx ) const
    {
        std::vector<NodeId> out;
        const Reference& r = m_ing.references[ refIdx ];
        for( NodeId id = 0; id < m_ing.symbols.size(); ++id )
        {
            if( m_member[id] != 0 && reaches( r, m_ing.symbols[id] ) )
            {
                out.push_back( id );
            }
        }
        return out;
    }
    // The usable Pattern sites made inside any of `fns` (the dispatcher's own sites), in reference order.
    std::vector<std::uint32_t> sitesIn( std::span<const NodeId> fns ) const
    {
        std::vector<std::uint32_t> out;
        std::ranges::copy_if( m_patterns, std::back_inserter( out ), [ & ]( std::uint32_t i ) { return std::ranges::find( fns, m_ing.references[i].fromSymbol ) != fns.end(); } );
        return out;
    }
    // Too-wide templates (`f"_{m}"`: no literal side of kVrPatternMinLiteral identifier characters) whose written sides
    // could name one of `defs`, in reference order: pattern_too_wide= counts them; never a candidate list. --safe-delete
    // names them as <pdw> rows when they are what keeps risk= from none-found.
    std::vector<std::uint32_t> wideSitesTo( std::span<const NodeId> defs ) const
    {
        return sitesNaming( m_patternsWide, defs );
    }

private:

    // The Pattern sites of `sites` (reference order) that can name at least one class member of `defs`, in that order.
    std::vector<std::uint32_t> sitesNaming( const std::vector<std::uint32_t>& sites, std::span<const NodeId> defs ) const
    {
        std::vector<std::uint32_t> out;
        std::ranges::copy_if( sites, std::back_inserter( out ), [ & ]( std::uint32_t i )
        {
            return std::ranges::any_of( defs, [ & ]( NodeId d ) { return m_member[d] != 0 && reaches( m_ing.references[i], m_ing.symbols[d] ); } );
        } );
        return out;
    }
    // Can Pattern reference `r` name class member `s`? Same value-ref family; the literal sides around a non-empty hole;
    // a self/this/cls receiver inside a class keeps only that class's family.
    bool reaches( const Reference& r, const Symbol& s ) const
    {
        if( valueRefFamily( s.lang ) != valueRefFamily( r.lang ) )
        {
            return false;
        }
        const std::string_view pre = r.fieldName;
        const std::string_view suf = r.composeRel;
        const std::string_view n   = s.name;
        if( n.size() <= pre.size() + suf.size() || !n.starts_with( pre ) || !n.ends_with( suf ) )
        {
            return false;
        }
        const std::string_view recv = r.recvVar;
        if( ( recv == "self" || recv == "this" || recv == "cls" ) && r.fromSymbol < m_ing.symbols.size() )
        {
            if( const NodeId site = m_classes.ownerOf( r.fromSymbol ); site != kNoNode )
            {
                const NodeId member = m_classes.ownerOf( s.id );
                return member != kNoNode && m_classes.sameFamily( site, member );
            }
        }
        return true;
    }
    const IngestResult&                                    m_ing;
    std::vector<std::uint32_t>                             m_patterns;       // usable Pattern references, in reference order
    std::vector<std::uint32_t>                             m_patternsWide;   // too-wide Pattern references
    std::vector<std::uint8_t>                              m_member;         // per symbol: 1 = a class member (all 0 when no Pattern reference exists)
    ClassFamilies                                          m_classes;        // a self/this/cls receiver's class family
};

// ── the rows every surface serves ─────────────────────────────────────────────────────────────────────────────
// One <vr> row. Callers side: in = the enclosing symbol of the binding site, calledBy = may-call functions.
// Callees side: to = the referenced function, through = the written callee of the call through the slot, sites =
// how many binding sites one (to, through) pair joins.
struct ValueRefRow
{
    std::uint32_t ref     = 0;          // the Value reference (bind=, into=)
    NodeId        in      = kNoNode;    // callers side: the enclosing symbol
    NodeId        to      = kNoNode;    // callees side: the referenced function
    std::string   calledBy;             // callers side: comma-joined names
    std::string   through;              // callees side
    std::uint32_t sites   = 1;
    // IX-1, callers side, only when calledBy is empty (a container or parameter join answers first): the slot calls that may
    // call through this struct-field slot — one per calling function (its first site), by name; the same-type tier alone
    // when it has any (slotTyped), else the field-name tier; slotNameAlso = name-tier functions the same-type tier hides.
    std::vector<std::uint32_t> slotCalls;
    bool                       slotTyped    = false;
    std::uint32_t              slotNameAlso = 0;
    std::uint32_t              slotCands    = 0;   // IX1-V2: distinct functions the first slot call's slot may hold (this one among them)
};

// IX-1, callees side: one call through a struct field made in the answered functions, and the functions its slot may hold.
struct SlotSiteRow
{
    std::uint32_t       ref   = 0;       // the slot Through reference (l=, through=)
    std::string         slot;            // "Type.field" (".field" when the type is unknown)
    bool                typed = false;   // the targets come from same-type slots (via="slot"), else name only (via="slot-name")
    std::vector<NodeId> targets;         // distinct functions, by name then path
    bool                anyDesignated = false;   // a target was stored by a designated `.f = fn` (the next= literal finds it)
    std::uint32_t       nameAlso = 0;            // L-1: name-tier functions (a store whose struct type is unread) the same-type tier hides
};

struct ValueRefRows
{
    std::vector<ValueRefRow> rows;      // every row, served order; the window is the caller's
    ValueRefIndex::DepthCuts depthCut;  // the walk's depth cut over the answered defs' families (value_refs_depth_capped=)
    std::vector<std::uint32_t> patternSites;   // IX-3 (the PatternIndex overloads): callers — template lookups that may name the defs; callees — the templates in them
    std::vector<std::uint32_t> patternWideSites;   // IX-3 (callers): too-wide templates whose sides could name the defs
    std::vector<SlotSiteRow>   slotSites;          // IX-1 (callees): calls through a struct field with at least one target
    bool                       slotCallers = false;   // IX-1 (callers): a row carries slot callers (called_at= via=)
    bool                       slotCands   = false;   // IX1-V2 (callers): a row carries cands= (its slot holds more than one function)
};

// IX-1: the calling functions of a slot hit list, one per function (its first site, by reference order), by name; `typed`
// keeps the same-type tier alone when it has any hit. Returns the kept reference indices; `nameAlso` counts the name-tier
// functions dropped behind a same-type tier.
inline std::vector<std::uint32_t> slotCallers( const IngestResult& ing, std::vector<SlotIndex::Hit> hits, bool& typed, std::uint32_t& nameAlso )
{
    typed = std::ranges::any_of( hits, &SlotIndex::Hit::typed );
    std::ranges::sort( hits, {}, &SlotIndex::Hit::ref );
    std::vector<std::uint32_t> out;
    std::vector<NodeId>        seen, seenName;
    for( const SlotIndex::Hit& h : hits )
    {
        const NodeId f = ing.references[h.ref].fromSymbol;
        if( f == kNoNode )
        {
            continue;
        }
        if( typed && !h.typed )
        {
            if( std::ranges::find( seenName, f ) == seenName.end() )
            {
                seenName.push_back( f );
            }
            continue;
        }
        if( std::ranges::find( seen, f ) == seen.end() )
        {
            seen.push_back( f );
            out.push_back( h.ref );
        }
    }
    nameAlso = static_cast<std::uint32_t>( std::ranges::count_if( seenName, [ & ]( NodeId f ) { return std::ranges::find( seen, f ) == seen.end(); } ) );
    std::ranges::sort( out, [ & ]( std::uint32_t a, std::uint32_t b )
    {
        const Symbol& sa = ing.symbols[ ing.references[a].fromSymbol ];
        const Symbol& sb = ing.symbols[ ing.references[b].fromSymbol ];
        return sa.name != sb.name ? sa.name < sb.name : a < b;
    } );
    return out;
}

inline SlotSiteRow slotSiteOf( const IngestResult& ing, const ValueRefIndex& idx, std::uint32_t call );

// --callers side: every value reference resolving to one of `defs`.
// IX-1 / IX1-V2: the slot callers of callers-side row `row` (only when no container or parameter join answered it), and how many
// distinct functions the first slot call's slot holds (cands=).
inline void fillSlotCallers( const IngestResult& ing, const ValueRefIndex& idx, ValueRefRow& row, ValueRefRows& out )
{
    row.slotCalls   = slotCallers( ing, idx.slots().callsFor( row.ref ), row.slotTyped, row.slotNameAlso );
    out.slotCallers = out.slotCallers || !row.slotCalls.empty();
    if( !row.slotCalls.empty() )
    {
        row.slotCands = static_cast<std::uint32_t>( slotSiteOf( ing, idx, row.slotCalls.front() ).targets.size() );
        out.slotCands = out.slotCands || row.slotCands > 1;
    }
}

inline ValueRefRows valueRefCallerRows( const IngestResult& ing, const ValueRefIndex& idx, std::span<const NodeId> defs )
{
    ValueRefRows out;
    out.depthCut = idx.depthCutsFor( defs );
    for( const std::uint32_t r : idx.valueRefsTo( defs ) )
    {
        ValueRefRow row;
        row.ref = r;
        row.in  = ing.references[r].fromSymbol;
        for( const NodeId f : idx.calledBy( r ) )
        {
            if( !row.calledBy.empty() )
            {
                row.calledBy.push_back( ',' );
            }
            row.calledBy += ing.symbols[f].name;
        }
        if( row.calledBy.empty() )
        {
            fillSlotCallers( ing, idx, row, out );   // IX-1
        }
        out.rows.push_back( std::move( row ) );
    }
    std::sort( out.rows.begin(), out.rows.end(), [ & ]( const ValueRefRow& a, const ValueRefRow& b )
    {
        const Reference& ra = ing.references[a.ref];
        const Reference& rb = ing.references[b.ref];
        if( ra.fileId != rb.fileId || ra.startByte != rb.startByte )
        {
            return vrBindLess( ing, ra, rb );
        }
        return a.ref < b.ref;   // two value references at one site: parse order within the file (a total order)
    } );
    return out;
}

// The --callees row order, a total order on content: the binding site, then the target's name, then through=. Rows tied
// on all three are two definitions of one name (`fp = helper;` with a `helper` in each of two files): std::sort leaves
// equal rows in an order each standard library picks differently, and the 64-row window would then show a
// toolchain-dependent subset — so the definition's path, then its line, decide.
inline bool vrCalleeRowLess( const IngestResult& ing, const ValueRefRow& a, const ValueRefRow& b )
{
    const Reference& ra = ing.references[a.ref];
    const Reference& rb = ing.references[b.ref];
    if( ra.fileId != rb.fileId || ra.startByte != rb.startByte )
    {
        return vrBindLess( ing, ra, rb );
    }
    const Symbol& ta = ing.symbols[a.to];
    const Symbol& tb = ing.symbols[b.to];
    if( ta.name != tb.name )
    {
        return ta.name < tb.name;
    }
    if( a.through != b.through )
    {
        return a.through < b.through;
    }
    if( ta.fileId != tb.fileId )
    {
        return ing.files[ta.fileId] < ing.files[tb.fileId];
    }
    if( ta.line != tb.line )
    {
        return ta.line < tb.line;
    }
    return a.to < b.to;   // two same-named definitions on one line (C++ overloads): their rows render alike, the order is still total
}

// The function stores AND calls through the slot: the stored row (binding site v, function target) carries through=, the
// first written callee. A second call through the same slot and callee is that row again, never a new one. False when
// no stored row joins (the call goes through a slot another function or the file filled).
inline bool vrJoinStoredRow( std::vector<ValueRefRow>& rows, std::uint32_t v, NodeId target, const std::string& through )
{
    const auto same = std::ranges::find_if( rows, [ & ]( const ValueRefRow& r )
    {
        return r.ref == v && r.to == target && ( r.through.empty() || r.through == through );
    } );
    if( same == rows.end() )
    {
        return false;
    }
    if( same->through.empty() )
    {
        same->through = through;
    }
    return true;
}

// The rows a call THROUGH a slot reaches: one per (to, through), bind= its first binding site, sites= the number of
// DISTINCT binding sites — two calls through one slot never count one site twice.
struct VrViaRows
{
    std::vector<ValueRefRow>                rows;
    std::vector<std::vector<std::uint32_t>> sites;   // parallel to rows, ascending Value refs

    void add( const IngestResult& ing, std::uint32_t v, NodeId target, const std::string& through )
    {
        const auto grouped = std::ranges::find_if( rows, [ & ]( const ValueRefRow& r ) { return r.to == target && r.through == through; } );
        if( grouped == rows.end() )
        {
            ValueRefRow row;
            row.ref     = v;
            row.to      = target;
            row.through = through;
            rows.push_back( std::move( row ) );
            sites.push_back( { v } );
            return;
        }
        std::vector<std::uint32_t>& s  = sites[ static_cast<std::size_t>( grouped - rows.begin() ) ];
        const auto                  at = std::ranges::lower_bound( s, v );
        if( at == s.end() || *at != v )
        {
            s.insert( at, v );
        }
        if( vrBindLess( ing, ing.references[v], ing.references[grouped->ref] ) )
        {
            grouped->ref = v;
        }
    }
    void appendTo( std::vector<ValueRefRow>& out )
    {
        for( std::size_t i = 0; i < rows.size(); ++i )
        {
            rows[i].sites = static_cast<std::uint32_t>( sites[i].size() );
            out.push_back( std::move( rows[i] ) );
        }
    }
};

// IX-1, callees side: one call through a struct field, its slot and the distinct functions that slot may hold (the
// same-type tier alone when it has any), by name then path.
inline SlotSiteRow slotSiteOf( const IngestResult& ing, const ValueRefIndex& idx, std::uint32_t call )
{
    const std::vector<SlotIndex::Hit> hits = idx.slots().valuesFor( call );
    SlotSiteRow site;
    site.ref   = call;
    site.slot  = idx.slots().nameOf( call );
    site.typed = std::ranges::any_of( hits, &SlotIndex::Hit::typed );
    std::vector<NodeId> hidden;   // L-1: the name tier a typed site does not list
    for( const SlotIndex::Hit& h : hits )
    {
        if( site.typed && !h.typed )
        {
            std::ranges::copy( idx.targetsOf( h.ref ), std::back_inserter( hidden ) );
            continue;
        }
        std::ranges::copy( idx.targetsOf( h.ref ), std::back_inserter( site.targets ) );
        site.anyDesignated = site.anyDesignated || ing.references[h.ref].composeRel.starts_with( '.' );
    }
    std::ranges::sort( site.targets, [ & ]( NodeId a, NodeId b )
    {
        const Symbol& sa = ing.symbols[a];
        const Symbol& sb = ing.symbols[b];
        if( sa.name != sb.name )
        {
            return sa.name < sb.name;
        }
        return ing.files[sa.fileId] != ing.files[sb.fileId] ? ing.files[sa.fileId] < ing.files[sb.fileId] : a < b;
    } );
    site.targets.erase( std::ranges::unique( site.targets ).begin(), site.targets.end() );
    std::ranges::sort( hidden );
    hidden.erase( std::ranges::unique( hidden ).begin(), hidden.end() );
    site.nameAlso = static_cast<std::uint32_t>( std::ranges::count_if( hidden, [ & ]( NodeId f ) { return std::ranges::find( site.targets, f ) == site.targets.end(); } ) );
    return site;
}
// The calls through a struct field made in `fns` that reach at least one function; a site the container join already
// answers (`ops.open()` on a table this file filled: a through= row) keeps that answer alone.
inline std::vector<SlotSiteRow> slotSiteRows( const IngestResult& ing, const ValueRefIndex& idx, std::span<const NodeId> fns )
{
    std::vector<std::uint64_t> answered;
    for( const std::uint32_t t : idx.madeIn( fns, RefRole::Through ) )
    {
        if( !idx.valuesThrough( t ).empty() )
        {
            answered.push_back( ( std::uint64_t( ing.references[t].fileId ) << 32 ) | ing.references[t].startByte );
        }
    }
    std::ranges::sort( answered );
    std::vector<SlotSiteRow> out;
    for( const NodeId f : fns )
    {
        for( const std::uint32_t c : idx.slots().callsIn( f ) )
        {
            const Reference& cr = ing.references[c];
            if( std::ranges::binary_search( answered, ( std::uint64_t( cr.fileId ) << 32 ) | cr.startByte ) )
            {
                continue;
            }
            if( SlotSiteRow site = slotSiteOf( ing, idx, c ); !site.targets.empty() )
            {
                out.push_back( std::move( site ) );
            }
        }
    }
    std::ranges::sort( out, {}, &SlotSiteRow::ref );   // reference order, whatever the order of `fns`
    return out;
}

// --callees side: the functions `fns` store/pass as values (through= absent unless the same function also calls
// through that very slot), and the functions they may call through a parameter or a container (through= the written
// callee; one row per (to, through), bind= its first site, sites= the number of distinct binding sites).
// Rows are per BINDING SITE and WRITTEN callee, never per call through it: two calls `tbl.k(); tbl.k();` through one slot
// are one row, and `TABLE.k()` called twice through a slot one site fills is sites=1, not 2. FLOOR: one slot called under two
// spellings (`tbl.k()` and `tbl["k"]()`) is two written callees, so two rows.
inline ValueRefRows valueRefCalleeRows( const IngestResult& ing, const ValueRefIndex& idx, std::span<const NodeId> fns )
{
    ValueRefRows out;
    out.depthCut = idx.depthCutsFor( fns );
    for( const std::uint32_t v : idx.madeIn( fns, RefRole::Value ) )
    {
        for( const NodeId t : idx.targetsOf( v ) )
        {
            ValueRefRow row;
            row.ref = v;
            row.to  = t;
            out.rows.push_back( std::move( row ) );
        }
    }
    VrViaRows via;
    for( const std::uint32_t t : idx.madeIn( fns, RefRole::Through ) )
    {
        const Reference& tr = ing.references[t];
        for( const std::uint32_t v : idx.valuesThrough( t ) )
        {
            for( const NodeId target : idx.targetsOf( v ) )
            {
                if( !vrJoinStoredRow( out.rows, v, target, tr.fieldName ) )
                {
                    via.add( ing, v, target, tr.fieldName );
                }
            }
        }
    }
    via.appendTo( out.rows );
    std::sort( out.rows.begin(), out.rows.end(), [ & ]( const ValueRefRow& a, const ValueRefRow& b ) { return vrCalleeRowLess( ing, a, b ); } );
    out.slotSites = slotSiteRows( ing, idx, fns );   // IX-1
    return out;
}

// `rows` (valueRefCallerRows / valueRefCalleeRows over `ids`) with the IX-3 Pattern rows riding inside: callers — the
// template lookups that may name `ids` and the too-wide count; callees — the templates made in `ids`.
inline ValueRefRows withPatternRows( ValueRefRows rows, const PatternIndex& pix, std::span<const NodeId> ids, bool callersSide )
{
    rows.patternSites   = callersSide ? pix.sitesTo( ids ) : pix.sitesIn( ids );
    rows.patternWideSites = callersSide ? pix.wideSitesTo( ids ) : std::vector<std::uint32_t>();
    return rows;
}

// The --uses / MCP uses site filter, ONE copy for both surfaces. A role="value" site is served only when the resolver
// binds it to `valueDefs` (empty = any function of that name); a call THROUGH a value is never a use site; and a value
// site replaces the value scanner's role="read" row at the same identifier (one site, one row).
class UsesValueFilter
{
public:
    UsesValueFilter( const IngestResult& ing, std::string_view name, std::span<const NodeId> valueDefs, const ValueRefIndex* cached = nullptr )
    {
        const std::optional<ValueRefIndex> local = cached == nullptr ? std::optional<ValueRefIndex>( std::in_place, ing ) : std::nullopt;
        const ValueRefIndex&               vri   = cached != nullptr ? *cached : *local;
        for( std::uint32_t i = 0; i < ing.references.size(); ++i )
        {
            const Reference& r = ing.references[i];
            if( r.role != RefRole::Value || r.calleeName != name || r.fieldName.starts_with( '@' ) )
            {
                continue;   // a decorator row is a fact about the DEFINITION, not a use site elsewhere: the callers verb lists it
            }
            const std::vector<NodeId> targets = vri.targetsOf( i );
            const bool chosen = !targets.empty()
                             && ( valueDefs.empty() || std::any_of( targets.begin(), targets.end(), [ & ]( NodeId t )
                                                                    { return std::find( valueDefs.begin(), valueDefs.end(), t ) != valueDefs.end(); } ) );
            if( chosen )
            {
                m_accepted.push_back( i );
                m_sites.push_back( ( std::uint64_t( r.fileId ) << 32 ) | r.startByte );
            }
        }
        std::sort( m_sites.begin(), m_sites.end() );
    }
    // True when reference `refIndex` is NOT a use-site row of this answer.
    bool skip( std::uint32_t refIndex, const Reference& r ) const
    {
        if( r.role == RefRole::Through || r.role == RefRole::Subscript || r.role == RefRole::Pattern )   // a subscript is a use only as the call it may resolve to; a name template never is one
        {
            return true;
        }
        if( r.role == RefRole::Value )
        {
            return !std::binary_search( m_accepted.begin(), m_accepted.end(), refIndex );   // decorator rows included: never accepted
        }
        if( ( r.role == RefRole::Read || r.role == RefRole::Write ) && !m_sites.empty() )
        {
            return std::binary_search( m_sites.begin(), m_sites.end(), ( std::uint64_t( r.fileId ) << 32 ) | r.startByte );
        }
        return false;
    }
    bool any() const noexcept { return !m_accepted.empty(); }

private:
    std::vector<std::uint32_t> m_accepted;   // ascending (built in index order)
    std::vector<std::uint64_t> m_sites;
};

// --path / path_between: with NO directed call path (`unreachable`), how often `dstDefs` are used as values (0 when a
// path exists, so the attribute is absent and the answer byte-identical) and the depth cut over their language families
// (ValueRefRows::depthCut: a count read off a cut file is a floor, and the answer says so, as --callers' does).
struct ToValueRefs
{
    std::size_t              count = 0;
    ValueRefIndex::DepthCuts depthCut;
};
inline ToValueRefs toValueRefs( const IngestResult& ing, bool unreachable, std::span<const NodeId> dstDefs, const ValueRefIndex* cached = nullptr )
{
    if( !unreachable )
    {
        return {};
    }
    const ValueRefRows rows = cached != nullptr ? valueRefCallerRows( ing, *cached, dstDefs ) : valueRefCallerRows( ing, ValueRefIndex( ing ), dstDefs );
    return { rows.rows.size(), rows.depthCut };
}

}   // namespace rw
