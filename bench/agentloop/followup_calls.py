#!/usr/bin/env python3
# followup_calls.py -- the follow-up-call-count column owed in docs/EVALS.md ("Owed, registered
# 2026-09-03, not yet measured: a follow-up-call-count column").
#
# WHAT THIS COUNTS. arXiv:2608.16370 found completion can hold flat while retrieval calls rise
# (21.0->63.9 in one of six measured comparisons) -- a tighter --token-budget can defer tokens into
# MORE calls instead of eliminating them, and nothing in this harness's existing metrics
# (tokens_in/out, wall_seconds, resolved, localization_hit) can tell the two apart. This script adds
# that column from data run_agentloop.py ALREADY RECORDS per instance: `ripwire_calls`, the count of
# ripwire invocations the harness's own shim/transcript parser attributed to that run (see
# run_agentloop.py's parse_codex_jsonl_metrics / parse_opencode_ndjson_metrics /
# parse_claude_session_metrics). No new instrumentation, no re-run -- this reads the SAME field
# analyze.py's substitution_rate() reads, from a different angle.
#
# DEFINITIONS (registered in docs/EVALS.md alongside this script).
#   calls      = record["ripwire_calls"]: total ripwire invocations attributed to one
#                (instance_id, arm, seed) run.
#   follow-ups = max(calls - 1, 0): every call after the first. The first call is the initial
#                retrieval attempt; a follow-up is evidence the first answer needed a second (or
#                third, ...) call to complete the task -- the "retrieval calls rose" signal the
#                registration is chasing.
#   FLOOR      = a record whose status != "ok". An aborted/errored/timed-out run cannot guarantee
#                its shim log or transcript parse captured every invocation before it stopped, so its
#                calls/follow-ups number is a minimum, never reported as a total -- CLAUDE.md
#                non-negotiable 3.
#   ABSENT     = a record whose ripwire_calls is None (the harness/date combination never measured
#                it -- e.g. claude-harness runs before 2026-08-22). Excluded from mean/median,
#                counted and disclosed separately, NEVER coerced to 0 (mean_substitution() in
#                analyze.py sets the precedent for this exact posture on the same field).
#
# COLUMN FORMAT (one row per arm): n_records, n_measured, n_absent, n_floor, mean_calls,
# median_calls, mean_followups, median_followups -- printed as a markdown table by print_report();
# analyze_followups() returns the same data as a dict for callers that want it raw.
#
# USAGE
#   python3 bench/agentloop/followup_calls.py --self-test
#   python3 bench/agentloop/followup_calls.py --results bench/agentloop/results/pilot-6run.json
import argparse, json, pathlib, statistics, sys

def median_or_none( xs ):
    return statistics.median( xs ) if xs else None

def mean_or_none( xs ):
    return ( sum( xs ) / len( xs ) ) if xs else None

def followups_for_arm( records, arm ):
    """(n_records, n_absent, n_floor, calls, followups) for one arm's records. calls/followups carry
    only records whose ripwire_calls is not None -- an absent record is counted in n_absent and never
    contributes a fabricated 0 to the lists that feed mean/median."""
    arm_records = [ r for r in records if r.get( "arm" ) == arm ]
    n_absent = n_floor = 0
    calls, followups = [], []
    for r in arm_records:
        c = r.get( "ripwire_calls" )
        if c is None:
            n_absent += 1
            continue
        if r.get( "status" ) != "ok":
            n_floor += 1
        calls.append( c )
        followups.append( max( c - 1, 0 ) )
    return len( arm_records ), n_absent, n_floor, calls, followups

def analyze_followups( records ):
    arms = sorted( { r.get( "arm" ) for r in records if r.get( "arm" ) } )
    out = {}
    for arm in arms:
        n, n_absent, n_floor, calls, followups = followups_for_arm( records, arm )
        out[ arm ] = dict(
            n_records=n, n_absent=n_absent, n_floor=n_floor, n_measured=len( calls ),
            mean_calls=mean_or_none( calls ), median_calls=median_or_none( calls ),
            mean_followups=mean_or_none( followups ), median_followups=median_or_none( followups ),
        )
    return out

def print_report( out ):
    def num( x ):
        return ( "%.2f" % x ) if x is not None else "n/a"
    print( "| arm | n | measured | absent | floor | mean calls | median calls | mean follow-ups | median follow-ups |" )
    print( "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |" )
    for arm in sorted( out ):
        row = out[ arm ]
        floor_tag = f"{row['n_floor']}*" if row[ "n_floor" ] else "0"
        print( f"| {arm} | {row['n_records']} | {row['n_measured']} | {row['n_absent']} | {floor_tag} | "
               f"{num(row['mean_calls'])} | {num(row['median_calls'])} | "
               f"{num(row['mean_followups'])} | {num(row['median_followups'])} |" )
    if any( out[ arm ][ "n_floor" ] for arm in out ):
        print( "\n* floor: at least one record's status != \"ok\" -- its call count is a minimum, not a total." )
    if any( out[ arm ][ "n_absent" ] for arm in out ):
        print( "absent: ripwire_calls was never measured for these records (harness/date gap) -- excluded" )
        print( "from mean/median, never coerced to 0." )

SCHEMA_PREFIX = "ripwire-agentloop-results-"

def load_results( path ):
    data = json.loads( pathlib.Path( path ).read_text() )
    schema = str( data.get( "schema", "" ) )
    if not schema.startswith( SCHEMA_PREFIX ):
        raise SystemExit( f"{path}: unexpected schema {schema!r} -- refusing (not a run_agentloop.py "
                          f"results file)" )
    return data

# ── self-test: a synthetic fixture that mirrors pilot-6run.json's actual record shape (schema
# ripwire-agentloop-results-v2, codex harness, baseline calls=0 / ripwire_cli calls>0 with a matching
# ripwire_commands list), plus the two cases the real committed file does not happen to exercise: a
# non-"ok" status (FLOOR) and an unmeasured ripwire_calls=None (ABSENT) -- both must be proven correct
# before any real number from this script is trusted. ──────────────────────────────────────────────
def _fixture_record( instance_id, arm, status, ripwire_calls, commands ):
    return dict( instance_id=instance_id, repo="fake/repo", base_commit="deadbeef", arm=arm, seed=1,
                harness="fixture", model="fixture", status=status, resolved=None, localization_hit=None,
                tokens_in=1000, tokens_out=100, wall_seconds=10.0, cost_usd=None,
                command_calls=len( commands ) if commands else 0,
                ripwire_calls=ripwire_calls, ripwire_commands=commands, events_path=None, error=None,
                started_unix=0, finished_unix=0 )

def synthetic_fixture():
    return [
        # baseline: never calls ripwire, mirrors pilot-6run.json's baseline rows exactly (calls=0).
        _fixture_record( "F01", "baseline", "ok", 0, [] ),
        _fixture_record( "F02", "baseline", "ok", 0, [] ),
        # ripwire_cli: two clean completed runs, calls=5 and calls=2 -> follow-ups 4 and 1.
        _fixture_record( "F01", "ripwire_cli", "ok", 5, [ "ripwire . --for=a" ] * 5 ),
        _fixture_record( "F02", "ripwire_cli", "ok", 2, [ "ripwire . --for=b" ] * 2 ),
        # ripwire_cli: a run that TIMED OUT after 9 recorded calls -- its count is a FLOOR, the run
        # may have made more calls the parser never saw before the process was killed.
        _fixture_record( "F03", "ripwire_cli", "timeout", 9, [ "ripwire . --for=c" ] * 9 ),
        # ripwire_cli: an UNMEASURED run (pre-2026-08-22 claude harness shape) -- ripwire_calls is
        # None, never a fabricated 0; must land in n_absent, excluded from every mean/median.
        _fixture_record( "F04", "ripwire_cli", "ok", None, None ),
    ]

def self_test():
    records = synthetic_fixture()
    out = analyze_followups( records )
    print_report( out )
    failures = []
    b = out.get( "baseline", {} )
    if b.get( "n_records" ) != 2: failures.append( f"baseline n_records: expected 2, got {b.get('n_records')}" )
    if b.get( "mean_calls" ) != 0.0: failures.append( f"baseline mean_calls: expected 0.0, got {b.get('mean_calls')}" )
    if b.get( "mean_followups" ) != 0.0: failures.append( f"baseline mean_followups: expected 0.0, got {b.get('mean_followups')}" )
    c = out.get( "ripwire_cli", {} )
    if c.get( "n_records" ) != 4: failures.append( f"ripwire_cli n_records: expected 4, got {c.get('n_records')}" )
    if c.get( "n_absent" ) != 1: failures.append( f"ripwire_cli n_absent: expected 1 (F04), got {c.get('n_absent')}" )
    if c.get( "n_floor" ) != 1: failures.append( f"ripwire_cli n_floor: expected 1 (F03 timeout), got {c.get('n_floor')}" )
    if c.get( "n_measured" ) != 3: failures.append( f"ripwire_cli n_measured: expected 3 (F01,F02,F03), got {c.get('n_measured')}" )
    # calls: 5, 2, 9 -> mean 16/3, median 5; followups: 4, 1, 8 -> mean 13/3, median 4
    if c.get( "mean_calls" ) is None or abs( c[ "mean_calls" ] - 16 / 3 ) > 1e-9:
        failures.append( f"ripwire_cli mean_calls: expected {16/3}, got {c.get('mean_calls')}" )
    if c.get( "median_calls" ) != 5: failures.append( f"ripwire_cli median_calls: expected 5, got {c.get('median_calls')}" )
    if c.get( "mean_followups" ) is None or abs( c[ "mean_followups" ] - 13 / 3 ) > 1e-9:
        failures.append( f"ripwire_cli mean_followups: expected {13/3}, got {c.get('mean_followups')}" )
    if c.get( "median_followups" ) != 4: failures.append( f"ripwire_cli median_followups: expected 4, got {c.get('median_followups')}" )
    if failures:
        print( "\nSELF-TEST FAIL:" )
        for f in failures: print( f"  - {f}" )
        return 1
    print( "\nSELF-TEST PASS: calls/follow-ups math, floor marking, and absent exclusion all check out." )
    return 0

def main():
    ap = argparse.ArgumentParser( description=__doc__.split( "\n\n" )[ 0 ] if __doc__ else "" )
    ap.add_argument( "--results", default="", help="run_agentloop.py results JSON (schema=ripwire-agentloop-results-v*)" )
    ap.add_argument( "--self-test", action="store_true", help="run the synthetic-fixture self-test; no --results needed" )
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.results:
        raise SystemExit( "--results PATH is required (or pass --self-test to validate the math on a fixture)" )
    data = load_results( a.results )
    out = analyze_followups( data.get( "records", [] ) )
    print_report( out )
    return 0

if __name__ == "__main__":
    sys.exit( main() )
