#!/usr/bin/env python3
"""
Unit tests for bench/locbench/crossctx_sites.py — the mechanical stage of the cross-context external-rate
pre-registration (docs/research/cross-context-external-rate.md, 2026-09-23; amendment 1 the same day).

SYNTHETIC ONLY. Every patch and every "pre-fix file" below is hand-written in this file. Nothing reads
Loc-Bench data, invokes git or the ripwire binary, or touches the network. The pre-registration requires
that no row be scored before the recipe is committed; these tests exist to prove the recipe's MECHANICS
(diff parsing, path classes, line→definition mapping, the legacy fingerprint rule, the sampler and its
enlargement, kappa, Wilson, the post-stratified estimate and the decision table) on data invented for the
purpose — and to pin the frozen constants so a later edit fails a test instead of moving silently.

Pure Python, no pytest dependency — same convention as test_compare_gate.py. Runs as a plain script:

    python3 bench/locbench/test_crossctx_sites.py
"""
import os, sys

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
import crossctx_sites as X

# ── a hand-written pre-fix module ─────────────────────────────────────────────────────────────────────────
BASE = """\
import os

LIMIT = 3

def helper(x):
    return x + 1

class Widget:
    kind = "w"

    @property
    def size(self):
        def inner(v):
            return v * 2
        return inner(self._n)

    def grow(self, n):
        self._n = n

def tail():
    return LIMIT
"""
# line numbers: 1 import, 3 LIMIT, 5-6 helper, 8 class, 9 kind, 11 @property, 12-15 size (inner 13-14), 17-18 grow, 20-21 tail

COND = """\
try:
    from fast import impl
except ImportError:
    def impl(x):
        return x

if TYPE_CHECKING:
    class Proto:
        def run(self):
            pass

with ctx():
    def under_with():
        pass
"""

def read_base( files ):
    return lambda p: files.get( p )

def diff( path, hunks, new_path=None, rename=False ):
    out = [ "diff --git a/%s b/%s" % ( path, new_path or path ) ]
    if rename:
        out += [ "similarity index 90%", "rename from %s" % path, "rename to %s" % new_path ]
    out += [ "--- a/%s" % path, "+++ b/%s" % ( new_path or path ) ]
    for hdr, lines in hunks:
        out.append( hdr ); out.extend( lines )
    return "\n".join( out ) + "\n"

# ── legacy fingerprint rule ───────────────────────────────────────────────────────────────────────────────
def test_legacy_shape_counts_tests_as_source_and_hunks_in_first_file():
    one = diff( "pkg/a.py", [ ( "@@ -5,2 +5,2 @@", [ " def helper(x):", "-    return x + 1", "+    return x + 2" ] ) ] )
    assert X.legacy_shape( one ) == "LOCAL"
    two_hunks = diff( "pkg/a.py", [ ( "@@ -5,2 +5,2 @@", [ "-a", "+b" ] ), ( "@@ -17,2 +17,2 @@", [ "-c", "+d" ] ) ] )
    assert X.legacy_shape( two_hunks ) == "SPREAD-IN-FILE"
    with_test = one + diff( "tests/test_a.py", [ ( "@@ -1,1 +1,2 @@", [ " x", "+y" ] ) ] )
    assert X.legacy_shape( with_test ) == "CROSS", "the legacy rule does NOT exclude tests — that is the point of reproducing it"
    assert X.legacy_shape( diff( "docs/x.rst", [ ( "@@ -1,1 +1,1 @@", [ "-a", "+b" ] ) ] ) ) is None

def test_fingerprint_passes_only_on_the_pinned_counts():
    rows = [ dict( patch=diff( "a.py", [ ( "@@ -1,1 +1,1 @@", [ "-a", "+b" ] ) ] ) ) ]
    counts, ok = X.fingerprint( rows )
    assert counts == { "CROSS": 0, "SPREAD-IN-FILE": 0, "LOCAL": 1 } and not ok
    assert X.FROZEN[ "fingerprint" ] == { "CROSS": 94, "SPREAD-IN-FILE": 254, "LOCAL": 212 }

# ── M1 parse ──────────────────────────────────────────────────────────────────────────────────────────────
def test_parse_patch_hunks_rename_and_dev_null():
    p = diff( "pkg/a.py", [ ( "@@ -5,2 +5,3 @@ def helper", [ " def helper(x):", "-    return x + 1", "+    y = 1", "+    return x + y" ] ) ] ) \
      + diff( "pkg/old.py", [], new_path="pkg/new.py", rename=True )
    fds = X.parse_patch( p )
    assert [ f.old_path for f in fds ] == [ "pkg/a.py", "pkg/old.py" ]
    assert fds[ 0 ].hunks[ 0 ].old_start == 5 and fds[ 0 ].hunks[ 0 ].old_len == 2 and len( fds[ 0 ].hunks[ 0 ].lines ) == 4
    assert fds[ 1 ].is_rename and fds[ 1 ].new_path == "pkg/new.py" and fds[ 1 ].hunks == []
    newf = "diff --git a/pkg/c.py b/pkg/c.py\nnew file mode 100644\n--- /dev/null\n+++ b/pkg/c.py\n@@ -0,0 +1,2 @@\n+def z():\n+    pass\n"
    fd = X.parse_patch( newf )[ 0 ]
    assert fd.old_path == "/dev/null" and X.file_identity( fd ) == "pkg/c.py"

# ── M2 classify ───────────────────────────────────────────────────────────────────────────────────────────
def test_classify_path_first_match_wins_and_doc_rules_spare_code():
    assert X.classify_path( "tests/unit/test_x.py" ) == "TEST"
    assert X.classify_path( "pkg/conftest.py" ) == "TEST"
    assert X.classify_path( "pkg/x_test.py" ) == "TEST"
    assert X.classify_path( "django/test/client.py" ) == "TEST", "known limit of the directory rule — counted via test_rule_basis"
    assert X.test_rule_basis( "django/test/client.py" ) == "dir" and X.test_rule_basis( "tests/test_x.py" ) == "basename"
    assert X.test_rule_basis( "pkg/core.py" ) is None
    assert X.classify_path( "docs/index.rst" ) == "DOC"
    assert X.classify_path( "CHANGELOG.rst" ) == "DOC"
    assert X.classify_path( "changelog.d/123.bugfix" ) == "DOC"
    assert X.classify_path( "prompt_toolkit/history.py" ) == "SOURCE", "DOC basename rule must not fire on code"
    assert X.classify_path( "app/news.py" ) == "SOURCE" and X.classify_path( "pkg/changes.py" ) == "SOURCE"
    assert X.classify_path( "docs/conf.py" ) == "SOURCE", "DOC directory rule must not fire on code"
    assert X.classify_path( "app/migrations/0004_auto.py" ) == "GENERATED"
    assert X.classify_path( "pkg/_version.py" ) == "GENERATED"
    assert X.classify_path( "pkg/gen.py", [ "# This file is auto-generated by foo. DO NOT EDIT", "", "" ] ) == "GENERATED"
    assert X.classify_path( "pkg/gen.py", [ '"""Support for generated columns."""', "", "" ] ) == "SOURCE", "a docstring is not a generator marker"
    assert X.classify_path( "pkg/gen.py", [ "import x", "y = 1", "z = 2", "# generated by foo" ] ) == "SOURCE", "only the first three lines"
    assert X.classify_path( "pkg/core.py" ) == "SOURCE"
    assert X.classify_path( "pkg/core.pyi" ) == "SOURCE"
    assert X.classify_path( "ext/fast.c" ) == "OTHERLANG"
    assert X.classify_path( "setup.cfg" ) == "NONSOURCE"
    assert X.classify_path( "tests/data/fixture.py" ) == "TEST", "tests/ wins over .py"

# ── M3 changed lines and insertion anchors ────────────────────────────────────────────────────────────────
def test_changed_old_lines_and_insertion_anchor():
    h = X.Hunk( 5, 3, [ " a", "-b", " c", "-d" ] )
    assert X.changed_old_lines( h ) == { 6, 8 } and X.insertion_anchor( h ) == ( None, None )
    ins = X.Hunk( 10, 2, [ " a", " b", "+c", "+d" ] )           # insertion after old line 11, not a definition
    assert X.changed_old_lines( ins ) == set() and X.insertion_anchor( ins ) == ( 11, None )
    top = X.Hunk( 1, 2, [ "+c", " a", " b" ] )                  # insertion at the top of a non-empty file
    assert X.insertion_anchor( top ) == ( 1, None )
    empty = X.Hunk( 0, 0, [ "+c", "+d" ] )                      # new content in an empty file
    assert X.insertion_anchor( empty ) == ( 0, None )
    newdef = X.Hunk( 18, 1, [ "         self._n = n", "+", "+    def shrink(self):", "+        self._n = 0" ] )
    assert X.insertion_anchor( newdef ) == ( 18, 4 ), "first non-blank + line begins a def at indent 4"
    deco = X.Hunk( 6, 1, [ "     return x + 1", "+", "+@wraps", "+def extra():", "+    pass" ] )
    assert X.insertion_anchor( deco ) == ( 6, 0 ), "a decorator begins the definition at indent 0"

# ── M4 spans ──────────────────────────────────────────────────────────────────────────────────────────────
def test_python_definition_spans_collapse_nested_and_include_decorators():
    spans = { s.qualname: ( s.start, s.end, s.col ) for s in X.python_definition_spans( BASE ) }
    assert spans[ "helper" ] == ( 5, 6, 0 )
    assert spans[ "Widget" ][ 0 ] == 8 and spans[ "Widget" ][ 2 ] == 0
    assert spans[ "Widget.size" ] == ( 11, 15, 4 ), "starts at the decorator, ends after the nested def's use"
    assert "Widget.size.inner" not in spans and "inner" not in spans
    assert spans[ "Widget.grow" ] == ( 17, 18, 4 )
    assert spans[ "tail" ] == ( 20, 21, 0 )
    sp = X.python_definition_spans( BASE )
    assert X.site_for_line( sp, 13 ) == "Widget.size"   # inside the nested def
    assert X.site_for_line( sp, 9 ) == "Widget"         # class attribute
    assert X.site_for_line( sp, 3 ) == "<module>"

def test_definitions_under_try_if_with_are_found():
    spans = { s.qualname for s in X.python_definition_spans( COND ) }
    assert spans == { "impl", "Proto", "Proto.run", "under_with" }, spans
    sp = X.python_definition_spans( COND )
    assert X.site_for_line( sp, 5 ) == "impl" and X.site_for_line( sp, 10 ) == "Proto.run" and X.site_for_line( sp, 14 ) == "under_with"

def test_site_for_new_definition_is_by_container_not_hunk_placement():
    sp = X.python_definition_spans( BASE )
    assert X.site_for_new_definition( sp, 18, 4 ) == "Widget", "a new method after grow's last line belongs to the class"
    assert X.site_for_new_definition( sp, 16, 4 ) == "Widget", "a new method at the blank line between methods"
    assert X.site_for_new_definition( sp, 18, 8 ) == "Widget.grow", "a nested def inside grow"
    assert X.site_for_new_definition( sp, 6, 0 ) == "<module>", "a new top-level def after helper is NOT helper"
    assert X.site_for_new_definition( sp, 7, 0 ) == "<module>", "...and the same insertion slid one line agrees"
    assert X.site_for_new_definition( sp, 19, 4 ) == "<module>", "a method-indented def after the class has no container"
    assert X.site_for_new_definition( sp, 0, 4 ) == "<module>"

# ── M5–M7 sites and class ─────────────────────────────────────────────────────────────────────────────────
FILES = { "pkg/a.py": BASE, "pkg/b.py": BASE }

def test_two_hunks_in_one_function_are_one_site():
    p = diff( "pkg/a.py", [ ( "@@ -12,1 +12,1 @@", [ "-    def size(self):", "+    def size(self):  # x" ] ),
                            ( "@@ -15,1 +15,1 @@", [ "-        return inner(self._n)", "+        return inner(self._n) + 0" ] ) ] )
    r = X.sites_for_row( p, read_base( FILES ) )
    assert r.sites == { ( "pkg/a.py", "Widget.size" ) } and r.mclass == "ONE-SITE" and r.mclass_collapsed == "ONE-SITE"

def test_two_functions_one_file_and_two_files():
    p = diff( "pkg/a.py", [ ( "@@ -6,1 +6,1 @@", [ "-    return x + 1", "+    return x + 2" ] ),
                            ( "@@ -21,1 +21,1 @@", [ "-    return LIMIT", "+    return LIMIT - 1" ] ) ] )
    r = X.sites_for_row( p, read_base( FILES ) )
    assert r.sites == { ( "pkg/a.py", "helper" ), ( "pkg/a.py", "tail" ) } and r.mclass == "MULTI-SITE-ONE-FILE"
    p2 = p + diff( "pkg/b.py", [ ( "@@ -3,1 +3,1 @@", [ "-LIMIT = 3", "+LIMIT = 4" ] ) ] )
    r2 = X.sites_for_row( p2, read_base( FILES ) )
    assert ( "pkg/b.py", "<module>" ) in r2.sites and r2.mclass == "MULTI-FILE"

def test_tests_docs_generated_are_not_sites_and_excluded_buckets_are_distinct():
    fix = diff( "pkg/a.py", [ ( "@@ -6,1 +6,1 @@", [ "-    return x + 1", "+    return x + 2" ] ) ] )
    extras = diff( "tests/test_a.py", [ ( "@@ -1,1 +1,2 @@", [ " x", "+y" ] ) ] ) \
           + diff( "docs/guide.rst", [ ( "@@ -1,1 +1,1 @@", [ "-a", "+b" ] ) ] ) \
           + diff( "app/migrations/0009_x.py", [ ( "@@ -1,1 +1,1 @@", [ "-a", "+b" ] ) ] )
    r = X.sites_for_row( fix + extras, read_base( FILES ) )
    assert r.sites == { ( "pkg/a.py", "helper" ) } and r.mclass == "ONE-SITE"
    assert r.buckets[ "TEST" ] == 1 and r.buckets[ "DOC" ] == 1 and r.buckets[ "GENERATED" ] == 1
    only_test = X.sites_for_row( diff( "tests/test_a.py", [ ( "@@ -1,1 +1,2 @@", [ " x", "+y" ] ) ] ), read_base( FILES ) )
    assert only_test.mclass == "TEST-ONLY" and not only_test.test_dir_only, "basename rule fired"
    dir_only = X.sites_for_row( diff( "django/test/client.py", [ ( "@@ -1,1 +1,2 @@", [ " x", "+y" ] ) ] ), read_base( FILES ) )
    assert dir_only.mclass == "TEST-ONLY" and dir_only.test_dir_only and "test_dir_only" in dir_only.flags
    only_doc = X.sites_for_row( diff( "README.md", [ ( "@@ -1,1 +1,1 @@", [ "-a", "+b" ] ) ] ), read_base( FILES ) )
    assert only_doc.mclass == "NON-CODE"
    newf = "diff --git a/pkg/c.py b/pkg/c.py\nnew file mode 100644\n--- /dev/null\n+++ b/pkg/c.py\n@@ -0,0 +1,2 @@\n+def z():\n+    pass\n"
    r3 = X.sites_for_row( newf, read_base( FILES ) )
    assert r3.sites == set() and "new_file" in r3.flags and r3.mclass == "NEW-FILE-ONLY", "not NON-CODE"
    gone = X.sites_for_row( diff( "pkg/missing.py", [ ( "@@ -1,1 +1,1 @@", [ "-a", "+b" ] ) ] ), read_base( FILES ) )
    assert gone.mclass == "EXCLUDED-UNREADABLE" and "unreadable" in gone.flags, "a pre-fix file that could not be read is never NON-CODE"

def test_pure_insertion_of_a_definition_lands_on_its_container():
    ins = diff( "pkg/a.py", [ ( "@@ -18,1 +18,4 @@", [ "         self._n = n", "+", "+    def shrink(self):", "+        self._n = 0" ] ) ] )
    r = X.sites_for_row( ins, read_base( FILES ) )
    assert r.sites == { ( "pkg/a.py", "Widget" ) }, "a new method lands on its class, not on the preceding method"
    ins2 = diff( "pkg/a.py", [ ( "@@ -16,1 +16,3 @@", [ "", "+    def extra(self):", "+        return 0" ] ) ] )
    assert X.sites_for_row( ins2, read_base( FILES ) ).sites == { ( "pkg/a.py", "Widget" ) }
    top1 = diff( "pkg/a.py", [ ( "@@ -6,1 +6,4 @@", [ "     return x + 1", "+", "+def extra():", "+    return 0" ] ) ] )
    top2 = diff( "pkg/a.py", [ ( "@@ -7,1 +7,4 @@", [ "", "+def extra():", "+    return 0", "+" ] ) ] )
    assert X.sites_for_row( top1, read_base( FILES ) ).sites == { ( "pkg/a.py", "<module>" ) }, "a new top-level def is <module>..."
    assert X.sites_for_row( top2, read_base( FILES ) ).sites == { ( "pkg/a.py", "<module>" ) }, "...whichever way git slid the hunk"
    body_ins = diff( "pkg/a.py", [ ( "@@ -18,1 +18,2 @@", [ "         self._n = n", "+        self._dirty = True" ] ) ] )
    assert X.sites_for_row( body_ins, read_base( FILES ) ).sites == { ( "pkg/a.py", "Widget.grow" ) }, "a non-definition insertion keeps the preceding-line anchor"

def test_otherlang_unparsed_rename_only_flags():
    c = diff( "ext/fast.c", [ ( "@@ -1,1 +1,1 @@", [ "-int a;", "+int b;" ] ) ] )
    r = X.sites_for_row( c, read_base( { "ext/fast.c": "int a;\n" } ) )
    assert r.sites == { ( "ext/fast.c", "<file>" ) } and "otherlang" in r.flags
    bad = diff( "pkg/bad.py", [ ( "@@ -1,1 +1,1 @@", [ "-def (:", "+def f():" ] ) ] )
    r2 = X.sites_for_row( bad, read_base( { "pkg/bad.py": "def (:\n" } ) )
    assert r2.sites == { ( "pkg/bad.py", "<unparsed>" ) } and "unparsed" in r2.flags
    ren = diff( "pkg/old.py", [], new_path="pkg/new.py", rename=True )
    r3 = X.sites_for_row( ren, read_base( FILES ) )
    assert r3.sites == set() and "rename_only" in r3.flags

def test_move_detection_and_collapse():
    # Widget.size occupies BASE lines 11-15 (decorator included): five non-blank lines, one site.
    body = [ "-    @property", "-    def size(self):", "-        def inner(v):", "-            return v * 2", "-        return inner(self._n)" ]
    plus = [ l.replace( "-", "+", 1 ) for l in body ]
    p = diff( "pkg/a.py", [ ( "@@ -11,5 +11,0 @@", body ) ] ) + diff( "pkg/b.py", [ ( "@@ -16,0 +17,5 @@", plus ) ] )
    assert X.detect_moves( X.parse_patch( p ) ) == { ( "pkg/a.py", 0 ) }, "only the SOURCE hunk is returned"
    same_file = diff( "pkg/a.py", [ ( "@@ -11,5 +11,0 @@", body ), ( "@@ -16,0 +17,5 @@", plus ) ] )
    assert not X.detect_moves( X.parse_patch( same_file ) ), "a move inside one file is not flagged"
    renamed = diff( "pkg/a.py", [ ( "@@ -11,5 +11,0 @@", body ), ( "@@ -16,0 +17,5 @@", plus ) ], new_path="pkg/a2.py", rename=True )
    assert not X.detect_moves( X.parse_patch( renamed ) ), "a renamed file moving a block within itself is the SAME file"
    short = diff( "pkg/a.py", [ ( "@@ -11,2 +11,0 @@", body[ :2 ] ) ] ) + diff( "pkg/b.py", [ ( "@@ -16,0 +17,2 @@", plus[ :2 ] ) ] )
    assert not X.detect_moves( X.parse_patch( short ) )
    defeated = diff( "pkg/a.py", [ ( "@@ -11,5 +11,0 @@", body ) ] ) + diff( "pkg/b.py", [ ( "@@ -16,0 +17,6 @@", [ "+    extra = 1" ] + plus ) ] )
    assert not X.detect_moves( X.parse_patch( defeated ) ), "whole-hunk equality: one extra line defeats it (stated in M6)"
    r = X.sites_for_row( p, read_base( FILES ) )
    assert "move" in r.flags and r.sites == { ( "pkg/a.py", "Widget.size" ), ( "pkg/b.py", "Widget" ) } and r.mclass == "MULTI-FILE", \
        "the destination hunk begins a decorated method at indent 4 inside b's class body, so its site is b's Widget (M3)"
    assert r.collapsed_sites == { ( "pkg/b.py", "Widget" ) } and r.mclass_collapsed == "ONE-SITE", "moves collapsed = drop the source hunk's sites"

# ── M8 ────────────────────────────────────────────────────────────────────────────────────────────────────
def test_gold_recall_over_source_gold_only():
    sites = { ( "pkg/a.py", "Widget.size" ), ( "pkg/a.py", "<module>" ) }
    assert X.spell( sites ) == { "pkg/a.py:Widget.size", "pkg/a.py:<module>" }
    assert X.gold_recall( sites, [ "pkg/a.py:Widget.size", "pkg/a.py:tail" ] ) == 0.5
    assert X.gold_recall( sites, [ "pkg/a.py:Widget.size", "tests/test_a.py:test_it" ] ) == 1.0, "test-file gold is not SOURCE gold"
    assert X.gold_recall( sites, [ "tests/test_a.py:test_it" ] ) is None
    assert X.gold_recall( sites, [] ) is None
    assert X.jaccard( { "a", "b" }, { "b", "c" } ) == 1 / 3.0 and X.jaccard( set(), set() ) == 1.0

# ── R1 sampler, enlargement, pilot ────────────────────────────────────────────────────────────────────────
def test_stratified_systematic_sample_is_deterministic_and_floored():
    strata = { "ONE-SITE": [ "r%03d" % i for i in range( 250 ) ], "MULTI-FILE": [ "m%02d" % i for i in range( 30 ) ],
               "MULTI-SITE-ONE-FILE": [ "s%02d" % i for i in range( 80 ) ] }
    s = X.stratified_systematic_sample( strata )
    assert len( s[ "ONE-SITE" ] ) == 42 and s[ "ONE-SITE" ][ :2 ] == [ "r000", "r006" ], "k = 250 // 40 = 6"
    assert s[ "MULTI-FILE" ] == sorted( strata[ "MULTI-FILE" ] ), "a stratum below the floor is taken whole"
    assert len( s[ "MULTI-SITE-ONE-FILE" ] ) == 40 and s[ "MULTI-SITE-ONE-FILE" ][ :2 ] == [ "s00", "s02" ], "80 → k=2 → 40"
    assert len( X.stratified_systematic_sample( { "x": [ "%02d" % i for i in range( 79 ) ] } )[ "x" ] ) == 79, "79 is taken whole"
    assert X.stratified_systematic_sample( { "x": list( reversed( strata[ "ONE-SITE" ] ) ) } )[ "x" ] == s[ "ONE-SITE" ], "order-independent"

def test_enlargement_is_one_offset_pass_and_a_union():
    strata = { "ONE-SITE": [ "r%03d" % i for i in range( 250 ) ], "MULTI-FILE": [ "m%02d" % i for i in range( 30 ) ] }
    first = X.stratified_systematic_sample( strata )
    big = X.enlargement_sample( strata, first )
    assert big[ "ONE-SITE" ][ :4 ] == [ "r000", "r003", "r006", "r009" ], "offset k//2 = 3 interleaves the first pass"
    assert len( big[ "ONE-SITE" ] ) == 84 and set( first[ "ONE-SITE" ] ) <= set( big[ "ONE-SITE" ] )
    assert big[ "MULTI-FILE" ] == first[ "MULTI-FILE" ], "a stratum taken whole gains nothing"
    assert X.enlargement_permitted( "CI [0.400, 0.620] straddles the anchors", 0 )
    assert not X.enlargement_permitted( "CI [0.400, 0.620] straddles the anchors", 1 ), "once only"
    assert not X.enlargement_permitted( "binary kappa 0.50 below 0.60 (R7)", 0 ), "never on a reliability failure"

def test_pilot_rows_are_the_first_unsampled_in_id_order():
    ids = [ "r%03d" % i for i in range( 30 ) ]
    sample = [ "r000", "r003", "r006" ]
    assert X.pilot_rows( ids, sample, 4 ) == [ "r001", "r002", "r004", "r005" ]
    assert len( X.pilot_rows( ids, sample ) ) == X.FROZEN[ "pilot_rows" ] == 10

# ── R6/R7 labels and kappa ────────────────────────────────────────────────────────────────────────────────
def test_row_label_three_way_and_kappa():
    assert X.row_label( "CROSS", "CROSS" ) == "CROSS" and X.row_label( "LOCAL", "LOCAL" ) == "LOCAL"
    assert X.row_label( "CROSS", "LOCAL" ) == ( "UNTAGGED", "DISAGREE" )
    assert X.row_label( "CROSS", "NOT-A-DEFECT" ) == ( "UNTAGGED", "NOT-A-DEFECT" )
    assert X.row_label( "UNDECIDED", "LOCAL" ) == ( "UNTAGGED", "UNDECIDED" )
    assert X.three_way( "CROSS" ) == "CROSS" and X.three_way( "UNDECIDED" ) == "other" and X.three_way( "NOT-A-DEFECT" ) == "other"
    a = [ "CROSS", "LOCAL", "CROSS", "LOCAL" ]
    assert X.cohen_kappa( a, a ) == 1.0
    assert abs( X.cohen_kappa( a, [ "CROSS", "CROSS", "LOCAL", "LOCAL" ] ) ) < 1e-12, "chance agreement is 0"
    assert X.cohen_kappa( [ "CROSS" ] * 4, [ "CROSS" ] * 4 ) == 1.0
    mixed = [ "CROSS", ( "UNTAGGED", "DISAGREE" ), "LOCAL" ]
    assert X.cohen_kappa( mixed, mixed ) == 1.0, "mixed str/tuple labels must not raise"
    assert X.kappa_verdict( 0.61 ) == "quotable" and X.kappa_verdict( 0.5 ) == "moderate" and X.kappa_verdict( 0.39 ) == "failed"

# ── §7 estimators ─────────────────────────────────────────────────────────────────────────────────────────
def test_wilson_pins_both_internal_comparators():
    lo, hi = X.wilson( 149, 169 )
    assert round( lo, 3 ) == 0.824 and round( hi, 3 ) == 0.922, ( lo, hi )
    c = X.internal_comparator()
    assert c[ "rows" ] == 377 and c[ "usable" ] == 292 and c[ "tagged" ] == 169 and c[ "untagged" ] == 123
    assert c[ "cross" ] == 149 and c[ "local" ] == 20 and round( c[ "rate" ], 3 ) == 0.882
    cc = X.internal_comparator( X.INTERNAL_CHAIN_CODE_ONLY )
    assert ( cc[ "usable" ], cc[ "tagged" ], cc[ "untagged" ], cc[ "cross" ], cc[ "local" ] ) == ( 209, 124, 85, 109, 15 )
    assert cc[ "usable" ] == cc[ "tagged" ] + cc[ "untagged" ] and cc[ "tagged" ] == cc[ "cross" ] + cc[ "local" ]
    assert round( cc[ "rate" ], 3 ) == 0.879 and round( cc[ "lo" ], 3 ) == 0.810 and round( cc[ "hi" ], 3 ) == 0.925, cc
    assert X.wilson( 0, 0 ) == ( 0.0, 0.0 )

def test_post_stratified_estimate_weights_by_manifest_and_is_reproducible():
    strata = { "ONE-SITE": dict( N=300, labels=[ "CROSS" ] * 10 + [ "LOCAL" ] * 30 ),
               "MULTI-FILE": dict( N=100, labels=[ "CROSS" ] * 30 + [ "LOCAL" ] * 10 ),
               "MULTI-SITE-ONE-FILE": dict( N=50, labels=[] ) }
    e = X.post_stratified_estimate( strata, resamples=200 )
    assert abs( e[ "point" ] - ( 0.75 * 0.25 + 0.25 * 0.75 ) ) < 1e-12, "weights from N, rates from the sample; the empty stratum is dropped and named"
    assert e[ "dropped" ] == [ "MULTI-SITE-ONE-FILE" ]
    assert e[ "lo" ] <= e[ "point" ] <= e[ "hi" ]
    assert X.post_stratified_estimate( strata, resamples=200 ) == e, "same seed, same interval"
    allc = X.post_stratified_estimate( { "s": dict( N=10, labels=[ "CROSS" ] * 5 ) }, resamples=50 )
    assert allc[ "point" ] == 1.0 and allc[ "lo" ] == 1.0 and allc[ "hi" ] == 1.0

def test_power_statement_at_the_planned_n_is_as_registered():
    # §9's power statement: with ~88 tagged rows split 3 ways, a true 0.62 and a true 0.70 both return
    # INDETERMINATE, and STARK/THIN need points of roughly <= 0.39 / >= 0.72. Synthetic labels, fixed seed.
    def strata_at( p, n=90 ):
        per = n // 3
        c = int( round( p * per ) )
        return { s: dict( N=100, labels=[ "CROSS" ] * c + [ "LOCAL" ] * ( per - c ) ) for s in X.SCOREABLE }
    for p in ( 0.45, 0.62, 0.67 ):
        e = X.post_stratified_estimate( strata_at( p ), resamples=400 )
        assert X.decision( e[ "lo" ], e[ "hi" ], 0.8, 0.2 )[ 0 ] == "INDETERMINATE", ( p, e )
        assert ( e[ "hi" ] - e[ "lo" ] ) > 0.15, "interval width at n≈88 is about ±0.10"
    e70 = X.post_stratified_estimate( strata_at( 0.70 ), resamples=400 )
    assert 0.58 < e70[ "lo" ] < 0.63, "0.70 sits AT the THIN edge at this n: the effective THIN bar is ~0.70-0.72, as §9 states"
    e = X.post_stratified_estimate( strata_at( 0.35 ), resamples=400 )
    assert X.decision( e[ "lo" ], e[ "hi" ], 0.8, 0.2 )[ 0 ] == "STARK"
    e = X.post_stratified_estimate( strata_at( 0.76 ), resamples=400 )
    assert X.decision( e[ "lo" ], e[ "hi" ], 0.8, 0.2 )[ 0 ] == "THIN"

# ── §9 decision ───────────────────────────────────────────────────────────────────────────────────────────
def test_decision_table_uses_the_frozen_anchors():
    assert X.decision( 0.30, 0.50, 0.7, 0.3 )[ 0 ] == "STARK"
    assert X.decision( 0.30, 0.51, 0.7, 0.3 )[ 0 ] == "INDETERMINATE"
    assert X.decision( 0.60, 0.80, 0.7, 0.3 )[ 0 ] == "THIN"
    assert X.decision( 0.59, 0.80, 0.7, 0.3 )[ 0 ] == "INDETERMINATE"
    assert X.decision( 0.30, 0.45, 0.59, 0.3 ) == ( "INDETERMINATE", "binary kappa 0.59 below 0.60 (R7)" )
    assert X.decision( 0.30, 0.45, 0.9, 0.51 )[ 0 ] == "INDETERMINATE"
    assert X.decision( 0.30, 0.45, 0.9, 0.3, fingerprint_ok=False ) == ( "INDETERMINATE", "fingerprint failed (§4.4)" )
    assert X.decision( 0.30, 0.45, 0.9, 0.3, m8_ok=False )[ 0 ] == "INDETERMINATE"
    assert X.decision( None, None, 0.9, 0.3 )[ 0 ] == "INDETERMINATE"

def test_frozen_constants_are_the_registered_ones():
    F = X.FROZEN
    assert F[ "rows_json_sha256" ] == "5bbcea4bff11396f38f8aca3e64d697a8ea1da2bc54d705da7f6e34886804c97"
    assert ( F[ "per_stratum_floor" ], F[ "kappa_floor" ], F[ "kappa_moderate" ] ) == ( 40, 0.60, 0.40 )
    assert ( F[ "stark_hi" ], F[ "thin_lo" ], F[ "untagged_ceiling" ] ) == ( 0.50, 0.60, 0.50 )
    assert ( F[ "bootstrap_seed" ], F[ "bootstrap_resamples" ], F[ "move_min_lines" ] ) == ( 20260923, 2000, 3 )
    assert ( F[ "m8_recall_floor" ], F[ "unavailable_floor" ] ) == ( 0.70, 0.05 )
    assert ( F[ "enlargement_steps" ], F[ "enlargement_offset" ], F[ "pilot_rows" ] ) == ( 1, "k//2", 10 )
    assert ( F[ "rater_tool_budget" ], F[ "rater_output_tokens" ] ) == ( 25, 1500 )
    assert F[ "rater_families" ] == ( "anthropic-claude", "openai-gpt" ) and len( set( F[ "rater_families" ] ) ) == 2

def test_manifest_line_and_hash():
    line = X.manifest_line( "id", "o/r", "abc", "ONE-SITE", 1, { "move", "otherlang" }, "ONE-SITE" )
    assert line.split( "\t" ) == [ "id", "o/r", "abc", "ONE-SITE", "1", "move,otherlang", "ONE-SITE" ]
    assert X.manifest_line( "id", "o/r", "abc", "EXCLUDED-UNAVAILABLE" ).split( "\t" )[ 4: ] == [ "0", "-", "EXCLUDED-UNAVAILABLE" ]
    assert len( X.MANIFEST_COLUMNS ) == 7
    assert X.manifest_hash( [ "a\tb" ] ) != X.manifest_hash( [ "a\tc" ] )

def test_main_refuses_an_unpinned_rows_file():
    import tempfile
    d = tempfile.mkdtemp()
    rows = os.path.join( d, "rows.json" )
    open( rows, "w" ).write( "[]" )
    rc = X.main( [ "--rows", rows, "--repos-dir", d, "--out", os.path.join( d, "out" ) ] )
    assert rc == 2, "an arbitrary rows file must be refused before anything is read (§4.1)"
    assert not os.path.exists( os.path.join( d, "out" ) )


def main():
    tests = [ ( n, f ) for n, f in sorted( globals().items() ) if n.startswith( "test_" ) and callable( f ) ]
    failed = 0
    for name, fn in tests:
        try:
            fn()
            print( "  PASS  %s" % name )
        except Exception as e:                       # report every failure, not just the first
            failed += 1
            print( "  FAIL  %s: %s: %s" % ( name, type( e ).__name__, e ) )
    print( "%d/%d passed" % ( len( tests ) - failed, len( tests ) ) )
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit( main() )
