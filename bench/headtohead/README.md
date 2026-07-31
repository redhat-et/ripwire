# Head-to-head archive: ctxpack vs Aider repo-map vs codebase-memory-mcp vs graphify

Phase B5.3 of `PLAN_researchImprove2026.md`, run **2026-07-13/14**. A 4-arm paired comparison on a
60-instance held-out LocBench slice (40/60 multi-file gold), with a loss-bucket analysis of every
ctxpack strict-file@10 loss, re-run and verified.

## What's here

- `REPORT.md` — the full writeup: methodology, exact tool/harness versions and hashes, the
  headline table, the win/loss matrix, per-instance loss buckets, and "what to build next."
  This is the primary deliverable — read it first.
- `headtohead_results.json` — machine-readable paired per-instance results (scoreboard source
  of truth).
- `loss_buckets.json` — the 14 loss instances, bucketed and annotated, with rerun evidence.
- `paired_table.md` — the human-readable 60-row paired table.

## What's NOT here

The arm-runner scripts, per-instance logs, raw JSONL captures, and the checked-out competitor
repos live outside this repo, under the scratchpad the run used
(`headtohead/{aider,cbm,graphify}_worker.py`, `run_*_arm.{py,sh}`, `score{,4}.py`, `logs/`,
`repos/`, `*60.jsonl`). They're run artifacts, not source — reproducing the run means re-cloning
the competitor tools at the pinned versions in `REPORT.md §(i)` and re-checking-out the LocBench
instances at their pinned commits, not replaying a script from this tree.

## Headline (see REPORT.md for full context)

N=60 paired, strict file@k:

| arm | file@10 | any@10 |
|---|---|---|
| ctxpack `--for` | 36.7% | 75.0% |
| codebase-memory-mcp | 26.7% | 66.7% |
| graphify (BFS traversal order) | 21.7% | 41.7% |
| aider repo-map (personalized) | 13.3% | 33.3% |

Median wall/instance: ctxpack 0.074s, codebase-memory-mcp 1.14s, aider 2.5s, graphify 5.8s.
