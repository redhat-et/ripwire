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
easy. Choosing between the three small-vectors is worth ≤1.5%, and which one wins depends on whether
the site polls `size()` or iterates.**

Three mechanisms were separated with hardware counters and a working-set sweep (§5). Only one of them
reaches the cardinalities this tool actually indexes:

| effect | size at 200K names | **size at real cardinality (3K–43K)** |
| --- | --- | --- |
| instance size 16 vs 24 B (locality) | −11.7% | **−0.2% to −0.5% — does not switch on** |
| ankerl's `size()` branch, inline lists | ~+6–9% | **~+6–7% — present everywhere** |
| ankerl's `size()` dependent load, spilled lists | +42–55% | rare here (~0.6% of names spill) |

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

## 5. Which MECHANISM is operating — corrected by hardware counters

> **This section previously concluded "it is the `size()` branch, not cache locality." That was wrong,
> and it was wrong twice over.** It was inferred without counters, from a shape-level run taken on a
> heavily contended machine whose own numbers did not reproduce. A counter run under `sudo`, plus a
> re-run on a quiet machine, overturned it. Both corrections are kept visible rather than edited away.

### What the counters said

At 200,000 names (`sudo bench_svector_wave`), the workload is **unambiguously memory-bound**:

| loop | IPC | L1D-MPKI | LLC-MPKI | verdict |
| --- | --- | --- | --- | --- |
| size-hot | 0.70 | 225.5 | 84.9 | memory-bound |
| iterated | 0.42 | 217.8 | 66.9 | memory-bound |

An LLC miss rate of 85 per thousand instructions at IPC 0.70 is not a compute-bound profile by any
reading. The earlier "compute/branch-bound" inference is retracted.

### Three effects, not two — and they live in different regimes

The union arm makes the variables genuinely separable, because D differs from C **only in size** (16
vs 24 B, both branch-free) and from B **only in the size() implementation** (both 16 B).

| # | effect | isolated by | where it bites |
| --- | --- | --- | --- |
| (i) | **instance size / value-array footprint** | D vs C | only past ~2.3 MB of value array |
| (ii) | **ankerl's `size()` branch, INLINE regime** | B vs D, short lists | everywhere, ~6–7% |
| (iii) | **ankerl's `size()` DEPENDENT LOAD, SPILLED regime** | B vs D, long lists | only when lists spill |

Effect (iii) is the one nobody named, and it is the largest. ankerl's `size()` is not merely a branch:

```cpp
auto size() const -> size_t { if (is_direct()) { return size<direction::direct>(); }
                              return size<direction::indirect>(); }   // -> indirect()->size()
```

`size<indirect>()` is `indirect()->size()` — read the pointer out of the SVO buffer, then **dereference
into the heap block's header**. Under a memory-bound profile that is a second cache miss, not a
predicted branch. `rw`/`rwx` read `sz_` out of the instance, which is already resident, in both regimes.

### The regime map, measured

Work held constant (4M reads at every point); only the working set varies. `~` = inside that column's
own A/A floor. Starred rows are real: ripwire's own tree indexes **3,220** symbols, the large
validation corpus **43,354**.

| names | value array | **D vs C** (isolates size) | floor | **B vs C** (size + `size()` cost) | 
| --- | --- | --- | --- | --- |
| **3,220*** | 75 KB | −0.2% `~` | 0.3% | +5.9% |
| 10,000 | 234 KB | −0.1% | 0.0% | +7.6% |
| **43,354*** | 1,016 KB | −0.5% | 0.2% | +7.0% |
| 100,000 | 2,344 KB | +0.1% `~` | 0.7% | +8.9% |
| 200,000 | 4,688 KB | **−6.4%** | 0.5% | +2.5% |
| 400,000 | 9,375 KB | **−2.8%** | 0.5% | +6.2% |

**Effect (i) — locality from instance size — does not exist below ~100,000 names.** At both real
cardinalities D beats C by 0.2–0.5%, at or barely above the floor. It switches on only past a ~2.3 MB
value array, which is 2.3× the largest corpus this tool has ever been pointed at and 31× its own tree.

**Effect (ii) — the branch — is present at every size, ~6–9%, and is flat.** It is the only mechanism
that reaches the real workload.

### Why the owner's run showed ankerl losing 55% and the sweep shows 6%

Both are correct; they are different regimes, and the difference is **ids per name**:

- the single-point rig pushes 1,000,000 ids over 200,000 names — **5 per name**, so lists spill past
  ankerl's inline capacity of 3 and every `size()` becomes effect (iii), the dependent load;
- the sweep pushes ~1.5 per name, which is `byName`'s **real** shape (`graph.h` documents "most names
  define 1-2 symbols", and only ~0.6% of names ever spill), so ankerl stays inline and pays only (ii).

So the 42–55% figure is real but describes a spill rate ripwire does not have. **At the real spill rate
the honest number for ankerl is ~6–7% on the size-hot loop**, which dilutes to the 1.9% measured on the
whole `buildGraph` phase in §2 — the two measurements are consistent, not in conflict.

### Contention

Still inapplicable to anything behind the alias (§4): the phase is single-threaded. Unchanged.

## 6. Is the workload memory-bound? — ANSWERED (superseded, kept for the method)

**UNAVAILABLE by counter.** This is the arm that would have CONFIRMED §5 rather than inferred it. `prof::pmc` needs root on Apple (kperf) and this session had no
passwordless `sudo`, so IPC and MPKI were never armed. A measure that could not be evaluated is
UNAVAILABLE, never "no difference" — re-run `sudo bench/bench_svector_wave.cpp` to fill this in.

**Yes, at 200K names — see §5 for the counters** (IPC 0.70, LLC-MPKI 84.9). The counter run settled
what the root-free proxy could not.

The methodological lesson is worth keeping, because it cost two wrong conclusions:

- **The proxy was run on a contended machine and its numbers did not reproduce.** The original sweep
  reported the union arm ~2% *behind* `rw` at 200K; a quiet re-run of the identical binary and config
  put it **11.6% ahead**, matching the owner's independent `sudo` run (11.7%) almost exactly. Nothing
  about the code changed. Load average during the first run was high enough that the two largest
  cardinalities carried A/A floors of 55% and 90% — and a 55% floor should have been read as "this
  machine cannot measure right now", not as "discard two rows and keep the rest".
- **A single global noise floor masked a real effect.** The rig reported one floor, the max across
  columns. The `rehash` column is ~6 ms, so a 0.4 ms wobble is 6.6% there, and that number became the
  bar for the `size` column whose own floor was 0.3% — burying an 11.7% result 39× its actual noise.
  Fixed: the rig now prints a floor **per column** and marks any delta inside its own column's floor,
  with the global max kept alongside as the conservative reading rather than the only one.

Rule adopted from this: an A/A floor above ~10% is a **machine-state failure, not a wide error bar**.
Re-run when quiet; do not reason about deltas underneath it.

## 7. The decision rule

Keyed on what the measurement actually showed, not on what was expected.

The rule now keys on **whether the site polls `size()`**, because that is the only mechanism that
reaches real cardinality.

| situation | choose | why |
| --- | --- | --- |
| **Any conversion from `std::vector`** | any small-vector | **+4.9% of post-parse pipeline time**, ~8% fewer allocations, ~7 MB lower peak. The wave's real payoff; all three arms deliver it equally. |
| **A site that ITERATES (range-for) and never polls `size()`** — the large majority of the ~138 | **`ankerl::svector`** | At real cardinality the iterated column is a wash (+0.6% / −0.6%, inside floor). ankerl is then 8 bytes smaller, avoids the most allocations, and is complete, vendored and maintained. |
| **A site that polls `size()` in a hot loop** | **`rw::svector`** | ~6–7% on the size-hot loop at *both* real cardinalities, flat and reproducible — 1.9% of `buildGraph`, 1.5% of post-parse. `rw` now has full interface parity, so this no longer costs generality. |
| **A site that polls `size()` on lists that SPILL past 3** | **`rw::svector`, emphatically** | ankerl's `size()` becomes a dependent load into the heap block; measured 42–55% on the size-hot loop. Rare in `byName` (~0.6% spill) but decisive wherever lists are long. |
| **Over-aligned `T`, or a `T` with a side-effecting destructor** | `ankerl::svector` | ankerl `static_assert`s against over-aligned `T`; `rw::svector` ties element lifetime to buffer lifetime. |
| **The two biggest structures (`symbolAdjacency`, `fileIncludes`)** | **CSR, not a small-vector** | 2.5–3× smaller than either. Do not spend the small-vector budget here. |

**Revised bottom line.** The earlier flat "standardise on ankerl, retire `rw::svector`" does not
survive the counter run and is withdrawn. `rw::svector` is measurably better wherever `size()` is
polled, the margin is real at every cardinality tested, and now that it has full interface parity the
maintenance argument that justified retiring it is much weaker. **Keep both, and pick by access
pattern**: iterate → ankerl, poll `size()` → `rw`. The absolute stakes remain modest (1.5% of
post-parse pipeline time, 0.05% of total runtime), so this is a tie-breaker rule, not a rewrite mandate.

### On the union arm (arm 3) — dismissal upheld, reasoning replaced

The earlier dismissal cited "+0.2%, inside the noise floor". **That number was contention noise and is
withdrawn.** On a quiet machine the union arm is genuinely the best arm at 200K names — best on all
four columns, 11.6–11.7% ahead of `rw` on size-hot (39× that column's 0.3% floor), lowest allocated
bytes and lowest footprint. The owner's reading of the shape-level table is correct.

**It still should not be promoted, for a different and better-supported reason:** its advantage is
effect (i), instance size, and §5 shows effect (i) **does not switch on below ~100,000 names**. At
3,220 and 43,354 — ripwire's own tree and the largest corpus it has been pointed at — D beats C by
0.2–0.5%, at or barely above the floor. The 11.7% win is real and lives entirely in a working-set
regime this tool never enters.

So: a successful experiment, a correct hypothesis, and **no reachable benefit** — which is a different
verdict from "it didn't work", and worth the distinction. It stays in `bench/`, and the sweep table in
§5 is the reason, so that if a corpus ever reaches ~100K distinct names the promotion case can be
reopened on evidence.

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
