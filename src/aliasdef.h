#pragma once
// aliasdef.h — INDEX-ALIAS-CONST: the ONE reader of "this declaration is another name for that target".
//
// A C++ `using X = Y;` / `namespace L = lib;` / function-type or pointer typedef, and a TypeScript module-level
// `const X = <alias- or table-shaped value>`, become definitions whose TARGET is the written text the parser hands
// back. Every site that needs the alias's target reads it here: the tags pass (ingest_sidecap.h captureTagsFacts:
// which captures to keep, and where the target starts — model.h AliasTarget, one 8-byte row per alias def), and the
// printer that shows it (--defs to=, defslookup.h aliasTargetText). The three older C/C++ alias readers (ingest_binds.h fnPtrAliasName,
// ingest_relations.h aliasSpecifierAndName, ingest_sidecap.h's typedef-name mention filter) keep their own walks
// for now; aliasShapeOf is the shape they can adopt (reports/index-alias-const.md, adoption plan).
//
// LANGUAGE LAYER (explicit, one arm per language): C++ reads node kinds the grammar fixes (alias_declaration's
// `type` field, namespace_alias_definition's last named child, type_definition's `type` field). TypeScript reads
// the variable_declarator's `value` field against an ALLOWLIST of right-hand-side shapes (SAFETY (d)(1)): every
// other module-level const is counted (consts_skipped=, --health) and never indexed, never as a function.
//
// TS RIGHT-HAND-SIDE ALLOWLIST (general shapes, written before any target row was read against it):
//   alias  an identifier `Y`; a member chain `a.b.c` (identifiers and property names only, no call, no index);
//          `require('m')` / `import('m')` with one string literal argument
//   table  a NON-EMPTY object literal `{ k: v, … }`; a NON-EMPTY array literal `[ a, b, … ]`
//   both may be wrapped in `( … )`, `… as const` / `… as T`, `… satisfies T` or a non-null `…!` (depth-bounded)
// NOT kept (counted): a call (`f()`), `new X()`, a string/number/template literal, an empty `{}` / `[]` (an
// accumulator, not a table), a conditional, a binary expression; and every const in a minified-suspect file.

#include "infra/fieldid.h"
#include "infra/nodekind.h"
#include "model.h"

#include <tree_sitter/api.h>

#include <cstdint>
#include <string_view>

namespace rw
{

enum class AliasForm : std::uint8_t
{
    None,            // not an alias or table
    TypeAlias,       // C++ `using X = Y;` and its template / class-scope forms, a function-type or pointer typedef
    NamespaceAlias,  // C++ `namespace L = lib;`
    ValueAlias,      // TS `const X = Y` / `= a.b` / `= require('m')`
    Table,           // TS `const X = { … }` / `[ … ]`
};

struct AliasShape
{
    AliasForm form   = AliasForm::None;
    TSNode    target {};   // the written target; null when form == None
};

// Wrapper unwrapping is bounded: a `((x as A) as B)!` chain deeper than this is not an alias shape anyone writes.
inline constexpr int kAliasUnwrapDepth = 6;

namespace aliasdef_detail
{
inline TSNode lastNamedChild( TSNode n ) noexcept
{
    const std::uint32_t c = ts_node_named_child_count( n );
    return c == 0 ? TSNode{} : ts_node_named_child( n, c - 1 );
}

inline bool isMemberChain( TSNode n ) noexcept
{
    for( int depth = 0; depth < 64; ++depth )
    {
        const char* t = ts_node_type( n );
        if( kindIs( t, "identifier" ) )
        {
            return true;
        }
        if( !kindIs( t, "member_expression" ) )
        {
            return false;
        }
        n = fieldChild( n, NodeField::Object );
        if( ts_node_is_null( n ) )
        {
            return false;
        }
    }
    return false;   // a 64-segment chain: not an alias anyone writes
}

inline bool isStringLiteralNode( TSNode n ) noexcept
{
    const char* t = ts_node_type( n );
    return kindIs( t, "string" ) || ( kindIs( t, "template_string" ) && ts_node_named_child_count( n ) == 0 );
}

// `require('m')` / `import('m')`: exactly one string-literal argument
inline bool isModuleLoadOfLiteral( TSNode call ) noexcept
{
    const TSNode fn   = fieldChild( call, NodeField::Function );
    const TSNode args = fieldChild( call, NodeField::Arguments );
    if( ts_node_is_null( fn ) || ts_node_is_null( args ) || ts_node_named_child_count( args ) != 1 )
    {
        return false;
    }
    const char* ft = ts_node_type( fn );
    const bool  loader = kindIs( ft, "import" ) || ( kindIs( ft, "identifier" ) && ts_node_end_byte( fn ) - ts_node_start_byte( fn ) == 7 );
    return loader && isStringLiteralNode( ts_node_named_child( args, 0 ) );
}
}   // namespace aliasdef_detail

// The TS value classification. `src` is needed only to tell `require` from another 7-letter callee.
inline AliasShape tsValueShape( TSNode value, std::string_view src ) noexcept
{
    for( int depth = 0; depth < kAliasUnwrapDepth && !ts_node_is_null( value ); ++depth )
    {
        const char* t = ts_node_type( value );
        if( kindIs( t, "parenthesized_expression" ) || kindIs( t, "as_expression" ) || kindIs( t, "satisfies_expression" ) || kindIs( t, "non_null_expression" ) )
        {
            value = ts_node_named_child( value, 0 );   // the expression; the type operand is the later child
            continue;
        }
        if( kindIs( t, "identifier" ) || ( kindIs( t, "member_expression" ) && aliasdef_detail::isMemberChain( value ) ) )
        {
            return { AliasForm::ValueAlias, value };
        }
        if( kindIs( t, "call_expression" ) && aliasdef_detail::isModuleLoadOfLiteral( value ) )
        {
            const TSNode fn = fieldChild( value, NodeField::Function );
            if( kindIs( ts_node_type( fn ), "import" ) || src.substr( ts_node_start_byte( fn ), 7 ) == "require" )
            {
                return { AliasForm::ValueAlias, value };
            }
            return {};
        }
        if( ( kindIs( t, "object" ) || kindIs( t, "array" ) ) && ts_node_named_child_count( value ) > 0 )
        {
            return { AliasForm::Table, value };
        }
        return {};
    }
    return {};
}

// A TS const whose value another tags pattern already indexes (queries/typescript/tags.scm): `= ( … ) => …` and `= function …` are
// function definitions, wrapped in a cast too; `= class …` is a class. Such a const is never "skipped" (consts_skipped= counts
// only consts no pattern indexes).
inline bool tsConstValueIndexedElsewhere( TSNode declarator ) noexcept
{
    TSNode v = fieldChild( declarator, NodeField::Value );
    for( int depth = 0; depth < kAliasUnwrapDepth && !ts_node_is_null( v ); ++depth )
    {
        const char* t = ts_node_type( v );
        if( kindIs( t, "arrow_function" ) || kindIs( t, "function_expression" ) || kindIs( t, "function" ) || kindIs( t, "class" ) )
        {
            return true;
        }
        if( !( kindIs( t, "parenthesized_expression" ) || kindIs( t, "as_expression" ) || kindIs( t, "satisfies_expression" ) ) )
        {
            return false;
        }
        v = ts_node_named_child( v, 0 );
    }
    return false;
}

// The shape of the declaration node a definition capture's role node names (C++), or of a TS variable_declarator.
inline AliasShape aliasShapeOf( Lang lang, TSNode decl, std::string_view src ) noexcept
{
    if( ts_node_is_null( decl ) )
    {
        return {};
    }
    const char* t = ts_node_type( decl );
    if( lang == Lang::Cpp )
    {
        if( kindIs( t, "alias_declaration" ) || kindIs( t, "type_definition" ) )
        {
            const TSNode ty = fieldChild( decl, NodeField::Type );
            return ts_node_is_null( ty ) ? AliasShape{} : AliasShape{ AliasForm::TypeAlias, ty };
        }
        if( kindIs( t, "namespace_alias_definition" ) )
        {
            const TSNode target = aliasdef_detail::lastNamedChild( decl );
            return ts_node_is_null( target ) ? AliasShape{} : AliasShape{ AliasForm::NamespaceAlias, target };
        }
        return {};
    }
    if( lang == Lang::TypeScript && kindIs( t, "variable_declarator" ) )
    {
        return tsValueShape( fieldChild( decl, NodeField::Value ), src );
    }
    return {};
}

// A C++ alias written inside a function body or lambda is a local name, not a definition (the local-const rule).
inline bool cppAliasIsFunctionLocal( TSNode n ) noexcept
{
    int depth = 0;
    for( TSNode p = ts_node_parent( n ); !ts_node_is_null( p ); p = ts_node_parent( p ), ++depth )
    {
        const char* pt = ts_node_type( p );
        if( depth >= 256 || kindIs( pt, "compound_statement" ) || kindIs( pt, "lambda_expression" ) )
        {
            return true;   // past the cap the enclosure is unknown: not indexed (a floor, never a false def)
        }
    }
    return false;
}

// The minified-suspect rule the --health report uses (verbs_report.h: ingest.h kHealthWsSampleBytes / kMinifiedWsPerMille
// / kMinifiedMinBytes over ingest_crawl.h's whitespace set), applied to a TS file once before its consts are classified: a
// bundle's `const a=b.c` is not an alias anyone named. Byte-wise (a multi-byte sequence is never whitespace either way).
inline bool aliasSourceLooksMinified( std::string_view src, std::size_t sampleBytes, std::size_t minBytes, std::uint32_t wsPerMille ) noexcept
{
    if( src.size() < minBytes )
    {
        return false;
    }
    const std::size_t n  = src.size() < sampleBytes ? src.size() : sampleBytes;
    std::uint64_t     ws = 0;
    for( std::size_t i = 0; i < n; ++i )
    {
        const char c = src[ i ];
        ws += ( c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v' ) ? 1u : 0u;
    }
    return n > 0 && ws * 1000u < std::uint64_t( n ) * wsPerMille;
}

}   // namespace rw
