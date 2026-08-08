---
name: ripwire-opt-remarks
description: >
  Triage clang optimization remarks (-Rpass / -Rpass-missed / -fsave-optimization-record) while editing
  ripwire's own C++. Use when a compiler remark says loop not vectorized, will not be inlined, load
  clobbered, or LICM failed to hoist — and you must decide whether that remark is worth a diff. Covers
  -DRIPWIRE_OPT_REMARKS=ON, the opt-record YAML triage, which remark classes are signal versus restated
  algorithm, the build-level answers (RIPWIRE_LTO, RIPWIRE_PGO), and the A/B a remark-driven fix must
  survive. Contributor-facing: it is about compiling this tool, never about running its verbs.
allowed-tools: Bash, Read, Edit
---

# Triaging clang optimization remarks in this repo

> Nearest neighbours:
> • A measured slow operation, any codebase → **ripwire-perf-target**. Do that FIRST; remarks are the
>   second question, not the first.
> • Maintenance risk / complexity in a subsystem → **ripwire-fresh-eyes**. Different axis entirely.

Full record of the pass this skill came from, with every number: **`docs/OPTREMARKS.md`**.

## The one rule

**A remark is an observation, not a defect.** Clang is reporting a decision, usually the right one.
The pass that produced this skill read ~1.1 M remarks over `src/`. **Zero of them justified a source
edit.** Two justified a BUILD change (LTO, then PGO), and the best-looking source-level candidate was
implemented, verified to do exactly what the remark asked, measured, and reverted. Budget your
attention accordingly: on this codebase, the answer to a remark is far more often a compiler flag
than a diff.

## Step 0 — profile first, or you will optimize a millisecond

```bash
cmake -S . -B build_prof -DRIPWIRE_PROFILE=ON && cmake --build build_prof -j 6
./build_prof/ripwire . --no-cache 2>&1 >/dev/null | sed -n '/hottest scopes/,/PROF_TSV/p'
```

On this codebase the answer is stable and counterintuitive: **PageRank is ~1 ms** of a ~2.7 s cold CPU
profile, the build-model sorts are ~1.7 ms, and ~31% sits in two phases of `src/ingest.cpp`
(`captureTagsFacts`, `captureSideFacts`) that spend it calling tree-sitter. So a remark in
`src/pagerank.cpp`, `src/sortutil.h` or `src/infra/radixSort.inl` is dismissible on arithmetic before
you read it. Re-derive this table if you touch the pipeline; do not trust this paragraph forever.

## Step 1 — collect

```bash
scripts/optremarks.sh --passes 'inline|loop-vectorize|slp-vectorizer|licm|gvn|.*unswitch|loop-idiom'
python3 scripts/optremarks.py --hot --top 40
```

Never in `build/` — CMake refuses it by name, because `build/ripwire` is the binary every gate and
bench number is measured against. Never with a build type: `RIPWIRE_ARCH_FLAGS` is already `-O2`, and
`Release` would define `NDEBUG` and blind the degrade-path gates. Run wide **once** to learn which
classes fire (`src/main.cpp` unfiltered exceeds 800 MB of YAML), then narrow.

## Step 2 — the remark classes, and what each one is worth here

### Real signal

**`Missed inline NoDefinition`, callee in another TU that you own the build of.**
*Meaning:* the definition is not visible, full stop — not a cost-model opinion.
*Confirmed here:* 397 of 636 distinct `NoDefinition` sites in `src/ingest.cpp` name a tree-sitter C
accessor (`ts_node_start_byte`, `ts_node_type`, `ts_query_capture_name_for_id`, …), each a two-line
function compiled into a separate C object, inside the phases that are 31% of a cold run.
*Fix pattern:* make the definition available — **link-time optimization**, not a source edit.
*Measured:* `-DRIPWIRE_LTO=ON`, four interleaved A/Bs (9/21/21/31 runs per arm) → **cold 1–6% faster,
warm 0–3%**, every cold statistic in every run favouring LTO; output byte-identical, build time
+2.6×. **Now the default** (`-DRIPWIRE_LTO=OFF` for a fast edit loop). Note the shape of that claim:
four runs put the cold median anywhere from −0.8% to −5.9%, so the honest number is the range and the
*unanimous direction*, not the best run.
*Tell it from noise:* if the callee is libc (`fopen`, `fread`, `stat`) the same remark is worthless —
inlining a syscall wrapper saves nothing. The class is only interesting when the callee is **tiny and
yours to build**.

**`Missed gvn LoadClobbered … clobbered by call`, in bulk, in one function.**
*Meaning:* fires per load per pass; 90,971 of them in this record. Useless individually.
*Fix pattern:* there isn't one for a single site. Its value is **aggregate** — a dense cluster in one
function means that function is call-bound, and that is how the `NoDefinition` finding above was
located. Read it as a heat map, never as a work item.

### Restated algorithm — dismiss as a class

**`loop-vectorize` early-exit family:** `TooManyUncountableEarlyExits`,
`PotentiallyFaultingEarlyExitLoop`, `CantComputeNumberOfIterations`, `UnsupportedUncountableLoop`,
`LoopContainsUnsupportedSwitch`, `WritesInEarlyExitLoop`.
*Confirmed here:* hundreds, concentrated in `src/docparse.h`, `src/arch.h`, `src/lexical.h`,
`src/graph.h`, `src/infra/radixSort.inl:402`. Every one is a scanner that `break`s on a delimiter. A
loop whose trip count depends on the bytes it is reading is uncountable **by construction**. There is
nothing to fix without changing the algorithm.

**`Missed inline NeverInline` naming `__clang_call_terminate`.** 275 in the hot set. The
exception-landing-pad helper; `noinline` is deliberate and it never runs on a hot path. Filter first,
every time.

**`Missed loop-vectorize MissedDetails`.** Always paired with an `Analysis` row that gives the actual
reason. Read the `Analysis` row; the `Missed` row carries no information of its own.

**`Missed gvn LoadClobbered … in favor of store … clobbered by store` on a histogram.**
*Confirmed here:* `src/infra/radixSort.inl:411-413`, the 4×-unrolled counting loop — the compiler
cannot prove `digit0 != digit1`, so each `++hist[pass][d]` reloads. Real, and it has a textbook fix
(private per-lane histograms, summed after). **Dismissed on the profile**, not on the analysis: the
sorts are 1.7 ms. Note the shape — *"the remark is right and the fix is known and it still is not
worth doing"* is a legitimate, common verdict.

### Real but not worth it — the calibration case

**`Missed licm LoadWithLoopInvariantAddressInvalidated` + `gvn LoadClobbered` on an address-escaped
struct in a call-heavy loop.**
*Confirmed here:* `src/ingest.cpp:4953`, `for( uint16_t ci = 0; ci < match.capture_count; ++ci )` over
`match.captures[ci]`. `match` had its address taken by `ts_query_cursor_next_match`, so every
accessor call in the body clobbers it: the trip count and the capture base were reloaded on every
iteration, inside the single hottest own-code loop in the tool.
*Fix pattern (the textbook one):* hoist to locals before the loop —
`const uint16_t captureCount = match.capture_count; const TSQueryCapture* const captures = match.captures;`
*What happened:* the remark **moved** exactly as predicted (from the inner loop's line to the hoist's
line — the load became per-match instead of per-capture). The wall clock did not:

| | baseline | hoisted |
| --- | --- | --- |
| run 1, cold median | 166.6 ms | 165.6 ms (−0.6%) |
| run 2, arms swapped | 243.7 ms | 257.6 ms (+5.7%) |

Direction flips between runs ⇒ noise. **Reverted.** The reason: the reload sits immediately beside an
opaque call that costs orders of magnitude more. **This is the most useful entry in this file** — if
you are about to hoist a load out of a loop whose body calls into another translation unit, expect
this outcome and measure before you commit to the diff.

**`Missed inline TooCostly` on libc++ (`basic_string::push_back`, `vector::push_back`,
`unordered_dense::table::…`).** The cost model declining to inline into a large caller. Occasionally
worth chasing; every hot-set instance here was in `src/docparse.h` (document extraction, off the
default path) or one-shot setup in `buildGraph`. Dismissed on **location**, not on principle — check
where yours is before you copy this verdict.

### The cost-model classes have a wholesale answer

**`inline/TooCostly` and `loop-vectorize/VectorizationNotBeneficial` are the same complaint:** the
cost model is guessing at hotness with no data. Chasing them one site at a time is nearly always a
loss — but you can just give the cost model the data.

*Confirmed here:* `scripts/pgobuild.sh` (`-DRIPWIRE_PGO=generate` → train → `llvm-profdata merge` →
`-DRIPWIRE_PGO=use`, on top of `-DRIPWIRE_LTO=ON`). Measured **cold 14–25% faster than a non-LTO build (6–16% over the LTO default), warm 5–10%** —
several times LTO's own effect — with the *largest* gain on a corpus that appears in no training run,
which is what rules out train-on-test. Output byte-identical, determinism gate green.
*The lesson to carry:* when a whole remark CLASS is the cost model rather than a fact about your
code, look for a build-level answer before you rewrite a single loop.
*And where it will NOT help:* the cold path gained 2–3× more than the warm one, because cold is a
branchy call-heavy walk over tree-sitter's parse tree while warm runs mostly in structures already
hand-tuned for cache locality under G2 (the CSR triple, the SoA symbol tables, `dynamic_map`'s
B+tree, the radix sorts). A profile has little to discover in code whose *layout* is already the
optimization — so expect cost-model remarks in G2-shaped code to stay dismissed even after PGO.

## Step 3 — the measurement a fix has to survive

A remark that does not move a measured number does not justify a diff. On this codebase that bar is
harder than it sounds: a cold run is ~160 ms and run-to-run spread is wide.

```bash
# interleaved A/B — A,B,A,B,… so thermal drift and background load hit both arms equally.
# Report median AND min, >= ~20 runs per arm, and REPEAT THE WHOLE A/B at least twice.
```

Two failure modes this bar exists for, both hit during the pass that wrote this file:

- **A single non-interleaved run would have "proved" the D2 hoist below.** Its first A/B said −0.6%;
  swapping the arms said +5.7%.
- **Repeating the A/B is what keeps a real win honest, too.** The LTO finding's four runs put the
  cold median at −3.9%, −4.6%, −0.8% and −5.9%. Quoting the best one would be a fabricated
  precision; what is actually established is a range plus a direction that never flipped.

`bench/perfgate.sh` (median of 5, cold + warm; ledger mode since 2026-08-08 — it prints the medians and
appends them to `bench/PROFILE.md`, no pass/fail against a budget) is the committed harness for the
whole-pipeline number; use `RIPWIRE_BIN=` to point it at each arm and read the two printed medians off
stdout. For a change inside one phase, `-DRIPWIRE_PROFILE=ON` gives per-phase medians that a 160 ms wall
clock cannot resolve.

Then, before you keep it:

```bash
./build/ripwire <dir> >a; ./build/ripwire <dir> >b; diff -q a b     # determinism is a contract
python3 test/pargates.py . ./build/ripwire -j 6
```

**Never** answer a vectorization remark with `-ffast-math` / `-ffp-contract` changes. `src/pagerank.cpp`
is compiled `-fno-fast-math` on purpose — the reduction must not reassociate — and anything that makes
output depend on optimization level is a bug even when the ranking still looks right.

## Anti-patterns this pass actually hit

- **Triaging the wide record.** `size-info`, `asm-printer`, `prologepilog`, `stack-frame-layout`,
  `regalloc` and `hotcoldsplit` are per-function-per-pass bookkeeping. They are most of the volume and
  none of the signal. Narrow with `--passes` after the first look.
- **Reading `third_party/` remarks.** The vendored tree-sitter core and sixteen grammars are C you do
  not own. `scripts/optremarks.py` drops them (and toolchain headers) by default; keep it that way.
- **Believing a remark about a loop you never profiled.** `src/lexical.h`'s BM25 loops looked like the
  best remaining candidate until the `--for` profile showed `lexicalScores` at 0.886 ms of a 95 ms run
  — and the `scanField` re-tokenizer the LICM remarks point at does not execute at all on a warm cache.
- **Publishing a one-run A/B.** See the table in Step 2. Swap the arms and run it again.
