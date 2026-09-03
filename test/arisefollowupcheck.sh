#!/usr/bin/env bash
# arisefollowupcheck.sh -- the ARISE head-to-head follow-up-call counter's contract
# (bench/arise-h2h/followup_calls.py).
#
# WHY THIS GATE EXISTS. docs/EVALS.md's "Owed ... follow-up-call-count column" paragraph names the
# ARISE fault-localization head-to-head (docs/EVALS.md § "ARISE fault-localization head-to-head") as
# one of the two places the column is owed. That round is registered PRE-REGISTERED 2026-08-31 and
# is blocked at the LM boundary (no model endpoint/API key at registration time, per its own text) --
# no arm has ever run an instance, so NO real SWE-agent trajectory exists anywhere in this worktree.
# ARISE's evaluation/parse_preds.py + run_eval.py are imported byte-unmodified (the round's own rule)
# and are not this repo's code to edit, so the counter lives as a standalone companion script that
# reads a SWE-agent trajectory (.traj) JSON -- the public schema every arm's harness already writes,
# unchanged by anything here -- and counts steps whose action invokes one of the nine registered
# rw_* shims (bench/arise-h2h/swe_agent_bundle_ripwire/bin/).
#
# Three rules, mirrored from the agentloop-side counter (test/agentloopfollowupcheck.sh) for the
# same reasons:
#   1. follow-ups = max(calls - 1, 0) -- the first call is not a follow-up.
#   2. FLOOR. A trajectory whose info.exit_status != "submitted" (early_exit / error / timeout / ...)
#      cannot prove every action before the cutoff was captured; its count is a minimum, not a total.
#   3. ABSENT. With no --traj given, the script must say so explicitly for all three arms -- never a
#      silent zero-row table -- because the registration's own text is why no file exists yet.
#
# Since no real ARISE transcript exists locally, this gate exercises ONLY the synthetic fixture
# (--self-test, whose header documents it as a mirror of the public SWE-agent trajectory schema, not
# a captured real run) plus the explicit no-file disclosure path.
#
# Usage: bash test/arisefollowupcheck.sh   (no BIN needed -- this exercises Python only)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
SCRIPT="$ROOT/bench/arise-h2h/followup_calls.py"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { echo "arisefollowupcheck: python3 required"; exit 2; }
[ -f "$SCRIPT" ] || { echo "arisefollowupcheck: no script at $SCRIPT"; exit 2; }

# ── (1) the script's own self-test: calls/follow-ups math, floor marking on a non-"submitted" exit ──
selfOut="$( python3 "$SCRIPT" --self-test 2>&1 )"; selfRc=$?
if [ "$selfRc" = 0 ] && printf '%s' "$selfOut" | grep -q 'SELF-TEST PASS'; then
    ok "(1) followup_calls.py --self-test passes its own fixture assertions"
else
    no "(1) followup_calls.py --self-test failed (rc=$selfRc)"
    printf '%s\n' "$selfOut" | sed 's/^/    | /'
fi

# ── (2) no local ARISE h2h transcript -- must disclose ABSENT for all three arms, never a silent
#        zero-row table, and must exit 0 (an accurate absence report is not a script failure) ───────
noneOut="$( python3 "$SCRIPT" 2>&1 )"; noneRc=$?
if [ "$noneRc" = 0 ] \
   && printf '%s' "$noneOut" | grep -qi 'no local ARISE' \
   && printf '%s' "$noneOut" | grep -q 'vanilla' \
   && printf '%s' "$noneOut" | grep -q 'arise_full' \
   && printf '%s' "$noneOut" | grep -q 'ripwire_bundle'; then
    ok "(2) with no --traj, all three registered arms (vanilla/arise_full/ripwire_bundle) are named absent"
else
    no "(2) missing-transcript disclosure did not name all three arms cleanly (rc=$noneRc)"
    printf '%s\n' "$noneOut" | sed 's/^/    | /'
fi

# ── (3) a real trajectory file, once one exists, must be refused if it is not SWE-agent-shaped ──────
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo '{"not_a_trajectory": true}' > "$TMP/bad.traj"
badOut="$( python3 "$SCRIPT" --traj "$TMP/bad.traj" 2>&1 )"; badRc=$?
if [ "$badRc" != 0 ] && printf '%s' "$badOut" | grep -qi 'trajectory'; then
    ok "(3) a non-trajectory-shaped file is refused, naming the mismatch"
else
    no "(3) a malformed .traj file was not refused (rc=$badRc): $badOut"
fi

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
