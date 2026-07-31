// fuzz_ingest.cpp — shared libFuzzer harness for one compile-selected tree-sitter grammar.

#include <tree_sitter/api.h>

#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <vector>

#if !defined( RIPWIRE_FUZZ_LANGUAGE )
#error "RIPWIRE_FUZZ_LANGUAGE must name one linked tree-sitter grammar entry point"
#endif

extern "C" const TSLanguage* RIPWIRE_FUZZ_LANGUAGE( void );

namespace
{

struct ParserState
{
    TSParser* parser = nullptr;

    ParserState()
    {
        parser = ts_parser_new();
        const TSLanguage* language = RIPWIRE_FUZZ_LANGUAGE();
        if( parser == nullptr || language == nullptr || !ts_parser_set_language( parser, language ) )
            std::abort();
    }

    ~ParserState()
    {
        if( parser != nullptr )
            ts_parser_delete( parser );
    }

    ParserState( const ParserState& ) = delete;
    ParserState& operator=( const ParserState& ) = delete;
};

void walkTree( TSNode root )
{
    std::vector<TSNode> stack;
    stack.reserve( 1024 );
    stack.push_back( root );

    while( !stack.empty() )
    {
        const TSNode node = stack.back();
        stack.pop_back();

        const std::uint32_t namedChildCount = ts_node_named_child_count( node );
        for( std::uint32_t namedChildIndex = 0; namedChildIndex < namedChildCount; ++namedChildIndex )
        {
            if( ts_node_is_null( ts_node_named_child( node, namedChildIndex ) ) )
                std::abort();
        }

        const std::uint32_t childCount = ts_node_child_count( node );
        for( std::uint32_t childIndex = childCount; childIndex > 0; --childIndex )
        {
            const TSNode child = ts_node_child( node, childIndex - 1 );
            if( ts_node_is_null( child ) )
                std::abort();
            stack.push_back( child );
        }
    }
}

} // namespace

extern "C" int LLVMFuzzerTestOneInput( const std::uint8_t* data, std::size_t size )
{
    if( size > std::numeric_limits<std::uint32_t>::max() )
        return 0;

    static ParserState state;
    TSTree* tree = ts_parser_parse_string( state.parser, nullptr, reinterpret_cast<const char*>( data ), static_cast<std::uint32_t>( size ) );
    if( tree != nullptr )
    {
        walkTree( ts_tree_root_node( tree ) );
        ts_tree_delete( tree );
    }
    return 0;
}
