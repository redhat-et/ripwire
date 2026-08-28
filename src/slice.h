#pragma once

// slice.h — --slice=SYM[:VAR] (lane/paper-slice): the NAME-BASED intra-procedural def-use slice of one
// variable inside ONE uniquely-resolved definition, exposed as a queryable verb.
//
// MOTIVATION. ARISE (arXiv:2605.03117) measured statement-level definition-use edges exposed as a
// queryable agent primitive at +17pp Function Recall@1 on SWE-bench Lite. ripwire's graph stops at
// symbol granularity; this is the bounded v1 of that primitive: one definition, one variable, its
// def/use statement rows in source order.
//
// HONESTY CONTRACT (all three limits are stated in the emitted legend, never implied):
//   • NAME-BASED — occurrences are identifier-name matches inside the definition's span. No alias
//     analysis (a pointer/reference alias is invisible), no flow sensitivity (rows are source-ordered,
//     not dependence-ordered), and a nested scope re-declaring VAR (shadowing) is NOT separated — its
//     rows may over-include.
//   • INTRA-PROCEDURAL ONLY — rows never cross into callees/callers.
//   • SERVED LANGUAGES ONLY — classification is a per-language-family parent-kind read, verified per
//     vendored grammar: C-family (C/C++/ObjC, +CUDA/Metal riding Lang::Cpp), Python, JS/TS, Go, Java,
//     Rust. Every other indexed language REFUSES loudly (exit 1, "not served for LANG yet") — never an
//     empty success, per the "a zero means none found, never none exists" doctrine.
//
// The walk re-parses the ONE file holding the definition with the same statically-linked grammar ingest
// used (sliceGrammarForFile — kLangTable stays the single extension→grammar fact), then classifies
// every `identifier` node inside [sigStartByte, endByte) by its parent node kind + field position.
// Node-kind and field-name strings below are VERIFIED against the vendored parsers (third_party/deps/
// */src/parser.c), not assumed from upstream docs.

#include "model.h"
#include "ingest.h"        // sliceGrammarForFile — path → grammar, ingest's one table
#include "serialize.h"     // escapeXml / appendCdataSafe / symTag / diskPath
#include "redact.h"        // redactInPlace — statement lines are a body-emission seam
#include "gitstamp.h"      // atAttr — the at="<sha>[+dirty]" root anchor, same placement as --edit-check
#include "sarif.h"         // rootPrefixOf / rootRelativeUri — root-relative p=, same as every verb

#include "infra/Diagnostics.h"   // DEGRADED_PATH_ALERT — the three parse-refusal arms are degrades, not asserts

#include <tree_sitter/api.h>

#include <algorithm>
#include <cstdint>
#include <iterator>    // std::size — the kOccTagNames extent
#include <cstring>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
namespace slicev
{

// ── the served language families ─────────────────────────────────────────────────────────────────────

enum class SliceFam : std::uint8_t { C, Py, Js, Go, Java, Rust, None };

inline SliceFam sliceFamilyOf( Lang l ) noexcept
{
    switch( l )
    {
        case Lang::Cpp:                                  // .metal and .cu/.cuh ride Lang::Cpp (kLangTable) —
        case Lang::C:                                    //   the CUDA grammar is a generated cpp superset, so
        case Lang::ObjC:       return SliceFam::C;       //   the C-family kinds below hold for all of them
        case Lang::Python:     return SliceFam::Py;
        case Lang::TypeScript:
        case Lang::JavaScript: return SliceFam::Js;
        case Lang::Go:         return SliceFam::Go;
        case Lang::Java:       return SliceFam::Java;
        case Lang::Rust:       return SliceFam::Rust;
        default:               return SliceFam::None;
    }
}

// the served-set spelling for the unsupported-language refusal — kept beside the switch it restates
inline constexpr const char* kSliceServedList = "c/cpp/objc (+cuda/metal), py, js/ts, go, java, rs";

// ── occurrence classification ────────────────────────────────────────────────────────────────────────

// t= vocabulary, in PRIORITY order (a line holding several occurrence roles reports the smallest value)
enum class OccT : std::uint8_t { Param = 0, Decl = 1, Assign = 2, CallArg = 3, Read = 4 };

// declarative table over a switch (G2's constexpr-table rule — also what keeps this from cloning the
// shapeName/styleTag/statusName switch skeleton QD flagged on the first cut), indexed by the enum value
inline constexpr const char* kOccTagNames[] = { "param", "decl", "assign", "call-arg", "read" };
static_assert( std::size( kOccTagNames ) == std::size_t( OccT::Read ) + 1 );

inline const char* occTag( OccT t ) noexcept
{
    const std::size_t occIndex = std::size_t( t );
    return kOccTagNames[ occIndex < std::size( kOccTagNames ) ? occIndex : std::size( kOccTagNames ) - 1 ];
}

struct SliceOcc
{
    std::uint32_t line  = 0;       // 1-based
    OccT          t     = OccT::Read;
    bool          isDef = false;
    bool          isUse = false;
    bool          skip  = false;   // a non-occurrence (e.g. a Python keyword-argument NAME) — never emitted
};

struct SliceLocal
{
    std::string   name;
    std::uint32_t line = 0;        // first-def line
    OccT          t    = OccT::Decl;
};

struct SliceScan
{
    bool                    parseOk = false;   // grammar present + file parsed + span located
    std::vector<SliceOcc>   occ;               // VAR-mode occurrences, source order (empty when var empty)
    std::vector<SliceLocal> locals;            // the sliceable-locals inventory, first-def order
};

// tree-sitter micro-helpers, in the house spelling
inline bool sliceKindIs( TSNode n, const char* kind ) noexcept
{
    return std::strcmp( ts_node_type( n ), kind ) == 0;
}

inline TSNode sliceField( TSNode p, const char* field ) noexcept
{
    return ts_node_child_by_field_name( p, field, std::uint32_t( std::strlen( field ) ) );
}

// n IS the field child (identity, not containment) — the precise arm: `x = …` defs x, `arr[i] = …` does not def i
inline bool sliceIsField( TSNode p, const char* field, TSNode n ) noexcept
{
    const TSNode c = sliceField( p, field );
    if( ts_node_is_null( c ) )
    {
        return false;
    }
    return ts_node_eq( c, n );
}

// n lies WITHIN the field child's byte span — the containment arm, for pattern-shaped fields (Rust
// `mut x`, Python tuples). ingest.cpp's spanContains is .cpp-private, so the range compare lives inline
// here rather than growing an export for two comparisons.
inline bool sliceInField( TSNode p, const char* field, TSNode n ) noexcept
{
    const TSNode outer = sliceField( p, field );
    if( ts_node_is_null( outer ) )
    {
        return false;
    }
    return ts_node_start_byte( outer ) <= ts_node_start_byte( n ) && ts_node_end_byte( n ) <= ts_node_end_byte( outer );
}

// the assignment operator's own text — "+=", "=", … — read to split a plain write from a read-modify-write
inline bool sliceOperatorIsPlainAssign( TSNode assignNode, std::string_view src ) noexcept
{
    const TSNode op = sliceField( assignNode, "operator" );
    if( ts_node_is_null( op ) )
    {
        return true;   // no operator field captured — treat as plain (a def, not a def+use guess)
    }
    const std::uint32_t a = ts_node_start_byte( op ), b = ts_node_end_byte( op );
    return b > a && b <= src.size() && src.substr( a, b - a ) == "=";
}

// classify ONE identifier node by its parent kind + field position, per family. Every string below is
// grep-verified against the vendored parser.c of each grammar this family serves.
inline SliceOcc sliceClassify( TSNode n, SliceFam fam, std::string_view src ) noexcept
{
    SliceOcc o;
    o.line = ts_node_start_point( n ).row + 1;

    TSNode p = ts_node_parent( n );
    if( ts_node_is_null( p ) )
    {
        o.isUse = true;
        return o;
    }
    const char* pk = ts_node_type( p );

    const auto def  = [ & ]( OccT t ) { o.t = t;  o.isDef = true; };
    const auto use  = [ & ]( OccT t ) { o.t = t;  o.isUse = true; };
    const auto both = [ & ]( OccT t ) { o.t = t;  o.isDef = true;  o.isUse = true; };

    switch( fam )
    {
        case SliceFam::C:
        {
            // climb the declarator wrappers first: `int *x`, `int x[4]`, `int &x`, `auto [a, b]`
            TSNode      d  = n;
            TSNode      pp = p;
            const char* dk = pk;
            while( std::strcmp( dk, "pointer_declarator" ) == 0 || std::strcmp( dk, "array_declarator" ) == 0
                   || std::strcmp( dk, "reference_declarator" ) == 0 || std::strcmp( dk, "parenthesized_declarator" ) == 0
                   || std::strcmp( dk, "structured_binding_declarator" ) == 0 )
            {
                d  = pp;
                pp = ts_node_parent( pp );
                if( ts_node_is_null( pp ) )
                {
                    break;
                }
                dk = ts_node_type( pp );
            }
            if( !ts_node_is_null( pp ) )
            {
                if( std::strcmp( dk, "init_declarator" ) == 0 && sliceInField( pp, "declarator", d ) )
                {
                    def( OccT::Decl );  return o;      // int count = 0;   (the value side falls through to uses)
                }
                if( std::strcmp( dk, "declaration" ) == 0 && !sliceInField( pp, "type", d ) )
                {
                    def( OccT::Decl );  return o;      // int count;
                }
                if( ( std::strcmp( dk, "parameter_declaration" ) == 0 || std::strcmp( dk, "optional_parameter_declaration" ) == 0 )
                    && !sliceInField( pp, "type", d ) && !sliceInField( pp, "default_value", d ) )
                {
                    def( OccT::Param );  return o;     // int limit  — a default value's identifiers stay uses
                }
                if( std::strcmp( dk, "for_range_loop" ) == 0 && sliceInField( pp, "declarator", d ) )
                {
                    def( OccT::Decl );  return o;      // for( auto x : v )
                }
            }
            if( std::strcmp( pk, "assignment_expression" ) == 0 && sliceIsField( p, "left", n ) )
            {
                if( sliceOperatorIsPlainAssign( p, src ) ) { def( OccT::Assign ); } else { both( OccT::Assign ); }
                return o;
            }
            if( std::strcmp( pk, "update_expression" ) == 0 )
            {
                both( OccT::Assign );  return o;       // ++count / count--
            }
            if( std::strcmp( pk, "argument_list" ) == 0 )
            {
                use( OccT::CallArg );  return o;
            }
            break;
        }

        case SliceFam::Py:
        {
            if( std::strcmp( pk, "parameters" ) == 0 )
            {
                def( OccT::Param );  return o;         // def f(n):
            }
            if( std::strcmp( pk, "typed_parameter" ) == 0 && !sliceInField( p, "type", n ) )
            {
                def( OccT::Param );  return o;         // def f(n: int):
            }
            if( ( std::strcmp( pk, "default_parameter" ) == 0 || std::strcmp( pk, "typed_default_parameter" ) == 0 )
                && sliceIsField( p, "name", n ) )
            {
                def( OccT::Param );  return o;         // def f(n=0):  — the default's identifiers stay uses
            }
            if( std::strcmp( pk, "assignment" ) == 0 || std::strcmp( pk, "augmented_assignment" ) == 0 )
            {
                const bool aug = std::strcmp( pk, "augmented_assignment" ) == 0;
                if( sliceIsField( p, "left", n ) )
                {
                    if( aug ) { both( OccT::Assign ); } else { def( OccT::Assign ); }
                    return o;
                }
            }
            if( ( std::strcmp( pk, "pattern_list" ) == 0 || std::strcmp( pk, "tuple_pattern" ) == 0 ) )
            {
                // a, b = …  /  for a, b in …: the list itself sits in the enclosing left/target field
                const TSNode gp = ts_node_parent( p );
                if( !ts_node_is_null( gp )
                    && ( ( sliceKindIs( gp, "assignment" ) && sliceInField( gp, "left", n ) )
                         || ( sliceKindIs( gp, "for_statement" ) && sliceInField( gp, "left", n ) )
                         || ( sliceKindIs( gp, "for_in_clause" ) && sliceInField( gp, "left", n ) ) ) )
                {
                    def( OccT::Decl );  return o;
                }
            }
            if( ( std::strcmp( pk, "for_statement" ) == 0 || std::strcmp( pk, "for_in_clause" ) == 0 ) && sliceInField( p, "left", n ) )
            {
                def( OccT::Decl );  return o;          // for total in …:
            }
            if( std::strcmp( pk, "named_expression" ) == 0 && sliceIsField( p, "name", n ) )
            {
                def( OccT::Assign );  return o;        // (total := …)
            }
            if( std::strcmp( pk, "as_pattern_target" ) == 0 || ( std::strcmp( pk, "as_pattern" ) == 0 && sliceInField( p, "alias", n ) ) )
            {
                def( OccT::Decl );  return o;          // with open(…) as f:
            }
            if( std::strcmp( pk, "keyword_argument" ) == 0 && sliceIsField( p, "name", n ) )
            {
                o.skip = true;  return o;              // f(count=3) — the NAME is the callee's keyword, not this local
            }
            if( std::strcmp( pk, "argument_list" ) == 0 )
            {
                use( OccT::CallArg );  return o;
            }
            break;
        }

        case SliceFam::Js:
        {
            if( std::strcmp( pk, "variable_declarator" ) == 0 && sliceIsField( p, "name", n ) )
            {
                def( OccT::Decl );  return o;          // let count = 0;
            }
            if( std::strcmp( pk, "formal_parameters" ) == 0 )
            {
                def( OccT::Param );  return o;         // function f(count)
            }
            if( ( std::strcmp( pk, "required_parameter" ) == 0 || std::strcmp( pk, "optional_parameter" ) == 0 )
                && sliceInField( p, "pattern", n ) )
            {
                def( OccT::Param );  return o;         // TS: (count: number)
            }
            if( std::strcmp( pk, "assignment_pattern" ) == 0 && sliceIsField( p, "left", n ) )
            {
                // (count = 0) — a parameter default when the pattern sits in a parameter shape, else a
                // destructuring default; both introduce the name
                const TSNode gp = ts_node_parent( p );
                const bool   inParams = !ts_node_is_null( gp )
                                        && ( sliceKindIs( gp, "formal_parameters" ) || sliceKindIs( gp, "required_parameter" ) || sliceKindIs( gp, "optional_parameter" ) );
                def( inParams ? OccT::Param : OccT::Decl );  return o;
            }
            if( std::strcmp( pk, "assignment_expression" ) == 0 && sliceIsField( p, "left", n ) )
            {
                def( OccT::Assign );  return o;
            }
            if( std::strcmp( pk, "augmented_assignment_expression" ) == 0 && sliceIsField( p, "left", n ) )
            {
                both( OccT::Assign );  return o;       // count += n
            }
            if( std::strcmp( pk, "update_expression" ) == 0 )
            {
                both( OccT::Assign );  return o;       // count++
            }
            if( std::strcmp( pk, "for_in_statement" ) == 0 && sliceIsField( p, "left", n ) )
            {
                def( OccT::Decl );  return o;          // for (x of xs) — bare-left form
            }
            if( std::strcmp( pk, "arguments" ) == 0 )
            {
                use( OccT::CallArg );  return o;
            }
            break;
        }

        case SliceFam::Go:
        {
            // Go's assignment left/right sides are expression_lists — hop one level when present
            TSNode      eff      = p;
            TSNode      effChild = n;
            if( std::strcmp( pk, "expression_list" ) == 0 )
            {
                const TSNode gp = ts_node_parent( p );
                if( !ts_node_is_null( gp ) )
                {
                    eff      = gp;
                    effChild = p;
                }
            }
            const char* ek = ts_node_type( eff );
            if( std::strcmp( ek, "short_var_declaration" ) == 0 && sliceIsField( eff, "left", effChild ) )
            {
                def( OccT::Decl );  return o;          // count := 0
            }
            if( std::strcmp( ek, "assignment_statement" ) == 0 && sliceIsField( eff, "left", effChild ) )
            {
                if( sliceOperatorIsPlainAssign( eff, src ) ) { def( OccT::Assign ); } else { both( OccT::Assign ); }
                return o;
            }
            if( std::strcmp( ek, "range_clause" ) == 0 && sliceIsField( eff, "left", effChild ) )
            {
                def( OccT::Decl );  return o;          // for i, v := range xs
            }
            if( std::strcmp( pk, "var_spec" ) == 0 && !sliceInField( p, "type", n ) && !sliceInField( p, "value", n ) )
            {
                def( OccT::Decl );  return o;          // var count int
            }
            if( std::strcmp( pk, "parameter_declaration" ) == 0 && !sliceInField( p, "type", n ) )
            {
                def( OccT::Param );  return o;         // func f(count int)
            }
            if( std::strcmp( pk, "inc_statement" ) == 0 || std::strcmp( pk, "dec_statement" ) == 0 )
            {
                both( OccT::Assign );  return o;       // count++ / count--
            }
            if( std::strcmp( pk, "argument_list" ) == 0 )
            {
                use( OccT::CallArg );  return o;
            }
            break;
        }

        case SliceFam::Java:
        {
            if( std::strcmp( pk, "variable_declarator" ) == 0 && sliceIsField( p, "name", n ) )
            {
                def( OccT::Decl );  return o;          // int count = 0;
            }
            if( std::strcmp( pk, "formal_parameter" ) == 0 && sliceIsField( p, "name", n ) )
            {
                def( OccT::Param );  return o;
            }
            if( std::strcmp( pk, "enhanced_for_statement" ) == 0 && sliceIsField( p, "name", n ) )
            {
                def( OccT::Decl );  return o;          // for (int x : xs)
            }
            if( std::strcmp( pk, "assignment_expression" ) == 0 && sliceIsField( p, "left", n ) )
            {
                if( sliceOperatorIsPlainAssign( p, src ) ) { def( OccT::Assign ); } else { both( OccT::Assign ); }
                return o;
            }
            if( std::strcmp( pk, "update_expression" ) == 0 )
            {
                both( OccT::Assign );  return o;
            }
            if( std::strcmp( pk, "argument_list" ) == 0 )
            {
                use( OccT::CallArg );  return o;
            }
            break;
        }

        case SliceFam::Rust:
        {
            // `let mut count = 0;` — the identifier sits inside the pattern field, possibly under
            // mut_pattern/reference_pattern wrappers, so containment (not identity) is the right arm
            const TSNode gp = ts_node_parent( p );
            if( std::strcmp( pk, "let_declaration" ) == 0 || ( !ts_node_is_null( gp ) && sliceKindIs( gp, "let_declaration" ) ) )
            {
                const TSNode letNode = std::strcmp( pk, "let_declaration" ) == 0 ? p : gp;
                if( sliceInField( letNode, "pattern", n ) )
                {
                    def( OccT::Decl );  return o;
                }
            }
            if( std::strcmp( pk, "parameter" ) == 0 || ( !ts_node_is_null( gp ) && sliceKindIs( gp, "parameter" ) ) )
            {
                const TSNode parNode = std::strcmp( pk, "parameter" ) == 0 ? p : gp;
                if( sliceInField( parNode, "pattern", n ) )
                {
                    def( OccT::Param );  return o;
                }
            }
            if( std::strcmp( pk, "closure_parameters" ) == 0 )
            {
                def( OccT::Param );  return o;         // |count| …
            }
            if( std::strcmp( pk, "for_expression" ) == 0 && sliceInField( p, "pattern", n ) )
            {
                def( OccT::Decl );  return o;          // for x in xs
            }
            if( std::strcmp( pk, "assignment_expression" ) == 0 && sliceIsField( p, "left", n ) )
            {
                def( OccT::Assign );  return o;
            }
            if( std::strcmp( pk, "compound_assignment_expr" ) == 0 && sliceIsField( p, "left", n ) )
            {
                both( OccT::Assign );  return o;       // count += n
            }
            if( std::strcmp( pk, "arguments" ) == 0 )
            {
                use( OccT::CallArg );  return o;
            }
            break;
        }

        case SliceFam::None:
        {
            break;
        }
    }

    o.isUse = true;   // everything unclassified is a plain read — the honest default, never a guessed def
    o.t     = OccT::Read;
    return o;
}

// does this family's inventory admit ASSIGN as a name-introducing def? Only Python (assignment IS the
// declaration there). C/Go/Java/Rust introductions all ride Decl/Param; a bare JS assignment writes an
// OUTER binding, so admitting it would list non-locals.
inline bool sliceAssignIntroduces( SliceFam fam ) noexcept
{
    return fam == SliceFam::Py;
}

// ── the walk ─────────────────────────────────────────────────────────────────────────────────────────

// Recursive descent over the definition's span, collecting classified `identifier` occurrences.
// Depth-bounded only by the AST itself; a definition's subtree is small (one function).
inline void sliceWalk( TSNode node, std::uint32_t spanStart, std::uint32_t spanEnd, SliceFam fam,
                       std::string_view src, std::string_view varName,
                       std::vector<SliceOcc>& occ, std::vector<SliceLocal>& locals, std::string_view selfName )
{
    const std::uint32_t a = ts_node_start_byte( node ), b = ts_node_end_byte( node );
    if( b <= spanStart || a >= spanEnd )
    {
        return;   // disjoint from the definition — prune the subtree
    }

    if( sliceKindIs( node, "identifier" ) && a >= spanStart && b <= spanEnd && b <= src.size() && b > a )
    {
        const std::string_view text = src.substr( a, b - a );
        const SliceOcc         c    = sliceClassify( node, fam, src );
        if( !c.skip )
        {
            if( !varName.empty() && text == varName )
            {
                occ.push_back( c );
            }
            const bool introduces = c.isDef
                                    && ( c.t == OccT::Param || c.t == OccT::Decl || ( c.t == OccT::Assign && sliceAssignIntroduces( fam ) ) );
            if( introduces && text != selfName )
            {
                bool known = false;
                for( const SliceLocal& lv : locals )
                {
                    known = known || ( lv.name == text );
                }
                if( !known )
                {
                    locals.push_back( SliceLocal{ std::string( text ), c.line, c.t } );
                }
            }
        }
        return;   // an identifier is a leaf — nothing beneath it
    }

    const std::uint32_t childCount = ts_node_child_count( node );
    for( std::uint32_t i = 0; i < childCount; ++i )
    {
        sliceWalk( ts_node_child( node, i ), spanStart, spanEnd, fam, src, varName, occ, locals, selfName );
    }
}

// parse + walk. `src` is the WHOLE file (symbol byte offsets are file-absolute). parseOk=false means
// the grammar refused or the span is out of range — the caller refuses loudly, never emits an empty
// success.
inline SliceScan sliceScanDefinition( const std::string& src, const Symbol& sym, SliceFam fam,
                                      const ::TSLanguage* grammar, std::string_view varName )
{
    SliceScan scan;
    if( grammar == nullptr || sym.sigStartByte >= sym.endByte || sym.endByte > src.size() )
    {
        return scan;
    }

    TSParser* parser = ts_parser_new();
    if( parser == nullptr )
    {
        DEGRADED_PATH_ALERT( "slice: ts_parser_new returned null" );
        return scan;
    }
    if( !ts_parser_set_language( parser, grammar ) )
    {
        DEGRADED_PATH_ALERT( "slice: grammar ABI mismatch" );
        ts_parser_delete( parser );
        return scan;
    }
    TSTree* tree = ts_parser_parse_string( parser, nullptr, src.data(), std::uint32_t( src.size() ) );
    if( tree == nullptr )
    {
        DEGRADED_PATH_ALERT( "slice: parse returned null" );
        ts_parser_delete( parser );
        return scan;
    }

    sliceWalk( ts_tree_root_node( tree ), sym.sigStartByte, sym.endByte, fam, src, varName, scan.occ, scan.locals, sym.name );
    scan.parseOk = true;

    ts_tree_delete( tree );
    ts_parser_delete( parser );
    return scan;
}

// ── XML assembly ─────────────────────────────────────────────────────────────────────────────────────

// one aggregated row per LINE touching VAR: k= def|use|both, t= the strongest role (enum order IS the
// priority), CDATA = the trimmed statement line
struct SliceLineRow
{
    std::uint32_t line   = 0;
    bool          hasDef = false;
    bool          hasUse = false;
    OccT          t      = OccT::Read;
};

inline std::string sliceBundleText( const IngestResult& ing, const std::string& root, NodeId focus,
                                    std::string_view varName, const SliceScan& scan, const std::string& src,
                                    RedactCounts* redact )
{
    const Symbol& s = ing.symbols[ focus ];

    // R-E: same single-root root= condition every other verb uses (sarif.h); --slice refuses multi-root
    // before reaching here, so rootPrefix is always live.
    const std::string rootPrefix = rw::sarif::rootPrefixOf( root );
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view v ) -> std::string { return std::string( escapeXml( v, esc ) ); };

    // 1-based line → [start, end) byte range of that line, for the CDATA payloads
    const auto lineSpanOf = [ & ]( std::uint32_t line1 ) -> std::pair<std::size_t, std::size_t>
    {
        std::size_t start = 0;
        std::uint32_t at  = 1;
        while( at < line1 )
        {
            const std::size_t nl = src.find( '\n', start );
            if( nl == std::string::npos )
            {
                return { src.size(), src.size() };
            }
            start = nl + 1;
            ++at;
        }
        std::size_t end = src.find( '\n', start );
        if( end == std::string::npos )
        {
            end = src.size();
        }
        return { start, end };
    };

    std::string out =
        "<!-- ripwire slice: NAME-BASED intra-procedural def-use slice of one variable inside ONE uniquely-resolved definition "
        "(statement-level def-use edges as a queryable agent primitive — the ARISE result, arXiv:2605.03117). LIMITS, stated rather "
        "than implied: occurrences are identifier-name matches inside the definition's span — no alias analysis (a pointer/reference "
        "alias is invisible), no flow sensitivity (rows are source-ordered, not dependence-ordered), and a nested scope re-declaring "
        "VAR (shadowing) is NOT separated, so its rows may over-include. Intra-procedural only: rows never cross into callees/callers "
        "(the callers/callees/uses verbs give the inter-procedural half). One <s> row per LINE touching VAR: k= def|use|both (both = "
        "the line writes AND reads it, e.g. `x += y`), t= the strongest role on the line (param > decl > assign > call-arg > read), "
        "CDATA = the trimmed source line. defs=/uses= count OCCURRENCES, not lines. Bare slice=SYM (no :VAR) lists the sliceable "
        "locals instead (<v n= l= t=/> rows at their first-def line, vars= the count). Languages served: C/C++/ObjC (+CUDA/Metal via "
        "the C-family grammars), Python, JS/TS, Go, Java, Rust — every other language refuses loudly, never an empty success. -->";

    out += "<slice sym=\"";  out += ex( s.name );
    out += "\" p=\"";        out += ex( rw::sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix ) );
    out += ":";              out += std::to_string( s.line );
    out += "\" t=\"";        out += symTag( s.kind );
    out += "\" lang=\"";     out += langTag( s.lang );
    out += "\"";

    if( varName.empty() )
    {
        out += " vars=\"" + std::to_string( scan.locals.size() ) + "\"";
    }
    else
    {
        std::size_t defCount = 0, useCount = 0;
        for( const SliceOcc& o : scan.occ )
        {
            defCount += o.isDef ? 1 : 0;
            useCount += o.isUse ? 1 : 0;
        }
        out += " var=\"" + ex( varName ) + "\" defs=\"" + std::to_string( defCount ) + "\" uses=\"" + std::to_string( useCount ) + "\"";
    }

    // at= then root=, appended after every pre-existing attribute — the --edit-check placement rule
    out += gitstamp::atAttr( root );
    out += " root=\"";  out += ex( root );  out += "\">";

    if( varName.empty() )
    {
        // the inventory. sliceWalk pushes in AST (≈ source) order; sort by (first-def line, name) so the
        // order is a stated contract, not a walk artifact.
        std::vector<SliceLocal> ordered = scan.locals;
        std::sort( ordered.begin(), ordered.end(), []( const SliceLocal& a, const SliceLocal& b )
                   { return a.line != b.line ? a.line < b.line : a.name < b.name; } );
        for( const SliceLocal& lv : ordered )
        {
            out += "<v n=\"" + ex( lv.name ) + "\" l=\"" + std::to_string( lv.line ) + "\" t=\"" + occTag( lv.t ) + "\"/>";
        }
    }
    else
    {
        // aggregate occurrences per line (occ is already line-ascending — the walk is a pre-order pass
        // over one file's AST — so one forward fold suffices)
        std::vector<SliceLineRow> rows;
        for( const SliceOcc& o : scan.occ )
        {
            if( rows.empty() || rows.back().line != o.line )
            {
                rows.push_back( SliceLineRow{ o.line, false, false, OccT::Read } );
            }
            SliceLineRow& r = rows.back();
            r.hasDef = r.hasDef || o.isDef;
            r.hasUse = r.hasUse || o.isUse;
            if( std::uint8_t( o.t ) < std::uint8_t( r.t ) )
            {
                r.t = o.t;   // enum order IS the priority order
            }
        }

        for( const SliceLineRow& r : rows )
        {
            const auto [ lineStart, lineEnd ] = lineSpanOf( r.line );
            std::string text( src, lineStart, lineEnd - lineStart );
            // trim — the row's l= carries the position; leading indentation is dead bytes (G4)
            const std::size_t first = text.find_first_not_of( " \t\r" );
            const std::size_t last  = text.find_last_not_of( " \t\r" );
            text = ( first == std::string::npos ) ? std::string() : text.substr( first, last - first + 1 );
            redactInPlace( text, redact );                      // a body-emission seam — same rule as packOutline

            out += "<s l=\"" + std::to_string( r.line ) + "\" k=\"";
            out += r.hasDef && r.hasUse ? "both" : r.hasDef ? "def" : "use";
            out += "\" t=\"";
            out += occTag( r.t );
            out += "\"><![CDATA[";
            std::string safe;
            safe.reserve( text.size() );
            appendCdataSafe( text, safe );                      // split ]]>, scrub C0 controls + invalid UTF-8
            out += safe;
            out += "]]></s>";
        }
    }

    out += "</slice>";
    return out;
}

}   // namespace slicev
}   // namespace rw
