---
name: ripwire-layers
description: >
  Architecture HEALTH and ENFORCEMENT — 'is this a dependency mess / does the UI reach into the database
  / enforce module boundaries in CI?': cycles, the godfile, propagation cost (how far a touch ripples),
  --arch rules with a baseline gate. Overview without gating → orient. One pass answers it.
allowed-tools: Bash, Read
---

# Layers with ripwire

> Routing: coupling risk in YOUR OWN diff → **ripwire-change-check** · a general risk sweep → **ripwire-fresh-eyes** ·
> an overview without gating → **ripwire-orient**.

Every metric has a NUMBER → THRESHOLD → ACTION; do not stop at reporting it.

| Question | Run | Act on |
|---|---|---|
| enforce "ui/ never imports db/" in CI | `ripwire <dir> --arch=rules.txt` — `layer NAME = substr…`, `deny FROM -> TO`, `allow FROM -> TO`; exit 2 = NEW violations | fix each, or `allow` it with a reason |
| adopt rules on a codebase with existing debt | `ripwire <dir> --arch=rules.txt --baseline` (commit `.ripwire_arch_baseline`; later runs fail only on NEW ones) | `--baseline-update` only in its own reviewed commit |
| is this a dependency mess? cycles, god files | `ripwire <dir> --deps --legend=compact` | `nccd` < 0.25 healthy; `shape` horizontal good; top-3 godfiles by `afferent` → layers with `deny` rules; a cycle in `--report` first |
| how far does a touch ripple? | `<metrics propagation_cost=>` from `--arch` (lower is better; > 0.3 worth a look) | the `<m path= ca= ce=>` rows show which directories drive it |
| where modules couple across boundaries | `ripwire <dir> --communities --legend=compact` | a high `<bridge>` count between non-adjacent clusters → a `deny` rule |

Trust god-files and cycles hardest — `afferent` and cycles are validated defect predictors; `nccd` and Martin's
`I`/`A`/`D` are design heuristics. A row with `no_file_edges=` is a language whose imports rarely resolve to files: an
absent number means not measured, never zero.

## Stop rule

One pass answers it: run the matching row, classify healthy / at-risk / needs restructuring, and for anything at-risk
name the boundary to formalize (which layer, which `deny` rule).

## Reference file

`layers-reference.md` — the rules grammar and baseline workflow, propagation cost, dependency health, module
clustering, the Mermaid view, the Output shape.
