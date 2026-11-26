#pragma once
// pyscopepin.h — PY-CLASS-SPRAY: the Python lexical-scope pin graph.h's resolve loop asks before the name ladder. A per-language
// file (test/langidentity/ratchet.tsv `perlang`): every Lang:: predicate here is the point of the file.
#include "model.h"
#include "infra/Diagnostics.h"   // ASSUME
#include "smallvec.h"        // rw::SmallVec — graph.h byName's value type
#include "externalnames.h"   // isPythonBuiltin — a conditional def of a builtin's name may leave the builtin bound

#include <algorithm>
#include <charconv>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <vector>

namespace rw
{

// "<id>#name" into the caller's reused buffer: the tables below key a name by the file that binds it
inline const std::string& pyScopeKey( std::string& key, std::uint32_t id, std::string_view name )
{
    char digits[ 16 ];
    const auto [ end, ec ] = std::to_chars( digits, digits + sizeof( digits ), id );
    ASSUME( ec == std::errc{}, "a u32 fits 16 decimal digits" );
    key.assign( digits, end ).append( 1, '#' ).append( name );
    return key;
}

// ── PY-CLASS-SPRAY: a bare Python call binds through its LEXICAL scope chain (LEGB) ────────────────────────────────────────────
// Python looks a bare name up in the scope the call runs in, then in each ENCLOSING FUNCTION (a class body only when it is that
// innermost scope), then in the module, then in the builtins: never in another function's body or another module (an import or a
// star import is a binding of the module's own). So a name the first binding scope of that chain binds by def or class statements
// ALONE names exactly those definitions: one is the edge, two or more (`if flag: class M … else: class M …`) are a split across
// them only. Before this rule such a call took the name-only ladder and split across every same-named definition in its directory:
// one `Model(b=1)` in a pydantic test reached all 965 `class Model` definitions of tests/ (517,311 edges from 643 callers).
// The scope answers only when every binding of the name in it is a def or class statement of an indexed definition (the binds
// channel files each such statement as one VarDecl record, ingest_binds.h capturePythonRebindShadowDecls). NO decision, so the
// unchanged ladder, when the binding cannot be read that way:
//   * another binding of the name in that scope: an assignment of any form, a for/with/except target, a walrus, `del`, a parameter,
//     an import (Rule 3's and the import pins' evidence), a match capture, a type parameter;
//   * a `global` or `nonlocal` of the name anywhere in the file (filed at byte 0, like a def that starts the file: a byte-0 record
//     no such def explains is one, and the binding it rewrites is not read here);
//   * a lambda parameter or comprehension target of the name whose span holds the call (`~name`);
//   * the innermost scope is a class body that binds the name (a class body looks names up at run time: a later binding is absent);
//   * at module scope: a star import in the file, a dynamic namespace write (`globals()`, `setattr`), a conditional def of a builtin's
//     name, or a call that runs at import time ahead of a definition.
// A call in a def's or class's HEADER (a default, an annotation, a decorator, a base clause) runs in the enclosing scope.
inline constexpr std::uint32_t kPythonModuleRow = UINT32_MAX;   // the module scope: no def or class row holds the byte

// one Python def or class as a scope: its span, the byte its body starts at, and the innermost row that holds it
struct PythonScopeRow
{
    std::uint32_t start   = 0;                  // Symbol::sigStartByte
    std::uint32_t body    = 0;                  // Symbol::sigEndByte: a byte before it is the header, run in the enclosing scope
    std::uint32_t end     = 0;                  // Symbol::endByte
    std::uint32_t parent  = kPythonModuleRow;   // the innermost row whose span holds this one
    NodeId        id      = kNoNode;
    bool          isClass = false;
};

// one binding record of a called name in a file: where it binds, and which kind of record it is
enum class PythonScopeBindKind : std::uint8_t
{
    Plain,       // a VarDecl or Import record of the name: one binding statement in `scope`
    Local,       // `~name`: a lambda parameter or comprehension target, local to [spanStart, spanEnd)
    CondDef,     // `?name`: a module-scope def or class of the name that may not run
    FileStart    // a record at byte 0, filed at module scope: a def or class at byte 0, or a `global` / `nonlocal` of the name (not read)
};
struct PythonScopeBind
{
    std::uint32_t       scope     = kPythonModuleRow;
    std::uint32_t       spanStart = 0;
    std::uint32_t       spanEnd   = 0;
    PythonScopeBindKind kind      = PythonScopeBindKind::Plain;
    // one binding statement of the name in `scope`: a byte-0 record is the module's (pythonLexicalScopePin first proves it is a def's)
    [[nodiscard]] bool statementIn( std::uint32_t row ) const noexcept
    {
        return ( kind == PythonScopeBindKind::Plain || kind == PythonScopeBindKind::FileStart ) && scope == row;
    }
};

// a def or class definition of a called name, with the scope its statement binds the name in
struct PythonScopeDef
{
    NodeId        id    = kNoNode;
    std::uint32_t scope = kPythonModuleRow;
};

struct PythonLexicalScopes
{
    std::vector<PythonScopeRow> rows;       // every Python def and class of the files below, grouped by file, start-sorted
    std::vector<std::uint32_t>  fileRows;   // fileId → its first row; fileRows[ f + 1 ] ends the run (size files + 1)
    HashMap<std::string, std::vector<PythonScopeDef>>      defs;    // "<fileId>#name" → the file's defs/classes of a called name
    HashMap<std::string, std::vector<PythonScopeBind>>     binds;   // "<fileId>#name" → every binding record of that name there
    [[nodiscard]] bool empty() const noexcept { return defs.empty(); }

    // the innermost row of file `f` whose span holds `byte`, kPythonModuleRow when none does. The last row starting at or before the
    // byte is the innermost such row or lies inside it (spans nest), so the answer is it or one of its ancestors.
    std::uint32_t rowHolding( std::uint32_t f, std::uint32_t byte ) const noexcept
    {
        if( f + 1 >= fileRows.size() )
        {
            return kPythonModuleRow;
        }
        const auto first = rows.begin() + fileRows[ f ];
        const auto last  = rows.begin() + fileRows[ f + 1 ];
        const auto after = std::upper_bound( first, last, byte, []( std::uint32_t b, const PythonScopeRow& row ) { return b < row.start; } );
        std::uint32_t row = after == first ? kPythonModuleRow : std::uint32_t( after - rows.begin() - 1 );
        while( row != kPythonModuleRow && rows[ row ].end <= byte )
        {
            row = rows[ row ].parent;
        }
        return row;
    }
    // the scope a call at `byte` RUNS in: the innermost row holding it, stepping out of every header it sits in
    std::uint32_t scopeRunning( std::uint32_t f, std::uint32_t byte ) const noexcept
    {
        std::uint32_t row = rowHolding( f, byte );
        while( row != kPythonModuleRow && byte < rows[ row ].body )
        {
            row = rows[ row ].parent;
        }
        return row;
    }
};

// a bare call: no receiver, no qualifier, not written on an object
inline bool isBareNameCall( const Reference& r ) noexcept
{
    return r.role == RefRole::Call && r.recv == RecvKind::None && r.qualifier.empty() && !r.memberCall;
}

inline bool isPythonBareCall( const Reference& r ) noexcept
{
    return r.lang == Lang::Python && isBareNameCall( r );
}

inline bool isPythonScopeDefKind( SymKind k ) noexcept
{
    return k == SymKind::Function || k == SymKind::Method || k == SymKind::Class;
}

// the names the rule can narrow: those of a bare Python call with two or more same-named definitions in the tree
inline HashMap<std::string, char> pythonSprayedCallNames( const IngestResult& ing, const HashMap<std::string, rw::SmallVec<NodeId, 2>>& byName )
{
    HashMap<std::string, char> names;
    for( const Reference& r : ing.references )
    {
        if( isPythonBareCall( r ) )
        {
            if( const auto it = byName.find( r.calleeName ); it != byName.end() && it->second.size() >= 2 )
            {
                names.try_emplace( it->first, '\0' );
            }
        }
    }
    return names;
}

// rows: every Python def and class of the files marked in `wanted`, start-sorted per file (a longer span first on a tie, so an
// enclosing row precedes what it holds), each with its innermost enclosing row
inline void buildPythonScopeRows( const IngestResult& ing, const std::vector<char>& wanted, PythonLexicalScopes& s )
{
    std::vector<NodeId> ids;
    for( const Symbol& sym : ing.symbols )
    {
        if( sym.fileId < wanted.size() && wanted[ sym.fileId ] != 0 && sym.lang == Lang::Python && isPythonScopeDefKind( sym.kind ) )
        {
            ids.push_back( sym.id );
        }
    }
    std::ranges::sort( ids, [ & ]( NodeId a, NodeId b )
    {
        const Symbol& x = ing.symbols[ a ];
        const Symbol& y = ing.symbols[ b ];
        return std::tuple( x.fileId, x.sigStartByte, std::uint32_t( UINT32_MAX - x.endByte ), a ) < std::tuple( y.fileId, y.sigStartByte, std::uint32_t( UINT32_MAX - y.endByte ), b );
    } );
    s.fileRows.assign( ing.files.size() + 1, 0 );
    std::vector<std::uint32_t> open;   // the rows still open at the current start, outermost first
    for( NodeId id : ids )
    {
        const Symbol&       sym = ing.symbols[ id ];
        const std::uint32_t at  = std::uint32_t( s.rows.size() );
        if( !s.rows.empty() && ing.symbols[ s.rows.back().id ].fileId != sym.fileId )
        {
            open.clear();
        }
        while( !open.empty() && s.rows[ open.back() ].end <= sym.sigStartByte )
        {
            open.pop_back();
        }
        s.rows.push_back( PythonScopeRow{ sym.sigStartByte, std::max( sym.sigEndByte, sym.sigStartByte ), sym.endByte,
                                          open.empty() ? kPythonModuleRow : open.back(), id, sym.kind == SymKind::Class } );
        open.push_back( at );
        ++s.fileRows[ sym.fileId + 1 ];
    }
    for( std::size_t f = 1; f < s.fileRows.size(); ++f )
    {
        s.fileRows[ f ] += s.fileRows[ f - 1 ];
    }
}

// one binding record into PythonLexicalScopes::binds, when it binds a name the file defines (defs holds its key)
inline void addPythonScopeBind( const Binding& b, PythonLexicalScopes& s, std::string& key )
{
    if( ( b.kind != LocalBindKind::VarDecl && b.kind != LocalBindKind::Import ) || b.fileId + 1 >= s.fileRows.size()
        || s.fileRows[ b.fileId ] == s.fileRows[ b.fileId + 1 ] )
    {
        return;
    }
    std::string_view          name( b.var );
    PythonScopeBindKind       kind = PythonScopeBindKind::Plain;
    if( name.starts_with( kPythonCondImportPrefix ) )
    {
        return;   // a conditional from-import's mark: the import's own record is the binding
    }
    if( name.starts_with( kPythonLocalScopePrefix ) || name.starts_with( kPythonCondDefPrefix ) )
    {
        kind = name.starts_with( kPythonLocalScopePrefix ) ? PythonScopeBindKind::Local : PythonScopeBindKind::CondDef;
        name.remove_prefix( 1 );
    }
    const auto it = s.binds.find( pyScopeKey( key, b.fileId, name ) );
    if( it == s.binds.end() )
    {
        return;
    }
    if( kind == PythonScopeBindKind::Plain && b.startByte == 0 )   // graph.h pythonBindAtFileStart: a byte-0 record sits at module scope
    {
        kind = PythonScopeBindKind::FileStart;
    }
    const std::uint32_t scope = kind == PythonScopeBindKind::FileStart ? kPythonModuleRow : s.rowHolding( b.fileId, b.startByte );
    it->second.push_back( PythonScopeBind{ scope, b.spanStart, b.spanEnd, kind } );
}

// PY-CLASS-SPRAY's tables, built once per graph: only for names a bare Python call sprays over, and only for the files that define one
inline PythonLexicalScopes buildPythonLexicalScopes( const IngestResult& ing, const HashMap<std::string, rw::SmallVec<NodeId, 2>>& byName )
{
    PythonLexicalScopes s;
    const HashMap<std::string, char> names = pythonSprayedCallNames( ing, byName );
    if( names.empty() )
    {
        return s;
    }
    std::vector<char> wanted( ing.files.size(), 0 );
    for( const Symbol& sym : ing.symbols )
    {
        if( sym.lang == Lang::Python && isPythonScopeDefKind( sym.kind ) && sym.fileId < wanted.size() && names.contains( sym.name ) )
        {
            wanted[ sym.fileId ] = 1;
        }
    }
    buildPythonScopeRows( ing, wanted, s );
    std::string key;
    for( const PythonScopeRow& row : s.rows )
    {
        const Symbol& sym = ing.symbols[ row.id ];
        if( names.contains( sym.name ) )
        {
            pyScopeKey( key, sym.fileId, sym.name );
            s.defs[ key ].push_back( PythonScopeDef{ row.id, row.parent } );
            s.binds.try_emplace( key );
        }
    }
    for( const Binding& b : ing.bindings )
    {
        addPythonScopeBind( b, s, key );
    }
    return s;
}

// the first scope of the call's chain that binds its name (the call's own scope, then each enclosing function, then the module), or
// kPythonModuleRow with `bound` false when none does; `inFunction`: the chain passed a function, so the call does not run at import time
struct PythonBindingScope
{
    std::uint32_t row        = kPythonModuleRow;
    bool          bound      = false;
    bool          inFunction = false;
};
inline PythonBindingScope pythonBindingScope( const PythonLexicalScopes& s, std::span<const PythonScopeBind> binds, const Reference& r )
{
    PythonBindingScope at{ s.scopeRunning( r.fileId, r.startByte ), false, false };
    const auto bindsIn = [ & ]( std::uint32_t row )
    {
        return std::ranges::any_of( binds, [ row ]( const PythonScopeBind& b ) { return b.statementIn( row ); } );
    };
    for( bool innermost = true;; innermost = false )
    {
        if( at.row != kPythonModuleRow && s.rows[ at.row ].isClass && !innermost )
        {
            at.row = s.rows[ at.row ].parent;   // an enclosing class body is not in the chain
            continue;
        }
        at.bound = bindsIn( at.row );
        if( at.bound || at.row == kPythonModuleRow )
        {
            return at;
        }
        at.inFunction = at.inFunction || !s.rows[ at.row ].isClass;
        at.row        = s.rows[ at.row ].parent;
    }
}

// a conditional module-scope def of a builtin's name: when it does not run, the builtin answers the call
inline bool pythonCondDefOfBuiltin( std::span<const PythonScopeBind> binds, const Reference& r )
{
    return externalnames::isPythonBuiltin( r.calleeName )
        && std::ranges::any_of( binds, []( const PythonScopeBind& b ) { return b.kind == PythonScopeBindKind::CondDef; } );
}

// PY-CLASS-SPRAY: the definitions a bare Python call names through its scope chain, appended to `out`; false (no decision, `out`
// untouched) whenever the binding is not read (see the banner above). `moduleUnread()`: the caller's tables say the module namespace of
// r's file may be rebound past its statements (a star import, a `globals()` / `setattr` write); asked only when the module scope decides.
template<class ModuleUnread>
inline bool pythonLexicalScopePin( const PythonLexicalScopes& s, const IngestResult& ing, const Reference& r, ModuleUnread&& moduleUnread,
                                   std::vector<NodeId>& out )
{
    std::string key;
    const auto  dit = s.defs.find( pyScopeKey( key, r.fileId, r.calleeName ) );
    if( dit == s.defs.end() )
    {
        return false;
    }
    const auto bit = s.binds.find( key );
    ASSUME( bit != s.binds.end(), "buildPythonLexicalScopes files a binds entry beside every defs entry" );
    const std::span<const PythonScopeBind> binds( bit->second.data(), bit->second.size() );
    // a byte-0 record beyond the defs that start at byte 0 is a `global` / `nonlocal`; a lambda or comprehension binding may hold the call
    const auto atFileStart = std::ranges::count_if( binds, []( const PythonScopeBind& b ) { return b.kind == PythonScopeBindKind::FileStart; } );
    const auto defsAtStart = std::ranges::count_if( dit->second, [ & ]( const PythonScopeDef& d )
                                                    { return d.scope == kPythonModuleRow && ing.symbols[ d.id ].sigStartByte == 0; } );
    const bool shadowed    = std::ranges::any_of( binds, [ & ]( const PythonScopeBind& b )
                                                  { return b.kind == PythonScopeBindKind::Local && r.startByte >= b.spanStart && r.startByte < b.spanEnd; } );
    if( atFileStart > defsAtStart || shadowed )
    {
        return false;
    }
    const PythonBindingScope at = pythonBindingScope( s, binds, r );
    if( !at.bound || ( at.row != kPythonModuleRow && s.rows[ at.row ].isClass ) )
    {
        return false;   // not bound in the chain (a builtin, a star import, undefined), or a class body that binds it
    }
    const auto statements = std::ranges::count_if( binds, [ & ]( const PythonScopeBind& b ) { return b.statementIn( at.row ); } );
    const auto here       = std::ranges::count_if( dit->second, [ & ]( const PythonScopeDef& d ) { return d.scope == at.row; } );
    if( here != statements || ( at.row == kPythonModuleRow && ( pythonCondDefOfBuiltin( binds, r ) || moduleUnread() ) ) )
    {
        return false;   // another binding of the name shares the scope (or the module's namespace is not read)
    }
    for( const PythonScopeDef& d : dit->second )
    {
        if( d.scope == at.row && !at.inFunction && at.row == kPythonModuleRow && ing.symbols[ d.id ].sigStartByte >= r.startByte )
        {
            return false;   // an import-time call ahead of a module-scope definition: the name is not bound by it yet
        }
    }
    for( const PythonScopeDef& d : dit->second )
    {
        if( d.scope == at.row )
        {
            out.push_back( d.id );
        }
    }
    return true;
}

} // namespace rw
