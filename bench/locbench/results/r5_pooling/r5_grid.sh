#!/usr/bin/env bash
# r5 pooling grid — the frozen cells from bench/locbench/results/r5_pooling/PREREG.md, TRAIN split only.
# The held-out 60 is the published number; it is not touched here.
set -u
REPO=/Users/qgames/AppDevelopLocal/project2/ripwire/.claude/worktrees/integration
ASSETS=/Users/qgames/AppDevelopLocal/project2/bench-assets/r4
cd "$REPO" || exit 2

# blend=0 at any K is the identity control: it MUST reproduce base exactly or no cell may be read.
CELLS="5,0 3,25 3,50 3,100 5,25 5,50 5,100 10,25 10,50 10,100"

for cell in $CELLS; do
    tag="${cell/,/x}"
    out="$ASSETS/results/r5_train_$tag.json"
    [ -f "$out" ] && { echo "skip $cell (done)"; continue; }
    RIPWIRE_POOL="$cell" RIPWIRE=$REPO/build/ripwire python3 bench/locbench/run_locbench.py \
        --split=train --max-scored 60 --arms for --n 560 \
        --work-dir "$ASSETS/work" --json-out "$out" \
        > "$ASSETS/logs/r5_$tag.log" 2>&1
    echo "done $cell"
done
