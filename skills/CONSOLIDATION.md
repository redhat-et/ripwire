# Skills consolidation — 30 → 17 (Wave 3, 2026-07)

The skills audit (`reviews/AUDIT_2026-07.md §Skills audit`) found 30 user-facing skills collapsing into
~8 jobs with mutually indistinguishable descriptions — a routing hazard and a token tax. This pass merged
them into **17 routable skills**, each answerable to "when would an agent pick THIS one over every other".

No content was invented; every merged skill preserves the best material of its sources (the concrete
use-when cues + honesty calibration of the 2025-refreshed skills), and every command line runs against this
repo. Absorbed skill directories were deleted — their content lives on in the merged skill named below.

## Old skill → new home

| Old skill            | New home                     | Notes |
|----------------------|------------------------------|-------|
| ctxpack-orient       | **ctxpack-orient**           | kept; now the escalation-ladder base |
| ctxpack-tour         | **ctxpack-orient**           | folded in as the report→deps→communities→hotspots ladder |
| ctxpack-zoom         | **ctxpack-orient**           | folded in as the nested-hierarchy + --mermaid/--html rungs |
| ctxpack-navigate     | **ctxpack-navigate**         | kept; --query-vs---for + graph-query pointer retained |
| ctxpack-explain      | **ctxpack-navigate**         | folded in as the one-symbol deep-dive section |
| ctxpack-triage       | **ctxpack-find-bug**         | → Branch A ("symptom, no idea where") |
| ctxpack-bisect       | **ctxpack-find-bug**         | → Branch B ("suspect a subsystem, narrow it") |
| ctxpack-diagnose     | **ctxpack-find-bug**         | → Branch C ("I changed X and it broke" — --situ) |
| ctxpack-design       | **ctxpack-before-you-build** | → feasibility spike / reusable blocks |
| ctxpack-plan         | **ctxpack-before-you-build** | → plan section |
| ctxpack-spike        | **ctxpack-before-you-build** | → feasibility-spike section |
| ctxpack-scope        | **ctxpack-before-you-build** | → sizing-rubric section |
| ctxpack-interface    | **ctxpack-before-you-build** | → interface section (design-time boundary work) |
| ctxpack-pr-impact    | **ctxpack-change-check**     | keeps --map-diff + --rank-by=churn |
| ctxpack-pre-pr       | **ctxpack-change-check**     | keeps --map-diff + --rank-by=churn |
| ctxpack-fresh-eyes   | **ctxpack-fresh-eyes**       | kept; now the repo-wide once-over base |
| ctxpack-clone-hunt   | **ctxpack-fresh-eyes**       | folded into duplicate-bodies pass |
| ctxpack-owners       | **ctxpack-fresh-eyes**       | folded into ownership / bus-factor pass |
| ctxpack-dead-code    | **ctxpack-fresh-eyes**       | folded in; dead-code's honest caveats preserved verbatim |
| ctxpack-coupling     | **ctxpack-fresh-eyes**       | folded into the hidden-coupling (co-change) pass |
| ctxpack-audit-skill  | **ctxpack-security-scan**    | → skill-file scanner section |
| ctxpack-mcp-audit    | **ctxpack-security-scan**    | → .mcp.json manual-checklist section |
| ctxpack-efficient    | **ctxpack-efficient**        | kept standalone |
| ctxpack-quality-bar  | **ctxpack-quality-bar**      | kept; cross-ref updated pre-pr → change-check |
| ctxpack-reuse-first  | **ctxpack-reuse-first**      | kept standalone |
| ctxpack-review       | **ctxpack-change-check** + **ctxpack-fresh-eyes** | **DELETED** — split by moment (see 2026-07 MOMENT pass below) |
| ctxpack-compress     | **ctxpack-compress**         | kept standalone (the detail-ladder rewrite) |
| ctxpack-handoff      | **ctxpack-handoff**          | kept standalone |
| ctxpack-layers       | **ctxpack-layers**           | kept standalone (--arch gate + baseline workflow) |
| ctxpack-mcp          | **ctxpack-mcp**              | kept; cross-ref updated mcp-audit → security-scan |
| ctxpack-graph-query  | **ctxpack-graph-query**      | kept standalone |
| ctxpack-perf-target  | **ctxpack-perf-target**      | kept standalone; description sharpened + routing header added |
| —                    | **ctxpack-write-tests**      | NEW (AUDIT4 S4, 2026-07-10) — no predecessor; untested-code coverage moment had no home until then |

## Judgment calls beyond the target taxonomy

- **interface → before-you-build** and **coupling → fresh-eyes** (the audit flagged both as optional). Both
  moves make descriptions MORE distinguishable: interface is a design-*time* boundary activity alongside
  spike/plan/scope; coupling is a hidden-dependency *sweep* over the same descriptive facts fresh-eyes
  already surfaces. This left `interface`/`coupling` from having near-duplicate "assess structure" triggers.
- **layers kept standalone** rather than folded into fresh-eyes: it owns the CI-enforceable `--arch=rules.txt`
  gate + baseline workflow (referenced elsewhere, e.g. from orient) — a distinct "is my architecture drifting"
  moment vs fresh-eyes' "what's the state of this code" once-over.
- **perf-target kept standalone** (it was the 30th skill, unplaced by the target taxonomy): "where should I
  optimize before profiling" is a moment no other skill claims. Description sharpened + routing header added.

Net: 17 skills (7 merged homes + 10 kept), each with a discriminating description and a routing header naming
its nearest neighbours.

## MOMENT pass (2026-07, `PLAN_skills2026.md`) — route by moment, not by feature

The 17 were well-written individually but agents **route by MOMENT**, and three moments were co-claimed by
near-synonym descriptions (router stalls → agent falls back to grep). This pass rewrote DESCRIPTIONS to be
pickable from the description alone, split `ctxpack-review` by moment, and added an entry-point router.

- **WRITE moment de-collided.** `ctxpack-reuse-first` = "about to write ONE symbol (fn/class/helper)";
  `ctxpack-before-you-build` = "about to start a FEATURE (multi-symbol, needs a plan/interface/sizing)";
  `ctxpack-efficient` reframed as a pure cross-cutting DISCIPLINE ("token+accuracy discipline for any read"),
  dropping "about to author" so it stops competing at the write moment. `--exemplar` now surfaced in
  before-you-build too (was reachable only from reuse-first).
- **`ctxpack-review` DELETED, split by moment:** its diff-review material (blast radius, tests, hotspots,
  `--metrics` interpretation) → **ctxpack-change-check**; its unfamiliar-subsystem-risk + refactor-planning
  material → **ctxpack-fresh-eyes** (now scope-to-a-subsystem, not repo-only). change-check + quality-bar are
  now an explicit CHAIN ("did the code get worse" → "is it safe to merge").
- **UNDERSTAND de-duped:** the verbatim "how does X work / where is Y" now lives only on `ctxpack-orient`;
  `ctxpack-efficient` dropped it.
- **Stranded features got interpretation homes:** `--metrics` attrs (`cbo`/`lcom4`/`nest`/`loc`/`params`/
  `tested`) interpreted with thresholds+actions in change-check; refactor/god-object trigger + `--communities`/
  `--cochange` in fresh-eyes; portable `--cache=FILE` one-liner in efficient.
- **Router added:** `ctxpack-router` = the moment→skill map (10+ moments → one skill each) + the two-reflex
  primer (before you write → `--exemplar`; before done → `--quality-delta`). Every skill also gained a
  one-line routing header so a wrong route self-corrects in one hop.

Net: 17 skills (review deleted, router added). The count is a rounding error; the win is every recognized
moment has exactly one clear entry.

## 2026-07-05 — ctxpack-compress merged into ctxpack-efficient (17 → 16)

`ctxpack-compress`'s detail ladder (map → `--pack-signatures` → `--outline` → `--expand` → `--pack-top-n`)
and its `--compress` scope/when-NOT-to-compress guidance never had its own MOMENT — agents already land in
`ctxpack-efficient` first (the map-before-you-read discipline), and `--compress` is the next question once
you're already reading a body `--expand`/`--outline` surfaced. Moved verbatim (plus the redaction/
`--no-redact` note, A3-S5) into `skills/ctxpack-efficient/compress-ladder.md`, a companion file loaded on
demand — same pattern as `ctxpack-quality-bar/quality-metrics.md`. `ctxpack-efficient/SKILL.md` gained one
pointer line; every `ctxpack-compress` reference elsewhere (router's reference-skills list) was repointed.
Directory `skills/ctxpack-compress/` deleted.

Net: 16 skills (compress folded into efficient as a companion file, no moment lost).

## 2026-07-10 — ctxpack-write-tests added (AUDIT4 S4) (16 → 17)

The untested-code-coverage moment ("this is untested, add coverage") had no home — it's distinct from
judging your own diff (`ctxpack-change-check`) or your own code's quality (`ctxpack-quality-bar`). New
standalone skill `ctxpack-write-tests`: ranks candidates by `--seams` (untested cross-module edges) and the
`tested=0` lens, pulls the symbol's outside contract via `--callers`, verifies the new test registers with
`--affected`. No skill was merged or deleted for this one — it's a genuinely new moment.

Net: 17 skills (write-tests added, no other change).
