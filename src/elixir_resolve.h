#pragma once

#include "model.h"

#include <algorithm>
#include <string>
#include <string_view>
#include <span>
#include <vector>

namespace rw
{

// The arity-less spelling of a `name/N` symbol name — `run/2` → `run`, `+/2` → `+`, `@type id/0` → `@type id`.
// A name with no `/digits` tail (a module, a plain attribute) comes back whole. A VIEW into `name`, so it is
// free to call per symbol; callers gate on Lang::Elixir, the function itself only reads the string.
inline std::string_view elixirBaseName( std::string_view name ) noexcept
{
    const std::size_t slash = name.rfind( '/' );
    if( slash == std::string_view::npos || slash + 1 == name.size() )
    {
        return name;
    }
    for( std::size_t i = slash + 1; i < name.size(); ++i )
    {
        if( name[ i ] < '0' || name[ i ] > '9' )
        {
            return name;
        }
    }
    return name.substr( 0, slash );
}

// Elixir binds functions by module/name/arity, independently of their physical file or directory.
// Reuse persisted Binding facts: defaults add lookup aliases, imports carry lexical spans, and
// callable declarations supply visibility. No per-reference payload or global symbol layout grows.
//
// `foldArity` keys the table by `Module::name` instead of `Module::name/N`, so a call reaches EVERY arity of
// the function its lexical facts bind it to. That is the --edit-check question — "which callers of run/1
// are now facing run/2?" — where the old arity no longer exists to key on (editcheck.h); every other verb
// keeps the exact key. Import filters (`only: [run: 1]`) still test the CALL's own arity either way.
struct ElixirResolver
{
    const IngestResult& ing;
    const bool          foldArity;
    HashMap<std::string, std::vector<NodeId>> functions;
    HashMap<std::uint32_t, std::vector<const Binding*>> imports;
    std::vector<std::uint8_t> privateFunction;
    std::vector<std::uint8_t> macroFunction;

    // the table key for a callable of `module` — see foldArity
    std::string keyOf( std::string_view module, std::string_view name ) const
    {
        std::string key( module );
        key += "::";
        key += foldArity ? elixirBaseName( name ) : name;
        return key;
    }

    explicit ElixirResolver( const IngestResult& input, bool foldArityKeys = false ) : ing( input ), foldArity( foldArityKeys )
    {
        std::size_t count = 0;
        for( const Symbol& symbol : ing.symbols ) { count += symbol.lang == Lang::Elixir ? 1 : 0; }
        if( count == 0 ) { return; }
        functions.reserve( count * 2 );
        imports.reserve( ing.files.size() );
        privateFunction.resize( ing.symbols.size(), 0 );
        macroFunction.resize( ing.symbols.size(), 0 );
        for( const Symbol& symbol : ing.symbols )
        {
            if( symbol.lang == Lang::Elixir && symbol.kind == SymKind::Function )
            {
                functions[ keyOf( symbol.scope, symbol.name ) ].push_back( symbol.id );
            }
        }
        for( const Binding& bind : ing.bindings )
        {
            if( bind.kind == LocalBindKind::ElixirImport ) { imports[ bind.fileId ].push_back( &bind ); }
            if( bind.kind != LocalBindKind::ElixirCallable ) { continue; }
            const auto found = functions.find( keyOf( bind.typeName, bind.var ) );
            if( found == functions.end() ) { continue; }
            for( NodeId node : found->second )
            {
                const Symbol& symbol = ing.symbols[ node ];
                if( symbol.fileId != bind.fileId || symbol.sigStartByte != bind.spanStart ) { continue; }
                privateFunction[ node ] = bind.importedName == "defp" || bind.importedName == "defmacrop" || bind.importedName == "defguardp";
                macroFunction[ node ] = bind.importedName == "defmacro" || bind.importedName == "defmacrop"
                                     || bind.importedName == "defguard" || bind.importedName == "defguardp";
            }
        }
        for( const Binding& bind : ing.bindings )
        {
            if( bind.kind != LocalBindKind::ElixirDefault ) { continue; }
            const auto found = functions.find( keyOf( bind.typeName, bind.importedName ) );
            if( found == functions.end() ) { continue; }
            // Copy before inserting: HashMap invalidates references when it grows.
            const auto targets = found->second;
            auto& aliases = functions[ keyOf( bind.typeName, bind.var ) ];
            for( NodeId target : targets )
            {
                if( ing.symbols[ target ].fileId == bind.fileId ) { aliases.push_back( target ); }
            }
        }
        for( auto& [ name, nodes ] : functions )
        {
            std::sort( nodes.begin(), nodes.end() );
            nodes.erase( std::unique( nodes.begin(), nodes.end() ), nodes.end() );
        }
    }

    void append( const Reference& ref, std::string_view module, bool external, std::string_view filter, std::vector<NodeId>& out ) const
    {
        const auto found = functions.find( keyOf( module, ref.calleeName ) );
        if( found == functions.end() ) { return; }
        for( NodeId node : found->second )
        {
            const Symbol& symbol = ing.symbols[ node ];
            if( external && privateFunction[ node ] ) { continue; }
            if( filter == "functions" && macroFunction[ node ] ) { continue; }
            if( filter == "macros" && !macroFunction[ node ] ) { continue; }
            // Prefer executable clauses over a default-argument declaration of the same function.
            if( symbol.endByte <= symbol.sigEndByte )
            {
                bool hasBody = false;
                for( NodeId other : found->second )
                {
                    const Symbol& candidate = ing.symbols[ other ];
                    if( candidate.fileId == symbol.fileId && candidate.endByte > candidate.sigEndByte ) { hasBody = true; break; }
                }
                if( hasBody ) { continue; }
            }
            out.push_back( node );
        }
    }

    void resolve( const Reference& ref, std::vector<NodeId>& out ) const
    {
        out.clear();
        const bool remote = ref.recv == RecvKind::ElixirModule || ref.recv == RecvKind::ElixirSelfModule;
        append( ref, ref.qualifier, remote, {}, out );
        if( remote ) { return; }
        bool explicitKernel = false;
        if( const auto found = imports.find( ref.fileId ); found != imports.end() )
        {
            // Fold every import of a module whose span encloses the call, in SOURCE order (bindings are start-byte
            // sorted per file). Kernel.SpecialForms.import/2: importing a module again ERASES its previous import —
            // a plain import, an `only:` list and `only: :functions`/`:macros` each reset what is admitted — EXCEPT
            // that `except:` is always exclusive on the import in force, so after `import L, only: [a: 1, b: 1]`
            // and `import L, except: [a: 1]` only b/1 is imported; with no import in force it excludes from all.
            // Reading newest-first and keeping one directive per module (the previous shape) let that later
            // `except:` admit every function the `only:` never listed (test/elixirnamearitycheck.sh G).
            struct ImportInForce
            {
                std::string_view module;
                std::string_view kind;     // all | only | functions | macros — anything else admits nothing
                std::string_view only;     // the `only:` list, "\nname/N\n"-delimited, when kind == only
                std::string      except;   // every `except:` list subtracted since the last reset, same delimiting
            };
            std::vector<ImportInForce> inForce;
            for( const Binding* bindPtr : found->second )
            {
                const Binding& bind = *bindPtr;
                if( ref.startByte < bind.spanStart || ref.startByte >= bind.spanEnd ) { continue; }
                auto state = std::find_if( inForce.begin(), inForce.end(), [ & ]( const ImportInForce& s ) { return s.module == bind.typeName; } );
                if( bind.var == "except" && state != inForce.end() )
                {
                    state->except += bind.importedName;
                    continue;
                }
                if( state == inForce.end() )
                {
                    inForce.push_back( { bind.typeName, {}, {}, {} } );
                    state = inForce.end() - 1;
                }
                state->kind   = bind.var == "except" ? std::string_view( "all" ) : std::string_view( bind.var );
                state->only   = bind.var == "only" ? std::string_view( bind.importedName ) : std::string_view{};
                state->except = bind.var == "except" ? bind.importedName : std::string{};
            }
            const std::string key = "\n" + ref.calleeName + "\n";
            for( const ImportInForce& state : inForce )
            {
                explicitKernel = explicitKernel || state.module == "Kernel";
                if( state.kind != "all" && state.kind != "only" && state.kind != "functions" && state.kind != "macros" ) { continue; }
                if( state.kind == "only" && state.only.find( key ) == std::string_view::npos ) { continue; }
                if( state.except.find( key ) != std::string::npos ) { continue; }
                append( ref, state.module, true, state.kind, out );
            }
        }
        if( !explicitKernel && out.empty() ) { append( ref, "Kernel", true, {}, out ); }
        std::sort( out.begin(), out.end() );
        out.erase( std::unique( out.begin(), out.end() ), out.end() );
    }

    bool reachesAny( const Reference& ref, std::span<const NodeId> selected ) const
    {
        if( ref.role != RefRole::Call )
        {
            for( NodeId node : selected )
            {
                const Symbol& symbol = ing.symbols[ node ];
                if( symbol.lang == Lang::Elixir && symbol.name == ref.calleeName && symbol.scope == ref.qualifier ) { return true; }
            }
            return false;
        }
        std::vector<NodeId> targets;
        resolve( ref, targets );
        for( NodeId node : targets )
        {
            if( std::find( selected.begin(), selected.end(), node ) != selected.end() ) { return true; }
        }
        return false;
    }
};

// Existing bare selectors still select all arities. Explicit f/N selects only that callable.
inline bool elixirNameMatches( const Symbol& symbol, std::string_view name ) noexcept
{
    return symbol.name == name || ( symbol.lang == Lang::Elixir && symbol.name.size() > name.size()
        && symbol.name.starts_with( name ) && symbol.name[ name.size() ] == '/' );
}

} // namespace rw
