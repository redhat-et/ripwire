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
    if( ts_node_is_null( list ) )
    {
        return {};
    }
    // An anonymous function literal `#(f %)` reads as `(fn* [x] (f x))`, so its head is a call head too (#548 arm 2).
    const char* listKind = ts_node_type( list );
    if( !kindIs( listKind, "list_lit" ) && !kindIs( listKind, "anon_fn_lit" ) )
    {
        return {};
    }
    // The head is the first named child that is not a comment, a `#_` discard or reader metadata (`^:tag`, `^{…}`):
    // the same leading slot queries/clojure/tags.scm's call pattern skips.
    const std::uint32_t childCount = ts_node_named_child_count( list );
    for( std::uint32_t childIndex = 0; childIndex < childCount; ++childIndex )
    {
        const TSNode child = ts_node_named_child( list, childIndex );
        const char*  kind  = ts_node_type( child );
        if( kindIs( kind, "comment" ) || kindIs( kind, "dis_expr" ) || kindIs( kind, "meta_lit" ) )
        {
            continue;
        }
        return kindIs( kind, "sym_lit" ) ? nodeTextOf( child, src ) : std::string_view{};
    }
    return {};
}

// Temporary keyword-head table: CONTRIBUTING slice 5a moves these decisions into tags-pass predicates.
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

bool clojureDeclarationMethod( TSNode list, std::string_view src ) noexcept
{
    const TSNode parent = parentOf( list );
    if( ts_node_is_null( parent ) || std::strcmp( ts_node_type( parent ), "list_lit" ) != 0 )
    {
        return false;
    }
    const std::string_view owner = clojureListHead( parent, src );
    return owner == "defprotocol" || owner == "definterface" || owner == "defrecord" || owner == "deftype";
}

bool clojureKeepCapture( TSNode role, bool isDef, std::string_view src ) noexcept
{
    if( inInertRegion( role, [ & ]( TSNode ancestor, TSNode )
    {
        const char* type = ts_node_type( ancestor );
        if( kindIs( type, "quoting_lit" ) || kindIs( type, "syn_quoting_lit" ) || kindIs( type, "dis_expr" )
            || ( kindIs( type, "list_lit" ) && clojureListHead( ancestor, src ) == "comment" ) )
        {
            return InertBoundary::Inert;
        }
        return InertBoundary::None;
    } ) )
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
    // Temporary keyword-head exclusions: CONTRIBUTING slice 5a moves this table into tags-pass predicates.
    constexpr std::string_view specialForms[] = {
        "if", "if-not", "when", "when-not", "cond", "case", "do", "let", "letfn", "loop", "recur",
        "fn", "fn*", "quote", "var", "set!", "new", ".", "throw", "try", "catch", "finally", "monitor-enter",
        "monitor-exit", "locking", "binding", "with-open", "doseq", "for", "dotimes", "doto", "->", "->>", "as->",
        "some->", "some->>", "cond->", "cond->>", "and", "or", "comment"
    };
    const std::string_view head = clojureListHead( role, src );
    return !head.empty() && std::find( std::begin( specialForms ), std::end( specialForms ), head ) == std::end( specialForms );
}

std::uint16_t clojureParams( TSNode definition, std::string_view src ) noexcept
{
    TSNode params {};
    const bool isDefmethod = clojureListHead( definition, src ) == "defmethod";
    std::uint32_t formIndex = 0;
    for( std::uint32_t i = 0; i < ts_node_named_child_count( definition ); ++i )
    {
        const TSNode child = ts_node_named_child( definition, i );
        if( kindIs( ts_node_type( child ), "comment" ) || kindIs( ts_node_type( child ), "dis_expr" ) )
        {
            continue;
        }
        if( isDefmethod && formIndex++ < 3 )
        {
            continue;
        }
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
