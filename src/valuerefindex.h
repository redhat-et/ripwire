#pragma once
// valuerefindex.h — the resolution core of the reference-as-value rows (src/valuerefs.h says what a row means):
// ValueRefIndex, the rows every surface serves, the --uses filter and the --path count. No rendering and no
// serialize.h, so quality.h (the --quality-delta dead kind) can include it without an include cycle.

#include "graph.h"             // jsImportKey — the "fileId#name" key, reused for containers
#include "mention.h"           // pathStem — a module path's file stem
#include "resolve.h"           // includerDir, resolvePreciseInclude — a module path's file
#include "infra/Diagnostics.h"   // EXPECTS/ENSURES — the window and index invariants
#include "model.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <optional>
#include <span>
#include <string>
#include <string_view>
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

// The index every verb queries. Built from one IngestResult in O(refs + symbols); no graph needed.
class ValueRefIndex
{
public:
    explicit ValueRefIndex( const IngestResult& ing ) : m_ing( ing )
    {
        for( NodeId id = 0; id < ing.symbols.size(); ++id )
        {
            const Symbol& s = ing.symbols[id];
            if( ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && valueRefFamily( s.lang ) != VrLangFamily::None )
            {
                m_fnByName[ s.name ].push_back( id );
            }
        }
        markPythonMembers();
        for( std::uint32_t i = 0; i < ing.references.size(); ++i )
        {
            const Reference& r = ing.references[i];
            if( r.role == RefRole::Value )
            {
                m_values.push_back( i );
                if( !r.recvVar.empty() )
                {
                    m_valueByContainer[ jsImportKey( r.fileId, r.recvVar ) ].push_back( i );
                }
            }
            else if( r.role == RefRole::Through )
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
    bool isValueReferenced( NodeId def ) const
    {
        const auto it = m_valuesByTarget.find( def );
        if( it == m_valuesByTarget.end() )
        {
            return false;
        }
        return std::ranges::any_of( it->second, [ & ]( std::uint32_t k )
        {
            return !vrIsWrapperDecorator( m_ing.references[ m_values[k] ].fieldName );
        } );
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

private:
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

    // A class member, in every armed language: a Method, or a Python def whose innermost enclosing def is its class.
    bool isClassMember( const Symbol& s ) const noexcept
    {
        if( s.kind == SymKind::Method )
        {
            return true;
        }
        return s.lang == Lang::Python && s.id < m_pyMember.size() && m_pyMember[ s.id ] != 0;
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
        const bool    fClass = ( f.kind == SymKind::Class || f.kind == SymKind::Struct ) && f.name == m.scope;
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

    // `name` as seen from reference `r`'s file, under the visibility rules in the header comment.
    std::vector<NodeId> resolveName( const Reference& r, std::string_view name ) const
    {
        const auto it = m_fnByName.find( std::string( name ) );
        if( it == m_fnByName.end() )
        {
            return {};
        }
        const VrLangFamily  fam = valueRefFamily( r.lang );
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
            case VrLangFamily::Js:
            case VrLangFamily::Py:
            {
                const auto imp = m_importsByFile.find( r.fileId );
                if( imp == m_importsByFile.end() )
                {
                    break;
                }
                for( const Binding* b : imp->second )
                {
                    const bool named = b->kind == LocalBindKind::JsImport ? ( b->var == name && b->importedName == name )
                                                                         : ( b->var == name && b->importedName.empty() );
                    if( !named )
                    {
                        continue;
                    }
                    // The import's module, resolved by the call graph's own Step-A (resolve.h resolvePreciseInclude: a
                    // relative JS/TS specifier against the importer, a Python module relative-to-file then root, then the
                    // whole-component suffix for an absolute Python spec). A bare package specifier resolves to no file:
                    // no row — a stem match across directories bound `import { test } from "./a"` to every a.js.
                    const std::uint32_t moduleFile = importedModuleFile( *b );
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
    std::vector<std::uint8_t>                            m_pyMember;   // per symbol: 1 = a Python def directly in its class (empty: no Python)
    std::vector<std::uint32_t>                           m_values;            // Value reference indices, ascending
    std::vector<std::vector<NodeId>>                     m_targets;           // parallel to m_values
    HashMap<NodeId, std::vector<std::uint32_t>>          m_valuesByTarget;    // target def → positions in m_values
    HashMap<std::string, std::vector<std::uint32_t>>     m_valueByContainer;  // "file#container" → Value refs
    HashMap<std::string, std::vector<std::uint32_t>>     m_throughByContainer;
    HashMap<NodeId, std::vector<std::uint32_t>>          m_throughParamBySym;
    HashMap<std::uint32_t, std::vector<const Binding*>>  m_importsByFile;
    mutable HashMap<std::string, std::uint32_t>          m_fileIndex;   // root-relative normalised path → fileId, built on first import
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
};

struct ValueRefRows
{
    std::vector<ValueRefRow> rows;      // every row, served order; the window is the caller's
};

inline bool vrBindLess( const IngestResult& ing, const Reference& a, const Reference& b )
{
    if( a.fileId != b.fileId )
    {
        return ing.files[a.fileId] < ing.files[b.fileId];
    }
    return a.startByte < b.startByte;
}

// --callers side: every value reference resolving to one of `defs`.
inline ValueRefRows valueRefCallerRows( const IngestResult& ing, const ValueRefIndex& idx, std::span<const NodeId> defs )
{
    ValueRefRows out;
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
    return ta.line < tb.line;
}

// --callees side: the functions `fns` store/pass as values (through= absent unless the same function also calls
// through that very slot), and the functions they may call through a parameter or a container (through= the written
// callee; one row per (to, through), bind= its first site, sites= the count).
inline ValueRefRows valueRefCalleeRows( const IngestResult& ing, const ValueRefIndex& idx, std::span<const NodeId> fns )
{
    ValueRefRows out;
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
    std::vector<ValueRefRow> via;
    for( const std::uint32_t t : idx.madeIn( fns, RefRole::Through ) )
    {
        const Reference& tr = ing.references[t];
        for( const std::uint32_t v : idx.valuesThrough( t ) )
        {
            for( const NodeId target : idx.targetsOf( v ) )
            {
                // the same function stores AND calls through the slot: the stored row carries through=
                auto same = std::find_if( out.rows.begin(), out.rows.end(), [ & ]( const ValueRefRow& r )
                {
                    return r.ref == v && r.to == target && r.through.empty();
                } );
                if( same != out.rows.end() )
                {
                    same->through = tr.fieldName;
                    continue;
                }
                auto grouped = std::find_if( via.begin(), via.end(), [ & ]( const ValueRefRow& r )
                {
                    return r.to == target && r.through == tr.fieldName;
                } );
                if( grouped != via.end() )
                {
                    if( vrBindLess( ing, ing.references[v], ing.references[grouped->ref] ) )
                    {
                        grouped->ref = v;
                    }
                    ++grouped->sites;
                    continue;
                }
                ValueRefRow row;
                row.ref     = v;
                row.to      = target;
                row.through = tr.fieldName;
                via.push_back( std::move( row ) );
            }
        }
    }
    for( ValueRefRow& r : via )
    {
        out.rows.push_back( std::move( r ) );
    }
    std::sort( out.rows.begin(), out.rows.end(), [ & ]( const ValueRefRow& a, const ValueRefRow& b ) { return vrCalleeRowLess( ing, a, b ); } );
    return out;
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
        if( r.role == RefRole::Through )
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

// --path / path_between: with NO directed call path (`unreachable`), how often `dstDefs` are used as values; 0 when a
// path exists, so the attribute is absent and the answer byte-identical.
inline std::size_t toValueRefsCount( const IngestResult& ing, bool unreachable, std::span<const NodeId> dstDefs, const ValueRefIndex* cached = nullptr )
{
    if( !unreachable )
    {
        return 0;
    }
    return cached != nullptr ? valueRefCallerRows( ing, *cached, dstDefs ).rows.size() : valueRefCallerRows( ing, ValueRefIndex( ing ), dstDefs ).rows.size();
}

}   // namespace rw
