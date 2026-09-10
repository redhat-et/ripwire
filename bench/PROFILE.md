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
TMPDIR=<per-arm> <bin> <ripwire-checkout> --exclude=bench/external                                 # files=1505
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

---

## 2026-09-03 — the `.gitignore` ignore probe: what one `git ls-files` per root costs, and what it buys

A LEDGER ROW, never a gate (the standing no-perf-budget-gates rule). Plain build at `4f6e601 + this
lane`, Apple Silicon, warm page cache, `--no-cache` for every cold number and the second run of an
auto-cached pair for every warm one. The corpora are the four D4 trees plus this repository's own root.

**What the probe itself costs.** One `git -C <root> -c core.quotepath=false ls-files --others
--ignored --exclude-standard --directory -z` per root, once, before the walk:

| tree | ignored entries returned | probe wall time (median of 3) |
| --- | ---: | ---: |
| ugrep `550599a6` | 0 | 0.020 s |
| rocksdb `0e2801ac` | 0 | 0.030 s |
| duckdb `19864453` | 0 | 0.150 s |
| this repository's root (12 top-level ignored entries + 3 checkouts under `bench/external/`) | 4 | 0.032 s |

`--directory` is what keeps that column flat: a wholly-ignored directory is ONE entry and ONE prune,
never an enumeration, so a 12,000-file checkout under `bench/external/` costs the same as an empty one.
Without it the same probe on this repository returns 3,962 entries and takes 0.10 s — still cheap, but
it scales with the ignored population instead of with the number of ignored ROOTS, and it cannot count
the files inside a nested checkout anyway (git stops at a nested `.git`), so the exact-count it appears
to buy is a floor, not a total.

**What it buys, on this repository's root with no `--exclude`.** The dev box's 158,202-file population
could not be reproduced in this lane's worktree (the `bench/external/swex/snapshots` tranche had been
moved out of the tree for the round), so the row below is a REBUILT stand-in: the three D4 checkouts
copied into the (gitignored) `bench/external/`, giving 18,995 files on disk and 8,674 crawlable ones.
The shape is the one the registration describes; the magnitude is smaller.

| `ripwire . <args>` | `files=` | cold | warm |
| --- | ---: | ---: | ---: |
| `--no-ignore` (the pre-2026-09-03 walk) | 8,674 | 2.81 s | 0.63 s |
| default (ignore rules honoured) | **1,522** | **0.52 s** | **0.10 s** |
| `--exclude=bench/external` (the workaround it replaces) | 1,522 | 0.41 s | 0.10 s |

**Re-measured on the full tree (orchestrator, merged round-5 tree, snapshots restored).** The stand-in
row above is kept because it is what the lane's commits were measured against; this is the real
population, `ripwire <repo root> --skipped`, one cold run per arm with a private `TMPDIR`:

| `ripwire <repo root> <args>` | `indexed=` | cold |
| --- | ---: | ---: |
| `--no-ignore` | 158,208 | 70.80 s |
| default (ignore rules honoured) | **1,682** | **1.44 s** |

One `git ls-files --directory` probe and one pruned directory turn a 70.8 s cold map into a 1.44 s one.

The default and the hand-written `--exclude` agree to the file, so the flag that every gate and every
agent invocation had to remember is now the tool's own behaviour, and the 0.032 s probe replaces 2.3 s
of crawling and parsing on a cold run.

**One cost this does NOT remove, stated because it is real.** Alternating modes leaves a SUPERSET blob
behind: a `--no-ignore` run writes 8,674 file records, the next default run reads that blob, finds
nothing dirty and never rewrites it, so a default warm run after a `--no-ignore` run costs 0.18-0.19 s
instead of 0.10 s until something invalidates the blob. Correctness is unaffected — the blob is keyed
per FILE, so a default run can only ever read back the files it actually crawled (`gitignorecheck`
arm 10 pins exactly that) — and this is the same shape `--exclude` has always had, which is why the
ignore mode is deliberately NOT part of the cache key.

---

## 2026-09-03 — the offset-table cache blob (v15): what a subset configuration used to pay, and what it pays now

LEDGER row, never a gate (the no-perf-budget rule). The registered bands are in docs/EVALS.md, "The
auto-cache key ignores `--exclude`" — bands (1)–(3) from the original registration and (6)–(8) from the
retry design. Band (6) (full-battery wall within 1.2× of base under the same `-j`) is measured on the
integration tree after merge, not here.

### Instrument and argv

Two binaries and one synthetic corpus, wall-clock around the whole process (`/usr/bin/time -p`, stdout to
`/dev/null`), each arm with its own `XDG_CACHE_HOME` (and `TMPDIR` unset) so the blobs never collide:

| arm | what it is |
| --- | --- |
| `base` | `d8fa59c` (this lane's fork point) — kCacheVersion 14, one whole-file blob per (root, class) |
| `head` | this lane's HEAD — kCacheVersion 15, the offset table + carry-over save |

The corpus is **31,000 generated C++ translation units** — 1,000 under `keep/` and 30,000 under `ext/` —
each a namespace with a struct, a method with one branch, and two free functions. Synthetic on purpose:
the effect under test is the ratio between a configuration's own file count and the blob's, and the real
tree that exhibits it (`bench/external`, 158,202 files) cannot be crawled on this machine without the 2 GiB
cache cap becoming the confound the reverted key change already died of. `--exclude=ext` is the narrow
configuration (1,000 files); the bare run is the wide one (31,000).

```
XDG_CACHE_HOME=<per-arm> <bin> <corpus>                  # wide,   files=31000
XDG_CACHE_HOME=<per-arm> <bin> <corpus> --exclude=ext    # narrow, files=1000
```

Five trials per timed cell after a priming run, machine otherwise idle, Apple Silicon, warm page cache.
**The arms were NOT rotated within a trial** (each arm's whole sequence ran before the next). That is a
weaker protocol than the card-A3 row above, and it is stated rather than hidden — it is adequate here only
because the two effects being read are 6–9× and 3.6×, an order of magnitude outside the within-trial ramp
that made rotation load-bearing there. The one cell where it would matter (`wide warm`, a ~0.1 s gap on a
0.3–0.4 s run) is reported as NOT RESOLVED below.

### Result

| measurement | `base` (v14) | **`head`** (v15) |
| --- | --- | --- |
| superset blob, 31,000 files | 30,147,173 B | **31,139,189 B** (+3.3%) |
| wide warm, 31,000 files (5 trials) | 0.39 0.40 0.41 0.42 0.43 s | 0.29 0.30 0.30 0.33 0.41 s |
| **narrow warm over the superset blob** (5 trials) | 0.06 0.07 0.07 0.08 0.09 s | **0.01 0.01 0.01 0.01 0.01 s** |
| narrow warm over its OWN `--cache=PATH` blob | — | 0.01 0.01 0.01 0.01 0.01 s |
| blob after a DIRTY narrow run | **951,814 B** (truncated to that run's 1,001 files) | **31,139,432 B** (extended) |
| the wide run that follows it | `reparsed=30000`, 0.96 s | **`reparsed=0`, 0.27 s** |
| a DIRTY narrow run's own wall (3 trials) | 0.02 s | 0.13 0.15 0.40 s |

* **Band (1)/(7) — the thrash is gone, and it was never about milliseconds.** Under `base`, a narrow run
  that is DIRTY rewrites the shared blob with its own 1,001 files and the other 30,000 records cease to
  exist; the next wide run cold-parses all of them (`reparsed=30000`, 0.96 s). Under `head` the same
  sequence leaves `reparsed=0` and 0.27 s. This row, not the load time, is the reason the format changed.
* **Band (2) — a subset run no longer pays for the superset.** 0.06–0.09 s → 0.01 s, and the auto-cache
  superset blob is now indistinguishable from the narrow configuration's own 983,619 B `--cache=PATH`
  blob (0.01 s both). The registered band was "within 2×"; measured ratio is 1.0–2.0× at 10 ms
  granularity, which is the resolution floor of this instrument rather than a difference.
* **The cost, stated plainly: +3.3% blob and a carry-over copy on a dirty subset save.** The table is
  32 B per file (31,000 × 32 = 992,000 B, the whole of the +992,016 B). A dirty narrow run must copy the
  30,000 records it did not crawl — ~30 MB read + rewritten — and that takes 0.13–0.40 s where `base`
  took 0.02 s. That is the trade, and it is the right way round: `base` "saved" 0.1–0.4 s by destroying
  work that then cost 0.96 s to redo, once per configuration switch, forever.
* **`wide warm` is NOT RESOLVED.** `head` is nominally ~0.1 s faster, but the arms were not rotated and
  `head`'s own spread (0.29–0.41) overlaps `base`'s (0.39–0.43). No claim is made in either direction;
  the wide path reads the same bytes it always did, in one coalesced pread instead of one `readFile`.

### Reproduce

```
git archive d8fa59c | tar -x -C <scratch>/base && cmake -S <scratch>/base -B <scratch>/base/build \
  && cmake --build <scratch>/base/build -j 6
python3 -c "…"                      # 1000 keep/ + 30000 ext/ units, template in this section's prose
for arm in base head; do
  X=<scratch>/xdg_$arm; rm -rf $X; mkdir -p $X/ripwire
  env -u TMPDIR XDG_CACHE_HOME=$X $BIN <corpus> >/dev/null            # prime the superset blob
  env -u TMPDIR XDG_CACHE_HOME=$X $BIN <corpus> --exclude=ext         # the narrow arm
  echo 'int knew( int a ) { return a + 7; }' > <corpus>/keep/knew.cpp # make it DIRTY
  env -u TMPDIR XDG_CACHE_HOME=$X RIPWIRE_CACHE_STATS=1 $BIN <corpus> --exclude=ext
  env -u TMPDIR XDG_CACHE_HOME=$X RIPWIRE_CACHE_STATS=1 $BIN <corpus>   # reparsed= is the whole story
done
```

Name the subtree `ext/`, not `vendor/` — the crawl's taxonomy filter skips a directory called `vendor`
outright, so a corpus built under that name silently measures 1,000 files in both arms.

## 2026-09-09 — the super-linear warm `--grep` floor: one stage, one operation, 143 s of 154 s on llvm-project

LEDGER row, never a gate (the no-perf-budget rule). The correctness gate this round landed is
`test/chaconecheck.sh`; it asserts sets, never seconds. The question came from the tgrep head-to-head
(docs/EVALS.md, "Head-to-head vs tgrep"): warm `--grep` cost 40 µs/file at 2,240 and 15,865 files and
938 µs/file at 182,555, and the decisive experiment named there was "stub the graph build, re-time".

### Instrument and argv

One binary, `cmake -S . -B build_prof -DRIPWIRE_PROFILE=ON` (plain flags otherwise — never Release, `NDEBUG`
compiles `DEGRADED_PATH_ALERT` and the profiler out). This round first added the scopes the ingest path
lacked at the grep path's granularity: `buildGraph/3..8` (the resolve loop and the five passes after it),
the parse pool's worker join and per-thread merge, and the two corpus-wide model post-passes. The
per-reference split inside the loop (six span timers + volume counters) was a scratch patch, not landed.

Corpora by `rg --files`: `golang/go` `49c3ea64` 15,865 files; `llvm/llvm-project` `2061c237` (shallow)
182,555 files, 2.9 GB — the same checkouts the head-to-head used. Warm = a dedicated `TMPDIR` per corpus,
primed once (llvm cold prime: 231 s wall, 367 s user on 18 cores, peak RSS 6.49 GB). Arms interleaved
`grep, help, callers` × 2 reps; `/usr/bin/time -l` for wall + RSS. 18-core Apple Silicon, 48 GB, shared:
the 1-minute load ranged 2.3–26 across the session, so read the ratios, not the third digit.

```
TMPDIR=<per-corpus> build_prof/ripwire <root> --grep=zzqxvnotpresentzz   # the absent literal (full scan)
TMPDIR=<per-corpus> build_prof/ripwire <root> --callers=main             # same graph, NO text scan
TMPDIR=<per-corpus> build_prof/ripwire <root> --help-task=zzqxvnotpresentzz   # crawl + cache + model, NO graph
```

`--help-task` returns before `buildGraph` and uses the same lean cache blob as `--grep`, so it IS the
"graph stubbed out" arm the head-to-head asked for, with no code change.

### Result — the decisive experiment, then the profile, then the operation

| llvm-project, warm, wall | pre-fix (2 reps) | **post-fix (2 reps)** |
| --- | --- | --- |
| `--grep=<absent>` | 159.7 s, 153.9 s | **9.2 s, 9.0 s** |
| `--callers=main` | 152.9 s, 151.8 s | **8.6 s, 8.7 s** |
| `--help-task` (no graph) | 3.8 s, 3.4 s | 3.7 s, 3.4 s |
| default map, `--top-k=100000` | 248 s | **10 s** |
| peak RSS, any arm | 5.9–6.2 GB | 5.8–5.9 GB |

**The floor is the graph, and only the graph.** The arm that runs the identical crawl, cache load,
validation and model build but never builds the graph took 3.8 s at the same 5.9 GB RSS. The cache load
plus per-file validation is 16 µs/file on llvm against 28 µs/file on go — linear, if anything sub-linear.
The memory-cliff hypothesis is refuted by the same row: RSS is the ingest's reference tables, present with
and without the graph, and wall did not move with it.

Profile scopes, llvm warm `--grep`, pre-fix (rep 1, 159.7 s wall): `buildGraph` 154.6 s, of which the
per-reference resolve loop 153.2 s; `ingest: total` 4.7 s (crawl 1.8 incl. the git ignore probe 1.3,
model 1.2, parse pool 1.2, loadCache 0.4); `grep/1 grepCollect scan` 1.07 s on its own thread. The 2.9 GB
text scan is 1 s; the answer waited 153 s for the graph.

Inside the loop, `--callers=main` warm, six spans over the SAME 4,546,850 references:

| span (per reference) | calls | total | mean |
| --- | ---: | ---: | ---: |
| a: role filter + byName + SCIP/binding tiers | 5,162,745 | 0.11 s | 0.02 µs |
| b: canonical + L3 + ES import + rules 1/2/2b/2c/3 | 4,546,850 | 1.09 s | 0.24 µs |
| c: external veto + candidate spray + namespace gate | 4,517,099 | 2.18 s | 0.48 µs |
| d: tier ladder (same file / same dir / unique) | 4,137,640 | 1.07 s | 0.26 µs |
| **e: CHA-lite cone + arity + locality** | 2,213,632 | **145.1 s** | **65.5 µs** (max 41.7 ms) |
| f: amb + confidence + edge emission | 2,213,632 | 0.31 s | 0.14 µs |

The obvious suspect was innocent: the five linear passes over the same-name candidate list visited
1,226,680,236 candidates (`test` 502 M of them, 7,405 defs; `S` 291 M; `foo` 76 M) and cost 3.3 s in
total — ~3 ns a visit, sequential ids, the prefetcher's happy case. Splitting span e once more: arity
0.015 s, the S6-C locality tie-break 0.27 s, **the CHA-lite cone ≈ 143 s.**

**The operation.** For every still-ambiguous call with a known receiver static type, the loop rebuilt the
type's inheritance cone — two BFS walks over the class-NAME graph, `std::vector<std::string>` with an
O(n²) `std::find` dedup, capped at 4,096 per walk — and tested each tier candidate by another linear
`std::find`. Counters: **86,667 cones for 2,984 distinct receiver types** (each rebuilt ~29×), mean cone
1,075 names (Σ 93,185,627), 1.65 ms a cone. On go the same span is 1.1 ms total — zero cones, because the
model has no class-inheritance edges there — which is why the floor looked flat until the corpus had deep
hierarchies. That is the super-linearity: Σ over calls of (cone size)², where both factors grow with the
tree.

**The fix** (`src/graph.h`, `ChaConeMemo`): one cone per receiver type, computed on first use over class
names interned to dense ids in byte-sorted order, the walk verbatim (same seed, discovery order and the
outer-loop-only cap), membership by binary search. Post-fix the loop is 4.5 s; span c's 2.2 s of
candidate spray is now the largest remaining item and is a different, linear-per-candidate fix. Default
maps are **byte-identical** pre/post on both corpora (go 10,415,057 B; llvm 21,802,319 B) and the six
resolver gates plus 18 more pass unchanged. Per file, the warm `--grep` floor is now 50 µs at 182,555
files against 33 µs at 15,865 — the 24× per-file regression is 1.5×.

### Reproduce

```
cmake -S . -B build_prof -DRIPWIRE_PROFILE=ON && cmake --build build_prof -j
git clone --depth 1 https://github.com/llvm/llvm-project <scratch>/llvm-project    # ~2.9 GB, ~182,555 files
export TMPDIR=<scratch>/tmp-llvm; mkdir -p "$TMPDIR"
build_prof/ripwire <scratch>/llvm-project --grep=zzqxvnotpresentzz >/dev/null 2>prime.err   # cold prime
for rep in 1 2; do for arm in --grep=zzqxvnotpresentzz --help-task=zzq --callers=main; do
  /usr/bin/time -l build_prof/ripwire <scratch>/llvm-project "$arm" >/dev/null 2>"$arm.$rep.err"; done; done
# the stderr report's "hottest scopes" table is the phase split; buildGraph/3 is the resolve loop
```

---

## 2026-09-09 — the loop-hoist sweep: going looking for the CHA-cone bug's siblings

LEDGER rows, never a gate (the no-perf-budget rule). The correctness gate this round landed is
`test/rustanccheck.sh`; it asserts sets, never seconds. The question came from the CHA-lite cone round
earlier the same day (the section above): **work inside a loop that should not be in there has bitten this
project several times, so go looking rather than wait for the next one.**

### The method, and why the phase table came first

The cone bug was not found by reading code. It was found by a CONTROL — `--help-task`, which runs the same
crawl, cache and model work with **no graph build**, at 3.8 s against `--grep`'s 159.7 s on llvm-project.
This round's equivalent was the phase table itself: `PROFILE_SCOPE` covered 12 of `src/graph.h`'s 259 loops
and **none of `src/resolve.h`'s 69**, so 35% of `buildGraph`'s warm wall on `go` — 61 ms of 172 — was
attributed to nothing at all. Instrumenting the gap (`buildGraph/1a..1i` for the prologue, `2a..2i` for the
side tables, plus the crawl's directory walk and the shadow post-pass's two halves) is what turned the two
findings below from invisible into obvious. `git diff -w` for that commit is 40 added lines.

The second half of the method was **corpus diversity**, and it mattered more than the instrumentation.
Every corpus in this file before today was C++, Go, Python or this repository. Adding
`rust-lang/rust-analyzer` and `rails/rails` moved a phase from 3% of the run to 41% and 26% respectively —
both findings below live on paths that no previously-measured corpus exercises at all.

### Phase table — warm `--callers=main`, min of 4-5 interleaved runs, `-DRIPWIRE_PROFILE=ON`, AFTER this round

18-core Apple Silicon, 48 GB, shared (1-minute load 3.5-4.5 across the session): read the ratios, not the
third digit. Corpora by `rg --files`: `golang/go` 15,865; `django/django` 7,036; `rails/rails` 4,923;
`rust-lang/rust-analyzer` 2,303; this repository 2,263; a private C++ tree 3,248.

| phase (ms) | go | django | rails | rust-analyzer | this repo | private C++ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **ingest: total** | 252.3 | 154.5 | 102.9 | 52.0 | 61.3 | 103.2 |
| — crawl (collectSources) | 83.3 | 99.5 | 47.8 | 21.5 | 25.9 | 27.3 |
| — — git ignore probe (one `git ls-files` fork) | 41.5 | 54.9 | 27.0 | 14.4 | 18.0 | 18.8 |
| — — directory walk (stat + classify) | 40.8 | 44.0 | 20.4 | 6.7 | 7.7 | — |
| — build model | 83.3 | 24.1 | 19.0 | 14.2 | 14.5 | 36.3 |
| — — shadow suppression (r9 post-pass) | 21.7 | 6.2 | — | 3.8 | 3.4 | 9.6 |
| — loadCache (read + deserialize) | 39.0 | 14.3 | 17.6 | 8.7 | 7.8 | 15.9 |
| — parse pool (tree-sitter, parallel) | 21.7 | 6.3 | 8.3 | 4.0 | 3.7 | — |
| **buildGraph: resolve refs + build CSR** | 147.2 | 69.6 | 191.8 | 46.1 | 15.0 | 40.2 |
| — /3 resolve loop (per reference) | 80.4 | 26.4 | 54.8 | 31.5 | 6.9 | 17.0 |
| — /2b transitive include closure (resolve.h) | — | — | **61.9** | — | — | — |
| — /2a precise include adjacency (resolve.h) | 2.6 | 6.5 | **52.8** | 2.1 | 0.6 | 1.8 |
| — /1a canonId + localityKey (per symbol) | 20.2 | — | 5.0 | 2.6 | 1.2 | 3.9 |
| — /2e Phase-5 external-veto tables | 3.5 | 10.2 | — | 0.6 | 0.8 | 1.4 |

**The headline shape: after the cone fix there is no single dominant phase left on any corpus — but which
phase is largest changes completely with the corpus's LANGUAGE.** On `go` it is the resolve loop and the
crawl; on `rails` it is the two include-resolution functions in `resolve.h` that had no instrumentation at
all before today; on `rust-analyzer` the resolve loop was 41% of the whole run at one seventh of `go`'s file
count. A phase table taken on one corpus family is a phase table for that family only.

### F1 — the Rust qualified-call ancestor closure: the same bug, in the function next door

`keepRustQualifiedCandidates` (`src/graph.h`) admits a candidate for `Qual::name()` when the candidate's
enclosing scope reaches `Qual` through the CHA-lite base-name graph. It answered that with a fresh
transitive BFS **per candidate per reference** — `std::vector<std::string>` frontier, a full `std::string`
COPY per queue element, an `O(n²)` `std::find` dedup, capped at 4,096. The cone bug's four properties, all
four, thirty lines from the memo that fixed them.

It was invisible because no corpus in this file had Rust in it. On `rust-analyzer`, warm: **7,539 active
calls, 23.9 ms, 47% of the resolve loop and 17% of the whole run.**

The fix computes each scope's capped base closure once, inside `ChaConeMemo` (same interning, same walk,
same seed and discovery order, same outer-loop-only cap), answered by binary search.

| rust-analyzer, warm, interleaved A,B | before | after |
| --- | --- | --- |
| `buildGraph/3` resolve loop (5 reps) | 49.4 48.0 49.8 49.4 48.4 ms | **33.0 32.1 32.2 32.2 32.1 ms** (−34%) |
| `buildGraph` (5 reps) | 66.0 64.0 66.0 64.9 64.1 ms | **49.6 48.0 47.7 48.2 47.8 ms** (−26%) |
| `--callers=main` wall, n=21, twice | — | **−13.2% / −13.2% median, −12.7% / −13.4% min** |
| default map wall, n=21, twice | — | **−10.4% / −11.4% median, −9.5% / −10.3% min** |

Controls (n=15 each): `go` +0.2%, this repository +0.4%, the private C++ tree −0.0% — the guard's active arm
is Rust-only, so a non-Rust corpus must not move, and does not. Byte-identical on six corpora.

### F2 — `lexicalNormalize` allocated a segment vector before it allocated its answer

`probeUpward` walks from the includer's directory to the tree root; for a non-relative Ruby `require` it
does that once per load root, and there are five. Each level calls `joinNormalizeLookup` → `lexicalNormalize`,
which allocated a `std::vector<std::string_view>` (a `reserve( 8 )` heap block) **before** the string it
returns. On `rails`: 28,555 includes, ~25 probes each, **714,000 calls paying two allocations where one is
the answer** — 87 ms of a 330 ms warm run, 3.05 µs per include.

Segments now append straight into the returned string; a `..` truncates back to the previous `/`; `rootLen`
(1 absolute, 0 relative) makes the two degrade rules one comparison; the vector's `segs.back() != ".."`
guard was invariant-true (only real segments were ever pushed) and went with it.

| corpus, warm | median | min |
| --- | ---: | ---: |
| `rails` `buildGraph/2a`, 5 interleaved reps | 74.3-76.0 → **52.6-54.8 ms** | −28%, no rep the other way |
| `rails --callers=main`, n=21, twice | **−6.0% / −6.2%** | −6.8% / −6.1% |
| `rails` default map, n=15 | −4.8% | −4.4% |
| `django --callers=main`, n=15 | −3.0% | −2.0% |
| `go` / this repo / `rust-analyzer` / private C++, n=15 each | −0.5% −0.5% −0.6% −0.7% | — |

Twelve of twelve run-level statistics favour it and none flips. Equivalence: a differential harness ran the
old body and the new one over **4,000,000 generated paths**, 0 mismatches, with two mutation controls that
produce 411,633 and 1,518,327 mismatches. Byte-identical on seven corpora.

### F3 — the shadow-suppression predicate asked its LEAST selective guard first

`suppressShadowedReferences`' per-reference predicate ANDs four pure guards, so their order is a cost
decision and nothing else. `defNames.find( calleeName )` hits whenever ANY indexed symbol carries the name —
for a call site, nearly always. `varSpans.find( "<caller>#<name>" )` hits only when THIS caller declares a
local of exactly that name — rare. The common one ran first, so every reference in the corpus paid a full
string hash to learn nothing. Swapped: same verdict by construction, byte-identical on four corpora.

`go`, warm, 5 interleaved reps: **30.2 30.1 31.5 31.2 31.5 ms → 22.3 22.8 22.8 28.7 22.6 ms** (≈ −26%, never
the other way). Whole run, two independent n=21 A/Bs: `--callers=main` −0.8% / −0.1% median, −2.7% / −1.4%
min; default map −1.0% / −0.5% median. Under ~3,000 files the phase is small enough that the run-level
number is inside the noise band and both directions appear — **the honest claim is the phase number plus
"about 1% of a warm run on go"**, not a run-level headline.

### R1 — REFUTED: memoising the bare-name candidate spray. Volume is not cost.

The resolve loop's spray — `for( NodeId c : byName[ name ] )` keeping the language- and role-compatible
defs — is a pure function of (name, `r.lang`, `r.role`) on a single-root run, recomputed once per
REFERENCE. Scratch volume counters, warm:

| corpus | refs | name hits | spray visits | namespace gate | tier-1 scan | tier-2 scan |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `go` | 671,200 | 655,306 | 16,401,717 | 16,349,433 | 16,349,433 | 12,850,696 |
| private C++ | 122,119 | 63,969 | 388,265 | 426,743 | 426,743 | 325,883 |
| this repo | 58,176 | 20,528 | 469,672 | 449,290 | 449,270 | 60,609 |

The spray plus the gate is **53% of the loop's whole scan volume** on `go`. A memo keyed on
(byName index, lang, role) into one contiguous arena removes both passes; it was built, gated
(fill / different key / hit-after-growth, with three mutation controls each reddening exactly its own arm),
proved byte-identical on four corpora and sanitizer-clean.

**It measured nothing.** Interleaved phase A/B on `go`, `buildGraph/3`: A median 80.3 ms, B median 81.5 ms —
the memo is *slightly slower*. Whole run, two n=21 A/Bs: −0.8% then −0.1% median, and the min flipped
positive on the repeat. Suspecting the corpus rather than the fix, a purpose-built **8×-multiplicity tree**
(14,072 files, eight copies of this repo's source in ONE root, so every name is defined eight times — the
llvm `test`-defined-7,405-times shape) was measured too: A median 121.3 ms, B median 121.8 ms, whole run
+0.3%. **Reverted.**

Why it cannot win is the same arithmetic the cone round already published for these five passes: ~3 ns a
visit over sequential ids, the prefetcher's happy case, and most `byName` lists are 1-2 entries held inline
by `rw::SmallVec<NodeId,2>`. The memo trades that for a 64-bit hash lookup per name hit plus a vector
assign, which costs about what it saves. **Scan VOLUME is not a proxy for scan COST** — this is D2's lesson
(docs/OPTREMARKS.md §6) arriving from the profile side instead of the compiler side.

### R2 — REFUTED: the duplicate `canonId` / `localityKey` string, and the opaque call in a loop condition

`buildGraph/1a` computes `canonicalId(...)` and `localityKeyOf(...)` per symbol, and for a SCOPED symbol
those are the same string built twice (`localityKeyOf`'s own comment says so). Ablation — interleaved, the
second string simply not written for scoped symbols — gives a real phase win and an irrelevant absolute one:
this repo 1.28 → 1.05 ms, private C++ 4.20 → 2.94 ms, the 8× tree 6.34 → 4.90 ms, and **`go` 21.5 → 22.7 ms
(nothing, because Go symbols carry no scope)**. The best case is 1.3 ms of a 160 ms run. Dismissed on the
arithmetic, exactly as D1 dismisses PageRank: there is no version of this work that shows up in a wall-clock
number, and the sentinel it would need makes the code read worse.

Same verdict for `for( i = 0; i < ts_node_named_child_count( node ); ++i )` — an opaque C call re-evaluated
every iteration, which is precisely the class this round hunted. There are **7 such sites** (`ingest_elixir.h`
×5, `ingest_relations.h` ×2); every one is on an Elixir/Lua/Ruby literal-node path, and every one iterates
the children of a string or tuple node — one to three of them. Hoisting is correct and unmeasurable.

### Open, with numbers — what this round did NOT fix

1. **`buildGraph/2b` transitive include closure, 61.9 ms on `rails`** — now the single largest phase there.
   It is an all-pairs reachability: Σ|closure| = **3,994,331** ids over 3,916 files, max closure 1,420, and
   **38.7 ms of it is `std::sort`** on 3,916 runs averaging 1,020 elements. The `std::unique` after that sort
   removed **0 duplicates in 3,916 calls** (the epoch stamp already guarantees uniqueness) at 0.98 ms — real,
   provable, and too small to be worth the churn on its own. The sort exists only to make membership a
   `binary_search`; at 26% density a bitset would remove it, but the materialisation scan is Θ(F/64) per
   source and that trade could not be tested at llvm scale this round, so it was not attempted.
2. **`buildGraph/2a`, still 52.8 ms on `rails` after F2** — the remaining cost is the two allocations
   `joinNormalizeLookup` still pays per probe (`joined`, then the normalized copy) times ~25 probes per
   include. Threading a caller-owned scratch buffer through `probeUpward`/`joinNormalizeLookup` is the
   in-house shape (`Narrower::keyScope` and friends) and is the next thing to try.
3. **`ingest: crawl (git ignore probe)`, 41.5 ms on `go` and 54.9 ms on `django`** — one `git ls-files` fork,
   10-20% of a warm run, already documented 2026-09-03. Not loop work; listed because the phase table now
   makes it the second-largest ingest item on two corpora.
4. **`ingest/loadCache: deserialize file records`, 37.9 ms on `go`** — allocation-bound (`FileFacts` carries
   several `std::string`s), not loop-invariant work. Read, dismissed for this round.

### Reproduce

```
cmake -S . -B build_prof -DRIPWIRE_PROFILE=ON && cmake --build build_prof -j
git clone --depth 1 https://github.com/rails/rails               <scratch>/rails
git clone --depth 1 https://github.com/rust-lang/rust-analyzer   <scratch>/rust-analyzer
export TMPDIR=<scratch>/tmp-rails; mkdir -p "$TMPDIR"
build_prof/ripwire <scratch>/rails --callers=main >/dev/null 2>prime.err   # warm prime, then re-run
# the stderr report's "hottest scopes" table is the phase split; take the MIN over >=4 runs, not one run —
# a single run on this shared box read buildGraph/3 at 111 ms and 80 ms an hour apart, and the difference
# was the machine, not the code. Every A/B in this section is interleaved A,B,A,B for the same reason.
```

**llvm-project could not be re-measured this round.** A `--depth 1` clone ran at ~4 MB/min against a 2.9 GB
pack — about 12 hours — and was abandoned. Every number above is from a corpus that fits the link. The
consequence is stated rather than buried: R1's refutation is proved up to 15,868 files and an 8×-multiplicity
14,072-file tree, and not beyond.

## 2026-09-09 — the 2b closure sort goes radix: one site converted, three refused, and the crossover that does not transfer

LEDGER rows, never a gate (the no-perf-budget rule). The correctness gate this round landed is four new
arms in `test/includeprecisecheck.sh`; they assert sets and invariants, never seconds.

This picks up open item 1 from the loop-hoist sweep above: **`buildGraph/2b` at 61.9 ms on `rails`, of
which 38.7 ms is `std::sort`**, over 3,916 closures averaging 1,020 ids, with a `std::unique` that removed
0 duplicates. The owner's read was that those sorts should be radix. They should — at exactly one of the
four sites that looked like candidates, and the three refusals are the more useful half of the result.

### The recorded crossover is 2048, and honouring it literally would have forfeited the entire win

`src/infra/sortutil.h` already carries a measured threshold — `kRadixThreshold = 2048` — on both
`radixSortByFromTo` and `radixSortByScoreDescId`. The 2b closures top out at **n = 1,420**. Routed through
that number, every single one takes the `std::sort` branch and the change does nothing.

That 2048 is not wrong; it describes **different work**. `radixSortByFromTo` moves 12-byte `Edge` RECORDS
through two full key passes. `radixSortByScoreDescId` pays a `scores[id]` GATHER, up to two `sortKeySmall`
calls and three O(n) prechecks. 2b sorts a `std::vector<NodeId>` — one 4-byte item, one direct key — and
because file ids span 12 bits on `rails`, the no-op pass skip in `sortKeySmall` collapses it to **two
passes, not four**. Re-measured for that shape (`-O2 -mcpu=apple-m1 -ffast-math`, medians of 15 interleaved
reps, random keys, ratio = radix / std::sort, <1 means radix faster):

| key range | n=32 | n=64 | n=128 | n=256 | n=1024 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 12-bit (`rails`, F=3,916) | 2.31x | 0.86x | 0.47x | 0.21x | 0.18x |
| 14-bit (`go`, F=15,868) | 1.71x | 0.85x | 0.46x | 0.31x | 0.17x |
| 16-bit | 1.79x | 0.85x | 0.47x | 0.26x | 0.18x |
| 20-bit | 2.46x | 1.22x | 0.64x | 0.40x | 0.23x |
| 32-bit (full) | 4.16x | 1.50x | 0.73x | 0.45x | 0.25x |

The crossover for this shape is **64 for narrow keys and 128 for a full 32-bit range**. The new entry point
`rw::sortutil::radixSortIdsAscending` takes **128** — the crossover of the widest range measured, so the
door holds whichever way the id range turns out — and its comment says at length why it is not 2048, so
nobody unifies the two numbers later.

### The threshold is what makes the change safe, not a nicety

Replaying the REAL captured closures (every `trans[s]` written to disk, replayed against both sorts,
medians of 15 interleaved reps). "radix always" is the unthresholded conversion:

| corpus | Σ closure | max n | std::sort | radix T=128 | radix ALWAYS |
| --- | ---: | ---: | ---: | ---: | ---: |
| `rails` | 3,994,331 | 1,420 | 42.01 ms | **11.44 ms (0.272x)** | 11.50 ms |
| private C++ (3,248 files) | 12,066 | 149 | 0.048 ms | 0.042 ms (0.865x) | 0.372 ms (**7.7x worse**) |
| this repo | 4,182 | 137 | 0.018 ms | 0.017 ms (0.960x) | 0.052 ms (**2.9x worse**) |
| `django` | 1,578 | 19 | 0.010 ms | 0.010 ms (0.958x) | 0.079 ms (**7.9x worse**) |
| `rust-analyzer` | 640 | 43 | 0.0045 ms | 0.0044 ms (0.991x) | 0.021 ms (**4.7x worse**) |
| `go` | 26 | 2 | 0.021 ms | 0.021 ms (1.000x) | 0.021 ms |

An unconditional conversion regresses four of six corpora by 3–8x. With the threshold, no corpus regresses
and `rails` gains 3.7x. **`rails` is the only corpus where this phase is large at all** — Σ|closure| there is
331x the next-biggest — which is the loop-hoist round's own lesson repeating: this is a Ruby `require`-graph
shape, and a C++/Go/Python corpus cannot see it.

### In situ — `buildGraph/2b`, warm, interleaved A,B

| corpus | base | radix | ratio |
| --- | ---: | ---: | ---: |
| `rails` (n=7) | min 64.97 med 65.21 ms | **min 34.73 med 35.01 ms** | **0.537** |
| `go` (n=5) | 0.029 ms | 0.026 ms | (sub-ms, jitter) |
| `django` (n=5) | 0.048 ms | 0.047 ms | (sub-ms, jitter) |
| `rust-analyzer` (n=5) | 0.022 ms | 0.023 ms | (sub-ms, jitter) |
| private C++ (n=5) | 0.289 ms | 0.300 ms | (sub-ms, jitter) |
| this repo (n=5) | 0.097 ms | 0.101 ms | (sub-ms, jitter) |

The `rails` reps do not overlap: base 65.0 65.0 65.1 65.2 65.3 65.4 65.5, radix 34.7 34.8 34.9 35.0 35.0
35.2 35.7. `buildGraph` total on `rails`: 223.0 → 186.7 ms median (−16%); `go` 1.000x, private C++ 0.995x.

Whole run, two independent n=21 interleaved A/Bs each:

| run | median | min |
| --- | ---: | ---: |
| `rails --callers=main` | **−7.8% / −8.5%** | −8.8% / −9.1% |
| `rails` default map | **−7.6% / −7.3%** | −8.2% / −7.6% |
| `go` / `django` / `rust-analyzer` / private C++ / this repo (n=15 each) | −0.6% / −0.5% / −0.8% / +0.1% / +0.5% | all within ±1.7% |

Byte-identical on six corpora × three verbs (default map, `--callers=main`, `--impact=main`): 18
comparisons, 18 distinct output sizes proving the corpus argument took effect in every one.

### The `std::unique` was dead, and it is dead by construction rather than by luck

`w` is appended to `trans[s]` inside the same branch that stamps `seenEpoch[w] = epoch`, and nothing clears
that stamp before `++epoch`. A file therefore reaches `trans[s]` **at most once per source** — the set is
duplicate-free by construction, not by coincidence. Measured: **0 duplicates removed in 24,216 calls across
six corpora**, costing **0.992 ms on `rails`** (independently reproducing the 0.98 ms recorded above).

It is removed. The sibling `ancestorsReach` in `graph.h` has always relied on this same epoch stamp with no
dedup, so this makes two walks agree rather than introducing a new assumption. It is NOT replaced by a
`VERIFY`: in a release build `VERIFY_TEXT` still evaluates its expression before `__builtin_unreachable`, so
an O(n) uniqueness scan there would reintroduce exactly the cost being removed. The invariant is asserted by
a gate instead (below), which costs nothing at runtime.

**The sort itself stays, and the reason is non-negotiable #2.** It is not merely making membership a
`binary_search` — the walk's discovery order is deterministic but is NOT id order, so the sort is what makes
`trans` a pure function of `adj`, exactly as this function's header comment claims. Radix only changes how
it is paid for. Attribution of the 30.2 ms: ~30.6 ms is the sort, 0.99 ms is the dedup.

### Three sites REFUSED — and the mechanism is presortedness, not size

`g.implementors[]`, `g.mentions[]` (`graph.h`) and the CHA cone/ancestor closures were the other candidates.
Measured on captured real data, thresholded exactly as 2b is:

| site | corpus | Σ | max n | duplicates | radix T=128 |
| --- | --- | ---: | ---: | ---: | ---: |
| `implementors` | `django` | 646,700 | 2,401 | 0 | **2.87x WORSE** |
| `implementors` | `rails` | 7 | 3 | 0 | 1.00x |
| `mentions` | `rails` | 73,948 | 79 | 18,732 | 0.89x |
| `mentions` | private C++ | 51,188 | 116 | 8,622 | 0.93x |
| `chacone` | `django` | 2,195 | 335 | 100 | 0.83x (of 0.008 ms) |
| `chaanc` | `rust-analyzer` | 3,326 | 27 | 0 | 0.98x |

`django`'s `implementors` is the interesting refusal: Σ = 646,700 with a max of 2,401 looks like the ideal
radix case and loses badly. The reason is that **100.0% of its 47,830 records arrive already sorted, with
zero adjacent descents** — they are built by `push_back` while iterating references in ascending id order.
`std::sort` detects that in O(n); radix cannot exploit it and pays both passes regardless. `rails`'
`mentions` is 100.0% presorted for the same reason. 2b is the odd one out at **1.6% presorted** (0.18
adjacent descents per element) because a graph walk emits in discovery order.

So the rule that decided all four sites is not "how big is n" but **"was this set built by appending in id
order, or by a scattered walk?"** — and it is now written into `radixSortIdsAscending`'s comment, because it
is the thing a future caller will get wrong. The remaining sites' absolute costs (0.008–0.6 ms) would not
have justified the churn even had they won.

**Also noted, not attempted: the two `std::vector<std::string>` sorts** at `graph.h:1886-1887` (the
`chaUp` / `chaDown` dedup). A string radix is a materially bigger change than an id radix — variable-length
keys, no fixed pass count, and the whole `sortKeySmall` contract assumes a scalar key — so it was scoped
out rather than rushed. The number that says it can wait: those two lines live inside `buildGraph/2h`, and
that WHOLE phase (name-graph construction, interning and both sorts together) measures **0.70 ms on `rails`,
3.69 ms on `django`, 1.93 ms on `go`, 0.90 ms on `rust-analyzer`, 0.50 ms on a private C++ tree** — a 4.5%
ceiling on `django`'s `buildGraph` and under 1.2% everywhere else, with the sorts themselves only a fraction
of it. It never appeared in the loop-hoist phase table because it never cleared the reporting threshold.

### The gate, and the arm that proved the fixture could not see the defect

`test/includeprecisecheck.sh` gained: a postcondition sweep asserting every `trans[f]` is sorted AND
duplicate-free; a **diamond** fixture (`diamond/top.h` → `left.h`+`right.h` → both → `shared.h`) asserting
`shared.h` appears exactly once despite two distinct paths; a **cycle** fixture (`cyc/p.h` ↔ `cyc/q.h`); and
a **400-node synthetic** arm checked element-for-element against an independent mark-and-sweep oracle.

The synthetic arm is not decoration. Two mutation controls were run:

| mutation | fixture arms | large-N arm |
| --- | --- | --- |
| delete the sort | **all PASS** | FAIL (sorted + oracle) |
| append without the epoch guard | uniqueness + diamond FAIL | FAIL (unique + oracle) |

**With the sort deleted entirely, every fixture-based arm stayed green** — the fixture's closures are all
under ten elements and its discovery order happens to be ascending, so it is a population that cannot
contain the defect (CONTRIBUTING.md §2, shape 1). Only the scrambled 400-node graph, whose closures exceed
the 128 threshold and whose discovery order is nowhere near sorted, can fail. It also carries an explicit
non-vacuity assertion that at least one synthetic closure exceeds the radix threshold, so the radix branch
cannot silently stop being exercised.

### Reproduce

```
cmake -S . -B build_prof -DRIPWIRE_PROFILE=ON && cmake --build build_prof -j
export TMPDIR=<scratch>/tmp-rails; mkdir -p "$TMPDIR"
build_prof/ripwire <scratch>/rails --callers=main >/dev/null 2>prime.err   # warm prime, then re-run
# the stderr "hottest scopes" table is the phase split; buildGraph/2b is the closure.
# Take the MIN over >=5 interleaved A,B reps — this box ran 1-minute loads of 5-19 across the session.
```
