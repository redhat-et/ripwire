#!/usr/bin/env python3
"""
Unit tests for bench/locbench/served_syms_signal.py — the §5.4 pre-registered scoring procedure for
`served_syms` (docs/research/confidence-and-abstention.md §5.4, dated 2026-09-23).

SYNTHETIC ONLY. Every fixture here is hand-built in this file. Nothing reads LocBench data, invokes
the ripwire binary, or touches the network — the pre-registration this module scores against requires
that no served_syms number be reported "on the 92" before the real asset tree is on disk; these tests
exist to prove the MATH (operating-point sweep, tie rule, fire-rate self-reject, orientation, bootstrap
determinism, fingerprint check) is correct in advance of that, on data invented for the purpose.

Pure Python, no network, no pytest dependency — same convention as bench/locbench/test_compare_gate.py.
Runs as a plain script:

    python3 bench/locbench/served_syms_signal.py    # (module has no __main__; run the test file)
    python3 bench/locbench/test_served_syms_signal.py

or, if pytest happens to be installed:

    python3 -m pytest bench/locbench/test_served_syms_signal.py

Each `test_*` function is a self-contained assert-based case; `main()` runs them all and reports.
"""
import os, sys

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
sys.path.insert( 0, os.path.join( os.path.dirname( HERE ), "arb" ) )

import served_syms_signal as S
from score_abstention_calibration import auroc


# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────
def mkrow( repo, served_syms, file_hit, func_hit, confidence="low", margin_pct=0, margin_bp=None ):
    """A hand-built row in exactly the shape calibrate_confidence.py's grade()/measure_instance()
    produce: instance_id/repo/served_syms/file_hit/func_hit/confidence/margin_pct at minimum — the
    fields served_syms_signal.py actually reads. `margin_bp` (R-MARGIN, §5.5) defaults to None like a
    row scored on a binary that does not emit it; tests that exercise `score_margin_bp` pass it."""
    return dict( instance_id="%s#%d" % ( repo, served_syms ), repo=repo, served_syms=served_syms,
                file_hit=file_hit, func_hit=func_hit, confidence=confidence, margin_pct=margin_pct,
                margin_bp=margin_bp )


def mkrow_margin( repo, margin_bp, file_hit, func_hit, confidence="low", margin_pct=0, served_syms=0 ):
    """R-MARGIN (§5.5) fixture helper: a row keyed by `margin_bp` instead of `served_syms` (the field
    `score_margin_bp` actually reads). `served_syms` defaults to 0 and is irrelevant to every test that
    uses this helper -- present only because `mkrow`'s shape carries it and some shared code paths
    (none that `score_margin_bp` itself uses) might expect the key to exist."""
    return dict( instance_id="%s#%d" % ( repo, margin_bp ), repo=repo, served_syms=served_syms,
                file_hit=file_hit, func_hit=func_hit, confidence=confidence, margin_pct=margin_pct,
                margin_bp=margin_bp )


def synthetic_summary( n=92, confidence_low=74, confidence_high=18,
                       misses_file=15, misses_func=38, auroc_file=0.580, auroc_func=0.622 ):
    """The slice of calibrate_confidence.py's `summary` dict check_fingerprint() actually reads."""
    return dict(
        n_scored=n,
        meta=dict( assets="/synthetic/assets", binary_version="ripwire 0.0.0 (test)" ),
        overall=dict( confidence_high=confidence_high ),
        discrimination=dict(
            file_hit=dict( misses=misses_file, auroc=auroc_file ),
            func_hit=dict( misses=misses_func, auroc=auroc_func ) ) )


# ── fingerprint (§5.4.1) ────────────────────────────────────────────────────────────────────────────
def test_fingerprint_matches():
    ok, detail = S.check_fingerprint( synthetic_summary() )
    assert ok, detail
    assert all( detail["checks"].values() ), detail["checks"]


def test_fingerprint_rejects_wrong_split():
    ok, detail = S.check_fingerprint( synthetic_summary( confidence_low=70, confidence_high=22 ) )
    assert not ok
    assert detail["checks"]["confidence_low"] is False
    assert detail["checks"]["confidence_high"] is False
    # everything NOT touched by the mutation must still read True — a single failing check must not
    # taint the others, or a report reading `checks` would misname which figure actually broke.
    assert detail["checks"]["n"] is True
    assert detail["checks"]["misses_file_hit"] is True


def test_fingerprint_rejects_auroc_outside_tolerance():
    ok, detail = S.check_fingerprint( synthetic_summary( auroc_func=0.700 ) )
    assert not ok
    assert detail["checks"]["score_auroc_func_hit"] is False
    assert detail["checks"]["score_auroc_file_hit"] is True


def test_fingerprint_tolerates_rounding_noise():
    # the pinned figures are the exact nearest AUROC-lattice point to the published value (fix round 1,
    # HIGH-2), not the published rendering itself -- both published rounded forms must still pass.
    ok, _detail = S.check_fingerprint( synthetic_summary( auroc_func=0.622, auroc_file=0.580 ) )
    assert ok, _detail
    ok2, _detail2 = S.check_fingerprint( synthetic_summary( auroc_func=0.6221, auroc_file=0.5805 ) )
    assert ok2, _detail2


def test_fingerprint_accepts_published_4dp_figures_and_their_exact_lattice_points():
    """HIGH-2 (reports/rv-served-syms-prereg.md): the fingerprint must accept the ONLY published 4-dp
    rendering of the file-grain figure (0.5805, from reports/rv-margin-resolution.md) and the exact
    15-miss x 77-hit AUROC lattice point that rendering can only come from (670.5/1155). Mirrors the
    reviewer's own C7/C7b/C7c cases."""
    ok, det = S.check_fingerprint( synthetic_summary( auroc_file=0.5805, auroc_func=0.6221 ) )
    assert ok, det["checks"]                                          # C7
    ok, det = S.check_fingerprint( synthetic_summary( auroc_file=670.5 / 1155, auroc_func=1276.5 / 2052 ) )
    assert ok, det["checks"]                                          # C7b -- exact lattice point
    ok, det = S.check_fingerprint( synthetic_summary( auroc_file=670 / 1155, auroc_func=1276.5 / 2052 ) )
    assert ok, det["checks"]                                          # C7c -- neighbouring lattice point


def test_fingerprint_rejects_lattice_points_two_steps_out():
    # 669.5/1155 is exactly TWO lattice steps (step = 0.5/1155) below the pinned 670.5/1155 -- outside
    # the +-1-step tolerance (0.0006 admits 1 step = 0.000433, excludes 2 steps = 0.000866) by
    # construction; the fingerprint must not admit it. (This was the OLD tolerance's own admissible
    # point, pre-fix-round-1 -- confirming the fix narrowed rather than just shifted the window.)
    ok, det = S.check_fingerprint( synthetic_summary( auroc_file=669.5 / 1155 ) )
    assert not ok
    assert det["checks"]["score_auroc_file_hit"] is False


def test_score_served_syms_reports_fingerprint_mismatch_and_nothing_else():
    summary = synthetic_summary( n=91 )   # off by one instance
    out = S.score_served_syms( summary, rows=[] )
    assert out["outcome"] == "fingerprint_mismatch"
    assert out["public_sentence"] == S.PUBLIC_SENTENCE_MISMATCH
    assert "grains" not in out
    assert "chosen_threshold" not in out
    assert "pass" not in out


def test_check_fingerprint_rows_len_check_is_optional_but_enforced_when_given():
    """HIGH-2's 'count checks' / the reviewer's C9: `len(rows) == n_scored` was not checked at all
    before fix round 1 -- `score_served_syms` always passes rows, so it now always enforces this, but
    `check_fingerprint(summary)` alone (no rows) must stay callable for a caller that only wants to
    check the summary in isolation (the reviewer's own C7/C7b/C7c call it this way)."""
    summary = synthetic_summary()   # n_scored=92
    ok_no_rows, det_no_rows = S.check_fingerprint( summary )                 # rows=None -> no rows check
    assert ok_no_rows
    assert "rows_len_matches_n" not in det_no_rows["checks"]

    ok_matching, _ = S.check_fingerprint( summary, rows=[ object() ] * 92 )
    assert ok_matching

    ok_mismatched, det_mismatched = S.check_fingerprint( summary, rows=[ object() ] * 50 )
    assert not ok_mismatched
    assert det_mismatched["checks"]["rows_len_matches_n"] is False


def test_score_served_syms_catches_row_count_mismatch_via_fingerprint():
    """C9 (reports/rv-served-syms-prereg.md): before fix round 1, `score_served_syms` scored 50 rows
    happily under a summary that claimed n_scored=92 -- the population fingerprint never checked its
    OWN caller's row count. Now it must refuse via the ordinary fingerprint_mismatch path."""
    rows50 = ( [ mkrow( "m/%d" % i, 30, file_hit=False, func_hit=False ) for i in range( 20 ) ]
              + [ mkrow( "h/%d" % i, 5, file_hit=True, func_hit=True ) for i in range( 30 ) ] )
    out = S.score_served_syms( synthetic_summary(), rows50 )   # summary says n_scored=92
    assert out["outcome"] == "fingerprint_mismatch", out["outcome"]
    assert out["fingerprint"]["checks"]["rows_len_matches_n"] is False
    assert "grains" not in out


# ── the >= confusion primitive and the threshold sweep (§5.4.4) ───────────────────────────────────────
def test_confusion_ge_hand_computed():
    # misses (label True) carry the LARGE served_syms values (10, 12); hits carry the small ones
    # (3, 4, 5) — the registered orientation (§5.4.3) says that is the pattern a real miss detector
    # would show.
    labels = [ True, True, False, False, False ]
    values = [ 10, 12, 3, 4, 5 ]
    assert S._confusion_ge( labels, values, 10 ) == ( 2, 0, 0, 3 )     # both misses caught, no hit warned
    assert S._confusion_ge( labels, values, 13 ) == ( 0, 2, 0, 3 )     # warn nobody -> both misses missed
    assert S._confusion_ge( labels, values, 3 )  == ( 2, 0, 3, 0 )     # warn everybody -> every hit false-warned


def test_confusion_ge_validates_integer_inputs():
    """LOW-1 (reports/rv-served-syms-prereg.md), folded into the MEDIUM-4 commit: the `t - 1` trick is
    exact only for real ints. A float value, a float threshold, or a bool sneaking in as a value (a
    bool IS an int in Python, but is never a real served_syms count) must raise loudly rather than
    silently miscount -- mirrors the reviewer's own C10 (float 7.5), which asserted the WRONG tuple
    `_confusion_ge` used to return for that input; the fix makes it raise instead."""
    labels = [ True, False ]
    try:
        S._confusion_ge( labels, [ 7.5, 7.0 ], 7.5 )
        assert False, "expected ValueError for a float served_syms value"
    except ValueError as e:
        assert "served_syms" in str( e ) or "int" in str( e )

    try:
        S._confusion_ge( labels, [ 7, 7 ], 7.5 )               # int values, float threshold
        assert False, "expected ValueError for a float threshold"
    except ValueError:
        pass

    try:
        S._confusion_ge( labels, [ True, 7 ], 7 )              # bool sneaking in as a value
        assert False, "expected ValueError for a bool value"
    except ValueError:
        pass

    # real ints must still work exactly as before (no regression from adding the check).
    assert S._confusion_ge( labels, [ 8, 7 ], 8 ) == ( 1, 0, 0, 1 )


def test_sweep_candidate_set_and_boundary_rows():
    labels = [ True, True, False, False, False ]
    values = [ 10, 12, 3, 4, 5 ]
    table = S.sweep( labels, values )
    thresholds = [ r["threshold"] for r in table ]
    assert thresholds == [ 3, 4, 5, 10, 12, 13 ], thresholds   # distinct(values) ∪ {max+1}, sorted

    low = next( r for r in table if r["threshold"] == 3 )      # warn everyone
    assert low["recall"] == 1.0 and low["false_warn"] == 1.0 and low["warn_rate"] == 1.0

    high = next( r for r in table if r["threshold"] == 13 )    # warn no one
    assert high["recall"] == 0.0 and high["false_warn"] == 0.0 and high["warn_rate"] == 0.0

    mid = next( r for r in table if r["threshold"] == 12 )
    assert mid["recall"] == 0.5 and mid["false_warn"] == 0.0
    assert abs( mid["warn_rate"] - 0.2 ) < 1e-9


def test_choose_operating_point_applies_fire_rate_self_reject():
    """t=10 has PERFECT recall/false-warn (1.0 / 0.0) but warns on 2 of 5 rows == 0.4 > the 0.25 fire-
    rate ceiling (SR-1), so it must be rejected as the SHIPPABLE-track pick even though it would
    otherwise be the obvious one. Only t=12 (recall 0.5, false_warn 0.0, warn_rate 0.2) survives both
    the band and SR-1 -- but t=10 still counts toward band_met/best_band_only (HIGH-3's split)."""
    labels = [ True, True, False, False, False ]
    values = [ 10, 12, 3, 4, 5 ]
    table = S.sweep( labels, values )
    op = S.choose_operating_point( table, n_rows=5 )
    assert op["band_met"] is True            # t=10 AND t=12 both satisfy false_warn<=0.2, recall>=0.5
    assert op["sr1_met"] is True             # t=12 also clears the fire-rate ceiling
    chosen = op["chosen"]
    assert chosen is not None
    assert chosen["threshold"] == 12
    assert chosen["recall"] == 0.5
    assert chosen["false_warn"] == 0.0
    assert op["best_band_only"]["threshold"] == 10   # the band-only winner ignores SR-1 entirely


def test_choose_operating_point_band_met_but_sr1_rejected():
    """HIGH-3 / the reviewer's C6: a threshold can satisfy the owner's actual band (false_warn<=0.20,
    recall>=0.50) while warning on more than 25% of rows. That must show up as band_met=True,
    sr1_met=False, chosen=None (no shippable-track candidate) -- never as a bare 'band not met'."""
    table = [ dict( threshold=30, recall=0.632, false_warn=0.111, warn_rate=0.326, tp=24, fn=14, fp=6, tn=48 ) ]
    op = S.choose_operating_point( table, n_rows=92 )
    assert op["band_met"] is True
    assert op["sr1_met"] is False
    assert op["chosen"] is None
    assert op["best_band_only"] is not None and op["best_band_only"]["threshold"] == 30


def test_choose_operating_point_tie_rule_prefers_larger_threshold():
    """Two candidate rows tied on recall (both 0.6, both inside the band and under the fire-rate
    ceiling) at different thresholds -- the larger threshold (fewer rows warned, more conservative)
    must win, per §5.4.4's tie rule."""
    table = [
        dict( threshold=5, recall=0.6, false_warn=0.10, warn_rate=0.20, tp=3, fn=2, fp=1, tn=9 ),
        dict( threshold=8, recall=0.6, false_warn=0.05, warn_rate=0.15, tp=3, fn=2, fp=1, tn=9 ),
        dict( threshold=2, recall=0.9, false_warn=0.50, warn_rate=0.60, tp=4, fn=1, fp=6, tn=4 ),  # out of band
    ]
    op = S.choose_operating_point( table, n_rows=15 )
    assert op["chosen"] is not None and op["chosen"]["threshold"] == 8


def test_choose_operating_point_none_when_nothing_qualifies():
    table = [ dict( threshold=t, recall=0.1, false_warn=0.9, warn_rate=0.5, tp=0, fn=0, fp=0, tn=0 )
             for t in ( 1, 2, 3 ) ]
    op = S.choose_operating_point( table, n_rows=10 )
    assert op["band_met"] is False
    assert op["sr1_met"] is False
    assert op["chosen"] is None
    assert op["best_band_only"] is None


# ── §5.2's AUROC band, reported not gating (MEDIUM-3) ─────────────────────────────────────────────────
def test_auroc_band_5_2_rungs():
    assert S.auroc_band_5_2( 0.75 ) == "meets"
    assert S.auroc_band_5_2( 0.70 ) == "meets"              # inclusive at the boundary
    assert S.auroc_band_5_2( 0.65 ) == "weak"
    assert S.auroc_band_5_2( 0.60 ) == "weak"                # inclusive at the boundary
    assert S.auroc_band_5_2( 0.50 ) == "does_not_meet"
    assert S.auroc_band_5_2( 0.36 ) == "does_not_meet"
    assert S.auroc_band_5_2( 0.35 ) == "does_not_meet_opposite_direction"   # HIGH-1(d)'s refutation rung
    assert S.auroc_band_5_2( 0.10 ) == "does_not_meet_opposite_direction"
    assert S.auroc_band_5_2( None ) is None
    # §5.2's band (0.70/0.60) is deliberately NOT the same numbers as ARB round one's own auroc_band()
    # (0.65/0.55) -- 0.62 must read "weak" under §5.2's band although it would "meet" ARB's.
    assert S.auroc_band_5_2( 0.62 ) == "weak"


def test_directional_refutation_never_flips_to_a_pass():
    """C5-equivalent at the auroc_band_5_2 level: an AUROC at or below 0.35 is reported as a directional
    refutation of the REGISTERED orientation, never silently re-read under the opposite one (which
    would otherwise look like a strong 'meets')."""
    assert S.auroc_band_5_2( 0.0 ) == "does_not_meet_opposite_direction"
    # if this had been silently flipped to `1 - 0.0 = 1.0`, it would misreport as "meets" -- assert the
    # actual rung is the refutation string, not a number anyone could mistake for a pass.
    assert S.auroc_band_5_2( 0.0 ) != "meets"


# ── orientation (§5.4.3) ────────────────────────────────────────────────────────────────────────────
def test_orientation_direction_matters_for_auroc():
    """A clean fixture where misses genuinely carry larger served_syms. Scoring it under the REGISTERED
    orientation (ORIENTATION * served_syms, i.e. served_syms unchanged since ORIENTATION == +1) must
    give a strong AUROC; scoring the SAME rows under the opposite orientation (manually negated here,
    never by touching the module constant) must give a correspondingly weak one -- proving the
    direction is not a free parameter the AUROC calculation quietly absorbs."""
    rows = ( [ mkrow( "r/a", sz, file_hit=False, func_hit=False ) for sz in ( 30, 32, 35, 40, 28 ) ]
            + [ mkrow( "r/b", sz, file_hit=True, func_hit=True ) for sz in ( 3, 5, 4, 6, 2 ) ] )
    labels = [ not r["func_hit"] for r in rows ]
    correct = auroc( labels, [ S.ORIENTATION * r["served_syms"] for r in rows ] )
    flipped = auroc( labels, [ -S.ORIENTATION * r["served_syms"] for r in rows ] )
    assert correct > 0.9, correct
    assert flipped < 0.1, flipped
    assert abs( ( correct + flipped ) - 1.0 ) < 1e-9   # AUROC(-score) == 1 - AUROC(score), exactly


# ── bootstrap (§5.4.5) ──────────────────────────────────────────────────────────────────────────────
def _clean_rows( n_miss_repos=6, n_hit_repos=6, miss_base=1000, hit_base=1 ):
    """Two disjoint served_syms ranges (miss rows always >= miss_base, hit rows always < miss_base) so
    the fixture stays cleanly separated regardless of how many repos of each kind are asked for —
    a hit-heavy fixture (for the fire-rate/warn_rate tests) must not accidentally let a hit row's
    served_syms wander into the miss range."""
    rows = []
    for i in range( n_miss_repos ):
        rows += [ mkrow( "miss-repo-%d" % i, sz, file_hit=False, func_hit=False )
                 for sz in ( miss_base + 2 * i, miss_base + 2 * i + 1 ) ]
    for i in range( n_hit_repos ):
        rows += [ mkrow( "hit-repo-%d" % i, sz, file_hit=True, func_hit=True )
                 for sz in ( hit_base + 2 * i, hit_base + 2 * i + 1 ) ]
    return rows


def test_bootstrap_auroc_ci_is_deterministic_and_sane():
    rows = _clean_rows()
    lo1, hi1, n1 = S.bootstrap_auroc_ci( rows, "func_hit", n_boot=500 )
    lo2, hi2, n2 = S.bootstrap_auroc_ci( rows, "func_hit", n_boot=500 )
    assert ( lo1, hi1, n1 ) == ( lo2, hi2, n2 ), "same seed, same rows must reproduce byte-identically"
    assert n1 > 0
    assert 0.0 <= lo1 <= hi1 <= 1.0
    point = auroc( [ not r["func_hit"] for r in rows ], [ r["served_syms"] for r in rows ] )
    assert lo1 <= point + 1e-9    # the point estimate should not sit strictly outside its own CI on a
                                  # clean, well-separated fixture (a loose sanity check, not a proof)


def test_bootstrap_operating_point_ci_matches_point_estimate_math():
    rows = _clean_rows()
    ci = S.bootstrap_operating_point_ci( rows, "func_hit", t=20, n_boot=300 )
    labels = [ not r["func_hit"] for r in rows ]
    values = [ r["served_syms"] for r in rows ]
    tp, fn, fp, tn = S._confusion_ge( labels, values, 20 )
    from score_abstention_calibration import prf
    expected = prf( tp, fn, fp, tn )
    assert ci["false_warn"]["point"] == expected["false_abstain_rate"]
    assert ci["recall"]["point"] == expected["recall"]
    assert ci["false_warn"]["n_resamples"] > 0 and ci["recall"]["n_resamples"] > 0


# ── end-to-end score_served_syms() (§5.4.6) ────────────────────────────────────────────────────────
def test_score_served_syms_end_to_end_pass():
    # 12 miss rows (served_syms >= 1000) + 80 hit rows (served_syms < 100) = 92, matching the
    # fingerprint's default n=92 exactly; the disjoint ranges keep warn_rate low (SR-1) once a
    # threshold near 1000 is chosen.
    rows = _clean_rows( n_miss_repos=6, n_hit_repos=40 )
    assert len( rows ) == 92
    summary = synthetic_summary()
    out = S.score_served_syms( summary, rows )
    assert out["outcome"] == "pass", out
    assert out["pass"] is True
    assert out["band_met"] is True and out["sr1_met"] is True
    assert out["chosen_threshold"] is not None
    assert "worth replicating" in out["public_sentence"]
    assert "not 'shippable'" in out["public_sentence"]
    assert out["grain_honesty"]["gating_grain"] == "func_hit"
    # MEDIUM-1: served_syms WAS scored exploratorily; the sentence must not claim it "was never
    # scored" or call it "our best disclosed signal" (an untested comparison).
    assert "was never scored" not in out["public_sentence"]
    assert "our best disclosed signal" not in out["public_sentence"]
    assert "0.669" in out["public_sentence"] and "0.723" in out["public_sentence"]
    # HIGH-1(e): the orientation-informed-by-a-seen-number clause is in every non-mismatch sentence.
    assert "not blind" in out["public_sentence"]
    # every candidate threshold's point must be present for both grains (nothing hidden but the winner)
    assert len( out["grains"]["func_hit"]["sweep"] ) >= 2
    assert len( out["grains"]["file_hit"]["sweep"] ) >= 2
    # MEDIUM-3: §5.2's separate AUROC band is reported per grain, not just the operating-point band.
    assert out["grains"]["func_hit"]["auroc_band_5_2"] in ( "meets", "weak", "does_not_meet",
                                                            "does_not_meet_opposite_direction" )


def test_score_served_syms_end_to_end_fail_on_no_signal():
    """served_syms uncorrelated with the miss label: no threshold should clear the band."""
    rows = ( [ mkrow( "r/%d" % i, 10, file_hit=( i % 2 == 0 ), func_hit=( i % 2 == 0 ) )
              for i in range( 46 ) ]
            + [ mkrow( "s/%d" % i, 10, file_hit=( i % 2 == 0 ), func_hit=( i % 2 == 0 ) )
               for i in range( 46 ) ] )
    # constant served_syms carries no ranking information at all -- a single-value column.
    summary = synthetic_summary( n=len( rows ) )
    out = S.score_served_syms( summary, rows )
    assert out["outcome"] == "fail", out
    assert out["pass"] is False
    assert out["band_met"] is False
    assert out["chosen_threshold"] is None
    assert "does not reach the band" in out["public_sentence"]
    assert "was never scored" not in out["public_sentence"]


def test_score_served_syms_end_to_end_pass_fire_rate_rejected():
    """HIGH-3 / the reviewer's C6, run through the full score_served_syms() pipeline: a threshold that
    meets the owner's band but warns on > 25% of the population must produce its OWN outcome and
    sentence -- never a silent 'pass' and never a false 'does not reach the band'."""
    # 38 func misses, 24 of them at served_syms=30 (recall 24/38 = 0.632); 54 hits, 6 at 30
    # (false_warn 6/54 = 0.111); warn_rate at t=30 is 30/92 = 0.326 > the 0.25 SR-1 ceiling.
    rows = ( [ mkrow( "m/%d" % i, 30 if i < 24 else 5, file_hit=False, func_hit=False ) for i in range( 38 ) ]
            + [ mkrow( "h/%d" % i, 30 if i < 6 else 5, file_hit=True, func_hit=True ) for i in range( 54 ) ] )
    assert len( rows ) == 92
    out = S.score_served_syms( synthetic_summary(), rows )
    assert out["outcome"] == "pass_fire_rate_rejected", out
    assert out["pass"] is False
    assert out["band_met"] is True
    assert out["sr1_met"] is False
    assert out["chosen_threshold"] is None                      # no shippable-track candidate
    assert out["best_band_only_threshold"]["threshold"] == 30
    assert "meets the band and fails the fire-rate self-reject" in out["public_sentence"]
    assert "does not reach the band" not in out["public_sentence"]
    assert "was never scored" not in out["public_sentence"]


def test_score_served_syms_pass_sentence_reports_other_grain_band_vs_safe_separately():
    """MEDIUM-4 (delta review, reports/rv-served-syms-prereg.md): a real PASS on func_hit whose
    non-gating grain (file_hit) is genuinely IN BAND but never clears the fire-rate ceiling must NOT
    be reported as "file_hit does not meet the same band" -- that is false; file_hit meets the band,
    it only fails SR-1, and the SR-2 clause must say exactly that (three-way, not band-vs-not-band).

    Fixture: served_syms(row_i) = i for i = 1..92 (one row per distinct repo).
      func_hit: miss for i in [55, 92] (38 misses, matching the default fingerprint), hit for i in
      [1, 54] (54 hits) -- no hit ever has served_syms >= 55, so a threshold in [55, 92] never false-
      warns; t=73 catches the top 20 misses (i in [73, 92]): recall = 20/38 ~= 0.526 >= 0.50,
      false_warn = 0 <= 0.20, warn_rate = 20/92 ~= 0.217 <= 0.25 -- func_hit reaches a real, safe PASS.

      file_hit: miss for i in [43, 92] (50 misses), hit for i in [1, 42] (42 hits) -- again no hit
      ever has served_syms >= 43. Catching >= 25 of the 50 misses (recall >= 0.5) requires a threshold
      t <= 68 (i in [68, 92] is exactly the top 25), so warn_rate is AT BEST 25/92 ~= 0.2717 > 0.25 at
      every band-satisfying threshold (fewer misses caught never reaches recall 0.5; more misses
      caught only raises warn_rate further; hits never subtract from the count since none are ever
      caught in this range) -- band_met is True for file_hit, but sr1_met is False for EVERY t, by
      construction, not by search."""
    rows = ( [ mkrow( "func-miss/%d" % i, i, file_hit=( i <= 42 ), func_hit=False ) for i in range( 55, 93 ) ]
            + [ mkrow( "func-hit-file-miss/%d" % i, i, file_hit=False, func_hit=True )
               for i in range( 43, 55 ) ]
            + [ mkrow( "both-hit/%d" % i, i, file_hit=True, func_hit=True ) for i in range( 1, 43 ) ] )
    assert len( rows ) == 92
    file_misses = sum( 1 for r in rows if not r["file_hit"] )
    func_misses = sum( 1 for r in rows if not r["func_hit"] )
    assert file_misses == 50 and func_misses == 38, ( file_misses, func_misses )

    out = S.score_served_syms( synthetic_summary(), rows )
    assert out["outcome"] == "pass", out                     # func_hit (the gating grain) really passes

    file_sweep = out["grains"]["file_hit"]["sweep"]
    assert any( r["band"] for r in file_sweep ), "file_hit must reach the band somewhere (t<=68)"
    assert not any( r["safe"] for r in file_sweep ), "file_hit must NEVER clear band+SR-1 together"

    gh = out["grain_honesty"]
    assert gh["other_grain"] == "file_hit"
    assert gh["other_band"] is True
    assert gh["other_safe"] is False

    sentence = out["public_sentence"]
    assert "meets the band but only above the 25% fire-rate ceiling" in sentence, sentence
    assert "file_hit does not meet the band" not in sentence     # MEDIUM-4's exact false claim
    assert "does not meet the same band" not in sentence         # the retired (ambiguous) phrasing


# ── R-MARGIN (§5.5) — the generalised direction/statistic primitives, and score_margin_bp() ──────────
def test_sweep_direction_ge_default_matches_original_sweep():
    """The generalisation must not change served_syms's own table: `sweep(labels, values)` (the
    original, still-exported name) must equal `S._sweep_dir(labels, values, "ge")` (the new internal
    engine's "ge" path) EXACTLY, on the same fixture `test_sweep_candidate_set_and_boundary_rows`
    already uses -- proof that generalising for margin_bp did not perturb served_syms's own numbers."""
    labels = [ True, True, False, False, False ]
    values = [ 10, 12, 3, 4, 5 ]
    assert S.sweep( labels, values ) == S._sweep_dir( labels, values, "ge" )


def test_confusion_le_hand_computed():
    """`_confusion_le`'s rule is `warn(row) <=> value(row) <= t` -- the mirror image of
    `_confusion_ge`'s hand-computed fixture (`test_confusion_ge_hand_computed`), but flipped: here
    the LOW values are the misses (labels[0:2] = True on values 3, 4), so a LOW threshold catches
    them, matching §5.5's actual margin_bp orientation (small margin = more miss evidence)."""
    labels = [ True, True, False, False, False ]
    values = [ 3, 4, 10, 11, 12 ]
    # t=4: warn iff value<=4 -> warns {3,4} (both misses, tp=2,fn=0) and no hit (fp=0,tn=3)
    assert S._confusion_le( labels, values, 4 ) == ( 2, 0, 0, 3 )
    # t=2: warn on nobody -> both misses missed (fn=2), no hit false-warned
    assert S._confusion_le( labels, values, 2 ) == ( 0, 2, 0, 3 )
    # t=12: warn on everybody -> every hit false-warned (fp=3)
    assert S._confusion_le( labels, values, 12 ) == ( 2, 0, 3, 0 )


def test_confusion_dir_dispatch_and_rejects_bad_direction():
    labels, values, t = [ True, False ], [ 5, 10 ], 7
    assert S._confusion_dir( labels, values, t, "ge" ) == S._confusion_ge( labels, values, t )
    assert S._confusion_dir( labels, values, t, "le" ) == S._confusion_le( labels, values, t )
    try:
        S._confusion_dir( labels, values, t, "sideways" )
        assert False, "expected ValueError for an invalid direction"
    except ValueError:
        pass


def test_sweep_dir_le_candidate_set_and_boundary_rows():
    """The "le" mirror of test_sweep_candidate_set_and_boundary_rows: the "warn on nobody" sentinel
    sits BELOW the minimum (min(values)-1), not above the maximum, because "le" warns on the LOW side."""
    labels = [ True, True, False, False, False ]
    values = [ 3, 5, 10, 11, 12 ]
    table = S._sweep_dir( labels, values, "le" )
    thresholds = [ r["threshold"] for r in table ]
    assert thresholds == [ 2, 3, 5, 10, 11, 12 ], thresholds   # {min-1} ∪ distinct(values), sorted

    nobody = next( r for r in table if r["threshold"] == 2 )
    assert nobody["recall"] == 0.0 and nobody["false_warn"] == 0.0 and nobody["warn_rate"] == 0.0

    everybody = next( r for r in table if r["threshold"] == 12 )
    assert everybody["recall"] == 1.0 and everybody["false_warn"] == 1.0 and everybody["warn_rate"] == 1.0

    mid = next( r for r in table if r["threshold"] == 5 )      # catches both misses (3,5), no hit
    assert mid["recall"] == 1.0 and mid["false_warn"] == 0.0
    assert abs( mid["warn_rate"] - 0.4 ) < 1e-9


def test_le_direction_is_mirror_image_of_ge_direction():
    """THE symmetry proof this whole generalisation rests on: take any "ge" dataset, negate every
    value, and score it under "le" -- the achieved (recall, false_warn, warn_rate) triples at
    corresponding thresholds must be IDENTICAL to the original "ge" table's, because `warn(v) <=> v
    >= t` on `v` is the exact same partition of rows as `warn(v) <=> -v <= -t` on `-v`. This is what
    "only the column differs, the procedure is identical" means, proven rather than asserted: the set
    of (recall, false_warn, warn_rate) triples reachable is the same set either way, not merely
    similar-looking numbers on two different hand-picked fixtures."""
    labels = [ True, True, False, False, False, False, True ]
    values_ge = [ 12, 9, 2, 3, 5, 1, 20 ]
    table_ge = S._sweep_dir( labels, values_ge, "ge" )
    triples_ge = sorted( ( r["recall"], r["false_warn"], r["warn_rate"] ) for r in table_ge )

    values_le = [ -v for v in values_ge ]
    table_le = S._sweep_dir( labels, values_le, "le" )
    triples_le = sorted( ( r["recall"], r["false_warn"], r["warn_rate"] ) for r in table_le )

    assert triples_ge == triples_le, ( triples_ge, triples_le )
    # and the threshold correspondence is exact too: t_le == -t_ge for the matching triple.
    by_triple_ge = { ( r["recall"], r["false_warn"], r["warn_rate"] ): r["threshold"] for r in table_ge }
    for r in table_le:
        key = ( r["recall"], r["false_warn"], r["warn_rate"] )
        assert r["threshold"] == -by_triple_ge[key], ( r["threshold"], by_triple_ge[key] )


def test_choose_operating_point_tie_rule_le_prefers_smaller_threshold():
    """The "le" mirror of test_choose_operating_point_tie_rule_prefers_larger_threshold: on a recall
    tie, the SMALLER threshold is more conservative (fewer false-warnings) under "warn iff value<=t",
    so it must win -- the opposite side from the "ge" rule, same underlying principle."""
    table = [
        dict( threshold=8, recall=0.6, false_warn=0.10, warn_rate=0.20, tp=3, fn=2, fp=1, tn=9 ),
        dict( threshold=5, recall=0.6, false_warn=0.05, warn_rate=0.15, tp=3, fn=2, fp=1, tn=9 ),
        dict( threshold=20, recall=0.9, false_warn=0.50, warn_rate=0.60, tp=4, fn=1, fp=6, tn=4 ),  # out of band
    ]
    op = S.choose_operating_point( table, n_rows=15, direction="le" )
    assert op["chosen"] is not None and op["chosen"]["threshold"] == 5


def test_choose_operating_point_rejects_bad_direction():
    try:
        S.choose_operating_point( [], n_rows=0, direction="up" )
        assert False, "expected ValueError"
    except ValueError:
        pass


def _clean_margin_rows( n_miss_repos=6, n_hit_repos=6, miss_bp=100, hit_bp=9000 ):
    """§5.5's rows: SMALL margin_bp is more miss evidence (the opposite sense from served_syms), so
    miss rows get the LOW basis-point values here and hit rows the HIGH ones -- deliberately mirrored
    from `_clean_rows` above, not a copy-paste of the same direction under a different name."""
    rows = []
    for i in range( n_miss_repos ):
        rows += [ mkrow_margin( "miss-repo-%d" % i, bp, file_hit=False, func_hit=False )
                 for bp in ( miss_bp + i, miss_bp + i + 1 ) ]
    for i in range( n_hit_repos ):
        rows += [ mkrow_margin( "hit-repo-%d" % i, bp, file_hit=True, func_hit=True )
                 for bp in ( hit_bp + i, hit_bp + i + 1 ) ]
    return rows


def test_score_margin_bp_end_to_end_pass():
    rows = _clean_margin_rows( n_miss_repos=6, n_hit_repos=40 )
    assert len( rows ) == 92
    out = S.score_margin_bp( synthetic_summary(), rows )
    assert out["outcome"] == "pass", out
    assert out["pass"] is True
    assert out["statistic"] == "margin_bp" and out["direction"] == "le"
    assert out["lane_fate"] == "eligible for review and landing"
    assert "0.579" in out["public_sentence"] and "0.604" in out["public_sentence"]
    assert "warn iff margin_bp <= t" in out["public_sentence"]
    assert "eligible for review and landing" in out["public_sentence"]


def test_score_margin_bp_end_to_end_fail_on_no_signal():
    rows = ( [ mkrow_margin( "r/%d" % i, 500, file_hit=( i % 2 == 0 ), func_hit=( i % 2 == 0 ) )
              for i in range( 46 ) ]
            + [ mkrow_margin( "s/%d" % i, 500, file_hit=( i % 2 == 0 ), func_hit=( i % 2 == 0 ) )
               for i in range( 46 ) ] )
    out = S.score_margin_bp( synthetic_summary( n=len( rows ) ), rows )
    assert out["outcome"] == "fail", out
    assert out["pass"] is False
    assert out["lane_fate"] == "CLOSED"
    assert "does not reach the band" in out["public_sentence"]
    assert "CLOSED" in out["public_sentence"]
    assert "deriveForConfidence zeroes margin_pct on hitCeiling" in out["public_sentence"]


def test_score_margin_bp_end_to_end_pass_fire_rate_rejected():
    # mirror of test_score_served_syms_end_to_end_pass_fire_rate_rejected, direction flipped: the
    # "wide net" value is now the SAME LOW number for most misses+some hits (warn iff <= 30 catches
    # both), forcing warn_rate over the 0.25 ceiling at the only band-satisfying threshold.
    rows = ( [ mkrow_margin( "m/%d" % i, 30 if i < 24 else 9000, file_hit=False, func_hit=False )
              for i in range( 38 ) ]
            + [ mkrow_margin( "h/%d" % i, 30 if i < 6 else 9000, file_hit=True, func_hit=True )
               for i in range( 54 ) ] )
    assert len( rows ) == 92
    out = S.score_margin_bp( synthetic_summary(), rows )
    assert out["outcome"] == "pass_fire_rate_rejected", out
    assert out["pass"] is False
    assert out["band_met"] is True
    assert out["sr1_met"] is False
    assert out["lane_fate"] == "CLOSED"
    assert out["best_band_only_threshold"]["threshold"] == 30
    assert "above the 25% fire-rate ceiling" in out["public_sentence"]
    assert "not a PASS" in out["public_sentence"]
    assert "CLOSED" in out["public_sentence"]


def test_score_margin_bp_reports_fingerprint_mismatch():
    bad_summary = synthetic_summary( n=91 )    # wrong population size
    out = S.score_margin_bp( bad_summary, _clean_margin_rows()[:91] )
    assert out["outcome"] == "fingerprint_mismatch"
    assert "public_sentence" in out
    assert "band_met" not in out         # nothing about discrimination may be asserted (§5.4.6 table)


TESTS = [
    test_fingerprint_matches,
    test_fingerprint_rejects_wrong_split,
    test_fingerprint_rejects_auroc_outside_tolerance,
    test_fingerprint_tolerates_rounding_noise,
    test_fingerprint_accepts_published_4dp_figures_and_their_exact_lattice_points,
    test_fingerprint_rejects_lattice_points_two_steps_out,
    test_score_served_syms_reports_fingerprint_mismatch_and_nothing_else,
    test_check_fingerprint_rows_len_check_is_optional_but_enforced_when_given,
    test_score_served_syms_catches_row_count_mismatch_via_fingerprint,
    test_confusion_ge_hand_computed,
    test_confusion_ge_validates_integer_inputs,
    test_sweep_candidate_set_and_boundary_rows,
    test_choose_operating_point_applies_fire_rate_self_reject,
    test_choose_operating_point_band_met_but_sr1_rejected,
    test_choose_operating_point_tie_rule_prefers_larger_threshold,
    test_choose_operating_point_none_when_nothing_qualifies,
    test_auroc_band_5_2_rungs,
    test_directional_refutation_never_flips_to_a_pass,
    test_orientation_direction_matters_for_auroc,
    test_bootstrap_auroc_ci_is_deterministic_and_sane,
    test_bootstrap_operating_point_ci_matches_point_estimate_math,
    test_score_served_syms_end_to_end_pass,
    test_score_served_syms_end_to_end_fail_on_no_signal,
    test_score_served_syms_end_to_end_pass_fire_rate_rejected,
    test_score_served_syms_pass_sentence_reports_other_grain_band_vs_safe_separately,
    test_sweep_direction_ge_default_matches_original_sweep,
    test_confusion_le_hand_computed,
    test_confusion_dir_dispatch_and_rejects_bad_direction,
    test_sweep_dir_le_candidate_set_and_boundary_rows,
    test_le_direction_is_mirror_image_of_ge_direction,
    test_choose_operating_point_tie_rule_le_prefers_smaller_threshold,
    test_choose_operating_point_rejects_bad_direction,
    test_score_margin_bp_end_to_end_pass,
    test_score_margin_bp_end_to_end_fail_on_no_signal,
    test_score_margin_bp_end_to_end_pass_fire_rate_rejected,
    test_score_margin_bp_reports_fingerprint_mismatch,
]


def main():
    failures = []
    for t in TESTS:
        try:
            t()
            print( "PASS  %s" % t.__name__ )
        except AssertionError as e:
            failures.append( t.__name__ )
            print( "FAIL  %s: %s" % ( t.__name__, e ) )
    print( "\n%d/%d passed" % ( len( TESTS ) - len( failures ), len( TESTS ) ) )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit( main() )
