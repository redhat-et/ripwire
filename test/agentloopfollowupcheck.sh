#!/usr/bin/env bash
# agentloopfollowupcheck.sh -- the follow-up-call-count column's contract (bench/agentloop/followup_calls.py).
#
# WHY THIS GATE EXISTS. docs/EVALS.md registers a follow-up-call-count column (arXiv:2608.16370:
# completion can hold flat while retrieval calls rise) whose three rules are load-bearing and easy to
# get quietly wrong in a rewrite:
#   1. follow-ups = max(calls - 1, 0), never calls itself -- the FIRST call is not a follow-up.
#   2. FLOOR. A record whose status != "ok" cannot prove its shim/transcript parse saw every call
#      before the run stopped; its count must be marked a floor, never presented as a total.
#   3. ABSENT. A record whose ripwire_calls is None (unmeasured, e.g. pre-2026-08-22 claude harness
#      runs) must be excluded from every mean/median and counted separately -- never coerced to 0,
#      which would read as "never used the tool" and invert the finding.
#
# This gate runs the script's own --self-test (asserts all three against a fixture that mirrors
# pilot-6run.json's real record shape) and then cross-checks the REAL committed results file
# (bench/agentloop/results/pilot-6run.json) end to end against hand-derived expected numbers, so a
# schema-shape regression that --self-test's synthetic fixture wouldn't catch still fails here.
#
# Usage: bash test/agentloopfollowupcheck.sh   (no BIN needed -- this exercises Python only)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
SCRIPT="$ROOT/bench/agentloop/followup_calls.py"
REAL="$ROOT/bench/agentloop/results/pilot-6run.json"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { echo "agentloopfollowupcheck: python3 required"; exit 2; }
[ -f "$SCRIPT" ] || { echo "agentloopfollowupcheck: no script at $SCRIPT"; exit 2; }
[ -f "$REAL" ]   || { echo "agentloopfollowupcheck: no real results file at $REAL"; exit 2; }

# ── (1) the script's own self-test: calls/follow-ups math, floor marking, absent exclusion ─────────
selfOut="$( python3 "$SCRIPT" --self-test 2>&1 )"; selfRc=$?
if [ "$selfRc" = 0 ] && printf '%s' "$selfOut" | grep -q 'SELF-TEST PASS'; then
    ok "(1) followup_calls.py --self-test passes its own fixture assertions"
else
    no "(1) followup_calls.py --self-test failed (rc=$selfRc)"
    printf '%s\n' "$selfOut" | sed 's/^/    | /'
fi

# ── (2) refuses a results file with the wrong schema (fail-closed, never guesses) ───────────────────
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo '{"schema":"not-an-agentloop-schema","records":[]}' > "$TMP/bad.json"
badOut="$( python3 "$SCRIPT" --results "$TMP/bad.json" 2>&1 )"; badRc=$?
if [ "$badRc" != 0 ] && printf '%s' "$badOut" | grep -q 'unexpected schema'; then
    ok "(2) a non-agentloop schema is refused, naming the mismatch"
else
    no "(2) a bad-schema file was not refused (rc=$badRc): $badOut"
fi

# ── (3) the REAL committed pilot-6run.json parses end to end and matches hand-derived numbers ───────
# pilot-6run.json (schema v2, codex harness, 3 instances x 2 arms): baseline ripwire_calls is 0/0/0
# on every record (the clean control the round reports in EVALS §3b); ripwire_cli is 5/2/6, all
# status="ok" -- so calls mean = 13/3, median = 5; follow-ups 4/1/5 -> mean = 10/3, median = 4. No
# floor, no absent: this file predates neither hazard.
realOut="$( python3 "$SCRIPT" --results "$REAL" 2>&1 )"; realRc=$?
if [ "$realRc" != 0 ]; then
    no "(3) followup_calls.py --results $REAL exited $realRc"
    printf '%s\n' "$realOut" | sed 's/^/    | /'
else
    baseRow="$( printf '%s\n' "$realOut" | grep '| baseline |' )"
    ctxRow="$(  printf '%s\n' "$realOut" | grep '| ripwire_cli |' )"
    printf '%s' "$baseRow" | grep -q '| 3 | 3 | 0 | 0 | 0.00 | 0.00 | 0.00 | 0.00 |' \
        && ok "(3) baseline row: n=3 measured=3 absent=0 floor=0 calls=0.00/0.00 followups=0.00/0.00" \
        || no "(3) baseline row mismatch: $baseRow"
    printf '%s' "$ctxRow" | grep -q '| 3 | 3 | 0 | 0 | 4.33 | 5.00 | 3.33 | 4.00 |' \
        && ok "(3) ripwire_cli row: n=3 measured=3 absent=0 floor=0 calls=4.33/5.00 followups=3.33/4.00" \
        || no "(3) ripwire_cli row mismatch: $ctxRow"
fi

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
