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
> (`--expand`) · an architecture/layering read → **ripwire-layers**.

**An interrupted WORKING SESSION** (not a subsystem summary)? One call: `ripwire <dir> --handoff --legend=compact` — a `<verified>`
section (branch, HEAD sha with `+dirty`, changed files and their symbols, blast radius, tests to run) that is disk truth,
and a `<heuristic>` section (co-change partners, notes, design-doc pointers) labelled as suggestion. Paste it as-is.
Single-root.

**A subsystem brief** (`SUBSYSTEM` = the area in plain words) — four calls, in order:

1. `ripwire <dir> --for="SUBSYSTEM" --signatures-only` — the top 10 symbols the recipient most needs.
2. `ripwire <dir> --expand=SYM1,SYM2,SYM3` — the top 3 in full; paste the contract verbatim (bodies are redacted by
   default, so pasting is safe).
3. `ripwire <dir> --recall="SUBSYSTEM"` — the design docs that say WHY; summarize the decisions. Fold in
   `ripwire <dir> --notes --legend=compact`, and `--note-add` any unwritten trap you found.
4. `ripwire <subdir> --hotspots` — maintenance risk in the subsystem; `--owners` for bus factor.

## Stamp it, and stop

Stamp the brief with the commit you measured at (`--pr-context`/`--test-gate`/`--quality-delta`/`--map-diff` headers
carry `at="<sha>[+dirty]"`; record it yourself otherwise). Signatures, bodies and counts are measured; "why" comes from
docs and is framing — say which is which. The brief is the four calls, compact and pasteable; append no whole files.

## Reference file

`handoff-reference.md` — each step in full, fact vs framing, commit stamping, the Output shape, the `--handoff` packet
with `--token-budget`.
