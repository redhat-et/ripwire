---
name: ripwire-quality-bar
description: >
  QUALITY of code YOU just wrote, before commit/'done' or cleanup: --quality-delta lists what got WORSE
  in 13 kinds; exit 2 if old code did (new-symbol rows never gate, except defect-shape format-arity, a
  new function at the ceiling and a tangled new one); each shape's fix. Merge safety → change-check.
  Even a single-line leaf fix runs it.
allowed-tools: Bash, Read
---

# The quality-bar convergence loop

> Routing: merge safety, tests to run → **ripwire-change-check** (run this skill FIRST, then its `--test-gate`) · reuse
> before writing → **ripwire-reuse-first** · rot in code you did not write → **ripwire-fresh-eyes** · a memory-layout
> hypothesis → **ripwire-perf-target**.

Measure the delta, don't eyeball it. Even a single-line leaf fix runs it: the warm run is well under a second.

## The one call

```
ripwire <dir> --quality-delta --legend=compact
```

In a git repo it compares the working tree with `git HEAD` (`baseline="git-HEAD"`) and lists only what YOUR change made
worse, across 13 kinds (complexity, verbosity, nesting, params, duplication, dead-code, api-surface, error-masking,
short-horizon-churn, new-clone-of-reused-helper, placeholder, defect-shape, tangle). **Watch `verbosity` hardest** —
LOC growth is the most-measured agent failure mode. Long multi-commit change? `ripwire <dir> --quality-baseline` FIRST,
on a clean tree, so later runs delta against where you started (dirty tree: refused; `--allow-dirty` pins anyway and
stamps `baseline_absorbed="N"`).

## Read the exit code — it is narrower than it looks

Exit 2 = at least one row gates, exactly the header's `gating="N"`: major, unacked, in scope, on code that already
existed (`preexisting-worse`), or one of three new-symbol exceptions — defect-shape format-arity, a new function at the
ceiling, a new function at tangle 6 or more. Read `gating=`, not `regressions=`. **Exit 0 means no row gated, NOT
"clean"**: open the `origin="new-symbol"` rows — they are the debt you are adding. Moved code: unchanged keeps its
identity, a small edit reads `origin="moved"` and never gates, a rewrite reads as new — so on a moving diff the exit
code is weak evidence. Before an extract-method fix, read `ev=` on the `cx=` row: absent or `ev="1"` = mechanical.

## Stop rule

A `gating="0"` run on a leaf fix that keeps the signature and adds no branch, symbol, dependency or abstraction is
confirmation: stop. Drill-down, `--dmm`, acking and a second round are for a run that reported something. Otherwise fix
the real rows, re-run, converge; two rounds without progress → report what remains.

## Reference files — read only the one the answer sends you to

| You need | Read |
|---|---|
| the wide-angle `--quality-panel` read (six evidence families) | `panel.md` |
| the full loop: exit-code contract, exemptions, idiom demotions, acking (`--quality-ack`) | `loop.md` |
| a flagged row: zoom in (`--dmm`, drill-down per kind) | `drill-down.md` |
| which refactor a shape calls for, and the loop that proves it landed | `playbook.md` |
| paying down EXISTING debt; guardrails; CI / pre-commit wiring | `debt-ci.md` |
| every metric's definition and threshold | `quality-metrics.md` |
