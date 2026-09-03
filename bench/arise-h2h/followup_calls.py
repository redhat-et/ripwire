#!/usr/bin/env python3
# followup_calls.py -- the ARISE head-to-head half of the follow-up-call-count column owed in
# docs/EVALS.md ("Owed, registered 2026-09-03, not yet measured: a follow-up-call-count column").
# Sibling of bench/agentloop/followup_calls.py; same definitions, different transcript shape.
#
# WHY THIS FILE EXISTS RATHER THAN A PATCH TO ARISE'S OWN SCORER. docs/EVALS.md's ARISE
# registration is explicit that evaluation/run_eval.py + parse_preds.py are imported BYTE-UNMODIFIED
# -- they are not this repo's code, and the round's own rule forbids editing them. The trajectory
# their SWE-agent harness writes for every run (one .traj JSON per instance: {"trajectory": [...],
# "info": {"exit_status": ..., ...}}, the public SWE-agent schema -- see
# https://github.com/SWE-agent/SWE-agent) already records every tool call verbatim as each step's
# `action` string, so counting rw_* invocations needs no change to their scorer at all: this script
# reads the SAME artifact from the outside, the same posture bench/arb/run_arb.py takes toward the
# Agent Retrieval Bench's own scorer.
#
# STATUS: no arm of the ARISE head-to-head has run an instance (docs/EVALS.md: "blocked at the LM
# boundary" -- no model endpoint/API key at registration time), so no real .traj file exists
# anywhere in this worktree for any of the three arms. This script is therefore exercised here only
# against a synthetic fixture (--self-test) that MIRRORS the public SWE-agent trajectory schema --
# never a captured real run, because none exists. With no --traj argument it prints the honest
# absence for all three registered arms rather than a silent zero-row table.
#
# DEFINITIONS -- identical to the agentloop-side script, restated for the trajectory shape:
#   calls      = the number of trajectory steps whose `action` invokes one of the nine registered
#                rw_* shims (bench/arise-h2h/swe_agent_bundle_ripwire/bin/), matched as the action's
#                leading word so "rw_for ..." counts and "rw_for_extra_thing ..." (a name that merely
#                starts with a registered shim's name) does not.
#   follow-ups = max(calls - 1, 0). The first call is the initial retrieval attempt.
#   FLOOR      = a trajectory whose info.exit_status != "submitted" (early_exit / error / any
#                non-clean stop). A run that did not finish cleanly cannot prove every action before
#                the cutoff is present in the recorded trajectory, so its count is a minimum.
#   ABSENT     = no .traj file exists for that arm/instance. Never coerced to 0 or omitted silently;
#                the missing-transcript path names every registered arm explicitly.
#
# ARM NAMES (registered in docs/EVALS.md's ARISE section): vanilla (SWE-agent baseline),
# arise_full (their bundle), ripwire_bundle (arm c, this repo's shim bundle).
#
# USAGE
#   python3 bench/arise-h2h/followup_calls.py --self-test
#   python3 bench/arise-h2h/followup_calls.py --traj path/to/instance.traj.json   # once one exists
import argparse, json, pathlib, sys

ARMS = ( "vanilla", "arise_full", "ripwire_bundle" )
RW_TOOLS = ( "rw_for", "rw_at", "rw_expand", "rw_callers", "rw_callees", "rw_impact",
             "rw_slice", "rw_pack_task", "rw_from_trace" )

def action_tool_name( action ):
    """The leading whitespace-delimited word of a trajectory step's action string, or "" for a
    blank/whitespace-only action. Matched as a whole leading word so a shim name is never confused
    with a longer command that merely starts with the same prefix."""
    if not action:
        return ""
    return str( action ).strip().split( None, 1 )[ 0 ] if str( action ).strip() else ""

def count_calls( trajectory ):
    return sum( 1 for step in trajectory if action_tool_name( step.get( "action" ) ) in RW_TOOLS )

def load_trajectory( path ):
    data = json.loads( pathlib.Path( path ).read_text() )
    if not isinstance( data, dict ) or "trajectory" not in data:
        raise SystemExit( f"{path}: not a SWE-agent trajectory (.traj) file -- expected a top-level "
                          f"\"trajectory\" list; refusing" )
    trajectory = data[ "trajectory" ]
    if not isinstance( trajectory, list ):
        raise SystemExit( f"{path}: \"trajectory\" is not a list -- malformed .traj file; refusing" )
    exit_status = ( data.get( "info" ) or {} ).get( "exit_status" )
    return trajectory, exit_status

def analyze_one( path ):
    trajectory, exit_status = load_trajectory( path )
    calls = count_calls( trajectory )
    return dict( calls=calls, followups=max( calls - 1, 0 ),
                is_floor=( exit_status != "submitted" ), exit_status=exit_status )

def print_report_one( path, result ):
    floor_tag = " (FLOOR -- exit_status=%r, count may be incomplete)" % result[ "exit_status" ] \
                if result[ "is_floor" ] else ""
    print( f"{path}: calls={result['calls']} follow-ups={result['followups']}{floor_tag}" )

def print_absence_report():
    print( "ARISE fault-localization head-to-head: no local ARISE transcripts for any arm." )
    print( "Per docs/EVALS.md's ARISE registration, every arm is blocked at the LM boundary (no model" )
    print( "endpoint/API key at registration time) -- no instance has run, so no .traj file exists." )
    print( "follow-up-call-count is ABSENT, not zero, for all three registered arms:" )
    for arm in ARMS:
        print( f"  | {arm} | n=0 | absent (no local transcript) |" )

# ── self-test: a synthetic fixture mirroring the public SWE-agent .traj schema (a top-level
# "trajectory" list of {action, observation, ...} steps plus an "info": {"exit_status": ...} dict) --
# never a real captured run, since none exists locally. Covers a clean multi-call trajectory (floor
# must be False) and an early-exit trajectory (floor must be True). ─────────────────────────────────
def _step( action ):
    return dict( action=action, observation="", response="", thought="", state={} )

def synthetic_clean_trajectory():
    # Stage 1 (navigate) then stage 2 (analyze) then the LOCATIONS submission -- 4 rw_* calls total,
    # one non-ripwire shell command mixed in (must NOT be counted), submitted cleanly.
    return dict(
        trajectory=[
            _step( "rw_for /repo failing test assertion" ),
            _step( "ls /repo/src" ),
            _step( "rw_expand /repo some_function" ),
            _step( "rw_callers /repo some_function" ),
            _step( "rw_at /repo src/mod.py 42" ),
            _step( "echo 'LOCATIONS\\nsrc/mod.py some_function 42\\nEND_LOCATIONS'" ),
        ],
        info=dict( exit_status="submitted" ),
    )

def synthetic_early_exit_trajectory():
    # Hit the step/turn cap before ever emitting LOCATIONS -- 9 rw_* calls recorded, but the harness
    # cut the episode off, so the true count could be higher; must be marked a FLOOR.
    return dict(
        trajectory=[ _step( "rw_for /repo query %d" % i ) for i in range( 9 ) ],
        info=dict( exit_status="early_exit" ),
    )

def self_test():
    failures = []
    clean = synthetic_clean_trajectory()
    calls = count_calls( clean[ "trajectory" ] )
    if calls != 4:
        failures.append( f"clean trajectory: expected 4 rw_* calls, got {calls}" )
    followups = max( calls - 1, 0 )
    if followups != 3:
        failures.append( f"clean trajectory: expected 3 follow-ups, got {followups}" )
    is_floor_clean = clean[ "info" ][ "exit_status" ] != "submitted"
    if is_floor_clean:
        failures.append( "clean trajectory (exit_status=submitted): must NOT be marked a floor" )

    early = synthetic_early_exit_trajectory()
    calls_early = count_calls( early[ "trajectory" ] )
    if calls_early != 9:
        failures.append( f"early-exit trajectory: expected 9 rw_* calls, got {calls_early}" )
    is_floor_early = early[ "info" ][ "exit_status" ] != "submitted"
    if not is_floor_early:
        failures.append( "early-exit trajectory (exit_status=early_exit): MUST be marked a floor" )

    # a non-rw_* shell command anywhere must never be counted, including one whose text merely
    # contains an rw_* substring mid-argument (only the leading word of `action` counts).
    mixed = dict( trajectory=[
        _step( "grep -rn rw_for /repo/README.md" ),   # mentions rw_for, does not INVOKE it
        _step( "rw_for /repo real query" ),            # this one does
    ], info=dict( exit_status="submitted" ) )
    calls_mixed = count_calls( mixed[ "trajectory" ] )
    if calls_mixed != 1:
        failures.append( f"mixed trajectory: expected exactly 1 real rw_for call (grep-mention must "
                          f"not count), got {calls_mixed}" )

    print( "self-test fixture (clean):      calls=%d follow-ups=%d floor=%s" % ( calls, followups, is_floor_clean ) )
    print( "self-test fixture (early-exit):  calls=%d follow-ups=%d floor=%s" %
          ( calls_early, max( calls_early - 1, 0 ), is_floor_early ) )
    print( "self-test fixture (mixed-text):  calls=%d (grep-mention excluded)" % calls_mixed )

    if failures:
        print( "\nSELF-TEST FAIL:" )
        for f in failures: print( f"  - {f}" )
        return 1
    print( "\nSELF-TEST PASS: rw_* action counting, follow-up math, and floor marking all check out." )
    return 0

def main():
    ap = argparse.ArgumentParser( description=__doc__.split( "\n\n" )[ 0 ] if __doc__ else "" )
    ap.add_argument( "--traj", default="", help="a SWE-agent .traj JSON file for one instance" )
    ap.add_argument( "--self-test", action="store_true", help="run the synthetic-fixture self-test; no --traj needed" )
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.traj:
        print_absence_report()
        return 0
    result = analyze_one( a.traj )
    print_report_one( a.traj, result )
    return 0

if __name__ == "__main__":
    sys.exit( main() )
