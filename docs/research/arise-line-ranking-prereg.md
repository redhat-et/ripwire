# ARISE line ranking — one honest attempt, PRE-REGISTERED 2026-09-23 (before any src/ change, before any number below exists)

**Status at commit: PRE-REGISTRATION ONLY. No `src/` change has landed yet (that is commit 2 of this
lane) and no number in this document was computed by a harness — the corpus (LocBench V1) is not on
this machine and is not fetched, read or scored here.** This document fixes the population, the one
ranking attempt, the verdict rule and the bands before any of them touch data, so that whichever way
the eventual measurement comes out, nothing here can be read as chosen after seeing it.

**Baseline this document cites, and does not re-derive.** `docs/research/slice-line-recall.md` on
`origin/lane/research-arise-slice` (draft PR #318, unmerged — the file does not exist on `main` or on
this branch; every figure below quoted from it is a citation, not a number this lane produced). Its
§10 "ARISE rung 3" is a separate question (cross-function call-graph reach) and is out of scope here.

## 0. Why this document exists — the owner's ruling

`$ORCH/PLAN_063.md` §3, row **#318**: *"line ranking is at chance (0.048 vs 0.042) and source order is
worse than random — fix it or stop ranking lines."* §"ARISE line ranking" stop condition: *"If ranking
still does not beat random after one honest attempt, stop ranking lines and emit them in a stated
order."* Owner ruling 1, 2026-09-21: *"prioritize the fix, then send the email"* — line ranking is now
the first priority of 0.6.3. Owner ruling, 2026-09-23: pre-register and write the one honest attempt
now, committed before any data; scoring waits for the corpus.

The **0.048 vs 0.042** the owner cites is `docs/research/slice-line-recall.md` §R4's **R1 def-use
coverage @1** against its **CTL random-control @1**, over the candidate pool of **every line in the
resolved function's span** — not the narrower, already-ADOPTED `docs/EVALS.md` "`--slice=SYM:VAR`
def-use row order" claim (0.285 vs 0.268 @1), whose candidate pool is only the lines `--slice` already
chose to emit. **R1 in that wider table is `sliceDefUseRowOrder` itself** (`src/slice.h:3214`, `order=
"defuse"`, shipped and ADOPTED on `main` today under its own, narrower, correctly-scoped claim) — so
"the at-chance ranking" the owner means is today's shipped rule, measured honestly against the pool an
agent actually sees when it does not yet know which lines `--slice` will filter to. This document does
not touch or weaken that narrower, already-true claim; it registers a **second**, additional attempt
aimed at the wider question, and a fallback if that attempt also fails.

## 1. Population — identified by fingerprint, not by count (reproduce first, or STOP)

"The 173" is not "however many rows this round's run happens to produce." Before a single number under
§3's rule is computed, the run must reproduce, **exactly**, `docs/research/slice-line-recall.md`'s own
cascade (§R1) and headline table (§R4), on the same corpus, checkouts and binary convention that note
used:

**Corpus.** `czlll/Loc-Bench_V1` test split, 560 rows, at the note's own
`<assets>/datasets/rows_czlll__Loc-Bench_V1_test_560.json` path (§2). Nothing downloaded, nothing
fetched by this lane or by the round that eventually scores this rule — the asset tree is supplied by
the owner (`$ORCH`'s standing rule; `BRIEF_MACHINE_2026-09-23.md`: *"bench-assets/ is NOT on this
machine... Do not fetch LocBench or any third-party repository yourself"*).

**Cascade (§R1), every stage an exact integer match, no tolerance — these are counts, not statistics:**

| stage | rows | gold lines |
| --- | ---: | ---: |
| dataset | 560 | — |
| multi-function (out of reach by construction) | 208 | 6,809 |
| single-function | 352 | 2,806 |
| …no local checkout | 169 | — |
| …`base_commit` absent | 1 | — |
| **carried to the harness** | **182** | **1,040** |
| …selector refused, plain `FILE:FN` | 3 | — |
| …selector refused, scoped `FILE::CLASS::METHOD` | 2 | — |
| …`--expand` served no body | 2 | — |
| …every gold line outside the resolved span | 2 | — |
| **scored instances** | **173** | — |

**498** (scored instance, inventory variable) pairs; **2,453** `--slice` calls per arm (v1/v2); mean
function span **86.9** lines; mean inventory **14.2** sliceable locals. Selector resolution on the
one-file tree: **177/182 = 97.3%**.

**Headline figures (§R4), reproduced to 3 decimal places as printed — the tolerance is the note's own
rendering, not a re-derived statistic:**

| order | @1 | MRR |
| --- | ---: | ---: |
| R0 source order | 0.029 | 0.154 |
| CTL random control (200 shuffles, seed 20260920) | 0.042 | 0.234 |
| R1 def-use coverage (= `sliceDefUseRowOrder`'s own rule, applied to the whole-span pool) | 0.048 | 0.289 |
| R2 flow depth (`--slice-flow=both`) | 0.048 (identical to R1 to every digit) | 0.289 |

**Every check above must pass before this round reports a single number under §3.** If any one does
not reproduce — a different cascade count, a different R0/R1/CTL @1 to 3dp — **the run stops there**
and reports exactly that: which check failed and what was measured instead, naming the asset tree path
and the binary's `built_from=` sha, in the same shape as
`docs/research/slice-line-recall.md`'s own §9 harness invocation:

```bash
python3 bench/slice/locbench_gold.py        --assets <assets> --json gold.json
python3 bench/slice/run_slice_linerecall.py --gold gold.json --bin build/ripwire --work <scratch> --json results.json
python3 bench/slice/inspect_slice_misses.py --results results.json --gold gold.json
```

No `served_syms`-style AUROC/threshold sweep applies here (the statistic is Recall@k/MRR over a fixed
candidate pool, not a classifier score); the fingerprint-first discipline is the part of that house
precedent (`origin/lane/served-syms-prereg`, `docs/research/confidence-and-abstention.md` §5.4.1) this
document follows: *check what the population IS before trusting any number computed on it.*

**Every report under this registration — PASS, FAIL, or fingerprint mismatch — must name the asset
tree it read and the scoring binary's `built_from=` sha.** A result that does not name both is not a
report under this registration.

## 2. What this document does NOT re-run

`docs/research/slice-line-recall.md` §R2 (set recall, 0.932/0.995 registered/strict), §R3
(reachability, the 70.8%-out-of-reach ceiling) and §R5 (granularity vs presentation) are cited as prior
knowledge, disclosed here, not re-derived. §10 (rung 3, cross-function reach, killed at `extend_2 =
6.14%`/`14.35%`) is unrelated to line ranking and is not touched by this lane.

## 3. The one attempt — R3, "def-primacy"

**Not source order (R0) and not flow depth (R2, already proven identical to R1 to every digit — §R4
reading 3: an unseeded `--slice-flow=both` hop always lands on a line already in some other variable's
flat slice, so BFS depth carries no information R1's own coverage count does not already have).** R3
is also not a re-run of R1 alone — R1 is already shipped (`sliceDefUseRowOrder`, `order="defuse"`,
ADOPTED on `main` under its own narrower claim) and is exactly the rule the 0.048-vs-0.042 figure
already measures at chance-adjacent margin. R3 adds one bit R1 discards.

### 3.1 The rule, fully specified, zero fitted parameters

For a candidate line `l` in the resolved function's span (same pool as §R4):

- `hasDef(l)` — **1** iff any inventory-tracked local has a **definition-role** occurrence on `l`
  (`SliceLineRow::hasDef`, `src/slice.h:2687`, already folded by `sliceFoldOcc` — `src/slice.h:2696`
  — from each occurrence's `isDef` flag, `src/slice.h:274`, set for `OccT::Param`, `OccT::Decl` and a
  def-shaped `OccT::Assign`, `src/slice.h:578-623`); **0** otherwise.
- `coverage(l)` — R1's own already-registered statistic, unchanged: the count of distinct inventory
  local names with **any** occurrence (def or use) on `l` (`docs/EVALS.md` "`--slice=SYM:VAR` def-use
  row order"; computed identically to `sliceDefUseRowOrder`'s `coverage[]`, `src/slice.h:3239-3250`).
- **Score = the lexicographic key `( hasDef(l) desc, coverage(l) desc, l asc )`.** A line the def-use
  filter never touches (`coverage(l) = 0`) sorts after every touched line, ties broken by source line
  ascending — the same "never left to container order" total-order discipline `sliceDefUseRowOrder`'s
  own doc comment states (`src/slice.h:3204-3211`).

**Zero fitted parameters.** `hasDef`, `coverage` and `l` are all facts `--slice` already computes for
every row it emits; nothing here is a threshold, weight or cutoff chosen by looking at gold lines. R3
is a **refinement** of R1, not a replacement: wherever R1 already places one line ahead of another, R3
either agrees or promotes a definition line ahead of a use-only line of equal or lower coverage — it
can only move rank **within** an R1 tie-class or **across** the def/non-def boundary, never invert an
R1 coverage difference.

### 3.2 Mechanistic justification, from the baseline's own analysis — no new inspection performed here

1. **The classifier this rule reads is already validated as reliable, on this exact corpus.**
   `docs/research/slice-line-recall.md` §R2: every one of the 100 misses under the *registered* oracle
   was inspected, and **97 of 100** are lines where the variable's name is not a real `NAME` token at
   all — docstring prose, a comment, a string literal, an f-string prefix. Under the *strict* (tokenizer)
   oracle, v1 recovers **99.5%** of gold lines that genuinely name a local. The 3 survivors are all a
   keyword-argument name shadowing a local — a case §8 Q4 already flags as an open question about the
   **oracle**, not the classifier. **The def/use role split (`isDef`/`isUse`) is computed by the exact
   same occurrence classifier this 99.5% figure already validates** (`SliceOcc::t`/`isDef`/`isUse`,
   `src/slice.h:266-278`) — conditioning R3 on `hasDef` does not import the oracle's own noise (comment
   and string false positives) back into the rule, because that noise was never in the classifier to
   begin with; it was in a subset of the *gold* labels the classifier was scored against.
2. **A structural prior, independent of this corpus.** A fix to a bug is disproportionately the line
   that *computes or reassigns* the value that turns out wrong — the definition site — rather than an
   arbitrary later read of it; this is the same intuition classical backward program slicing seeds a
   slice at. R1's coverage-only rule is blind to this distinction: a line can carry high coverage while
   consisting entirely of reads. R3 adds exactly the one bit R1 discards, and discards nothing R1 already
   uses (coverage remains the tie-break).
3. **Why not another `--slice-flow`-shaped signal.** §R4 reading 3 already showed unseeded flow depth
   (R2) is a provable no-op over R1 — this is stated as a fact already measured, not re-tested here. A
   role signal is structurally different from a BFS-depth signal: it needs no flow substrate at all
   (v1-only; `--slice-flow` is not invoked by R3), so it cannot inherit R2's specific redundancy, which
   is a property of the *flow* relation, not of ranking signals in general.

### 3.3 Determinism

`hasDef` is a `bool` (0/1), `coverage` is a `std::uint32_t`, `l` is a `std::uint32_t` — a pure integer
lexicographic sort, the same discipline `sliceDefUseRowOrder` already uses and `CONTRIBUTING.md`
requires (*"A sort has no tolerance band... run twice, `diff -q` the bytes"*; no float score, no
epsilon tie-break). No `string_view` comparator is introduced by this rule; where the implementation
touches one (name lookups reused from `sliceDefUseRowOrder`), it uses `rw::sortutil::svLess`, never
`operator<` (`src/infra/sortutil.h`; the exact rule `847c9d89` fixed for the existing function).

## 4. The verdict rule — fixed now, before any number exists

Computed identically to `docs/research/slice-line-recall.md` §R4's own harness: same population (§1),
same candidate pool (every line of the resolved function span), same metrics (Recall@{1,3,5,10,20},
MRR, instance mean, n = 173).

**Margin bar, pre-registered rather than "CI excludes zero" alone.** R1's own margin over chance was
+0.006 (0.048 − 0.042 @1) — the baseline note's own reading of that number: *"no effect worth naming"*
(§R4 reading 1). A margin that merely repeats R1's scale is not a fix. **The pre-registered bar is a
margin at least three times R1's own — `R3_recall@1 − CTL_recall@1 ≥ 0.018`, stated as `≥ 0.02`** — set
from the baseline's own prior reading, before this round's number exists, not fit to it.

**Uncertainty — bootstrap by instance, fixed seed.** Resample the **173 scored instances** with
replacement, 173 draws per resample (not the 498 instance×variable pairs — the clustering unit is the
LocBench instance, so a multi-variable instance is not treated as several independent draws), pool
every (instance, variable) pair belonging to the resampled instances, recompute Recall@1 for R3, R1,
R0 and CTL on the pooled sample, and repeat. **Fixed seed `"ripwire-arise-line-rank-v1"`, fixed 10,000
resamples.** Report the 95% CI of `R3 − CTL`, `R3 − R1`, `R3 − R0` at Recall@1, plus the same for MRR
(reported beside the Recall@1 verdict, never instead of it — the registered metric is @1, per the
owner's own citation of "0.048 vs 0.042").

**Verdict, exactly:**

- **PASS ("ADOPT R3"):** `R3_recall@1 − CTL_recall@1 ≥ 0.02` **and** its 95% CI excludes 0 **and**
  `R3_recall@1 > R1_recall@1` **and** `R3_recall@1 > R0_recall@1`. All four conditions, not any one.
- **FAIL (the stop condition fires):** any one of the four does not hold. **`--slice` stops claiming to
  rank lines over the whole-function pool**: the shipped default emits a **stated order** (source
  order, line ascending — no coverage, no def/use signal), and every place that described an ordering
  as a ranking (root `order=` attribute, its legend entry, `--help`, `docs/COMMANDS.md`) says instead
  that the order is a presentation order, not a ranking, for the reader who was told otherwise before.
  This governs the **wide-pool** claim only — it does not touch or retract the narrower, already-true,
  separately-scoped `docs/EVALS.md` "def-use row order" ADOPT (0.285 vs 0.268 @1, over the
  already-filtered rows), which is a different, already-measured population and is not re-litigated by
  a FAIL here.
- **Fingerprint mismatch:** §1's reproduction fails. No PASS/FAIL is reported; only which check failed.

**Self-reject, carried from the house precedent (`served_syms` §5.4.4's SR-family), restated for this
rule.** A `R3` that clears the margin bar **in-sample** on the 173 licenses "worth shipping as the
default," not "proven" — there is no held-out replication population for this corpus (all 173 usable
instances are spent by this round; unlike `served_syms`'s 92-vs-40 split, LocBench V1's Python
single-function population is exhausted by the baseline note's own §R1 cascade). This is disclosed as a
limit, not hidden: a PASS here is a single-sample result, reported as such, never as "shippable and
independently validated."

## 5. `--slice-flow=both` disclosure — pre-registered here, ALREADY LANDED on `main`

**This half of the #318 row is already shipped and does not wait on this lane's verdict.** Checked at
this document's own base commit (`main` / `origin/main` at `60b65f02`):

- `src/slice.h:3490-3493` emits `flow_redundant="1"` on the `<slice>` root exactly when
  `flowSpec->dir == SliceFlowDir::Both && seedInfo == nullptr` — unseeded `both`, the case
  `docs/research/slice-line-recall.md` §R4 reading 3 measured as provably redundant (unioned reach
  equals the flat inventory's own union, to 16 decimal places, 0.5126 both).
- The disclosure is documented in `--help` (`src/cli.h:1879-1882`) and `docs/COMMANDS.md:3313`, and
  carries the measurement's own citation and mitigation ("seed it via `--at=FILE:LINE` for real reach
  — measured +8.6pp Recall@3 there, `R2-oracle` in the baseline note's §R4").
- It is **never gated** — an unseeded `both` still runs and still answers; the attribute discloses,
  it does not refuse, matching CONTRIBUTING's degrade-not-fail ladder.

**What this document registers, then, is confirmation, not a new commitment:** this pre-registration
found the disclosure already satisfies the #318 row's second improvement task, cites its exact site and
behavior above so a reviewer can check it without re-deriving it, and states plainly that **commit 2 of
this lane makes no `--slice-flow` change** — there is nothing left to land here. Any future change to
`SliceFlowDir::Both`'s unseeded semantics must keep `flow_redundant="1"`'s condition and text truthful,
or update this section.

## 6. Licensed sentences, per outcome — for the #318 reply (the owner sends it)

| outcome | what is reported | the sentence it licenses |
| --- | --- | --- |
| **Fingerprint mismatch** | which §1 check failed, what was measured instead, asset tree + binary sha | *"Line ranking over the whole function span had never been scored against a pre-registered rule with a margin and a confidence interval — only the narrower, already-shipped 'rank the lines `--slice` already chose to show' claim had. We pre-registered one honest attempt (def-primacy: definitions before uses, coverage as the tie-break) and a decision rule before looking at any number. The asset tree available when we tried to score it did not reproduce the 173-instance population our own prior note measured 0.048-vs-0.042 on, so no verdict is reported from this attempt."* |
| **PASS** | R3's Recall@{1,3,5,10,20} and MRR, the margin over CTL/R1/R0 with its 95% CI (10,000-resample, seed named), the per-pair better/worse/tied split against R1 | *"We pre-registered one honest attempt at ranking — definitions before uses, then coverage, zero fitted parameters — before running it. It clears the bar we set in advance: `<margin>` over chance `[CI]`, and it beats both the coverage-only rule already shipped and plain source order. It is now the default order `--slice` emits. This is a single-sample, in-corpus result; we have no held-out population left in this dataset to replicate it on."* |
| **FAIL** | R3's numbers against the same bands, stated as a negative result with the same rigor a PASS would carry | *"We pre-registered one honest attempt — definitions before uses, then coverage — before running it, per your rule that a ranking claiming to rank at chance is the `--adaptive` defect in another costume. It did not clear the pre-registered bar (`<numbers>`). Per our own stop condition, `--slice` no longer claims to rank lines over the whole function: it emits them in source order and says so in the legend and `--help`. The narrower claim — that among the lines `--slice` already selects, def-use coverage beats a random shuffle — still stands on its own, separately measured, and is not affected."* |

## 7. Judgement calls for an adversarial reviewer

- **§0's reading of "0.048 vs 0.042" as the R4 whole-pool figure, not the EVALS.md 0.285-vs-0.268
  figure.** Both exist on `main`/the cited branch; PLAN_063's own row quotes the R4 numbers verbatim, so
  this reading is textual, not inferred — but a reviewer should check `$ORCH/PLAN_063.md` line 127 and
  `docs/research/slice-line-recall.md` §R4 against this claim directly rather than trust this document.
- **The margin bar (`≥ 0.02`, "3× R1's own margin") is a judgement call, not a fact the baseline note
  states.** It is derived from the note's own qualitative reading ("no effect worth naming" at +0.006)
  rather than from a formal power calculation — a reviewer could reasonably argue for a different
  multiplier, and the number is stated here precisely so it can be argued with before any data exists,
  not defended after.
- **R3 is scoped to the same population and pool R4 used (LocBench V1, Python, single-function,
  whole-function-span candidate pool).** Nothing here re-opens §6 of the baseline note ("what we are NOT
  claiming") — R3's verdict, PASS or FAIL, is a claim about this primitive on this corpus, not a general
  line-ranking claim, exactly as the baseline note already disclaims for its own numbers.
- **The self-reject in §4 (no held-out replication population) is a real limit, not a formality** — a
  reviewer who wants a replication-backed PASS should say so before this round is scored, since there is
  no second LocBench-shaped Python corpus staged anywhere in this repo's `bench/` tree today.
  `bench/mulocbench` (PR #314) is a plausible future source and is explicitly not assumed here.
- **§5's claim that the `--slice-flow=both` disclosure is already complete is a reviewer-checkable fact,
  not a measurement** — the citation is exact line numbers on `main` at this document's base commit;
  re-read `src/slice.h:3480-3493` directly rather than trust the excerpt.
- **The FAIL sentence in §6 deliberately does not retract the already-ADOPTED narrower claim.** A
  reviewer who reads "ranking is at chance" as an indictment of *every* `--slice` ordering claim should
  weigh §0's distinction before agreeing — the two claims are measured on different pools and this
  document treats them as severable by design, which is itself a judgement call worth checking.

## 8. Reproducing (once the corpus is available)

```bash
python3 bench/slice/locbench_gold.py        --assets <assets> --json gold.json
python3 bench/slice/run_slice_linerecall.py --gold gold.json --bin build/ripwire --work <scratch> --json results.json
python3 bench/slice/inspect_slice_misses.py --results results.json --gold gold.json
```

Identical to `docs/research/slice-line-recall.md` §9's first three commands — this document reuses that
harness rather than forking it; scoring R3 needs one additional ranking rule registered in the harness's
own rank-rule table (§9's `run_slice_linerecall.py`, which lives on `origin/lane/research-arise-slice`
and is not committed to this tree, same as the baseline note itself states), not a new script.
