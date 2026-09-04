#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_metrics.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_metrics.h — the per-definition structural metrics, moved VERBATIM from ingest.cpp in the
// 2026-08-29 split: cyclomatic complexity (Myers' &&/|| extension), cognitive complexity with its
// nesting/hump accounting, the O(children) child collection (ChildCursor/collectChildren), the
// essential-complexity ev(G) single-exit reduction (CtrlNode arena, EvCtx, the why-tag taxonomy),
// the local-variable-indexing walk (ln_*), the fused complexityOf DFS, and parameter/arity counting
// (countParams, cc_paramArityExact, callArity). Pure metric machinery: reads an AST, fills RawDef
// numbers, emits nothing. Same contract as every ingest_*.h: reopens `namespace rw` and the unnamed
// namespace inside it — one TU, one unnamed namespace, internal linkage unchanged, zero new API
// surface — under the RIPWIRE_INGEST_TU guard.

namespace rw
{

namespace
{

// ---- cyclomatic complexity: 1 + decision points in a def's subtree (Myers' &&/|| extension). ----
// Decision-point node types across our grammars (C++/Python/TS/Go/Rust/Swift + Ruby). Reported as a raw
// number (--metrics), never a gate — the map's distribution is the local baseline the agent reads against.
//
// `lang` exists for exactly ONE reason and the PHP/Lua port round added it: `do_statement` is a LOOP in
// the C family and a TRY in Swift (both decisions), but in Lua `do … end` is a bare SCOPE BLOCK — no
// condition, no branch. Counting it would not be a floor, it would be a wrong number, which is the one
// direction the honesty rule forbids. Every other language's answer is byte-identical to before the
// parameter existed (the Lua carve-out is the only place `lang` is read).
inline bool isDecisionType( const char* t, Lang lang ) noexcept
{
    return    std::strcmp( t, "if_statement" ) == 0       || std::strcmp( t, "if_expression" ) == 0
           || std::strcmp( t, "for_statement" ) == 0      || std::strcmp( t, "for_range_loop" ) == 0
           || std::strcmp( t, "for_in_statement" ) == 0   || std::strcmp( t, "for_expression" ) == 0
           || std::strcmp( t, "while_statement" ) == 0    || std::strcmp( t, "while_expression" ) == 0
           || ( std::strcmp( t, "do_statement" ) == 0 && lang != Lang::Lua ) || std::strcmp( t, "loop_expression" ) == 0
           // Lua: `repeat … until c` is a real post-test loop, and `elseif c then` is the flat +1 arm of
           // an if-chain (a SIBLING statement in this grammar, not a child clause, so cc_walk's else-if
           // flattening below never sees it and it must be counted here).
           || std::strcmp( t, "repeat_statement" ) == 0   || std::strcmp( t, "elseif_statement" ) == 0
           // PHP 8: each `match` arm is a decision, exactly like C#'s switch_expression_arm and Ruby's
           // `when`. `match_default_expression` is the fall-through arm and is deliberately NOT counted,
           // matching how a C-family `default:` label is not a decision.
           || std::strcmp( t, "match_conditional_expression" ) == 0
           || std::strcmp( t, "case_statement" ) == 0     || std::strcmp( t, "match_arm" ) == 0
           || std::strcmp( t, "expression_case" ) == 0    || std::strcmp( t, "communication_case" ) == 0
           || std::strcmp( t, "catch_clause" ) == 0       || std::strcmp( t, "except_clause" ) == 0
           || std::strcmp( t, "conditional_expression" ) == 0 || std::strcmp( t, "ternary_expression" ) == 0
           || std::strcmp( t, "boolean_operator" ) == 0    // Python `and`/`or`
           // Ruby (tree-sitter-ruby node kinds): block `if`/`elsif`/`unless`/`while`/`until`/`for`, the
           // trailing modifier forms (`x if a`), each `when`/`in_clause` arm, `rescue`, and the `? :`
           // `conditional`. Ruby's `case`/`case_match` head is a nesting container (see cc_isNestingControl),
           // NOT a decision — each `when`/`in_clause` arm is the decision, matching C-family case_statement.
           || std::strcmp( t, "if" ) == 0                 || std::strcmp( t, "elsif" ) == 0
           || std::strcmp( t, "unless" ) == 0             || std::strcmp( t, "while" ) == 0
           || std::strcmp( t, "until" ) == 0              || std::strcmp( t, "for" ) == 0
           || std::strcmp( t, "if_modifier" ) == 0        || std::strcmp( t, "unless_modifier" ) == 0
           || std::strcmp( t, "while_modifier" ) == 0     || std::strcmp( t, "until_modifier" ) == 0
           || std::strcmp( t, "when" ) == 0               || std::strcmp( t, "in_clause" ) == 0
           || std::strcmp( t, "rescue" ) == 0             || std::strcmp( t, "conditional" ) == 0
           // C# (tree-sitter-c-sharp): `foreach` is a distinct loop node (not `for_statement`); each
           // classic-switch `case`/`default` arm is a `switch_section`, each modern switch-expression
           // arm is a `switch_expression_arm` — both are the per-arm decision, matching Ruby's `when`.
           || std::strcmp( t, "foreach_statement" ) == 0   || std::strcmp( t, "switch_section" ) == 0
           || std::strcmp( t, "switch_expression_arm" ) == 0
           // Swift `guard cond else { exit }` — a decision point every cyclomatic tool counts, previously
           // missed (kParserVer 44). Also load-bearing for essential complexity: ev's per-construct weights
           // mirror this predicate exactly (ev_ctrl machinery below), so counting the guard-else exit in ev
           // without counting the guard here would break the structural ev <= cx containment.
           || std::strcmp( t, "guard_statement" ) == 0;
}

// (cyclomatic is now counted inside the fused cc_walk / complexityOf below — one DFS computes cx AND ccx.)

// ---- cognitive complexity (SonarSource-style, AST-approximate across our 7 grammars) ----
// Differs from cyclomatic in the two ways that matter: (1) NESTING is
// penalised — a control structure costs 1 + current-nesting, so deep code scores higher; (2) a flat
// switch costs 1 (not 1-per-case), rewarding dispatch tables over deep if/else (the house style).
// else-if chains are flattened (a C-family else-if = +1, not +1+nesting). Boolean runs collapse:
// `a && b && c` = +1, `a && b || c` = +2. Reported as `ccx` (raw fact, never a gate).
// Known approximations: plain C-family `else {}` blocks aren't separately scored; recursion isn't added.
// `lang` is read for the SAME single carve-out isDecisionType documents: Lua's `do … end` is a bare scope
// block, not a loop or a try, so it neither scores nor deepens nesting. Every other language is unchanged.
inline bool cc_isNestingControl( const char* t, Lang lang ) noexcept
{
    return    std::strcmp( t, "if_statement" ) == 0      || std::strcmp( t, "if_expression" ) == 0
           || std::strcmp( t, "for_statement" ) == 0     || std::strcmp( t, "for_range_loop" ) == 0
           || std::strcmp( t, "for_in_statement" ) == 0  || std::strcmp( t, "for_expression" ) == 0
           || std::strcmp( t, "while_statement" ) == 0   || std::strcmp( t, "while_expression" ) == 0
           || ( std::strcmp( t, "do_statement" ) == 0 && lang != Lang::Lua ) || std::strcmp( t, "loop_expression" ) == 0
           // Lua `repeat … until c` opens a nested body and scores, exactly like `while`. Lua's
           // `elseif_statement` is deliberately absent for the C-family else-if reason: flat +1, no deeper
           // nesting — and because it is a SIBLING here, cc_walk's else-if detector cannot flatten it, so
           // admitting it would charge 1+nesting for what is one arm of one chain.
           || std::strcmp( t, "repeat_statement" ) == 0
           || std::strcmp( t, "switch_statement" ) == 0  || std::strcmp( t, "switch_expression" ) == 0
           || std::strcmp( t, "match_expression" ) == 0
           || std::strcmp( t, "catch_clause" ) == 0      || std::strcmp( t, "except_clause" ) == 0
           || std::strcmp( t, "conditional_expression" ) == 0 || std::strcmp( t, "ternary_expression" ) == 0
           // Ruby (tree-sitter-ruby): the block control forms each open a nested body, so they raise nesting
           // AND score. `case`/`case_match` is the switch-equivalent container (flat +1, arms score via
           // isDecisionType — mirrors switch_statement). The trailing MODIFIER forms (`x if a`) have no nested
           // body and are deliberately absent here — they count as decisions only, matching the C-family model.
           || std::strcmp( t, "if" ) == 0                || std::strcmp( t, "unless" ) == 0
           || std::strcmp( t, "while" ) == 0             || std::strcmp( t, "until" ) == 0
           || std::strcmp( t, "for" ) == 0               || std::strcmp( t, "case" ) == 0
           || std::strcmp( t, "case_match" ) == 0        || std::strcmp( t, "rescue" ) == 0
           || std::strcmp( t, "conditional" ) == 0
           || std::strcmp( t, "foreach_statement" ) == 0;   // C# `foreach (var x in xs)` — a distinct loop node
           // NOTE: Ruby `elsif` is intentionally NOT here — like a C-family else-if / Python elif_clause it is a
           // flat +1 that does not deepen nesting; it is handled in the elif_clause/else_clause branch of cc_walk.
}
inline bool cc_isNestingOnly( const char* t ) noexcept   // raises nesting, scores nothing (lambdas/closures)
{
    return    std::strcmp( t, "lambda_expression" ) == 0 || std::strcmp( t, "lambda" ) == 0
           || std::strcmp( t, "closure_expression" ) == 0;
}

// A node's source text, or "" when the node is null or its byte range does not lie inside `src`. The
// null+range guard is the same three lines every extraction helper in this file would otherwise repeat (it
// is what --quality-delta flagged as a clone when the Rust helpers open-coded it, and again when the
// preprocessor include readers did), so it lives once, here — hoisted above the first consumer rather
// than sitting halfway down the file where three helpers ahead of it could not reach it.
//
// A FIELD read is the common case: nodeFieldText( n, "operator", 8, src ) is the whole of what most
// callers want, and ts_node_child_by_field_name's length argument is the one thing easy to get wrong.
inline std::string_view nodeTextOf( TSNode node, std::string_view src ) noexcept
{
    if( ts_node_is_null( node ) )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( node ), b = ts_node_end_byte( node );
    return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
}

inline std::string_view nodeFieldText( TSNode node, const char* field, std::uint32_t fieldLen, std::string_view src ) noexcept
{
    return nodeTextOf( ts_node_child_by_field_name( node, field, fieldLen ), src );
}

// The written spelling of a node's `operator:` field, or "" when it has none / the span is out of range.
// ONE derivation, shared by the two consumers below — cc_boolOp (cognitive: does this operator CONTINUE
// a boolean run?) and cc_isBooleanJoin (cyclomatic: does it count as a decision at all?). They ask
// different questions of the same string, and before the PHP/Lua port they answered them from two
// hand-copied spans — a duplication --quality-delta scored the moment the second one grew a case.
inline std::string_view cc_operatorText( TSNode n, std::string_view src ) noexcept
{
    return nodeFieldText( n, "operator", 8, src );
}

// the boolean-operator spelling of a node, or "" if it isn't one (&&/|| for C-family, and/or for Python)
inline std::string_view cc_boolOp( TSNode n, std::string_view src ) noexcept
{
    const std::string_view o = cc_operatorText( n, src );
    return ( o == "&&" || o == "||" || o == "and" || o == "or" ) ? o : std::string_view{};
}

// Myers' &&/|| extension for CYCLOMATIC counting: does this `binary_expression` join two conditions?
// Extracted from cc_walk rather than written inline — the PHP/Lua port needed a second spelling family
// (the WORD operators), and the inline form scored a measured +12 cx / +13 LOC on cc_walk, which is a
// --quality-delta regression on a function already at the top of this file's complexity distribution.
//
// Two spelling families, and the Lang gate is what keeps the second from touching any other grammar:
//   * `&&` / `||`  — C/C++/ObjC, TS/JS, Java, C#, Swift, Rust, Go, PHP. Two bytes.
//   * `and`/`or`/`xor` — Lua (its ONLY spelling) and PHP (its low-precedence alternative). `or` is also
//     two bytes, so the Lang test, not the length test, is what makes this sound: without it a
//     hypothetical grammar spelling some non-boolean operator `or` would start scoring.
// Python is deliberately absent from both: its `and`/`or` parse to a `boolean_operator` NODE, which
// isDecisionType already names, so counting it here too would double it.
inline bool cc_isBooleanJoin( TSNode n, std::string_view src, Lang lang ) noexcept
{
    const std::string_view o        = cc_operatorText( n, src );
    const bool             wordLang = ( lang == Lang::Lua || lang == Lang::Php );
    return    o == "&&" || o == "||"
           || ( wordLang && ( o == "and" || o == "or" ) )
           || ( lang == Lang::Php && o == "xor" );
}

// ── O(children) child collection for whole-subtree walks ─────────────────────────────────────────────
// ts_node_child( n, i ) restarts tree-sitter's child iterator from the FIRST child on every call, so an
// indexed loop over a node's C children costs O(C²). Width is attacker-controlled: ONE 980 KB file of
// 14 000 line comments hands the root 14 000 children and turned ingest into ~2 s of user CPU, quadratic
// in line count (gate: test/padscalecheck.sh). Every unbounded-width walk below therefore collects the
// child list ONCE per node with a TSTreeCursor — the same child set (named + anonymous + extras) in the
// same left-to-right order, O(C) total. The cursor and the out vector are caller-owned and reused across
// nodes, so a warm walk allocates nothing per node. Bounded-shape scans (base clauses, argument lists)
// keep the indexed form — their widths come from the grammar, not from the input file.
struct ChildCursor   // RAII — several walkers return mid-loop, so deletion must not depend on fallthrough
{
    TSTreeCursor cur;
    explicit ChildCursor( TSNode n ) noexcept : cur( ts_tree_cursor_new( n ) ) {}
    ChildCursor( const ChildCursor& ) = delete;
    ChildCursor& operator=( const ChildCursor& ) = delete;
    ~ChildCursor() { ts_tree_cursor_delete( &cur ); }
};
inline void collectChildren( TSNode n, TSTreeCursor& cur, std::vector<TSNode>& out )   // A4-F25: NOT noexcept — `out` allocates
{
    out.clear();
    ts_tree_cursor_reset( &cur, n );
    if( ts_tree_cursor_goto_first_child( &cur ) )
    {
        do
        {
            out.push_back( ts_tree_cursor_current_node( &cur ) );
        }
        while( ts_tree_cursor_goto_next_sibling( &cur ) );
    }
}

// bounded-depth search for a structured_binding_declarator anywhere under `n` — the vendored tree-sitter-cpp
// grammar nests it TWO levels below the `declaration` node (declaration -> init_declarator ->
// structured_binding_declarator for `auto [a,b] = …`; verified against the vendored grammar via a parse-tree
// dump, not assumed), so a same-level-only child scan misses it. `declaration` subtrees are grammar-bounded
// (a handful of children, not attacker-widenable like a comment run), so a small depth cap (not the
// cursor/stack machinery cc_walk itself uses for the whole-function walk) is the right tool here.
inline bool cc_declHasStructuredBinding( TSNode n, int depth ) noexcept
{
    if( depth <= 0 )
    {
        return false;   // pathological-AST guard — declaration subtrees never legitimately need this deep
    }
    const std::uint32_t childCount = ts_node_child_count( n );
    for( std::uint32_t ci = 0; ci < childCount; ++ci )
    {
        const TSNode child = ts_node_child( n, ci );
        if( std::strcmp( ts_node_type( child ), "structured_binding_declarator" ) == 0 )
        {
            return true;
        }
        if( cc_declHasStructuredBinding( child, depth - 1 ) )
        {
            return true;
        }
    }
    return false;
}

// Phase 1 (local-variable-indexing, docs/LOCALS_INDEXING.md): is `n` a LOCAL-VARIABLE declaration
// statement that cc_walk's own fused DFS should count? `declaration` node whose PARENT is the enclosing
// `compound_statement` (a direct block-statement local) — one rule that, WITHOUT any per-shape special
// case, naturally excludes an if-init (`if(int x=f())`)/switch-condition/for-init declarator (parent is
// the control-structure node, not compound_statement) and a catch-clause exception declarator (parent is
// catch_clause; also a different node KIND — parameter_declaration, not declaration — in the vendored
// grammar). A structured-binding declarator (`auto [a,b] = …`) is excluded explicitly: it IS a direct
// compound_statement child but introduces an unknown-count of names from one node, so counting it as "1"
// would silently mis-state what the count means — the floor semantics (locals_floor=, model.h) already
// cover honest undercounting elsewhere; this is a DIFFERENT axis (miscounting), kept out on purpose.
// C/C++ ONLY (model.h localsCountedLang) — the caller gates on lang before ever reaching here.
inline bool cc_isCountableLocalDecl( TSNode n, const char* t ) noexcept
{
    if( std::strcmp( t, "declaration" ) != 0 )
    {
        return false;
    }
    const TSNode parent = ts_node_parent( n );
    if( ts_node_is_null( parent ) || std::strcmp( ts_node_type( parent ), "compound_statement" ) != 0 )
    {
        return false;
    }
    return !cc_declHasStructuredBinding( n, 4 );
}

// shared by cc_countLocalDeclarators (below) and ln_declaratorIdentifiers (Phase 2, further down): is child
// `ci` of `declNode` one comma-separated declarator SLOT? The vendored grammar gives every comma-separated
// declarator its own `declarator`-FIELDED direct child of the `declaration` node (`int a=1,b=2;` has TWO) —
// pulled out to ONE predicate so the two counting/walking loops that need it never drift on the field name.
inline bool cc_isDeclaratorField( TSNode declNode, std::uint32_t ci ) noexcept
{
    const char* fieldName = ts_node_field_name_for_child( declNode, ci );
    return fieldName != nullptr && std::strcmp( fieldName, "declarator" ) == 0;
}

// L3 fix (2026-08-08 audit): a `declaration` node already proven countable by cc_isCountableLocalDecl can
// still introduce MORE THAN ONE local — `int a=1,b=2,…,j=10;` is ONE `declaration` node holding TEN
// comma-separated declarators, and counting the STATEMENT ("1") instead of each DECLARATOR undercounts on
// exactly the axis cc_isCountableLocalDecl's own structured-binding exclusion exists to avoid (a `locals=`
// that doesn't mean "how many names were declared"). Counts cc_isDeclaratorField direct children — no
// recursion: a declarator's own nested pointer/reference/array wrapper is still one name, one
// comma-separated slot, one `declarator` field. A declaration with ZERO declarator-fielded children (a
// type-only statement, e.g. a local `struct Foo;` forward declaration) now correctly counts as zero rather
// than the previous "1" — a declaration that names no local was never meant to be a local, and the old
// per-statement count silently over-counted that shape too.
inline std::uint32_t cc_countLocalDeclarators( TSNode n ) noexcept
{
    std::uint32_t count = 0;
    const std::uint32_t childCount = ts_node_child_count( n );
    for( std::uint32_t ci = 0; ci < childCount; ++ci )
    {
        if( cc_isDeclaratorField( n, ci ) )
        {
            ++count;
        }
    }
    return count;
}

// Every accumulator the fused walk fills, in ONE bundle. It used to be six by-reference out-parameters
// threaded through cc_walk's signature; the ppalt disclosure and the nesting-depth profile together
// would have made that ten, which is the
// parameter-count smell --metrics itself reports. One struct, passed by reference, is the same code with a
// name — and the walk's own hot loop touches it exactly as before.
struct CcAccum
{
    std::uint32_t cog     = 0;   // cognitive complexity (nesting-weighted)
    std::uint32_t cyclo   = 0;   // cyclomatic decision count (cx = 1 + this)
    std::uint32_t maxNest = 0;   // deepest control nesting reached  → Symbol::maxNest
    std::uint32_t locals  = 0;   // Phase 1 local-declaration floor  → Symbol::locals
    std::uint32_t ppAlt   = 0;   // preproc alternative branches      → Symbol::ppAlt   (see model.h)
    std::uint32_t humps   = 0;   // regions reaching quality::kNestBar → Symbol::humps   (see model.h)
    std::uint32_t deepLoc = 0;   // lines inside those regions        → Symbol::deepLoc  (a FLOOR)
    std::uint32_t deepEnd = 0;   // 1-based end row of the last counted hump — the anti-double-count clamp
};


// An ALTERNATIVE-introducing preprocessor node: `#else` / `#elif` / `#elifdef` inside the def mean the
// body carries code that never coexists at compile time, so every summed structural metric (cx/ccx/nest/
// loc/locals) over-counts vs any single build (bullet's btMatrix3x3.h::getRotation: both arms of a
// BT_USE_SSE guard, ~2x). ripwire never guesses which arm a build takes — it COUNTS the alternatives and
// the row discloses them (ppalt=, serialize.h). A bare `#if…#endif` with no `#else` introduces no
// mutually-exclusive alternative and deliberately does not count. Prefix match so grammar-internal
// variants (the `_in_field_declaration_list` family) ride along; both prefixes are 12 bytes. C, C++ and
// C# spell these node types identically (verified by real parses — test/ppaltcheck.sh's own fixtures);
// ObjC/CUDA/Metal share the C/C++ preproc node family (kPreprocConditionalNodes below). Grammars without
// a preprocessor simply never match — no per-language gate needed.
inline bool cc_isPreprocAlternative( const char* t ) noexcept
{
    return std::strncmp( t, "preproc_else", 12 ) == 0 || std::strncmp( t, "preproc_elif", 12 ) == 0;
}


// A hump is a control-nesting region whose depth FIRST reaches quality::kNestBar. Counting it at the
// crossing is what makes the count exact: a deeper region inside an already-deep one has an ancestor chain
// that is already at or over the bar, so it cannot cross again and cannot be counted twice.
//
// `deepLoc` bills the crossing node's whole line span, control header included — the `if(` line is part of
// what a reader must hold in their head. Sibling humps are reached in document order (the DFS pushes
// children in reverse, so pops run left to right), so a hump starting on the line the previous one ended is
// clamped to start after it. The clamp can only ever SUBTRACT: if the order assumption is ever violated the
// result is an under-count, never an over-count, which is exactly why deepLoc is published as a floor.
inline void cc_noteHump( TSNode n, std::uint32_t fromNesting, std::uint32_t toNesting, CcAccum& acc ) noexcept
{
    if( fromNesting >= quality::kNestBar || toNesting < quality::kNestBar )
    {
        return;   // already deep (counted at an ancestor), or still shallow
    }
    ++acc.humps;
    const std::uint32_t startRow = ts_node_start_point( n ).row + 1u;   // tree-sitter rows are 0-based
    const std::uint32_t endRow   = ts_node_end_point( n ).row + 1u;
    const std::uint32_t from     = ( startRow > acc.deepEnd ) ? startRow : acc.deepEnd + 1u;
    if( endRow >= from )
    {
        acc.deepLoc += endRow - from + 1u;
    }
    if( endRow > acc.deepEnd )
    {
        acc.deepEnd = endRow;
    }
}

// ═══ essential complexity ev(G) — the syntactic single-exit reduction (the essential-complexity design note) ═══
//
// THE RULE (§2.2, reference-verified — see test/essentialcxcheck.sh's reconciliation header): a jump marks
// irreducible every control construct STRICTLY BETWEEN it and its target construct; irreducibility then
// propagates OUTWARD to the function root (stopping at closure/nested-fn boundaries); a marked switch head
// contributes every arm. ev = 1 + Σ (own cx decision weight of every marked construct). Weights are
// EXACTLY `isNamed && isDecisionType(t)` — one weight-1 arena node per cyclo-counted decision node and
// never more — which is what makes ev <= cx structural rather than hoped for (boolean operators add to
// cyclo but never enter the arena, widening the gap only in the safe direction).
//
// THE FLOOR RULE (§6, load-bearing): an unrecognised jump node type, or an unresolvable target, marks
// NOTHING. Never mark speculatively. Every failure mode — a noreturn call, a macro-hidden return, a label
// this scan cannot find, a grammar shape not in the tables below — therefore lands in the UNDER-counting
// direction, so emitted ev <= true ev(G) always, which is what lets serialize.h stamp ev_floor="1".
//
// DATA STRUCTURE (§2.3, G2): a parent-index arena, not a CFG — POD nodes, 32-bit handles, no edges, no
// graph library. Pre-order guarantees parent index < child index, which the propagation pass exploits.
enum class CtrlKind : std::uint8_t { Loop, Switch, Case, Branch, Try, Catch, Fn, Block, Labelled };
struct CtrlNode
{
    std::uint32_t parent;   // arena index of the innermost enclosing construct; kNoCtrl at function root
    std::uint16_t weight;   // this construct's OWN cx decision weight (isDecisionType), see above
    std::uint8_t  kind;     // CtrlKind
    std::uint8_t  marked;   // 0/1 — in the irreducible residue
};
static_assert( sizeof( CtrlNode ) == 8, "CtrlNode is the ev arena's hot element — keep it POD and tight" );
inline constexpr std::uint32_t kNoCtrl = 0xFFFFFFFFu;

// EvWhyTag indices MUST track model.h's kEvWhyTagTable declaration order — the table is the single
// source of the public spellings; these are the write-side indices.
enum class EvWhyTag : std::uint8_t { GuardReturn = 0, LoopEscape, SwitchEscape, Goto, LabelledJump, BackEdge, Fallthrough, MultiEntry };

// Everything the walk accumulates for one def's ev. Vectors are constructed per complexityOf call and
// reserve small — the same per-def allocation posture as cc_walk's own frame stack/kids (A4-F25: NOT
// noexcept; bad_alloc propagates to the per-file degrade catch).
struct EvCtx
{
    std::vector<CtrlNode> arena;
    struct LabelDef     { std::uint32_t ctrl; std::string name; };            // label -> its construct's arena index
    struct PendingJump  { std::uint32_t ctrl; std::uint8_t tag; std::string label; };   // gotos + labelled jumps, resolved post-walk
    std::vector<LabelDef>    labels;
    std::vector<PendingJump> pending;
    std::uint32_t            why[ kEvWhyTagCount ] = {};
};

// jump-target kind masks for ev_findTarget
enum : std::uint8_t { kEvTgtLoop = 1, kEvTgtSwitch = 2, kEvTgtBlock = 4, kEvTgtTry = 8, kEvTgtFn = 16 };

// source text of the first child with one of the given node types ("" when absent). Jump statements are
// grammar-bounded shapes (a keyword + at most a label/expression), so the indexed child form is right here
// (see the O(children) note above collectChildren — this is a bounded-shape scan, not an unbounded walk).
inline std::string_view ev_childText( TSNode n, std::string_view src, std::initializer_list<const char*> types ) noexcept
{
    const std::uint32_t childCount = ts_node_child_count( n );
    for( std::uint32_t ci = 0; ci < childCount; ++ci )
    {
        const TSNode child = ts_node_child( n, ci );
        const char*  ct    = ts_node_type( child );
        for( const char* want : types )
        {
            if( std::strcmp( ct, want ) == 0 )
            {
                const std::uint32_t a = ts_node_start_byte( child ), b = ts_node_end_byte( child );
                if( b <= src.size() && b > a )
                {
                    return src.substr( a, b - a );
                }
            }
        }
    }
    return {};
}

// does the node carry an ANONYMOUS keyword child with this exact spelling? (C# `goto case 1;` /
// `yield break;` — the discriminating token is unnamed, so type-based lookup cannot see it.)
inline bool ev_hasAnonKeyword( TSNode n, std::string_view src, std::string_view keyword ) noexcept
{
    const std::uint32_t childCount = ts_node_child_count( n );
    for( std::uint32_t ci = 0; ci < childCount; ++ci )
    {
        const TSNode child = ts_node_child( n, ci );
        if( ts_node_is_named( child ) )
        {
            continue;
        }
        const std::uint32_t a = ts_node_start_byte( child ), b = ts_node_end_byte( child );
        if( b <= src.size() && b - a == keyword.size() && src.substr( a, b - a ) == keyword )
        {
            return true;
        }
    }
    return false;
}

// one label spelling across the grammars: Rust labels carry a leading tick (`'outer`), Swift statement
// labels a trailing colon (`outer:`); the jump side and the definition side must agree byte-for-byte.
inline std::string_view ev_normalizeLabel( std::string_view label ) noexcept
{
    if( !label.empty() && label.front() == '\'' ) { label.remove_prefix( 1 ); }
    if( !label.empty() && label.back() == ':' )   { label.remove_suffix( 1 ); }
    return label;
}

// nearest enclosing construct of an allowed kind, walking parent links. A Fn node is a hard boundary:
// return-family jumps may TARGET it (kEvTgtFn), everything else fails there — a break can never leave a
// closure, so resolving past one would mark constructs the jump provably does not cross (floor rule).
// Returns kNoCtrl for "function root" when the mask includes kEvTgtFn, and for FAILURE otherwise — the
// callers' masks make the two cases unambiguous per jump family.
inline std::uint32_t ev_findTarget( const EvCtx& ctx, std::uint32_t from, std::uint8_t mask ) noexcept
{
    for( std::uint32_t i = from; i != kNoCtrl; i = ctx.arena[i].parent )
    {
        const CtrlKind k = CtrlKind( ctx.arena[i].kind );
        if( k == CtrlKind::Fn )
        {
            return ( mask & kEvTgtFn ) ? i : kNoCtrl;
        }
        if( ( ( mask & kEvTgtLoop ) && k == CtrlKind::Loop ) || ( ( mask & kEvTgtSwitch ) && k == CtrlKind::Switch )
            || ( ( mask & kEvTgtBlock ) && k == CtrlKind::Block ) || ( ( mask & kEvTgtTry ) && k == CtrlKind::Try ) )
        {
            return i;
        }
    }
    return kNoCtrl;   // reached the function root
}

// a throw's target: the nearest enclosing try — but a try whose chain we enter THROUGH its own catch
// clause is not a landing site (a rethrow propagates outward), so a Catch on the chain skips the next Try.
inline std::uint32_t ev_findThrowTarget( const EvCtx& ctx, std::uint32_t from ) noexcept
{
    bool skipOwnTry = false;
    for( std::uint32_t i = from; i != kNoCtrl; i = ctx.arena[i].parent )
    {
        const CtrlKind k = CtrlKind( ctx.arena[i].kind );
        if( k == CtrlKind::Fn )
        {
            return i;
        }
        if( k == CtrlKind::Catch )
        {
            skipOwnTry = true;
        }
        else if( k == CtrlKind::Try )
        {
            if( skipOwnTry ) { skipOwnTry = false; }
            else             { return i; }
        }
    }
    return kNoCtrl;   // function root — an uncaught throw is a guard-shaped exit
}

// mark every construct STRICTLY BETWEEN `from` and `target` (exclusive). A Case arm that is the target's
// own DIRECT arm is the jump's normal exit (design §2.2 row 1 — `case 1: … break;` is structured) and is
// skipped when excludeDirectArm. Returns whether this jump CONTRIBUTES to ev_why: it must have crossed a
// construct that actually raises ev — one carrying decision weight, or a switch head (whose arms then
// complete). A weight-0 transparent wrapper alone (a goto label around the tail return, a bare Try) does
// not make a jump a contributor — the tag counts must explain a RAISED ev, not narrate the walk.
// Already-marked nodes still count — two breaks under one if are two contributing jumps, not one.
inline bool ev_markBetween( EvCtx& ctx, std::uint32_t from, std::uint32_t target, bool excludeDirectArm ) noexcept
{
    bool contributed = false;
    for( std::uint32_t i = from; i != target && i != kNoCtrl; i = ctx.arena[i].parent )
    {
        if( excludeDirectArm && CtrlKind( ctx.arena[i].kind ) == CtrlKind::Case && ctx.arena[i].parent == target )
        {
            continue;
        }
        ctx.arena[i].marked = 1;
        if( ctx.arena[i].weight > 0 || CtrlKind( ctx.arena[i].kind ) == CtrlKind::Switch )
        {
            contributed = true;
        }
    }
    return contributed;
}

inline void ev_countWhy( EvCtx& ctx, EvWhyTag tag ) noexcept
{
    ++ctx.why[ std::size_t( tag ) ];
}

// is `t` a control construct the arena tracks, and of what kind? Lang-gated where node-type spellings
// collide across grammars (Swift's `do_statement` is a try, the C family's a loop; Ruby's bare-word kinds
// double as anonymous keyword tokens elsewhere — the caller's isNamed gate recovers them, exactly as
// cc_isNestingControl's note explains). Node-type spellings verified against the VENDORED grammars via
// real parses (--match probes per language), not assumed — the ln_extractDeclaratorIdentifiers discipline.
inline bool ev_ctrlKindFor( const char* t, Lang lang, CtrlKind& kindOut ) noexcept
{
    // branches
    if(    std::strcmp( t, "if_statement" ) == 0        || std::strcmp( t, "if_expression" ) == 0
        || std::strcmp( t, "conditional_expression" ) == 0 || std::strcmp( t, "ternary_expression" ) == 0
        || std::strcmp( t, "guard_statement" ) == 0     || std::strcmp( t, "conditional" ) == 0
        || std::strcmp( t, "elif_clause" ) == 0         || std::strcmp( t, "else_clause" ) == 0
        || std::strcmp( t, "elsif" ) == 0               || std::strcmp( t, "if" ) == 0
        || std::strcmp( t, "unless" ) == 0              || std::strcmp( t, "if_modifier" ) == 0
        || std::strcmp( t, "unless_modifier" ) == 0 )
    {
        kindOut = CtrlKind::Branch;
        return true;
    }
    // loops (Swift's do_statement is a TRY and is handled below)
    if(    std::strcmp( t, "for_statement" ) == 0       || std::strcmp( t, "for_range_loop" ) == 0
        || std::strcmp( t, "for_in_statement" ) == 0    || std::strcmp( t, "for_expression" ) == 0
        || std::strcmp( t, "while_statement" ) == 0     || std::strcmp( t, "while_expression" ) == 0
        || std::strcmp( t, "loop_expression" ) == 0     || std::strcmp( t, "foreach_statement" ) == 0
        || std::strcmp( t, "repeat_while_statement" ) == 0
        || ( std::strcmp( t, "do_statement" ) == 0 && lang != Lang::Swift )
        || std::strcmp( t, "while" ) == 0               || std::strcmp( t, "until" ) == 0
        || std::strcmp( t, "for" ) == 0                 || std::strcmp( t, "while_modifier" ) == 0
        || std::strcmp( t, "until_modifier" ) == 0 )
    {
        kindOut = CtrlKind::Loop;
        return true;
    }
    // switch/match heads (weight 0 — the arms carry the decisions, as in cx)
    if(    std::strcmp( t, "switch_statement" ) == 0    || std::strcmp( t, "switch_expression" ) == 0
        || std::strcmp( t, "match_expression" ) == 0    || std::strcmp( t, "match_statement" ) == 0
        || std::strcmp( t, "expression_switch_statement" ) == 0 || std::strcmp( t, "type_switch_statement" ) == 0
        || std::strcmp( t, "select_statement" ) == 0    || std::strcmp( t, "case" ) == 0
        || std::strcmp( t, "case_match" ) == 0 )
    {
        kindOut = CtrlKind::Switch;
        return true;
    }
    // arms
    if(    std::strcmp( t, "case_statement" ) == 0      || std::strcmp( t, "switch_section" ) == 0
        || std::strcmp( t, "switch_expression_arm" ) == 0 || std::strcmp( t, "match_arm" ) == 0
        || std::strcmp( t, "expression_case" ) == 0     || std::strcmp( t, "communication_case" ) == 0
        || std::strcmp( t, "default_case" ) == 0        || std::strcmp( t, "type_case" ) == 0
        || std::strcmp( t, "case_clause" ) == 0         || std::strcmp( t, "switch_entry" ) == 0
        || std::strcmp( t, "switch_rule" ) == 0         || std::strcmp( t, "switch_block_statement_group" ) == 0
        || std::strcmp( t, "when" ) == 0                || std::strcmp( t, "in_clause" ) == 0 )
    {
        kindOut = CtrlKind::Case;
        return true;
    }
    // try / catch (Swift spells try as do_statement + catch_block)
    if(    std::strcmp( t, "try_statement" ) == 0       || std::strcmp( t, "try_with_resources_statement" ) == 0
        || std::strcmp( t, "begin" ) == 0               || ( std::strcmp( t, "do_statement" ) == 0 && lang == Lang::Swift ) )
    {
        kindOut = CtrlKind::Try;
        return true;
    }
    if(    std::strcmp( t, "catch_clause" ) == 0        || std::strcmp( t, "except_clause" ) == 0
        || std::strcmp( t, "catch_block" ) == 0         || std::strcmp( t, "rescue" ) == 0 )
    {
        kindOut = CtrlKind::Catch;
        return true;
    }
    // function boundaries — the jump barrier. A miss here is the ONE table error that would OVER-count
    // (a return inside an unrecognised closure shape would mark the outer function's constructs), which
    // is why this list errs wide and every entry was probe-verified.
    if(    std::strcmp( t, "lambda_expression" ) == 0   || std::strcmp( t, "lambda" ) == 0
        || std::strcmp( t, "closure_expression" ) == 0  || std::strcmp( t, "function_definition" ) == 0
        || std::strcmp( t, "function_declaration" ) == 0 || std::strcmp( t, "function_expression" ) == 0
        || std::strcmp( t, "arrow_function" ) == 0      || std::strcmp( t, "generator_function" ) == 0
        || std::strcmp( t, "generator_function_declaration" ) == 0 || std::strcmp( t, "method_definition" ) == 0
        || std::strcmp( t, "method_declaration" ) == 0  || std::strcmp( t, "func_literal" ) == 0
        || std::strcmp( t, "function_item" ) == 0       || std::strcmp( t, "lambda_literal" ) == 0
        || std::strcmp( t, "local_function_statement" ) == 0 || std::strcmp( t, "anonymous_method_expression" ) == 0
        || std::strcmp( t, "method" ) == 0              || std::strcmp( t, "singleton_method" ) == 0 )
    {
        kindOut = CtrlKind::Fn;
        return true;
    }
    // Ruby blocks — a jump scope of their own (`each do … next end`: next is the block's normal exit);
    // lang-gated because Go/Java/C# spell their PLAIN braces "block", which must stay out of the arena.
    if( lang == Lang::Ruby && ( std::strcmp( t, "block" ) == 0 || std::strcmp( t, "do_block" ) == 0 ) )
    {
        kindOut = CtrlKind::Block;
        return true;
    }
    if( std::strcmp( t, "labeled_statement" ) == 0 )
    {
        kindOut = CtrlKind::Labelled;
        return true;
    }
    return false;
}

// append one arena node; registers labels (labeled_statement wrappers; Rust/Swift loops carrying their
// own label child) and fires the §2.6 multi-entry detection for displaced arms. Returns the new index.
inline std::uint32_t ev_appendCtrl( EvCtx& ctx, TSNode n, CtrlKind kind, std::uint16_t weight, std::uint32_t parentIdx, Lang lang, std::string_view src )
{
    const std::uint32_t newIdx = std::uint32_t( ctx.arena.size() );
    ctx.arena.push_back( CtrlNode{ parentIdx, weight, std::uint8_t( kind ), 0 } );
    if( kind == CtrlKind::Labelled )
    {
        const std::string_view label = ev_normalizeLabel( ev_childText( n, src, { "statement_identifier", "label_name", "identifier" } ) );
        if( !label.empty() )
        {
            ctx.labels.push_back( { newIdx, std::string( label ) } );
        }
    }
    else if( ( kind == CtrlKind::Loop || kind == CtrlKind::Switch ) && ( lang == Lang::Rust || lang == Lang::Swift ) )
    {
        // Rust: `'outer: loop { … }` — the label is a child of the loop expression itself.
        // Swift: `outer: for … { … }` — a statement_label child, colon included.
        const std::string_view label = ev_normalizeLabel( ev_childText( n, src, { "label", "statement_label" } ) );
        if( !label.empty() )
        {
            ctx.labels.push_back( { newIdx, std::string( label ) } );
        }
    }
    if( kind == CtrlKind::Case && parentIdx != kNoCtrl )
    {
        const CtrlKind parentKind = CtrlKind( ctx.arena[ parentIdx ].kind );
        if( parentKind != CtrlKind::Switch && parentKind != CtrlKind::Case )
        {
            // §2.6 — a case label displaced under a loop/branch between it and its switch (Duff's device):
            // a REAL multi-entry region the single-entry theorem excludes everywhere else. Mark the arm;
            // outward propagation then keeps the displacing construct, the switch, and every sibling arm.
            ctx.arena[ newIdx ].marked = 1;
            ev_countWhy( ctx, EvWhyTag::MultiEntry );
        }
    }
    return newIdx;
}

// note one visited node for ev: either it opens a control construct (-> new arena node, returned as the
// children's ctrl) or it is a jump (-> resolve or defer). Anything else returns parentIdx unchanged.
// Caller guarantees isNamed (anonymous keyword tokens must never look like Ruby's bare-word nodes).
inline std::uint32_t ev_noteNode( EvCtx& ctx, TSNode n, const char* t, std::uint32_t parentIdx, Lang lang, std::string_view src )
{
    CtrlKind kind;
    if( ev_ctrlKindFor( t, lang, kind ) )
    {
        return ev_appendCtrl( ctx, n, kind, std::uint16_t( isDecisionType( t, lang ) ? 1 : 0 ), parentIdx, lang, src );
    }

    // ── jumps. Every rule below: resolve the target (ancestors only — the arena already holds them in a
    //    pre-order walk), mark strictly between, count the tag iff the chain was non-empty. Unresolvable
    //    (or unrecognised) ⇒ mark nothing — the floor rule.
    const bool isRuby = ( lang == Lang::Ruby );

    // return-family: target = nearest closure boundary, else the function root. Ruby `return` passes
    // THROUGH blocks (a non-local method return), which kEvTgtFn-only masks give for free.
    const auto noteReturn = [ & ]()
    {
        if( ev_markBetween( ctx, parentIdx, ev_findTarget( ctx, parentIdx, kEvTgtFn ), false ) )
        {
            ev_countWhy( ctx, EvWhyTag::GuardReturn );
        }
    };
    const auto noteThrow = [ & ]()
    {
        if( ev_markBetween( ctx, parentIdx, ev_findThrowTarget( ctx, parentIdx ), false ) )
        {
            ev_countWhy( ctx, EvWhyTag::GuardReturn );
        }
    };
    // break/continue-family: `armExit` = an arm-tail break is the target's normal exit (row 1).
    const auto noteEscape = [ & ]( std::uint8_t mask, bool armExit )
    {
        const std::uint32_t target = ev_findTarget( ctx, parentIdx, mask );
        if( target == kNoCtrl )
        {
            return;   // no such construct below the closure boundary — never mark speculatively
        }
        if( ev_markBetween( ctx, parentIdx, target, armExit ) )
        {
            ev_countWhy( ctx, CtrlKind( ctx.arena[ target ].kind ) == CtrlKind::Switch ? EvWhyTag::SwitchEscape : EvWhyTag::LoopEscape );
        }
    };

    if( std::strcmp( t, "return_statement" ) == 0 || std::strcmp( t, "return_expression" ) == 0
        || std::strcmp( t, "co_return_statement" ) == 0 || ( isRuby && std::strcmp( t, "return" ) == 0 ) )
    {
        noteReturn();
    }
    else if( std::strcmp( t, "throw_statement" ) == 0 || std::strcmp( t, "raise_statement" ) == 0 )
    {
        noteThrow();
    }
    else if( std::strcmp( t, "break_statement" ) == 0 || std::strcmp( t, "continue_statement" ) == 0 )
    {
        const bool             isBreak = ( t[0] == 'b' );
        const std::string_view label   = ev_normalizeLabel( ev_childText( n, src, { "statement_identifier", "label_name", "identifier" } ) );
        if( !label.empty() )
        {
            ctx.pending.push_back( { parentIdx, std::uint8_t( EvWhyTag::LabelledJump ), std::string( label ) } );
        }
        else
        {
            // Python's match does not capture break (§3.1's easily-missed case) — its head is in the arena
            // as a Switch for structure, but a Python break resolves past it to the loop.
            const std::uint8_t mask = isBreak ? std::uint8_t( lang == Lang::Python ? kEvTgtLoop : ( kEvTgtLoop | kEvTgtSwitch ) )
                                              : std::uint8_t( kEvTgtLoop );
            noteEscape( mask, isBreak );
        }
    }
    else if( std::strcmp( t, "break_expression" ) == 0 || std::strcmp( t, "continue_expression" ) == 0 )
    {
        // Rust: `break 'label` / `continue 'label` carry a label child; a bare break targets the loop only.
        const std::string_view label = ev_normalizeLabel( ev_childText( n, src, { "label", "loop_label" } ) );
        if( !label.empty() )
        {
            ctx.pending.push_back( { parentIdx, std::uint8_t( EvWhyTag::LabelledJump ), std::string( label ) } );
        }
        else
        {
            noteEscape( kEvTgtLoop, t[0] == 'b' );
        }
    }
    else if( isRuby && ( std::strcmp( t, "break" ) == 0 || std::strcmp( t, "next" ) == 0 ) )
    {
        noteEscape( kEvTgtLoop | kEvTgtBlock, false );
    }
    else if( isRuby && ( std::strcmp( t, "redo" ) == 0 || std::strcmp( t, "retry" ) == 0 ) )
    {
        // genuine back edges outside every prime (§3.1): mark the chain AND the target construct itself —
        // even a redo sitting directly in the loop body makes that loop a hand-rolled goto shape.
        const std::uint32_t target = ev_findTarget( ctx, parentIdx, std::uint8_t( t[2] == 'd' ? ( kEvTgtLoop | kEvTgtBlock ) : kEvTgtTry ) );
        if( target != kNoCtrl )
        {
            ev_markBetween( ctx, parentIdx, target, false );
            ctx.arena[ target ].marked = 1;
            ev_countWhy( ctx, EvWhyTag::BackEdge );
        }
    }
    else if( std::strcmp( t, "goto_statement" ) == 0 )
    {
        if( lang == Lang::CSharp && ( ev_hasAnonKeyword( n, src, "case" ) || ev_hasAnonKeyword( n, src, "default" ) ) )
        {
            // C# `goto case L;` / `goto default;` — an explicit intra-switch goto: target the enclosing
            // switch WITHOUT the arm-exit grace (jumping INTO another arm is never a normal exit).
            const std::uint32_t target = ev_findTarget( ctx, parentIdx, kEvTgtSwitch );
            if( target != kNoCtrl && ev_markBetween( ctx, parentIdx, target, false ) )
            {
                ev_countWhy( ctx, EvWhyTag::Goto );
            }
        }
        else
        {
            const std::string_view label = ev_normalizeLabel( ev_childText( n, src, { "statement_identifier", "label_name", "identifier" } ) );
            if( !label.empty() )
            {
                ctx.pending.push_back( { parentIdx, std::uint8_t( EvWhyTag::Goto ), std::string( label ) } );
            }
        }
    }
    else if( std::strcmp( t, "fallthrough_statement" ) == 0 )
    {
        // Go — an explicit intra-switch goto; counts (§3.1). The arm itself is marked (no arm-exit grace),
        // and propagation then keeps the switch and every sibling arm. (Swift's fallthrough is an
        // undetectable hidden token in its grammar — probe-verified — so Swift under-counts here: floor.)
        const std::uint32_t target = ev_findTarget( ctx, parentIdx, kEvTgtSwitch );
        if( target != kNoCtrl && ev_markBetween( ctx, parentIdx, target, false ) )
        {
            ev_countWhy( ctx, EvWhyTag::Fallthrough );
        }
    }
    else if( std::strcmp( t, "yield_statement" ) == 0 )
    {
        if( lang == Lang::Java )
        {
            // a switch-expression's value production — the arm's normal exit when at arm tail; an escape
            // when it crosses an intervening construct (same geometry as break-to-switch).
            const std::uint32_t target = ev_findTarget( ctx, parentIdx, kEvTgtSwitch );
            if( target != kNoCtrl && ev_markBetween( ctx, parentIdx, target, true ) )
            {
                ev_countWhy( ctx, EvWhyTag::SwitchEscape );
            }
        }
        else if( lang == Lang::CSharp && ev_hasAnonKeyword( n, src, "break" ) )
        {
            noteReturn();   // `yield break` ends the iterator — a return; `yield return` is a suspension, not a jump
        }
    }
    else if( std::strcmp( t, "control_transfer_statement" ) == 0 )
    {
        // Swift wraps break/continue/return/throw in one node kind; the keyword is its first token.
        const std::uint32_t a = ts_node_start_byte( n );
        const std::string_view rest = ( a < src.size() ) ? src.substr( a ) : std::string_view{};
        const std::string_view label = ev_normalizeLabel( ev_childText( n, src, { "simple_identifier" } ) );
        if( rest.starts_with( "break" ) || rest.starts_with( "continue" ) )
        {
            if( !label.empty() )
            {
                ctx.pending.push_back( { parentIdx, std::uint8_t( EvWhyTag::LabelledJump ), std::string( label ) } );
            }
            else
            {
                noteEscape( rest.starts_with( "break" ) ? std::uint8_t( kEvTgtLoop | kEvTgtSwitch ) : std::uint8_t( kEvTgtLoop ), rest.starts_with( "break" ) );
            }
        }
        else if( rest.starts_with( "return" ) )
        {
            noteReturn();
        }
        else if( rest.starts_with( "throw" ) )
        {
            noteThrow();
        }
    }
    return parentIdx;
}

// post-walk finalization: resolve the label-addressed jumps (a label can sit AFTER its goto), run the
// outward propagation, complete marked switches' arms, and sum. Returns ev (>= 1) and the tag counters.
inline void ev_finalize( EvCtx& ctx, std::uint32_t& evOut, std::array<std::uint8_t, kEvWhyTagCount>& whyOut )
{
    // 1. label-addressed jumps — goto via lowest common ancestor (§2.5), labelled break/continue via the
    //    ancestor check. A label that is missing, duplicated, or across a closure boundary marks NOTHING.
    for( const EvCtx::PendingJump& jump : ctx.pending )
    {
        std::uint32_t labelCtrl = kNoCtrl;
        bool          found = false, duplicated = false;
        for( const EvCtx::LabelDef& def : ctx.labels )
        {
            if( def.name == jump.label )
            {
                duplicated = found;
                labelCtrl  = def.ctrl;
                found      = true;
            }
        }
        if( !found || duplicated )
        {
            continue;
        }
        if( EvWhyTag( jump.tag ) == EvWhyTag::LabelledJump )
        {
            // the labelled construct must be an ANCESTOR reached without crossing a closure boundary
            bool reachable = false;
            for( std::uint32_t i = jump.ctrl; i != kNoCtrl; i = ctx.arena[i].parent )
            {
                if( CtrlKind( ctx.arena[i].kind ) == CtrlKind::Fn ) { break; }
                if( i == labelCtrl ) { reachable = true; break; }
            }
            if( reachable && ev_markBetween( ctx, jump.ctrl, labelCtrl, false ) )
            {
                ev_countWhy( ctx, EvWhyTag::LabelledJump );
            }
        }
        else   // goto
        {
            // both chains, each ending at the first closure boundary (inclusive, so two nodes under the
            // SAME closure still meet); no common node + any boundary ⇒ different scopes ⇒ mark nothing.
            const auto chainOf = [ & ]( std::uint32_t from, std::vector<std::uint32_t>& out, bool& hitFn )
            {
                out.clear();
                hitFn = false;
                for( std::uint32_t i = from; i != kNoCtrl; i = ctx.arena[i].parent )
                {
                    out.push_back( i );
                    if( CtrlKind( ctx.arena[i].kind ) == CtrlKind::Fn ) { hitFn = true; break; }
                }
            };
            std::vector<std::uint32_t> jumpChain, labelChain;
            bool jumpHitFn = false, labelHitFn = false;
            chainOf( jump.ctrl, jumpChain, jumpHitFn );
            chainOf( labelCtrl, labelChain, labelHitFn );
            std::uint32_t lca      = kNoCtrl;
            std::size_t   lcaJump  = jumpChain.size(), lcaLabel = labelChain.size();
            for( std::size_t j = 0; j < jumpChain.size() && lca == kNoCtrl; ++j )
            {
                for( std::size_t l = 0; l < labelChain.size(); ++l )
                {
                    if( labelChain[l] == jumpChain[j] )
                    {
                        lca = jumpChain[j]; lcaJump = j; lcaLabel = l;
                        break;
                    }
                }
            }
            if( lca == kNoCtrl && ( jumpHitFn || labelHitFn ) )
            {
                continue;   // different closure scopes (a label name reused inside a lambda) — floor rule
            }
            bool contributed = false;
            const auto markChainNode = [ & ]( std::uint32_t idx )
            {
                ctx.arena[ idx ].marked = 1;
                if( ctx.arena[ idx ].weight > 0 || CtrlKind( ctx.arena[ idx ].kind ) == CtrlKind::Switch )
                {
                    contributed = true;   // same contributor rule as ev_markBetween: a crossed construct that raises ev
                }
            };
            for( std::size_t j = 0; j < lcaJump; ++j )   { markChainNode( jumpChain[j] ); }
            for( std::size_t l = 0; l < lcaLabel; ++l )  { markChainNode( labelChain[l] ); }
            if( contributed )
            {
                ev_countWhy( ctx, EvWhyTag::Goto );
            }
        }
    }

    // 2. outward propagation (§2.2): an uncollapsed child keeps its ancestors in the residue. Ascending
    //    index order + early stop is correct because parents precede children in a pre-order arena, and a
    //    walk that marks a node always finishes that node's whole chain in the same sweep. Closure
    //    boundaries (Fn) and Ruby blocks (Block) contain their tangles — the outer function's constructs
    //    stay reducible around them.
    for( std::uint32_t i = 0; i < std::uint32_t( ctx.arena.size() ); ++i )
    {
        if( !ctx.arena[i].marked )
        {
            continue;
        }
        for( std::uint32_t p = ctx.arena[i].parent; p != kNoCtrl; p = ctx.arena[p].parent )
        {
            const CtrlKind k = CtrlKind( ctx.arena[p].kind );
            if( k == CtrlKind::Fn || k == CtrlKind::Block || ctx.arena[p].marked )
            {
                break;
            }
            ctx.arena[p].marked = 1;
        }
    }

    // 3. a marked switch head contributes EVERY arm (§2.2 last row). Ascending order cascades through
    //    nested consecutive labels (an arm whose parent is itself an arm).
    for( std::uint32_t i = 0; i < std::uint32_t( ctx.arena.size() ); ++i )
    {
        if( CtrlKind( ctx.arena[i].kind ) != CtrlKind::Case || ctx.arena[i].parent == kNoCtrl )
        {
            continue;
        }
        const CtrlNode& parent = ctx.arena[ ctx.arena[i].parent ];
        if( parent.marked && ( CtrlKind( parent.kind ) == CtrlKind::Switch || CtrlKind( parent.kind ) == CtrlKind::Case ) )
        {
            ctx.arena[i].marked = 1;
        }
    }

    // 4. ev = 1 + Σ marked weights (saturating, humps' rule), and the tag counters (saturating at u8).
    std::uint32_t sum = 1;
    for( const CtrlNode& node : ctx.arena )
    {
        if( node.marked )
        {
            sum += node.weight;
        }
    }
    evOut = ( sum > 65535u ) ? 65535u : sum;
    for( std::size_t tagIndex = 0; tagIndex < kEvWhyTagCount; ++tagIndex )
    {
        whyOut[ tagIndex ] = std::uint8_t( ctx.why[ tagIndex ] > 255u ? 255u : ctx.why[ tagIndex ] );
    }
}

// A4-F25: NOT noexcept — the frame-stack vector allocates, so under memory pressure bad_alloc must be
// allowed to propagate to the per-file degrade catch, not turn into terminate().
inline void cc_walk( TSNode start, std::uint32_t startNesting, std::string_view src, CcAccum& acc, int startDepth,
                      bool countLocals,   // Phase 1: countLocals gates on lang (model.h localsCountedLang), C/C++ only
                      Lang lang, EvCtx* evCtx )   // essential complexity: nullptr outside model.h evCountedLang — zero work then
{
    // iterative pre-order DFS — an EXPLICIT frame stack, not recursion: worker threads get 512 KB stacks on
    // macOS, so a deep AST overflows the call stack well inside the depth guard. Children are pushed in
    // reverse so pops preserve the original left-to-right visit order; the guard bounds the heap stack.
    struct CcFrame { TSNode node; std::uint32_t nesting; std::uint32_t ctrl; std::uint16_t depth; };   // ctrl: innermost enclosing ev arena index (kNoCtrl at root)
    std::vector<CcFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { start, startNesting, kNoCtrl, static_cast<std::uint16_t>( startDepth ) } );
    ChildCursor         cursor( start );
    std::vector<TSNode> kids;       kids.reserve( 64 );
    std::vector<TSNode> elifKids;   elifKids.reserve( 64 );   // the else-if grandchild descent below nests inside a kids iteration

    while( !stack.empty() )
    {
        const CcFrame frame = stack.back();
        stack.pop_back();
        if( frame.depth > 512 )
        {
            continue; // pathological-AST guard (file size is already capped at 1 MB)
        }
        const TSNode        n          = frame.node;
        const std::uint32_t nesting    = frame.nesting;
        const std::uint16_t childDepth = static_cast<std::uint16_t>( frame.depth + 1 );
        const char*         t          = ts_node_type( n );
        // NAMED-only gate for the control/decision predicates: Ruby's tree-sitter node kinds are bare words
        // (`if`, `for`, `while`, `case`, `when`, ...) that ALSO collide with the ANONYMOUS keyword TOKENS
        // several grammars (JS/TS) emit under those exact type strings. Anonymous keyword tokens are never a
        // real control subtree root in ANY of our grammars — only their named parents are — so requiring
        // ts_node_is_named here recovers the correct Ruby nodes while keeping C-family/JS byte-identical.
        // (The boolean-operator / binary_expression paths below are deliberately NOT gated — unchanged.)
        const bool isNamed = ts_node_is_named( n );

        // essential complexity: one arena/jump note per named node, and the ctrl index the children
        // inherit. All jump nodes are named in every supported grammar, and the isNamed gate is what
        // keeps Ruby's bare-word kinds from colliding with anonymous keyword tokens (see the note above).
        const std::uint32_t ctrl = ( evCtx != nullptr && isNamed ) ? ev_noteNode( *evCtx, n, t, frame.ctrl, lang, src ) : frame.ctrl;

        // cyclomatic (flat decision count) accumulated in the SAME DFS as cognitive — one walk, both metrics.
        if( isNamed && isDecisionType( t, lang ) )
        {
            ++acc.cyclo;
        }
        // ppalt disclosure: an alternative-introducing preproc node is neither control nor decision, so it
        // falls through to the generic descent below (its children ARE walked and summed — that summing is
        // exactly what this counter discloses).
        if( isNamed && cc_isPreprocAlternative( t ) )
        {
            ++acc.ppAlt;
        }
        // Phase 1 (local-variable-indexing): same fused DFS, third accumulator — zero extra tree-sitter
        // queries. countLocals is false for every non-C/C++ def (model.h localsCountedLang), so this whole
        // check compiles to a single branch-not-taken for every other language's walk. L3 fix (2026-08-08):
        // counts DECLARATORS (cc_countLocalDeclarators), not declaration statements — `int a,b,c;` is one
        // countable `declaration` node but three locals; see cc_countLocalDeclarators' own comment.
        if( countLocals && isNamed && cc_isCountableLocalDecl( n, t ) )
        {
            acc.locals += cc_countLocalDeclarators( n );
        }
        else if( std::strcmp( t, "binary_expression" ) == 0 && cc_isBooleanJoin( n, src, lang ) )
        {
            ++acc.cyclo;   // Myers' &&/|| extension — see cc_isBooleanJoin for the two spelling families
        }

        if( isNamed && cc_isNestingControl( t, lang ) )
        {
            const bool   isIf = ( std::strcmp( t, "if_statement" ) == 0 || std::strcmp( t, "if_expression" ) == 0 );
            const TSNode p    = ts_node_parent( n );
            const bool   elseIf = isIf && !ts_node_is_null( p )
                                  && ( std::strcmp( ts_node_type( p ), "if_statement" ) == 0 || std::strcmp( ts_node_type( p ), "if_expression" ) == 0 );
            const std::uint32_t childNest = elseIf ? nesting : nesting + 1;   // else-if doesn't deepen
            acc.cog += elseIf ? 1u : ( 1u + nesting );                           // flat +1 for else-if, else +1+nesting
            if( childNest > acc.maxNest )
            {
                acc.maxNest = childNest; // Q4: deepest control nesting reached
            }
            cc_noteHump( n, nesting, childNest, acc );   // profile: did THIS control cross the bar?
            collectChildren( n, cursor.cur, kids );
            for( std::size_t i = kids.size(); i > 0; --i )
            {
                stack.push_back( { kids[i - 1], childNest, ctrl, childDepth } );
            }
            continue;
        }
        if( isNamed && ( std::strcmp( t, "elif_clause" ) == 0 || std::strcmp( t, "else_clause" ) == 0
                         || std::strcmp( t, "elsif" ) == 0 ) )   // else / elif / else-if (+ Ruby `elsif`): flat +1 (cognitive)
        {
            acc.cog += 1u;
            collectChildren( n, cursor.cur, kids );
            for( std::size_t i = kids.size(); i > 0; --i )
            {
                const TSNode c  = kids[ i - 1 ];
                const char*  ct = ts_node_type( c );
                if( std::strcmp( ct, "if_statement" ) == 0 || std::strcmp( ct, "if_expression" ) == 0 )
                {
                    // C-family `else if`: descend into the if's CHILDREN so cognitive doesn't re-score it as a
                    // fresh control — but cyclomatic still counts that `if` as a decision (parity with the old walk).
                    // ev: that if never becomes a frame, so it gets its arena node HERE (Branch, weight 1 — 1:1
                    // with the cyclo increment above, preserving the structural ev <= cx containment).
                    ++acc.cyclo;
                    const std::uint32_t elifCtrl = ( evCtx != nullptr ) ? ev_appendCtrl( *evCtx, c, CtrlKind::Branch, 1, ctrl, lang, src ) : ctrl;
                    collectChildren( c, cursor.cur, elifKids );   // NOT kids — that iteration is still live
                    for( std::size_t j = elifKids.size(); j > 0; --j )
                    {
                        stack.push_back( { elifKids[j - 1], nesting, elifCtrl, childDepth } );
                    }
                }
                else
                {
                    // An else/elif body sits at the construct's PRIMARY-body level: `nesting` here is the
                    // clause's inherited frame nesting, which already carries the parent construct's +1 (the
                    // if pushed ALL its children at childNest). Deepening again — as this branch did before
                    // the nestcal r1 round — double-counted every clause body AND raised maxNest/minted one
                    // hump per clause CHILD (the anonymous keyword token, the condition, `:`), which is how a
                    // 20-line elif ladder reported humps=16. No maxNest bump and no cc_noteHump belong here:
                    // the parent construct recorded this depth when IT crossed, and a clause opens no new
                    // depth (matches Java/Go/C#, whose grammars have no clause node and were always flat).
                    // (ev rides along untouched: `ctrl` is the clause's own arena index from ev_noteNode.)
                    stack.push_back( { c, nesting, ctrl, childDepth } );
                }
            }
            continue;
        }
        if( cc_isNestingOnly( t ) )
        {
            if( nesting + 1 > acc.maxNest )
            {
                acc.maxNest = nesting + 1; // Q4: a lambda/closure body deepens nesting
            }
            cc_noteHump( n, nesting, nesting + 1, acc );
            collectChildren( n, cursor.cur, kids );
            for( std::size_t i = kids.size(); i > 0; --i )
            {
                stack.push_back( { kids[i - 1], nesting + 1, ctrl, childDepth } );
            }
            continue;
        }
        const std::string_view bop = cc_boolOp( n, src );
        if( !bop.empty() && cc_boolOp( ts_node_parent( n ), src ) != bop )
        {
            ++acc.cog; // new boolean run (cognitive)
        }

        collectChildren( n, cursor.cur, kids );
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], nesting, ctrl, childDepth } );
        }
    }
}
struct Complexity { std::uint32_t cx; std::uint32_t ccx; std::uint32_t maxNest; std::uint32_t locals; std::uint32_t ppAlt; std::uint32_t humps; std::uint32_t deepLoc; std::uint32_t ev; std::array<std::uint8_t, kEvWhyTagCount> evWhy; };
// `lang`: Phase 1 (local-variable-indexing) gates the locals accumulator to model.h's localsCountedLang
// (C/C++ only, MVP scope) INSIDE the same fused walk — every other language pays one branch-not-taken
// per node and gets locals=0, which the caller (this file, RawDef→Symbol) leaves at 0 and serialize.h
// never emits (absent, not a bare "0" — see localsCountedLang's own comment).
inline Complexity complexityOf( TSNode root, std::string_view src, Lang lang )   // one fused DFS → cx, ccx, maxNest, locals, ppAlt, the nesting profile, AND ev
{                                                                     // A4-F25: NOT noexcept — cc_walk (and kids here) allocate
    CcAccum acc;
    const bool countLocals = localsCountedLang( lang );
    // essential complexity rides the SAME walk (zero new tree-sitter queries). ONE arena/label/pending set
    // across all top-level children — a goto and its label can sit in sibling statements — finalized once
    // the whole def has been walked. nullptr outside evCountedLang: every other language pays one
    // branch-not-taken per node and gets ev=0, which serialize.h never emits (model.h evCountedLang).
    EvCtx        evCtx;
    EvCtx* const evPtr = evCountedLang( lang ) ? &evCtx : nullptr;
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );
    collectChildren( root, cursor.cur, kids );              // start INSIDE the def (the def node is neither control nor decision)
    // ONE accumulator across all top-level children: the deepEnd clamp has to see the whole def in document
    // order, and humps in sibling statements are humps of the same function.
    for( const TSNode c : kids )
    {
        cc_walk( c, 0, src, acc, 0, countLocals, lang, evPtr );
    }
    // cx = 1 + decisions ; ccx = nesting-weighted cognitive ; maxNest = deepest control nesting ;
    // locals = Phase 1 floor count ; ppAlt = preproc alternative branches (model.h Symbol::ppAlt) ;
    // humps/deepLoc = the nesting profile ; ev/evWhy = essential complexity (model.h Symbol) —
    // 0 outside evCountedLang, >= 1 inside it.
    Complexity out{ 1u + acc.cyclo, acc.cog, acc.maxNest, acc.locals, acc.ppAlt, acc.humps, acc.deepLoc, 0u, {} };
    if( evPtr != nullptr )
    {
        ev_finalize( evCtx, out.ev, out.evWhy );
    }
    return out;
}

// ── local-variable-indexing plan, Phase 2 (docs/LOCALS_INDEXING.md) ─────────────────────────────────
//
// bounded-depth: the identifier(s) a DECLARATOR subtree ultimately names, following ONLY the grammar's
// "declarator:" field at each wrapper level (never "value:"/"size:"/"type:" — those hold an initializer
// expression / array-size expression / type qualifier, whose own identifiers are USE sites, not the local's
// own name; `int arr[n]` would otherwise wrongly harvest the USE of `n` as if it were a declared name).
// EXPLICIT allowlist of wrapper shapes, verified against the vendored grammar via a real parse-tree dump
// (not assumed — the exact same discipline Phase 1's structured-binding fix needed): init_declarator,
// pointer_declarator, array_declarator all expose a "declarator:" field; reference_declarator's inner
// identifier is an ANONYMOUS single child (no field name at all in this grammar — verified the same way).
// A node type NOT in this allowlist (e.g. a local function-pointer declarator, or anything the dump did not
// cover) is left UN-descended — silently fewer names captured is the safe floor outcome; a wrong or
// misattributed name is the failure mode this walk exists to avoid, per the WITHDRAWN naming-body-mismatch
// lesson (src/naminglens.h's own note): reasoning-only "this shape probably parses like X" is exactly what
// shipped wrong there.
inline void ln_extractDeclaratorIdentifiers( TSNode node, std::vector<TSNode>& outIdents, int depth ) noexcept
{
    if( depth <= 0 )
    {
        return;   // pathological-AST guard — real declarator nesting never legitimately needs this deep
    }
    const char* t = ts_node_type( node );
    if( std::strcmp( t, "identifier" ) == 0 || std::strcmp( t, "field_identifier" ) == 0 )
    {
        outIdents.push_back( node );
        return;
    }
    if( std::strcmp( t, "reference_declarator" ) == 0 )
    {
        const std::uint32_t n = ts_node_child_count( node );
        for( std::uint32_t i = 0; i < n; ++i )
        {
            ln_extractDeclaratorIdentifiers( ts_node_child( node, i ), outIdents, depth - 1 );
        }
        return;
    }
    if( std::strcmp( t, "init_declarator" ) == 0 || std::strcmp( t, "pointer_declarator" ) == 0 || std::strcmp( t, "array_declarator" ) == 0 )
    {
        const std::uint32_t n = ts_node_child_count( node );
        for( std::uint32_t i = 0; i < n; ++i )
        {
            const char* fieldName = ts_node_field_name_for_child( node, i );
            if( fieldName != nullptr && std::strcmp( fieldName, "declarator" ) == 0 )
            {
                ln_extractDeclaratorIdentifiers( ts_node_child( node, i ), outIdents, depth - 1 );
            }
        }
        return;
    }
    // unrecognized wrapper (incl. structured_binding_declarator, which should never reach here — Phase 1's
    // cc_isCountableLocalDecl already excludes any `declaration` containing one before this ever runs):
    // do not descend.
}

// one `declaration` node (already proven countable by cc_isCountableLocalDecl) → every declarator name it
// introduces (plural: `int a, b;` is ONE declaration with TWO "declarator:"-fielded children — since the L3
// fix, Phase 1's COUNT (cc_countLocalDeclarators, above) agrees with Phase 2 here at the SLOT level: both
// count 2. They still differ one level deeper — this walk recurses INTO each slot to find the actual name
// node(s) Phase 2 judges, where Phase 1 only needs the slot count — reusing cc_isDeclaratorField for the
// shared "which children are declarator slots" scan, not re-typing the field-name check.
inline void ln_declaratorIdentifiers( TSNode declNode, std::vector<TSNode>& outIdents )
{
    const std::uint32_t n = ts_node_child_count( declNode );
    for( std::uint32_t i = 0; i < n; ++i )
    {
        if( cc_isDeclaratorField( declNode, i ) )
        {
            ln_extractDeclaratorIdentifiers( ts_node_child( declNode, i ), outIdents, 6 );
        }
    }
}

// declDepth: count of `compound_statement` ancestors from `declNode` up to and including the function's
// OWN outermost body block (stops at `funcRoot`, the re-parsed def's root node) — so a direct top-level
// local gets declDepth=1, and a local one control-structure block deeper gets declDepth=2+, matching
// checkLocalNameShape's own declDepth>=2 gate (naminglens.h) exactly.
inline std::uint8_t ln_declDepth( TSNode declNode, TSNode funcRoot ) noexcept
{
    std::uint8_t depth = 0;
    TSNode       cur   = ts_node_parent( declNode );
    while( !ts_node_is_null( cur ) )
    {
        if( std::strcmp( ts_node_type( cur ), "compound_statement" ) == 0 )
        {
            ++depth;
            if( depth == 255 )
            {
                break;   // pathological-AST guard — matches the declDepth field's own uint8_t width
            }
        }
        if( ts_node_eq( cur, funcRoot ) )
        {
            break;
        }
        cur = ts_node_parent( cur );
    }
    return depth;
}

// bounded-width recursive descent over the WHOLE re-parsed def subtree, collecting every countable local
// declaration's name(s) — reuses cc_isCountableLocalDecl/cc_declHasStructuredBinding UNCHANGED, so the SET
// of declarations this walk visits is provably the same set Phase 1's `locals=` count already covers (no
// second, silently divergent detection rule). NOT the cursor/stack machinery cc_walk uses for a whole-
// function hot-path walk — this only ever runs on an ALREADY-GATED (rare) function, so a plain recursive
// walk (bounded by the same depth guard) is the right tool, not premature machinery.
inline void ln_collectLocalDecls( TSNode node, TSNode funcRoot, int depth, std::vector<LocalNameFact>& out,
                                   std::uint32_t defStartLine, std::string_view defBytes )
{
    if( depth <= 0 )
    {
        return;   // pathological-AST guard (mirrors cc_walk's own 512-frame guard, scaled to plain recursion)
    }
    const char* t = ts_node_type( node );
    if( ts_node_is_named( node ) && cc_isCountableLocalDecl( node, t ) )
    {
        std::vector<TSNode> idents;
        ln_declaratorIdentifiers( node, idents );
        const std::uint8_t declDepth = ln_declDepth( node, funcRoot );
        for( const TSNode& id : idents )
        {
            const std::uint32_t startByte = ts_node_start_byte( id );
            const std::uint32_t endByte   = std::min( ts_node_end_byte( id ), std::uint32_t( defBytes.size() ) );
            if( endByte <= startByte )
            {
                continue;
            }
            // row is relative to the RE-PARSED SUBSTRING (starts at row 0 = defStartLine); absolute file
            // line = defStartLine + row, so a caller never has to know this function re-parses in isolation.
            const std::uint32_t row = ts_node_start_point( id ).row;
            LocalNameFact        fact;
            fact.line      = defStartLine + row;
            fact.declDepth = declDepth;
            fact.name.assign( defBytes.substr( startByte, endByte - startByte ) );
            out.push_back( std::move( fact ) );
        }
        return;   // do not descend INTO a countable declaration's own subtree again (nothing further to find)
    }
    const std::uint32_t n = ts_node_child_count( node );
    for( std::uint32_t i = 0; i < n; ++i )
    {
        ln_collectLocalDecls( ts_node_child( node, i ), funcRoot, depth - 1, out, defStartLine, defBytes );
    }
}

// collectGatedLocalNames itself (the ingest.h-declared, EXTERNAL-linkage entry point) is defined further
// down, OUTSIDE this anonymous namespace — same split as ingest()/astQueryGrouped() in this same file:
// an anonymous-namespace definition would give it INTERNAL linkage, which cannot satisfy ingest.h's
// declaration. The ln_* helpers above stay in here (internal-only, next to cc_walk/complexityOf which they
// mirror) and remain visible to that later definition, exactly like ingest()/astQueryGrouped() already
// call plenty of anonymous-namespace-scoped helpers from outside the namespace block in this same TU.

// Q4 PARAMETER COUNT: find the def's parameter-list node and count its formal parameters. Parameter-list
// node types across our 7 grammars: C++/ObjC `parameter_list`, Python/TS `parameters`/`formal_parameters`,
// Go `parameter_list`, Rust `parameters`, Swift `parameter_clause`/`parameters`. The list is not always a
// direct child of the def node (C++ wraps it in a function_declarator), so we do a bounded pre-order search
// for the FIRST such list within the def subtree, then count its named parameter children (commas/parens are
// anonymous nodes and are skipped by ts_node_is_named). Deterministic + allocation-free. Reported as a raw
// NUMBER on --metrics (never a 7±2 threshold — that myth is debunked, §1d kill-list).
inline bool cc_isParamList( const char* t ) noexcept
{
    return    std::strcmp( t, "parameter_list" )   == 0     // C++/ObjC/Go
           || std::strcmp( t, "parameters" )       == 0     // Python / Rust / Swift
           || std::strcmp( t, "formal_parameters" )== 0     // TypeScript / JS
           || std::strcmp( t, "parameter_clause" ) == 0     // Swift
           || std::strcmp( t, "method_parameters" )== 0     // Ruby `def f(a, b)`
           || std::strcmp( t, "block_parameters" ) == 0     // Ruby `{ |x, y| ... }`
           || std::strcmp( t, "lambda_parameters" )== 0;    // Ruby `->(n) { ... }`
}
// a named parameter node (skip `self`/`this`-only? no — count as written, deterministic). Anonymous separators
// (',', '(', ')') are unnamed → excluded by ts_node_is_named.
inline std::uint16_t countParams( TSNode defNode )   // A4-F25: NOT noexcept — allocates (see cc_walk)
{
    // bounded pre-order search for the FIRST parameter list inside the def; then count its named children.
    struct PF { TSNode n; std::uint16_t depth; };
    std::vector<PF> stack;
    stack.reserve( 32 );
    stack.push_back( { defNode, 0 } );
    ChildCursor         cursor( defNode );
    std::vector<TSNode> kids;
    kids.reserve( 32 );
    while( !stack.empty() )
    {
        const PF f = stack.back();
        stack.pop_back();
        if( f.depth > 12 )
        {
            continue; // params live near the signature; bound the search
        }
        const char* t = ts_node_type( f.n );
        collectChildren( f.n, cursor.cur, kids );           // one collection serves both arms below
        if( f.n.id != defNode.id && cc_isParamList( t ) )   // don't treat the def node itself as a param list
        {
            std::uint16_t count = 0;
            for( const TSNode c : kids )
            {
                if( !ts_node_is_named( c ) )
                {
                    continue; // skip '(', ')', ',' separators
                }
                const char* ct = ts_node_type( c );
                if( std::strcmp( ct, "comment" ) == 0 )
                {
                    continue; // a comment inside the list is not a parameter
                }
                ++count;
            }
            return count;
        }
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], std::uint16_t( f.depth + 1 ) } );
        }
    }
    return 0;
}

// B2.2 CALL-COMPARABLE ARITY: is `params` a FIXED arity that can be compared 1:1 against a call site's
// positional-argument count? True ONLY when EVERY qualifying condition holds, so the safe default (any
// uncertainty) is FALSE → the resolver never arity-filters that candidate (zero false negatives). Conditions:
//   * the language is one whose method params do NOT include an implicit receiver AND whose default/variadic
//     forms we can positively detect (C++/Java/Swift/TS/JS). Python is filterable for FREE FUNCTIONS only —
//     a Python/Ruby METHOD lists `self`/`cls`, which the call site omits, so a naive count is off by one.
//   * the def actually HAS a parameter-list node (an empty `()` counts — a real 0-arity), and
//   * that list contains NO variadic (`...`, `*args`/`**kwargs`, Java `...`, rest `...x`) and NO defaulted /
//     optional parameter (`= v`, TS `x?`) — any of which makes the accepted arity a RANGE, not a point.
// A bounded pre-order scan of the FIRST parameter list mirrors countParams; deterministic + allocation-free.
//
// Residual conservative gap (honest): a C++ default argument written ONLY on a separate PROTOTYPE
// (`void f( int x = 5 );` in a header) and NOT on the definition (`void f( int x ){…}`) is invisible here —
// the definition's parameter shows no default. byName resolves a call to the DEFINITION, so such a candidate
// reads as a fixed arity==params. This is a source-visibility limit (the default lives on an uncaptured
// decl), not a logic bug; it can only bite when ≥2 same-name overloads are same-file/dir AND the true target
// relies on a header-only default. Whenever the default IS on the definition (the common case) the arity is
// correctly treated as elastic and the candidate is never filtered.
//
// Decided: graph.h's arity filter only excludes on `argCount > params`, so
// this residual gap can no longer drop the correct edge for an (params-1)-arg call — the header-default def
// stays a candidate and correctly re-enters amb= when a sibling overload survives too. The gap is now
// strictly a precision (not honesty) limit: a too-many-args call still provably excludes on the def's
// visible arity regardless of where a default lives, which is sound in every language.
inline bool cc_paramArityExact( TSNode defNode, Lang lang, SymKind kind ) noexcept
{
    // language / kind gate — see the header. Only these emit a filterable point arity.
    const bool langOk =    lang == Lang::Cpp || lang == Lang::Java || lang == Lang::Swift
                        || lang == Lang::TypeScript || lang == Lang::JavaScript || lang == Lang::Python;
    if( !langOk )
    {
        return false;
    }
    if( ( lang == Lang::Python || lang == Lang::Ruby ) && kind == SymKind::Method )
    {
        return false; // implicit self/cls
    }

    // an "elastic" (variadic / default / optional) node kind or token makes the arity a RANGE → not filterable.
    const auto isElastic = []( const char* t ) noexcept
    {
        return    std::strstr( t, "variadic" ) != nullptr || std::strstr( t, "splat" )   != nullptr
               || std::strstr( t, "spread" )   != nullptr || std::strstr( t, "optional" )!= nullptr
               || std::strstr( t, "default" )  != nullptr || std::strcmp( t, "rest_pattern" ) == 0
               || std::strcmp( t, "..." ) == 0 || std::strcmp( t, "=" ) == 0;
    };

    struct PF { TSNode n; std::uint16_t depth; };
    std::vector<PF> stack;
    stack.reserve( 32 );
    stack.push_back( { defNode, 0 } );
    ChildCursor         cursor( defNode );
    std::vector<TSNode> kids;
    kids.reserve( 32 );
    while( !stack.empty() )
    {
        const PF f = stack.back();
        stack.pop_back();
        if( f.depth > 12 )
        {
            continue;
        }
        const char* t = ts_node_type( f.n );
        if( f.n.id != defNode.id && cc_isParamList( t ) )       // the FIRST parameter list — scan it for elastic forms
        {
            struct QF { TSNode n; std::uint16_t depth; };
            std::vector<QF> q;
            q.reserve( 32 );
            q.push_back( { f.n, 0 } );
            while( !q.empty() )                                 // never returns to the outer loop → reusing kids below is safe
            {
                const QF g = q.back();
                q.pop_back();
                if( g.depth > 6 )
                {
                    continue; // param forms live shallow inside the list
                }
                if( g.n.id != f.n.id && isElastic( ts_node_type( g.n ) ) )
                {
                    return false;
                }
                collectChildren( g.n, cursor.cur, kids );
                for( const TSNode c : kids )
                {
                    q.push_back( { c, std::uint16_t( g.depth + 1 ) } );
                }
            }
            return true;                                        // a real parameter list, no elastic form → fixed arity
        }
        collectChildren( f.n, cursor.cur, kids );
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], std::uint16_t( f.depth + 1 ) } );
        }
    }
    return false;   // no parameter-list node found at all → can't be sure → not filterable (safe)
}

// B2.2 CALL-SITE ARITY: count the positional arguments of the call whose callee identifier is `nameNode`.
// Returns { argCount, known }. `known` is true ONLY when a recognized call node + argument container is
// found for a supported language AND no spread/splat/apply argument is present (which would make the count
// unreliable). Any uncertainty → { 0, false } so the resolver never arity-filters that call (zero false
// negatives). Pure-syntactic, deterministic, allocation-free. Languages: C++/Python/TS/JS/Java/Swift/C#.
inline std::pair<std::uint16_t, bool> callArity( TSNode nameNode, Lang lang, std::string_view /*src*/ ) noexcept
{
    // walk up a bounded number of parents to the enclosing CALL node (the callee sits 1-2 levels below it).
    TSNode call{};
    bool   found = false;
    TSNode n = nameNode;
    for( int hop = 0; hop < 4 && !ts_node_is_null( n ); ++hop )
    {
        const TSNode p = ts_node_parent( n );
        if( ts_node_is_null( p ) )
        {
            break;
        }
        const char* pt = ts_node_type( p );
        if(    std::strcmp( pt, "call_expression" )       == 0     // C++/TS/JS/Swift
            || std::strcmp( pt, "call" )                  == 0     // Python
            || std::strcmp( pt, "method_invocation" )     == 0     // Java
            || std::strcmp( pt, "invocation_expression" ) == 0 )   // C#
        { call = p; found = true; break; }
        n = p;
    }
    if( !found )
    {
        return { 0, false };
    }

    // find the argument container: the `arguments` field, else the first child of a known list type.
    TSNode args = ts_node_child_by_field_name( call, "arguments", 9 );
    if( ts_node_is_null( args ) )
    {
        const std::uint32_t cc = ts_node_child_count( call );
        for( std::uint32_t i = 0; i < cc; ++i )
        {
            const TSNode c = ts_node_child( call, i );
            const char* ct = ts_node_type( c );
            if(    std::strcmp( ct, "argument_list" )  == 0 || std::strcmp( ct, "arguments" ) == 0
                || std::strcmp( ct, "value_arguments" )== 0 )     // Swift
            { args = c; break; }
        }
    }
    if( ts_node_is_null( args ) )
    {
        return { 0, false };
    }

    // count NAMED argument children; a spread / splat / apply argument makes the count unreliable → not known.
    std::uint16_t count = 0;
    const std::uint32_t an = ts_node_child_count( args );
    for( std::uint32_t i = 0; i < an; ++i )
    {
        const TSNode c = ts_node_child( args, i );
        if( !ts_node_is_named( c ) )
        {
            continue; // skip '(' ')' ',' separators
        }
        const char* ct = ts_node_type( c );
        if( std::strcmp( ct, "comment" ) == 0 )
        {
            continue;
        }
        if( std::strstr( ct, "splat" ) != nullptr || std::strstr( ct, "spread" ) != nullptr || std::strcmp( ct, "..." ) == 0 )
        {
            return { 0, false };                                  // `f(*args)` / `f(...xs)` → unreliable
        }
        ++count;
    }
    (void)lang;
    return { count, true };
}
}   // namespace — ingest_metrics.h section of ingest.cpp

}   // namespace rw
