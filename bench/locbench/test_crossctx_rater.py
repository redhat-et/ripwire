#!/usr/bin/env python3
"""
Unit tests for bench/locbench/crossctx_rater.py — the rater-stage driver of the cross-context external-rate
pre-registration (docs/research/cross-context-external-rate.md §6–§8, amendment 1, 2026-09-23).

SYNTHETIC ONLY. Rows, sites, pre-fix files and rater answers below are hand-written here. Nothing reads
Loc-Bench data, calls a model, invokes git or touches the network. These tests prove the driver's MECHANICS
before any packet exists: the packet carries no identity, the brief and packets cannot leak the hypothesis,
the answer schema is enforced, a CROSS answer is verified against the tree, labels ingest without hand
transcription, kappa handles every category, and the §8 table assembles.

Pure Python, no pytest dependency. Runs as a plain script:

    python3 bench/locbench/test_crossctx_rater.py
"""
import os, sys

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
import crossctx_sites as S
import crossctx_rater as R
from test_crossctx_sites import BASE, FILES, diff, read_base

FIX = diff( "pkg/a.py", [ ( "@@ -6,1 +6,1 @@", [ "-    return x + 1", "+    return x + 2" ] ) ] )
ROW = dict( instance_id="owner__repo-1", repo="owner/repo", base_commit="deadbeef", problem_statement="helper is off by one",
            patch=FIX, edit_functions=[ "pkg/a.py:helper" ] )

def answer( idx, verdict, primary="pkg/a.py:helper", second=None, relation=None, **kw ):
    a = dict( packet_index=idx, primary_site=primary, verdict=verdict, second_site=second, relation=relation,
              external_contract=False, confidence="sure", tool_calls=3, output_tokens=200, note="" )
    a.update( kw )
    return a

# ── the brief ─────────────────────────────────────────────────────────────────────────────────────────────
def test_brief_exists_is_hashed_and_leaks_nothing():
    text = open( R.BRIEF_PATH, encoding="utf-8" ).read()
    assert len( R.brief_sha256() ) == 64
    assert R.leaks( text ) == [], R.leaks( text )
    for must in ( "quote test", "primary site", "second site", "ls-tree", "25 reads", "1,500 output tokens", "UNDECIDED", "NOT-A-DEFECT",
                  "external_contract", "packet_index" ):
        assert must in text, must
    for must_not in ( "§3.4", "§9", "roadmap", "comparab" ):
        assert must_not not in text, must_not

# ── R2 packet ─────────────────────────────────────────────────────────────────────────────────────────────
def test_packet_carries_sites_and_no_identity():
    res = S.sites_for_row( FIX, read_base( FILES ) )
    p = R.build_packet( 7, ROW, res, read_base( FILES ), "b" * 64 )
    assert p[ "packet_index" ] == 7 and p[ "brief_sha256" ] == "b" * 64
    assert "instance_id" not in p and "repo" not in p and "owner__repo" not in str( p )
    assert p[ "sites" ] == [ dict( site="pkg/a.py:helper", pre_fix_text="def helper(x):\n    return x + 1" ) ]
    assert p[ "tree_access" ] == dict( commands=[ "ls-tree", "show", "grep" ], read_budget=25, output_token_budget=1500, network=False )
    assert "test_patch" not in p
    p2 = R.build_packet( 8, dict( ROW, test_patch="diff --git a/tests/test_a.py b/tests/test_a.py\n" ), res, read_base( FILES ), "b" * 64 )
    assert p2[ "test_patch" ].startswith( "diff --git" ), "the dataset's test_patch is shown when it exists"

def test_packet_refuses_to_leak():
    res = S.sites_for_row( FIX, read_base( FILES ) )
    try:
        R.build_packet( 1, dict( ROW, problem_statement="the internal rate is 88%" ), res, read_base( FILES ), "b" * 64 )
        assert False, "must raise"
    except ValueError as e:
        assert "88%" in str( e )

# ── R4/R6 validate ────────────────────────────────────────────────────────────────────────────────────────
def test_validate_label_schema_and_downgrades():
    ok = R.validate_label( answer( 1, "LOCAL" ) )
    assert ok[ "verdict" ] == "LOCAL" and ok[ "flags" ] == set()
    for bad in ( answer( 1, "MAYBE" ), answer( 1, "CROSS" ), answer( 1, "CROSS", second="pkg/a.py:tail" ),
                 answer( 1, "LOCAL", primary=None ), answer( 1, "LOCAL", confidence="meh" ), "not an object", answer( "x", "LOCAL" ) ):
        try:
            R.validate_label( bad ); assert False, bad
        except ValueError:
            pass
    nad = R.validate_label( answer( 1, "NOT-A-DEFECT", primary=None ) )
    assert nad[ "verdict" ] == "NOT-A-DEFECT"
    over = R.validate_label( answer( 1, "CROSS", second="pkg/a.py:tail", relation="caller-callee-contract", tool_calls=26 ) )
    assert over[ "verdict" ] == "UNDECIDED" and "budget_exceeded" in over[ "flags" ]
    over2 = R.validate_label( answer( 1, "LOCAL", output_tokens=1501 ) )
    assert over2[ "verdict" ] == "UNDECIDED"
    ext = R.validate_label( answer( 1, "CROSS", second="pkg/a.py:tail", relation="other", external_contract=True ) )
    assert ext[ "verdict" ] == "LOCAL" and "external_contract" in ext[ "flags" ], "an external contract is LOCAL by §3.3"

# ── F1 verify ─────────────────────────────────────────────────────────────────────────────────────────────
def test_verify_second_site_against_the_tree():
    rb = read_base( FILES )
    good = R.verify_second_site( R.validate_label( answer( 1, "CROSS", second="pkg/a.py:tail", relation="caller-callee-contract" ) ), rb, { "pkg/a.py:helper" } )
    assert good[ "verdict" ] == "CROSS" and "second_site_edited" not in good[ "flags" ]
    edited = R.verify_second_site( R.validate_label( answer( 1, "CROSS", second="pkg/b.py:tail", relation="caller-callee-contract" ) ), rb, { "pkg/a.py:helper", "pkg/b.py:tail" } )
    assert edited[ "verdict" ] == "CROSS" and "second_site_edited" in edited[ "flags" ], "a second site the fix also touched stays CROSS, flagged"
    for ss in ( "pkg/a.py:nothere", "pkg/zzz.py:tail", "pkg/a.py:helper", "pkg/a.py:Widget.size.inner" ):
        lab = R.verify_second_site( R.validate_label( answer( 1, "CROSS", second=ss, relation="other" ) ), rb, { "pkg/a.py:helper" } )
        assert lab[ "verdict" ] == "UNDECIDED" and "unverified_second_site" in lab[ "flags" ], ss
    mod = R.verify_second_site( R.validate_label( answer( 1, "CROSS", second="pkg/b.py:<module>", relation="constant-format-schema-elsewhere" ) ), rb, set() )
    assert mod[ "verdict" ] == "CROSS", "<module> of an existing file is a site"
    cls = R.verify_second_site( R.validate_label( answer( 1, "CROSS", second="pkg/a.py:Widget", relation="other" ) ), rb, set() )
    assert cls[ "verdict" ] == "CROSS", "a class is a site"
    local = R.verify_second_site( R.validate_label( answer( 1, "LOCAL" ) ), rb, set() )
    assert local[ "verdict" ] == "LOCAL"

# ── R6 ingest and R7 kappa ────────────────────────────────────────────────────────────────────────────────
def records():
    rb = read_base( FILES )
    A = { 0: answer( 0, "CROSS", second="pkg/a.py:tail", relation="caller-callee-contract" ),
          1: answer( 1, "LOCAL" ), 2: answer( 2, "CROSS", second="pkg/a.py:tail", relation="other" ),
          3: answer( 3, "UNDECIDED" ), 4: answer( 4, "CROSS", second="pkg/a.py:ghost", relation="other" ),
          5: answer( 5, "LOCAL" ), 6: "garbage" }
    B = { 0: answer( 0, "CROSS", second="pkg/a.py:tail", relation="caller-callee-contract" ),
          1: answer( 1, "LOCAL" ), 2: answer( 2, "LOCAL" ), 3: answer( 3, "LOCAL" ),
          4: answer( 4, "CROSS", second="pkg/a.py:tail", relation="other" ), 5: answer( 5, "NOT-A-DEFECT", primary=None ),
          6: answer( 6, "LOCAL" ) }
    return R.ingest( A, B, lambda i: rb, lambda i: { "pkg/a.py:helper" } )

def test_ingest_labels_and_sub_buckets():
    recs = { r.packet_index: r for r in records() }
    assert recs[ 0 ].label == "CROSS" and recs[ 1 ].label == "LOCAL"
    assert ( recs[ 2 ].label, recs[ 2 ].sub ) == ( "UNTAGGED", "DISAGREE" )
    assert ( recs[ 3 ].label, recs[ 3 ].sub ) == ( "UNTAGGED", "UNDECIDED" )
    assert ( recs[ 4 ].label, recs[ 4 ].sub ) == ( "UNTAGGED", "UNVERIFIED-SECOND-SITE" ) and recs[ 4 ].a == "UNDECIDED"
    assert ( recs[ 5 ].label, recs[ 5 ].sub ) == ( "UNTAGGED", "NOT-A-DEFECT" )
    assert ( recs[ 6 ].label, recs[ 6 ].sub ) == ( "UNTAGGED", "UNDECIDED" ) and "schema_error" in recs[ 6 ].flags
    assert R.untagged_share( list( recs.values() ) ) == 5 / 7.0
    assert R.sub_buckets( list( recs.values() ) ) == { "DISAGREE": 1, "UNDECIDED": 2, "UNVERIFIED-SECOND-SITE": 1, "NOT-A-DEFECT": 1 }

def test_kappa_three_way_and_binary_on_records():
    recs = records()
    k3 = R.kappa_three_way( recs )
    assert -1.0 <= k3 <= 1.0, "3-way kappa runs over tuples/others without raising"
    kb, n = R.kappa_binary( recs )
    assert n == 3 and -1.0 <= kb <= 1.0, "binary kappa over the 3 rows where both chose CROSS/LOCAL (0, 1, 2)"
    perfect = [ R.Record( i, v, v, v, None, frozenset(), None, None ) for i, v in enumerate( [ "CROSS", "LOCAL", "CROSS" ] ) ]
    assert R.kappa_three_way( perfect ) == 1.0 and R.kappa_binary( perfect ) == ( 1.0, 3 )
    assert R.kappa_binary( [ R.Record( 0, "UNDECIDED", "LOCAL", "UNTAGGED", "UNDECIDED", frozenset(), None, None ) ] ) == ( None, 0 )

# ── §7/§8 ─────────────────────────────────────────────────────────────────────────────────────────────────
def manifest():
    rows = []
    for i in range( 60 ):
        cls = "ONE-SITE" if i < 40 else ( "MULTI-FILE" if i < 55 else "TEST-ONLY" )
        flags = "move" if i == 41 else ( "test_dir_only" if i == 56 else "-" )
        rows.append( dict( instance_id="r%02d" % i, repo="o/r", base_commit="c", mclass=cls, n_sites="1",
                           flags=flags, mclass_collapsed="ONE-SITE" if i == 41 else cls ) )
    return rows

def test_strata_file_grain_and_outcome_table():
    man = manifest()
    stratum_of = lambda idx: "r%02d" % idx
    primary_of = lambda idx: "pkg/a.py:helper"
    recs = [ R.Record( 0, "CROSS", "CROSS", "CROSS", None, frozenset(), "pkg/a.py:tail", "pkg/a.py:tail" ),
             R.Record( 1, "LOCAL", "LOCAL", "LOCAL", None, frozenset(), None, None ),
             R.Record( 41, "CROSS", "CROSS", "CROSS", None, frozenset(), "pkg/b.py:tail", "pkg/b.py:tail" ),
             R.Record( 42, "CROSS", "LOCAL", "UNTAGGED", "DISAGREE", frozenset(), "pkg/b.py:tail", None ) ]
    strata = R.strata_from( man, recs, stratum_of )
    assert strata[ "ONE-SITE" ] == dict( N=40, labels=[ "CROSS", "LOCAL" ] ) and strata[ "MULTI-FILE" ] == dict( N=15, labels=[ "CROSS" ] )
    assert strata[ "MULTI-SITE-ONE-FILE" ] == dict( N=0, labels=[] )
    fg = R.file_grain( recs, primary_of )
    assert fg[ 0 ].label == "LOCAL" and fg[ 2 ].label == "CROSS", "same-file second site is LOCAL at file grain; other-file stays CROSS"
    col = R.strata_from( man, recs, stratum_of, "mclass_collapsed" )
    assert col[ "ONE-SITE" ][ "N" ] == 41 and col[ "MULTI-FILE" ][ "N" ] == 14, "moves collapsed re-weights by the collapsed class"
    assert [ r.label for r in R.resolve_disagreements( recs, "CROSS" ) ][ 3 ] == "CROSS"
    text, res = R.outcome_table( man, recs, stratum_of, primary_of, { "CROSS": 94, "SPREAD-IN-FILE": 254, "LOCAL": 212 }, True, 0.9, True,
                                 "m" * 64, "b" * 64, [ "t" * 64, "u" * 64 ], S.FROZEN[ "rater_families" ] )
    for must in ( "60 rows", "TEST-ONLY", "scoreable N            55", "fingerprint (legacy)", "M8 gold recall         0.900  [pass]",
                  "kappa", "P (post-stratified)", "sensitivities", "file-grain", "moves-collapsed", "disagree->CROSS",
                  "TEST-ONLY by dir-rule  1 rows", "internal               149/169 = 88.2% [82.4, 92.2]; code-only 109/124 = 87.9%",
                  "contrast", "anthropic-claude, openai-gpt", "decision (§9)" ):
        assert must in text, ( must, text )
    assert res[ "verdict" ] == "INDETERMINATE", "four synthetic rows cannot reach a verdict"
    assert set( res[ "sensitivities" ] ) == { "file-grain", "moves-collapsed", "otherlang-dropped", "disagree->CROSS", "disagree->LOCAL", "unedited-second-site-only" }

def test_second_site_edited_is_printed_and_bounded():
    man = manifest()
    stratum_of = lambda idx: "r%02d" % idx
    primary_of = lambda idx: "pkg/a.py:helper"
    ed = frozenset( { "second_site_edited" } )
    recs = [ R.Record( 0, "CROSS", "CROSS", "CROSS", None, ed, "pkg/a.py:tail", "pkg/a.py:tail" ),
             R.Record( 1, "CROSS", "CROSS", "CROSS", None, frozenset(), "pkg/b.py:tail", "pkg/b.py:tail" ),
             R.Record( 2, "LOCAL", "LOCAL", "LOCAL", None, frozenset(), None, None ),
             R.Record( 3, "CROSS", "LOCAL", "UNTAGGED", "DISAGREE", ed, "pkg/b.py:tail", None ) ]
    assert R.second_site_edited_count( recs ) == 1, "only CROSS-labelled rows count; the DISAGREE row does not"
    low = R.unedited_second_site_only( recs )
    assert [ r.label for r in low ] == [ "LOCAL", "CROSS", "LOCAL", "UNTAGGED" ]
    strata = R.strata_from( man, recs, stratum_of )
    assert strata[ "ONE-SITE" ][ "labels" ] == [ "CROSS", "CROSS", "LOCAL" ]
    text, res = R.outcome_table( man, recs, stratum_of, primary_of, { "CROSS": 94, "SPREAD-IN-FILE": 254, "LOCAL": 212 }, True, 0.9, True,
                                 "m" * 64, "b" * 64, [], S.FROZEN[ "rater_families" ] )
    assert "second_site_edited     1 CROSS rows" in text, text
    assert "unedited-second-site-only" in text and res[ "sensitivities" ][ "unedited-second-site-only" ][ "point" ] < res[ "estimate" ][ "point" ], \
        "the bound is below the primary estimate when an edited second site exists"
    assert "code-only - P" in text, "the contrast is printed against both internal chains"
    assert "(two model families)" in text
    fb_text, _ = R.outcome_table( man, recs, stratum_of, primary_of, { "CROSS": 94, "SPREAD-IN-FILE": 254, "LOCAL": 212 }, True, 0.9, True,
                                  "m" * 64, "b" * 64, [], S.FROZEN[ "rater_families_fallback" ] )
    assert "FALLBACK pair" in fb_text and "WEAKER independence" in fb_text, "a same-family run says so in its own table"
    odd_text, _ = R.outcome_table( man, recs, stratum_of, primary_of, { "CROSS": 94, "SPREAD-IN-FILE": 254, "LOCAL": 212 }, True, 0.9, True,
                                   "m" * 64, "b" * 64, [], ( "some-model", "other-model" ) )
    assert "UNREGISTERED pair" in odd_text

def test_outcome_table_with_no_records():
    man = manifest()
    text, res = R.outcome_table( man, [], lambda i: None, lambda i: None, { "CROSS": 0, "SPREAD-IN-FILE": 0, "LOCAL": 0 }, False, None, False,
                                 "m" * 64, "b" * 64, [], S.FROZEN[ "rater_families" ] )
    assert "[FAIL]" in text and res[ "verdict" ] == "INDETERMINATE" and res[ "clause" ] == "fingerprint failed (§4.4)"


def main():
    tests = [ ( n, f ) for n, f in sorted( globals().items() ) if n.startswith( "test_" ) and callable( f ) ]
    failed = 0
    for name, fn in tests:
        try:
            fn()
            print( "  PASS  %s" % name )
        except Exception as e:
            failed += 1
            print( "  FAIL  %s: %s: %s" % ( name, type( e ).__name__, e ) )
    print( "%d/%d passed" % ( len( tests ) - failed, len( tests ) ) )
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit( main() )
