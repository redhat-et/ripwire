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

## The headline

**On the real workload the four arms are indistinguishable end-to-end, and the committed "~25% faster
than ankerl" figure does not reproduce in situ.** It is a microbenchmark artifact. See the correction
now carried in `bench/bench_svector3.cpp` and `src/infra/svector.h`.

The reason is not subtle once measured: **the affected phase is 0.2–0.3% of a run.**

| corpus | `buildGraph` phase | full run | phase share |
| --- | --- | --- | --- |
| `src` (~9K symbols) | 3.6 ms | ~580 ms | 0.1–0.2% |
| large corpus (2376 files, ~43K symbols) | 25.4 ms | ~1200 ms (instrumented) / ~900 ms (plain) | 0.2–0.3% |

A 25% win on 0.2% of the run is 0.05% end-to-end — three orders of magnitude under the noise floor.

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

| arm | `src` (floor **6.1%**) | large corpus (floor **0.3%**) |
| --- | --- | --- |
| `std::vector` | 3.73 ms (+3.2%) | 26.97 ms (**+6.0%**) |
| `ankerl::svector` | 3.54 ms (−1.8%) | 25.91 ms (**+1.9%**) |
| `rw::svector` | 3.61 ms (—) | 25.44 ms (—) |
| `rwx::svector16` | 3.62 ms (+0.2%) | 25.48 ms (+0.2%) |

On `src` the floor is 6.1%, so **nothing on that corpus is a result**. On the large corpus the floor is
0.3% and three things are:

- **`std::vector` → any small-vector is worth ~6%** of the phase. That is the conversion wave's real
  payoff, and it is the same for all three small-vectors.
- **ankerl is 1.9% behind `rw`**, not 25%. Real, reproducible, and worth ~0.5 ms per run.
- **The union arm is indistinguishable from `rw` (+0.2%, inside the floor) at ankerl's 16 bytes.** The
  hypothesis held: you can have the smaller struct and the branch-free `size()` at once.

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

## 4. Is the workload memory-bound?

**UNAVAILABLE by counter.** `prof::pmc` needs root on Apple (kperf) and this session had no
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

## 5. The decision rule

Keyed on what the measurement actually showed, not on what was expected.

| situation | choose | why |
| --- | --- | --- |
| **Any conversion from `std::vector`** | any small-vector | ~6% of the affected phase, ~8% fewer allocations, ~7 MB lower peak. This is the wave's real payoff and all three arms deliver it. |
| **Default for the conversion wave** | **`ankerl::svector`** | Within 2% of everything else on the real workload, 8 bytes smaller, avoids the most allocations, complete (25 ops), vendored, maintained, and already in the tree. |
| **A genuinely hot branch-free `size()` poll** | `rw::svector` | Worth 1.9% of the affected phase. The survey found exactly one such site (`search_perFileSites`). |
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
