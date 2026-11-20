---
name: ripwire-fresh-eyes
description: >
  Maintenance risk in code you did NOT write — inheriting a module, planning a refactor, a suspected
  god object, 'what's gnarly / where's the rot / safe to touch?': hotspots, dead or inactive code,
  switches/defaults (--flags), clones, a function's real shape, bus factor, co-change. Naming the fix
  or judging YOUR new code → quality-bar. A single-lens question is a single call.
allowed-tools: Bash, Read
---

# Fresh-eyes risk review with ripwire

> Routing: any DIFF about to push or merge → **ripwire-change-check** · you have the measurement and need the
> FIX (which refactor a shape calls for, and the fix-then-prove loop) → **ripwire-quality-bar** · architecture
> health and layering rules → **ripwire-layers** · where a specific bug lives → **ripwire-find-bug** · unsure →
> **ripwire-router**.

Scope it to the subsystem you are about to touch: point `<dir>` at it (`ripwire src/net --hotspots`) or keep the
root and `--exclude` the rest; add `--exclude=build --exclude=.git` so artifacts don't read as clones or dead
code. Inheriting it? `ripwire <dir> --notes --legend=compact` first — a prior agent's pinned gotcha is the
cheapest fact there is.

## The decision: one lens per question

| Question | Run |
|---|---|
| "what's gnarly here?" — the whole picture in one ranked report (six evidence families; a lens, not a gate) | `ripwire <dir> --quality-panel --legend=compact` |
| where developers keep working AND the code is hard (`score = churn × ccx`, `top=` names the worst fn) | `ripwire <dir> --hotspots --legend=compact` (`--since="2 weeks ago"` for recent) |
| what the repository has been moving lately | `ripwire <dir> --rank-by=churn-decay --legend=compact` |
| what is built but DARK (compiled or flagged off) — "why don't I see feature X" | `ripwire <dir> --flags --legend=compact` · `--flip=NAME` for the blast radius of turning one on |
| can I trust the docs? | `ripwire <dir> --doc-drift --legend=compact` |
| dead or inactive code | `ripwire <dir> --dead-code --legend=compact` |
| duplicate bodies | `ripwire <dir> --clones --legend=compact` |
| AST smells | `ripwire <dir> --lint --legend=compact` |
| bus factor / who knows this | `ripwire <dir> --owners --legend=compact` |
| a change here keeps breaking unrelated files | `ripwire <dir> --cochange --legend=compact` |
| planning a refactor / a suspected god object | `ripwire <dir> --communities --legend=compact`, then `--impact=SYM` and `--cochange=FILE` |

Read a function's real shape, not one number: `nest=` is a max, so read its `humps=`/`deep=` profile beside it;
`ev=` (essential complexity) says whether an extract is a cheap lift (`1`) or a rewrite (`2+`). On C-family/C#
code, discount a body carrying `ppalt=`: its metrics sum every `#ifdef` branch. Then take the shape to
**ripwire-quality-bar**'s playbook for the fix.

## Stop rule

A single-lens question is a single call. Run the panel or the one lens that answers it; read the top rows'
source; stop. Absence is a floor — a clean `--dead-code` or `--clones` means "none found", never "none exists".

## Reference files

| You need | Read |
|---|---|
| hotspots and churn in full (`--since`, `--in=DIR`, `merge_bombs_skipped`, `ppalt=`) | `hotspots-churn.md` |
| dark gates (`--flags`, `--flip`), doc drift, plans never launched (`--plan-lint`) | `dark-docs-plans.md` |
| dead code, clones, lint (every lint rule: `lint-rules.md`) | `dead-clones-lint.md` |
| ownership, bus factor, the shape metrics (`humps=`, `deep=`, `locals=`, `ev=`) | `owners.md` |
| hidden coupling, refactor planning, the Output shape | `coupling-refactor.md` |
