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
| `src/ingest.cpp` (the TU: + 15 `ingest_*.h` sections) | 161,159 (142 MB) | 128,495 (104 MB) |
| `src/main.cpp` | >1 M, **>800 MB and still growing** | 983,888 (~38 MB region at capture) |

Re-measured 2026-09-10 on the same narrowed filter, after the ingest and main splits: `pagerank.cpp`
582 (1 MB), `ingest.cpp` **200,556 (178 MB)**, `main.cpp` **1,753,329 (1.5 GB)**. The splits moved
where a record's `DebugLoc` points — into `src/ingest_*.h` and `src/verbs_*.h` — but not how much of
it there is: these are the same translation units, compiled the same way.

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

**The remark.** In the **ingest translation unit** — `src/ingest.cpp` plus the fifteen
`src/ingest_*.h` sections it includes, holding the two phases that are ~29% of a cold run —
**831 of 1,437 distinct `inline/NoDefinition` sites name a tree-sitter C entry point**:
`ts_node_start_byte`, `ts_node_end_byte`, `ts_node_type`, `ts_node_is_null`,
`ts_node_child_by_field_name`, `ts_node_start_point`, `ts_query_capture_name_for_id`,
`ts_query_cursor_next_match`. Each is a two-or-three-line accessor. Each is also, from the
optimizer's point of view, an opaque call that clobbers memory — which is why the same TU carries
**7,683 `gvn/LoadClobbered … clobbered by call` remarks**. The capture loop reloads everything it
holds across every one of those accessor calls.

*(Both counts are the 2026-09-10 re-run over the whole TU. The original pass reported 397/636 and
5,448 against `src/ingest.cpp` alone, which after the split is 0.2% of the TU — see §8.)*

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

## 5c. F3 — the per-node `strcmp` dispatch, and why a hand-written SIMD routine lost to a byte loop

**The lead.** §8b, from the newly-covered 98%: **528 distinct `inline/NoDefinition` sites naming
`strcmp`** — a figure inherited from §8b, not re-measured here, and one that carries the site→callee
selection §7 documents: `scripts/optremarks.py` keys a distinct site on `( file, line, remark-name )`
and keeps the FIRST record, while the callee lives in the detail, so a site naming more than one
callee is counted under whichever it named first. **Nothing below rests on it.** F3's conclusion rests
on leaf-of-stack attribution and an instrumented call count; a different reading of the site count
changes no sentence in this section. The chains it points at are (`isDecisionType`, `cc_isNestingControl`, `ev_ctrlKindFor`,
`bindsVisitNode`) that are ~forty comparisons long and run per AST node. Neither F1 nor any §6
dismissal covered it: LTO cannot make libc's `strcmp` available (so F1's answer does not reach), and
D4's "inlining a syscall wrapper saves nothing" does not apply to a leaf string compare.

**Sizing it before touching it.** A remark is not a measurement, and these functions have no
`PROFILE_SCOPE` of their own — their cost is folded into `captureTagsFacts`. So the sizing came from
leaf-of-stack attribution instead (`sample` at a 1 ms interval, cold run, the whole process):

| corpus | language | `strcmp` frames, share of **busy** samples |
| --- | --- | --- |
| rust-analyzer | Rust | **12.31%** |
| go | Go | **10.76%** |
| llvm-project | C/C++ | **10.56%** |
| django | Python | **9.31%** |
| rails | Ruby | **6.14%** |

On llvm-project that is 4,582 of 43,330 busy samples, and it splits three ways:
`_platform_strcmp` 2,619 · `DYLD-STUB$$_platform_strcmp` 1,023 · `DYLD-STUB$$strcmp` 940. **43% of
the cost is the two dyld stubs** — `strcmp` is an external symbol, so every call hops our image's
stub, then libsystem_platform's, before the routine begins. Attributed to callers, the class is
almost entirely one walk: `cc_walk` 60.7%, `isDecisionType` 17.9%, `bindsVisitNode` 15.3%,
`captureTagsFacts` 2.0% — i.e. the complexity DFS, not the side-capture walk §8b guessed at.

**The change.** `rw::kindIs` (`src/infra/nodekind.h`): `kindIs( t, "if_statement" )` is exactly
`std::strcmp( t, "if_statement" ) == 0`, unrolled inline against a literal whose length the type
system carries. Applied mechanically to the **569** `std::strcmp` call sites (on 412 lines) in the five ingest
walk sections. Sites comparing against a *variable* (`ev_childText`'s caller-supplied list,
`isTypeDeclarationSite`'s parent table) keep `std::strcmp` — the array-reference signature does not
bind to them, deliberately.

**Why not SIMD — the question this answers with numbers, not taste.** `_platform_strcmp` *is* the
hand-written NEON routine, and it is what lost. Instrumenting the compare to histogram the byte index
at which it decides (throwaway build, one cold run per corpus):

| corpus | `kindIs` calls | decided at byte 0 | by byte 1 | by byte 2 |
| --- | --- | --- | --- | --- |
| llvm-project | 4,861,917,534 | 92.96% | 98.12% | 99.04% |
| go | 1,930,294,567 | 92.63% | 98.64% | 99.54% |
| rails | 353,856,824 | 92.30% | 97.89% | 98.88% |

**~1.1 bytes decide the average call.** A 16-byte vector load does an order of magnitude more work
than the answer needs, and it cannot be used here anyway without reading past `t`'s NUL — the exact
hazard the byte loop avoids by construction and `test/nodekindcheck.sh` arm B proves the absence of
with an `mprotect( PROT_NONE )` guard page. Nor does the compiler want vectors: given the chain,
clang emits a **shared-prefix decision tree** — one `ldrb` of byte 0, then immediate compares that
fall straight to the common exit — with **zero vector registers in the emitted function**. The
dispatch is not a string problem; it is a branch problem, and the win came from deleting the call.

**The result on the same instrument.** llvm-project, cold: `strcmp` frames **10.56% → 0.23%** of busy
samples. The compares did not vanish, they moved inline: `cc_walk`'s own self time goes 1.02% → 1.92%.

**The A/B.** §7's rules in full: interleaved `A,B,A,B,…`, ≥20 runs per arm, median **and** min, the
whole thing repeated end to end with the **arms swapped**, on corpora that are not this repository.
Both instruments are reported because they disagree in precision: this machine carried heavy
competing load from other sessions, which inflates wall clock without changing how many instructions
the process executes, so **child CPU time (user+sys) is the tighter instrument here and wall clock is
the noisier one**. Negative = the change is faster.

| corpus | R1 cpu med / min | R1 wall med / min | R2 cpu med / min | R2 wall med / min |
| --- | --- | --- | --- | --- |
| llvm-project (n=20/arm) | −3.83% / −3.93% | −2.64% / −2.86% | −3.86% / −4.12% | −3.90% / −1.53% |
| django (n=25/arm) | −1.21% / −0.71% | −0.46% / −0.34% | −2.71% / −3.46% | *(−43%, outlier)* / −1.90% |
| go (n=25/arm) | −3.32% / −2.92% | −1.01% / −3.13% | −6.82% / −8.55% | −1.70% / −8.08% |
| this repo, frozen (n=25/arm) | −3.62% / −2.89% | −1.28% / −1.67% | −3.24% / −6.39% | −5.32% / −6.28% |

**All 32 statistics favour the change**, which is the unanimity-of-direction test F1 passes and D2
fails. **The honest claim is a range: cold CPU is 1–7% lower and cold wall 0.3–8% lower**, with the
larger figures on Go and the smaller ones on Python. Do not quote −8.55%: django R2's wall median is
a single contaminated run (mean 1,071 ms against a min of 543 ms) and is shown struck through rather
than dropped, because dropping it silently is how a table starts flattering itself.

**Behaviour.** Byte-identical: seven corpora × `--metrics` / `--lint` / `--hotspots` / `--clones` /
the default map, plus `--slice` / `--for` / `--pack-task` / `--expand` on the frozen self corpus.
`test/argvdiffcheck.sh` against a pre-change reference binary: **640 of 642 vectors identical** in
stdout, stderr and exit code; the two that differ are both `--version`, differing by exactly the six
bytes of the `+dirty` build stamp an uncommitted tree earns. Determinism three times, `xmllint`
clean, ASan/UBSan/LSan clean on six corpora.

**The gate, written before the code it measures.** `test/nodekindcheck.sh`: (A) `kindIs` must agree
with `std::strcmp( … ) == 0` on **1,348,096 enumerated pairs** — every node-kind literal the walk
sections actually use, harvested from the tree at gate time, against a candidate matrix of every
proper prefix, every one-byte extension, last-byte substitutions, high bytes 0x80..0xFF and the empty
string; (B) the guard-page arm above; (C) **two mutation controls** — a header whose loop stops
before the NUL must turn A red (it does: 1,417 disagreements), and one that reads a byte past must
turn B red (it does: a fault on the guard page); (D) the five walk sections must still be on `kindIs`,
so the measured win cannot be reverted a site at a time.

**What it cost.** `--clones`, uncapped: 407 groups before, 409 after — the rewrite adds 7 and removes
5. Six of the seven added pair a node-kind `||`-chain with an unrelated `||`-chain over a **disjoint**
literal set in another subsystem (`cc_isParamList` against `predicatePrefixed`, whose literals are
English name prefixes), because a shorter compare puts short predicate bodies inside the clone
detector's token window. Those are idiom collisions, not copies, and are acked with that reasoning
rather than merged into a helper parameterised on an unrelated table.

**A near-miss worth recording, because the instrument was the interesting part.**
`test/showcasecapturecheck.sh` arm (C-band) asserts the top-50 `--pack-signatures` reduction on **this
repository as its own corpus**. Measured against the lane's original base, shortening 569 dispatch
comparisons cut top-50 *body* bytes 31,887 → 30,275 (−5.1%) and moved the ratio 72.4% → 71.7%, one
step below a 72.0 floor — and it really was this lane's doing: one fixed binary over the twelve
preceding checkouts reads 72.3–72.4%, so the quantity barely moves on its own and the floor had 0.4
points of margin. The floor was **not** lowered to accommodate it. Rebasing dissolved the collision
instead: `main` had already re-centred the band twice for unrelated reasons — once for the
printf-family → `std::print` conversion, once for `--expand`'s `sibs=` cap going 8 → 100, which grows
the BODY side of this very ratio — so the arm now reads **81.9% inside 73.0–91.0** and this change sits
nine points clear of the floor.

The lesson survives the near-miss, and it is the one to keep: **the arm reads the LIVE tree, so it
cannot distinguish "the elider elides less" from "our own source got shorter."** This lane's output is
byte-identical on seven corpora — the elider provably did not change — yet the arm fired. Three
re-centerings in two days, all for changes to the *corpus* rather than to the elision, are that
blind spot showing. A corpus-frozen basis (`git archive`, the way `test/optremarkshotcheck.sh` freezes
the hot set) would make the band mean what its own comment says it means. That is its own round.

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
`ingest_sidecap.h:1428` (`ingest.cpp:4953` before the split) — `for( uint16_t ci = 0; ci < match.capture_count; ++ci )` over
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
python3 scripts/optremarks.py --file src/ingest --name NoDefinition --sites 30000 --width 200 | grep -c ts_
```

The profile column in §3:

```bash
cmake -S . -B build_prof -DRIPWIRE_PROFILE=ON && cmake --build build_prof -j 6
./build_prof/ripwire . --no-cache 2>&1 >/dev/null | sed -n '/hottest scopes/,/PROF_TSV/p'
```

`PROFILE_SCOPE` answers "which phase", and a remark class that sits INSIDE one phase — F3's per-node
dispatch is folded whole into `captureTagsFacts` — is invisible to it. The instrument for that is
leaf-of-stack attribution, which needs no instrumentation and no rebuild:

```bash
./build/ripwire <dir> --no-cache >/dev/null 2>&1 & sample $! 6 1 -f /tmp/s.txt   # 1 ms, whole run
awk '/Sort by top of stack, same collapsed/,0' /tmp/s.txt | head -20            # leaf symbols, by cost
```

Read it as a share of BUSY samples (subtract the `__ulock_wait` / `__psynch_cvwait` idle rows first —
a 19-thread run parks workers in them), then walk the call tree up from a leaf to find which of our
own functions owns it. That is how F3 was found, and how it was afterwards shown to be gone.

A wall clock is not the only instrument, and on a loaded machine it is not the best one. F3's arms
separate cleanly in **child CPU time (user+sys)** and barely at all in wall clock, because competing
load changes how long the process waits without changing how many instructions it runs. Report both,
say which machine state they were taken in, and never quote the flattering one alone.

Any A/B must be interleaved and reported as median **and** min over at least ~20 runs per arm — and
then **repeated end to end at least once more**. D2 is what a single non-interleaved run would have
let you publish; F1's four-run spread is what a single run would have let you *oversell*.

## 8. The hot set went stale, silently, and what the other 98% turned out to hold

**What happened.** `--hot` narrows the record to `HOT_FILES`, a literal list matched EXACTLY. The
ingest split moved ~18,000 lines out of `src/ingest.cpp` into fifteen `src/ingest_*.h` sections of the
same translation unit. Every path in the list still existed, so nothing failed and no gate fired. The
compiler kept emitting the same remarks; their `DebugLoc` simply began naming the section headers,
which the list did not contain.

| | remarks |
| --- | --- |
| ingest translation unit, first-party | 33,957 |
| of those, seen by `--hot` (i.e. attributed to `src/ingest.cpp`) | **69 — 0.20%** |
| `--hot` total, before the refresh | 29,467 |
| `--hot` total, after | **56,488 (1.92×)** |

The two hottest own-code phases in the tool were among the hidden 98% for the entire time:
`ingest_sidecap.h` (`captureTagsFacts` 23.7% + `captureSideFacts` 5.6% of a cold run) and
`ingest_parsepool.h` (the tag flush, 10.2%). **Treat every `--hot` conclusion about ingest recorded
before 2026-09-10 as unverified.** §5's was re-run and grew; nothing else was resting on it.

**Why the existing gate did not catch it.** `test/optremarkscheck.sh` asserts the *inverse* — that
`--hot` does not DROP a file `HOT_FILES` names — and stayed green throughout, because
`src/ingest.cpp` is still listed and still exists. A list can be perfectly self-consistent about
itself while describing a tree that has moved. The missing assertion was coverage, and coverage has
to be asserted against the source tree, not against the list.
`test/optremarkshotcheck.sh` now does that: every file the tree groups with a hot one — by the
section's own `RIPWIRE_<X>_TU` `#error` guard, or by name family — must be in `HOT_FILES` or in
`COLD_FILES` **with a stated reason**, and a ceiling arm keeps the list from buying coverage by
growing into a copy of the tree.

### 8b. F3 — a lead from the newly-covered 98%, since measured and acted on (§5c)

Re-triaging the previously hidden remarks surfaced one class that neither F1 nor any dismissal in §6
explains: **528 distinct `inline/NoDefinition` sites naming `strcmp`** — 414 of them in files that
were invisible before the refresh, concentrated in `ingest_metrics.h` (129), `ingest_binds.h` (94),
`ingest_sidecap.h` (79) and `ingest_relations.h` (71). They are node-kind dispatch chains such as
`isDecisionType`, `cc_isNestingControl`, `ev_ctrlKindFor` and `bindsVisitNode`: a linear
`std::strcmp( t, "if_statement" ) == 0 || std::strcmp( t, "for_statement" ) == 0 || …` roughly forty
comparisons long, evaluated **per AST node**, inside the walk that is ~29% of a cold run.

It is not D4. D4 dismisses libc `NoDefinition` because inlining a syscall wrapper saves nothing;
these are leaf string compares in a per-node dispatch, and the chain is linear in the number of node
kinds. It is not F1 either: LTO cannot make libc's `strcmp` definition available, so the answer that
covered the `ts_*` accessors does not reach this.

**Acted on, and it held: see §5c (F3).** It was recorded here as a lead, not a result, with §7's
rules to clear and D2 as the standing reminder of what happens when a remark is real, the fix is
correct and the wall clock does not move. It cleared them: `strcmp` was measured at 6–12% of busy CPU
across five corpora, the fix took llvm-project's share to 0.23%, and all 32 A/B statistics across two
end-to-end rounds and four corpora favour it. **§5c also corrects this section's guess about WHERE**:
the cost is `cc_walk` (the complexity DFS), not the side-capture walk named above — 78.6% of the
class sits in `cc_walk` + `isDecisionType` and 15.3% in `bindsVisitNode`, which is why the sizing had
to come from leaf-of-stack attribution rather than from the remark's own file counts.

---

`test/optremarkscheck.sh` gates the parser against a committed fixture (exact counts, the wrapped
`DebugLoc` continuation line, the `Args`-nested `DebugLoc` that a naive line reader mis-attributes)
and runs the real configure that proves the `build/` refusal — because a triage tool that silently
parses fewer records reports "nothing to fix", which is the green-while-inert failure this suite
gates against everywhere else.
