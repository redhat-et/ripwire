# The small-vector A/B — what was measured, and what it decided

Four implementations of the same shape, measured in situ over the real pipeline rather than argued
about. Driven by `bench/svectorab.py` on top of the one-line alias in `src/smallvec.h`.

| arm | type | bytes/instance | inline slots | `size()` |
| --- | --- | --- | --- | --- |
| 0 | `std::vector<T>` | 24 | 0 (always heap) | branch-free |
| 1 | `ankerl::svector<T,2>` | **16** | **3** (fills its own padding) | branches on the SVO tag |
| 2 | `rw::svector<T,2>` | 24 | 2 | branch-free |
| 3 | `rwx::svector16<T,2>` | **16** | 2 | branch-free |

Arm 3 is the experiment from `bench/svector_union_arm.h`: `rw::svector` with `inl_` and `heap_`
unioned, which reaches ankerl's 16 bytes while keeping the size in its own field.

---

## The denominator, first — because it decides whether any of this looks like a win

Total runtime is **parse-dominated and mostly not ours**. Measured phase table on the large corpus
(`-DRIPWIRE_PROFILE=ON`, `--no-cache`):

| | wall ms | share of total |
| --- | --- | --- |
| `ingest: total (crawl + parse + model)` | 837.4 | **~96% — tree-sitter, not ours to optimize** |
| `buildGraph: resolve refs + build CSR` | 23.5 | 2.7% |
| `rankGraph: PageRank` | 7.3 | 0.8% |
| `emit: serialize ranked map` | 0.6 | 0.1% |
| **post-parse pipeline (the controllable part)** | **31.4** | **3.6%** |

**Every timing delta below is reported against the 31.4 ms post-parse figure, not against the ~900 ms
total.** Reporting against the total is how a real win gets written off as noise: the same 1.5 ms is
0.17% of total runtime and **4.9% of the part we control**. `buildGraph` alone is 75% of post-parse
time, so a win localized there is not diluted.

## The headline

**Measured against post-parse pipeline time, converting away from `std::vector` is worth ~4.9% and is
easy. Choosing between the three small-vectors is worth ≤1.5% and is not.**

And the committed "~25% faster than ankerl" figure **does not reproduce in situ** — it is a
microbenchmark artifact, corrected now in both places that asserted it (`bench/bench_svector3.cpp`,
`src/infra/svector.h`). In situ ankerl is 1.9% behind `rw` on `buildGraph`, which is 1.5% of post-parse
and 0.17% of total.

---

## 1. End-to-end, four arms, both corpora

`bench/svectorab.py --reps 7`, fresh build tree per arm, `--no-cache` on every run, arm order rotated
per rep. All four arms emitted **byte-identical maps** on both corpora (checked, not assumed), and the
four binaries were confirmed distinct (the non-vacuity guard).

| arm | `src` median | spread | vs rw | large-corpus median | spread | vs rw |
| --- | --- | --- | --- | --- | --- | --- |
| `std::vector` | 147.1 ms | 138–151 | +0.7% | 918.5 ms | 815–1047 | +1.5% |
| `ankerl::svector` | 150.2 ms | 143–219 | +2.8% | 870.8 ms | 817–930 | −3.7% |
| `rw::svector` | 146.1 ms | 142–173 | — | 904.7 ms | 822–980 | — |
| `rwx::svector16` | 148.2 ms | 142–158 | +1.4% | 903.2 ms | 828–981 | −0.2% |

Every spread overlaps every other spread. **Null result on both corpora.** The machine was contended
during these runs (other builds in flight), which is visible in the ±9% spreads and is the honest
reason the end-to-end numbers cannot resolve anything smaller.

## 2. The affected phase only — where a difference is actually visible

Same binaries, `-DRIPWIRE_PROFILE=ON`, 11 interleaved reps, reading only the
`buildGraph: resolve refs + build CSR` scope. The **A/A noise floor** is `rw` against its own
split-half samples at the same cardinality; nothing below it is a result.

`src` was re-run at 41 reps specifically to tighten its floor from 6.1% to 1.9%, because the
corpus-size comparison below turns on it.

| arm | `src`, 41 reps (floor **1.9%**) | large corpus, 11 reps (floor **0.3%**) |
| --- | --- | --- |
| `std::vector` | 3.68 ms (**+3.5%**) | 26.97 ms (**+6.0%**) |
| `ankerl::svector` | 3.55 ms (−0.2%, inside floor) | 25.91 ms (**+1.9%**) |
| `rw::svector` | 3.55 ms (—) | 25.44 ms (—) |
| `rwx::svector16` | 3.61 ms (+1.5%, inside floor) | 25.48 ms (+0.2%, inside floor) |

Restated against the 31.4 ms post-parse denominator (large corpus):

| arm | delta on `buildGraph` | in ms | **share of post-parse pipeline** | share of total runtime |
| --- | --- | --- | --- | --- |
| `std::vector` | +6.0% | +1.53 ms | **+4.9%** | +0.17% |
| `ankerl::svector` | +1.9% | +0.48 ms | **+1.5%** | +0.05% |
| `rwx::svector16` | +0.2% | +0.05 ms | +0.16% (inside floor) | — |

- **`std::vector` → any small-vector is worth ~4.9% of the controllable pipeline.** That is the wave's
  real payoff, it is the same for all three small-vectors, and it is the number to quote.
- **ankerl is 1.9% behind `rw` on the phase — 1.5% of post-parse**, not 25% of anything.
- **The union arm matches `rw` at ankerl's 16 bytes.** The hypothesis held; the margin does not matter.

An earlier n=1 reading of this same table had the union arm 14% ahead. It was noise; 11 reps removed
it. Recorded because it is exactly the trap the repetition discipline exists for.

## 3. Heap allocations — deterministic, no noise floor needed

`-DRIPWIRE_ALLOC_COUNT=ON` (`src/alloccount.cpp`). Only the **delta between arms** is attributable to
the container; the absolute totals include tree-sitter and every `std::string` in the symbol table.

| arm | large-corpus allocs | vs `std::vector` | total bytes | peak live |
| --- | --- | --- | --- | --- |
| `std::vector` | 813,693 | — | 1,336.2 MB | 113.0 MB |
| `ankerl::svector` | 748,378 | **−65,315 (−8.0%)** | 1,327.4 MB | 109.4 MB |
| `rw::svector` | 750,699 | −62,994 (−7.7%) | 1,322.2 MB | 107.0 MB |
| `rwx::svector16` | 750,736 | −62,957 (−7.7%) | 1,320.0 MB | **106.2 MB** |

On `src`: ~8,400 allocations avoided (−9.1%) by any small-vector.

Two things worth naming. **ankerl avoids the most allocations** — its inline capacity is genuinely 3,
not 2, so more lists stay inline. And **the union arm has the lowest peak live bytes**, 6.8 MB under
`std::vector`, which is the 8-bytes-per-instance saving showing up exactly where it should.

### What these numbers do and do not cover

The alias currently spans the **14 pre-existing `rw::svector` type-mentions**, not the wave's ~101
candidate structures. Split by when they are built, because a win a user feels on every call is a
different thing from one behind a verb flag:

| subset | sites | built | in the numbers above? |
| --- | --- | --- | --- |
| `byName`, `canonByName`, `defs`, `kept`, `fnBindTargetIds`, `pushCFamily`, and `resolve.h`'s rule 1/2/3 | 12 of 14 | **every invocation**, inside `buildGraph` | **yes** — a default run builds exactly these |
| `docdrift.h::byBase` | 1 | `--doc-drift` only | no |
| `contextratio.h::NameDefs` | 1 | `--context-ratio` only | no |

So everything reported here is the **always-on subset**, which is the actionable one. The verb-gated
pair and the wave's other structures (`varSpans`, `fileIncludes`, `symbolAdjacency`, the `byFile`
family) are not behind the alias yet and are not measured. Treat the allocation figures as a **floor
for the wave**, not a total.

## 4. Allocator contention — why the thread-count sweep was not run

The hypothesis: allocations on a parallel path are a shared-resource serialization point, so removing
them is a *scaling* win rather than a constant-factor one, and the instrument is an A/B at 1 / mid /
full thread counts.

**It does not apply to anything currently behind the alias, and the reason is structural rather than
experimental.** `buildGraph` — where all 12 always-on converted sites live — contains **no threading at
all**: no `std::thread`, no `hardware_concurrency`, no async, across its whole span from `graph.h:613`.
It is single-threaded start to finish. Allocator contention cannot be a mechanism for a structure that
is only ever touched by one thread.

The parallel paths in this tree are elsewhere — `ingest.cpp` (5 sites, the per-file tree-sitter parse
pool), `docdrift.h` (2), `lexical.h`, `search.h`, `crossref.h`. Of those, the only one the alias reaches
is `docdrift.h`, and that is verb-gated. There is also **no CLI or environment knob for thread count**
(checked: no `--jobs`/`--threads` flag, no `RIPWIRE_*THREAD*` getenv), so a sweep would need a new knob
added first.

**This is a real result, not a skipped task**: the contention argument is sound and the owner's
reasoning about libmalloc holds, but it becomes testable only when the wave converts a structure on the
parallel ingest path. When it does, the sweep is the right instrument and the 1-thread-vs-N-thread
delta is the contention measurement. Recorded here so the question is asked at the right time rather
than answered against a single-threaded phase and wrongly retired.

The two mechanisms stay separate in this report and should stay separate in the next one: **locality**
(fewer dependent loads) and **contention** (fewer trips to a shared allocator) can each be present or
absent on their own, and neither is evidence for the other.

## 5. Which MECHANISM is operating — the corpus-size arbitration

Three mechanisms could produce a small-vector win, and they are separable by how the win *behaves*
rather than by its size:

| mechanism | signature | verdict here |
| --- | --- | --- |
| (a) allocator contention | win grows with thread count | **inapplicable** — the phase is single-threaded (§4) |
| (b) cache locality | win grows with corpus size; shows in miss counters | **not observed; the sign is wrong** |
| (c) the `size()` branch | win flat in both; shows in branch/instruction counts | **the only mechanism consistent with the data** |

The prediction for (b) was explicit: if cache residency decides, the 16-byte arms should rank
*relatively better* on the larger corpus, because that is the only regime where 8 bytes per instance
can bind. **The opposite happened.**

| | `src` (~9K symbols) | large corpus (~43K symbols) | direction |
| --- | --- | --- | --- |
| ankerl (16 B, branching) vs rw (24 B, branch-free) | −0.2% (tied, inside floor) | **+1.9% (measurably worse)** | ankerl gets **worse** as the corpus grows |
| union (16 B, branch-free) vs rw (24 B, branch-free) | +1.5% (inside floor) | +0.2% (inside floor) | tied everywhere |

Being 16 bytes bought **nothing** that grew with working-set size. The union arm — 16 bytes *and*
branch-free — is indistinguishable from the 24-byte `rw` on both corpora, which is the cleanest
possible isolation: hold the branch constant, vary only the size, and the difference disappears. Vary
only the branch (ankerl vs union, both 16 B) and a difference appears on the larger corpus.

This matches the hardware note rather than contradicting it: on a large-cache, 128-byte-line Apple
part, more of the working set stays resident, so the locality advantage of being smaller does not bind
and the branch is what is left. **On this machine, size is not the axis; the branch is** — and the
branch is worth 1.9% of a phase that is 2.7% of a run.

Honest limits on that conclusion: it is inferred from how the deltas *behave* across corpus size, not
confirmed by branch-miss counters (see §6 — no root). And "the branch is the axis" is a statement about
this hardware tier and these two corpus sizes; a smaller-cache machine or a much larger corpus could
still put (b) back in play.

## 6. Is the workload memory-bound?

**UNAVAILABLE by counter.** This is the arm that would have CONFIRMED §5 rather than inferred it. `prof::pmc` needs root on Apple (kperf) and this session had no
passwordless `sudo`, so IPC and MPKI were never armed. A measure that could not be evaluated is
UNAVAILABLE, never "no difference" — re-run `sudo bench/bench_svector_wave.cpp` to fill this in.

The root-free proxy (`bench_svector_wave --sweep`, holding code fixed and growing the working set) is
**inconclusive**. Usable rows only — the two largest cardinalities had A/A floors of 55% and 90% on a
contended box and are discarded:

| names | value array | ankerl vs rw, size-hot | ankerl vs rw, iterated | floor |
| --- | --- | --- | --- | --- |
| 25,000 | 0.57 MB | +19.8% | +12.1% | 2.0% |
| 50,000 | 1.14 MB | +22.2% | +15.1% | 0.6% |
| 100,000 | 2.29 MB | +27.1% | +16.8% | 4.4% |

The 16-byte arms do **not** pull ahead as the working set grows across this range — ankerl stays
consistently *behind*, and the union arm stays within ~2% of `rw`. At these sizes the evidence points
at the `size()` branch mattering more than the 8 bytes, i.e. **not** memory-bound in the regime tested.
That is a weaker claim than a counter reading and is labelled as such.

## 7. The decision rule

Keyed on what the measurement actually showed, not on what was expected.

| situation | choose | why |
| --- | --- | --- |
| **Any conversion from `std::vector`** | any small-vector | **+4.9% of post-parse pipeline time**, ~8% fewer allocations, ~7 MB lower peak. This is the wave's real payoff and all three arms deliver it equally. |
| **Default for the conversion wave** | **`ankerl::svector`** | Costs 1.5% of post-parse against the best arm, is 8 bytes smaller, avoids the most allocations, and is complete (25 ops), vendored, maintained and already in the tree. |
| **A genuinely hot branch-free `size()` poll on a LARGE corpus** | `rw::svector` | The branch is the only mechanism that survived §5, and it is worth 1.5% of post-parse — but only at ~43K symbols; at ~9K the two are tied. The survey found exactly one such site (`search_perFileSites`). |
| **Over-aligned `T`, or a `T` with a side-effecting destructor** | `ankerl::svector` | ankerl `static_assert`s against over-aligned `T`; `rw::svector` ties element lifetime to buffer lifetime. Neither is a general container. |
| **The two biggest structures (`symbolAdjacency`, `fileIncludes`)** | **CSR, not a small-vector** | 2.5–3× smaller than either svector. Do not spend the small-vector budget here. |

**The honest bottom line: use the vendored complete one.** On this workload the differences between the
three small-vectors are at or under 2%, and `ankerl::svector` is free — no maintenance, no hand-rolled
lifetime rules, no second type to keep correct. That conclusion would retire `rw::svector` rather than
grow it, and the measurement supports it.

### On the union arm (arm 3)

It worked: 16 bytes, branch-free `size()`, lowest peak memory, and correctness-clean under the
differential harness including the union-specific hazards. But it buys **+0.2% (inside the noise
floor)** over `rw::svector` and ~1.7% over ankerl on the affected phase, against the cost of a second
hand-rolled small-vector with union lifetime rules. **Recommendation: do not promote it.** It stays in
`bench/` as a measured, documented negative-value result so nobody rebuilds it on a hunch.

---

## Reproducing

```bash
bench/svectorab.py --reps 7 --corpus src --corpus /path/to/large/corpus   # end-to-end, 4 arms
bench/svectorab.py --instrumented --keep                                  # phases + allocations
c++ -O2 -std=c++23 bench/bench_svector_wave.cpp -Isrc -Isrc/infra -Ithird_party -Ibench -o /tmp/w
/tmp/w              # shape-level, with the known-negative arm printed every run
/tmp/w --sweep      # working-set sweep
sudo /tmp/w         # + PMC counters (the memory-boundedness verdict)
```

Correctness first: `bash test/svectorcheck.sh` must be green before any number here is worth reading.

### Measurement hygiene these tools enforce

- a **fresh build tree per arm**, never an incremental rebuild;
- `--no-cache` on **both sides** of every comparison;
- **non-vacuity** — the arm binaries must differ, or the alias flip did nothing;
- **output equivalence** — all arms must emit byte-identical maps, or they are not doing the same work;
- **interleaved reps** with rotated arm order, and median plus spread rather than a bare mean;
- a **known-negative arm** (the same implementation twice) printed on every run of the shape rig, so the
  noise floor is always on screen next to the deltas. It is the reason the n=1 union-arm result in §2
  was caught instead of published.
