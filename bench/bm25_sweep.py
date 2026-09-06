#!/usr/bin/env python3
"""bm25_sweep.py — A4 BM25 parameter sweep: does the same headroom PI-SERINI (arXiv 2605.10848) reports for
tuned BM25 exist in ripwire? Runs `ripwire <root> --eval-retrieval` (the CORRECTED census sampler, midrank
ties — src/eval.h, fixed the commit this lane is based on) over a grid of (k1, b), reading the resolved
value through the RIPWIRE_BM25_K1 / RIPWIRE_BM25_B env override (src/lexical.h resolveBm25Params(), A4).

House rule this script exists under (owner-registered, see docs/EVALS.md): a measurement harness is a
LEDGER, never a red CI gate. This reports numbers; it never returns non-zero because a number moved. It is
not wired into test/regression.sh or test/pargates.py, and it is not meant to be — see bench/ANSWERQUALITY.md
and bench/BENCHMARK.md for the same posture on this repo's other benches.

"Retrieval depth" is NOT a third swept input alongside (k1,b): --eval-retrieval already reports recall@1,
recall@5 and recall@10 from ONE ranking per query (the gold rank against the full exhaustive score vector),
so depth is a column of the existing output, not a knob this script needs to add. A k1 x b grid with three
recall@K columns per cell already reads as the "k1 x b x depth" table the lane calls for.

Usage:
    bench/bm25_sweep.py                                  # default grid, src/, build/ripwire
    bench/bm25_sweep.py --root . --k1 1.0 1.5 2.0 --b 0.5 0.75 1.0
    RIPWIRE_BIN=asan/ripwire bench/bm25_sweep.py --json > sweep.json

Deterministic: --eval-retrieval's own numbers are a pure function of the score vectors (no threading in the
metric), so re-running this script with the same grid and the same binary reproduces the same table.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BIN = os.environ.get("RIPWIRE_BIN", str(ROOT / "build" / "ripwire"))
DEFAULT_CORPUS = "src"                        # the corpus README/EVALS.md publish --eval-retrieval numbers for
DEFAULT_K1 = 1.5                              # the shipped default (src/lexical.h kBm25Default) — always in the grid
DEFAULT_B = 0.75
DEFAULT_K1_GRID = [0.5, 1.5, 3.5]             # pre-registered grid (docs/EVALS.md) — coarse and WIDE by
DEFAULT_B_GRID = [0.0, 0.5, 0.75, 1.0]        # deliberate choice: each cell costs ~90-150s on src/ (2988
                                               # doc-commented symbols, exhaustive census), so this trades
                                               # resolution for covering the full clamp range at all; a
                                               # promising direction found here is worth a finer follow-up
                                               # grid along that one axis, not a blind denser cartesian pass.

# one row per (ranker, query-mode) as printed by src/eval.h::runEvalRetrieval's `row()` lambda:
#   "  %-9s %-11s %6.3f %8.1f%% %8.1f%% %8.1f%%\n"
ROW_RE = re.compile(
    r"^\s*(?P<ranker>subtoken|name-exact|anchored|routed)\s+(?P<mode>name|doc-phrase)\s+"
    r"(?P<mrr>[0-9]+\.[0-9]+)\s+(?P<r1>[0-9]+\.[0-9]+)%\s+(?P<r5>[0-9]+\.[0-9]+)%\s+(?P<r10>[0-9]+\.[0-9]+)%"
)
SAMPLE_RE = re.compile(r"population=(?P<population>\d+)\s+scored=(?P<scored>\d+)\s+rule=(?P<rule>\S+)")


def run_eval_retrieval(binary: str, corpus: str, k1: float, b: float, timeout: int) -> dict[str, Any]:
    """One `--eval-retrieval` invocation at a configured (k1,b). Raises on a non-zero exit or an
    unparseable table — a sweep that silently drops a cell would misreport the winner."""
    env = dict(os.environ)
    env["RIPWIRE_BM25_K1"] = repr(k1)
    env["RIPWIRE_BM25_B"] = repr(b)
    started = time.monotonic()
    proc = subprocess.run(
        [binary, corpus, "--eval-retrieval"],
        capture_output=True, text=True, timeout=timeout, env=env, cwd=str(ROOT),
    )
    elapsed = time.monotonic() - started
    if proc.returncode != 0:
        raise RuntimeError(f"--eval-retrieval exited {proc.returncode} at k1={k1} b={b}: {proc.stderr.strip()}")
    rows: dict[str, dict[str, float]] = {}
    sample: dict[str, Any] = {}
    for line in proc.stdout.splitlines():
        m = ROW_RE.match(line)
        if m:
            key = f'{m.group("ranker")}/{m.group("mode")}'
            rows[key] = {
                "mrr": float(m.group("mrr")),
                "recall@1": float(m.group("r1")),
                "recall@5": float(m.group("r5")),
                "recall@10": float(m.group("r10")),
            }
            continue
        sm = SAMPLE_RE.search(line)
        if sm:
            sample = {"population": int(sm.group("population")), "scored": int(sm.group("scored")), "rule": sm.group("rule")}
    if len(rows) != 8:
        raise RuntimeError(f"--eval-retrieval at k1={k1} b={b} produced {len(rows)}/8 ranker/mode rows — parser or output drifted:\n{proc.stdout}")
    if not sample:
        raise RuntimeError(f"--eval-retrieval at k1={k1} b={b} printed no population=/scored=/rule= line")
    return {"k1": k1, "b": b, "sample": sample, "rows": rows, "elapsed_s": round(elapsed, 1)}


def sweep(binary: str, corpus: str, k1_grid: list[float], b_grid: list[float], timeout: int) -> list[dict[str, Any]]:
    # DEFAULT_K1/DEFAULT_B always included, deduped, so the table always has a same-row baseline to diff
    # every other cell against — a sweep that forgets to measure its own baseline can't report a delta.
    k1s = sorted(set(k1_grid) | {DEFAULT_K1})
    bs = sorted(set(b_grid) | {DEFAULT_B})
    cells = []
    total = len(k1s) * len(bs)
    for i, k1 in enumerate(k1s):
        for j, b in enumerate(bs):
            n = i * len(bs) + j + 1
            print(f"[{n}/{total}] k1={k1} b={b} …", file=sys.stderr, flush=True)
            cells.append(run_eval_retrieval(binary, corpus, k1, b, timeout))
    return cells


# the single scalar this lane optimizes for: the identifier-query ranker's own MRR (name-exact/name) is the
# lane's primary metric (it is what routing forwards nearly every NAME query to — see the `note:` line
# --eval-retrieval itself prints), with subtoken/doc-phrase as the runner-up read (routed's fallback ranker
# on conceptual queries). Reported, not silently chosen for you: PRIMARY_METRIC names which column "best"
# below means, and every other column is still in the table to check for a metric that improved at that
# column's expense.
PRIMARY_METRIC = "name-exact/name"


def best_cell(cells: list[dict[str, Any]], metric: str = PRIMARY_METRIC) -> dict[str, Any]:
    return max(cells, key=lambda c: c["rows"][metric]["mrr"])


def default_cell(cells: list[dict[str, Any]]) -> dict[str, Any]:
    for c in cells:
        if c["k1"] == DEFAULT_K1 and c["b"] == DEFAULT_B:
            return c
    raise RuntimeError("the default (k1,b) cell is not in the sweep — sweep() should always include it")


def print_text(cells: list[dict[str, Any]], corpus: str) -> None:
    sample = cells[0]["sample"]
    print(f"bm25_sweep: corpus={corpus} cells={len(cells)} population={sample['population']} scored={sample['scored']} rule={sample['rule']}")
    print(f"{'k1':>5} {'b':>5}  " + "  ".join(f"{m:>21}" for m in ("name-exact/name", "subtoken/doc-phrase", "routed/name", "routed/doc-phrase")))
    for c in cells:
        cols = []
        for metric in ("name-exact/name", "subtoken/doc-phrase", "routed/name", "routed/doc-phrase"):
            r = c["rows"][metric]
            cols.append(f'{r["mrr"]:.3f} r1={r["recall@1"]:5.1f} r10={r["recall@10"]:5.1f}')
        marker = " <- default" if (c["k1"], c["b"]) == (DEFAULT_K1, DEFAULT_B) else ""
        print(f'{c["k1"]:>5} {c["b"]:>5}  ' + "  ".join(cols) + marker)

    best, default = best_cell(cells), default_cell(cells)
    d_mrr, b_mrr = default["rows"][PRIMARY_METRIC]["mrr"], best["rows"][PRIMARY_METRIC]["mrr"]
    d_r1, b_r1 = default["rows"][PRIMARY_METRIC]["recall@1"], best["rows"][PRIMARY_METRIC]["recall@1"]
    delta_pct = 100.0 * (b_mrr - d_mrr) / d_mrr if d_mrr else float("nan")
    print(f"\nprimary metric: {PRIMARY_METRIC} MRR")
    print(f"  default (k1={DEFAULT_K1}, b={DEFAULT_B}): MRR={d_mrr:.3f} recall@1={d_r1:.1f}%")
    print(f"  best    (k1={best['k1']}, b={best['b']}): MRR={b_mrr:.3f} recall@1={b_r1:.1f}%  ({delta_pct:+.1f}% MRR vs default)")
    if best["k1"] == DEFAULT_K1 and best["b"] == DEFAULT_B:
        print("  the shipped default IS the sweep optimum on this grid/corpus.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=DEFAULT_CORPUS, help=f"corpus to run --eval-retrieval over (default: {DEFAULT_CORPUS})")
    parser.add_argument("--bin", default=DEFAULT_BIN, help="ripwire binary (default: $RIPWIRE_BIN or build/ripwire)")
    parser.add_argument("--k1", type=float, nargs="+", default=DEFAULT_K1_GRID, help=f"k1 grid (default: {DEFAULT_K1_GRID})")
    parser.add_argument("--b", type=float, nargs="+", default=DEFAULT_B_GRID, help=f"b grid (default: {DEFAULT_B_GRID})")
    parser.add_argument("--timeout", type=int, default=600, help="per-cell subprocess timeout in seconds (default: 600)")
    parser.add_argument("--json", action="store_true", help="emit the full sweep as JSON instead of the text table")
    args = parser.parse_args()

    binary = args.bin if os.path.isabs(args.bin) else str(ROOT / args.bin)
    if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
        print(f"bm25_sweep.py: no ripwire binary at {binary} — build first (cmake --build build -j)", file=sys.stderr)
        return 2

    cells = sweep(binary, args.root, args.k1, args.b, args.timeout)
    if args.json:
        print(json.dumps({"corpus": args.root, "binary": binary, "primary_metric": PRIMARY_METRIC, "cells": cells}, sort_keys=True, indent=None, separators=(",", ":")))
    else:
        print_text(cells, args.root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
