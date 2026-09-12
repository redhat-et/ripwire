# Correctness fuzzers — from "it didn't crash" to "it's right"

You are adding fuzzers to ripwire whose oracle is a **correctness property**, not a crash. Five oracles
are described below. Pick **one** to start, land it as its own PR with a replayable corpus and a gate,
and only then take the next.

Work in a git worktree, not the main checkout. Fuzz, sanitizer and dev builds live in **separate build
trees**. Run every gate in the foreground.

---

## Why it matters

ripwire's fuzzing today answers one question: does a parser crash on hostile bytes?
`test/fuzz/fuzz_ingest.cpp` hands random input to one tree-sitter grammar and walks the tree. That
exercises the **vendored parser**. It does not run one line of ripwire's own extraction, resolver, call
graph, ranking or emitter. Its oracle is "no sanitizer report".

That is necessary, and it is not enough for this tool. CLAUDE.md's first non-negotiable says why: a
ranking, a token estimate and a call graph **all look plausible whether or not they are correct**. A
wrong edge does not crash. A reordered map does not crash. A cache that serves one stale parse does not
crash. They produce an answer an agent believes.

The good news is that ripwire's contracts are already written as mechanical properties — byte-identical
output, warm equal to cold, a well-formed CSR, every call accounted for. Those are exactly the oracles a
fuzzer needs. This work turns "it didn't crash" into "it's right".

---

## Background — what exists, with file pointers

| File | What it gives you |
| --- | --- |
| `CMakeLists.txt`, `RIPWIRE_FUZZ` | Opt-in, OFF by default, mutually exclusive with `RIPWIRE_ASAN` and `RIPWIRE_TSAN`. Requires Clang, and configure compiles and links a real harness first because some Xcode distributions ship Clang without `libclang_rt.fuzzer_osx.a` |
| `CMakeLists.txt`, `add_ripwire_fuzzer( NAME LANGUAGE KEY )` | One `ripwire_fuzz_<name>` per grammar, `EXCLUDE_FROM_ALL`, linking only `test/fuzz/fuzz_ingest.cpp` and that grammar's objects; 21 are registered, and the umbrella target is `ripwire_fuzzers` |
| `test/fuzz/run.sh` | The bounded local sweep: 120 s per grammar by default, 4 jobs, inputs up to 64 KiB, artifacts kept on failure. "Not part of normal regression" |
| `test/fuzz/seeds/<grammar>/valid`, `test/fuzz/seeds/common/utf8.txt` | The seed corpus. Note the extensionless names (trap 4) |
| `test/cachefuzzcheck.sh` | The existing **correctness** fuzzer, for cache blobs: a fixed table of about 26 byte-level and 5 filesystem-shape mutations; the oracle is output byte-identical to a `--no-cache` run. In the regression loop, and a named CI step under ASan. **The model for everything below:** a fixed table, never a random seed at gate time |
| `src/infra/csrverify.h`, `verifyCsr` | The CSR invariants: shape equals node count, `rowOffsets[0] == 0`, `rowOffsets[n] == nnz`, monotone offsets, every column index in range, every value finite and non-negative. Called through `VERIFY` at the end of `buildGraph` (`src/graph.h`) and at the top of `pageRankDouble` (`src/pagerank.cpp`) |
| `test/verify_csr.cpp`, `test/verify_pagerank.cpp` | Doctest property tests: random CSRs from 0 to 10,000 nodes with adjacency round-trip, a 70,001-edge row, NaN and negative rejection, `buildGraph` orientation on a hand-built `IngestResult`; PageRank's empty boundary, a hand-derived dangling vector, all-dangling equals teleport, mass within 1e-9, top-K order with the id tie-break |
| `test/mcpincrementalcheck.sh`, `test/racymtimecheck.sh`, `test/freshnesscheck.sh` | Warm-versus-cold under edit, delete and add; the racy-mtime stat gate; the same-size same-mtime edit that only `ctime` betrays |
| `src/pincensus.h`, `test/declinecheck.sh` arm (F) | Since [#136](https://github.com/redhat-et/ripwire/pull/136) (merged 2026-09-11), `--pin-census=FILE` ends with `# dispositions calls=N bound=… unaccounted=K`: `calls=` is re-derived from the references, the buckets must sum to it, and `unaccounted` must be 0. It raises `DEGRADED_PATH_ALERT` on plain builds. The fixture covers 17 languages |
| `docs/ARCHITECTURE.md`, "Crawl order is deterministic" | Paths are sorted before node ids are assigned; per-thread parse results are re-sorted, so collection order never reaches the output |
| `src/ingest_parsepool.h` | The parse worker count is `min( hardware_concurrency, nfiles )`. No flag or environment variable overrides it |
| `.github/workflows/ci.yml`, det-gate | Two runs of the **same** argv, byte-diffed. It never varies discovery order or worker count |

Two gaps worth knowing before you start, both verified on `main`:

- **`test/fuzz/run.sh` sweeps 15 of the 21 registered targets.** `toml`, `yaml`, `csharp`, `c`, `php`
  and `lua` have targets and seeds but are not in its grammar list. `test/g1configcheck.sh` greps the
  runner for its flags, not for its coverage.
- **Nothing builds the CSR and PageRank property tests.** They exist only under
  `-DRIPWIRE_TESTS=ON`. No gate and no CI step builds `ripwire_test_csr` or `ripwire_test_pagerank`
  (only `ripwire_test_strkern` is built, by `test/strkerncheck.sh` and `test/emitescapecheck.sh`), yet
  CONTRIBUTING.md §2 lists "the CSR property test fails" as an automatic rejection.

---

## The five oracles

### 1. Graph invariants

- **Input.** A random `IngestResult` — files, symbols and references, built the way
  `test/verify_csr.cpp`'s orientation case builds one by hand — passed to
  `rw::buildGraph( ing )` (`src/graph.h`). No parser is involved, so it is fast and fully deterministic.
  A second harness can feed random source text through `ingest()` on a temporary directory.
- **Oracle.**
  - `verifyCsr( g.inEdges, N )` is true, **evaluated explicitly**, never through `VERIFY` (trap 1).
  - Every out-edge target is below `N`.
  - No self-loops, since the builders state they drop them. Assert it; do not assume it.
  - The in-edge CSR holds exactly the same (from, to, weight) multiset as the out-edge arrays.
  - `wOutDeg[s]` equals the double-precision sum of `s`'s out-edge weights, recomputed independently.
    PageRank's column-stochastic argument rests on this equality.

### 2. Rank mass

- **Input.** A random valid CSR, out-degree vector and teleport vector, passed to `pageRankDouble`. A
  second arm runs the float-narrowed vector `rankGraphTeleport` actually returns.
- **Oracle.** Every entry is finite and non-negative, and the total mass is within a tolerance you
  **derive from the arithmetic and write down** before running. The existing unit test's 1e-9 was
  measured at tolerance 1e-13 and 400 iterations, not at the shipped 1e-6 and 100, so it does not
  transfer. If the mass error exceeds your derived bound, that is a finding, not a tolerance to loosen.

### 3. Input-order invariance — the determinism contract

- **Input.** One corpus, run under N recorded permutations of file discovery order, times worker
  counts {1, 2, all cores}.
- **Oracle.** Every output is byte-identical to the first.
- **It needs a test-only hook**, because neither order nor worker count is controllable today. The
  precedent is `RIPWIRE_TEST_PR_MAXITERS` in `src/pagerank.cpp`:
  - It is not a flag and appears in no `--help`; `test/prconvergecheck.sh` arm (G) asserts that.
  - It can only change something the contract says must not matter.
  - It is honoured in every build flavour and read once per process.
  - Its own arm (C) proves an unset or malformed value leaves output unchanged. Yours needs the same.

### 4. Cache round-trip after mutations

- **Input.** A cold run, then a recorded sequence of mutations: edit, add, delete, rename, touch without a
  content change, and an edit that keeps size and mtime (the case `ctime` exists for).
- **Oracle.** After each step, the warm run equals a `--no-cache` run on the same tree state, byte for
  byte. Include the `--mcp` server's revalidation path if you can; `test/mcpincrementalcheck.sh` is its
  three-step version.

### 5. Census conservation

- **Input.** Random corpora in the languages `test/declinefix` covers.
- **Oracle.**
  - Parse the `# dispositions` line from `--pin-census=FILE`. The buckets sum to `calls=` and
    `unaccounted=0`.
  - A plain build prints no `DEGRADED_PATH_ALERT`.
  - The header gauges (`declined=`, `external=`, `unresolved=`) equal the census buckets
    `test/declinecheck.sh` re-derives them from.
- **Prerequisite satisfied.** #136 landed the dispositions this oracle reads.

---

## How to reproduce and measure

```bash
cmake -S . -B fuzz -DRIPWIRE_FUZZ=ON          # Clang with the libFuzzer runtime; configure refuses otherwise
cmake --build fuzz -j -t ripwire_fuzzers       # the harnesses are EXCLUDE_FROM_ALL: a plain build makes none of them
bash test/fuzz/run.sh fuzz 60                  # bounded local sweep: build dir, seconds per grammar
```

- **Replay without fuzzing.** When libFuzzer is given a list of files rather than directories, it
  re-runs those files as inputs and performs no fuzzing
  ([llvm.org/docs/LibFuzzer.html](https://llvm.org/docs/LibFuzzer.html)). That is the CI mode: a
  committed, minimized corpus, replayed with bounded work.
- **Minimize.** `-merge=1` merges inputs that add coverage into the first corpus directory. Commit the
  minimized set, not the raw pile.
- **Whole-binary oracles** (3 and 4) may fit better as a deterministic generator plus a gate script than
  as libFuzzer targets: a seed table recorded in the gate, like `test/cachefuzzcheck.sh`. Choosing is
  part of your plan.

---

## Design space and constraints

- **Gate before code, and see it red.** Break the property deliberately in a scratch copy — keep a
  self-loop, reverse a sort, skip a census bucket — and show the oracle catches it from the replay corpus
  or a bounded run. CONTRIBUTING.md §2's control rules apply: mutate real input, assert the mutation
  took, prove it from a bash script.
- **Determinism, including the fuzzer's.** CI replays a fixed corpus or a fixed seed table. Never a
  time-bounded random search at gate time — `test/cachefuzzcheck.sh` states the rule as "a FIXED table,
  not a random seed".
- **No performance-budget gates.** Bound CI work by input count, never by wall time. The suite runner's
  default timeout (300 s in `test/pargates.py`) is a hang guard, not an assertion.
- **Respect the CI budget.** `.github/pargates-macos-plain-skip.txt` records the macOS plain leg as an
  `-O0` binary on a 3-core runner and the workflow's critical path at 33–37 minutes. Heavy fuzzing never
  goes into a CI budget. CI replays; open-ended fuzzing runs locally (or in a manually dispatched
  workflow, if maintainers want one).
- **Honesty in output.** A fuzzer that reports "0 findings" says how many inputs it executed. A replay
  that executed 0 inputs is a FAIL, not a pass.
- **Test hooks are not flags (G5).** No parser entry, no `--help` line, a gate arm that asserts both, and
  proof that the unset hook leaves output byte-identical.
- **Any new degrade path in `src/` uses `DEGRADED_PATH_ALERT`,** never `VERIFY( false )`
  (non-negotiable 4).
- **House C++ style** in harnesses too: Allman braces, braces on every body, spaces inside parens, no
  `std::map` or `std::unordered_map` (CONTRIBUTING.md §3).
- **Build discipline.** Never edit the tree while a build runs. The fuzz, sanitizer and dev trees are
  separate by construction.

---

## Acceptance criteria

1. **One oracle per PR.** Each comes with a harness, a committed replay corpus or fixed seed table, and a
   `test/<name>check.sh` gate listed in `test/regression.sh` in the same commit, with the gate count
   regenerated by `python3 docs/gatecount_build.py` (never by hand).
2. **Observed red.** Each oracle has been seen failing on a deliberately broken build. The red output is
   recorded in the gate header, the way `test/prconvergecheck.sh` records its own.
3. **CI replay is bounded by input count.** It runs under ASan and UBSan, carries no timing assertion,
   reports how many inputs it executed, and fails when that number is 0.
4. **Local fuzzing is documented:** the command, the duration option, where artifacts land, and how a
   crash or oracle failure becomes a minimized replay input.
5. **Every bug found** gets its minimized input committed to the replay corpus, and its fix lands
   separately with a red-first arm.
6. **The sweep list stops drifting.** `test/fuzz/run.sh` covers every registered target, derived from
   CMake rather than a hand list, or states why not; `test/g1configcheck.sh` asserts whichever you choose.
7. **The property tests run.** The CSR and PageRank doctest targets are built and run by a gate, or the
   PR states why they should not be and CONTRIBUTING.md §2 is corrected.
8. **Gates green in the foreground:** your new gate, `test/manifestcheck.sh`, `test/gatecountcheck.sh`,
   `test/g1configcheck.sh`, `test/ripwirepubliccheck.sh`, `test/cachefuzzcheck.sh`,
   `test/declinecheck.sh`, and the two-run determinism diff.

---

## Known traps

1. **`VERIFY` is an optimizer hint in a release build.** Under `NDEBUG`, `src/infra/Diagnostics.h`
   compiles it to `__builtin_assume` (Clang) or an `if( !expr ) __builtin_unreachable()` (GCC). A
   violated invariant in a Release build is undefined behaviour, not a report. Evaluate oracles
   explicitly, in a non-`NDEBUG` tree.
2. **An oracle that calls the code under test agrees with it.** Re-derive independently. #136 is the
   pattern: `calls=` is counted off the references, "never summed from the buckets it is checked against".
   Recompute out-degree from the edge list; recompute the edge multiset from both CSR sides.
3. **Empty equals agreement.** A replay directory that is missing, or a corpus glob that matches
   nothing, runs zero inputs and exits cleanly. Assert the count first.
4. **Corpus files are part of the repository ripwire indexes.** The live-tree gates crawl this checkout,
   and the seed corpus uses extensionless names (`valid`), so it is never parsed as source. A replay
   corpus of `.py` and `.cpp` files would be. It would also meet `test/ripwirepubliccheck.sh`, which sweeps
   tracked text for home-directory paths and credential-shaped literals — shapes a mutator can produce.
5. **Randomness at gate time breaks the contract the gate exists to protect.** Record seeds, commit
   minimized inputs, and replay them.
6. **libFuzzer is not in every Clang.** Configure refuses when the runtime is missing. Use an LLVM
   toolchain that ships it, or Linux.
7. **Leak detection differs by platform.** `test/fuzz/run.sh` turns leak detection off on macOS and on
   elsewhere, with `lsan_suppressions.txt`. A leak-clean replay on macOS proves nothing about leaks.
8. **The census alert is plain-build only.** `DEGRADED_PATH_ALERT` compiles out of Release, so a Release
   run reports a non-zero `unaccounted` only in the census line. Parse the line; never rely on stderr alone.
9. **A hook that changes output when unset is a behaviour switch.** Prove it inert first, as
   `test/prconvergecheck.sh` arm (C) does for its own hook.

---

## What the PR description should contain

- **The oracle and its property**, stated before the code: what "right" means and how it is re-derived
  independently of the code under test.
- **The red run:** the deliberate break, the failing output, and the input that caught it.
- **Corpus provenance:** how inputs were generated, how they were minimized, how many there are, and the
  replay's executed-input count.
- **CI cost** as an input count, and which legs run it. No timing claim.
- **Every bug found**, with its minimized input and the separate fix PR.
- **What the oracle does not cover:** languages, input shapes, and the build flavour it runs in.

---

**Write the plan — the oracle you start with, its independent re-derivation, the harness shape, the
replay corpus, the red run, and where it runs in CI — then STOP for my go-ahead.**
