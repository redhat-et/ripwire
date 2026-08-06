# `--field-affinity` — the cache-locality lens, and the one worked example that validates it

`--field-affinity` answers a question no shipping tool answers: **which fields are read together but
declared far apart?** Every layout tool in the field answers the other one — "where are the holes?"
(pahole, `optin.performance.Padding`, PVS-Studio V802, Go `fieldalignment`, `-Wpadded`). This document
records what the verb is, what it is *not* (almost all of it is 1999 prior art), and the single
end-to-end measurement that closes the loop from a static hypothesis to real hardware.

`src/fieldaffinity.h`'s file header is the design of record; `--help` is the flag contract. This
document is the **evidence**.

## 1. What is prior art (claimed by nobody here as new)

| Idea | Where it comes from |
| --- | --- |
| Field affinity graph (nodes = fields, edges = co-access) | Chilimbi, Davidson & Larus, *Cache-Conscious Structure Definition*, **PLDI 1999** (`bbcache`) |
| Static field-access enumeration approximating an instance as `<function, struct type>`, **explicitly without pointer analysis** | same |
| The separation weight `wt(fi,fj) = (cache_block_size − dist) / cache_block_size` | same — reproduced verbatim in `separationWeight()` |
| Validating layout work against **hardware counters** | same (UltraSPARC) |
| **Advice mode** that reports instead of transforming; per-field D-cache miss counts from PMU sampling; static (Wu-Larus) *and* profile weighting | Hundt, Mannarswamy & Chakrabarti, *Practical Structure Layout Optimization and Advice*, **CGO 2006** (HP SYZYGY, HP-UX Itanium) |
| Recommend-to-the-developer, static + dynamic | Ye, Lis & Fedorova, D-SAG, **MEMSYS 2019** |
| Purely static layout analysis, no profiling | Rohwedder, de Carvalho & Amaral, RebaseDL, **CC 2024** |

**What is actually new is narrow, and it is engineering, not science:** a *source-level,
cross-language-capable, no-debug-info, whole-repo-ranking* implementation. pahole needs DWARF; Hundt's
lived inside one proprietary compiler on a dead architecture; D-SAG needs its own toolchain; RebaseDL is
LLVM-internal; `lshaz` — the one adjacent shipping tool — is Linux-x86-only, needs
`compile_commands.json` plus LLVM dev libraries, and answers the **inverse** question (which fields to
*separate*, for false sharing). Nothing ranks a whole repository from source bytes alone.

**Patent flag, load-bearing:** US9146719 (HP; Hundt/Mannarswamy/Lozano) covers *trace-driven* field
affinity and is active until 2031; US8359291 (IBM) likewise obtains an execution trace. Both are
trace-driven, which is a meaningful distinction from a purely static approach — but get a real
patent-landscape review before publishing or commercialising anything in this area.

## 2. Why it advises and never transforms

Five serious compiler attempts at automatic field layout are dead: GCC `-fipa-struct-reorg` (shipped
4.3–4.6, removed in 4.7 — "did not always work correctly, nor did they work with link-time
optimization"), LLVM GlobalOpt heap SRA (removed 2021; PR50027 "could crash or miscompile"),
EfficiencySanitizer's cache-fragmentation tool (removed 2019), StructFieldCacheAnalysis (never landed),
Qualcomm's 2024 AoS→SoA RFC (dead — C type info is unreliable under pointer casts and type punning).
Every one that died on *soundness* died because a compiler must **prove** a pointer points at a pool of
that struct. **A tool that only advises cannot miscompile.** That is the opening, and also the warning:
the two advisory efforts died of neglect instead.

There is no rewrite mode, and there will not be one.

## 3. Which way is bad — the filter, applied

Exactly two findings fire, because exactly two have a direction defensible in one sentence:

- **`split-line`** — two fields co-accessed by ≥ 2 distinct indexed functions whose byte distance is ≥
  64, i.e. `wt == 0.00`. *No field order can put them on one line as declared.* A fact.
- **`straddle`** — one co-accessed field whose own `[off, off+size)` crosses a 64-byte boundary, so
  every access to that one field touches two lines. Strictly worse than not crossing, at equal size.

**Deliberately not emitted:** "sort fields by decreasing size", "pack tighter", "remove padding". Those
are the universal shipped advice *and* the non-monotonic move. The Go team excludes its own
`fieldalignment` analyzer from `vet` and `gopls` because "the diagnostics produced by fieldanalyzer very
rarely indicate a significant problem", and because "the most compact order is not always the most
efficient" — tight packing co-locates independently-updated fields and can induce false sharing.
§5 below adds a *second*, independently measured reason.

## 4. The two honest limits, disclosed in every header

1. **Static access counts are not dynamic frequency.** One field in a hot loop beats fifty on cold
   paths. `fns=` is a **floor** of distinct indexed functions; `w=` is a call-graph reachability
   **proxy** (`Σ 1 + fan-in`), labelled `weighting="fanin-floor"` and never presented as a frequency.
   Only dot/arrow member syntax is counted — a bare field name inside its own method is
   indistinguishable from a local, so it is not counted, and a field name declared by **two** aggregates
   is *refused* and tallied in `amb_skipped=` rather than guessed.
2. **True `sizeof`/alignment is unknowable from source** under templates, virtuals, bases and the target
   ABI. All geometry is `--layout`'s LP64 standard-layout model, marked `model="lp64-approx"`; a
   definition `--layout` marks `modeled="0"` contributes its affinity graph and **no** geometry finding.

A third, named in the header as `block="64"`: 64 B is the L1 line, and on the Apple M5 Pro this document
was measured on, `hw.cachelinesize` reports **128**. The geometry half must be discounted accordingly on
any machine whose line is not 64 B.

## 5. The worked example — static hypothesis → hardware

`bench/bench_field_ab.cpp` is the validation harness. It builds the two layouts the lens compares,
alternates them to cancel thermal drift, and reads `prof::pmc` — ripwire's existing counter backend
(`src/infra/profilePmc.h`: kpep on macOS, `perf_event_open` on Linux). Both arms are 256 B, both put the
position and velocity quads on identically aligned 16-byte slots, and the **only** variable is the byte
distance between them: 192 in the flagged (`split`) arm, 16 in the `packed` arm.

```
c++ -O2 -std=c++23 bench/bench_field_ab.cpp -Isrc -Isrc/infra -Ithird_party -o /tmp/ripwire_field_ab
/tmp/ripwire_field_ab 9          # timing only
sudo /tmp/ripwire_field_ab 9     # + hardware counters
```

### 5.1 Counters: UNAVAILABLE in this run, and said so

`prof::pmc::active()` is **false** without root on macOS (kperf needs root or the
`com.apple.private.kperf` entitlement) — verified directly: a probe against `profilePmc.h` reports
`active=0 events=6` and all-zero deltas unprivileged. The harness prints
`counters=UNAVAILABLE` and `l1d-cache-misses UNAVAILABLE (the mechanism claim is unverified in this
run)`, then reports the timing anyway. **The mechanism claim — that the split arm's extra line is what
costs — is therefore UNCONFIRMED here, not confirmed-by-omission.** Re-run under `sudo` to close it.

### 5.2 Timing: measured, five repeats per stride

Apple M5 Pro, 256 Ki elements × 256 B = 64 MB per arm, 7 alternating samples per run, median of each
arm, five repeats. `ratio` = split ÷ packed, so **> 1.00 means the flagged layout is slower** (hypothesis
confirmed). **The machine was under concurrent load from sibling agent worktrees**, which is why the
spread is reported rather than a single number.

| stride (elements) | ratio, five repeats | reading |
| --- | --- | --- |
| 1 (fully sequential) | 0.49 0.55 0.43 0.46 0.46 | **REFUTED** — the flagged layout is ~2× *faster* |
| 9 | 1.28 1.11 1.08 1.20 1.24 | confirmed, 8–28 % slower |
| 129 | 1.13 1.16 1.03 1.21 0.91 | weak / mixed |
| 1025 | 1.27 1.04 1.41 1.21 1.18 | confirmed, 4–41 % slower |
| 4097 | 1.40 1.18 1.07 1.08 1.27 | confirmed, 7–40 % slower |

### 5.3 What that actually establishes

**The hypothesis holds in four of five access regimes and inverts in the fifth.** Under a fully
sequential sweep the packed arm moves *less* data — one 64 B line per 256 B element instead of two — and
is still **twice as slow**. Fewer bytes, more time. The plausible mechanism is prefetcher density: a
single 64 B touch inside every 256 B element is a sparser stream than two, and the hardware prefetcher
reacts to density. That mechanism is a hypothesis in its own right and is **unconfirmed** while the
counters are unavailable.

Three conclusions, all load-bearing:

1. **A split-line finding is a hypothesis, not a defect.** It survived measurement in four regimes and
   was refuted in one. That is exactly the shape the file header claims and the reason the verb has no
   rewrite mode and no non-zero exit code.
2. **The Go team's caution has a second, independent cause.** Tight packing can hurt *without* any false
   sharing — by making the access stream sparser. This is a measured instance, not a citation.
3. **One stride is not an answer.** The harness prints that sentence on every run, precisely so a single
   flattering number cannot be quoted as validation. Reporting the regime where the hypothesis *fails*
   alongside the four where it holds is the whole point of building the harness.

## 6. The static→PMC bridge, on ripwire's own source

`perf c2c` resolves a miss to a cache line **and an offset within it** but deliberately never names a
struct field — you are expected to map offset→field yourself with pahole and DWARF. The lens closes the
other half of that path from source: **field → offset → the functions that co-access it → the
`PROFILE_SCOPE` those functions sit inside**, computed by locating each co-accessing function's enclosing
`PROFILE_SCOPE_DESCRIBE`, never hand-written.

Run against ripwire itself:

```
./build/ripwire src --field-affinity
```

- 500 aggregates modelled across 78 C-family files, 2274 function bodies scanned, 5091 attributed
  member accesses, **9326 refused as ambiguous** (a field name owned by two aggregates), 324 structs
  with at least one attributed access, 17 findings in the ranked head.
- Top-ranked: `MainDispatch` (`src/main.cpp`, 144 B, three cache lines, `sepcost=92.75`, 12 findings) —
  `multiRoot` at offset 32 and `notesPtr` at 136 are 104 B apart and co-accessed by two handlers.
  `<validate scopes="2" status="instrumented">` names `emit: serialize ranked map` and
  `main: co-change prior boost (mine + apply)` — real, existing `PROFILE_SCOPE`s to measure against.
- **The honest reading of that #1:** `MainDispatch` is constructed once per process and read a handful
  of times. Its static separation cost is real and its dynamic cost is almost certainly nil. That is
  limit (1) — static counts are not dynamic frequency — visible in the lens's own top result, and it is
  why `w=` (fan-in weighted) and the `<validate>` bridge exist at all: the static rank *nominates*, the
  counters *decide*.
- ripwire's own genuine hot path (PageRank, `buildGraph`, ingest) produces **no** findings, because it is
  already SoA — 32-bit handles and parallel arrays, per guardrail G2. A locality lens finding nothing in
  the code written to be cache-local is the expected result, and a small independent check that the lens
  is not firing at random.

## 7. Reproducing everything in this document

```bash
cmake -S . -B build && cmake --build build -j
bash test/fieldaffinitycheck.sh                       # the gate: hand-computed offsets, both findings,
                                                      #   the negative case, the ambiguity refusal
./build/ripwire test/fieldaffinityfix --field-affinity # the fixture, whose offsets are written out in hot.h
./build/ripwire src --field-affinity                  # §6
c++ -O2 -std=c++23 bench/bench_field_ab.cpp -Isrc -Isrc/infra -Ithird_party -o /tmp/ripwire_field_ab
for s in 1 9 129 1025 4097; do /tmp/ripwire_field_ab $s; done   # §5.2
sudo /tmp/ripwire_field_ab 9                          # §5.1 — the counter columns this run could not get
```
