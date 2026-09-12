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
        std::vector<std::string_view> seen;
        if( const auto found = imports.find( ref.fileId ); found != imports.end() )
        {
            // Later directives in an enclosing lexical span replace earlier imports of that module.
            for( auto it = found->second.rbegin(); it != found->second.rend(); ++it )
            {
                const Binding& bind = **it;
                if( ref.startByte < bind.spanStart || ref.startByte >= bind.spanEnd ) { continue; }
                if( std::find( seen.begin(), seen.end(), bind.typeName ) != seen.end() ) { continue; }
                seen.push_back( bind.typeName );
                explicitKernel = explicitKernel || bind.typeName == "Kernel";
                const bool listed = bind.importedName.find( "\n" + ref.calleeName + "\n" ) != std::string::npos;
                if( ( bind.var == "only" && !listed ) || ( bind.var == "except" && listed ) ) { continue; }
                if( bind.var != "all" && bind.var != "only" && bind.var != "except" && bind.var != "functions" && bind.var != "macros" ) { continue; }
                append( ref, bind.typeName, true, bind.var, out );
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
