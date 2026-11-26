#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_metrics.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_metrics.h — the per-definition structural metrics, moved VERBATIM from ingest.cpp in the
// 2026-08-29 split: cyclomatic complexity (Myers' &&/|| extension), cognitive complexity with its
// nesting/hump accounting (the O(children) child collection it used to hold, ChildCursor/collectChildren,
// now lives in src/infra/tschildren.h so walks outside this TU can obey the same rule), the
// essential-complexity ev(G) single-exit reduction (CtrlNode arena, EvCtx, the why-tag taxonomy),
// the local-variable-indexing walk (ln_*), the fused complexityOf DFS, and parameter/arity counting
// (countParams, cc_paramShape, callArity). Pure metric machinery: reads an AST, fills RawDef
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
    return    kindIs( t, "if_statement" )       || kindIs( t, "if_expression" )
           || kindIs( t, "for_statement" )      || kindIs( t, "for_range_loop" )
           || kindIs( t, "for_in_statement" )   || kindIs( t, "for_expression" )
           || kindIs( t, "while_statement" )    || kindIs( t, "while_expression" )
           || ( kindIs( t, "do_statement" ) && lang != Lang::Lua ) || kindIs( t, "loop_expression" )
           || ( lang == Lang::Kotlin && kindIs( t, "do_while_statement" ) )   // Kotlin's own do/while spelling —
                                                                             // lang test first so every other
                                                                             // language short-circuits on one
                                                                             // byte compare (this chain runs per
                                                                             // named node of every def body)
           // Lua: `repeat … until c` is a real post-test loop, and `elseif c then` is the flat +1 arm of
           // an if-chain (a SIBLING statement in this grammar, not a child clause, so cc_walk's else-if
           // flattening below never sees it and it must be counted here).
           || kindIs( t, "repeat_statement" )   || kindIs( t, "elseif_statement" )
           // PHP 8: each `match` arm is a decision, exactly like C#'s switch_expression_arm and Ruby's
           // `when`. `match_default_expression` is the fall-through arm and is deliberately NOT counted,
           // matching how a C-family `default:` label is not a decision.
           || kindIs( t, "match_conditional_expression" )
           || kindIs( t, "case_statement" )     || kindIs( t, "match_arm" )
           || kindIs( t, "expression_case" )    || kindIs( t, "communication_case" )
           || kindIs( t, "catch_clause" )       || kindIs( t, "except_clause" )
           || kindIs( t, "conditional_expression" ) || kindIs( t, "ternary_expression" )
           || kindIs( t, "boolean_operator" )    // Python `and`/`or`
           // Kotlin: each `when { }` arm is a `when_entry`, the per-arm decision — matching how C#'s
           // switch_expression_arm and Ruby's `when` are counted, NOT the `when_expression` head (that is
           // a nesting container, see cc_isNestingControl, the same split as Ruby's case/case_match vs
           // when/in_clause). `catch_block` is this grammar's OWN spelling of a catch handler (not
           // `catch_clause`) — but `catch_block` is ALSO a real node-type spelling in the vendored Swift
           // and Elixir grammars, where it is a PRE-EXISTING, disclosed gap (neither language's catch is
           // counted today, matching how Elixir's try/rescue routes entirely through the separate
           // elixirDecision keyword channel below, not through this predicate). Un-guarded, this string
           // would silently start counting Swift's and Elixir's catch too — an undisclosed behavior change
           // to two already-shipped languages, out of scope for the Kotlin port. `lang` scopes it to Kotlin
           // only, same carve-out shape as the Lua `do_statement` guard above.
           || ( lang == Lang::Kotlin && ( kindIs( t, "when_entry" ) || kindIs( t, "catch_block" ) ) )
           // GDScript: `pattern_section` is one `match` ARM — the decision, exactly as Kotlin's
           // when_entry and the C-family case_statement are. The `match_statement` CONTAINER scores
           // flat +1 in cc_isNestingControl instead, so the two never double-count the same arm.
           || ( lang == Lang::GDScript && kindIs( t, "pattern_section" ) )
           // Ruby (tree-sitter-ruby node kinds): block `if`/`elsif`/`unless`/`while`/`until`/`for`, the
           // trailing modifier forms (`x if a`), each `when`/`in_clause` arm, `rescue`, and the `? :`
           // `conditional`. Ruby's `case`/`case_match` head is a nesting container (see cc_isNestingControl),
           // NOT a decision — each `when`/`in_clause` arm is the decision, matching C-family case_statement.
           || kindIs( t, "if" )                 || kindIs( t, "elsif" )
           || kindIs( t, "unless" )             || kindIs( t, "while" )
           || kindIs( t, "until" )              || kindIs( t, "for" )
           || kindIs( t, "if_modifier" )        || kindIs( t, "unless_modifier" )
           || kindIs( t, "while_modifier" )     || kindIs( t, "until_modifier" )
           || kindIs( t, "when" )               || kindIs( t, "in_clause" )
           || kindIs( t, "rescue" )             || kindIs( t, "conditional" )
           // C# (tree-sitter-c-sharp): `foreach` is a distinct loop node (not `for_statement`); each
           // classic-switch `case`/`default` arm is a `switch_section`, each modern switch-expression
           // arm is a `switch_expression_arm` — both are the per-arm decision, matching Ruby's `when`.
           || kindIs( t, "foreach_statement" )   || kindIs( t, "switch_section" )
           || kindIs( t, "switch_expression_arm" )
           // Swift `guard cond else { exit }` — a decision point every cyclomatic tool counts, previously
           // missed (kParserVer 44). Also load-bearing for essential complexity: ev's per-construct weights
           // mirror this predicate exactly (ev_ctrl machinery below), so counting the guard-else exit in ev
           // without counting the guard here would break the structural ev <= cx containment.
           || kindIs( t, "guard_statement" );
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
    return    kindIs( t, "if_statement" )      || kindIs( t, "if_expression" )
           || kindIs( t, "for_statement" )     || kindIs( t, "for_range_loop" )
           || kindIs( t, "for_in_statement" )  || kindIs( t, "for_expression" )
           || kindIs( t, "while_statement" )   || kindIs( t, "while_expression" )
           || ( kindIs( t, "do_statement" ) && lang != Lang::Lua ) || kindIs( t, "loop_expression" )
           || ( lang == Lang::Kotlin && kindIs( t, "do_while_statement" ) )   // Kotlin's own do/while spelling (lang test first, see isDecisionType)
           // Lua `repeat … until c` opens a nested body and scores, exactly like `while`. Lua's
           // `elseif_statement` is deliberately absent for the C-family else-if reason: flat +1, no deeper
           // nesting — and because it is a SIBLING here, cc_walk's else-if detector cannot flatten it, so
           // admitting it would charge 1+nesting for what is one arm of one chain.
           || kindIs( t, "repeat_statement" )
           || kindIs( t, "switch_statement" )  || kindIs( t, "switch_expression" )
           || kindIs( t, "match_expression" )
           || kindIs( t, "catch_clause" )      || kindIs( t, "except_clause" )
           || kindIs( t, "conditional_expression" ) || kindIs( t, "ternary_expression" )
           // Kotlin: `when_expression` is the switch-equivalent CONTAINER (flat +1, arms score via
           // isDecisionType's when_entry) — mirrors switch_statement/case_match above. `catch_block` is
           // this grammar's own spelling of a catch handler (own nested body, scores like catch_clause) —
           // but it is ALSO a real node-type spelling in the vendored Swift/Elixir grammars (a PRE-EXISTING,
           // disclosed gap there, out of scope for the Kotlin port — see isDecisionType's matching comment),
           // so `lang` scopes it to Kotlin only.
           || ( lang == Lang::Kotlin && ( kindIs( t, "when_expression" ) || kindIs( t, "catch_block" ) ) )
           // GDScript: `match_statement` is the switch-equivalent CONTAINER (flat +1; the arms score
           // through isDecisionType's pattern_section) — mirrors switch_statement/when_expression.
           || ( lang == Lang::GDScript && kindIs( t, "match_statement" ) )
           // Ruby (tree-sitter-ruby): the block control forms each open a nested body, so they raise nesting
           // AND score. `case`/`case_match` is the switch-equivalent container (flat +1, arms score via
           // isDecisionType — mirrors switch_statement). The trailing MODIFIER forms (`x if a`) have no nested
           // body and are deliberately absent here — they count as decisions only, matching the C-family model.
           || kindIs( t, "if" )                || kindIs( t, "unless" )
           || kindIs( t, "while" )             || kindIs( t, "until" )
           || kindIs( t, "for" )               || kindIs( t, "case" )
           || kindIs( t, "case_match" )        || kindIs( t, "rescue" )
           || kindIs( t, "conditional" )
           || kindIs( t, "foreach_statement" );   // C# `foreach (var x in xs)` — a distinct loop node
           // NOTE: Ruby `elsif` is intentionally NOT here — like a C-family else-if / Python elif_clause it is a
           // flat +1 that does not deepen nesting; it is handled in the elif_clause/else_clause branch of cc_walk.
}
inline bool cc_isNestingOnly( const char* t ) noexcept   // raises nesting, scores nothing (lambdas/closures)
{
    return    kindIs( t, "lambda_expression" ) || kindIs( t, "lambda" )
           || kindIs( t, "closure_expression" );
}

// A node's source text, or "" when the node is null or its byte range does not lie inside `src`. The
// null+range guard is the same three lines every extraction helper in this file would otherwise repeat (it
// is what --quality-delta flagged as a clone when the Rust helpers open-coded it, and again when the
// preprocessor include readers did), so it lives once, here — hoisted above the first consumer rather
// than sitting halfway down the file where three helpers ahead of it could not reach it.
//
// A FIELD read is the common case: nodeFieldText( n, NodeField::Operator, src ) is the whole of what most
// callers want, and infra/fieldid.h is what keeps the field's id out of the per-node path (see it for why).
inline std::string_view nodeTextOf( TSNode node, std::string_view src ) noexcept
{
    if( ts_node_is_null( node ) )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( node ), b = ts_node_end_byte( node );
    return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
}

inline std::string_view nodeFieldText( TSNode node, NodeField field, std::string_view src ) noexcept
{
    return nodeTextOf( fieldChild( node, field ), src );
}

// First DIRECT child of `n` whose node type is `type`, or a null node when none exists — the one
// child-scan shape every ingest_*.h section reuses (the using-declaration keyword guard and the
// phantom-`::` probe in ingest_names.h, the Kotlin scope walker, the Kotlin import_header reader in
// ingest_relations.h), so they cannot drift into near-clones of each other. Lives here, beside
// nodeTextOf, because this header is included before every section that needs it. O(children): lane W3
// kept this indexed because "the width comes from the grammar", and `using /*…*/ namespace ns::inner;`
// refuted that at 12.9x its control (test/childwalkscalecheck.sh, arm B22) — the comments are the
// using_declaration's own children, like every extra (src/infra/tschildren.h).
inline TSNode firstChildOfType( TSNode n, const char* type ) noexcept
{
    return firstChildOfKind( n, /*namedOnly=*/false, { type } );
}

// The written spelling of a node's `operator:` field, or "" when it has none / the span is out of range.
// ONE derivation, shared by the two consumers below — cc_boolOp (cognitive: does this operator CONTINUE
// a boolean run?) and cc_isBooleanJoin (cyclomatic: does it count as a decision at all?). They ask
// different questions of the same string, and before the PHP/Lua port they answered them from two
// hand-copied spans — a duplication --quality-delta scored the moment the second one grew a case.
inline std::string_view cc_operatorText( TSNode n, std::string_view src ) noexcept
{
    const std::string_view viaOperator = nodeFieldText( n, NodeField::Operator, src );
    if( !viaOperator.empty() )
    {
        return viaOperator;
    }
    // tree-sitter-gdscript names the field `op`, not `operator` — its binary_operator carries
    // left/op/right. Every language that resolves through `operator` above is untouched by this
    // fallback (it only runs when that field is absent), so the widening cannot move an existing
    // score; without it GDScript's `and`/`or`/`&&`/`||` joins read as empty and never count.
    return nodeFieldText( n, NodeField::Op, src );
}

// the boolean-operator spelling of a node, or "" if it isn't one (&&/|| for C-family, and/or for Python)
inline std::string_view cc_boolOp( TSNode n, std::string_view src ) noexcept
{
    const std::string_view o = cc_operatorText( n, src );
    return ( o == "&&" || o == "||" || o == "and" || o == "or" ) ? o : std::string_view{};
}

// Myers' &&/|| extension for CYCLOMATIC counting: does this binary operator join two conditions?
// Extracted from cc_walk rather than written inline — the PHP/Lua port needed a second spelling family
// (the WORD operators), and the inline form scored a measured +12 cx / +13 LOC on cc_walk, which is a
// --quality-delta regression on a function already at the top of this file's complexity distribution.
//
// Two spelling families, and the Lang gate is what keeps the second from touching any other grammar:
//   * `&&` / `||` — symbolic joins in the binary-expression nodes visited by cc_walk.
//   * `and`/`or` — Lua, PHP and Elixir; `xor` — PHP only. `or` is also two bytes, so the Lang test,
//     not the length test, keeps a grammar's non-boolean spelling from accidentally scoring.
// Python is deliberately absent from both: its `and`/`or` parse to a `boolean_operator` NODE, which
// isDecisionType already names, so counting it here too would double it.
/// Recognize short-circuit boolean joins, including word operators supported by the given language.
inline bool cc_isBooleanJoin( TSNode n, std::string_view src, Lang lang ) noexcept
{
    const std::string_view o        = cc_operatorText( n, src );
    const bool             wordLang = ( lang == Lang::Lua || lang == Lang::Php || lang == Lang::Elixir
                                       || lang == Lang::GDScript );
    return    o == "&&" || o == "||"
           || ( wordLang && ( o == "and" || o == "or" ) )
           || ( lang == Lang::Php && o == "xor" );
}

// ── O(children) child collection for whole-subtree walks ─────────────────────────────────────────────
// ChildCursor / collectChildren MOVED to src/infra/tschildren.h (audit P1-0, 2026-09-10). They were
// defined here, inside this TU's unnamed namespace, which put them out of reach of the whole-subtree
// walks compiled outside ingest.cpp — src/preprocdead.h kept the indexed O(C²) form for exactly that
// reason and cost 56.67% of a cold llvm run. Unqualified lookup from this unnamed namespace still
// finds rw::collectChildren, so every call site below is unchanged; the rule they enforce, and why a
// bounded-shape scan keeps the indexed form, are stated in full on the new header.

// bounded-depth search for a structured_binding_declarator anywhere under `n` — the vendored tree-sitter-cpp
// grammar nests it TWO levels below the `declaration` node (declaration -> init_declarator ->
// structured_binding_declarator for `auto [a,b] = …`; verified against the vendored grammar via a parse-tree
// dump, not assumed), so a same-level-only child scan misses it. The DEPTH is grammar-bounded and still
// capped here; the WIDTH is not, and an earlier revision of this comment claimed it was. A `declaration`'s
// child list carries every comment between its type and its declarator as a direct child — extras are
// spliced into the array, not balanced by a repeat node (src/infra/tschildren.h) — so the indexed scan this
// used to be was O(C²) and measured 797 of the 2 956 child-iterator samples on a 16 000-comment declaration
// (test/childwalkscalecheck.sh, arm B7). Each frame owns its cursor: the loop body recurses.
inline bool cc_declHasStructuredBinding( TSNode n, int depth )
{
    return anyChildBelow( n, depth, false, []( TSNode child ) { return kindIs( ts_node_type( child ), "structured_binding_declarator" ); } );
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
    if( !kindIs( t, "declaration" ) )
    {
        return false;
    }
    const TSNode parent = parentOf( n );
    if( ts_node_is_null( parent ) || !kindIs( ts_node_type( parent ), "compound_statement" ) )
    {
        return false;
    }
    return !cc_declHasStructuredBinding( n, 4 );
}

// shared by cc_countLocalDeclarators (below) and ln_declaratorIdentifiers (Phase 2, further down): is child
// `ci` of `declNode` one comma-separated declarator SLOT? The vendored grammar gives every comma-separated
// declarator its own `declarator`-FIELDED direct child of the `declaration` node (`int a=1,b=2;` has TWO) —
// pulled out to ONE predicate so the two counting/walking loops that need it never drift on the field name.
// Takes the child's FIELD NAME, not its index: `ts_node_field_name_for_child( declNode, ci )` restarts
// tree-sitter's child iterator at the first child on every call, so both loops below were O(C²) in a
// declaration's child count — a width a comment run sets, not the grammar (arm B7). Off a cursor,
// `ts_tree_cursor_current_field_name` answers the identical question in O(1): NULL for an extra, else the
// non-inherited field at the child's structural index, else the name inherited through the invisible nodes
// above it (third_party/deps/tree_sitter/lib/src/tree_cursor.c:657 vs node.c:689).
inline bool cc_isDeclaratorFieldName( const char* fieldName ) noexcept
{
    return fieldName != nullptr && kindIs( fieldName, "declarator" );
}

// …and the ONE walk over those slots, for the same reason the predicate is shared: cc_countLocalDeclarators
// and ln_declaratorIdentifiers ask the identical question of the identical child list and must never drift.
template< class Fn >
inline void forEachDeclaratorSlot( TSNode declNode, const Fn& fn )
{
    ChildCursor cursor( declNode );
    forEachChild( declNode, cursor.cur, [ & ]( TSNode c ) { if( cc_isDeclaratorFieldName( ts_tree_cursor_current_field_name( &cursor.cur ) ) ) { fn( c ); } return true; } );
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
inline std::uint32_t cc_countLocalDeclarators( TSNode n )
{
    std::uint32_t count = 0;
    forEachDeclaratorSlot( n, [ &count ]( TSNode ) { ++count; } );
    return count;
}

// QD-TANGLE BLOCK FACTS (tangleBlocks_* below): the index of no top-level block — before the first one, or a slot no top-level
// statement declared.
inline constexpr std::uint32_t kNoTangleBlock = 0xFFFFFFFFu;

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
    // QD-TANGLE steering locals (model.h Symbol::steer) — the walk's one new fact, filled only when `steerOn` (a function over 50
    // lines in a language with a langfacts.h steerDecl). `stmt` is the statement ordinal in document order (the DFS pops left to right), the clock the
    // 10-statement distance is measured on; `slots` are the candidate locals seen so far, searched newest first (a shadowing
    // redeclaration wins). `detail` is null in ingest; tangleDetailOf (--quality-delta time, one function) points it at the names.
    bool                   tangleOn     = false;   // a body over 50 lines: the flat-dispatch tagging below runs (every language)
    bool                   steerOn      = false;   // ... and in a language with a langfacts.h steerDecl: the steering locals too
    bool                   anyRewritten = false;   // some slot was written after its declaration: until then no condition can steer
    std::uint32_t          stmt         = 0;
    std::uint32_t          steered      = 0;       // distinct slots that steered a branch → Symbol::steer (saturated by the caller)
    struct SteerSlot
    {
        std::string_view name;
        std::uint32_t    lastWrite    = 0;   // statement ordinal of the latest write so far (the declaration counts as one)
        std::uint32_t    lastWriteRow = 0;   // 1-based line of that write (detail only)
        std::uint32_t    scopeEnd     = UINT32_MAX;   // end byte of the block that declares it (steer_scopeEndOf): no read or write past it
        bool             prim         = false;
        bool             rewritten    = false;
        bool             steered      = false;
        // QD-TANGLE BLOCK FACTS: the top-level block that declared it (kNoTangleBlock: no top-level statement did), the first block
        // that writes it after its declaration, and 1 + the last block that reads it (0: none) — a CROSS LOCAL when that read is
        // later than that write
        std::uint32_t    topBlock      = kNoTangleBlock;
        std::uint32_t    firstWrite    = kNoTangleBlock;
        std::uint32_t    lastReadPlus1 = 0;
    };
    std::vector<SteerSlot> slots;
    TangleDetailFacts*     detail       = nullptr;
    std::uint32_t          deepDispatch = 0;       // the part of deepLoc inside short arms of a flat dispatch (dispatch_* below)
    std::uint32_t          nestOutArm   = 0;       // deepest control nesting reached OUTSIDE those arms (the tangle's nest; census 11-19: parseArgs)
    // QD-TANGLE BLOCK FACTS (tangleBlocks_* below): the body's top-level blocks in document order, each with the nesting it reaches
    // (all of it, and outside short dispatch arms), its deep lines and their dispatch-arm share — the body's own facts, per block.
    // Empty unless the walk counts steering locals (steerOn) and the def has a block body: then the cap is not measured.
    struct TangleBlock
    {
        std::uint32_t startByte = 0, startRow = 0, endRow = 0;   // rows 1-based
        std::uint32_t nest = 0, nestOut = 0, deep = 0, deepDispatch = 0;
        std::uint32_t deepEnd = 0;   // the last row this block's deep counted (its own clamp: a row two blocks share counts in both)
    };
    std::vector<TangleBlock> blocks;
    std::uint32_t            blockAt   = kNoTangleBlock;   // the block the walk is in (the last one whose start it has passed)
    std::uint32_t            blockNext = 0;
    bool                     declTop   = false;            // the node being noted starts a top-level block: a declaration there is top-level
    std::uint64_t            topNames  = 0;                // a 64-bit filter over the top-level slots' names (crossName_bit): a read whose bit is clear is no top-level local
};

// QD-TANGLE FLAT DISPATCH (the false-positive class STAGE0 2.4 named: parseArgs, an `if( a == "--flag" )` chain; envoy's 40-case
// switch). A switch with kDispatchMinArms or more case arms, or an if / else-if chain with that many arms, whose arm is at most
// kDispatchArmMaxRows lines: each arm reads alone, like a row of a table, so the depth it reaches is the arm's own business. The
// walk tags every frame with where it sits in such a construct; a deep region that first crosses the bar inside a short arm is
// billed to deepLoc as always (the published metric is unchanged) AND to deepDispatch, which the tangle score leaves out.
enum class ChainState : std::uint8_t
{
    None,         // not inside a dispatch construct
    Structure,    // the construct's own frame: a condition, an else clause, the link between arms
    Arm,          // inside one short arm — a deep region here is exempt from the tangle score
    SwitchBody,   // a switch's body: its children are the case arms
};
inline constexpr std::uint32_t kDispatchMinArms    = 4;
inline constexpr std::uint32_t kDispatchArmMaxRows = 40;

inline std::uint32_t dispatch_rows( TSNode n ) noexcept
{
    return ts_node_end_point( n ).row - ts_node_start_point( n ).row + 1u;
}
inline ChainState dispatch_armState( TSNode arm ) noexcept
{
    return dispatch_rows( arm ) <= kDispatchArmMaxRows ? ChainState::Arm : ChainState::None;
}
// The node kinds the tangle walk asks about, by role, in one table (no kind holds two roles): a block, an if, a switch, a switch or
// match arm, a primitive literal (the initializer that makes an untyped declaration — Python, an untyped `let`, Go's `:=` — a
// primitive local) and a subscript (whose index is a position, not a read that steers).
enum class TangleKind : std::uint8_t { Other, Block, If, Switch, CaseArm, PrimLiteral, Subscript };
inline constexpr std::pair<std::string_view, TangleKind> kTangleKinds[] = {
    { "compound_statement", TangleKind::Block }, { "block", TangleKind::Block }, { "statement_block", TangleKind::Block },
    { "if_statement", TangleKind::If }, { "if_expression", TangleKind::If },
    { "switch_statement", TangleKind::Switch }, { "switch_expression", TangleKind::Switch }, { "match_expression", TangleKind::Switch },
    { "case_statement", TangleKind::CaseArm }, { "switch_case", TangleKind::CaseArm }, { "switch_default", TangleKind::CaseArm },
    { "switch_block_statement_group", TangleKind::CaseArm }, { "switch_rule", TangleKind::CaseArm }, { "switch_section", TangleKind::CaseArm },
    { "match_arm", TangleKind::CaseArm },
    { "number_literal", TangleKind::PrimLiteral }, { "number", TangleKind::PrimLiteral }, { "integer", TangleKind::PrimLiteral },
    { "float", TangleKind::PrimLiteral }, { "true", TangleKind::PrimLiteral }, { "false", TangleKind::PrimLiteral },
    { "string", TangleKind::PrimLiteral }, { "string_literal", TangleKind::PrimLiteral }, { "char_literal", TangleKind::PrimLiteral },
    { "decimal_integer_literal", TangleKind::PrimLiteral }, { "hex_integer_literal", TangleKind::PrimLiteral },
    { "decimal_floating_point_literal", TangleKind::PrimLiteral }, { "integer_literal", TangleKind::PrimLiteral },
    { "real_literal", TangleKind::PrimLiteral }, { "boolean_literal", TangleKind::PrimLiteral }, { "int_literal", TangleKind::PrimLiteral },
    { "float_literal", TangleKind::PrimLiteral }, { "interpreted_string_literal", TangleKind::PrimLiteral },
    { "raw_string_literal", TangleKind::PrimLiteral }, { "character_literal", TangleKind::PrimLiteral },
    { "subscript_expression", TangleKind::Subscript }, { "subscript", TangleKind::Subscript }, { "index_expression", TangleKind::Subscript },
    { "element_access_expression", TangleKind::Subscript }, { "array_access", TangleKind::Subscript },
};
inline TangleKind tangleKindOf( const char* t ) noexcept
{
    const std::string_view v( t );
    const auto* it = std::find_if( std::begin( kTangleKinds ), std::end( kTangleKinds ), [ v ]( const auto& e ) { return e.first == v; } );
    return it == std::end( kTangleKinds ) ? TangleKind::Other : it->second;
}

// The arms of the if / else-if chain that starts at `n`: Python counts its elif/else clauses, every other grammar follows the
// alternative links (an else_clause wrapper in C, C++, JS/TS and Rust; the bare statement in Java, C# and Go).
inline std::uint32_t dispatch_ifChainArms( TSNode n )
{
    std::uint32_t arms = 1;
    bool          clauses = false;   // Python: the elif / else clauses are the if's own children, not a chain of ifs
    {
        ChildCursor cursor( n );
        forEachChild( n, cursor.cur, [ & ]( TSNode c )
        {
            const char* t = ts_node_type( c );
            if( kindIs( t, "elif_clause" ) || ( kindIs( t, "else_clause" ) && !ts_node_is_null( fieldChild( c, NodeField::Body ) ) ) )
            {
                ++arms;
                clauses = true;
            }
            return true;
        } );
    }
    for( TSNode cur = n; !clauses && arms < 1000u; )
    {
        TSNode alt = fieldChild( cur, NodeField::Alternative );
        if( ts_node_is_null( alt ) )
        {
            break;
        }
        if( kindIs( ts_node_type( alt ), "else_clause" ) && ts_node_named_child_count( alt ) > 0 )
        {
            alt = ts_node_named_child( alt, ts_node_named_child_count( alt ) - 1u );
        }
        ++arms;
        if( tangleKindOf( ts_node_type( alt ) ) != TangleKind::If )
        {
            break;   // the final else
        }
        cur = alt;
    }
    return arms;
}

inline std::uint32_t dispatch_switchArms( TSNode n )
{
    const TSNode  body = fieldChild( n, NodeField::Body );
    const TSNode  box  = ts_node_is_null( body ) ? n : body;
    std::uint32_t arms = 0;
    ChildCursor   cursor( box );
    forEachChild( box, cursor.cur, [ & ]( TSNode c ) { arms += tangleKindOf( ts_node_type( c ) ) == TangleKind::CaseArm ? 1u : 0u; return true; } );
    return arms;
}

// True when the control `n`, popped in state `st`, opens a dispatch (state None, enough arms) or continues one (an else-if link a
// grammar walks as its own frame, state Structure). `on`: the walk scores tangle (tangleOn); every other walk opens nothing.
inline bool dispatch_opensOrLinks( bool on, TSNode n, const char* t, ChainState st, bool elseIf )
{
    if( !on )
    {
        return false;
    }
    if( st == ChainState::Structure )
    {
        return tangleKindOf( t ) == TangleKind::If;
    }
    if( st != ChainState::None )
    {
        return false;
    }
    if( tangleKindOf( t ) == TangleKind::If )
    {
        return !elseIf && dispatch_ifChainArms( n ) >= kDispatchMinArms;
    }
    return tangleKindOf( t ) == TangleKind::Switch && dispatch_switchArms( n ) >= kDispatchMinArms;
}

// The state a child of `parent` is pushed with. `link`: `parent` opened or continues a dispatch (dispatch_opensOrLinks), so its
// consequence and its final else block are arms, a switch's body holds the arms, and the rest is the construct's structure.
// Outside a dispatch (every walk that does not score tangle) it is None.
inline ChainState dispatch_childState( TSNode parent, ChainState parentState, bool link, TSNode child )
{
    if( !link && parentState == ChainState::None )
    {
        return ChainState::None;
    }
    const char* ct = ts_node_type( child );
    if( link )
    {
        if( ts_node_eq( child, fieldChild( parent, NodeField::Consequence ) )
            || ( tangleKindOf( ct ) == TangleKind::Block && ts_node_eq( child, fieldChild( parent, NodeField::Alternative ) ) ) )
        {
            return dispatch_armState( child );
        }
        if( tangleKindOf( ts_node_type( parent ) ) == TangleKind::Switch && ts_node_eq( child, fieldChild( parent, NodeField::Body ) ) )
        {
            return ChainState::SwitchBody;
        }
        return ChainState::Structure;
    }
    switch( parentState )
    {
        case ChainState::SwitchBody: return tangleKindOf( ct ) == TangleKind::CaseArm ? dispatch_armState( child ) : ChainState::Structure;
        case ChainState::Structure:  return tangleKindOf( ct ) == TangleKind::Block ? dispatch_armState( child ) : ChainState::Structure;   // an else / elif clause's body
        case ChainState::Arm:        return ChainState::Arm;
        case ChainState::None:       return ChainState::None;
    }
    return ChainState::None;
}


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


// QD-TANGLE BLOCK FACTS: a deep region's rows, billed to the block it starts in and clamped against that block's own last counted
// row (not the function-wide deepEnd: a row two top-level statements share is in both blocks' loc, so both bill it).
inline void tangleBlocks_billDeep( CcAccum& acc, std::uint32_t startRow, std::uint32_t endRow, bool inDispatchArm ) noexcept
{
    if( acc.blockAt == kNoTangleBlock )
    {
        return;
    }
    CcAccum::TangleBlock& b    = acc.blocks[ acc.blockAt ];
    const std::uint32_t   from = startRow > b.deepEnd ? startRow : b.deepEnd + 1u;
    if( endRow >= from )
    {
        b.deep += endRow - from + 1u;
        b.deepDispatch += inDispatchArm ? endRow - from + 1u : 0u;
    }
    b.deepEnd = std::max( b.deepEnd, endRow );
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
inline void cc_noteHump( TSNode n, std::uint32_t fromNesting, std::uint32_t toNesting, CcAccum& acc, bool inDispatchArm = false ) noexcept
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
        acc.deepDispatch += inDispatchArm ? endRow - from + 1u : 0u;   // QD-TANGLE: a short dispatch arm's own depth (ChainState)
    }
    tangleBlocks_billDeep( acc, startRow, endRow, inDispatchArm );   // QD-TANGLE BLOCK FACTS: the same lines, billed to the block the region starts in
    if( endRow > acc.deepEnd )
    {
        acc.deepEnd = endRow;
    }
    if( acc.detail != nullptr && endRow >= from && !inDispatchArm )
    {
        acc.detail->humps.push_back( { from, endRow } );   // the span deepLoc billed — the region a tangle row's fix= names
    }
}

// A construct that deepens nesting from `nesting` to `childNest`: the deepest nesting (Q4), the deepest outside a short dispatch arm
// (QD-TANGLE: an arm's own nesting is the arm's business, like its deep lines), and the hump profile (did THIS construct cross the bar?).
inline void cc_noteDepth( TSNode n, std::uint32_t nesting, std::uint32_t childNest, CcAccum& acc, ChainState chain ) noexcept
{
    const bool inArm = chain == ChainState::Arm;
    acc.maxNest      = std::max( acc.maxNest, childNest );
    acc.nestOutArm   = inArm ? acc.nestOutArm : std::max( acc.nestOutArm, childNest );
    if( acc.blockAt != kNoTangleBlock )   // QD-TANGLE BLOCK FACTS: the block's own nesting, by the same two readings
    {
        CcAccum::TangleBlock& b = acc.blocks[ acc.blockAt ];
        b.nest    = std::max( b.nest, childNest );
        b.nestOut = inArm ? b.nestOut : std::max( b.nestOut, childNest );
    }
    cc_noteHump( n, nesting, childNest, acc, inArm );
}

// ═══ QD-TANGLE steering locals (STAGE0 2.1; model.h Symbol::steer) ═══════════════════════════════════════════════════
//
// A STEERING LOCAL is a local of a primitive written type that is written again after its declaration and read in a branch
// condition 10 or more statements after its last preceding write: the flag or counter set in one step that steers a branch in
// another. A flag set and tested in the same step does not count, and neither does a loop's own induction variable (a
// declaration in a for head, like a const one, is no candidate: only a name that hides an outer one while in scope). Three
// facts per node, read in the fused walk's document order: is it a STATEMENT (the distance clock), a DECLARATION of a local
// (a new slot, live until its block closes), or a WRITE to a slot; and at every branch, the identifiers its condition reads.
// Per-language shapes, verified against the vendored grammars by test/tanglecheck.sh's fixtures; a shape this table does not
// know is no slot (fewer steering locals, never a wrong one).
inline constexpr std::uint32_t kSteerStmts = 10;   // the distance, in statements, that makes a read "far" from its write

inline bool steer_isStatement( const char* t ) noexcept
{
    const std::size_t n = std::strlen( t );
    constexpr std::string_view kStmt = "_statement";
    if( n > kStmt.size() && std::string_view( t + n - kStmt.size(), kStmt.size() ) == kStmt )
    {
        return !kindIs( t, "compound_statement" );   // a C-family block is a container, not a step
    }
    return kindIs( t, "declaration" ) || kindIs( t, "lexical_declaration" ) || kindIs( t, "variable_declaration" )
        || kindIs( t, "local_variable_declaration" ) || kindIs( t, "short_var_declaration" ) || kindIs( t, "let_declaration" );
}

// A written type that names a primitive: the grammar's own primitive node, or a typedef spelling of one (size_t, uint32_t, u32 …
// arrive as type_identifier in some grammars and as std::size_t qualified in C++).
inline bool steer_isPrimitiveType( TSNode type, std::string_view src ) noexcept
{
    if( ts_node_is_null( type ) )
    {
        return false;
    }
    const char* t = ts_node_type( type );
    if( kindIs( t, "primitive_type" ) || kindIs( t, "sized_type_specifier" ) || kindIs( t, "integral_type" ) || kindIs( t, "floating_point_type" )
        || kindIs( t, "boolean_type" ) )
    {
        return true;
    }
    std::string_view text = nodeTextOf( type, src );
    if( kindIs( t, "type_annotation" ) )   // TS `: number` — the annotation wraps the type
    {
        const TSNode inner = ts_node_named_child( type, 0 );
        text = nodeTextOf( inner, src );
    }
    if( text.starts_with( "std::" ) )
    {
        text.remove_prefix( 5 );
    }
    static constexpr std::string_view kNames[] = {
        "size_t", "ssize_t", "ptrdiff_t", "intptr_t", "uintptr_t", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t",
        "uint32_t", "uint64_t", "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64", "u_int", "u_char", "u_short", "u_long",
        "int", "uint", "bool", "char", "long", "short", "float", "double", "number", "boolean", "string", "usize", "isize", "byte",
        "rune", "int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64", "float32", "float64", "sbyte", "ushort",
        "ulong", "decimal", "str",
    };
    return std::find( std::begin( kNames ), std::end( kNames ), text ) != std::end( kNames );
}

// QD-TANGLE BLOCK FACTS — a top-level local's filter bit (CcAccum::topNames): a read whose name maps to a clear bit names no
// top-level local, and skips the slot search. Two bytes and the length are enough to spread the few names a body declares.
inline std::uint64_t crossName_bit( std::string_view name ) noexcept
{
    if( name.empty() )
    {
        return 0;
    }
    const std::uint32_t h = std::uint32_t( std::uint8_t( name.front() ) ) * 31u + std::uint32_t( std::uint8_t( name.back() ) ) * 7u + std::uint32_t( name.size() );
    return std::uint64_t( 1 ) << ( h & 63u );
}
// A write to a slot in the block the walk is in: the first such block is the one a later read crosses from.
inline void crossSlot_written( CcAccum& acc, CcAccum::SteerSlot& slot ) noexcept
{
    if( slot.topBlock != kNoTangleBlock && acc.blockAt != kNoTangleBlock )
    {
        slot.firstWrite = std::min( slot.firstWrite, acc.blockAt );
    }
}

// The newest slot named `name` whose block is still open at byte `at` (census 11-19: genPathOf's `b == a` read the `a` of a block
// that had closed 30 lines earlier, the for-head `a` in scope being no slot).
inline CcAccum::SteerSlot* steer_find( CcAccum& acc, std::string_view name, std::uint32_t at ) noexcept
{
    CcAccum::SteerSlot* newest = nullptr;   // slots are declared in document order: the last match is the innermost
    for( CcAccum::SteerSlot& slot : acc.slots )
    {
        newest = slot.name == name && at < slot.scopeEnd ? &slot : newest;
    }
    return newest;
}

// The end byte of the block a declaration lives in: the nearest enclosing block or for-loop (a for-head name lives in the loop).
// Python scopes by function, so its slots never close.
inline std::uint32_t steer_scopeEndOf( TSNode n, Lang lang ) noexcept
{
    if( langFacts( lang ).steerDecl == SteerDecl::Python )
    {
        return UINT32_MAX;
    }
    for( TSNode p = parentOf( n ); !ts_node_is_null( p ); p = parentOf( p ) )
    {
        const char* pt = ts_node_type( p );
        if( tangleKindOf( pt ) == TangleKind::Block || std::strncmp( pt, "for", 3 ) == 0 )
        {
            return ts_node_end_byte( p );
        }
    }
    return UINT32_MAX;
}

inline void steer_declare( CcAccum& acc, TSNode nameNode, bool prim, std::string_view src, std::uint32_t scopeEnd = UINT32_MAX )
{
    if( ts_node_is_null( nameNode ) || !kindIs( ts_node_type( nameNode ), "identifier" ) )
    {
        return;   // a pattern or a destructuring declarator: no single name, no slot (C/C++ pointer/reference/array wrappers are
                  // unwrapped by steer_cDeclaration)
    }
    CcAccum::SteerSlot slot;
    slot.name         = nodeTextOf( nameNode, src );
    slot.lastWrite    = acc.stmt;
    slot.lastWriteRow = ts_node_start_point( nameNode ).row + 1u;
    slot.prim         = prim;
    slot.scopeEnd     = scopeEnd;
    slot.topBlock     = acc.declTop ? acc.blockAt : kNoTangleBlock;   // QD-TANGLE BLOCK FACTS: declared by a top-level statement
    acc.topNames     |= acc.declTop ? crossName_bit( slot.name ) : 0u;
    acc.slots.push_back( slot );
}

inline void steer_write( CcAccum& acc, TSNode target, std::string_view src )
{
    if( ts_node_is_null( target ) || !kindIs( ts_node_type( target ), "identifier" ) )
    {
        return;   // a member, an element or a dereference: not a local's own write
    }
    if( CcAccum::SteerSlot* slot = steer_find( acc, nodeTextOf( target, src ), ts_node_start_byte( target ) ) )
    {
        slot->rewritten    = true;
        slot->lastWrite    = acc.stmt;
        slot->lastWriteRow = ts_node_start_point( target ).row + 1u;
        acc.anyRewritten   = acc.anyRewritten || slot->prim;
        crossSlot_written( acc, *slot );   // QD-TANGLE BLOCK FACTS
    }
}

// True when `n` is in a for-loop head (an induction variable, never a slot).
inline bool steer_inForHead( TSNode n ) noexcept
{
    const TSNode p = parentOf( n );   // for_statement, for_range_loop, for_in_statement, for_clause
    return !ts_node_is_null( p ) && std::string_view( ts_node_type( p ) ).starts_with( "for" );
}

// TANGLE-RULE: the identifier a C/C++ declarator slot declares — `T& header = raw;`, `int* p = q;`, `int a[ 4 ];` name the one inside
// the wrapper (before, the wrapper reached steer_declare and made no slot: envoy parseHeader's `header` crossed four blocks unseen).
// `wrapped`: a pointer, reference or array local, which is no primitive flag, so steer= is what it was; its slot counts for
// crossLocals and hides an outer local of its name.
struct CDeclaratorName
{
    TSNode name;
    bool   wrapped = false;
};
inline CDeclaratorName steer_cDeclaratorName( TSNode d ) noexcept
{
    CDeclaratorName out{ kindIs( ts_node_type( d ), "init_declarator" ) ? fieldChild( d, NodeField::Declarator ) : d };
    for( int depth = 0; depth < 8 && !ts_node_is_null( out.name ); ++depth )
    {
        const char* t = ts_node_type( out.name );
        if( kindIs( t, "pointer_declarator" ) || kindIs( t, "array_declarator" ) )
        {
            out.name = fieldChild( out.name, NodeField::Declarator );
        }
        else if( kindIs( t, "reference_declarator" ) )
        {
            out.name = ts_node_named_child( out.name, 0 );   // the grammar gives its identifier no field name (ln_extractDeclaratorIdentifiers)
        }
        else
        {
            break;
        }
        out.wrapped = true;
    }
    return out;
}

// The C-family declaration: `[const] TYPE a = 1, b;` — every declarator slot, primitive by the written type. A const one, or one in
// a for head (`shadow`), is no candidate but still a slot: it hides an outer local of the same name for as long as it is in scope.
inline void steer_cDeclaration( CcAccum& acc, TSNode n, std::string_view src, bool shadow )
{
    bool isConst = false;
    {
        ChildCursor cursor( n );
        forEachChild( n, cursor.cur, [ & ]( TSNode c )
        {
            if( kindIs( ts_node_type( c ), "type_qualifier" ) && nodeTextOf( c, src ).starts_with( "const" ) ) { isConst = true; }
            return !isConst;
        } );
    }
    const bool          prim     = !shadow && !isConst && steer_isPrimitiveType( fieldChild( n, NodeField::Type ), src );
    const std::uint32_t scopeEnd = steer_scopeEndOf( n, Lang::Cpp );
    forEachDeclaratorSlot( n, [ & ]( TSNode d )
    {
        const auto [ name, wrapped ] = steer_cDeclaratorName( d );
        steer_declare( acc, name, prim && !wrapped, src, scopeEnd );   // a wrapped local is no primitive flag: it never steers
    } );
}

// One declarator list (JS/TS variable_declarator, Java/C# variable_declarator): the name, and primitive by the declaration's
// written type or, untyped, by its initializer; a `shadow` list (const / final, a for head) only hides outer names (steer_cDeclaration).
inline void steer_declaratorList( CcAccum& acc, TSNode n, bool typePrim, std::string_view src, bool shadow )
{
    const std::uint32_t scopeEnd = steer_scopeEndOf( n, Lang::Cpp );
    ChildCursor cursor( n );
    forEachChild( n, cursor.cur, [ & ]( TSNode c )
    {
        if( !kindIs( ts_node_type( c ), "variable_declarator" ) )
        {
            return true;
        }
        TSNode name = fieldChild( c, NodeField::Name );
        if( ts_node_is_null( name ) )
        {
            name = ts_node_named_child( c, 0 );   // C#: the identifier is the declarator's first named child
        }
        const TSNode value = fieldChild( c, NodeField::Value );
        const bool   prim  = !shadow && ( typePrim || steer_isPrimitiveType( fieldChild( c, NodeField::Type ), src )
                                          || ( !ts_node_is_null( value ) && tangleKindOf( ts_node_type( value ) ) == TangleKind::PrimLiteral ) );
        steer_declare( acc, name, prim, src, scopeEnd );
        return true;
    } );
}

// Python has no declaration: the FIRST binding of a bare name is its declaration (primitive by a literal, a len()/int()/str()/
// float()/bool() call, or an int/str/bool/float annotation); every later one is a write.
inline void steer_pythonAssignment( CcAccum& acc, TSNode n, std::string_view src )
{
    const TSNode left = fieldChild( n, NodeField::Left );
    if( ts_node_is_null( left ) || !kindIs( ts_node_type( left ), "identifier" ) )
    {
        return;
    }
    const std::string_view name = nodeTextOf( left, src );
    if( name == "self" || name == "cls" )
    {
        return;
    }
    if( steer_find( acc, name, ts_node_start_byte( left ) ) != nullptr || kindIs( ts_node_type( n ), "augmented_assignment" ) )
    {
        steer_write( acc, left, src );
        return;
    }
    const TSNode right = fieldChild( n, NodeField::Right );
    bool prim = steer_isPrimitiveType( fieldChild( n, NodeField::Type ), src );
    if( !prim && !ts_node_is_null( right ) )
    {
        const char* rt = ts_node_type( right );
        if( tangleKindOf( rt ) == TangleKind::PrimLiteral )
        {
            prim = true;
        }
        else if( kindIs( rt, "call" ) )
        {
            const std::string_view fn = nodeFieldText( right, NodeField::Function, src );
            prim = fn == "len" || fn == "int" || fn == "str" || fn == "float" || fn == "bool";
        }
    }
    steer_declare( acc, left, prim, src );
}

// The declaration shapes, per grammar. True when `n` was a declaration (its children are still walked: an initializer can write).
// A Go `var` spec whose declaration (through a grouped `var ( … )` list) starts a top-level block: the spec itself starts after `var`.
inline bool steer_goVarTop( const CcAccum& acc, TSNode spec ) noexcept
{
    if( acc.blockAt == kNoTangleBlock )
    {
        return false;
    }
    TSNode p = parentOf( spec );
    if( !ts_node_is_null( p ) && kindIs( ts_node_type( p ), "var_spec_list" ) )
    {
        p = parentOf( p );
    }
    return !ts_node_is_null( p ) && kindIs( ts_node_type( p ), "var_declaration" ) && ts_node_start_byte( p ) == acc.blocks[ acc.blockAt ].startByte;
}
inline bool steer_noteDeclaration( CcAccum& acc, TSNode n, const char* t, Lang lang, std::string_view src )
{
    const SteerDecl shape = langFacts( lang ).steerDecl;
    if( shape == SteerDecl::Python )
    {
        if( kindIs( t, "assignment" ) || kindIs( t, "augmented_assignment" ) )
        {
            steer_pythonAssignment( acc, n, src );
            return true;
        }
        return false;
    }
    if( shape == SteerDecl::CFamily && kindIs( t, "declaration" ) )
    {
        steer_cDeclaration( acc, n, src, steer_inForHead( n ) );
        return true;
    }
    if( shape == SteerDecl::JsLexical && ( kindIs( t, "lexical_declaration" ) || kindIs( t, "variable_declaration" ) ) )
    {
        steer_declaratorList( acc, n, false, src, steer_inForHead( n ) || nodeTextOf( n, src ).starts_with( "const" ) );
        return true;
    }
    if( shape == SteerDecl::Java && kindIs( t, "local_variable_declaration" ) )
    {
        steer_declaratorList( acc, n, steer_isPrimitiveType( fieldChild( n, NodeField::Type ), src ), src,
                              steer_inForHead( n ) || nodeTextOf( n, src ).starts_with( "final" ) );
        return true;
    }
    if( shape == SteerDecl::CSharp && kindIs( t, "variable_declaration" ) )
    {
        const TSNode p = parentOf( n );
        const bool local = !ts_node_is_null( p ) && kindIs( ts_node_type( p ), "local_declaration_statement" );
        steer_declaratorList( acc, n, steer_isPrimitiveType( fieldChild( n, NodeField::Type ), src ), src, !local || nodeTextOf( p, src ).starts_with( "const" ) );
        return true;
    }
    if( shape == SteerDecl::Go && kindIs( t, "short_var_declaration" ) )
    {
        const bool          shadow   = steer_inForHead( n );
        const std::uint32_t scopeEnd = steer_scopeEndOf( n, lang );
        const TSNode        left     = fieldChild( n, NodeField::Left );
        const TSNode        right    = fieldChild( n, NodeField::Right );
        const std::uint32_t names    = ts_node_is_null( left ) ? 0u : ts_node_named_child_count( left );
        for( std::uint32_t i = 0; i < names; ++i )
        {
            const TSNode value = ts_node_is_null( right ) ? TSNode{} : ts_node_named_child( right, i );
            steer_declare( acc, ts_node_named_child( left, i ), !shadow && !ts_node_is_null( value ) && tangleKindOf( ts_node_type( value ) ) == TangleKind::PrimLiteral, src, scopeEnd );
        }
        return true;
    }
    if( shape == SteerDecl::Go && kindIs( t, "var_spec" ) )
    {
        const TSNode value = fieldChild( n, NodeField::Value );
        const bool   prim  = steer_isPrimitiveType( fieldChild( n, NodeField::Type ), src )
                          || ( !ts_node_is_null( value ) && ts_node_named_child_count( value ) > 0 && tangleKindOf( ts_node_type( ts_node_named_child( value, 0 ) ) ) == TangleKind::PrimLiteral );
        acc.declTop = acc.declTop || steer_goVarTop( acc, n );   // QD-TANGLE BLOCK FACTS: the spec starts after `var`, its declaration at the block
        steer_declare( acc, fieldChild( n, NodeField::Name ), prim, src, steer_scopeEndOf( n, lang ) );
        return true;
    }
    if( shape == SteerDecl::Rust && kindIs( t, "let_declaration" ) )
    {
        const bool   mut   = !ts_node_is_null( firstChildOfType( n, "mutable_specifier" ) );   // an immutable `let` only shadows
        const TSNode value = fieldChild( n, NodeField::Value );
        const bool   prim  = mut && ( steer_isPrimitiveType( fieldChild( n, NodeField::Type ), src )
                                      || ( !ts_node_is_null( value ) && tangleKindOf( ts_node_type( value ) ) == TangleKind::PrimLiteral ) );
        steer_declare( acc, fieldChild( n, NodeField::Pattern ), prim, src, steer_scopeEndOf( n, lang ) );
        return true;
    }
    return false;
}

// A write to a bare name, in any steered grammar: assignment (plain and compound) and increment/decrement.
inline void steer_noteWrite( CcAccum& acc, TSNode n, const char* t, std::string_view src )
{
    if( kindIs( t, "assignment_expression" ) || kindIs( t, "augmented_assignment_expression" ) || kindIs( t, "compound_assignment_expr" ) )
    {
        steer_write( acc, fieldChild( n, NodeField::Left ), src );
    }
    else if( kindIs( t, "assignment_statement" ) )   // Go: `a, b = …` / `a += …`
    {
        const TSNode left = fieldChild( n, NodeField::Left );
        const std::uint32_t names = ts_node_is_null( left ) ? 0u : ts_node_named_child_count( left );
        for( std::uint32_t i = 0; i < names; ++i )
        {
            steer_write( acc, ts_node_named_child( left, i ), src );
        }
    }
    else if( kindIs( t, "update_expression" ) || kindIs( t, "inc_statement" ) || kindIs( t, "dec_statement" ) )
    {
        const TSNode arg = fieldChild( n, NodeField::Argument );
        steer_write( acc, ts_node_is_null( arg ) ? ts_node_named_child( n, 0 ) : arg, src );
    }
    else if( kindIs( t, "postfix_unary_expression" ) || kindIs( t, "prefix_unary_expression" ) )   // C#: only ++ / -- write
    {
        const std::string_view text = nodeTextOf( n, src );
        if( text.starts_with( "++" ) || text.starts_with( "--" ) || text.ends_with( "++" ) || text.ends_with( "--" ) )
        {
            steer_write( acc, ts_node_named_child( n, 0 ), src );
        }
    }
}

// ═══ QD-TANGLE BLOCK FACTS — the writes and reads a cross local is counted from (TANGLE-RULE R-D) ══════════════════════════
//
// steer_write already sees a bare name assigned or stepped. A local is also WRITTEN through a member or an element (`x.f = …`,
// `x[i] += …`, `x.n++`), by a mutator call on it (`x.push_back( … )`, `x.add( … )`; the name list the labelled census used), and by
// `&x` (C, C++) or `&mut x` (Rust) passed as an argument. It is READ by any other mention, except a plain `=` target and a name that
// only spells a member, a qualified name's segment or a keyword argument (crossQuietChild).
inline constexpr std::array<std::string_view, 6> kCrossAccessKinds = { "field_expression", "member_expression", "selector_expression", "attribute",
                                                                         "field_access", "member_access_expression" };
inline bool cross_isAccess( const char* t ) noexcept
{
    return std::ranges::contains( kCrossAccessKinds, std::string_view( t ) ) || tangleKindOf( t ) == TangleKind::Subscript;
}
// The local a member or element access lands on: `x` of `x.f`, `x->f`, `x[i]`, `x.f[i].g` (every grammar puts the object first).
inline TSNode cross_rootName( TSNode n ) noexcept
{
    for( std::uint32_t hop = 0; hop < 16u && !ts_node_is_null( n ); ++hop )
    {
        const char* t = ts_node_type( n );
        if( kindIs( t, "identifier" ) )
        {
            return n;
        }
        if( !cross_isAccess( t ) || ts_node_named_child_count( n ) == 0 )
        {
            return TSNode{};
        }
        n = ts_node_named_child( n, 0 );
    }
    return TSNode{};
}
// `m` is the verb `p`, or `p` and then a word boundary (`_`, a capital, a digit): `addEdge` and `add_item`, never `address`.
inline bool cross_startsWithVerb( std::string_view m, std::string_view p ) noexcept
{
    if( !m.starts_with( p ) )
    {
        return false;
    }
    if( m.size() == p.size() || p.back() == '_' )
    {
        return true;
    }
    const char c = m[ p.size() ];
    return c == '_' || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' );
}
inline bool cross_isMutatorName( std::string_view m ) noexcept
{
    static constexpr std::string_view kExact[]  = { "reserve", "swap", "sort", "splice", "release", "try_emplace", "entry", "discard", "increment",
                                                    "decrement", "appendleft", "extendleft", "popleft", "popitem", "setdefault" };
    static constexpr std::string_view kPrefix[] = { "push", "emplace", "insert", "erase", "clear", "append", "add", "set", "remove", "pop", "resize",
                                                    "reset", "assign", "merge", "extend", "update", "fill", "truncate", "drain", "retain", "store",
                                                    "fetch_", "inc", "dec", "write", "put", "mutable", "Add", "Set", "Clear", "Mutable", "Merge", "Copy" };
    return std::ranges::find( kExact, m ) != std::end( kExact )
        || std::ranges::any_of( kPrefix, [ m ]( std::string_view p ) { return cross_startsWithVerb( m, p ); } );
}
inline void cross_markWrite( CcAccum& acc, TSNode name, std::string_view src )
{
    if( ts_node_is_null( name ) || acc.blockAt == kNoTangleBlock )
    {
        return;
    }
    if( CcAccum::SteerSlot* slot = steer_find( acc, nodeTextOf( name, src ), ts_node_start_byte( name ) ) )
    {
        crossSlot_written( acc, *slot );
    }
}
// The object and the member name of a call's callee when the callee is a member access (`x.push_back`, `x->insert`, `x.append`).
inline void cross_noteMutatorCall( CcAccum& acc, TSNode n, const char* t, std::string_view src )
{
    TSNode object, member;
    if( kindIs( t, "method_invocation" ) )   // Java: object and name are the call's own fields
    {
        object = fieldChild( n, NodeField::Object );
        member = fieldChild( n, NodeField::Name );
    }
    else
    {
        const TSNode callee = fieldChild( n, NodeField::Function );
        if( ts_node_is_null( callee ) || tangleKindOf( ts_node_type( callee ) ) == TangleKind::Subscript || !cross_isAccess( ts_node_type( callee ) )
            || ts_node_named_child_count( callee ) < 2 )
        {
            return;
        }
        object = ts_node_named_child( callee, 0 );
        member = ts_node_named_child( callee, ts_node_named_child_count( callee ) - 1u );
    }
    if( !ts_node_is_null( object ) && !ts_node_is_null( member ) && cross_isMutatorName( nodeTextOf( member, src ) ) )
    {
        cross_markWrite( acc, cross_rootName( object ), src );
    }
}
inline void cross_noteWrite( CcAccum& acc, TSNode n, const char* t, std::string_view src )
{
    if( kindIs( t, "assignment_expression" ) || kindIs( t, "augmented_assignment_expression" ) || kindIs( t, "compound_assignment_expr" )
        || kindIs( t, "assignment" ) || kindIs( t, "augmented_assignment" ) )
    {
        const TSNode left = fieldChild( n, NodeField::Left );
        if( !ts_node_is_null( left ) && !kindIs( ts_node_type( left ), "identifier" ) )   // a bare name is steer_write's (or a declaration's)
        {
            cross_markWrite( acc, cross_rootName( left ), src );
        }
        return;
    }
    if( kindIs( t, "assignment_statement" ) )   // Go: `x.f, y[i] = …`
    {
        const TSNode        left  = fieldChild( n, NodeField::Left );
        const std::uint32_t names = ts_node_is_null( left ) ? 0u : ts_node_named_child_count( left );
        for( std::uint32_t i = 0; i < names; ++i )
        {
            const TSNode target = ts_node_named_child( left, i );
            if( !kindIs( ts_node_type( target ), "identifier" ) )
            {
                cross_markWrite( acc, cross_rootName( target ), src );
            }
        }
        return;
    }
    if( kindIs( t, "update_expression" ) )   // `x.n++`, `x[i]--` (a bare name is steer_write's)
    {
        const TSNode arg = fieldChild( n, NodeField::Argument );
        if( !ts_node_is_null( arg ) && !kindIs( ts_node_type( arg ), "identifier" ) )
        {
            cross_markWrite( acc, cross_rootName( arg ), src );
        }
        return;
    }
    if( kindIs( t, "call_expression" ) || kindIs( t, "call" ) || kindIs( t, "method_invocation" ) || kindIs( t, "invocation_expression" ) )
    {
        cross_noteMutatorCall( acc, n, t, src );
        return;
    }
    if( kindIs( t, "argument_list" ) || kindIs( t, "arguments" ) )   // `f( &x )`, `f( &mut x )`
    {
        ChildCursor cursor( n );
        forEachChild( n, cursor.cur, [ & ]( TSNode c )
        {
            const char*            ct   = ts_node_type( c );
            const std::string_view text = nodeTextOf( c, src );
            if( ( kindIs( ct, "pointer_expression" ) && text.starts_with( "&" ) ) || ( kindIs( ct, "reference_expression" ) && text.starts_with( "&mut" ) ) )
            {
                const TSNode named = ts_node_named_child_count( c ) > 0 ? ts_node_named_child( c, ts_node_named_child_count( c ) - 1u ) : TSNode{};
                if( !ts_node_is_null( named ) && kindIs( ts_node_type( named ), "identifier" ) )
                {
                    cross_markWrite( acc, named, src );
                }
            }
            return true;
        } );
    }
}
// A mention of a name that is a read: the last block that reads a top-level slot.
inline void cross_noteRead( CcAccum& acc, TSNode n, std::string_view src ) noexcept
{
    if( acc.blockAt == kNoTangleBlock )
    {
        return;
    }
    const std::string_view name = nodeTextOf( n, src );
    if( ( acc.topNames & crossName_bit( name ) ) == 0 )
    {
        return;   // no top-level local spells this name's filter bit
    }
    CcAccum::SteerSlot* slot = steer_find( acc, name, ts_node_start_byte( n ) );
    if( slot != nullptr && slot->topBlock != kNoTangleBlock )
    {
        slot->lastReadPlus1 = std::max( slot->lastReadPlus1, acc.blockAt + 1u );
    }
}
// The child of `n` that names no read (pushed with CcFrame::quiet): a plain `=` target (written, not read), the name in a member
// access whose grammar spells it as an identifier (Python attribute, Java field_access / method_invocation, C# member access), a
// qualified name's last segment (C++ `ns::x`, Rust `a::x`) and a Python keyword argument's name. Null otherwise.
inline TSNode cross_quietChild( TSNode n, const char* t, std::string_view src )
{
    switch( t[0] )
    {
        case 'a':
            if( kindIs( t, "assignment_expression" ) || kindIs( t, "assignment" ) || kindIs( t, "assignment_statement" ) )
            {
                const std::string_view op = nodeFieldText( n, NodeField::Operator, src );
                return op.empty() || op == "=" ? fieldChild( n, NodeField::Left ) : TSNode{};
            }
            return kindIs( t, "attribute" ) ? fieldChild( n, NodeField::Attribute ) : TSNode{};
        case 'f': return kindIs( t, "field_access" ) ? fieldChild( n, NodeField::Field ) : TSNode{};
        case 'k': return kindIs( t, "keyword_argument" ) ? fieldChild( n, NodeField::Name ) : TSNode{};
        case 'm':
            return kindIs( t, "method_invocation" ) || kindIs( t, "member_access_expression" ) ? fieldChild( n, NodeField::Name ) : TSNode{};
        case 'q': return kindIs( t, "qualified_identifier" ) ? fieldChild( n, NodeField::Name ) : TSNode{};
        case 's': return kindIs( t, "scoped_identifier" ) ? fieldChild( n, NodeField::Name ) : TSNode{};
        default:  return TSNode{};
    }
}
// A quiet list (`a, b = …`) quiets its names too.
inline constexpr std::array<std::string_view, 3> kCrossQuietListKinds = { "expression_list", "pattern_list", "tuple_pattern" };
// Which children of a node the walk pushes quiet: the one cross_quietChild names, or all of a quiet list's.
struct CrossQuiet
{
    TSNode child;
    bool   all = false;
    bool   of( TSNode kid ) const noexcept { return all || ( !ts_node_is_null( child ) && ts_node_eq( kid, child ) ); }
};
inline CrossQuiet cross_quietOf( bool blocksOn, bool frameQuiet, TSNode n, const char* t, std::string_view src )
{
    if( !blocksOn )
    {
        return {};
    }
    return { cross_quietChild( n, t, src ), frameQuiet && std::ranges::contains( kCrossQuietListKinds, std::string_view( t ) ) };
}

// Per named node, before the walk dispatches on it: the statement clock, then a declaration or a write (steering walks only).
inline void steer_noteNode( CcAccum& acc, TSNode n, const char* t, Lang lang, std::string_view src )
{
    if( !acc.steerOn || !ts_node_is_named( n ) )
    {
        return;
    }
    if( steer_isStatement( t ) )
    {
        ++acc.stmt;
    }
    acc.declTop = acc.blockAt != kNoTangleBlock && ts_node_start_byte( n ) == acc.blocks[ acc.blockAt ].startByte;   // QD-TANGLE BLOCK FACTS
    if( !steer_noteDeclaration( acc, n, t, lang, src ) )
    {
        steer_noteWrite( acc, n, t, src );
    }
    if( !acc.blocks.empty() )
    {
        cross_noteWrite( acc, n, t, src );   // QD-TANGLE BLOCK FACTS: a member or element write, a mutator call, `&x` passed on
    }
    acc.declTop = false;
}

// A branch's condition: every identifier it reads (a member's own name and a callee's name are not reads of a local). The
// condition is small, so a bounded explicit stack is enough; a slot that steers is counted once.
// A read that is a POSITION, not a decision (census 11-19, the cursor class: lexCpp's `j < s.size()`, buildGraph's `mdLinkPin[ siteIndex ]`):
// an operand of an order comparison (< <= > >=) bounds a scan, and an index picks an element. Neither makes a local steer.
inline bool steer_isOrderComparison( TSNode c, const char* t, std::string_view src )
{
    const auto isOrder = []( std::string_view op ) { return op == "<" || op == "<=" || op == ">" || op == ">="; };
    if( kindIs( t, "binary_expression" ) || kindIs( t, "binary_operator" ) )
    {
        return isOrder( nodeFieldText( c, NodeField::Operator, src ) );
    }
    if( kindIs( t, "comparison_operator" ) )   // Python: the operators are the node's anonymous children
    {
        const std::uint32_t kids = ts_node_child_count( c );
        for( std::uint32_t i = 0; i < kids; ++i )
        {
            const TSNode k = ts_node_child( c, i );
            if( !ts_node_is_named( k ) && isOrder( ts_node_type( k ) ) )
            {
                return true;
            }
        }
    }
    return false;
}
inline void steer_noteCondition( CcAccum& acc, TSNode branch, std::string_view src )
{
    if( !acc.steerOn || !acc.anyRewritten )
    {
        return;   // not a steering walk, or nothing written since its declaration yet: no read can be far from a rewrite
    }
    TSNode cond = fieldChild( branch, NodeField::Condition );
    if( ts_node_is_null( cond ) )
    {
        cond = fieldChild( branch, NodeField::Value );   // JS/TS switch, Go expression switch
    }
    if( ts_node_is_null( cond ) )
    {
        return;
    }
    TSNode stack[ 64 ];
    std::size_t depth = 0;
    stack[ depth++ ] = cond;
    while( depth > 0 )
    {
        const TSNode c = stack[ --depth ];
        const char*  t = ts_node_type( c );
        if( kindIs( t, "identifier" ) )
        {
            CcAccum::SteerSlot* slot = steer_find( acc, nodeTextOf( c, src ), ts_node_start_byte( c ) );
            if( slot != nullptr && slot->prim && slot->rewritten && !slot->steered && acc.stmt - slot->lastWrite >= kSteerStmts )
            {
                slot->steered = true;
                ++acc.steered;
                if( acc.detail != nullptr )
                {
                    acc.detail->steer.push_back( { std::string( slot->name ), slot->lastWriteRow, ts_node_start_point( c ).row + 1u } );
                }
            }
            continue;
        }
        if( steer_isOrderComparison( c, t, src ) )
        {
            continue;   // a bound, not a decision (steer_isOrderComparison)
        }
        // a member access reads its OBJECT only (Python `self.done`, Java `this.done`, C# `x.Done`); a call's callee is no local; a
        // subscript reads its container only (the index is a position)
        TSNode only = TSNode{};
        if( tangleKindOf( t ) == TangleKind::Subscript )
        {
            only = ts_node_named_child_count( c ) > 0 ? ts_node_named_child( c, 0 ) : TSNode{};
        }
        else if( kindIs( t, "attribute" ) || kindIs( t, "field_access" ) )
        {
            only = fieldChild( c, NodeField::Object );
        }
        else if( kindIs( t, "member_access_expression" ) )
        {
            only = fieldChild( c, NodeField::Expression );
        }
        else if( kindIs( t, "call_expression" ) || kindIs( t, "call" ) || kindIs( t, "method_invocation" ) || kindIs( t, "invocation_expression" ) )
        {
            only = fieldChild( c, NodeField::Arguments );
        }
        else if( kindIs( t, "lambda_expression" ) || kindIs( t, "lambda" ) || kindIs( t, "arrow_function" ) || kindIs( t, "closure_expression" ) )
        {
            continue;
        }
        if( !ts_node_is_null( only ) )
        {
            if( depth < std::size( stack ) )
            {
                stack[ depth++ ] = only;
            }
            continue;
        }
        const std::uint32_t kids = ts_node_named_child_count( c );
        for( std::uint32_t i = kids; i > 0 && depth < std::size( stack ); --i )
        {
            stack[ depth++ ] = ts_node_named_child( c, i - 1 );
        }
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
// kEvWhyTagCount (model.h) is spelled 8 by hand and sizes EvCtx::why below, which is indexed by an EvWhyTag: a tag
// appended here without raising it would be a write past the array's end. Proven exact at compile time.
static_assert( enumCountIsExact<EvWhyTag, kEvWhyTagCount>(), "kEvWhyTagCount must equal the EvWhyTag count — raise it with the append" );

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

// Is `t` a FUNCTION node — named or anonymous, in any grammar — whose body is a scope of its own? The ev arena's jump
// barrier and the function-local def scope (ingest_names.h enclosingFunctionScope) read the SAME list, so the two can
// never disagree about where a function starts. A miss here is the ONE table error that would OVER-count ev (a
// return inside an unrecognised closure shape would mark the outer function's constructs), which is why this list
// errs wide and every entry was probe-verified. Only ever handed NAMED node kinds by its callers where a spelling
// doubles as an anonymous keyword token (`lambda`, `method`): an ancestor is never a leaf token.
inline bool isFunctionBoundaryKind( const char* t ) noexcept
{
    return kindIs( t, "lambda_expression" )   || kindIs( t, "lambda" )
        || kindIs( t, "closure_expression" )  || kindIs( t, "function_definition" )
        || kindIs( t, "function_declaration" ) || kindIs( t, "function_expression" )
        || kindIs( t, "arrow_function" )      || kindIs( t, "generator_function" )
        || kindIs( t, "generator_function_declaration" ) || kindIs( t, "method_definition" )
        || kindIs( t, "method_declaration" )  || kindIs( t, "func_literal" )
        || kindIs( t, "function_item" )       || kindIs( t, "lambda_literal" )
        || kindIs( t, "local_function_statement" ) || kindIs( t, "anonymous_method_expression" )
        || kindIs( t, "method" )              || kindIs( t, "singleton_method" );
}

// is `t` a control construct the arena tracks, and of what kind? Lang-gated where node-type spellings
// collide across grammars (Swift's `do_statement` is a try, the C family's a loop; Ruby's bare-word kinds
// double as anonymous keyword tokens elsewhere — the caller's isNamed gate recovers them, exactly as
// cc_isNestingControl's note explains). Node-type spellings verified against the VENDORED grammars via
// real parses (--match probes per language), not assumed — the ln_extractDeclaratorIdentifiers discipline.
inline bool ev_ctrlKindFor( const char* t, Lang lang, CtrlKind& kindOut ) noexcept
{
    // branches
    if(    kindIs( t, "if_statement" )        || kindIs( t, "if_expression" )
        || kindIs( t, "conditional_expression" ) || kindIs( t, "ternary_expression" )
        || kindIs( t, "guard_statement" )     || kindIs( t, "conditional" )
        || kindIs( t, "elif_clause" )         || kindIs( t, "else_clause" )
        || kindIs( t, "elsif" )               || kindIs( t, "if" )
        || kindIs( t, "unless" )              || kindIs( t, "if_modifier" )
        || kindIs( t, "unless_modifier" ) )
    {
        kindOut = CtrlKind::Branch;
        return true;
    }
    // loops (Swift's do_statement is a TRY and is handled below)
    if(    kindIs( t, "for_statement" )       || kindIs( t, "for_range_loop" )
        || kindIs( t, "for_in_statement" )    || kindIs( t, "for_expression" )
        || kindIs( t, "while_statement" )     || kindIs( t, "while_expression" )
        || kindIs( t, "loop_expression" )     || kindIs( t, "foreach_statement" )
        || kindIs( t, "repeat_while_statement" )
        || ( kindIs( t, "do_statement" ) && lang != Lang::Swift )
        || kindIs( t, "while" )               || kindIs( t, "until" )
        || kindIs( t, "for" )                 || kindIs( t, "while_modifier" )
        || kindIs( t, "until_modifier" ) )
    {
        kindOut = CtrlKind::Loop;
        return true;
    }
    // switch/match heads (weight 0 — the arms carry the decisions, as in cx)
    if(    kindIs( t, "switch_statement" )    || kindIs( t, "switch_expression" )
        || kindIs( t, "match_expression" )    || kindIs( t, "match_statement" )
        || kindIs( t, "expression_switch_statement" ) || kindIs( t, "type_switch_statement" )
        || kindIs( t, "select_statement" )    || kindIs( t, "case" )
        || kindIs( t, "case_match" ) )
    {
        kindOut = CtrlKind::Switch;
        return true;
    }
    // arms
    if(    kindIs( t, "case_statement" )      || kindIs( t, "switch_section" )
        || kindIs( t, "switch_expression_arm" ) || kindIs( t, "match_arm" )
        || kindIs( t, "expression_case" )     || kindIs( t, "communication_case" )
        || kindIs( t, "default_case" )        || kindIs( t, "type_case" )
        || kindIs( t, "case_clause" )         || kindIs( t, "switch_entry" )
        || kindIs( t, "switch_rule" )         || kindIs( t, "switch_block_statement_group" )
        || kindIs( t, "when" )                || kindIs( t, "in_clause" ) )
    {
        kindOut = CtrlKind::Case;
        return true;
    }
    // try / catch (Swift spells try as do_statement + catch_block)
    if(    kindIs( t, "try_statement" )       || kindIs( t, "try_with_resources_statement" )
        || kindIs( t, "begin" )               || ( kindIs( t, "do_statement" ) && lang == Lang::Swift ) )
    {
        kindOut = CtrlKind::Try;
        return true;
    }
    if(    kindIs( t, "catch_clause" )        || kindIs( t, "except_clause" )
        || kindIs( t, "catch_block" )         || kindIs( t, "rescue" ) )
    {
        kindOut = CtrlKind::Catch;
        return true;
    }
    // function boundaries — the jump barrier (isFunctionBoundaryKind, above).
    if( isFunctionBoundaryKind( t ) )
    {
        kindOut = CtrlKind::Fn;
        return true;
    }
    // Ruby blocks — a jump scope of their own (`each do … next end`: next is the block's normal exit);
    // lang-gated because Go/Java/C# spell their PLAIN braces "block", which must stay out of the arena.
    if( lang == Lang::Ruby && ( kindIs( t, "block" ) || kindIs( t, "do_block" ) ) )
    {
        kindOut = CtrlKind::Block;
        return true;
    }
    if( kindIs( t, "labeled_statement" ) )
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

    if( kindIs( t, "return_statement" ) || kindIs( t, "return_expression" )
        || kindIs( t, "co_return_statement" ) || ( isRuby && kindIs( t, "return" ) ) )
    {
        noteReturn();
    }
    else if( kindIs( t, "throw_statement" ) || kindIs( t, "raise_statement" ) )
    {
        noteThrow();
    }
    else if( kindIs( t, "break_statement" ) || kindIs( t, "continue_statement" ) )
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
    else if( kindIs( t, "break_expression" ) || kindIs( t, "continue_expression" ) )
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
    else if( isRuby && ( kindIs( t, "break" ) || kindIs( t, "next" ) ) )
    {
        noteEscape( kEvTgtLoop | kEvTgtBlock, false );
    }
    else if( isRuby && ( kindIs( t, "redo" ) || kindIs( t, "retry" ) ) )
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
    else if( kindIs( t, "goto_statement" ) )
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
    else if( kindIs( t, "fallthrough_statement" ) )
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
    else if( kindIs( t, "yield_statement" ) )
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
    else if( kindIs( t, "control_transfer_statement" ) )
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

// ═══ QD-TANGLE BLOCK FACTS — the body's top-level blocks (TANGLE-RULE R-D; model.h TangleInputs::maxBlock10) ════════════════
//
// A block is a byte range the walk enters in document order. The body's statements are blocks, except: a bare scope `{ }` is
// transparent (its statements are top-level blocks: the house style scopes a step's locals that way), an if / else-if chain is one
// block per arm (the first arm starts at the `if` and holds its condition; each later one starts at its `else` / `elif`), and so
// is a switch or match (the first arm holds the head). An expression statement around an if or a match (Rust) is that construct.
inline void tangleBlocks_push( CcAccum& acc, TSNode from, TSNode to )
{
    acc.blocks.push_back( { ts_node_start_byte( from ), ts_node_start_point( from ).row + 1u, ts_node_end_point( to ).row + 1u } );
}
// The arms of the chain that starts at `n`: Python's elif / else clauses are the if's own children; every other grammar links the
// next arm through `alternative` (an else_clause wrapper in C, C++, JS/TS and Rust; the bare if or block in Java, C# and Go).
inline void tangleBlocks_ifArms( CcAccum& acc, TSNode n )
{
    TSNode armStart = n;
    for( std::uint32_t arm = 0; !ts_node_is_null( n ) && arm < 4096u; ++arm )
    {
        const TSNode cons = fieldChild( n, NodeField::Consequence );
        tangleBlocks_push( acc, armStart, ts_node_is_null( cons ) ? n : cons );
        bool clauses = false;
        {
            ChildCursor cursor( n );
            forEachChild( n, cursor.cur, [ & ]( TSNode c )
            {
                const char* t = ts_node_type( c );
                if( kindIs( t, "elif_clause" ) || ( kindIs( t, "else_clause" ) && !ts_node_is_null( fieldChild( c, NodeField::Body ) ) ) )
                {
                    tangleBlocks_push( acc, c, c );
                    clauses = true;
                }
                return true;
            } );
        }
        const TSNode alt = fieldChild( n, NodeField::Alternative );
        if( clauses || ts_node_is_null( alt ) )
        {
            return;
        }
        armStart          = alt;
        const bool   wrap = kindIs( ts_node_type( alt ), "else_clause" );
        const TSNode next = wrap && ts_node_named_child_count( alt ) > 0 ? ts_node_named_child( alt, ts_node_named_child_count( alt ) - 1u ) : alt;
        if( ts_node_is_null( next ) || tangleKindOf( ts_node_type( next ) ) != TangleKind::If )
        {
            tangleBlocks_push( acc, alt, alt );   // the final else
            return;
        }
        n = next;
    }
}
inline void tangleBlocks_switchArms( CcAccum& acc, TSNode n )
{
    const TSNode body  = fieldChild( n, NodeField::Body );
    const TSNode box   = ts_node_is_null( body ) ? n : body;
    bool         first = true;
    ChildCursor  cursor( box );
    forEachChild( box, cursor.cur, [ & ]( TSNode c )
    {
        if( tangleKindOf( ts_node_type( c ) ) == TangleKind::CaseArm )
        {
            tangleBlocks_push( acc, first ? n : c, c );
            first = false;
        }
        return true;
    } );
    if( first )
    {
        tangleBlocks_push( acc, n, n );   // no arm the table knows: the construct is one block
    }
}
inline void tangleBlocks_collect( CcAccum& acc, TSNode box, std::uint32_t depth )
{
    ChildCursor cursor( box );
    forEachChild( box, cursor.cur, [ & ]( TSNode c )
    {
        const char* t = ts_node_type( c );
        if( !ts_node_is_named( c ) || std::strstr( t, "comment" ) != nullptr )
        {
            return true;
        }
        const TSNode     inner = kindIs( t, "expression_statement" ) && ts_node_named_child_count( c ) == 1 ? ts_node_named_child( c, 0 ) : c;
        const TangleKind kind  = tangleKindOf( ts_node_type( inner ) );
        if( kind == TangleKind::Block && depth < 64u )
        {
            tangleBlocks_collect( acc, inner, depth + 1u );   // a bare scope: its statements are top-level blocks
        }
        else if( kind == TangleKind::If )
        {
            tangleBlocks_ifArms( acc, inner );
        }
        else if( kind == TangleKind::Switch )
        {
            tangleBlocks_switchArms( acc, inner );
        }
        else
        {
            tangleBlocks_push( acc, c, c );
        }
        return true;
    } );
}
// The def's block body (its `body` field, or the def itself when it is a block: a body-sibling def), else null — no blocks then.
inline TSNode tangleBlocks_bodyOf( TSNode root ) noexcept
{
    TSNode body = fieldChild( root, NodeField::Body );
    if( ts_node_is_null( body ) )
    {
        body = root;
    }
    return tangleKindOf( ts_node_type( body ) ) == TangleKind::Block ? body : TSNode{};
}
// The walk passes a block's start: it is in that block now, at the frame's nesting at least (an arm sits inside its construct).
inline void tangleBlocks_enter( CcAccum& acc, TSNode n, std::uint32_t nesting ) noexcept
{
    const std::uint32_t at = ts_node_start_byte( n );
    if( acc.blockNext >= acc.blocks.size() || at < acc.blocks[ acc.blockNext ].startByte )
    {
        return;
    }
    do
    {
        acc.blockAt = acc.blockNext++;
    } while( acc.blockNext < acc.blocks.size() && at >= acc.blocks[ acc.blockNext ].startByte );
    CcAccum::TangleBlock& b = acc.blocks[ acc.blockAt ];
    b.nest    = std::max( b.nest, nesting );
    b.nestOut = std::max( b.nestOut, nesting );
}
// Per node of a walk that collected blocks (`on`), before the steering note bills its declarations and writes: the block the node is
// in, and a read of a top-level local when the node is a named identifier its parent did not quiet (`mayRead`).
inline void cross_noteNode( CcAccum& acc, bool on, TSNode n, const char* t, std::uint32_t nesting, bool mayRead, std::string_view src ) noexcept
{
    if( !on )
    {
        return;
    }
    tangleBlocks_enter( acc, n, nesting );
    if( mayRead && kindIs( t, "identifier" ) )
    {
        cross_noteRead( acc, n, src );
    }
}
// The two facts, once the walk is done: the highest one-block score (tenths, tangleScore10 over the block alone, no steering locals:
// the body's own steer stays in its S) and the cross locals. kTangleNoCap when no block was collected.
struct TangleBlockScore
{
    std::uint32_t maxBlock10 = kTangleNoCap;
    std::uint32_t cross      = 0;
};
inline TangleBlockScore tangleBlocks_score( const CcAccum& acc ) noexcept
{
    TangleBlockScore out;
    if( acc.blocks.empty() )
    {
        return out;
    }
    out.maxBlock10 = 0;
    for( const CcAccum::TangleBlock& b : acc.blocks )
    {
        const std::uint32_t loc  = b.endRow >= b.startRow ? b.endRow - b.startRow + 1u : 1u;
        const std::uint32_t deep = std::min( b.deep, loc );
        const std::uint32_t arms = std::min( b.deepDispatch, deep );
        out.maxBlock10 = std::max( out.maxBlock10, tangleScore10( tangleInputsFrom( loc, b.nest, deep, 0, tangleDispatchShare( deep, arms, b.nest - std::min( b.nest, b.nestOut ) ) ) ) );
    }
    for( const CcAccum::SteerSlot& slot : acc.slots )
    {
        out.cross += slot.topBlock != kNoTangleBlock && slot.firstWrite != kNoTangleBlock && slot.lastReadPlus1 > slot.firstWrite + 1u ? 1u : 0u;
    }
    return out;
}

// A4-F25: NOT noexcept — the frame-stack vector allocates, so under memory pressure bad_alloc must be
// allowed to propagate to the per-file degrade catch, not turn into terminate().
/// Accumulate syntactic complexity and nesting in one iterative walk from start.
/// Update acc in place using the supplied initial depth/nesting; quoted Elixir AST is excluded.
inline void cc_walk( TSNode start, std::uint32_t startNesting, std::string_view src, CcAccum& acc, int startDepth,
                      bool countLocals,   // Phase 1: countLocals gates on lang (model.h localsCountedLang), C/C++ only
                      Lang lang, EvCtx* evCtx )   // essential complexity: nullptr outside model.h evCountedLang — zero work then
{
    // iterative pre-order DFS — an EXPLICIT frame stack, not recursion: worker threads get 512 KB stacks on
    // macOS, so a deep AST overflows the call stack well inside the depth guard. Children are pushed in
    // reverse so pops preserve the original left-to-right visit order; the guard bounds the heap stack.
    // ctrl: innermost enclosing ev arena index (kNoCtrl at root); chain: where the frame sits in a flat dispatch (tangle walks only); quiet: no read
    struct CcFrame { TSNode node; std::uint32_t nesting; std::uint32_t ctrl; std::uint16_t depth; ChainState chain; bool quiet = false; };
    std::vector<CcFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { start, startNesting, kNoCtrl, static_cast<std::uint16_t>( startDepth ), ChainState::None } );
    ChildCursor         cursor( start );
    std::vector<TSNode> kids;       kids.reserve( 64 );
    std::vector<TSNode> elifKids;   elifKids.reserve( 64 );   // the else-if grandchild descent below nests inside a kids iteration

    while( !stack.empty() )
    {
        const CcFrame frame = stack.back();
        stack.pop_back();
        if( frame.depth > 512 )
        {
            // pathological-AST guard, independent of file size: the old justification "file size is already capped at 1 MB" went
            // stale when kDefaultMaxFileBytes became 4 MB (2026-07) and --max-file-size can raise it further. Measured 2026-09-10
            // on this tree (15,926 symbols): deepest real frame 103 against a bound of 512 — 5x headroom, inert.
            continue;
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
        // Elixir controls are ordinary calls whose target text supplies the keyword.
        const auto elixirKeyword = lang == Lang::Elixir ? nodeFieldText( n, NodeField::Target, src ) : std::string_view{};
        if( elixirKeyword == "quote" )
        {
            continue; // quoted AST is not executed control flow
        }
        cross_noteNode( acc, !acc.blocks.empty(), n, t, nesting, !frame.quiet && isNamed, src );   // QD-TANGLE BLOCK FACTS, before the steering note
        // QD-TANGLE: the statement clock, a declaration or a write — before the dispatch below, so every named node is seen once.
        steer_noteNode( acc, n, t, lang, src );
        const bool elixirDecision = elixirKeyword == "if" || elixirKeyword == "unless" || elixirKeyword == "for" || elixirKeyword == "with";
        const bool elixirControl = elixirDecision || elixirKeyword == "case" || elixirKeyword == "cond" || elixirKeyword == "receive" || elixirKeyword == "try";
        if( isNamed && ( isDecisionType( t, lang ) || elixirDecision || ( lang == Lang::Elixir && kindIs( t, "stab_clause" ) ) ) )
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
        else if( ( kindIs( t, "binary_expression" )
                   || ( ( lang == Lang::Elixir || lang == Lang::GDScript ) && kindIs( t, "binary_operator" ) ) )
                 && cc_isBooleanJoin( n, src, lang ) )
        {
            ++acc.cyclo;   // Myers' &&/|| extension — see cc_isBooleanJoin for the two spelling families
        }

        if( isNamed && ( cc_isNestingControl( t, lang ) || elixirControl ) )
        {
            const bool   isIf = ( kindIs( t, "if_statement" ) || kindIs( t, "if_expression" ) );
            const TSNode p    = parentOf( n );
            const bool   elseIf = isIf && !ts_node_is_null( p )
                                  && ( kindIs( ts_node_type( p ), "if_statement" ) || kindIs( ts_node_type( p ), "if_expression" ) );
            const std::uint32_t childNest = elseIf ? nesting : nesting + 1;   // else-if doesn't deepen
            acc.cog += elseIf ? 1u : ( 1u + nesting );                           // flat +1 for else-if, else +1+nesting
            cc_noteDepth( n, nesting, childNest, acc, frame.chain );
            const bool link = dispatch_opensOrLinks( acc.tangleOn, n, t, frame.chain, elseIf );
            steer_noteCondition( acc, n, src );   // QD-TANGLE: the locals this branch's condition reads
            collectChildren( n, cursor.cur, kids );
            for( std::size_t i = kids.size(); i > 0; --i )
            {
                stack.push_back( { kids[i - 1], childNest, ctrl, childDepth, dispatch_childState( n, frame.chain, link, kids[i - 1] ) } );
            }
            continue;
        }
        if( isNamed && ( kindIs( t, "elif_clause" ) || kindIs( t, "else_clause" )
                         || kindIs( t, "elsif" ) ) )   // else / elif / else-if (+ Ruby `elsif`): flat +1 (cognitive)
        {
            acc.cog += 1u;
            steer_noteCondition( acc, n, src );   // QD-TANGLE: Python's elif_clause carries its own condition (an else carries none)
            collectChildren( n, cursor.cur, kids );
            for( std::size_t i = kids.size(); i > 0; --i )
            {
                const TSNode c  = kids[ i - 1 ];
                const char*  ct = ts_node_type( c );
                if( kindIs( ct, "if_statement" ) || kindIs( ct, "if_expression" ) )
                {
                    steer_noteNode( acc, c, ct, lang, src );   // QD-TANGLE: the C-family else-if never becomes a frame — clock and condition here
                    steer_noteCondition( acc, c, src );
                    // C-family `else if`: descend into the if's CHILDREN so cognitive doesn't re-score it as a
                    // fresh control — but cyclomatic still counts that `if` as a decision (parity with the old walk).
                    // ev: that if never becomes a frame, so it gets its arena node HERE (Branch, weight 1 — 1:1
                    // with the cyclo increment above, preserving the structural ev <= cx containment).
                    ++acc.cyclo;
                    const std::uint32_t elifCtrl = ( evCtx != nullptr ) ? ev_appendCtrl( *evCtx, c, CtrlKind::Branch, 1, ctrl, lang, src ) : ctrl;
                    collectChildren( c, cursor.cur, elifKids );   // NOT kids — that iteration is still live
                    const bool link = frame.chain == ChainState::Structure;   // an else-if link of a dispatch chain
                    for( std::size_t j = elifKids.size(); j > 0; --j )
                    {
                        stack.push_back( { elifKids[j - 1], nesting, elifCtrl, childDepth, dispatch_childState( c, frame.chain, link, elifKids[j - 1] ) } );
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
                    stack.push_back( { c, nesting, ctrl, childDepth, dispatch_childState( n, frame.chain, false, c ) } );
                }
            }
            continue;
        }
        if( cc_isNestingOnly( t ) )
        {
            cc_noteDepth( n, nesting, nesting + 1, acc, frame.chain );   // a lambda/closure body deepens nesting
            collectChildren( n, cursor.cur, kids );
            for( std::size_t i = kids.size(); i > 0; --i )
            {
                stack.push_back( { kids[i - 1], nesting + 1, ctrl, childDepth, dispatch_childState( n, frame.chain, false, kids[i - 1] ) } );
            }
            continue;
        }
        const std::string_view bop = cc_boolOp( n, src );
        if( !bop.empty() && cc_boolOp( parentOf( n ), src ) != bop )
        {
            ++acc.cog; // new boolean run (cognitive)
        }

        collectChildren( n, cursor.cur, kids );
        const CrossQuiet quiet = cross_quietOf( !acc.blocks.empty(), frame.quiet, n, t, src );
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], nesting, ctrl, childDepth, dispatch_childState( n, frame.chain, false, kids[i - 1] ), quiet.of( kids[i - 1] ) } );
        }
    }
}
struct Complexity { std::uint32_t cx; std::uint32_t ccx; std::uint32_t maxNest; std::uint32_t locals; std::uint32_t ppAlt; std::uint32_t humps; std::uint32_t deepLoc; std::uint32_t ev; std::array<std::uint8_t, kEvWhyTagCount> evWhy; std::uint32_t steer; std::uint32_t deepDispatch; std::uint32_t nestArmCut; std::uint32_t maxBlock10; std::uint32_t cross; };
// `lang`: Phase 1 (local-variable-indexing) gates the locals accumulator to model.h's localsCountedLang
// (C/C++ only, MVP scope) INSIDE the same fused walk — every other language pays one branch-not-taken
// per node and gets locals=0, which the caller (this file, RawDef→Symbol) leaves at 0 and serialize.h
// never emits (absent, not a bare "0" — see localsCountedLang's own comment).
// QD-TANGLE: the steering-locals fact is walked only where the tangle score can be non-zero — a body over kTangleAmpLoc lines
// (S = T × log2(loc/50), so 0 at 50 or fewer) — in a language with a langfacts.h steerDecl. `detail` (tangleDetailOf only) collects the names and spans.
inline constexpr std::uint32_t kSteerMinRows = 51;
inline Complexity complexityOf( TSNode root, std::string_view src, Lang lang, TangleDetailFacts* detail = nullptr )   // one fused DFS → cx, ccx, maxNest, locals, ppAlt, the nesting profile, ev AND steer
{
    PROFILE_SCOPE_DESCRIBE( "ingest/metrics: complexityOf one function (fused DFS)" );                                                                     // A4-F25: NOT noexcept — cc_walk (and kids here) allocate
    CcAccum acc;
    acc.tangleOn = ts_node_end_point( root ).row - ts_node_start_point( root ).row + 1u >= kSteerMinRows;
    acc.steerOn  = acc.tangleOn && langFacts( lang ).steerDecl != SteerDecl::None;
    acc.detail  = detail;
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
    // QD-TANGLE BLOCK FACTS: walked with the steering locals, whose slot table the cross locals are counted on
    if( acc.steerOn )
    {
        if( const TSNode body = tangleBlocks_bodyOf( root ); !ts_node_is_null( body ) )
        {
            tangleBlocks_collect( acc, body, 0 );
        }
    }
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
    const TangleBlockScore blocks = tangleBlocks_score( acc );
    Complexity out{ 1u + acc.cyclo, acc.cog, acc.maxNest, acc.locals, acc.ppAlt, acc.humps, acc.deepLoc, 0u, {}, acc.steered, acc.deepDispatch, acc.maxNest - std::min( acc.maxNest, acc.nestOutArm ),
                    blocks.maxBlock10, blocks.cross };
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
    if( kindIs( t, "identifier" ) || kindIs( t, "field_identifier" ) )
    {
        outIdents.push_back( node );
        return;
    }
    // Both walks below are O(children) on a cursor this frame owns (the body recurses): a declarator's own
    // child list takes a comment between any two of its parts, so the width is input-set (arm B7).
    if( kindIs( t, "reference_declarator" ) )
    {
        ChildCursor cursor( node );
        forEachChild( node, cursor.cur, [ & ]( TSNode c ) { ln_extractDeclaratorIdentifiers( c, outIdents, depth - 1 ); return true; } );
        return;
    }
    if( kindIs( t, "init_declarator" ) || kindIs( t, "pointer_declarator" ) || kindIs( t, "array_declarator" ) )
    {
        forEachDeclaratorSlot( node, [ & ]( TSNode c ) { ln_extractDeclaratorIdentifiers( c, outIdents, depth - 1 ); } );
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
    forEachDeclaratorSlot( declNode, [ &outIdents ]( TSNode c ) { ln_extractDeclaratorIdentifiers( c, outIdents, 6 ); } );
}

// declDepth: count of `compound_statement` ancestors from `declNode` up to and including the function's
// OWN outermost body block (stops at `funcRoot`, the re-parsed def's root node) — so a direct top-level
// local gets declDepth=1, and a local one control-structure block deeper gets declDepth=2+, matching
// checkLocalNameShape's own declDepth>=2 gate (naminglens.h) exactly.
inline std::uint8_t ln_declDepth( TSNode declNode, TSNode funcRoot ) noexcept
{
    std::uint8_t depth = 0;
    TSNode       cur   = parentOf( declNode );
    while( !ts_node_is_null( cur ) )
    {
        if( kindIs( ts_node_type( cur ), "compound_statement" ) )
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
        cur = parentOf( cur );
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
    // O(children), not O(children²): the re-parsed subtree is a whole DEFINITION, whose body node holds
    // one child per statement AND one per comment between them (extras are spliced into the child array —
    // src/infra/tschildren.h). A 16 000-comment body measured 15× --lint without --naming-locals before
    // this became a cursor (test/childwalkscalecheck.sh, arm B6). The cursor is this frame's own: the
    // loop body recurses.
    ChildCursor cursor( node );
    forEachChild( node, cursor.cur, [ & ]( TSNode child )
    { ln_collectLocalDecls( child, funcRoot, depth - 1, out, defStartLine, defBytes ); return true; } );
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
    return    kindIs( t, "parameter_list" )          // C++/ObjC/Go
           || kindIs( t, "parameters" )              // Python / Rust / Swift
           || kindIs( t, "formal_parameters" )       // TypeScript / JS
           || kindIs( t, "parameter_clause" )        // Swift
           || kindIs( t, "method_parameters" )       // Ruby `def f(a, b)`
           || kindIs( t, "block_parameters" )        // Ruby `{ |x, y| ... }`
           || kindIs( t, "lambda_parameters" )       // Ruby `->(n) { ... }`
           || kindIs( t, "formal_parameter_list" )   // Dart (NOT TS/JS's formal_parameters)
           || kindIs( t, "function_value_parameters" );   // Kotlin `fun f(a: Int, b: String)` — counted by `parameter` kind, see countParams
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
        // re-derivation bound (2026-09-10): tripped 97 times over 15,926 symbols but deepest found param list was depth 6;
        // raising to 64/256 yielded identical 12,785 params, proving bound is inert (measured C++/mixed, not at scale)
        if( f.depth > 12 )
        {
            continue; // params live near the signature; bound the search
        }
        const char* t = ts_node_type( f.n );
        collectChildren( f.n, cursor.cur, kids );           // one collection serves both arms below
        if( f.n.id != defNode.id && cc_isParamList( t ) )   // don't treat the def node itself as a param list
        {
            // Kotlin's function_value_parameters counts `parameter` children ONLY: a parameter's own
            // modifiers (`vararg`) and its default-value expression are SIBLINGS of the `parameter` node in
            // this grammar, not nested inside it, so the generic "every named child" rule reads 3 real
            // params as 5 (verified on a real parse before this branch was written).
            const bool kotlinList = kindIs( t, "function_value_parameters" );
            std::uint32_t count = 0;   // a list may hold more children than the uint16 result: saturate below, never wrap
            for( const TSNode c : kids )
            {
                if( !ts_node_is_named( c ) )
                {
                    continue; // skip '(', ')', ',' separators
                }
                const char* ct = ts_node_type( c );
                if( kotlinList )
                {
                    if( !kindIs( ct, "parameter" ) )   // Kotlin: only `parameter` counts — its modifiers
                    {                                   // and default value are siblings, not nested
                        continue;
                    }
                }
                else if( kindIs( ct, "comment" ) )
                {
                    continue; // a comment inside the list is not a parameter
                }
                ++count;
            }
            return std::uint16_t( std::min<std::uint32_t>( count, std::numeric_limits<std::uint16_t>::max() ) );
        }
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], std::uint16_t( f.depth + 1 ) } );
        }
    }
    return 0;
}

// B2.2 MINIMUM ARITY — the per-language DATA, one sparse family-owned row per language that takes part (the
// lang-specific-layer tier-3 shape: a MISSING row means the language has no lower bound). A row names the
// parameter-list children that are NOT a required argument:
//   * `defaulted`          — a child of this kind carries a default value (C++ `int b = 1`, Python `y=1`, TS `b?`);
//   * `defaultedWithValue` — a child of this kind carries one when it has a `value` field (TS `b = 2`);
//   * `notParam`           — a child of this kind is no parameter at all (Python's bare `*` and `/` separators);
//   * `soleVoid`           — a list whose ONLY parameter reads exactly this text has no parameter (C++ `f(void)`);
//   * `receiverChild`      — a child holding a node of this kind is never passed (TS `this: T`) → NO minimum;
//   * `decoratedParent`    — a def whose PARENT is this kind is decorated; a decorator may supply arguments → NO minimum;
//   * `selfOwner`          — a def whose nearest enclosing class-or-function scope is this kind is a method whose first
//                            parameter (`self`/`cls`) the call omits → NO minimum. Python tags every `def`
//                            @definition.function, so SymKind::Method never marks a Python method and the kind gate
//                            below cannot see one; the parse tree can.
//   * `fnValue`            — a parameter list owned by a function VALUE of this kind (TS arrow / function expression,
//                            Python lambda) bound to the def's name gets a minimum only when the arrow's own list IS
//                            the call's contract: the value is the binding's `value` directly (no `as`/`satisfies` cast,
//                            no wrapper), the binding carries no `type` annotation, and every parameter carries its own
//                            `type`. Otherwise the signature lives elsewhere — hono `header: SetHeaders = (name, value,
//                            options) => …` takes `value?`/`options?` from SetHeaders, and an untyped parameter is
//                            contextually typed — so the arrow's parameter count says nothing about optionality → NO minimum.
// Every kind name is the vendored grammar's own (third_party/deps/<lang>/src/parser.c symbol table). Languages
// WITHOUT a row, each for a stated reason: JavaScript (a call may legally pass fewer arguments than declared);
// Swift (a trailing closure is an argument outside the list callArity counts); Kotlin, C#, PHP, Ruby, Dart and the
// rest (no call-comparable arity at all: cc_paramShape's language gate below). Their paramsMin is 0, so the
// resolver never drops one of their candidates for too FEW arguments — exactly the behaviour before this table.
struct ParamMinLang
{
    Lang             lang;
    std::string_view defaulted[2];
    std::string_view defaultedWithValue;
    std::string_view notParam[2];
    std::string_view soleVoid;
    std::string_view receiverChild;
    std::string_view decoratedParent;
    std::string_view selfOwner;
    std::string_view fnValue[2];
};
inline constexpr ParamMinLang kParamMinLangs[] = {
    { Lang::Cpp,        { "optional_parameter_declaration", {} },        {},                   { {}, {} },                                     "void", {},     {},                     {},                 { {}, {} } },
    { Lang::Java,       { {}, {} },                                      {},                   { {}, {} },                                     {},     {},     {},                     {},                 { {}, {} } },   // no default parameters
    { Lang::Python,     { "default_parameter", "typed_default_parameter" }, {},                { "keyword_separator", "positional_separator" }, {},     {},     "decorated_definition", "class_definition", { "lambda", {} } },
    { Lang::TypeScript, { "optional_parameter", {} },                    "required_parameter", { {}, {} },                                     {},     "this", {},                     {},                 { "arrow_function", "function_expression" } },
};
// Is `def` a member of an `owner`-kind node: the nearest enclosing `owner` or function is `owner`. The walk has no
// depth cap — a class body may hold a def under any number of `if`/`try`/`with`/`else` blocks and a decorator wrapper
// (a fixed hop count missed `class A:\n  if X:\n    def m(self, a)`, counted `self` and dropped the real method); it
// stops at the first function, since a def nested in a method's body is a closure, not a member.
inline bool ownedBy( TSNode def, std::string_view owner ) noexcept
{
    for( TSNode p = parentOf( def ); !ts_node_is_null( p ); p = parentOf( p ) )
    {
        const std::string_view t = ts_node_type( p );
        if( t == owner )
        {
            return true;
        }
        if( t.find( "function" ) != std::string_view::npos )
        {
            return false;
        }
    }
    return false;
}
inline bool paramKindIn( std::string_view t, const std::string_view ( &kinds )[2] ) noexcept
{
    return ( !kinds[0].empty() && t == kinds[0] ) || ( !kinds[1].empty() && t == kinds[1] );
}

// B2.2 CALL-COMPARABLE ARITY + MINIMUM. `exact`: is `params` a FIXED arity that can be compared 1:1 against a call
// site's positional-argument count? True ONLY when EVERY qualifying condition holds, so the safe default (any
// uncertainty) is FALSE → the resolver never drops that candidate for too MANY arguments. Conditions:
//   * the language is one whose method params do NOT include an implicit receiver AND whose default/variadic
//     forms we can positively detect (C++/Java/Swift/TS/JS). Python is filterable for FREE FUNCTIONS only —
//     a Python/Ruby METHOD lists `self`/`cls`, which the call site omits, so a naive count is off by one.
//   * the def actually HAS a parameter-list node (an empty `()` counts — a real 0-arity), and
//   * that list contains NO variadic (`...`, `*args`/`**kwargs`, Java `...`, rest `...x`) and NO defaulted /
//     optional parameter (`= v`, TS `x?`) — any of which makes the accepted arity a RANGE, not a point.
// `minimum`: the fewest arguments a call can pass — the list's parameters minus its defaulted ones and minus what is
// no parameter (kParamMinLangs). 0 = no lower bound known: no row, a variadic or implicit-self list, a receiver
// parameter, a decorated def, a Python method, a function value typed elsewhere, or no list. The resolver takes the minimum over this def AND every declaration of
// it (graph.h paramsMinAcrossDeclarations), because C++ may put the default on a separate prototype only.
// A bounded pre-order scan of the FIRST parameter list mirrors countParams; deterministic.
struct ParamShape
{
    bool          exact   = false;
    std::uint16_t minimum = 0;
};
inline ParamShape cc_paramShape( TSNode defNode, Lang lang, SymKind kind, std::string_view src )   // NOT noexcept — allocates
{
    // language / kind gate — see the header. Only these emit a filterable arity.
    const bool langOk =    lang == Lang::Cpp || lang == Lang::Java || lang == Lang::Swift
                        || lang == Lang::TypeScript || lang == Lang::JavaScript || lang == Lang::Python;
    if( !langOk )
    {
        return {};
    }
    if( ( lang == Lang::Python || lang == Lang::Ruby ) && kind == SymKind::Method )
    {
        return {}; // implicit self/cls
    }
    const ParamMinLang* row = findByField( kParamMinLangs, &ParamMinLang::lang, lang );   // nullptr = no row: no lower bound

    // an "elastic" (variadic / default / optional) node kind or token makes the arity a RANGE → not filterable.
    const auto isElastic = []( const char* t ) noexcept
    {
        return    std::strstr( t, "variadic" ) != nullptr || std::strstr( t, "splat" )   != nullptr
               || std::strstr( t, "spread" )   != nullptr || std::strstr( t, "optional" )!= nullptr
               || std::strstr( t, "default" )  != nullptr || kindIs( t, "rest_pattern" )
               || kindIs( t, "..." ) || kindIs( t, "=" );
    };
    // a direct child of the list that its row says carries a default; its subtree is not scanned for elastic forms
    // (its own `=` / kind name is what the scan would find), it only makes the arity a range.
    const auto isDefaulted = [ row ]( TSNode c ) noexcept
    {
        if( row == nullptr )
        {
            return false;
        }
        const std::string_view t = ts_node_type( c );
        return paramKindIn( t, row->defaulted )
            || ( !row->defaultedWithValue.empty() && t == row->defaultedWithValue && !ts_node_is_null( fieldChild( c, NodeField::Value ) ) );
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
        // re-derivation bound (2026-09-10): see countParams
        if( f.depth > 12 )
        {
            continue;
        }
        const char* t = ts_node_type( f.n );
        if( f.n.id != defNode.id && cc_isParamList( t ) )       // the FIRST parameter list — classify and scan it
        {
            collectChildren( f.n, cursor.cur, kids );           // the list's direct children — read before the scan below reuses kids
            // uint32: a generated list can hold 65,536+ children, and a wrapped `named` broke the ASSUME below.
            std::uint32_t named = 0, defaulted = 0, notParam = 0;
            bool          elastic = false, receiver = false, untyped = false;
            TSNode        lone{};
            struct QF { TSNode n; std::uint16_t depth; };
            std::vector<QF> q;
            q.reserve( 32 );
            for( const TSNode c : kids )
            {
                const char* ct = ts_node_type( c );
                if( ts_node_is_named( c ) && !kindIs( ct, "comment" ) )
                {
                    ++named;
                    lone    = c;
                    untyped = untyped || ts_node_is_null( fieldChild( c, NodeField::Type ) );
                    if( isDefaulted( c ) )
                    {
                        ++defaulted;
                        continue;                              // its `=` / kind is the default, not a variadic form
                    }
                    notParam += ( row != nullptr && paramKindIn( ct, row->notParam ) ) ? 1u : 0u;
                }
                q.push_back( { c, 1 } );
            }
            while( !q.empty() && !elastic )
            {
                const QF g = q.back();
                q.pop_back();
                if( g.depth > 6 )
                {
                    continue; // param forms live shallow inside the list
                }
                const char* gt = ts_node_type( g.n );
                elastic  = isElastic( gt );
                receiver = receiver || ( g.depth == 2 && row != nullptr && !row->receiverChild.empty() && std::string_view( gt ) == row->receiverChild );
                collectChildren( g.n, cursor.cur, kids );
                for( const TSNode c : kids )
                {
                    q.push_back( { c, std::uint16_t( g.depth + 1 ) } );
                }
            }
            ParamShape shape;
            shape.exact = !elastic && defaulted == 0;
            const TSNode decoParent = parentOf( defNode );
            const bool   decorated  = row != nullptr && !row->decoratedParent.empty() && !ts_node_is_null( decoParent )
                                   && std::string_view( ts_node_type( decoParent ) ) == row->decoratedParent;
            const bool   method     = row != nullptr && !row->selfOwner.empty() && ownedBy( defNode, row->selfOwner );
            const bool   soleVoid   = row != nullptr && !row->soleVoid.empty() && named == 1 && nodeTextOf( lone, src ) == row->soleVoid;
            // a function VALUE whose signature lives elsewhere (row comment `fnValue`): annotated or cast binding, or a
            // contextually typed (untyped) parameter.
            const TSNode fnNode     = parentOf( f.n );
            const TSNode binding    = ts_node_is_null( fnNode ) ? TSNode{} : parentOf( fnNode );
            const bool   fnValue    = row != nullptr && !ts_node_is_null( fnNode ) && paramKindIn( ts_node_type( fnNode ), row->fnValue );
            const bool   typedElsewhere = fnValue
                                   && ( untyped || ts_node_is_null( binding ) || !ts_node_eq( fieldChild( binding, NodeField::Value ), fnNode )
                                        || !ts_node_is_null( fieldChild( binding, NodeField::Type ) ) );
            if( row != nullptr && !elastic && !receiver && !decorated && !method && !soleVoid && !typedElsewhere )
            {
                ASSUME( defaulted + notParam <= named );   // each counted child is one of the named ones
                shape.minimum = std::uint16_t( std::min<std::uint32_t>( named - defaulted - notParam, std::numeric_limits<std::uint16_t>::max() ) );
            }
            ENSURES( shape.minimum <= named );
            return shape;
        }
        collectChildren( f.n, cursor.cur, kids );
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], std::uint16_t( f.depth + 1 ) } );
        }
    }
    return {};   // no parameter-list node found at all → can't be sure → not filterable (safe)
}

// #155 KOTLIN TRAILING LAMBDA: true when a Kotlin call_expression writes its lambda AFTER the argument list — the grammar's
// annotated_lambda directly under its call_suffix: `s.run { }`, `with( sb ) { }`, `s?.let { }`, `xs.also { }`. The lambda of
// `s.let( { } )` sits inside value_arguments, so it is NOT a trailing lambda (a disclosed floor, FalseEdgeRules' Kotlin arm).
// Not noexcept: firstChildOfKind's cursor allocates (infra/tschildren.h A4-F25).
inline bool kotlinTrailingLambda( TSNode call )
{
    const TSNode suffix = kindIs( ts_node_type( call ), "call_expression" ) ? firstChildOfKind( call, /*namedOnly=*/true, { "call_suffix" } ) : TSNode{};   // one call_suffix per call_expression
    return !ts_node_is_null( suffix ) && !ts_node_is_null( firstChildOfKind( suffix, /*namedOnly=*/true, { "annotated_lambda" } ) );
}

// The argument-list node of the call whose callee identifier is `nameNode`: walks up a bounded number of parents to the enclosing
// CALL node (the callee sits 1-2 levels below it), then takes its `arguments` field, else the first child of a known list type.
// A null node when no call or no list is found.
inline TSNode callArgumentList( TSNode nameNode ) noexcept
{
    TSNode call{};
    bool   found = false;
    TSNode n = nameNode;
    for( int hop = 0; hop < 4 && !ts_node_is_null( n ); ++hop )
    {
        const TSNode p = parentOf( n );   // the climb reads the file's cached ancestor path (infra/tsparent.h)
        if( ts_node_is_null( p ) )
        {
            break;
        }
        const char* pt = ts_node_type( p );
        if(    kindIs( pt, "call_expression" )     // C++/TS/JS/Swift
            || kindIs( pt, "call" )                // Python
            || kindIs( pt, "method_invocation" )   // Java
            || kindIs( pt, "invocation_expression" ) )   // C#
        { call = p; found = true; break; }
        n = p;
    }
    if( !found )
    {
        return TSNode{};
    }
    TSNode args = fieldChild( call, NodeField::Arguments );
    if( ts_node_is_null( args ) )
    {
        ChildCursor callCursor( call );
        forEachChild( call, callCursor.cur, [ & ]( TSNode c )
        {   const char* ct = ts_node_type( c );
            if( !kindIs( ct, "argument_list" ) && !kindIs( ct, "arguments" ) && !kindIs( ct, "value_arguments" ) ) { return true; }   // Swift
            args = c;
            return false; } );
    }
    return args;
}

// B2.2 CALL-SITE ARITY: count the positional arguments of the call whose callee identifier is `nameNode`.
// Returns { argCount, known }. `known` is true ONLY when a recognized call node + argument container is
// found for a supported language AND no spread/splat/apply/pack-expansion argument is present (which would make the count
// unreliable). Any uncertainty → { 0, false } so the resolver never arity-filters that call (zero false
// negatives). Pure-syntactic, deterministic, allocation-free. Languages: C++/Python/TS/JS/Java/Swift/C#.
inline std::pair<std::uint16_t, bool> callArity( TSNode nameNode, Lang lang, std::string_view /*src*/ ) noexcept
{
    const TSNode args = callArgumentList( nameNode );
    if( ts_node_is_null( args ) )
    {
        return { 0, false };
    }

    // count NAMED argument children; a spread / splat / apply argument makes the count unreliable → not known.
    // O(children): the `comment` skip below is itself the proof that this list's width is INPUT-set, and this
    // counter runs once per CALL SITE, so the indexed form was O(calls x C²) — arm B11, 56x its control.
    std::uint32_t count      = 0;   // wider than the uint16 result: an overflowing count is unknown below, never a wrapped known one
    bool          unreliable = false;
    ChildCursor   argsCursor( args );
    forEachChild( args, argsCursor.cur, [ & ]( TSNode c )
    {   if( !ts_node_is_named( c ) ) { return true; }                                          // '(' ')' ',' separators
        const char* ct = ts_node_type( c );
        if( kindIs( ct, "comment" ) ) { return true; }
        if(    std::strstr( ct, "splat" ) != nullptr || std::strstr( ct, "spread" ) != nullptr || kindIs( ct, "..." )
            || kindIs( ct, "parameter_pack_expansion" ) )
        {
            unreliable = true;                                    // `f(*args)` / `f(...xs)` / C++ `f(t...)` (a pack of any size) → unreliable
            return false;
        }
        ++count;
        return true; } );
    (void)lang;
    if( unreliable || count > std::numeric_limits<std::uint16_t>::max() )
    {
        return { 0, false };   // CR #586: 65,536+ arguments wrapped to a KNOWN 0 and arity-dropped the right def
    }
    return { std::uint16_t( count ), true };
}

// The KEYWORD arguments of the Python call whose callee identifier is `nameNode`, as the byte pyKwTag writes (model.h): the count
// (low 7 bits, saturating) and kCallKwOther when any keyword is spelled other than `timeout` / `block`, the two the queue
// signatures (queue.Queue.put/get, asyncio.Queue) take. Read only for the queue operations (isQueueCallName); the resolver's
// arity filter keeps counting them in argCount. 0 when there is none.
inline std::uint8_t callKeywords( TSNode nameNode, std::string_view src ) noexcept
{
    const TSNode args = callArgumentList( nameNode );
    if( ts_node_is_null( args ) )
    {
        return 0;
    }
    std::uint8_t kw = 0;
    ChildCursor  argsCursor( args );
    forEachNamedChild( args, argsCursor.cur, [ & ]( TSNode c )
    {   if( !kindIs( ts_node_type( c ), "keyword_argument" ) ) { return true; }
        const TSNode           nameN   = fieldChild( c, NodeField::Name );
        const std::uint32_t    a       = ts_node_is_null( nameN ) ? 0 : ts_node_start_byte( nameN );
        const std::uint32_t    b       = ts_node_is_null( nameN ) ? 0 : ts_node_end_byte( nameN );
        const std::string_view spelled = a < b && b <= src.size() ? src.substr( a, b - a ) : std::string_view();
        const bool             queueKw = spelled == "timeout" || spelled == "block";
        kw = std::uint8_t( std::min<unsigned>( ( kw & kCallKwCount ) + 1u, kCallKwCount ) | ( kw & kCallKwOther ) | ( queueKw ? 0u : kCallKwOther ) );
        return true; } );
    return kw;
}
}   // namespace — ingest_metrics.h section of ingest.cpp

}   // namespace rw
