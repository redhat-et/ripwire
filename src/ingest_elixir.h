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
    for( std::uint32_t i = 0; !ts_node_is_null( args ) && i < ts_node_named_child_count( args ); ++i )
    {
        const TSNode child = ts_node_named_child( args, i );
        if( std::strcmp( ts_node_type( child ), "comment" ) != 0 ) { return child; }
    }
    return {};
}

// Both `do ... end` and `do: expression` carry a body, but neither has a body: field.
/// Find the value of a `key:` entry in node's own keyword arguments (`def f(), do: 1`, `defimpl P, for: T`).
/// key carries its trailing colon. Return a null node when node has no such keyword.
TSNode elixirKeywordValue( TSNode node, std::string_view key, std::string_view src ) noexcept
{
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
            auto found = nodeTextOf( ts_node_child_by_field_name( pair, "key", 3 ), src );
            while( !found.empty() && std::isspace( static_cast<unsigned char>( found.back() ) ) )
            {
                found.remove_suffix( 1 );
            }
            if( found == key )
            {
                return ts_node_child_by_field_name( pair, "value", 5 );
            }
        }
    }
    return {};
}

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
    return elixirKeywordValue( node, "do:", src );
}

/// Count syntactic parameters in an ordinary or guarded definition head, saturating at UINT16_MAX.
/// Missing argument lists count as zero; this does not infer callable arities from default values.
std::uint16_t elixirParams( TSNode node, std::string_view src ) noexcept
{
    TSNode head = elixirFirstArgument( node );
    if( !ts_node_is_null( head ) && std::strcmp( ts_node_type( head ), "binary_operator" ) == 0 && nodeFieldText( head, "operator", 8, src ) == "when" )
    {
        head = ts_node_child_by_field_name( head, "left", 4 );
    }
    if( !ts_node_is_null( head ) && std::strcmp( ts_node_type( head ), "binary_operator" ) == 0 ) { return 2; }
    if( !ts_node_is_null( head ) && std::strcmp( ts_node_type( head ), "unary_operator" ) == 0 ) { return 1; }
    const TSNode args = elixirArguments( head );
    std::uint32_t count = 0;
    for( std::uint32_t i = 0; !ts_node_is_null( args ) && i < ts_node_named_child_count( args ); ++i )
    {
        count += std::strcmp( ts_node_type( ts_node_named_child( args, i ) ), "comment" ) != 0 ? 1u : 0u;
    }
    return std::uint16_t( std::min( count, std::uint32_t( 65535 ) ) );
}

std::string_view elixirAttribute( TSNode node, std::string_view src ) noexcept
{
    if( ts_node_is_null( node ) || nodeFieldText( node, "operator", 8, src ) != "@" ) { return {}; }
    return elixirTarget( ts_node_child_by_field_name( node, "operand", 7 ), src );
}

bool elixirTypedAttribute( std::string_view name ) noexcept
{
    return name == "type" || name == "typep" || name == "opaque" || name == "callback" || name == "macrocallback";
}

bool elixirMetadataAttribute( std::string_view name ) noexcept
{
    constexpr std::string_view metadata[] = { "doc", "moduledoc", "typedoc", "spec", "impl", "behaviour", "behavior", "derive", "enforce_keys",
        "dialyzer", "on_load", "before_compile", "after_compile", "after_verify", "optional_callbacks", "compile", "external_resource", "vsn", "file" };
    return elixirTypedAttribute( name ) || std::find( std::begin( metadata ), std::end( metadata ), name ) != std::end( metadata );
}

/// Decide whether a candidate definition or call capture represents supported executable Elixir syntax.
/// role and name are non-null query captures into src. Reject quoted and dynamic syntax and metadata
/// references; retain executable defaults and attributes while excluding declaration heads and patterns.
bool elixirKeepCapture( TSNode role, TSNode name, bool isDef, SymKind kind, std::string_view src ) noexcept
{
    // Quoted syntax and module attributes (notably @spec/@type) are not runtime call sites.
    for( TSNode parent = ts_node_parent( role ); !ts_node_is_null( parent ); parent = ts_node_parent( parent ) )
    {
        if( elixirTarget( parent, src ) == "quote" )
        {
            return false;
        }
        if( std::strcmp( ts_node_type( parent ), "unary_operator" ) == 0 && nodeFieldText( parent, "operator", 8, src ) == "@" )
        {
            if( elixirMetadataAttribute( elixirAttribute( parent, src ) )
                || ts_node_eq( ts_node_child_by_field_name( parent, "operand", 7 ), role ) ) { return false; }
        }
    }
    const auto target = elixirTarget( role, src );
    if( isDef )
    {
        if( const auto attribute = elixirAttribute( role, src ); !attribute.empty() )
        {
            return kind == SymKind::Struct ? elixirTypedAttribute( attribute ) : !elixirMetadataAttribute( attribute );
        }
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
        // `defimpl` defines a real module (`Protocol.For`); ElixirContext supplies its full name.
        if( kind == SymKind::Other ) { return elixirModuleKeyword( target ) || target == "defimpl"; }
        return elixirFunctionKeyword( target ) && nodeTextOf( name, src ) != "unquote" && nodeTextOf( name, src ) != "when";
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
        if( ts_node_is_null( receiver ) || ( std::strcmp( ts_node_type( receiver ), "alias" ) != 0
            && std::strcmp( ts_node_type( receiver ), "atom" ) != 0 && std::strcmp( ts_node_type( receiver ), "dot" ) != 0
            && nodeTextOf( receiver, src ) != "__MODULE__" ) )
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
        if( !ts_node_is_null( head ) && std::strcmp( ts_node_type( head ), "binary_operator" ) == 0 && nodeFieldText( head, "operator", 8, src ) == "when" )
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

// Lexical facts are collected by tags.scm, through the same cursor as every other language.
// The helpers below inspect parents/fields of those captures; they never walk an independent AST.
bool elixirNodeIs( TSNode node, const char* type ) noexcept
{
    return !ts_node_is_null( node ) && std::strcmp( ts_node_type( node ), type ) == 0;
}

bool elixirContains( TSNode outer, TSNode inner ) noexcept
{
    return !ts_node_is_null( outer ) && !ts_node_is_null( inner ) && ts_node_start_byte( outer ) <= ts_node_start_byte( inner )
        && ts_node_end_byte( inner ) <= ts_node_end_byte( outer );
}

TSNode elixirLexicalScope( TSNode node ) noexcept
{
    for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        if( elixirNodeIs( p, "source" ) || elixirNodeIs( p, "do_block" ) || elixirNodeIs( p, "stab_clause" )
            || elixirNodeIs( p, "block" ) || elixirNodeIs( p, "pair" ) || elixirNodeIs( p, "else_block" )
            || elixirNodeIs( p, "rescue_block" ) || elixirNodeIs( p, "catch_block" ) || elixirNodeIs( p, "after_block" ) )
        {
            return p;
        }
    }
    return {};
}

// The do/else/rescue/catch/after arms are siblings inside one grammar do_block, but distinct scopes.
std::uint32_t elixirVisibilityEnd( TSNode scope, std::string_view src ) noexcept
{
    if( ts_node_is_null( scope ) ) { return 0; }
    auto end = ts_node_end_byte( scope );
    TSNode body = scope;
    if( elixirTarget( scope, src ) == "with" )
    {
        body = elixirBody( scope, src );
        const TSNode otherwise = elixirKeywordValue( scope, "else:", src );
        if( !ts_node_is_null( otherwise ) ) { end = ts_node_start_byte( otherwise ); }
    }
    if( elixirNodeIs( body, "do_block" ) )
    {
        for( std::uint32_t i = 0; i < ts_node_named_child_count( body ); ++i )
        {
            const TSNode child = ts_node_named_child( body, i );
            if( elixirNodeIs( child, "else_block" ) || elixirNodeIs( child, "rescue_block" )
                || elixirNodeIs( child, "catch_block" ) || elixirNodeIs( child, "after_block" ) )
            {
                return std::min( end, ts_node_start_byte( child ) );
            }
        }
    }
    return end;
}

bool elixirQuoted( TSNode node, std::string_view src ) noexcept
{
    for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        if( elixirTarget( p, src ) == "quote" ) { return true; }
    }
    return false;
}

std::string elixirFunctionName( std::string_view name, std::uint32_t arity )
{
    return std::string( name ) + "/" + std::to_string( arity );
}

struct ElixirLexicalName
{
    TSNode scope{};
    std::uint32_t startByte = 0;
    std::string target;
    std::uint32_t endByte = 0;
};

struct ElixirContext
{
    std::string_view src;
    std::vector<TSNode> calls;
    std::vector<TSNode> identifiers;
    HashMap<std::string, std::vector<ElixirLexicalName>> aliases;
    HashMap<std::string, std::vector<ElixirLexicalName>> variables;
    HashMap<std::uint32_t, std::string> modules;

    std::string scopeOf( TSNode node, unsigned depth = 0 ) const
    {
        if( depth > 128 ) { DEGRADED_PATH_ALERT( "Elixir module nesting exceeds 128" ); return {}; }
        for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
        {
            if( elixirModuleKeyword( elixirTarget( p, src ) ) || elixirTarget( p, src ) == "defimpl" )
            {
                return moduleName( p, depth + 1 );
            }
        }
        return {};
    }

    std::string expandAlias( std::string written, TSNode site ) const
    {
        if( written.starts_with( "Elixir." ) ) { return written.substr( 7 ); }
        const auto dot = written.find( '.' );
        const std::string first = written.substr( 0, dot );
        const auto found = aliases.find( first );
        if( found != aliases.end() )
        {
            for( auto it = found->second.rbegin(); it != found->second.rend(); ++it )
            {
                if( it->startByte <= ts_node_start_byte( site ) && ts_node_start_byte( site ) < it->endByte && elixirContains( it->scope, site ) )
                {
                    return it->target + ( dot == std::string::npos ? "" : written.substr( dot ) );
                }
            }
        }
        return written;
    }

    std::string moduleOf( TSNode name, TSNode site, unsigned depth = 0 ) const
    {
        if( ts_node_is_null( name ) ) { return {}; }
        if( depth > 128 ) { DEGRADED_PATH_ALERT( "Elixir module nesting exceeds 128" ); return {}; }
        if( elixirNodeIs( name, "alias" ) ) { return expandAlias( std::string( nodeTextOf( name, src ) ), site ); }
        if( elixirNodeIs( name, "atom" ) ) { return std::string( nodeTextOf( name, src ) ); }
        if( nodeTextOf( name, src ) == "__MODULE__" ) { return scopeOf( site, depth + 1 ); }
        if( elixirNodeIs( name, "dot" ) )
        {
            const TSNode left = ts_node_child_by_field_name( name, "left", 4 );
            const TSNode right = ts_node_child_by_field_name( name, "right", 5 );
            if( !elixirNodeIs( right, "alias" ) ) { return {}; }
            const auto prefix = moduleOf( left, site, depth + 1 );
            if( !prefix.empty() ) { return prefix + "." + std::string( nodeTextOf( right, src ) ); }
        }
        return {};
    }

    std::string moduleName( TSNode node, unsigned depth = 0 ) const
    {
        if( depth > 128 ) { DEGRADED_PATH_ALERT( "Elixir module nesting exceeds 128" ); return {}; }
        if( const auto it = modules.find( ts_node_start_byte( node ) ); it != modules.end() ) { return it->second; }
        const auto target = elixirTarget( node, src );
        const TSNode name = elixirFirstArgument( node );
        auto written = moduleOf( name, node, depth + 1 );
        if( written.empty() ) { return {}; }
        if( target == "defimpl" )
        {
            const TSNode forNode = elixirKeywordValue( node, "for:", src );
            const auto forName = ts_node_is_null( forNode ) ? scopeOf( node, depth + 1 ) : moduleOf( forNode, node, depth + 1 );
            if( elixirNodeIs( forNode, "list" ) )
            {
                const auto names = implementationNames( node );
                return names.empty() ? std::string{} : names.front();
            }
            return forName.empty() ? std::string{} : written + "." + forName;
        }
        if( !elixirModuleKeyword( target ) ) { return {}; }
        const auto parent = scopeOf( node, depth + 1 );
        if( elixirNodeIs( name, "alias" ) && !nodeTextOf( name, src ).starts_with( "Elixir." )
            && written == nodeTextOf( name, src ) && !parent.empty() )
        {
            written = parent + "." + written;
        }
        return written;
    }

    std::vector<std::string> implementationNames( TSNode node ) const
    {
        std::vector<std::string> out;
        if( elixirTarget( node, src ) != "defimpl" ) { return out; }
        const auto protocol = moduleOf( elixirFirstArgument( node ), node );
        const TSNode targets = elixirKeywordValue( node, "for:", src );
        if( protocol.empty() || !elixirNodeIs( targets, "list" ) ) { return out; }
        for( std::uint32_t i = 0; i < ts_node_named_child_count( targets ); ++i )
        {
            if( auto target = moduleOf( ts_node_named_child( targets, i ), node ); !target.empty() ) { out.push_back( protocol + "." + target ); }
        }
        std::sort( out.begin(), out.end() );
        out.erase( std::unique( out.begin(), out.end() ), out.end() );
        return out;
    }

    std::vector<std::string> directiveModules( TSNode node ) const
    {
        std::vector<std::string> out;
        const TSNode first = elixirFirstArgument( node );
        if( auto name = moduleOf( first, node ); !name.empty() ) { out.push_back( std::move( name ) ); return out; }
        if( !elixirNodeIs( first, "dot" ) ) { return out; }
        const auto prefix = moduleOf( ts_node_child_by_field_name( first, "left", 4 ), node );
        const TSNode members = ts_node_child_by_field_name( first, "right", 5 );
        if( prefix.empty() || !elixirNodeIs( members, "tuple" ) ) { return out; }
        for( std::uint32_t i = 0; i < ts_node_named_child_count( members ); ++i )
        {
            const TSNode member = ts_node_named_child( members, i );
            if( elixirNodeIs( member, "alias" ) ) { out.push_back( prefix + "." + std::string( nodeTextOf( member, src ) ) ); }
        }
        return out;
    }

    void bindAlias( std::string local, std::string target, TSNode node )
    {
        const TSNode scope = elixirLexicalScope( node );
        aliases[ std::move( local ) ].push_back( { scope, ts_node_start_byte( node ), std::move( target ), elixirVisibilityEnd( scope, src ) } );
    }

    // An identifier is a binding only in a pattern. The innermost matching construct defines
    // visibility: function parameters, clause patterns, matches and comprehension generators.
    TSNode bindingScope( TSNode node ) const
    {
        for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
        {
            if( elixirNodeIs( p, "unary_operator" ) && nodeFieldText( p, "operator", 8, src ) == "^" ) { return {}; }
            if( elixirFunctionKeyword( elixirTarget( p, src ) ) )
            {
                TSNode head = elixirFirstArgument( p );
                if( elixirNodeIs( head, "binary_operator" ) && nodeFieldText( head, "operator", 8, src ) == "when" )
                {
                    head = ts_node_child_by_field_name( head, "left", 4 );
                }
                if( elixirNodeIs( head, "binary_operator" ) || elixirNodeIs( head, "unary_operator" ) ) { return elixirContains( head, node ) ? p : TSNode{}; }
                return elixirContains( elixirArguments( head ), node ) ? p : TSNode{};
            }
            if( elixirNodeIs( p, "stab_clause" ) )
            {
                TSNode pattern = ts_node_child_by_field_name( p, "left", 4 );
                if( elixirNodeIs( pattern, "binary_operator" ) && nodeFieldText( pattern, "operator", 8, src ) == "when" )
                {
                    pattern = ts_node_child_by_field_name( pattern, "left", 4 );
                }
                return elixirContains( pattern, node ) ? p : TSNode{};
            }
            if( elixirNodeIs( p, "binary_operator" ) )
            {
                const auto op = nodeFieldText( p, "operator", 8, src );
                if( op == "=" || op == "<-" || op == "\\\\" )
                {
                    if( !elixirContains( ts_node_child_by_field_name( p, "left", 4 ), node ) ) { return {}; }
                    if( op == "<-" )
                    {
                        for( TSNode c = ts_node_parent( p ); !ts_node_is_null( c ); c = ts_node_parent( c ) )
                        {
                            if( elixirTarget( c, src ) == "for" || elixirTarget( c, src ) == "with" ) { return c; }
                        }
                    }
                    if( op != "\\\\" ) { return elixirLexicalScope( p ); }
                }
            }
        }
        return {};
    }

    bool bareCall( TSNode name ) const
    {
        const auto text = nodeTextOf( name, src );
        if( text.empty() || text.front() == '_' || text == "true" || text == "false" || text == "nil" ) { return false; }
        const TSNode parent = ts_node_parent( name );
        if( elixirNodeIs( parent, "dot" ) || ( elixirNodeIs( parent, "call" )
            && ts_node_eq( ts_node_child_by_field_name( parent, "target", 6 ), name ) ) ) { return false; }
        // A capture names a function even if a variable with the same spelling is bound.
        if( elixirNodeIs( parent, "binary_operator" ) && nodeFieldText( parent, "operator", 8, src ) == "/"
            && elixirNodeIs( ts_node_parent( parent ), "unary_operator" )
            && nodeFieldText( ts_node_parent( parent ), "operator", 8, src ) == "&" ) { return true; }
        if( !ts_node_is_null( bindingScope( name ) ) ) { return false; }
        if( const auto it = variables.find( std::string( text ) ); it != variables.end() )
        {
            for( const auto& variable : it->second )
            {
                if( variable.startByte <= ts_node_start_byte( name ) && ts_node_start_byte( name ) < variable.endByte
                    && elixirContains( variable.scope, name ) ) { return false; }
            }
        }
        return true;
    }

    void prepare( TSQueryCursor* cursor, TSQuery* query, TSNode root, std::string_view bytes,
                  std::uint32_t fileId, std::vector<RawBind>& binds, std::vector<Include>& includes, std::vector<RawRef>& refs )
    {
        src = bytes;
        ts_query_cursor_exec( cursor, query, root );
        TSQueryMatch match;
        while( ts_query_cursor_next_match( cursor, &match ) )
        {
            for( std::uint16_t i = 0; i < match.capture_count; ++i )
            {
                const auto& capture = match.captures[ i ];
                std::uint32_t size = 0;
                const char* name = ts_query_capture_name_for_id( query, capture.index, &size );
                const std::string_view label( name, size );
                if( label == "elixir.context" && !elixirQuoted( capture.node, src ) ) { calls.push_back( capture.node ); }
                if( label == "reference.bare" && !elixirQuoted( capture.node, src ) ) { identifiers.push_back( capture.node ); }
            }
        }
        std::sort( calls.begin(), calls.end(), []( TSNode a, TSNode b ) { return ts_node_start_byte( a ) < ts_node_start_byte( b ); } );
        aliases.reserve( calls.size() / 8 + 1 );
        variables.reserve( identifiers.size() / 2 + 1 );
        modules.reserve( calls.size() / 8 + 1 );
        for( TSNode call : calls )
        {
            const auto keyword = elixirTarget( call, src );
            if( elixirModuleKeyword( keyword ) || keyword == "defimpl" )
            {
                auto full = moduleName( call );
                if( full.empty() ) { continue; }
                modules.emplace( ts_node_start_byte( call ), full );
                if( keyword == "defimpl" )
                {
                    RawRef ref;
                    ref.fileId = fileId; ref.startByte = ts_node_start_byte( call ); ref.line = ts_node_start_point( call ).row + 1;
                    ref.lang = Lang::Elixir; ref.role = RefRole::Extends; ref.isInherit = true;
                    ref.name = moduleOf( elixirFirstArgument( call ), call );
                    refs.push_back( std::move( ref ) );
                }
                if( keyword != "defimpl" )
                {
                    const auto written = nodeTextOf( elixirFirstArgument( call ), src );
                    if( written.find( '.' ) == std::string_view::npos && elixirNodeIs( elixirFirstArgument( call ), "alias" ) )
                    {
                        bindAlias( std::string( written ), full, call );
                    }
                }
                continue;
            }
            const bool behaviour = ( keyword == "behaviour" || keyword == "behavior" )
                                && elixirAttribute( ts_node_parent( call ), src ) == keyword;
            if( keyword != "alias" && keyword != "import" && keyword != "require" && keyword != "use" && !behaviour ) { continue; }
            const auto targets = directiveModules( call );
            for( const std::string& target : targets )
            {
                Include include;
                include.fileId = fileId;
                include.target = target;
                include.byte = ts_node_start_byte( call );
                includes.push_back( std::move( include ) );
                RawRef ref;
                ref.fileId = fileId; ref.startByte = ts_node_start_byte( call ); ref.line = ts_node_start_point( call ).row + 1;
                ref.lang = Lang::Elixir; ref.role = behaviour ? RefRole::Extends : RefRole::Import; ref.isInherit = behaviour;
                ref.name = target;
                refs.push_back( std::move( ref ) );
                const TSNode as = elixirKeywordValue( call, "as:", src );
                if( keyword == "alias" || ( keyword == "require" && !ts_node_is_null( as ) ) )
                {
                    const auto dot = target.rfind( '.' );
                    const auto local = ts_node_is_null( as ) ? target.substr( dot == std::string::npos ? 0 : dot + 1 ) : std::string( nodeTextOf( as, src ) );
                    if( local != "false" ) { bindAlias( local, target, call ); }
                }
                if( keyword != "import" ) { continue; }
                RawBind bind;
                bind.fileId = fileId; bind.lang = Lang::Elixir; bind.kind = LocalBindKind::ElixirImport;
                bind.startByte = ts_node_start_byte( call ); bind.spanStart = ts_node_end_byte( call );
                const TSNode lexical = elixirLexicalScope( call );
                bind.spanEnd = ts_node_is_null( lexical ) ? bind.spanStart : elixirVisibilityEnd( lexical, src );
                bind.typeName = target;
                TSNode filter = elixirKeywordValue( call, "only:", src );
                bind.var = "only";
                if( ts_node_is_null( filter ) ) { filter = elixirKeywordValue( call, "except:", src ); bind.var = ts_node_is_null( filter ) ? "all" : "except"; }
                if( elixirNodeIs( filter, "atom" ) )
                {
                    bind.var = std::string( nodeTextOf( filter, src ).substr( 1 ) );
                }
                else if( elixirNodeIs( filter, "list" ) )
                {
                    for( std::uint32_t i = 0; i < ts_node_named_child_count( filter ); ++i )
                    {
                        const TSNode entries = ts_node_named_child( filter, i );
                        if( !elixirNodeIs( entries, "keywords" ) ) { continue; }
                        for( std::uint32_t j = 0; j < ts_node_named_child_count( entries ); ++j )
                        {
                            const TSNode pair = ts_node_named_child( entries, j );
                            auto key = nodeTextOf( ts_node_child_by_field_name( pair, "key", 3 ), src );
                            while( !key.empty() && ( key.back() == ':' || std::isspace( static_cast<unsigned char>( key.back() ) ) ) ) { key.remove_suffix( 1 ); }
                            const auto count = nodeTextOf( ts_node_child_by_field_name( pair, "value", 5 ), src );
                            bind.importedName += "\n" + std::string( key ) + "/" + std::string( count ) + "\n";
                        }
                    }
                }
                binds.push_back( std::move( bind ) );
            }
        }
        for( TSNode identifier : identifiers )
        {
            const TSNode scope = bindingScope( identifier );
            if( ts_node_is_null( scope ) ) { continue; }
            auto visibleFrom = ts_node_start_byte( identifier );
            for( TSNode p = ts_node_parent( identifier ); !ts_node_is_null( p ) && !ts_node_eq( p, scope ); p = ts_node_parent( p ) )
            {
                const auto op = nodeFieldText( p, "operator", 8, src );
                if( ( op == "=" || op == "<-" ) && elixirContains( ts_node_child_by_field_name( p, "left", 4 ), identifier ) )
                {
                    visibleFrom = ts_node_end_byte( p ); // the RHS runs before the new binding exists
                    break;
                }
            }
            variables[ std::string( nodeTextOf( identifier, src ) ) ].push_back( { scope, visibleFrom, {}, elixirVisibilityEnd( scope, src ) } );
        }
    }
};

// `defimpl P, for: [A, B]` has one written body and two real modules. Duplicate its source
// facts before IDs are assigned; reference attribution below fans its shared spans out likewise.
void elixirExpandImplementations( const ElixirContext& context, std::vector<RawDef>& defs, std::size_t firstDef,
                                 std::vector<RawBind>& binds, std::size_t firstBind )
{
    const auto replacePrefix = []( std::string& text, const std::string& from, const std::string& to )
    {
        if( text == from || ( text.starts_with( from ) && text.size() > from.size() && text[ from.size() ] == '.' ) )
        {
            text.replace( 0, from.size(), to );
        }
    };
    for( TSNode call : context.calls )
    {
        const auto names = context.implementationNames( call );
        if( names.size() < 2 ) { continue; }
        const auto begin = ts_node_start_byte( call ), end = ts_node_end_byte( call );
        const auto defEnd = defs.size(), bindEnd = binds.size();
        for( std::size_t i = 1; i < names.size(); ++i )
        {
            for( std::size_t j = firstDef; j < defEnd; ++j )
            {
                if( defs[j].startByte < begin || defs[j].endByte > end ) { continue; }
                RawDef clone = defs[j];
                replacePrefix( clone.scope, names.front(), names[i] );
                replacePrefix( clone.name, names.front(), names[i] );
                defs.push_back( std::move( clone ) );
            }
            for( std::size_t j = firstBind; j < bindEnd; ++j )
            {
                if( binds[j].startByte < begin || binds[j].startByte >= end || binds[j].kind == LocalBindKind::ElixirImport ) { continue; }
                RawBind clone = binds[j];
                replacePrefix( clone.typeName, names.front(), names[i] );
                binds.push_back( std::move( clone ) );
            }
        }
    }
}

// Explicit call, bare zero-arity call, pipe and &name/arity all use one counting rule.
std::pair<std::uint16_t, bool> elixirCallArity( TSNode role, TSNode name, std::string_view src ) noexcept
{
    TSNode expression = role;
    if( elixirNodeIs( role, "binary_operator" ) && nodeFieldText( role, "operator", 8, src ) == "|>" )
    {
        expression = name;
    }
    const TSNode parent = ts_node_parent( expression );
    if( elixirNodeIs( parent, "binary_operator" ) && nodeFieldText( parent, "operator", 8, src ) == "/"
        && nodeFieldText( ts_node_parent( parent ), "operator", 8, src ) == "&" )
    {
        const auto arity = nodeFieldText( parent, "right", 5, src );
        std::uint16_t count = 0;
        const auto parsed = std::from_chars( arity.data(), arity.data() + arity.size(), count );
        return { count, parsed.ec == std::errc{} && parsed.ptr == arity.data() + arity.size() };
    }
    const TSNode args = elixirArguments( expression );
    std::uint32_t count = 0;
    if( !ts_node_is_null( args ) )
    {
    for( std::uint32_t i = 0; !ts_node_is_null( args ) && i < ts_node_named_child_count( args ); ++i )
        {
            if( !elixirNodeIs( ts_node_named_child( args, i ), "comment" ) ) { ++count; }
        }
    }
    for( std::uint32_t i = 0; i < ts_node_named_child_count( expression ); ++i )
    {
        if( elixirNodeIs( ts_node_named_child( expression, i ), "do_block" ) ) { ++count; }
    }
    if( elixirNodeIs( parent, "binary_operator" ) && nodeFieldText( parent, "operator", 8, src ) == "|>"
        && ts_node_eq( ts_node_child_by_field_name( parent, "right", 5 ), expression ) ) { ++count; }
    return { std::uint16_t( std::min( count, 65535u ) ), count <= 65535u };
}

void elixirDefinitionFacts( const RawDef& def, TSNode node, std::string_view src, std::vector<RawBind>& binds )
{
    const auto keyword = elixirTarget( node, src );
    if( !elixirFunctionKeyword( keyword ) ) { return; }
    RawBind bind;
    bind.fileId = def.fileId; bind.startByte = def.startByte; bind.lang = Lang::Elixir;
    bind.kind = LocalBindKind::ElixirCallable; bind.var = def.name; bind.typeName = def.scope; bind.importedName = keyword;
    bind.spanStart = def.startByte; bind.spanEnd = def.endByte;
    binds.push_back( bind );
    TSNode head = elixirFirstArgument( node );
    if( elixirNodeIs( head, "binary_operator" ) && nodeFieldText( head, "operator", 8, src ) == "when" )
    {
        head = ts_node_child_by_field_name( head, "left", 4 );
    }
    const TSNode args = elixirArguments( head );
    std::uint32_t defaults = 0;
    for( std::uint32_t i = 0; !ts_node_is_null( args ) && i < ts_node_named_child_count( args ); ++i )
    {
        if( nodeFieldText( ts_node_named_child( args, i ), "operator", 8, src ) == "\\\\" ) { ++defaults; }
    }
    const auto name = std::string_view( def.name ).substr( 0, def.name.rfind( '/' ) );
    for( std::uint32_t count = 1; count <= defaults && count <= def.params; ++count )
    {
        bind.kind = LocalBindKind::ElixirDefault;
        bind.var = elixirFunctionName( name, def.params - count );
        bind.importedName = def.name;
        binds.push_back( bind );
    }
}

} // namespace
} // namespace rw
