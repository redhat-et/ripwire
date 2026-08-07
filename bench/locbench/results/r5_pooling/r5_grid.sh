#!/usr/bin/env bash
# r5 pooling grid — the frozen cells from bench/locbench/results/r5_pooling/PREREG.md, TRAIN split only.
# The held-out 60 is the published number; it is not touched here.
#
# REPO is derived from this script's own location; ASSETS must be supplied, because the corpora and the
# cloned repos are deliberately NOT in the tree (bench/locbench/README.md: clones and dataset cache live
# only under --work-dir). Both used to be absolute paths into the author's home directory, which is the
# leak test/ripwirepubliccheck.sh arm 2 exists to catch — it went red on all four CI legs.
set -u
REPO="${RIPWIRE_REPO:-$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../../.." && pwd )}"
ASSETS="${LOCBENCH_ASSETS:-}"
[ -n "$ASSETS" ] || { echo "set LOCBENCH_ASSETS=<dir> — the scratch tree holding results/, work/ and logs/ (see bench/locbench/README.md)" >&2; exit 2; }
cd "$REPO" || exit 2
mkdir -p "$ASSETS/results" "$ASSETS/logs" || exit 2

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
