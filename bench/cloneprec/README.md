# cloneprec — gating precision of the clone `--quality-delta` kinds, and rows per underlying duplication

**Status: PRE-REGISTERED 2026-11-27, before any result was looked at.** Everything from here to
`## Results` was written first and is not edited afterwards except to correct a factual error about the
method, which is then marked as such. The results section is appended below it.

Two quantities, measured separately, on two different populations. **The whole reason this file exists is
that those two populations were conflated**, so every number below states which one it describes.

## Why this exists

`--quality-delta`'s clone family (`duplication`, `new-clone-of-reused-helper`) is the most heavily measured
part of the verb, and the published record is in `docs/EVALS.md`:

- **`docs/EVALS.md:19457`** "Clone operand path and the repeated-decision facet (QD-LESSONS-1, 2026-11-19)"
- **`docs/EVALS.md:19526`** "Clone shrink-only pairs (QD-SHRINK-PAIR, 2026-11-20)"

and the arc starts earlier, at zero:

- **`ecaff19fe`** (2026-09-10), mirrored in `src/quality.h` Q-DIAL-5 and `test/qddialscheck.sh` §5:
  "Duplication's gating precision over 40 replayed commits was ZERO — 11 gating rows, 9 noise and 2 wrong."
- **`8e1a04c90`** withdrew the one-file drop (two of this repo's own gates said it was wrong).
- **PR #629** (QD-DUP-SHORT) and the two EVALS rounds above are the three rounds after it.

**The hole in that record is a population confusion, not a missing number.** The strongest published figures
are **precision of the DEMOTIONS** — "24 random envoy demotions: 21 are idiom collisions over different
data … 0 are verbatim copies", and a second sample of 14 where 12 are collisions. A demotion is a row the
tool decided **not** to gate on. "21 of 24 demotions were correctly demoted" is a true and useful claim, and
it is **not** a claim about the rows that still gate. Nobody has published **precision of the surviving
gating population**: of the clone rows that gate today, what fraction names a duplication a maintainer would
act on.

That is quantity (1). Quantity (2) is a different thing again, made measurable by PR #809.

## Honesty rules binding both halves

1. **Absolute numbers.** Counts, with their denominator, every time.
2. **Every count that cannot be a total is labelled a floor.**
3. **A cell that cannot be graded is reported as ungradeable, with its count and its reason, never dropped.**
   (The failure this guards against: a target measured on a population that could not be scored, where the
   gap collapsed once it could.)
4. **No default, threshold, bar or cap is touched.** Not `kMinCloneTokens`, not the 80-token idiom ceiling,
   not a severity rule. `docs/METHODOLOGY.md` §9: terminality is the objective, the ceiling is a constraint.
   This is a measurement lane; a number that comes out badly is the finding.
5. **Which population each number describes is stated in the sentence that carries the number.**

---

# Part 1 — gating precision of the clone kinds as they ship today

## Population and how it was selected

- **Binary under measurement**: the train tip `2ad2b6254c0d404ace336a58734846dfcf04c82f`, built as a plain
  dev build (no `CMAKE_BUILD_TYPE`), which is "as they ship today".
- **Corpus**: this repository, which is the only corpus to hand with the full history a range replay needs
  (the external corpus checkouts to hand are depth-1 shallow clones; a `A..B` replay cannot run in them).
- **Ranges**: `bench/cloneprec/ranges.lock`, frozen before any run — **the last 40 first-parent merge
  commits reachable from the tip, each replayed as `C~1..C`**. One range is one landed change.
  - `n=40` is chosen to be directly comparable with the September figure, which was "40 replayed commits".
  - First-parent merge ranges are the unit `docs/EVALS.md` QD-LESSONS-1 already uses ("the last 20
    first-parent merges"), so the population rule is not invented here.
- **Command**, one process at a time, no concurrency:
  `ripwire . --quality-delta=C~1..C --quality-kinds=duplication,new-clone-of-reused-helper --no-cache`
  - The kind selector is both kinds together, deliberately: `src/quality.h`
    `mergeOverlappingCloneRows` is a no-op unless both clone kinds are selected, so selecting one would
    measure a different tool.
- **The population P** is every emitted row of either clone kind that **gates**: `sev` is not `minor`, no
  `origin="new-symbol"`, not acked. Non-gating rows (minor, demoted, new-symbol) are counted and reported,
  but they are *not* population P — they are the population the published demotion figures already describe.

## What counts as a true positive, who decides, and the independence problem

A gating clone row is **TRUE** when the duplication it names is one a maintainer of this repo would act on:
the members share domain meaning, not merely shape, and a reader told "these are copies of each other"
would agree rather than reply "those are two different things that happen to look alike".

A gating clone row is **FALSE** when the members operate on different data or belong to different domains
and the resemblance is structural only — the shape the demotion rounds exist to remove (an enum converter
beside another enum converter, a bounded peek beside a bounded peek, a one-line AST-tag predicate beside
another in a different language).

A row is **CHRONIC** when the duplication is real but predates the change: true as a statement about the
code, misattributed as a statement about this change. Counted separately and **not** scored as either.

**Who decides, and the problem with the answer.** There are two label sources and neither is clean:

- **(a) Pre-existing committed labels, authored by other lanes.** `test/dupshortcheck.sh`'s MUST-DEMOTE and
  MUST-KEEP-GATING lists name specific real pairs with their fix SHAs; `docs/EVALS.md` QD-LESSONS-1's "What
  still gates" names more. These are adjudications I did not make, pinned in gates.
  **They cannot give an unbiased precision, and this is pre-registered as a known defect rather than
  discovered afterwards:** every pair in those lists is listed *because* it was adjudicated during the
  rounds that built the demotion rules, and the FALSE ones were then demoted by those very rules. So the
  labelled-FALSE rows are, by construction, no longer in population P. Computing precision over the
  labelled subpopulation would return approximately 100% **as an artifact of how the labels came to
  exist** — a near-tautology, and reporting it as the precision would be the defect this lane was created
  to avoid. It is therefore reported only as a **regression check** (a labelled-FALSE pair appearing in P
  today is a regression; a labelled-TRUE pair missing from P is a recall loss), explicitly not as precision.
- **(b) A fresh adjudication of a salted random sample of P, graded by this lane against the rubric above.**
  This is the only route to an unbiased estimate, and **the grader is the lane doing the measuring**, which
  is not independent. It is disclosed in those words everywhere the number appears, each verdict is recorded
  with the evidence that produced it so a reader can overturn it, and the rubric above is fixed before the
  sample is drawn.

**The independence gap is an owner call, and this lane does not decide it.** If the owner wants a gating
precision figure that does not depend on the measuring lane's own judgement, the adjudication needs a
different reader; the per-row evidence table is written so that can be done later without re-running
anything.

## Sampling, salt, sample size, interval, stopping rule

- If `|P| <= 30`, **every** row in P is graded; there is no sample and no sampling error, only the
  adjudication's own uncertainty.
- If `|P| > 30`, draw **30** rows without replacement, ordered by `SHA-256( "cloneprec-1127" + ":" + range
  + ":" + kind + ":" + sym )` ascending, taking the first 30. The salt `cloneprec-1127` is recorded in
  `ranges.lock`. 30 is pre-registered as the size: at an observed 0.70 it gives a Wilson 95% interval of
  roughly ±0.16, which is enough to separate "mostly true" from "mostly noise" and from the September 0%,
  and is not enough to split hairs — no finer claim is made from it.
- **Interval**: Wilson score 95%, computed on the graded denominator, reported as an interval and never as
  a bare point estimate.
- **Stopping rule**: the sample is drawn once, graded once, and reported. No second draw, no extension of
  `n` after seeing the result, no range added or removed after `ranges.lock` was frozen. If a row cannot be
  graded it is reported ungradeable and the graded denominator shrinks — it is **not** replaced by another
  draw, because replacing it would let the ungradeable rows select the sample.

## What is expected to be ungradeable, and how it is reported

Pre-registered, before looking: three shapes are expected to resist grading, and each is counted and named
rather than dropped.

1. A row whose members no longer exist at the tip (the range is historical), so the bodies cannot be read
   without a checkout per range.
2. A row on vendored or generated code that the vendored-path rules did not catch.
3. A row whose members are genuinely borderline — the shape the EVALS hand-checks also called "borderline"
   (`HeaderUtility::matchHeaders | ConfigUtility::matchQueryParams`: one loop over two different pointer
   types that a generic helper could serve). A borderline row is reported as its own count and is **not**
   silently resolved to either side.

The headline for Part 1 is therefore a **triple**: TRUE / FALSE / (CHRONIC + ungradeable), over the graded
denominator, with `|P|` stated. Not a bare percentage.

---

# Part 2 — rows emitted per underlying duplication, before and after PR #809

## Why this metric and not a finding count

A raw finding count can be made to look better by splitting one duplication into several rows, and worse by
merging them — so **a count of clone findings is not evidence about how well the tool reports duplication**,
in either direction. Rows per underlying duplication is a rate with a denominator that does not move when
the reporting changes: the underlying duplications in a diff are a property of the code, and the rows are
the tool's account of them. It should be 1.0. Anything above 1.0 is the same duplication charged to the
reader more than once, which costs the reader tokens and costs the gate its credibility when two rows are
answered separately.

This is stated here because it is the argument for the metric, and it has to be made before the numbers,
not after they come out favourably.

## The definition, computable from either binary's output

For one range, over the **gating** clone rows only (PR #809 merges only gating rows, so the non-gating ones
are outside the quantity):

- each row's `sym` is its members' canonical ids joined by `" | "`;
- build an undirected graph whose vertices are member ids and whose edges join the members named by one row;
- an **underlying duplication** is one connected component of that graph;
- **rows per underlying duplication** = (gating clone rows) / (components).

This definition reads only the emitted document, so it is computed identically on a binary that merges and
one that does not — the measurement does not depend on the feature under test. On a binary that merges
correctly it is 1.0 by construction, which is why the interesting number is the **before**.

## The three binaries, and #809's standing

- **today** — train tip `2ad2b6254`. This is the shipping behaviour and the number a reader of today's docs
  would be entitled to.
- **809-parent** — `f18bba967`, the commit PR #809 is actually based on.
- **809-head** — `455b7f6d7`, the PR as it stands.

**PR #809 is an unmerged fork PR** (branch `fix/merge-overlapping-clone-reports`, CI approved earlier today,
not landed). It is measured **where it stands**, against its own parent, with no rebase onto the train tip —
so the parent/head pair attributes the change to the PR, and the `today` column is reported separately
rather than being used as #809's baseline. A rebase would have measured a tree that does not exist.

## Corpus

The same frozen 40 ranges as Part 1, on this repository. "Not only the fixture": `test/clonededupcheck.sh`
arm b2 already pins `len(rows) == 1` on a synthetic pair, and a fixture cannot say whether the shape it pins
occurs in real diffs or how often. The 40 real ranges answer that; the fixture answers whether the mechanism
works. Both are reported, and the fixture number is never presented as the corpus number.

## What would make Part 2 uninformative, declared in advance

If the 40 real ranges contain **no** range with two or more overlapping gating clone rows, then
rows-per-duplication is 1.0 everywhere before and after, #809 changes nothing measurable on this corpus, and
the honest report is "the shape #809 fixes does not occur in this corpus at this frequency; the fixture is
the only evidence, and the metric's value is as a guard against regression, not as a win". That outcome is
pre-registered as a legitimate result so it cannot be quietly turned into a search for a corpus that shows
a win.

---

---

# Addendum, declared 2026-11-27 after population A was run and before population B was run

Two changes, both marked where they appear. The pre-registration above is **not** edited to match the
results; this addendum sits after it so a reader can see exactly what was decided when.

**(i) A factual correction to the method, not to a finding.** Part 2's definition said "each row's `sym`
is its members' canonical ids joined". That is wrong for one of the two kinds: a `duplication` row names
its group in **`members=`**, and only a `new-clone-of-reused-helper` row uses `sym=`. The parser reads
both (`run_cloneprec.py::members_of`). Nothing else about the definition changes.

**(ii) Population A returned an EMPTY gating population, so a second population was declared.**
Population A (the 40 frozen first-parent merge ranges) emitted clone rows but **zero gating** ones, and a
precision cannot be computed on an empty population - this is the failure the honesty rules above
anticipated, and A's result is reported as it came out rather than being replaced. Two consequences:

- **Population B** - `bench/cloneprec/ranges_b.lock`, the last **80 non-merge** commits from the tip,
  each as `C~1..C`, frozen before it was run. The reason for the shape: A's rows were overwhelmingly
  `origin="new-symbol"`, and a clone group whose every member is new **cannot** gate by construction, so
  A's population was structurally incapable of carrying the quantity. An ordinary commit more often
  touches code that already exists. Same rubric, same salt, same stopping rule. **B does not replace A**;
  both are reported, and if B is also empty that is the finding, not a prompt for a population C.
- **A post-hoc second metric for Part 2**, clearly labelled as post-hoc: rows per underlying duplication
  over **all** clone rows, gating or not, in addition to the pre-registered gating-only metric. The
  pre-registered metric is gating-only because PR #809 merges only gating rows; the all-rows figure
  measures what a reader of the document actually sees. It is reported beside the pre-registered one and
  never in place of it, and the fact that #809 does not act on the non-gating rows is stated with it.

## Results

All runs: plain dev builds, `--no-cache`, one ripwire process at a time, `--quality-kinds=duplication,`
`new-clone-of-reused-helper`. Every range reported `stale_tree="1"` and `churn="unavailable"` on all 40 of
population A - the working tree is not either compared ref, and the churn input the short-horizon kind
needs was not available. Neither affects the clone kinds, and both are disclosed here rather than omitted.

### Part 1, population A - the gating population is EMPTY, so gating precision is UNDEFINED

Over the 40 frozen first-parent merge ranges, on the tip binary `2ad2b6254`:

| | count |
| --- | --- |
| ranges replayed | 40 |
| ranges emitting at least one clone row | 17 |
| clone rows emitted | 68 |
| ... `sev="minor"` (demoted, non-gating) | 50 |
| ... `origin="new-symbol"` (never gating, `src/quality.h` `rowGates`) | 18 |
| **gating clone rows, population P** | **0** |

`50 + 18 = 68`: every emitted row is accounted for, and the two classes partition the rows.
Cross-check: the document root's own `gating=` count agreed with the per-row rule on **40 of 40** ranges,
so the zero is the tool's own verdict and not a parsing artifact. All 40 runs exited 0, which is what
`--quality-delta` returns when nothing gates, so the exit statuses agree with the row counts too.

**The pre-registered precision is therefore UNDEFINED on population A, not low and not high.** A ratio
with a zero denominator is not a small number. Reporting "0% precision", or quietly substituting the
non-gating rows, would both be wrong: the non-gating rows are the population the published demotion
figures already describe.

**Why A could not carry the quantity**, diagnosed afterwards and reported as a property of the population
rather than as an excuse: a clone group gates only when **some** member existed at the baseline
(`rowGates` = `!isMinor && !isNewSymbol` for these kinds), and a first-parent merge range on this repo is
dominated by new code. The clearest single case is `f7cfcec7a`, which emitted **12 duplication rows, all
`origin="new-symbol"`**, over one family of seven new Python fixture generators in
`test/lib/tanglecapfixtures.py`.

**Ungradeable cells: all 0 of them, because there were no cells.** No row was dropped, no row was
excluded, and no row was graded. The three shapes the pre-registration expected to resist grading
(members gone at the tip, vendored code, genuinely borderline pairs) never arose, because nothing reached
the grader. The salted draw was never performed: with `|P| = 0` there is nothing to draw from, and
`draw_sample.py` reports `|P| = 0` rather than inventing a sample.

### Part 2, population A - rows per underlying duplication, and why #809 is inert here

The pre-registered metric is defined on **gating** clone rows, because `mergeOverlappingCloneRows` acts
only on those (`src/quality.h`: `if( row.cloneGroupIndex == 0 || !rowGates( row ) ) continue;`). With
`|P| = 0` it is **UNDEFINED on all three binaries**, and the three binaries agree exactly:

| binary | clone rows | minor | new-symbol | gating | rows per duplication (gating, pre-registered) |
| --- | --- | --- | --- | --- | --- |
| today, tip `2ad2b6254` | 68 | 50 | 18 | 0 | UNDEFINED |
| #809 parent `f18bba967` | 68 | 50 | 18 | 0 | UNDEFINED |
| #809 head `455b7f6d7` | 68 | 50 | 18 | 0 | UNDEFINED |

**This is the outcome the pre-registration declared in advance as legitimate**, and it is reported as
declared: the shape #809 fixes does not occur in the *gating* population of this corpus, so on these 40
real ranges #809 changes nothing that can be measured, and its fixture arm is the only evidence that the
mechanism works. The metric's value here is as a regression guard, not as a win.

**The post-hoc all-rows metric, which is where the inflation actually is.** Counting components over
**all** 68 clone rows rather than only the gating ones:

| binary | clone rows | underlying duplications (components) | **rows per underlying duplication (ALL rows, post-hoc)** |
| --- | --- | --- | --- |
| today, tip `2ad2b6254` | 68 | 27 | **2.5185** |
| #809 parent `f18bba967` | 68 | 27 | **2.5185** |
| #809 head `455b7f6d7` | 68 | 27 | **2.5185** |

Worst single range: **12 rows for 1 underlying duplication** (`f7cfcec7a`). So the inflation #809 was
written to remove **is real and is present in this corpus at 2.52 rows per duplication** - and it sits
entirely in the population #809 does not act on, because every one of those 68 rows is minor or
new-symbol. That is a statement about #809's *scope*, not its correctness: #809 does what it says, the
gate arm b2 pins it, and this corpus simply contains none of the gating overlaps it merges.

**What this does NOT say.** It does not say #809 should be widened to non-gating rows - that is a product
decision about what a reader should see, it would change what `--quality-delta` prints by default, and
this lane does not make it. It is flagged for the owner, not acted on.

### Part 1, population B - |P| = 4, every row graded, 1 TRUE

Population B is the 80 frozen non-merge commits. It has a gating population, and it is small:

| | count |
| --- | --- |
| ranges replayed | 80 |
| ranges emitting at least one clone row | 5 |
| clone rows emitted | 8 |
| ... `sev="minor"` | 1 |
| ... `origin="new-symbol"` | 3 |
| **gating clone rows, population P_B** | **4** |
| underlying duplications among them | **3** |

`|P_B| = 4 <= 30`, so the pre-registered rule applies: **the whole population is graded, there is no
sample, and there is no sampling error** - only the adjudication's own uncertainty. The salt was
therefore never used. Root `gating=` agreed with the per-row rule on **80 of 80** ranges. Three ranges
exited 2, which is what `--quality-delta` returns when a row gates, and that matches the three ranges
that carry gating rows.

Verdicts, with the evidence for each, are in `bench/cloneprec/verdicts_B.tsv`.
**GRADED BY THIS LANE, which is not independent** - the lane that produced the rows judged them. Each
verdict records the bodies it was based on at the commit the row was emitted for, so any line can be
overturned by a different reader without re-running anything.

| unit | TRUE | FALSE | CHRONIC | BORDERLINE | ungradeable | precision | Wilson 95% |
| --- | --- | --- | --- | --- | --- | --- | --- |
| per gating **row** | 1 | 3 | 0 | 0 | 0 | **1 of 4** | 4.6% - 69.9% |
| per underlying **duplication** | 1 | 2 | 0 | 0 | 0 | **1 of 3** | 6.1% - 79.2% |

**Nothing was ungradeable.** All three pairs' bodies were readable at their commits, none was vendored,
and none came out borderline. The count is 0 and it is reported rather than left implied.

The one TRUE is `rw::findByField | namingconsistency::groupFor` - and it is the best case the kind can
have: `src/infra/tablelookup.h` exists *because* `--quality-delta` found an earlier instance of this very
shape, as its own comment records ("a two-instance dedup turned out to be a three-instance one").
`groupFor` matches two fields where `findByField` matches one, so the fix is a predicate overload rather
than a drop-in call, but the duplication is real and actionable.

The three FALSE rows are two distinct shapes:
- `rw::refuseFlagValue | printStrayFilterNoMatch`: two *different* diagnostics, each one `rw::emitTo(
  stderr, <a different format literal>, ... )`. The only shared code is the house output helper, so there
  is nothing to extract - the common factor **is** `emitTo`. It carries `idiom="call-sequence"` and still
  gates.
- `RedactCounts::total | ledger::sumInput`, counted twice because it is reported under both kinds: the
  accumulator idiom over different data (a `std::array` of `SecretKind` tallies vs a `vector<Entry>`'s
  `inputTokens`), and one member lives in a **test fixture**, `test/estcalibfix/ledger.cpp`.

**Interval honesty.** At n=4 and n=3 the intervals span most of the unit interval and **cannot** separate
"mostly true" from "mostly noise". The point estimate is reported with its interval and no claim is made
that a 25% is distinguishable from a 50%. What the measurement *does* establish, which needs no
interval, is the **size** of the population: 4 gating clone rows across 80 landed non-merge commits, and
0 across 40 landed merges.

### Part 2, population B, and the corrected metric

My own metric definition was wrong, and measuring it is what showed that. Union-by-shared-member
conflates two different shapes:

- **two clone GROUPS that overlap** (an exact group and a near group sharing a member) - this is what PR
  #809 merges, and `test/clonededupcheck.sh` arm (b2) pins it;
- **one group reported under BOTH kinds** - which #809 deliberately keeps as two rows. Arm (b) of its own
  gate asserts exactly that: "new binary reports 'new-clone-of-reused-helper' (consumer #2 fires - dedup
  kept BOTH consumers)".

So the pre-registered target of 1.0 is unreachable *and should be*, while one duplication legitimately
produces one row per kind. The metric is therefore reported **per kind** (components computed within each
kind) as well as kind-mixed, and the per-kind figure is the one that can be read as a defect rate:

| population | rows | per-kind duplications | **rows/dup (per kind)** | kind-mixed duplications | rows/dup (kind-mixed) |
| --- | --- | --- | --- | --- | --- |
| A, gating (all three binaries) | 0 | 0 | UNDEFINED | 0 | UNDEFINED |
| A, all clone rows (all three binaries) | 68 | 38 | **1.7895** | 27 | 2.5185 |
| B, gating (all three binaries) | 4 | 4 | **1.0000** | 3 | 1.3333 |
| B, all clone rows (all three binaries) | 8 | 6 | **1.3333** | 5 | 1.6000 |

**#809's effect on real code, measured where it stands: none, on either population.** Every figure above
is identical on `2ad2b6254` (today), `f18bba967` (#809's parent) and `455b7f6d7` (#809's head). The
gating population it acts on already emits exactly one row per duplication per kind (1.0000), so there is
nothing for it to merge in 120 replayed real changes.

**The mechanism works; this corpus just does not contain its shape.** Proven rather than assumed, through
`RIPWIRE_BIN` so the binary under test is not the checkout's own:

- `test/clonededupcheck.sh` on **#809's head binary: ALL PASS**, 15 arms, including the mutation-test arm
  that proves the assertions are not vacuous.
- The same gate (head's checkout) on **#809's parent binary: 4 arms FAIL** - "(b2) expected one gating
  reused-helper report for the exact/near overlap", "(b2) expected the displayed symbol list to select
  all findings in the overlap", "(b2) expected exactly one clone row after removing reuse evidence",
  "(b2) expected a separate gating calcChain/calcNear pair and a three-member reused-helper row".
- On the fixture, the parent binary emits **4 gating rows** (`calc|calcDup` and `calc|calcNear` under both
  kinds) for **one** underlying duplication family: 2.0 per kind, 4.0 kind-mixed. #809's head reports one
  gating reused-helper row for the overlap. So **2.0 -> 1.0 per kind on the fixture, 1.0 -> 1.0 on real
  code.**

**Where the inflation a reader actually sees lives.** On population A the document carries **1.79 rows
per duplication per kind** (2.52 kind-mixed), and the worst single range emits **12 rows for one
underlying duplication** - seven new Python fixture generators in `test/lib/tanglecapfixtures.py` at
`f7cfcec7a`. Every one of those 68 rows is minor or new-symbol, so **#809 does not act on any of them.**
That is a statement about its scope, not its correctness.

**Not acted on, flagged for the owner.** Whether the merge should extend to non-gating rows is a product
decision about what `--quality-delta` prints by default. This lane did not make it and changed no
default, bar, cap or threshold.

### What was tempted and refused

- `kMinCloneTokens` sits next to the rows that came out FALSE (36, 31 and 41 tokens). Raising it would
  have turned a 1-of-4 into a better-looking number. `src/quality.h` already records that this was
  measured and **refuted** - the canonical true positive is 59 tokens while the noise ran 22 to 127 - so
  a floor above 22 costs true positives before it clears noise. Untouched.
- The 80-token idiom ceiling and the `one-statement` / `call-sequence` / operand-path conditions would
  each have demoted the `emitTo` pair. Untouched: a demotion rule tuned to a lane's own sample is how a
  measurement lane turns into a number-flattering lane.
- Population A's emptiness was a standing invitation to go looking for a corpus that yields gating rows.
  The pre-registration forbade it, A is reported as it came out, and B was declared in writing before it
  was run.
