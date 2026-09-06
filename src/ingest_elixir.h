#pragma once

#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_elixir.h is a section of ingest.cpp; include it only there"
#endif

namespace rw
{
namespace
{

// Included by ingest.cpp after the shared AST helpers.
// Elixir keywords are identifiers, so tags.scm alone cannot distinguish def f(x) from
// ordinary(f(x)). Keep the text gates local to this grammar instead of changing every tags pass.
/// Return an identifier call target as a view into src, or an empty view for null or remote targets.
std::string_view elixirTarget( TSNode node, std::string_view src ) noexcept
{
    if( ts_node_is_null( node ) )
    {
        return {};
    }
    const TSNode target = ts_node_child_by_field_name( node, "target", 6 );
    if( ts_node_is_null( target ) || std::strcmp( ts_node_type( target ), "identifier" ) != 0 )
    {
        return {};
    }
    return nodeTextOf( target, src );
}

/// Return whether target introduces a function, macro, guard, or delegate definition.
bool elixirFunctionKeyword( std::string_view target ) noexcept
{
    constexpr std::string_view keywords[] = { "def", "defp", "defmacro", "defmacrop", "defguard", "defguardp", "defdelegate" };
    return std::find( std::begin( keywords ), std::end( keywords ), target ) != std::end( keywords );
}

/// Return whether target introduces a statically named module or protocol, excluding defimpl.
bool elixirModuleKeyword( std::string_view target ) noexcept
{
    return target == "defmodule" || target == "defprotocol";
}

/// Find the direct arguments child of node; return a null node when node or its arguments are absent.
TSNode elixirArguments( TSNode node ) noexcept
{
    if( ts_node_is_null( node ) )
    {
        return {};
    }
    for( std::uint32_t childId = 0; childId < ts_node_named_child_count( node ); ++childId )
    {
        const TSNode child = ts_node_named_child( node, childId );
        if( std::strcmp( ts_node_type( child ), "arguments" ) == 0 )
        {
            return child;
        }
    }
    return {};
}

/// Return the first direct call argument, or a null node for an absent or empty argument list.
TSNode elixirFirstArgument( TSNode node ) noexcept
{
    const TSNode args = elixirArguments( node );
    return ts_node_is_null( args ) ? TSNode{} : ts_node_named_child( args, 0 );
}

// Both `do ... end` and `do: expression` carry a body, but neither has a body: field.
/// Find a definition's direct do-block or do-keyword value without adopting an ancestor's body.
/// node must be non-null; src must contain its source span. Return a null node when no body exists.
TSNode elixirBody( TSNode node, std::string_view src ) noexcept
{
    for( std::uint32_t childId = 0; childId < ts_node_named_child_count( node ); ++childId )
    {
        const TSNode child = ts_node_named_child( node, childId );
        if( std::strcmp( ts_node_type( child ), "do_block" ) == 0 )
        {
            return child;
        }
    }
    const TSNode args = elixirArguments( node );
    if( ts_node_is_null( args ) )
    {
        return {};
    }
    for( std::uint32_t argId = 0; argId < ts_node_named_child_count( args ); ++argId )
    {
        const TSNode arg = ts_node_named_child( args, argId );
        if( std::strcmp( ts_node_type( arg ), "keywords" ) != 0 )
        {
            continue;
        }
        for( std::uint32_t pairId = 0; pairId < ts_node_named_child_count( arg ); ++pairId )
        {
            const TSNode pair = ts_node_named_child( arg, pairId );
            auto key = nodeTextOf( ts_node_child_by_field_name( pair, "key", 3 ), src );
            while( !key.empty() && std::isspace( static_cast<unsigned char>( key.back() ) ) )
            {
                key.remove_suffix( 1 );
            }
            if( key == "do:" )
            {
                return ts_node_child_by_field_name( pair, "value", 5 );
            }
        }
    }
    return {};
}

/// Count syntactic parameters in an ordinary or guarded definition head, saturating at UINT16_MAX.
/// Missing argument lists count as zero; this does not infer callable arities from default values.
std::uint16_t elixirParams( TSNode node ) noexcept
{
    TSNode head = elixirFirstArgument( node );
    if( !ts_node_is_null( head ) && std::strcmp( ts_node_type( head ), "binary_operator" ) == 0 )
    {
        head = ts_node_child_by_field_name( head, "left", 4 );
    }
    const TSNode args = elixirArguments( head );
    const auto count = ts_node_is_null( args ) ? 0u : ts_node_named_child_count( args );
    return std::uint16_t( std::min( count, std::uint32_t( 65535 ) ) );
}

/// Decide whether a candidate definition or call capture represents supported executable Elixir syntax.
/// role and name are non-null query captures into src. Reject quoted, attributed, dynamic, and defimpl
/// syntax; retain executable defaults while excluding declaration heads and argument patterns.
bool elixirKeepCapture( TSNode role, TSNode name, bool isDef, SymKind kind, std::string_view src ) noexcept
{
    // Quoted syntax and module attributes (notably @spec/@type) are not runtime call sites.
    for( TSNode parent = ts_node_parent( role ); !ts_node_is_null( parent ); parent = ts_node_parent( parent ) )
    {
        if( elixirTarget( parent, src ) == "quote" || elixirTarget( parent, src ) == "defimpl"
            || ( std::strcmp( ts_node_type( parent ), "unary_operator" ) == 0 && nodeFieldText( parent, "operator", 8, src ) == "@" ) )
        {
            return false;
        }
    }
    const auto target = elixirTarget( role, src );
    if( isDef )
    {
        if( target == "test" && std::strcmp( ts_node_type( name ), "string" ) == 0 )
        {
            const auto title = nodeTextOf( name, src );
            if( title.size() < 2 || title.front() != '"' || title.back() != '"' || title.starts_with( "\"\"\"" ) )
            {
                return false; // only complete, ordinary string titles have a static display name here
            }
            for( std::uint32_t childId = 0; childId < ts_node_named_child_count( name ); ++childId )
            {
                if( std::strcmp( ts_node_type( ts_node_named_child( name, childId ) ), "interpolation" ) == 0 )
                {
                    return false;
                }
            }
            return true;
        }
        return kind == SymKind::Other ? elixirModuleKeyword( target ) : elixirFunctionKeyword( target );
    }
    const TSNode firstArg = elixirFirstArgument( role );
    if( target == "test" && !ts_node_is_null( firstArg ) && std::strcmp( ts_node_type( firstArg ), "string" ) == 0 && !ts_node_is_null( elixirBody( role, src ) ) )
    {
        return false; // the test declaration itself is not a call
    }
    const TSNode callTarget = ts_node_child_by_field_name( role, "target", 6 );
    if( !ts_node_is_null( callTarget ) && std::strcmp( ts_node_type( callTarget ), "dot" ) == 0 )
    {
        const TSNode receiver = ts_node_child_by_field_name( callTarget, "left", 4 );
        if( ts_node_is_null( receiver ) || std::strcmp( ts_node_type( receiver ), "alias" ) != 0 )
        {
            return false; // runtime receiver / anonymous function dispatch cannot name a module
        }
    }
    constexpr std::string_view special[] = { "defimpl", "defstruct", "defexception", "defoverridable", "alias", "import", "require", "use",
                                            "quote", "unquote", "unquote_splicing", "case", "cond", "for", "if", "unless", "with", "receive", "try" };
    if( elixirFunctionKeyword( target ) || elixirModuleKeyword( target )
        || std::find( std::begin( special ), std::end( special ), target ) != std::end( special ) )
    {
        return false;
    }
    bool inDefault = false;
    for( TSNode parent = ts_node_parent( role ); !ts_node_is_null( parent ); parent = ts_node_parent( parent ) )
    {
        if( std::strcmp( ts_node_type( parent ), "binary_operator" ) == 0 && nodeFieldText( parent, "operator", 8, src ) == "\\\\" )
        {
            const TSNode value = ts_node_child_by_field_name( parent, "right", 5 );
            inDefault = inDefault || ( !ts_node_is_null( value ) && ts_node_start_byte( role ) >= ts_node_start_byte( value )
                                      && ts_node_end_byte( role ) <= ts_node_end_byte( value ) );
        }
        if( !elixirFunctionKeyword( elixirTarget( parent, src ) ) )
        {
            continue;
        }
        TSNode head = elixirFirstArgument( parent );
        if( !ts_node_is_null( head ) && std::strcmp( ts_node_type( head ), "binary_operator" ) == 0 )
        {
            head = ts_node_child_by_field_name( head, "left", 4 );
        }
        if( !ts_node_is_null( head ) && ts_node_start_byte( name ) >= ts_node_start_byte( head ) && ts_node_end_byte( name ) <= ts_node_end_byte( head ) )
        {
            return inDefault;
        }
    }
    return true;
}

/// Build the enclosing static module/protocol scope, outermost first, from ancestors of node.
/// Return an owned dotted name, or an empty string at file scope; alias resolution is not inferred.
std::string elixirScope( TSNode node, std::string_view src )
{
    std::string scope;
    for( TSNode parent = ts_node_parent( node ); !ts_node_is_null( parent ); parent = ts_node_parent( parent ) )
    {
        if( elixirModuleKeyword( elixirTarget( parent, src ) ) )
        {
            const auto name = nodeTextOf( elixirFirstArgument( parent ), src );
            if( !name.empty() )
            {
                scope = std::string( name ) + ( scope.empty() ? "" : "." + scope );
            }
        }
    }
    return scope;
}

} // namespace
} // namespace rw
