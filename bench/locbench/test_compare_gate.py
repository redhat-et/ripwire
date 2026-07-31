#!/usr/bin/env python3
"""
Unit tests for bench/locbench/compare_runs.py's acceptance gate — both the legacy flat-AND predicate
(byte-identity guard) and the new opt-in --gate=two-tier mode (Phase B1, see GATE_DECISION.md).

Pure Python, no network, no pytest dependency (none is vendored in this repo — see PLAN_researchImprove2026.md
Phase B1 task notes). Runs as a plain script:

    python3 bench/locbench/test_compare_gate.py

or, if pytest happens to be installed:

    python3 -m pytest bench/locbench/test_compare_gate.py

Each `test_*` function is a self-contained assert-based case; `main()` runs them all and reports a summary.
"""
import json, os, random, subprocess, sys, tempfile

HERE = os.path.dirname( os.path.abspath( __file__ ) )
COMPARE_RUNS = os.path.join( HERE, "compare_runs.py" )
ARM = "anchor"


# Fixture construction. Deterministic given `seed` (a random.Random seed) — same seed always produces the
# same JSON pair, byte for byte, so golden-capture assertions are stable across machines and reruns.

def build_pair( seed, n_repos, n_per_repo, quality_gain, cost_mult_warm, cost_mult_cold, cost_mult_token,
                 arm=ARM, base_hit_prob=0.4 ):
    rng = random.Random( seed )
    before_rows, after_rows = [], []
    for r in range( n_repos ):
        repo = f"org/repo{r}"
        for k in range( n_per_repo ):
            iid = f"{repo}#{k}"
            primary = [ "src/a.py" ] if k % 5 != 0 else [ "src/a.py", "src/b.py" ]
            gold_funcs = [ "a.py::f" ]
            after_hit_prob = min( 0.95, base_hit_prob + quality_gain )
            before_hit = rng.random() < base_hit_prob
            after_hit = rng.random() < after_hit_prob
            before_rank = rng.randint( 0, 9 ) if before_hit else None
            after_rank = rng.randint( 0, 9 ) if after_hit else None
            base_wall = 0.02 + rng.random() * 0.01
            base_cold = 0.05 + rng.random() * 0.02
            base_tok = 4000 + rng.random() * 1000
            before_rows.append( dict(
                instance_id=iid, repo=repo, gold_files=primary, primary_files=primary, gold_funcs=gold_funcs,
                arms={ arm: dict(
                    file_worst=before_rank, file_first=before_rank, func_first=before_rank,
                    wall_median=round( base_wall, 4 ), wall_p95=round( base_wall * 1.3, 4 ),
                    cold_wall=round( base_cold, 4 ), index_wall=round( base_cold * 0.5, 4 ),
                    output_tokens_ceiling=round( base_tok ),
                ) } ) )
            after_rows.append( dict(
                instance_id=iid, repo=repo, gold_files=primary, primary_files=primary, gold_funcs=gold_funcs,
                arms={ arm: dict(
                    file_worst=after_rank, file_first=after_rank, func_first=after_rank,
                    wall_median=round( base_wall * cost_mult_warm, 4 ), wall_p95=round( base_wall * 1.3 * cost_mult_warm, 4 ),
                    cold_wall=round( base_cold * cost_mult_cold, 4 ), index_wall=round( base_cold * 0.5, 4 ),
                    output_tokens_ceiling=round( base_tok * cost_mult_token ),
                ) } ) )

    def summarize( rows ):
        n = len( rows )
        allf10 = sum( 1 for row in rows if row["arms"][arm]["file_worst"] is not None )
        return { "n": n, "allf10": allf10 }

    def wrap( rows ):
        return dict( dataset="czlll/Loc-Bench_V1", split="test", split_contract="ctxpack-a7-v2",
                     skipped={ "unindexable": 0 }, instances=rows, arms={ arm: summarize( rows ) } )

    return wrap( before_rows ), wrap( after_rows )


def write_json( obj, dirpath, name ):
    path = os.path.join( dirpath, name )
    json.dump( obj, open( path, "w" ) )
    return path


def run_compare( before_path, after_path, extra_args=() ):
    proc = subprocess.run( [ sys.executable, COMPARE_RUNS, before_path, after_path, "--arm", ARM, *extra_args ],
                            capture_output=True, text=True )
    return proc.returncode, proc.stdout, proc.stderr


# Tests

def test_legacy_byte_identity_golden():
    """Default (--gate omitted, i.e. legacy) output must match a fixed golden capture, exactly."""
    with tempfile.TemporaryDirectory() as d:
        before, after = build_pair( seed="golden-legacy-v1", n_repos=20, n_per_repo=6, quality_gain=0.10,
                                     cost_mult_warm=1.01, cost_mult_cold=1.01, cost_mult_token=1.01 )
        bp = write_json( before, d, "before.json" ); ap = write_json( after, d, "after.json" )
        rc, out, err = run_compare( bp, ap )
        golden = (
            "paired corrected LocBench: arm=anchor n=120 repos=20\n"
            "  strict file@10 delta +0.00pp; clustered bootstrap 95% lower -13.33pp\n"
            "  lenient file@10 delta +0.00pp; symbol MRR delta -0.0204\n"
            "  multi-file strict@10 delta -10.00pp (n=40)\n"
            "  warm latency p50 delta +1.0%; p95 delta +1.2%\n"
            "  production payload token ceiling p50 +1.0%; p95 +1.0%\n"
            "  cold p50/p95 +1.0%/+1.1%; index p50/p95 +0.0%/+0.0%\n"
            "  category deltas single strict/lenient +5.00pp/+5.00pp; multi -10.00pp/-10.00pp\n"
            "  all-patch secondary strict@10 delta +0.00pp (zero-primary rows count as failures)\n"
            "REJECT\n"
        )
        assert out == golden, f"legacy output drifted from golden capture:\n--- got ---\n{out}--- want ---\n{golden}"
        assert rc == 0, f"non-enforce run must exit 0 regardless of ACCEPT/REJECT, got {rc}"
        # Same fixture, --gate=legacy passed explicitly, must be byte-identical to gate-omitted output.
        rc2, out2, _ = run_compare( bp, ap, extra_args=[ "--gate", "legacy" ] )
        assert out2 == out and rc2 == rc, "explicit --gate=legacy must be byte-identical to the default"


def test_tier1_absolute_rejection():
    """Big quality win, but candidate's absolute warm/cold p95 exceeds the interactive SLA ceiling -> REJECT,
    even though tier 2's utility ratio alone would pass."""
    with tempfile.TemporaryDirectory() as d:
        before, after = build_pair( seed="tier1-reject-v1", n_repos=20, n_per_repo=6, quality_gain=0.35,
                                     cost_mult_warm=1.02, cost_mult_cold=1.02, cost_mult_token=1.02 )
        bp = write_json( before, d, "before.json" ); ap = write_json( after, d, "after.json" )
        rc, out, err = run_compare( bp, ap, extra_args=[
            "--gate", "two-tier", "--abs-warm-p95-ms", "25", "--abs-cold-p95-ms", "60",
            "--min-quality-per-cost", "1.0" ] )
        assert "tier1 absolute SLA" in out
        assert "FAIL" in out.split( "tier1 absolute SLA" )[1].split( "\n" )[0]
        assert out.strip().endswith( "REJECT" )
        assert rc == 0  # non-enforce


def test_tier2_accept_big_quality_small_cost():
    with tempfile.TemporaryDirectory() as d:
        before, after = build_pair( seed="tier2-accept-v1", n_repos=20, n_per_repo=6, quality_gain=0.35,
                                     cost_mult_warm=1.05, cost_mult_cold=1.02, cost_mult_token=1.05 )
        bp = write_json( before, d, "before.json" ); ap = write_json( after, d, "after.json" )
        rc, out, err = run_compare( bp, ap, extra_args=[
            "--gate", "two-tier", "--abs-warm-p95-ms", "100", "--abs-cold-p95-ms", "200",
            "--min-quality-per-cost", "1.0" ] )
        assert out.strip().endswith( "ACCEPT" ), out
        tier2_line = [ line for line in out.splitlines() if "tier2 utility" in line ][0]
        assert tier2_line.strip().endswith( "PASS" ), tier2_line


def test_tier2_reject_small_quality_big_cost():
    with tempfile.TemporaryDirectory() as d:
        before, after = build_pair( seed="tier2-reject-v1", n_repos=20, n_per_repo=6, quality_gain=0.03,
                                     cost_mult_warm=1.40, cost_mult_cold=1.20, cost_mult_token=1.40 )
        bp = write_json( before, d, "before.json" ); ap = write_json( after, d, "after.json" )
        rc, out, err = run_compare( bp, ap, extra_args=[
            "--gate", "two-tier", "--abs-warm-p95-ms", "100", "--abs-cold-p95-ms", "200",
            "--min-quality-per-cost", "1.0" ] )
        assert out.strip().endswith( "REJECT" ), out
        tier2_line = [ line for line in out.splitlines() if "tier2 utility" in line ][0]
        assert tier2_line.strip().endswith( "FAIL" ), tier2_line


def test_delta_cost_le_zero_auto_accept():
    """Quality up, weighted cost delta <= 0 (cost flat or down) -> tier 2 auto-accepts (reports qpc = inf)
    as long as the quality lower bound is positive; tier 1 must still be satisfied independently."""
    with tempfile.TemporaryDirectory() as d:
        before, after = build_pair( seed="tier2-autoaccept-v1", n_repos=20, n_per_repo=6, quality_gain=0.35,
                                     cost_mult_warm=0.95, cost_mult_cold=0.90, cost_mult_token=0.97 )
        bp = write_json( before, d, "before.json" ); ap = write_json( after, d, "after.json" )
        rc, out, err = run_compare( bp, ap, extra_args=[
            "--gate", "two-tier", "--abs-warm-p95-ms", "100", "--abs-cold-p95-ms", "200",
            # min-quality-per-cost set absurdly high: only the Δcost<=0 auto-accept branch can pass this.
            "--min-quality-per-cost", "1000" ] )
        assert "= inf" in out, out
        assert out.strip().endswith( "ACCEPT" ), out


def test_mismatched_contract_still_refused():
    """The paired-comparison contract checks (dataset/split/split_contract, skipped counts, instance-set
    identity, per-instance repo/gold_files/primary_files/gold_funcs) are unconditional and must still fire
    under --gate=two-tier, before any gate logic runs."""
    with tempfile.TemporaryDirectory() as d:
        before, after = build_pair( seed="mismatch-v1", n_repos=20, n_per_repo=6, quality_gain=0.10,
                                     cost_mult_warm=1.0, cost_mult_cold=1.0, cost_mult_token=1.0 )
        after = dict( after ); after["dataset"] = "some/other-dataset"
        bp = write_json( before, d, "before.json" ); ap = write_json( after, d, "after.json" )
        rc, out, err = run_compare( bp, ap, extra_args=[
            "--gate", "two-tier", "--abs-warm-p95-ms", "100", "--abs-cold-p95-ms", "200",
            "--min-quality-per-cost", "1.0" ] )
        assert rc != 0, ( out, err )
        assert "dataset differs; paired comparison refused" in err, err

        # Also cover a per-instance identity mismatch (gold_files) with the legacy gate.
        before2, after2 = build_pair( seed="mismatch-v2", n_repos=20, n_per_repo=6, quality_gain=0.10,
                                       cost_mult_warm=1.0, cost_mult_cold=1.0, cost_mult_token=1.0 )
        after2 = json.loads( json.dumps( after2 ) )
        after2["instances"][0]["gold_files"] = [ "some/other/file.py" ]
        bp2 = write_json( before2, d, "before2.json" ); ap2 = write_json( after2, d, "after2.json" )
        rc2, out2, err2 = run_compare( bp2, ap2 )
        assert rc2 != 0, ( out2, err2 )
        assert "gold_files differs; paired comparison refused" in err2, err2


def test_missing_two_tier_flags_rejected_before_reading_input():
    """--gate=two-tier without the three required flags must fail fast with a clear message (no silent
    default policy number — those are a proposal pending SPEC review, see GATE_DECISION.md)."""
    rc, out, err = run_compare( "/nonexistent/before.json", "/nonexistent/after.json",
                                 extra_args=[ "--gate", "two-tier" ] )
    assert rc != 0
    assert "requires --abs-warm-p95-ms" in err, err


TESTS = [
    test_legacy_byte_identity_golden,
    test_tier1_absolute_rejection,
    test_tier2_accept_big_quality_small_cost,
    test_tier2_reject_small_quality_big_cost,
    test_delta_cost_le_zero_auto_accept,
    test_mismatched_contract_still_refused,
    test_missing_two_tier_flags_rejected_before_reading_input,
]


def main():
    failures = []
    for t in TESTS:
        try:
            t()
            print( f"PASS  {t.__name__}" )
        except AssertionError as e:
            failures.append( t.__name__ )
            print( f"FAIL  {t.__name__}: {e}" )
    print( f"\n{len(TESTS) - len(failures)}/{len(TESTS)} passed" )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit( main() )
