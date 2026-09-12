#!/usr/bin/env bash
# childwalkscalecheck.sh — the SCALING gate for every unbounded indexed child walk left after audit P1-0,
# and the answers each of them must still produce. Lane W2 wrote arms (B1..B6) for the ten class-1
# `ts_node_child( n, i )` walks; lane W3 added (B7..B9) for the last two — bindsVisitNode's index-keyed
# field lookup and --slice`s rung-3 flow walk (`ts_node_named_child`, the same defect with
# include_anonymous=false) — and (B10..B12) for the three "class 3" sites that refuted the class-3 table.
# Lane W4 (2026-09-10) added (B13..B36): one isolation arm for every indexed loop the W3 handover left
# unaudited across src/ingest_relations.h, ingest_names.h, ingest_elixir.h, ingest_sidecap.h and
# pattern.h — twenty-two walks, EVERY one of them red on the pre-change binary (12x..86x its control).
#
#   bash test/childwalkscalecheck.sh                       # build/ripwire
#   bash test/childwalkscalecheck.sh .ripwire_pre          # the RED run (pre-change binary, indexed walks)
#   RIPWIRE_BIN=asan/ripwire bash test/childwalkscalecheck.sh
#   RIPWIRE_REF_BIN=/path/to/pre-change/ripwire bash test/childwalkscalecheck.sh   # arm (C)
#
# WHY A THIRD SCALING GATE. test/padscalecheck.sh covers the comment flood through the INGEST walks;
# test/preprocdeadscalecheck.sh covers `collectPreprocDeadRanges` (the include-guard flood the `#if` text
# gate hides from the first). Neither reaches the ten OTHER walks that indexed their children with
# `ts_node_child( n, i )` — five of them live behind a VERB (`--slice`, `--grep`, `--pattern`,
# `--lint --naming-locals`) that no ingest-shaped gate runs, and two more only enter on a file the parser
# had to recover in (`measureFileHealth`) or on an `extern "C"` block (`ffiVisitNode`).
#
# WHAT MAKES THE WALK QUADRATIC — AND WHAT DOES NOT. `ts_node_child( n, i )` restarts tree-sitter's child
# iterator at the first child every call (see the note on src/infra/tschildren.h), so indexing C children
# costs O(C^2) — but ONLY when the child list is FLAT. A grammar REPEAT (16 000 declarations at file
# scope, 16 000 elements in one brace initializer) is stored as a balanced tree of invisible `_repeat`
# nodes, and `ts_node__child` skips a whole invisible subtree in O(1) via `ts_node__relevant_child_count`
# (third_party/deps/tree_sitter/lib/src/node.c). Measured on the pre-change binary, 2026-09-10: a root of
# 128 000 DECLARATIONS is linear (8k/64k/128k = 0.04 / 0.33 / 0.63 s), while a root of 16 000 COMMENTS is
# 117x its own control. Comments are tree-sitter EXTRAS: the parser splices them into the child array
# itself, where no repeat node balances them. Every fixture below is therefore a COMMENT flood — a
# declaration flood of the same width proves nothing and would have shipped a green gate over a live
# defect.
#
# THE FIXTURE SHAPE IS "WIDE NODE, CHEAP CHILDREN". Each fixture makes ONE node's child list N wide and
# every child trivial to process, so what the arm measures is the indexing, not the per-child work. The
# first attempt at these fixtures made the children expensive (16 000 real statements inside the sliced
# definition) and buried the walk under sliceWalkOccurrence — the ratio came out linear with the defect
# still in place.
#
# ARMS
#   (A) ANSWERS — every converted verb still answers correctly ON THE FLOODED FIXTURE, so it is the
#       converted wide walk that produced the answer: the slice's vars, the grep hit, the pattern match,
#       the extern "C" symbol row, `parse_degraded="1"` for the recovered file, and the eight
#       `naming-underscore` LOCAL rows that only --naming-locals can reach. Plus determinism.
#   (B1..B12) SCALING — user CPU, every arm an ISOLATION pair: the SAME fixture width with the walk
#       ENTERED and NOT entered (--slice vs the plain map, --grep vs the plain map, --pattern vs the plain
#       map, --lint --naming-locals vs --lint, an error token present vs absent, `extern "C"` present vs
#       absent). An isolation pair names ONE walk instead of saying "the verb got slower", and it cannot
#       be defeated by a fixed start-up cost the way a 1k-vs-16k ratio can (ffiVisitNode's own 1k arm is
#       0.09 s of C++ ingest, which flattens its ratio to 13x while the walk is 13x its control).
#   (C) BYTE-IDENTICAL vs RIPWIRE_REF_BIN, every fixture x every reaching verb — the conversion must not
#       move one byte. SKIPPED and disclosed when RIPWIRE_REF_BIN is unset.
#   (D) MUTATION — the ratio verdict and the row readers are shown able to fail.
#
# User CPU, never wall, so a loaded box cannot flake the ratios; every ratio floors its divisor so a ~0 s
# small arm cannot manufacture a large one.
#
# NOT CONVERTED, AND WHY (the rest of the audit P1-0 follow-up table, whose class 1 this gate closes):
#   * src/slice.h sliceWalkPreproc HAS a scaling arm now — (B9) — and could not before. Two measurements
#     said why, and the second one is what changed. (i) Its natural isolation control (the identical flood
#     with the `#if` removed) routes through sliceWalk's own child loop, so that pair read 0.98x on BOTH
#     binaries and could never go red; the control used instead is the PLAIN MAP of the same file, which
#     enters neither slice walk. (ii) The arm could not go GREEN while --slice's rung-3 flow walk
#     (SliceRdWalker, 15 `ts_node_named_child` loops in this same file) was a LARGER quadratic on the same
#     path: --slice over a 16 000-comment definition was 2.38 s before lane W2, 1.21 s after it, and a
#     `sample` of the W2 binary put that residual 1.21 s in `ts_node_named_child` even on a fixture whose
#     slice resolves ZERO vars. Lane W3 converted that walk (B8), which is what lets (B9) go green.
#   * src/pattern.h smallestContaining / snapshotNode ARE converted, but have NO arm here and cannot get
#     one: both index the children of the PATTERN's parse tree, and pattern.h:78 caps a pattern at
#     kMaxPatternBytes = 4096 — every path in, --pattern and --lint-rules alike, goes through that one
#     check (pattern.h:683). 4096 bytes is ~2 000 children, i.e. ~2e6 iterator steps, ~1 ms. The cap is
#     why the site was never hot; the conversion is for uniformity and is covered by arm (C).
#   * src/ingest_binds.h (bindsVisitNode) IS converted now — arms (A9) and (B7), the gate this lane W2
#     asked for. Its declarator loop needed the INDEX for `ts_node_field_name_for_child( n, i )`, which is
#     the same restarting scan as `ts_node_child` and made the loop quadratic THREE times over per node
#     (one child fetch, two field lookups). The fix is the cursor's own O(1)
#     `ts_tree_cursor_current_field_name`, which is a SEMANTIC substitution, not a mechanical one — hence
#     this arm rather than a fold into a no-output-change lane. The two agree exactly, and the vendored
#     source says why: `ts_node_field_name_for_child` returns NULL for an EXTRA child and otherwise looks
#     up the non-inherited field entry at the child's structural index in its parent production, falling
#     back to the nearest field name inherited on the way down through invisible nodes
#     (third_party/deps/tree_sitter/lib/src/node.c:689); `ts_tree_cursor_current_field_id` performs the
#     identical lookup by walking the cursor's stack UP through exactly those invisible ancestors, breaks
#     on an extra, and stops at the next visible one (lib/src/tree_cursor.c:657). Same set, same
#     precedence, O(1) instead of O(C).
#     Why it was worth it: on a cold llvm-project map of the W2 binary (`sample`, 12 s of a 46 s run,
#     127 453 busy leaf samples) `ts_node_child_iterator_next` was still the #1 leaf at 14.26%, and
#     attributing its samples to the nearest non-tree-sitter caller put bindsVisitNode SECOND at 5 614 —
#     30% of that leaf, behind captureTagsFacts' 7 304 (the tags-query pass, a different shape). Then
#     qualifierOf 2 629, enclosingScopeOf 1 040, cc_isCountableLocalDecl 676, cc_walk 531.
#     bindsVisitNode's TypeScript `type_annotation` scan was converted in the same pass: it breaks at the
#     first `type_identifier`, but nothing bounds how many comments precede one.
#   * src/ingest_names.h (firstChildOfType) WAS kept indexed by W3 — "both callers pass a using_declaration
#     / qualified_identifier, whose width comes from the grammar" — which is the exact reason the next bullet
#     refutes. `using` + 16 000 comments + `namespace ns::inner;` measured 12.9x its control (B22). Converted.
#   * THE CLASS-3 TABLE WAS WRONG, AND ARMS (B10..B12) ARE WHAT SHOWS IT. The P1-0 follow-up called ~37
#     sites "class 3 — width from the GRAMMAR, correct as written": base clauses, argument and parameter
#     lists, attribute lists, a declaration's declarators. A comment can sit between ANY two children of
#     ANY node and tree-sitter splices the extra into that node's own child array, so a list's width is set
#     by the FILE wherever a comment may legally appear in it. Measured on the W2 binary, 16 000 comments
#     inside ONE list vs the identical flood just outside it: `declaration` 77x (B7), `argument_list` 56x
#     (B11), lambda capture list 26x (B12), `base_class_clause` 13x (B10). All four are converted.
#     W3's sweep then flooded fifteen language SHAPES on the fixed binary and found them flat — evidence of
#     absence for those shapes only, not clearance for the loops. Lane W4 went loop by loop instead, and the
#     difference is what (B13..B36) record: a Python base list is flat when the flood sits in the class body
#     (W3's shape) and 54x when it sits INSIDE the superclasses parens (B28); a Ruby class body is flat when
#     the comments LEAD the body (tree-sitter hands leading extras to the parent `class`, not to the
#     body_statement that has not started) and 58x once one nested class precedes them (B19); a C++ `using`
#     is flat in its unqualified spelling because that form is never captured, and 12.9x in the qualified
#     one (B22). A flat measurement proves the FIXTURE missed the list, never that the loop is safe. Every
#     arm below therefore records the shape that reached its walk, and the CPU `sample` that attributed the
#     two fixtures whose owner was not obvious (excall -> elixirBody; testmacrosemi -> the MISSING-`;` probe).
#     THE THREE LOOPS THAT STAY INDEXED, each with the one-line reason the note on src/infra/tschildren.h
#     demands, written at the loop: mdWalk (src/ingest_docs.h — the markdown grammar declares NO extras, its
#     parser.c has zero SHIFT_EXTRA actions, so every child list there is a balanced grammar repeat);
#     stringLiteralText (src/ingest_relations.h) and the Elixir test-title interpolation scan
#     (src/ingest_elixir.h) — a string's children are produced by the external scanner, which owns every
#     byte between the delimiters, so no comment token is ever lexed into that list.
#     TWO CONTROLS THAT WERE THEMSELVES QUADRATIC, and what they mean. The C# controls first put the flood
#     in the class body and read 1.09 s / 2.31 s — csharpNodeCarriesTestAttr is applied to every ANCESTOR
#     of a def (anySelfOrAncestor), so the declaration_list and the compilation_unit scanned the flood too.
#     The controls now flood a method BODY, which is no def's ancestor. And the Rust control floods AFTER
#     the item, because rustItemCarriesTestAttr's own prev-sibling climb (`ts_node_prev_sibling`, which
#     restarts from the parent's first child on every call) is a second restarting scan this gate does not
#     own — it is the parent-chain family, not a child walk, and is left for that lane.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
REF="${RIPWIRE_REF_BIN:-}"
[ -n "$REF" ] && [ "${REF#/}" = "$REF" ] && REF="$ROOT/$REF"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "childwalkscalecheck: python3 required"; exit 2; }
echo "childwalkscalecheck: BIN=$BIN"
[ -n "$REF" ] && echo "childwalkscalecheck: REF=$REF"

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────
# Generated, never committed: a committed 1 MB comment flood would join every OTHER gate's view of test/
# (trap: a gate fixture that is also part of the live tree the tool indexes).
python3 - "$TMP" <<'PY'
import os, sys
base = sys.argv[ 1 ]
C = "// pad " + "x" * 40
H = "# pad " + "x" * 40      # the `#` comment: Python, Ruby, Elixir
B = "/* pad */"              # a block comment: the one shape a preprocessor line can hold 16 000 of

def w( rel, lines ):
    p = os.path.join( base, rel )
    os.makedirs( os.path.dirname( p ), exist_ok = True )
    open( p, 'w' ).write( "\n".join( lines ) + "\n" )

for n in ( 1000, 16000 ):
    # sliceWalk — N comments as children of the ROOT, the sliced definition tiny and early
    w( "slicew/n%d/big.c" % n,
       [ "int helper( int x );", "int target( int x )", "{", "    int acc = x;",
         "    return helper( acc );", "}" ] + [ C ] * n )
    # sliceWalkPreproc — N comments as children of ONE `#if` block INSIDE the sliced definition
    w( "slicepp/n%d/big.c" % n,
       [ "int helper( int x );", "int target( int x )", "{", "    int acc = x;", "#if 1" ]
       + [ C ] * n + [ "#endif", "    return helper( acc );", "}" ] )
    # collectSpanTiers — N comments as children of the ROOT, reached by --grep's span-tier pass
    w( "span/n%d/big.c" % n, [ C ] * n + [ "// needle_marker", "int s0;" ] )
    # measureFileHealth — the same flood, plus ONE token the parser must recover from (walk ENTERED)
    w( "health/n%d/big.c" % n, [ C ] * n + [ "@ @ @", "int e0;" ] )
    # …and its control: byte-for-byte the same flood with no error token (walk RETURNS at the has_error check)
    w( "health_off/n%d/big.c" % n, [ C ] * n + [ "int e0;" ] )
    # ffiVisitNode — N comments as children of an `extern "C"` block's declaration list (walk ENTERED)
    w( "ffi/n%d/big.cpp" % n,
       [ 'extern "C" {' ] + [ C ] * n + [ 'int f0( int a );', '}', 'int useit( void ) { return f0( 1 ); }' ] )
    # …and its control: the same flood and the same declarations, no linkage_specification
    w( "ffi_off/n%d/big.cpp" % n,
       [ C ] * n + [ 'int f0( int a );', 'int useit( void ) { return f0( 1 ); }' ] )
    # ln_collectLocalDecls — N comments in a function body wide enough to clear namingLocalsGate
    # (loc bar AND locals >= 8); the eight locals carry a shape the naming rules report, so arm (A) can
    # prove the re-parse walk ran at all.
    w( "locals/n%d/big.c" % n,
       [ "int bigfun( int x )", "{", "    if( x > 0 )", "    {" ]
       + [ "        int loc__%d = x + %d;" % ( i, i ) for i in range( 8 ) ]
       + [ "        x = loc__0;", "    }" ] + [ C ] * n + [ "    return x;", "}" ] )
    # findMatches (root flood) + matchChildren (the candidate compound_statement's own flood)
    w( "pat/n%d/big.c" % n, [ "void f( void )", "{", "    int a;" ] + [ C ] * n + [ "}" ] + [ C ] * n )
    # bindsVisitNode — N comments as children of ONE `declaration` node (they sit between the type and
    # the declarator, so the declaration's own child list is the flood). TWO same-named methods make the
    # declarator binding OBSERVABLE: with it, `a.m()` resolves to Foo::m alone; without it the call is
    # ambiguous and BOTH methods get a caller (measured, arm A9).
    w( "binds/n%d/big.cpp" % n,
       [ "struct Foo { int m( void ); };", "struct Bar { int m( void ); };", "int bigfun( void )", "{", "    Foo" ]
       + [ C ] * n + [ "    a;", "    return a.m();", "}" ] )
    # …and its control: the identical flood in the same body, OUTSIDE the declaration (the walk is still
    # entered on the declaration — its child list is just 3 wide instead of N)
    w( "binds_off/n%d/big.cpp" % n,
       [ "struct Foo { int m( void ); };", "struct Bar { int m( void ); };", "int bigfun( void )", "{", "    Foo a;" ]
       + [ C ] * n + [ "    return a.m();", "}" ] )
    # captureBases — N comments as children of ONE `base_class_clause`. This list LOOKS grammar-bounded (a
    # class's base types) and the P1-0 follow-up table called it class 3 for that reason; EXTRAS refute it.
    w( "bases/n%d/big.cpp" % n,
       [ "struct A { int m( void ); };", "struct B : public A," ] + [ C ] * n
       + [ "   public A { int q( void ); };" ] )
    # …and its control: the identical flood between the two structs, outside any clause
    w( "bases_off/n%d/big.cpp" % n,
       [ "struct A { int m( void ); };" ] + [ C ] * n
       + [ "struct B : public A, public A { int q( void ); };" ] )
    # ccCallArity's argument scan — N comments inside ONE `argument_list`. Same refutation: the scan already
    # skipped `comment` children by kind, which is the author knowing they land here, indexed anyway.
    w( "args/n%d/big.c" % n,
       [ "int g( int a, int b );", "int f( void )", "{", "    return g( 1," ] + [ C ] * n + [ "    2 );", "}" ] )
    w( "args_off/n%d/big.c" % n,
       [ "int g( int a, int b );", "int f( void )", "{", "    return g( 1, 2 );" ] + [ C ] * n + [ "}" ] )
    # captureLambdaShadowDecls — N comments inside ONE lambda capture list
    w( "lcap/n%d/big.cpp" % n,
       [ "int f( int x )", "{", "    auto L = [ x," ] + [ C ] * n + [ "      & ](){ return x; };", "    return L();", "}" ] )
    w( "lcap_off/n%d/big.cpp" % n,
       [ "int f( int x )", "{", "    auto L = [ x, & ](){ return x; };" ] + [ C ] * n + [ "    return L();", "}" ] )
    # SliceRdWalker (--slice's rung-3 flow walk) — N comments on either side of an `if` INSIDE the sliced
    # definition's body, so seq/structure/hasStructureBelow/ifC are the wide loops. slicew above floods the
    # ROOT and leaves the definition narrow, which is why it never reached this walk.
    w( "slicerd/n%d/big.c" % n,
       [ "int helper( int x );", "int target( int x )", "{", "    int acc = x;" ] + [ C ] * n
       + [ "    if( x > 0 )", "    {", "        acc = x + 1;", "    }" ] + [ C ] * n
       + [ "    return helper( acc );", "}" ] )
    # ── lane W4: one pair per walk the W3 handover left indexed. Each floods ONE node's own child list and
    # its control puts the identical flood where no walk under test owns it as a direct child.
    # captureMacroBodyCalls — a preproc_params list (block comments: a #define is one logical line)
    w( "macroparams/n%d/big.c" % n, [ "int h( int a, int b );", "#define F( a, " + B * n + " b ) h( a, b )", "int g( int x ) { return F( x, 1 ); }" ] )
    w( "macroparams_off/n%d/big.c" % n, [ "int h( int a, int b );", B * n, "#define F( a, b ) h( a, b )", "int g( int x ) { return F( x, 1 ); }" ] )
    # captureFields, the type walk — a qualified_identifier `ns /*…*/ ::T` as a field's type
    w( "fieldtype/n%d/big.cpp" % n, [ "namespace ns { struct T { int q; }; }", "struct S", "{", "    ns" ] + [ C ] * n + [ "    ::T m;", "};" ] )
    w( "fieldtype_off/n%d/big.cpp" % n, [ "namespace ns { struct T { int q; }; }", "struct S", "{", "    ns::T m;" ] + [ C ] * n + [ "};" ] )
    # captureFields, the declarator walk — a reference_declarator `T & /*…*/ m`
    w( "fielddecl/n%d/big.cpp" % n, [ "struct T { int q; };", "struct S", "{", "    T &" ] + [ C ] * n + [ "    m;", "};" ] )
    w( "fielddecl_off/n%d/big.cpp" % n, [ "struct T { int q; };", "struct S", "{", "    T & m;" ] + [ C ] * n + [ "};" ] )
    # csharpUsingTarget — a using_directive; its control floods a method BODY (see the header: a class body
    # or the file root is an ancestor of every def, and the ancestor scan would read the flood too)
    w( "csusing/n%d/big.cs" % n, [ "using" ] + [ C ] * n + [ "    System.Text;", "namespace A { class K { void M() {} } }" ] )
    w( "csusing_off/n%d/big.cs" % n, [ "using System.Text;", "namespace A { class K { void M() {" ] + [ C ] * n + [ "} } }" ] )
    # phpUseTarget — a namespace_use_declaration
    w( "phpuse/n%d/big.php" % n, [ "<?php", "namespace A;", "use" ] + [ C ] * n + [ "    Foo\\Bar;", "function f() {}" ] )
    w( "phpuse_off/n%d/big.php" % n, [ "<?php", "namespace A;", "use Foo\\Bar;" ] + [ C ] * n + [ "function f() {}" ] )
    # jsModuleLoadTarget — require()'s arguments
    w( "jsrequire/n%d/big.js" % n, [ "const m = require(" ] + [ C ] * n + [ "    'mod' );", "function f() { return m; }" ] )
    w( "jsrequire_off/n%d/big.js" % n, [ "const m = require( 'mod' );" ] + [ C ] * n + [ "function f() { return m; }" ] )
    # rubyNamespaceOnly — a class body_statement; ONE nested class precedes the flood so the comments are
    # the body's children (leading extras go to the parent `class` node, whose body has not started)
    w( "rubyns/n%d/big.rb" % n, [ "class Foo", "  class Baz", "  end" ] + [ H ] * n + [ "  class Bar", "  end", "end" ] )
    w( "rubyns_off/n%d/big.rb" % n, [ "class Foo", "  class Baz", "  end", "  class Bar", "  end", "end" ] + [ H ] * n )
    # rubyMixinTargets — an `include` argument_list
    w( "rubymixin/n%d/big.rb" % n, [ "module A; end", "module B; end", "class Foo", "  include A," ] + [ "  " + H ] * n + [ "    B", "end" ] )
    w( "rubymixin_off/n%d/big.rb" % n, [ "module A; end", "module B; end", "class Foo", "  include A, B" ] + [ "  " + H ] * n + [ "end" ] )
    # elixirAliasGroup — an `alias Foo.{…}` tuple
    w( "exalias/n%d/big.ex" % n, [ "defmodule M do", "  alias Foo.{A," ] + [ "  " + H ] * n + [ "    B}", "  def f, do: 1", "end" ] )
    w( "exalias_off/n%d/big.ex" % n, [ "defmodule M do", "  alias Foo.{A, B}" ] + [ "  " + H ] * n + [ "  def f, do: 1", "end" ] )
    # firstChildOfType — a using_declaration, in the QUALIFIED spelling the tags query captures
    w( "cppusing/n%d/big.cpp" % n, [ "namespace ns { namespace inner { int q; } }", "using" ] + [ C ] * n + [ "    namespace ns::inner;", "int f( void ) { return q; }" ] )
    w( "cppusing_off/n%d/big.cpp" % n, [ "namespace ns { namespace inner { int q; } }", "using namespace ns::inner;" ] + [ C ] * n + [ "int f( void ) { return q; }" ] )
    # rustItemCarriesTestAttr — an attribute_item; control flood AFTER the item (see the header)
    w( "rustattr/n%d/big.rs" % n, [ "#[" ] + [ C ] * n + [ "test]", "fn t() { let a = 1; }" ] )
    w( "rustattr_off/n%d/big.rs" % n, [ "#[test]", "fn t() { let a = 1; }" ] + [ C ] * n )
    # csharpNodeCarriesTestAttr — a method_declaration's own children; control floods its body
    w( "csattr/n%d/big.cs" % n, [ "namespace A { class K {", "public" ] + [ C ] * n + [ "void M() {}", "} }" ] )
    w( "csattr_off/n%d/big.cs" % n, [ "namespace A { class K {", "public void M() {" ] + [ C ] * n + [ "}", "} }" ] )
    # testMacroBlockPartsOf — the argument scan (flood inside the parens) and the MISSING-`;` probe (flood
    # between `)` and `{`, which the recovered expression_statement owns); one control serves both
    w( "testmacro/n%d/big.cpp" % n, [ "TEST_CASE(" ] + [ C ] * n + [ "    \"title\" ) { int a = 1; }" ] )
    w( "testmacrosemi/n%d/big.cpp" % n, [ "TEST_CASE( \"title\" )" ] + [ C ] * n + [ "{ int a = 1; }" ] )
    w( "testmacro_off/n%d/big.cpp" % n, [ "TEST_CASE( \"title\" ) { int a = 1; }" ] + [ C ] * n )
    # childTokenAmong — a field_declaration with NO `static`, so the scan runs to the end
    w( "fieldstatic/n%d/big.cpp" % n, [ "struct S", "{", "    int" ] + [ C ] * n + [ "    m;", "};" ] )
    w( "fieldstatic_off/n%d/big.cpp" % n, [ "struct S", "{", "    int m;" ] + [ C ] * n + [ "};" ] )
    # isPyEnumMemberTarget — the superclasses argument_list (W3's flood sat in the class body: flat)
    w( "pyenum/n%d/big.py" % n, [ "from enum import Enum", "class C(" ] + [ H ] * n + [ "    Enum", "):", "    A = 1" ] )
    w( "pyenum_off/n%d/big.py" % n, [ "from enum import Enum", "class C( Enum ):", "    A = 1" ] + [ H ] * n )
    # elixirKeywordValue — a def's arguments between the head and `do:`
    w( "exkw/n%d/big.ex" % n, [ "defmodule M do", "  def f(x)," ] + [ "  " + H ] * n + [ "    do: x", "end" ] )
    w( "exkw_off/n%d/big.ex" % n, [ "defmodule M do", "  def f(x), do: x" ] + [ "  " + H ] * n + [ "end" ] )
    # elixirBody — a call's OWN child list: comments between the head and its do_block (attributed by
    # `sample`: 3 441 of 3 441 busy samples under elixirBody -> ts_node_named_child)
    w( "excall/n%d/big.ex" % n, [ "defmodule M do", "  def f(x)" ] + [ "  " + H ] * n + [ "  do", "    x", "  end", "end" ] )
    w( "excall_off/n%d/big.ex" % n, [ "defmodule M do", "  def f(x) do", "    x", "  end" ] + [ "  " + H ] * n + [ "end" ] )
    # ffiVisitNode, the pybind arm — `m.def(…)`'s argument_list (the file names pybind11, which arms it)
    w( "pybind/n%d/big.cpp" % n, [ "#include <pybind11/pybind11.h>", "int f( int a );", "PYBIND11_MODULE( m, mod )", "{", "    mod.def(" ] + [ C ] * n + [ "        \"f\", &f );", "}" ] )
    w( "pybind_off/n%d/big.cpp" % n, [ "#include <pybind11/pybind11.h>", "int f( int a );", "PYBIND11_MODULE( m, mod )", "{", "    mod.def( \"f\", &f );" ] + [ C ] * n + [ "}" ] )
    # ffiVisitNode, the linkage-string scan — between `extern` and `"C"` (ffi/ above floods the BODY)
    w( "externc/n%d/big.cpp" % n, [ "extern" ] + [ C ] * n + [ "\"C\" {", "int f0( int a );", "}", "int useit( void ) { return f0( 1 ); }" ] )
    w( "externc_off/n%d/big.cpp" % n, [ C ] * n + [ "extern \"C\" {", "int f0( int a );", "}", "int useit( void ) { return f0( 1 ); }" ] )
    # pyMethodsKeyword — a Flask route decorator's argument_list
    w( "pyroute/n%d/big.py" % n, [ "from flask import Flask", "app = Flask( __name__ )", "@app.route( \"/x\"," ] + [ H ] * n + [ "    methods=[ \"POST\" ] )", "def h():", "    return 1" ] )
    w( "pyroute_off/n%d/big.py" % n, [ "from flask import Flask", "app = Flask( __name__ )", "@app.route( \"/x\", methods=[ \"POST\" ] )", "def h():", "    return 1" ] + [ H ] * n )
    # jsMethodProperty — fetch()'s options object
    w( "jsfetch/n%d/big.js" % n, [ "function g() {", "    return fetch( '/x', {" ] + [ C ] * n + [ "        method: 'POST' } );", "}" ] )
    w( "jsfetch_off/n%d/big.js" % n, [ "function g() {", "    return fetch( '/x', { method: 'POST' } );" ] + [ C ] * n + [ "}" ] )
    # captureTagsFacts, the ObjC body fallback — a method_definition's own children before its `{`
    w( "objcbody/n%d/big.m" % n, [ "@interface Foo", "@end", "@implementation Foo", "- (void) m" ] + [ C ] * n + [ "{ }", "@end" ] )
    w( "objcbody_off/n%d/big.m" % n, [ "@interface Foo", "@end", "@implementation Foo", "- (void) m { }" ] + [ C ] * n + [ "@end" ] )
    # nodesMatchExactly — two flooded argument_lists joined by a repeated metavariable (`$X == $X`); its
    # control runs the SAME --pattern over the same two floods placed in the body OUTSIDE both argument
    # lists, so both sides execute nodesMatchExactly and only the flooded list differs (CodeRabbit, #130)
    w( "patmeta/n%d/big.c" % n, [ "int a( int x );", "int f( void )", "{", "    return a(" ] + [ C ] * n + [ "    1 ) == a(" ] + [ C ] * n + [ "    1 );", "}" ] )
    w( "patmeta_off/n%d/big.c" % n, [ "int a( int x );", "int f( void )", "{", "    return a( 1 ) == a( 1 );" ] + [ C ] * n + [ C ] * n + [ "}" ] )
PY

# user-CPU seconds (user+sys) of one cold run of "$@" against corpus $1
usercpu(){ # $1 = corpus dir, rest = binary + flags
    local dir="$1"; shift
    { /usr/bin/time -p "$@" "$dir" --no-cache >/dev/null; } 2>"$TMP/t" || { echo FAIL; return; }
    awk '/^user/ { u = $2 } /^sys/ { s = $2 } END { printf "%.2f", u + s }' "$TMP/t"
}

# The one ratio verdict, so no arm hand-rolls a second arithmetic for the same job. Prints
# "fast" | "linear" | "quad <ratio>". $1 small/control, $2 big, $3 ratio ceiling, $4 absolute short-circuit.
verdict(){ awk -v s="$1" -v b="$2" -v cap="$3" -v floor="$4" 'BEGIN {
    if( b + 0 < floor + 0 ) { print "fast"; exit }        # absolute cost already fine — scaling is moot
    if( s + 0 < 0.02 ) { s = 0.02 }                       # floor the divisor: a ~0 arm cannot invent a ratio
    if( b / s < cap + 0 ) { printf "linear %.1f", b / s } else { printf "quad %.1f", b / s }
}'; }

# One scaling arm. $1 = label, $2 = control CPU, $3 = walk CPU, $4 ceiling, $5 floor, $6 = what the pair is
arm(){
    local label="$1" c="$2" w="$3" cap="$4" fl="$5" what="$6"
    if [ "$c" = FAIL ] || [ "$w" = FAIL ] || [ -z "$c" ] || [ -z "$w" ]; then
        no "$label a timed run failed outright"; return
    fi
    local v; v="$( verdict "$c" "$w" "$cap" "$fl" )"
    case "$v" in
        fast)      ok "$label ${w}s CPU < ${fl}s — the O(C^2) walk is absent ($what, control ${c}s)";;
        linear\ *) ok "$label ${v#linear } x its control (walk=${w}s control=${c}s) — under the ${cap}x ceiling";;
        *)         no "$label ${v#quad } x its control — $what is quadratic in child count (walk=${w}s control=${c}s)";;
    esac
}

count_rows(){ python3 -c '
import re,sys
sys.stdout.write( str( len( re.findall( sys.argv[2], open( sys.argv[1] ).read() ) ) ) )' "$1" "$2"; }

# ── (A) the answers, on the FLOODED fixtures ─────────────────────────────────────────────────────────
echo
echo "=== (A) every converted walk still answers, on a 1000-comment-wide node ==="

"$BIN" "$TMP/slicew/n1000" --no-cache --slice=target >"$TMP/a_slice.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_slice.xml" '<v n="acc"' )" = 1 ] && [ "$( count_rows "$TMP/a_slice.xml" '<v n="x"' )" = 1 ]; then
    ok "(A1) sliceWalk: --slice=target still finds both vars (param x, decl acc) past a 1000-comment root"
else
    no "(A1) sliceWalk: --slice=target lost a var on the flooded fixture"
fi
"$BIN" "$TMP/slicepp/n1000" --no-cache --slice=target >"$TMP/a_slicepp.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_slicepp.xml" '<v n="acc"' )" = 1 ]; then
    ok "(A2) sliceWalkPreproc: --slice=target still finds acc across a 1000-comment \`#if\` block"
else
    no "(A2) sliceWalkPreproc: --slice=target lost acc across the flooded \`#if\` block"
fi
"$BIN" "$TMP/span/n1000" --no-cache --grep=needle_marker >"$TMP/a_grep.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_grep.xml" 'tier="comment"' )" = 1 ] && [ "$( count_rows "$TMP/a_grep.xml" '<hit ' )" = 1 ]; then
    ok "(A3) collectSpanTiers: --grep still finds the hit AND still classifies it tier=comment"
else
    no "(A3) collectSpanTiers: --grep lost the hit or its comment tier on the flooded fixture"
fi
"$BIN" "$TMP/health/n1000" --no-cache --grep=pad >"$TMP/a_health.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_health.xml" '<f p="big[.]c" parse_degraded="1"' )" = 1 ]; then
    ok "(A4) measureFileHealth: the recovered file is still flagged parse_degraded=\"1\""
else
    no "(A4) measureFileHealth: the recovered file lost its parse_degraded flag"
fi
"$BIN" "$TMP/ffi/n1000" --no-cache --top-k=100000 >"$TMP/a_ffi.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_ffi.xml" '<c n="f0"/>' )" = 1 ]; then
    ok "(A5) ffiVisitNode: the extern \"C\" declaration is still resolved as a call target"
else
    no "(A5) ffiVisitNode: the extern \"C\" call edge is gone on the flooded fixture"
fi
"$BIN" "$TMP/locals/n1000" --no-cache --lint --naming-locals >"$TMP/a_loc_on.xml" 2>/dev/null
"$BIN" "$TMP/locals/n1000" --no-cache --lint                 >"$TMP/a_loc_off.xml" 2>/dev/null
A_ON="$(  count_rows "$TMP/a_loc_on.xml"  '<f rule="naming-underscore"' )"
A_OFF="$( count_rows "$TMP/a_loc_off.xml" '<f rule="naming-underscore"' )"
if [ "$A_ON" = 8 ] && [ "$A_OFF" = 0 ]; then
    ok "(A6) ln_collectLocalDecls: all 8 local naming rows are still served (and 0 without --naming-locals)"
else
    no "(A6) ln_collectLocalDecls: expected 8 local rows with --naming-locals and 0 without; got $A_ON / $A_OFF"
fi
"$BIN" "$TMP/pat/n1000" --no-cache --pattern='{ int a; ... }' >"$TMP/a_pat.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_pat.xml" '<m p="big.c:2" in="f">' )" = 1 ]; then
    ok "(A7) findMatches/matchChildren: the pattern still matches f's body past 1000 comment children"
else
    no "(A7) findMatches/matchChildren: the pattern lost its match on the flooded body"
fi
callers_count(){ # $1 = corpus, $2 = fully qualified symbol -> the callers verb's count= attribute
    "$BIN" "$1" --no-cache --callers="$2" 2>/dev/null | sed -n 's/.*<callers [^>]*count="\([0-9]*\)".*/\1/p'
}
A_FOO="$( callers_count "$TMP/binds/n1000" 'big.cpp::Foo::m' )"
A_BAR="$( callers_count "$TMP/binds/n1000" 'big.cpp::Bar::m' )"
if [ "$A_FOO" = 1 ] && [ "$A_BAR" = 0 ]; then
    ok "(A9) bindsVisitNode: \`Foo a;\` still binds a->Foo past a 1000-comment declaration (Foo::m 1 caller, Bar::m 0)"
else
    no "(A9) bindsVisitNode: the declarator binding is gone — expected Foo::m=1 Bar::m=0, got $A_FOO / $A_BAR (ambiguous a.m() gives 1/1)"
fi
"$BIN" "$TMP/slicerd/n1000" --no-cache --slice=target:acc >"$TMP/a_rd.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_rd.xml" '<s l="2009" k="use" t="call-arg" rd="4,1007">' )" = 1 ]; then
    ok "(A10) SliceRdWalker: the use at line 2009 still joins BOTH defs (rd=\"4,1007\") across a 2000-comment body"
else
    no "(A10) SliceRdWalker: the reaching-def join is wrong — expected rd=\"4,1007\" on the line-2009 use row"
fi
# lane W4 — the four converted walks whose answer is visible in the map or a verb row
"$BIN" "$TMP/externc/n1000" --no-cache --top-k=100000 >"$TMP/a_externc.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_externc.xml" '<c n="f0"/>' )" = 1 ]; then
    ok "(A11) ffiVisitNode/linkage: \`extern /*…*/ \"C\"\` is still read as C linkage past 1000 comments (f0 is a call target)"
else
    no "(A11) ffiVisitNode/linkage: the linkage string was not found past the flood — the extern \"C\" call edge is gone"
fi
"$BIN" "$TMP/pyenum/n1000" --no-cache --top-k=100000 >"$TMP/a_pyenum.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_pyenum.xml" '<s t="var" n="A" id="big.py::C::A"' )" = 1 ]; then
    ok "(A12) isPyEnumMemberTarget: \`A = 1\` is still an enum member when Enum sits past 1000 comments in the base list"
else
    no "(A12) isPyEnumMemberTarget: the Enum base was not found past the flood — the member row is gone"
fi
"$BIN" "$TMP/testmacro/n1000" --no-cache --top-k=100000 >"$TMP/a_tm.xml" 2>/dev/null
"$BIN" "$TMP/testmacrosemi/n1000" --no-cache --top-k=100000 >"$TMP/a_tms.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_tm.xml" '<s t="fn" n="title"' )" = 1 ] && [ "$( count_rows "$TMP/a_tms.xml" '<s t="fn" n="title"' )" = 1 ]; then
    ok "(A13) testMacroBlockPartsOf: TEST_CASE still mints its \`title\` symbol with 1000 comments in the args AND with 1000 before the block"
else
    no "(A13) testMacroBlockPartsOf: the title string or the MISSING \`;\` was not found past the flood"
fi
"$BIN" "$TMP/patmeta/n1000" --no-cache --pattern='$X == $X' >"$TMP/a_pm.xml" 2>/dev/null
if [ "$( count_rows "$TMP/a_pm.xml" '<m p="big.c:4" in="f">' )" = 1 ]; then
    ok "(A14) nodesMatchExactly: \`\$X == \$X\` still unifies two calls whose argument lists each hold 1000 comments"
else
    no "(A14) nodesMatchExactly: the repeated metavariable no longer unifies across the flooded argument lists"
fi
"$BIN" "$TMP/slicew/n1000" --no-cache --slice=target >"$TMP/a_slice2.xml" 2>/dev/null
if [ ! -s "$TMP/a_slice.xml" ]; then
    no "(A8) determinism (empty --slice answer)"
elif cmp -s "$TMP/a_slice.xml" "$TMP/a_slice2.xml"; then
    ok "(A8) determinism (two cold --slice runs byte-identical, $( wc -c <"$TMP/a_slice.xml" | tr -d ' ' ) B)"
else
    no "(A8) determinism (two cold --slice runs differ)"
fi

# ── (B) scaling ──────────────────────────────────────────────────────────────────────────────────────
echo
echo "=== (B) scaling: one node's child list 16000 wide, every child trivial ==="

b_slicew_map="$(   usercpu "$TMP/slicew/n16000"  "$BIN" --top-k=100000 )"
b_slicew_walk="$(  usercpu "$TMP/slicew/n16000"  "$BIN" --slice=target )"
arm "(B1) sliceWalk" "$b_slicew_map" "$b_slicew_walk" 8 0.30 "--slice over a 16000-comment root vs the plain map of the same file"

b_span_map="$(     usercpu "$TMP/span/n16000"    "$BIN" --top-k=100000 )"
b_span_walk="$(    usercpu "$TMP/span/n16000"    "$BIN" --grep=needle_marker )"
arm "(B2) collectSpanTiers" "$b_span_map" "$b_span_walk" 8 0.30 "--grep's span-tier pass over a 16000-comment root vs the plain map"

b_health_off="$(   usercpu "$TMP/health_off/n16000" "$BIN" --top-k=100000 )"
b_health_on="$(    usercpu "$TMP/health/n16000"     "$BIN" --top-k=100000 )"
arm "(B3) measureFileHealth" "$b_health_off" "$b_health_on" 8 0.30 "one recovered token over a 16000-comment root vs the identical flood with none"

b_ffi_off="$(      usercpu "$TMP/ffi_off/n16000" "$BIN" --top-k=100000 )"
b_ffi_on="$(       usercpu "$TMP/ffi/n16000"     "$BIN" --top-k=100000 )"
arm "(B4) ffiVisitNode" "$b_ffi_off" "$b_ffi_on" 8 0.30 "an extern \"C\" block 16000 children wide vs the identical flood outside one"

b_loc_off="$(      usercpu "$TMP/locals/n16000"  "$BIN" --lint )"
b_loc_on="$(       usercpu "$TMP/locals/n16000"  "$BIN" --lint --naming-locals )"
arm "(B5) ln_collectLocalDecls" "$b_loc_off" "$b_loc_on" 8 0.30 "--naming-locals' re-parse walk over a 16000-comment body vs --lint alone"

b_pat_map="$(      usercpu "$TMP/pat/n16000"     "$BIN" --top-k=100000 )"
b_pat_walk="$(     usercpu "$TMP/pat/n16000"     "$BIN" --pattern='{ int a; ... }' )"
arm "(B6) findMatches/matchChildren" "$b_pat_map" "$b_pat_walk" 8 0.30 "--pattern over a 16000-comment root and body vs the plain map"

b_binds_off="$(    usercpu "$TMP/binds_off/n16000" "$BIN" --top-k=100000 )"
b_binds_on="$(     usercpu "$TMP/binds/n16000"     "$BIN" --top-k=100000 )"
arm "(B7) bindsVisitNode" "$b_binds_off" "$b_binds_on" 8 0.30 "one declaration 16000 children wide vs the identical flood beside it in the same body"

b_srd_map="$(      usercpu "$TMP/slicerd/n16000"  "$BIN" --top-k=100000 )"
b_srd_walk="$(     usercpu "$TMP/slicerd/n16000"  "$BIN" --slice=target )"
arm "(B8) SliceRdWalker" "$b_srd_map" "$b_srd_walk" 8 0.30 "--slice's flow walk over a 16000-comment definition body vs the plain map of the same file"

b_spp_map="$(      usercpu "$TMP/slicepp/n16000"  "$BIN" --top-k=100000 )"
b_spp_walk="$(     usercpu "$TMP/slicepp/n16000"  "$BIN" --slice=target )"
arm "(B9) sliceWalkPreproc/preprocC" "$b_spp_map" "$b_spp_walk" 8 0.30 "--slice over a 16000-comment \`#if\` block inside the definition vs the plain map"

b_bases_off="$(    usercpu "$TMP/bases_off/n16000" "$BIN" --top-k=100000 )"
b_bases_on="$(     usercpu "$TMP/bases/n16000"     "$BIN" --top-k=100000 )"
arm "(B10) captureBases" "$b_bases_off" "$b_bases_on" 8 0.30 "a base_class_clause 16000 children wide vs the identical flood outside any clause"

b_args_off="$(     usercpu "$TMP/args_off/n16000"  "$BIN" --top-k=100000 )"
b_args_on="$(      usercpu "$TMP/args/n16000"      "$BIN" --top-k=100000 )"
arm "(B11) ccCallArity" "$b_args_off" "$b_args_on" 8 0.30 "an argument_list 16000 children wide vs the identical flood outside the call"

b_lcap_off="$(     usercpu "$TMP/lcap_off/n16000" "$BIN" --top-k=100000 )"
b_lcap_on="$(      usercpu "$TMP/lcap/n16000"     "$BIN" --top-k=100000 )"
arm "(B12) captureLambdaShadowDecls" "$b_lcap_off" "$b_lcap_on" 8 0.30 "a lambda capture list 16000 children wide vs the identical flood outside it"

# lane W4 — one map-path pair per walk; `pair LABEL fixture control what` times both sides of one shape
pair(){ # $1 = label, $2 = walk fixture, $3 = control fixture, $4 = what the pair is
    local off on
    off="$( usercpu "$TMP/$3/n16000" "$BIN" --top-k=100000 )"
    on="$(  usercpu "$TMP/$2/n16000" "$BIN" --top-k=100000 )"
    arm "$1" "$off" "$on" 8 0.30 "$4"
}
pair "(B13) captureMacroBodyCalls"      macroparams  macroparams_off "a preproc_params list 16000 children wide vs the identical flood outside the #define"
pair "(B14) captureFields/type"         fieldtype    fieldtype_off   "a field's qualified_identifier type 16000 children wide vs the identical flood after the field"
pair "(B15) captureFields/declarator"   fielddecl    fielddecl_off   "a field's reference_declarator 16000 children wide vs the identical flood after the field"
pair "(B16) csharpUsingTarget"          csusing      csusing_off     "a using_directive 16000 children wide vs the identical flood inside a method body"
pair "(B17) phpUseTarget"               phpuse       phpuse_off      "a namespace_use_declaration 16000 children wide vs the identical flood after it"
pair "(B18) jsModuleLoadTarget"         jsrequire    jsrequire_off   "require()'s arguments 16000 children wide vs the identical flood after the statement"
pair "(B19) rubyNamespaceOnly"          rubyns       rubyns_off      "a class body_statement 16000 children wide vs the identical flood after the class"
pair "(B20) rubyMixinTargets"           rubymixin    rubymixin_off   "an include argument_list 16000 children wide vs the identical flood after the include"
pair "(B21) elixirAliasGroup"           exalias      exalias_off     "an alias tuple 16000 children wide vs the identical flood after the alias"
pair "(B22) firstChildOfType"           cppusing     cppusing_off    "a using_declaration 16000 children wide vs the identical flood after it"
pair "(B23) rustItemCarriesTestAttr"    rustattr     rustattr_off    "an attribute_item 16000 children wide vs the identical flood after the item"
pair "(B24) csharpNodeCarriesTestAttr"  csattr       csattr_off      "a method_declaration 16000 children wide vs the identical flood inside its body"
pair "(B25) testMacroBlockPartsOf/args" testmacro    testmacro_off   "a TEST_CASE argument_list 16000 children wide vs the identical flood after the block"
pair "(B26) testMacroBlockPartsOf/;"    testmacrosemi testmacro_off  "16000 comments between TEST_CASE(…) and its block vs the identical flood after the block"
pair "(B27) childTokenAmong"            fieldstatic  fieldstatic_off "a field_declaration 16000 children wide vs the identical flood after the field"
pair "(B28) isPyEnumMemberTarget"       pyenum       pyenum_off      "a superclasses argument_list 16000 children wide vs the identical flood after the class"
pair "(B29) elixirKeywordValue"         exkw         exkw_off        "a def's arguments 16000 children wide vs the identical flood after the def"
pair "(B30) elixirBody"                 excall       excall_off      "a def call 16000 children wide (comments before its do) vs the identical flood after the def"
pair "(B31) ffiVisitNode/pybind"        pybind       pybind_off      "m.def()'s argument_list 16000 children wide vs the identical flood after the call"
pair "(B32) ffiVisitNode/linkage"       externc      externc_off     "a linkage_specification 16000 children wide (before its \"C\") vs the identical flood before it"
pair "(B33) pyMethodsKeyword"           pyroute      pyroute_off     "a route decorator's argument_list 16000 children wide vs the identical flood after the def"
pair "(B34) jsMethodProperty"           jsfetch      jsfetch_off     "fetch()'s options object 16000 children wide vs the identical flood after the call"
pair "(B35) captureTagsFacts/objc-body" objcbody     objcbody_off    "an ObjC method_definition 16000 children wide vs the identical flood after the method"
b_pm_off="$(  usercpu "$TMP/patmeta_off/n16000" "$BIN" --pattern='$X == $X' )"
b_pm_walk="$( usercpu "$TMP/patmeta/n16000"     "$BIN" --pattern='$X == $X' )"
arm "(B36) nodesMatchExactly" "$b_pm_off" "$b_pm_walk" 8 0.30 "--pattern='\$X == \$X' over two 16000-comment argument lists vs the same pattern with the floods outside both lists"

# ── (C) byte-identical against a reference binary ────────────────────────────────────────────────────
echo
echo "=== (C) byte-identical output vs RIPWIRE_REF_BIN ==="
if [ -z "$REF" ]; then
    skip "(C) RIPWIRE_REF_BIN unset — no reference binary to compare against (set it to the pre-change build)"
elif [ ! -x "$REF" ]; then
    no "(C) RIPWIRE_REF_BIN=$REF is not executable"
else
    c_fail=0
    c_seen=0
    cmp_pair(){ # $1 = corpus, rest = flags
        local dir="$1"; shift
        c_seen=$(( c_seen + 1 ))
        "$BIN" "$dir" --no-cache "$@" >"$TMP/c_new" 2>/dev/null
        "$REF" "$dir" --no-cache "$@" >"$TMP/c_ref" 2>/dev/null
        if [ ! -s "$TMP/c_ref" ]; then
            no "(C) reference output of $( basename "$( dirname "$dir" )" )/$( basename "$dir" ) [$*] is empty — the comparison would be vacuous"; c_fail=1
        elif ! cmp -s "$TMP/c_new" "$TMP/c_ref"; then
            no "(C) $( basename "$( dirname "$dir" )" )/$( basename "$dir" ) [$*] differs from the reference binary"; c_fail=1
        fi
    }
    for n in n1000 n16000; do
        for d in slicew slicepp span health health_off ffi ffi_off locals pat binds binds_off slicerd \
                 bases bases_off args args_off lcap lcap_off \
                 macroparams macroparams_off fieldtype fieldtype_off fielddecl fielddecl_off csusing csusing_off \
                 phpuse phpuse_off jsrequire jsrequire_off rubyns rubyns_off rubymixin rubymixin_off exalias exalias_off \
                 cppusing cppusing_off rustattr rustattr_off csattr csattr_off testmacro testmacrosemi testmacro_off \
                 fieldstatic fieldstatic_off pyenum pyenum_off exkw exkw_off excall excall_off pybind pybind_off \
                 externc externc_off pyroute pyroute_off jsfetch jsfetch_off objcbody objcbody_off patmeta patmeta_off; do
            cmp_pair "$TMP/$d/$n" --top-k=100000
        done
        cmp_pair "$TMP/patmeta/$n"     --pattern='$X == $X'
        cmp_pair "$TMP/patmeta_off/$n" --pattern='$X == $X'
        cmp_pair "$TMP/slicew/$n"  --slice=target
        cmp_pair "$TMP/slicepp/$n" --slice=target
        cmp_pair "$TMP/span/$n"    --grep=needle_marker
        cmp_pair "$TMP/health/$n"  --grep=pad
        cmp_pair "$TMP/locals/$n"  --lint --naming-locals
        cmp_pair "$TMP/pat/$n"     --pattern='{ int a; ... }'
        cmp_pair "$TMP/binds/$n"    --callers='big.cpp::Foo::m'
        cmp_pair "$TMP/binds/$n"    --callers='big.cpp::Bar::m'
        cmp_pair "$TMP/binds_off/$n" --callers='big.cpp::Foo::m'
        cmp_pair "$TMP/slicerd/$n"  --slice=target
        cmp_pair "$TMP/slicerd/$n"  --slice=target:acc
        cmp_pair "$TMP/slicerd/$n"  --slice=target:acc --slice-flow=both
        cmp_pair "$TMP/slicepp/$n"  --slice=target:acc --slice-flow=both
    done
    [ "$c_fail" = 0 ] && ok "(C1) $c_seen generated fixture x verb pairs are byte-identical to the reference"
    c_fail=0
    c_seen=0
    for d in "$ROOT/test/cfix" "$ROOT/test/cppqualfix" "$ROOT/test/preproccondfix" "$ROOT/test/ffifix" "$ROOT/test/pyimportprecisefix" "$ROOT/test/sliceflowsensfix" "$ROOT/test/lintfix"; do
        [ -d "$d" ] || continue
        cmp_pair "$d" --top-k=100000
        cmp_pair "$d" --grep=int
        cmp_pair "$d" --lint --naming-locals
    done
    if [ "$c_seen" = 0 ]; then
        no "(C2) no committed fixture tree found — the arm would have been vacuous"
    elif [ "$c_fail" = 0 ]; then
        ok "(C2) $c_seen committed fixture x verb pairs are byte-identical to the reference"
    fi
fi

# ── (D) mutation: every verdict shape above is shown able to fail ────────────────────────────────────
echo
echo "=== (D) MUTATION — the verdict and row readers are shown able to fail ==="
case "$( verdict 0.09 1.22 8 0.30 )" in
    quad\ *) ok "(D) the measured pre-change ffiVisitNode pair (0.09s vs 1.22s) IS called quad";;
    *)       no "(D) the isolation verdict cannot see the pathology it was written against";;
esac
case "$( verdict 0.02 2.43 8 0.30 )" in
    quad\ *) ok "(D) the measured pre-change findMatches pair (0.02s vs 2.43s) IS called quad";;
    *)       no "(D) the isolation verdict cannot see the largest pathology it was written against";;
esac
case "$( verdict 0.11 7.71 8 0.30 )" in
    quad\ *) ok "(D) the measured pre-change bindsVisitNode pair (0.11s vs 7.71s) IS called quad";;
    *)       no "(D) the isolation verdict cannot see the bindsVisitNode pathology";;
esac
case "$( verdict 0.03 2.52 8 0.30 )" in
    quad\ *) ok "(D) the measured pre-change SliceRdWalker pair (0.03s vs 2.52s) IS called quad";;
    *)       no "(D) the isolation verdict cannot see the SliceRdWalker pathology";;
esac
case "$( verdict 0.03 2.57 8 0.30 )" in
    quad\ *) ok "(D) the measured pre-change elixirAliasGroup pair (0.03s vs 2.57s) IS called quad";;
    *)       no "(D) the isolation verdict cannot see the elixirAliasGroup pathology";;
esac
case "$( verdict 0.09 1.13 8 0.30 )" in
    quad\ *) ok "(D) the measured pre-change linkage-string pair (0.09s vs 1.13s, the smallest W4 ratio) IS called quad";;
    *)       no "(D) the isolation verdict cannot see the smallest W4 pathology";;
esac
case "$( verdict 0.10 0.70 8 0.30 )" in
    linear\ *) ok "(D) a 7x pair (0.10s vs 0.70s) IS called linear, not quad";;
    *)         no "(D) the isolation verdict calls a linear pair quadratic";;
esac
case "$( verdict 0.01 0.20 8 0.30 )" in
    fast) ok "(D) a sub-0.30s walk arm short-circuits to fast";;
    *)    no "(D) the absolute short-circuit does not fire";;
esac
printf '<lint><f rule="naming-underscore" p="a:1" in="g">a__b</f><f rule="naming-short" p="a:2" in="g">q</f></lint>' >"$TMP/m.xml"
if [ "$( count_rows "$TMP/m.xml" '<f rule="naming-underscore"' )" = 1 ] && [ "$( count_rows "$TMP/m.xml" '<f rule="nope"' )" = 0 ]; then
    ok "(D) the row reader counts rows that are present and invents none that are absent"
else
    no "(D) the row reader miscounts"
fi

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
