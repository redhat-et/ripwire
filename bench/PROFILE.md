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

## 2026-08-08 — perfgate ledger: label=default

Ledger-mode measurement (owner directive 2026-08-08: perf budgets are not the model — best
tool first, then make it fast; no pass/fail — see bench/perfgate.sh header). BIN=build/ripwire (lane-F worktree)
corpus=. (lane-F worktree) runs=5 (median) machine=Darwin arm64 generated=2026-08-08 14:33 UTC

| key | median (ms) |
|---|---:|
| cold | 178.4 |
| warm | 35.7 |

## 2026-08-08 — representative_perfgate ledger

Ledger-mode measurement (owner directive 2026-08-08: perf budgets are not the model — best
tool first, then make it fast; no pass/fail — see bench/representative_perfgate.sh header).
machine=Darwin/arm64 (Mac17,8) fixture=08352db35d9c93c4fc7e3af7f38469af8f8b86d1 copies=80 files=480 bytes=183040 runs=5 generated=2026-08-08 14:33 UTC

| key | median (ms) |
|---|---:|
| cold | 59.439 |
| warm-index-retrieval | 13.365 |
| report | 59.729 |
| quality-delta | 142.838 |
| dead-code | 62.362 |
| mcp-warm-request | 1.309 |

## 2026-08-08 — `--lint`: three astQuery passes collapsed to one walk, one tree walk per file, one compile per PRESENT grammar

**Ledger, not a gate.** No budget or threshold was added, here or in CI — per the owner's directive
these numbers are a record, never a red build. What justified the change is that the cost removed was
defect-shaped (duplicate work, not a tradeoff) and that the output is byte-identical.

**How the cost was localized.** A profile build (`cmake -S . -B prof -DRIPWIRE_PROFILE=ON`) with
`PROFILE_SCOPE` armed inside the naming lens and around each phase of `runLint`. The audit finding
that opened this round attributed the regression to the `naming-*` rule family; the profile does not
support that. `namingLensChecks TOTAL` is **15.2 ms of a 1365 ms run — 1.1%**. The three astQuery
passes are 1175 ms of it:

| scope (pre-fix, `--lint` on the frozen HEAD tree) | calls | ms |
| --- | ---: | ---: |
| `lint: mergeAtomsPack` | 1 | 498.0 |
| `lint: astQuery built-in checks` | 1 | 344.2 |
| `lint: mergeCachePack` | 1 | 333.4 |
| `ingest/readFile: fopen+read whole file` (summed over threads) | 4281 | 159.5 |
| `lint: unreachableCheck` | 1 | 66.9 |
| `lint: lintSymbolLevelChecks` | 1 | 23.4 |
| `lint: mergeNamingLens` | 1 | **15.2** |
| ` └ naminglens: checkScopeGroups (series + confusable)` | 1 | 2.4 |
| ` └ naminglens: buildNameCorpusStats (subtoken df)` | 1 | 0.6 |

That also reconciles the regression arithmetically against the Aug-4 baseline: 422 (Aug-4) + 498
(atoms, `8acab2c`, Aug-5) + 333 (cache, `c049627`, Aug-7) + 15 (naming lens, `a63a9f1`, Aug-5) = 1268,
against ~1300 measured. The `readFile` count is the tell: 4281 ≈ 4 × 1070 files.

**Three defects, one per layer.** (1) each pack called `astQuery` itself, so the corpus was read and
parsed three times; (2) `ts_query_cursor_exec` walks the subtree once **per query**, so ~45
single-pattern specs walked every C++ file ~45 times; (3) every spec was compiled against all sixteen
linked grammars, single-threaded, in front of a fully parallel walk.

| scope (post-fix, same corpus) | calls | ms | vs pre |
| --- | ---: | ---: | ---: |
| `astQuery/worker: cursor exec + captures` (summed over threads) | 894 | 463 | 4939 → 463 |
| `astQuery/worker: tree-sitter parse` (summed over threads) | 894 | 772 | ~3× fewer parse passes |
| `astQuery: compile queries per grammar` (SERIAL pre-fix) | 1 | 628 → ~40 | present grammars only, one per thread |

**Warm medians, 7 runs each, Apple Silicon (18 hw threads), exact argv.**
Pre-fix binary is `git archive HEAD` (`d06f4db`) built in its own tree; both binaries run against the
same frozen corpora so the tool's own source edits cannot move the numbers.

```sh
# corpus_cpp = git archive d06f4db (1075 indexed files, twelve languages)
# corpus_py  = every .py in that tree, flattened (67 files)
ripwire /tmp/lane_b/corpus_cpp --lint      # 1.34 s / 7.58 s CPU  ->  0.40 s / 2.73 s CPU   (-70% wall, -64% CPU)
ripwire /tmp/lane_b/corpus_py  --lint      # 0.59 s / 0.81 s CPU  ->  0.19 s / 0.32 s CPU   (-68% wall, -60% CPU)
ripwire /tmp/lane_b/corpus_cpp --match='(goto_statement) @g'
                                           # 0.10 s / 0.53 s CPU  ->  0.09 s / 0.53 s CPU   (one group: unchanged, as designed)
ripwire /tmp/lane_b/corpus_cpp             # 0.03 s               ->  0.03 s                (map untouched)
```

**Identity obligations discharged.** `--lint` output byte-identical (`diff -q`) against the pre-fix
binary on BOTH corpora; `--lint` and the map deterministic run-to-run; both well-formed under
`xmllint --noout`; 14 lint-family gates (`lintcheck`, `lintbudgetcheck`, `lintdedupcheck`,
`lintprecisioncheck`, `lintrulescheck`, `lintscopecheck`, `atomscheck`, `cachelintcheck`,
`naminglenscheck`, `naminglocalscheck`, `namingcalibrationcheck`, `namingconsistencycheck`,
`matchcapturecheck`, `coplintcheck`) plus 20 astQuery-adjacent gates green.

**What is still on the table.** `unreachableCheck` (67 ms) runs its own fourth corpus walk with the
same crawl-order file queue; the naming lens's `getBytes` (11 ms) is a fifth read of files the walk
already had in hand. Both are small next to what was removed, and neither was touched here.

---

## 2026-08-08 — lane B3: the newline byte scan, raced three ways

`buildNewlineOffsets` (`src/ingest.cpp`) builds the per-file newline index that `lineAtByte` binary
-searches. It scanned whole file buffers **one byte at a time**. The owner called this experiment
explicitly for fun and named its ceiling in advance — the scope is well under 1% of a `--lint` run,
so no wall-clock headline was ever available. It was run with full rigour anyway, for the precedent:
this is the shape a one-kernel question should have.

**The three arms** (`bench/bench_newline_ab.cpp`, modelled on `bench_radix_ab.cpp` — alternating
order with a rotating lead, median of 9 rounds, `prof::BenchTimer` + `prof::escape` barriers):

- **(a) scalar byte loop** — the shipping loop, lifted verbatim, so the baseline is the real thing.
- **(b) libc `memchr` in a loop** — the "use others' efforts, even libc's" control. Not a straw man:
  Apple's arm64 `memchr` is hand-tuned NEON.
- **(c) `rw::findByte`** — a hand-rolled NEON/SSE2 kernel added to `src/infra/fixedStr.h` beside that
  header's existing branchless compare/hash, as a **free function**: it scans arbitrary byte spans,
  so it is not a `FixedStr` member. arm64 has no `movemask`, so the NEON arm folds the compare with
  `vshrn_n_u16(..., 4)` into a 64-bit word carrying 4 mask bits per byte and takes `ctz`; SSE2 uses
  `_mm_movemask_epi8`. Scalar fallback on other arches behind the same interface.

**16.08 MiB of real repo bytes** (227 files, 479,713 newlines; deterministic corpus — sorted paths,
no timestamps, `.git`/build trees excluded). Both compiler settings measured, because `build/` ships
`-O2 -mcpu=apple-m1` while `build_prof/` uses `-O3 -march=native`:

| arm | ms (`-O2 -mcpu=apple-m1`) | GB/s | ms (`-O3 -march=native`) | GB/s | vs scalar |
| --- | ---: | ---: | ---: | ---: | ---: |
| (a) scalar byte loop | 7.05 | 2.39 | 6.32 | 2.67 | 1.00x |
| (b) libc `memchr` | 4.79 | 3.52 | 4.49 | 3.75 | ~1.45x |
| (c) `rw::findByte` | **3.38** | **4.99** | **3.23** | **5.22** | **~2.05x** |

**The hand-rolled kernel shipped**, beating libc `memchr` by ~1.4x and the byte loop by ~2.05x. That
outcome was not assumed: arm (b) existed precisely so that "libc already wins, ship `memchr`" could
be the answer, and it would have been reported as the equal result. All three ratios held across
corpus sizes from 1 MiB (cache-resident) to 64 MiB (DRAM), so this is a kernel win, not a cache
artifact — an early hypothesis that cache residency explained the in-situ gap was **tested and
rejected** (1 MiB widens the margin only 2.09x → 2.36x).

**In situ, `--lint` on a frozen 209 MB corpus** — two `RIPWIRE_PROFILE` binaries built from the two
source states and run **interleaved**, 9 rounds each, warm:

| `strings: buildNewlineOffsets` | median | min | calls |
| --- | ---: | ---: | ---: |
| before | 26.1 ms | 12.7 ms | 1847 |
| after | **7.8 ms** | **7.2 ms** | 1847 |

Read the **minimum** as the signal (1.76x) and the median gap (3.35x) as scheduler noise on a 209 MB
corpus: the min-to-min ratio is the one that reconciles with the isolated bench's ~2.05x. The first
"before" reading taken was 64.9 ms — a **cold page cache** on a freshly extracted corpus, discarded
once the interleaved warm A/B was run. It is recorded here because it is exactly the trap this
methodology exists to catch, and a single un-interleaved sample would have published an 8x claim.

**Wall-clock `--lint`, same corpus, interleaved, 9 rounds:** 437.2 ms → 434.1 ms median (min 427.4 →
426.5). That is inside the noise band, and it is the honest headline: the scope was ~1.2% of the run
before and ~0.3% after, so **the tool is not measurably faster and this change should not be sold as
if it were.** What it buys is a correct, tested, reusable primitive where a byte loop used to be.

**Identity obligations discharged.** `rw::findByte` is **exact**, so determinism is untouched by
construction, not merely by measurement — and the bench asserts it rather than asserting it in prose:
all three arms must produce **identical offset vectors** over 14 edge fixtures **and** all 227 corpus
files before a single timing number is printed. The fixtures are where a vectorised scan goes wrong —
empty span, needle at position 0, no trailing newline, spans of 15/16/17 bytes, a match on the last
byte of a vector and the first byte of the tail, 64 adjacent newlines, and **CRLF**: `'\r'` is not a
line break here and never was, and that fixture is what proves every arm ignores it identically.
Downstream, `--lint` and the map are **byte-identical** (sha256) against the pre-change binary on the
frozen corpus; both deterministic run-to-run and well-formed under `xmllint --noout`; `lintcheck`,
`lintrulescheck`, `matchcapturecheck`, `naminglenscheck`, `manifestcheck` and `deckcheck` green;
`--edit-check=buildNewlineOffsets` reports `status="unchanged"`, `incompatible="0"`.
## 2026-08-08 — `--lint`: the fourth and fifth corpus reads folded into the same walk (lane B2)

**Ledger, not a gate.** No budget or threshold added, here or in CI. This is the follow-up to the
entry above, which closed its own round by naming exactly what it had left behind — `unreachableCheck`
and the naming lens's `getBytes`. Both are now gone, and for the same reason the first three were:
the cost was defect-shaped (the same file read and parsed again to ask one more question about a tree
that had just been thrown away), not a tradeoff, and the output is byte-identical.

**Method.** Profile build (`cmake -S . -B prof -DRIPWIRE_PROFILE=ON`), warm, both binaries run against
the SAME frozen corpus so the tool's own source edits cannot move the numbers. The pre binary is the
`prof/` build of the parent commit (`9305487`, lane B's merge), snapshotted before this round's first
edit; the corpus is `git archive 9305487` (1460 files, 1075 indexed, twelve languages).

| main-thread scope, `--lint` on the frozen corpus | pre (ms) | post (ms) |
| --- | ---: | ---: |
| `lint: astQueryGrouped` (built-in + atoms + cache → **+ unreachable**) | 333.4 | 334.4 |
| `lint: unreachableCheck` | 103.3 | — |
| `lint: mergeUnreachable` (merge only; the walk rode the shared pass) | — | 0.0 |
| `lint: lintSymbolLevelChecks` | 45.1 | 37.7 |
| `lint: mergeNamingLens` | 19.5 | 6.3 |
| ` └ naminglens: getBytes whole-file read` | 12.9 (907 calls) | **— (0 calls)** |
| `lint: mergeAtomsPack` | 1.8 | 1.8 |
| `lint: mergeCachePack` | 0.4 | 0.4 |
| **sum** | **503.5** | **380.6** |

`ingest/readFile: fopen+read whole file` (summed over threads) falls **2335 → 1168 calls**, 102.6 →
70.8 ms. Counting the two `getBytes` memos, which open files directly and so never appeared in that
row, `--lint` went from roughly four thousand whole-file opens to 1168 — one per file it looks at.

Two rows deserve reading twice. `astQueryGrouped` costs ~1 ms MORE, not less: it now parses 1050 files
where it parsed 991, because a walk group wants files whose grammar compiled no spec and the
`byGrammar`-miss `continue` had been skipping them. Those 59 files were being parsed anyway — by the
separate pool, on top of everything else. And `lintSymbolLevelChecks` drops 7.4 ms without being the
scope anyone set out to fix: it kept the second of the two near-identical `getBytes` memos, and it was
handed the same retained bytes.

**Warm wall clock, 6 runs each, Apple Silicon, same frozen corpus, exact argv.**

```sh
ripwire <corpus_cpp> --lint     # 0.51-0.52 s  ->  0.42-0.43 s   (-17.5%, spread <= 10 ms either side)
```

On this repo's own tree, `--lint` goes 0.71-0.73 s / 3.1-3.2 s CPU → 0.61-0.63 s / 2.2-2.6 s CPU.

**What it cost.** Retaining the corpus text is opt-in (`astQueryGrouped`'s `keptBytesOut`) because it
is not free: peak RSS **182.5 → 192.7 MB, +5.6%**, one corpus of source held for the length of the
lint block. That is the whole trade — ~7% of the wall for ~6% of the peak — and it is only worth it
because BOTH downstream passes use the same buffer. Wiring only one of them would have paid the full
memory cost for half the benefit.

**Identity obligations discharged.** `--lint` byte-identical (`diff -q`) against the pre binary on a
1460-file C++ corpus AND a mixed Python/TypeScript corpus, stderr empty on every run; `--ensemble`
(the other `appendNamingFindings` caller, which passes no retained bytes) byte-identical too; `--lint`
and the map deterministic run-to-run and well-formed under `xmllint --noout`; the concurrent write
into `keptBytesOut` verified under ASan+UBSan (`-fno-sanitize-recover=all`, committed LSan
suppressions) — clean on both corpora, output still identical. 20 gates green: lane B's 14
lint-family set plus `unreachablecheck`, `deadcheck`, `deadfiltercheck`, `deadprecisioncheck`,
`g1freshcheck`, `manifestcheck`.

**What is still on the table.** The two `getBytes` memos are still two — `lintSymbolLevelChecks`
(src/main.cpp) and `namingLensChecks` (src/naminglens.h) carry near-identical read-and-memoize
lambdas, and they now also carry near-identical pre-read guards. Consolidating them into one shared
type would delete a real clone, but it is a refactor of pre-existing code rather than part of this
fold, so it was left alone deliberately.

---

## 2026-08-29 — main.cpp verb-family split: build-time ledger row (not a gate)

The split moved 13,258 lines of main.cpp into eight `src/verbs_*.h` sections of the same translation
unit (16,901 → 3,643 lines in main.cpp itself; RIPWIRE_MAIN_TU-guarded, unnamed-namespace-reopening
includes), so the compiler still sees one TU and the cost was expected to hold still. It did:

| build | cold `cmake --build build --clean-first -j` wall | machine |
| --- | --- | --- |
| before (28f82b1) | 43.68 s | this Apple Silicon dev box, AppleClang 21, dev build (no build type) |
| after (the split) | 42.56 s | same box, same session |

Ledger row only, per the no-perf-budget house rule: the numbers are recorded so drift is visible,
never asserted by CI. Behavior over the whole flag surface is pinned instead by test/argvdiffcheck.sh
against the pre-split binary (byte-identical stdout/stderr/exit on every vector; the only reported
diffs are the two disclosed non-deterministic surfaces — the `--version` sha stamp and `--run-trace`'s
measured `duration_ms`).

---

## 2026-08-29 — ingest.cpp section split: build-time ledger row (not a gate)

The follow-on to the main.cpp row above, same mechanism: 11,730 lines of ingest.cpp moved into nine
`src/ingest_*.h` sections of the same translation unit (13,799 → 2,069 lines in ingest.cpp itself;
RIPWIRE_INGEST_TU-guarded — eight sections reopen the unnamed namespace, the --match/--lint tail
reopens `namespace rw` alone), so the compiler still sees one TU and the cost was expected to hold
still. It did:

| build | cold `cmake --build build --clean-first -j 6` wall | machine |
| --- | --- | --- |
| before (c267a4b) | 45.74 s | this Apple Silicon dev box, AppleClang 21, dev build (no build type) |
| after (the split) | 43.82 s | same box, same session |

Ledger row only, per the no-perf-budget house rule. Behavior is pinned the same way as the main.cpp
split: test/argvdiffcheck.sh against the pre-split c267a4b binary, byte-identical on every vector
except the two disclosed non-deterministic surfaces (`--version` sha stamp, `--run-trace`
`duration_ms`), plus the index-side proofs the main.cpp split never needed — self-map determinism,
warm-vs-`--no-cache` byte equality, and xmllint, all run after every one of the nine stages.

---

## 2026-08-29 — the `--grep` fast path (P4.1): where a warm literal grep actually spends its time

Ledger row only, per the no-perf-budget house rule: the numbers are recorded so drift is visible, never
asserted by CI. What IS asserted is the equivalence — `test/grepfastcheck.sh` (13 `--grep` option vectors,
cold == warm == warm, `--no-cache` parity, two staleness arms, and a byte-compare against a pre-change
reference binary) plus `test/argvdiffcheck.sh` at `RIPWIRE_BASE=<the d5e7d94 binary>`, which reports
608 of 610 argv vectors byte-identical (the two diffs are the disclosed `--version` sha stamp).

### The premise that was wrong

The round's plan proposed skipping "ranking / bundle assembly" for a plain literal `--grep`. A phase
breakdown says `--grep` does neither: it never ranks, and it assembles no bundle. Its cost is the
pipeline it sits behind plus its own scan. Measured warm on a 4,175-tracked-file mixed C++/ObjC/Metal
corpus (`-DRIPWIRE_PROFILE=ON`, this Apple Silicon dev box), one hit-bearing literal:

| phase | before | share | what it is |
| --- | --- | --- | --- |
| `ingest` (crawl + cache load + doc post-pass + model) | 93 ms | 41% | the index, warm |
| `buildGraph` | 40 ms | 18% | reference resolution + CSR |
| `grep/2` span tiers | **49 ms** | **21%** | tree-sitter re-parse of every hit file, to classify comment/string spans |
| `grep/1` scan | 34 ms | 15% | the parallel literal scan itself |
| `grep/3` aux + `grep/4` emit | 11 ms | 5% | unindexed-ext scan, window, enrichment, serialization |

The verb's own scan was never the problem. The two costs worth taking were the span-tier re-parse — larger
than `buildGraph`, and repeated verbatim on every later grep of the same unchanged file — and the fact
that `buildGraph` and the scan ran back to back although neither reads the other's output.

### The two changes

1. **Span-tier memo** (`src/ingest_astquery.h`). `SpanTierMap` is a pure function of (file bytes, grammar),
   so it is cached per file under the shared cache-dir ladder, stat-gated by the ingest cache's own
   `(sizeBytes, mtimeNs)` + racy-mtime rule, with the path stored in the blob so a filename-hash collision
   cannot alias two files. A hit skips the read as well as the parse. `--no-cache` disables it.
   A measured size floor (32 KiB) keeps the blob count down: source files at or above it are 12.9% of this
   corpus's file count but 86.1% of its bytes, so the floor keeps essentially all of the saving.
2. **Scan/graph overlap** (`src/verbs_grep.h`, `src/main.cpp`). The three scan phases move into
   `collectGrepScanPhases`, started on one thread while `buildGraph` runs on another, and joined before
   anything is emitted. Only when the dispatch-precedence table says `--grep` is the verb that will answer.

### Result

Three arms — the pre-change binary, this one, and `rg` — run back to back inside each repetition, so a
load spike moves all three together and only the ratio survives. 11 repetitions per query, warm cache,
**medians not bests**, on the 4,175-tracked-file corpus (1,674 source files / 93.3 MB, plus 1,961
markdown; 116,620 files on disk) at machine load ~7:

| query | hits | before | after | `rg` | before/rg | after/rg |
| --- | --- | --- | --- | --- | --- | --- |
| a rare identifier | 54 | 253.8 ms | 169.6 ms | 45.8 ms | 5.55x | 3.71x |
| a long unique name | 3 | 204.1 ms | 168.8 ms | 45.1 ms | 4.53x | 3.74x |
| absent identifier | 0 | 205.5 ms | 174.1 ms | 45.3 ms | 4.54x | 3.84x |
| a bucketing helper | 32 | 238.0 ms | 167.9 ms | 44.1 ms | 5.40x | 3.81x |
| a common word | 3745 | 260.8 ms | 177.4 ms | 52.6 ms | 4.96x | 3.38x |
| absent type name | 0 | 205.4 ms | 173.3 ms | 45.8 ms | 4.49x | 3.79x |
| **median** | | | | | **4.75x** | **3.77x** |

A 1.3x speed-up — not the 2x-of-`rg` the round targeted. The honest reason it stops there is the phase
table above: after both changes the answer is ~93 ms of `ingest` plus ~47 ms of scan work overlapped with
a ~40 ms `buildGraph`, and every one of those milliseconds feeds something the answer prints. (An
intermediate arm with the memo but not the overlap measured 200 ms / 4.4x on the hit-bearing queries.)

**Why `buildGraph` is not simply skipped for `--grep`.** It is needed for exactly one thing — `callers=` on
the `<enc>` rows — and a targeted "resolve only these few names" shortcut is *not* sound: fn-pointer and
FFI binding edges resolve through a variable's name, not the target's, so a name-filtered pass would
under-count callers on precisely the symbols the graph is most useful for. An under-count printed without
a floor marker is the kind of quiet wrongness this repo treats as worse than being slow, so the graph
stays, and it is hidden behind the scan instead.

### Reproduce

```sh
cmake -S . -B build_prof -DRIPWIRE_PROFILE=ON && cmake --build build_prof -j
build_prof/ripwire <repo> --grep=<literal> >/dev/null      # run twice; the second is warm
# the grep/1..grep/4 rows in the stderr #PROF_TSV block are the phase split above
```
Both arms must be timed alternately against the same warm cache on the same box: the phases are all
CPU-bound, so a busy machine moves both arms together and only the ratio survives.

## 2026-08-30 — `redactSecrets` was quadratic in LINE length: the `--expand` pathological bundle

**Ledger row, not a gate.** Per the house rule these numbers are a record, never a red-CI threshold. The
gate that landed with the fix, `test/redactfixcheck.sh`, asserts BEHAVIOUR only (the memo caches must not
leak across a line or a run boundary); a revert would make it slow, not red.

### The symptom

The SWE-Explore harness (`bench/swex/run_swex.py`) guards its extent-resolution `--expand` calls with a
90 s / 30 s timeout, and it existed for exactly one shape: symbols ranked inside vendored, minified
bundles. On `babel__babel-13928` those are `.yarn/releases/yarn-3.1.0.cjs` — **2,196,921 bytes across 768
lines**, so a "line" averages 2.9 KB and the longest are far larger. Those were the only timeouts the
whole 68-instance run ever hit.

### Reproduce

```sh
SNAP=bench/external/swex/snapshots/babel__babel-13928
ripwire "$SNAP" >/dev/null                                            # warm the index once (~2.7 s)
time ripwire "$SNAP" '--expand=.yarn/releases/yarn-3.1.0.cjs:O3e'     # ONE selector
```

A self-contained version needing no benchmark data (this is the row measured below, and the same fixture
`test/redactfixcheck.sh` generates — a 20 KB single line inside a docstring):

```sh
python3 - "$T" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "memofix.py"
p.write_text('def f():\n    """\n    token: ' + "z9" * 10000 + ' ' + 'J' * 32 + '\n    """\n    return 0\n')
PY
time ripwire "$T" --expand=f --no-cache
```

### Where the time went

`sample(1)` on the running process, twice (12 s in and 75 s in), both ~100% in one place:

| top of stack | share |
| --- | --- |
| `rw::redactdetail::lineNamesCredential` | 26% |
| `std::basic_regex::__search` + its `__state` copy/alloc churn | 74% |
| everything else (ingest, graph, serialize) | ~0% |

Called from `runDefaultMap` → `renderWholeFiles` → `redactSecrets`. Note *what* was being redacted: the
whole-file candidate `chooseExpandServe` prices against the bundle and — at 2.1 MB against a 2,110-byte
bundle — always discards. The tool spent all of that time redacting output nobody would ever see.

### The cause — three costs, all O(line) or O(run), all paid per POSITION

`redactSecrets` sweeps left to right and, at each cursor, tries the rules the first-byte mask admits. The
`GenericAssigned` rule (`[A-Za-z0-9+/=_\-]{32,}`, the low-precision shape behind the per-line credential
keyword gate) made every one of those steps superlinear:

1. `enclosingLine( in, i )` walked to both boundaries of the enclosing line — O(lineLength).
2. `lineNamesCredential` then rescanned that whole line for one of 12 keywords — O(lineLength).
3. The rule's own `regex_search( match_continuous )` is a bare greedy class run with nothing after it, so
   it consumed the **maximal run from the cursor** — O(runLength) — and then, if the gate declined, the
   sweep advanced ONE byte and re-consumed the same run minus one character. O(runLength²) per run.

On ordinary source, lines are ~100 bytes and this is invisible; that is why it survived. On a minified
bundle it is quadratic in a number measured in hundreds of kilobytes.

### The fix

All three values are functions of the *line* or the *run* the cursor is in, not of the cursor — so each is
computed once and reused for as long as it stays true (`redactdetail::LineGate`, `redactdetail::ClassRun`,
both held in a per-call `SweepState`). The `GenericAssigned` match itself stops going through the regex
entirely: its match at the cursor IS the maximal class run from the cursor, so it becomes a subtraction
against a run end found once. The sweep is now linear in the input.

This is pure memoization of already position-independent values, so it is an **output no-op**: verified
byte-identical (stdout, stderr and exit code) against the pre-change binary over 24 corpora × 5 verb
shapes = 120 invocations, the 24 including 20 external SWE-Explore snapshots across 9 languages.

### Result

| workload | before | after | ratio |
| --- | --- | --- | --- |
| `--expand` on a 20 KB single line (the self-contained fixture above) | 23.02 s | 0.017 s | **~1350x** |
| `--expand`, ONE selector in babel's 2.1 MB / 768-line yarn bundle | did not complete | 0.46 s warm (1.39 s cold) | — |
| `--expand`, the harness's own 3-selector chunk on that bundle | did not complete | 0.47 s, 11 bodies | — |

The babel rows have no honest "before" number, because the pre-change binary never produced one. It was
killed by the harness at its 90 s guard; a manual `timeout 200` run, alone on the box, burned 196.7 s of
user CPU and was still going when the timeout fired; and an unattended run left to finish was killed at **1,343.9 s of user CPU**
(23 min 27 s wall) with a still-empty output file. "Did not complete" is the measurement; 196.7 s is the only clean lower
bound worth quoting.

The four redaction gates (`redactcheck`, `jsonredactcheck`, `mcpredactcheck`, `sigredactcheck`) pass
unchanged before and after, and `redactfixcheck.sh` passes against BOTH binaries — the old one in 47.5 s,
the new one in 0.2 s. Same verdicts, same contract; only the cost is gone.

## 2026-09-03 — card A3 freshness disclosure: what the per-request re-validation actually costs

LEDGER row, never a gate (the no-perf-budget rule). Registered band: docs/EVALS.md, "Freshness disclosure
on a cached answer (card A3)", band 1 — the re-validation under 5% of warm wall-clock on a ~1500-file tree.

### Instrument and argv

`RIPWIRE_MCP_TIMINGS=1` makes `--mcp` print one stderr line per handled request —
`ripwire-timing verb=<v> wall_ms=<f> rebuilt=<0|1>` — which is what separates a warm reuse from a rebuild
without guessing. One long-lived server per arm over the SAME tree, driven through a FIFO:

```
RIPWIRE_MCP_TIMINGS=1 TMPDIR=<per-arm> <bin> --mcp < fifo
  {"jsonrpc":"2.0","id":1,"method":"initialize"}
  {"jsonrpc":"2.0","id":N,"method":"tools/call","params":{"name":"find_symbol",
     "arguments":{"path":"<private objc++ tree>","symbol":"printf"}}}
```

12 warm requests, then 6 more each preceded by `touch <root>/log/log.cpp` (an indexed file, content
untouched) to force a rebuild. Corpus: a private ~2400-file ObjC++/Metal tree (not reproducible publicly), **`files=2377`** as this binary
indexes it (the band said ~1500; the tree that was available is larger, and the count is reported rather
than the target). Arms alternated HEAD / base `3eec040` five times; the table is the median of the five
per-trial p50s. Apple Silicon, warm page cache, machine otherwise idle.

### Result

| request class | base `3eec040` | HEAD (with `_fresh`) | delta |
| --- | --- | --- | --- |
| warm reuse (`rebuilt=0`) | 11.17 ms | 10.52 ms | **−0.65 ms (−5.8%)** |
| rebuild (`rebuilt=1`) | 499.15 ms | 479.37 ms | **−19.78 ms (−4.0%)** |

Both point estimates are NEGATIVE — the instrumented binary measured faster — which is the honest way of
saying the added cost is below this machine's noise floor. The base arm's own five trials spread 9.94 →
17.28 ms warm and 460 → 515 ms rebuild, wider than either delta. Band 1 is met, and it is met with a
measurement that cannot resolve the cost, not with a cost of zero.

That is what the code predicts. `mcpStale()` is byte-identical to base (the count is a separate function
the hot path never calls), so the warm path adds one 15-byte `std::string`. The rebuild path adds one full
stat sweep plus two O(n log n) fingerprint sorts and one linear walk — against a rebuild that re-crawls,
re-hashes and re-ranks 2377 files.

### The number the band was really asking for

Band 1 assumed a NEW per-query check and asked what fraction of the warm request it would be. The
inventory found the check already existed, so the interesting quantity is the other one: how much of a warm
request IS the re-validation. Same instrument, two tree sizes, same verb:

| tree | indexed files | warm p50 |
| --- | --- | --- |
| `private tree/Metal` | 120 | 0.51 ms |
| `private tree` | 2377 | 10.52 ms |

**≈4.4 µs per indexed file** ( (10.52 − 0.51) / (2377 − 120) ), which puts ~95% of a 2377-file warm request
in the freshness sweep. A warm MCP request on a tree this size is very nearly nothing but the re-validation
the server was already doing silently — the disclosure is a report on work already paid for, and that is
the finding, not a footnote to it. It also sets the price of ever closing the same-(mtime,size) residual:
the whole-tree re-read `mcpStale`'s comment prices at ~13x lands on top of a request that is already
sweep-bound.

## 2026-09-03 — card A3 follow-up: what the ctime discriminator costs, and what re-hashing would have cost

LEDGER row, never a gate (the no-perf-budget rule). Registered band and rejection rule: docs/EVALS.md,
"Closing the same-`(mtime, size)` warm-path residual (card A3 follow-up)", band 2 — a settled warm run must
add **zero file reads**, and a warm delta landing outside the base arm's own trial spread in the slower
direction REJECTS the fix in favour of the disclosure-only refusal.

### Instrument and argv

Three binaries, one measurement harness, wall-clock around the whole process (`time.perf_counter` in a
python driver, stdout to `/dev/null`), each arm with its own `TMPDIR` so the cache blobs never collide:

| arm | what it is |
| --- | --- |
| `base` | `1c6fdf4` (this lane's fork point), built from `git archive` into a scratch tree |
| `head` | this lane's HEAD — `(size, mtime, ctime)` |
| `hashall` | **option (a) proper**: `head` with `statMatches` forced `false`, so every stat-equal file is read + content-hashed and its cached FACTS are still reused. Prices the read+hash, not a reparse. NOT COMMITTED — a measurement arm, patched in a scratch copy of the tree. |

```
TMPDIR=<per-arm> <bin> /Users/qgames/AppDevelopLocal/project2/rw-n4-b --exclude=bench/external   # files=1505
TMPDIR=<per-arm> <bin> <corpora>/duckdb                                                          # files=5123
```

Each arm primed with two runs before any trial. **Nine trials, and the arm order ROTATES by trial**
(`base head hashall` / `head hashall base` / `hashall base head` / …). That rotation is the measurement:
a first pass with a FIXED order — base always first, head always second — reported head +19.9 ms on duckdb,
outside base's spread and therefore a REJECT under the registered rule. It was position, not code: the
within-trial ramp penalises whichever arm runs second. The fixed-order numbers are discarded and the
rotation is what is reported. Apple Silicon, warm page cache, machine otherwise idle.

### Result — the fix is free, and the alternative is not

| tree | arm | median | min | max |
| --- | --- | --- | --- | --- |
| ripwire, `files=1505` | `base` | 62.4 ms | 59.8 | 75.1 |
| | **`head`** | **61.3 ms** | 59.4 | 75.1 |
| | `hashall` (option (a)) | 75.2 ms | 71.7 | 83.8 |
| duckdb, `files=5123` | `base` | 219.4 ms | 198.5 | 342.9 |
| | **`head`** | **212.8 ms** | 197.2 | 269.0 |
| | `hashall` (option (a)) | 261.4 ms | 232.3 | 366.9 |

* **`head` vs `base`: −1.1 ms (ripwire) and −6.6 ms (duckdb).** Both point estimates are NEGATIVE and both
  sit well inside the base arm's own trial spread — the honest reading is that one integer comparison per
  file, on a `struct stat` the loop had already filled, does not resolve against this machine's noise.
  Band 2 is met and the rejection rule is not triggered.
* **`hashall` vs `head`: +13.9 ms (+22.7%) and +48.6 ms (+22.8%).** Strikingly consistent across a 3.4×
  difference in tree size, because it is the same thing both times: re-reading and re-hashing every file in
  the tree on every invocation. That is what option (a) costs to buy exactly what one already-taken `stat`
  field gives for nothing.
* `RIPWIRE_CACHE_STATS=1` on a settled tree reports `reparsed=0 reused=1505 files=1505` and
  `reparsed=0 reused=5123 files=5123` for **all three** arms — the arms differ only in whether they READ,
  never in what they conclude, which is what makes the wall-clock gap readable as the read cost.

### What this does NOT say

It does not say option (a) is unaffordable in absolute terms: `hashall` never reparses (the hash agrees), so
its penalty is ~23% of a warm run and not the 1.1–2.3 s cold parse. It says option (a) is **dominated** —
it costs ~23% of every warm invocation, and it still closes the residual only for files it can READ, while
the recorded ctime closes it for free and keeps the cached parse of a file that has become unreadable
(`statgatecheck` (e)). The A3 ledger's ~13× figure for a whole-tree re-read on the MCP path stands
unchallenged; this row prices the same idea on the CLI, where the facts-reuse makes it far cheaper than 13×
and still the wrong trade.
