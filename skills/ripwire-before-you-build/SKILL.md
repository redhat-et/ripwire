---
name: ripwire-before-you-build
description: >
  Starting a FEATURE (multi-symbol work): the plan, the API boundary, the scope — how big does this
  change get — from the codebase's real structure. Implementing an EXISTING interface? --lego=Iface
  lists its contract and implementors. ONE standalone symbol → reuse-first. A small feature with an
  obvious home needs none of this.
allowed-tools: Bash, Read
---

# Before you build — with ripwire

> Routing: ONE symbol (fn/class/helper) → **ripwire-reuse-first** · already written → **ripwire-change-check** ·
> judging what you wrote → **ripwire-quality-bar** · restructuring EXISTING code → **ripwire-fresh-eyes**.

`FEATURE` = your task in 2–4 plain words; `SYM` = a representative symbol.

## The one call

`ripwire <dir> --pack-task="FEATURE" --legend=compact` — prior decisions + the `--for` ranking with its quality lens + top bodies +
caller signatures + notes + `tests_to_run`, in ONE budgeted bundle. If a design doc in it covers the feature, read it
fully: the decision may be made (look for "rejected" / "future work").

**Implementing an interface?** `ripwire <dir> --lego=I` (`--lego=file:I` to disambiguate) — its method contract plus
every existing implementor. Read one implementor as the template.

## Then only the section your question needs

| Question | Calls | Answer shape |
|---|---|---|
| is this approach viable? | `ripwire <dir> --seams --legend=compact` · `ripwire <dir> --deps --legend=compact` | build on existing / greenfield but seams exist / needs a new seam |
| the ordered steps | `--seams`, then `ripwire <dir> --impact=SYM --legend=compact` for anything you modify | steps naming file + symbol, each with blast radius and test gate (`--affected`) |
| the boundary / API | `ripwire <dir> --around=SYM --metrics` · `--seams` · `--callers=SYM` | 3–5 high-fan-in, called-from-outside symbols, their seam, what to hide |
| how big is this change? | `--impact=SYM` (`reaches=`) · `--affected=F1,F2` · `ripwire <dir> --cochange=fileA.cpp` | local (≤5, tests exist) / moderate (5–20) / wide (>20 or no tests) |

For each new symbol, `ripwire <dir> --exemplar="<the sub-task in words>"` gives the house shape to copy.

## Stop rule and honesty

A small feature with an obvious home needs none of this — **ripwire-reuse-first** for its one new symbol. Otherwise the
one call, then one section. Seams and impact are name-based (dynamic dispatch, callbacks, macros can be missing); say
what is genuinely missing rather than reinventing it.

## Reference file

`build-reference.md` — every section step by step (recall, the bundle's quality lens, exemplar eligibility,
feasibility spike, plan, interface, sizing rubric).
