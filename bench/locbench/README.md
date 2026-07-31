# LocBench — ctxpack code-localization accuracy on a public benchmark

`run_locbench.py` measures how well ctxpack **localizes** the code an issue asks you to change, on a
public, LLM-free, externally-defined scoreboard: **Loc-Bench** (LocAgent, [arXiv 2503.09089](https://arxiv.org/abs/2503.09089),
ACL'25), with a **SWE-bench-Lite** fallback. It is the public-benchmark sibling of the co-change
retrieval proxy in [`../ANSWERQUALITY.md`](../ANSWERQUALITY.md) §1 — same deterministic, leave-nothing-out
posture, but on someone else's benchmark with their metric definitions, so the number is not one we defined.

This closes the AUDIT4 §E credibility gap ("localization is now a benchmarked subfield; *no published
benchmark* is the gap"). The house rule governs it: **publish the losses with the wins.**

## 2026-07-13 corrected evaluator + accepted router (A7) — CURRENT results

Everything below this section uses the **legacy 2026-07-11 methodology** (grouped-source ranking,
unique-basename fallback credit, no method scope, no train/held-out split, candidate-export bytes as
the payload proxy). It is preserved as historical evidence and is **not comparable** to the corrected
numbers here — denominators and identity rules differ.

The corrected evaluator (this `run_locbench.py`) enforces: exact repo-relative path identity (duplicate
basenames never earn credit), method identity = file + scope + name, one flat global candidate rank, a
frozen repository-disjoint train/held-out split (`dataset.lock`, salted SHA-256; train 317/87 repos,
held-out 243/78), zero silent skips, and paired repository-clustered bootstrap comparison
(`compare_runs.py`); production payload/latency are measured from the real `--for` output (five warm
samples, one cold, one index rebuild per instance), separately from the scored candidate export.

Held-out (N=243, zero exclusions, 564/564 scoped gold-function coverage), shipping routed `--for`:

| | file@1 | file@3 | file@5 | file@10 | lenient@10 | func-any@10 | fn-MRR | single-file strict | multi-file strict | all-patch strict |
|---|---|---|---|---|---|---|---|---|---|---|
| routed `--for` (accepted) | 19.3% | 38.3% | 51.0% | **60.9%** | 74.9% | 38.7% | 0.213 | 73.4% | 18.2% | 53.5% |
| pre-routing baseline | — | — | — | 27.6% | 36.2% | 11.1% | 0.053 | 33.5% | 7.3% | 24.7% |

Paired deltas (243 instances, 78 repo clusters): strict file@10 **+33.33pp** (95% clustered-bootstrap
lower bound +25.00pp), lenient +38.68pp, MRR +0.160, multi-file strict +10.91pp, all-patch +28.81pp.
Cost ledger of the accepted candidate vs baseline: warm p50 +3.4% (absolute p95 697ms vs 675ms), cold
p50 +3.0%, index p50 +4.4%, production token ceiling p50 **−39.4%** (rank-adaptive 7,500-byte payload
budget). Acceptance used the two-tier gate (absolute interactive SLA + quality-per-cost;
`GATE_DECISION.md`) under the recorded quality-first product decision; the legacy flat-percentage
comparator output is retained in the same file for the honest record.

Implementation shipped with the win: persisted per-symbol subtoken postings in the rich cache (warm
queries do zero per-file reads — property-gated), exhaustive-identical MaxScore pruning
(`CTXPACK_NO_PRUNE=1` byte-identity gate), per-file Bloom pre-filter, and the deterministic
rank-adaptive payload budget. Gates: `test/postingscheck.sh`, `test/routecheck.sh`,
`test/retrievalqualitycheck.sh`, `test/knownitemcheck.sh`.

---

## What it measures

Each Loc-Bench instance = a real GitHub issue + the repo at the pre-fix commit + the **gold edit
locations** (the files/functions the accepted fix patch actually touched). The harness, per instance:

1. **checkout** the repo at `base_commit` (shallow, single-commit fetch, cached across runs);
2. run ctxpack as the localizer — `ctxpack <repo> --for="<issue text>"` (+ two more arms below);
3. **parse** the ranked symbols/files out of ctxpack's XML;
4. **score** file-level Acc@k and function-level Acc@k + MRR against gold.

Deterministic given `(dataset slice, ctxpack binary)`: no LLM, no RNG, stable instance order.

### Three arms (all deterministic, same parse, same scoring)

| arm | invocation | what it is |
|---|---|---|
| `for` | `ctxpack <repo> --for="<issue>"` | the flagship **task lens** (routed by default): a focused ~40-symbol reuse bundle |
| `query` | `ctxpack <repo> --query="<issue>"` | **pure lexical BM25** — the full ranked symbol list, no compose/quality framing |
| `anchor` | `ctxpack <repo> --for=... --anchor` | EXPERIMENTAL lexically-anchored **graph expansion** (PPR seeded from top lexical hits) |

### Metrics (matched to LocAgent §4.1)

- **Acc@k (strict).** LocAgent scores a localization successful only if **all** gold locations fall
  within the top-k predictions. We use that exact strict definition. File-level **Acc@1 / @3 / @5 / @10**;
  function-level **Acc@5 / @10**. (We also print a *lenient* "any-gold-within-top-10" recall flavor —
  clearly labeled — because on multi-file gold sets the strict metric is unforgiving and the lenient one
  shows the "surfaced at least one right location" signal.)
- **first-hit MRR** — reciprocal rank of the *first* gold function found (0 if none). Labeled "first-hit"
  so it is not confused with LocAgent's internal reciprocal-rank confidence aggregation.
- **parse coverage** — fraction of gold functions ctxpack's parser emitted *at all* (the localizer's
  ceiling: a function the parser never saw is an automatic miss, reported as its own number).

### Gold, and what we count honestly

- **gold files** = files the fix patch touches; **gold functions** = Loc-Bench `edit_functions`
  (`path:name`, or `path:Class.method` → matched on the bare method name ctxpack emits).
- **`added_functions`** (functions the patch *adds* — they do **not** exist at `base_commit`) are
  **structurally un-findable by any static localizer** and are **excluded** from the function denominator
  and reported apart, never folded into the wins.
- **non-Python gold** (ctxpack speaks Py/TS/Go/Rust/C++/Swift/ObjC) is **skipped with a count**
  (Loc-Bench is all-Python, so this is a guard, not a factor).
- parse-coverage misses count as **automatic misses** in the strict Acc/MRR — the honest denominator.

## How to run

No auth needed — the dataset is pulled row-by-row from the public HuggingFace datasets-server JSON API
and cached to `--work-dir`. Clones and dataset cache live **only** under `--work-dir` (never in the repo).

```sh
# ctxpack must be the CURRENT build. On this machine the PATH `ctxpack` may be stale — point at the fresh one:
export CTXPACK=/path/to/ctxpack/build/ctxpack

# validation slice (25 instances)
python3 bench/locbench/run_locbench.py --n 25 --work-dir /tmp/locbench --verbose

# full set (560 instances)
python3 bench/locbench/run_locbench.py --n 560 --work-dir /tmp/locbench --json-out full.json

# SWE-bench-Lite fallback (gold = files + Python hunk-header functions the fix patch touches)
python3 bench/locbench/run_locbench.py --dataset swebench-lite --n 25 --work-dir /tmp/locbench
```

Flags: `--arms for,query,anchor`, `--top-k` (per `--for`/`--anchor` bundle), `--query-chars`
(issue-text prefix used as the query, default 1200), `--json-out` (per-instance results).

The SWE-bench-Lite fallback path is verified working (astropy/django/sympy slice): gold = files the fix
patch touches + functions from its Python `@@ ... @@ def/class` hunk headers. On the astropy spot check
`--for` ranks the gold file **#1** where `--query` ranks it #531 — the cleanest single illustration of the
lens's file-localization sharpness. Loc-Bench was fully accessible here, so it is the primary dataset and
SWE-bench-Lite is provided as the documented fallback.

## Full-run results (n=560 — the complete Loc-Bench test set)

**n=560, all instances, zero skips** (nonpy=0, checkout-fail=0, ctxpack-fail=0). Loc-Bench
(`czlll/Loc-Bench_V1`, test split), ctxpack build as of this commit, on an M-series Mac; total run
~28 min wall (checkouts dominate; cached). Per-instance rows: [`full560.json`](full560.json).
`Acc@k` = strict (all gold within top-k), per the paper.

**Strict Acc@k** (all gold locations within top-k, per the paper):

| arm | file@1 | file@3 | file@5 | file@10 | func@5 | func@10 | fn-MRR | wall/inst |
|---|---|---|---|---|---|---|---|---|
| `for` | 7.3% | 14.3% | 19.5% | 28.8% | **4.8%** | 6.2% | 0.049 | 0.48s |
| `query` | 0.5% | 1.1% | 1.8% | 4.6% | 0.0% | 0.0% | 0.006 | 0.33s |
| **`anchor`** | **8.4%** | **16.6%** | **21.2%** | **29.6%** | 4.5% | **6.8%** | **0.055** | 0.19s |

**Lenient "any gold within top-10"** (recall flavor — *not* the paper's strict Acc; shows the
"surfaced at least one right location" signal that strict multi-file ALL hides):

| arm | file(any)@10 | func(any)@10 |
|---|---|---|
| `for` | 39.8% | 11.1% |
| `query` | 8.9% | 0.7% |
| **`anchor`** | **41.6%** | **12.5%** |

**Parse coverage: 1148/1149 gold functions = 99.9%** (301 `added_functions` excluded, structurally
absent) — ctxpack's parser emits all but one gold function, so the ceiling here is the *ranker*
(relevance ordering), not the parser.

> **Footnote — the earlier n=60 validation slice** (first 60 instances, kept for comparison):
> `for` file@1/5/10 = 0.0/5.0/8.3%, MRR 0.050, lenient file 31.7%; `query` 0.0/3.3/10.0%, MRR 0.035,
> lenient 15.0%; `anchor` 1.7/5.0/11.7%, MRR 0.079, lenient 38.3%; parse coverage 189/189 = 100%.
> The full-run strict numbers are *higher* than the slice's because the instance mix differs sharply:
> **76% of the full set has single-file gold** (median 1) vs only 25% of the first-60 slice (median 3)
> — strict "ALL gold within top-k" is far easier when gold = 1 file. Same harness, same metric.

### Honest reading of these numbers

- **ctxpack ranks *symbols*; LocAgent-style BM25 ranks *files* (whole-file documents).** Our file-level
  score is derived by max-pooling symbol ranks up to their file, a strictly harder granularity for
  file-level Acc@1 — so **these numbers are not comparable to the paper's BM25 file Acc@1 (38.7%)** and
  we do not claim they are.
- **Strict Acc is modest, and we publish it.** Requiring *all* gold locations inside a small top-k is
  unforgiving for a raw, LLM-free ranker on noisy issue prose (checkbox templates, stack traces, "search
  before asking" boilerplate). This is precisely the gap the LocAgent paper motivates LLM agents to fill.
  The multi-file subset stays brutal (the n=60 slice, 75% multi-file, shows single-digit strict file Acc);
  the full-set numbers are lifted by its 76% single-file-gold mix.
- **The lens vs raw lexical is the clearest full-run result**: `--for`/`--anchor` put a correct file in the
  top-10 **~4.5×** as often as `--query` (lenient 39.8/41.6% vs 8.9%; strict file@10 28.8/29.6% vs 4.6%) —
  the focused, structurally-weighted bundle concentrates the right file where the long flat BM25 list buries
  it. The SWE-bench-Lite astropy case is the clean illustration: `--for` ranks the gold file **#1** where
  `--query` ranks it #531.
- **The `--anchor` verdict at full N: the n=60 edge HOLDS.** The 2026-07-05 co-change note said LocBench
  "is the right instrument for a second opinion before deleting or defaulting the mode"; the n=60 slice came
  back mildly positive, and n=560 confirms it: `--anchor` beats `--for` on strict file@1 (8.4% vs 7.3%),
  file@3 (16.6% vs 14.3%), file@5 (21.2% vs 19.5%), file@10 (29.6% vs 28.8%), func@10 (6.8% vs 6.2%),
  first-hit MRR (0.055 vs 0.049), and both lenient metrics (41.6%/12.5% vs 39.8%/11.1%) — losing only
  func@5 by a hair (4.5% vs 4.8%). A **mild but now consistent-at-full-N** win: graph expansion surfaces
  structurally-adjacent locations the task's words miss, exactly its design intent. It is also the *fastest*
  arm (0.19s vs 0.48s/inst). This justifies keeping `--anchor` and graduates the question from "delete it?"
  to "when to recommend it"; the margins (~1pp strict) are still too small to flip the default on their own.
- **Function-level strict Acc stays low (≤7%) and first-hit MRR small (~0.05)** — deterministic symbol
  retrieval on issue text alone does not solve function localization. That is the honest floor, and the
  reason the real product is a *cheap high-recall candidate feed* into a reasoning agent, not a standalone
  answer.

## The honest comparison (cost vs accuracy, not parity)

ctxpack is a **$0, zero-dependency, sub-second, deterministic ranker**. LocAgent / SweRank / Agentless are
**LLM and/or trained-reranker systems** — many API calls and seconds-to-minutes per instance. Their
headline Loc-Bench numbers (for context, **not** a claim of parity):

| system | file Acc@1 | func Acc@5 | cost / determinism |
|---|---|---|---|
| BM25 (file-document) | 38.7% | 31.8% | $0, deterministic (but file-granularity retrieval) |
| E5-base-v2 (embedding) | 49.6% | 39.4% | model inference, non-deterministic |
| Agentless (Claude-3.5) | 72.6% | 58.8% | multi-call LLM |
| LocAgent (Claude-3.5) | 77.7% | 73.4% | multi-call LLM agent |
| **ctxpack `--anchor` (this harness, n=560 full set)** | **8.4%** (strict, symbol max-pool) | **4.5%** (strict) | **$0, deterministic, ~0.19s/inst, symbol-granularity** |

The point of running this is not to beat an LLM agent at localization with a $0 ranker — it is to (a) put
a **published, reproducible** number on ctxpack's deterministic floor, (b) show **parse coverage is not the
bottleneck** (the map sees the code), and (c) frame ctxpack honestly as the **fast, free candidate
generator** that feeds those rerankers (cf. AUDIT4 A4-R6 `--format=candidates`), not their replacement.

## Caveats / limitations

- File ranking = symbol max-pool (first gold-file appearance in the rank-ordered output). A dedicated
  file-granularity retriever would likely score higher on file-level; ctxpack does not emit one.
- Query = the first `--query-chars` (default 1200) of the issue `problem_statement`, verbatim, deterministic.
  No cleaning of issue boilerplate (that would be non-reproducible curation); a longer budget did not move
  the hard cases in spot checks.
- Function match = exact bare-name within the (path-or-basename) matched file; two same-named methods in a
  file are indistinguishable at this granularity (rare).
- Numbers move with the ctxpack binary and the dataset slice; re-run to reproduce. cf. `../BENCHMARK.md`
  (tokens + speed), `../ANSWERQUALITY.md` (co-change + known-item retrieval).
