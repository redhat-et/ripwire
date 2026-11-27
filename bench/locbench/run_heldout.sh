#!/usr/bin/env bash
# run_heldout.sh — the placebo round's held-out run (bench/locbench/PREREG_PLACEBO.md, ADDENDUM 2026-11-26).
#
#   RIPWIRE=/path/to/pinned/ripwire bench/locbench/run_heldout.sh RESULTS_DIR [WORK_DIR]
#
# Run it from a terminal where `claude auth status` says loggedIn=true. It never reads or prints a token.
# RESULTS_DIR must hold the Stage 0 seal `payloads_s0/` (302 manifests, ripwire-a7-v2 after rule A2).
#
# What it runs: 302 instances x A0/A1/A2/A3 x K=3, plus A2s/A1p x 1 = 4,228 episodes of claude-haiku-5-5 at
# effort low, `--allow-heldout`, UNSCORED at run time (no gold is loaded while a model runs). Stops:
#   exit 3  the 12-episode cost guard (prereg-priced tokens > 2x the central estimate);
#   exit 4  the rolling stop (mean input of the last 50 episodes > 2 x the pilot's 33,525);
#   exit 5  a provider error that survived its one re-run (never counted; re-run this script to resume).
# On a clean finish it grades (the ONLY step that reads gold, into scored.jsonl hit flags) and runs B1-B3.
set -euo pipefail
ROOT="$( cd "$( dirname "$0" )/../.." && pwd )"
R="${1:?usage: run_heldout.sh RESULTS_DIR [WORK_DIR]}"
W="${2:-$R/work}"
OUT="$R/heldout/run"
[ -d "$R/payloads_s0" ] || { echo "run_heldout: missing $R/payloads_s0 (Stage 0 seal)"; exit 2; }
[ -n "${RIPWIRE:-}" ] && [ -x "$RIPWIRE" ] || { echo "run_heldout: set RIPWIRE to the pinned binary (grading needs it)"; exit 2; }
command -v claude >/dev/null 2>&1 || { echo "run_heldout: no claude CLI on PATH"; exit 2; }
claude auth status 2>/dev/null | grep -q '"loggedIn": true' || { echo "run_heldout: claude CLI is not logged in"; exit 2; }
python3 "$ROOT/bench/locbench/agent_loc.py" --work-dir "$W" --payloads "$R/payloads_s0" --allow-heldout \
    --arms A0,A1,A2,A3 --seeds 3 --secondary-arms A2s,A1p --secondary-seeds 1 --workers "${WORKERS:-4}" \
    --model claude-haiku-5-5 --effort low --credential "claude.ai subscription (CLI)" \
    --claude-bin "$( command -v claude )" --cost-check-after 12 --cost-stop-multiple 2 --out "$OUT"
python3 "$ROOT/bench/locbench/agent_loc.py" --work-dir "$W" --grade --out "$OUT"
python3 "$ROOT/bench/locbench/agent_loc.py" --work-dir "$W" --analyze --out "$OUT"
