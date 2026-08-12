# docdriftfix notes

A deliberately half-stale design note. Every anchor below is labelled with the verdict `--doc-drift` must
reach, so the gate proves TRUE POSITIVES and TRUE NEGATIVES from the same run.

## file:line anchors

- HOLDS — `stableHelper` returns the clamped value (code.h:18).
- DRIFTS (line-moved) — `stableHelper` doubles its argument (code.h:23), which is now someone else's body.
- DRIFTS (past-eof) — the tail of `stableHelper` is at code.h:900.
- DRIFTS (missing-file) — the old helper lived in deletedFile.h:12.
- UNCHECKED (not-indexed) — the exercise mode is set in exercise.cmake:2.
- UNCHECKED (named-elsewhere) — `otherEntry` is called from code.h:18, a call site rather than its own body.

## symbol mentions

- HOLDS — `stableHelper` is still the entry point.
- DRIFTS (undefined) — `stableHelper` used to hand off to `deletedHelper`, which no longer exists.
- SILENT (uncorroborated) — a bare mention of `phantomHelper` with no live name beside it.
- SILENT (foreign-scope) — `otherProject::vanishedThing` belongs to another codebase.
- SILENT (not-a-definition) — `ddfixMutableKnob` is a mutable global the index deliberately does not tag as a definition.

## constants and extents

- HOLDS — `kHoldingLimit` = 7.
- DRIFTS (const-value) — `kDriftedLimit` = 10.
- HOLDS — the lookup is `kHoldingTable[4]`.
- DRIFTS (array-extent) — the wide lookup is `kDriftedTable[16]`.
- DRIFTS (array-extent, bare form) — `kDriftedTable` is a [16] entry table.
- PROSE (never an anchor) — the hand-tuned knob `absent_from_all_code` = 42.

## a fenced example — nothing in here is a claim about this repo

```
$ ripwire . --doc-drift
  → pointing at code.h:999 (`ghostSymbol`) — an illustration, not an anchor
```
