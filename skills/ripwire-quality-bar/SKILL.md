---
name: ripwire-quality-bar
description: >
  Code QUALITY of what YOU just wrote, before commit/'done' or a cleanup: --quality-delta
  lists what got WORSE in 13 kinds; exit 2 if old code did (new-symbol rows never gate,
  except defect-shape format-arity, a new function at the ceiling and a tangled new one); the fix each shape calls for.
  Merge safety → change-check. Even a single-line leaf fix runs it.
allowed-tools: Bash, Read
---

# The quality-bar convergence loop

> Routing: merge safety, tests to run → **ripwire-change-check** (run this skill FIRST, then its `--test-gate`) ·
> reuse before writing → **ripwire-reuse-first** · rot in code you did not write → **ripwire-fresh-eyes** ·
> a memory-layout hypothesis → **ripwire-perf-target** · unsure → **ripwire-router**.

Don't eyeball quality — measure the delta your change introduced. Even a single-line leaf fix runs it: the check
warm-runs in well under a second, cheaper than deciding by eye whether the edit "counts".

## The one call

```
ripwire <dir> --quality-delta --legend=compact
```

In a git repo it compares the working tree against `git HEAD` (`baseline="git-HEAD"` in the header) — no setup.
It lists only what YOUR change made worse, across 13 kinds (complexity, verbosity, nesting, params, duplication,
dead-code, api-surface, error-masking, short-horizon-churn, new-clone-of-reused-helper, placeholder, defect-shape, tangle). **Watch `verbosity` hardest** — LOC growth is the most-measured agent failure mode.

Long multi-commit change? Run `ripwire <dir> --quality-baseline` FIRST, on a clean tree, so every later run
deltas against where you started instead of the last commit (on a dirty tree it refuses; `--allow-dirty` pins
anyway and stamps `baseline_absorbed="N"`).

## Read the exit code — it is narrower than it looks

Exit 2 ONLY on a finding that is major AND unacked AND on code that already existed (`preexisting-worse`) —
exactly the header's `gating="N"`. Read `gating=`, not `regressions=`. The new-symbol rows never gate, except defect-shape format-arity, a new function at the ceiling and a tangled new function
(a format/argument mismatch is a defect, so it gates on new code too). **Exit 0 means "nothing that already existed got worse", NOT "clean"**: open the
`origin="new-symbol"` rows — they are the debt you are adding. A renamed or moved symbol reads as new
(`origin="moved"` never gates), so on a diff that moves code the exit code is weak evidence. Before an extract-method fix, read `ev=`
(essential complexity) on the `cx=` row: absent or `ev="1"` means the extraction is mechanical.

## Stop rule

A clean `gating="0"` run on a single-line leaf fix that preserves the signature and adds no branch, symbol,
dependency or abstraction is confirmation: stop there. Everything after a clean run — drill-down, `--dmm`, acking,
a second round — is for a run that reported something. Otherwise: fix the real rows, re-run, converge; bound it
(two rounds without progress → report what remains).

## Reference files — read only the one the answer sends you to

| You need | Read |
|---|---|
| the wide-angle `--quality-panel` read (six evidence families) before you converge | `panel.md` |
| the full loop: exit-code contract, exemptions, idiom demotions, acking (`--quality-ack`) | `loop.md` |
| a flagged row — zoom in (`--dmm`, drill-down per kind) | `drill-down.md` |
| which refactor a shape calls for, and the closed fix loop that proves it landed | `playbook.md` |
| paying down EXISTING debt one finding per commit; guardrails; CI / pre-commit wiring; honesty | `debt-ci.md` |
| every metric's definition and threshold | `quality-metrics.md` |
