---
name: ripwire-handoff
description: >
  Brief someone ELSE on a subsystem — 'hand this area off' to a successor, teammate or fresh session:
  purpose, the 2-3 entry points with bodies, the design docs that say WHY, hotspot/bus-factor risk — a
  compact pasteable brief, not a wall of source. Understanding it yourself → orient.
allowed-tools: Bash, Read
---

# Handoff with ripwire

> Routing: understanding the subsystem yourself → **ripwire-orient** · ONE symbol's contract → **ripwire-navigate**
> (`--expand`) · an architecture/layering read → **ripwire-layers** · unsure → **ripwire-router**.

Trigger: you are handing a subsystem to another agent or developer and want a fast, accurate brief — not a wall of
source. `SUBSYSTEM` = the area in plain words ("ingest pipeline").

## The decision

**An interrupted WORKING SESSION** (not a subsystem summary)? One call: `ripwire <dir> --handoff --legend=compact` —
a `<verified>` section (branch, HEAD sha with `+dirty`, changed files and their symbols, blast radius, tests to
run) that is disk truth, and a `<heuristic>` section (co-change partners, notes, design-doc pointers) labelled as
suggestion. Paste it to the next agent as-is. Single-root.

**A fresh code-editing subagent** (a task, not a subsystem)? One call: `ripwire <dir> --brief="TASK" --legend=compact` — one 3.5/5/7 KB page
(layout with `(skip)` dirs, build/test commands quoted from manifests, entries, the task's act ranges, edges, where-else,
conventions, the three-moment block). Paste it into the subagent's prompt as-is. Single-root.

**A subsystem brief** — four calls, in order:

1. `ripwire <dir> --for="SUBSYSTEM" --signatures-only` — the top 10 symbols the recipient most needs.
2. `ripwire <dir> --expand=SYM1,SYM2,SYM3 --legend=compact` — the top 3 in full; paste the contract verbatim.
   Bodies are redacted by default (credentials masked), so pasting is safe.
3. `ripwire <dir> --recall="SUBSYSTEM"` — the design docs that say WHY; summarize the decisions. Fold in
   `ripwire <dir> --notes --legend=compact` and `--note-add` any trap you found that is not written down.
4. `ripwire <subdir> --hotspots` — maintenance risk scoped to the subsystem; also `--owners` for bus factor.

## Stamp it, and the stop rule

Stamp the brief with the commit you measured at: `--pr-context`/`--test-gate`/`--quality-delta`/`--map-diff`
headers carry `at="<sha>[+dirty]"`; record the sha yourself for the rest. Facts (signatures, bodies, counts) are
measured; "why" comes from docs and is framing — say which is which. The brief is the four calls above, compact
and pasteable; do not append whole files.

## Reference file

`handoff-reference.md` — each step in full, the calibration of fact vs framing, commit stamping, the Output
shape, and the `--handoff` packet with `--token-budget`.
