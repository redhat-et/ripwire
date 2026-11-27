---
name: ripwire-fresh-eyes
description: >
  Maintenance risk in code you did NOT write — inheriting a module, planning a refactor, a suspected god
  object, 'what's gnarly / where's the rot / safe to touch?': hotspots, dead or inactive code,
  switches/defaults (--flags), clones, a function's real shape, bus factor, co-change. Naming the fix or
  YOUR new code → quality-bar. A single-lens question is a single call.
allowed-tools: Bash, Read
---

# Fresh-eyes risk review with ripwire

> Routing: a DIFF about to push or merge → **ripwire-change-check** · you have the measurement and need the FIX →
> **ripwire-quality-bar** · architecture and layering rules → **ripwire-layers** · where a specific bug lives →
> **ripwire-find-bug**.

Scope it to the subsystem you will touch (`ripwire src/net --hotspots`, or the root with `--exclude`); add
`--exclude=build --exclude=.git` so artifacts don't read as clones or dead code. Inheriting it? `ripwire <dir> --notes --legend=compact`
first — a prior agent's pinned gotcha is the cheapest fact there is.

## One lens per question

| Question | Run |
|---|---|
| "what's gnarly here?" — one ranked report over six evidence families (a lens, not a gate) | `ripwire <dir> --quality-panel --legend=compact` |
| where people keep working AND the code is hard (`score = churn × ccx`, `top=` = worst fn) | `ripwire <dir> --hotspots` (`--since="2 weeks ago"` for recent) |
| what the repository has been moving lately | `ripwire <dir> --rank-by=churn-decay --legend=compact` |
| built but DARK (compiled or flagged off) — "why don't I see feature X" | `ripwire <dir> --flags --legend=compact` · `--flip=NAME` for turning one on |
| can I trust the docs? | `ripwire <dir> --doc-drift --legend=compact` |
| dead or inactive code · duplicate bodies · AST smells | `ripwire <dir> --dead-code --legend=compact` · `--clones` · `--lint` |
| bus factor / who knows this | `ripwire <dir> --owners` |
| a change here keeps breaking unrelated files | `ripwire <dir> --cochange` |
| planning a refactor / a suspected god object | `ripwire <dir> --communities --legend=compact`, then `--impact=SYM` and `--cochange=FILE` |

Read a function's real shape, not one number: `nest=` is a max, so read `humps=`/`deep=` beside it; `ev=` (essential
complexity) says whether an extract is a cheap lift (`1`) or a rewrite (`2+`). On C-family/C# code, discount a body with
`ppalt=`: its metrics sum every `#ifdef` branch. Take the shape to **ripwire-quality-bar**'s playbook for the fix.

## Stop rule

A single-lens question is a single call: run it, read the top rows' source, stop. Absence is a floor — a clean
`--dead-code` or `--clones` means "none found", never "none exists".

## Reference files

`hotspots-churn.md` hotspots and churn (`--since`, `--in=DIR`, `merge_bombs_skipped`, `ppalt=`) · `dark-docs-plans.md`
dark gates (`--flags`, `--flip`), doc drift, plans never launched (`--plan-lint`) · `dead-clones-lint.md` dead code,
clones, lint (every rule: `lint-rules.md`) · `owners.md` ownership, bus factor, shape metrics (`humps=`, `deep=`,
`locals=`, `ev=`) · `coupling-refactor.md` hidden coupling, refactor planning, the Output shape.
