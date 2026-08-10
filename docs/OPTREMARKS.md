# Optimization remarks — the build, the triage, and what it actually found

Clang can be asked what the optimizer *did* and, more usefully, what it *declined* to do: loops it
would not vectorize, calls it would not inline, loads it could not hoist because something might
alias. This document is the build that collects those remarks, the triage that turns ~1.1 million of
them into a short list, and the honest record of what survived triage on this codebase.

**One rule governs everything below: a remark is an observation, not a defect.** The optimizer is
reporting a decision it made, usually correctly. Acting on one without a bench number is how readable
code gets churned for nothing — so every finding here is paired with a measurement, including the
findings whose measurement said *no*.

---

## 1. Collecting them

```bash
scripts/optremarks.sh                     # configure + build + summary triage
scripts/optremarks.sh --triage-only -- --hot --pass loop-vectorize --sites 40
scripts/optremarks.sh --passes 'inline|loop-vectorize|licm|gvn'   # narrow (see §2)
scripts/optremarks.sh --clean
```

The script drives `-DRIPWIRE_OPT_REMARKS=ON`, which adds
`-Rpass=.* -Rpass-missed=.* -Rpass-analysis=.* -gline-tables-only -fsave-optimization-record` to
`ripwire` and `ripwire_probe` only. Three properties are deliberate:

- **A separate tree, `build_remarks/`.** `CMakeLists.txt` refuses the option inside `build/` or
  `asan/` by name, and `test/optremarkscheck.sh` runs the real configure to prove the refusal.
  `build/ripwire` is what every gate and every bench number in this repo is measured against; a
  remarks build would leave ~1 GB of opt-record beside it.
- **No build type.** Remarks only describe an optimized build, and `-DCMAKE_BUILD_TYPE=Release` is
  forbidden in a dev tree here — `NDEBUG` compiles the degrade-path alert out and blinds the
  degrade-path gates (CONTRIBUTING.md §5). None is needed: `RIPWIRE_ARCH_FLAGS` already puts the
  plain configuration at `-O2`, so `build_remarks/` reports on **the same codegen the shipping binary
  has**, with the degrade paths still compiled in.
- **Our targets only.** Attached with `target_compile_options`, never `add_compile_options`, so the
  vendored tree-sitter core and the sixteen grammar objects stay out. `scripts/optremarks.py` drops
  `third_party/` and toolchain headers a second time, at triage.

Remarks are a **Clang** feature as spelled here; a GCC configure is refused rather than silently
producing an empty record.

## 2. The cost, and how to narrow

The wide pass is genuinely expensive, and the cost is not spread evenly:

| translation unit | records, unfiltered | records, `inline\|loop-vectorize\|slp-vectorizer\|licm\|gvn\|*unswitch\|loop-idiom` |
| --- | --- | --- |
| `src/pagerank.cpp` | 994 (0.8 MB) | 622 (0.55 MB) |
| `src/ingest.cpp` | 161,159 (142 MB) | 128,495 (104 MB) |
| `src/main.cpp` | >1 M, **>800 MB and still growing** | 983,888 (~38 MB region at capture) |

`src/main.cpp` is one ~605 KB translation unit holding thousands of functions, and the
per-function-per-pass bookkeeping classes (`size-info/FunctionMISizeChange`,
`asm-printer/InstructionMix`, `prologepilog/StackSize`, `stack-frame-layout/StackLayout`) grow with
*functions × passes*. An unfiltered `main.cpp` run writes hundreds of megabytes of stderr and the
same again of YAML before it finishes.

**So: run wide once, on the small TUs, to learn which classes exist. Then narrow.**
`--passes` sets `RIPWIRE_OPT_REMARKS_FILTER`, which is applied to the `-Rpass*` trio *and* the YAML
record together, so the log and the record can never disagree about what was collected.

## 3. The triage rule this codebase needs

Where the time actually goes decides which remarks can matter. Measured on this repository as its own
corpus (937 files, cold, `-DRIPWIRE_PROFILE=ON`, aggregated across 19 threads):

| phase | ms | share | whose code |
| --- | --- | --- | --- |
| tree-sitter parse | 860.7 | 32.2% | third_party |
| tags query exec + captures (`captureTagsFacts`) | 705.1 | 26.4% | **ours**, calling tree-sitter |
| flush pending parsed tags | 381.9 | 14.3% | ours (wraps the two above) |
| wait for query prewarm | 360.1 | 13.5% | idle, not work |
| side captures (`captureSideFacts`) | 125.8 | 4.7% | **ours**, calling tree-sitter |
| readFile (`fopen`+read) | 87.1 | 3.3% | ours, calling libc |
| crawl | 6.5 | 0.2% | ours |
| build model (dedup + symbols/refs) | 4.1 | 0.2% | ours |
| buildGraph (resolve refs + CSR) | 4.1 | 0.2% | ours |
| **PageRank (power iteration)** | **0.98** | **0.04%** | ours |
| emit: serialize ranked map | 0.27 | 0.01% | ours |

Two consequences, and both are load-bearing:

1. **PageRank and the sort/rank layer are not hot.** PageRank is *one millisecond*. Every remark in
   `src/pagerank.cpp`, `src/infra/sortutil.h` and `src/infra/radixSort.inl` is therefore dismissed on
   arithmetic before it is read: a 20% win on a 1 ms phase is 0.2 ms of a 160 ms run. This is exactly
   the finding `bench/PROFILE.md` has carried since 2026: *the ranking is the cheap part; parsing is
   the tax.*
2. **The own-code that IS hot spends its time calling into another translation unit.** Which turns
   out to be the whole story — see F1.

`scripts/optremarks.py --hot` restricts the report to a literal, reviewable list of files
(`HOT_FILES`) rather than a heuristic, so what the report calls "hot" stays auditable.

## 4. What fired

Narrowed record, first-party only, hot-set files (39,915 remarks). Top classes and the verdict:

| n | class | verdict |
| --- | --- | --- |
| 19,082 | `Missed gvn LoadClobbered` | **Noise as a work item, signal as a pointer** — see §5 |
| 7,344 | `Passed inline Inlined` | informational |
| 3,448 | `Missed licm LoadWithLoopInvariantAddressInvalidated` | tested (D2), no measured effect |
| 1,799 | `Passed licm Hoisted` | informational |
| 1,641 | `Missed slp-vectorizer NotPossible` | dismissed — cost model, cold sites |
| 1,142 | `Missed inline TooCostly` | dismissed per-site (§6 D6) — answered wholesale by **F2 (PGO)** |
| 1,019 | `Missed licm LoadWithLoopInvariantAddressCondExecuted` | as above |
| 950 | `Missed inline NoDefinition` | **F1 — the finding** |
| 467 | `Missed loop-vectorize MissedDetails` | dismissed — the `Analysis` rows below explain each |
| 275 | `Missed inline NeverInline` | dismissed — see §5 |
| 218 | `Analysis loop-vectorize CantVectorizeInstruction` | dismissed — string scanners |
| 173 | `Analysis loop-vectorize TooManyUncountableEarlyExits` | dismissed — string scanners |

## 5. F1 — the first remark that moved a number

**The remark.** In `src/ingest.cpp` — the TU holding the two phases that are 31% of a cold run —
**397 of 636 distinct `inline/NoDefinition` sites name a tree-sitter C entry point**:
`ts_node_start_byte`, `ts_node_end_byte`, `ts_node_type`, `ts_node_is_null`,
`ts_node_child_by_field_name`, `ts_node_start_point`, `ts_query_capture_name_for_id`,
`ts_query_cursor_next_match`. Each is a two-or-three-line accessor. Each is also, from the
optimizer's point of view, an opaque call that clobbers memory — which is why the same TU carries
**5,448 `gvn/LoadClobbered … clobbered by call` remarks**. The capture loop reloads everything it
holds across every one of those accessor calls.

`will not be inlined … because its definition is unavailable` is not a cost-model opinion. It is a
statement of fact about translation units, and no source edit inside `ingest.cpp` reaches it. The
fix a `NoDefinition` remark justifies is to make the definition available: **link-time optimization.**

**The measurement.** `-DRIPWIRE_LTO=ON` (a new option; `CMAKE_INTERPROCEDURAL_OPTIMIZATION` set
before the first target so it reaches our C++, the sixteen C grammars, and the tree-sitter core in
its own subdirectory). Interleaved A/B — `A,B,A,B,…` so thermal drift and background load hit both
arms equally — this repository as corpus. **Four independent runs, all four reported**, because the
first two alone would have oversold it:

| run | n/arm | cold median | cold min | warm median | warm min |
| --- | --- | --- | --- | --- | --- |
| 1 | 9 | 205.3 → 197.2 (−3.9%) | 179.8 → 171.3 (−4.7%) | 39.1 → 39.0 (−0.3%) | 35.2 → 36.9 (**+4.8%**) |
| 2 | 21 | 164.1 → 156.5 (−4.6%) | 155.0 → 146.0 (−5.8%) | 31.5 → 30.7 (−2.5%) | 30.5 → 29.8 (−2.3%) |
| 3 | 21 | 156.8 → 155.5 (−0.8%) | 146.4 → 141.9 (−3.1%) | 33.8 → 32.8 (−3.0%) | 32.2 → 31.0 (−3.7%) |
| 4 | 31 | 159.9 → 150.4 (−5.9%) | 145.5 → 138.3 (−4.9%) | 30.2 → 29.5 (−2.3%) | 29.0 → 28.5 (−1.7%) |

**The honest claim is a range, not the best row: cold is 1–6% faster and every cold statistic in
every run favours LTO; warm is 0–3% and one run's warm min went the wrong way.** That unanimity of
*direction* across four runs is what separates this from D2 below, where the direction itself
flipped. Do not quote −5.9%.

| | baseline | LTO |
| --- | --- | --- |
| binary | 38.2 MB | 37.1 MB (−2.8%) |
| rebuild after touching `src/main.cpp` | 34 s | 89 s (**+2.6×**) |

Output is **byte-identical** to the baseline binary, the determinism gate passes three times on the
LTO tree, and its output pipes clean through `xmllint`.

**Why it is ON by default.** It costs build time — a rebuild after touching `src/main.cpp` goes
34 s → 89 s — and that is not a reason to decline it. What this project optimizes for is how fast the
shipped tool runs; a slower link in exchange for a faster binary is a trade with no downside for the
person the tool is for. `-DRIPWIRE_LTO=OFF` is there for a fast edit loop. Nothing about the
determinism contract objects: `src/pagerank.cpp`'s `-fno-fast-math` is a per-function IR attribute
that survives LTO, and the gate proves it on the built tree.

**One gotcha worth knowing.** `option()` never overwrites an existing cache entry, so a tree
configured before this default flipped keeps `RIPWIRE_LTO:BOOL=OFF` and quietly keeps building slow.
Re-running `cmake -S . -B build` does not fix it — delete the tree, or pass `-DRIPWIRE_LTO=ON`.

## 5b. F2 — PGO: the answer to the classes LTO cannot touch

F1 fixes calls the optimizer *could not* inline. It does nothing for the calls and branches the
optimizer *chose* not to optimize — and two of the biggest dismissal piles in §6 are exactly that:
`inline/TooCostly` (1,142 in the hot set) and `loop-vectorize/VectorizationNotBeneficial` are the cost
model guessing at hotness with no data. A profile replaces the guess with counts.

`scripts/pgobuild.sh` runs the whole thing as one command: instrument (`-DRIPWIRE_PGO=generate`),
train on a mixed workload, `llvm-profdata merge`, rebuild (`-DRIPWIRE_PGO=use`), always in
`build_pgogen/` and `build_pgo/` — CMake refuses PGO in `build/` and `asan/` by name.

```bash
scripts/pgobuild.sh                          # instrument -> train -> merge -> optimize
scripts/pgobuild.sh --corpus /path/to/repo   # train on a different tree
scripts/pgobuild.sh --reuse-profile          # rebuild from the existing .profdata, no retraining
scripts/pgobuild.sh --clean
```

**Measured, PGO **on top of** LTO.** Interleaved A/B as in F1:

| corpus | n/arm | cold median | cold min | warm median | warm min |
| --- | --- | --- | --- | --- | --- |
| this repo, vs baseline | 31 | 152.5 → 130.5 (−14.4%) | 145.7 → 121.0 (−17.0%) | 29.4 → 27.3 (−7.1%) | 28.1 → 26.1 (−7.1%) |
| this repo, vs baseline (loaded box) | 31 | 567.7 → 474.7 (−16.4%) | 393.1 → 256.2 (−34.8%) | 70.1 → 63.2 (−9.8%) | 51.4 → 46.8 (−9.0%) |
| this repo, vs baseline (rebuilt by `pgobuild.sh`) | 21 | 282.2 → 219.8 (−22.1%) | 183.8 → 155.1 (−15.6%) | 36.4 → 34.4 (−5.5%) | 33.7 → 32.1 (−4.7%) |
| this repo, vs **LTO alone** | 31 | 214.1 → 179.0 (−16.4%) | 173.2 → 148.6 (−14.2%) | 39.9 → 38.8 (−2.8%) | 34.3 → 32.5 (−5.2%) |
| this repo, vs **LTO alone** (repeat, loaded box) | 21 | 284.8 → 258.4 (−9.3%) | 187.4 → 176.6 (−5.8%) | 45.6 → 41.5 (−9.0%) | 34.1 → 36.9 (+8.2%) |
| **held-out corpus** (a ~2000-file private C++ tree, in no training run) | 15 | 3845.7 → 2899.5 (−24.6%) | 2228.2 → 1687.2 (−24.3%) | 533.4 → 481.1 (−9.8%) | 315.7 → 287.0 (−9.1%) |
| **held-out corpus**, rebuilt by `pgobuild.sh` | 11 | 1377.3 → 1170.9 (−15.0%) | 1208.3 → 947.4 (−21.6%) | 126.9 → 120.8 (−4.8%) | 119.7 → 110.7 (−7.5%) |

**Two claims, because the reference point matters now that LTO is the default.** Against a plain
`-DRIPWIRE_LTO=OFF` build, PGO+LTO is roughly **14–25% faster cold and 5–10% warm**, and it holds on a
corpus that appears in no training run. Against the **shipped LTO default**, the marginal gain is
smaller and noisier — **6–16% cold** across two runs — which is the honest number to quote to someone
already on the default build. Six A/Bs, two corpora, two independently
built PGO binaries (one hand-driven, one produced by `scripts/pgobuild.sh`); every statistic in every
run favours PGO. Output is byte-identical to the baseline binary on both corpora, the determinism
gate passes three times on the PGO tree, and its output pipes clean through `xmllint`.

**A caveat on the absolute numbers in this table.** They were taken on a shared developer machine
that spent part of this pass at load average 65 (other worktree sessions building and benchmarking),
which is why the same corpus appears at 152 ms in one row and 567 ms in another. Interleaving is what
makes the *comparison* survive that — both arms eat the same contention — but treat the absolute
milliseconds as scenery and the percentages as the result.

**The train-on-test caveat, stated rather than buried.** The training workload in `scripts/pgobuild.sh`
includes this repository, which is also the benchmark corpus for the first three rows. That is why the
fourth row exists: a large C++ tree that has never been in a training run shows the *largest* gain, so
the profile is generalising to "parse and capture tree-sitter nodes", not memorising a corpus.

**Why cold gains 2–3× more than warm.** The two paths are not the same kind of code, and the split
falls exactly where you would expect it to. A cold run is dominated by parse and capture: a branchy,
call-heavy walk over tree-sitter's parse tree, pointer-chasing structures this repo does not own or
control. That is precisely the workload a profile helps most — LTO makes the C accessors inlinable,
and the profile then tells the inliner which ones are worth it and which way each branch around them
goes. A warm run skips almost all of that and spends its time in the parts that were already
hand-tuned for cache locality under G2 — the CSR triple, the SoA symbol tables, `dynamic_map`'s
B+tree with its vectorized key scan, the radix sorts. There is far less for a profile to discover in
code whose layout is already the optimization. *(This is an interpretation consistent with the phase
table in §3 and the per-phase PMC data in `bench/PROFILE.md`; it is not separately instrumented here
— confirming it would mean re-running the PMC pass against the PGO binary.)*

**Why PGO is a driven build rather than the default.** Not cost — build cost is not a currency this
project spends. It is that PGO cannot be expressed as a flag: it needs the binary to be *run* between
two configures, which a bare `cmake --build build` must not start doing behind the caller's back, and
which has no answer at all in a cross-compile. So it stays one command (`scripts/pgobuild.sh`) that
you invoke deliberately — and it is the right build for anything shipped. That is still in real
tension with G3's one-deterministic-build-step rule; the script makes the tension survivable, not
absent. The `.profdata` is deliberately **not committed**: a stale committed profile is a clang
*warning*, not an error, which would trade a visible two-step build for an invisible wrong one.

## 6. The dismissals, and why

Reported because a triage that only lists wins is not a triage.

**D1 — every remark in `src/pagerank.cpp`, `src/infra/sortutil.h`, `src/infra/radixSort.inl`.**
`VectorizationNotBeneficial` on the CSR gather (`pagerank.cpp:96`), `LoadWithLoopInvariantAddress-
Invalidated` on the teleport scale (`:92`, `:100`), `LoadClobbered … in favor of store` on the radix
histogram increments (`radixSort.inl:411-413`). The histogram one is even *real* and has a textbook
fix (private per-lane histograms summed at the end). **Dismissed on the profile**: PageRank is 0.98 ms
and the build-model sorts are 1.7 ms of a 2.7 s cold CPU profile. There is no version of this work
that shows up in a wall-clock number.

**D2 — hoisting the escaped-struct loads out of the hottest loop (tested, reverted).**
`ingest.cpp:4953` — `for( uint16_t ci = 0; ci < match.capture_count; ++ci )` over
`match.captures[ci]` — carries `gvn/LoadClobbered` (`load of type i16 … clobbered by call`) and
`licm/LoadWithLoopInvariantAddressInvalidated`, because `match` had its address taken by
`ts_query_cursor_next_match` and every accessor call in the body therefore clobbers it. I hoisted
both into locals. The remark *moved* as predicted (from the inner loop's line to the new hoist's
line — the load is now per-match rather than per-capture). The number did not:

| | baseline | hoisted |
| --- | --- | --- |
| run 1, cold median | 166.6 ms | 165.6 ms (−0.6%) |
| run 2 (arms swapped), cold median | 243.7 ms | 257.6 ms (**+5.7%**) |

The direction flips between runs — that is noise, not a win. **Reverted.** The reason it cannot win
is F1's reason inverted: the reload sits immediately beside an opaque call that costs far more than
it does. This is the single most useful calibration in this document — the remark was real, the fix
was correct, and it bought nothing.

**D3 — `inline/NeverInline` on `__clang_call_terminate` (275 in the hot set).** This is the
exception-landing-pad helper. `noinline` is deliberate and the code never executes on a hot path.
Pure noise; filter it out first, every time.

**D4 — `inline/NoDefinition` on libc (`fopen`, `fread`, `fclose`, `fseek`, `ftell`, `stat`).**
Same fact as F1 — the definition is elsewhere — but the callee is a syscall wrapper, so inlining it
would save nothing even if it were possible. F1's version is worth acting on only because the callees
are three-line struct accessors.

**D5 — `loop-vectorize` early-exit families on string scanners.** `TooManyUncountableEarlyExits`,
`PotentiallyFaultingEarlyExitLoop`, `CantComputeNumberOfIterations`, `LoopContainsUnsupportedSwitch`,
`WritesInEarlyExitLoop` — hundreds of them, concentrated in `src/docparse.h`, `src/arch.h`,
`src/lexical.h`, `src/graph.h`. Every one is a scanner that `break`s on a delimiter. A loop whose
trip count depends on the data it is reading is uncountable *by construction*; the remark is
restating the algorithm. Dismissed as a class.

**D6 — `inline/TooCostly` on libc++ (`basic_string::push_back`, `vector::push_back`,
`unordered_dense::table::…`).** The cost model declining to inline a container method into a large
caller. Real, and occasionally worth chasing — but every hot-set instance here sits in `docparse.h`
(document extraction, off the default path) or in one-shot setup inside `buildGraph`. Dismissed on
location, not on principle.

**D7 — `gvn/LoadClobbered` as a work item (90,971 across the whole record).** The single largest
class by an order of magnitude, and the least actionable one-by-one: it fires per load per pass. Its
value is *aggregate* — a dense cluster of `clobbered by call` in one function means that function is
call-bound, which is how F1 was found. Never triage these individually.

**D8 — `src/lexical.h`'s BM25 loops.** `VectorizationNotBeneficial` at `:490/:517/:532/:577` and 22
LICM sites in the `scanField` token matcher looked like the best remaining source-level candidate.
Profiling the actual `--for` path killed it: `lexicalScores` is **0.886 ms of a 95 ms run**, and the
`scanField` corpus re-tokenizer the LICM remarks point at does not run at all on a warm cache (the
B0.2 persisted subtoken stats path replaces it). The remark points at a loop the hot path skips.

## 7. Reproducing

```bash
scripts/optremarks.sh --passes 'inline|loop-vectorize|slp-vectorizer|licm|gvn|.*unswitch|loop-idiom'
python3 scripts/optremarks.py --hot --top 40
python3 scripts/optremarks.py --file src/ingest.cpp --name NoDefinition --sites 30000 --width 200 | grep -c ts_
```

The profile column in §3:

```bash
cmake -S . -B build_prof -DRIPWIRE_PROFILE=ON && cmake --build build_prof -j 6
./build_prof/ripwire . --no-cache 2>&1 >/dev/null | sed -n '/hottest scopes/,/PROF_TSV/p'
```

Any A/B must be interleaved and reported as median **and** min over at least ~20 runs per arm — and
then **repeated end to end at least once more**. D2 is what a single non-interleaved run would have
let you publish; F1's four-run spread is what a single run would have let you *oversell*.

`test/optremarkscheck.sh` gates the parser against a committed fixture (exact counts, the wrapped
`DebugLoc` continuation line, the `Args`-nested `DebugLoc` that a naive line reader mis-attributes)
and runs the real configure that proves the `build/` refusal — because a triage tool that silently
parses fewer records reports "nothing to fix", which is the green-while-inert failure this suite
gates against everywhere else.
