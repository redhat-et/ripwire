# ARISE line ranking — one honest attempt, PRE-REGISTERED 2026-09-23 (before any src/ change, before any number below exists)

**Status: PRE-REGISTRATION ONLY, round 2. No number in this document was computed by a harness — the
corpus (LocBench V1) is not on this machine and is not fetched, read or scored here.** This document
fixes the population, the one ranking attempt, the verdict rule and the bands before any of them touch
data, so that whichever way the eventual measurement comes out, nothing here can be read as chosen
after seeing it.

**Round 2 revises round 1 after an adversarial review found it NOT READY (`rv-arise-line-ranking.md`),
all before any data existed under either round — the review read the round-1 code and prose, never a
corpus.** Every finding is addressed below, marked inline where it changed something material: the
population fingerprint now registers a CONSTRUCTION RULE and gates on dataset-only counts rather than
one machine's disk state (HIGH-1); a binary-drift re-fingerprint separates "wrong population" from "the
classifier moved" (HIGH-2); the verdict rule now has one margin bar, a bootstrap unit that matches the
metric, and a disclosed power figure (HIGH-3); the FAIL/PASS outcomes are reconciled with the
already-ADOPTED `docs/EVALS.md` ordering rule instead of contradicting it (HIGH-4); the forward-looking
legend/help prose round 1 shipped is reverted — today's default `--slice=SYM:VAR` output is
byte-identical to `main` again (HIGH-5); the harness-side R3 rule now has a real, self-tested command
(`bench/slice/score_arise_linerank.py`, MEDIUM-2); the replication-population claim is corrected
(MEDIUM-3); the unit test's vacuous item is fixed and a real-classifier equivalence arm is added
(MEDIUM-4); and a structural limit of the rule (the function-signature line) is disclosed rather than
found later (Attack 2). §7 keeps a judgement-call log across both rounds.

**Baseline this document cites, and does not re-derive.** `docs/research/slice-line-recall.md` on
`origin/lane/research-arise-slice` (draft PR #318, unmerged — the file does not exist on `main` or on
this branch; every figure below quoted from it is a citation, not a number this lane produced). Its
§10 "ARISE rung 3" is a separate question (cross-function call-graph reach) and is out of scope here.

## 0. Why this document exists — the owner's ruling

The 0.6.3 planning record's row for the ARISE draft PR (#318) reads: *"line ranking is at chance (0.048
vs 0.042) and source order is worse than random — fix it or stop ranking lines."* Its "ARISE line
ranking" stop condition: *"If ranking still does not beat random after one honest attempt, stop ranking
lines and emit them in a stated order."* Owner ruling, 2026-09-21: *"prioritize the fix, then send the
email"* — line ranking is now the first priority of 0.6.3. Owner ruling, 2026-09-23: pre-register and
write the one honest attempt now, committed before any data; scoring waits for the corpus. (That
planning record is an internal orchestration document, not part of this tree, and is not cited by path
here for that reason — the quotations above are reproduced in full so this section stands on its own.)

The **0.048 vs 0.042** the owner cites is `docs/research/slice-line-recall.md` §R4's **R1 def-use
coverage @1** against its **CTL random-control @1**, over the candidate pool of **every line in the
resolved function's span** — not the narrower, already-ADOPTED `docs/EVALS.md` "`--slice=SYM:VAR`
def-use row order" claim (0.285 vs 0.268 @1), whose candidate pool is only the lines `--slice` already
chose to emit. **R1 in that wider table is `sliceDefUseRowOrder` itself** (`src/slice.h:3214`, `order=
"defuse"`, shipped and ADOPTED on `main` today under its own, narrower, correctly-scoped claim) — so
"the at-chance ranking" the owner means is today's shipped rule, measured honestly against the pool an
agent actually sees when it does not yet know which lines `--slice` will filter to. This document does
not touch or weaken that narrower, already-true claim; it registers a **second**, additional attempt
aimed at the wider question, and a DISCLOSURE change (not a new fallback rule — §4.3 corrects round 1's
attempt at one) for what the legend says if that attempt fails.

## 1. Population — construction rule, then fingerprint by tier (reproduce first, or STOP)

**Round-1 defect, per `rv-arise-line-ranking.md` HIGH-1: this section demanded an exact match on
disk-state counts (`…no local checkout 169`, `…base_commit absent 1`) without ever stating the rule
that CONSTRUCTS the 182-row carried set — so a correctly rebuilt tree (a clean checkout of exactly the
held-out repositories, nothing extra) reads `170 / 0`, not `169 / 1`, and round 1's exact-match rule
would have refused the right population.** Fixed by registering the construction rule explicitly, and
by fingerprinting the CARRIED set rather than the disk-state cascade that produces it.

### 1.1 Corpus and construction rule

`czlll/Loc-Bench_V1` test split, 560 rows, at `<assets>/datasets/rows_czlll__Loc-Bench_V1_test_560.json`
(the baseline note's own `<assets>` placeholder convention, §2). Nothing downloaded, nothing fetched by
this lane — the asset tree is supplied by the owner; this machine's standing rule is not to fetch
third-party data from a lane.

**The population is registered, before any run, as:** *the 352 single-function rows of the dataset
(`edit_functions_length == 1`) whose `repo` is one of the 88 repositories already checked out for this
project's held-out measurement round, AND whose `base_commit` object is present in that checkout* —
predicted **182 rows / 1,040 gold lines**, computable from the dataset json ALONE, independent of which
machine or which binary reads it. Either an export of the old measurement round's own tree (every row's
`base_commit` present by construction) or a freshly cloned 88-repo tree with every one of those 182
rows' `base_commit` objects fetched satisfies the rule — **both are the SAME 182 rows**, because the
construction rule names the rows by `repo ∈ held-out-88 ∧ single-function`, not by which specific disk
happened to serve them.

**Adjudicating the 169/1 vs 170/0 mismatch, in advance, per HIGH-1:** these two disk-state cascades
(*"…no local checkout"* / *"…base_commit absent"*) are NOT part of the registered population — they are
an artifact of which extra, non-held-out directories a PARTICULAR checkout happens to also contain. The
old measurement round's disk carried two directories outside the 88 held-out repos, and exactly one of
those two extra directories' rows was the row later counted as `base_commit absent`; a clean 88-only
checkout has no such extra directory, so it reports `170 / 0` instead — same 182 rows carried either
way, split differently across two buckets neither of which gates. **What gates is the CARRIED total:
182 rows, 1,040 gold lines.** Report `…no local checkout` and `…base_commit absent` for the record on
whatever disk a given run used; they are floors on that disk's own completeness, never a fingerprint
check.

**The fetch step this needs, named rather than left implicit (HIGH-1):** a fresh 88-repo checkout is
shallow by default and resolves only a minority of the 182 `base_commit`s (own measurement: 46 of 182 on
a depth-1 clone). The remaining ~136 commit objects must be fetched (`git fetch origin <sha>` per row,
or an equivalent deepening) before the harness's own `no_commit` stage can be trusted to report zero on
a freshly built tree. **This is an owner-run step — lanes fetch nothing — and this lane does not perform
it or ask for it to be performed now.** A round that scores this rule states, in its own report, whether
it read the old round's export (commits already present) or a freshly deepened checkout (and how many
commits it fetched).

### 1.2 Fingerprint tiers — gate on (a) and (b) exactly, (c) to a stated tolerance; (LOW-2)

**(a) Dataset-only (no binary, no checkout needed) — exact integer match, no tolerance:**

| stage | rows | gold lines |
| --- | ---: | ---: |
| dataset | 560 | — |
| multi-function (out of reach by construction) | 208 | 6,809 |
| single-function | 352 | 2,806 |
| **carried** (single-function ∧ repo ∈ held-out-88) | **182** | **1,040** |

`bench/slice/score_arise_linerank.py`'s `fingerprint_dataset_only()` computes exactly this tier from the
dataset json and a held-out-repo list, with no binary invoked (§8).

**(b) Binary-dependent counts — exact integer match, no tolerance (a specific binary's classification,
not a statistic with sampling noise):**

| stage | rows |
| --- | ---: |
| …selector refused, plain `FILE:FN` | 3 |
| …selector refused, scoped `FILE::CLASS::METHOD` | 2 |
| …`--expand` served no body | 2 |
| …every gold line outside the resolved span | 2 |
| **scored instances** | **173** |

**498** (scored instance, inventory variable) pairs; **177/182 = 97.3%** selector resolution.

**(c) Statistics (§R4 headline figures) — tolerance `|measured − printed| ≤ 0.0005 + 1e-9` per figure**
(the note's table is a hand-rendered 3dp of a JSON mean; a tolerance centered on the exact rendering
rather than a bare 3dp string match, the same fix `served_syms` §5.4.1 HIGH-2 needed for its own AUROC
table):

| order | @1 | MRR |
| --- | ---: | ---: |
| R0 source order | 0.029 | 0.154 |
| CTL random control (200 shuffles, seed 20260920) | 0.042 | 0.234 |
| R1 def-use coverage (= `sliceDefUseRowOrder`'s own rule, applied to the whole-span pool) | 0.048 | 0.289 |
| R2 flow depth (`--slice-flow=both`) | 0.048 (identical to R1 to every digit) | 0.289 |

Reported only, never gating: mean function span 86.9 lines; mean inventory 14.2 sliceable locals;
2,453 `--slice` calls per arm (v1/v2) — these move with corpus/binary detail without indicating a
population mismatch on their own.

**All of (a), (b) and (c) must pass before this round reports a single number under §4.** If (a) does
not match, the population itself is wrong (a different construction, a different dataset file) and the
run stops immediately — (b)/(c) are not even attempted. If (a) matches but (b) or (c) does not, see §1.3
before concluding the population is wrong. Every stop reports which check failed and what was measured
instead, naming the asset tree path and the binary's `built_from=` sha.

### 1.3 Binary-drift re-fingerprint — separating "wrong population" from "the classifier moved" (HIGH-2)

§R4's own figures were produced by `built_from=755f9026f`. The binary that would score this round is
necessarily later (`slice.h` changed in several ordering/legend commits since, none touching the
row-set or the inventory computation, so reproduction is *likely* — but "likely" is not a fingerprint).
**If tier (a) matches but a tier-(b) or tier-(c) figure does not: before concluding the population is
wrong, rebuild `755f9026f` (the exact binary `built_from=` names) and re-run the SAME fingerprint check
with it.**

- A match under `755f9026f` is a **population PASS with disclosed binary drift** — report both
  binaries' tier-(b)/(c) figures side by side, and use the CURRENT binary's own figures as R0/R1/CTL for
  §4's verdict (the attempt is scored against what the shipping binary actually does today, not against
  a five-commits-old snapshot).
- A mismatch under `755f9026f` too is a genuine **population FAIL** — the population itself, not the
  binary, is wrong; stop and report which tier-(a) fact does not hold.

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
tree it read and the scoring binary's `built_from=` sha (both binaries', if §1.3 fired).** A result that
does not name both is not a report under this registration.

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

**Two drafting corrections, made before any code or number existed, recorded so the final rule is not
mistaken for the first thing tried.** First: `--slice=SYM:VAR`'s rows are pre-filtered to lines where
the **seed variable VAR itself** occurs (`sliceFoldLines( scan.occ )`, `src/slice.h`, where `scan.occ`
is documented as *"VAR-mode occurrences... empty when var empty"* — the seed's own occurrences, not
every local's) — so `SliceLineRow::hasDef` (folded from `scan.occ`) answers "does the seed have a def
on `l`", not the seed-free question R1 is defined against. Second, having caught that: R1 itself
(§4b of the baseline note) is explicitly **seed-free — "it unions over the whole inventory and never
looks at the gold"** — so a `hasDef` built from one seed would not even be R1's own kind of statistic.
The rule below reads role information the SAME seed-free way R1 already reads coverage, from every
local's occurrences (`scan.all`), not from one seed's rows:

For a candidate line `l` in the pool `--slice=SYM:VAR` ranks (its own seed-restricted row set, the
same pool `sliceDefUseRowOrder` orders today):

- `hasAnyDef(l)` — **1** iff **any** inventory local (not only the seed; every binding in
  `scan.bindings`, read through `scan.all`, the same whole-inventory substrate `coverage(l)` below
  already scans) has a **definition-role** occurrence on `l` (`SliceOcc::isDef`, `src/slice.h:274`, set
  for `OccT::Param`, `OccT::Decl` and a def-shaped `OccT::Assign`, `src/slice.h:578-623`); **0**
  otherwise. New code (`sliceRowHasAnyDef`), but new only in the sense of a new SCAN over facts
  `--slice` already classifies — no new classification rule.
- `coverage(l)` — R1's own already-registered statistic, unchanged: the count of distinct inventory
  local names with **any** occurrence (def or use) on `l` (`docs/EVALS.md` "`--slice=SYM:VAR` def-use
  row order"; computed identically to `sliceDefUseRowOrder`'s original inline coverage computation,
  extracted unchanged into the shared `sliceRowCoverage` helper for this attempt).
- **Score = the lexicographic key `( hasAnyDef(l) desc, coverage(l) desc, l asc )`**, then the same
  binding-line / row-index tail `sliceDefUseRowOrder` already uses so nothing is left to container
  order (`src/slice.h`).

**Zero fitted parameters.** `hasAnyDef`, `coverage` and `l` are all facts computed from data `--slice`
already classifies; nothing here is a threshold, weight or cutoff chosen by looking at gold lines.
**R3 is not a strict refinement of R1.** Making `hasAnyDef` the primary key CAN invert an R1 coverage
difference: a line with a definition but otherwise low coverage is promoted ahead of a higher-coverage
line with no definition on it at all. That inversion is not a bug to disclaim; it is the one bit R1
discards and the entire mechanism §3.2 argues should matter — a rule that only ever agreed with R1
would have no chance of moving Recall@1 away from R1's own 0.048.

### 3.2 Mechanistic justification, from the baseline's own analysis — no new inspection performed here

1. **The classifier this rule reads is already validated as reliable, on this exact corpus.**
   `docs/research/slice-line-recall.md` §R2: every one of the 100 misses under the *registered* oracle
   was inspected, and **97 of 100** are lines where the variable's name is not a real `NAME` token at
   all — docstring prose, a comment, a string literal, an f-string prefix. Under the *strict* (tokenizer)
   oracle, v1 recovers **99.5%** of gold lines that genuinely name a local. The 3 survivors are all a
   keyword-argument name shadowing a local — a case §8 Q4 already flags as an open question about the
   **oracle**, not the classifier. **The def/use role split (`isDef`/`isUse`) is computed by the exact
   same occurrence classifier this 99.5% figure already validates** (`SliceOcc::t`/`isDef`/`isUse`,
   `src/slice.h:266-278`) — conditioning R3 on `hasAnyDef` does not import the oracle's own noise
   (comment and string false positives) back into the rule, because that noise was never in the
   classifier to begin with; it was in a subset of the *gold* labels the classifier was scored against.
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

`hasAnyDef` is a `std::uint32_t` valued 0 or 1, `coverage` is a `std::uint32_t`, `l` is a
`std::uint32_t` — a pure integer lexicographic sort, the same discipline `sliceDefUseRowOrder` already
uses and `CONTRIBUTING.md` requires (*"A sort has no tolerance band... run twice, `diff -q` the
bytes"*; no float score, no epsilon tie-break). No `string_view` comparator is introduced by this rule;
where the implementation touches one (the same tracked-local-name lookup `sliceRowCoverage` already
performs, reused by `sliceRowHasAnyDef`), it uses `rw::sortutil::svLess`, never `operator<`
(`src/infra/sortutil.h`; the exact rule `847c9d89` fixed for the existing function).

### 3.4 A known structural limit, disclosed now rather than found after data (`rv-arise-line-ranking.md` Attack 2)

A function's parameter list rows every parameter as `k="def" t="param"` (`OccT::Param` is def-shaped,
§3.1). So the signature line's own coverage is (at least) the function's own parameter count — on many
functions, that already ties or beats every other single line's coverage, since few individual
statements name that many distinct locals at once. **On such a function, R0 (source order — the
signature is line 1), R1 (coverage-max) AND this attempt (`hasAnyDef`=1 from the params, at that same
maximal coverage) all rank the signature line first alike.** R0@1 = 0.029 in the baseline note is
essentially "the signature line is gold" already; R1's 0.048 is only +0.019 above that, consistent with
R1 mostly picking the signature line too. **This attempt's only @1 gains over R1 can come from instances
where R1's own top pick was a pure-use line, not the signature** — the signature-line case is a
structural ceiling shared by all three orders, not an advantage of this one.

**Stated plainly so it is not read as an after-the-fact excuse for a small margin, and not amended: this
rule does NOT special-case or exclude the signature line.** If a future round wants that exclusion, it
is a DIFFERENT attempt and must be pre-registered as one before any data, per the owner's own rule that
a construct is not amended after seeing what it does to a result.

## 4. The verdict rule — fixed now, before any number exists

Computed identically to `docs/research/slice-line-recall.md` §R4's own harness: same population (§1),
same candidate pool (**every line of the resolved function span** — not `--slice=SYM:VAR`'s own,
narrower, seed-restricted row set), same metric (Recall@1, **computed ONCE PER INSTANCE over that
instance's own gold set** — `run_slice_linerecall.py`'s `rank_scores()`, an instance mean over n = 173;
@{3,5,10,20} and MRR are reported beside it, never instead of it, but @1 is what gates).

**Scope note, flagged explicitly rather than left implicit.** §3's `hasAnyDef(l)`/`coverage(l)` are
seed-free by construction (§3.1), so they are well-defined over R4's full candidate pool exactly the
way R1/R0/CTL already are — the harness that scores this verdict computes them over **every** line of
the function (most of which no one seed's `--slice=SYM:VAR` output ever lists), the same way
`run_slice_linerecall.py` already computes R1 there (§9). **Commit 2's `src/` change is a narrower
thing: it applies the identical formula to `--slice=SYM:VAR`'s own existing, seed-restricted row set**
— because that is the one CLI surface that shows a human or agent a ranked list of lines today; there is
no existing verb that emits "every line of the function, ranked." §7 flags this scope split as a
judgement call, corrected below (§4.3) after review: **the shipped-vs-measured relationship it draws to
`order="defuse"` is NOT what §4.3 ships — read §4.3 before assuming a PASS here ships `defrole`.**

### 4.1 Margin bar — ONE number (`rv-arise-line-ranking.md` HIGH-3)

**Round-1 defect:** an earlier draft of this section stated the bar as both `≥ 0.018` and `≥ 0.02` in
the same sentence — two different thresholds, so a margin of 0.019 would PASS one reading and FAIL the
other. Fixed: **the bar is `R3_recall@1 − CTL_recall@1 ≥ 0.02`, exactly, one number.** (Derivation kept
for the record, not as a second threshold: R1's own margin over chance was +0.006 @1 — *"no effect
worth naming"* in the baseline note's own words, §R4 reading 1 — and 0.02 is roughly three times that,
rounded; a reviewer could reasonably argue for a different multiplier, which is why the derivation is
shown rather than hidden, per §7.)

**Redundancy, noted rather than relied on:** given the fingerprinted CTL = 0.042, R1 = 0.048, R0 = 0.029
(§1.2c), clearing `R3@1 ≥ CTL@1 + 0.02 = 0.062` already implies `R3@1 > R1@1` and `R3@1 > R0@1`. The
verdict below still checks both explicitly (§4.2's four conditions) rather than assuming this holds,
because the fingerprint's own tolerance band (§1.2c) means CTL/R1/R0 are not pinned to infinite
precision — the two conditions are cheap insurance against exactly that tolerance being exercised.

### 4.2 Uncertainty and the verdict, exactly — bootstrap unit fixed to match the metric (HIGH-3)

**Round-1 defect:** an earlier draft said to *"pool every (instance, variable) pair belonging to the
resampled instances, recompute Recall@1... on the pooled sample"* — but Recall@1 here is an
INSTANCE-level statistic (§4's own metric line, corrected above); there is no per-pair quantity to pool
at this candidate pool (the 498 pairs exist only for the separate §R2 set-recall metric). Fixed:

**Bootstrap, exactly:** resample the **173 scored instances** with replacement, 173 draws per resample
(with repeats — instances may repeat, none are dropped in expectation). For each resample, compute the
mean of (that instance's `r3@1` − that instance's `ctl@1`) over the 173 drawn instances — a **paired**
statistic, since both values come from the SAME resampled instance each draw. Repeat **10,000** times,
`random.Random("ripwire-arise-line-rank-v1")` (Python's stdlib PRNG, this exact seed string). The
**95% CI is the PERCENTILE method**: the 2.5th and 97.5th percentiles of the 10,000 resample means.
`bench/slice/score_arise_linerank.py`'s `paired_bootstrap_ci()` is this rule, executable, self-tested on
synthetic instances (§8).

**Power, disclosed rather than computed-and-hidden:** per-instance Recall@1 values are 0 or `1/|G|` for
that instance's gold set — a small-valued, mostly-zero statistic. At n = 173 the standard error of the
paired mean difference is large enough (empirically, on synthetic data shaped like this: ~0.01) that a
TRUE effect of +0.02 — exactly the registered bar — can fail the CI-excludes-zero clause roughly half
the time by chance alone. **A FAIL under this rule is read as "did not clear the bar at this sample
size," never as proof the underlying signal does not help** — this sentence is normative for §6's FAIL
sentence, not only a caveat here.

**Verdict, exactly, all four conditions required:**

1. `R3_recall@1 − CTL_recall@1 ≥ 0.02` (the point estimate, §4.1).
2. The paired-bootstrap 95% CI of that same difference excludes 0 on the positive side (its 2.5th
   percentile is `> 0`).
3. `R3_recall@1 > R1_recall@1`.
4. `R3_recall@1 > R0_recall@1`.

- **PASS-wide-pool:** all four hold. This licenses moving to §4.3's narrow-pool check before anything
  ships — a wide-pool PASS ALONE does not license shipping `defrole` (§4.3).
- **FAIL:** any one of the four does not hold. See §4.3 — FAIL does NOT mean "un-ship `order=defuse`."
- **Fingerprint mismatch:** §1's reproduction fails. No PASS/FAIL is reported; only which check failed.

### 4.3 Reconciling the outcome with the already-ADOPTED `docs/EVALS.md` rule (`rv-arise-line-ranking.md` HIGH-4)

**Round-1 defect, stated plainly: round 1's FAIL branch un-shipped `order="defuse"` while its own §0
claimed not to touch it — both cannot be true.** `docs/EVALS.md`'s "`--slice=SYM:VAR` def-use row
order" registration pre-registered AND MEASURED its own, narrower, ALREADY-ADOPTED claim on 2026-09-22:
*"ADOPT R1 ordering iff the emitted-order MRR beats the random control... Otherwise stop ranking: emit
in source order"* — and it ADOPTED (MRR 0.628 vs random-control 0.602; @1 0.285 vs 0.268; **plain
source order measured WORSE than random on those same rows, 0.525 vs 0.602**). Round 1's FAIL branch
would have replaced `order="defuse"` — proven to beat random on the rows in play — with plain source
order — proven to LOSE to random on the very same rows — because a DIFFERENT claim (ranking the whole
function span, which `--slice` never advertised; its own legend already scopes "ranked" to "these
rows") failed. Symmetrically, round 1's PASS branch would have shipped `order="defrole"` on the rows
though `defrole` was verdict-ed only on the wide, whole-function pool (§4.3.2) — never measured on the
EVALS narrow pool at all.

**Resolved, before any data, as follows — recommendation (i) of the review, adopted:**

#### 4.3.1 FAIL: keep `order="defuse"`; change ONLY the disclosure, and only when the verdict is real

A wide-pool FAIL does not un-ship anything. `--slice=SYM:VAR`'s shipped row order stays exactly
`sliceDefUseRowOrder` (`order="defuse"`) — the EVALS ADOPT governs the rows, and this attempt failing a
DIFFERENT, wider question does not retract it. **What a real FAIL changes is the legend/help
DISCLOSURE**: the `order=` reading is amended to scope "ranked" explicitly to "these rows" and to state
that, over the whole function span, this coverage rule ranks at chance (§0's own 0.048-vs-0.042) — that
IS "stop claiming to rank lines [beyond what is proven]," the owner's actual rule, without touching a
claim that is separately true. **This disclosure change is NOT shipped by this lane, on purpose**: it
describes a verdict that does not exist yet, and landing it now would repeat exactly the "forward-looking
prose in what ships today" defect §4.5 (HIGH-5) already found and reverted. It is a change a FUTURE
commit makes WITH the verdict, not before it — this document is where its wording is pre-registered
(§6), not where it is shipped early.

#### 4.3.2 PASS: `defrole` ships only if it ALSO clears EVALS' own narrow-pool bar

A wide-pool PASS (§4.2) is necessary but not sufficient to ship `order="defrole"`. Before `defrole`
replaces `defuse`, it must ALSO be measured on EVALS' own narrow pool — the SAME 478 (scored instance,
inventory variable) pairs, the SAME emission-order MRR metric, the SAME RNG — and clear:

**`defrole`'s narrow-pool MRR ≥ `defuse`'s already-measured 0.628.**

- **Wide-pool PASS AND narrow-pool clears:** `order="defrole"` ships (`kSliceLineRankVerdict` flips to
  `Ranked`, plus the legend/help/COMMANDS sites §4.5/MEDIUM-1 lists).
- **Wide-pool PASS but narrow-pool does NOT clear:** the wide-pool result is REPORTED (it is real and
  belongs in the #318 reply) but nothing ships — `order="defuse"` stays the default, exactly as a FAIL
  would leave it, because shipping a row order never measured to be at least as good on the rows
  themselves would repeat round 1's PASS defect. `kSliceLineRankVerdict` stays `Pending`.

Either way, "the constant just flips" (§3's own design) still holds: the CODE decision is binary
(`Pending` stays, or flips to `Ranked`) even though the REASONING that decides it now has two gates
instead of one.

### 4.4 Replication (`rv-arise-line-ranking.md` MEDIUM-3, correcting round 1)

**Round-1 defect: this section claimed *"LocBench V1's Python single-function population is exhausted
by the baseline note's own §R1 cascade"* — false.** From the dataset alone: **170 single-function rows,
in 45 repositories NOT among the 88 held-out directories, were never measured** (no checkout on the
original round) — a replication population of `served_syms`'s own shape (a second sample, disjoint from
the scored 173). **Corrected registration:** the 170-row / 45-repo complement is the replication
population for this rule, kept in a separate assets directory from the held-out 88 (so this stays
disjoint from `served_syms`'s own split, per the review's own note). Replication rule: same construction
(§1.1, restricted to the 45 repos instead of the 88), same binary, same bands (§4.1/§4.2). Fetching
those 45 repositories is an owner decision, not a lane's, and is not assumed to happen. Until it does:

- A wide-pool PASS that also clears §4.3.2's narrow-pool bar is reported as **"worth shipping as
  default,"** not as independently replicated.
- If the owner declines to fetch the 45-repo complement, that is stated explicitly in the eventual
  result, rather than silently treated as "no replication population exists."

### 4.5 Byte-identity of what ships today (`rv-arise-line-ranking.md` HIGH-5)

**Round-1 defect: a claim of "byte-for-byte, zero regression" was checked only at the `<slice>`-element
level; the LEGEND was not checked and had, in fact, grown.** Round 1 added forward-looking prose to
`src/compactlegend.h`'s `order` reading and to `--help`/`docs/COMMANDS.md` describing a verdict that did
not exist — +327 bytes (+29%) on every default `--slice=SYM:VAR` call's legend, a real per-call tax
(the baseline note's own R6 puts v1's mean cost at 1,152 B; this was not a rounding error). **Reverted.**
Every default `--slice=SYM:VAR` output (bare, `--slice-flow=both`, `--slice-flow=back`, `--legend=full`,
`--legend=compact`, `--help=all`) is now byte-identical to `origin/main` at this lane's base commit
(`60b65f0266d779bf5635054b0d9441cbd11822c3`) — checked directly, several fixtures, both binaries, both
legend tiers. **The rule going forward: legend/help text describing an outcome belongs to the commit
that SHIPS that outcome, never to `Pending`.** §4.3.1/§4.3.2 above are written to that rule: their
wording is registered here, for the reply and for the eventual shipping commit to copy, but is not
itself shipped by this lane.

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

Revised after review (HIGH-4): FAIL no longer claims to un-ship `order="defuse"` (it was never un-adopted);
PASS is split into two outcomes, since a wide-pool PASS alone does not license shipping `defrole` (§4.3).

| outcome | what is reported | the sentence it licenses |
| --- | --- | --- |
| **Fingerprint mismatch** | which §1 check failed, what was measured instead, both asset tree paths + both binaries' shas if §1.3 fired | *"Line ranking over the whole function span had never been scored against a pre-registered rule with a margin and a confidence interval — only the narrower, already-shipped 'rank the lines `--slice` already chose to show' claim had. We pre-registered one honest attempt (def-primacy: definitions before uses, coverage as the tie-break), a construction rule for the population, and a decision rule, all before looking at any number. The population we could reproduce did not match the pre-registered construction rule, so no verdict is reported from this attempt."* |
| **PASS, ships** (wide-pool clears §4.2 AND narrow-pool clears §4.3.2) | R3's Recall@{1,3,5,10,20} and MRR, the margin over CTL/R1/R0 with its 95% CI (10,000-resample, seed named), the per-instance better/worse/tied split against R1, `defrole`'s narrow-pool MRR vs `defuse`'s 0.628, the signature-line structural note (§3.4) | *"We pre-registered one honest attempt at ranking — definitions before uses, then coverage, zero fitted parameters — before running it. It clears the bar we set in advance for the whole function span (`<margin>` over chance `[CI]`), and it separately matches or beats the coverage-only rule already shipped on the narrower pool that rule was itself measured on, so we are replacing it: `order="defrole"` is now the default. This is a single-sample, in-corpus result on the 173 held-out instances; a 170-instance, 45-repository complement exists in the dataset and has not been measured, and we [have / have not] fetched and scored it."* |
| **PASS, reported not shipped** (wide-pool clears §4.2, narrow-pool does not clear §4.3.2) | the same wide-pool numbers, plus `defrole`'s narrow-pool MRR falling short of `defuse`'s 0.628 | *"The same honest attempt clears our pre-registered bar for ranking over the whole function span (`<margin>` over chance `[CI]`), but on the narrower pool our already-shipped ordering was itself measured on, it does not match that ordering's own result (`<defrole MRR>` vs `0.628`). We are reporting the wide-pool result rather than dropping it, and shipping neither `defrole` in its place — `order="defuse"` stays the default, since we will not replace a row order proven on its own rows with one that is not."* |
| **FAIL** | R3's numbers against the same bands, stated as a negative result with the same rigor a PASS would carry, and the power note (§4.2) | *"We pre-registered one honest attempt — definitions before uses, then coverage — before running it, per your rule that a ranking claiming to rank at chance is the `--adaptive` defect in another costume. It did not clear the pre-registered bar over the whole function span (`<numbers>`; at our sample size this could mean either no real effect or an effect too small to detect — we report the numbers, not a claim about which). `--slice` does not claim to rank lines over the whole function beyond what is proven, and says so in the legend and `--help`. The narrower, already-shipped claim — that among the lines `--slice` already selects, def-use coverage beats a random shuffle — is unaffected and stays the default: source order was measured WORSE than random on those same rows, so replacing it with source order would be a regression, not a fix."* |

## 7. Judgement calls for an adversarial reviewer

**Carried across both rounds — round 1's judgement-call log, with each item's disposition after
`rv-arise-line-ranking.md`'s "Rulings on the producer's judgement calls":**

- **The verdict (§4) is scored at the whole-function candidate pool by a harness computation; the
  shipped `src/` change only ever reorders one seed's own, already-narrower row set.** *Ruling: the
  scope split itself is fine (disclosed exactly as house precedent asks), but round 1's stated
  CONSEQUENCE of that split — what FAIL/PASS do to the shipped default — was wrong. Fixed in §4.3;
  this bullet's own claim about the split stands.* A reviewer should still not assume a PASS at the
  harness level means every `--slice=SYM:VAR` call "ranks the function" — it means that seed's own rows
  are ordered by a formula that, measured at the wider scope AND on the narrower pool (§4.3.2), beat both
  bars. A caller who queries a seed touching few gold lines gets a locally-correct ordering of a
  locally-small set.
- **§0's reading of "0.048 vs 0.042" as the R4 whole-pool figure, not the EVALS.md 0.285-vs-0.268
  figure.** *Ruling: upheld — checkable directly against `docs/research/slice-line-recall.md` §R4 and
  the 0.6.3 planning record's own #318 row.*
- **The margin bar (`≥ 0.02`) is a judgement call, not a fact the baseline note states.** *Ruling:
  upheld as a judgement call, but round 1 stated it inconsistently (two numbers in one sentence) — fixed
  to one number in §4.1.* Still open to argument: a reviewer could reasonably want a different
  multiplier than "3× R1's own margin."
- **R3 is scoped to the same population and pool R4 used.** *Ruling: not separately contested.*
- **"No held-out replication population exists."** *Ruling: overruled on the facts — 170 rows / 45
  repositories are unmeasured in the dataset. Corrected in §4.4.*
- **`docs/research/` created with a README table.** *Ruling: upheld — `ripwirepubliccheck`/
  `readmedriftcheck` pass, format accepted.*
- **`--slice-flow=both` disclosure already shipped, cited not reimplemented.** *Ruling: upheld —
  re-verified at `src/slice.h:3486-3493` on `main` at this lane's base commit: `flow_redundant="1"` iff
  `dir == Both && seedInfo == nullptr`, `--help` and `docs/COMMANDS.md` both carry it.*
- **The FAIL sentence in §6 (round 1) did not retract the already-ADOPTED narrower claim, in WORDS, while
  the CODE it described did retract it.** *Ruling: this was the central defect (HIGH-4) — the prose and
  the code disagreed with each other. §4.3/§6 now match: FAIL genuinely does not touch `order="defuse"`,
  in both the doc and (once shipped) the code.*

**New in round 2:**

- **The bootstrap unit (§4.2) is now per-instance, matching `rank_scores()` — but this document has not
  run `run_slice_linerecall.py` and cannot independently confirm that function's exact shape beyond the
  baseline note's own description and the review's citation of it.** A reviewer with access to that
  script should check `rank_scores()` directly against §4.2's wording before trusting it.
- **§4.3.2's narrow-pool bar (`defrole` MRR ≥ `defuse`'s 0.628) is a NEW judgement call, not dictated by
  the review in exactly this form** — the review's own recommendation (i) states the requirement
  qualitatively (*"the narrow-pool arm... to show `defrole` MRR ≥ defuse's 0.628"*) and this document
  operationalizes it as a hard gate with a binary PASS-ships/PASS-reported-not-shipped split. A reviewer
  could reasonably ask for a softer treatment (e.g. reporting a narrow-pool REGRESSION as its own,
  named outcome rather than folding it into "not shipped") — the current form was chosen for symmetry
  with §4.2's own four-condition, all-or-nothing PASS rule.
- **§3.4's signature-line disclosure states a STRUCTURAL fact about the rule's own ceiling, derived from
  reading `src/slice.h`'s param classification, not from running the rule on real data** — it is a priori
  reasoning about the classifier's known behavior (params are `k="def"`), the same status as §3.2's other
  mechanistic arguments, not a measurement.
- **`bench/slice/score_arise_linerank.py` (§8) is a NEW, from-scratch harness script, not an extension of
  `run_slice_linerecall.py` itself** (that script lives on a different branch and is not committed here —
  round 1's §8 claim that R3 needs only "one additional ranking rule registered in the harness's own
  rank-rule table" undersold the gap: no command computing the fingerprint or the verdict existed at all,
  on either branch). This script is this lane's own statement of the rule in harness terms, self-tested
  on synthetic data; a future round that has the real `run_slice_linerecall.py` may either import this
  module or reimplement the same rule inline — both are faithful to this registration as long as the
  formula (§3.1) and the verdict (§4.1/§4.2) match exactly.
- **`test/slicerank_unit.cpp` item (6)'s real-classifier equivalence check uses a hand-built minimal
  `rw::Symbol` (`sigStartByte=0`, `endByte=src.size()`) rather than one produced by the real ingest
  pipeline** — sufficient to drive `sliceScanDefinition` correctly (confirmed: it parses and classifies
  the fixture as expected), but a reviewer who wants the FULL ingest path (file crawl → symbol table →
  slice) exercised, not just the scanner `sliceScanDefinition` itself, should say so; that is a larger
  test than this lane's synthetic-fixtures scope covers.

## 8. Reproducing, and the harness command that would score this (once the corpus is available)

```bash
python3 bench/slice/locbench_gold.py        --assets <assets> --json gold.json
python3 bench/slice/run_slice_linerecall.py --gold gold.json --bin build/ripwire --work <scratch> --json results.json
python3 bench/slice/inspect_slice_misses.py --results results.json --gold gold.json
```

Identical to `docs/research/slice-line-recall.md` §9's first three commands — reused, not forked
(`run_slice_linerecall.py` lives on `origin/lane/research-arise-slice` and is not committed to this
tree, same as the baseline note itself states).

**`bench/slice/score_arise_linerank.py`** (this lane, self-tested only — `rv-arise-line-ranking.md`
MEDIUM-2's "no command exists" fix) states the R3 rule in harness terms and computes the fingerprint
(§1.2a) and the verdict (§4.1/§4.2) from a per-instance results file a future round's harness run would
produce:

```bash
python3 bench/slice/score_arise_linerank.py --self-test    # this lane: synthetic rows only, no corpus

# a future round, once run_slice_linerecall.py has been extended to also emit r3_at1 per instance:
python3 bench/slice/score_arise_linerank.py \
    --dataset rows_czlll__Loc-Bench_V1_test_560.json --heldout heldout_88.json \
    --results results.json --verdict-out verdict.json
```

**Code↔harness equivalence, stated explicitly (MEDIUM-2 asks that a PASS transfer to the binary):** the
harness's `hasdef[n] = 1 iff some inventory var's v1 rows contain <s l=n k="def"|"both">` and the
shipped `sliceRowHasAnyDef` (`src/slice.h`) compute the same fact by construction — both read whether
ANY tracked local has a definition-role occurrence on line `n`, both from the identical `isDef` flag
`sliceFoldOcc` folds into `k=` (`SliceLineRow::hasDef`/`hasUse`, emitted verbatim as the row's `k=`
attribute). This is not only argued in prose: `test/slicerank_unit.cpp` item (6) runs the REAL
tree-sitter classifier on a real Python fixture (`sliceScanDefinition`, not a hand-built `SliceScan`)
and checks `sliceRowHasAnyDef`'s output against an independently-computed second pass over the same
real `scan.all` — the binary-level half of the equivalence claim the harness-level half above states.
