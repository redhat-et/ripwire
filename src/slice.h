#pragma once

// slice.h — --slice=SYM[:VAR] (lane/paper-slice): the NAME-BASED intra-procedural def-use slice of one
// variable inside ONE uniquely-resolved definition, exposed as a queryable verb.
//
// MOTIVATION. ARISE (arXiv:2605.03117) measured statement-level definition-use edges exposed as a
// queryable agent primitive at +17pp Function Recall@1 on SWE-bench Lite. ripwire's graph stops at
// symbol granularity; this is the bounded v1 of that primitive: one definition, one variable, its
// def/use statement rows in source order.
//
// HONESTY CONTRACT (all four limits are stated in the emitted legend, never implied):
//   • NAME-BASED — occurrences are identifier-name matches inside the definition's span. No alias
//     analysis (a pointer/reference alias is invisible), no flow sensitivity (rows are source-ordered,
//     not dependence-ordered), and a nested scope re-declaring VAR (shadowing) is NOT separated — its
//     rows may over-include.
//   • RECEIVER MUTATION IS NOT A DEF — a write a callee performs through the variable (`v.push_back(x)`,
//     `buf.append(s)`) classifies as a READ, because proving it writes needs the receiver's TYPE and the
//     callee's BODY, and this slicer has neither. Registered as a DECISION, not an oversight, and
//     measured before it was registered (2026-08-31, docs/EVALS.md "Receiver mutation as a slice
//     definition"): across ripwire's own src/ and ugrep @550599a6, 79.1% of receiver call sites on
//     these variables are not mutations at all, and of the ones that are, `reserve` (capacity, never
//     value) and `clear`/`pop_back` (no incoming value) dominate — so a curated method-name rule would
//     mint far more false defs than true ones. A false def is strictly worse than an absent one here:
//     sliceFlowExpandFwd breaks on the next def, so a fabricated def SUPPRESSES the reach of the real
//     def before it. The cost is paid in the legend instead, and defs=/steps= carry counts_floor="1".
//   • INTRA-PROCEDURAL ONLY — rows never cross into callees/callers.
//   • SERVED LANGUAGES ONLY — classification is a per-language-family parent-kind read, verified per
//     vendored grammar: C-family (C/C++/ObjC, +CUDA/Metal riding Lang::Cpp), Python, JS/TS, Go, Java,
//     Rust. Every other indexed language REFUSES loudly (exit 1, "not served for LANG yet") — never an
//     empty success, per the "a zero means none found, never none exists" doctrine.
//
// The walk re-parses the ONE file holding the definition with the same statically-linked grammar ingest
// used (sliceGrammarForFile — kLangTable stays the single extension→grammar fact), then classifies
// every `identifier` node inside [sigStartByte, endByte) by its parent node kind + field position
// (plus, C-family only, the `type_identifier` arguments of a most-vexing-parse direct initialization).
// Node-kind and field-name strings below are VERIFIED against the vendored parsers (third_party/deps/
// */src/parser.c), not assumed from upstream docs.

#include "model.h"
#include "ingest.h"        // sliceGrammarForFile — path → grammar, ingest's one table
#include "serialize.h"     // escapeXml / appendCdataSafe / symTag / diskPath
#include "redact.h"        // redactInPlace — statement lines are a body-emission seam
#include "gitstamp.h"      // atAttr — the at="<sha>[+dirty]" root anchor, same placement as --edit-check
#include "graphlegend.h"   // kGraphCountFloorAttrXml — ONE spelling of the floor marker, tree-wide
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

// ── reserved-word exclusion ──────────────────────────────────────────────────────────────────────────
//
// A keyword can reach the walk as an `identifier` node only through a MISPARSE: tree-sitter lexes
// keywords as their own token kinds, so an identifier whose text is a reserved word of the file's own
// language is an error-recovery artifact of a degraded region (seen in the wild on ugrep's
// lib/matcher.cpp: a preprocessor guard swallows the `if`, and recovery reads the orphaned
// `else if( … )` as a declaration whose declarator is `if`). Such an occurrence is dropped from the
// walk entirely — the inventory, the VAR rows, and the flow substrate — because a keyword is never a
// variable; --slice=SYM:if then refuses like any unknown VAR, never an empty success.
//
// Tables are per-LANGUAGE, not per-family, so the check never rejects a legal identifier: `class` is
// a valid C identifier, so the C++ list must not apply to Lang::C. Contextual/soft keywords that
// remain legal identifiers stay OFF the lists on purpose (Python `match`/`type`, TS `type`/
// `interface`, Java `var`/`record`/`yield`, Rust `union`, JS `let`/`async`).

inline constexpr std::string_view kSliceCReserved[] = {
    "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline",
    "int", "long", "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void",
    "volatile", "while" };

inline constexpr std::string_view kSliceCppReserved[] = {
    "alignas", "alignof", "and", "and_eq", "asm", "auto", "bitand", "bitor", "bool", "break", "case", "catch", "char", "char16_t", "char32_t",
    "char8_t", "class", "co_await", "co_return", "co_yield", "compl", "concept", "const", "const_cast", "consteval", "constexpr", "constinit",
    "continue", "decltype", "default", "delete", "do", "double", "dynamic_cast", "else", "enum", "explicit", "export", "extern", "false", "float",
    "for", "friend", "goto", "if", "inline", "int", "long", "mutable", "namespace", "new", "noexcept", "not", "not_eq", "nullptr", "operator", "or",
    "or_eq", "private", "protected", "public", "register", "reinterpret_cast", "requires", "return", "short", "signed", "sizeof", "static",
    "static_assert", "static_cast", "struct", "switch", "template", "this", "thread_local", "throw", "true", "try", "typedef", "typeid", "typename",
    "union", "unsigned", "using", "virtual", "void", "volatile", "wchar_t", "while", "xor", "xor_eq" };

inline constexpr std::string_view kSlicePyReserved[] = {
    "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except",
    "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while",
    "with", "yield" };

inline constexpr std::string_view kSliceJsReserved[] = {
    "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "false",
    "finally", "for", "function", "if", "import", "in", "instanceof", "new", "null", "return", "super", "switch", "this", "throw", "true", "try",
    "typeof", "var", "void", "while", "with" };

inline constexpr std::string_view kSliceGoReserved[] = {
    "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import",
    "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var" };

inline constexpr std::string_view kSliceJavaReserved[] = {
    "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const", "continue", "default", "do", "double", "else",
    "enum", "extends", "false", "final", "finally", "float", "for", "goto", "if", "implements", "import", "instanceof", "int", "interface", "long",
    "native", "new", "null", "package", "private", "protected", "public", "return", "short", "static", "strictfp", "super", "switch",
    "synchronized", "this", "throw", "throws", "transient", "true", "try", "void", "volatile", "while" };

inline constexpr std::string_view kSliceRustReserved[] = {
    "Self", "abstract", "as", "async", "await", "become", "box", "break", "const", "continue", "crate", "do", "dyn", "else", "enum", "extern",
    "false", "final", "fn", "for", "if", "impl", "in", "let", "loop", "macro", "match", "mod", "move", "mut", "override", "priv", "pub", "ref",
    "return", "self", "static", "struct", "super", "trait", "true", "try", "type", "typeof", "unsafe", "unsized", "use", "virtual", "where",
    "while", "yield" };

static_assert( std::is_sorted( std::begin( kSliceCReserved ),    std::end( kSliceCReserved ) ) );
static_assert( std::is_sorted( std::begin( kSliceCppReserved ),  std::end( kSliceCppReserved ) ) );
static_assert( std::is_sorted( std::begin( kSlicePyReserved ),   std::end( kSlicePyReserved ) ) );
static_assert( std::is_sorted( std::begin( kSliceJsReserved ),   std::end( kSliceJsReserved ) ) );
static_assert( std::is_sorted( std::begin( kSliceGoReserved ),   std::end( kSliceGoReserved ) ) );
static_assert( std::is_sorted( std::begin( kSliceJavaReserved ), std::end( kSliceJavaReserved ) ) );
static_assert( std::is_sorted( std::begin( kSliceRustReserved ), std::end( kSliceRustReserved ) ) );

inline bool sliceIsReservedName( std::string_view text, Lang lang ) noexcept
{
    const auto in = []( const auto& tbl, std::string_view t ) noexcept { return std::binary_search( std::begin( tbl ), std::end( tbl ), t ); };
    switch( lang )
    {
        case Lang::Cpp:        return in( kSliceCppReserved, text );    // CUDA/Metal ride Lang::Cpp (kLangTable)
        case Lang::C:
        case Lang::ObjC:       return in( kSliceCReserved, text );      // ObjC's own additions are @-prefixed, never identifiers
        case Lang::Python:     return in( kSlicePyReserved, text );
        case Lang::TypeScript:
        case Lang::JavaScript: return in( kSliceJsReserved, text );
        case Lang::Go:         return in( kSliceGoReserved, text );
        case Lang::Java:       return in( kSliceJavaReserved, text );
        case Lang::Rust:       return in( kSliceRustReserved, text );
        default:               return false;
    }
}

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
    std::uint32_t line     = 0;    // 1-based
    std::uint32_t stmtLine = 0;    // 1-based FIRST line of the enclosing statement — the flow-chaining anchor
                                   //   (a statement spanning lines via continuation is ONE unit; 0 = fall back to line)
    OccT          t        = OccT::Read;
    bool          isDef    = false;
    bool          isUse    = false;
    bool          skip     = false;   // a non-occurrence (e.g. a Python keyword-argument NAME) — never emitted
};

struct SliceLocal
{
    std::string   name;
    std::uint32_t line = 0;        // first-def line
    OccT          t    = OccT::Decl;
};

// one classified occurrence WITH its identifier text — the substrate the rung-2 flow BFS folds per
// variable (VAR-mode `occ` below stays the seed's own filtered view, byte-stable for v1 consumers)
struct SliceNamedOcc
{
    std::string name;
    SliceOcc    occ;
};

// ── rung 3 (--slice-guards): CONTROL dependence, the other half of Ferrante's program dependence graph ─
//
// Control and data dependence belong in one graph — Ferrante, Ottenstein & Warren, TOPLAS 1987. Rungs 1
// and 2 model DATA dependence only; this is the bounded control half: for each emitted row, WHICH
// condition decides whether that line executes. Registered in docs/EVALS.md before any of this existed.
//
// TWO HALVES OF UNEQUAL STRENGTH, and the honesty of this feature is that it says so:
//   • the ENCLOSING-GUARD CHAIN is EXACT for goto-free structured code by construction — a syntactic
//     ancestor walk, no CFG required: a statement inside an if's consequence, a loop's body, a switch
//     case or a ternary arm is control-dependent on that construct's condition, always;
//   • the EARLY-EXIT half is an APPROXIMATION of Ferrante post-dominance — a statement after
//     `if( c ) return;` in the same block is treated as control-dependent on `c`. Exact for the
//     early-exit idiom, and WRONG IN CORNERS this slicer does not claim: a `break` deep in a nested
//     loop deciding post-loop statements needs the control-flow graph that is deliberately not built.
//     The scan never crosses a lambda/closure boundary in either direction, so a `return` inside a
//     nested lambda is the LAMBDA's exit and never the outer function's.
enum class GuardK : std::uint8_t { If, Loop, Switch, Cond, Exit };

inline constexpr const char* kGuardTagNames[] = { "if", "loop", "sw", "cond", "exit" };

inline const char* guardTag( GuardK k ) noexcept
{
    const std::size_t guardIndex = std::size_t( k );
    return kGuardTagNames[ guardIndex < std::size( kGuardTagNames ) ? guardIndex : std::size( kGuardTagNames ) - 1 ];
}

// one control-dependence edge: the statement anchored at `line` executes only if the condition whose
// construct begins at `guardLine` allows it
struct SliceGuardEdge
{
    std::uint32_t line      = 0;   // 1-based, the GUARDED line
    std::uint32_t guardLine = 0;   // 1-based, the DECIDING construct's first line
    GuardK        k         = GuardK::If;
};

// WHY a definition's guard chain is untrustworthy, when the AST can see the reason. The invisible
// reasons — macro-hidden control flow, a throwing call, a noreturn callee — are legend-only by
// construction (no AST read detects them), which is why guard rows are FLOORS like every other count.
struct SliceGuardDegrade
{
    bool jumpLabel  = false;   // goto_statement / labeled_statement: control can arrive from anywhere
    bool fallThru   = false;   // a switch case that can fall through (conservative syntactic test)
    bool coroutine  = false;   // co_await / co_return / co_yield: resumption is scheduler-controlled
    bool sehTry     = false;   // __try/__except: a non-C++ exception edge the walk cannot see
    bool preproc    = false;   // a #if/#ifdef inside the span: the parse in hand is ONE carved branch

    bool any() const noexcept { return jumpLabel || fallThru || coroutine || sehTry || preproc; }
};

struct SliceScan
{
    bool                       parseOk = false;   // grammar present + file parsed + span located
    std::vector<SliceOcc>      occ;               // VAR-mode occurrences, source order (empty when var empty)
    std::vector<SliceLocal>    locals;            // the sliceable-locals inventory, first-def order
    std::vector<SliceNamedOcc> all;               // EVERY classified occurrence, source order (flow substrate)

    // rung 3, computed only when the caller asked (--slice-guards): zero bytes and zero work otherwise
    bool                        guardsComputed = false;
    std::vector<SliceGuardEdge> guards;           // (line, guardLine) — line-ascending, deduped
    SliceGuardDegrade           guardDegrade;
};

// ── the line seed (lane/tc-sliceat): --slice --at=FILE:LINE / --slice=@FILE:LINE — ARISE's own seed ────
//
// The paper seeds its slicer at (file, line[, variable]); ripwire's v1 addressed by (symbol, variable).
// This is the disclosure record of a line-seeded run: how the seed resolved is EMITTED (seed=, and either
// var_from="seed" or seed_vars= + per-row seed="1"), never implied — the 07ec07f rebind-disclosure posture.
struct SliceSeedInfo
{
    std::string              spec;                 // the FILE:LINE seed in force (leading @ stripped)
    bool                     varFromSeed = false;  // var= was pre-picked because the seed line names exactly ONE sliceable local
    std::size_t              seedVarCount = 0;     // DISTINCT sliceable locals the seed line names (inventory mode discloses)
    std::vector<std::string> seedVars;             // their names, sorted — inventory rows matching carry seed="1"
};

// The DISTINCT sliceable locals with a classified occurrence on `seedLine`, sorted by name — the seed's
// variable candidates. Exactly one candidate ⇒ the caller pre-picks it (disclosed as var_from="seed");
// zero or several ⇒ the inventory is served with the candidates marked, never a guess (§A6a's rule at
// variable grain). Occurrences the classifier refused (skip) and names that are not sliceable locals
// (fields, globals, the fn's own name) do not count — the pick must be something a :VAR spec could name.
inline std::vector<std::string> sliceSeedLineLocals( const SliceScan& scan, std::uint32_t seedLine )
{
    std::vector<std::string> out;
    for( const SliceNamedOcc& no : scan.all )
    {
        if( no.occ.line != seedLine || no.occ.skip )
        {
            continue;
        }
        bool isLocal = false;
        for( const SliceLocal& lv : scan.locals )
        {
            if( lv.name == no.name ) { isLocal = true; break; }
        }
        if( !isLocal )
        {
            continue;
        }
        if( std::find( out.begin(), out.end(), no.name ) == out.end() )
        {
            out.push_back( no.name );
        }
    }
    std::sort( out.begin(), out.end() );
    return out;
}

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

// `Wrap w( seed, extra, true, true );` — tree-sitter-cpp resolves a direct-initialization declaration
// whose arguments are all bare names/literals to the most-vexing parse: declaration → function_declarator
// → parameter_list, each argument a parameter_declaration whose TYPE field is a type_identifier (even
// `true`). Inside a definition's span that shape is a constructor call, so those "types" are argument
// reads; recognize the exact four-level shape so a genuine parameter type (whose function_declarator
// hangs off a function_definition, not a declaration) never matches.
inline bool sliceIsDirectInitCtorArg( TSNode n ) noexcept
{
    const TSNode p = ts_node_parent( n );
    if( ts_node_is_null( p ) || !sliceKindIs( p, "parameter_declaration" ) || !sliceIsField( p, "type", n ) )
    {
        return false;
    }
    const TSNode paramList = ts_node_parent( p );
    if( ts_node_is_null( paramList ) || !sliceKindIs( paramList, "parameter_list" ) )
    {
        return false;
    }
    const TSNode fnDecl = ts_node_parent( paramList );
    if( ts_node_is_null( fnDecl ) || !sliceKindIs( fnDecl, "function_declarator" ) )
    {
        return false;
    }
    const TSNode decl = ts_node_parent( fnDecl );
    return !ts_node_is_null( decl ) && sliceKindIs( decl, "declaration" );
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
            if( std::strcmp( pk, "parameter_declaration" ) == 0 && sliceIsDirectInitCtorArg( n ) )
            {
                use( OccT::CallArg );  return o;       // Wrap w( seed, … ); — a ctor argument the grammar dressed as a parameter type
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

// ── the statement anchor (arm 25's mechanism) ────────────────────────────────────────────────────────
//
// A statement spanning several LINES via continuation (a wrapped call's argument, a parenthesized
// operand, a multi-line C initializer) must flow-chain as ONE statement — line-keyed chaining alone
// leaves a def blind to reads on its continuation lines (steps=0 where the contract's own words say
// the operand feeds the seed; found on real Python, 2026-08-31 smoke pass). The anchor is the FIRST
// line of the innermost enclosing statement: climb from the identifier until the parent is a
// statement CONTAINER for the family — the child at that boundary IS the statement.

// declarative table over a switch (G2): the node kinds whose DIRECT children are statements
inline constexpr const char* kSliceStmtContainers[ std::size_t( SliceFam::None ) ][ 6 ] =
{
    /* C    */ { "compound_statement", "translation_unit", "field_declaration_list", "declaration_list", "case_statement", nullptr },
    /* Py   */ { "block", "module", nullptr, nullptr, nullptr, nullptr },
    /* Js   */ { "statement_block", "program", "class_body", "switch_case", "switch_default", nullptr },
    /* Go   */ { "block", "source_file", "expression_case", "default_case", "communication_case", nullptr },
    /* Java */ { "block", "class_body", "program", "constructor_body", "switch_block_statement_group", nullptr },
    /* Rust */ { "block", "source_file", "declaration_list", "match_block", nullptr, nullptr },
};

inline bool sliceIsStmtContainer( TSNode n, SliceFam fam ) noexcept
{
    if( fam == SliceFam::None )
    {
        return false;
    }
    for( const char* kind : kSliceStmtContainers[ std::size_t( fam ) ] )
    {
        if( kind == nullptr )
        {
            break;
        }
        if( sliceKindIs( n, kind ) )
        {
            return true;
        }
    }
    return false;
}

// the enclosing statement's first line, 1-based; an identifier with no container above it (a degraded
// parse, or a signature identifier whose statement IS the definition head) anchors to the outermost
// node below the boundary — and when even that is absent, to its own line (behaves as before)
inline std::uint32_t sliceStmtAnchorLine( TSNode node, SliceFam fam ) noexcept
{
    TSNode cur    = node;
    TSNode parent = ts_node_parent( cur );
    while( !ts_node_is_null( parent ) )
    {
        if( sliceIsStmtContainer( parent, fam ) )
        {
            return std::uint32_t( ts_node_start_point( cur ).row ) + 1;
        }
        cur    = parent;
        parent = ts_node_parent( cur );
    }
    return std::uint32_t( ts_node_start_point( node ).row ) + 1;
}

// ── rung 3's node-kind tables (--slice-guards) ───────────────────────────────────────────────────────
//
// Every literal below is grep-VERIFIED against the vendored parser it names (third_party/deps/*/src/
// parser.c), the same discipline the classifier's tables carry. A kind this table misses under-reports,
// which is why guard rows are floors — never a wrong guard, only a missing one.

// a construct whose BODY is control-dependent on its condition. `condField` names the field holding
// that condition: a node INSIDE it is the condition, not something the condition guards. nullptr means
// the whole construct guards everything under it (a case label, a match arm).
struct SliceGuardKindRow
{
    const char* kind      = nullptr;
    GuardK      k         = GuardK::If;
    const char* condField = nullptr;
};

inline constexpr std::size_t kSliceGuardKindCap = 8;

inline constexpr SliceGuardKindRow kSliceGuardKinds[ std::size_t( SliceFam::None ) ][ kSliceGuardKindCap ] =
{
    /* C    */ { { "if_statement", GuardK::If, "condition" }, { "while_statement", GuardK::Loop, "condition" },
                 { "for_statement", GuardK::Loop, nullptr }, { "do_statement", GuardK::Loop, "condition" },
                 { "for_range_loop", GuardK::Loop, nullptr }, { "switch_statement", GuardK::Switch, "condition" },
                 { "case_statement", GuardK::Switch, nullptr }, { "conditional_expression", GuardK::Cond, "condition" } },
    /* Py   */ { { "if_statement", GuardK::If, "condition" }, { "elif_clause", GuardK::If, "condition" },
                 { "while_statement", GuardK::Loop, "condition" }, { "for_statement", GuardK::Loop, "right" },
                 { "match_statement", GuardK::Switch, "subject" }, { "case_clause", GuardK::Switch, nullptr },
                 { "conditional_expression", GuardK::Cond, nullptr }, {} },
    /* Js   */ { { "if_statement", GuardK::If, "condition" }, { "while_statement", GuardK::Loop, "condition" },
                 { "for_statement", GuardK::Loop, nullptr }, { "for_in_statement", GuardK::Loop, nullptr },
                 { "do_statement", GuardK::Loop, "condition" }, { "switch_statement", GuardK::Switch, "value" },
                 { "switch_case", GuardK::Switch, nullptr }, { "ternary_expression", GuardK::Cond, "condition" } },
    /* Go   */ { { "if_statement", GuardK::If, "condition" }, { "for_statement", GuardK::Loop, nullptr },
                 { "expression_switch_statement", GuardK::Switch, "value" }, { "type_switch_statement", GuardK::Switch, nullptr },
                 { "select_statement", GuardK::Switch, nullptr }, { "expression_case", GuardK::Switch, nullptr },
                 { "communication_case", GuardK::Switch, nullptr }, {} },
    /* Java */ { { "if_statement", GuardK::If, "condition" }, { "while_statement", GuardK::Loop, "condition" },
                 { "for_statement", GuardK::Loop, nullptr }, { "enhanced_for_statement", GuardK::Loop, nullptr },
                 { "do_statement", GuardK::Loop, "condition" }, { "switch_expression", GuardK::Switch, "condition" },
                 { "switch_block_statement_group", GuardK::Switch, nullptr }, { "ternary_expression", GuardK::Cond, "condition" } },
    /* Rust */ { { "if_expression", GuardK::If, "condition" }, { "while_expression", GuardK::Loop, "condition" },
                 { "for_expression", GuardK::Loop, "value" }, { "loop_expression", GuardK::Loop, nullptr },
                 { "match_expression", GuardK::Switch, "value" }, { "match_arm", GuardK::Switch, nullptr }, {}, {} },
};

// a statement that JUMPS out of the straight-line flow. `if( c ) <jump>;` makes everything after it in
// the same block control-dependent on c — the early-exit approximation, the half that is not exact.
inline constexpr const char* kSliceJumpKinds[ std::size_t( SliceFam::None ) ][ 6 ] =
{
    /* C    */ { "return_statement", "break_statement", "continue_statement", "throw_statement", "goto_statement", nullptr },
    /* Py   */ { "return_statement", "break_statement", "continue_statement", "raise_statement", nullptr, nullptr },
    /* Js   */ { "return_statement", "break_statement", "continue_statement", "throw_statement", nullptr, nullptr },
    /* Go   */ { "return_statement", "break_statement", "continue_statement", "goto_statement", nullptr, nullptr },
    /* Java */ { "return_statement", "break_statement", "continue_statement", "throw_statement", nullptr, nullptr },
    /* Rust */ { "return_expression", "break_expression", "continue_expression", nullptr, nullptr, nullptr },
};

// the SCOPE BOUNDARY the exit scan must not cross, in EITHER direction (the registered contract point):
// a `return` inside one of these exits IT, never the enclosing function.
inline constexpr const char* kSliceClosureKinds[ std::size_t( SliceFam::None ) ][ 3 ] =
{
    /* C    */ { "lambda_expression", nullptr, nullptr },
    /* Py   */ { "lambda", "function_definition", nullptr },
    /* Js   */ { "arrow_function", "function_expression", "function_declaration" },
    /* Go   */ { "func_literal", nullptr, nullptr },
    /* Java */ { "lambda_expression", nullptr, nullptr },
    /* Rust */ { "closure_expression", nullptr, nullptr },
};

inline bool sliceKindInTable( TSNode n, const char* const* table, std::size_t cap ) noexcept
{
    for( std::size_t kindIndex = 0; kindIndex < cap; ++kindIndex )
    {
        if( table[ kindIndex ] == nullptr )
        {
            break;
        }
        if( sliceKindIs( n, table[ kindIndex ] ) )
        {
            return true;
        }
    }
    return false;
}

inline bool sliceIsJumpKind( TSNode n, SliceFam fam ) noexcept
{
    return fam != SliceFam::None && sliceKindInTable( n, kSliceJumpKinds[ std::size_t( fam ) ], 6 );
}

inline bool sliceIsClosureKind( TSNode n, SliceFam fam ) noexcept
{
    return fam != SliceFam::None && sliceKindInTable( n, kSliceClosureKinds[ std::size_t( fam ) ], 3 );
}

// the guard-construct lookup: which row of this family's table (if any) this node is
inline const SliceGuardKindRow* sliceGuardRowOf( TSNode n, SliceFam fam ) noexcept
{
    if( fam == SliceFam::None )
    {
        return nullptr;
    }
    const SliceGuardKindRow* rows = kSliceGuardKinds[ std::size_t( fam ) ];
    for( std::size_t rowIndex = 0; rowIndex < kSliceGuardKindCap; ++rowIndex )
    {
        if( rows[ rowIndex ].kind == nullptr )
        {
            break;
        }
        if( sliceKindIs( n, rows[ rowIndex ].kind ) )
        {
            return &rows[ rowIndex ];
        }
    }
    return nullptr;
}

// does this node ALWAYS leave the straight-line flow? A bare jump does; a block does when its LAST
// statement does. Conservative on purpose — a maybe-jump must not mint a guard.
inline bool sliceAlwaysJumps( TSNode n, SliceFam fam ) noexcept
{
    if( ts_node_is_null( n ) )
    {
        return false;
    }
    if( sliceIsJumpKind( n, fam ) )
    {
        return true;
    }
    if( !sliceIsStmtContainer( n, fam ) )
    {
        return false;
    }
    const std::uint32_t named = ts_node_named_child_count( n );
    for( std::uint32_t backIndex = named; backIndex > 0; --backIndex )
    {
        const TSNode child = ts_node_named_child( n, backIndex - 1 );
        if( !ts_node_is_null( child ) && !sliceKindIs( child, "comment" ) )
        {
            return sliceIsJumpKind( child, fam );
        }
    }
    return false;
}

// `if( c ) <always-jumps>` with NO else — the early-exit shape. An if with an else is a fork, not an
// exit: the statements after it are reached either way, so it guards nothing downstream.
inline bool sliceIsEarlyExitIf( TSNode n, SliceFam fam ) noexcept
{
    const SliceGuardKindRow* row = sliceGuardRowOf( n, fam );
    if( row == nullptr || row->k != GuardK::If )
    {
        return false;
    }
    if( !ts_node_is_null( sliceField( n, "alternative" ) ) )
    {
        return false;
    }
    return sliceAlwaysJumps( sliceField( n, "consequence" ), fam );   // every served family spells it `consequence`
}

// the degrade sweep: everything an AST read CAN see that defeats the chain. Runs over the same subtree
// as the guard walk, once, so a definition pays for it only when guards were asked for.
inline void sliceGuardDegradeSweep( TSNode node, std::uint32_t spanStart, std::uint32_t spanEnd, SliceFam fam,
                                    SliceGuardDegrade& degrade )
{
    if( ts_node_end_byte( node ) <= spanStart || ts_node_start_byte( node ) >= spanEnd )
    {
        return;
    }
    // OVERLAP admits the subtree for DESCENT — the definition is nested under nodes that contain it —
    // but a construct only defeats the chain when it BEGINS inside the definition. Testing overlap here
    // instead flagged every function wrapped in an `#ifdef`, which is most of a portable C++ tree, and
    // an attribute that fires on everything discloses nothing (found by probe, 2026-08-31).
    const bool beginsInSpan = ts_node_start_byte( node ) >= spanStart && ts_node_start_byte( node ) < spanEnd;
    const std::uint32_t childCount = ts_node_child_count( node );
    if( !beginsInSpan )
    {
        for( std::uint32_t childIndex = 0; childIndex < childCount; ++childIndex )
        {
            sliceGuardDegradeSweep( ts_node_child( node, childIndex ), spanStart, spanEnd, fam, degrade );
        }
        return;
    }
    const char* kind = ts_node_type( node );
    if( std::strcmp( kind, "goto_statement" ) == 0 || std::strcmp( kind, "labeled_statement" ) == 0 )
    {
        degrade.jumpLabel = true;
    }
    if( std::strcmp( kind, "co_await_expression" ) == 0 || std::strcmp( kind, "co_return_statement" ) == 0
        || std::strcmp( kind, "co_yield_statement" ) == 0 )
    {
        degrade.coroutine = true;
    }
    if( std::strcmp( kind, "seh_try_statement" ) == 0 )
    {
        degrade.sehTry = true;
    }
    if( std::strncmp( kind, "preproc_if", 10 ) == 0 || std::strcmp( kind, "preproc_elif" ) == 0
        || std::strcmp( kind, "preproc_else" ) == 0 )
    {
        degrade.preproc = true;
    }
    // fallthrough: a NON-EMPTY case body whose last statement is not a jump can fall into the next case,
    // so the case label above is not the only condition reaching those statements. C-family and JS only —
    // no other served family has fallthrough.
    if( ( fam == SliceFam::C && std::strcmp( kind, "case_statement" ) == 0 )
        || ( fam == SliceFam::Js && ( std::strcmp( kind, "switch_case" ) == 0 || std::strcmp( kind, "switch_default" ) == 0 ) ) )
    {
        TSNode last = {};
        for( std::uint32_t childIndex = ts_node_named_child_count( node ); childIndex > 0; --childIndex )
        {
            const TSNode child = ts_node_named_child( node, childIndex - 1 );
            if( !sliceKindIs( child, "comment" ) )
            {
                last = child;
                break;
            }
        }
        if( !ts_node_is_null( last ) && !sliceIsJumpKind( last, fam ) && !sliceKindIs( last, "case_statement" ) )
        {
            degrade.fallThru = true;
        }
    }
    for( std::uint32_t childIndex = 0; childIndex < childCount; ++childIndex )
    {
        sliceGuardDegradeSweep( ts_node_child( node, childIndex ), spanStart, spanEnd, fam, degrade );
    }
}

// the guard walk. Descends the definition carrying the guard stack in force, and writes that stack to
// every LINE the current statement spans — deeper statements are visited later, so the innermost stack
// wins per line, and a stack always CONTAINS its enclosing guards.
//
// `lineGuards[ line - firstLine ]` is the stack for that line. A vector-of-vectors indexed by line is
// the right shape here: a definition is one function, so the extent is tens of lines, and the
// alternative (an associative container) is forbidden by the house container rule anyway.
inline void sliceGuardWalk( TSNode node, std::uint32_t spanStart, std::uint32_t spanEnd, SliceFam fam,
                            std::uint32_t firstLine, std::vector<std::vector<SliceGuardEdge>>& lineGuards,
                            std::vector<SliceGuardEdge>& stack )
{
    if( ts_node_end_byte( node ) <= spanStart || ts_node_start_byte( node ) >= spanEnd )
    {
        return;
    }

    // a closure body is a scope of its own: the exits accumulated OUTSIDE it do not decide whether its
    // statements run (its invocation does), and its own exits never escape. Enclosing structural guards
    // still hold — they decide whether the closure is even created — so only the exit half is dropped.
    std::vector<SliceGuardEdge> inner = stack;
    if( sliceIsClosureKind( node, fam ) )
    {
        inner.clear();
        for( const SliceGuardEdge& e : stack )
        {
            if( e.k != GuardK::Exit )
            {
                inner.push_back( e );
            }
        }
    }

    // paint this node's lines with the stack in force. Painting EVERY node (not just statements) is
    // what makes a multi-statement or continuation line resolve to its innermost guard: the walk is
    // pre-order, so a deeper node's paint lands later and wins, and a deeper stack always CONTAINS the
    // shallower one it overwrites.
    const std::uint32_t startLine = std::uint32_t( ts_node_start_point( node ).row ) + 1;
    const std::uint32_t endLine   = std::uint32_t( ts_node_end_point( node ).row ) + 1;
    for( std::uint32_t line = startLine; line <= endLine; ++line )
    {
        if( line >= firstLine && std::size_t( line - firstLine ) < lineGuards.size() )
        {
            lineGuards[ line - firstLine ] = inner;
        }
    }

    const SliceGuardKindRow* row     = sliceGuardRowOf( node, fam );
    const TSNode             condNode = ( row != nullptr && row->condField != nullptr ) ? sliceField( node, row->condField ) : TSNode{};

    // the early-exit accumulator, per BLOCK: a guarded jump makes every LATER sibling depend on it
    const bool isBlock = sliceIsStmtContainer( node, fam );

    const std::uint32_t childCount = ts_node_child_count( node );
    for( std::uint32_t childIndex = 0; childIndex < childCount; ++childIndex )
    {
        const TSNode child = ts_node_child( node, childIndex );
        std::vector<SliceGuardEdge> childStack = inner;
        if( row != nullptr )
        {
            // the condition itself is not guarded BY the construct it belongs to; everything else is
            const bool insideCond = !ts_node_is_null( condNode )
                                    && ts_node_start_byte( child ) >= ts_node_start_byte( condNode )
                                    && ts_node_end_byte( child ) <= ts_node_end_byte( condNode );
            if( !insideCond )
            {
                childStack.push_back( SliceGuardEdge{ 0, startLine, row->k } );
            }
        }
        sliceGuardWalk( child, spanStart, spanEnd, fam, firstLine, lineGuards, childStack );
        if( isBlock && sliceIsEarlyExitIf( child, fam ) )
        {
            inner.push_back( SliceGuardEdge{ 0, std::uint32_t( ts_node_start_point( child ).row ) + 1, GuardK::Exit } );
        }
    }
}

// the entry point: paint the definition's lines, then flatten to line-ascending, deduplicated edges
inline void sliceCollectGuards( TSNode root, const Symbol& sym, SliceFam fam, SliceScan& scan )
{
    scan.guardsComputed = true;
    if( fam == SliceFam::None || sym.endByte <= sym.sigStartByte )
    {
        return;
    }
    sliceGuardDegradeSweep( root, sym.sigStartByte, sym.endByte, fam, scan.guardDegrade );

    // locate the definition's own node to bound the line extent — the root spans the whole file
    std::uint32_t firstLine = 0, lastLine = 0;
    {
        TSNode cur = ts_node_descendant_for_byte_range( root, sym.sigStartByte, sym.endByte > 0 ? sym.endByte - 1 : 0 );
        if( ts_node_is_null( cur ) )
        {
            cur = root;
        }
        firstLine = std::uint32_t( ts_node_start_point( cur ).row ) + 1;
        lastLine  = std::uint32_t( ts_node_end_point( cur ).row ) + 1;
    }
    if( lastLine < firstLine )
    {
        DEGRADED_PATH_ALERT( "slice-guards: definition span has no line extent" );
        return;
    }

    std::vector<std::vector<SliceGuardEdge>> lineGuards( std::size_t( lastLine - firstLine ) + 1 );
    std::vector<SliceGuardEdge>              stack;
    sliceGuardWalk( root, sym.sigStartByte, sym.endByte, fam, firstLine, lineGuards, stack );

    for( std::size_t lineIndex = 0; lineIndex < lineGuards.size(); ++lineIndex )
    {
        const std::uint32_t line = firstLine + std::uint32_t( lineIndex );
        for( const SliceGuardEdge& e : lineGuards[ lineIndex ] )
        {
            if( e.guardLine == line )
            {
                continue;   // a construct never guards its own header line — a self-edge adds no line to the slice
            }
            bool seen = false;
            for( const SliceGuardEdge& kept : scan.guards )
            {
                seen = seen || ( kept.line == line && kept.guardLine == e.guardLine && kept.k == e.k );
            }
            if( !seen )
            {
                scan.guards.push_back( SliceGuardEdge{ line, e.guardLine, e.k } );
            }
        }
    }
}

// ── the walk ─────────────────────────────────────────────────────────────────────────────────────────

// Recursive descent over the definition's span, collecting classified `identifier` occurrences.
// Depth-bounded only by the AST itself; a definition's subtree is small (one function).
inline void sliceWalk( TSNode node, std::uint32_t spanStart, std::uint32_t spanEnd, SliceFam fam, Lang lang,
                       std::string_view src, std::string_view varName,
                       std::vector<SliceOcc>& occ, std::vector<SliceLocal>& locals, std::string_view selfName,
                       std::vector<SliceNamedOcc>& all )
{
    const std::uint32_t a = ts_node_start_byte( node ), b = ts_node_end_byte( node );
    if( b <= spanStart || a >= spanEnd )
    {
        return;   // disjoint from the definition — prune the subtree
    }

    // the C-family also yields variable occurrences dressed as type_identifier: the arguments of a
    // direct-initialization declaration under the most-vexing parse (see sliceIsDirectInitCtorArg)
    const bool occurrenceKind = sliceKindIs( node, "identifier" )
                                || ( fam == SliceFam::C && sliceKindIs( node, "type_identifier" ) && sliceIsDirectInitCtorArg( node ) );
    if( occurrenceKind && a >= spanStart && b <= spanEnd && b <= src.size() && b > a )
    {
        const std::string_view text = src.substr( a, b - a );
        if( sliceIsReservedName( text, lang ) )
        {
            return;   // a keyword lexed as an identifier is a degraded-parse artifact, never a variable
        }
        SliceOcc c = sliceClassify( node, fam, src );
        if( !c.skip )
        {
            c.stmtLine = sliceStmtAnchorLine( node, fam );
            all.push_back( SliceNamedOcc{ std::string( text ), c } );
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
        sliceWalk( ts_node_child( node, i ), spanStart, spanEnd, fam, lang, src, varName, occ, locals, selfName, all );
    }
}

// parse + walk. `src` is the WHOLE file (symbol byte offsets are file-absolute). parseOk=false means
// the grammar refused or the span is out of range — the caller refuses loudly, never emits an empty
// success.
inline SliceScan sliceScanDefinition( const std::string& src, const Symbol& sym, SliceFam fam,
                                      const ::TSLanguage* grammar, std::string_view varName, bool wantGuards = false )
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

    sliceWalk( ts_tree_root_node( tree ), sym.sigStartByte, sym.endByte, fam, sym.lang, src, varName, scan.occ, scan.locals, sym.name, scan.all );
    if( wantGuards )
    {
        // rung 3 rides THIS parse — the AST is already in hand, so control dependence costs no second
        // parse and no new infrastructure, only a second descent over one function's subtree
        sliceCollectGuards( ts_tree_root_node( tree ), sym, fam, scan );
    }
    scan.parseOk = true;

    ts_tree_delete( tree );
    ts_parser_delete( parser );
    return scan;
}

// ── rung 2: the cross-statement data-flow slice (lane/or-arise) ─────────────────────────────────────
//
// The ARISE paper's own slicer semantics (arXiv:2605.03117), adapted to the house rules: a seed
// variable plus a direction, a bounded BFS over reaching-definition def-use edges, stopping at the
// function boundary — the paper itself keeps its slicer intra-procedural and leaves the
// inter-procedural half to its call-graph ranking tier, which here is --callers/--impact.
//
// DEVIATIONS from the paper, deliberate and disclosed (EVALS carries the registration):
//   • statement ≈ LINE for the ROWS — rows aggregate per source line (a multi-statement line
//     merges) — while CHAINING is statement-anchored (arm 25): a statement spanning several lines
//     via continuation chains as ONE unit keyed on its first line, so a def is never blind to the
//     operands on its continuation lines;
//   • name-based and scope-insensitive like v1 — no lexical-scope separation (shadowing may
//     over-include), no alias analysis, where the paper handles global/nonlocal explicitly;
//   • the seed is the whole variable inside ONE resolved definition (v1's addressing), not a
//     (file, line, variable) triple — the paper's line seed is recoverable by reading the d=0 rows.

// one aggregated row per LINE touching a variable: k= def|use|both, t= the strongest role (enum order
// IS the priority), CDATA = the trimmed statement line
struct SliceLineRow
{
    std::uint32_t line   = 0;
    bool          hasDef = false;
    bool          hasUse = false;
    OccT          t      = OccT::Read;
};

// fold line-ascending occurrences into per-line rows — the ONE aggregation both the v1 seed rows and
// the flow substrate use, so the two can never disagree on what a line's k=/t= is
inline std::vector<SliceLineRow> sliceFoldLines( const std::vector<SliceOcc>& occ )
{
    std::vector<SliceLineRow> rows;
    for( const SliceOcc& o : occ )
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
    return rows;
}

enum class SliceFlowDir : std::uint8_t { Back, Fwd, Both };

inline constexpr std::uint32_t kSliceFlowDefaultDepth = 8;    // the disclosed default bound (depth= always states it)
// the depth band, named so the MCP dialect's refusal and the CLI's parse-time domain (cli.h's
// --slice-depth= row spells 1..32 as literals) can be pinned together by a static_assert rather than prose
inline constexpr std::uint32_t kSliceFlowDepthMin = 1;
inline constexpr std::uint32_t kSliceFlowDepthMax = 32;

struct SliceVarRows
{
    std::string               name;
    std::vector<SliceLineRow> rows;    // line-ascending
};

// one flow step: variable varIdx's line row rowIdx, reached at BFS depth d from line `from`
struct SliceFlowRow
{
    std::uint32_t varIdx = 0;
    std::uint32_t rowIdx = 0;
    std::uint32_t d      = 0;
    std::uint32_t from   = 0;
};

struct SliceFlowOut
{
    std::vector<SliceVarRows> vars;         // name-ascending; rows line-ascending
    std::vector<SliceFlowRow> rows;         // emission order: (d, line, var name) ascending
    bool                      truncated = false;
    bool                      seedFound = false;
};

// everything the emitter needs to render a flow — one optional argument instead of three
struct SliceFlowSpec
{
    const SliceFlowOut* out   = nullptr;
    SliceFlowDir        dir   = SliceFlowDir::Back;
    std::uint32_t       bound = kSliceFlowDefaultDepth;
};

// the reaching definition of vars[vi] at line L: the LAST def row strictly before L in source order
// (the paper's edge rule, at line grain). Returns the row index, or npos when no def precedes.
inline std::size_t sliceReachingDef( const SliceVarRows& v, std::uint32_t line )
{
    std::size_t hit = std::size_t( -1 );
    for( std::size_t rowIndex = 0; rowIndex < v.rows.size() && v.rows[ rowIndex ].line < line; ++rowIndex )
    {
        if( v.rows[ rowIndex ].hasDef )
        {
            hit = rowIndex;
        }
    }
    return hit;
}

// the bounded BFS. Emission dedups per (var, line) row — first (shallowest) reach wins; in Both mode
// the backward walk runs first, so a row both directions reach keeps its backward depth. truncated
// flips only when the bound suppresses a NOVEL row — a bound that cuts nothing new is not a cut.
// the per-variable line folds, name-ascending. scan.all is source-ordered, so a stable sort by name
// keeps each variable's occurrences line-ascending for the fold.
inline std::vector<SliceVarRows> sliceFoldVarRows( const SliceScan& scan )
{
    std::vector<SliceVarRows> vars;
    std::vector<std::uint32_t> order( scan.all.size() );
    for( std::uint32_t occIndex = 0; occIndex < order.size(); ++occIndex ) { order[ occIndex ] = occIndex; }
    std::stable_sort( order.begin(), order.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return scan.all[ a ].name < scan.all[ b ].name; } );
    for( std::uint32_t occIndex : order )
    {
        const SliceNamedOcc& no = scan.all[ occIndex ];
        if( vars.empty() || vars.back().name != no.name )
        {
            vars.push_back( SliceVarRows{ no.name, {} } );
        }
        std::vector<SliceLineRow>& rows = vars.back().rows;
        if( rows.empty() || rows.back().line != no.occ.line )
        {
            rows.push_back( SliceLineRow{ no.occ.line, false, false, OccT::Read } );
        }
        SliceLineRow& r = rows.back();
        r.hasDef = r.hasDef || no.occ.isDef;
        r.hasUse = r.hasUse || no.occ.isUse;
        if( std::uint8_t( no.occ.t ) < std::uint8_t( r.t ) )
        {
            r.t = no.occ.t;
        }
    }
    return vars;
}

// the statement-anchored occurrence table (arm 25): chaining is per STATEMENT, not per line — an
// occurrence's anchor is its statement's FIRST line, so a continuation-line operand chains to and
// from the def it belongs to. Source order (scan.all) is the iteration order; emission dedup plus
// the final (d, line, name) sort keep the output canonical regardless.
struct SliceAnchorOcc
{
    std::uint32_t anchor = 0, varIdx = 0, rowIdx = 0;
    bool          isDef = false, isUse = false;
};

inline std::vector<SliceAnchorOcc> sliceBuildAnchorOccs( const SliceScan& scan, const std::vector<SliceVarRows>& vars )
{
    std::vector<SliceAnchorOcc> occs;
    occs.reserve( scan.all.size() );
    for( const SliceNamedOcc& no : scan.all )
    {
        std::size_t varIdx = std::size_t( -1 );
        for( std::size_t varIndex = 0; varIndex < vars.size(); ++varIndex )
        {
            if( vars[ varIndex ].name == no.name ) { varIdx = varIndex; }
        }
        if( varIdx == std::size_t( -1 ) ) { continue; }   // unreachable — every folded name has a var
        std::size_t rowIdx = std::size_t( -1 );
        const std::vector<SliceLineRow>& rows = vars[ varIdx ].rows;
        for( std::size_t rowIndex = 0; rowIndex < rows.size(); ++rowIndex )
        {
            if( rows[ rowIndex ].line == no.occ.line ) { rowIdx = rowIndex; }
        }
        if( rowIdx == std::size_t( -1 ) ) { continue; }   // unreachable — the fold made a row per line
        occs.push_back( SliceAnchorOcc{ no.occ.stmtLine != 0 ? no.occ.stmtLine : no.occ.line,
                                        std::uint32_t( varIdx ), std::uint32_t( rowIdx ), no.occ.isDef, no.occ.isUse } );
    }
    return occs;
}

// backward expansion of one DEF node: this def STATEMENT's value came from the uses in it —
// continuation lines included: every variable read anywhere in the statement chains to ITS reaching
// definition. The reach point is the statement's ANCHOR line, so a same-statement operand resolves
// to the def BEFORE the statement, never into the statement's own later lines.
template< class EmitFn, class EnqueueFn >
inline void sliceFlowExpandBack( const std::vector<SliceVarRows>& vars, const std::vector<SliceAnchorOcc>& anchorOccs,
                                 std::uint32_t varIdx, std::uint32_t rowIdx, std::uint32_t d, std::uint32_t line,
                                 const EmitFn& emitRow, const EnqueueFn& enqueue )
{
    for( const SliceAnchorOcc& defOcc : anchorOccs )
    {
        if( !defOcc.isDef || defOcc.varIdx != varIdx || defOcc.rowIdx != rowIdx ) { continue; }
        for( const SliceAnchorOcc& useOcc : anchorOccs )
        {
            if( useOcc.anchor != defOcc.anchor || !useOcc.isUse ) { continue; }
            const std::size_t rd = sliceReachingDef( vars[ useOcc.varIdx ], defOcc.anchor );
            if( rd != std::size_t( -1 ) )
            {
                emitRow( useOcc.varIdx, rd, d + 1, line );
                enqueue( useOcc.varIdx, rd, d + 1 );
            }
        }
    }
}

// forward expansion of one DEF node: the def reaches every later use of the same variable up to (and
// including) its next redefinition; a reached STATEMENT that defines a variable carries the value
// onward — continuation lines included. A use inside the def's OWN statement (possible only when the
// statement spans lines) is the PREVIOUS def's reader, so it is skipped.
template< class EmitFn, class EnqueueFn >
inline void sliceFlowExpandFwd( const std::vector<SliceVarRows>& vars, const std::vector<SliceAnchorOcc>& anchorOccs,
                                std::uint32_t varIdx, std::uint32_t rowIdx, std::uint32_t d, std::uint32_t line,
                                const EmitFn& emitRow, const EnqueueFn& enqueue )
{
    const SliceVarRows& x = vars[ varIdx ];
    for( std::size_t rowIndex = rowIdx + 1; rowIndex < x.rows.size(); ++rowIndex )
    {
        const SliceLineRow& r = x.rows[ rowIndex ];
        if( r.hasUse )
        {
            bool crossStmt = false;   // at least one use occurrence on this row lies OUTSIDE the def's own statement
            for( const SliceAnchorOcc& useOcc : anchorOccs )
            {
                if( !useOcc.isUse || useOcc.varIdx != varIdx || useOcc.rowIdx != rowIndex ) { continue; }
                bool ownStmt = false;
                for( const SliceAnchorOcc& defOcc : anchorOccs )
                {
                    ownStmt = ownStmt || ( defOcc.isDef && defOcc.varIdx == varIdx && defOcc.rowIdx == rowIdx && defOcc.anchor == useOcc.anchor );
                }
                crossStmt = crossStmt || !ownStmt;
            }
            if( crossStmt )
            {
                emitRow( varIdx, rowIndex, d + 1, line );
                for( const SliceAnchorOcc& useOcc : anchorOccs )
                {
                    if( !useOcc.isUse || useOcc.varIdx != varIdx || useOcc.rowIdx != rowIndex ) { continue; }
                    for( const SliceAnchorOcc& defOcc : anchorOccs )
                    {
                        if( defOcc.isDef && defOcc.anchor == useOcc.anchor )
                        {
                            enqueue( defOcc.varIdx, defOcc.rowIdx, d + 1 );   // aug-assign self-rows included
                        }
                    }
                }
            }
        }
        if( r.hasDef ) { break; }   // the next def kills this def's reach
    }
}

inline SliceFlowOut sliceFlowCompute( const SliceScan& scan, std::string_view seedVar, SliceFlowDir dir, std::uint32_t bound )
{
    SliceFlowOut out;
    out.vars = sliceFoldVarRows( scan );
    const std::vector<SliceAnchorOcc> anchorOccs = sliceBuildAnchorOccs( scan, out.vars );

    std::size_t seedIdx = std::size_t( -1 );
    for( std::size_t varIndex = 0; varIndex < out.vars.size(); ++varIndex )
    {
        if( out.vars[ varIndex ].name == seedVar ) { seedIdx = varIndex; }
    }
    if( seedIdx == std::size_t( -1 ) )
    {
        return out;   // the caller already refuses unknown seeds; belt and braces
    }
    out.seedFound = true;

    // emitted[v][r]: the row already IS in the slice (seed rows pre-count — they print as the d=0 block)
    std::vector<std::vector<bool>> emitted;
    emitted.reserve( out.vars.size() );
    for( const SliceVarRows& v : out.vars ) { emitted.push_back( std::vector<bool>( v.rows.size(), false ) ); }
    for( std::size_t rowIndex = 0; rowIndex < out.vars[ seedIdx ].rows.size(); ++rowIndex ) { emitted[ seedIdx ][ rowIndex ] = true; }

    struct Node { std::uint32_t varIdx, rowIdx, d; };

    const auto walk = [ & ]( bool backward )
    {
        std::vector<std::vector<bool>> visited;
        visited.reserve( out.vars.size() );
        for( const SliceVarRows& v : out.vars ) { visited.push_back( std::vector<bool>( v.rows.size(), false ) ); }

        std::vector<Node> queue;
        for( std::size_t rowIndex = 0; rowIndex < out.vars[ seedIdx ].rows.size(); ++rowIndex )
        {
            if( out.vars[ seedIdx ].rows[ rowIndex ].hasDef )
            {
                visited[ seedIdx ][ rowIndex ] = true;
                queue.push_back( Node{ std::uint32_t( seedIdx ), std::uint32_t( rowIndex ), 0 } );
            }
        }

        // emit = put the row in the slice (dedup per row, shallowest reach wins); enqueue = expand it
        // later. The two are separate on purpose: a line REACHED for variable x already rows as x, so a
        // second variable defined on it carries the value onward (enqueue) without a duplicate row.
        const auto emitRow = [ & ]( std::size_t vi, std::size_t ri, std::uint32_t d, std::uint32_t from )
        {
            if( d > bound )
            {
                out.truncated = out.truncated || !emitted[ vi ][ ri ];
                return;
            }
            if( !emitted[ vi ][ ri ] )
            {
                emitted[ vi ][ ri ] = true;
                out.rows.push_back( SliceFlowRow{ std::uint32_t( vi ), std::uint32_t( ri ), d, from } );
            }
        };
        const auto enqueue = [ & ]( std::size_t vi, std::size_t ri, std::uint32_t d )
        {
            if( d > bound )
            {
                out.truncated = out.truncated || !visited[ vi ][ ri ];
                return;
            }
            if( !visited[ vi ][ ri ] )
            {
                visited[ vi ][ ri ] = true;
                queue.push_back( Node{ std::uint32_t( vi ), std::uint32_t( ri ), d } );
            }
        };

        for( std::size_t head = 0; head < queue.size(); ++head )
        {
            const Node          node = queue[ head ];
            const SliceVarRows& x    = out.vars[ node.varIdx ];
            const std::uint32_t line = x.rows[ node.rowIdx ].line;
            if( !x.rows[ node.rowIdx ].hasDef ) { continue; }   // both directions expand DEF rows only
            if( backward )
            {
                sliceFlowExpandBack( out.vars, anchorOccs, node.varIdx, node.rowIdx, node.d, line, emitRow, enqueue );
            }
            else
            {
                sliceFlowExpandFwd( out.vars, anchorOccs, node.varIdx, node.rowIdx, node.d, line, emitRow, enqueue );
            }
        }
    };

    if( dir == SliceFlowDir::Back || dir == SliceFlowDir::Both ) { walk( true ); }
    if( dir == SliceFlowDir::Fwd  || dir == SliceFlowDir::Both ) { walk( false ); }

    // the stated output order: (d, line, variable name) ascending — a contract, not a walk artifact
    std::stable_sort( out.rows.begin(), out.rows.end(), [ & ]( const SliceFlowRow& a, const SliceFlowRow& b )
    {
        const std::uint32_t la = out.vars[ a.varIdx ].rows[ a.rowIdx ].line, lb = out.vars[ b.varIdx ].rows[ b.rowIdx ].line;
        if( a.d != b.d )  { return a.d < b.d; }
        if( la != lb )    { return la < lb; }
        return out.vars[ a.varIdx ].name < out.vars[ b.varIdx ].name;
    } );
    return out;
}

// ── XML assembly ─────────────────────────────────────────────────────────────────────────────────────

inline std::string sliceBundleText( const IngestResult& ing, const std::string& root, NodeId focus,
                                    std::string_view varName, const SliceScan& scan, const std::string& src,
                                    RedactCounts* redact, const SliceFlowSpec* flowSpec = nullptr,
                                    const SliceSeedInfo* seedInfo = nullptr )
{
    const SliceFlowOut* flow = flowSpec != nullptr ? flowSpec->out : nullptr;
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
        "VAR (shadowing) is NOT separated, so its rows may over-include. RECEIVER MUTATION IS NOT COUNTED AS A DEF: a write a callee "
        "performs through the variable itself — v.push_back(x), buf.append(s), m.insert(k) — is classified k=\"use\" t=\"read\", "
        "because proving it writes needs the receiver's TYPE and the callee's BODY and this slicer has neither. Declining to guess is "
        "deliberate: a method-name list would mint false defs (v.reserve(n) changes capacity, never the value), and a false def is "
        "worse than a missing one because the flow walk stops at the NEXT def, so a fabricated one suppresses the real def before it. "
        "The consequence to read for: a variable written ONLY through method calls reports defs= counting just its introduction, and a "
        "flow of steps=\"0\" — which means \"no def-use edge this slicer can prove\", never \"this variable is never written\". "
        "counts_floor=\"1\" says exactly that of every count on the root: defs=, uses=, vars= and steps= are FLOORS, never totals. "
        "Intra-procedural only: rows never cross into callees/callers "
        "(the callers/callees/uses verbs give the inter-procedural half). One <s> row per LINE touching VAR: k= def|use|both (both = "
        "the line writes AND reads it, e.g. `x += y`), t= the strongest role on the line (param > decl > assign > call-arg > read), "
        "CDATA = the trimmed source line. defs=/uses= count OCCURRENCES, not lines. A reserved word of the definition's own language "
        "is never an occurrence or a local — a keyword lexed as an identifier is a degraded-parse artifact and is dropped, so slicing "
        "one refuses like any unknown VAR. Bare slice=SYM (no :VAR) lists the sliceable "
        "locals instead (<v n= l= t=/> rows at their first-def line, vars= the count). Languages served: C/C++/ObjC (+CUDA/Metal via "
        "the C-family grammars), Python, JS/TS, Go, Java, Rust — every other language refuses loudly, never an empty success. -->";

    if( seedInfo != nullptr )
    {
        // conditional, like the flow legend below: the seed vocabulary is defined exactly where a reader
        // meets it and costs zero bytes on an unseeded run (G4).
        out +=
            "<!-- slice-seed: this slice was LINE-SEEDED (the at grammar, FILE:LINE — ARISE's own (file, line[, variable]) seed). "
            "seed= is the seed in force; the definition sliced is the innermost indexed one enclosing that line. var_from=\"seed\" "
            "means the seed line names exactly ONE sliceable local and var= is it — a pre-pick, disclosed, never a guess. A seed "
            "line naming zero or several sliceable locals serves the inventory instead: seed_vars= counts the locals that line "
            "names, and each candidate <v> row carries seed=\"1\" so the caller can pick a :VAR and re-run. -->";
    }

    if( flow != nullptr )
    {
        out +=
            "<!-- slice-flow: TRANSITIVE cross-statement data-flow slice — bounded BFS from the seed variable over "
            "reaching-definition def-use edges (a use of a variable reaches the LAST definition of it in source order before it "
            "— the ARISE paper's own slicer semantics, arXiv:2605.03117; like the paper's, this slicer stops at the function "
            "boundary, the inter-procedural half being the callers/impact verbs). flow= is the direction: back = statements whose "
            "values feed the seed, fwd = statements the seed's value reaches, both = the union of the two walks (backward first, "
            "deduplicated). The seed variable's own rows are depth 0 and keep the v1 shape; every FLOW row adds v= the variable "
            "at that step, d= the BFS depth it was reached at, f= the line it was reached FROM. Flow rows order by (d=, l=, v=) "
            "— a stated contract, not a walk artifact. steps= counts flow rows; depth= is the bound in force (default "
            "8, set with slice-depth); flow_truncated= \"1\" means the bound suppressed at least one row — the slice is bounded "
            "here, NOT proven complete; its absence means the walk finished inside the bound. steps=\"0\" is a FLOOR like every "
            "other count here (counts_floor=\"1\"): it means no def-use edge was PROVABLE from this seed, never that the variable "
            "has no data flow. Its commonest cause is v1's receiver-mutation limit above — a variable whose only writes are method "
            "calls ON it (queue.push_back(x)) has no def for the walk to anchor on, so both directions return zero while the v1 "
            "rows still SHOW those lines, classified as reads. Read the rows, not just the count. EXTRA LIMITS on top of v1's: "
            "line-granular ROWS (a multi-statement line merges and may over-connect) over statement-anchored CHAINING (a "
            "statement spanning several lines chains as ONE unit keyed on its first line), and flow follows "
            "NAMES, not values — no alias analysis, no flow sensitivity beyond source order, shadowing may over-include. DATA dependence "
            "only on this run — no control dependence here: the guard (if/loop) deciding whether a def executes is not a row unless "
            "slice-guards asks for it (rung 3, off by default). -->";
    }

    if( scan.guardsComputed )
    {
        out +=
            "<!-- slice-guards: CONTROL dependence beside the data rows — for each emitted line, WHICH condition decides whether it "
            "executes (Ferrante/Ottenstein/Warren's program dependence graph, TOPLAS 1987, whose point is that the two dependences "
            "belong in one graph). Each <g> row is one DISTINCT deciding line, ordered by l= ascending and emitted after the <s> rows: "
            "l= the line the deciding construct begins on, k= if|loop|sw|cond|exit, n= how many emitted rows it decides, CDATA = that "
            "source line. guards= counts the <g> rows. TWO HALVES OF UNEQUAL STRENGTH, and which one you are reading matters: k=\"if\", "
            "\"loop\", \"sw\" and \"cond\" are the ENCLOSING-GUARD CHAIN — a syntactic ancestor walk, EXACT for goto-free structured "
            "code by construction; k=\"exit\" is the EARLY-EXIT APPROXIMATION — a row after `if( c ) return;` in the same block is "
            "treated as deciding on c, exact for that idiom and WRONG IN CORNERS (a break deep in nested loops deciding post-loop "
            "statements needs the control-flow graph and post-dominator tree this slicer deliberately does not build; such a guard is "
            "ABSENT, never wrong). guards_degraded=\"1\" fires when the definition's own AST shows the chain being defeated: a goto or "
            "a label (control can arrive from anywhere), a switch case that can fall through, a coroutine co_await/co_return/co_yield "
            "(resumption is the scheduler's), __try/__except, or a #if/#ifdef inside the span (the parse in hand is ONE carved "
            "branch). What no AST read can see is disclosed only here, and is why guard rows are FLOORS under counts_floor=\"1\": "
            "macro-hidden control flow (a macro expanding to if/return parses as a plain call), a call that may THROW (exceptional "
            "edges need the callee's body), and a noreturn callee (exit/abort/longjmp falsify post-dominance silently). An absent "
            "guard row means \"none proved\", NEVER \"this line runs unconditionally\". Scope: a return inside a nested "
            "lambda/closure exits the LAMBDA, so it never becomes an outer-function exit, and outer exits never reach into a closure "
            "body. The measured claim is C-family only (docs/EVALS.md); other served families emit rows off the same walk. -->";
    }

    // ── rung 3: fold the per-line control edges into the DISTINCT deciding lines of THIS emission ──────
    // Computed before the root because guards= is a root attribute. The guarded set is exactly the lines
    // this invocation emits — the seed's own rows plus, when a flow ran, its rows — so composing the two
    // rungs widens the guard set rather than producing a second, disagreeing one.
    struct GuardRowOut
    {
        std::uint32_t guardLine = 0;
        GuardK        k         = GuardK::If;
        std::uint32_t n         = 0;   // how many emitted rows this line decides
    };
    std::vector<GuardRowOut> guardRows;
    if( scan.guardsComputed && !varName.empty() )
    {
        std::vector<std::uint32_t> emitted;
        for( const SliceLineRow& r : sliceFoldLines( scan.occ ) )
        {
            emitted.push_back( r.line );
        }
        if( flow != nullptr )
        {
            for( const SliceFlowRow& fr : flow->rows )
            {
                emitted.push_back( flow->vars[ fr.varIdx ].rows[ fr.rowIdx ].line );
            }
        }
        std::sort( emitted.begin(), emitted.end() );
        emitted.erase( std::unique( emitted.begin(), emitted.end() ), emitted.end() );

        for( std::uint32_t line : emitted )
        {
            for( const SliceGuardEdge& e : scan.guards )
            {
                if( e.line != line )
                {
                    continue;
                }
                bool merged = false;
                for( GuardRowOut& g : guardRows )
                {
                    if( g.guardLine == e.guardLine && g.k == e.k )
                    {
                        ++g.n;
                        merged = true;
                    }
                }
                if( !merged )
                {
                    guardRows.push_back( GuardRowOut{ e.guardLine, e.k, 1 } );
                }
            }
        }
        // the stated order: (l=, k=) ascending — a contract, not a walk artifact, like the flow rows'
        std::sort( guardRows.begin(), guardRows.end(), []( const GuardRowOut& a, const GuardRowOut& b )
                   { return a.guardLine != b.guardLine ? a.guardLine < b.guardLine : std::uint8_t( a.k ) < std::uint8_t( b.k ); } );
    }

    out += "<slice sym=\"";  out += ex( s.name );
    out += "\" p=\"";        out += ex( rw::sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix ) );
    out += ":";              out += std::to_string( s.line );
    out += "\" t=\"";        out += symTag( s.kind );
    out += "\" lang=\"";     out += langTag( s.lang );
    out += "\"";

    if( seedInfo != nullptr )
    {
        out += " seed=\"" + ex( seedInfo->spec ) + "\"";   // the seed in force, before the mode attributes it steered
    }

    if( varName.empty() )
    {
        out += " vars=\"" + std::to_string( scan.locals.size() ) + "\"";
        if( seedInfo != nullptr )
        {
            out += " seed_vars=\"" + std::to_string( seedInfo->seedVarCount ) + "\"";
        }
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
        if( seedInfo != nullptr && seedInfo->varFromSeed )
        {
            out += " var_from=\"seed\"";
        }
        if( flow != nullptr )
        {
            out += " flow=\"";
            out += flowSpec->dir == SliceFlowDir::Back ? "back" : flowSpec->dir == SliceFlowDir::Fwd ? "fwd" : "both";
            out += "\" depth=\"" + std::to_string( flowSpec->bound ) + "\" steps=\"" + std::to_string( flow->rows.size() ) + "\"";
            if( flow->truncated )
            {
                out += " flow_truncated=\"1\"";
            }
        }
        if( scan.guardsComputed )
        {
            out += " guards=\"" + std::to_string( guardRows.size() ) + "\"";
            if( scan.guardDegrade.any() )
            {
                // ONE bit, not five: the legend enumerates the reasons, and a per-reason attribute would
                // invite reading the absent ones as "cleared" — which the invisible defeaters forbid
                out += " guards_degraded=\"1\"";
            }
        }
    }

    // at= then root=, appended after every pre-existing attribute — the --edit-check placement rule.
    // counts_floor= goes LAST of all (graphlegend.h's own placement rule) so no attribute-ADJACENCY
    // assertion in test/ can break on it: defs=/uses=/vars=/steps= are floors for the same reason the
    // graph verbs' counts are — the classification is name-based, and receiver mutation is not a def.
    out += gitstamp::atAttr( root );
    out += " root=\"";  out += ex( root );  out += "\"";
    out += kGraphCountFloorAttrXml;
    out += ">";

    if( varName.empty() )
    {
        // the inventory. sliceWalk pushes in AST (≈ source) order; sort by (first-def line, name) so the
        // order is a stated contract, not a walk artifact.
        std::vector<SliceLocal> ordered = scan.locals;
        std::sort( ordered.begin(), ordered.end(), []( const SliceLocal& a, const SliceLocal& b )
                   { return a.line != b.line ? a.line < b.line : a.name < b.name; } );
        for( const SliceLocal& lv : ordered )
        {
            out += "<v n=\"" + ex( lv.name ) + "\" l=\"" + std::to_string( lv.line ) + "\" t=\"" + occTag( lv.t ) + "\"";
            if( seedInfo != nullptr
                && std::find( seedInfo->seedVars.begin(), seedInfo->seedVars.end(), lv.name ) != seedInfo->seedVars.end() )
            {
                out += " seed=\"1\"";   // a candidate the seed line names — the pick a :VAR re-run would make explicit
            }
            out += "/>";
        }
    }
    else
    {
        // the CDATA tail every row shares: the trimmed statement line, redacted and made ]]>-safe.
        // `tag` closes it — the guard rows below are a different element carrying the same payload, and
        // one emitter for both is what keeps the redaction seam single (a second copy is a second bug).
        const auto rowTailAs = [ & ]( std::uint32_t line, const char* tag )
        {
            const auto [ lineStart, lineEnd ] = lineSpanOf( line );
            std::string text( src, lineStart, lineEnd - lineStart );
            // trim — the row's l= carries the position; leading indentation is dead bytes (G4)
            const std::size_t first = text.find_first_not_of( " \t\r" );
            const std::size_t last  = text.find_last_not_of( " \t\r" );
            text = ( first == std::string::npos ) ? std::string() : text.substr( first, last - first + 1 );
            redactInPlace( text, redact );                      // a body-emission seam — same rule as packOutline
            out += "><![CDATA[";
            std::string safe;
            safe.reserve( text.size() );
            appendCdataSafe( text, safe );                      // split ]]>, scrub C0 controls + invalid UTF-8
            out += safe;
            out += "]]></";
            out += tag;
            out += ">";
        };
        const auto rowTail = [ & ]( std::uint32_t line ) { rowTailAs( line, "s" ); };

        // the seed variable's rows — the v1 emission, byte-stable with or without a flow
        // (occ is already line-ascending — the walk is a pre-order pass over one file's AST)
        for( const SliceLineRow& r : sliceFoldLines( scan.occ ) )
        {
            out += "<s l=\"" + std::to_string( r.line ) + "\" k=\"";
            out += r.hasDef && r.hasUse ? "both" : r.hasDef ? "def" : "use";
            out += "\" t=\"";
            out += occTag( r.t );
            out += "\"";
            rowTail( r.line );
        }

        // the flow rows, (d=, l=, v=)-ordered — same element, three extra attributes
        if( flow != nullptr )
        {
            for( const SliceFlowRow& fr : flow->rows )
            {
                const SliceVarRows& v = flow->vars[ fr.varIdx ];
                const SliceLineRow& r = v.rows[ fr.rowIdx ];
                out += "<s l=\"" + std::to_string( r.line ) + "\" k=\"";
                out += r.hasDef && r.hasUse ? "both" : r.hasDef ? "def" : "use";
                out += "\" t=\"";
                out += occTag( r.t );
                out += "\" v=\"" + ex( v.name ) + "\" d=\"" + std::to_string( fr.d ) + "\" f=\"" + std::to_string( fr.from ) + "\"";
                rowTail( r.line );
            }
        }

        // the guard rows (rung 3), l= ascending, AFTER every data row: a distinct element because a
        // control edge is not a def-use row, and one row per DISTINCT deciding line because the same
        // `if` guarding eight slice lines is one fact, not eight (G4). n= carries the weight the
        // deduplication would otherwise throw away.
        for( const GuardRowOut& g : guardRows )
        {
            out += "<g l=\"" + std::to_string( g.guardLine ) + "\" k=\"";
            out += guardTag( g.k );
            out += "\" n=\"" + std::to_string( g.n ) + "\"";
            rowTailAs( g.guardLine, "g" );
        }
    }

    out += "</slice>";
    return out;
}

}   // namespace slicev
}   // namespace rw
