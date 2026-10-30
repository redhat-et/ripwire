#pragma once
// regindex.h — REGISTRAR (lane registrar; reports/dispatch-register-design.md REGISTRY half, the Python + TypeScript first slice):
// a registry KEY joined to its registration sites and its consumers, printed on a compact-route --for answer as ONE present-only
// row per key.
//
// WHY. "Which receivers run when request_finished is sent?" (Django) and "which event plugin handles (keydown.enter)?" (Angular)
// are answered by REGISTRATIONS: `signals.request_finished.connect( close_old_connections )` in another module, or
// `{ provide: EVENT_MANAGER_PLUGINS, useClass: KeyEventsPlugin, multi: true }` in a provider array. The index already records each
// registered function or class as a Value row (src/ingest_valuerefs.h), but nothing joins the rows of one key, so the answer shows
// the key's definition (or its consumer) and none of what is registered under it.
//
// THE RECORD (one per registration site; the design note's RegSite shape, so the C++/Rust/Go slices compose onto it):
//   registrarDef  the registrar (Python: the method `C.m` whose parameter is stored into a container of self; TS: the provider
//                 record form itself, kNoNode)
//   siteRef       the Value reference of the registered value (its file:line is the registration site)
//   registered    the name as written at the site (resolved definitions are not needed to name it; `as=` = the record field)
//   key           {kind Identifier, text, the ONE definition it resolves to through the site file's imports}
//   test          the site is in a test path (counted, never listed)
// The language layer is model.h kRegLangs (RegForm, container stores, provider-record fields, consumer calls). A language
// without a row is byte-identical.
//
// IDENTITY (exact or no row; T1 / dispatch-classes §(a) 1, 3, 11, 14):
//   * the key is an IDENTIFIER resolved to one module-level definition: the site file's own, else the definition the file's
//     import of that name binds (`from m import K`, `import { K } from './m'`), or `mod.K` through a module import. Never a bare
//     name lookup across the tree; two definitions → no key → no row.
//   * Python: the registrar callee is never matched by name (`connect`, `add`, `register` are namesake-rich): the key variable
//     must be `K = C()` (a module-scope typed binding), C must resolve the same way to a class, C's method m must exist once and
//     carry a registrar fact (kValueRefRegParamScope) at the call's argument position. An unrelated `Pool().connect( f )` or a
//     `pool.connect( f )` whose class does not store the parameter gives nothing.
//   * TS: the key and the value are pairs of ONE object literal (same into= prefix, one `provide` pair under it); a lookalike
//     literal without `provide` gives nothing.
// HONESTY: a registration row is a static fact at a site — registered at import time; conditional or dynamic registration may
// exist; it is not proof the receiver ran. weak=/dispatch_uid=/multi semantics are not read. Test registrations are counted,
// not listed. Nothing here enters reaches=, a count, or the call graph.
//
// GATE (L-B, present-only): a key prints only with >= 2 non-test registrations, and only when the question names the key or one of
// its non-test registered names, or a SHOWN ranked row is a consumer of the key (the function that sends through it / the
// constructor that injects it, or that consumer's class) AND the question shares a word with the key's name. When the question names some key, only the
// named keys print. At most kRegRowCap keys, kRegSiteCap sites each.
// RIPWIRE_NO_REG_ROWS (any value) turns it off: the A/B handle.

#include "filter.h"            // isTestPath — test registrations are counted, not listed
#include "graph.h"             // jsImportKey — the "fileId#name" key
#include "langfacts.h"         // langFacts().memberSeparator — a consumer named as its rows are
#include "model.h"
#include "resolve.h"           // resolvePreciseInclude, resolvePythonModuleSuffix, lexicalNormalize — an import's module file
#include "serialize.h"         // escapeXml

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t kRegRowCap  = 2;   // keys per answer (a spew guard)
inline constexpr std::size_t kRegSiteCap = 4;   // listed non-test registrations per key; the rest is counted (n=, capped=1 next=)
inline constexpr std::size_t kRegConsumerCap = 2;

inline bool forRegRowsOn()
{
    return std::getenv( "RIPWIRE_NO_REG_ROWS" ) == nullptr;
}

inline constexpr std::string_view kForCompactRegLegend =
    "; reg key= p= a registry key and its definition, r sym= p= what is registered under it at p= (as= the record field), n= non-test "
    "registrations, tests= test ones (counted only), by= the registrar, consumers= where the key is sent or injected, a static fact "
    "at the site (registered at import time, conditional or dynamic registration may exist), not proof it ran";
inline constexpr std::string_view kForRegLegend =
    "; reg rows: a registry key= (its definition at p=) joined to the registrations of that key by the index: each r is what a site "
    "registers (sym= as written, p= the site, as= the provider field), n= the non-test registrations (up to 4 listed, capped=1 next= "
    "lists every site), tests= test registrations (counted, not listed), by= the registrar method, consumers= the functions that send "
    "or inject the key, a static fact at the site (registered at import time, conditional or dynamic registration may exist, and it "
    "is not proof the receiver ran)";
static_assert( kForCompactRegLegend.find( ';', 1 ) == std::string_view::npos && kForRegLegend.find( ';', 1 ) == std::string_view::npos,
               "one clause each: a ';' inside would split it (the legend's clause separator)" );
static_assert( kRegSiteCap == 4, "kForRegLegend states the cap: move the sentence with the constant" );

struct RegSite
{
    NodeId        registrarDef = kNoNode;   // Python: C.m; TS provider record: kNoNode
    std::uint32_t siteRef      = 0;         // the registered value's Value reference
    std::string   registered;               // as written
    std::string   as;                       // TS: the provider field (useClass…); "" otherwise
    NodeId        key          = kNoNode;   // the key's one definition
    bool          test         = false;
};

struct RegKey
{
    NodeId                     key = kNoNode;
    NodeId                     registrar = kNoNode;   // one registrar (Python), else kNoNode
    std::vector<RegSite>       sites;                 // source order (reference order)
    std::vector<NodeId>        consumers;             // enclosing symbols of a send / inject site, first-seen order
    std::vector<bool>          consumerTest;
};

class RegIndex
{
public:
    explicit RegIndex( const IngestResult& ing ) : m_ing( ing ) {}

    // Every key with at least one registration, in key-definition order. Empty when no language with a kRegLangs row is present.
    std::vector<RegKey> build()
    {
        std::vector<RegKey> keys;
        if( !std::ranges::any_of( m_ing.references, [ & ]( const Reference& r ) { return r.role == RefRole::Value && regLang( r.lang ) != nullptr; } ) )
        {
            return keys;
        }
        indexFacts();
        std::vector<RegSite> sites;
        collectReceiverSites( sites );
        collectProviderSites( sites );
        for( RegSite& s : sites )
        {
            auto it = std::ranges::find( keys, s.key, &RegKey::key );
            if( it == keys.end() )
            {
                keys.push_back( { s.key, s.registrarDef, {}, {}, {} } );
                it = keys.end() - 1;
            }
            if( it->registrar != s.registrarDef )
            {
                it->registrar = kNoNode;   // two registrars of one key: by= is not printed (both still registrations)
            }
            it->sites.push_back( std::move( s ) );
        }
        collectConsumers( keys );
        std::ranges::sort( keys, {}, &RegKey::key );
        return keys;
    }

    const IngestResult& ing() const noexcept { return m_ing; }

private:
    const IngestResult&                         m_ing;
    mutable HashMap<std::string, NodeId>        m_top;        // "fileId#name" → its one module-level definition (kAmbiguous: several)
    HashMap<std::string, std::uint32_t>         m_fileIndex;  // root-relative normalised path → fileId
    HashMap<std::uint32_t, std::vector<const Binding*>> m_imports;   // fileId → its import bindings
    HashMap<std::string, std::vector<const Binding*>>   m_types;     // "fileId#var" → module-scope typed bindings
    HashMap<NodeId, std::vector<std::uint16_t>> m_regFacts;   // registrar method → the parameter positions it stores

    static constexpr NodeId kAmbiguous = kNoNode - 1;
    static std::string fk( std::uint32_t f, std::string_view n ) { return jsImportKey( f, n ); }

    void indexFacts()
    {
        for( const Symbol& s : m_ing.symbols )
        {
            // a Python class row carries its own name as scope (ingest's class-scope convention): still module level
            if( ( s.scope.empty() || ( s.kind == SymKind::Class && s.scope == s.name ) ) && s.kind != SymKind::Method && s.kind != SymKind::Section && s.kind != SymKind::ModuleScope && s.kind != SymKind::Field
                && regLang( s.lang ) != nullptr )
            {
                const auto [ it, fresh ] = m_top.try_emplace( fk( s.fileId, s.name ), s.id );
                if( !fresh )
                {
                    it->second = kAmbiguous;
                }
            }
        }
        for( std::uint32_t f = 0; f < m_ing.files.size(); ++f )
        {
            m_fileIndex.emplace( lexicalNormalize( rootRelPath( m_ing, f ) ), f );
        }
        for( const Binding& b : m_ing.bindings )
        {
            if( b.kind == LocalBindKind::Import || b.kind == LocalBindKind::JsImport )
            {
                m_imports[ b.fileId ].push_back( &b );
            }
            else if( b.kind == LocalBindKind::Type && !b.typeName.empty()
                     && ( b.fromSymbol == kNoNode
                          || ( b.fromSymbol < m_ing.symbols.size() && m_ing.symbols[ b.fromSymbol ].kind == SymKind::Var
                               && m_ing.symbols[ b.fromSymbol ].scope.empty() && m_ing.symbols[ b.fromSymbol ].name == b.var ) ) )
            {
                m_types[ fk( b.fileId, b.var ) ].push_back( &b );
            }
        }
        for( const Reference& r : m_ing.references )
        {
            if( r.role == RefRole::Value && !r.qualifier.empty() && r.qualifier[0] == kValueRefRegParamScope && r.fromSymbol != kNoNode && r.argCountKnown )
            {
                m_regFacts[ r.fromSymbol ].push_back( r.argCount );
            }
        }
    }

    // The one module-level definition `name` has in file `f` (kNoNode: none, or several).
    NodeId topLevel( std::uint32_t f, std::string_view name ) const
    {
        // a name with no definition files an entry that reads as none (try_emplace never overwrites a definition)
        const NodeId one = m_top.try_emplace( fk( f, name ), kNoNode ).first->second;
        return one == kAmbiguous ? kNoNode : one;
    }
    // The file an import's module resolves to (kNoFile: a package outside the tree): valuerefindex.h importedModuleFile's rule.
    std::uint32_t moduleFile( std::uint32_t importer, std::string_view module, bool python ) const
    {
        if( module.empty() )
        {
            return kNoFile;
        }
        const std::uint32_t precise = resolvePreciseInclude( rootRelPath( m_ing, importer ), module, /*isAngle=*/false, m_fileIndex );
        if( precise != kNoFile || !python )
        {
            return precise;
        }
        return resolvePythonModuleSuffix( module, m_fileIndex, m_ing.fileRoot.empty() ? nullptr : &m_ing.fileRoot, importer );
    }
    // Identifier `name` as file `f` sees it: its own module-level definition, else the one its import of `name` binds.
    // A module that only re-imports the name (`from .dispatcher import Signal` in a package __init__) is followed, at most
    // kReexportDepth hops.
    static constexpr int kReexportDepth = 3;
    NodeId resolveIdent( std::uint32_t f, std::string_view name, int depth = 0 ) const
    {
        if( const NodeId own = topLevel( f, name ); own != kNoNode )
        {
            return own;
        }
        const auto imp = m_imports.find( f );
        if( imp == m_imports.end() )
        {
            return kNoNode;
        }
        NodeId found = kNoNode;
        for( const Binding* b : imp->second )
        {
            if( b->var != name )
            {
                continue;
            }
            const bool          js   = b->kind == LocalBindKind::JsImport;
            const std::uint32_t mf   = moduleFile( f, b->typeName, !js );
            const std::string_view there = js && !b->importedName.empty() ? std::string_view( b->importedName ) : name;
            const NodeId        def  = mf == kNoFile || mf == f ? kNoNode
                                     : depth < kReexportDepth ? resolveIdent( mf, there, depth + 1 ) : topLevel( mf, there );
            if( def == kNoNode || ( found != kNoNode && found != def ) )
            {
                return kNoNode;   // an unresolved import of the name, or two that disagree: no definition
            }
            found = def;
        }
        return found;
    }
    // `mod.K` (Python): `mod` is a module import of file `f` (`from pkg import mod` → pkg.mod first, `import pkg.mod as mod`).
    NodeId resolveDotted( std::uint32_t f, std::string_view text ) const
    {
        const std::size_t dot = text.find( '.' );
        if( dot == std::string_view::npos )
        {
            return identLike( text ) ? resolveIdent( f, text ) : kNoNode;
        }
        const std::string_view mod = text.substr( 0, dot ), name = text.substr( dot + 1 );
        if( !identLike( mod ) || !identLike( name ) )
        {
            return kNoNode;
        }
        const auto imp = m_imports.find( f );
        if( imp == m_imports.end() )
        {
            return kNoNode;
        }
        NodeId found = kNoNode;
        for( const Binding* b : imp->second )
        {
            if( b->var != mod || b->kind != LocalBindKind::Import )
            {
                continue;
            }
            const std::string sub = b->typeName.ends_with( '.' ) ? b->typeName + std::string( mod ) : b->typeName + "." + std::string( mod );
            std::uint32_t     mf  = moduleFile( f, sub, true );
            if( mf == kNoFile )
            {
                mf = moduleFile( f, b->typeName, true );
            }
            const NodeId def = mf == kNoFile ? kNoNode : topLevel( mf, name );
            if( def == kNoNode || ( found != kNoNode && found != def ) )
            {
                return kNoNode;
            }
            found = def;
        }
        return found;
    }
    static bool identLike( std::string_view s ) noexcept
    {
        return !s.empty() && std::ranges::all_of( s, []( char c ) { return c == '_' || c == '$' || ( c >= '0' && c <= '9' ) || ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || static_cast<unsigned char>( c ) >= 0x80; } )
            && !( s.front() >= '0' && s.front() <= '9' );
    }
    bool testFile( std::uint32_t f ) const { return isTestPath( rootRelPath( m_ing, f ) ); }

    // Python: the registrar method `C.m` of key variable `key` (`K = C()`), when m stores parameter `arg` (kNoNode otherwise).
    NodeId registrarOf( NodeId key, std::string_view method, std::uint16_t arg ) const
    {
        const Symbol& k  = m_ing.symbols[key];
        const auto    tb = m_types.find( fk( k.fileId, k.name ) );
        if( k.kind != SymKind::Var || tb == m_types.end() )
        {
            return kNoNode;
        }
        std::string_view cls;
        for( const Binding* b : tb->second )
        {
            if( !cls.empty() && cls != b->typeName )
            {
                return kNoNode;   // K is bound to two classes: no registrar
            }
            cls = b->typeName;
        }
        const NodeId c = resolveIdent( k.fileId, cls );
        if( c == kNoNode || m_ing.symbols[c].kind != SymKind::Class )
        {
            return kNoNode;
        }
        const Symbol& cs = m_ing.symbols[c];
        NodeId        m  = kNoNode;
        for( const Symbol& s : m_ing.symbols )
        {
            if( s.fileId == cs.fileId && s.scope == cs.name && s.name == method && ( s.kind == SymKind::Function || s.kind == SymKind::Method ) )
            {
                if( m != kNoNode )
                {
                    return kNoNode;   // two definitions of C.m: no registrar (exact or no row)
                }
                m = s.id;
            }
        }
        const auto facts = m == kNoNode ? m_regFacts.end() : m_regFacts.find( m );
        return facts != m_regFacts.end() && std::ranges::find( facts->second, arg ) != facts->second.end() ? m : kNoNode;
    }

    // Python ReceiverMethod: a Value row at argument k of `K.m( … )` / `mod.K.m( … )` (into= "<receiver>.<m>#arg<k>").
    void collectReceiverSites( std::vector<RegSite>& out ) const
    {
        HashMap<std::string, char> methods;   // the registrar facts' method names: the only calls worth resolving
        for( const auto& [ id, args ] : m_regFacts )
        {
            methods.try_emplace( m_ing.symbols[id].name, char( 1 ) );
        }
        if( methods.empty() )
        {
            return;
        }
        for( std::uint32_t i = 0; i < m_ing.references.size(); ++i )
        {
            const Reference& r   = m_ing.references[i];
            const RegLang*   row = r.role == RefRole::Value ? regLang( r.lang ) : nullptr;
            if( row == nullptr || row->form != RegForm::ReceiverMethod || isSlotJoinRecord( r ) || r.calleeName.empty() || !r.argCountKnown )
            {
                continue;
            }
            const std::string_view into = r.fieldName;
            const std::size_t      hash = into.rfind( "#arg" );
            const std::size_t      dot  = hash == std::string_view::npos ? std::string_view::npos : into.rfind( '.', hash );
            if( dot == std::string_view::npos || into.substr( hash + 4 ) != std::to_string( r.argCount ) )
            {
                continue;
            }
            const std::string_view method = into.substr( dot + 1, hash - dot - 1 );
            if( !methods.contains( std::string( method ) ) )
            {
                continue;
            }
            const NodeId key = resolveDotted( r.fileId, into.substr( 0, dot ) );
            const NodeId reg = key == kNoNode ? kNoNode : registrarOf( key, method, r.argCount );
            if( reg == kNoNode )
            {
                continue;
            }
            out.push_back( { reg, i, r.calleeName, "", key, testFile( r.fileId ) } );
        }
    }

    // TS ProviderRecord: `{ provide: K, useClass: C }` — the value pair and the ONE `provide` pair of the same object literal.
    void collectProviderSites( std::vector<RegSite>& out ) const
    {
        struct Pair { std::uint32_t ref; std::string_view prefix; std::string_view field; };
        HashMap<std::uint32_t, std::vector<Pair>> keysByFile;
        std::vector<Pair>                         values;
        for( std::uint32_t i = 0; i < m_ing.references.size(); ++i )
        {
            const Reference& r   = m_ing.references[i];
            const RegLang*   row = r.role == RefRole::Value ? regLang( r.lang ) : nullptr;
            if( row == nullptr || row->form != RegForm::ProviderRecord || isSlotJoinRecord( r ) || r.calleeName.empty() || r.composeRel.size() < 2
                || r.composeRel[0] != '.' )
            {
                continue;
            }
            const std::string_view field = std::string_view( r.composeRel ).substr( 1 );
            const std::string_view into  = r.fieldName;
            if( !into.ends_with( r.composeRel ) )
            {
                continue;   // the written slot was capped (vrClean): its object is not provable
            }
            const Pair p{ i, into.substr( 0, into.size() - r.composeRel.size() ), field };
            if( field == row->keyField )
            {
                keysByFile[ r.fileId ].push_back( p );
            }
            else if( std::ranges::find( row->valueFields, field ) != row->valueFields.end() )
            {
                values.push_back( p );
            }
        }
        constexpr std::uint32_t kSameObjectBytes = 600;   // one object literal's pairs: a capped prefix never joins two objects
        for( const Pair& v : values )
        {
            const Reference& r  = m_ing.references[ v.ref ];
            const auto       kf = keysByFile.find( r.fileId );
            if( kf == keysByFile.end() )
            {
                continue;
            }
            const Pair* key = nullptr;
            std::size_t n   = 0;
            for( const Pair& k : kf->second )
            {
                const Reference& kr = m_ing.references[ k.ref ];
                if( k.prefix == v.prefix && kr.fromSymbol == r.fromSymbol )
                {
                    ++n;
                    key = &k;
                }
            }
            if( n != 1 )
            {
                continue;   // no `provide` pair, or two objects share the prefix: not provably one record
            }
            const Reference& kr   = m_ing.references[ key->ref ];
            const std::uint32_t d = kr.startByte > r.startByte ? kr.startByte - r.startByte : r.startByte - kr.startByte;
            const NodeId     kdef = d <= kSameObjectBytes ? resolveIdent( r.fileId, kr.calleeName ) : kNoNode;
            if( kdef == kNoNode )
            {
                continue;
            }
            out.push_back( { kNoNode, v.ref, r.calleeName, std::string( v.field ), kdef, testFile( r.fileId ) } );
        }
        std::ranges::sort( out, {}, &RegSite::siteRef );
    }

    void addConsumer( RegKey& k, NodeId from ) const
    {
        if( from == kNoNode || std::ranges::find( k.consumers, from ) != k.consumers.end() )
        {
            return;
        }
        k.consumers.push_back( from );
        k.consumerTest.push_back( testFile( m_ing.symbols[from].fileId ) );
    }

    // Consumers: Python — a call `K.x( … )` / `mod.K.x( … )` on the key that is neither its registrar method nor a consumerSkip
    // method; TS — a consumerCalls argument naming the key (`@Inject( K )`, `inject( K )`).
    void collectConsumers( std::vector<RegKey>& keys ) const
    {
        if( keys.empty() )
        {
            return;
        }
        HashMap<std::string, std::vector<std::size_t>> byName;   // key name → keys
        for( std::size_t k = 0; k < keys.size(); ++k )
        {
            byName[ m_ing.symbols[ keys[k].key ].name ].push_back( k );
        }
        for( const Reference& r : m_ing.references )
        {
            const RegLang* row = regLang( r.lang );
            if( row == nullptr || r.fromSymbol == kNoNode || isSlotJoinRecord( r ) )
            {
                continue;
            }
            if( row->form == RegForm::ProviderRecord && r.role == RefRole::Value )
            {
                const auto it = byName.find( r.calleeName );
                const std::size_t hash = std::string_view( r.fieldName ).rfind( "#arg" );
                if( it == byName.end() || hash == std::string::npos
                    || std::ranges::find( row->consumerCalls, std::string_view( r.fieldName ).substr( 0, hash ) ) == row->consumerCalls.end() )
                {
                    continue;
                }
                const NodeId def = resolveIdent( r.fileId, r.calleeName );
                for( const std::size_t k : it->second )
                {
                    if( keys[k].key == def )
                    {
                        addConsumer( keys[k], r.fromSymbol );
                    }
                }
            }
            else if( row->form == RegForm::ReceiverMethod && r.role == RefRole::Call && !r.recvVar.empty() )
            {
                const std::string_view leaf = r.fieldName.empty() ? std::string_view( r.recvVar ) : std::string_view( r.fieldName );
                const auto             it   = byName.find( std::string( leaf ) );
                if( it == byName.end() || std::ranges::find( row->consumerSkip, std::string_view( r.calleeName ) ) != row->consumerSkip.end() )
                {
                    continue;
                }
                const NodeId def = resolveDotted( r.fileId, r.fieldName.empty() ? r.recvVar : r.recvVar + "." + r.fieldName );
                for( const std::size_t k : it->second )
                {
                    const RegKey& key = keys[k];
                    if( key.key == def && ( key.registrar == kNoNode || m_ing.symbols[ key.registrar ].name != r.calleeName ) )
                    {
                        addConsumer( keys[k], r.fromSymbol );
                    }
                }
            }
        }
    }
};

namespace reg_detail
{
// The class a member is written in: its scope, else (a TS `constructor` row carries none) the innermost class row of its file
// whose extent holds it. "" when none.
inline std::string_view ownerOf( const IngestResult& ing, const Symbol& s )
{
    if( !s.scope.empty() )
    {
        return s.scope;
    }
    if( s.kind != SymKind::Method && s.name != "constructor" )
    {
        return {};
    }
    const Symbol* best = nullptr;
    for( const Symbol& c : ing.symbols )
    {
        if( c.fileId == s.fileId && c.kind == SymKind::Class && c.sigStartByte < s.sigStartByte && s.endByte <= c.endByte
            && ( best == nullptr || c.sigStartByte > best->sigStartByte ) )
        {
            best = &c;
        }
    }
    return best == nullptr ? std::string_view() : std::string_view( best->name );
}
inline std::string qualName( const IngestResult& ing, const Symbol& s )
{
    const std::string_view owner = ownerOf( ing, s );
    return owner.empty() ? s.name : std::string( owner ) + std::string( langFacts( s.lang ).memberSeparator ) + s.name;
}
// The identifier tokens of the question (`request_finished`, `EVENT_MANAGER_PLUGINS`): the "names the key" test.
inline std::vector<std::string> taskIdents( std::string_view task )
{
    std::vector<std::string> out;
    std::string              cur;
    for( const char c : std::string( task ) + " " )
    {
        if( c == '_' || c == '$' || ( c >= '0' && c <= '9' ) || ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) )
        {
            cur += c;
        }
        else if( !cur.empty() )
        {
            out.push_back( std::move( cur ) );
            cur.clear();
        }
    }
    return out;
}
// The key's name subtokens (snake / camel split, lower-cased, >= 3 letters, a trailing plural `s` dropped) against the question's
// plain words normalised the same way (an identifier in the question stays ONE word: `findPluginFor` is not "plugin").
inline std::string normWord( std::string w )
{
    for( char& c : w )
    {
        c = ( c >= 'A' && c <= 'Z' ) ? static_cast<char>( c - 'A' + 'a' ) : c;
    }
    if( w.size() > 3 && w.back() == 's' )
    {
        w.pop_back();
    }
    return w;
}
inline bool sharesWord( std::string_view key, const std::vector<std::string>& words )
{
    std::vector<std::string> subs;
    std::string              cur;
    for( std::size_t i = 0; i <= key.size(); ++i )
    {
        const char c     = i < key.size() ? key[i] : '_';
        const bool split = c == '_' || c == '$' || ( c >= '0' && c <= '9' )
                        || ( c >= 'A' && c <= 'Z' && !cur.empty() && cur.back() >= 'a' && cur.back() <= 'z' );
        if( split && !cur.empty() )
        {
            subs.push_back( normWord( std::move( cur ) ) );
            cur.clear();
        }
        if( c != '_' && c != '$' && !( c >= '0' && c <= '9' ) )
        {
            cur += c;
        }
    }
    return std::ranges::any_of( subs, [ & ]( const std::string& sub )
    {
        return sub.size() >= 3 && std::ranges::any_of( words, [ & ]( const std::string& w ) { return normWord( w ) == sub; } );
    } );
}
}   // namespace reg_detail

// THE RENDER: the <reg> rows a compact --for answer gains for the shown ranked rows `shownIds` and question `task` (the gate
// above). "" when no key passes it.
inline std::string renderRegRows( const IngestResult& ing, std::span<const NodeId> shownIds, std::string_view task )
{
    RegIndex                  idx( ing );
    const std::vector<RegKey> keys = idx.build();
    if( keys.empty() )
    {
        return {};
    }
    const std::vector<std::string> words = reg_detail::taskIdents( task );
    const auto named = [ & ]( std::string_view n ) { return std::ranges::find( words, n ) != words.end(); };
    const auto shown = [ & ]( NodeId id )
    {
        if( std::ranges::find( shownIds, id ) != shownIds.end() )
        {
            return true;
        }
        const Symbol&          s     = ing.symbols[id];   // or its class is a shown row (the constructor that injects the key)
        const std::string_view owner = reg_detail::ownerOf( ing, s );
        return !owner.empty() && std::ranges::any_of( shownIds, [ & ]( NodeId o )
        {
            return o < ing.symbols.size() && ing.symbols[o].fileId == s.fileId && ing.symbols[o].name == owner
                && ( ing.symbols[o].kind == SymKind::Class || isStructOrNamedType( ing.symbols[o].kind ) );
        } );
    };
    struct Pick { std::size_t k; bool consumerShown; std::size_t n; bool asked; };
    std::vector<Pick> picks;
    for( std::size_t k = 0; k < keys.size(); ++k )
    {
        const RegKey&     key = keys[k];
        const std::size_t n   = static_cast<std::size_t>( std::ranges::count( key.sites, false, &RegSite::test ) );
        bool              consumerShown = false;
        for( std::size_t c = 0; c < key.consumers.size(); ++c )
        {
            consumerShown = consumerShown || ( !key.consumerTest[c] && shown( key.consumers[c] ) );
        }
        const bool asked = named( ing.symbols[ key.key ].name )
                        || std::ranges::any_of( key.sites, [ & ]( const RegSite& s ) { return !s.test && named( s.registered ); } );
        // fire table (LD-2): a shown consumer alone fired on Angular DI tokens with one provider (ChangeDetectionScheduler on 4
        // rows) and on a sibling signal (request_started on a runserver question): a registry needs >= 2 non-test registrations,
        // and a shown consumer opens the gate only when the question shares a word with the key's name (EVENT_MANAGER_PLUGINS ~
        // "which event plugin …")
        if( n >= 2 && ( asked || ( consumerShown && reg_detail::sharesWord( std::string_view( ing.symbols[ key.key ].name ), words ) ) ) )
        {
            picks.push_back( { k, consumerShown, n, asked } );
        }
    }
    // A question that names a key is about THAT key: a sibling key shown only through a shared consumer (request_started beside
    // request_finished, both sent by one handler) is not printed then.
    if( std::ranges::any_of( picks, &Pick::asked ) )
    {
        std::erase_if( picks, []( const Pick& p ) { return !p.asked; } );
    }
    std::ranges::stable_sort( picks, []( const Pick& a, const Pick& b ) { return a.consumerShown != b.consumerShown ? a.consumerShown : a.n > b.n; } );
    std::string       out;
    std::vector<char> esc;
    for( std::size_t p = 0; p < picks.size() && p < kRegRowCap; ++p )
    {
        const RegKey& key = keys[ picks[p].k ];
        const Symbol& ks  = ing.symbols[ key.key ];
        out += "<reg key=\"";
        out += escapeXml( ks.name, esc );
        out += "\" p=\"";
        out += escapeXml( rootRelPath( ing, ks.fileId ), esc );
        out += ":" + std::to_string( ks.line ) + "\"";
        if( key.registrar != kNoNode )
        {
            out += " by=\"";
            out += escapeXml( reg_detail::qualName( ing, ing.symbols[ key.registrar ] ), esc );
            out += "\"";
        }
        const std::size_t n     = picks[p].n;
        const std::size_t tests = key.sites.size() - n;
        out += " n=\"" + std::to_string( n ) + "\"";
        if( tests > 0 )
        {
            out += " tests=\"" + std::to_string( tests ) + "\"";
        }
        std::vector<std::string> cons;
        std::size_t              consMore = 0;
        for( std::size_t c = 0; c < key.consumers.size(); ++c )
        {
            if( key.consumerTest[c] )
            {
                continue;
            }
            std::string nm = reg_detail::qualName( ing, ing.symbols[ key.consumers[c] ] );
            if( std::ranges::find( cons, nm ) != cons.end() )
            {
                continue;
            }
            if( cons.size() < kRegConsumerCap )
            {
                cons.push_back( std::move( nm ) );
            }
            else
            {
                ++consMore;
            }
        }
        if( !cons.empty() )
        {
            out += " consumers=\"";
            for( std::size_t c = 0; c < cons.size(); ++c )
            {
                out += c == 0 ? "" : ",";
                out += escapeXml( cons[c], esc );
            }
            out += "\"";
            if( consMore > 0 )
            {
                out += " consumers_more=\"" + std::to_string( consMore ) + "\"";
            }
        }
        if( n > kRegSiteCap )
        {
            out += " capped=\"1\" next=\"--grep=";
            out += escapeXml( ks.name, esc );
            out += "\"";
        }
        out += ">";
        std::size_t listed = 0;
        for( const RegSite& s : key.sites )
        {
            if( s.test || listed == kRegSiteCap )
            {
                continue;
            }
            ++listed;
            const Reference& r = ing.references[ s.siteRef ];
            out += "<r sym=\"";
            out += escapeXml( s.registered, esc );
            out += "\"";
            if( !s.as.empty() )
            {
                out += " as=\"";
                out += escapeXml( s.as, esc );
                out += "\"";
            }
            out += " p=\"";
            out += escapeXml( rootRelPath( ing, r.fileId ), esc );
            out += ":" + std::to_string( r.line ) + "\"/>";
        }
        out += "</reg>";
    }
    return out;
}

// THE SPLICE: the <reg> rows go just inside the end of <sigs> (after the ranked rows they join). Returns the bytes added.
inline std::size_t spliceRegRows( std::string& sigs, const IngestResult& ing, std::span<const NodeId> shownIds, std::string_view task )
{
    constexpr std::string_view kClose = "</sigs>";
    if( !sigs.ends_with( kClose ) )
    {
        return 0;
    }
    const std::string rows = renderRegRows( ing, shownIds, task );
    sigs.insert( sigs.size() - kClose.size(), rows );
    return rows.size();
}

}   // namespace rw
