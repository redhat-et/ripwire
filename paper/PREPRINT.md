# Deterministic, Model-Free Code Localization: a Measured Floor, a Public C++ Localization Benchmark, and a Pre-Registered Negative Result on Graph Expansion

*The ripwire authors.*

> **STATUS — working draft, in preparation. Not submitted anywhere, not peer-reviewed, and not a
> release artifact.** Ported into this repository on **2026-08-03**; every measured number below is
> current as of that date and was reconciled against [`docs/EVALS.md`](../docs/EVALS.md) — this
> project's register of published numbers, its honest counterexamples, and the claims it deliberately
> refuses to publish — plus the pinning files `docs/EVALS.md` names. **Each table states the in-repo
> artifact that pins it.** Markdown is the source of truth for this paper. Numbers taken from other
> systems' papers are cited to those papers, are reproduced as *they* report them, have not been
> independently re-measured here, and are never interleaved with ours as if comparable.
>
> Where this draft and `docs/EVALS.md` disagreed, `docs/EVALS.md` won and the change is stated in the
> text. Numbers move with the binary; a table is a measurement of the version its artifact pins, not
> a permanent property of the tool.

---

## Abstract

Code localization — mapping an issue report to the files and functions a fix must touch — is
dominated by LLM agents and trained embedding retrievers. We evaluate the opposite corner of the
design space: a **deterministic, zero-runtime-dependency, sub-second, symbol-granularity** static
ranker (ripwire) that uses no model, no network, and no randomness, and whose output is
byte-identical run-to-run. We contribute: **(1)** a corrected LocBench evaluation methodology for
symbol-granularity rankers — exact path identity, a frozen repository-disjoint train/held-out split,
repository-clustered paired bootstrap inference, and a zero-silent-skip contract; **(2)** a public
C++ localization benchmark, mined from the human-verified C++ split of Multi-SWE-bench (n=121
issue-report instances across 5 repositories, frozen by content hash) — on which the ranker reaches
any-gold@10 **89.3%** and strict file@10 **55.4%**, while the honest hard number, **multi-file
strict@10, is 32.9%**: complete blast-radius retrieval on large C++ patches remains open headroom;
**(3)** a head-to-head against three local-first repo-mapping tools under one harness, with
per-instance win/loss and loss-bucket analysis; and **(4)** a fully pre-registered **negative
result**: a LARGER-style 1-hop graph-expansion re-ranker ("anchor-hop"), calibrated on train splits
only and judged by a two-tier quality-per-cost gate, was **rejected twice** — held-out strict file@10
+0.41pp (clustered-bootstrap 95% lower bound +0.00pp) on Python, and **exactly +0.00pp** (CI [+0.00,
+0.00]) on the repository- and query-style-disjoint C++ held-out set — despite a +2.6pp train-corpus
signal. We publish the calibration sweeps, the one-shot held-out protocol, the gate verdicts, and the
candidate patches, because the field's ablation tables rarely report the expansions that did not
survive a disjoint held-out set.

---

## 1. Introduction

Localization benchmarks and systems have converged on a pipeline shape: retrieve candidates, then
spend model capacity (agentic exploration, trained rerankers, embeddings) ordering them. Published
systems report strong numbers — LocAgent reports 77.7% file-level Acc@1 with Claude-3.5 on Loc-Bench,
and Agentless 72.6% [1]; SweRank [5] and SWE-Debate [6] push agentic/reranked localization further —
at the cost of API calls, latency, nondeterminism, and infrastructure.

This paper measures what is achievable at the **other** end: a single self-contained binary, C++23,
zero runtime dependencies, whose ranked output is a pure function of (repository bytes, query bytes,
binary version). The motivation is not to beat LLM agents at localization — it is to establish the
**deterministic floor** they build on: (a) a reproducible public number for model-free retrieval at
symbol granularity, (b) evidence that parse coverage is not the bottleneck (the ranker's ceiling is
ordering, not visibility), and (c) a benchmark for a language the public localization sets we are aware
of do not cover: C++.

**Contributions.**

- **C1 — a public C++ localization benchmark** (§3.2, results §4.2): 121 issue-report instances mined
  deterministically from Multi-SWE-bench's human-verified C++ split [2], frozen by content hash with
  a zero-silent-skip scoring contract and an offline CI fixture. The public localization sets we are
  aware of are Python-only (Loc-Bench [1], SWE-bench-Lite–derived sets) or do not isolate C++ with
  localization gold in a retrieval-ready harness. *This primacy claim is a literature claim, not a
  measurement: no gate in this repository can check it, and it is hedged (“we are aware of”, “available to us”) for
  that reason.*
- **C2 — a corrected LocBench methodology for symbol-granularity rankers** (§3.1): exact
  repo-relative path identity (duplicate basenames never earn credit), a frozen repository-disjoint
  train/held-out split, paired repository-clustered bootstrap comparison, and production
  payload/latency measured separately from scored candidate exports.
- **C3 — the measured floor and a same-harness head-to-head** (§4.1, §4.4): held-out strict file@10
  60.9% on Python LocBench for the shipping ranker, and a paired n=60 comparison against aider's
  repo-map, codebase-memory-mcp, and graphify with loss-bucket analysis.
- **C4 — a pre-registered negative result on graph expansion** (§6): two full accept/reject cycles
  with train-only calibration, one-shot held-out evaluation, and a two-tier quality-per-cost gate —
  both honest rejects, with all artifacts committed.
- **C5 — component ablations** (§5): query routing, query-mention anchoring, and lens-vs-raw-BM25,
  each isolated as an on/off arm on frozen datasets.

## 2. The system under test

ripwire parses a repository with tree-sitter (15 vendored grammars: C++, C, ObjC/ObjC++, Python,
TypeScript, JavaScript, Java, Ruby, Bash, Go, Rust, Swift, C#, plus JSON config keys), builds a
symbol graph (definitions, name-resolved call/import/decl-use edges with an explicit ambiguity
counter on guessed edges), and ranks symbols by Personalized PageRank blended with lexical evidence.
The localization surface evaluated here is the task lens `--for`:

- **Lexical scoring** is BM25F over subtoken postings (name/doc/body fields, weights 3/2/1),
  persisted in a content-hashed cache; MaxScore pruning is exhaustive-equivalent (a byte-identity
  gate compares pruned against unpruned output, with pruning disabled by an environment switch).
- **Query routing**: queries that exactly name an indexed symbol route to a name-exact scorer;
  conceptual prose routes to the subtoken/body scorer. Routing is deterministic from the query text,
  and it is **confidence-gated** — `docs/EVALS.md` §4 publishes what an ungated router costs.
- **Mention anchoring**: a file path, dotted module, or `Type.method` literally present in the query
  (including inside URLs) is lifted toward the top of the ranking, and never displaces the top hit.
- **Determinism contract**: no wall-clock, no RNG, no network in any output path; a byte-diff gate in
  `test/regression.sh` enforces byte-identical output across repeated runs and between warm and cold
  cache states; float accumulation orders are fixed.

The evaluated artifact is this repository. Every benchmark harness pins the binary it scored and
verifies each arm run byte-identical twice before scoring.

*Repository-side sources for this section:* [`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) (the
pipeline and the determinism contract), [`README.md`](../README.md) (the vendored grammar count),
[`docs/EVALS.md`](../docs/EVALS.md) §4 (the router's confidence gate, measured).

## 3. Benchmarks and methodology

### 3.1 LocBench (Python) — corrected evaluator

The harness (`bench/locbench/run_locbench.py`) scores Loc-Bench [1] (`czlll/Loc-Bench_V1`, test
split, 560 instances; a SWE-bench-Lite fallback path is also implemented). Each instance:
shallow-checkout the repo at `base_commit`, run the localizer on the first 1,200 characters of the
verbatim issue text, parse the flat ranked candidate export, score against the gold files/functions
the accepted fix patch touched.

Metric definitions follow LocAgent §4.1 exactly: **strict Acc@k** = ALL gold locations inside the
top-k of one flat rank (file@1/3/5/10, function@5/10), plus a clearly-labeled lenient any-gold@10 and
first-hit MRR. The corrected evaluator additionally enforces:

- **exact repo-relative path identity** — duplicate basenames never earn credit;
- **method identity** = file + scope + name; one flat global candidate rank (no grouped-source
  credit);
- a **frozen repository-disjoint train/held-out split** (salted SHA-256 over repository names,
  committed in `bench/locbench/dataset.lock`): train 317 instances / 87 repositories, held-out 243 /
  78;
- **zero silent skips** — a checkout, index, or localizer failure aborts the run loudly;
- **paired repository-clustered bootstrap** for every before/after comparison
  (`bench/locbench/compare_runs.py`; 10,000 deterministic seeded resamples, clusters =
  repositories);
- **production cost measured separately from scored output**: per instance, the real production
  bundle is timed with 5 warm samples + 1 cold (cache-less) sample + 1 index rebuild, sequentially,
  run alone; the scored candidate export is never the timing payload;
- **structural honesty rules**: functions the fix patch *adds* do not exist at `base_commit`, are
  un-findable by any static localizer, and are excluded from denominators and reported separately;
  parse-coverage misses count as automatic misses. On the full 560-instance set, parse coverage is
  **1148/1149 gold functions = 99.9%** — the ceiling is ranking, not parsing.

*Pinned by:* `bench/locbench/README.md`, `bench/locbench/dataset.lock`, `bench/locbench/full560.json`;
summarized in `docs/EVALS.md` §3.

**Granularity caveat, stated up front:** ripwire ranks *symbols*; file ranks are derived by
max-pooling symbol ranks to their file. This is a strictly harder granularity for file-level Acc@1
than file-document retrieval, so our file-level numbers are **not comparable to file-granularity BM25
baselines** in [1], and we do not claim they are (§4.5 keeps the two tables separate).

### 3.2 The Multi-SWE C++ split

No public, human-verified, issue-report-shaped C++ localization benchmark was available to us. We
built one (`bench/multiswe/run_multiswe.py`) by mining Multi-SWE-bench [2] — reported there as 1,632
human-verified, test-passing PRs across 8 languages, curated by 68 expert annotators — down to its C++
split (pinned Hugging Face dataset revision
`56ff018c04a38e27ada1e9d0a6d5839a51f88f0d`, recorded with the dataset's license statement in
`bench/multiswe/dataset.lock`).

Per instance: **query** = the linked GitHub issue's title + body (`resolved_issues` — written by
someone who does *not* yet know the fix; the same query shape Loc-Bench uses, and deliberately harder
than post-hoc commit messages). **Gold** = the language-extension source files the PR's `fix_patch`
touches, excluding files the patch adds (structurally absent from the indexed base tree). The
repository is shallow-checked-out **at `base.sha`**, never the fix commit. Gold functions are derived
best-effort from git's own hunk-header context and recorded per instance but **not scored** — hunk
context is too coarse to back a strict function-level claim, and we decline to publish a number we
cannot defend.

Mining is deterministic and every exclusion is counted (`mining_stats` in the lock): non-empty linked
issue (at least four words), non-empty patch touching at least one non-added file in the split's
extensions, and a hygiene rule excluding issue texts that embed a contributor's local home-directory
path. The C++ split yields **n=122 mined / 121 scored** (one instance's gold is outside the indexable
universe; the reason is printed, not silently dropped) across catchorg/Catch2, fmtlib/fmt,
nlohmann/json, simdjson/simdjson, and yhirose/cpp-httplib. The C split (zstd, jq, ponyc)
is minable by the same harness (`--languages=c,cpp`) but is not in the committed lock; this paper
mines and scores the C++ split.

Scoring is identical in shape to §3.1 (strict file@k per [1] §4.1, lenient any@10, first-hit MRR);
every arm run is verified byte-identical twice; an offline fixture gate (`test/multiswecheck.sh`, no
network) locks the mining, tamper-rejection, and scoring contracts in CI.

*Pinned by:* `bench/multiswe/README.md`, `bench/multiswe/dataset.lock`, `test/multiswecheck.sh`.

### 3.3 cppbench (SFML) — a commit-message C++ set, used as train/calibration only

`bench/cppbench/run_cppbench.py` mines 120 instances from SFML's own history (pinned commit recorded
in `bench/cppbench/dataset.lock`; 115 scored, 5 unindexable): query = the commit message, gold = the
1–5 `.cpp/.h/.mm` files that commit touched, repository archived at the parent commit. Its documented
caveats matter: commit messages are written by the person who already fixed the bug (an easier,
non-portable query distribution), and it is one repository. We therefore use it **only as a
calibration/train split** (§6.3) and never as an acceptance set. Full mining rules, exclusion counts,
and corpus-selection rationale: `bench/cppbench/README.md`.

### 3.4 Acceptance methodology: pre-registration + a two-tier quality-per-cost gate

Every ranking change in this program is accepted or rejected by a gate **fixed before any candidate
run**, in the ablation discipline the strongest recent localization work uses (LARGER's
component-wise ablation table [4] is the design precedent), extended with three rules we found
necessary for honesty:

1. **Train-only calibration.** Free parameters are swept on the train split only; chosen constants
   are baked into the binary before the held-out run. Calibration sweeps are committed as JSON.
2. **One-shot held-out.** The held-out set is run once per arm after constants are baked. No re-runs
   after seeing numbers; unavoidable protocol deviations are logged in the verdict file as evidence
   *against* the run, not for it.
3. **The two-tier gate** (`bench/locbench/GATE_DECISION.md`; comparator
   `bench/locbench/compare_runs.py`):
   - **Tier 1 — absolute interactive-SLA ceiling**, computed from the candidate run's own absolute
     p95 latencies (not relative caps, which drift release-over-release): warm p95 at most 775 ms,
     cold p95 at most 1,650 ms on the real held-out corpus.
   - **Tier 2 — utility ratio**: the repository-clustered bootstrap **95% lower bound** of the paired
     strict file@10 delta, divided by a weighted cost delta (0.5·warm-p50 + 0.5·token-p50
     paired-ratio deltas), must be at least R = 2.5; if weighted cost is not positive, a quality lower
     bound above zero suffices (Pareto branch).

**A correction the port had to make.** An earlier version of this section described the two-tier gate
as this project's acceptance *policy*. It is not. `bench/locbench/GATE_DECISION.md` says on its own
first lines that it is a **proposal**, opt-in in the comparator; the comparator's default remains the
legacy gate and is byte-identical to it (`docs/EVALS.md` §3). What is accurate is narrower and is
what this paper claims: the two-tier gate was **pre-registered and applied to the two acceptance
decisions in §6**, and their verdict files record it doing so.

The gate's clustered lower bound is deliberately conservative: a mean improvement whose lower bound
is 0.00pp is treated as unproven, whatever the mean says. §6 shows this bar doing its job twice.

## 4. Results

All ripwire numbers in this section are from the committed artifacts named under each table, at the
binary versions those artifacts pin. "Strict" always means LocAgent's ALL-gold-in-top-k.

### 4.1 Python LocBench, held-out n=243 — the shipping ranker

| arm | file@1 | file@3 | file@5 | file@10 | lenient@10 | func-any@10 | fn-MRR | single-file strict | multi-file strict |
|---|---|---|---|---|---|---|---|---|---|
| routed `--for` (shipping) | 19.3% | 38.3% | 51.0% | **60.9%** | 74.9% | 38.7% | 0.213 | 73.4% | 18.2% |
| pre-routing baseline | — | — | — | 27.6% | 36.2% | 11.1% | 0.053 | 33.5% | 7.3% |

*Pinned by:* `bench/locbench/README.md` (corrected-evaluator section), `bench/locbench/dataset.lock`;
republished in `docs/EVALS.md` §3. N = 243, zero exclusions, 564/564 scoped gold functions covered.

Paired deltas across 243 instances in 78 repository clusters: **strict file@10 +33.33pp**, 95%
clustered-bootstrap lower bound **+25.00pp**; lenient +38.68pp; MRR +0.160; multi-file strict
+10.91pp. Cost ledger for that gain: warm p50 +3.4%, cold p50 +3.0%, index p50 +4.4%, and the
production token ceiling p50 **−39.4%** — more accurate *and* cheaper, which is why it shipped.

**A number this port deliberately did not carry over.** An earlier draft headlined this table with
held-out strict file@10 **66.7%**. That figure is real, but it is the **baseline arm of the
anchor-hop experiment** at that experiment's own binary — not this project's published shipping
number — and `docs/EVALS.md` §8 lists it among the claims this project refuses to publish in that
role, precisely because it circulates detached from the arm it belongs to. It appears in this paper
only in §6, labeled as what it is. The 60.9% row above is the published figure. The gap between the
two is not a contradiction; it is version coupling (§7), and it is the reason every table here names
the artifact that pins it.

Multi-file strict@10 on this split is **18.2%** — the same single-versus-multi cliff every corpus in
this paper shows.

### 4.2 The C++ benchmark — Multi-SWE C++ split, n=121

| arm | file@1 | file@3 | file@5 | file@10 | any@10 | MRR | wall/inst |
|---|---|---|---|---|---|---|---|
| `--for` (shipping default) | 8.3% | 36.4% | 47.9% | **55.4%** | **89.3%** | 0.465 | 0.17 s |
| `--for --no-mention-boost` | 8.3% | 35.5% | 45.5% | 53.7% | 86.8% | 0.447 | 0.09 s |
| `--query` (raw BM25) | 8.3% | 35.5% | 45.5% | 53.7% | 86.8% | 0.447 | 0.09 s |

Strata (`--for`): **single-file instances (n=51): strict@10 86.3%**; **multi-file instances (n=70):
strict@10 32.9%** — the multi-file figure identical across all three arms.

*Pinned by:* `bench/multiswe/results/cpp_scoreboard.md` (machine-generated), per-instance rows in
`bench/multiswe/results/cpp.json`, frozen instance list in `bench/multiswe/dataset.lock`.

**The honest headline is both numbers.** any@10 89.3% says a deterministic ranker almost always
surfaces at least one correct file from a raw C++ issue report in about 0.2 s at zero marginal cost.
**Multi-file strict@10 32.9%** is the hard truth beside it: complete blast-radius retrieval — every
file the fix touched inside the top-10 — fails two times out of three. §6 is the record of our first
two attempts to close exactly that gap. Two further readings: file@1 (8.3%) is low by construction —
strict@1 can only score when gold is a single file; read it with the single-file stratum (86.3% @10).
And all arms tie on the multi-file stratum: terse issue reports on these libraries rarely name enough
files for any query-side lever to separate arms.

Constructing the benchmark also improved the tool — scoring it exposed a tree-sitter error-recovery
blowup on a parser-torture corpus (43 s on one 100 KB file) that was fixed before these numbers were
produced. A benchmark that cannot hurt you cannot help you.

### 4.3 cppbench (SFML), n=115 — commit-message queries

| arm | file@1 | file@3 | file@5 | file@10 | any@10 | MRR |
|---|---|---|---|---|---|---|
| `--for` | 7.0% | 14.8% | 20.0% | 31.3% | 45.2% | 0.219 |
| `--for --no-mention-boost` | 7.0% | 14.8% | 20.0% | 31.3% | 45.2% | 0.219 |
| `--query` | 7.0% | 14.8% | 20.0% | 31.3% | 45.2% | 0.219 |

Strict@10 by gold size: single-file (n=72) **47.2%**; multi-file (n=43) **7.0%**.

*Pinned by:* `bench/cppbench/results/sfml_scoreboard.md` (machine-generated), per-instance rows in
`bench/cppbench/results/sfml.json`, `bench/cppbench/README.md`; strata republished in
`docs/EVALS.md` §7.

All three arms are byte-value identical here: SFML's terse changelog-style messages (`Fixed X`) give
the mention anchor nothing to anchor and the lens nothing to frame. This is itself a finding about
query distributions (§5), and the reason this set is train-only in §6.3.

**The public-versus-private divergence, stated as `docs/EVALS.md` §7 states it.** An earlier version
of this benchmark ran on a private corpus and scored far higher — roughly **89% any@10** and **0.62
first-hit MRR** — against the public SFML figures above (31.3% strict file@10, 45.2% any@10, 0.22
MRR). The private corpus was removed for public release and its numbers are **no longer reproducible
from this tree**; `docs/EVALS.md` §8 accordingly declines to publish the private absolutes at all,
this paper carries only the rounded framing §7 itself uses, and does not restate the private strict file@10 figure. The mechanism behind the gap is visible in the query shape: the
private corpus's commit messages were long, identifier-dense technical notes (an easy retrieval
shape); SFML's are terse changelog summaries whose vocabulary barely overlaps the code. **A benchmark
that produced easier-looking numbers from a harder-to-publish corpus is not evidence, and the public
number is the baseline going forward.**

### 4.4 Head-to-head under one harness (Python LocBench, n=60 paired held-out slice)

Four local-first, no-API-key arms, identical checkouts, identical gold, and the **same metric code
imported unmodified** from the LocBench harness; zero exclusions in any arm. Versions pinned in the
report: aider-chat 0.86.2 (repo-map, fed the issue through its own ident-extraction),
codebase-memory-mcp 0.9.0 (its shipping BM25 graph-search path), graphifyy 0.9.15 (local BFS
traversal, `PYTHONHASHSEED=0` — see below). The slice is deliberately hard: 40 of 60 instances have
multi-file gold.

| arm | file@1 | file@3 | file@5 | file@10 | any@10 | median wall |
|---|---|---|---|---|---|---|
| **ripwire `--for`** | 5.0% | **18.3%** | **26.7%** | **36.7%** | **75.0%** | **0.074 s** (warm, pre-built index) |
| codebase-memory-mcp | **6.7%** | 10.0% | 16.7% | 26.7% | 66.7% | 1.14 s |
| graphify (BFS order) | 0.0% | 3.3% | 5.0% | 21.7% | 41.7% | 5.8 s |
| aider repo-map (personalized) | 0.0% | 1.7% | 6.7% | 13.3% | 33.3% | 2.5 s |
| aider repo-map (no persona) | 0.0% | 1.7% | 3.3% | 10.0% | 26.7% | — |

Win/loss (strict file@10): against aider **16–2**, against codebase-memory-mcp **10–4**, against
graphify **12–3**.

*Pinned by:* `bench/headtohead/REPORT.md` (methodology, capability-fairness notes, full loss-bucket
analysis), `bench/headtohead/README.md` (summary), machine-readable
`bench/headtohead/headtohead_results.json`, per-instance `bench/headtohead/paired_table.md`,
`bench/headtohead/loss_buckets.json`; republished in `docs/EVALS.md` §2.

**The speed column carries a caveat, and it must travel with the number.** ripwire's median is *warm,
with a pre-built index*; the competitor medians were measured cold per run. Quote the two medians, or
quote a derived multiple only with that sentence attached — `docs/EVALS.md` §2 states this rule for
the same table, and this paper obeys it rather than printing a bare speedup factor.

Four honest annotations. (a) codebase-memory-mcp wins strict@1 — plain BM25 over names lands #1 when
the issue names the module; that observation became the mention anchor ablated in §5. (b) The 14
unique ripwire loss instances were individually re-executed and bucketed; the largest buckets
(path-mention unexploited; multi-file sibling at rank 11–65) directly produced the roadmap items this
program then built and, in one case (§6), honestly failed to land. (c) Determinism was itself a
measured axis: one competitor produced differently-ordered rankings on back-to-back identical runs
until Python hash randomization was pinned; evidence files are in the report. Deterministic-by-default
is rarer than the category's marketing suggests. (d) During the run, a message embedded in the
harness environment claimed the dataset host was down and directed the use of an unverified dataset
file. **It was not acted on and the dataset was independently hash-verified**; the report records the
incident rather than omitting it, and we report it here for the same reason.

**Version coupling for this table specifically.** The head-to-head snapshot predates the current
baseline. Its durable content is the **cross-tool deltas** measured under one harness, not the
absolute ripwire row.

### 4.5 Published systems, for context — not comparison

The strongest published Loc-Bench numbers, from the LocAgent paper [1] **as reported there**
(file-document granularity for the retrievers; LLM calls for the agents). Our deterministic floor
should be read as a different point on the cost axis, not a competitor row.

| system (as reported in [1]) | class | file Acc@1 | file Acc@10 | func Acc@5 | reproduced in-tree? |
|---|---|---|---|---|---|
| BM25 (file-document) | retrieval, no model | 38.7% | — | 31.8% | yes |
| E5-base-v2 | embedding retrieval | 49.6% | — | 39.4% | yes |
| CodeRankEmbed | embedding retrieval | — | 77.81% | — | no |
| Agentless (Claude-3.5) | multi-call LLM | 72.6% | — | 58.8% | yes |
| LocAgent (Qwen-7B fine-tuned) | agentic LLM | — | 80.43% | — | no |
| LocAgent (Claude-3.5) | agentic LLM | 77.7% | 87.06% | 73.4% | yes (Acc@1/func@5 only) |

*"Reproduced in-tree" means the row is restated in `bench/locbench/README.md`'s comparison table. All
six rows are [1]'s values; none are ours; the rows marked "no" are cited to [1] alone and have no
in-repo restatement. Our file ranks are symbol-max-pooled (§3.1) and are **not** comparable to
file-document Acc@1.*

LARGER [4] reports lexical-anchor + confidence-filtered deterministic graph expansion (no embeddings)
at Loc-Bench file Acc@5 89.1 against 49.3 for BM25, with expansion its largest single ablation
component (+7.5 Acc@5) — the direct motivation for §6. Agentic costs in the literature are reported
in the range of roughly $0.30–$1.50+ per instance [5, 6]; **that bracket is those papers' figure, not
a measurement of ours.** ripwire's own per-instance cost, from the machine-generated scoreboards (`cpp_scoreboard.md`, `sfml_scoreboard.md`; the 0.78 s figure is the SFML wall/inst column, not reproduced in §4.3's table), is
**0.17–0.78 s of local CPU** with no API call.

**An arithmetic claim this port removed.** An earlier draft summarized the gap as "LocAgent-class
agents buy roughly +20pp file@10 over this floor." That subtraction depended on the 66.7% figure
§4.1 retired, and it compares a symbol-max-pooled held-out slice against a file-document full-set
number across two papers — exactly the comparison §3.1 forbids. The honest frame survives without
the arithmetic: **the deterministic floor is the candidate feed such systems rerank, not their
rival**, and it is separated from them by orders of magnitude in latency and by a per-call price.

## 5. Ablations

Each retrieval component is isolated as an on/off arm on a frozen dataset (component-wise, in the
style of [4]'s ablation table). All numbers appear with their source artifact in §4; this table
collects them.

| component (arm toggled) | dataset | metric | off → on |
|---|---|---|---|
| routed lexical scorer (against the pre-routing ranker) | LocBench held-out n=243 | strict file@10 | 27.6% → 60.9% (+33.33pp, LB +25.00pp) |
| task lens (`--for` against raw `--query` BM25) | LocBench full 560 | strict file@10 | 4.6% → 28.8% |
| task lens (`--for` against raw `--query` BM25) | LocBench full 560 | lenient file@10 | 8.9% → 39.8% (about 4.5×) |
| mention anchor | Multi-SWE C++ n=121 | strict file@10 | 53.7% → 55.4% (+1.7pp) |
| mention anchor, single-file stratum | Multi-SWE C++ n=51 | strict file@10 | 82.4% → 86.3% (+3.9pp) |
| mention anchor | cppbench SFML n=115 | strict file@10 | 31.3% → 31.3% (+0.0pp) |
| anchor-hop 1-hop graph expansion | LocBench held-out n=243 | strict file@10 | +0.41pp, LB +0.00pp — **rejected** (§6.2) |
| anchor-hop, C++ recalibrated | Multi-SWE C++ n=121 | strict file@10 | 55.4% → 55.4% (+0.00pp exactly) — **rejected** (§6.3) |

*Pinned by:* rows 1–3 `bench/locbench/README.md`; rows 4–5 `bench/multiswe/results/cpp_scoreboard.md`;
row 6 `bench/cppbench/results/sfml_scoreboard.md`; rows 7–8
`bench/locbench/results/r1_anchorhop/gate_verdict.txt` and
`bench/locbench/results/r1cpp_anchorhop/gate_verdict.txt`. The mention-anchor rows are republished in
`docs/EVALS.md` §4.

**A correction the port had to make.** An earlier draft reported the mention anchor's single-file
stratum as **+4.9pp**. The machine-generated scoreboard gives 86.3% against 82.4% = **+3.9pp**, which
is also the figure `docs/EVALS.md` §4 publishes. The draft's number was an arithmetic error and is
corrected here.

Two structural lessons. **Query distribution decides which components pay.** The mention anchor is
worth +3.9pp on single-file issue reports that name code, and exactly +0.0pp on terse commit
messages — the same component, the same code, a different query population. Any localization paper
reporting a single pooled number for a query-side component is averaging over this axis silently.
**The routed scorer is the floor's load-bearing wall** — one accepted change is +33pp of the total;
everything since (including both §6 attempts) has fought for single points against a much stronger
baseline than the literature's BM25 rows.

## 6. The pre-registered negative result: anchor-hop graph expansion

This section is the paper's credibility centerpiece, reported at the same level of detail a win would
get. LARGER's ablation [4] identifies graph expansion as its largest single component. We implemented
the analogous mechanism twice under pre-registered gates, and it failed the held-out bar twice. The
artifacts — calibration sweeps, one-shot held-out runs, comparator verdicts, and the full candidate
implementation patches — are committed so any future attempt starts from the actual record rather
than our summary of it.

### 6.1 Design (fixed before implementation)

Scope: the conceptual (subtoken/body) route only — the name-exact route is contractually byte-frozen.
Mechanics: take the top-m (m=10) anchors from the existing ranked list; propagate `α · anchorScore ·
ω(edge)` to 1-hop call/import/decl-use neighbors, with ω = 1/(1 + ambiguous-call-count) discounting
resolver-guessed edges; θ-filter the propagated mass; cap additions at 2m; re-rank the union. α and θ
are calibrated on train only.

One implementation finding worth publishing: per-candidate hop mass must combine supporting edges by
**MAX, not SUM**. Summing lets a hub shared by many anchors accumulate several anchors' worth of mass
and outrank the true top lexical hits — measured train strict@1 collapsed **27.1% → 8.2%** at α=0.2
under SUM before the rule was fixed. MAX bounds any candidate at α·topAnchorScore (with α < 1, a
hop-only candidate can never displace the #1 hit) and is order-independent.

*Pinned by:* `bench/locbench/anchorhop_calib.json` (`combination_rule_finding`).

### 6.2 Attempt 1 (Python-primary)

Train (n=317): the strict@10 delta plateaus at **+0.95pp** for α ∈ [0.05, 0.15] and decays above,
with @1/MRR damage growing monotonically in α; we chose α=0.10 / θ=0.50 (θ not binding under the MAX
rule). Held-out (n=243, release timing protocol, one shot):

| arm | strict f@10 | lenient@10 | fn-MRR | warm p50 / p95 | token p50 |
|---|---|---|---|---|---|
| baseline (hop off) | 66.7% | 79.0% | 0.2328 | 145.6 / 772.0 ms | 3,141 |
| candidate (α=0.10, θ=0.50) | 67.1% | 79.8% | 0.2316 | 145.9 / 761.5 ms | 3,140 |

**Read this table as what it is.** Both rows are arms of *this experiment*, at *this experiment's*
binary. The 66.7% baseline is **not** the shipping figure of §4.1 (60.9%, a different binary and the
one this project publishes), and `docs/EVALS.md` §8 exists partly because that 66.7% has circulated
detached from this table. The experiment's result is the **delta**, and the delta is what the gate
judged. (One register correction landed with this port: `docs/EVALS.md` §8 previously mislabelled this baseline arm as the train slice; the pinning file's `heldout_acceptance` block is unambiguous and the register now says held-out, n=243.)

Paired, 78 repository clusters: strict f@10 **+0.41pp, 95% lower bound +0.00pp**; lenient +0.82pp;
warm p50 +2.8% / p95 +10.2%; token p50 +0.2%. Gate: tier-1 **PASS** (761.5 ms / 1,623.8 ms against
775 / 1,650 ceilings); tier-2 **FAIL** — quality lower bound +0.00pp over weighted cost +1.50% = ratio
0.000, against a minimum of 2.5 → **REJECT**; the ranking change was reverted.

*Pinned by:* `bench/locbench/results/r1_anchorhop/gate_verdict.txt` (the verdict quoted above), both
release JSONs in the same directory, calibration `bench/locbench/anchorhop_calib.json` (whose
`baseline_absolute` block pins every baseline figure in the table), candidate diff
`r1_candidate_implementation.patch`, gate script + fixture archive
`r1_gate_and_fixture.tgz`.

Post-hoc diagnosis, recorded with the reject: (a) the p95 cost was not the hop math but a **pruning
giveback** — the expansion consumes the full score distribution, forcing exact MaxScore pruning off
on the conceptual route; (b) the quality lever underdelivered relative to [4] partly because the
baseline it had to beat is far stronger than the BM25-class baselines expansion is usually measured
against, and mention anchoring already captures much of the "structurally adjacent" win on
issue-style queries. One informational signal survived: on the C++ cppbench train set the same
candidate gained **+2.6pp** strict@10 (31.3% → 33.9%) — C++ call-graph evidence is denser than
Python's — motivating a C++-primary retry.

### 6.3 Attempt 2 (C++-primary retry, gate pre-registered before any run)

The retry fixed attempt 1's cost root cause first: a **top-m-anchor-restricted exact bound re-enables
MaxScore pruning under expansion** (K′ = max(consumerK, m) keeps the top-m anchors provably exact;
hop mass reads only anchor scores + edge evidence; the θ-surviving candidates, capped at 2m, are
re-scored bit-identically from retained integer BM25 statistics), gated by a byte-identity test of
pruned against unpruned output under a firing expansion. The cost problem of §6.2 is thereby solved
and the solution archived — independent of the quality outcome.

The pre-registered gate (`bench/locbench/results/r1cpp_anchorhop/GATE_DECISION_r1cpp.md`, committed
before the calibration sweep): train = cppbench SFML (n=115); **held-out = the Multi-SWE C++ split
(n=121) — repository-disjoint AND query-style-disjoint** (calibrate on post-hoc commit messages,
accept on issue reports; the strongest generalization test the two frozen locks can express). Same
two-tier gate; clustering = the 5 held-out repositories; strict file@10 pre-registered as primary;
one shot; a Python no-regression guard and a cost spot-guard; a shipping decision tree fixed in
advance.

Calibration on train found a stronger optimum than attempt 1's: α=0.40 / θ=0.75, **+3.48pp** train
strict@10 with no @1/MRR damage (the grid extension above the pre-registered α range is logged in the
calibration JSON as a train-only deviation). Held-out, one shot:

| held-out metric (n=121, 5 repository clusters) | baseline | candidate | Δ |
|---|---|---|---|
| strict file@1 | 8.3% | 11.6% | +3.31pp |
| strict file@3 | 36.4% | 35.5% | −0.83pp |
| strict file@5 | 47.9% | 47.9% | +0.00pp |
| strict file@10 (**pre-registered primary**) | 55.4% | 55.4% | **+0.00pp**, 95% CI [+0.00, +0.00] |
| lenient any@10 | 89.3% | 88.4% | −0.83pp |
| first-hit MRR | 0.4654 | 0.4896 | +0.0243 |
| single-file strict@10 (n=51) | 86.3% | 86.3% | +0.00pp |
| multi-file strict@10 (n=70) | 32.9% | 32.9% | +0.00pp |

Tier-2 is unpassable at a lower bound of +0.00 for any cost value → **REJECT, decided by the quality
tier alone**; the timing protocol and the Python guard were skipped as moot, both logged as
deviations in the verdict rather than omitted. The result is not vacuous: **32/121 instances changed
first-hit rank**, 21/121 changed worst-gold rank, and strict@1 moved **+4 / −0** instances — the
expansion genuinely fires and reshuffles *within* the top-10, but never moved a gold file across the
@10 frontier in either direction. The train signal (+2.6pp on SFML in §6.2; +3.48pp recalibrated) did
not generalize off its corpus, the same qualitative failure as the Python attempt.

*Pinned by:* `bench/locbench/results/r1cpp_anchorhop/` — `GATE_DECISION_r1cpp.md`,
`anchorhop_calib_cpp.json`, `gate_verdict.txt` (the source of every row above), held-out quality
JSONs, comparator `compare_cpp.py` + timing script `timing_multiswe.py`, train JSONs, candidate diff
`r1cpp_candidate_implementation.patch`, gates + fixture archive `r1cpp_gate_and_fixture.tgz`.

### 6.4 What the negative result establishes

1. **A single-corpus expansion signal — even a clean, monotone, calibrated one — is not evidence.**
   Both attempts had real train-split wins (+0.95pp plateau; +2.6pp / +3.48pp) that went to exactly
   zero on repository-disjoint held-out sets. Ablation tables computed on one corpus, or without a
   disjoint split, would have shipped this component twice.
2. **The gate's conservatism is load-bearing.** A mean +0.41pp with a lower bound of +0.00pp reads
   like "small win" in a results table; the clustered lower bound correctly identified it as
   unproven.
3. **The hop moves first-hit metrics, not the strict frontier.** Consistent @1/MRR movement in both
   attempts (strict@1 +3.31pp, MRR +0.024 on C++) is the honest surviving hypothesis: a *first-hit*
   retrieval improvement, which a future attempt must pre-register as primary from the start —
   reported here as a hypothesis precisely because switching primary metrics after seeing these
   numbers would be the post-hoc move the protocol exists to prevent.
4. **The engineering survives the science.** The pruning-under-expansion mechanism (§6.3) is correct,
   byte-identity-gated, and archived; any future expansion retry starts with attempt 1's cost problem
   already solved.

**The sequel, and why it strengthens rather than softens this section.** The same discipline was
applied again after these two attempts, to the shipped experimental `--anchor` expansion mode, and it
reached the same verdict: a candidate measuring **+0.41pp paired with a 95% lower bound of +0.00pp**
was **rejected outright by the acceptance gate**. Both `--anchor` and `--cochange-boost` are
consequently dropped from the binary's help text and refuse to run without an explicit development
environment variable, with their evaluation records attached rather than deleted. That policy — keep
the negative result runnable, keep it out of the default surface, publish its number — is stated in
`docs/EVALS.md` §7 and `docs/METHODOLOGY.md` §5.

## 7. Limitations and threats to validity

- **Granularity.** Symbol-max-pool file ranking depresses file@1 relative to file-document
  retrievers (§3.1); our numbers under-state what a dedicated file-granularity mode would score, and
  no cross-paper file@1 comparison should be made against [1]'s BM25 rows.
- **Version coupling — the sharpest threat in this paper.** Numbers move with the binary. §4.1
  publishes 60.9% and §6.2 tabulates a 66.7% baseline arm; both are correct measurements of different
  binaries, and the only defense is that every table names the artifact that pins it. A reader
  comparing two numbers in this paper must first check they came from the same artifact.
- **C++ held-out breadth.** Five repositories (one contributing a single instance) is thin for
  clustered inference; the C split (zstd/jq/ponyc) is minable by the same harness but not in the
  committed lock, and widening the repository base is the benchmark's most valuable future increment. MULocBench [3] is
  documented in the harness as the next adoption for the non-code-gold axis (configs, docs), which
  every set here structurally omits.
- **Query construction.** Verbatim issue text truncated at 1,200 characters, no boilerplate cleaning
  — reproducible, but it under-serves issues whose signal sits below checkbox templates and stack
  traces.
- **Function-level gold in C++** is recorded but unscored (hunk-header derivation is too coarse); the
  benchmark currently measures file-level localization only.
- **Head-to-head staleness.** The §4.4 snapshot predates the current baseline; its cross-tool deltas,
  not its absolute ripwire row, are the durable content. Competitor tools were run through their real
  shipping local paths, with capability-fairness notes recorded in the report; their hosted/LLM modes
  were out of scope.
- **Selection effects.** Multi-SWE-bench's curation (merged, test-verified PRs on popular libraries)
  and our mining filters define a particular population of C++ fixes; `mining_stats` in the lock make
  the filters auditable, but generalization to private industrial C++ is a claim we do not make — and
  the public-versus-private divergence in §4.3 is a *measured* example of exactly that
  non-portability.
- **External numbers are not re-measured.** Every figure attributed to [1]–[7] is reproduced as those
  works report it. We did not re-run any of those systems.

## 8. Reproducibility statement

Every benchmark in this paper is reproducible from this repository with no credentials: frozen
`dataset.lock` files pin instance sets, base SHAs, query hashes, and (for Multi-SWE) the upstream
dataset revision; harnesses re-verify locks by content hash and refuse tampered inputs; every scored
arm run is executed twice and byte-compared before scoring; scoring is LLM-free and RNG-free; offline
CI fixtures (`test/multiswecheck.sh`, `test/cppbenchcheck.sh`) lock the harness contracts without
network. One-command reproduction blocks are in `bench/locbench/README.md`,
`bench/multiswe/README.md`, and `bench/cppbench/README.md`; `docs/EVALS.md` §9 lists the shortest path
from a clean clone to a number. The system under test is itself deterministic by contract (two-run
byte-identity is a release gate), so a third party re-running any table needs only the pinned binary
version and the lock files.

## 9. Where this paper is going

The draft above makes one contribution: a measured deterministic floor for code localization, with a
public C++ benchmark and a negative result attached. A **second** contribution is now available in
this repository and is being folded into the next revision. It is a methodology claim, and it is
arguably the more transferable of the two:

- **An adversarial audit loop with a measured hit rate.** Every document that makes claims — the
  tool's own output included — is treated as a claims corpus and audited by a reviewer whose explicit
  job is to find the round *broken*, not to approve it. **Eighteen consecutive audit rounds each
  found real defects**, including in the document that records the count. Equally important, the
  reviewer's findings are claims rather than verdicts: more than once a reviewer's factual claim was
  refuted by measurement, and the measurement won. (`docs/LINEAGE.md`, `docs/METHODOLOGY.md` §4.)
- **Gate-before-code, and the gate that cannot see what it asserts.** The dominant failure mode is
  not a missing test but a *green* one: a gate asserting a degrade path that the release build
  compiles out, or a probe anchored on a commit that turns out to be documentation-only. The fix in
  the first case was structural — build and run the whole suite in **both** build flavours — and it
  is why this project's CI compiles the tree twice. (`docs/METHODOLOGY.md` §1,
  `docs/ARCHITECTURE.md`.)
- **Sibling-completeness as the dominant defect class.** A fix lands on one member of a family and
  almost never on its siblings; the practice that follows — enumerate the family, gate the family —
  is the highest-yield habit recorded here. (`docs/METHODOLOGY.md` §3.)
- **Gated claims: documentation that cannot silently diverge from the binary.** This is the part with
  the most direct bearing on a paper. Prose claims in this repository are machine-checked: every
  command-line flag named in a shipped prose surface must exist in the binary's own help output or be
  allowlisted with a reason (`test/deckcheck.sh` — **including this paper**); the counts asserted in
  `docs/LINEAGE.md` and the README are re-derived from the underlying tables on every run
  (`test/readmedriftcheck.sh`); the token-economy figures are recounted from the live repository and
  fail on drift beyond a stated tolerance (`test/showcasecapturecheck.sh`); the gate list itself
  cannot rot (`test/manifestcheck.sh`); and the generated command reference is proven to document
  exactly the binary's flag set, in both directions (`test/docscommandscheck.sh`).

The intended shape of the revision is *not* to rewrite the localization result in methodology terms.
It is to present the localization program of §3–§6 as the **worked example** of a claims-gating
method, with §6's double reject as the case where the method cost the project a feature it wanted —
which is the only kind of evidence that a method is more than a preference.

## References

Every external number in this paper appears in one of these works, is reproduced as that work reports
it, and was not re-measured here.

1. **LocAgent: Graph-Guided LLM Agents for Code Localization.** arXiv:2503.09089, ACL 2025. Defines
   the Loc-Bench dataset (`czlll/Loc-Bench_V1`) and the strict Acc@k metric used throughout this
   paper; source of the published baseline/agent numbers in §4.5.
2. **Multi-SWE-bench: A Multilingual Benchmark for Issue Resolving.** ByteDance-Seed,
   arXiv:2504.02605, NeurIPS 2025. Hugging Face dataset `ByteDance-Seed/Multi-SWE-bench`, revision
   `56ff018c04a38e27ada1e9d0a6d5839a51f88f0d` (pinned in `bench/multiswe/dataset.lock` together with
   the dataset card's license statement). The human-verified C/C++ PR corpus §3.2 mines.
3. **MULocBench.** arXiv:2509.25242, 2025. 1,100 issues across 46 Python projects with non-code gold
   (configs, docs); reports all tested methods, including LLM-prompted ones, under 40% file-level
   Acc@5/F1. Adopted (documented, not yet scored) as this harness's next set — see
   `bench/multiswe/README.md`.
4. **LARGER.** arXiv:2605.16352, 2026. Lexical anchors + confidence-filtered deterministic graph
   expansion, no embeddings; reports Loc-Bench file Acc@5 89.1 against 49.3 for BM25, with expansion
   the largest single ablation component (+7.5 Acc@5). The design precedent for §6 and for §5's
   ablation style.
5. **SweRank.** arXiv:2505.07849, 2025. Trained-reranker localization; cited for the cost/accuracy
   frontier context in §4.5.
6. **SWE-Debate.** arXiv:2507.23348, 2025. Agentic localization (81.67% file-level reported); cited
   with [5] for the agentic per-instance cost bracket in §4.5.
7. **ARISE.** arXiv:2605.03117, 2026. Reports the retrieval-quality → repair-success correlation
   strengthening (Spearman 0.05 → 0.53) that motivates top-k-weighted localization metrics; context
   for why strict@10 (not lenient recall) is this paper's primary metric.

---

*Artifact index for this paper, all paths relative to the repository root:* `bench/locbench/`
(harness, `dataset.lock`, `GATE_DECISION.md`, `compare_runs.py`, `anchorhop_calib.json`,
`full560.json`, `results/r1_anchorhop/`, `results/r1cpp_anchorhop/`), `bench/multiswe/` (harness,
`dataset.lock`, `results/cpp.json`, `results/cpp_scoreboard.md`), `bench/cppbench/` (harness,
`dataset.lock`, `results/sfml.json`, `results/sfml_scoreboard.md`), `bench/headtohead/`
(`REPORT.md`, `README.md`, `headtohead_results.json`, `paired_table.md`, `loss_buckets.json`), and
the register that governs all of them, [`docs/EVALS.md`](../docs/EVALS.md).
