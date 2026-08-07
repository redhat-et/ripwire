# ripwire — self-profile (where the time goes)

ripwire instruments its own pipeline with the vendored `PROFILE_SCOPE`
(`src/infra/profileScope.h` + `profilePmc.h`). Gated behind a CMake option so the normal
binary stays **byte-identical + zero-cost** (every marker → `((void)0)`; verified: no report,
deterministic, map unchanged).

## Reproduce
```sh
cmake -S . -B build_prof -DRIPWIRE_NATIVE=ON -DRIPWIRE_PROFILE=ON && cmake --build build_prof -j
# timing only (per-phase CNTVCT wall):
build_prof/ripwire <repo> --no-cache            # cold (full tree-sitter parse)
build_prof/ripwire <repo>                        # warm (cache hit) — run twice, 2nd is warm
# + Apple PMC cycles/instructions/cache-misses per phase (needs root to arm the counters):
sudo build_prof/ripwire <repo> --no-cache > /tmp/map.xml 2> /tmp/p.txt
```
The report auto-prints at exit **on stderr** (a `#PROF_TSV_BEGIN…END` block carries the raw integers
for tooling); stdout stays the well-formed XML map, so `>map.xml 2>report.txt` captures both and
piping the map (`| xmllint --noout -`) keeps working in the profile flavour.

**Counter backends.** Two real PMC backends sit behind one surface (`src/infra/profilePmc.h`):
Apple Silicon (kperf/kpep — needs root or the kperf entitlement to ARM; event-name resolution
verified through M5 Pro, whose last-level alias resolves via `PL2_CACHE_MISS_LD`) and Linux
(`perf_event_open` — one pinned, atomically-scheduled event group per thread, whole group read in
one syscall; `exclude_kernel` so the stock `perf_event_paranoid=2` admits it, no root needed).
On Linux the graceful per-event skip applies to the group leader too: a box whose kernel refuses
the hardware events (most VMs have no vPMU — every `PERF_TYPE_HARDWARE` open fails `ENOENT` there;
bare metal and `*.metal` instances expose the real thing) still arms the trailing
`PERF_TYPE_SOFTWARE` rows — `task-clock` (on-CPU ns; its gap against the wall column is off-CPU
time) and `page-faults` — so a cloud-VM profile keeps honest per-scope counter columns instead of
timing only. Distinct column names, raw integers, never a stand-in for the hardware counts. Only
when the kernel offers nothing at all (`perf_event_paranoid>=3`, seccomp) does a backend degrade
to plain timing, silently; `test/pmccheck.sh` asserts whichever arm (active/inactive) the machine
can express, and its inactive arm now also proves the kernel truly offered no counter.

**Validation status, stated rather than implied.** The Apple backend's active path is exercised by the
`sudo` run above, and its event-name resolution is verified through M5 Pro. The Linux backend's
**active** path is not yet validated on real hardware: it has been run for correctness, degrade
behavior and the full sanitizer set under x86-64 emulation and on PMU-less VMs, both of which can only
express the *inactive* arm (`perf_event_open` fails, the backend reports `active()==false`, timing
continues). Until it runs on a bare-metal box, treat Linux counter columns as unproven; the timing
columns are unaffected either way.

**Does this box have a PMU?** Ask before writing code against it — most virtualized hosts expose none.

```sh
perf stat -e cycles,instructions,branch-misses,cache-misses true   # `<not supported>` ⇒ no PMU, stop here
cat /proc/sys/kernel/perf_event_paranoid                            # 2 is the stock value, and is enough
```

The first is the real discriminator: if the kernel reports `<not supported>` for the hardware events,
no amount of privilege will help and the backend will correctly go inactive. `perf_event_paranoid` at
its stock `2` suffices because every event is opened `exclude_kernel` — only the Debian/Ubuntu
downstream `3`, which denies unprivileged perf entirely, forces the inactive arm on an otherwise
capable box. There is nothing to check about `rdpmc`: the userspace mmap+`rdpmc` fast-path read is a
bench-gated follow-up that does not exist yet, and today's backend always reads through the `read()`
syscall on the group leader.

**Historical, private corpus (not reproducible publicly):** every table below labeled against a
large ~1500-2000-file private C++ corpus was measured on the owner's own codebase, which is not
public. Re-run the `Reproduce` commands above against your own large repo to reproduce the shape;
absolute numbers will differ by corpus.

## Timing breakdown — whole private C++ corpus (1560 files), Apple Silicon
Structure is stable run-to-run (±~15% wall); percentages are the robust story. (Numbers below are
the *pre-fix diagnosis*; the query-compile column is then cut by the optimization — see end.)

| phase | cold (~1.0 s) | warm (~0.29 s) | what it is |
|---|---|---|---|
| tree-sitter **parse** (parallel) | **76%** (~780 ms) | ~33 ms | parse every file → tags; the cache makes it incremental |
| tree-sitter **query-compile** | 17% (~175 ms) | **62%** (~176 ms) | compile each grammar's `tags.scm` — **constant, every run** |
| fs **crawl** | ~3% (~34 ms) | ~12% | directory walk + gitignore filter |
| **resolve refs + build CSR** | ~1% (~10 ms) | ~4% | name→def resolution, in/out-edge CSR |
| **PageRank** | ~1% (~10 ms) | ~4% | power iteration over the call graph |
| build-model + cache I/O + emit | ~2% | ~14% | dedup, cache read/write, serialize map |

**Three findings**
1. **The ranking is the cheap part.** ref-resolution + PageRank = **~21 ms (~2% cold)**. The graph
   "intelligence" everyone assumes is expensive costs almost nothing; parsing is the tax.
2. **The cache collapses parse 782 → 33 ms (24×)** — that's the warm speedup.
3. **A 175 ms constant** — tree-sitter query-compile, run every invocation regardless of cache →
   was **62% of warm**. **Fixed** (commit `b9b5763`): compile only the grammars present in the
   crawl. See below.

## Build-profile options (2026-08-05) — measured, both off by default

Everything else in this document profiles the **default build**. A clang optimization-remarks pass
over `src/` (`-DRIPWIRE_OPT_REMARKS=ON`) found the hot phases above are call-bound across a
translation-unit boundary into tree-sitter's C API — 397 of 636 distinct `inline/NoDefinition`
remarks in `src/ingest.cpp` name a `ts_*` accessor. Two build options answer that:

| build | cold | warm | cost |
|---|---|---|---|
| `-DRIPWIRE_LTO=ON` | 1–6% faster | 0–3% | rebuild after touching main.cpp 34 s → 89 s |
| `scripts/pgobuild.sh` (PGO on LTO) | **14–25% faster** (6–16% over the LTO default) | 5–10% | two configures + a training run |

Interleaved A/B, median and min, 9–31 runs per arm, repeated; measured on this repo AND on a
~2000-file C++ tree in no training run. Output byte-identical, determinism gate green on both trees.
The cold/warm split matches the phase table above: cold is a branchy walk over tree-sitter's parse
tree (lots for a profile to learn), warm already runs in the cache-tuned CSR/SoA/B+tree structures.
Full triage, per-run tables and every dismissed remark: [`../docs/OPTREMARKS.md`](../docs/OPTREMARKS.md).

## Optimization landed — two passes
**1. Compile only present grammars** (commit `b9b5763`). After the crawl the present extensions are
known, so the prewarm compiles only those grammars (a `.h` may re-route to objc via `looksObjC`, so
any `.h` pulls objc in too — keeping the set a superset of every grammar a worker touches; workers
only *read* the non-thread-safe query cache).

**2. Compile the remaining grammars in parallel** (commit `9432b4d`). PMC said `ts_query_new` is
compute-bound (IPC 4.0) → it parallelizes well. Prime `queryFor()` single-threaded (→ safe concurrent
`.scm` reads), `ts_query_new` each distinct grammar on its own thread into a local, then install into
the cache single-threaded after the join — so workers keep reading the query cache lock-free.

| | original (8 grammars) | + skip absent | + parallel |
|---|---|---|---|
| query-compile (private corpus: C++/ObjC/Python) | ~175 ms | ~97 ms | **~68 ms** |
| **warm wall, whole repo** | ~313 ms | ~206 ms | **~182 ms (1.7×)** |
| warm wall, small dir (infrastucture) | ~186 ms | ~103 ms | **~77 ms (2.4×)** |

Verified at each step: output **byte-identical** (A/B against the pre-change binary on a frozen
3806-file snapshot), deterministic, regression **ALL PASS**, and the parallel pass is
**ThreadSanitizer-clean** (targeted C++/ObjC/Python corpus + the full snapshot). The ~68 ms floor is
real — C++/ObjC/Python are genuinely present and the C++ `tags.scm` is the costly one; a
single-language (esp. non-C++) repo wins far more.

## Apple PMC — per-phase hardware counters (one `sudo` run)
`PMC: cycles, instructions, branch-misses, l1d-cache-misses, l1i-cache-misses`

| phase | IPC | l1d MPKI | br MPKI | instructions | note |
|---|---|---|---|---|---|
| query-compile | **4.00** | 6.1 | 2.5 | 2.14 G | near-peak IPC ⇒ **compute-bound** → fix is *do less* (skip absent langs) |
| crawl | 4.32 | 0.5 | 0.1 | 0.63 G | compute-bound (FS page-cached, string/path work) |
| build-model | 3.29 | 16.8 | 2.3 | 0.13 G | dedup sorts thrash L1d |
| resolve + CSR | 2.71 | 15.4 | 4.8 | 0.08 G | hash-lookup-bound (name resolution) |
| PageRank | 2.19 | 13.2 | 14.5 | 0.07 G | **memory + branch-bound** — classic sparse-graph (CSR pointer-chase) |
| emit | 1.43 | 4.4 | 17.0 | 0.006 G | printf / serialize |

**⚠ Caveat — the `parse pool` row's PMC is *not* the parse.** `kpc_get_thread_counters` reads the
**calling thread only**; parse runs on worker threads, so that row's counters (IPC ~1.3) are just the
main thread's spawn/join wait. Its **wall time is real**; its counters are not. Every other phase is
single-threaded → its counters are accurate.

## 2026-07-03 refresh — Wave 2 #8 (perf self-guarding), HEAD `f76fa6d`, Apple Silicon

Closes the audit's "PROFILE.md stale — no gate" risk and the "PROFILE_SCOPE the lexical+gitmine gaps"
finding. Two new instrumented paths, one new drift
alarm, and a fresh measurement pass with the current binary.

### New instrumentation
`PROFILE_SCOPE_DESCRIBE` one-liners added at function entry (zero behavior change; compiles to
`((void)0)` off the profile flag — verified below):
- `src/lexical.h` — `lexicalScores()` (the whole BM25-over-symbols pass; was entirely dark before —
  previously only visible as time NOT accounted for by any `ingest:`/`buildGraph:`/`rankGraph:` scope).
- `src/gitmine.h` — the four popen-based git-mining entry points: `gitCommitFileSets()` (log
  --name-only, backs co-change + churn), `churnTeleport()` (`--rank-by=churn`), `gitFileAuthors()`
  (`--owners`, one `popen` per file), `cochangePartners()` (`--cochange`).

**Headline finding from turning the light on:** `gitFileAuthors` (`--owners` on this repo, ~150
tracked files) cost **5.3 s** in one profiled run — by far the single most expensive user-facing
operation in the whole tool, and it was invisible in every prior PROFILE.md/PERF.md pass because
nobody had instrumented gitmine.h. It does one `popen("git log --follow ...")` per file — O(files),
each spawning a subprocess. Not fixed in this pass (out of scope: instrumentation only, zero behavior
change) — flagged here as the next perf target, likely batching into fewer git invocations or a
single `git log --name-status` walk shared across files (the same trick `gitCommitFileSets` already
uses for co-change/churn).

### The drift alarm — `bench/perfgate.sh`
New script: builds nothing, times a fixed corpus (this repo's own root — `src/` + `third_party/` +
whatever the denylist keeps; ripwire takes one positional `<dir>` so `$ROOT` stands in for "src +
third_party") cold (`--no-cache`) and warm (`--cache=`, primed), median of 5 via `/usr/bin/time`,
compares against `bench/perf_budgets.txt`. Exits 1 with a loud message on any median over budget.
**Not** wired into `test/regression.sh` — perf gates flake in CI (thermal throttling, shared runners,
background load); this is an on-demand + pre-release check a human runs on a quiet machine.

Initial budgets seeded via `bench/perfgate.sh --write-budgets` = measured median × 1.5 (headroom for
machine variance without masking a real regression — see the file's own header for the rationale):

| key | measured median | budget (×1.5) |
|---|---|---|
| cold (`--no-cache`) | ~160–170 ms | 255 ms |
| warm (`--cache=`) | ~20 ms | 30 ms |

**Alarm proof:** temporarily set `cold`'s budget to 1 ms → `bench/perfgate.sh` reported
`FAIL  cold  170.0 ms  >  budget 1 ms` and exited 1; restored the real budget → back to
`PASS` / exit 0. The gate fires when it should and stays quiet when it shouldn't.

### Fresh measurement table (current binary, HEAD `f76fa6d`)

Rebuilt from a clean tree in an isolated build dir (`-DRIPWIRE_NATIVE=ON`); medians of 3+.

| repo | cold | warm | --for | --hotspots |
|---|---|---|---|---|
| this repo (ripwire, ~150 files) | 0.16 s | 0.02 s | — | — |
| private C++ corpus (1849 files / 33k syms) | 1.50–1.63 s (med ~1.54 s) | 0.28–0.29 s | 0.32–0.34 s | 0.38–0.61 s (med ~0.41 s) |

Tracks the recorded perf-audit baseline (repo cold 0.16 s/warm 0.02 s; private corpus
cold 1.30 s/warm 0.32 s/`--for` 0.79 s/`--hotspots` 0.43 s) closely — this repo's numbers match
exactly; the private corpus's cold and `--for` measure somewhat faster here (1.5 s vs 1.3 s is within
run-to-run variance in the other direction, but `--for` 0.33 s vs 0.79 s is a real gap, consistent with
perf work landed in the batches since the audit was written — not independently re-attributed here,
flagged for a future profiling pass to confirm which fix gets the credit).

### Fresh private-corpus phase table (profile build, `-DRIPWIRE_PROFILE=ON`)

**Cold** (`--no-cache`, 1849 files):

| phase | ms | %tot |
|---|---|---|
| ingest: total | 1354.2 | 96.6% |
| — parse pool (tree-sitter, parallel) | 1125.0 | 80.2% |
| — compile queries (tags.scm prewarm) | 85.1 | 6.1% |
| — doc post-pass | 61.0 | 4.3% |
| — build model (dedup + symbols/refs) | 52.7 | 3.8% |
| — crawl (collectSources) | 25.0 | 1.8% |
| buildGraph: resolve refs + build CSR | 36.2 | 2.6% |
| rankGraph: PageRank | 9.6 | 0.7% |
| emit: serialize ranked map | 2.0 | 0.1% |

**Warm** (`--cache=`, primed, zero file changes):

| phase | ms | %tot |
|---|---|---|
| ingest: total | 228.0 | 81.7% |
| — doc post-pass | 62.8 | 22.5% |
| — build model | 50.3 | 18.0% |
| — parse pool (hash-check only) | 28.7 | 10.3% |
| — crawl | 20.2 | 7.2% |
| — compile queries prewarm | 19.3 | 6.9% |
| buildGraph: resolve refs + build CSR | 39.0 | 14.0% |
| ingest: loadCache | 32.0 | 11.5% |
| rankGraph: PageRank | 10.1 | 3.6% |
| emit: serialize ranked map | 2.0 | 0.7% |

Notable vs. the original diagnosis at the top of this file: **`saveCache` no longer appears in the warm
table** — the P2 dirty-flag fix (`ingest.cpp:1966`, "Win 2 (PERF.md P2) — dirty flag: skip saveCache
when nothing changed") is confirmed landed and working: a zero-change warm run skips the 7+ MB
re-serialize entirely. **Doc post-pass is now the single largest warm-run item (62.8 ms, 22.5%)** —
matches the audit's P3 finding ("cache doc post-pass", ~53–63 ms warm) and remains unfixed; still the
next-best warm-run lever after `gitFileAuthors` above.

*Reproduce:* `cmake -S . -B build_prof -DRIPWIRE_NATIVE=ON -DRIPWIRE_PROFILE=ON && cmake --build build_prof -j`,
then `build_prof/ripwire <repo> --no-cache` (cold) / `build_prof/ripwire <repo> --cache=/tmp/c.bin` run
twice (warm). Perf-gate check: `bench/perfgate.sh` (needs `build/ripwire`; see its header for
`--write-budgets`).

## 2026-07-11 — MEASURE-FIRST: speculative-prefetch experiment (Phase E)

The design's Phase-E experiment: instrument the MCP server, drive a realistic ~20-call session, and let the
NUMBERS decide whether the speculative-prefetch mechanism is worth building. **Outcome: build the
instrumentation + harness, build NOTHING else this round** — the honest, design-anticipated result.

### Instrumentation (env-gated, zero-cost-off)
`RIPWIRE_MCP_TIMINGS=1` makes `runMcp` (`src/mcp.h`) emit ONE stderr line per request —
`ripwire-timing verb=<v> wall_ms=<f> rebuilt=<0|1>` — where `rebuilt=1` means a full `getIndex()` rebuild
(the staleness / post-edit cache-miss path) fired during that request. Off by default → the server is
byte-identical + silent on stdout (gated by `test/spectimingcheck.sh`, and the A/B in `bench/spec_trace.py
--determinism`). Same precedent as `ingest.cpp`'s `RIPWIRE_CACHE_STATS`.

> **Deviation from the design (noted for the coordinator):** the design named a `--mcp-timings` CLI flag.
> `src/cli.h`/`main.cpp` were owned by a concurrent agent this round, so the switch is the env var
> `RIPWIRE_MCP_TIMINGS` instead — same zero-cost-off contract, no CLI surface touched. If the mechanism ever
> ships, the flag can be added then; the observable's behavior is identical either way.

### Decision table — per-request wall (ms), medians over 5 reps, Apple Silicon
Reproduce: `python3 bench/spec_trace.py --bin build/ripwire --reps 5`.

| phase | verb / step | ripwire p50 | ripwire p95 | reb | canyon p50 | canyon p95 | reb |
|---|---|---:|---:|:-:|---:|---:|:-:|
| orient | for (first verb) | 64.8 | 68.7 | 1 | 362.1 | 416.3 | 1 |
| read | find_symbol | 0.7 | 0.8 | 0 | 4.7 | 6.3 | 0 |
| read | fetch_body | 1.1 | 1.2 | 0 | 10.7 | 12.5 | 0 |
| read | callers | 0.7 | 0.7 | 0 | 4.9 | 6.4 | 0 |
| read | impact | 1.0 | 1.1 | 0 | 10.9 | 11.9 | 0 |
| read | uses | 0.8 | 1.0 | 0 | 7.9 | 10.2 | 0 |
| read | grep | 102.5 | 103.1 | 0 | 1668.8 | 1796.0 | 0 |
| read | analyze | 0.9 | 0.9 | 0 | 5.2 | 8.5 | 0 |
| **edit** | **replace_symbol_body (rebuild)** | **51.8** | **52.4** | **1** | *skipped (read-only)* | — | — |
| post-edit | for (warm, edit already rebuilt) | 11.2 | 11.3 | 0 | — | — | — |
| **quality** | **quality_delta (cold qsnap)** | **734.1** | **779.0** | 0 | **14493.4** | **14702.9** | 0 |
| quality | quality_delta (warm qsnap) | 377.8 | 386.9 | 0 | 8154.4 | 8284.7 | 0 |
| situ | situational_awareness | 81.3 | 83.0 | 0 | 251.5 | 307.6 | 0 |

Read verbs are **microseconds-to-low-ms warm over the in-memory graph** — candidates (b) cache-warming and
(c) co-change prefetch confirmed to have **~0 latency to hide** (design REJECT stands, now measured). The only
slow moments are rebuilds and the quality-snapshot pass.

### The load-bearing finding on candidate (d)
`quality_delta` compares the **working tree** to the **HEAD tree**. Only the HEAD side (the `qsnap` Snapshot,
`quality.h:428`, keyed by sha) is cacheable/prefetchable; the working-tree clone pass is recomputed on **every**
call and is **un-prefetchable** by construction. So the figure that decides (d) is the **prefetchable delta
`cold − warm`** (with the on-disk qsnap family cleared before the cold call — else "cold" is silently warm),
NOT the absolute wall:

| corpus | prefetchable qsnap delta p50 | p95 | total cold quality_delta | un-prefetchable working-tree residual |
|---|---:|---:|---:|---:|
| ripwire (~150 files) | 357.7 ms | 392.1 ms | 734 ms | ~378 ms |
| private C++ corpus (1849 files) | 6213.5 ms | 6586.1 ms | 14493 ms | ~8154 ms |

Even where (d) is GO, the prefetch hides only **~43 % of `quality_delta`** (6.2 s of 14.5 s) — the working-tree
clone pass (~8.2 s) is the larger elephant and no prefetch touches it. (The design's TL;DR "~1.5 s cold ingest"
and the reviewer's "~3 s" both **understated** the true cost; the whole point of measure-first.)

### GO / NO-GO verdict (thresholds from the design's §4)
| candidate | ripwire (~150 files) | private C++ corpus (1849 files) |
|---|---|---|
| **(a) edit-rebuild** — DEAD if <500 ms total OR p95<200 ms | **DEAD** (52 ms) | *edit skipped (read-only).* Warm rebuild proxy = for(first) **362/416 ms p95**: a **single** edit is <500 ms total → DEAD; **≥2** edits crosses both thresholds → would SURVIVE. **Marginal, edit-frequency-dependent.** |
| **(b) predicted-verb cache-warm** | **DEAD** (read verbs ~0.7 ms warm — nothing to hide) | **DEAD** (~5–11 ms warm) |
| **(c) co-change prefetch** | **DEAD** (same — no answer latency) | **DEAD** |
| **(d) qsnap prefetch on HEAD-move** — GO if prefetchable p95 > 1 s | **NO-GO** (392 ms) | **GO** (6586 ms p95) |

### What was built — and what was NOT
- **Built:** the `RIPWIRE_MCP_TIMINGS` observable (`src/mcp.h`), the `bench/spec_trace.py` harness, this
  section, and `test/spectimingcheck.sh` (the zero-cost-off + protocol-byte-identity gate).
- **NOT built — Phase M deferred (STOP):** (d) fires GO only at large-repo scale, and its mechanism is **not
  "genuinely small."** The thing it prefetches is the single heaviest op in the tool (a full HEAD Snapshot:
  git archive + ingest + `findClones`), run on a background thread **concurrently with request-serving** — which
  mandates the design's **G-race (TSan)**, **G-non-vacuity**, and **G-monotone-freshness** gates and a
  reconciliation with the team-index design's proposed global request mutex (reviewer note, §5). That is a
  Phase-M change with a real concurrency surface, not a detached one-liner, and its gates cannot be brought to
  green cheaply this round. Per the house phase-gate rule (write the gate before the code) and the design's own
  "measure says don't build it is a first-class outcome," the correct call is **ship the instrumentation, record
  (d) GO-at-scale, and build the mechanism in a dedicated Phase-M round.** The bigger perf lever it surfaced —
  the **un-prefetchable ~8 s working-tree clone pass** — is a better next target than the qsnap prefetch itself.

## 2026-07-11 — post clone-dedup quality-delta (private C++ corpus, warm, medians of 3)

After the computeDelta clone-pass dedup (commit d1ad890: both consumers now share one
findClones+findClonesType3 result) on top of the per-sha quality-Snapshot cache: warm
`--quality-delta` = **4.06 s** (4.33/4.05/4.06 measured 2026-07-11 on the live tree; was 7.87 s
before the dedup, 17.1 s before that). The remaining cost is the single Type-3 pair-enumeration
pass (~2.7 s, 60.5 M pair-visits — the B1 lever) + ingest/churn.

## 2026-07-11 — JSON token-calibration measurement (A1-backlog, Wave 1)

`kTokenCalib[Lang::Json]` shipped as a **2.50 placeholder** ("mid-band until measured"). Measured with
real `o200k_base` tiktoken — the same procedure and encoding that produced the rest of the table
(commit `aece7e5` "MAPE vs o200k"): `bytesPerToken = total UTF-8 bytes /
total tokens` over the concatenated corpus. New value: **3.10 B/tok**.

- **Corpus:** n=108 real `package.json`/`tsconfig.json` files from the LocBench repo cache
  (178,825 bytes, 57,616 tokens).
- **Reproduce:** `python3 bench/calib_json.py <locbench-repos-dir>` → `bytesPerToken=3.1037 (rounded 3.10)`.
- **Note:** the measured rate (3.10) is *above* the code-language rows (2.36–2.59), which is plausible —
  pretty-printed JSON's 2-space indentation and the English prose in `description`/dependency-name fields
  compress unusually well under BPE. Well inside the <1.5 / >4 sanity band. Golden unaffected (test/fixture
  has no JSON); only `--token-budget`/economy estimates on JSON-bearing corpora shift.

## 2026-07-11 — Type-3 pair-enumeration reorder (B1, THE SANCTIONED OUTPUT CHANGE)

The ~2.7 s tail of `--clones`/`--quality-delta` was ~60.5 M intra-bucket pair-visits, each doing
`pairSeen` hashmap find+emplace bookkeeping BEFORE the cheap prefilters. **Fix:** hoist the O(1),
pure length-band gate AHEAD of `pairSeen` — a length-mismatched pair (the common case) is now dropped
with one float compare and never touches the hashmap. The O(|fp|) Jaccard gate DELIBERATELY stays
behind the de-dup (hoisting it too measured ~3× slower — a pair recurs in every shared-k-gram bucket,
so its merge would re-run per recurrence instead of once per distinct pair).

Both gates are pure, so their order relative to the de-dup never changes WHICH distinct pairs pass:
the emitted SET is byte-identical on repo/fixture/canyon (verified: committed-binary output ==
new-binary output on all three, for both `--clones` and `--quality-delta`; det-gate ×3 clean).

**Sanctioned semantic change** (cap only): `kType3MaxPairs` now bounds "the first N pairs that clear
BOTH gates" instead of "the first N raw visits" — a strictly more meaningful degrade cap. It changes
emitted output ONLY on a pathological cap-hitting corpus (none of the shipped corpora reach it). Gated
by a synthetic cap-hitting fixture (`-DCTX_TYPE3_MAX_PAIRS` compile-time override, test-only) asserting
the first-N-survivors truncation + a mutation check (cap 2→2, 3→3, default→6).

**Timing** (private C++ corpus, warm, median of 3; committed HEAD vs this change):
- `--clones`:         2.63 s → **1.82 s**  (−31%)
- `--quality-delta`:  4.07 s → **2.87 s**  (−30%)

The absolute "Type-3 pass ≤ ~1 s" aspiration was not fully reached — keeping the Jaccard gate behind
the de-dup (the measured-faster choice) leaves that portion of the pass in place; the win here is the
eliminated hashmap-bookkeeping churn on length-mismatched pairs. Byte-identity + determinism (the
mandatory obligations) hold.
