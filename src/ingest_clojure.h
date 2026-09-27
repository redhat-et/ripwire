#pragma once

#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_clojure.h is a section of ingest.cpp; include it only there"
#endif

namespace rw
{
namespace
{

struct ClojureDefinitionShape
{
    bool    matches = false;
    SymKind kind    = SymKind::Other;
};

std::string_view clojureListHead( TSNode list, std::string_view src ) noexcept
{
    if( ts_node_is_null( list ) || std::strcmp( ts_node_type( list ), "list_lit" ) != 0 )
    {
        return {};
    }
    const std::uint32_t childCount = ts_node_named_child_count( list );
    std::uint32_t       headIndex  = 0;
    while( headIndex < childCount && kindIs( ts_node_type( ts_node_named_child( list, headIndex ) ), "comment" ) )
    {
        ++headIndex;
    }
    if( headIndex == childCount )
    {
        return {};
    }
    const TSNode head = ts_node_named_child( list, headIndex );
    return kindIs( ts_node_type( head ), "sym_lit" ) ? nodeTextOf( head, src ) : std::string_view{};
}

ClojureDefinitionShape clojureDefinitionShape( TSNode list, std::string_view src ) noexcept
{
    const std::string_view head = clojureListHead( list, src );
    if( head == "ns" )                                     { return { true, SymKind::Other }; }
    if( head == "def" || head == "defonce" )              { return { true, SymKind::Var }; }
    if( head == "defn" || head == "defn-" || head == "defmulti" || head == "defmethod" )
    {
        return { true, SymKind::Function };
    }
    if( head == "defmacro" )                               { return { true, SymKind::Macro }; }
    if( head == "defprotocol" || head == "definterface" ) { return { true, SymKind::Interface }; }
    if( head == "defrecord" || head == "deftype" )        { return { true, SymKind::Class }; }
    return {};
}

bool clojureQuotedOrDiscarded( TSNode node ) noexcept
{
    for( TSNode parent = ts_node_parent( node ); !ts_node_is_null( parent ); parent = ts_node_parent( parent ) )
    {
        const char* type = ts_node_type( parent );
        if( kindIs( type, "quoting_lit" ) || kindIs( type, "syn_quoting_lit" ) || kindIs( type, "dis_expr" ) )
        {
            return true;
        }
    }
    return false;
}

bool clojureDeclarationMethod( TSNode list, std::string_view src ) noexcept
{
    const TSNode parent = ts_node_parent( list );
    if( ts_node_is_null( parent ) || std::strcmp( ts_node_type( parent ), "list_lit" ) != 0 )
    {
        return false;
    }
    const std::string_view owner = clojureListHead( parent, src );
    return owner == "defprotocol" || owner == "definterface" || owner == "defrecord" || owner == "deftype";
}

bool clojureKeepCapture( TSNode role, bool isDef, std::string_view src ) noexcept
{
    if( clojureQuotedOrDiscarded( role ) )
    {
        return false;
    }
    const ClojureDefinitionShape definition = clojureDefinitionShape( role, src );
    if( isDef )
    {
        return definition.matches;
    }
    if( definition.matches || clojureDeclarationMethod( role, src ) )
    {
        return false;
    }
    constexpr std::string_view specialForms[] = {
        "if", "if-not", "when", "when-not", "cond", "case", "do", "let", "letfn", "loop", "recur",
        "fn", "fn*", "quote", "var", "set!", "new", ".", "throw", "try", "catch", "finally", "monitor-enter",
        "monitor-exit", "locking", "binding", "with-open", "doseq", "for", "dotimes", "doto", "->", "->>", "as->",
        "some->", "some->>", "cond->", "cond->>", "and", "or"
    };
    const std::string_view head = clojureListHead( role, src );
    return !head.empty() && std::find( std::begin( specialForms ), std::end( specialForms ), head ) == std::end( specialForms );
}

std::uint16_t clojureParams( TSNode definition, std::string_view src ) noexcept
{
    TSNode params {};
    for( std::uint32_t i = 0; i < ts_node_named_child_count( definition ); ++i )
    {
        const TSNode child = ts_node_named_child( definition, i );
        if( std::strcmp( ts_node_type( child ), "vec_lit" ) == 0 )
        {
            params = child;
            break;
        }
    }
    std::uint32_t count = 0;
    for( std::uint32_t i = 0; !ts_node_is_null( params ) && i < ts_node_named_child_count( params ); ++i )
    {
        const TSNode child = ts_node_named_child( params, i );
        if( std::strcmp( ts_node_type( child ), "comment" ) != 0 && nodeTextOf( child, src ) != "&" )
        {
            ++count;
        }
    }
    return std::uint16_t( std::min( count, std::uint32_t( 65535 ) ) );
}

} // namespace
} // namespace rw
