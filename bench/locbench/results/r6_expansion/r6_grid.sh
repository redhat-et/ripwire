#!/usr/bin/env bash
# r6 expansion grid — frozen cells from bench/locbench/results/r6_expansion/PREREG.md, TRAIN split only.
#
# REPO/ASSETS: see the same header in ../r5_pooling/r5_grid.sh — absolute home-directory paths here are what
# test/ripwirepubliccheck.sh arm 2 rejects, and did on all four CI legs.
set -u
REPO="${RIPWIRE_REPO:-$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../../.." && pwd )}"
ASSETS="${LOCBENCH_ASSETS:-}"
[ -n "$ASSETS" ] || { echo "set LOCBENCH_ASSETS=<dir> — the scratch tree holding results/, work/ and logs/ (see bench/locbench/README.md)" >&2; exit 2; }
cd "$REPO" || exit 2
mkdir -p "$ASSETS/results" "$ASSETS/logs" || exit 2
for cell in 2,1 2,2 2,3 3,1 3,2 3,3 5,1 5,2 5,3; do
    tag="${cell/,/x}"
    out="$ASSETS/results/r6_train_$tag.json"
    [ -f "$out" ] && { echo "skip $cell"; continue; }
    RIPWIRE_EXPAND="$cell" RIPWIRE=$REPO/build/ripwire python3 bench/locbench/run_locbench.py \
        --split=train --max-scored 60 --arms for --n 560 \
        --work-dir "$ASSETS/work" --json-out "$out" > "$ASSETS/logs/r6_$tag.log" 2>&1
    echo "done $cell"
done
