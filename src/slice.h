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
//     not dependence-ordered).
//   • BLOCK SCOPES ARE SEPARATED (2026-09-02, audit F-02) — a name declared twice in one definition is
//     two variables; each occurrence binds to the innermost enclosing scope whose declaration precedes
//     it, and the flow walk never chains into a sibling block's shadow. Rows of a shadowed name carry
//     b= (the binding's declaration line), the root bindings=. Python is function-scoped (one binding).
//   • A WRITE HIDDEN BEHIND A CALL IS NOT A DEF — a write a callee performs through the variable
//     (`v.push_back(x)`, `buf.append(s)`) classifies as a READ, and a write a callee or macro performs
//     through an ARGUMENT (a by-reference/pointer parameter, an out-parameter, a function-like macro)
//     classifies as a CALL-ARG use (widened 2026-09-02, audit F-12), because proving either writes needs
//     the receiver's TYPE, the callee's SIGNATURE and BODY, or the macro's expansion, and this slicer has
//     none of them. Registered as a DECISION, not an oversight, and
//     measured before it was registered (2026-08-31, docs/EVALS.md "Receiver mutation as a slice
//     definition"): across ripwire's own src/ and ugrep @550599a6, 79.1% of receiver call sites on
//     these variables are not mutations at all, and of the ones that are, `reserve` (capacity, never
//     value) and `clear`/`pop_back` (no incoming value) dominate — so a curated method-name rule would
//     mint far more false defs than true ones. A false def is strictly worse than an absent one here:
//     sliceFlowExpandFwd breaks on the next def, so a fabricated def SUPPRESSES the reach of the real
//     def before it. The cost is paid in the legend instead, and every count carries counts="as-classified"
//     (kSliceCountsAttrXml) — not counts_floor=, because a slice count over-includes as well.
//   • PREPROCESSOR RULE (C-family) — `#if 0` bodies and the `#else` of `#if 1` are dropped (preproc_rows=
//     discloses the count); every other conditional region is build-dependent, kept and flagged pp="1",
//     and a pp def never kills the reach of the unconditional def before it. See SlicePp below.
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

// THE COUNT MARKER. Every <slice> root carries counts="as-classified", appended LAST like the graph
// verbs' counts_floor= — and deliberately not that marker: a floor promises true >= reported, and a
// slice count breaks that promise in BOTH directions (defs= misses a write hidden behind a call; defs=
// over-counts a build-dependent pp row or a same-spelled member the grammar exposes as an identifier).
// The numbers are exact counts of what the name-based classifier rowed, and the legend says so.
inline constexpr const char* kSliceCountsAttrXml = " counts=\"as-classified\"";

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

// t= vocabulary, in PRIORITY order (a line holding several occurrence roles reports the smallest value).
// Global/Nonlocal are Python's scope statements: neither a def nor a use (k="scope"), weakest of all.
enum class OccT : std::uint8_t { Param = 0, Decl = 1, Assign = 2, CallArg = 3, Read = 4, Global = 5, Nonlocal = 6 };

// declarative table over a switch (G2's constexpr-table rule — also what keeps this from cloning the
// shapeName/styleTag/statusName switch skeleton QD flagged on the first cut), indexed by the enum value
inline constexpr const char* kOccTagNames[] = { "param", "decl", "assign", "call-arg", "read", "global", "nonlocal" };
static_assert( std::size( kOccTagNames ) == std::size_t( OccT::Nonlocal ) + 1 );

inline bool sliceIsScopeStatementRole( OccT t ) noexcept
{
    return t == OccT::Global || t == OccT::Nonlocal;
}

inline const char* occTag( OccT t ) noexcept
{
    const std::size_t occIndex = std::size_t( t );
    return kOccTagNames[ occIndex < std::size( kOccTagNames ) ? occIndex : std::size( kOccTagNames ) - 1 ];
}

// "no declaration inside the definition binds this occurrence" — an outer/global name, or a use that
// precedes its declaration; rows of such an occurrence print b="0" when the name is shadowed
inline constexpr std::uint32_t kSliceUnbound = 0xFFFFFFFFu;

struct SliceOcc
{
    std::uint32_t line       = 0;    // 1-based
    std::uint32_t stmtLine   = 0;    // 1-based FIRST line of the enclosing statement — the flow-chaining anchor
                                     //   (a statement spanning lines via continuation is ONE unit; 0 = fall back to line)
    std::uint32_t byte       = 0;    // file-absolute start byte — the scope-resolution key
    std::uint32_t bindingIdx = kSliceUnbound;   // index into SliceScan::bindings, resolved after the walk
    OccT          t          = OccT::Read;
    bool          isDef      = false;
    bool          isUse      = false;
    bool          skip       = false;   // a non-occurrence (e.g. a Python keyword-argument NAME) — never emitted
    bool          pp         = false;   // inside a BUILD-DEPENDENT preprocessor region (#ifdef/#ifndef/#if EXPR) — kept, flagged pp="1"
};

// one VARIABLE: a declaration and the scope it is visible in. A name declared twice in one definition
// is two of these, and rows/flow are keyed per binding, never per name (block-scope separation below).
struct SliceBinding
{
    std::string   name;
    std::uint32_t declLine    = 0;    // the b= value — the line of the declaration
    std::uint32_t visibleFrom = 0;    // byte the binding is visible from (its own initializer excluded for Go/Rust)
    std::uint32_t scopeStart  = 0;    // [scopeStart, scopeEnd): the innermost scope-creating node enclosing the declaration
    std::uint32_t scopeEnd    = 0;
    OccT          t           = OccT::Decl;
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

struct SliceScan
{
    bool                       parseOk = false;   // grammar present + file parsed + span located
    std::vector<SliceOcc>      occ;               // VAR-mode occurrences, source order (empty when var empty)
    std::vector<SliceLocal>    locals;            // the sliceable-locals NAMES, first-def order (refusal text, seed pick)
    std::vector<SliceBinding>  bindings;          // the sliceable-locals inventory, one per VARIABLE (a shadowed name lists twice)
    std::vector<SliceNamedOcc> all;               // EVERY classified occurrence, source order (flow substrate)
    std::vector<SliceNamedOcc> dropped;           // occurrences inside a preprocessor-DEAD region — never rows; preproc_rows= counts their lines
};

// how many distinct bindings the occurrences of `name` fall into (an unbound group counts as one) —
// >1 means the name is shadowed and its rows carry b=
inline std::size_t sliceBindingGroupsOf( const SliceScan& scan, std::string_view name )
{
    std::vector<std::uint32_t> seen;
    for( const SliceNamedOcc& no : scan.all )
    {
        if( no.name == name && std::find( seen.begin(), seen.end(), no.occ.bindingIdx ) == seen.end() )
        {
            seen.push_back( no.occ.bindingIdx );
        }
    }
    return seen.size();
}

inline std::uint32_t sliceBindingLine( const SliceScan& scan, std::uint32_t bindingIdx ) noexcept
{
    return bindingIdx == kSliceUnbound ? 0u : scan.bindings[ bindingIdx ].declLine;
}

// tree-sitter micro-helpers, in the house spelling
inline bool sliceKindIs( TSNode n, const char* kind ) noexcept
{
    return std::strcmp( ts_node_type( n ), kind ) == 0;
}

// ── preprocessor-conditional regions (C-family only) ─────────────────────────────────────────────────
//
// tree-sitter-c/cpp parse `#if`/`#ifdef` blocks inside a body as preproc_if / preproc_ifdef nodes whose
// direct children are the guarded statements and whose `alternative` field is the `#else` / `#elif` /
// `#elifdef` chain. A lexical walk that ignores them reads a def under `#if 0` as a real def, and because
// the flow walk stops at the NEXT def, that dead def then REPLACES the live chain (audit 2026-09-02,
// F-01: `--slice=if0:w --slice-flow=back` returned only `v = 111;` from inside `#if 0`).
//
// THE RULE, exactly as the legend states it:
//   • DECIDED — the literal conditions. `#if 0`'s body and the `#else` of `#if 1` are DEAD: their rows are
//     dropped and counted on the root as preproc_rows=. `#if 1`'s body and the `#else` of `#if 0` are
//     LIVE and unmarked. Only the bare literal decides (`#if (0)` is an expression, see below).
//   • UNDECIDED — everything else: `#ifdef X`, `#ifndef X`, `#elifdef`, `#if defined(X)`, `#if EXPR`,
//     `#elif`. Whether X is defined belongs to the BUILD (-DNDEBUG, -DHAVE_FOO), not to the file; "the
//     file never #defines X" is exactly the shape of a build-defined macro, so it is not evidence of
//     dead code. These rows are KEPT and flagged pp="1", and a pp def does not kill the reach of the
//     unconditional def before it in the flow walk — both are emitted, so the worst case is an extra
//     flagged row, never a replaced chain.
//   • A region that ENCLOSES the whole definition is not considered (the definition exists as indexed;
//     an include guard wraps every function in a header). Only conditionals starting inside the span.
//   • Condition text (`#ifdef NAME`, `#if defined(X)`) is never an occurrence: macro names are not
//     variables.
enum class SlicePp : std::uint8_t { Live = 0, Undecided = 1, Dead = 2 };

inline bool sliceIsPreprocConditional( TSNode n ) noexcept
{
    return sliceKindIs( n, "preproc_if" ) || sliceKindIs( n, "preproc_ifdef" ) || sliceKindIs( n, "preproc_elif" )
           || sliceKindIs( n, "preproc_elifdef" ) || sliceKindIs( n, "preproc_else" );
}

// the states of (this node's own body, its `alternative` chain), folded under the enclosing state —
// dead dominates, undecided survives a live inner literal, live never lifts an outer undecided
inline std::pair<SlicePp, SlicePp> slicePreprocBranchStates( TSNode n, std::string_view src, SlicePp enclosing ) noexcept
{
    SlicePp body = SlicePp::Undecided, alt = SlicePp::Undecided;
    if( sliceKindIs( n, "preproc_else" ) )
    {
        body = SlicePp::Live;   // the caller already folded the chain's state into `enclosing`
        alt  = SlicePp::Live;
    }
    else if( sliceKindIs( n, "preproc_if" ) || sliceKindIs( n, "preproc_elif" ) )
    {
        const TSNode cond = ts_node_child_by_field_name( n, "condition", 9 );
        if( !ts_node_is_null( cond ) && sliceKindIs( cond, "number_literal" ) )
        {
            const std::uint32_t a = ts_node_start_byte( cond ), b = ts_node_end_byte( cond );
            const std::string_view text = ( b > a && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view();
            if( text == "0" )      { body = SlicePp::Dead;  alt = SlicePp::Live; }
            else if( text == "1" ) { body = SlicePp::Live;  alt = SlicePp::Dead; }
        }
    }
    const auto fold = []( SlicePp outer, SlicePp inner ) noexcept { return std::uint8_t( outer ) > std::uint8_t( inner ) ? outer : inner; };
    return { fold( enclosing, body ), fold( enclosing, alt ) };
}

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

// the JS/TS destructuring wrappers an identifier climbs through to reach its declarator
inline bool sliceIsJsPatternKind( TSNode n ) noexcept
{
    return sliceKindIs( n, "object_pattern" ) || sliceKindIs( n, "array_pattern" ) || sliceKindIs( n, "pair_pattern" )
           || sliceKindIs( n, "object_assignment_pattern" ) || sliceKindIs( n, "assignment_pattern" ) || sliceKindIs( n, "rest_pattern" );
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

// JS/TS: the BINDER shapes, destructured or plain. Climbs the pattern wrappers to the binding site, so
// `const { x, y: yy, z = 3, ...rest } = o`, `const [ a, b ] = o`, `function f({ p }, [ q ])`,
// `for (const { k } of o)` and `({ x } = o)` all bind their names (audit 2026-09-02, F-08: they minted
// nothing). The side that never binds — a pair_pattern's KEY (a property name, or a computed-key
// expression) and a default's RIGHT side — is a read and returns false for the caller to fall through.
inline bool sliceClassifyJsBinder( TSNode n, TSNode p, const char* pk, SliceOcc& o ) noexcept
{
    TSNode      d  = n;
    TSNode      pp = p;
    const char* dk = pk;
    while( !ts_node_is_null( pp ) && sliceIsJsPatternKind( pp ) )
    {
        if( ( std::strcmp( dk, "pair_pattern" ) == 0 && !sliceInField( pp, "value", d ) )
            || ( ( std::strcmp( dk, "object_assignment_pattern" ) == 0 || std::strcmp( dk, "assignment_pattern" ) == 0 ) && !sliceInField( pp, "left", d ) ) )
        {
            return false;   // the key / default side: a read
        }
        d  = pp;
        pp = ts_node_parent( pp );
        dk = ts_node_is_null( pp ) ? "" : ts_node_type( pp );
    }
    if( ts_node_is_null( pp ) )
    {
        return false;
    }
    // identity when n sits directly in the field (`arr[i] = …` must not def i), containment once a
    // pattern was climbed (the field then holds the pattern, not the identifier)
    const bool climbed = !ts_node_eq( d, n );
    const auto inField = [ & ]( const char* field ) noexcept { return climbed ? sliceInField( pp, field, d ) : sliceIsField( pp, field, n ); };
    const auto def     = [ & ]( OccT t ) noexcept { o.t = t;  o.isDef = true;  return true; };
    if( std::strcmp( dk, "variable_declarator" ) == 0 && inField( "name" ) )
    {
        return def( OccT::Decl );      // let count = 0;   const { x } = o;
    }
    if( std::strcmp( dk, "formal_parameters" ) == 0 )
    {
        return def( OccT::Param );     // function f(count)   f({ p }, [ q ])   f(count = 0)
    }
    if( ( std::strcmp( dk, "required_parameter" ) == 0 || std::strcmp( dk, "optional_parameter" ) == 0 ) && inField( "pattern" ) )
    {
        return def( OccT::Param );     // TS: (count: number)   ({ p }: T)
    }
    if( std::strcmp( dk, "assignment_expression" ) == 0 && inField( "left" ) )
    {
        return def( OccT::Assign );    // count = …   ({ x } = o)
    }
    if( std::strcmp( dk, "for_in_statement" ) == 0 && inField( "left" ) )
    {
        return def( OccT::Decl );      // for (x of xs)   for (const { k } of xs)
    }
    if( std::strcmp( dk, "catch_clause" ) == 0 && inField( "parameter" ) )
    {
        return def( OccT::Decl );      // catch (e)   catch ({ message })
    }
    return false;
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
                if( std::strcmp( dk, "declaration" ) == 0 && !sliceInField( pp, "type", d ) && !sliceInField( pp, "value", d ) )
                {
                    def( OccT::Decl );  return o;      // int count;  — but not the `x` of `if( int k = x )`: tree-sitter-cpp's
                }                                      //   condition-clause declaration carries its initializer in a `value` field
                                                       //   with no init_declarator, and that x is a READ (a false def here became a
                                                       //   false binding once block scopes were separated, 2026-09-02)
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
            if( std::strcmp( pk, "global_statement" ) == 0 )
            {
                o.t = OccT::Global;  return o;         // global X — a scope declaration: neither a read nor a write (k="scope")
            }
            if( std::strcmp( pk, "nonlocal_statement" ) == 0 )
            {
                o.t = OccT::Nonlocal;  return o;       // nonlocal X — same
            }
            if( std::strcmp( pk, "argument_list" ) == 0 )
            {
                use( OccT::CallArg );  return o;
            }
            break;
        }

        case SliceFam::Js:
        {
            if( sliceClassifyJsBinder( n, p, pk, o ) )
            {
                return o;                              // a declarator / parameter / for-of / assignment binder, destructured or plain
            }
            if( std::strcmp( pk, "augmented_assignment_expression" ) == 0 && sliceIsField( p, "left", n ) )
            {
                both( OccT::Assign );  return o;       // count += n
            }
            if( std::strcmp( pk, "update_expression" ) == 0 )
            {
                both( OccT::Assign );  return o;       // count++
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

// membership of a node's kind in a nullptr-terminated kind row — the ONE loop the statement-container,
// scope-kind and JS-function-kind lookups share (a per-family row is a fixed-extent array; nullptr ends it early)
inline bool sliceKindInTable( TSNode n, const char* const* table, std::size_t extent ) noexcept
{
    for( std::size_t kindIndex = 0; kindIndex < extent && table[ kindIndex ] != nullptr; ++kindIndex )
    {
        if( sliceKindIs( n, table[ kindIndex ] ) )
        {
            return true;
        }
    }
    return false;
}

inline bool sliceIsStmtContainer( TSNode n, SliceFam fam ) noexcept
{
    return fam != SliceFam::None && sliceKindInTable( n, kSliceStmtContainers[ std::size_t( fam ) ], std::size( kSliceStmtContainers[ 0 ] ) );
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

// ── block-scope separation (audit 2026-09-02, F-02) ──────────────────────────────────────────────────
//
// A name declared more than once inside one definition is that many VARIABLES. Every introducing
// occurrence (param / decl / Python assign) creates a SliceBinding whose scope is the innermost
// scope-creating ancestor of the declaration inside the span (the definition itself when none), and
// every other occurrence binds to the innermost enclosing scope whose declaration of the name precedes
// it — a post-walk pass (sliceResolveBindings), so the walk stays one pre-order pass. Before this the
// flow walk chained `int r = v;` into a sibling block's `int v = 7;` and never reached the outer
// declaration or the parameter: a chain through a variable r does not read.
//
// Per-family scope kinds, verified against the vendored parser.c of each grammar. Python has NO block
// scope (function-scoped by the language; comprehension/lambda scopes are not separated here), so its
// row is empty and every Python binding spans the definition. JS `var` is function-scoped (hoisting),
// so a var binding climbs to the nearest function kind instead (kSliceJsFunctionKinds).
inline constexpr const char* kSliceScopeKinds[ std::size_t( SliceFam::None ) ][ 14 ] =
{
    /* C    */ { "compound_statement", "for_statement", "for_range_loop", "if_statement", "switch_statement", "while_statement", "do_statement",
                 "catch_clause", "lambda_expression", "function_definition", nullptr, nullptr, nullptr, nullptr },
    /* Py   */ { nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr },
    /* Js   */ { "statement_block", "for_statement", "for_in_statement", "catch_clause", "switch_body", "function_declaration", "function_expression",
                 "arrow_function", "generator_function", "generator_function_declaration", "method_definition", nullptr, nullptr, nullptr },
    /* Go   */ { "block", "for_statement", "if_statement", "expression_switch_statement", "type_switch_statement", "select_statement", "expression_case",
                 "default_case", "type_case", "communication_case", "func_literal", "function_declaration", "method_declaration", nullptr },
    /* Java */ { "block", "for_statement", "enhanced_for_statement", "catch_clause", "lambda_expression", "switch_block", "method_declaration",
                 "constructor_declaration", "try_with_resources_statement", nullptr, nullptr, nullptr, nullptr, nullptr },
    /* Rust */ { "block", "for_expression", "while_expression", "if_expression", "match_arm", "closure_expression", "function_item",
                 nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr },
};

inline constexpr const char* kSliceJsFunctionKinds[] = { "function_declaration", "function_expression", "arrow_function", "generator_function",
                                                         "generator_function_declaration", "method_definition" };

inline bool sliceIsScopeKind( TSNode n, SliceFam fam ) noexcept
{
    return fam != SliceFam::None && sliceKindInTable( n, kSliceScopeKinds[ std::size_t( fam ) ], std::size( kSliceScopeKinds[ 0 ] ) );
}

inline bool sliceIsJsFunctionKind( TSNode n ) noexcept
{
    return sliceKindInTable( n, kSliceJsFunctionKinds, std::size( kSliceJsFunctionKinds ) );
}

// JS: `var x` (variable_declaration) is function-scoped; `let`/`const` (lexical_declaration) block-scoped
inline bool sliceJsIsVarBinding( TSNode declIdent ) noexcept
{
    TSNode cur = ts_node_parent( declIdent );
    while( !ts_node_is_null( cur ) && sliceIsJsPatternKind( cur ) )
    {
        cur = ts_node_parent( cur );
    }
    if( ts_node_is_null( cur ) || !sliceKindIs( cur, "variable_declarator" ) )
    {
        return false;
    }
    const TSNode decl = ts_node_parent( cur );
    return !ts_node_is_null( decl ) && sliceKindIs( decl, "variable_declaration" );
}

// [scopeStart, scopeEnd) of a declaration: the innermost scope-creating ancestor that starts inside the
// span, else the whole definition
inline std::pair<std::uint32_t, std::uint32_t> sliceScopeOf( TSNode declIdent, SliceFam fam, std::uint32_t spanStart, std::uint32_t spanEnd ) noexcept
{
    const bool fnScoped = fam == SliceFam::Js && sliceJsIsVarBinding( declIdent );
    TSNode     cur      = ts_node_parent( declIdent );
    while( !ts_node_is_null( cur ) && ts_node_start_byte( cur ) >= spanStart )
    {
        const bool isScope = fnScoped ? sliceIsJsFunctionKind( cur ) : sliceIsScopeKind( cur, fam );
        if( isScope )
        {
            return { ts_node_start_byte( cur ), ts_node_end_byte( cur ) };
        }
        cur = ts_node_parent( cur );
    }
    return { spanStart, spanEnd };
}

// the byte a binding is visible from. Go's `v := v + 1` / `var v = v + 1` and Rust's `let v = v + 1`
// read the PREVIOUS binding in their own initializer, so those climb to the end of the declaring
// statement; every other family binds from the identifier itself (C++'s point of declaration).
inline std::uint32_t sliceVisibleFrom( TSNode declIdent, SliceFam fam ) noexcept
{
    if( fam == SliceFam::Go || fam == SliceFam::Rust )
    {
        TSNode cur = ts_node_parent( declIdent );
        for( int hop = 0; hop < 4 && !ts_node_is_null( cur ); ++hop )
        {
            if( sliceKindIs( cur, "short_var_declaration" ) || sliceKindIs( cur, "var_spec" ) || sliceKindIs( cur, "let_declaration" ) )
            {
                return ts_node_end_byte( cur );
            }
            cur = ts_node_parent( cur );
        }
    }
    return ts_node_end_byte( declIdent );
}

// bind every non-introducing occurrence to the innermost enclosing scope whose declaration of the
// name precedes it (ties: the latest declaration — Rust re-`let`); none ⇒ kSliceUnbound
inline void sliceResolveBindings( SliceScan& scan )
{
    for( SliceNamedOcc& no : scan.all )
    {
        if( no.occ.bindingIdx != kSliceUnbound )
        {
            continue;   // an introducing occurrence binds where it was created
        }
        std::uint32_t best = kSliceUnbound;
        for( std::uint32_t bindingIndex = 0; bindingIndex < scan.bindings.size(); ++bindingIndex )
        {
            const SliceBinding& b = scan.bindings[ bindingIndex ];
            if( b.name != no.name || b.scopeStart > no.occ.byte || no.occ.byte >= b.scopeEnd || b.visibleFrom > no.occ.byte )
            {
                continue;
            }
            const bool inner = best == kSliceUnbound || b.scopeStart > scan.bindings[ best ].scopeStart
                               || ( b.scopeStart == scan.bindings[ best ].scopeStart && b.visibleFrom > scan.bindings[ best ].visibleFrom );
            if( inner )
            {
                best = bindingIndex;
            }
        }
        no.occ.bindingIdx = best;
    }
}

// ── the walk ─────────────────────────────────────────────────────────────────────────────────────────

// what every level of the walk reads and never writes
struct SliceWalkCtx
{
    std::uint32_t    spanStart = 0, spanEnd = 0;   // [sigStartByte, endByte) of the definition
    SliceFam         fam       = SliceFam::None;
    Lang             lang      = Lang::Unknown;
    std::string_view src;                          // the WHOLE file
    std::string_view selfName;                     // the definition's own name — never a local
};

// does this occurrence INTRODUCE its name? param / decl everywhere, assign where assignment is the
// declaration (Python), and a Python global/nonlocal statement (its own role), so the assignments after
// it bind to the scope statement rather than minting an unbound group
inline bool sliceIntroduces( const SliceOcc& c, SliceFam fam ) noexcept
{
    return ( c.isDef && ( c.t == OccT::Param || c.t == OccT::Decl || ( c.t == OccT::Assign && sliceAssignIntroduces( fam ) ) ) )
           || sliceIsScopeStatementRole( c.t );
}

// the binding an introducing occurrence creates — or, in the same scope, the one it re-declares (a Rust
// re-`let` in one block is a NEW binding; everywhere else a redeclaration is the same variable, and
// Python's every-assignment-introduces folds onto its first). Also keeps the name-deduped locals list.
inline std::uint32_t sliceBindIntroducer( SliceScan& scan, std::string_view text, TSNode node, const SliceWalkCtx& ctx, const SliceOcc& c )
{
    const auto [ scopeStart, scopeEnd ] = sliceScopeOf( node, ctx.fam, ctx.spanStart, ctx.spanEnd );
    std::uint32_t bindingIdx = kSliceUnbound;
    if( ctx.fam != SliceFam::Rust )
    {
        for( std::uint32_t bindingIndex = 0; bindingIndex < scan.bindings.size(); ++bindingIndex )
        {
            const SliceBinding& existing = scan.bindings[ bindingIndex ];
            if( existing.name == text && existing.scopeStart == scopeStart && existing.scopeEnd == scopeEnd )
            {
                bindingIdx = bindingIndex;
            }
        }
    }
    if( bindingIdx == kSliceUnbound )
    {
        bindingIdx = std::uint32_t( scan.bindings.size() );
        scan.bindings.push_back( SliceBinding{ std::string( text ), c.line, sliceVisibleFrom( node, ctx.fam ), scopeStart, scopeEnd, c.t } );
    }
    bool known = false;
    for( const SliceLocal& lv : scan.locals )
    {
        known = known || ( lv.name == text );
    }
    if( !known )
    {
        scan.locals.push_back( SliceLocal{ std::string( text ), c.line, c.t } );
    }
    return bindingIdx;
}

inline void sliceWalk( TSNode node, const SliceWalkCtx& ctx, SliceScan& scan, SlicePp pp );

// a preprocessor conditional STARTING inside the definition: decide (or refuse to decide) each branch,
// skip the condition text, and carry the state down — see SlicePp for the rule
inline void sliceWalkPreproc( TSNode node, const SliceWalkCtx& ctx, SliceScan& scan, SlicePp pp )
{
    const auto [ bodyState, altState ] = slicePreprocBranchStates( node, ctx.src, pp );
    const TSNode condition   = sliceField( node, "condition" );
    const TSNode macroName   = sliceField( node, "name" );
    const TSNode alternative = sliceField( node, "alternative" );
    const std::uint32_t ppChildCount = ts_node_child_count( node );
    for( std::uint32_t childIndex = 0; childIndex < ppChildCount; ++childIndex )
    {
        const TSNode child = ts_node_child( node, childIndex );
        if( ( !ts_node_is_null( condition ) && ts_node_eq( child, condition ) ) || ( !ts_node_is_null( macroName ) && ts_node_eq( child, macroName ) ) )
        {
            continue;   // macro names and #if expressions are never variable occurrences
        }
        const bool isAlt = !ts_node_is_null( alternative ) && ts_node_eq( child, alternative );
        sliceWalk( child, ctx, scan, isAlt ? altState : bodyState );
    }
}

// one occurrence node: classify, anchor, drop-or-flag by preprocessor state, bind if it introduces
inline void sliceWalkOccurrence( TSNode node, std::string_view text, const SliceWalkCtx& ctx, SliceScan& scan, SlicePp pp )
{
    SliceOcc c = sliceClassify( node, ctx.fam, ctx.src );
    if( c.skip )
    {
        return;
    }
    c.stmtLine = sliceStmtAnchorLine( node, ctx.fam );
    c.byte     = ts_node_start_byte( node );
    c.pp       = pp == SlicePp::Undecided;
    if( pp == SlicePp::Dead )
    {
        scan.dropped.push_back( SliceNamedOcc{ std::string( text ), c } );   // counted (preproc_rows=), never a row, never a local
        return;
    }
    if( sliceIntroduces( c, ctx.fam ) && text != ctx.selfName )
    {
        c.bindingIdx = sliceBindIntroducer( scan, text, node, ctx, c );
    }
    scan.all.push_back( SliceNamedOcc{ std::string( text ), c } );
}

// Recursive descent over the definition's span, collecting classified `identifier` occurrences.
// Depth-bounded only by the AST itself; a definition's subtree is small (one function).
inline void sliceWalk( TSNode node, const SliceWalkCtx& ctx, SliceScan& scan, SlicePp pp )
{
    const std::uint32_t a = ts_node_start_byte( node ), b = ts_node_end_byte( node );
    if( b <= ctx.spanStart || a >= ctx.spanEnd )
    {
        return;   // disjoint from the definition — prune the subtree
    }
    if( ctx.fam == SliceFam::C && a >= ctx.spanStart && sliceIsPreprocConditional( node ) )
    {
        sliceWalkPreproc( node, ctx, scan, pp );
        return;
    }

    // the C-family also yields variable occurrences dressed as type_identifier: the arguments of a
    // direct-initialization declaration under the most-vexing parse (see sliceIsDirectInitCtorArg);
    // JS/TS dress an object-pattern shorthand binder (`const { x } = o`) as its own node kind
    const bool occurrenceKind = sliceKindIs( node, "identifier" )
                                || ( ctx.fam == SliceFam::C && sliceKindIs( node, "type_identifier" ) && sliceIsDirectInitCtorArg( node ) )
                                || ( ctx.fam == SliceFam::Js && sliceKindIs( node, "shorthand_property_identifier_pattern" ) );
    if( occurrenceKind && a >= ctx.spanStart && b <= ctx.spanEnd && b <= ctx.src.size() && b > a )
    {
        const std::string_view text = ctx.src.substr( a, b - a );
        if( !sliceIsReservedName( text, ctx.lang ) )   // a keyword lexed as an identifier is a degraded-parse artifact, never a variable
        {
            sliceWalkOccurrence( node, text, ctx, scan, pp );
        }
        return;   // an identifier is a leaf — nothing beneath it
    }

    const std::uint32_t childCount = ts_node_child_count( node );
    for( std::uint32_t i = 0; i < childCount; ++i )
    {
        sliceWalk( ts_node_child( node, i ), ctx, scan, pp );
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

    SliceWalkCtx ctx;
    ctx.spanStart = sym.sigStartByte;
    ctx.spanEnd   = sym.endByte;
    ctx.fam       = fam;
    ctx.lang      = sym.lang;
    ctx.src       = src;
    ctx.selfName  = sym.name;
    sliceWalk( ts_tree_root_node( tree ), ctx, scan, SlicePp::Live );
    sliceResolveBindings( scan );
    for( const SliceNamedOcc& no : scan.all )
    {
        if( !varName.empty() && no.name == varName )
        {
            scan.occ.push_back( no.occ );   // the VAR-mode view: source order, every binding of the name (rows carry b= when >1)
        }
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
//   • name-based like v1 — no alias analysis; block scopes ARE separated since 2026-09-02 (a shadowed
//     name is several bindings, each walked on its own — see the scope-separation block);
//   • the seed is the whole variable inside ONE resolved definition (v1's addressing), not a
//     (file, line, variable) triple — the paper's line seed is recoverable by reading the d=0 rows.

// one aggregated row per LINE touching a variable: k= def|use|both, t= the strongest role (enum order
// IS the priority), CDATA = the trimmed statement line
struct SliceLineRow
{
    std::uint32_t line       = 0;
    bool          hasDef     = false;
    bool          hasUse     = false;
    OccT          t          = OccT::Read;
    bool          pp         = false;   // the line sits in a build-dependent preprocessor region (a line never straddles one)
    std::uint32_t bindingIdx = kSliceUnbound;   // a line touching TWO bindings of one name (Go `v := v + 1`) is two rows
};

// fold ONE occurrence into the row list — the single aggregation rule both the v1 seed rows and the
// flow substrate use, so the two can never disagree on what a line's k=/t=/pp=/b= is
inline void sliceFoldOcc( std::vector<SliceLineRow>& rows, const SliceOcc& o )
{
    if( rows.empty() || rows.back().line != o.line || rows.back().bindingIdx != o.bindingIdx )
    {
        rows.push_back( SliceLineRow{ o.line, false, false, o.t, false, o.bindingIdx } );   // seeded with the FIRST role, then min'd — Read is not the weakest any more
    }
    SliceLineRow& r = rows.back();
    r.hasDef = r.hasDef || o.isDef;
    r.hasUse = r.hasUse || o.isUse;
    r.pp     = r.pp || o.pp;
    if( std::uint8_t( o.t ) < std::uint8_t( r.t ) )
    {
        r.t = o.t;   // enum order IS the priority order
    }
}

// fold line-ascending occurrences into per-line rows
inline std::vector<SliceLineRow> sliceFoldLines( const std::vector<SliceOcc>& occ )
{
    std::vector<SliceLineRow> rows;
    for( const SliceOcc& o : occ )
    {
        sliceFoldOcc( rows, o );
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
    std::uint32_t             bindingIdx = kSliceUnbound;   // ONE binding of the name — a shadowed name is several of these
    std::vector<SliceLineRow> rows;                          // line-ascending
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

// the emitter's optional inputs, one struct so the two call sites (CLI, MCP) never grow positional
// nullptrs: a flow to render, a line seed to disclose, the compact legend tier
struct SliceEmitOpts
{
    const SliceFlowSpec* flow          = nullptr;
    const SliceSeedInfo* seed          = nullptr;
    bool                 compactLegend = false;   // --legend=compact: schema="ripwire.slice/v1", rows byte-identical
};

// the reaching definitions of vars[vi] at line L: the LAST unconditional def row strictly before L in
// source order (the paper's edge rule, at line grain) PLUS every build-dependent (pp) def row after it —
// a def the build may compile out cannot be allowed to hide the def it would otherwise replace, so both
// are reaching. Empty when no def precedes.
inline std::vector<std::size_t> sliceReachingDefs( const SliceVarRows& v, std::uint32_t line )
{
    std::vector<std::size_t> hits;
    for( std::size_t rowIndex = 0; rowIndex < v.rows.size() && v.rows[ rowIndex ].line < line; ++rowIndex )
    {
        if( !v.rows[ rowIndex ].hasDef )
        {
            continue;
        }
        if( !v.rows[ rowIndex ].pp )
        {
            hits.clear();   // an unconditional def kills every reach before it
        }
        hits.push_back( rowIndex );
    }
    return hits;
}

// the per-BINDING line folds, (name, binding)-ascending. scan.all is source-ordered, so a stable sort
// by that key keeps each binding's occurrences line-ascending for the fold. A variable here IS a
// binding: a shadowed name folds into two entries that the walk never confuses.
inline std::vector<SliceVarRows> sliceFoldVarRows( const SliceScan& scan )
{
    std::vector<SliceVarRows> vars;
    std::vector<std::uint32_t> order( scan.all.size() );
    for( std::uint32_t occIndex = 0; occIndex < order.size(); ++occIndex ) { order[ occIndex ] = occIndex; }
    std::stable_sort( order.begin(), order.end(), [ & ]( std::uint32_t a, std::uint32_t b )
    {
        const SliceNamedOcc& x = scan.all[ a ];
        const SliceNamedOcc& y = scan.all[ b ];
        return x.name != y.name ? x.name < y.name : x.occ.bindingIdx < y.occ.bindingIdx;
    } );
    for( std::uint32_t occIndex : order )
    {
        const SliceNamedOcc& no = scan.all[ occIndex ];
        if( vars.empty() || vars.back().name != no.name || vars.back().bindingIdx != no.occ.bindingIdx )
        {
            vars.push_back( SliceVarRows{ no.name, no.occ.bindingIdx, {} } );
        }
        sliceFoldOcc( vars.back().rows, no.occ );
    }
    return vars;
}

// the bounded BFS. Emission dedups per (var, line) row — first (shallowest) reach wins; in Both mode
// the backward walk runs first, so a row both directions reach keeps its backward depth. truncated
// flips only when the bound suppresses a NOVEL row — a bound that cuts nothing new is not a cut.

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
            if( vars[ varIndex ].name == no.name && vars[ varIndex ].bindingIdx == no.occ.bindingIdx ) { varIdx = varIndex; }
        }
        if( varIdx == std::size_t( -1 ) ) { continue; }   // unreachable — every folded (name, binding) has a var
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
            for( const std::size_t rd : sliceReachingDefs( vars[ useOcc.varIdx ], defOcc.anchor ) )
            {
                emitRow( useOcc.varIdx, rd, d + 1, line );
                enqueue( useOcc.varIdx, rd, d + 1 );
            }
        }
    }
}

// forward expansion of one DEF node: the def reaches every later use of the same variable up to (and
// including) its next UNCONDITIONAL redefinition (a build-dependent pp def is passed through — it may
// not be compiled); a reached STATEMENT that defines a variable carries the value onward — continuation
// lines included. A use inside the def's OWN statement (possible only when the statement spans lines)
// is the PREVIOUS def's reader, so it is skipped.
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
        if( r.hasDef && !r.pp ) { break; }   // the next UNCONDITIONAL def kills this def's reach; a build-dependent one may not exist
    }
}

inline SliceFlowOut sliceFlowCompute( const SliceScan& scan, std::string_view seedVar, SliceFlowDir dir, std::uint32_t bound )
{
    SliceFlowOut out;
    out.vars = sliceFoldVarRows( scan );
    const std::vector<SliceAnchorOcc> anchorOccs = sliceBuildAnchorOccs( scan, out.vars );

    // the seed is a NAME: every binding of it seeds (a shadowed name's bindings walk separately, each
    // from its own rows — none ever chains into the other's block)
    std::vector<std::size_t> seedIdxs;
    for( std::size_t varIndex = 0; varIndex < out.vars.size(); ++varIndex )
    {
        if( out.vars[ varIndex ].name == seedVar ) { seedIdxs.push_back( varIndex ); }
    }
    if( seedIdxs.empty() )
    {
        return out;   // the caller already refuses unknown seeds; belt and braces
    }
    out.seedFound = true;

    // emitted[v][r]: the row already IS in the slice (seed rows pre-count — they print as the d=0 block)
    std::vector<std::vector<bool>> emitted;
    emitted.reserve( out.vars.size() );
    for( const SliceVarRows& v : out.vars ) { emitted.push_back( std::vector<bool>( v.rows.size(), false ) ); }
    for( const std::size_t seedIdx : seedIdxs )
    {
        for( std::size_t rowIndex = 0; rowIndex < out.vars[ seedIdx ].rows.size(); ++rowIndex ) { emitted[ seedIdx ][ rowIndex ] = true; }
    }

    struct Node { std::uint32_t varIdx, rowIdx, d; };

    const auto walk = [ & ]( bool backward )
    {
        std::vector<std::vector<bool>> visited;
        visited.reserve( out.vars.size() );
        for( const SliceVarRows& v : out.vars ) { visited.push_back( std::vector<bool>( v.rows.size(), false ) ); }

        std::vector<Node> queue;
        for( const std::size_t seedIdx : seedIdxs )
        {
            for( std::size_t rowIndex = 0; rowIndex < out.vars[ seedIdx ].rows.size(); ++rowIndex )
            {
                if( out.vars[ seedIdx ].rows[ rowIndex ].hasDef )
                {
                    visited[ seedIdx ][ rowIndex ] = true;
                    queue.push_back( Node{ std::uint32_t( seedIdx ), std::uint32_t( rowIndex ), 0 } );
                }
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

    // the stated output order: (d, line, variable name, binding) ascending — a contract, not a walk artifact
    std::stable_sort( out.rows.begin(), out.rows.end(), [ & ]( const SliceFlowRow& a, const SliceFlowRow& b )
    {
        const std::uint32_t la = out.vars[ a.varIdx ].rows[ a.rowIdx ].line, lb = out.vars[ b.varIdx ].rows[ b.rowIdx ].line;
        if( a.d != b.d )  { return a.d < b.d; }
        if( la != lb )    { return la < lb; }
        if( out.vars[ a.varIdx ].name != out.vars[ b.varIdx ].name ) { return out.vars[ a.varIdx ].name < out.vars[ b.varIdx ].name; }
        return out.vars[ a.varIdx ].bindingIdx < out.vars[ b.varIdx ].bindingIdx;
    } );
    return out;
}

// ── the legend ───────────────────────────────────────────────────────────────────────────────────────
//
// Emitted by sliceBundleText, kept apart so the emitter's own control flow is about attributes and rows.
inline std::string sliceLegendText( const SliceEmitOpts& opts )
{
    const bool compactLegend = opts.compactLegend;
    const bool seeded        = opts.seed != nullptr;
    const bool flowing       = opts.flow != nullptr && opts.flow->out != nullptr;
    // THE LEGEND. Three tiers, one owner per rule (audit 2026-09-02, F-11: the flow run used to concatenate
    // two full LIMITS paragraphs restating each other, 88% of the bytes on a small slice):
    //   • v1 block — every rule of the slice, stated once, numbered so the flow block can point at it;
    //   • seed / flow blocks — only the vocabulary they add, never a v1 limit restated;
    //   • compact (--legend=compact, schema="ripwire.slice/v1") — attribute vocabulary only, one block, for
    //     the many-small-calls seed loop; the payload is byte-identical to the full form.
    std::string out;
    if( compactLegend )
    {
        out =
            "<!-- ripwire slice ripwire.slice/v1: name-based intra-procedural def-use rows of one variable in one definition. "
            "counts=as-classified — defs/uses/vars/steps count what the classifier rowed, neither floors nor totals. "
            "<s l k t [b] [pp]>: k=def|use|both|scope, t=param|decl|assign|call-arg|read|global|nonlocal, b=declaration line a "
            "shadowed name binds to (0=unbound), pp=1 build-dependent preprocessor region. Inventory <v n l t [seed]>, vars=count. "
            "bindings=shadow count; preproc_rows=lines dropped under #if 0; seed/var_from/seed_vars/seed=1 = line-seed disclosure. "
            "Flow rows add v=variable d=depth f=from-line; steps=flow rows, depth=bound, flow_truncated=1 bounded not complete. "
            "Limits: a write hidden behind a call (receiver mutation, by-ref/out-param, macro) rows as a use; no alias analysis; "
            "no control dependence; block scopes separated; C-family #if 0 dropped, other #if kept+flagged. Full legend: omit "
            "legend=compact (an XML comment cannot spell the flag with its dashes). -->";
    }
    else
    {
        out =
            "<!-- ripwire slice: NAME-BASED intra-procedural def-use slice of one variable inside ONE resolved definition (ARISE, "
            "arXiv:2605.03117). ROWS: one <s> per LINE touching VAR, source order — k= def|use|both|scope (both = the line writes AND "
            "reads it, `x += y`; scope = a Python global/nonlocal statement: neither read nor write, it introduces the name and "
            "never anchors a flow), t= the strongest role on the line (param > decl > assign > call-arg > read > global/nonlocal), CDATA "
            "= the trimmed line. Bare slice=SYM lists the sliceable locals: <v n= l= t=/> per BINDING at its declaration "
            "line, vars= their count. COUNTS: counts=\"as-classified\" — not the graph verbs' counts_floor= — defs=, uses=, vars= and "
            "steps= are exact counts of what this classifier ROWED, neither floors nor totals of the program's truth: LOW "
            "where a write hides behind a call (limit 2), HIGH where a rowed occurrence is not this variable's (a pp=\"1\" row, or a "
            "same-spelled member/attribute a grammar exposes as a bare identifier — Python/Java `o.v`). LIMITS, stated not implied: "
            "(1) no alias analysis — a pointer/reference alias is invisible; no flow sensitivity — rows are source-ordered. "
            "(2) A WRITE HIDDEN BEHIND A CALL IS NOT A DEF: receiver mutation (v.push_back(x), buf.append(s)) rows k=\"use\" t=\"read\", "
            "and a write through an ARGUMENT — a by-reference/pointer parameter, an out-parameter, a function-like macro (SETIT( m )) — "
            "rows k=\"use\" t=\"call-arg\", because proving either writes needs the callee's body or the macro's expansion, which "
            "this slicer lacks; a false def is worse than a missing one (the flow walk stops at the NEXT def), so it declines to guess "
            "— such a variable reports defs= as its introduction alone and a flow of steps=\"0\": no provable edge, not \"never "
            "written\". (3) BLOCK SCOPES ARE SEPARATED: a name declared more "
            "than once inside the definition is that many variables; an occurrence binds to the innermost enclosing scope whose "
            "declaration precedes it (blocks, loop/if/switch heads, catch clauses, lambdas/closures, per family; JS/TS let/const per "
            "block, var per function; Go `v := v+1` and Rust `let v = v+1` read the previous binding in their own initializer; Python "
            "is function-scoped — one binding per name, comprehension/lambda scopes not separated). A shadowed seed carries bindings= "
            "on the root and b= on every row — the "
            "declaration line it binds to; b=\"0\" = no declaration inside the definition binds it (an outer name, or a use before its "
            "declaration). (4) PREPROCESSOR (C-family): a conditional region starting inside the definition is decided only by its "
            "literal — the body of `#if 0` and the `#else` of `#if 1` are dead, their rows dropped and counted as preproc_rows= "
            "(absent when zero); every other conditional (`#ifdef`, `#ifndef`, `#if defined(X)`, `#if EXPR`, `#elif`) is "
            "build-dependent: its rows are kept and flagged pp=\"1\", and in a flow a pp def does not kill the reach of the "
            "unconditional def before it (both are emitted); macro names in directive text are never occurrences. (5) JS/TS "
            "destructuring binders (`const { x, y: yy, z = 3, ...rest } = o`, `[a, b] = arr`, destructured parameters, for-of "
            "patterns) are locals defined at the pattern line; a default's right side and a computed key are reads. "
            "(6) A reserved word is never an occurrence (a degraded-parse artifact); slicing one refuses like any unknown VAR. "
            "(7) Intra-procedural: rows never cross into callees/callers (callers/uses give that half). "
            "Served: C/C++/ObjC (+CUDA/Metal), Python, JS/TS, Go, Java, Rust — any other language refuses loudly, never an empty "
            "success. -->";

        if( seeded )
        {
            // conditional: the seed vocabulary costs zero bytes on an unseeded run (G4)
            out +=
                "<!-- slice-seed: LINE-SEEDED (FILE:LINE — ARISE's (file, line[, variable]) seed). seed= is the seed in force; the "
                "definition sliced is the innermost indexed one enclosing that line. var_from=\"seed\" = the seed line names exactly "
                "ONE sliceable local and var= is it — a pre-pick, disclosed, never a guess. Zero or several serve the inventory "
                "instead: seed_vars= counts the locals that line names, each candidate <v> carries seed=\"1\" — pick a :VAR and re-run. -->";
        }

        if( flowing )
        {
            // only what the flow ADDS — every v1 limit above applies unchanged and is not restated here
            out +=
                "<!-- slice-flow: TRANSITIVE cross-statement data-flow — bounded BFS from the seed variable over reaching-definition "
                "edges: a use reaches the LAST unconditional def of its variable before it in source order, plus any pp=\"1\" def "
                "after that one (the ARISE slicer's rule; stops at the function boundary like the paper's). flow= back = statements "
                "whose values feed the seed | fwd = statements the seed's value reaches | both = the union (backward first, "
                "deduplicated). Seed rows are depth 0 in the v1 shape; each FLOW row adds v= the variable at that step, d= its BFS "
                "depth, f= the line it was reached FROM (b= as in v1 when v= is shadowed); rows order by (d=, l=, v=). steps= counts "
                "flow rows; depth= is the bound in force (default 8, slice-depth sets it); flow_truncated=\"1\" = the bound suppressed "
                "at least one row — bounded here, not proven complete. steps=\"0\" = no PROVABLE edge from this seed — its commonest "
                "cause is limit (2): receiver mutation leaves no def to anchor on — read the rows, not just the count. EXTRA LIMITS: "
                "rows are line-granular (a multi-statement line merges and may over-connect) while chaining is statement-anchored (a "
                "statement spanning lines chains as ONE unit keyed on its first line); data dependence only — no control dependence: "
                "the guard (if/loop) deciding whether a def executes is never a row. -->";
        }
    }
    return out;
}

// ── XML assembly ─────────────────────────────────────────────────────────────────────────────────────

// the element BODY: the inventory (<v> per binding) or the seed rows + flow rows (<s> per line per
// binding). Kept apart from sliceBundleText so the emitter's own control flow is the root element.
inline void sliceEmitBody( std::string& out, const SliceScan& scan, std::string_view varName, const SliceFlowOut* flow,
                           const std::string& src, RedactCounts* redact, const SliceSeedInfo* seedInfo, std::size_t seedBindingGroups )
{
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

    if( varName.empty() )
    {
        // the inventory: one <v> per BINDING (a shadowed name lists once per declaration). sliceWalk
        // creates bindings in AST (≈ source) order; sort by (declaration line, name) so the order is a
        // stated contract, not a walk artifact.
        std::vector<SliceBinding> ordered = scan.bindings;
        std::sort( ordered.begin(), ordered.end(), []( const SliceBinding& a, const SliceBinding& b )
                   { return a.declLine != b.declLine ? a.declLine < b.declLine : a.name < b.name; } );
        for( const SliceBinding& lv : ordered )
        {
            out += "<v n=\"" + ex( lv.name ) + "\" l=\"" + std::to_string( lv.declLine ) + "\" t=\"" + occTag( lv.t ) + "\"";
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
        // the CDATA tail every row shares: the trimmed statement line, redacted and made ]]>-safe
        const auto rowTail = [ & ]( std::uint32_t line )
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
            out += "]]></s>";
        };

        // the seed variable's rows — the v1 emission, byte-stable with or without a flow
        // (occ is already line-ascending — the walk is a pre-order pass over one file's AST)
        for( const SliceLineRow& r : sliceFoldLines( scan.occ ) )
        {
            out += "<s l=\"" + std::to_string( r.line ) + "\" k=\"";
            out += r.hasDef && r.hasUse ? "both" : r.hasDef ? "def" : r.hasUse ? "use" : "scope";
            out += "\" t=\"";
            out += occTag( r.t );
            out += "\"";
            if( seedBindingGroups > 1 )
            {
                out += " b=\"" + std::to_string( sliceBindingLine( scan, r.bindingIdx ) ) + "\"";
            }
            if( r.pp )
            {
                out += " pp=\"1\"";   // LAST on the row, so no k=/t= adjacency assertion can break on it
            }
            rowTail( r.line );
        }

        // the flow rows, (d=, l=, v=)-ordered — same element, three extra attributes
        if( flow != nullptr )
        {
            // b= per flow variable: only a NAME with several bindings in this definition carries it
            std::vector<bool> shadowed;
            shadowed.reserve( flow->vars.size() );
            for( const SliceVarRows& v : flow->vars ) { shadowed.push_back( sliceBindingGroupsOf( scan, v.name ) > 1 ); }
            for( const SliceFlowRow& fr : flow->rows )
            {
                const SliceVarRows& v = flow->vars[ fr.varIdx ];
                const SliceLineRow& r = v.rows[ fr.rowIdx ];
                out += "<s l=\"" + std::to_string( r.line ) + "\" k=\"";
                out += r.hasDef && r.hasUse ? "both" : r.hasDef ? "def" : r.hasUse ? "use" : "scope";
                out += "\" t=\"";
                out += occTag( r.t );
                out += "\" v=\"" + ex( v.name ) + "\" d=\"" + std::to_string( fr.d ) + "\" f=\"" + std::to_string( fr.from ) + "\"";
                if( shadowed[ fr.varIdx ] )
                {
                    out += " b=\"" + std::to_string( sliceBindingLine( scan, v.bindingIdx ) ) + "\"";
                }
                if( r.pp )
                {
                    out += " pp=\"1\"";
                }
                rowTail( r.line );
            }
        }
    }

}

inline std::string sliceBundleText( const IngestResult& ing, const std::string& root, NodeId focus,
                                    std::string_view varName, const SliceScan& scan, const std::string& src,
                                    RedactCounts* redact, const SliceEmitOpts& opts = {} )
{
    const SliceFlowSpec* flowSpec      = opts.flow;
    const SliceSeedInfo* seedInfo      = opts.seed;
    const bool           compactLegend = opts.compactLegend;
    const SliceFlowOut*  flow          = flowSpec != nullptr ? flowSpec->out : nullptr;
    const Symbol&        s             = ing.symbols[ focus ];

    // R-E: same single-root root= condition every other verb uses (sarif.h); --slice refuses multi-root
    // before reaching here, so rootPrefix is always live.
    const std::string rootPrefix = rw::sarif::rootPrefixOf( root );
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view v ) -> std::string { return std::string( escapeXml( v, esc ) ); };

    std::string out = sliceLegendText( opts );

    out += "<slice sym=\"";  out += ex( s.name );
    out += "\" p=\"";        out += ex( rw::sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix ) );
    out += ":";              out += std::to_string( s.line );
    out += "\" t=\"";        out += symTag( s.kind );
    out += "\" lang=\"";     out += langTag( s.lang );
    out += "\"";
    if( compactLegend )
    {
        out += " schema=\"ripwire.slice/v1\"";   // the versioned compact dialect id, grep's placement (right after the identity attrs)
    }

    if( seedInfo != nullptr )
    {
        out += " seed=\"" + ex( seedInfo->spec ) + "\"";   // the seed in force, before the mode attributes it steered
    }

    // bindings= / b= arm only when the seed NAME is shadowed — an unshadowed slice is byte-identical
    const std::size_t seedBindingGroups = varName.empty() ? 0 : sliceBindingGroupsOf( scan, varName );

    if( varName.empty() )
    {
        out += " vars=\"" + std::to_string( scan.bindings.size() ) + "\"";
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
        if( seedBindingGroups > 1 )
        {
            out += " bindings=\"" + std::to_string( seedBindingGroups ) + "\"";
        }
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
    }

    // preproc_rows= — the LINES a preprocessor-dead region cost this answer: in VAR mode the seed
    // variable's dropped lines (the rows that would have printed), in inventory mode every dropped line
    // holding an occurrence. Absent when zero (the skipped verb's "absent means nothing was dropped").
    {
        std::vector<std::uint32_t> droppedLines;
        for( const SliceNamedOcc& no : scan.dropped )
        {
            if( ( varName.empty() || no.name == varName ) && std::find( droppedLines.begin(), droppedLines.end(), no.occ.line ) == droppedLines.end() )
            {
                droppedLines.push_back( no.occ.line );
            }
        }
        if( !droppedLines.empty() )
        {
            out += " preproc_rows=\"" + std::to_string( droppedLines.size() ) + "\"";
        }
    }

    // at= then root=, appended after every pre-existing attribute — the --edit-check placement rule.
    // counts= goes LAST of all (the graphlegend.h placement rule for its counts_floor= sibling) so no
    // attribute-ADJACENCY assertion in test/ can break on it. It is NOT counts_floor=: a slice count
    // over-includes (a pp row, a same-spelled member) as well as under-includes (a write hidden behind a
    // call), so "floor" was a false claim (audit 2026-09-02, F-03) — the marker says what the numbers ARE.
    out += gitstamp::atAttr( root );
    out += " root=\"";  out += ex( root );  out += "\"";
    out += kSliceCountsAttrXml;
    out += ">";

    sliceEmitBody( out, scan, varName, flow, src, redact, seedInfo, seedBindingGroups );

    out += "</slice>";
    return out;
}

}   // namespace slicev
}   // namespace rw
