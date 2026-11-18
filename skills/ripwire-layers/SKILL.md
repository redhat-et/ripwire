---
name: ripwire-layers
description: >
  Architecture HEALTH and ENFORCEMENT — 'is this a dependency mess / does the UI reach into the
  database / enforce module boundaries in CI?': cycles, the godfile, propagation cost (how far a touch
  ripples), --arch rules with a baseline gate. Overview without gating → orient. One pass answers it.
allowed-tools: Bash, Read
---

# Layers with ripwire

> Routing: reviewing YOUR OWN diff for coupling risk → **ripwire-change-check** · a general risk sweep, not
> architecture-specific → **ripwire-fresh-eyes** · an overview without gating → **ripwire-orient**.

Trigger: a factual picture of architectural health before a large refactor, or enforcing module boundaries in CI.
Every metric has a NUMBER → THRESHOLD → ACTION — do not stop at reporting it.

## The decision

| Question | Run | Act on |
|---|---|---|
| enforce "ui/ never imports db/" in CI | `ripwire <dir> --arch=rules.txt` — grammar `layer NAME = substr…`, `deny FROM -> TO`, `allow FROM -> TO`; exit 2 = NEW violations | fix each violation or `allow` it with a reason |
| adopt rules on a codebase with existing debt | `ripwire <dir> --arch=rules.txt --baseline` (commit `.ripwire_arch_baseline`; later runs fail only on NEW ones) | `--baseline-update` only in its own reviewed commit |
| is this a dependency mess? cycles, god files | `ripwire <dir> --deps --legend=compact` | `nccd` < 0.25 healthy; `shape` horizontal good; top-3 godfiles by `afferent` → name them as layers with `deny` rules; a cycle in `--report` first |
| how far does a touch ripple? | `<metrics propagation_cost=>` from `--arch` (lower is better; > 0.3 worth a look) | the `<m path= ca= ce=>` rows show which directories drive it |
| where do modules couple across boundaries | `ripwire <dir> --communities --legend=compact` | a high `<bridge>` count between non-adjacent clusters → a `deny` rule |

Trust the god-file and cycle read hardest — `afferent` and cycles are validated defect predictors; `nccd` and the
Martin `I`/`A`/`D` block are design heuristics. A row with `no_file_edges=` is a language whose imports rarely
resolve to files: an absent number means not measured, never zero.

## Stop rule

One pass answers it: run the row that matches, then classify healthy / at-risk / needs restructuring, and for
anything at-risk name the boundary to formalize (which layer, which `deny` rule).

## Reference file

`layers-reference.md` — the rules grammar and baseline workflow in full, propagation cost, dependency health,
module clustering, the Mermaid view, and the Output shape.
