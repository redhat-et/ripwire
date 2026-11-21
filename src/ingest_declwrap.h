// ingest_declwrap.h — a section of ingest.cpp: rw::wrappedDeclStart (declared in declwrap.h, which says why it exists).
// It lives here because the extension-to-grammar mapping is ingest's fact (sliceGrammarForFile), and so that serialize.h
// and the edit verbs can ask "where does this declaration start" without a tree-sitter include.
#pragma once

#include "declwrap.h"
#include "infra/hashutil.h"   // fnv1a64 — the one-entry tree memo's content key
#include "infra/nodekind.h"   // kindIs

#include <tree_sitter/api.h>

#include <algorithm>
#include <array>
#include <limits>

namespace rw
{
namespace declwrap_detail
{

// A node of one of these kinds wraps exactly one declaration and starts where that declaration is written from.
// Kind names are per grammar, so a row needs no language: TS/TSX/JS export_statement (and the decorators it carries),
// TS ambient_declaration (`declare function`), Python decorated_definition, C++/CUDA template_declaration, and
// C/C++ linkage_specification — reached as the definition's DIRECT parent only in the one-declaration form
// (`extern "C" int f() {}`; the block form puts a declaration_list between).
inline constexpr std::array<std::string_view, 5> kWrapperParentKinds = { "export_statement", "ambient_declaration", "decorated_definition",
                                                                         "template_declaration", "linkage_specification" };
// An attribute a grammar hangs IN FRONT of the item as a sibling: Rust attribute_item, a TS/JS member's decorator, a
// Dart or GDScript annotation. (Java, Kotlin, C#, Swift and PHP keep theirs inside the declaration node: measured.)
inline constexpr std::array<std::string_view, 3> kLeadingAttributeKinds = { "attribute_item", "decorator", "annotation" };
// What may sit between two attributes of one run, or between the run and its item.
inline constexpr std::array<std::string_view, 4> kCommentKinds = { "line_comment", "block_comment", "comment", "documentation_comment" };

template< std::size_t N >
inline bool kindIn( TSNode n, const std::array<std::string_view, N>& kinds ) noexcept
{
    return std::ranges::contains( kinds, std::string_view( ts_node_type( n ) ) );
}

// Is `p`, the parent of `n`, a wrapper around the one declaration `n`? Every test is on node KINDS, which belong to
// one grammar each, so none asks which language this is (test/langidentitycheck.sh: no per-site language compare).
inline bool wrapsOneDeclaration( TSNode p, TSNode n ) noexcept
{
    if( kindIn( p, kWrapperParentKinds ) )
    {
        return true;
    }
    // Lua `local f = function( a ) … end`: the captured assignment_statement sits in a variable_declaration that adds
    // `local`. The child kind is what tells it from JavaScript's `var` statement, which shares the parent's kind name
    // and holds variable_declarator children.
    if( kindIs( ts_node_type( p ), "variable_declaration" ) && kindIs( ts_node_type( n ), "assignment_statement" ) )
    {
        return true;
    }
    // Ruby `private def f` / `memoize def f`: a receiverless call whose paren-less argument list IS the definition
    // (the list starts where the def does, which is how `n` came to be it). `foo( def f … )` has a list that starts at
    // its paren, so it never reaches here; no other grammar here has a paren-less argument_list.
    if( kindIs( ts_node_type( p ), "call" ) && kindIs( ts_node_type( n ), "argument_list" ) )
    {
        return ts_node_named_child_count( n ) == 1 && ts_node_is_null( ts_node_child_by_field_name( p, "receiver", 8 ) )
            && ts_node_is_null( ts_node_child_by_field_name( p, "block", 5 ) );
    }
    return false;
}

// One parsed file, kept until the next call asks about another: a body verb serves several definitions of one file
// back to back, and each would otherwise re-parse it. Keyed by grammar and content (length + FNV-1a), never by pointer.
struct ParsedMemo
{
    const ::TSLanguage* grammar = nullptr;
    std::size_t         size    = 0;
    std::uint64_t       hash    = 0;
    TreeGuard           tree;   // the house owner (ingest_sidecap.h): freed when the memo is replaced, and at thread exit

    ParsedMemo() = default;
    ParsedMemo( const ParsedMemo& )            = delete;
    ParsedMemo& operator=( const ParsedMemo& ) = delete;

    // The tree of `src` under `g`, or nullptr when the parse gave none.
    const TSTree* treeOf( const ::TSLanguage* g, std::string_view src )
    {
        const std::uint64_t contentHash = hashutil::fnv1a64( src );
        if( tree.get() != nullptr && grammar == g && size == src.size() && hash == contentHash )
        {
            return tree.get();
        }
        tree = TreeGuard{};   // the old tree goes BEFORE the new parse, so two are never alive at once
        ParserGuard pg;
        ASSUME( pg.p != nullptr, "ts_parser_new: the default tree-sitter allocator aborts on failure" );
        if( ts_parser_set_language( pg.p, g ) )
        {
            tree = TreeGuard( parseTree( pg.p, src ) );
        }
        grammar = g;
        size    = src.size();
        hash    = contentHash;
        return tree.get();
    }
};

// The definition: the LARGEST node that starts at defStart and ends inside the symbol's span (a symbol whose body is a
// sibling of its signature ends past its own node). A null node when no node starts there: this parse is not the one
// the symbol came from, and nothing is claimed.
inline TSNode definitionNodeAt( const TSTree* tree, std::uint32_t defStart, std::uint32_t defEnd ) noexcept
{
    TSNode n = ts_node_descendant_for_byte_range( ts_tree_root_node( tree ), defStart, defStart + 1 );
    if( ts_node_is_null( n ) || ts_node_start_byte( n ) != defStart )
    {
        return TSNode{};
    }
    for( TSNode p = ts_node_parent( n ); !ts_node_is_null( p ) && ts_node_start_byte( p ) == defStart && ts_node_end_byte( p ) <= defEnd; p = ts_node_parent( n ) )
    {
        n = p;
    }
    return n;
}

// Up through the wrappers of `n`. A parent with the very same span (a one-statement block, a paren-less argument list)
// is the same text and is stepped through; anything else that is not a wrapper ends the climb.
inline TSNode outermostWrapper( TSNode n ) noexcept
{
    for( TSNode p = ts_node_parent( n ); !ts_node_is_null( p ); p = ts_node_parent( n ) )
    {
        const bool sameSpan = ts_node_start_byte( p ) == ts_node_start_byte( n ) && ts_node_end_byte( p ) == ts_node_end_byte( n );
        if( !sameSpan && !wrapsOneDeclaration( p, n ) )
        {
            break;
        }
        n = p;
    }
    return n;
}

// The attribute run in front of `n`: back over attributes and comments, to the TOPMOST attribute (a comment above the
// run is not part of the declaration; one inside the run is). n's own start when no attribute precedes it.
inline std::uint32_t attributeRunStart( TSNode n ) noexcept
{
    std::uint32_t start = ts_node_start_byte( n );
    for( TSNode prev = ts_node_prev_sibling( n ); !ts_node_is_null( prev ) && ( kindIn( prev, kLeadingAttributeKinds ) || kindIn( prev, kCommentKinds ) );
         prev = ts_node_prev_sibling( prev ) )
    {
        if( kindIn( prev, kLeadingAttributeKinds ) )
        {
            start = ts_node_start_byte( prev );
        }
    }
    return start;
}

}   // namespace declwrap_detail

std::uint32_t wrappedDeclStart( std::string_view path, std::string_view src, std::uint32_t defStart, std::uint32_t defEnd )
{
    using namespace declwrap_detail;
    const ::TSLanguage* grammar = sliceGrammarForFile( path );
    if( grammar == nullptr || defStart >= defEnd || defEnd > src.size() || src.size() > std::numeric_limits<std::uint32_t>::max() )
    {
        return defStart;
    }
    thread_local ParsedMemo memo;
    const TSTree*           tree = memo.treeOf( grammar, src );
    const TSNode            def  = tree != nullptr ? definitionNodeAt( tree, defStart, defEnd ) : TSNode{};
    if( ts_node_is_null( def ) )
    {
        return defStart;
    }
    return std::min( attributeRunStart( outermostWrapper( def ) ), defStart );
}

}   // namespace rw — ingest_declwrap.h section of ingest.cpp
