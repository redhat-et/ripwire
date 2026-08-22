# DRAFT — pre-registration for the retrieval-loss-bucket ranking round

> ## THIS IS A DRAFT. IT REGISTERS NOTHING YET.
>
> **No ranker change may be attempted against these bands until the owner signs off on this
> document.** Nothing in this file is a measured result of a fix, a commitment to ship one, or a
> published number. It records four **baselines** taken before any code was written, and it proposes
> the **band shapes** a later round would be judged against. The round itself — writing the ranker
> change, running the slice a second time, and applying the decision rule below — is a separate,
> owner-gated piece of work. When (if) it happens, the accepted version of this file moves into
> `docs/EVALS.md` in the same commit as the code, per the house registration convention. **This lane
> deliberately made no `docs/EVALS.md` edit and added no gate.**

---

## 1. What this registers, and why it needed a new instrument

Four retrieval-loss shapes were diagnosed on outside repositories. Each is a *mechanism*, not a
symptom, and each is invisible to every instrument this repository already owns:

| Bucket slug | The mechanism |
|---|---|
| `diagnostic-class` | A conceptual query's content words are also the NAME of a diagnostic class (a `*Warning` / `*Error`, or a plugin whose only job is to report one). The diagnostic is named after the failure the mechanism can produce, so it matches the query's words with a tiny body and no competition, and the implementation never surfaces. |
| `thin-registration` | The answer is a small registration/wiring class whose name literally spells most of the query's content words, but which carries near-zero graph centrality. Structurally central symbols sharing *fewer* query terms displace it. |
| `subsystem-directory` | The concept the query names IS a directory name. Path components are not ranking evidence, so the query word matches inside unrelated symbol names elsewhere while the directory literally named for the concept contributes nothing. |
| `vendored-asset` | Vendored front-end assets and numbered database migrations take top slots in task bundles that have nothing to do with either. |

**Why the existing instruments cannot see them.** `bench/recalleval/`'s two frozen corpora
(`snapshot.mdpack`, `snapshot.srcpack`) are snapshots of *this* repository. This tree contains no
vendored asset directory, no numbered migrations, no thin one-hook registration classes, and no
directory-per-subsystem layout with a diagnostic-class sibling per mechanism. A gate written here for
those shapes would pass because the offending population is **absent**, not because the ranker
handles it — green-while-inert, which is the specific failure this project's gate discipline exists
to prevent. That is the whole reason the fourth bucket was held out of an earlier fix lane rather
than gated on this tree.

So the slice is pinned to two outside trees that do contain the populations, and the instrument is
the same `--for` computation an agent actually consumes.

## 2. The instrument

| Piece | File | Status |
|---|---|---|
| Corpus pins + materialize recipe | `bench/recalleval/extcorpus.lock` | new, committed |
| Labels, django half | `bench/recalleval/labels_extcorpus_django.tsv` | new, committed (30 rows) |
| Labels, webpack half | `bench/recalleval/labels_extcorpus_webpack.tsv` | new, committed (24 rows) |
| Absolute per-bucket scorer | `bench/recalleval/run_extcorpus.py` | new, committed |
| Per-query comparative diff | `bench/recalleval/run_r3diff.py` | existing, unmodified — runs the slice as-is |
| Class vocabulary | `bench/recalleval/run_recalleval.py` | widened by one constant; both lanes still green |

**Corpora are pinned, not committed.** ~1 GB of third-party source under its own licences is not
vendored into a public export. The integrity anchor is the commit pin *plus* the tree hash, verified
by `run_extcorpus.py` before any query runs; a mismatch is a hard refusal (exit 2), never a quiet
re-baseline. Recorded honestly: this is a weaker anchor than the content-hashed packs the two in-tree
corpora use, because an upstream force-push could make a pin unfetchable. The mitigation is that the
failure mode is a refusal to measure, not a wrong measurement.

**Reproduce the baseline** (both binaries and both corpora identical to the numbers below):

```
mkdir -p <corpora-dir> && cd <corpora-dir>
git clone --filter=blob:none --no-checkout https://github.com/django/django.git django
git -C django   checkout --detach 03988c5a5ba248c3b9b11ea96fd4fda5e98849aa
git clone --filter=blob:none --no-checkout https://github.com/webpack/webpack.git webpack
git -C webpack  checkout --detach a943d69c4fd4e7b3edcdc03bce7c41eceef3bfd6

python3 bench/recalleval/run_extcorpus.py --bin ./build/ripwire --corpora-dir <corpora-dir>
```

**Labels.** 54 rows. Every gold was chosen by READING the pinned source at the pinned commit — the
file's body, its class, its hooks — never by transcribing a rank. Per-row provenance is recorded in
each label file, split into `OBSERVED` (the query shape came from the head-to-head that diagnosed the
bucket) and `NEW` (authored in this lane from source). **New rows are the majority of every bucket on
purpose**: a band fitted to the exact query set that produced a diagnosis measures the fit, not the
mechanism. Of 54 rows, **5 are `OBSERVED`** (2 `diagnostic-class`, 1 `thin-registration`,
1 `subsystem-directory`, 1 `vendored-asset`) and **49 are `NEW`**.

## 3. Baseline — measured at `3702693`, before any ranker code was written

Binary: plain dev build (no build type) of `3702693` in a clean worktree. `--top-k=10`. Two full runs
byte-identical. Zero skipped labels — every labelled path resolves on disk in both pinned trees.

### Combined (the registration's headline numbers)

| Bucket | n | gold in top-5 | strict r@1 | strict r@5 | strict r@10 | lenient r@5 | strict MRR | asset slots in top-5 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `diagnostic-class` | 14 | **7 / 14** | 21.4% | **50.0%** | 57.1% | 57.1% | 0.332 | 0.0% |
| `thin-registration` | 14 | **7 / 14** | 42.9% | **50.0%** | 64.3% | 50.0% | 0.486 | 0.0% |
| `subsystem-directory` | 14 | **4 / 14** | 7.1% | **28.6%** | 50.0% | 35.7% | 0.159 | 0.0% |
| `vendored-asset` | 12 | **6 / 12** | 16.7% | **50.0%** | 58.3% | 58.3% | 0.326 | **10.0%** (6 of 60) |

### Per corpus (the split matters — see the interpretation notes)

| Bucket | django n | django strict r@5 | webpack n | webpack strict r@5 |
|---|---:|---:|---:|---:|
| `diagnostic-class` | 6 | 66.7% | 8 | 37.5% |
| `thin-registration` | 6 | 66.7% | 8 | 37.5% |
| `subsystem-directory` | 6 | 33.3% | 8 | 25.0% |
| `vendored-asset` | 12 | 50.0% | — | — (population absent) |

### Two things the baseline confirms, and one it does not

1. **The buckets reproduce, and they are not the same bucket.** `subsystem-directory` is far the
   worst (4 of 14) and is the only one where a majority of golds are missing at depth 10. The two
   name-driven buckets sit at exactly half. That spread is what makes four separate bands worth
   registering instead of one aggregate.
2. **The asset population is live and is charged where it should be.** 6 of 60 top-5 slots on the
   task-shaped django queries are vendored assets or numbered migrations — including the two
   independently-observed slots on the database-backend-feature-flag query. The other three buckets
   show 0.0%, which is the honest reading: this is a district failure, not background noise, and a
   path de-prioritization is the mechanism that can move it.
3. **What the baseline does NOT establish** is that a low gold-rank rate in `vendored-asset` is
   *caused* by asset noise. Several of those queries are hard for reasons unrelated to it (a task
   phrased in feature vocabulary whose answer is one unglamorous module). The asset-slot share is the
   metric that sees the mechanism; gold rank in that bucket is registered as a **non-inferiority
   guard only**, and reading it as evidence for the bucket would be an overclaim.

## 4. Proposed bands — PROPOSED, not registered

House rule: a band is at least 2 units wide, and the unit is a whole label row (the metric is a count
over a fixed deterministic set, so a band narrower than 2 rows reads label-set sensitivity rather
than a mechanism).

| Bucket | Registered metric | Baseline | Proposed ACCEPT band | Width | Headroom |
|---|---|---:|---|---:|---:|
| `diagnostic-class` | net flipped rows, gold-in-top-5, n=14 | 7 | **[+2, +6]** | 5 rows | +7 |
| `thin-registration` | net flipped rows, gold-in-top-5, n=14 | 7 | **[+2, +6]** | 5 rows | +7 |
| `subsystem-directory` | net flipped rows, gold-in-top-5, n=14 | 4 | **[+3, +8]** | 6 rows | +10 |
| `vendored-asset` (primary) | vendored/generated slots in top-5, of 60 | 6 | **[0, 2] slots remaining** | 3 slots | 6 |
| `vendored-asset` (guard) | net flipped rows, gold-in-top-5, n=12 | 6 | **[−1, +4]** | 6 rows | +6 |

**Reading of each edge, so nobody has to reconstruct it later.**

- *Lower edges are non-zero on the three ranking buckets* because each proposed fix is a deliberate
  ranking change with a real cost surface (see the floors in §5). A change that moves one row is
  indistinguishable from a change that moved that row by accident; two is the smallest result the
  mechanism can be credited with. `subsystem-directory` starts at +3 because it starts from the
  lowest base and its proposed fix (path components as evidence, or a directory-cluster row) is the
  bluntest instrument on the list — a fix that blunt moving only two rows has not earned its cost.
- *Upper edges are leakage guards, not ceilings.* A perfect score (`+7`, `+7`, `+10`) is deliberately
  **outside** every band. A ranking change that lifts every gold in a bucket has almost certainly
  found the label set rather than the mechanism, and that result is to be **audited, not banked** —
  the same posture an earlier round took when a fix over-performed its registered ceiling.
- *The asset band is stated in slots, not rows*, because slots is the unit the mechanism moves. `[0,
  2]` demands that at least 4 of the 6 offending slots go away. Reaching 0 is in band: unlike the
  ranking buckets there is no leakage story for a path filter that removes exactly the paths it names.
- *The asset guard is non-inferiority-shaped* (`−1` allowed): de-prioritizing a path family can cost
  a gold if a gold ever sat behind one, and one row of that is an acceptable price for the slot
  recovery. Two rows is not.

**Interpretation note that must travel with any result: the buckets overlap in one place and it is
not hidden.** Six of the eight webpack `thin-registration` golds live under `lib/ids/`, which is also
a `subsystem-directory` population. A fix that works purely by lifting directories would therefore
move BOTH bucket rates, and a reader would over-credit it. Any result must report the two buckets'
movement separately AND state how many of the `thin-registration` flips were `lib/ids/` rows; a fix
whose `thin-registration` gain is entirely `lib/ids/` is a `subsystem-directory` fix wearing two hats.

**One measurement, one attempt.** Each bucket gets exactly one measurement against these bands. A
retry is a new round with a fresh registration.

## 5. Simultaneous floors — all must hold; a win on one surface bought past a floor on another is a REJECT

Every value below was measured at `3702693` in this lane, on the same binary that produced §3.

### Skill routing (`ripwire skills --eval-skills=test/skillevalfix/prompts.tsv`)

| Metric | Floor | Measured at `3702693` | Headroom |
|---|---:|---:|---|
| split=test `bm25-desc` hit@1 | **60.0%** | **73.1%** | 13.1pp |
| split=test `bm25-desc` sep-auc | **0.89** | **0.957** | 0.067 |
| split=dev `bm25-desc` hit@1 | 46.0% | 69.1% | 23.1pp |
| split=dev `bm25-desc` sep-auc | 0.75 | 0.887 | 0.137 |
| judged-only `bm25-desc` hit@1 | 50% | 64.5% (98/152) | 14.5pp |
| judged-only `for-routed` hit@1 | 50% | 61.2% (93/152) | 11.2pp |

The two bolded rows are the floors named in the round brief. Both hold with room today; the round's
obligation is that they still hold after the fix, and `test/skillevalcheck.sh` /
`test/skillroutingjudgedcheck.sh` are the arbiters, not this table.

### Recall and ranking lanes (`test/recallevalcheck.sh`, frozen corpora)

| Metric | Floor / ceiling | Measured at `3702693` | Headroom |
|---|---:|---:|---|
| recall lane lenient recall@5 | ≥ 71% | 88.1% | 17.1pp |
| recall lane lenient MRR | ≥ 0.57 | **0.643** | 0.073 |
| LIVE-corpus pollution@5 | ≤ 16% | 2.4% | 13.6pp |
| ranking lane lenient recall@5 | ≥ 70% | **71.9%** | **1.9pp — the tightest floor on the board** |
| ranking lane lenient MRR | ≥ 0.55 | 0.639 | 0.089 |
| ranking lane pollution@5 | ≤ 5% | 0.0% | 5.0pp |
| ranking adversarial-class pollution@5 | ≤ 8% | 0.0% | 8.0pp |

Frozen corpora at the measurement: docs `commit=7a7f79892034 files=113 sha=cfeb23c71cd2`, source
`commit=7a3194b51ac6 files=1422 sha=eb25c17569d5`.

**The ranking lane's lenient recall@5 is the one to watch.** 71.9% against a 70% floor is under two
labels of margin on a 32-label lane. Three of the four proposed fixes are general ranking changes, so
this is the floor a bucket win is most likely to be bought past — and buying it is a REJECT, not a
trade.

**Expected direction on the in-tree lanes: neutral, and no directional claim is registered.** The
frozen corpora carry none of the four populations, which is why the slice exists; a change targeted
at them should be close to inert here. If an in-tree lane moves *up*, that is an unregistered result
and is reported, not banked.

### Standing requirements (not part of any band)

`python3 test/pargates.py . ./build/ripwire -j 6` rc=0 · ASan clean under the committed suppressions ·
two runs of the slice and of both lanes byte-identical · `--quality-delta` with zero unacked
regressions · `bash test/ripwirepubliccheck.sh` clean.

## 6. Decision rule

For each bucket independently: **in band with every floor in §5 green → keep that bucket's change.**
Out of band on either edge, or any floor breached → **revert that bucket's change**, keep this
registration and the negative result on record, and keep any gate added for it only if it still
describes shipped behavior.

The four buckets are separable and may be attempted in separate commits; a bucket whose fix is
reverted does not invalidate the others. What is NOT permitted is re-cutting a band after seeing a
result, adding labels to a bucket after measuring it, or refreshing the corpus pins in the same
commit as a measurement — each of those turns the instrument into a description of the fix.

## 7. Known limits of this slice, recorded before it is used to decide anything

- **Two repositories, two languages** (Python, JavaScript). Nothing here says a fix generalizes to
  C++, Go, Rust or Swift. A fix that is language-neutral by construction (a scoring term, a path
  weight) inherits that claim from its own shape, not from this measurement.
- **54 labels across 4 buckets** is small. Per-bucket n of 12–14 is why the bands are stated in whole
  rows and why a 1-row move is registered as indistinguishable from noise.
- **The labels are ours.** Authored from source before any ranking work and frozen, but not drawn
  from an external gold set. Five rows carry an outside arm's answer on record; 49 do not.
- **`acceptable` is used narrowly** — only a file that would let an agent land the task without
  another call. A wider list would flatter every number in §3.
- **The corpus is pinned to a moving upstream.** Both trees are active projects; these commits are
  reachable today and the instrument refuses rather than drifts if they stop being.
- **The two name-driven buckets overlap by six rows** (see §4). Any result must decompose it.
