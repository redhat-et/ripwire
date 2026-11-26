# Skills consolidation — 30 → 17 (Wave 3, 2026-07)

The skills audit found 30 user-facing skills collapsing into
~8 jobs with mutually indistinguishable descriptions — a routing hazard and a token tax. This pass merged
them into **17 routable skills**, each answerable to "when would an agent pick THIS one over every other".

No content was invented; every merged skill preserves the best material of its sources (the concrete
use-when cues + honesty calibration of the 2025-refreshed skills), and every command line runs against this
repo. Absorbed skill directories were deleted — their content lives on in the merged skill named below.

## Old skill → new home

| Old skill            | New home                     | Notes |
|----------------------|------------------------------|-------|
| ripwire-orient       | **ripwire-orient**           | kept; now the escalation-ladder base |
| ripwire-tour         | **ripwire-orient**           | folded in as the report→deps→communities→hotspots ladder |
| ripwire-zoom         | **ripwire-orient**           | folded in as the nested-hierarchy + --mermaid/--html rungs |
| ripwire-navigate     | **ripwire-navigate**         | kept; --query-vs---for + graph-query pointer retained |
| ripwire-explain      | **ripwire-navigate**         | folded in as the one-symbol deep-dive section |
| ripwire-triage       | **ripwire-find-bug**         | → Branch A ("symptom, no idea where") |
| ripwire-bisect       | **ripwire-find-bug**         | → Branch B ("suspect a subsystem, narrow it") |
| ripwire-diagnose     | **ripwire-find-bug**         | → Branch C ("I changed X and it broke" — --situ) |
| ripwire-design       | **ripwire-before-you-build** | → feasibility spike / reusable blocks |
| ripwire-plan         | **ripwire-before-you-build** | → plan section |
| ripwire-spike        | **ripwire-before-you-build** | → feasibility-spike section |
| ripwire-scope        | **ripwire-before-you-build** | → sizing-rubric section |
| ripwire-interface    | **ripwire-before-you-build** | → interface section (design-time boundary work) |
| ripwire-pr-impact    | **ripwire-change-check**     | keeps --map-diff + --rank-by=churn |
| ripwire-pre-pr       | **ripwire-change-check**     | keeps --map-diff + --rank-by=churn |
| ripwire-fresh-eyes   | **ripwire-fresh-eyes**       | kept; now the repo-wide once-over base |
| ripwire-clone-hunt   | **ripwire-fresh-eyes**       | folded into duplicate-bodies pass |
| ripwire-owners       | **ripwire-fresh-eyes**       | folded into ownership / bus-factor pass |
| ripwire-dead-code    | **ripwire-fresh-eyes**       | folded in; dead-code's honest caveats preserved verbatim |
| ripwire-coupling     | **ripwire-fresh-eyes**       | folded into the hidden-coupling (co-change) pass |
| ripwire-audit-skill  | **ripwire-security-scan**    | → skill-file scanner section |
| ripwire-mcp-audit    | **ripwire-security-scan**    | → .mcp.json manual-checklist section |
| ripwire-efficient    | **ripwire-efficient**        | kept standalone |
| ripwire-quality-bar  | **ripwire-quality-bar**      | kept; cross-ref updated pre-pr → change-check |
| ripwire-reuse-first  | **ripwire-reuse-first**      | kept standalone |
| ripwire-review       | **ripwire-change-check** + **ripwire-fresh-eyes** | **DELETED** — split by moment (see 2026-07 MOMENT pass below) |
| ripwire-compress     | **ripwire-compress**         | kept standalone (the detail-ladder rewrite); later merged into ripwire-efficient, see 2026-07-05 below |
| ripwire-handoff      | **ripwire-handoff**          | kept standalone |
| ripwire-layers       | **ripwire-layers**           | kept standalone (--arch gate + baseline workflow) |
| ripwire-mcp          | **ripwire-mcp**              | kept; cross-ref updated mcp-audit → security-scan |
| ripwire-graph-query  | **ripwire-graph-query**      | kept standalone |
| ripwire-perf-target  | **ripwire-perf-target**      | kept standalone; description sharpened + routing header added |
| —                    | **ripwire-write-tests**      | NEW (S4, 2026-07-10) — no predecessor; untested-code coverage moment had no home until then |

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

## MOMENT pass (2026-07) — route by moment, not by feature

The 17 were well-written individually but agents **route by MOMENT**, and three moments were co-claimed by
near-synonym descriptions (router stalls → agent falls back to grep). This pass rewrote DESCRIPTIONS to be
pickable from the description alone, split `ripwire-review` by moment, and added an entry-point router.

- **WRITE moment de-collided.** `ripwire-reuse-first` = "about to write ONE symbol (fn/class/helper)";
  `ripwire-before-you-build` = "about to start a FEATURE (multi-symbol, needs a plan/interface/sizing)";
  `ripwire-efficient` reframed as a pure cross-cutting DISCIPLINE ("token+accuracy discipline for any read"),
  dropping "about to author" so it stops competing at the write moment. `--exemplar` now surfaced in
  before-you-build too (was reachable only from reuse-first).
- **`ripwire-review` DELETED, split by moment:** its diff-review material (blast radius, tests, hotspots,
  `--metrics` interpretation) → **ripwire-change-check**; its unfamiliar-subsystem-risk + refactor-planning
  material → **ripwire-fresh-eyes** (now scope-to-a-subsystem, not repo-only). change-check + quality-bar are
  now an explicit CHAIN ("did the code get worse" → "is it safe to merge").
- **UNDERSTAND de-duped:** the verbatim "how does X work / where is Y" now lives only on `ripwire-orient`;
  `ripwire-efficient` dropped it.
- **Stranded features got interpretation homes:** `--metrics` attrs (`cbo`/`lcom4`/`nest`/`loc`/`params`/
  `tested`) interpreted with thresholds+actions in change-check; refactor/god-object trigger + `--communities`/
  `--cochange` in fresh-eyes; portable `--cache=FILE` one-liner in efficient.
- **Router added:** `ripwire-router` = the moment→skill map (10+ moments → one skill each) + the two-reflex
  primer (before you write → `--exemplar`; before done → `--quality-delta`). Every skill also gained a
  one-line routing header so a wrong route self-corrects in one hop.

Net: 17 skills (review deleted, router added). The count is a rounding error; the win is every recognized
moment has exactly one clear entry.

## 2026-07-05 — ripwire-compress merged into ripwire-efficient (17 → 16)

`ripwire-compress`'s detail ladder (map → `--pack-signatures` → `--outline` → `--expand` → `--pack-top-n`)
and its `--compress` scope/when-NOT-to-compress guidance never had its own MOMENT — agents already land in
`ripwire-efficient` first (the map-before-you-read discipline), and `--compress` is the next question once
you're already reading a body `--expand`/`--outline` surfaced. Moved verbatim (plus the redaction/
`--no-redact` note, A3-S5) into `skills/ripwire-efficient/compress-ladder.md`, a companion file loaded on
demand — same pattern as `ripwire-quality-bar/quality-metrics.md`. `ripwire-efficient/SKILL.md` gained one
pointer line; every `ripwire-compress` reference elsewhere (router's reference-skills list) was repointed.
Directory `skills/ripwire-compress/` deleted.

Net: 16 skills (compress folded into efficient as a companion file, no moment lost).

## 2026-07-10 — ripwire-write-tests added (S4) (16 → 17)

The untested-code-coverage moment ("this is untested, add coverage") had no home — it's distinct from
judging your own diff (`ripwire-change-check`) or your own code's quality (`ripwire-quality-bar`). New
standalone skill `ripwire-write-tests`: ranks candidates by `--seams` (untested cross-module edges) and the
`tested=1` coverage lens, pulls the symbol's outside contract via `--callers`, verifies the new test registers with
`--affected`. No skill was merged or deleted for this one — it's a genuinely new moment.

Net: 17 skills (write-tests added, no other change).

## 2026-09-07 — the efficient skill folded into ripwire-orient (18 → 17 dirs; 16 routable + router)

The description-budget round (issue #49; `docs/EVALS.md` "Skill descriptions under a client budget") put
every description in front of three blind LLM raters — full text, head-cut at 350, and the rewrite. The one
loss that survived in every model and every arm was the efficient skill's rows routing to `ripwire-orient`:
raters could not see the boundary even from the full 977-character description, because "about to open
several files to answer one question" is the same moment as "understand this fast". The fold arm had zero
such misses. So the directory is gone: its `SKILL.md` became `skills/ripwire-orient/map-before-you-read.md`
(the discipline, verbatim), `compress-ladder.md` moved beside it, orient's description claims the moment, the
router's four rows point at orient, the corpus's 12 rows carry the mechanical relabel, and `--help-task`'s
`compact-legend` intent names orient.

Net: 17 skill directories (16 routable + the router; `ripwire-opt-remarks` stays contributor-gated at install).

## 2026-11-18 — short SKILL.md bodies, everything else in on-demand reference files (lane P3; 17 dirs unchanged)

No skill was added, removed or renamed, and every description is byte-identical. Each `SKILL.md` body was cut
to its skill's core recipe (total 261,872 → 52,931 B, median 9,478 → 3,072 B, max 41,668 → 3,787 B; the router
4,544 B), and everything else moved VERBATIM into flat reference files beside it (5 → 46 files), each named in a
"read only the one you need" table at the foot of the body. A conservation check found no old line lost except
two stale router statements corrected in passing (quality-delta covers 12 kinds, not 10; exit 2 means pre-existing
code got worse). Blind raters given only the skill text scored 32 of 33 pre-registered tasks with both the old and
the new bodies (one reference open in 33), so the cut shows no loss, not a gain. A proposal to delist five
skills from the listing and reach them through the router (arm L) measured in band but is an owner call and was
NOT landed.

## 2026-11-26 — shorter bodies against Anthropic's current skill guidance (17 dirs unchanged)

No skill was added, removed or renamed. The guidance used: platform.claude.com Agent Skills overview and best practices
(no date shown on either page, read 2026-11-26) and the engineering post on equipping agents with skills (published
2025-10-16). Routing is decided by the name and description alone, and the description is always loaded. The body is
loaded on trigger and should stay under 500 lines. References are loaded on demand, should sit one level deep, and need
a contents list over 100 lines. Descriptions are written in third person and name both what the skill does and when to
use it.

- **Bodies 47,243 → 40,466 B (−14.3%), every skill shorter.** Routing lines no longer end in "unsure → router", since
  the router is already in the listing. Shared trust boilerplate is cut to the per-skill caveat. Recipes and reference
  tables are terser. Every phrase a gate pins is kept.
- **Descriptions 5,461 → 5,339 B.** These were already at their measured optimum from the 2026-09-07 budget round.
  A draft at −505 characters cost 16 of 214 lexical rows, so only the cuts that cost nothing were kept. Navigate and
  find-bug no longer open in second person, and the router's description is 52 B shorter.
- **References 319,868 → 323,655 B.** The 13 references over 100 lines gained a `Contents:` line.
  `ripwire-navigate/blast-radius.md` no longer says the CLI defaults to the full legend.
- **Routing, before → after** (`bench/skillrater/results/2026-11-26/README.md`): lexical `bm25-desc` hit@1 147 → 147
  of 214, judged 100 → 100 of 160. Blind raters, Haiku 208 and 207 → 208 of 214, Sonnet 204 and 208 → 207 of 214. No
  rater fired on any of the 68 negatives after the change.
- Fixed in passing: the router said quality-delta covers 12 kinds, and the binary says 13.
