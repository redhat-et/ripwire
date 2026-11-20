---
name: ripwire-before-you-build
description: >
  Starting a FEATURE (multi-symbol work): the plan, the API boundary, the scope — how big does
  this change get — from the codebase's real structure. Implementing an EXISTING interface?
  --lego=Iface lists its contract and current implementors. ONE standalone symbol → reuse-first.
  A small feature with an obvious home needs none of this.
allowed-tools: Bash, Read
---

# Before you build — with ripwire

> Routing: ONE symbol (fn/class/helper) → **ripwire-reuse-first** · already written, want the pre-submit check →
> **ripwire-change-check** · judging what you wrote → **ripwire-quality-bar** · restructuring EXISTING code →
> **ripwire-fresh-eyes** · unsure → **ripwire-router**.

`<dir>` = repo root; `FEATURE` = your task in 2–4 plain words; `SYM` = a representative symbol.

## The one call

`ripwire <dir> --pack-task="FEATURE" --legend=compact` — recall of prior decisions + the `--for` ranking with its
quality lens + top bodies + caller signatures + notes + `tests_to_run`, in ONE budgeted bundle. If a design doc
in it already covers the feature, read it fully: the decision may be made (look for "rejected" / "future work").

**Implementing against an interface?** `ripwire <dir> --lego=I --legend=compact` (`--lego=file:I` to disambiguate)
— the interface's method contract plus every existing implementor. Read one implementor as the template.

## The decision: then run only the section your question needs

| Question | Calls | Answer shape |
|---|---|---|
| is this approach viable? | `ripwire <dir> --seams --legend=compact` · `ripwire <dir> --deps --legend=compact` | build on existing / greenfield but seams exist / needs new seam, flag risk |
| the ordered implementation steps | `--seams`, then `ripwire <dir> --impact=SYM --legend=compact` for anything you will modify | steps naming file + symbol, blast radius and test gate (`--affected`) each |
| what should the boundary / API be? | `ripwire <dir> --around=SYM --legend=compact --metrics` · `--seams` · `--callers=SYM` | 3–5 high-fan-in, called-from-outside symbols, the seam they live on, what to hide |
| how big is this change? | `--impact=SYM` (`reaches=`) · `--affected=F1,F2` · `ripwire <dir> --cochange=fileA.cpp --legend=compact` | local (≤5, tests exist) / moderate (5–20) / wide (>20 or no tests) |

For each new symbol the feature adds, `ripwire <dir> --exemplar="<the sub-task in words>"` returns the repo's
best-in-class instance of that shape to copy (structure, error handling, naming).

## Stop rule

A small feature with an obvious home needs none of this — go to **ripwire-reuse-first** for its one new symbol.
Otherwise run the one call, then only the section that answers your question.

## Honesty

Seams and impact are name-based: dynamic dispatch, callbacks and macros can be missing. Compose from what exists;
say what is genuinely missing rather than reinventing it.

## Reference file

`build-reference.md` — every section step by step (recall, the write-mode bundle's quality lens, exemplar
eligibility, feasibility spike, plan, interface, sizing rubric).
