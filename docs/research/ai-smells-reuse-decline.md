# reuse-decline, and two smells we do not measure

An investigation note, not a plan. It has three parts:

1. A precise specification of `--quality-delta`'s `new-clone-of-reused-helper` kind — called
   *reuse-decline* in the flag help — written so that someone outside this project can
   re-implement it, or show that it is wrong.
2. Two smells from the same line of work that ripwire does **not** measure today, each with a
   concrete proposal, its failure modes, where it would live, and how it would be judged.
3. Measurements on real trees, including the ones where the signal turned out to be weak.

**Provenance.** Three of `--quality-delta`'s ten kinds — verbosity, duplication and reuse-decline —
were shaped by Zhu, Tsantalis and Rigby, *AI-generated code smells*
([arXiv:2605.02741](https://arxiv.org/abs/2605.02741)), which is the row already recorded in
[`LINEAGE.md`](../LINEAGE.md). Of those three, reuse-decline is the only one that is ours rather
than a standard metric, and it is therefore the only one worth critiquing. Everything below about
the paper is our reading of the paper; nothing here should be taken as the authors' position.

**Reproducing the numbers.** Every table names the script that produced it. All three live in
`bench/aismells/` and take the corpus root as an argument, so they run against any tree:

```bash
python3 bench/aismells/clone_locality.py       --bin ./build/ripwire --root .
python3 bench/aismells/clone_locality.py       --bin ./build/ripwire --corpus DIR_OF_CHECKOUTS
python3 bench/aismells/reuse_decline_replay.py --bin ./build/ripwire --root . --commits 150 --all
python3 bench/aismells/fix_spread.py           --root . --commits 5000
bash    bench/aismells/reuse_decline_example.sh ./build/ripwire
```

Corpora referred to below:

| Name | What it is | Size |
| --- | --- | --- |
| **this repo** | ripwire itself, at the branch tip that carries this document | 2,820 non-merge commits |
| **Corpus A** | 90 open-source repositories (Python-majority, a few very large polyglot ones) from the project's benchmark checkout set | 284,732 clone groups; **no git history — every checkout is `--depth 1`** |
| **Corpus B** | a private C++/polyglot codebase used as a scale validation corpus | 2,718 tracked files, 1,648 commits |

---

## 1. What reuse-decline computes

### 1.1 The claim the kind makes

> *This change added a copy of a helper that the tree was already reusing, instead of calling it.*

It is a **regression kind**, not a debt scan: it fires only on something this change introduced,
never on pre-existing duplication. That is the whole `--quality-delta` contract, and it is why the
kind can carry a gating exit code at all.

### 1.2 The algorithm, exactly

Source of record: `src/quality.h`, the `§D#4-3 reuse-connectivity decline` block inside
`computeDelta`. A row is emitted for a clone group `G` when **all** of the following hold.

**(a) `G` is a clone group.** Two passes contribute, both over function/method bodies only:

- `findClones` — Type-1/2: bodies whose **normalized token streams are byte-identical**.
  Normalization (`src/clones.h`) maps identifiers to `$I` and literals to `$N`/`$S`, and keeps
  keywords, operators and punctuation verbatim, so renamed variables still match but different
  control flow does not.
- `findClonesType3` — gapped near-misses: pairs whose LCS ratio `2·LCS/(|a|+|b|)` lands in
  `[0.80, 1.0)`, after a k-gram-fingerprint Jaccard prefilter (`≥ 0.40`, k = 5) and a token-count
  length band (`≥ 0.70`). Exact matches are excluded here by construction — they score 1.0 and
  belong to the first pass. Type-3 groups are always **pairs**.

Both passes take the same floor: `kMinCloneTokens = 18` normalized tokens. Bodies below it are not
candidates. Raising this floor was measured and rejected; see §1.5.

**(b) `G` is new.** The group's identity is `cloneGroupHash` — FNV-1a-64 over its **sorted member
canonical ids**, root-relative. If that hash is in the baseline snapshot's sorted clone-group list,
the group already existed and nothing is reported. Note the consequence: adding a *third* copy to an
existing pair changes the member set, so it is a new group.

**(c) `G` contains a pre-existing, well-reused member.** For each member `m`:

- `m` must be classifiable — it must have a non-zero identity key. The key is
  `pathQualifiedKey = fnv1a64( rootRelativePath \0 scope \0 name )`. A member with no key is never
  evidence of anything.
- `m` must have **existed at the baseline** under that key (`existedAtBaseline`).
- `fanin(m)` = `m`'s in-edge count in the call-graph CSR.

`maxFanin` is the maximum over members that pass both tests, and the group qualifies only if
`maxFanin ≥ kReusedHelperMinFanin`, which is **3**.

The "existed at the baseline" requirement is not decorative. It was added after the original
implementation claimed — in a comment and in a commit message — that the reused helper was
pre-existing "by construction", which is false: three brand-new call sites reach fan-in 3 trivially,
so an all-new blob of code duplicating *itself* was being reported under a kind whose entire meaning
is *you eroded reuse that already existed*. Nothing was lost by tightening it; that case is still
reported, as `duplication`, which is where it belongs. This is fixture **B** in §1.4.

**(d) `G` is in scope.** `cloneGroupIsOutOfScope` drops a group when either

- every member shares one canonical id — an **overload set**; a helper cannot have eroded its own
  reuse by being overloaded; or
- every member sits under a **vendored path** — upstream's shape is not this tree's to fix.

Note what is *not* on that list: **members sharing one file are not exempt.** That was written and
then withdrawn, because two of this repository's own gates encode the opposite policy: a
copy-pasted body is duplication wherever it lands, and file identity cannot distinguish a deliberate
specialization from a paste.

**(e) The member set has not already been reported this run**, keyed by the same hash.

### 1.3 What the row says

```
<r kind="new-clone-of-reused-helper" sym="calc | calcDup" was="0" now="3"
   p="src/util.cpp:1" gating="1" next="--expand='src/util.cpp:calc | calcDup'"/>
```

- `sym=` — the group's members, sorted canonical ids joined with ` | `. The finding is a **relation
  over a set**, not a property of one symbol.
- `was="0"`, `now=` — `now` is `maxFanin`: *the amount of reuse this copy eroded*. `was` is
  structurally zero; this is a presence kind, not a numeric trend.
- `p=` — the first-sorting member's `path:line`.
- Severity: presence kinds have **no minor tier**, so a reuse-decline row is always major.
- Origin: precondition (c) guarantees at least one member existed at the baseline, so
  `cloneGroupIsNew` is necessarily false and the row is **always `preexisting-worse`**. Combined
  with the previous point, **an unacked reuse-decline row always gates `--quality-delta` to exit 2.**

**Fan-in is per distinct caller, not per call site.** Measured, not assumed: a helper called eight
times from three distinct functions reports `now="3"`.

### 1.4 Worked example, with real output

`bash bench/aismells/reuse_decline_example.sh ./build/ripwire` builds three throwaway git fixtures
and prints the real `--quality-delta` for each. Verbatim output:

```
===== A  POSITIVE — new copy of a pre-existing helper with fan-in 3 (three distinct callers) =====
  quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="3" minor="0"
    acked="0" stale="0" preexisting-worse="2" new-symbol="1" gating="2" ...
  r kind="dead-code" sym="calcDup" origin="new-symbol" p="src/feature.cpp:1"/>
  r kind="duplication" members="calc | calcDup" tokens="34" p="src/util.cpp:1" gating="1"/>
  r kind="new-clone-of-reused-helper" sym="calc | calcDup" was="0" now="3" p="src/util.cpp:1"
    gating="1" next="--expand='src/util.cpp:calc | calcDup'"/>
  (exit 2)

===== B  NEGATIVE — helper, callers and copy all NEW: no pre-existing reuse was eroded =====
  quality-delta ... regressions="5" preexisting-worse="0" new-symbol="5" gating="0" ...
  r kind="dead-code" sym="calcDup" origin="new-symbol" p="src/feature.cpp:1"/>
  r kind="dead-code" sym="callcalc1" origin="new-symbol" p="src/util.cpp:11"/>
  r kind="dead-code" sym="callcalc2" origin="new-symbol" p="src/util.cpp:12"/>
  r kind="dead-code" sym="callcalc3" origin="new-symbol" p="src/util.cpp:13"/>
  r kind="duplication" members="calc | calcDup" tokens="34" origin="new-symbol" p="src/util.cpp:1"/>
  (exit 0)

===== C  NEGATIVE — pre-existing helper with fan-in 1: below kReusedHelperMinFanin=3 =====
  quality-delta ... regressions="2" preexisting-worse="1" new-symbol="1" gating="1" ...
  r kind="dead-code" sym="calcDup" origin="new-symbol" p="src/feature.cpp:1"/>
  r kind="duplication" members="calc | calcDup" tokens="34" p="src/util.cpp:1" gating="1"/>
  (exit 2)
```

All three fixtures contain the **same 34-token copy**. A separates from B on *when the helper was
born*, and from C on *how many callers it had*. In every case the copy is still reported as
`duplication`; reuse-decline is strictly the narrower claim on top.

### 1.5 Why the threshold is 3 — and the honest answer

`kReusedHelperMinFanin = 3` is a **defensible default, not a fitted operating point.** The reasoning
recorded in the source is ordinal rather than empirical: fan-in 1 is a single call site and there is
no reuse to erode; fan-in 2 is a pair that can easily be coincidence; 3 is the smallest count at
which "several places already call this" is true.

What does **not** exist, and we are not going to pretend it does:

- no sweep of 2 / 3 / 4 / 5 against a labelled set;
- no precision or recall number for this kind at any threshold;
- no cost model trading a missed erosion against a false alarm.

The one adjacent parameter that *was* swept is the token floor, and it was swept in the negative
direction: raising `kMinCloneTokens` above 18 was measured and **refuted**. The canonical true
positive in the replay set (a 12-line copy of a reused helper) is 59 tokens, while the idiom
collisions in the same run measured 22, 24, 31, 36, 56, 65, 66, 74, 78, 91, 92, 96, 114 and 127
tokens. A floor set high enough to clear the noise loses true positives first. **Token count is the
wrong axis** — which is a useful negative result, and it is also why the fan-in axis has never been
properly tested: it was the axis that was left.

§3.1 measures where the threshold actually sits relative to the findings it produces, and the answer
is uncomfortable.

### 1.6 What it does NOT catch

Stated as capability limits, not as apologies.

1. **A re-implementation that is not a token clone.** The dominant case in the paper's own framing —
   an agent writes the helper's *role* again from scratch, with a different loop form, different
   control flow, a different algorithm. Type-3 needs LCS ≥ 0.80 on the normalized stream. A
   semantically equivalent rewrite routinely scores far below that. **This is the largest gap, and
   no clone detector of this family closes it.**
2. **Inlined copies.** A clone member is a whole function body. A helper's logic pasted into the
   middle of a larger function changes that function's token stream and matches nothing.
3. **Bodies under 18 normalized tokens.**
4. **Helpers whose real fan-in the call graph cannot see.** Edges are name-based. Dynamic dispatch,
   callbacks, function pointers, macro-assembled calls and reflection contribute no edges, so a
   genuinely well-reused helper can measure below 3 and be silently ineligible. The map's own
   `ambiguous=` header is the completeness gauge; this kind does not consult it.
5. **Cross-language duplication.** Fan-in and clone groups are both computed inside one
   language's resolved graph.
6. **Cross-repository duplication.** `--quality-delta` is single-root; the multi-root merge that
   other verbs support is explicitly excluded from it.
7. **Pre-existing copies.** By design — precondition (b).
8. **All-new self-duplication.** By design — precondition (c), fixture B.
9. **Anything the member-set identity loses.** The two clone kinds key on a member-**set** hash that
   no single symbol carries, so they are **not** re-filed across renames the way the per-symbol
   kinds are. A rename or move of any member makes an old group read as new. This is a disclosed
   floor in the verb's own legend, not a discovered bug — but it is a false-alarm channel, below.

### 1.7 False-alarm behaviour

Ranked by how often they were actually observed (§3.1).

- **Idiom collisions.** Short bodies that spell a recognized shape — a threshold ladder, a
  switch-over-a-name-table, a builder chain, a one-line `std::find` predicate, a per-enumerator
  switch — collide on the normalized token stream without being copies of each other.
  `--quality-delta` has a demotion for exactly this: a group carrying a recognized `idiom=` that
  *also* shares no non-keyword identifier between any two members, sits in pairwise-distinct
  enclosing contexts, and stays under 80 normalized tokens is reported **minor** instead of gating.
  **That demotion was, at the time we drafted this note, applied to `duplication` and not to
  `new-clone-of-reused-helper` (reuse-decline).** The reporter passed `false` for the minor flag
  unconditionally, so an idiom collision that happened to contain a pre-existing symbol with three
  callers gated at full severity. We read that asymmetry as an oversight, and it has since been
  fixed and shipped in v0.6.2 (`5a316628`, "fix(quality-delta): reuse-decline gets duplication's two
  clone-group demotions"): `new-clone-of-reused-helper` now reuses the same `CloneIdiomVerdict`
  demotion `duplication` does. A behavioral gate for it, and a fix for a disclosure gap it exposed
  (a demoted row carried `sev="minor"` but no `idiom=` attribute), are in review as a follow-up
  change.
- **Test-harness boilerplate.** `duplication` skips a group whose members are *all* test scripts —
  sibling shell gates repeat near-identical `setup`/`ok`/`no` boilerplate by convention.
  **`new-clone-of-reused-helper` lacked that exemption too** — same asymmetry, same reporter, same
  line of code — and it is fixed by the same commit.
- **Deliberate non-merge.** Two bodies that genuinely are near-identical, which the architecture
  forbids merging — a helper in a lower layer that a higher-layer header cannot include without
  inverting the include order, a verbatim copy kept in a verification translation unit precisely so
  that it can be compared against the original. These are true positives about the code and false
  alarms about the action.
- **Rename/move churn**, per §1.6 item 9.
- **The degrade path.** If the baseline predates the per-symbol map that answers "did this exist?",
  `existedAtBaseline` **fails closed and returns true for everything**, which collapses precondition
  (c) back to the pre-fix behaviour. The run emits a `DISCLOSE` line saying so. This is the correct
  direction to fail — a silent disarm of an exit code is worse — but a reader who ignores the
  disclosure will misread the rows.

There is a ledger for the accepted cases: `.ripwire_quality_acks` suppresses a finding until it
worsens past its acked magnitude, keyed by the member-set hash, with a free-text reason. §3.1 reads
that ledger as data.

---

## 2. Two smells we do not measure

Both are **cross-context** in the sense our own backtest uses: the defect is not visible from any
single function or file — you need a second site to see it at all. That study recorded 377 defects
from AI-authored code in this project, of which 292 were usable; of those, 169 could be tagged by
locality (123, or 42.1% of the usable rows, could not). Of the 169 tagged, **149 (88%) were
cross-context and 20 (12%) were local**. The same direction shows on a human-authored comparison
slice, but we will not put a number on it: our two proxies for that external rate disagree, and
neither has a written recipe.

That is the whole argument for these two proposals. Per-function bars — length, nesting, parameter
count, complexity — cannot see an 88%-cross-context population *by construction*, no matter how
they are tuned. Reuse-decline is already a cross-context kind: it is a relation over a member set
plus a graph property. The two below are the same shape, aimed at the two cross-context failures we
have independent evidence for.

### 2.1 Cross-file duplication

**The smell.** An agent re-implements near-identical code in a *different file* from the one that
already has it. The context window saw one file; the repository has the other.

**What ripwire would compute.** Nothing new has to be detected — the clone detector already emits
every group with a `path:line` per member. What is missing is that the **locality of a clone group
is never computed or reported**. Concretely:

1. `--clones`: a per-group attribute `locality="same-file|cross-file|cross-dir"`, and header counters
   `cross_file_groups=` / `cross_dir_groups=` beside the existing `groups=`/`type3=`.
2. `--quality-delta`: the existing `duplication` row carries the same `locality=` facet. This is a
   **facet, not a new kind** — the same discipline `short-horizon-churn` uses for `churn="self|ambient"`
   and `api-surface` for its tier. Facets classify; they do not gate by themselves.
3. Only then, and only if the measurement in §3.2 justifies it, a severity rule: a cross-file new
   clone group is the one that should gate; a same-file one is demoted to minor. Not proposed yet.

**Where it would live.** `CloneGroup` in `src/clones.h` gains a computed locality (it already holds
member `NodeId`s, and `IngestResult` already holds each symbol's `fileId`). `src/quality.h`'s
`reportNewClones` reads it into the row's facet. `src/verbs_quality.h` and the `--clones` emitter
carry it into the document and the legend. No new pass, no new cost.

**How it could be wrong.**

- **A same-file clone is not benign.** This repository's own gates assert the opposite: a
  copy-pasted body is duplication wherever it lands, and two of them pin same-file groups as real
  findings. If the facet quietly became "cross-file gates, same-file does not", it would contradict
  two existing gates and lose real findings. That is why step 3 above is conditional.
- **File boundaries are a weak proxy for context boundaries.** A 6,000-line file and a 40-line file
  are one "file" each. Directory distance, module distance, or whether the two members' enclosing
  files ever co-change would each be a better proxy — and each is more expensive and more arguable.
- **Same-file clones dominate in some codebases** and cross-file in others by a factor of five
  (§3.2). A single global operating point would be wrong for most trees.
- **Language conventions confound it.** A language whose convention is one class per file makes
  every intra-class copy "cross-file"; a language with large modules makes the same copy
  "same-file". The measurement in §3.2 must therefore never be pooled across languages without
  saying so.

**How it would be measured.** Red-first, as every behaviour change here is: a gate fixture with one
same-file and one cross-file new clone group, asserting the facet on each and a mutation arm that
turns the assertion red. Then the corpus number: the per-repo cross-file share (§3.2), re-run, with
the distribution reported rather than the mean — because the distribution is the finding.

### 2.2 A single fix spread across many files

**The smell.** One logical defect is repaired by edits in many files, because the same rule was
re-derived in each of them. The understandability cost is paid by the next reader, who has to
reassemble the rule from N sites. Our own worst instance: one rule about how a version-control tool
treats partially-checked-out paths was copied into three places and got it wrong in three different
ways; deleting the copies was the fix.

**What ripwire would compute.** The inputs all exist.

- `--cochange` (`src/gitmine.h`) already mines *files that change together*, with `together=`,
  `recur=` over sub-windows, and a `surprising=` classification; `--cochange-groups` already names
  a core file and its partners.
- The call graph already answers whether two touched files are structurally connected.
- `--situ` already reports "forgotten co-change partners" for the current diff.

The missing computation is a **retrospective** one, over history rather than over the working tree.
For each fix-shaped commit: take the set of source files it touched; compute (i) how many of the
file *pairs* had ever been committed together before — the **novel-pair fraction**; and (ii) whether
the touched files are reachable from one another in the call graph. A fix whose files are neither
historically coupled nor structurally connected is a rule that lives in N places with nothing
linking them, and that is the reportable shape.

The forward-looking half already half-exists: `--situ` could say *the files you are editing have no
prior co-change and no call path between them — is this one rule in several places?*

**Where it would live.** The history walk belongs in `src/gitmine.h` next to the co-change miner
that already reads the same `git log`; the verdict belongs behind an existing verb rather than a new
one. Reuse of the co-change window, sub-window and `recur=` machinery is the point — a second commit
walk with its own window semantics is exactly the duplication this document is about.

**How it could be wrong.**

- **"Fix" is read off a commit subject.** A regex over commit messages is a weak classifier, it is
  language- and convention-dependent, and squashed or batched commits break it outright. §3.3 reports
  the control arm for this reason.
- **Spread is often correct.** An interface change, a rename, a new parameter threaded through
  callers, a generated file and its generator — all spread by construction and none is a smell.
  Without a way to separate "one rule in N places" from "one contract touching N callers", the
  metric measures commit style.
- **Novel-pair fraction is inflated by young or shallow history.** In a repository's first months
  almost every pair is novel. Any operating point has to be conditioned on history depth, and a
  shallow clone has to be refused rather than scored — see §3.3, where an entire 90-repository
  corpus turned out to be unscoreable for exactly this reason.
- **It cannot see the fix that should have spread and did not.** A one-file fix to one of three
  copies looks perfect by this metric and is the worse outcome.
- **Direction is unproven.** We have not shown that high-spread fixes correlate with anything bad.
  §3.3's control arm is the first honest look, and it does not support a strong claim.

**How it would be measured.** Two stages. First, does the fix/non-fix split separate at all on the
novel-pair fraction and the file count? §3.3 runs exactly that and the answer is *barely, and not
consistently*. Second, and only if the first stage separates: a labelled set of defects where the
number of sites is known independently — this project's own caught-by ledger records the site of
each defect — scored for whether the metric ranks the multi-site ones above the single-site ones.

### 2.3 How the two relate to the 88%

Both are cross-context by construction and neither can be reduced to a per-function bar:

| | Second site needed to see it | What links the sites |
| --- | --- | --- |
| reuse-decline (shipped) | the pre-existing helper | token similarity + call-graph fan-in |
| cross-file duplication | the other file's copy | token similarity + file identity |
| fix spread | the other file the same rule lives in | commit co-occurrence + call reachability |

The relationship to the 88% figure is a hypothesis about *coverage*, and it should be read as one:
these two smells have the same shape as the population the study measured, so they are plausible
places to look. They are not a claim to detect 88% of anything. Reuse-decline is the existing proof
that the shape is implementable; it is also, per §3.1, the existing proof that implementable is not
the same as calibrated.

---

## 3. Measurements

### 3.1 How often does reuse-decline fire, and on what?

**Instrument A — the ack ledger.** `.ripwire_quality_acks` records every finding a human judged and
chose not to act on, with a reason and the magnitude at which it was accepted. It is the longest
record we have of this kind meeting real code. All 1,613 rows, by kind:

| Kind | Acks |
| --- | --- |
| short-horizon-churn | 629 |
| duplication | 221 |
| api-surface:new-symbol | 202 |
| api-surface | 172 |
| verbosity | 137 |
| complexity | 121 |
| **new-clone-of-reused-helper** | **62** |
| params | 50 |
| nesting | 9 |
| dead-code:new-symbol | 8 |
| error-masking, dead-code:preexisting | 1 each |

Reuse-decline is 3.8% of accepted findings, and 22% as frequent as plain `duplication` — which is
the right order of magnitude, since it is a strict subset of new clone groups plus a graph
condition.

The fan-in at which each was accepted (`now=` at ack time):

| fan-in | 3 | 4 | 5 | 6 | 7 | 10 | 14 | 16 | 20 | 42 | 120 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| acks | 24 | 19 | 7 | 2 | 1 | 1 | 1 | 1 | 1 | 3 | 2 |

**43 of 62 (69%) sat at fan-in 3 or 4 — in the threshold's immediate neighbourhood — and 50 of 62
(81%) at fan-in ≤ 5.** This is the sharpest thing in the document. The ledger only records findings
that were *not* acted on, so it is the accepted tail rather than a precision estimate; but a kind
whose accepted tail piles up one notch above its own threshold is a kind whose threshold is
carrying most of the decision, and that threshold (§1.5) was never fitted.

Reading the free-text reasons of all 62: 31 name an idiom-class or one-line/shape collision, and 20
name a test gate, harness, fixture or probe translation unit. Those two categories are precisely the
two demotions that `duplication` had and `new-clone-of-reused-helper` lacked at the time this ledger
was read (§1.7). The categories overlap and the count is a keyword scan of the reason text, not a
hand label — treat it as an order of magnitude, not a partition.

**Instrument B — replaying the kind over history.** `reuse_decline_replay.py` runs
`--quality-delta=<parent>..<sha>` over a window of non-merge commits and counts rows per kind. See
§3.4 for the result and for what the replay cannot see.

### 3.2 Same-file versus cross-file duplication

`clone_locality.py`, over `--clones` output, skipping the fixture/shell-runner groups that
`--quality-delta`'s duplication kind already ignores.

| Corpus | groups | same-file | cross-file | cross-file % | of those, cross-dir | exempt skipped |
| --- | --- | --- | --- | --- | --- | --- |
| this repo | 296 | 127 | 169 | **57.1%** | 51 (30.2%) | 317 |
| Corpus A (90 repos, pooled) | 284,732 | 94,926 | 189,806 | **66.7%** | 120,196 (63.3%) | 32 |
| Corpus B | 3,765 | 2,317 | 1,448 | **38.5%** | 499 (34.5%) | 0 |

By clone type, pooled over Corpus A: Type-1/2 groups are 70.1% cross-file (19,073 of 27,222);
Type-3 pairs are 66.3% cross-file (170,733 of 257,510). This repo: 71.1% and 55.0% respectively.

**The pooled figure is misleading and should not be quoted alone.** It is dominated by a handful of
very large repositories — one contributes 68,714 groups at 94.5% cross-file, another 43,829 at
91.0%. Per repository, the distribution over the 89 repositories that have any clone group at all:

| min | p25 | median | p75 | max |
| --- | --- | --- | --- | --- |
| 0.0% | 16.7% | **37.3%** | 57.4% | 94.5% |

Cross-file duplication is the *majority* in only 32 of 89 repositories (36%). The honest reading:
cross-file duplication is common everywhere and dominant in some codebases, with a spread wide
enough (0% to 94.5%) that no single global threshold could be right. That spread is the argument for
reporting locality as a **facet** rather than baking it into a severity rule (§2.1), and it is also
a caution: much of the between-repo variance is plausibly language and file-size convention rather
than anything about quality. We have not decomposed it.

Two caveats on the corpus itself. Corpus A's checkouts are a benchmark selection of active
open-source projects; we have **no ground truth about which of their code was AI-authored**, and we
are not going to imply otherwise. And the three corpora differ in language mix (A is
Python-majority, B and this repo are C++-majority), which is confounded with the cross-file share by
exactly the mechanism §2.1 warns about.

### 3.3 What a fix spread across files looks like in git history

`fix_spread.py`. A commit is a "fix" if its subject matches a fix/bug/regression/crash/revert regex.
Source files only. `novel_pair_%` = of the file pairs a multi-file fix touched together, the share
that had never been committed together before, measured against history *prior to that commit*.

| Corpus | commits | fix | multi-file % | >3 files % | median files | median dirs | novel-pair % |
| --- | --- | --- | --- | --- | --- | --- | --- |
| this repo | 2,820 | 923 | **74.5%** | 35.1% | 2 | 2 | **57.7%** |
| this repo — non-fix control | 2,820 | 1,111 | 58.1% | — | 2 | — | — |
| Corpus B | 1,637 | 96 | **72.9%** | 45.8% | 3 | 1 | **77.3%** |
| Corpus B — non-fix control | 1,637 | 814 | 78.6% | — | 3 | — | — |
| Corpus A | — | — | — | — | — | — | — |

Fix-commit file-count distribution, this repo (1 / 2 / 3 / 4–10 / 11+ files):
25.5% / 26.0% / 13.4% / 29.3% / 5.9%. 62.5% of fix commits touch more than one top-level directory.
Corpus B: 27.1% / 17.7% / 9.4% / 30.2% / 15.6%, and 27.1% cross-directory.

**The signal is weak, and in one direction it reverses.** On this repository fix commits are more
spread than non-fix commits (74.5% vs 58.1% multi-file). On Corpus B they are *less* spread (72.9%
vs 78.6%), with identical medians. Two corpora, opposite signs, both with the confound that
"non-fix" includes feature work, refactors and renames, which spread for good reasons. A
commit-message classifier plus a file count does not isolate the smell. Anyone proposing to ship
§2.2 on this evidence would be shipping a measurement of commit style.

The novel-pair fraction is the more interesting half and the less trustworthy one: 57.7% and 77.3%
of the file pairs that fix commits touch together had never been committed together before. If that
survives a proper control it says co-change history *cannot* be the whole instrument, because most
of the pairs a fix has to reach are pairs history has never linked. But it has no control arm yet —
we have not computed the same fraction for non-fix commits, and a young or fast-growing repository
inflates it mechanically.

**Corpus A contributes nothing here and the row is left empty on purpose.** All 90 checkouts are
`--depth 1` shallow clones with exactly one commit each. The first run of this script against them
produced a clean-looking table — 17 repositories, 100% multi-file fixes, median 286 files, 0.0%
novel pairs — which is an artifact of scoring a single root commit that touches the entire tree. We
downloaded nothing to repair it. The lesson is the one already on the books here: an empty result is
not evidence, and a *full-looking* result from an instrument pointed at the wrong input is worse.

### 3.4 Replaying reuse-decline over this repository's history

`reuse_decline_replay.py --root . --commits 150 --all`, comparing each non-merge first-parent commit
against its own parent.

150 commits swept, 0 errors. 24 of the 150 produced any `--quality-delta` row at all. Rows by kind:

| Kind | Rows over 150 commits |
| --- | --- |
| verbosity | 31 |
| complexity | 19 |
| duplication | 8 |
| nesting | 3 |
| error-masking | 2 |
| dead-code | 1 |
| **new-clone-of-reused-helper** | **1** |
| params | 1 |

**Reuse-decline fired once in 150 commits (0.67%).** That is a rare kind, which is consistent with
its definition — it is a strict subset of new clone groups, intersected with a graph condition — but
it is worth stating plainly rather than leaving as an impression.

The single firing is the more useful half of the result, because it is a false alarm of the exact
shape §1.7 predicts:

```
commit fc17c51a  test(gates): RED first — --connect's equal-distance join is decided by file name
fan-in 3   locator test/notescheck.sh:182
members    mcp | mcp_call | mcp_call | mcp_call | mcp_call | mcp_call | mcp_call | mcp_call
           | mcp_call | mcp_call | mcp_call | mcp_call | mcp_call
```

The commit adds one new shell gate script. That script carries the same `mcp_call` helper that
twelve sibling gate scripts already carry, which is the house convention for these harnesses, so
the member set changed and a new group was born. Every member is a test script — the exemption
`duplication` applies and, at measurement time, `new-clone-of-reused-helper` did not. **The kind's
only firing in 150 commits is a row the sibling kind would have dropped.** One instance is not a
rate; it is an existence proof for the asymmetry, and it agrees with the ledger reading in §3.1,
where 20 of 62 accepted findings name a test gate, harness, fixture or probe translation unit.

That count was measured on the pre-fix binary. Replaying the same 150-commit window
(`bench/aismells/reuse_decline_replay.py`) with the demotions from `5a316628` applied produces
**0** `new-clone-of-reused-helper` rows: the one firing above is exactly the row the all-test-script
skip removes. The kind's only recorded firing in this history was the false alarm its own asymmetry
predicted, not a defect the demotion would have missed.

Note also that the members span twelve different files — the cross-file case §2.1 is about, which
the row itself has no way to say.

Two structural limits on this instrument, both worth knowing before reading the number:

- **Acks suppress.** The ledger is read from the target tree, so a finding that was accepted at the
  time it was made does not appear as a row in the replay. The 62 ledger entries in §3.1 are
  findings this replay is structurally blind to, and they are the population that matters most.
- **The range form disables one kind.** `--quality-delta=A..B` reports `churn="unavailable"`;
  short-horizon-churn cannot be measured between two materialized trees. Its silence in the replay
  is not an absence of churn.

---

## 4. What we would like help with

In rough order of how much a wrong answer would cost us. The first is the real ask.

1. **Is `fan-in ≥ 3` the right shape of condition at all?** §1.5 is candid that the value was
   reasoned, not fitted, and §3.1 shows 69% of accepted findings sitting at fan-in 3–4. Three
   distinguishable critiques, and we do not know which is right:
   (a) the threshold is simply too low and should be 5 or 6;
   (b) a raw in-edge count is the wrong statistic, and what matters is how *dispersed* the callers
   are — three callers in one file is not the same reuse as three callers in three modules;
   (c) the whole idea of a fan-in gate is wrong, because a helper's importance is not its caller
   count. If there is a principled alternative — caller dispersion, a centrality measure, the
   helper's age, whether it sits on a module boundary — we would rather adopt it than tune a number.
2. **Is "a new clone group containing a pre-existing high-fan-in member" a faithful operationalization
   of reuse decline, or a proxy that happens to be computable?** §1.6 item 1 is the part that worries
   us: the failure mode the smell names is an agent *re-implementing* a helper's role, and token-level
   clone detection sees only the subset where it re-implemented it *similarly*. We would like to know
   whether that subset is a useful sample of the phenomenon or a biased one.
3. **The two demotions, now made symmetric.** `duplication` demotes recognized idioms and skips
   all-test-script groups; `new-clone-of-reused-helper` had neither (§1.7), and the ledger's reasons
   suggested that was where most of its noise came from. We read the asymmetry as an oversight; the
   fix shipped in v0.6.2 (`5a316628`), and a behavioral gate plus an `idiom=` disclosure fix are in
   review as a follow-up change. Is there an argument that an idiom collision involving a
   well-reused helper should be *more* serious rather than less — in which case the demotion is the
   wrong default, and we should revert it rather than have made it symmetric?
4. **Cross-file duplication as a facet, not a kind** (§2.1). The per-repository spread in §3.2 is
   0%–94.5%, which we read as "report it, do not threshold it". Is there a defensible normalization —
   per language, per file-size distribution, per module granularity — that would make a threshold
   meaningful, or is the spread irreducible?
5. **Fix spread** (§2.2, §3.3). Our own measurement does not separate fix commits from non-fix
   commits consistently, and reverses sign between two corpora. Before building anything we would
   like to know whether the construct is measurable from commit history at all, or whether it
   requires the defect-level ground truth that a commit log does not carry.
6. **The 88% cross-context claim** (§2.3). It comes from our own defect corpus, under our own
   tagging rule, on code this project's agents wrote — a population with obvious selection effects.
   We would value a reading of whether it is evidence of anything general, or a fact about how this
   project works.

What we are **not** asking for is validation. The parts of this document most likely to be wrong are
§1.5 (a threshold with no sweep behind it) and §3.3 (a weak signal reported as weak); those are the
parts where a flat contradiction would be worth more to us than agreement.
