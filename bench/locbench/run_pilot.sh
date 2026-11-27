#!/usr/bin/env bash
# run_pilot.sh — the placebo round's Haiku pilot in one command (bench/locbench/PREREG_PLACEBO.md, stopping rule 1).
#
#   bench/locbench/run_pilot.sh RESULTS_DIR [WORK_DIR]
#
# Run it from a terminal where `claude auth status` says loggedIn=true. It never reads or prints a token: the CLI
# authenticates itself, and the run record names the credential only.
#
# RESULTS_DIR must already hold the pilot's TRAIN seal, made by the $0 no-model step:
#   pilot_ids.txt              agent_loc.py --select-pilot (24 TRAIN ids, repo round-robin)
#   payloads_pilot_train/      run_locbench.py --instances=@pilot_ids.txt --emit-payloads=...
#   pilot_seal_train.json      run_locbench.py --json-out=...  (the scorer's sidecar; it holds gold, never print it)
#
# What it runs: 24 instances x A0/A1/A2/A3 x 1 seed = 96 episodes of claude-haiku-5-5 at effort low. After 12
# episodes it checks the realised usage per episode against the prereg's central estimate and STOPS (exit 3) when
# it is above 2x. Held-out instances are refused by the driver. Re-running resumes: finished episodes are skipped.
set -euo pipefail
ROOT="$( cd "$( dirname "$0" )/../.." && pwd )"
R="${1:?usage: run_pilot.sh RESULTS_DIR [WORK_DIR]}"
W="${2:-$R/work}"
for need in "$R/pilot_ids.txt" "$R/payloads_pilot_train" "$R/pilot_seal_train.json" "$W/datasets"; do
    [ -e "$need" ] || { echo "run_pilot: missing $need (run the \$0 seal step first)"; exit 2; }
done
command -v claude >/dev/null 2>&1 || { echo "run_pilot: no claude CLI on PATH"; exit 2; }
claude auth status 2>/dev/null | grep -q '"loggedIn": true' || { echo "run_pilot: claude CLI is not logged in"; exit 2; }
exec python3 "$ROOT/bench/locbench/agent_loc.py" --work-dir "$W" --payloads "$R/payloads_pilot_train" \
    --seal-json "$R/pilot_seal_train.json" --instances "@$R/pilot_ids.txt" --arms A0,A1,A2,A3 --seeds 1 \
    --model claude-haiku-5-5 --effort low --credential "claude.ai subscription (CLI)" \
    --claude-bin "$( command -v claude )" --cost-check-after 12 --cost-stop-multiple 2 --out "$R/pilot_run"
