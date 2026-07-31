# ctxpack — the benchmark (closing the "no published number" gap)

The honest gap in the pitch was: *no published benchmark.* This closes it. Two numbers, both
**reproducible** — re-run `python3 bench/bench_proof.py` (needs `tiktoken`; the wall-clock head-to-head
needs `aider-chat`). Real GPT-4 tokens (tiktoken `cl100k_base`). Measured 2026-06-20 on a large private
C++ corpus — **historical, private corpus (not reproducible publicly)**; re-run against your own corpus
(set `CTXPACK_BIN`/`CTXPACK_BENCH_ROOT`, see `bench/bench_proof.py`) to reproduce the shape.

## 1. Token reduction — ctxpack's structured answer vs the naive read
Methodology mirrors codebase-memory-mcp's "% reduction on N structural queries": for realistic agent
questions, count the tokens of ctxpack's answer vs. the naive thing an agent does **without** it.
- **who-calls** tasks: `--callers=SYM` vs the raw `grep -rn SYM` dump an agent reads.
- **orient** tasks: `--for="…"` (the ranked map) vs reading **whole** the files that map surfaces.

| task | ctxpack tok | baseline tok | saved | factor |
|---|---|---|---|---|
| who calls materialize | 1,573 | 25,664 | 93.9% | 16.3× |
| who calls simulateRun | … | … | (see run) | |
| who calls evaluateGenome | … | … | (see run) | |
| orient: feedback loop | 4,206 | 124,211 | 96.6% | 29.5× |
| orient: sphere fire | 3,800 | 156,531 | 97.6% | 41.2× |
| orient: steering behaviors | 4,212 | 54,566 | 92.3% | 13.0× |
| **HEADLINE TOTAL** | **14,758** | **367,192** | **96.0%** | **24.9×** |

**→ ~96% fewer tokens (24.9× less) across these agent questions.**

**Honest parity note (shown, not hidden):** `--grep` is *not* a token reducer — it adds enclosing-symbol
structure at ~grep cost: `--grep frantic` +19.7%, `--grep FirePolicy` −11.2% vs raw grep. The reduction
comes from **structured answers** (`--callers`) and **orientation** (`--for`), not from grep-like modes.

## 2. Wall-clock — ctxpack (C++23) vs aider repo-map (Python + NetworkX)
The fairest comparison in the field: **the same algorithm** (tree-sitter parse → PageRank), so the gap is
purely compiled-vs-interpreted. aider's tags cache cleared each run (cold == ctxpack `--no-cache`); min of N runs.

| repo | files | ctxpack cold | ctxpack warm | aider cold | speedup |
|---|---|---|---|---|---|
| infrastucture | 47 | 224 ms | 77 ms | 2,526 ms | **11.3×** |
| steer | 168 | 245 ms | 82 ms | 4,684 ms | **19.1×** |
| sound | 195 | 311 ms | 80 ms | 2,843 ms | **9.1×** |
| canyon | 366 | 321 ms | 97 ms | 10,135 ms | **31.6×** |
| whole repo | 1,560 | 951 ms | 182 ms | 39,950 ms | **42.0×** |

**→ 9–42× faster than aider on the same task.** Whole repo: ~1s cold / **0.18s warm** vs aider's **40 s**.
(ctxpack ingested *more* files than the set handed to aider on several repos — so this is conservative.
Warm column reflects the query-compile optimization — commits `b9b5763` (skip absent grammars) +
`9432b4d` (compile present grammars in parallel), see [PROFILE.md](PROFILE.md); cumulatively warm
313→182 ms (1.7×), ~2.4× on small dirs. Speedups are vs aider's *cold* map, unchanged.)

## Honest caveats
- **The token baseline is a model of "naive agent read"** (grep dump / whole files the map points at) — a
  reasonable, documented, auditable proxy, not a live agent trace. It's the same methodology competitors use.
- **Wall-clock is on one machine**, min-of-N; aider run via its `RepoMap` API with the tags cache cleared.
  File *sets* differ slightly (each tool's own source-file definition); ctxpack handled ≥ as many files.
- **What this does NOT measure:** answer *quality* / task *success* (that needs a SWE-bench-style agent
  harness — the next benchmark to build; cf. RepoGraph's +32.8% SWE-bench from structural retrieval,
  [arXiv 2410.14684]). These numbers prove **cheaper + faster**, not **better outcomes** — say so.
- Tokens via `tiktoken cl100k_base` (bytes ≈ 4/token). Numbers move with the corpus; re-run to reproduce.
