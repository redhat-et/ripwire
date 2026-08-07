#!/usr/bin/env bash
# r6 expansion grid — frozen cells from bench/locbench/results/r6_expansion/PREREG.md, TRAIN split only.
set -u
REPO=/Users/qgames/AppDevelopLocal/project2/ripwire/.claude/worktrees/integration
ASSETS=/Users/qgames/AppDevelopLocal/project2/bench-assets/r4
cd "$REPO" || exit 2
for cell in 2,1 2,2 2,3 3,1 3,2 3,3 5,1 5,2 5,3; do
    tag="${cell/,/x}"
    out="$ASSETS/results/r6_train_$tag.json"
    [ -f "$out" ] && { echo "skip $cell"; continue; }
    RIPWIRE_EXPAND="$cell" RIPWIRE=$REPO/build/ripwire python3 bench/locbench/run_locbench.py \
        --split=train --max-scored 60 --arms for --n 560 \
        --work-dir "$ASSETS/work" --json-out "$out" > "$ASSETS/logs/r6_$tag.log" 2>&1
    echo "done $cell"
done
